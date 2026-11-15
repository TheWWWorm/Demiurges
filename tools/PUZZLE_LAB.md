# Puzzle content validation

`puzzle_lab.py` runs the repository's actual `ELDuel`, `ELMatchSave`, card behavior,
and puzzle `Run` code without loading artwork or requiring a game installation.
It creates a small isolated Godot project and fills an `ELProfile` from the
printed card facts in `wiki/catalog/en.json`. The two editions have separate
costs, statistics, and abilities.

Requirements: Python 3 and Godot 4.6 or 4.7 on `PATH`. A C compiler named `cc` is
optional; when available it builds a temporary command-line bridge to the
repository's native battle engine. No downloaded packages are required.

## Replaying the authored solutions

Run from the repository root, replacing the absolute paths as appropriate:

```sh
python3 tools/puzzle_lab.py \
  --workspace=/tmp/demiurges-puzzle-lab \
  --file=/absolute/path/to/Demiurges/game/puzzles/el1.json \
  --report=/tmp/el1-puzzle-report.json
```

Use `el2.json` for Etherlords II. `--only=<puzzle-id>` selects one puzzle.
Every reference action must be legal. After each action, the independent goal
check must agree with the actual `ELPuzzles.Run` outcome. The final action must
solve the objective. The report includes every action, both heroes' health and
ether, remaining creature IDs, and the final snapshot. A failing solution returns
a nonzero exit code. GDScript runtime errors also make the wrapper fail, even when
Godot itself exits with zero.

The command fields follow `ELCombatSearch.apply`. For convenience, a cast may
name `card` instead of a hand index; the lab resolves the current index, so a
previous cast cannot shift the intended card. An optional `side` must match the
actual side to act. Missing cast fields default to `target=-1`, `grave=-1`, and
`power=0`; missing ability fields default to `target=-1`, `choice=-1`, and
`amount=-1`.

## Regression checks

Add `--regression` to exercise the actual runtime observer, including victory,
health floors, creature protection, clear-board objectives, survival timing,
capture targets and response windows, combined completion requirements,
Expert schema bounds, hint/mastery accounting, ordinary win timeouts, and the
puzzle-only fixed-supply rules. The same checks
also verify that ordinary duels still draw cards and gain natural ether channels.
The hero expansion adds real skill-rank validation, asymmetric hero levels,
Channeling on both sides, edition-specific disturbance, Regeneration cadence,
lethal disturbance before healing, maximum-health caps, and bilingual combatant
metadata independent of puzzle difficulty.
Run them once for each edition.

## Challenge and shortcut checks

Add `--search --depth=14 --budget=30000` to search all enumerated legal decisions
against an adversarial defender. The search uses actual GDScript state copies;
it does not use the computer player's heuristic move priorities. It includes
spell targets and X values, creature and hero abilities, attack declarations and
withdrawals, blocker assignments and changes, and ending the phase. Exact
repeated positions are skipped to avoid spending the entire budget on reversible
UI toggles. Blocker insertion order and the random-generator state are retained
in position keys.

For positions with many preparatory spells, add `--reference-order`. The lab
still generates the same legal moves, but tries the validated reference action
first at an exactly matching player snapshot. Every opponent response must
still be checked. Different snapshots receive no assumed continuation, and
wrong-prefix searches retain all their legal choices. Reports record this move
ordering explicitly; it improves the search for a winning strategy without
claiming that the reference line is the only solution.

For multi-turn positions, `--reference-policy` also transfers an ordering hint
between states with the same own hero resources (excluding current health),
own army (excluding its transient `hit` markers), phase, turn counters, attack
declarations and blocker assignments.
During defence, the incoming attack subset and own creature damage are also
omitted from this ordering context, so a demonstrated defensive choice can be
tried against a different attack. Existing blocker assignments still match.
This lets a known preparation be tried after a different enemy attack subset.
The opponent's state and the hero's health are ignored **only for ordering**:
full snapshots, including health, `hit` markers, opponent readiness, RNG and block order,
remain the search and memo keys. The hint must already be in the complete legal
move list. Every continuation and every defender reply is still searched, and
an illegal hint introduces no action. Reports name this broader ordering mode.
Implicit hero targets in no-target spells/abilities are canonicalized only in
the ordering copy; reference execution and recorded commands stay unchanged.

Search results are explicit:

- `forced`: a strategy reaches the objective against every enumerated response
  within the completed search.
- `refuted`: every enumerated route fails within the completed search.
- `unknown`: the action-depth or position budget prevents a conclusion. This is
  **not** evidence that the puzzle is impossible or uniquely solved.

`refutations` are tempting, legal action prefixes. Each is replayed and then
searched independently. A prefix that still has a forced solution is reported
and makes the run fail; a budget-limited prefix remains `unknown`. The report
never turns an incomplete search into a proof. Increase only the budget or depth
that a concrete unresolved puzzle needs.

For a targeted unresolved starting position, `--search --root-only` skips the
authored wrong-prefix searches. The report preserves the entire definition,
states the restricted search scope, and leaves the prefix-result array empty.
It certifies no wrong opening; retain any earlier prefix evidence separately
with its own recorded bounds. The pack builder's strict `--prove` route always
requests the complete root-and-prefix checks.

The pack builder's `--prove` option requires every root to be `forced` and every
authored wrong prefix to be `refuted`. Unknown results prevent the builder from
replacing either requested pack. Each new lab result carries its exact gameplay
definition so a later content change cannot inherit evidence for an older state.

The optional `--native --native_budget=1000000` also asks the unchanged C model
for a **hero victory** proof. This result appears separately as
`native_win_proof`: that engine does not represent the pack's clear-board,
protection, capture, or health-floor objectives, so its result cannot certify those goals.

`--baselines` tries four deliberately simple players: pass every phase, attack
with everything, use the plain computer player, and use its casts/abilities then
attack with everything. The defender uses the game's native search with a fixed
200,000-position budget. These rollouts help find easy patterns, but a heuristic
defender's mistake is not a proof. Each result includes the full command trace.
The plain/obvious players use ordinary combat heuristics; they do not receive
the puzzle's capture, reserve or survivor requirements as a planning objective.
A failure can therefore reflect a goal mismatch as well as a missed combination.
Use successful traces to inspect shortcuts, not failed-rollout counts to assign
human difficulty.

## Authoring helpers

Difficulty `level` runs from 1 (Easy) through 4 (Expert). It is an authored
judgment about the reasoning a human must perform, not a score assigned by
the search. Keep existing puzzle IDs when revising presentation or difficulty.

### Hero identities, levels and skills

`entry.level` remains the four-tier **puzzle difficulty**. The independent
`state.heroes[side].level` is the actual battle hero level, from 1 to 20. Cards and
Briefing show both combatants and their levels; search includes their English
and Russian names and level text.

Use `hero(..., level=12, template="GreenFemale2", turns=15, ...)` to author an
explicit hero appearance and clock. `state()` preserves supplied values instead
of replacing them with its legacy defaults. Its serial is the sum of the two
own-turn counters. Normal old definitions still produce the same gameplay.

The optional `hero_names` and `hero_names_ru` presentation fields each contain
exactly two nonempty strings in player/opponent order. They do not alter the
battle snapshot. Without them, the interface uses a snapshot title, an installed
template name, or the literal template identifier.

Skill values are zero-based ranks: `{"REGN": 2}` means rank-three Regeneration,
and `{"CNLG": 0}` means rank-one Channeling. Both heroes' ranks matter. Turn-start
disturbance is applied before Regeneration; a lethally damaged hero does not
recover. Describe a late clock explicitly in the briefing so the puzzle can be
reasoned through without reverse engineering its snapshot.

Snapshots contain an authored `maximum` health value. Restoring a snapshot does
not recalculate it from level. Healing and Greater Healing use that stored
value. Use verified template/level values when natural maximum health matters,
and state any authored scenario variation plainly. A template's appearance does
not itself grant a passive ability; put supported skills explicitly in the
snapshot. The new pack does not introduce random specialization effects.

All four objective types can add these completion requirements:

| Field | Meaning |
|---|---|
| `finish_health: N` | At least N hero health when the objective succeeds. |
| `finish_mana: N` | At least N unspent ether when the objective succeeds. |
| `min_allies: N` | At least N creatures currently owned by the player when the objective succeeds. |

These are checked together with the main objective. Temporary shortfalls are
allowed: a cleared battlefield can remain in play while the player heals or
rebuilds. If the duel ends or the turn budget expires without the requirements,
the attempt fails. In contrast, `min_health` and `protect` apply continuously;
breaking either is an immediate, irreversible failure for that attempt.

A control objective can additionally specify `enemy_turns: N`. All named
creatures must be alive and controlled after at least N enemy turns have ended
since the starting snapshot. This is a response window measured from the puzzle
start, not a timer starting at the moment of capture. It can complete on the
enemy-end boundary, just like survival, before the next own turn exceeds the
budget. Hero victory before that response window does not replace capture.

Final ether is measured in the settled state, including normal turn-start
refills at a survival or delayed-capture boundary. Set channels and the briefing
accordingly; use `protect` for an ally whose exact identity matters rather than
relying on the numerical army requirement.

`--normalize` writes the selected pack's starting snapshots with actual printed
creature flags and recalculated stats, including current enchantments and auras.
It preserves each puzzle's metadata and intended damage/ready state. Review the
resulting source diff. `--inspect` only checks that the states restore.

`--commands=/absolute/path/to/commands.json` replaces the reference line for a
selected puzzle, useful when examining a suspected shortcut. `--prepare` builds
the isolated workspace and prints its path for debugging. Use a different
workspace per concurrent process because the optional native bridge uses local
temporary input and output files.

## Scope of the evidence

The lab executes real combat behavior, but supplies card tables from the
repository's published wiki instead of mounting the player's original archives.
It rejects campaign scripts, campaign monster appearances, artifacts, and
random specialization fixtures and unsupported hero skills instead of silently
simulating them. Deterministic `REGN` (Regeneration) and `CNLG` (Channeling) ranks
are supported: registration rows come from the checked-in skill reference, while
rank validation and combat effects use the real game classes. Campaign skill
offers, experience progression and specialization probability tables are outside
this fixture. Hero templates are registered only to restore the supplied
snapshot, after checking its identity against edition-specific references in
`ELCatalog`, `ELDuelPresets` and the story-gallery metadata. An unreferenced or
wrong-edition appearance is rejected. This still does not verify availability
in the original archives or infer innate abilities from a hero appearance.
The authored pack freezes draws and natural channel growth; existing channels
refill normally and spell/ability effects still apply. This makes its behavior
independent of the unavailable original mana-income table.

Godot 4.6 requires explicit typed-array conversion at some returns that Godot
4.7 infers automatically. The wrapper adds this compatibility syntax only to
temporary copies; production source is not changed and battle logic is retained.
The C bridge similarly changes only transport into the native engine.

These checks establish legal reference solutions and recorded search results
under those fixtures. They do not replace checking the final build with the
player's original game data and the actual battle UI. The existing
`tools/puzzles_check.gd` remains the installed-data battle-screen check.

## Checking against the player's installed data

The same script can mount actual original tables without the offline wrapper:

```sh
godot --headless --path game --script ../tools/puzzle_lab.gd -- \
  --file=/absolute/path/to/Demiurges/game/puzzles/el2.json \
  --installed=/absolute/path/to/Etherlords-II \
  --report=/tmp/el2-installed-data-report.json
```

This route requires the project's Godot 4.7 engine and the player's own game
files. It uses the real `ELProfile.mount`, including the engine's normal edition
and patch handling. Add the same `--search`, `--baselines`, `--native`, or
`--regression` options as needed. The report identifies installed-data evidence
separately from wiki-fixture evidence. Do not pass `--installed` to the isolated
Python wrapper; it deliberately does not emulate mounting a game installation.
