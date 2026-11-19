#!/usr/bin/env python3
"""Generate a catalog-derived fixture for the Arena checks in the game project.

Use --fixture=<workspace>/fixture.json with the draft, run, screen, or
combat check. The game project can run these checks without an original
installation. The fixture supplies catalog data and synthetic hero/income
rows. Use --el2=<installation> to exercise installed tables and art.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import puzzle_lab

ROOT = Path(__file__).resolve().parents[1]


def prepare(destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((ROOT / "wiki/catalog/en.json").read_text(encoding="utf-8"))
    fixture = puzzle_lab.card_tables()
    for page in catalog["pages"]:
        code = page.get("card")
        if not code:
            continue
        description = puzzle_lab.plain(page["html"].split("<table", 1)[0])
        for edition in page.get("games", []):
            if edition in fixture:
                fixture[edition]["texts"][code + "Info"] = description
        # The generic puzzle fixture intentionally omits shop availability.
        # Arena must not mistake an artifact-granted 0-ether spell for an
        # ordinary draft card. Read the explicit wiki row per edition.
        table = re.search(r"<table[^>]*>(.*?)</table>", page["html"], re.S)
        if table:
            rows = re.findall(r"<tr>(.*?)</tr>", table.group(1), re.S)
            headers = [puzzle_lab.plain(v) for v in re.findall(r"<th[^>]*>(.*?)</th>", rows[0])]
            columns = [(i, "el2" if name == "Etherlords II" else "el1")
                       for i, name in enumerate(headers) if name in ("Etherlords", "Etherlords II")]
            if not columns and len(page.get("games", [])) == 1:
                columns = [(1, page["games"][0])]
            for row in rows:
                cells = [puzzle_lab.plain(v) for v in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
                if not cells or cells[0] != "Artifact":
                    continue
                for col, edition in columns:
                    if len(cells) > col and cells[col].lower() == "yes":
                        spell = fixture[edition]["CombatSpells"].get(code)
                        if spell is not None:
                            spell["IsArtifact"] = "True"
    (destination / "fixture.json").write_text(
        json.dumps(fixture, ensure_ascii=False), encoding="utf-8")
    return destination / "fixture.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.workspace.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
