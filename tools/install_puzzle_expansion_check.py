#!/usr/bin/env python3
"""Exercise preservation, conflict handling, and rollback of the data installer."""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from install_puzzle_expansion import install

ROOT = Path(__file__).resolve().parents[1]


class InstallationChecks(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="demiurges-install-check-")
        self.addCleanup(self.folder.cleanup)
        self.target = Path(self.folder.name) / "checkout"
        self.pack = Path(self.folder.name) / "expansion"
        self.pack.mkdir()
        (self.target / "game/src/duel").mkdir(parents=True)
        (self.target / "game/puzzles").mkdir()
        (self.target / "game/project.godot").write_bytes((ROOT / "game/project.godot").read_bytes())
        (self.target / "game/src/duel/puzzles.gd").write_bytes((ROOT / "game/src/duel/puzzles.gd").read_bytes())
        self.before = {}
        self.originals = {}
        self.incoming = {}
        for edition in ("el1", "el2"):
            document = json.loads((ROOT / "game/puzzles" / (edition + ".json")).read_text(encoding="utf-8"))
            document["custom_metadata"] = {"keep": "unknown future fields"}
            # Keep a locally authored puzzle unrelated to this expansion.
            custom = deepcopy(document["puzzles"][0])
            custom["id"] = edition + "_local_custom_puzzle"
            document["puzzles"].append(custom)
            self.originals[edition] = deepcopy(document)
            destination = self.target / "game/puzzles" / (edition + ".json")
            destination.write_text(json.dumps(document), encoding="utf-8")
            self.before[edition] = destination.read_bytes()
            new = deepcopy(custom)
            new["id"] = edition + "_installer_check_new"
            new["expansion"] = "curiosities-v1"
            self.incoming[edition] = {"format": "etherlords-puzzles", "version": 2,
                                      "game": edition, "collection_id": "curiosities-v1", "puzzles": [new]}
            self.write_incoming(edition)

    def write_incoming(self, edition):
        (self.pack / (edition + ".json")).write_text(json.dumps(self.incoming[edition]), encoding="utf-8")

    def catalogs(self):
        return {edition: (self.target / "game/puzzles" / (edition + ".json")).read_bytes()
                for edition in ("el1", "el2")}

    def test_dry_run_never_writes(self):
        report = install(self.target, self.pack, dry_run=True)
        self.assertEqual([item["added"] for item in report["catalogs"]], [1, 1])
        self.assertEqual(self.catalogs(), self.before)
        self.assertFalse((self.target / "build").exists())

    def test_preserves_local_entries_metadata_and_exact_backups(self):
        report = install(self.target, self.pack)
        backup = Path(report["backup"])
        for edition, contents in self.catalogs().items():
            installed = json.loads(contents)
            old = self.originals[edition]
            by_id = {entry["id"]: entry for entry in installed["puzzles"]}
            for original in old["puzzles"]:
                self.assertEqual(by_id[original["id"]], original)
            self.assertEqual(installed["custom_metadata"], old["custom_metadata"])
            self.assertEqual(installed["collection_id"], old["collection_id"])
            self.assertEqual(len(installed["puzzles"]), len(old["puzzles"]) + 1)
            self.assertEqual((backup / (edition + ".json")).read_bytes(), self.before[edition])

    def test_repeat_install_is_a_noop(self):
        install(self.target, self.pack)
        once = self.catalogs()
        report = install(self.target, self.pack)
        self.assertIsNone(report["backup"])
        self.assertEqual([item["added"] for item in report["catalogs"]], [0, 0])
        self.assertEqual(self.catalogs(), once)

    def test_crucible_preserves_all_previous_entries_and_revision(self):
        for edition in ("el1", "el2"):
            self.incoming[edition]["collection_id"] = "crucible-v1"
            self.incoming[edition]["puzzles"][0]["expansion"] = "crucible-v1"
            self.write_incoming(edition)
        report = install(self.target, self.pack)
        self.assertEqual([item["added"] for item in report["catalogs"]], [1, 1])
        for edition, contents in self.catalogs().items():
            installed = json.loads(contents)
            by_id = {entry["id"]: entry for entry in installed["puzzles"]}
            for original in self.originals[edition]["puzzles"]:
                self.assertEqual(by_id[original["id"]], original)
            self.assertIn("crucible-v1", installed["expansions"])
            self.assertGreaterEqual(installed["content_revision"], 12)
        once = self.catalogs()
        repeated = install(self.target, self.pack)
        self.assertEqual([item["added"] for item in repeated["catalogs"]], [0, 0])
        self.assertEqual(self.catalogs(), once)

    def test_successive_cumulative_expansions_preserve_earlier_entries(self):
        install(self.target, self.pack)
        for generation in (2, 3):
            before = self.catalogs()
            expansion = f"curiosities-v{generation}"
            for edition in ("el1", "el2"):
                self.incoming[edition]["collection_id"] = expansion
                newest = deepcopy(self.incoming[edition]["puzzles"][0])
                newest["id"] += f"_expansion_{generation}"
                newest["expansion"] = expansion
                self.incoming[edition]["puzzles"].append(newest)
                self.write_incoming(edition)
            report = install(self.target, self.pack)
            self.assertEqual([item["added"] for item in report["catalogs"]], [1, 1])
            for edition, contents in self.catalogs().items():
                installed = json.loads(contents)
                by_id = {entry["id"]: entry for entry in installed["puzzles"]}
                for original in json.loads(before[edition])["puzzles"]:
                    self.assertEqual(by_id[original["id"]], original)
                for number in range(1, generation + 1):
                    self.assertIn(f"curiosities-v{number}", installed["expansions"])
                self.assertGreaterEqual(installed["content_revision"], 4 + generation)
            after = self.catalogs()
            repeated = install(self.target, self.pack)
            self.assertEqual([item["added"] for item in repeated["catalogs"]], [0, 0])
            self.assertEqual(self.catalogs(), after)

    def test_newest_only_preserves_custom_edits_to_prior_expansions(self):
        install(self.target, self.pack)
        for edition in ("el1", "el2"):
            path = self.target / "game/puzzles" / (edition + ".json")
            document = json.loads(path.read_text())
            original_id = self.incoming[edition]["puzzles"][0]["id"]
            for entry in document["puzzles"]:
                if entry["id"] == original_id:
                    entry["title_ru"] = "Локальная редакция ранней головоломки"
            path.write_text(json.dumps(document), encoding="utf-8")
            newest = deepcopy(self.incoming[edition]["puzzles"][0])
            newest["id"] += "_newest_only"
            newest["expansion"] = "curiosities-v3"
            self.incoming[edition]["collection_id"] = "curiosities-v3"
            self.incoming[edition]["puzzles"] = [newest]
            self.write_incoming(edition)
        edited = self.catalogs()
        report = install(self.target, self.pack)
        self.assertEqual([item["added"] for item in report["catalogs"]], [1, 1])
        for edition, contents in self.catalogs().items():
            by_id = {entry["id"]: entry for entry in json.loads(contents)["puzzles"]}
            for original in json.loads(edited[edition])["puzzles"]:
                self.assertEqual(by_id[original["id"]], original)

    def test_conflict_in_second_edition_leaves_both_unchanged(self):
        incoming = self.incoming["el2"]["puzzles"][0]
        incoming["id"] = self.originals["el2"]["puzzles"][0]["id"]
        incoming["title"] = "Conflicting local definition"
        self.write_incoming("el2")
        with self.assertRaisesRegex(ValueError, "Conflicting existing puzzle"):
            install(self.target, self.pack)
        self.assertEqual(self.catalogs(), self.before)
        self.assertFalse((self.target / "build").exists())

    def test_second_replace_failure_rolls_back_first_edition(self):
        import os
        original_replace = os.replace
        calls = 0

        def fail_second(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("Simulated disk failure")
            return original_replace(source, destination)

        with patch("install_puzzle_expansion.os.replace", side_effect=fail_second):
            with self.assertRaisesRegex(OSError, "Simulated disk failure"):
                install(self.target, self.pack)
        self.assertEqual(self.catalogs(), self.before)
        self.assertEqual(list((self.target / "game/puzzles").glob("*.tmp")), [])

    def test_refuses_non_checkout_target(self):
        (self.target / "game/project.godot").unlink()
        with self.assertRaisesRegex(ValueError, "source repository"):
            install(self.target, self.pack)
        self.assertEqual(self.catalogs(), self.before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
