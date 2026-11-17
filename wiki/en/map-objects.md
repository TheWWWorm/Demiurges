---
title: Map objects
category: rules
order: 65
summary: What every building, mine, shop and pickup on the map gives a hero
---
The objects on the [adventure map](adventure-map) that a hero can use, with the numbers from the games' own tables. The names are those of the English and Russian editions.

In Etherlords a hero uses an object from a tile next to it: order the hero to it during the day and the visit happens at night. Visiting costs nothing but the walk. Only the owner of the visiting hero sees the building's message. A "week" is seven days, counted from the start of the mission.

## Resources and ether (Etherlords)

**Mines** are captured by a hero who visits them and then pay their owner every turn. Another player takes a mine the same way. The owner can upgrade a mine twice; the upgrade costs are the same for every player.

| Mine | Pays per turn (level 1 / 2 / 3) | First upgrade | Second upgrade |
|---|---|---|---|
| Mandrake Garden | 10 / 12 / 15 Mandrake Root | 30 Root, 5 Ruby, 5 Diamond, 3 Frozen Flames | 60 Root, 5 Emerald, 5 Sapphire, 5 Frozen Flames |
| Lotus Garden | 10 / 12 / 15 Black Lotus | 25 Root, 7 Emerald, 7 Sapphire, 2 Frozen Flames | 50 Root, 7 Ruby, 7 Diamond, 4 Frozen Flames |
| Ruby Mine | 6 / 8 / 10 Bloody Ruby | 20 Root, 20 Lotus, 20 Ruby, 5 Frozen Flames | 40 Ruby, 15 Emerald, 15 Diamond, 10 Frozen Flames |
| Emerald Mine | 6 / 8 / 10 Poison Emerald | 20 Root, 20 Lotus, 20 Emerald, 5 Frozen Flames | 40 Emerald, 15 Ruby, 15 Sapphire, 10 Frozen Flames |
| Sapphire Mine | 6 / 8 / 10 Star Sapphire | 20 Root, 20 Lotus, 20 Sapphire, 5 Frozen Flames | 40 Sapphire, 15 Emerald, 15 Diamond, 10 Frozen Flames |
| Diamond Mine | 6 / 8 / 10 Smoke Diamond | 20 Root, 20 Lotus, 20 Diamond, 5 Frozen Flames | 40 Diamond, 15 Ruby, 15 Sapphire, 10 Frozen Flames |
| Fire Glacier | 2 / 3 / 4 Frozen Flames | 25 each of Ruby, Emerald, Sapphire and Diamond | 50 each of Ruby, Emerald, Sapphire and Diamond |

!objects el1/ResourceMine/RTM@0 = Mandrake Garden | el1/ResourceMine/LTM@0 = Lotus Garden | el1/ResourceMine/RM-Red@0 = Ruby Mine | el1/ResourceMine/EM-Green@0 = Emerald Mine | el1/ResourceMine/SM-Blue@0 = Sapphire Mine | el1/ResourceMine/DM-Black@0 = Diamond Mine | el1/ResourceMine/FFM@0 = Fire Glacier

**Ether nodes** (Red, Green, Blue and Black Ether node) are captured the same way. A node gives its owner 30 ether per turn when it has the owner's colour and 15 when it has another colour. They cannot be upgraded. Ether pays the upkeep of heroes and the global spells.

!objects el1/ManaNodes/ManaNode.Red = Red Ether node | el1/ManaNodes/ManaNode.Green = Green Ether node | el1/ManaNodes/ManaNode.Blue = Blue Ether node | el1/ManaNodes/ManaNode.Black = Black Ether node

**Resource piles** of one resource lie on the map. A hero who takes one gets the whole pile once and the pile is gone. Each map sets the amount of every pile.

!objects el1/ResourceCut/BigRoot = Mandrake Root | el1/ResourceCut/BigLotus = Black Lotus | el1/ResourceCut/BigRuby = Bloody Ruby | el1/ResourceCut/BigFFlame = Frozen Flames

## Shops (Etherlords)

Shops come in three kinds and three ranks. A hero who opens a shop captures it for his player. The owner can upgrade it twice; the cost depends on the owner's colour, and "your gem" below is the gem of that colour: Ruby for red, Emerald for green, Sapphire for blue and Diamond for black.

| Shop | Sells | First upgrade | Second upgrade |
|---|---|---|---|
| Apprentice's Lab | Common sorceries and enchantments | 15 Root, 40 Lotus, 3 of your gem, 2 Frozen Flames | 15 of your gem, 10 + 10 other gems, 6 Frozen Flames |
| Sorcerer's Lab | Rare sorceries and enchantments | 25 Root, 50 Lotus, 6 of your gem, 4 Frozen Flames | 20 of your gem, 15 + 15 other gems, 9 Frozen Flames |
| Wizard's Lab | Unique sorceries and enchantments | 35 Root, 70 Lotus, 9 of your gem, 6 Frozen Flames | 30 of your gem, 25 + 25 other gems, 15 Frozen Flames |
| Summoner's Hut | Common creatures | 30 Root, 10 Lotus, 5 of your gem, 1 Frozen Flames | 20 of your gem, 10 + 10 other gems, 5 Frozen Flames |
| Summoner's Tower | Rare creatures | 40 Root, 20 Lotus, 7 of your gem, 3 Frozen Flames | 25 of your gem, 15 + 15 other gems, 8 Frozen Flames |
| Summoner's Guild | Unique creatures | 60 Root, 30 Lotus, 10 of your gem, 5 Frozen Flames | 40 of your gem, 25 + 25 other gems, 12 Frozen Flames |
| Stone Portal | Runes, cheapest for common spells | 25 Root, 25 Lotus, 5 of your gem, 3 Frozen Flames | 30 of your gem, 10 + 10 other gems, 5 Frozen Flames |
| Granite Portal | Runes, cheapest for rare spells | 30 Root, 30 Lotus, 10 of your gem, 5 Frozen Flames | 40 of your gem, 15 + 15 other gems, 10 Frozen Flames |
| Obsidian Portal | Runes, cheapest for unique spells | 50 Root, 50 Lotus, 15 of your gem, 10 Frozen Flames | 50 of your gem, 25 + 25 other gems, 15 Frozen Flames |

!objects el1/NewBuildings/CommonLab@0 = Apprentice's Lab | el1/NewBuildings/RareLab@0 = Sorcerer's Lab | el1/NewBuildings/UniqueLab@0 = Wizard's Lab | el1/NewBuildings/CommonZoo@0 = Summoner's Hut | el1/NewBuildings/RareZoo@0 = Summoner's Tower | el1/NewBuildings/UniqueZoo@0 = Summoner's Guild | el1/NewBuildings/CommonPortal@0 = Stone Portal | el1/NewBuildings/RarePortal@0 = Granite Portal | el1/NewBuildings/UniquePortal@0 = Obsidian Portal

- **Labs and summoner's buildings** sell only spells of the hero's colour, from the list the map gives the shop. That list has three tiers: an unupgraded shop sells the first, each upgrade adds the next. A bought spell takes a place in the spell book. The price is the spell's cost; for every copy of that spell already in the book it rises: ×2 for the second copy, ×3, ×5, ×10, ×20 and so on.
- **Portals** sell runes for the spells in the hero's book (cantrips need none). A rune costs the spell's rune price times a factor: in a Stone Portal ×1 for common, ×5 for rare and ×25 for unique spells; in a Granite Portal ×2, ×1 and ×5; in an Obsidian Portal ×4, ×2 and ×1. An upgraded portal sells 15% cheaper, and 40% cheaper after the second upgrade.
- The **Bargain** skill lowers both kinds of prices. See [Heroes and levels](heroes) and [Runes and artifacts](runes-artifacts).
- In a portal, **Buy one each** adds one rune to every spellbook copy that can hold another. **Return one each** withdraws one pending rune from each copy. Cantrips and full copies are skipped; owned runes are kept. The purchase is paid only when you accept it. Affordable shop prices are green, unaffordable prices red; hover a resource icon to see its name.

## Learning and strength (Etherlords)

| Object | What a visit gives | How often |
|---|---|---|
| Teacher | Half of the total experience the next level needs (table below) | Once per hero |
| Mentor | 100 experience | Once per hero |
| Master | Learns a skill or raises it one rank: the skill the map sets, otherwise a random one. A skill already at its highest rank is not raised, and a hero with five skills learns no sixth | Once per hero, even when nothing was learnt |
| Training Camp | The hero leaves the map and gains 50 experience every day until he is ordered out; he then returns to the tile he entered from. One hero at a time | While he stays |
| Spring of Life | Health +¼ of the hero's health, until the end of the week | Once per hero per week |
| Spring of Movement | Movement and sight +¼ of the hero's movement, until the end of the week | Once per hero per week |

!objects el1/AdditionalBuildings/Teacher = Teacher | el1/AdditionalBuildings/Magister = Mentor | el1/AdditionalBuildings/Master = Master | el1/AdditionalBuildings/TrainingCamp = Training Camp | el1/AdditionalBuildings/SpringOfStrength = Spring of Life | el1/AdditionalBuildings/SpringOfDexterity = Spring of Movement

The amounts of the Teacher and the Mentor are before the **Learning** skill, which adds 25, 50 or 100% to them. Experience stops at level 20.

| Hero's level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Teacher gives | 25 | 50 | 125 | 250 | 500 | 1250 | 2500 | 5000 | 15000 | 37500 |

| Hero's level | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 |
|---|---|---|---|---|---|---|---|---|---|
| Teacher gives | 62500 | 125000 | 250000 | 500000 | 1000000 | 1500000 | 2000000 | 2500000 | 3000000 |

## Buildings to hold (Etherlords)

These are captured by a visit and help their owner while he holds them. Any other player takes them by visiting.

| Building | Effect while held |
|---|---|
| Altar | Ether income +25% for each Altar (of the income from nodes and the castle, rounded down) |
| Healer's Citadel | Health of all your heroes +10% for each citadel |
| Wanderer's Citadel | Movement and sight of all your heroes +10% for each citadel |

A **Fort** holds one hero. The hero who enters captures it and guards the area within three tiles: an enemy who walks into it is stopped for a battle. The owner can upgrade a fort twice: 25 Ruby, 25 Diamond and 10 Frozen Flames, then 25 Emerald, 40 Sapphire and 15 Frozen Flames. In an upgraded fort the hero in it fights with a fully charged [Rod of Defense](card-rddf); in a fully upgraded fort the hero's level in battle is also one higher. Many maps place their forts already upgraded.

!objects el1/AdditionalBuildings/ShrineMagic = Altar | el1/AdditionalBuildings/HealersCitadel = Healer's Citadel | el1/AdditionalBuildings/WanderersCitadel = Wanderer's Citadel | el1/Buildings/Fortress.0.Red = Fort

## Gnomes and wagons (Etherlords)

| Object | What a visit gives | How often |
|---|---|---|
| Trader's Wagon | Three random resources, 6 to 36 of each (6 × 1 to 6); the same resource can come twice | Once; the wagon leaves the map |
| Magician's Wagon | 3 runes for every spell in the hero's book (not cantrips) | Once; the wagon leaves the map |
| Gnome-Merchant | One random resource, 6 to 36 | Once a week, for the first visitor of any player |
| Gnome-Alchemist | 1 rune for every spell in the hero's book (not cantrips) | Once a week, for the first visitor of any player |
| Gnome-Artificer | Shows its message that artifacts are recharged, but changes no artifact, as in the original game | Once a week, for the first visitor of any player |

!objects el1/AdditionalBuildings/TraderWagon = Trader's Wagon | el1/AdditionalBuildings/MageWagon = Magician's Wagon | el1/AdditionalBuildings/GnomeMerchant = Gnome-Merchant | el1/AdditionalBuildings/GnomeAlchemist = Gnome-Alchemist | el1/AdditionalBuildings/GnomeTinkerer = Gnome-Artificer

Artifacts carried by a hero of Etherlords start every battle fully charged anyway.

## Lairs and guards (Etherlords)

| Lair | Holds |
|---|---|
| Dungeon | One creature of level 2 to 4 |
| Labyrinth | One creature of level 5 to 7 |
| Crypt | One creature of level 8 to 10 |

!objects el1/AdditionalBuildings/Dungeon1 = Dungeon | el1/AdditionalBuildings/Dungeon2 = Labyrinth | el1/AdditionalBuildings/Dungeon3 = Crypt

A hero who enters a lair fights the creature inside. Each week an empty lair gets a new creature, drawn at random from all neutral creatures of its levels at the chosen difficulty. Neutral creatures standing on the map guard the area within two tiles: a hero who walks into it is stopped for a battle.

## Finds, keys and story objects (Etherlords)

- **Artifacts** lying on the map are taken by a visit and belong to that hero. See [Runes and artifacts](runes-artifacts).
- A **Global spell** scroll lets its finder's player cast a global spell from the castle: the first spell on the scroll that is colourless or of the player's colour. A **Global spell part** offers Clock of the Apocalypse, Terminal Discharge, Ether Calm and Ether Leak, one for each colour; three parts held by the same hero complete the spell of the player's colour; parts held by different heroes never do. Scrolls stay with the hero and are lost with him.
- A **Prison** frees the hero inside, who joins the visitor's player on the cage's tile. Once.
- A **Warding Stone** gives the visiting hero its key and leaves the map; if the hero falls, the stone returns. A **Rune Stone** or **Greater Rune Stone** opens for a hero carrying its key; some keys open and close it again.
- An **Observation Point** shows its visitor's player the land around every **Observation Device** that belongs to it. It can be used again and again.
- The **Altars of War** of the Wild Wasteland can be destroyed by a visit, once each; every one destroyed makes the Fire Konung one step weaker (IV, III, II, I).
- The **Town Center** of the Lost City gives the key to the Temple of Time and wins the chapter. In the chapters of the **Temple of Time**, rocks bar the way to it until the rival's castle is destroyed, and a hero who reaches the temple wins.

!objects el1/Artefacts/RodOfFire = Artifact (rod) | el1/Artefacts/RingOfHealing = Artifact (ring) | el1/Artefacts/EtherAmulet = Artifact (amulet) | el1/Artefacts/ScrollOfBless = Artifact (scroll) | el1/GlobalSpellCut/FullSpell = Global spell | el1/GlobalSpellCut/PartSpell = Global spell part | el1/AdditionalBuildings/Prison = Prison | el1/AdditionalBuildings/WardingStone = Warding Stone | el1/AdditionalBuildings/Runestone1 = Rune Stone | el1/AdditionalBuildings/Runestone2 = Greater Rune Stone | el1/AdditionalBuildings/Lake = Observation Point | el1/AdditionalBuildings/ReflectingBowl = Observation Device | el1/AdditionalBuildings/AltarOfWar = Altar of War | el1/AdditionalBuildings/TownBunker = Town Center | el1/AdditionalBuildings/WhiteCastle = Temple of Time

## Etherlords II

In Etherlords II using a building takes 2 of the hero's travel points for the day (a hero has 8); reading a sign is free. Most effects are given only to the hero who used the building.

| Object | What it does |
|---|---|
| Mandrake Garden, Ruby Mine, Fire Glacier | Captured by a visit; pays its owner every day for ten days and is then exhausted. The map sets the total |
| Resource piles | Taken once: usually 10, 20 or 40 Plants, 3, 6 or 12 Stones, or 2, 4 or 8 Frozen Flames, by size |
| Labs and summoner's buildings | The six shops of the first game's names, where heroes buy and sell spells. See [About spells](spells) |
| Fort | Holds one hero or creature. A garrison of an upgraded fort fights with a fully charged Rod of Defense; in a fully upgraded fort its specialisation level is one higher. Forts cannot be upgraded in Etherlords II |
| Beacon | For heroes of its colour: doubles the distance a hero can sail each day for 10 days (at most 16 points). A new beacon replaces the earlier one |
| Ether Node of Synthesis, Ordering, Life or Chaos | Restores all the experience a hero lost in the Pale lands, for a hero of a player of the node's colour |
| Shrine of Knowledge | Gives the specialisation the map sets. Once per mission for all heroes; the use is spent even if the hero already had it |
| Prison | Frees the prisoner, once; the cage leaves the map |
| Sign, Stone Sign | Show their text |
| Magic Font | Shows the land around the Ocularis Orbs that belong to it. Can be used again |
| Rune Stone, Warding Stone | As in Etherlords: the stone gives a key, the barrier opens for its holder |
| Artifact Recharger | Recharges all the hero's artifacts; needs at least one artifact, and has no waiting time |
| Artifact Recipe | Shows how to make an artifact |
| Jetty | Takes the hero on board a ship or puts him ashore |
| Teleporter | Moves the hero to a linked receiver (one at random if there are several) |
| Tunnel | Moves the hero to another mouth of the same tunnel. A creature may wait inside; it must be beaten first, and the victory clears every mouth of that tunnel |
| Corpse | Searched by the main hero; what it holds depends on the chapter |

!objects el2/ResourceMine/Mine.Root.Green = Mandrake Garden | el2/ResourceMine/Mine.Ruby.Red = Ruby Mine | el2/ResourceMine/Mine.FF = Fire Glacier | el2/ResourceCut/Res.Root.3 = Plants | el2/ResourceCut/Res.Ruby.3 = Stones | el2/ResourceCut/Res.FF.3 = Frozen Flames | el2/NewBuildings/CommonLab@0 = Apprentice's Lab | el2/NewBuildings/RareLab@0 = Sorcerer's Lab | el2/NewBuildings/UniqueLab@0 = Wizard's Lab | el2/NewBuildings/CommonZoo@0 = Summoner's Hut | el2/NewBuildings/RareZoo@0 = Summoner's Tower | el2/NewBuildings/UniqueZoo@0 = Summoner's Guild | el2/Buildings/Fortress.0.Blue = Fort | el2/AdditionalBuildings/BeaconBlue = Beacon

!objects el2/AdditionalBuildings/PowerNodeBlack = Ether Node of Synthesis | el2/AdditionalBuildings/PowerNodeBlue = Ether Node of Ordering | el2/AdditionalBuildings/PowerNodeGreen = Ether Node of Life | el2/AdditionalBuildings/PowerNodeRed = Ether Node of Chaos | el2/AdditionalBuildings/Specialization = Shrine of Knowledge | el2/AdditionalBuildings/Prison = Prison | el2/AdditionalBuildings/Sign = Sign | el2/AdditionalBuildings/StoneSign = Stone Sign | el2/AdditionalBuildings/Lake = Magic Font | el2/AdditionalBuildings/ReflectingEye = Ocularis Orb | el2/AdditionalBuildings/Runestone1Green = Rune Stone | el2/AdditionalBuildings/WardingStoneGreen = Warding Stone | el2/AdditionalBuildings/ArtefactRecharger = Artifact Recharger | el2/AdditionalBuildings/ArtefactRecipe = Artifact Recipe | el2/AdditionalBuildings/Dock = Jetty | el2/AdditionalBuildings/Teleport = Teleporter | el2/AdditionalBuildings/TeleportReceiver = Teleport receiver | el2/AdditionalBuildings/TunnelGreen = Tunnel

**Battleground buildings** change battles. There are three kinds:

- **Activated for 10 days**: the effect goes with the hero for 10 days, and the building can then be used by nobody for 10 days. Reality Convertor, Mech Worms Production Facility, Temple of Frost Wind, Source of Oblivion, Ticks Breeding Grounds, Shrine of Nature, Wolves dens, Stone plate.
- **Activated once per hero**: the effect stays with the hero. Magneto, Purify Station, Contagious Fingus, Hermit's Hut, Altar of Storms, Rat Holes, Lightning Generator.
- **Working by distance**, without a visit: they affect the battles of every hero or creature within 10 tiles of them. Disturbance Generator, Data Flow, Gravity Anomaly Site, Ether Stir, Monument of Peace, Aviak's Sacred Place, Ancestral Tomb, Resonating caves, Balance Grounds, Protector of Life, Toxic Wastes, Cursed Spring, Active Volcano, Shaking grounds, Links of Pain.

!objects el2/AdditionalBuildings/E2Black1 = Reality Convertor | el2/AdditionalBuildings/E2Black5 = Mech Worms Production Facility | el2/AdditionalBuildings/E2Blue3 = Temple of Frost Wind | el2/AdditionalBuildings/E2Blue8 = Source of Oblivion | el2/AdditionalBuildings/E2Green3 = Ticks Breeding Grounds | el2/AdditionalBuildings/E2Green8 = Shrine of Nature | el2/AdditionalBuildings/E2Red2 = Wolves dens | el2/AdditionalBuildings/E2Red7 = Stone plate | el2/AdditionalBuildings/E2Black4 = Magneto | el2/AdditionalBuildings/E2Black6 = Purify Station | el2/AdditionalBuildings/E2Green1 = Contagious Fingus | el2/AdditionalBuildings/E2Green2 = Hermit's Hut | el2/AdditionalBuildings/E2Red5 = Altar of Storms | el2/AdditionalBuildings/E2Red6 = Rat Holes | el2/AdditionalBuildings/E2Red9 = Lightning Generator | el2/AdditionalBuildings/E2Black2 = Disturbance Generator | el2/AdditionalBuildings/E2Black3 = Data Flow | el2/AdditionalBuildings/E2Black7 = Gravity Anomaly Site | el2/AdditionalBuildings/E2Blue1 = Ether Stir | el2/AdditionalBuildings/E2Blue2 = Monument of Peace | el2/AdditionalBuildings/E2Blue4 = Aviak's Sacred Place | el2/AdditionalBuildings/E2Blue5 = Ancestral Tomb | el2/AdditionalBuildings/E2Blue6 = Resonating caves | el2/AdditionalBuildings/E2Blue7 = Balance Grounds | el2/AdditionalBuildings/E2Green5 = Protector of Life | el2/AdditionalBuildings/E2Green6 = Toxic Wastes | el2/AdditionalBuildings/E2Green7 = Cursed Spring | el2/AdditionalBuildings/E2Red1 = Active Volcano | el2/AdditionalBuildings/E2Red4 = Shaking grounds | el2/AdditionalBuildings/E2Red8 = Links of Pain

Each building's tooltip on the map describes its battle effect.
