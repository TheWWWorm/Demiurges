#!/usr/bin/env python3
"""Build and validate the authored puzzle packs; run from any directory."""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile

from puzzle_authoring import ROOT
from puzzle_designs_el1 import puzzles as first_puzzles
from puzzle_designs_el1_advanced import puzzles as first_advanced
from puzzle_designs_el1_master import puzzles as first_master
from puzzle_designs_el1_legends import puzzles as first_legends
from puzzle_designs_el1_legends_extra import puzzles as first_legends_extra
from puzzle_designs_el1_legends_crowd import puzzles as first_legends_crowd
from puzzle_designs_el1_curiosities import puzzles as first_curiosities
from puzzle_designs_el1_paradoxes import puzzles as first_paradoxes
from puzzle_designs_el1_crossroads import puzzles as first_crossroads
from puzzle_designs_el1_crucible import puzzles as first_crucible
from puzzle_designs_el2 import puzzles as second_puzzles
from puzzle_designs_el2_advanced import puzzles as second_advanced
from puzzle_designs_el2_master import puzzles as second_master
from puzzle_designs_el2_legends import puzzles as second_legends
from puzzle_designs_el2_curiosities import puzzles as second_curiosities
from puzzle_designs_el2_paradoxes import puzzles as second_paradoxes
from puzzle_designs_el2_crossroads import puzzles as second_crossroads
from puzzle_designs_el2_crucible import puzzles as second_crucible
from puzzle_designs_pale import puzzles as pale_puzzles

# These are role labels for the existing studies, not invented campaign names.
# New authored matchups supply their own bilingual presentation names.
HERO_LABELS = {
    "GreenMale1": ("Vital warrior", "Воин виталов"),
    "RedMaleWarrior2": ("Chaot warrior", "Воин хаотов"),
    "RedMale4": ("Chaot warrior", "Воин хаотов"),
    "BlueWingedMale1": ("Kinet adept", "Адепт кинетов"),
    "BlackMale1": ("Synthet adept", "Адепт синтетов"),
    "White Lord I": ("White Lord", "Белый Лорд"),
}

ARCHIVE_EXPANSIONS = {"unwritten-rules-v1", "battlecraft-v2", "battlecraft-v3", "battlecraft-v4"}


def retain_archive_puzzles(edition, document):
    # The shipped snapshots are the authoring source for these imports.
    shipped = json.loads((ROOT / "game/puzzles" / (edition + ".json")).read_text(encoding="utf-8"))
    archive_entries = [entry for entry in shipped["puzzles"] if entry.get("expansion") in ARCHIVE_EXPANSIONS]
    generated_ids = {entry["id"] for entry in document["puzzles"]}
    for entry in archive_entries:
        if entry["id"] in generated_ids:
            raise ValueError("Repeated puzzle ID: " + entry["id"])
        generated_ids.add(entry["id"])
    document["puzzles"].extend(archive_entries)
    # Keep installed studies in their existing order within each tier. New
    # studies follow them, just as in the additive installer; a rebuild must
    # not move the newly authored tier ahead of earlier imported studies.
    installed_order = {entry["id"]: index for index, entry in enumerate(shipped["puzzles"])}
    document["puzzles"].sort(key=lambda entry: (entry["level"], installed_order.get(entry["id"], len(installed_order))))
    document["expansions"] = sorted({entry["expansion"] for entry in document["puzzles"] if entry.get("expansion")})
    document["content_revision"] = max(document["content_revision"], shipped["content_revision"])


def entries(edition, collection="all"):
    result = (first_puzzles() + first_advanced() + first_master() + first_legends() + first_legends_extra() + first_legends_crowd()) if edition == "el1" else (second_puzzles() + pale_puzzles() + second_advanced() + second_master() + second_legends())
    additions = first_curiosities() if edition == "el1" else second_curiosities()
    paradoxes = first_paradoxes() if edition == "el1" else second_paradoxes()
    crossroads = first_crossroads() if edition == "el1" else second_crossroads()
    crucible = first_crucible() if edition == "el1" else second_crucible()
    for entry in additions:
        entry["expansion"] = "curiosities-v1"
        # The existing selector searches categories in both languages. A
        # visible label makes this expansion discoverable without a UI fork.
        if not entry["category"].startswith("Curiosities · "):
            entry["category"] = "Curiosities · " + entry["category"]
        if not entry["category_ru"].startswith("Курьёзы · "):
            entry["category_ru"] = "Курьёзы · " + entry["category_ru"]
    for entry in paradoxes:
        entry["expansion"] = "curiosities-v2"
        if not entry["category"].startswith("Curiosities · Paradoxes · "):
            entry["category"] = "Curiosities · Paradoxes · " + entry["category"]
        if not entry["category_ru"].startswith("Курьёзы · Парадоксы · "):
            entry["category_ru"] = "Курьёзы · Парадоксы · " + entry["category_ru"]
    for entry in crossroads:
        entry["expansion"] = "curiosities-v3"
        if not entry["category"].startswith("Curiosities · Crossroads · "):
            entry["category"] = "Curiosities · Crossroads · " + entry["category"]
        if not entry["category_ru"].startswith("Курьёзы · Развилки · "):
            entry["category_ru"] = "Курьёзы · Развилки · " + entry["category_ru"]
    for entry in crucible:
        entry["expansion"] = "crucible-v1"
        if not entry["category"].startswith("Crucible · "):
            entry["category"] = "Crucible · " + entry["category"]
        if not entry["category_ru"].startswith("Горнило · "):
            entry["category_ru"] = "Горнило · " + entry["category_ru"]
    if collection == "curiosities":
        result = additions + paradoxes + crossroads
    elif collection == "crossroads":
        result = crossroads
    elif collection == "paradoxes":
        result = paradoxes
    elif collection == "curiosities-v1":
        result = additions
    elif collection == "crucible":
        result = crucible
    elif collection == "all":
        result += additions + paradoxes + crossroads + crucible
    elif collection != "original":
        raise ValueError("Unknown puzzle collection: " + collection)
    module = __import__("puzzle_translations_" + edition)
    translations = module.TRANSLATIONS
    for entry in result:
        # Translation modules may use either localized keys or bare field
        # names. Always preserve the English authoring text when merging.
        for key, value in translations.get(entry["id"], {}).items():
            entry[key if key.endswith("_ru") else key + "_ru"] = value
        for language, suffix in enumerate(("", "_ru")):
            entry.setdefault("hero_names" + suffix, [HERO_LABELS.get(h["template"], (h["template"], h["template"]))[language] for h in entry["state"]["heroes"]])
    # Stable authored ordering within each difficulty. Do not infer human
    # difficulty from the number of winning opening commands.
    result.sort(key=lambda p: p["level"])
    ids = set()
    for entry in result:
        if entry["id"] in ids:
            raise ValueError("Repeated puzzle ID: " + entry["id"])
        ids.add(entry["id"])
        for key in ("title", "category", "briefing", "explanation", "title_ru", "category_ru", "briefing_ru", "explanation_ru"):
            if not isinstance(entry.get(key), str) or not entry[key].strip():
                raise ValueError(f"{entry['id']}: missing {key}")
        if len(entry.get("hints", [])) != 3 or len(entry.get("hints_ru", [])) != 3:
            raise ValueError(entry["id"] + ": exactly three hints per language are required")
        if not entry.get("solution") or not entry.get("refutations"):
            raise ValueError(entry["id"] + ": reference solution and a tested tempting alternative are required")
        for key in ("hero_names", "hero_names_ru"):
            names = entry.get(key)
            if not isinstance(names, list) or len(names) != 2 or any(not isinstance(name, str) or not name.strip() for name in names):
                raise ValueError(entry["id"] + ": two nonempty combatant names per language are required")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edition", choices=("el1", "el2", "both"), default="both")
    parser.add_argument("--collection", choices=("all", "crucible", "curiosities", "crossroads", "paradoxes", "curiosities-v1", "original"), default="all",
                        help="Build all studies, Crucible, all Curiosities expansions, one named expansion, or the original studies")
    parser.add_argument("--godot", default=shutil.which("godot") or shutil.which("godot4") or shutil.which("godot-4") or "godot")
    parser.add_argument("--report-dir", type=Path, default=ROOT / "build/puzzle-validation")
    parser.add_argument("--output-dir", type=Path,
                        help="Destination; subsets default to build/puzzle-collections/<collection> so they cannot replace the installed catalog")
    parser.add_argument("--prove", action="store_true", help="Also run the bounded adversarial search")
    parser.add_argument("--reference-order", action="store_true", help="Try reference moves first at exact matching search states")
    parser.add_argument("--reference-policy", action="store_true", help="Also try reference moves at matching own-resource/army contexts; legal moves and full-state search are unchanged")
    parser.add_argument("--depth", type=int, default=32)
    parser.add_argument("--budget", type=int, default=80000)
    args = parser.parse_args()
    if args.output_dir is None:
        args.output_dir = ROOT / ("game/puzzles" if args.collection == "all" else "build/puzzle-collections/" + args.collection)
    if args.collection != "all" and args.output_dir.resolve() == (ROOT / "game/puzzles").resolve():
        parser.error("A subset cannot replace game/puzzles; choose a separate --output-dir")
    editions = ("el1", "el2") if args.edition == "both" else (args.edition,)
    args.report_dir.mkdir(parents=True, exist_ok=True)
    validated = {}
    with tempfile.TemporaryDirectory(prefix="demiurges-puzzles-") as folder:
        temp = Path(folder)
        for edition in editions:
            collection_name = {"crucible": "Crucible", "curiosities": "Curiosities", "curiosities-v1": "Curiosities", "paradoxes": "Curiosities: Paradoxes", "crossroads": "Curiosities: Crossroads"}.get(args.collection, "Tactical Studies")
            collection_id = {"crucible": "crucible-v1", "curiosities": "curiosities-v3", "curiosities-v1": "curiosities-v1", "paradoxes": "curiosities-v2", "crossroads": "curiosities-v3"}.get(args.collection, "tactical-studies-v2")
            pack = {"format": "etherlords-puzzles", "version": 2, "game": edition,
                    "collection": collection_name, "collection_id": collection_id,
                    "content_revision": {"original": 4, "curiosities-v1": 5, "paradoxes": 6, "crucible": 12, "all": 12}.get(args.collection, 7),
                    "puzzles": entries(edition, args.collection)}
            path = temp / (edition + ".json")
            path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            command = [sys.executable, str(ROOT / "tools/puzzle_lab.py"), "--godot", args.godot,
                       "--workspace", str(temp / (edition + "-lab")), "--file=" + str(path),
                       "--normalize", "--report=" + str(args.report_dir.resolve() / (edition + ".json"))]
            if args.prove:
                command += ["--search", "--depth=" + str(args.depth), "--budget=" + str(args.budget)]
                if args.reference_policy:
                    command.append("--reference-policy")
                elif args.reference_order:
                    command.append("--reference-order")
            subprocess.run(command, check=True)
            if args.prove:
                report = json.loads((args.report_dir.resolve() / (edition + ".json")).read_text(encoding="utf-8"))
                incomplete = [item["id"] for item in report["results"]
                              if item.get("proof", {}).get("result") != "forced"
                              or any(branch.get("proof", {}).get("result") != "refuted"
                                     for branch in item.get("refutations", []))]
                if incomplete:
                    raise RuntimeError("Incomplete adversarial validation; packs were not replaced: " + ", ".join(incomplete))
            document = json.loads(path.read_text(encoding="utf-8"))
            if args.collection == "all":
                retain_archive_puzzles(edition, document)
            validated[edition] = document
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for edition, document in validated.items():
            destination = args.output_dir / (edition + ".json")
            destination.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            counts = Counter(p["level"] for p in document["puzzles"])
            print(f"Wrote {destination}: {len(document['puzzles'])} studies; Easy {counts[1]}, Medium {counts[2]}, Hard {counts[3]}, Expert {counts[4]}")


if __name__ == "__main__":
    main()
