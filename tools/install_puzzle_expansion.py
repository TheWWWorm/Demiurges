#!/usr/bin/env python3
"""Merge a puzzle expansion into a Demiurges source checkout, preserving entries.

This installs puzzle data only. Apply the accompanying source patch as well if
you want tools/build_tactical_puzzles.py to regenerate the expansion later.
No game saves or files from an original Etherlords installation are touched.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile

EXPANSIONS = {"curiosities-v1": 5, "curiosities-v2": 6, "curiosities-v3": 7, "crucible-v1": 12}


def read_pack(path: Path, edition: str) -> tuple[bytes, dict]:
    raw = path.read_bytes()
    document = json.loads(raw)
    if (not isinstance(document, dict)
            or document.get("format") != "etherlords-puzzles"
            or document.get("game") != edition
            or not isinstance(document.get("puzzles"), list)):
        raise ValueError(f"Not a valid {edition} puzzle catalog: {path}")
    seen = set()
    for entry in document["puzzles"]:
        if (not isinstance(entry, dict) or not isinstance(entry.get("id"), str)
                or not entry["id"] or entry["id"] in seen):
            raise ValueError(f"Missing or duplicate puzzle ID in {path}")
        seen.add(entry["id"])
    return raw, document


def stage(path: Path, data: bytes) -> Path:
    descriptor, name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        return temporary
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def install(target: Path, pack: Path, dry_run: bool = False) -> dict:
    target, pack = target.resolve(), pack.resolve()
    project = target / "game/project.godot"
    runtime = target / "game/src/duel/puzzles.gd"
    if not project.is_file() or not runtime.is_file():
        raise ValueError("Target must be the Demiurges source repository (the folder containing game/project.godot), not an installed Etherlords folder or a release executable.")
    source = runtime.read_text(encoding="utf-8")
    if any(marker not in source for marker in ("finish_health", "finish_mana", "min_allies", '"control"', "failed_target")):
        raise ValueError("This checkout lacks the objective-aware puzzle runtime. Update Demiurges before installing this expansion.")

    planned = []
    stats = []
    # Resolve and validate BOTH editions and every conflict before any writes.
    for edition in ("el1", "el2"):
        _, incoming = read_pack(pack / (edition + ".json"), edition)
        if incoming.get("collection_id") not in EXPANSIONS or not incoming["puzzles"]:
            raise ValueError(f"Expected a nonempty supported puzzle expansion in {pack / (edition + '.json')}")
        for entry in incoming["puzzles"]:
            if entry.get("expansion") not in EXPANSIONS or entry.get("state", {}).get("profile") != edition:
                raise ValueError(f"Unexpected expansion entry: {entry['id']}")
        destination = target / "game/puzzles" / (edition + ".json")
        before, existing = read_pack(destination, edition)
        by_id = {entry["id"]: entry for entry in existing["puzzles"]}
        additions = []
        for entry in incoming["puzzles"]:
            previous = by_id.get(entry["id"])
            if previous is not None:
                if previous != entry:
                    raise ValueError(f"Conflicting existing puzzle {entry['id']}; no files were changed. Review that local entry before merging.")
            else:
                additions.append(entry)
        stats.append({"edition": edition, "preserved": len(existing["puzzles"]), "added": len(additions), "total": len(existing["puzzles"]) + len(additions)})
        if not additions:
            continue
        existing["puzzles"].extend(additions)
        existing["puzzles"].sort(key=lambda entry: entry.get("level", 1))
        # Keep the original collection identity and any unknown metadata.
        expansions = existing.setdefault("expansions", [])
        if not isinstance(expansions, list):
            raise ValueError(f"Invalid expansions metadata in {destination}")
        for expansion in sorted({entry["expansion"] for entry in incoming["puzzles"]}):
            if expansion not in expansions:
                expansions.append(expansion)
        existing["content_revision"] = max(int(existing.get("content_revision", 0)),
                                            max(EXPANSIONS[entry["expansion"]] for entry in incoming["puzzles"]))
        after = (json.dumps(existing, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        planned.append((destination, before, after))

    result = {"dry_run": dry_run, "catalogs": stats, "backup": None}
    if dry_run or not planned:
        return result

    backups = target / "build/puzzle-backups"
    backups.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("puzzles-%Y%m%dT%H%M%SZ-")
    backup = Path(tempfile.mkdtemp(prefix=stamp, dir=backups))
    staged = []
    replaced = []
    try:
        for destination, before, after in planned:
            (backup / destination.name).write_bytes(before)
            staged.append((destination, before, stage(destination, after)))
        for destination, before, _ in staged:
            if destination.read_bytes() != before:
                raise ValueError(f"Catalog changed while preparing the merge: {destination}. Nothing was installed.")
        for destination, before, temporary in staged:
            os.replace(temporary, destination)
            replaced.append((destination, before))
    except BaseException:
        for destination, before in reversed(replaced):
            os.replace(stage(destination, before), destination)
        raise
    finally:
        for _, _, temporary in staged:
            temporary.unlink(missing_ok=True)
    result["backup"] = str(backup)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path, help="Demiurges source repository root")
    parser.add_argument("--pack", type=Path, default=Path(__file__).resolve().parent / "new_puzzles",
                        help="Folder containing the two expansion-only catalogs (default: new_puzzles next to this script)")
    parser.add_argument("--dry-run", action="store_true", help="Check compatibility and conflicts without changing files")
    args = parser.parse_args()
    try:
        result = install(args.target, args.pack, args.dry_run)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"Cannot install puzzles: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
