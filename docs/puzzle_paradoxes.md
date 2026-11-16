# Curiosities: Paradoxes

> Archived guide for Paradoxes v2: 14 additions and 93 puzzles at that release. The current collection has 105 puzzles. Use [the Crossroads guide](puzzle_crossroads.md) for current installation and rebuild instructions.

**14 more authored puzzles: 7 for Etherlords I and 7 for Etherlords II.** This second release includes the previous 22 Curiosities puzzles, giving you 36 additions and 93 puzzles overall. All 79 previously delivered puzzle entries retain their exact definitions, IDs, hints, and presentation.

## Find the newest puzzles

Open **Puzzles** and search **Paradoxes** (English) or **Парадоксы** (Russian). Search **Curiosities** / **Курьёзы** to see both expansions. Difficulty, objective, and progress filters work as before. Every new puzzle has an English and Russian briefing, three staged hints, and an explanation. Any legal line that meets its objective is accepted.

## Design and variety

The new collection explores unusual uses of existing rules: beneficial enemy actions, effects that change readiness and resource timing, awkward sacrifices, and plans that must survive the opponent's response. The catalog identifies each puzzle's tactical theme without giving its solution steps.

- Goals: 4 clear, 1 control, 3 survive, 6 win.
- Intended difficulty: 0 Easy, 9 Medium, 4 Hard, 1 Expert.
- 5 defensive starts; 11 with a 1-turn budget, 1 with a 2-turn budget, 2 with a 3-turn budget.
- 2 explicitly documented additional winning routes, each replayed independently.
- Card draws and natural channel growth are disabled. Existing channels still refill; explicit channel changes, direct card returns, and copies work normally.

Difficulty labels are design estimates, not measurements from human playtesting. A longer command sequence is not automatically a harder puzzle.

## New catalog

### Etherlords I

| Puzzle | Difficulty | Goal | Own turns | Tactical theme |
| --- | --- | --- | --- | --- |
| Borrowed Scissors | Medium | survive | 1 | Borrow the enemy’s disenchanting strike |
| Keep the Change | Medium | win | 1 | Close every route for spending the burn away |
| No Free Funerals | Medium | clear | 1 | Count actual deaths and reserve regeneration |
| Riot on Repeat | Medium | clear | 1 | One returning curse, two ways to finish |
| A Fatal Upgrade | Medium | clear | 3 | An enemy bonus starts a lethal decay clock |
| Night Shift | Hard | win | 3 | Three turns of borrowed vigilance through Smoke |
| The Living Budget | Hard | control | 1 | A sacrifice changes both income and upkeep |

### Etherlords II

| Puzzle | Difficulty | Goal | Own turns | Tactical theme |
| --- | --- | --- | --- | --- |
| After the Storm | Medium | win | 1 | A sacrifice that arrives after the sweep |
| The Last Spell Is No Spell | Medium | clear | 1 | Escape a final spell backlash |
| Empty the Other Room | Medium | win | 1 | Count aspects and races separately |
| A Helpful Thief | Medium | win | 1 | Let a stolen card remove the counterspells |
| Family at a Distance | Hard | survive | 1 | Change a shared kinship bonus during defence |
| Thank You for the Fog | Hard | win | 2 | Make the enemy's defence fund your own |
| Pay at Every Door | Expert | survive | 1 | Two defences with different protection plans |



The first collection is documented in [puzzle_curiosities.md](puzzle_curiosities.md). Its original release notes describe the earlier 79-puzzle total.

## What was verified

All **93 reference solutions** were rebuilt and replayed through the actual GDScript battle implementation in Godot 4.7.2, using the checked-in card tables and narrow asset-free fixture services. All 79 earlier entries compare exactly with the previous release. The new positions begin unsolved, and all 112 commands in their reference lines are covered by the lab's move enumeration.

For the 14 new positions, bounded adversarial search found winning strategies and refuted all 20 authored wrong-plan prefixes. Runtime evidence contains 15 complete legal losing replays and 5 still-live prefixes whose continuations were refuted by bounded search. The no-action and attack-everyone policies failed all 28 new attempts against the objective-aware game AI. Additional winning lines, where supplied, were independently replayed.

The previous 22 puzzles' search reports are included unchanged. Their inputs and the hashes of all rule sources used for those reports were checked against this release. Earlier objective and hero-effect regression results (198 assertions plus two card-enumeration checks) are retained as prior evidence; the rule implementation did not change in this update. Seven installer tests cover preservation, cumulative upgrades, no-op reinstall, conflicts, dry runs, invalid targets, and rollback. Both real installation routes (original 57 or previous 79) and both source patches were applied in temporary checkouts and compared with the shipped files.

A replay establishes its exact legal outcome. A losing example alone does not prove every possible continuation loses. The bounded search uses reference-assisted move ordering and the lab's generated moves; it is not a blind native-solver result or an unrestricted completeness or uniqueness certificate. This content has not been manually played with an installed copy of the original game's assets.

## Rebuild and verify

Use Python 3.10+ and Godot 4.7.2 from the repository root. The packaged baseline reports were generated on Linux with a C compiler available as `cc`, enabling the lab's optional bridge to the repository's native AI:

```sh
python tools/build_tactical_puzzles.py --godot /path/to/godot
python tools/build_tactical_puzzles.py --collection paradoxes --prove --reference-policy --depth 36 --budget 90000 --report-dir build/paradoxes-bounded-search --godot /path/to/godot
python tools/curiosities_check.py --collection paradoxes --runtime --baselines --base-dir /path/to/unzipped/reference/previous_curiosities --proof-dir build/paradoxes-bounded-search --godot /path/to/godot
python tools/install_puzzle_expansion_check.py
```

`--collection curiosities` builds both expansions, `--collection paradoxes` builds only this update, and `--collection curiosities-v1` builds only the first collection. Subsets go into `build/puzzle-collections/<collection>` and cannot replace the full installed catalogs. The default builder produces all 93 puzzles.

Exact bilingual solutions and optional alternate routes are in [puzzle_paradoxes_solutions.md](puzzle_paradoxes_solutions.md).
