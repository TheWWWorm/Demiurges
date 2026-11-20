#!/usr/bin/env python3
"""Prepare provenance-labelled data for offline Expedition combat experiments.

Printed spell/creature data comes from the current checked-in wiki. Decks are
recovered from checked-in EL2 duel snapshots, never invented as original
campaign decks. The original mana-income table, Expedition preset metadata,
campaign enemy spellbooks, and boss scripts are not available in these files.
The combat tool therefore explicitly labels its derived income curves and
authored encounter books as proxies. Use --el2 with the combat tool to replace
the printed/hero/income tables with an installed game's data.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

import arena_lab

ROOT = Path(__file__).resolve().parents[1]
# Exclude observations from matches containing cards/creatures capable of
# changing either side's channel count or preventing normal growth. This is
# conservative; retained rows are still observations, not the registry table.
CHANNEL_EFFECTS = set("GEYS VOLC SNRG SNCR SNHG MNBR MNST BLNC JUST INCR LQRL FRST "
                      "SNOV FTCH SPLK ORSH ORGD OUS1 OUD1 OUD2 OUD3 STSI RLWP".split())


def prepare(destination: Path) -> Path:
    path = arena_lab.prepare(destination)
    data = json.loads(path.read_text(encoding="utf-8"))
    observed_books = defaultdict(Counter)
    book_sources = defaultdict(lambda: defaultdict(list))
    income = defaultdict(lambda: defaultdict(Counter))
    income_sources = defaultdict(lambda: defaultdict(list))
    for folder in ("duel_ai_positions", "duel_ai_puzzles"):
        for source in sorted((ROOT / "tools" / folder).glob("*.json")):
            raw = json.loads(source.read_text(encoding="utf-8"))
            state = raw.get("state", {})
            if state.get("profile") != "el2":
                continue
            heroes = state.get("heroes", [])
            players = state.get("setup", {}).get("players", [])
            if len(heroes) != 2 or len(players) != 2:
                continue
            relative = source.relative_to(ROOT).as_posix()
            for hero, player in zip(heroes, players):
                name = player.get("deck", "")
                cards = tuple(hero.get("deck", []))
                if name and len(cards) == 16:
                    observed_books[name][cards] += 1
                    book_sources[name][cards].append(relative)
            if any(not player.get("deck") for player in players):
                continue
            if set(state.get("setup", {})) - {"players", "first_side", "arena"}:
                continue
            if any(hero.get("spec") not in (None, "NONE") or hero.get("artifacts") for hero in heroes):
                continue
            if any(code in CHANNEL_EFFECTS for hero in heroes for code in hero.get("deck", [])):
                continue
            for hero in heroes:
                level, turn, channels = hero.get("level"), hero.get("turns"), hero.get("channels")
                if all(isinstance(v, int) for v in (level, turn, channels)) and turn > 0:
                    income[level][turn][channels] += 1
                    income_sources[level][turn].append(relative)
    books = {}
    for name, counts in observed_books.items():
        cards, support = counts.most_common(1)[0]
        books[name] = {"cards": list(cards), "records": support, "distinct_variants": len(counts),
                       "sources": sorted(set(book_sources[name][cards]))}
    for name in ("STR1", "STG1", "STU1", "STB1"):
        if name not in books or books[name]["distinct_variants"] != 1:
            raise ValueError(f"A single corroborated starter book could not be recovered: {name}")
    observations = {}
    for level, turns in sorted(income.items()):
        observations[str(level)] = {}
        for turn, counts in sorted(turns.items()):
            observations[str(level)][str(turn)] = {
                "counts": dict(sorted(counts.items())),
                "sources": sorted(set(income_sources[level][turn])),
            }
    data["expedition_balance"] = {
        "format": "expedition-offline-balance-fixture", "version": 1,
        "printed_data": "wiki/catalog/en.json via arena_lab/puzzle_lab",
        "books": books, "observed_channels": observations,
        "limitations": [
            "Recorded starter books are not a reconstruction of full Expedition DuelPresets metadata.",
            "Income observations are sparse cumulative totals; interpolation is a proxy, not the original table.",
            "Authored benchmark opponents are not original campaign encounter decks.",
            "Boss scripts, original arenas, art, and encounter placement are not exercised offline.",
        ],
    }
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    path = prepare(args.workspace.resolve())
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
