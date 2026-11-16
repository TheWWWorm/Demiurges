# Tactical Studies: puzzle redesign

> Curiosities + Paradoxes + Crossroads: **48 additions, 105 total puzzles.** This page documents the preserved original 57. See [Curiosities](puzzle_curiosities.md), [Paradoxes](puzzle_paradoxes.md), [Crossroads](puzzle_crossroads.md), and [the newest solutions](puzzle_crossroads_solutions.md).

Tactical Studies contains **57 authored positions: 29 for Etherlords I and 28 for Etherlords II**. The Heroes and Creatures expansion adds 12 studies to the previous 45. It covers 33 victory challenges, 12 battlefield-clearance challenges, 8 survival challenges, and 4 capture challenges. The intended progression is 4 Easy, 17 Medium, 30 Hard, and 6 Expert. These labels are editorial judgments about human reasoning, not measured solve rates. All previously delivered IDs and gameplay definitions remain stable. Hero identity labels were added to the older studies for readable browsing.

The pack uses existing cards and combat behavior. Its changes are in the positions, objectives, guidance, and puzzle-specific resource rules. Both editions retain their own card costs and mechanics. The source is based on repository commit `a348000f7dda53ba48e9f6f37d3c07542f26c8cc`.

## Why the original collection felt repetitive

The original active packs contained 44 generated positions: 24 for the first game and 20 for the second. All began in the attack phase and asked the player to defeat the opposing hero within two to four own turns. The [candidate generator](../tools/duel_ai_puzzles.gd) sampled late positions from computer-played duels and deliberately excluded one-turn victories. This produced useful tactical material, but repeatedly framed the question as finding a winning attack from a narrow family of endgames.

The [packer](../tools/duel_puzzle_pack.gd) originally labeled a position Hard when exactly one of at least four opening commands preserved a forced victory. A two-turn position with at least a quarter of its openings winning was Easy; other cases were Medium. That measures **opening selectivity**, which need not match human difficulty. One obvious removal spell can be the only winning opening; several interchangeable preparations can belong to a demanding combination. Deduplication by duel seed also allowed closely related decks and tactical patterns to recur.

The redesign therefore starts from a distinct decision for each position: choose the sacrifice, assign defensive roles, exploit a targeting threshold, retain regeneration ether, sequence aura deaths, or plan for the opponent's response. Some studies deliberately have a short solution. Their challenge is recognizing why it works.

## Difficulty and player guidance

| Level | Intended reasoning demand |
| --- | --- |
| Easy | One central interaction, a small resource calculation, and a clearly explainable trap. These introduce the pack's way of asking questions. |
| Medium | Two linked decisions, a constrained resource, defensive assignment, or a timing rule such as summoning sickness. The player must look beyond the immediately attractive target. |
| Hard | Several interacting systems, retained damage, shared auras, meaningful enemy counterplay, or a plan spanning turns. A plausible greedy move must have a concrete reason to fail. |
| Expert | A compact position with several dependent decisions: resolve the enabling interaction, manage a scarce resource, account for an enemy response or delayed effect, and reach the exact finishing condition. Several attractive alternatives fail for different reasons. |

No score is awarded for matching a stored command sequence. **Any legal play that satisfies the objective succeeds.** Commuting preparations and genuinely different winning routes are allowed; the reference line explains one route. Human playtesting should later adjust labels using solve times, hint use, and players' explanations of mistakes.

Each study has a short briefing and three manually revealed hints. The first points toward the relevant interaction, the second focuses attention on the resource or target, and the third makes the combination concrete. Hiding and reopening a hint does not advance it. The explanation appears after success; failure reports the broken requirement without automatically revealing the solution. Titles, categories, briefings, all hints, and explanations have English and Russian text. Failure messages identify the lost protected or capture target, or the actual and required health values.

## Collection browsing and practice

The selector combines objective, difficulty, progress and text search. Search matches every typed word across the title, category, briefing, combatant names and hero-level text in both English and Russian. Hints and explanations are excluded so a search does not expose solution text. The query persists when switching editions.

Progress options are **All**, **Unsolved**, **Solved**, **Needs practice** (solved without a recorded hintless success), and **Hintless**. Continue starts the first matching unsolved study in All/Unsolved, or the first matching practice study in Needs practice. Solved and Hintless views keep explicit card selection. The counter distinguishes global completion from the number currently shown.

After a result, Next challenge follows the same combined filters. It scans forward and then wraps once, using First matching when it wraps. A tooltip names the destination. The current puzzle is excluded; Retry handles another attempt. If no other study matches, navigation disables without widening the filters. Goal and turn budget have their own card line. Two compact matchup rows show each actual hero level before the name; full names are available in the tooltip and Briefing. The filter says All difficulties to distinguish its four tiers from hero levels.

A star marks a successful attempt in which the player revealed no hints. Practice replays can earn it. The runtime tracks the deepest hint stage revealed, so reopening a hidden hint does not count as another hint, and browsing another edition cannot reset the running attempt's record. Fastest completion and fewest hints improve independently. A slower unassisted replay therefore earns the star without erasing a faster completion.

The old `user://puzzles.json` format is preserved. New hint records use `user://puzzle_mastery.json`; old completions do not receive an invented hintless badge when their historical hint use is unknown.

## Hero matchups and creature variety

The collection now uses hero levels **1 through 20**, with the actual selected levels being 1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 16, 18, 20. The new studies include asymmetric matchups: the stronger-looking hero need not have the easier task. A novice can win through a precise interaction; a veteran can deliberately spend health to keep a creature available for a later combination.

Hero level and puzzle difficulty are separate values. `entry.level` is an editorial difficulty tier from 1 to 4. `state.heroes[side].level` is the battle hero's level from 1 to 20. The interface reads the latter for each combatant. Scenario names are localized labels; they do not imply a new campaign character or innate passive ability. Named story appearances use the repository's corresponding template references.

The [actual hero-effect rules](../game/src/duel/hero_effects.gd) make the level choices mechanically useful:

| Property | Tactical consequence |
| --- | --- |
| Hero level | A higher level postpones ether disturbance at the same own-turn count. |
| Channeling | Delays its owner's disturbance and advances the opponent's; both ranks enter the calculation. |
| Regeneration | Restores one health on its rank's own-turn schedule, only below maximum. Lethal disturbance resolves first. |
| Stored maximum health | Healing and Greater Healing read the snapshot's maximum, so health recovery can depend on which hero profile is in the position. |
| Current health | A wounded veteran and a full-health novice can require different defensive plans even when the board is similar. |

Levels do not recalculate a restored snapshot's health. Every starting health and maximum is explicit. Capacities are explicitly authored for these scenarios. Some match saved positions for the same edition and template, while others follow the documented duel-preset fallback. They are not a reconstruction of unavailable original template tables. The repository's duel-preset fallback is `7 + 3 × level`, but it is not treated as proof of every original template's statistics. Random specialization effects are absent from this pack. Supported skills are written explicitly into the state, and their ranks and effects use the real game code.

Template identities are checked against edition-specific references from [the catalog](../game/src/duel/catalog.gd), [duel presets](../game/src/duel/duel_presets.gd), and the wiki's [Diamanda](../wiki/en/diamanda.md) and [White Lord](../wiki/en/white-lord.md) gallery entries. The offline validator rejects an unreferenced template or a form used in the wrong edition. Original-archive availability remains an installed-game check.

The starting armies, hands and graveyards now contain **71 distinct creature card types in Etherlords I** and **67 in Etherlords II**. The new studies introduce 30 previously unused first-game creature types and 24 second-game types under that definition. Counts exclude the unused fixed-hand deck and do not merge edition-specific rules.

Late-game clocks, skill ranks and unusual maximum-health conditions are stated in each relevant briefing. A player should be able to reason about the starting position before revealing a hint.

## Objectives and fixed resources

The [puzzle runtime](../game/src/duel/puzzles.gd) supports four objective types:

| Metadata | Success condition |
| --- | --- |
| `{"type": "win"}` | Win the duel within the allowed number of own turns. This remains the default for older entries. |
| `{"type": "clear"}` | Remove every enemy creature while keeping the hero alive, within the own-turn limit. Defeating the enemy hero while creatures remain does not satisfy this objective. |
| `{"type": "survive", "enemy_turns": N}` | Survive the specified completed enemy turns, or win sooner. Completion is checked at the enemy-turn boundary, before the next own turn causes a timeout. |
| `{"type": "control", "targets": [ids]}` | Take control of every specified enemy creature simultaneously, within the own-turn budget. Every target must remain alive; a destroyed or returned target fails immediately. Killing the enemy hero alone does not satisfy capture. |

Any objective can add `protect: [creature_ids]` and `min_health: N`. Protection means those exact creatures must remain alive and under the player's control. A health floor applies throughout the attempt. The runtime checks these requirements after each settled action, including the winning action, rather than only at the end or once per rendered frame. Sacrificing a protected creature and resurrecting it later cannot erase the failure.

The Expert expansion also supports conditions measured at completion:

| Metadata | Requirement |
| --- | --- |
| `finish_health: N` | Finish with at least N hero health. |
| `finish_mana: N` | Finish with at least N unspent ether. |
| `min_allies: N` | Finish with at least N creatures owned by the player. |
| `enemy_turns: N` on a control goal | Own all named, living targets after at least N enemy turns have ended since the initial snapshot. |

Temporary shortfalls in a completion requirement are legal. For example, after clearing the enemy army, the player can still heal or summon enough allies before the turn deadline. Winning the duel while a required reserve is missing ends the attempt in failure. The interface states each condition and reports the actual and required final value. A continuous `min_health` floor or exact-creature `protect` requirement still fails immediately when broken.

Delayed capture leaves room for the opponent's response. Its clock starts at the puzzle snapshot; it does not start when a target is captured. All targets must remain alive throughout, and all must belong to the player at completion. Delayed capture and survival can finish at the enemy-end boundary before the next own turn causes timeout. Final ether uses the settled state, including normal turn-start refills at that boundary.

Every authored position explicitly enables two rules, displayed in the battle interface:

- **Fixed hands:** `state.setup.puzzle_fixed_hands` suppresses deck draws, including draws requested by spells or abilities. Returning a card to hand or creating one through an effect still works. The starting hand is therefore a defined resource, but combinations can legitimately change it.
- **Fixed channels:** `state.setup.puzzle_fixed_channels` suppresses automatic channel growth from the turn-income table. Existing channels still provide their normal refill, subject to ordinary effects. Cards and abilities that change channels or ether retain their behavior.

These flags are opt-in. Ordinary duels continue to draw cards and use their usual natural income schedule. Retry restores the same starting snapshot. The interface keeps the objective and own-turn budget visible, including studies that begin in defence during the enemy's turn.

## Catalog

The previous 45 studies remain available. **New** marks this revision's additions. The stable authored difficulty sort preserves existing IDs and progress.

### Etherlords I

| ID | Title | Difficulty | Goal | Matchup |
| --- | --- | --- | --- | --- |
| `el1_tactical_v2_empty_battlements` | Empty Battlements | Easy | win | Kinet adept (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_count_the_ashes` | Count the Ashes | Easy | win | Chaot warrior (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_dangerous_promotion` | A Dangerous Promotion | Easy | clear | Synthet adept (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_one_open_lane` | One Open Lane | Medium | survive | Synthet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_two_locked_gates` | Two Locked Gates | Medium | win | Kinet adept (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_borrowed_life` | Borrowed Life | Medium | win | Vital warrior (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_late_arrival` | The Late Arrival | Medium | win | Synthet adept (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_balanced_destruction` | Balanced Destruction | Medium | win | Chaot warrior (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_silence_is_not_sleep` | Silence Is Not Sleep | Medium | win | Vital warrior (Lv 4) / Synthet adept (Lv 4) |
| `el1_tactical_v2_useful_survivor` | The Useful Survivor | Medium | win | Kinet adept (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_crowded_return` | The Crowded Return **New** | Medium | win | Vital healer (Lv 5) / Kinet matriarch (Lv 20) |
| `el1_tactical_v2_fall_of_the_crown` | Fall of the Crown | Hard | clear | Vital warrior (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_keep_the_spark` | Keep the Spark | Hard | win | Synthet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_cracked_mirror` | The Cracked Mirror | Hard | win | Synthet adept (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_buried_reserve` | Buried Reserve | Hard | win | Kinet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_lasting_wounds` | Lasting Wounds | Hard | clear | Chaot warrior (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_safe_passage` | Safe Passage | Hard | control | Kinet adept (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_wings_outlive_wizard` | Wings Outlive the Wizard | Hard | survive | Kinet adept (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_two_lives_one_reset` | Two Lives, One Reset | Hard | clear | Kinet adept (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_census_of_eyes` | A Census of Eyes | Hard | clear | Vital warrior (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_gift_too_generous` | A Gift Too Generous | Hard | survive | Chaot warrior (Lv 4) / Chaot warrior (Lv 4) |
| `el1_tactical_v2_empty_handed_standard` | The Empty-Handed Standard **New** | Hard | win | Chaot Marshal (Lv 16) / Kinet Novice (Lv 2) |
| `el1_tactical_v2_two_venoms_before_dawn` | Two Venoms Before Dawn **New** | Hard | win | Diamanda (Lv 8) / The White Lord (Lv 20) |
| `el1_tactical_v2_enemy_grave_recruit` | Recruit from the Enemy Grave **New** | Hard | clear | Omega-800D Diamanda (Lv 12) / Chaot Veteran (Lv 20) |
| `el1_tactical_v2_spare_the_parasite` | Spare the Parasite **New** | Hard | win | Synthet Novice (Lv 2) / The White Lord (Lv 20) |
| `el1_tactical_v2_room_for_two` | Room for Two **New** | Hard | win | Kinet Archmage (Lv 20) / Chaot Adept (Lv 5) |
| `el1_tactical_v2_every_coin_draws_blood` | Every Coin Draws Blood | Expert | win | Kinet adept (Lv 4) / Vital warrior (Lv 4) |
| `el1_tactical_v2_wall_after_battle` | The Wall After the Battle | Expert | survive | Kinet adept (Lv 4) / Kinet adept (Lv 4) |
| `el1_tactical_v2_borrowed_armour` | Borrowed Armour | Expert | control | Kinet adept (Lv 4) / Vital warrior (Lv 4) |

### Etherlords II

| ID | Title | Difficulty | Goal | Matchup |
| --- | --- | --- | --- | --- |
| `el2_tactical_v2_repair_by_breaking` | Repair by Breaking | Easy | win | Synthet adept (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_other_reservoir` | The Other Reservoir | Medium | win | Synthet adept (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_shield_elsewhere` | The Shield Belongs Elsewhere | Medium | survive | Kinet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el2_tactical_v2_invitation_to_discard` | An Invitation to Discard | Medium | survive | Kinet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el2_tactical_v2_last_ether` | The Last Ether | Medium | clear | Chaot warrior (Lv 4) / Vital warrior (Lv 4) |
| `el2_tactical_v2_exact_price` | The Exact Price | Medium | win | Kinet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el2_tactical_v2_borrowed_tomorrow` | Borrowed Tomorrow | Medium | win | Kinet adept (Lv 4) / Synthet adept (Lv 4) |
| `el2_tactical_v2_chain_of_custody` | Chain of Custody | Medium | control | Kinet adept (Lv 4) / Vital warrior (Lv 4) |
| `el2_tactical_v2_beneath_the_numbers` | Beneath the Numbers | Medium | clear | Vital warrior (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_smaller_well` | The Smaller Well **New** | Medium | survive | The Azure Adept (Lv 8) / The Winged Regent (Lv 12) |
| `el2_tactical_v2_second_attack` | Plan the Second Attack | Hard | win | Kinet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el2_tactical_v2_smaller_refund` | The Smaller Refund | Hard | win | Vital warrior (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_last_layer` | The Last Layer | Hard | win | Kinet adept (Lv 4) / White Lord (Lv 4) |
| `el2_tactical_v2_last_line_of_defence` | The Last Line of Defence | Hard | clear | Chaot warrior (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_every_road_hurts` | Every Road Hurts | Hard | win | Synthet adept (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_three_turn_lock` | A Three-Turn Lock | Hard | win | Kinet adept (Lv 4) / Chaot warrior (Lv 4) |
| `el2_tactical_v2_third_funeral` | The Third Funeral | Hard | win | Synthet adept (Lv 4) / Vital warrior (Lv 4) |
| `el2_tactical_v2_shared_escape` | A Shared Escape | Hard | control | Kinet adept (Lv 4) / Vital warrior (Lv 4) |
| `el2_tactical_v2_surviving_investment` | The Surviving Investment | Hard | clear | White Lord (Lv 4) / Vital warrior (Lv 4) |
| `el2_tactical_v2_airlock_census` | Airlock Census | Hard | clear | White Lord (Lv 4) / White Lord (Lv 4) |
| `el2_tactical_v2_last_breath` | The Last Breath | Hard | win | Vital warrior (Lv 4) / Kinet adept (Lv 4) |
| `el2_tactical_v2_midnight_census` | Midnight Census **New** | Hard | survive | The Crimson Keeper (Lv 3) / The Emerald Huntress (Lv 9) |
| `el2_tactical_v2_bank_discount` | Bank the Discount **New** | Hard | win | The Sapphire Veteran (Lv 12) / The Red Warlord (Lv 4) |
| `el2_tactical_v2_queens_shadow` | The Queen's Shadow **New** | Hard | win | The Verdant Matriarch (Lv 6) / The Scarlet Poacher (Lv 1) |
| `el2_tactical_v2_behind_magic_screen` | Behind the Magic Screen **New** | Hard | clear | The Iron Exile (Lv 10) / The Ashen Marshal (Lv 16) |
| `el2_tactical_v2_sealed_response` | Seal the Response | Expert | win | White Lord (Lv 4) / White Lord (Lv 4) |
| `el2_tactical_v2_delayed_verdicts` | Two Delayed Verdicts | Expert | win | White Lord (Lv 4) / White Lord (Lv 4) |
| `el2_tactical_v2_keep_gift_alive` | Keep the Gift Alive **New** | Expert | win | Diamanda, Last Form (Lv 20) / The Crimson Regent (Lv 18) |

## Integration and development

The runtime reads `game/puzzles/el1.json` and `game/puzzles/el2.json`. The authored packs use format `etherlords-puzzles`, version `2`, collection `Tactical Studies`, and collection ID `tactical-studies-v2`, and `content_revision: 4`. Stable, edition-prefixed IDs keep progress independent of list order and avoid inheriting completion from the replaced generated positions.

Entries retain `state`, `turns`, and `level`, and add `authored`, `objective`, `category`, `briefing`, three `hints`, and `explanation`. English fields are unsuffixed; Russian counterparts use `_ru`. `solution` is a replayable reference, while `refutations` contains labeled, tempting action prefixes for development checks. Neither field restricts the player's legal actions. Legacy entries without the new fields retain victory objectives and the existing hint fallback.

Edit the sources in [puzzle_designs_el1.py](../tools/puzzle_designs_el1.py), [puzzle_designs_el2.py](../tools/puzzle_designs_el2.py), or [puzzle_designs_pale.py](../tools/puzzle_designs_pale.py), with the corresponding translation module. The expansion sources are [puzzle_designs_el1_advanced.py](../tools/puzzle_designs_el1_advanced.py) and [puzzle_designs_el2_advanced.py](../tools/puzzle_designs_el2_advanced.py), each with inline bilingual metadata. The Expert expansion is authored in [puzzle_designs_el1_master.py](../tools/puzzle_designs_el1_master.py) and [puzzle_designs_el2_master.py](../tools/puzzle_designs_el2_master.py), also with inline bilingual metadata. The Heroes and Creatures expansion is authored in [puzzle_designs_el1_legends.py](../tools/puzzle_designs_el1_legends.py), [puzzle_designs_el1_legends_extra.py](../tools/puzzle_designs_el1_legends_extra.py), [puzzle_designs_el1_legends_crowd.py](../tools/puzzle_designs_el1_legends_crowd.py), and [puzzle_designs_el2_legends.py](../tools/puzzle_designs_el2_legends.py), including both combatant names and all instructional text in English and Russian. The shared [authoring helpers](../tools/puzzle_authoring.py) construct valid snapshots from canonical card information. Then build into a review directory:

```sh
python3 tools/build_tactical_puzzles.py --output-dir build/puzzles --prove
```

The [builder](../tools/build_tactical_puzzles.py) checks required bilingual metadata, normalizes creature flags and statistics through the real rules, replays every reference solution, and optionally searches adversarially. It validates the requested editions before writing their output. With `--prove`, every root must be forced and every authored wrong prefix refuted; an unknown result prevents replacement of the packs. Increase only the bound required by a specific unresolved study. Its default output directory is the active `game/puzzles` directory; use an explicit review directory while iterating. Inspect the resulting diff and reports before replacing released packs.

Use the [puzzle lab](../tools/puzzle_lab.py) for individual IDs, changed command sequences, regression checks, and shortcut baselines. [PUZZLE_LAB.md](../tools/PUZZLE_LAB.md) documents commands, limits, and the installed-data validation route. Recheck a position whenever its starting state, objective, or relevant combat rule changes.

## What the validation establishes

Every final reference solution is replayed through the repository's actual combat code and puzzle observer. Reports bind each search to its exact state, objective, turn budget, solution and authored wrong prefixes. The previously delivered 45 gameplay definitions remain unchanged; their completed searches are retained with explicit provenance and checked against the newly replayed final states. New studies receive fresh adversarial and baseline checks. Hero mechanics, supported skill ranks, source-referenced template identities and actual matchup display are checked separately. The validation summary records each hero's template, level, current/maximum health, own-turn count and skills.

The release evidence lists the result and bounds of every starting position and tempting alternative. These results concern the enumerated legal decisions within the recorded depth, position budget and repeated-position handling. They do not establish globally unique solutions or impossibility beyond the tested search domain. An unfinished search remains `unknown`.

The four baseline policies form a separate shortcut screen: passing every phase, attacking with everything, the plain computer policy, and its casts-then-attack variant. Their successes and failures are both retained. A heuristic success that follows the intended combination is not evidence that a puzzle is trivial for a human; a heuristic failure is not proof that it is difficult. The plain/obvious policies plan for ordinary combat and do not receive the custom puzzle goal; failures on capture or reserve requirements can reflect that mismatch.

The lab uses real battle GDScript with edition-specific card tables extracted from the checked-in wiki. Godot 4.6 compatibility coercions are confined to temporary test copies. **A full original-asset application running the project's Godot 4.7 engine was unavailable here.** The evidence therefore does not certify final rendering, asset integration, or every mounted-data difference. Release testing should replay both editions with the player's original game files and inspect the battle interface.

## Keeping generated candidates separate

The legacy packer now defaults to `res://puzzles/generated/<game>.json` and clearly logs its destination. It refuses to overwrite an authored collection by default; replacement requires an explicit `--out-pack=<path>`. Empty or ineligible results leave existing files intact.

Per-opening proofs must complete before their outcomes contribute to a generated difficulty label. Aborted, unresolved, and older incomplete rating records cannot imply a losing opening or a unique winning choice. Even a completed generator rating remains an opening-selectivity heuristic: new candidates still need editorial review, tactical variety checks, and human playtesting before joining the authored collection.
