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
- Glazzz and Warp, as computer heroes, walk a fixed route that turns at the points (55, 110), (55, 146), (64, 84) and (55, 104).
- These points show that the map was large: at least 65 tiles wide and 160 tiles long.

## The Chosen One

The mission's hero is called "the Chosen One" («Избранный»), and its Russian title, «Проклятые руины», sounds like «Проклятые земли», the Russian title of Nival's earlier game *Evil Islands*, whose hero Zak is called the Chosen One there too. The bonus mission was probably a nod to it.
