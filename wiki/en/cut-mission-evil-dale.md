---
title: Evil Dale (cut mission)
category: story
order: 92
summary: A cut bonus mission of Etherlords: the Chosen One must escape a dale of ancient ruins
---
**Evil Dale** is a bonus mission of [Etherlords](cut-content-el1) that was never released. Its map, `bmission01`, is in neither edition, but its texts, its six heroes and their decks are in the game's files, and the program still checks its win condition. The Russian edition calls it «Проклятые руины» ("Cursed Ruins").

## Briefing

A vanguard of the Vitals finds a scroll in lands long hidden from the Lords. After days of rituals it reveals knowledge of an ancient power, greater than the Lords' own, in which all four elements are united. One Vital alone is chosen to follow the "Way of Knowledge" to the dale the scroll describes. When he arrives, the trees close behind him and mountains rise across the way back, so the only way left is forward.

In the game's own wiki, the full briefing from your copy of the game appears here:

!text el1/MT_B1_DESC

The mission's conditions, as the English edition words them:

| Condition | Text |
|---|---|
| Objective | Investigate the surroundings and find the way out of the dale |
| Victory | Find the way out of the dale |
| Defeat | Death of the Chosen |

## Heroes

The player has a single level 1 Vital, the **Chosen One**. The other five heroes, one or two of each race and stronger at every step, were probably the opponents met along the way.

| Hero | Race | Level | Specialization | Skills | Deck |
|---|---|---|---|---|---|
| Chosen One | Vitals | 1 | [Rebirth](spec-rvve) | none | Start green deck |
| Zarus | Chaots | 4 | [Rats' Tenacity](spec-rrtr) | [Luck](skill-mstr) 3 | "Bonus level Walls" |
| Glazzz | Vitals | 6 | [Raise Dead](spec-etti) | [Strength](skill-heal) 2, [Concentration](skill-conc) 3 | "Bonus level Fliers" |
| Valaddin | Kinets | 8 | [Adhesive](spec-msen) | Luck 3, [Suppression](skill-supr) 3, Concentration 1 | "Bonus level Control" |
| Tango | Synthets | 10 | [Velos' Twins](spec-bvld) | Luck 3, Strength 3, Concentration 3 | "Bonus level Rush" |
| Warp | Chaots | 12 | [Dragon Skin](spec-drsk) | Strength 3, [Artificer](skill-artf) 3, Luck 3, [Regeneration](skill-regn) 3 | "Bonus level Last" |

!objects el1/HeroTemplates/BLevStartHero = Chosen One | el1/HeroTemplates/BLevHero1 = Zarus | el1/HeroTemplates/BLevHero2 = Glazzz | el1/HeroTemplates/BLevHero3 = Valaddin | el1/HeroTemplates/BLevHero4 = Tango | el1/HeroTemplates/BLevHero5 = Warp

!objects el1/Portrait/70 = Chosen One | el1/Portrait/34 = Zarus | el1/Portrait/75 = Glazzz | el1/Portrait/91 = Valaddin | el1/Portrait/56 = Tango | el1/Portrait/39 = Warp

## Decks

- **Start green deck** (the Chosen One): 4× [Spitting Fingus](card-spfg), 3× [Tick Warrior](card-tiwr), 2× [Dense Forest](card-dnfr), 3× [Sharp Claws](card-shcl), 3× [Ether Drop](card-mndp).
- **Bonus level Walls** (Zarus): 2× [Rock Wall](card-rkwl), 3× [Disease Rat](card-drat), 3× [Earthquake](card-erqa), 2× [Burning Graves](card-brgr), 2× [Plague Rat](card-prat), 1× [Stink Rat](card-strt), 2× [Lesser Strength](card-lsst).
- **Bonus level Fliers** (Glazzz): 3× [Bee Warrior](card-bewr), 2× [Bee Worker](card-bewk), 1× [Magic Hornet](card-maho), 1× [Bee Queen](card-beqn), 1× [Mother Bee](card-mobe), 1× [Dominance](card-domn), 1× [Endurance of the Woods](card-enwo), 3× [Ether Tap](card-mntp), 1× [Strength of Woods](card-stwo), 1× [Mystic Hornet](card-myho).
- **Bonus level Control** (Valaddin): 2× [Flood](card-flod), 2× [Hostile Ambience](card-hoam), 2× [Condensed Air](card-cnar), 2× [Ice Storm](card-icst), 3× [Water Elemental](card-wtel), 2× [Fog](card-fogg), 1× [Feedback](card-fdbk), 1× [Air Link](card-ailk).
- **Bonus level Rush** (Tango): 3× [Small Velos](card-smvl), 3× [Big Velos](card-bgvl), 2× [Overload](card-ovrl), 2× [Data Attraction](card-trlb), 2× [Alpha Strike](card-alst), 2× [Frenzy Gas](card-frgs), 1× [Tap Life](card-tplf).
- **Bonus level Last** (Warp): 2× [Ash storm](card-asst), 1× [Geyser](card-geys), 2× [Volcano](card-volc), 2× [Overload](card-ovrl), 3× [Orc Elder](card-orel), 2× [Orc Warrior](card-orwr), 1× [Glitterdust](card-gldt), 2× [Air Link](card-ailk).

## What the program still knows

- The mission is won when the Chosen One comes within two tiles of the point (30, 123). The area from x 0 to 39 and y 104 to 159 is revealed first, and the victory follows at the next check.
- It is lost when no Chosen One is left.
- Glazzz walks a fixed loop: from (55, 146) to (55, 110), then (64, 84), then (55, 104) and back to (55, 146). When the Chosen One comes within his sight, less three tiles, he attacks him instead.
- Warp keeps no route: he attacks the Chosen One when he comes within sight, and otherwise visits the sites near him.
- Every other rival also attacks the Chosen One when he comes within its sight.
- Every hero of the map whose template is a BLevHero guards the tiles around it, as a neutral creature does: a hero who steps beside a rival is stopped and must fight.
- These points show that the map was large: at least 65 tiles wide and 160 tiles long. Every map of the game is square, so it was probably the largest size, 160 by 160.

## In Demiurges

Demiurges rebuilds Evil Dale as a single mission of its own, listed after [Savage Desert](cut-mission-savage-desert). The [random map](adventure-map) generator lays it out from a fixed recipe on a 160-tile map, and the mission keeps every rule the program still has:

- The Chosen One is alone: no castle, no other hero, no summoning, and no scrolls of global spells, which he could not cast. He starts in a glade of the Vitals' woods in the south-east, with the shops and mines of a small homeland around him.
- The dale is one long valley, walled by cliffs and woods, that winds through the four elements: the Chaots' dark rock, the Kinets' snow (with a second homeland of shops and mines), the Synthets' sand (with an outpost of their shops and a component portal where it begins), and the Vitals' woods again, where Glazzz walks his loop on the program's points, along an old track lined with groves. A pass in the west leads to the way out at (30, 123). Where the dale passes from one element to the next, a pair of its marks stands on either side of the way: the Chaots' fires where the rock begins, spires of ice at the snow, the Synthets' monuments at the sand and great trees where the woods come back.
- The rivals wait along the way, each in the ground of his race: Zarus in the rock, Valaddin in the snow, Tango in the sand, Glazzz in the last woods and Warp at the pass. Each waits among the marks of his race: Zarus between fires in the rock, Valaddin in a ring of ice spires, Tango among Synthet ruins and Warp between fires at the pass. As the program has it, each rival guards the tiles around him and attacks the Chosen One who comes within his sight; Glazzz walks his loop meanwhile, and the others hold their places.
- The creatures grow with the journey, from the first level at the glade to the ninth near the exit, and belong to the ground they stand on. They are chosen in the order the Chosen One meets them: no kind comes back until four others have been met.
- Beyond the pass lie the ruins where the four elements meet: four quarters of ground around a monument, in a ring of broken walls. The program reveals them when the Chosen One reaches the way out, and the mission is won.
- The Chosen One and the rivals speak on the way, in message boxes with their portraits: at the start, at the ground of each element, when he meets each rival and after Glazzz and Warp are beaten. Each rival is a hero of his race who came seeking the same power and is trapped in the dale too. The original has no lines for the mission beyond its briefing, so these are Demiurges' own, written after the dialogues of Etherlords II.
- Both editions show their own texts.

This is a reconstruction: only the points and the rules above come from the original. The dale's course between them, the places of Zarus, Valaddin and Tango, the elements along the way and the ruins are Demiurges' reading of the briefing.

## The Chosen One

The mission's hero is called "the Chosen One" («Избранный»), and its Russian title, «Проклятые руины», sounds like «Проклятые земли», the Russian title of Nival's earlier game *Evil Islands*, whose hero Zak is called the Chosen One there too. The bonus mission was probably a nod to it.
