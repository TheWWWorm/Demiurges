# Curiosities: a new puzzle expansion

> Archived guide for Curiosities v1: 22 additions and 79 puzzles at that release. The current collection has 105 puzzles. Use [the Crossroads guide](puzzle_crossroads.md) for current installation and rebuild instructions.

**22 new authored puzzles: 10 for Etherlords I and 12 for Etherlords II.** The installed collection now contains 79 puzzles; the earlier 57 entries retain their exact definitions, IDs, and presentation. Based on Demiurges 0.16.0, commit `1933bc4a303c3369657accb5c29475810089653a`.

## Find the new puzzles

Open **Puzzles** in the game and search for **Curiosities** (English) or **Курьёзы** (Russian). The existing difficulty, objective and progress filters still work. Every addition has a bilingual briefing, three progressively more explicit hints, an explanation, and an exact reference line. Any legal solution that meets the objective is accepted.

## What varies

- Goals: 9 clear, 3 control, 2 survive, 8 win.
- Intended difficulty: 1 Easy, 13 Medium, 5 Hard, 3 Expert.
- 4 defensive starts; own-turn budgets: 16 with a 1-turn budget, 6 with a 2-turn budget.
- Actual hero levels used: 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20.
- Fixed hands and fixed natural channel growth make each starting position reproducible. Existing channels still refill normally.

The goal is to vary the decisions: target attributes, copied printed bodies, shared effects, damage prevention, resource conversion, conditional abilities, protection and delayed completion. Hero level and puzzle difficulty remain separate. Difficulty labels are design estimates; they have not been calibrated with human solve times.

## Catalog (no solution steps)

### Etherlords I

| Puzzle | Difficulty | Goal | Turns | Hero levels | Tactical theme |
| --- | --- | --- | --- | --- | --- |
| The Last Coin | Easy | win | 1 | 3 vs 12 | Taking less ether leaves a stronger finishing spell |
| Inferno Geometry | Medium | win | 1 | 11 vs 9 | A defensive statistic becomes ammunition |
| A Clean Copy | Medium | win | 1 | 5 vs 14 | Printed bodies, enchantments and haste |
| A Universal Wake-Up Call | Medium | win | 1 | 7 vs 10 | A global readying ability and enemy regeneration |
| The Pteros' Bargain | Medium | clear | 1 | 9 vs 14 | Dispel cost is not the size of the enchantment |
| Poison Division | Hard | clear | 1 | 10 vs 18 | Poison immunity and ordered blockers |
| A Merciful Exchange | Hard | survive | 1 | 13 vs 17 | Destroying a regenerating ally to gain life |
| Two Mouths, One Meal | Hard | clear | 1 | 12 vs 16 | Rebirth supplies a second sacrifice during defence |
| Keep the Quarry Alive | Expert | control | 2 | 17 vs 10 | Preserve an enemy through its own fatal upkeep |
| The Adoption Papers | Expert | control | 2 | 12 vs 17 | Clean the recruit before paying for control |



### Etherlords II

| Puzzle | Difficulty | Goal | Turns | Hero levels | Tactical theme |
| --- | --- | --- | --- | --- | --- |
| Copy Through Glass | Medium | win | 1 | 5 vs 11 | Copy an inaccessible enchantment |
| Throw Away the Shield | Medium | win | 1 | 14 vs 17 | Self-damage as a finishing attack |
| Two Appetites | Medium | clear | 1 | 10 vs 20 | Different devour tests and healing |
| Borrow the Door | Medium | clear | 1 | 7 vs 13 | Enemy manifestation and friendly shelter |
| The Enemy You Need | Medium | win | 1 | 9 vs 15 | Exploit an enemy's shared aura |
| Late Insurance | Medium | clear | 2 | 6 vs 8 | Wait for the correct response window |
| Lend Them Wings | Medium | clear | 1 | 13 vs 18 | Change an enemy's category before a sweep |
| Block the Smallest | Medium | win | 1 | 11 vs 14 | Let exactly enough damage through |
| Catch the Shockwave | Medium | clear | 1 | 8 vs 15 | Protect an ally before releasing a death effect |
| Not a Scratch | Hard | clear | 2 | 16 vs 12 | Poison prevention by physical armor |
| Bury It Tomorrow | Hard | survive | 2 | 15 vs 18 | Create a resource after the enemy can remove it |
| A Cage Built in Advance | Expert | control | 2 | 12 vs 19 | Prepare a capture, then ready its defender |



## Validation and its limits

All 22 new reference lines are executed through the repository’s real GDScript battle implementation and the objective observer in Godot 4.7.2. The test uses checked-in wiki card tables and narrow asset-free services. Each puzzle also has at least one separately validated legal wrong plan, checked by terminal replay or bounded adversarial search. There are 34 authored alternative prefixes in total. Bounded adversarial searches find a winning strategy for every new position and refute every authored wrong-plan prefix under the lab move generator. No-action and attack-everyone policies fail every new position against the goal-aware game AI. All reference actions are present in the lab’s generated move list.

The full 79-puzzle catalogs are rebuilt and replayed, and the old 57 entries are compared exactly with the base revision. The existing objective/hero-effect regression suite passes 198 assertions, with two additional duplicate-card enumeration checks. The expansion merger is checked for preservation, no-op reinstall, conflicts, dry-run, invalid targets and rollback after a simulated write failure.

A replay proves that its exact line is legal and reaches the stated goal. A losing example demonstrates that continuation, not that every continuation after its first move loses. Naive-policy failures do not establish human difficulty. This package does not claim an exhaustive forced-win or uniqueness certificate, does not promise that the native in-game solver finds every solution, and has not been manually played with an installed copy of the original game.

## Rebuild and verify

Use Python 3.10+ and a Godot 4.7.2 binary. Run from the repository root:

```sh
python tools/build_tactical_puzzles.py --godot /path/to/godot
python tools/build_tactical_puzzles.py --collection curiosities --prove --reference-policy --depth 32 --budget 80000 --report-dir build/curiosities-bounded-search --godot /path/to/godot
python tools/curiosities_check.py --runtime --baselines --proof-dir build/curiosities-bounded-search --godot /path/to/godot
python tools/install_puzzle_expansion_check.py
```

To build only the new content without replacing the installed full catalogs:

```sh
python tools/build_tactical_puzzles.py --collection curiosities --godot /path/to/godot
```

The subset is written to `build/puzzle-collections/curiosities`. The preservation check uses the pinned base commit; for a checkout without that Git history, pass `--base-dir /path/to/unzipped/reference/original_puzzles` to `curiosities_check.py`.

Exact bilingual solutions and command sequences are in [puzzle_curiosities_solutions.md](puzzle_curiosities_solutions.md).
