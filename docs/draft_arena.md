# Draft Arena

Draft Arena is an offline mode available from the main menu when Etherlords II is mounted. It has a sixteen-pick draft, a deck-aware bot, resumable matches, and English and Russian menus. The draft uses original interface plates, power/toughness glyphs and trait icons, a generated amphitheater backdrop, and the same animated creature previews as Autochess. Hero choices use the same renderer for full-body previews.

## Player rules

| Setting | Behavior |
|---|---|
| Entry | Free; main menu → Draft Arena; Etherlords II must be mounted |
| Hero choice | Three distinct normal factions, selected from the four available factions |
| Draft | Sixteen picks; three distinct legal candidates at each pick; choose exactly one |
| Card pool | **Any faction** draws from all four factions and the curated neutral pool. **Hero’s faction only** gives each hero only cards from their own faction. The run's choice applies to the player and every opponent. |
| Copies | At most four copies of a card in the sixteen slots |
| Hero | Choose the level both sides play at, from 1–13. The default is 5. Explicit `{"PRVD": 0}`, no other skills, specialization, or artifacts |
| Spell charges | Ordinary EL2 Providence rules: two charges for each drafted slot |
| Resources | The faction pool uses tier 5. Any faction uses the cross-faction duel tier. The draft enforces four copies per card in both pools. |
| Deck changes | Locked after drafting; no reserve, rewards, upgrades, or between-match editing |
| Match start | Full hero health and fresh spell charges for both sides |
| Opponents | A newly drafted bot per encounter; all use strong drafting and combat policies |
| Run end | Twelve wins, three losses, or deliberate retirement |
| Draws | Recorded; consume neither a win nor a loss; continuing creates the next encounter |
| Persistence | One Arena slot, separate from normal duel/campaign saves |
| Seed | Optional integer from 0 to 2147483647; blank uses a random seed |

The same seed and the same player picks reproduce the same offers. Player choices affect copy eligibility and missing-role opportunities. Bot identity, faction, style, and draft seed depend on the run seed and encounter index, not on the player's faction or cards. The bot therefore does not draft a counter-deck after inspecting the player.

The three bot draft choices are generated through exactly the same code used for the player. There are no additional bot picks, rerolls, or post-draft replacements. Completed matches expose the opponent's deck and all sixteen offers/selections for inspection.

## Shared offer generation

Pure random offers can produce a spellbook without early creatures or any answer to persistent enchantments. Version 1 uses public role safeguards equally for player and bot:

1. One slot offers a creature when available. It prefers an early threat until the selected deck has four early threats.
2. Starting at pick 4, a missing interaction role receives an opportunity in a second slot.
3. Starting at pick 7, that slot prioritizes missing removal; from pick 9 it prioritizes a missing enchantment answer.
4. After three expensive cards, the creature slot prefers a card costing at most five.
5. Remaining slots sample the legal pool. Cards already selected four times are excluded, and all three candidates are distinct.
6. Candidate positions are shuffled deterministically, so the first displayed card is not a special slot.

These are opportunities, not compulsory picks. A player can still choose an unusual or risky deck. A role with no eligible cards falls back to other legal candidates.

In Any faction, cards of the same rarity have equal weight across factions. Rarity weights are 10 for Cantrip/Common, 7 for Rare, and 5 for Unique. The bot scores card effects and deck fit independently of rarity.

## Bot drafting

`ELArenaDraftBot.choose()` scores the marginal value of each offered card against the cards already selected. It reads the current three candidates and its own draft only.

The evaluator considers:

- Creature density and enough affordable threats to start playing early.
- Useful creature stats, evasion, regeneration, activated abilities, generators, and other printed traits.
- Removal, broader interaction, and answers to both creature and hero enchantments.
- Printed ether costs, additional sacrificed channels, ramp, and excessive expensive cards.
- Real tribe membership, tribal payoffs, and the creatures that a generator can produce.
- Whether sacrifice, cloning, or similar conditional cards have enough supporting bodies.
- Draw support, the five-card hand context, and diminishing returns from repeated permanent engines, healing, narrow answers, or ramp.

Balanced, aggressive, control, and synergy styles adjust priorities modestly. All retain the same composition safeguards and strong scoring; later wins do not enable a different legality rule or a deliberately weaker/stronger cheating tier. Seeded tie variation is bounded to ±0.16 so it cannot dominate a missing core role.

Creature/removal/dispel roles can overlap. A creature with an appropriate ability can contribute both a body and an enchantment answer. The drafter currently favors roughly twelve creature slots in the catalog fixture. This is an initial practical policy, not a claim that twelve is universally optimal.

### Combat AI policy

The duel view selects AI level 2 for an active Arena battle independently of the normal Options difficulty. Arena uses full-information combat search, including both hands and upcoming draws. A build without the native extension uses the existing GDScript fallback. The run and encounter IDs in the battle setup associate the checkpoint with its drafted spellbooks.

## Card curation

The pool first filters installed content using the actual game tables and existing combat rules. Disabled spells, support/internal rows, artifacts, adventure-only cards, unknown factions, and cards without implemented combat rules cannot appear. The four-copy ceiling is enforced while generating offers and independently when validating a completed deck.

Thirty explicit exclusions are in `ELArenaRules.EXCLUDED`, each with a readable reason:

| Package | Codes | Reason |
|---|---|---|
| Global/self locks | `STSI`, `SMOK`, `FLOD`, `BLKD` | Need a prepared lock, recovery, evasion, or alternative-win shell |
| Specialized engines | `CHNL`, `TRLB`, `COPL`, `GIFT` | Depend on tuned life, ether, noncreature, regeneration, or campaign plans |
| Aspect packages and narrow counters | `PRWT`, `PLSL`, `PLWP`, `PRBN`, `PRWR`, `ALNS`, `OCRP`, `BNSH`, `ORFT`, `OFLX`, `OMSW`, `OMWP`, `OEXC`, `GBNS`, `OST2`, `OST3` | Require particular Pale/bright aspects, triggers, boards, or opposing creatures |
| Symmetrical cost wardings | `LCWR`, `GCWR`, `LSWR`, `GSWR`, `LEWR`, `GEWR` | Tax both sides and need a deliberately asymmetric deck |

Ordinary tribal creatures, Mother Tick/Mother Bee, sacrifice, resurrection, ramp, and independently usable Pale creatures remain eligible. Curation should be changed from observed play, rather than by banning every synergy card.

Feature extraction uses the real `ELCatalog` effect and ability identifiers. For example, Sacrificial Cleansing (`ETTD`) counts as an enchantment answer; Blast (`OBLS`) does not count as unrestricted removal or a hero-enchantment answer; Cleave (`OCLV`) is valued for ordinary-creature bounce; Fetch (`FTCH`) includes its sacrificed channel.

## Source map

| File | Responsibility |
|---|---|
| `game/src/arena/rules.gd` | Rules constants, curation, derived card features, pool signatures, composition summaries, preset validation |
| `game/src/arena/draft.gd` | Shared seeded offers, exact pick history, replay validation, copy limits |
| `game/src/arena/draft_bot.gd` | Deck-aware marginal scoring and sixteen real bot selections |
| `game/src/arena/run.gd` | Run state, independent random streams, opponents, checkpoints, scoring, end conditions |
| `game/src/arena/screen.gd` | Landing, hero choice, draft, deck inspection, hub, results, transcripts, confirmations, save retry; EN/RU |
| `game/src/render/game_choice.gd` | Main-menu Draft Arena button |
| `game/src/render/front_menu.gd` | Signal forwarding and menu-row width fitting |
| `game/src/duel/view.gd` | Arena screen/battle hosting, autosave, resume, surrender, result routing, mode-transition guards, AI level |
| `tools/arena_lab.py` | Optional catalog-derived fixture for the Arena checks |
| `tools/arena_draft_check.gd` | Pool legality, exact transcript replay, human/bot parity, many-seed composition checks |
| `tools/arena_run_check.gd` | Lifecycle, save-failure injection, exact battle restore, result idempotency, run limits |
| `tools/arena_screen_check.gd` | Real screen layout/intents and optional graphical captures |
| `tools/arena_combat_check.gd` | Functional matches with real drafted decks, native AI, played checkpoints and result recording |

The run phases are `hero → draft → ready → battle → result → ready`. Twelve wins or three losses route the result to `finished`. Retirement also enters `finished`. The screen emits intent; the run controller owns validation and persistence.

## Save contract and failure behavior

The save is `user://arena-el2.json`, format `demiurges-draft-arena`, save version 1, with rules version 2 for Any faction and 3 for Hero’s faction only. Its size limit is 4 MiB. It contains:

- Run identity, seed, phase, hero choices, selected faction, and counters.
- The player's current offer, selected cards, and every previous three-card offer plus selection.
- Installed pool signatures for all four factions.
- Opponent identity, preset, sixteen-pick transcript, draft seed, battlefield, first side, and battle seed.
- A complete ordinary duel snapshot, including RNG and current hand/board/charges.
- Completed encounter IDs, results, cumulative records, and opponent transcripts.

`create()` initializes memory without writing, so the initial `persist()` can succeed before replacing the current saved run. Later mutators save transactionally by default. A failed write rolls the run back to its prior checkpoint. The live battle remains available in the host after a failed battle/result write; the Arena overlay blocks further play and offers Retry Saving.

Writes use the existing `ELSafeFile` temporary-write/verification/rename implementation. A recorded encounter cannot be scored a second time. A saved terminal battle is resolved on resume without creating a fresh opening or opponent. Surrender uses the ordinary duel's winner detection and counts as a loss. Retry/restart and ordinary quick-load do not replace an active Arena encounter.

Draft restore regenerates every offer, replays every selected index, and compares the deck and current offer. It rejects altered, missing, or malformed picks and changed pools without replacing the receiving draft. Pool caches include profile identity and mount generation.

The save stores both hero levels and the selected card pool. Checkpoints made before the level selectors load both heroes at level 5. Earlier version 1 checkpoints keep their original faction-plus-neutral pool and offer weights. A future change to curation, offer generation, or draft interpretation needs a new rules version to preserve transcript validation. Changes to the save structure use `ELArenaRun.SAVE_VERSION`.

## Verification and reproduction

### Installed-game checks

From the repository root, using its supported Godot 4.7 runtime and your Etherlords II installation:

```sh
godot --headless --editor --path game --import
godot --headless --path game --script ../tools/arena_draft_check.gd -- --el2=/path/to/Etherlords2 --drafts=2048
godot --headless --path game --script ../tools/arena_run_check.gd -- --el2=/path/to/Etherlords2
godot --headless --path game --script ../tools/arena_combat_check.gd -- --el2=/path/to/Etherlords2 --games=4 --think-ms=200
godot --path game --script ../tools/arena_screen_check.gd -- --el2=/path/to/Etherlords2 --capture=/tmp/arena-captures
```

Use shell quoting when the installation path contains spaces. Pass `--pool=faction` to the combat check to play faction-only decks. Tests use in-memory runs or a dedicated test save; they do not replace `arena-el2.json`.

### Checks without an original installation

Run the same scripts with the imported game project. Omit `--el2` to use the small synthetic profile, or generate a larger catalog-derived fixture.

```sh
python3 tools/arena_lab.py --workspace /tmp/demiurges-arena-lab
godot --headless --path game --script ../tools/arena_draft_check.gd -- --fixture=/tmp/demiurges-arena-lab/fixture.json --drafts=2048
```

The catalog fixture contains synthetic hero health and income. Use the installed-game checks for asset coverage and real battle setup. Set `DEMIURGES_LANGUAGE=ru` or `en` to test Arena captions. Card names and descriptions come from the installed game's language. At short window heights, the draft uses scrollable rules text within each card so the three choices remain available together.
