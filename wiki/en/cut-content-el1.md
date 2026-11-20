---
title: Cut content of Etherlords
category: story
order: 90
summary: Buildings, creatures, cards, missions and heroes left unused in the first game's files
---
Etherlords shipped with more than it uses. Its archives keep the models, textures, tables and texts of features that were removed before release or never finished. Nothing on this page appears in a normal game. The pictures are rendered by Demiurges from the original files. A few models have no texture of their own; they are shown in plain white, or with the texture whose name matches theirs, as the captions say.

The evidence for each item is that no table, map, campaign or text of the game refers to it, or that the program never reads it. Where only the names suggest what something was, the text says "probably". The names in quotes are the Russian edition's, translated; Etherlords II's English texts give some of them.

See also [Cut content of Etherlords II](cut-content-el2).

## The gold economy

Early in development the castle had a town around it. The table of building statistics still lists the income and upkeep of a **Bank** (2,500, 6,000 and 12,000 gold at its three levels), a **Mana Collector**, a **Factory** that made production points and a **Laboratory** that made research points, and a castle income of 1,000 gold a turn. The program still recognises all four building types and the fields for their build cost and build time, but the shipped game has no gold, and its building table only has castles and forts.

The four buildings survive as complete models, each in three levels with idle animations, a scaffold and a building site, and their textures are still in the archive. Heroes still have a hire cost of 1,000 to 1,200 gold, the hero screen keeps a **Hire hero** button that does nothing, and the console still has a `set money` command. A set of interface voices named after the same screens (bank, factories, mana collectors, research labs, "hire new hero") ships unused.

!objects el1/Model/tebumaba3@TerrainObjects/Alpha/bank00@TerrainObjects/Alpha/bank01 = Bank, level 3 | el1/Model/tebumafa1@TerrainObjects/factory00@TerrainObjects/factory01 = Factory, level 1 | el1/Model/tebumala1@TerrainObjects/laboratory00@TerrainObjects/laboratory01 = Laboratory, level 1 | el1/Model/tebumama3@TerrainObjects/manacollector00@TerrainObjects/manacollector01 = Mana Collector, level 3 | el1/Buildings/a10 = Fort scaffold | el1/Buildings/a9 = Fort building site

- Forts kept their construction stages: rows of the building table for a scaffold and a building site still point to those models, but a fort is upgraded at once in the shipped game.
- Two more tables belong to the same design and are never read. **Rituals** lists ten strategic spells paid for with production points, research points and gold (Health, Workers, Swamp, Haste, Eagle Sight, Summon Money, Dispel, Mana Stream, Mana Drain, Scientists). **ResearchTree** is a laboratory tree of 74 nodes that unlocks spells. It has nodes for the Chaots, Synthets and Vitals only, none for the Kinets, so it was abandoned before it was finished.

## Shrines and other map sites

Models and textures of map sites that no map places:

!objects el1/Model/tebuad5@TerrainObjects/shrinecrafting_knowledge00 = Shrine of Knowledge | el1/Model/tebuad7@TerrainObjects/shrineprosperity00 = Shrine of Prosperity | el1/Model/tebuad16@none = Probably a ship (no texture)

- Textures with no model or table: a **Spring of Mind** (next to the shipped springs of strength and dexterity), a **Teleport** with its effect frames, and a **Tunnel**.
- Smaller leftovers: a second lake and an alternative dungeon model, terrain pieces no table names, nine arena props no battlefield uses, and a resource pile of Mandrake Root and Emerald that no map places.
- The [Gnome Tinkerer](map-objects) says that the hero's artifacts were recharged, but recharges nothing; Demiurges keeps this as it is.

## Unused creatures and figures

- **Basic Maggot** (`BSMG`) is a switched-off black creature: 0/1, flying, with the Maggot's model. Its card has no name or description, and it is only in two test decks.
- **cr213** is a complete creature with no table, texture or name, probably of the Chaots, whose models are numbered like it: a long body with six forelimbs, eight legs, a five-part tail and a full set of combat animations (idle, walk, run, attack, hit, death). It sits in the gap between the Rat and the Orc Shaman in the model numbering.
- **cr601** is a cone with three stub animations, a placeholder.

!objects el1/CombatCreatures/BSMG = Basic Maggot | el1/Model/cr213@none = cr213 (no texture) | el1/Model/cr601@none = Placeholder cone

Five creatures have adventure-map figures and small map textures, but no map monster uses them:

!objects el1/Model/ad106@Creatures/smblackmaggot00 = Maggot | el1/Model/ad307@Creatures/smgreenmantis00@Creatures/smgreenmantisadd00 = Mantis | el1/Model/ad314@Creatures/smgreenbeholder00 = Beholder | el1/Model/ad501@Creatures/smknight00 = Konung | el1/Model/ad502@Creatures/smhunter00 = Huntress

## Switched-off cards

Five cards are switched off in the card table and have no name or description text. The program still has working code for each of them:

| Card | Kind | What the code does | Where it is mentioned |
|---|---|---|---|
| Basic Maggot (`BSMG`) | Black creature, 1 ether | A 0/1 flying maggot | Two test decks |
| Ether Flash (`MNFL`) | Green sorcery, 1 ether | Pay X channels: your creatures get +X/+X until the end of the opponent's turn | The research tree |
| Reset (`RSET`) | Black sorcery, 2 ether | Both heroes discard their hands and draw as many spells | The research tree |
| Somnolent Gas (`SMGS`) | Black enchantment, 5 ether | Enemy creatures cannot attack until it is dispelled | The research tree |
| Gift (`GIFT`) | Blue sorcery, 1 ether | Your creature goes over to the opponent, and back when dispelled | Nowhere |

!objects el1/Icon/MNFL = Ether Flash | el1/Icon/RSET = Reset | el1/Icon/SMGS = Somnolent Gas | el1/Icon/GIFT = Gift

Etherlords II brought Gift back as a card of the Pale: see [Gift](card-gift).

Twenty-three global spells can be bought and cast but do nothing. Seventeen of them (among them Automatic Repair, Chaos Shield, Ice Shield, Rot, Erosion, Retribution and Blessing of the Forest) charge their daily upkeep, but nothing in the game reads them. Six (Final Discharge, Spell Destruction, Disenchant, Visions, Ether Leak and Spell Strike) are used up without effect. The hero skills [Ethereal Attack](skill-etat) and [Ethereal Defense](skill-etdf) are offered on level-up, but castle damage never changes.

## Missions that never shipped

The texts of ten missions are in the game, but their maps are not. Each has a page of its own with its texts, heroes and decks:

- [Evil Dale](cut-mission-evil-dale) (`bmission01`, «Проклятые руины» in Russian): a bonus mission for a lone Vital, "the Chosen One", with five rival heroes and a win condition written into the program.
- [Snowflake Maze](cut-mission-snowflake-maze): a tournament of the Kinets, probably a New Year 2002 map, with heroes named Santa Claus and Father Frost.
- [Three Lakes Valley](cut-mission-three-lakes-valley): the Vitals defend a valley against the Chaots.
- Six scenarios of an "S" series, named only in the English edition: [Savage Desert](cut-mission-savage-desert), [Balance of Terror](cut-mission-balance-of-terror), [First Strike](cut-mission-first-strike), [Ice Trap](cut-mission-ice-trap), [Dragon Lake](cut-mission-dragon-lake) and [Synthets Menace](cut-mission-synthets-menace).

A start text for a game "as the Vitals against the Synthets and the Kinets" is not used by any map either. Six Duel presets were cut: their decks (Bee Swarm, Beholders' Wrath, Ticks Assault, Gibberling Rush, Mind Blast and No Fight) and preset names such as "Deadly Hive" and "Mind Annihilator" are still in the files. Eight more presets were for the demo only.

## Test heroes

The hero table has about forty heroes that appear on no map: `TestHero1` to `TestHero7`, red, blue and black test heroes, a level 20 test hero, a test White Lord, a test Konung of Fire, a copy of Diamanda made for screenshots, and named characters with no mission, from Eleanor and Dominicius to the Synthets Delta-300B, Gamma-100D and Beta-700E. Two carry the names of bosses from another game, Lord Nagafen and Lady Vox.

!objects el1/HeroTemplates/TestHero1 = TestHero1 | el1/HeroTemplates/JohnTestWhiteLord = A test White Lord

## Texts, sounds and tables

- The English edition has texts the Russian one lacks, for objects and rules that do not exist: a **Dock** ("Your hero has loaded on a ship"), a **Teleport**, a **Tunnel** ("a dwelling of weak creatures"), a **Sign** and a **Stone Sign**, a hero skill **Pathfinding** whose three ranks are described as "UNUSED", and a creature ability **Dust** ("All creatures can not attack until their next turn"). Its interface still carries the build date, "build 07.10.2001".
- Besides the economy voices, a few button and building sounds are never played, `loading.mp3` is never named, and the introduction movie `firstlogo.bik` is asked for at start-up but is not on the disc.
- A third table, **HeroFaces**, repeats the faces, models and voices of the hero table, probably for an editor, and is never read.

## What Demiurges does with it

Demiurges plays the shipped game: cut cards, demo presets and unplaced heroes stay out of play, and the inert global spells, skills and the Gnome Tinkerer stay as inert as in the original. Sea travel and random maps in Demiurges are new features; they use the boat of Etherlords II, not the cut ship above.
