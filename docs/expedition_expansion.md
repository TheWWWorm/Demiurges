# Ether Expedition expansion

This expansion develops the existing Etherlords II Expedition into a longer
roguelike deck-building run. It uses the existing combat engine, card effects,
campaign opponents, and boss scripts.

## Starting and resuming

Choose **Expedition** on the main menu, select a starter, and begin a **new** run.
You start with 40 gold and choose one of three passive relics: recovery after
victories, additional gold, or more spell reward options. All three kinds of
run decisions—survival, spending, and deck construction—are available immediately.
The four playable hero factions retain their existing starter selection.

New runs use **rules version 15**. Versions 1–7 retain their existing six-room acts.
Version 8 retains the first expansion's eight-room routes and original prices,
relic effects, and event selection. Resuming an older run does not silently
upgrade its rules. Version 9 retains its previous study-free rewards, guardian
relics, challenge-free elites, economy, and retry behavior. Version 10 keeps its
previous event pool, single spell exchanges, merchant offers, and battle-resume
randomness. Version 11 keeps its paid Haven exchange, camp-consuming reserve swap,
reserve-only Library and original cartographer bargain. Version 12 keeps its
four-item guardian reward pool and has no guardian combat powers. Version 13
retains its guardian combat powers and previous offers, without opening-spell
rehearsal. Version 14 retains its opening preparation, Spirit offers and
eighteen-event pool, without the new artifact projects and recharging services.
The version-15 gameplay changes leave versions 1–14 unchanged. Retry keeps the
finished run's rules version, seed, and difficulty.
From version 10 onward, an active duel is a
commitment: resume its saved state or surrender the run. Restarting an individual
duel to erase damage and reroll draws is disabled. A finished run can still be retried.

Version 11 and later preserve the exact random state of a saved duel. The
same saved position and subsequent commands produce the same future draws and
random effects. A failed checkpoint write pauses the run and keeps its current
state in memory. **Retry Save** saves and resumes that same duel. Normal menu,
quit, and renderer-restart actions wait for a successful save.

## Study paths

After the starting relic, choose one of your faction's three study paths, or
take **The Open Road** for 10 extra starting gold and unrestricted offers.

| Faction | Paths |
| --- | --- |
| Red | Ash Raiders; Cinder Circle; Night Hunters |
| Green | Living Swarm; Living Grove; Venom Trail |
| Blue | Sky Patrol; Mist Skirmishers; Spirit Covenant |
| Black | Scrap Custodians; Workshop Vanguard; Toxin Foundry |

A path biases the third ordinary spell-reward slot toward its theme, and the
fourth merchant slot. It does not give another card or change printed effects.
The other slots keep their normal creature, non-creature, and rarity preferences.
Focus candidates must be legal, implemented, within the four-copy limit, and
cost at most **3 / 5 / 8 ether in Acts I / II / III**, with one version-14
exception: **Spirit Covenant** can offer the four-ether **Warrior Spirit (WRSP)**
and **Shaman Spirit (SHSP)** in Act I. An eligible one of these is preferred in
the focus slot until you own a Spirit in either the active book or reserve.
Their printed prices and effects stay the same. Once you own a Spirit, the
school resumes its broader themed selection. When no suitable candidate remains,
the slot uses the normal pool. The Haven's missing anti-enchantment counter
takes precedence over its focus slot. The printed Spirit cards and their
Regeneration interactions are documented in the [lore sources](expedition_lore_sources.md#early-spirit-covenant-offers-in-version-14).

Paths use existing tribal and mechanical relationships: for example, bees and
ticks with swarm support, machines with repair, or direct damage behind walls.
The Deck panel lists their supported spells. At the new **Crossroads Archive**,
pay 18 gold to change paths or return to the Open Road, or take 12 gold for travel
notes and keep your current focus. Returning to the Open Road later does not
repeat its starting-gold bonus. Near the end of Act III, the Archive checks the
remaining route, including available Compass detours and the final Haven's
actual stock. A switch with no remaining offer to change is disabled; selling
your notes still gives 12 gold.

## Reserve and preparation

Your **two-page reserve** holds situational spells outside the active book.
When choosing a normal battle reward or buying from an ordinary merchant, you
can pack the incoming page in an empty reserve slot or replace a reserved page.
This consumes the same reward or purchase; it does not grant another card or
the recovery alternative. Replacing a reserved page discards that page.

At camp, choose a reserved spell and then the active page to exchange with it.
Both pages remain yours, and the active book keeps the same size. **Swapping is
free and does not use the camp action.** You may rearrange both reserve pages,
then choose one main action: healing, training, removal, study, foraging, or
opening-spell rehearsal, artifact assembly, or artifact recharging.
That main action closes the camp. Back cancels a pending swap without changes.
You cannot edit the reserve during a duel or return to a completed camp.

The Last Haven also allows free reserve swaps before the final duel, with no
one-swap limit. Purchases there still go directly into the active book. A swap
changes where already-owned pages sit; it does not grant or duplicate a spell.
Version 11 saves retain their original camp cost and paid 18-gold Haven exchange.

Active and reserved pages count together toward the four-copy ownership limit.
Only active pages enter battle or provide spell charges. Duelist's Crest still
uses the active book's size; a one-for-one reserve exchange cannot activate it
by shrinking the book. The UI shows active charges using the same Providence
rank calculation as combat, plus creature counts and printed-cost distribution.
These are factual comparisons, not card ratings or guaranteed strategy advice.

### Preparing an opening spell

From version 14 onward, you can rehearse one spell from your active book so that, while
prepared, it is among your **normal five opening cards in every duel**. It
occupies one of those five slots and keeps its usual casting cost, charges and
discard rules. Rehearsal
does not require another copy of the spell. Its other copies follow the normal
draw rules.

| Where | What you give up | When the choice takes effect |
| --- | --- | --- |
| Camp | The camp's one main action, instead of resting, training or another service | Confirming the spell completes the camp. Free reserve swaps and power preparation are available first. |
| Shrine of Knowledge | The alternative copying job, which pays 12 gold | Confirming the free lesson completes the encounter. |
| Last Haven | 24 gold before the usual merchant price modifiers | Gold is paid on confirmation; the Haven remains open for other preparations. |

Choose the rehearsal service, inspect a spell, then confirm. **Back cancels
without payment or using the camp action.** Choosing a different spell replaces
the previous preparation and enables the new spell. The learned spell stays
disabled in the rehearsal list; use the free preparation control to enable it again.
Merchant's Seal and Living Heart affect the Haven fee through
the same combined multiplier and final rounding used by its other services.

At camp or the Haven, **Set aside opening preparation** is free. It restores
ordinary random openings and keeps the lesson. **Prepare again** enables the
same spell for free; neither action uses the camp's main service or merchant
stock. These controls are available before committing to the next room or duel.
Learning a different opening spell still requires a new lesson at its normal
cost. The selection and its set-aside state both survive saving.

Preparation follows the spell, not a particular duplicate. Removing one copy
does not matter while another remains in the active book. Moving its last active
copy into reserve keeps the selection but makes it inactive; a later free swap
back into the book restores the guarantee if you have not set the preparation
aside. Removing or replacing the final owned copy clears
the preparation. A crafted replacement does not inherit it. Comparisons warn
about these consequences before confirmation, and readiness and the Spellbook
panel distinguish prepared, set-aside and reserved spells.

The lesson is a new Expedition service from a Kinet scholar beside the established
[Shrine of Knowledge](../wiki/en/map-objects.md). The [source guide](expedition_lore_sources.md)
distinguishes the encounter from the original map object's specialization reward.

## Artifact projects and charges

Version 15 adds the **Artifact Constructor**, a Synthet workshop with up to
three unfinished projects. Take one to assemble later, or earn **12 gold**
sorting salvage. Projects use six original Etherlords II spells. They do not
add pages to the active book or reserve.

You can carry **one unfinished project and one completed travel artifact**.
Taking another project discards the old project but keeps the completed tool
usable. Assembly consumes the project and replaces the carried artifact;
its old charges are lost rather than transferred. Elite rewards also offer
one finished artifact with two charges as an alternative to the relic or
supplies. That choice preserves a different unfinished project and is followed
by the normal spell reward.

An unfinished project does nothing in combat. Finish it at any reachable camp,
or bring it to the guaranteed Last Haven before the final guardian. No second
random event is needed. The offer shows the completion destination and price,
and warns when no later camp can be reached.

| Service | Cost | Result |
| --- | --- | --- |
| Assemble at camp | The camp's main action | Complete the carried project with 2/2 charges and leave camp. |
| Recharge at camp | The camp's main action | Restore one charge and leave camp. |
| Assemble at the Last Haven | 28 gold before merchant modifiers | Complete the project with 2/2 charges; preparations remain open. |
| Recharge at a merchant or the Haven | 20 gold before merchant modifiers, once per visit | Restore one charge; stock and other services remain available. |
| Recharge at the Silent Reliquary | Three life per charge | Restore one or two missing charges, then complete the encounter. Enough life to survive is required. |

Assembly and recharge comparisons show the exact payment, resulting charges,
and anything being discarded. **Back spends nothing.** Merchant's Seal and
Living Heart modify the gold prices through the normal combined multiplier
and single rounding. A recharge cannot exceed the two-charge capacity.

These are **finite journey charges**: using one in combat leaves it spent
after the duel and after saving. They differ from the older Reliquary keepsake,
which still supplies one charge per duel. A depleted travel artifact stays
visible at 0/2 and can be recharged later. The finished artifact uses one of
the hero's five artifact slots; existing, borrowed and keepsake artifacts
still occupy their own slots.

All artifacts share the hero's **per-duel activation limit**: one without
Artificer, or two, four or eight with its three ranks. Two stored charges
therefore do not necessarily mean two uses in one fight. New recipes can be
activated in the attack phase from the round below, and become ready again
the round after use. Activating them costs no ether or hand card.

| Artifact's spell | Effect | First usable round |
| --- | --- | --- |
| Ether Drop / Капля Эфира | Gain two ether; Stasis can prevent the gain. | 1 |
| Unsummon / Развоплощение | Return a target creature to its owner's hand, including your own creature. | 1 |
| Repair / Ремонт | Return a creature from your graveyard to hand and damage the enemy hero by its printed power. Book charges are not restored. | 1 |
| Purify / Очистка | Remove one dispellable enchantment from a creature or hero. | 2 |
| Enlightenment / Просвещение | Discard your hand and draw the same number from remaining book charges. An empty or exhausted book cannot supply extra cards. | 2 |
| Assault / Штурм | Until the end of the enemy hero's turn, friendly creatures gain +2 power, +2 toughness, Trample and Berserk. | 3 |

The underlying spells keep their normal targets, immunity and prevention
rules. **Artifact spells still trigger spell traps and Data Attraction**,
including that power's life loss. **Spell Translocation** does not grant its
extra draw from an artifact cast. Purify still supports **Selective
Purification**, and **Expert Artificer** can preserve a charge. That activation
still counts against the shared per-duel limit. The Artificer skill's larger
allowance and the specialization's charge conservation are separate benefits.
The run records the charges actually left by combat.

Near the end of the run, recharge offers also check the remaining route and
the hero's shared allowance. A paid extra charge that cannot be used on any
remaining path is disabled. For example, a hero with one stored charge and
one artifact use per duel cannot buy a second charge at the final Haven.
Taking a full finished artifact is still possible there, with a warning
that only one of its two charges can be used in the remaining duel.

The Deck panel separates completed artifacts from unfinished projects and
links each tool to its original spell. Readiness shows the current charges
and shared allowance. The workshop story adapts the original blank-artifact,
Artifact Recipe and Artifact Recharger systems; the journey costs are new
mode rules. See [the bilingual source map](expedition_lore_sources.md#version-15-artifact-projects).

## Visible spellbinding recipes

The Mirror and Runesmith's Forge now let you choose the outgoing common/cantrip
page, then inspect up to two distinct rare/unique alternatives of the same spell
class. One matching your study path is preferred when available, with a broader
alternative when possible. Candidates cost at most **3 / 5 / 8 printed ether**
by act and obey the combined ownership cap.

| Service | Pages consumed | Result | Payment |
| --- | ---: | --- | --- |
| Spellwright's Mirror | 1 active page | 1 rarer page of the same class | 3 life |
| Runesmith's Forge | 1 active page | 1 rarer page of the same class | 32 gold |
| Resonant Anvil | 2 identical active pages | 1 rarer page of the same class | 12 gold |

Recipes are fixed by room and source page. Backing out, changing the source
selection, and reloading cannot reroll a source's offers. Payment and page changes
happen together on confirmation, and the completed service consumes the event.
The Mirror's copying/removal options and the Forge's training alternative remain.

The Anvil reduces the active book by one page, losing that page's initial duel
charges. It cannot reduce a book below eight pages or consume reserved pages.
It offers 10 gold in salvaged metal instead when you prefer to keep your pages.
Higher rarity alone does not guarantee a better spell for the current book.

## Routes and rewards

New runs have **three acts of eight rooms** each. The columns are shuffled and
connections vary by seed. The room mixture gives several opportunities to choose
between a stronger deck, recovery, an event, and an elite reward. Every route
contains at least the opening duel, a mid-act combat, and the guardian.

| Floor | Possible room kinds before column shuffling |
| --- | --- |
| 1 | Battle, battle, battle |
| 2 | Encounter, battle, encounter |
| 3 | Battle, elite, encounter |
| 4 | Merchant, rest, encounter |
| 5 | Battle, battle, elite |
| 6 | Encounter, merchant, rest |
| 7 | Elite, rest, treasure |
| 8 | Guardian |

Gold is settled once after a victory. Relic bonuses and courier payments are
shown in the reward receipt. Base payouts are:

| Victory | Act I | Act II | Act III |
| --- | --- | --- | --- |
| Ordinary battle | 15–20 | 17–22 | 19–24 |
| Elite or optional event elite | 31–36 | 34–39 | 37–42 |
| Guardian | 50–55 | 55–60 | 60–65 |

Elite victories give a choice of one passive relic or, from version 15, one
finished travel artifact, then the existing spell reward. From version 10 onward, guardians give the distinct keystone choice below instead
of an ordinary passive. Declining a relic gives **field supplies: 20
gold and 20% maximum-life recovery**. A treasure room gives a relic choice or
25 gold with the same recovery. Defeating the final guardian still ends the
run immediately. Gold is capped at 9,999.

Card rewards retain the existing creature/non-creature mixture, early cheap
creature preference, and rare/unique bonus choices for elites and guardians.
You still take one spell for the active book or reserve, or recover life.
More options do not mean more free cards.

Once per act, **redraw a spell reward for 12 gold**. The changed selection is
deterministic and survives saving, selecting a card, and backing out. It avoids
the previous offers when the available pool permits. If no genuinely different
set is available, the action is disabled; gold is never spent just to reorder
the same choices.

## Guardian powers and keystones

The first two guardians each grant one major reward. New runs offer **two
eligible combat powers and one unowned keystone**, then the ordinary guardian
spell reward. If a sparse mounted catalog has fewer eligible powers, remaining
keystones fill the empty choices. There are still only **two major rewards in
the entire run**: taking a power means passing up the other powers and keystone.
You may instead take 20 gold and 20% maximum-life recovery. The selection and
settled choice survive saves, and a guardian reward cannot be collected twice.
Versions 10–12 retain their three choices from the original four-keystone pool.

### Ten combat powers

Powers use existing Etherlords II spell and skill rules. Nine begin each duel
with an ordinary enchantment already attached to the hero; the initial attachment
costs no spellbook charge or ether and is not a spell cast. The power's activated
abilities still pay their normal costs. Opponents can dispel the enchantment;
it returns at the start of the next duel, not when a checkpoint is resumed.
Concentration instead prepares the existing hero skill before the opening draw.

| Faction | Power | What it changes |
| --- | --- | --- |
| Chaots / Red | Burnout | Once per own turn, pay 1 ether and sacrifice a creature to deal its power as damage to another creature or hero. |
| Chaots / Red | Crystal Ball | Your creatures have First Strike while the enchantment remains. |
| Vitals / Green | Ether Feeding | Once per own turn, pay 2 ether and sacrifice a creature to gain 2 ether channels. |
| Vitals / Green | Martyrdom | Pay 1 ether and sacrifice a creature to temporarily add its power and toughness to another creature and grant Trample; usable while blocking. |
| Kinets / Blue | Hostile Ambience | New enemy creatures arrive rested. Creatures arriving in Pale aspect and those unaffected by magic keep the original exceptions. |
| Kinets / Blue | Concentration | Gain at least the advanced rank: one extra spell every third own turn. An existing expert rank is preserved; offers omit a rank the starter already has. |
| Synthets / Black | Second Birth | Once per own turn, pay a creature's printed ether cost to return it from your graveyard directly to play. Spent book charges stay spent. |
| Synthets / Black | Data Attraction | Your enchantment and sorcery casts draw one spell and inflict 2 unavoidable damage on you. Creature spells do not trigger it. |
| Any faction | Energy Barrier | Reduce each magical attack against your hero by 3. It does not prevent melee damage or Data Attraction's damage. |
| Any faction | Transfer Aspects | Pay 1 ether to bring a creature from Pale aspect into the Ether while another bright creature moves into the Colourless Plane. Offered only when owned pages contain a suitable Pale/bright pair. |

New rewards are filtered to the hero's faction plus the two neutral powers.
Transfer Aspects considers the reserve when offering a build opportunity, but
only the active book enters a duel. You must still summon legal targets.
Magic immunity, target restrictions, activation timing and finite charges follow
the original engine; the power does not grant an unlimited supply of spells.

Learned powers start prepared. At camp or the Last Haven, **Prepare** or **Set
aside** is free and repeatable before the main camp action. This is especially
useful when Data Attraction would be too costly at low life. Preparation changes
neither ownership nor the two-reward limit. It cannot be changed during combat,
from the route, or in the middle of placing a spell page. The battle readiness
panel and spellbook show the exact effects and preparation state.

### The four keystones

| Keystone | Lasting effect |
| --- | --- |
| Blood Crown | Fight one hero level higher, capped at 20. The recovery alternative to spell rewards is unavailable; other healing remains available. |
| Living Heart | Gain 8 maximum life and immediately recover 8 life. Merchant prices rise by 20%. Its multiplier combines with Merchant's Seal before one final rounding. |
| Prismatic Quill | One more spell option in battle rewards; still choose one card. The once-per-act redraw costs no gold, without resetting a redraw already spent. |
| Wayfarer's Compass | Once per act, step into a disconnected room on the next floor. Normal connected steps do not spend it. It cannot skip a floor, guardian, or the final Haven. |

Compass detours are marked separately on the route. Only the actual disconnected
step consumes the act's use, including after a save/reload. Since a keystone is
first earned at the end of Act I, detours begin in Act II.

## Elite profiles

Entering an unscripted elite room opens a comparison before combat. The original
opponent is always available. Optional profiles preserve its cards, skills, and
tactical plan while exchanging life against level:

| Profile | Change to the actual opponent | Extra victory gold |
| --- | --- | ---: |
| Standard | No additional change | 0 |
| Overcharged | +1 level; 15% less life, rounded up | 10 |
| Fortified, from Act II | -1 level; 25% more life, rounded up | 10 |

Veteran difficulty is applied first, so the preview matches the actual battle.
Overcharged is unavailable at level 20; Fortified is unavailable at level 1.
Guardians, scripted opponents, and optional event duels keep their existing
entry rules. The extra gold settles once and is not multiplied by Veteran.
These profiles favor different books; they are not guaranteed to be equally
difficult or harder in every matchup. Fortified unlocks in Act II because the
early combat probes found its lower income could outweigh its extra life.

## Merchants

Each visit offers up to four distinct spells, up to one unowned relic, one healing
service, and one spell removal. You can buy several offers and leave when ready.
The list remains fixed throughout the visit and after reloading. From version 9
onward, merchants also sell provisions for the next duel.

Version-11 merchant stock excludes economic relics that cannot earn more than
their purchase price even under an optimistic remaining-route bound. This
counts the best room on each future floor, optional event duels, discounts,
Living Heart's surcharge, and the final Haven; final-boss gold has no later
spending opportunity. It is an upper bound, not an expected return or a promise
that a purchase will pay for itself. Master's Seal additionally needs enough
remaining training opportunities and legal skill ranks to use a third session.

- Spell prices start at 20 / 30 / 48 / 62 gold for cantrip / common / rare / unique,
  plus 3 gold for each act after the first.
- Relic prices now depend on the passive, with no act markup. See the table below.
- Healing costs 24 gold and restores 35% of maximum life, rounded up and capped
  at missing life. It is unavailable at full life.
- Removal starts at 40 gold and rises by 15 after each merchant removal. There
  is only one removal per visit, and the spellbook cannot fall below eight cards.
  Purifier's Stone subtracts 25 from the base price before the Merchant's Seal
  discount: a first removal costs 15 with Stone, or 12 with both relics.
  These examples exclude Living Heart's surcharge; with all three effects the
  first removal costs 15, using `ceil((40 - 25) × 0.8 × 1.2)`.
- Provisions cost 16 gold and give one extra hero level for the next duel only.
  They do not stack with existing provisions, and hero level remains capped at 20.
- From version 15, one recharge per visit restores a carried artifact charge
  for 20 gold before merchant modifiers, if the extra charge can still be used.

Selecting a spell opens the add/replace choice. **Gold is charged only when the
placement is confirmed. Back cancels without paying or consuming the stock.**
To put a purchase into a full 24-card active book, replace an active page.
Ordinary merchants also allow reserve placement; Haven purchases use the active
book. The combined four-copy limit still applies.
Unaffordable and already bought offers remain visible with their reason.

## The Last Haven and difficulty

From version 9 onward, entering White Lord's final room first opens **The Last Haven**.
Every route reaches this preparation stop. You can spend your remaining gold on
spells, healing, one removal, provisions, and a useful passive if an eligible
unowned passive remains, before pressing **Face White Lord**. You can inspect
the actual guardian before committing. Version 14 adds opening-spell rehearsal
for 24 gold before merchant modifiers; selecting and inspecting a spell costs
nothing until you confirm it.
Version 15 also lets you assemble a carried artifact project for 28 gold
before modifiers, with the same payment-on-confirmation rule.

If your book lacks its faction's supported anti-enchantment spell, the Haven
includes that spell in stock. This gives a final paid opportunity to answer the
guardian's wards. The offer obeys normal faction/card rules, and buying it still
requires an available slot or a replacement.

Late elite/treasure relic choices and Haven stock filter out passives that cannot
meaningfully affect the remaining preparation or duel. The supplies alternative
remains useful even when every suitable passive is already owned. Unfinished
courier contracts and bounties expire on entry: their payments must be earned
before the last spending opportunity.

Choose **Standard** or **Veteran** when starting a version-9-or-newer run. Standard keeps
the existing combat strength curve. Veteran gives all opponents 15% more life
(rounded up), plus one level for ordinary/elite encounters that do not use special
battle scripts. Guardians retain their levels and scripts. Veteran gives 15%
more **base** victory gold; it does not multiply relic or contract bonuses.
Difficulty persists through checkpoints and retry. Guardian scouting uses the
actual run's difficulty, seed, and rules.

## Passive relics

These are expedition passives, separate from the original charged artifacts.
They are unique within a run and do not take an artifact slot. Their full effects
are shown in the Deck panel and when offered.

| Relic | Merchant price before discounts | Effect |
| --- | ---: | --- |
| Amber Seed | 65 | Recover 2 life after each victory. |
| Silver Scale | 45 | Earn 6 extra gold after each victory. |
| Glass Compass | 65 | One additional spell option in battle rewards; still choose one. |
| Hunter's Badge | 60 | Earn 20 extra gold after elite and guardian victories, including event duels. |
| Merchant's Seal | 35 | Merchant prices are reduced by 20%, rounded up. Event bargains are unchanged. |
| Wayfarer's Rations | 65 | Recover 2 life when entering an event, merchant, rest site, or treasure room, including the Last Haven. |
| Pilgrim's Flask | 45 | Camp rest heals 45% of maximum life instead of 30%. |
| Ether Prism | 85 | Fight one hero level higher, capped at level 20. |
| Duelist's Crest | 80 | With at most 12 spells, fight two hero levels higher, capped at level 20. |
| Ember Purse | 45 | Earn 12 extra gold for winning by the end of round 8. Version 8 keeps its round-6 cutoff. |
| Purifier's Stone | 70 | Merchant removal costs 25 less gold before other discounts. Version 8 keeps free removal. |
| Master's Seal | 55 | Allow three skill-training sessions per run instead of two. |

For example, a small-book run can combine removal, the Duelist's Crest, and
extra reward choices to search for a compact plan. A run hunting elites can
prioritize the Hunter's Badge and spending power. Recovery relics support routes
that accept more fights or life-cost bargains. These are incentives to choose
different paths, not hard class restrictions.

Camp visits additionally offer **Gather supplies to sell** for 18 gold, using
the visit instead of resting, removing a spell, studying, or training.

## Nineteen encounter types

The original Wayside Spring, Spellwright's Mirror, Totem of the Wilds, Silent
Reliquary, and Bridge Warden remain. The reliquary and warden still unlock from
Act II. New events are:

| Encounter | Decision |
| --- | --- |
| Caravan in the Mist | Browse the merchant or take 12 gold for guiding the caravan. In version 14, you may return to the guiding choice until you buy something or use a merchant service. Cancelling a pending purchase keeps that option available. |
| The Lost Courier | Invest 20 gold for 55 after two future victories, or take 10 gold immediately. One contract may be active; it survives act transitions but must finish before the Last Haven. Late contracts are disabled when no route has two remaining scheduled nonfinal wins. |
| Runesmith's Forge | Pay 32 gold to exchange a chosen common/cantrip page for one of its affordable rarer recipes, or pay 38 for an available skill-training session. Choose one service. |
| The Wounded Cartographer | Carry him across for 24 / 28 / 32 gold at a cost of 4 / 5 / 6 life in Acts I / II / III, or pay 22 gold to recover 40% of maximum life. Versions 8–11 keep 4 life for 38 gold. |
| The Veteran's Trial | Accept an optional elite duel for its relic/artifact choice and spell reward, with 30 extra gold for victory by round 6. A loss ends the run. |
| The Sealed Vault | Claim the shown relic for 50 gold or 12 life. Both payment methods buy the same relic. Version 8 keeps 55 gold / 8 life. |
| Feast of Wanderers | Recover 15% life for free, pay 25 gold for 60% recovery, or pay 16 for one extra hero level in the next duel only. Provisions do not stack. |
| The Relic Broker | Inspect up to two unowned relics; exchange one of your own and 12 gold for the chosen passive. Select the incoming relic, then the outgoing one. Back cancels without paying. A Master's Seal supporting a third training session cannot be traded away. |
| The Bounty Board | Pay a 10-gold bond. Within the next two victories, defeat an elite for 40 gold, or win by round 8 for 30 gold. Only one bounty can be active. Failed/expired bounties pay nothing; guardians do not fulfill the elite bounty. |
| The Crossroads Archive | Pay 18 gold to change your study path, including a return to unrestricted offers, or take 12 gold for your notes and keep your current focus. Version 14 disables a late switch that cannot change any remaining offer. |
| The Resonant Anvil | Pay 12 gold to bind two identical active common/cantrip pages into one affordable rarer page of the same class, or salvage metal for 10 gold. |
| The Abandoned Library | Choose one of up to three affordable common/cantrip pages: add it to the active book, replace a page, or keep it in reserve. Alternatively, take 12 gold for the catalogue. Version 11 remains reserve-only. |
| Shrine of Knowledge | Rehearse an active spell for the normal opening hand at no gold cost, or earn 12 gold copying the scholar's notes. Choose one. Added in version 14. |
| Artifact Constructor | Take one unfinished project from up to three fixed offers, or gain 12 gold sorting salvage. Assembly at a later camp or the final Haven replaces the carried travel artifact only when completed. Added in version 15. |

Every event permits leaving. Life-cost choices require enough life to survive.
Offers and requirements are visible before confirming. An act assigns a shuffled
bag of distinct events to its event rooms, preventing repetition within that act.
Provisions, courier progress, and bounties appear in the route journal and Deck
panel. Bounties with no suitable remaining scheduled opponent are disabled.
From version 10 onward, offers check the actual two-victory deadline across act boundaries: an
intervening guardian consumes a victory without satisfying an elite bounty.
It also accounts for an available Compass detour. An offer promises a possible
route, not payment if you subsequently choose fewer or different combats.
The last Haven expires unfinished contracts, preventing promises of useful
post-run payments. The Veteran's Trial keeps its more demanding **round-6** bonus.
The paid Feast is disabled when its free modest meal would restore exactly the
same missing life. Provisions are disabled when the current effective hero level
is already 20. These guards do not change healing amounts or combat levels.

After a completed decision, a receipt shows actual gold, life, active-page,
reserve-page, relic, training, and preparation changes. It survives saving and
remains visible until the next room; merchant purchases update it while shopping.
Version 12 gives completed encounters a short closing line above those changes.
The scene establishes who is there and what happened; choice descriptions carry
costs and effects. English and Russian use the same rules and outcomes.

## Reading and choosing

Camp removal opens a separate card list, so the main choices are easy to find.
Add and Reserve destinations appear before the replacement list. Confirmation
buttons name the action, and comparisons show changed quantities rather than
repeating the entire book summary. The Spellbook panel keeps the full curve,
creature counts, copy limits and charge totals. Shops retain the scroll position
after a purchase. Camp rest is unavailable at full health, and a pending spell
cannot be wasted replacing an identical copy.
Merchant removal previews have a working confirmation button, including when
resuming a version-11 run. That interface fix does not change the saved rules.

Version 14 puts reachable rooms before the longer readiness summaries. Opening
an opponent's details and returning restores the original Inspect button and
scroll position. In the Spellbook panel, active spells and reserve now precede
detailed skills and guardian powers. Camps list free rearrangement and power
preparation, including the free opening-spell toggle, before the services that
end the visit. The new ordering applies to
version 14; the room-inspection return fix also helps resumed older runs.

The elite bounty explicitly distinguishes its objective from its deadline:
a guardian win uses one of the two chances but does not complete an elite bounty.
Late offers warn when only one further victory can pay before the Last Haven.

## Tactical encounter variety

New runs can encounter thirteen faction plans: bee swarms, treant growth, venom,
fungus sacrifice, raiders, direct damage, night hunters, aerial patrols, tempo,
spirit recursion, repairs, machine augmentation, and toxins. Scouting names the
plan and gives a counterplay hint alongside the actual opponent spellbook.

Each plan changes only a small part of the original book: up to 3–5 cards,
depending on act and encounter type. It retains at least half the original book
and at least one copy of each original unique creature. New cards must be legal,
implemented, non-artifact, same-faction, under the cost limit, and within four
copies. If the transformation cannot be made safely, the original book is used.

The opening normal duel and some later ordinary encounters keep their original
books. Poison and spirit plans unlock in Act II. Scripted encounters and all
guardians preserve their original scripts and decks. Eight-floor acts stretch
the existing difficulty curve; they do not accidentally count as later acts.

## Verification and remaining playtesting

The new checks run in the actual Godot game code with explicitly synthetic
tables and small campaign maps. They do not read or overwrite the player's
Expedition checkpoint.

```sh
godot --headless --editor --path game --import
godot --headless --path game --script ../tools/expedition_expansion_check.gd
godot --headless --path game --script ../tools/expedition_v10_check.gd
godot --headless --path game --script ../tools/expedition_v11_check.gd
godot --headless --path game --script ../tools/expedition_v12_check.gd
godot --headless --path game --script ../tools/expedition_save_failure_check.gd
godot --headless --path game --script ../tools/expedition_v11_economy_check.gd -- --seeds=64
godot --headless --path game --script ../tools/expedition_tactics_check.gd
godot --headless --path game --script ../tools/expedition_ui_check.gd
godot --headless --path game --script ../tools/expedition_journey_stress.gd
godot --headless --path game --script ../tools/expedition_economy_balance.gd -- --rules=12
```

Use the repository's supported **Godot 4.7**. The lifecycle checks cover seeded
routes, full journeys and retry, all new event and relic effects, shop boundaries,
real duel startup and checkpoint restore, malformed saves, and old route hashes.
The UI suite checks real controls in English and Russian at 1280×720. Headless
UI checks verify sizing, visibility, and interactions, not a rendered screenshot
of the original game's art.

The journey stress check uses forced victories with simulated damage and round
counts, random enabled decisions, and a JSON round trip after every transition.
It tests completion and checkpoint consistency, not whether an AI can win.

The original installed assets are required for end-to-end playtesting. The
automated suite proves state and transaction behavior; it does not establish
win rates or subjective difficulty. The next balance pass should compare a
recovery route, an elite-focused route, and a small-book route with all four
factions, particularly against the original scripted guardians.


## Balance evidence for version 9

The structural economy audit enumerates seeded routes and uses the actual run's
payout, shop, and event rules. Its route averages are uniform over enumerated
paths, not predictions of player choices or win rates. It exposed late payouts
without a useful merchant, dead final-elite relic offers, and the original
Purifier Stone's rapidly growing savings. The Haven, late-offer filtering,
differentiated relic prices, fixed removal discount, and contract deadline guards
address those concrete cases.

The combat benchmark plays real native-AI duels with printed spell/creature data
from the checked-in wiki and starter books recovered from checked-in duel
snapshots. It never forces the winner. Original campaign mobs and full original
mana-income tables were unavailable. Therefore its enemy books and interpolated
income remain explicit proxies. The fixture records provenance, and the benchmark
uses paired seeds/opening sides, bounded search, and separate failure tracking.
It is a controlled comparison, not an installed-game campaign win-rate estimate.

These comparisons supported retaining the existing level relics: their effect
varied by faction, deck, draw, and search budget. They supported an eight-round
Ember Purse/swift-bounty threshold: six rounds rarely triggered, while eight
favored pressure and compact books over slower engines. Ten rounds was too
broad for that intended niche. Ordinary reward healing was not reduced without
reliable original-content damage distributions.

Reproduce the combat fixture and a bounded pilot from the repository root:

```sh
python3 tools/expedition_balance_fixture.py --workspace /tmp/expedition-balance
godot --headless --path game --script ../tools/expedition_combat_balance.gd -- \
  --fixture=/tmp/expedition-balance/fixture.json \
  --output=/tmp/expedition-balance/pilot.jsonl \
  --styles=starter --variants=base --limit=8 --think-ms=0
```

The delivered handoff supplies the exact benchmark commands, assumptions, and
recorded reports for this pass.

## Balance evidence for version 10

The new offer audit compares the actual reward and merchant functions over
12 study paths, three acts, and 64 seeds. All 2,304 focused reward selections
and ordinary merchant selections contained an affordable eligible path card.
The corresponding unfocused baselines did so in 45.4% and 38.5% of cases.
The other two normal reward slots and three merchant slots stayed exactly
unchanged. Separate capped-copy and missing-pool cases retained legality and
fell back to the ordinary selection. These are offer-distribution checks, not
combat or player win-rate estimates.

Another 216 actual native-AI duels compared elite profiles on Standard and
Veteran and tested Living Heart's extra life. Previously recorded matching
+1-level cases supply an explicitly reused Blood Crown comparator. Early
Fortified foes were easier for the tested starter books, which prompted the
Act II eligibility gate. Midact effects differed across pressure, engine, and
compact books. The fixture's original-data limitations remain the same as in
the previous pass.

Living Heart preserves more life in these controlled duels. Its future merchant
surcharge, and Blood Crown's lost spell-reward recovery, require whole-run
decisions that single-duel comparisons do not price. A separate economy audit
checks exact combined prices and records recovery opportunity ceilings; those
ceilings are not predicted damage or realized healing loss.

After generating the fixture shown above, run the catalog and offer audits:

```sh
godot --headless --path game --script ../tools/expedition_paths_check.gd -- \
  --fixture=/tmp/expedition-balance/fixture.json
godot --headless --path game --script ../tools/expedition_draft_audit.gd -- \
  --fixture=/tmp/expedition-balance/fixture.json --seeds=64 \
  --output=/tmp/expedition-balance/draft-audit.jsonl
```

## Balance evidence for version 11

The printed-card audit covers 3,072 faction/path/act/seed scenarios. Its 29,184
source recipes all offered two distinct, legal, affordable alternatives, and
20,160 eligible focused recipes all included a matching study card. Library
offers preserve their first two ordinary slots while guiding the third where
possible. Separate sparse-catalog, copy-cap, aliasing, and consumption cases are
included in 182,834 assertions, with zero failures.

The previous Mirror's randomly chosen replacement exceeded the new act cost
ceiling in 63/256 Act I cases, 23/256 Act II cases, and 6/256 Act III cases.
Those fixed starter/seed comparisons explain the affordability change; they
are not campaign encounter probabilities.

A bounded new experiment played 40 actual native-AI duels: the same four
recorded starter matchups and both starting sides across the original book,
two Forge alternatives, and the corresponding two Anvil alternatives. All
completed without runner failures. Each changed group won five of eight cases,
versus four of eight for the baseline, but switching Anvil alternatives reversed
four paired outcomes. The Anvil books began with 30 spell charges rather than
32. Removing that extra source page sometimes lost a win and sometimes improved
a matchup, reflecting both finite charges and changed draws/AI decisions.
The Forge and Anvil gold payments are not priced by a single duel, and these
were not Mirror treatments: no three-life payment was applied.

The independent economy audit checked 33,792 node/act/opportunity/inclusion
states, including ordinary paths, Compass detours, and generated optional event
duels. The optimistic bounds never underestimated a legal route. Across 128
late merchants per version, v10 offered 26 economic relics unable to repay
their price and 12 Master's Seals unable to enable a third training session.
Version 11 offered none of either, while retaining a relic at every sampled
merchant. A direct comparison with the frozen version-10 implementation kept
all 4,224 sampled room offers and every sampled route/event assignment unchanged.
This measures eligibility and upper bounds, not player behavior or expected value.

Reproduce the new printed-card and bounded combat checks after preparing the
fixture above:

```sh
godot --headless --path game --script ../tools/expedition_crafting_check.gd -- \
  --fixture=/tmp/expedition-balance/fixture.json --seeds=64 \
  --output=/tmp/expedition-balance/crafting.jsonl
godot --headless --path game --script ../tools/expedition_crafting_combat.gd -- \
  --fixture=/tmp/expedition-balance/fixture.json \
  --output=/tmp/expedition-balance/crafting-combat.jsonl \
  --nodes=25000 --think-ms=0 --limit=40 --total-ms=240000 --game-ms=30000
```

## Balance rationale for version 12

The reserve previously charged twice for a situational spell: acquiring the page
used a reward or gold, then preparing it used an entire camp action. At the base
24 / 28 / 32 life caps, that could mean giving up 8 / 9 / 10 life of camp healing,
18 gold from foraging, or an available training session. Free rearrangement keeps
the acquisition cost and two-page limit while making preparation practical.
It preserves total ownership, active size and charges, including Crest eligibility.
The camp still permits only one main service, and combat still locks the book.

The Library now permits active placement because finding a readable page should
not require another stop. Its reward still competes with 12 gold, grants only one
page and uses the existing affordable common/cantrip pool. The four-copy limit
includes reserve pages, and a full book must replace rather than add a page.

The Cartographer's previous 38 gold for 4 life paid 9.5 gold per life in every act.
The new 24 / 28 / 32 gold for 4 / 5 / 6 life pays 6.0 / 5.6 / 5.33 gold per life.
The life cost remains about 17–19% of base maximum life, and the reward still
exceeds safe 18-gold foraging by 6 / 10 / 14 gold. These are resource comparisons,
not estimates of how often a player should take the bargain. Medicine stays
22 gold for 40% recovery. Combat levels, printed spells, Forge and Anvil prices,
reward healing and guardian scripts did not change in this pass.

The v12 lifecycle suite exercises these transactions and save boundaries with
synthetic content. Its frozen-v11 comparison covers 1,056 controlled room states
and 23 reachable selection/completion stages, using the old core with current
shared content and localization. The headless UI suite checks both languages;
full journeys use forced victories and JSON restoration after each transition.
This pass adds no native-AI duels or original-asset campaign win-rate evidence.
Earlier combat reports are retained as historical evidence, not counted again.


## Wiki writing and combat powers in version 13

The current scenes and endings, study descriptions, relic setting details and
scouting text now draw on the repository’s English and Russian wiki. The
[source map](expedition_lore_sources.md) identifies the exact articles and
printed-card pages, and separates canonical setting facts from new Expedition
meetings, items and reward rules. Costs stay in the choices; scenes explain why
the decision arises. The damaged Recharger and the courier contract explicitly
connect their life/gold costs to the situation.

The ten guardian powers above add sacrifice, permanent channel growth, temporary
stat transfer, revival, cast-triggered draws, arrival control and aspect exchanges.
They occupy the existing two major-reward slots. The normal spell engine handles
their activated costs, legal targets, dispels, damage and charge limits. No printed
card or native-AI combat rule was altered for this pass.

New tests cover acquisition through both guardians, free preparation, pending-page
isolation, saved ownership, malformed markers, dispels, exact resumed random state,
all ten effects and native state representation. The focused power UI checks both
languages at 1280×720, including the active-book warning for Transfer Aspects.

To reproduce the added checks with the supported Godot 4.7 runtime:

```sh
python3 tools/expedition_balance_fixture.py --workspace /tmp/expedition-balance
godot --headless --path game --script ../tools/expedition_attunements_check.gd -- --fixture=/tmp/expedition-balance/fixture.json --output=/tmp/attunements.json
godot --headless --path game --script ../tools/expedition_v13_check.gd -- --fixture=/tmp/expedition-balance/fixture.json --baseline=/path/to/v12/run.gd --seeds=16 --output=/tmp/v13-integration.json
godot --headless --path game --script ../tools/expedition_power_ui_check.gd
godot --headless --path game --script ../tools/expedition_v13_combat_balance.gd -- --fixture=/tmp/expedition-balance/fixture.json --styles=pressure,engine,thin,pale --enemy-style=pressure --player-level=4 --enemy-level=6 --player-life=28 --enemy-life=30 --nodes=12000 --think-ms=0 --limit=136 --total-ms=900000 --output=/tmp/power-balance.jsonl
```

The released pass completed 1,872 v13 integration assertions, 716 focused power
assertions, 126 focused UI assertions and 744 existing UI assertions, with zero
failures. Its v12 frozen comparison covers 1,056 room states and 23 lifecycle
stages. The older rule suites also pass.

There are 176 new complete AI-versus-AI duels: 136 paired power comparisons and
40 additional Green/Black engine-matchup probes. No winners were assigned and
all actions were accepted. These use the existing documented wiki-card and
interpolated-income harness, not original campaign scripts. Two-power builds
have real synergies, but their results depend on the matchup; the second probes
did not reproduce automatic wins. Full installed-game guardian playtests and
human feedback remain the next evidence needed for stronger balance claims.

## Version 14 verification

The completed checks cover the opening-hand rule, run persistence, offer changes
and UI, including the final free set-aside and reactivation controls:

| Check group | Assertions | Failures |
| --- | ---: | ---: |
| Run integration and compatibility | 1,635 | 0 |
| Opening-hand engine | 4,352 | 0 |
| Version-14 offers and guards | 2,118 | 0 |
| UI: 190 opening-spell checks, 126 power checks and 744 existing checks | 1,060 | 0 |

The integration suite includes 1,056 frozen-v13 room comparisons, 23 lifecycle
stages, four prepared-duel setups and five kinds of caravan purchase. It checks
suppressed preparation at camp and Haven, save identity and exact continuation.
Earlier versions 1–12 were also tested before the final version-14-only toggle
addition; those reports retain that source provenance. Controlled victories in
the integration tests reach lifecycle checkpoints and are not AI win-rate evidence.

The UI checks exercise English and Russian at 1280×720, including camp
cancellation, paid Haven confirmation, the free scholar lesson, reserve
inactivity and restoration, last-copy removal, free suppression and reactivation,
checkpoint reload, and route-inspection focus.
All three UI suites exited successfully with no runtime errors or warnings.
They use headless layout checks and synthetic tables; original-art rendering
and human playtesting are not covered by these totals. These assertion counts
do not establish a win rate or a final balance conclusion.

The new combat experiment completed **96 actual AI-versus-AI duels** across
32 matched contexts: four factions, two authored book styles, two enemy/seed
contexts and both starting sides, each with no preparation, a prepared cheap
creature and a prepared key spell. All games finished without refused commands,
empty decisions or assigned winners. Its **1,688 paired invariant comparisons**
also passed.

| Preparation | Wins / games | Openings changed from the matched baseline |
| --- | ---: | ---: |
| None | 17 / 32 | 0 |
| Cheap creature | 17 / 32 | 6 |
| Selected key spell | 15 / 32 | 20 |

These fixed matchups show why preparation can be set aside: selecting a known
page can displace another useful natural draw. Some losses became wins and some
wins became losses. The benchmark uses the real engine and native AI with
wiki-exported card data, authored opponents and the disclosed interpolated income
proxy. It does not simulate the camp's lost healing or supplies, the full run,
original guardian scripts or human choices. The 176 v13 power duels described
above remain historical evidence and are not part of these 96 new games.

The focused version-14 checks can be reproduced with Godot 4.7:

```sh
python3 tools/expedition_balance_fixture.py --workspace /tmp/expedition-balance
godot --headless --path game --script ../tools/expedition_opening_check.gd -- --fixture=/tmp/expedition-balance/fixture.json --baseline=/path/to/v13/state.gd --output=/tmp/opening-engine.json
godot --headless --path game --script ../tools/expedition_v14_offers_check.gd -- --fixture=/tmp/expedition-balance/fixture.json --baseline=/path/to/v13/run.gd --output=/tmp/v14-offers.json
godot --headless --path game --script ../tools/expedition_v14_check.gd -- --baseline=/path/to/v13/run.gd --output=/tmp/v14-integration.json
godot --headless --path game --script ../tools/expedition_opening_ui_check.gd
godot --headless --path game --script ../tools/expedition_power_ui_check.gd
godot --headless --path game --script ../tools/expedition_ui_check.gd
godot --headless --path game --script ../tools/expedition_v14_combat_balance.gd -- --fixture=/tmp/expedition-balance/fixture.json --nodes=12000 --think-ms=0 --limit=96 --output=/tmp/v14-combat.jsonl
```

### Version 15 interface verification

The artifact presentation checks and three existing interface suites passed
on Godot 4.7, in English and Russian at 1280×720:

| Suite | Checks | Failures |
| --- | ---: | ---: |
| Artifact projects, replacement, assembly and recharging | 402 | 0 |
| Opening-spell preparation regression | 190 | 0 |
| Guardian powers and skill inspection regression | 126 | 0 |
| Earlier Expedition interface regression | 744 | 0 |
| **Total** | **1,462** | **0** |

The new suite checks exact confirmation payments, cancellation without
changes, old-project versus old-artifact loss, depleted items, shared
Artificer limits, merchant reuse guards, the final Haven, life-cost recharging,
elite reward exclusivity, JSON reloads, unfinished-project text after both
victory and defeat, and the version-14 interface boundary.
It also checks that artifact details explain spell triggers without displaying
the source spell's ether price as an activation cost. All four commands exited
successfully; the complete logs contained no parse errors, runtime errors or
warnings.

These are headless layout and flow checks using synthetic profiles. They do
not verify original-art rendering, human play, or combat balance. Earlier
versioned combat and integration results above remain historical evidence;
they are not additional version-15 artifact duels.

```sh
godot --headless --path game --script ../tools/expedition_artifact_ui_check.gd -- --report=/tmp/v15-artifact-ui.json
godot --headless --path game --script ../tools/expedition_opening_ui_check.gd
godot --headless --path game --script ../tools/expedition_power_ui_check.gd
godot --headless --path game --script ../tools/expedition_ui_check.gd
```
