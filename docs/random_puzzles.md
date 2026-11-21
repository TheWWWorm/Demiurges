# Random tactical challenges, version 6

Open **Puzzles → Random challenge**, choose a difficulty, and select
**Generate & play**. Both Etherlords I and Etherlords II are supported. The
same combat rules and card tables used by the installed game also construct,
prove and play the challenges.

The authored collection remains available under **Collection**. Generated
attempts have their own entry path and do not write authored completion or
mastery records.

## Choose the kind of challenge

| Tier | Certified lower bound on a guaranteed strategy | Scope |
| --- | --- | --- |
| Medium | At least one player spell or ability | Compact tactical interactions. |
| Hard | At least two player spells or abilities | Resource allocation, combinations, and some two-turn plans. |
| Expert | At least three player spells or abilities | More dependent actions and stronger replies to account for. |
| Master | At least four player spells or abilities, and a second own turn is necessary | Preparation, an intervening hostile turn, and a finishing plan that survives the opponent's choices. |

Attack and block declarations do not count as spells or abilities. These are
lower bounds on the resources needed to **guarantee** victory, not ratings
measured on human players. A cooperative opponent can sometimes allow a
shorter successful line; that does not bypass the adversarial difficulty test.

A two-turn challenge begins during the player's first turn and must be won
within the displayed allowance of two own turns. One-turn counterattack puzzles can
instead begin during enemy combat. The battle strip shows the actual allowance.
Master never silently falls back to a one-turn challenge.

## Playing, information and sharing

- Leave the input blank for a fresh challenge. Enter a positive integer or
  paste a complete code such as `ELP6:el1:5:12345` to reproduce a specific one.
- A code includes the generator version, edition, difficulty and seed. Pasting
  a code selects its installed edition. Copying it is available during play
  and on the result screen.
- **Restart** and **Try again** restore the exact starting position. **New
  challenge** uses the same difficulty and the session's variety selection.
- Fixed supply details in the briefing expose the hands and resource rules
  needed to reason about the opponent's replies. Current battlefield and
  creature information still come from the ordinary battle interface.
- Hints arrive in three stages: a useful question, a tactical relationship,
  then the combination. Results explain the idea. None of the proof internals
  are needed to play.
- **Tactical hint** checks the position you are playing now, including changes
  made by the opponent. It offers one verified next action when a winning
  continuation is proved, or says that the current position cannot guarantee
  the win after a complete refutation. A search limit produces no conclusion.
  It never plays the action for you. Requests and stale or inconclusive results
  do not count as hints; revealing a verified recommendation or refutation does.
- Cancellation, changing editions, changing screens and leaving the mode
  discard pending work. A cancelled request cannot open a battle later.

Hands do not draw naturally and channels do not grow naturally. Existing
channels still refill ether, and ordinary cards and abilities can change
supplies. Natural recovery, summoning sickness, graveyard order, retained
wounds, enchantment decay and death effects all follow the actual game rules.

Codes reproduce the position with the **same generator version and combat
rules/card tables**. Version 6 uses `ELP6`. Earlier `ELP1`–`ELP5` codes are
rejected with an explicit version message instead of producing a different
position under the old code. Keep the corresponding older build to replay
those codes. Future construction or acceptance changes must bump the version;
arbitrary balance mods cannot promise identical seeded output.

## Different tactical families

Positions come from seeded tactical constructions with changing roles,
resources and constraints. A recipe only proposes a position, reference line
and mistakes. It cannot certify its own output.

| Family | Main decision |
| --- | --- |
| A Narrow Front | Distribute enhancements to improve the damage left after the opponent's strongest block. |
| Crossed Lines | Allocate different damage sources across guards without wasting the damage needed to open the attack. |
| An Open Horizon | Identify the aerial route when the imposing ground threat cannot break the defence. |
| The Last Yard | Combine increased attack and reduced defence to force trample damage. |
| Two Gatekeepers | Rest a durable defender and remove a fragile one with different tools. |
| After the Storm | Preserve the necessary attacker before applying global damage. |
| A Dangerous Invitation | Enhance an enemy into a removal threshold, then arrange repeated activations safely. |
| A Fractured Reflection | Account for retained wounds when exchanging power and toughness before a sacrifice. |
| The Other Reserve | Take enough enemy ether to fund the finish while preserving the pool that determines damage. |
| The Turning Point | Keep the correct defensive survivor and use the refill for a lethal counterattack. |
| Keep a Reply | Retain a defensive ether reserve and adapt the next attack to whether the opponent attacks or holds its army. |
| A Second Wind | Prepare a creature that cannot recover normally, cover the hero, and finish without another ether refill. |
| The Buried / Living Relay | Reserve a returning corpse or living ally as a later readiness payment while accounting for temporary protection and enemy timing. |
| Borrowed Readiness | Choose a corpse that can act immediately and combine revival with the right answer to blockers. |
| After Their Choice | Prepare a defender, then spend a limited refill on power or evasion according to which attacker survives enemy removal. |
| The One Still Loyal | Secure two possible finishers against a dispel, then use the one still under your control instead of spending the finish on recapture. |
| A Crowded Hand | Return creatures to make hand size lethal, while preventing the symmetric damage from killing your own hero. |
| The Last Accounting / Life in the Aftermath | Preserve army power for Annihilation while surviving its return damage; harder positions account for death-trigger healing and graveyard damage. |
| The Newest Grave | Order deaths so automatic recovery returns the useful haste creature, then summon it as a ready finisher. |
| A Change of Aspect (Etherlords II) | Force the opposing controller to pay for both halves of a plane exchange; remove a directional lock before committing the harder exchange. |
| The Same Reservoir | Split one ether reserve between Comet and Tap Life: Comet clears the blocker, Tap Life takes the rest, and the attacker finishes. Expert adds a frail second blocker for Zap. |
| The Price of a Passage | Trade a disposable creature for a flying blocker, account for the opponent’s compensation, then finish using Comet and a flying attack. Expert adds Strength on the attacker. |
| Which Creature to Feed? (Etherlords II) | Choose which unit Carnivorous should consume; preserve the attacker and clear its aerial blocker. |


The same family can contain distinct plans, such as preventing a reply spell
versus surviving its damage, or bypassing a line of walls versus piercing a
single guard. Different numerical positions within a plan still share its
core idea. This is a finite, extensible collection of tactical grammars, not
an unlimited source of previously unseen game mechanics.

Version 4 added four families with different sources of victory. Hand-size
puzzles use returned cards as damage and can require discarding your own cards
or spending a targeted spell before its targets disappear. Death-accounting
puzzles use army power, healing during deaths, and removal of a dangerous own
corpse before a symmetric grave burn. Grave-priority puzzles depend on which
creature died last, rather than allowing an arbitrary revival target. The
second game's aspect-toll puzzles require selecting two opposing creatures and
understanding whose ether and health pay for their transitions.

These additions are one-turn puzzles at Medium, Hard or Expert; they do not
add a needless turn to qualify for Master. Three Master families retain their
certified two-turn requirements and opposing choices. Version 6 withdrew
The One Still Loyal (`control_fork`) and A Second Wind (`restless_horizon`)
from Master: in all 72 of their codes among 180 sampled version 5 Master codes,
the plain first turn described under admission check 6 below already kept a
forced win. Their recipes remain at lower tiers.

| Tier | Etherlords I families | Etherlords II families |
| --- | --- | --- |
| Medium | 11 | 11 |
| Hard | 18 | 20 |
| Expert | 19 | 21 |
| Master | 3 | 3 |

There are 23 registered families overall: 21 in Etherlords I and 23 in Etherlords II in the expanded recipe catalogue. Three new families focus on variable-cost spells, two-target compensation and sacrificial spell effects. Each new candidate still has to pass the generator’s exact adversarial proof and runtime replay gates.

### Variety across a session

Fresh selection starts with a balanced shuffle of supported families, putting
the immediately previous family last. It may move to another family when the
first proposals repeat a recent decision structure. It remembers 64 delivered
material positions; the distinct decision preference uses the last 12 entries
from the same edition, including entries played at another difficulty.

The new **decision fingerprint** replays the reference through real combat and
records actual spell/ability semantics, anonymous participants, shared source
and target relationships, changes to health/resources/zones, and phase/turn
boundaries. Enhancing a creature and consuming that same creature differs from
enhancing one and consuming another. Family names, variant labels, story text,
card codes, absolute entity identifiers and numeric magnitudes do not create
novelty. Verified commuting preparations are normalized where supported.

This is a conservative description of one reference, not an equivalence proof
for every winning strategy or a human originality score. Some genuinely
different positions can share a fingerprint. Cross-family collisions are
reported explicitly instead of being hidden behind family labels. Material
fingerprints and the older reference-plan fingerprints remain available as
separate measurements.

Within a family, the selector prefers its less recently encountered semantic
variant and an unfamiliar reference plan. After at most four previews in a
family it can move on to seek an unseen decision structure elsewhere. Normal
deterministic rejection can admit a different candidate from the preview, so
the completed, certified result is checked again. A certified non-repeating
material fallback can be retained while one further request seeks a better
alternative. Reports disclose a repeated decision and relaxed preference.

The decision preference is bounded and can relax when the searched alternatives
or remaining work do not supply a new one. Exact recent material repetition
remains disallowed. Selection never claims unlimited new mechanisms, and a
bounded request can report that it found no fresh certified challenge.

Replaying a known code refreshes its recency without adding another copy;
retrying the current attempt adds no history item. Generation and cancellation
do not record unplayed candidates. An explicit seed bypasses history. Fresh
selection chooses a seed and runs the ordinary deterministic generator; history
never changes the code's entry, solution, hints or certificate. History is held
in memory and resets when the puzzle-mode instance is recreated.

## Admission checks

Every delivered entry passes these independent gates:

1. **Valid, live position.** The ordinary schema and duel restore must accept
   an unfinished state with fixed supplies and an ordinary victory goal.
2. **Forced victory.** Actual GDScript combat proves a player strategy that
   wins within the allowance against every legal enemy response. It does not
   rely on the battle AI's heuristic move shortlist.
3. **No smaller guaranteed combination.** A restricted search must completely
   refute strategies using fewer than the tier's required spells/abilities.
   This cap applies across the whole attempt, including later turns.
4. **The extra turn matters.** Every two-turn entry is separately searched
   with a one-turn allowance and unrestricted tactics. That search must be
   refuted. Merely setting the displayed allowance to two is insufficient.
5. **An opponent choice at Master.** The certified strategy must contain an
   opponent decision with multiple retained legal continuations. This is a
   structural check, not a claim that every such choice is equally hard.
6. **No obvious first turn at Master.** The original opponent's quick reading
   (its Easy setting, 40 positions per decision, no clock, so a code still
   yields one entry) plays the player's first attack phase. If that already
   wins, or a completed proof shows the win is still forced from where it
   leaves the position, the candidate is rejected (`naive_first_turn`). Version
   5 admitted such positions in about three Master codes of five. An unknown
   proof result does not reject.
7. **A meaningful mistake.** A plausible wrong target, resource allocation or
   ordering must be legal, and a completed continuation proof must show that
   it loses the player's guarantee. Mistakes can include committing an early
   attack; the verifier retains the original turn deadline and never dictates
   a cooperative enemy reply. A recipe's assertion is not sufficient.
8. **Runtime replay.** Both the recipe reference behind the hints and the
   solver's principal line must finish as solved through `ELPuzzles.Run` and
   its normal settled-action observer, without changing authored progress.
   Their player abilities must also be available in the ordinary battle
   interface; execution-only edge cases cannot become published instructions.

Exhaustion of a depth or node budget is **unknown**. Unknown victory,
shortcut, one-turn or mistake results are rejected. Several valid orders or
winning plans may exist; this generator does not claim a unique solution.

The winning certificate also reports action/tactic and own-turn ranges across
the selected strategy, maximum enemy choices and enemy tactical replies.
Those are descriptive measurements of one certified strategy. The separate
restricted refutations establish its guaranteed difficulty floor.

## Implementation and cost

- `game/src/duel/puzzle_recipes.gd`: registration, shared construction helpers,
  normalization, and the original tactical families.
- `game/src/duel/puzzle_mortality_recipes.gd`: death accounting and ordered
  graveyard recovery, with edition-specific costs and effects.
- `game/src/duel/puzzle_zone_recipes.gd`: hand-size damage and opposing aspect
  tolls, with localized briefings, staged hints and candidate mistakes.
- `game/src/duel/puzzle_proof.gd`: incremental, bounded AND/OR proof. Player
  choices are alternatives; every retained opponent reply must be covered.
- `game/src/duel/puzzle_generator.gd`: quality gates, codes, runtime replays,
  decision/plan/material fingerprints, and bounded fresh-selection sessions.
- `game/src/duel/puzzle_advice.gd`: opt-in analysis of a copied live position,
  with the original turn deadline, stale-result detection and localized next
  actions. It leaves the live duel and authored progress untouched.
- `ELPuzzles.Run.begin_entry()`: independent attempts without authored
  completion writes. Puzzle mode handles tiers, cancellation, exact retries,
  code copying and the next challenge.

Legal enumeration retains duplicate hand indices, spell targets, variable
powers, grave/enchantment choices, abilities, attacks and ordered blocks.
It includes execution-legal paired sacrifices and resource-spending uses that
the ordinary AI may consider unproductive. Campaign scripts and custom spell
artifacts are explicitly outside the verifier's scope; current recipes use
neither. Advice and published reference lines require usable player controls.
State identity retains RNG and order-sensitive information. Pure assignment
histories are reduced while preserving reachable ordered configurations;
TeamAttack/Berserk dependencies and material changes such as paid declarations
remain available. Unknown results never become completed cache entries.

Work advances on the main thread in requested 6 ms slices. The clock decides
when to yield; deterministic limits decide acceptance. A single engine
operation can exceed a slice, so this is not a hard frame-time guarantee.
There is no new native binary, worker thread or background service requirement.

An explicit code allows at most 24 candidate proposals and 24,000 newly
expanded proof positions across all checks on Medium/Hard/Expert, or 60,000
on Master. Limits cover unsuccessful candidates too. A fresh request allows
at most 128 lightweight previews and four ordinary jobs, with a combined
node ceiling equal to two full jobs: 48,000 on Medium/Hard/Expert and 120,000
on Master. Before each job starts, its entire ordinary allowance must fit
under the remaining ceiling. Two cheap results that turn out to repeat recent
material therefore leave room for recovery, while two expensive jobs cannot
start a third. Individual code limits never change. Master is
allowed more work because the proof covers both the hostile turn and the
one-turn countercheck; complex positions can take noticeably longer.

Adding a family requires a real-rule witness, honest factual information,
plausible mistakes, semantic metadata, and test coverage in every supported
edition. An edition-specific mechanic must be excluded from other editions. Raising a difficulty label alone does not bypass its gates. The
current runtime intentionally caps generated positions at two own turns.

### Checking that a new mechanism is essential

The development variety audit first proves an unrestricted forced win for each
new-family sample, then repeats the proof with a nominated player operation
unavailable. For example, a hand-size puzzle must lose its guarantee without
Mind Blast, and a grave-order puzzle must lose its guarantee without its
newest-corpse recovery. A completed refutation is evidence that the operation
matters; a timeout is inconclusive and fails the audit.

`ELPuzzleProof` accepts a development-only `without_player` dictionary with
`casts` (card codes), `effects` (cast effect names), and `abilities` (base keys).
These restrictions remove matching player actions only. They do not remove a
card from hand, change resources, alter combat rules, or suppress enemy replies.
Player-facing advice rejects this option so a restricted refutation cannot be
presented as an ordinary loss. Normal generation uses its existing unrestricted
proof gates and unchanged node limits.

New recipe metadata declares `development_requirements` for the audit runner.
These labels never enter the decision fingerprint. Passing sampled audits does
not establish necessity for every possible future seed; the normal production
quality gates continue to apply to every generated challenge.

### Advice follows the live position

The hint search starts from an independent search copy of the live duel. It
retains order-sensitive state, card identities and RNG state, and uses the
remaining allowance derived from the original `ELPuzzles.Run` deadline. The
starting recipe's solution is never reused as if it described a later board.

A player can sometimes still win through a defensive ability after the last
allowed own turn. That position has zero future own turns, not one. Advice
handles the immediate defensive opportunity while treating any later own turn
as beyond the deadline. Asking for help never grants another refill or attack.

Changing the position, restarting, opening the puzzle list or leaving the mode
discards pending advice and hides obsolete guidance. Only the player can
request it, and only while the player has control. The same verified result can
be hidden and reopened without counting it repeatedly. Recipe hints and live
tactical hints have separate counts within the attempt's total assistance.

## Reproducing verification

Godot 4.7 is the project's target. The asset-free laboratory also supports
Godot 4.6 through narrow typed-array compatibility rewrites in copied sources.
Combat rules are copied from the repository; the fixture supplies per-edition
card tables and stubs for unavailable assets.

```sh
python3 tools/puzzle_generator_check.py \
  --samples=3 --report-dir=build/random-puzzle-validation

python3 tools/puzzle_generator_check.py \
  --difficulty=5 --samples=2 --session-samples=24 \
  --report-dir=build/random-master-validation

python3 tools/puzzle_variety_check.py \
  --file=build/random-puzzle-validation/el1-generated.json \
  --file=build/random-puzzle-validation/el2-generated.json \
  --require-new-families=hand_overload,funeral_math,grave_priority,aspect_toll \
  --report=build/random-variety/report.json

python3 tools/puzzle_generator_ui_check.py

python3 tools/puzzle_lab.py \
  --file=game/puzzles/el1.json --regression
```

The generator report separates accepted entries, rejected candidates,
material fingerprints, coarser reference-plan fingerprints, label-independent
decision fingerprints, proof metrics and fresh-session rows. The separate
variety audit reports cross-family overlaps and essential-operation results. Generated packs retain full snapshots, the verified
reference, winning witness and certified mistake, and can be independently
replayed through the older laboratory:

```sh
python3 tools/puzzle_lab.py \
  --file=build/random-puzzle-validation/el1-generated.json \
  --baselines --report=build/random-puzzle-validation/el1-replay.json
```

Use `--edition=el1`, `--difficulty=5`, `--family=grave_clock` and `--offset=1`
for targeted or held-out batches. `--code=ELP5:el1:5:12345` verifies a single
exact code and overrides batch selection. `--session-samples` exercises real fresh
selection, family variation, non-repetition and replaying its codes outside
history. Structural regressions include hostile refills, next-turn abilities,
conditional removal targets, wrong-side commands, cache depth, real turn
accounting, and cooperative traces shorter than the certified guarantee.
Live-advice regressions also check changing survivor targets, the zero-turn
defensive boundary, cancellation, unchanged live state and safe next actions.

The UI runner checks real controls and behavior, including English and Russian
at 800 × 600. Asset-free validation cannot replace a full rendered run with
retail art/audio and installed data. Automated certificates establish rule
correctness and measurable challenge properties; they do not establish a
human enjoyment score or fully calibrated difficulty curve.


### Version 5: underused spells and cross-session spell repertoire

Three new spell-centric candidate grammars exercise distinct mechanisms:

- **The Same Reservoir** uses Tap Life, Comet, and at Expert Zap, with explicit
  X amounts. Both X spells deal one damage per ether, so the decision is the
  Comet's target: only it can destroy the blocker, and the attacker's power
  exceeds the blocker's toughness plus Tap Life's (and Zap's) base cost, so
  burning the hero with everything always falls short.
- **The Price of a Passage** uses Trade's ordered secondary creature target,
  including healing paid to the other creature's controller. Removing an aerial
  blocker is not free damage. Comet's X always exceeds the guard's toughness,
  so killing the guard with Comet instead leaves less damage than paying
  Trade's debt. Expert enhances the surviving flyer with Strength, which is
  worth more than the same ether in Comet's X.
- **Which Creature to Feed?** (EL2) uses Carnivorous' sacrifice, healing/draw
  and the choice of preserving a flying finisher, then uses Lightning to open
  its lane. The guard always has toughness Lightning can destroy. The harder
  variant prepares the sacrificed creature with Strength.

These are recipe proposals, not pre-certified puzzles. They call the actual
combat rules to calibrate effect values, then submit to unchanged opponent-
robust proof, minimum-action, and meaningful-mistake gates. If a particular
seed cannot pass within the node budget it fails explicitly instead of using
an unverified fallback.

The freshness selector additionally tracks **performed spells** (not every
card in a hand) and two complementary repertoire keys:

1. Normalized rule roles, from the rule catalogue; mechanically equivalent
   printed cards may share a role.
2. Printed card codes, so repeated use of an identical spell can be noticed
   even when its decision structure is new.

Within a recent 12-challenge window, unseen roles and printed spells gain a
secondary preference. A new decision structure remains higher priority, and
material repeats remain forbidden inside the existing 64-entry session window.
This never rewrites a seeded code. The variety result includes the spell roles
and cards used by the certified reference and which were new relative to the
session window.

**Validation:** the three families generate, prove and replay at Hard and
Expert in both editions with `tools/puzzle_generator_check.py` on Godot 4.7,
alongside the full matrix, the variety audit and the user-interface check. The
game still refuses any candidate that fails a proof.
