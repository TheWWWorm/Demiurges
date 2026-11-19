# Crucible / Горнило

**Ten new Expert puzzles, five for each game, with ordinary victory objectives and a maximum of three own turns.** One puzzle has a one-turn limit, eight have two turns, and one has three. The collection concentrates on resource timing, difficult defensive assignments, interacting creature abilities, and lethal attacks that must survive the opponent's replies.

The catalogs now contain **175 puzzles: 87 for Etherlords I and 88 for Etherlords II**. All 165 earlier entries retain their exact definitions, presentation, and relative order. This expansion is `crucible-v1`, at content revision **12**.

## Find and play

Open **Puzzles**, select **Expert**, and search **Crucible** or **Горнило**. Each puzzle includes an English and Russian briefing, three staged hints, and a solution explanation. Any legal winning plan within the deadline is accepted; the reference line is not a required script.

The limits count your own turns. **Two Bequests** begins during an enemy attack, so its opening defence precedes the two own turns available. Fixed hands and fixed channel growth remove random draws and automatic channel increases; existing channels still refill, and explicit card and channel effects work normally.

## New puzzles

These themes describe the challenges without giving move sequences.

| Game | Puzzle | Russian title | Own turns | Theme |
| --- | --- | --- | --- | --- |
| I | The Buried Reserve | Погребённый резерв | 2 | Graveyard timing and resources held across two battles |
| I | A Mortal Equation | Смертельное уравнение | 1 | Health, ether and the exact cost of a lethal spell |
| I | The Frozen Account | Замороженный счёт | 2 | Resource denial, upkeep and a defensive reserve |
| I | The Black Furnace | Чёрная печь | 2 | Damage across attacks and response windows |
| I | Two Bequests | Два наследства | 2 | Surviving a siege before assembling the finishing attack |
| II | Borrowed Violence | Заёмная сила | 2 | Reanimation, immediate pressure and a limited reserve |
| II | Glass Furnace | Стеклянная печь | 2 | Defensive investment and a returned spell |
| II | The Last Funeral | Последние похороны | 2 | Forced attacks, precise blocks and a counterstroke |
| II | Two Doors, One Key | Две двери — один ключ | 2 | Planar movement, health conversion and hostile replies |
| II | The Venom Clock | Часы яда | 3 | Poison, ordered blocks and resources that cannot refill |

Expert is an authoring judgment. Short turn limits do not imply short combinations, and solver effort does not measure human difficulty.

## Install or rebuild

The checked-in catalogs already include Crucible. For development, run these commands from the repository root with Python 3.10+, Godot 4.7, and a C compiler available as `cc`. Set `CRUCIBLE_GODOT` to the executable if it is not named `godot` on your `PATH`.

```sh
CRUCIBLE_GODOT=godot

# Build only the ten additions into a separate directory.
python tools/build_tactical_puzzles.py --collection crucible \
  --godot "$CRUCIBLE_GODOT" --report-dir build/crucible-build

# Check an additive installation, then install it.
python tools/install_puzzle_expansion.py . \
  --pack build/puzzle-collections/crucible --dry-run
python tools/install_puzzle_expansion.py . \
  --pack build/puzzle-collections/crucible

# Rebuild the complete catalogs from this checkout.
python tools/build_tactical_puzzles.py --godot "$CRUCIBLE_GODOT"
python tools/install_puzzle_expansion_check.py
```

The installer target `.` is a Demiurges source checkout; replace it with another checkout's path to install there. It merges by ID, preserves existing entries, refuses conflicting definitions, and backs up changed catalogs under the target's `build/puzzle-backups`. Reinstalling the same expansion makes no changes. Installing puzzle data alone does not install its Python authoring modules; rebuilding another checkout also requires the accompanying source changes.

Subset builds go to `build/puzzle-collections/crucible` and cannot replace `game/puzzles`. The full builder replays **115 authored references**, then appends **60 archived entries** from the shipped catalogs while preserving their installed order within each difficulty tier. Appending archives is not a replay of their solutions.

## Verification and its limits

The ten new reference solutions passed in the actual GDScript battle implementation, using checked-in wiki card tables and narrow offline fixture services. All **143 reference actions** also passed individual native/GDScript state comparisons. These checks exercise battle logic; original installed assets and the rendered game UI were not exercised.

The final strict quality check passed with **zero errors and zero review notes**. It checked all ten live starting positions, their reference lines, one additional winning line for The Black Furnace, and all **23 declared wrong-plan prefixes**: 21 covered by GDScript proof or terminal replay, with two using the separately identified native fallback. All nine installer tests passed.

Bounded GDScript search found forced winning strategies for all ten starting positions, with reference-assisted move ordering. The separate native model completed minimum-turn certificates for **nine puzzles**, ruling out shorter horizons where applicable. **Two Bequests** remains an exception: its native proof aborted and is inconclusive. Its legal reference replay and GDScript forced-win result establish a solution within the allowance, but the native audit does not certify its minimum.

The native player also found winning lines for all ten across the tested decision budgets: seven at 200,000 and the remaining three at the repository's 8,000,000 setting. Clock limits were disabled for these reproducible budget-controlled checks, so they do not establish live-game solve times. Passing every phase and attacking with every available creature both failed all ten. More capable heuristic policies solved The Buried Reserve through its intended combination; these policy results are diagnostic observations, not ratings of human difficulty.

The 165 earlier entries were compared against commit `5d39ca49b07b0fd65adc7eaca4ce89d70c704c6c`, including their order. Of their reference solutions, **152 supported offline replays passed**; **13 are unsupported by this offline harness** and are not claimed as runtime-verified by this update.

A reference replay proves its particular legal outcome. Native comparisons cover the reference actions, not every possible branch. A wrong-plan prefix is a specific commitment; refuting it does not make the full puzzle's solution unique. Unknown, unsupported, or aborted searches are not winning or losing proofs. Alternative solutions are allowed, and no uniqueness or exhaustive engine-equivalence claim is made.

## Reproduce the checks

After building the Crucible subset above, run structural checks and fresh runtime checks:

```sh
python tools/curiosities_check.py --collection crucible
python tools/curiosities_check.py --collection crucible --runtime --baselines \
  --godot "$CRUCIBLE_GODOT" --report-dir build/crucible-runtime
```

The checker defaults to the pre-Crucible preservation commit. A checkout without that history can supply `--base-dir /path/to/previous/catalogs`, containing the earlier `el1.json` and `el2.json`.

For adversarial evidence, use separate report directories and one lab per edition. Absolute input paths below are derived from the current repository root because Godot runs inside each lab:

```sh
mkdir -p build/crucible-proofs build/crucible-native
for edition in el1 el2; do
  python tools/puzzle_lab.py --godot "$CRUCIBLE_GODOT" \
    --workspace "build/crucible-lab-$edition" \
    --file="$PWD/build/puzzle-collections/crucible/$edition.json" \
    --search --reference-policy --depth=42 --budget=150000 \
    --report="$PWD/build/crucible-proofs/$edition.json"
  cp tools/crucible_audit.gd "build/crucible-lab-$edition/"
  "$CRUCIBLE_GODOT" --headless --path "build/crucible-lab-$edition" \
    --script crucible_audit.gd -- \
    --file="$PWD/build/puzzle-collections/crucible/$edition.json" \
    --report="$PWD/build/crucible-native/$edition.json" \
    --native --native-refutations --parity --native-budget=3000000
done

python tools/curiosities_check.py --collection crucible \
  --runtime --baselines --require-proofs --godot "$CRUCIBLE_GODOT" \
  --proof-dir build/crucible-proofs --native-proof-dir build/crucible-native \
  --report-dir build/crucible-quality
```

These are finite search bounds. An inconclusive report can require a focused rerun with a larger bound; a zero exit code from the search alone does not establish completed proofs. The strict checker requires a fresh runtime report, exact gameplay definitions, a completed root proof, and evidence for every declared wrong-plan prefix. It accepts native fallback only with matching reference parity and prefix replay evidence, and reports native and GDScript results separately. Conflicting verdicts fail the check. Retain the generated reports to record which backend and bounds support each result.

Authoring sources are [puzzle_designs_el1_crucible.py](../tools/puzzle_designs_el1_crucible.py) and [puzzle_designs_el2_crucible.py](../tools/puzzle_designs_el2_crucible.py). They contain the full bilingual hints, explanations, exact reference lines and tested wrong plans, so reading them reveals solutions.
