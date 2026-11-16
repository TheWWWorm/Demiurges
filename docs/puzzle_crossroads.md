# Curiosities: Crossroads

**12 more authored puzzles: 6 for Etherlords I and 6 for Etherlords II.** This third release includes the previous 22 Curiosities and 14 Paradoxes puzzles, giving you 48 additions and 105 puzzles overall. All 93 previously delivered puzzle entries retain their exact definitions, IDs, hints, and presentation.

## Find the newest puzzles

Open **Puzzles** and search **Crossroads** (English) or **Развилки** (Russian). Search **Curiosities** / **Курьёзы** to see all three expansions. Difficulty, objective, and progress filters work as before. Every new puzzle has an English and Russian briefing, three staged hints, and an explanation. Any legal line that meets its objective is accepted.

## Design and variety

The new collection explores underused creature abilities, resource timing, hero skills, and plans that must adapt to the opponent's response. The catalog identifies each puzzle's tactical theme without giving its solution steps.

- Goals: 4 clear, 8 win.
- Intended difficulty: 0 Easy, 6 Medium, 6 Hard, 0 Expert.
- 4 defensive starts; 6 with a 1-turn budget, 3 with a 2-turn budget, 3 with a 3-turn budget.
- 2 explicitly documented additional winning lines, each replayed independently.
- Card draws and natural channel growth are disabled. Existing channels still refill; explicit channel changes, direct card returns, and copies work normally.

Difficulty labels are design estimates, not measurements from human playtesting. A longer command sequence is not automatically a harder puzzle.

## New catalog

### Etherlords I

| Puzzle | Difficulty | Goal | Own turns | Tactical theme |
| --- | --- | --- | --- | --- |
| The Last Receipt | Medium | win | 1 | Two ways to supply the last point before disturbance |
| First Free the Midwife | Medium | win | 2 | Two broods and two sacrifices |
| The Quiet Cleric | Medium | clear | 1 | A reborn ally helps before it can act |
| Life in Installments | Hard | win | 3 | One channel across three attacks |
| Above the Flood | Hard | win | 2 | Recovery on the ground and in the air |
| The Anchor You Own | Hard | win | 3 | Shared bonds and a hostile sacrifice |

### Etherlords II

| Puzzle | Difficulty | Goal | Own turns | Tactical theme |
| --- | --- | --- | --- | --- |
| Evict the Parasite | Medium | win | 1 | Dispose of a dangerous ally through an ordered block |
| A Small Appetite | Medium | clear | 1 | Balance a shared hunger sweep |
| Empty Pockets, Fast Feet | Medium | win | 1 | Spend your hand in the right order |
| Step Back, Spring Forward | Hard | clear | 2 | A conditional investment and its refill |
| Let It Grow Teeth | Hard | win | 3 | Permanent growth unlocks a dangerous final boost |
| One Last Reprieve | Hard | clear | 1 | Keep a regenerating attacker in combat |



The earlier collections are documented in [puzzle_curiosities.md](puzzle_curiosities.md) and [puzzle_paradoxes.md](puzzle_paradoxes.md). Those historical release notes describe the earlier totals of 79 and 93 puzzles.

## What was verified

All **105 reference solutions** were rebuilt and replayed through the actual GDScript battle implementation in Godot 4.7.2, using the checked-in card tables and narrow asset-free fixture services. All 93 earlier entries compare exactly with the previous release. The new positions begin unsolved, and all 116 commands in their reference lines are covered by the lab's move enumeration.

For the 12 new positions, bounded adversarial search found winning strategies and refuted all 19 authored wrong-plan prefixes. Runtime evidence contains 12 complete legal losing replays and 7 still-live prefixes whose continuations were refuted by bounded search. The no-action and attack-everyone policies failed all 24 new attempts against the objective-aware game AI. Additional winning lines, where supplied, were independently replayed.

The previous 36 additions' search reports are included unchanged. Their inputs and the hashes of all rule sources used for those reports were checked against this release. Earlier objective and hero-effect regression results (198 assertions plus two card-enumeration checks) are retained as prior evidence; the rule implementation did not change in this update. Eight installer tests cover preservation, successive cumulative upgrades, newest-only installation with earlier local edits, no-op reinstall, conflicts, dry runs, invalid targets, and rollback. All three installation routes (original 57, Curiosities 79, or Paradoxes 93) and all three source patches were applied in temporary checkouts and compared with the shipped files.

A replay establishes its exact legal outcome. A losing example alone does not prove every possible continuation loses. The bounded search uses reference-assisted move ordering and the lab's generated moves; it is not a blind native-solver result or an unrestricted completeness or uniqueness certificate. This content has not been manually played with an installed copy of the original game's assets.

## Rebuild and verify

Use Python 3.10+ and Godot 4.7.2 from the repository root. The packaged baseline reports were generated on Linux with a C compiler available as `cc`, enabling the lab's optional bridge to the repository's native AI:

```sh
python tools/build_tactical_puzzles.py --godot /path/to/godot
python tools/build_tactical_puzzles.py --collection crossroads --prove --reference-policy --depth 40 --budget 90000 --report-dir build/crossroads-bounded-search --godot /path/to/godot
python tools/curiosities_check.py --collection crossroads --runtime --baselines --base-dir /path/to/unzipped/reference/previous_paradoxes --proof-dir build/crossroads-bounded-search --godot /path/to/godot
python tools/install_puzzle_expansion_check.py
```

`--collection curiosities` builds all three expansions, `--collection crossroads` builds only this update, `--collection paradoxes` builds only the second expansion, and `--collection curiosities-v1` builds only the first collection. Subsets go into `build/puzzle-collections/<collection>` and cannot replace the full installed catalogs. The default builder produces all 105 puzzles.

Exact bilingual solutions and optional alternate lines are in [puzzle_crossroads_solutions.md](puzzle_crossroads_solutions.md).
