---
title: Cut content of Etherlords II
category: story
order: 91
summary: Pale cards, buildings, heroes, scripts and sounds left unused in the second game's files
---
Etherlords II was built on the first game, and its archives keep both its own unfinished content and much of Etherlords that the sequel no longer uses. Nothing on this page appears in a normal game. The pictures are rendered by Demiurges from the original files; models with no texture of their own are shown in plain white.

The evidence for each item is that no table, map, script, campaign or text of the game refers to it, or that the program never reads it. Where only the names suggest what something was, the text says "probably". The card names are those of the English texts in the game's tables.

See also [Cut content of Etherlords](cut-content-el1).

## Cards of the Pale

Six White cards of the Pale are switched off in the card table. None of them has code behind it, and their descriptions say why:

| Card | Description in the files |
|---|---|
| Alien Lace (`ALLC`) | When the enchanted creature deals combat damage to a creature, that creature goes to the outer plane |
| Counter Spell (`CNSP`) | When the enemy hero casts a spell costing X ether, spend 2X ether to cancel it; the enemy hero gains X ether |
| Call to Outside (`COUT`) | "Non functional yet" |
| Outer Swap (`OSWP`) | "[SPELL OBSOLETE]" |
| Presence of Outside (`POUT`) | "[SPELL OBSOLETE]" |
| Spell Block (`SPBL`) | Cancels a spell being cast; the enchantment is lost and the enemy hero gains X life |

None of them got artwork: four have no icon at all, and Outer Swap and Presence of Outside point at empty cells of the icon sheet.

More cards are left over from the first game:

- The four cards already switched off in Etherlords (Ether Flash, Reset, Somnolent Gas and Basic Maggot) are still there, switched off. Basic Maggot's English description is the single word "Unused", and Somnolent Gas still has a developer's placeholder for its Russian name, "!!!Brick in the wall".

!objects el2/CombatCreatures/BSMG = Basic Maggot

## Skills and specializations

- Six hero skills of Etherlords are still in the skill table but marked as not in use: Estates, Bargain, Ethereal Attack, Ethereal Defense, Mobility and Looting. Their texts are still the first game's.
- The specialization **Outside mastery** has only that name, for both its name and its description, no icon and no effect.

## Buildings and map objects

Etherlords II never places a **Teacher**, a **Master** or a **Magister**. Their models and textures were made new for the sequel, and they have rows in the object table, but no map uses them. The sequel also drops the springs, the gnomes' shops and the wagons of Etherlords: the program still knows these buildings, and their English texts and two spring sounds still ship, but they have no table rows and their old models have lost their textures.

!objects el2/TerrObj/Teacher00 = Teacher | el2/TerrObj/Master00 = Master | el2/TerrObj/Magister00 = Magister

Single variants that no map places, although the other colours of the same building are used: a green tunnel, a red warding stone, and a **Scroll** whose text is only "Contains some description".

!objects el2/AdditionalBuildings/TunnelGreen = Green tunnel | el2/AdditionalBuildings/WardingStoneRed = Red warding stone | el2/AdditionalBuildings/Scroll = Scroll

- The **White castle** of Etherlords, with its lava moat, still ships with its texture, but the White Lord's castle in Etherlords II uses the blue castle model.
- The castles' three upgrade levels of the first game are still there as models, without textures.
- The first game's ether nodes are still in the tables, unplaced; the sequel's power nodes reuse their models.
- The bank, factory, laboratory and mana collector of the first game's [gold economy](cut-content-el1) are still in the model archive, as are the Rituals and ResearchTree tables.
- Several ships, docks, gates, towers and walls are in the archives with no table that names them, among them a ship model and a gnome figure with no building. A ship row of the object table is not placed either.

!objects el2/Model/tebuca5@TerrainObjects/whitecastle00 = White castle | el2/Model/tebuad551@TerrainObjects/Alpha/Boat01 = Unused ship | el2/TerrObj/Ship_01 = Unplaced ship row | el2/Model/telamise620@none = A gnome (no texture)

## Heroes and figures

The maps of Etherlords II describe each hero in the map itself, so the campaign does not use the hero table's 346 rows. Duel does: four rows are its default heroes, and its choice of face offers every hero of a colour that is not marked as a quest hero, so many rows still appear there. Most rows are copies from Etherlords, its test heroes and the New Year 2002 heroes included. Forty-six exist only in Etherlords II and look like the plan of an earlier campaign: heroes for missions 12 to 14 such as Aelan the green traitor, Ralin, Ermelaus, Juna, the Synthet Delta-220C "Mistress" and a level 12 Green Dragon, the main heroes of each race at three stages, and a Diamanda for each colour.

!objects el2/HeroTemplates/A6M14GreeDragon = Green Dragon | el2/HeroTemplates/A6M12GreenBetrayer = Aelan | el2/HeroTemplates/A6M13Suicider = Delta-220C "Mistress" | el2/HeroTemplates/MainHeroRed1 = Red main hero | el2/HeroTemplates/MainHeroBlack2 = Black main hero | el2/HeroTemplates/Diamanda1Blue = Blue Diamanda

- Four map figures are never placed: the Wall of Burning Rock, the Wall of Blades, a night wolf and the Basic Maggot.
- **cr500**, a winged flier with a tail and two animations, is in both games and used by neither; no texture for it is known. Two map models of the same shape are unused too.
- A crossbow-carrying map figure is probably the Huntress, who has no map figure in the game.
- Six pieces of a shell (top, mask, chest, bottom, left and right) are probably armour breaking off one of the Lords.

!objects el2/Model/cr500@none = cr500 (no texture) | el2/Model/ad502@Creatures/Alpha/Hunter00 = Huntress figure, with her battle skin

## Scripts and tables

- `ArtifactTracker.scp_old` is an older copy of the artifact recipe script, never loaded. It has the artifact names written in English instead of text keys, and the icons of the two Rods of Mechoses swapped.
- `a6lib.scp` is an empty script; "A6" is the sequel's working name inside the files, as in the names of its credits and campaign screens.
- Many tables of Etherlords ship unchanged and unused: the global spells (the sequel has none), the combat events (the program always picks none), Rituals and ResearchTree.
- The battle scripts can react to five events that no shipped script uses, and branches of several scripts for summoned creatures can never run, because the game never reports a spell as a summoning.

## Debug features, texts and sounds

- Mission 13's script has a debug key, Ctrl+Shift+E, that writes the state of its dialogs to the screen.
- The Hall of Fame opens but never receives a record: nothing in the program adds one.
- The first game's credits screen and diplomacy texts (truces, shared vision, shared shops) are still in the files, and the map editor's 45 preview pictures ship without a map editor.
- The texts of every mission of Etherlords, the cut ones included, are still in the sequel's text archive. Its English edition also holds the draft of a campaign that never shipped: [Intrusion](cut-campaign-intrusion), a Vitals campaign of two placeholder missions with the plan of its opening story.
- Two complete creature sound sets, OutFighter1 and OutFighter2 (attacks, hits, deaths and footsteps on snow, sand and grass), are never used; the Pale fighters use other creatures' sounds. Some building sounds are never played. Every music track and movie is used.

## What Demiurges does with it

Demiurges plays the shipped game, and the switched-off cards stay out of play. Unlike the original, Demiurges fills the Hall of Fame with campaign and [duel](duel) results (see [Etherlords II campaigns](campaign-el2)).
