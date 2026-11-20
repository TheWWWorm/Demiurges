# Etherlords I stock map survey

This survey measures the 37 original Etherlords I missions so that random maps
can follow the same layout. It covers 20 campaign, 7 single and 10
multiplayer missions. Generator version 13 (`EL1R13:`) is built from the
rules below. The tables compare it with the stock missions and with version 12.

Run the survey with `tools/first_map_survey.gd`:

```
godot --headless --path game --script ../tools/first_map_survey.gd -- --maps=stock --out=<dir>
godot --headless --path game --script ../tools/first_map_survey.gd -- --maps=generated --presets=frontier,lakes --seeds=212,audit-7 --out=<dir>
```

The script writes one JSON file per map. `--png=<dir>` also saves a
schematic of each map. All figures use the mission-start state at the middle
difficulty and count land tiles only, so sea on naval maps is excluded.
Values are given as mean [minimum–maximum] over maps.

## Definitions

- **Scenery cover** is the share of land tiles occupied by the footprint of
  a decorative prop, such as a tree, rock, bush or crater.
- **Clearance** of a walkable tile is its distance to the nearest blocked
  tile, counting diagonal steps. A clearance of 0 or 1 means the tile lies in
  a passage at most about three tiles wide.
- **Zones** use walking steps from the nearest castle: home is up to 15
  steps, mid is 16–30 steps and far is beyond 30.
- **Creature level** comes from the creature's roster definition at the
  middle difficulty.

## Stock missions

| Measure | Campaign | Single | Multiplayer | All stock |
| --- | ---: | ---: | ---: | ---: |
| Map side | 74 [20–120] | 80 [40–120] | 92 [40–160] | 80 [20–160] |
| Water % of map | 5.5 [0–19.5] | 15.4 [0–32] | 13.8 [0–32.8] | 9.6 [0–32.8] |
| Road % of land | 3.1 [0–8.4] | 6.7 [0–12.2] | 5.3 [0–10.3] | 4.4 [0–12.2] |
| Scenery props per 1000 land | 96 [0–204] | 179 [88–275] | 139 [74–237] | 123 [0–275] |
| Scenery cover % of land | 35 [0–55] | 54 [44–65] | 45 [36–61] | 41.5 [0–65] |
| Mean prop footprint, tiles | 4.7 | 5.5 | 4.9 | 4.9 [0–8.4] |
| Mean scenery cluster, tiles | 37 | 54 | 52 | 44 [0–138] |
| Largest scenery cluster, tiles | 769 | 437 | 391 | 604 [0–2110] |
| Walkable tiles with clearance ≤ 1 | 66% | 77% | 80% | 72% [19–93] |
| Walkable tiles with clearance ≥ 4 | 12.6% | 0.0% | 0.0% | 6.8% |
| Widest open spot (clearance) | 6.3 | 3.1 | 3.2 | 4.9 [2–18] |
| Castle-to-castle route / straight line | 1.3 | 1.7 | 1.3 | 1.4 [0.9–2.0] |
| Narrow share of castle routes | 74% | 79% | 83% | 79% [66–92] |
| Creatures per 1000 land | 10.1 [1.2–27.9] | 8.4 [6.8–9.6] | 11.7 [7.9–23] | 10.2 [1.2–27.9] |
| Mines per 1000 land | 1.8 | 2.1 | 3.5 | 2.3 [0–6.3] |
| Resource piles per 1000 land | 4.0 | 1.4 | 4.5 | 3.7 [0–14.2] |
| Service buildings per 1000 land | 4.9 | 8.5 | 5.8 | 5.8 [0–12.4] |
| Gap to nearest creature, tiles | 5.0 | 6.4 | 5.8 | 5.4 [2–8] |
| Gap to nearest site, tiles | 3.9 | 4.9 | 4.1 | 4.2 [3–5] |

Campaign missions are the most varied, from small scripted arenas to large
open plains. Single and multiplayer missions follow one consistent pattern.
The large open areas counted in the campaign column come from a few story
missions.

### By zone

| Zone | Land share | Creatures / 1000 | Sites / 1000 | Scenery cover | Road % |
| --- | ---: | ---: | ---: | ---: | ---: |
| Home | 36% | 9.2 | 15.9 | 38% | 5.1 |
| Mid | 31% | 10.6 | 17.8 | 43% | 5.1 |
| Far | 33% | 10.0 | 17.5 | 45% | 4.1 |

Density barely changes with distance. Starting areas are slightly more open,
but they are not empty clearings.

### By ground

| Ground | Land tiles | Scenery cover | Creatures / 1000 | Sites / 1000 |
| --- | ---: | ---: | ---: | ---: |
| Red (Chaots) | 72,724 | 62% | 6.5 | 13.7 |
| Green (Vitals) | 78,867 | 45% | 8.9 | 16.3 |
| Black (Synthets) | 64,875 | 42% | 9.7 | 18.3 |
| Blue (Kinets) | 27,849 | 24% | 15.9 | 20.2 |

Red ground is a crowded rock maze. Blue ice fields are the most open and hold
the most creatures for their area.

### Creatures

Across 2,251 stock creatures:

| Steps from castle | Count | Median level | Mean level |
| --- | ---: | ---: | ---: |
| ≤ 10 | 308 | 2 | 2.8 |
| 11–20 | 501 | 4 | 3.7 |
| 21–30 | 491 | 4 | 4.5 |
| 31–45 | 480 | 5 | 5.1 |
| > 45 | 471 | 6 | 5.4 |

- 49% stand within two tiles of a site.
- 26% stand on or beside a road.
- 59% stand in a passage with clearance ≤ 1.
- 37% match the faction of their ground.
- The median distance from a castle is 27 steps.

### Scenery

The most common prop families are Green forest, Green stone, Green bush,
Blue pine, Red bush, Black stone, Red stone, Black bush, Black tree and
neutral rock. Stock ground is flat: the original missions have no relief.

Prop names follow the art sets, not the ground they stand on. The dark Chaot
ground carries the neutral grey rock stacks (`rock_1`–`rock_8`), black trees,
black hills and some ice ridges (`Blue_rock1_*`). The tan Synthet ground
carries the `Red_rock`, `Red_Stone` and `Red_Bush` props. Grass carries green
forest and the green crags (`GreenRock*`), and snow carries blue pines, ice and
a few snowy ridges.

Large props shape the maze. Cliffs and rocks with a span of five tiles or more
make up 50% of all scenery cover: 62% on dark ground, 44% on tan, 33% on grass
and 8% on snow. Their footprints interlock, so they form continuous walls
rather than separate boulders. By footprint area, the remaining cover is 25%
props three to four tiles across, 18% two-tile props and 8% single tiles.
`STOCK_SCENERY` in the generator lists each ground's prop mix by share of cover.

## Derived rules

1. Keep the ground level. Shape the land with scenery and water, not hills
   and valleys.
2. Fill about 40% of the land with scenery, joined into masses of tens to
   hundreds of tiles. The walkable land between them forms veins two to four
   tiles wide. About 70–80% of walkable tiles should lie in a passage.
3. Vary the density by ground. Red is the densest, Blue the most open, and
   Green and Black sit in between.
4. Keep open areas small. Outside story missions, the widest open spot has a
   clearance of three to five.
5. Let roads merge into a sparse network covering about 4–5% of the land.
   Routes between castles wind, at about 1.4 times the straight distance.
6. Place about 10 creatures per 1000 land tiles evenly across home, mid and
   far ground. Put most of them in passages, many beside sites and about a
   quarter on roads.
7. Raise creature levels with walking distance, from about 2–3 near a castle
   to 5–6 far away.
8. Place about 16–18 interactable sites per 1000 land tiles, about four tiles
   apart.

## Roads

Twenty-six of the 37 stock missions have roads. The road bytes only set
movement cost and the minimap colour; the game draws no road surface.
Instead, about three in four road tiles carry the climate's path ground on
their corners (kind 0 on grass, 4 on snow, 8 on red ground and 12 on tan
ground), and the tile blending shows that as a soft band. On snow and tan
ground the path ground looks almost the same as the field around it.

Stock roads are one tile wide and climb diagonals as staircases; 44% of
their tiles are turns. They branch rarely: 3% of road tiles are junctions,
and a map holds 20 to 40 separate road pieces, the largest 60 to 180
tiles long.

Version 13 paints its roads the same way. After it drops short side spurs,
36% of its road tiles are turns and 6% are junctions. Its roads still form
one network between the castles rather than separate pieces.

## Comparison with generated maps

Generated figures come from 2 seeds (212 and audit-7) of each of the 11
presets. They cover 22 maps per version, and each version was measured on
the same set.

| Measure | Stock | Version 12 | Version 13 |
| --- | ---: | ---: | ---: |
| Ground relief | flat | hills and valleys | flat |
| Scenery props per 1000 land | 123 | 49 | 182 |
| Scenery cover % of land | 41.5 | 14.4 | 50.0 |
| Cover from props spanning 5+ tiles | 50% | — | 33% |
| Mean prop footprint, tiles | 4.9 | 2.9 | 2.5 |
| Mean scenery cluster, tiles | 44 | — | 48 |
| Walkable tiles with clearance ≤ 1 | 72% | 51% | 74% |
| Walkable tiles with clearance ≥ 4 | 6.8% | 4.2% | 0.1% |
| Widest open spot (clearance) | 4.9 | 9.6 | 8.3 |
| Narrow share of castle routes | 79% | 49% | 67% |
| Castle route / straight line | 1.4 | 1.1 | 1.2 |
| Road % of land | 4.4 | 4.9 | 5.6 |
| Creatures per 1000 land | 10.2 | 8.6 | 10.2 |
| Creatures in passages | 59% | 71% | 90% |
| Creatures near a site | 49% | 36% | 69% |
| Creatures on or beside a road | 26% | 16% | 23% |
| Creature level, ≤ 10 steps (mean) | 2.8 | 2.3 | 3.8 |
| Creature level, 11–20 steps | 3.7 | 2.5 | 4.1 |
| Creature level, 21–30 steps | 4.5 | 2.8 | 4.5 |
| Creature level, 31–45 steps | 5.1 | 3.2 | 4.9 |
| Gap to nearest creature, tiles | 5.4 | 5.0 | 5.5 |
| Gap to nearest site, tiles | 4.2 | 5.2 | 5.2 |

Scenery cover by ground in version 13 is Red 54%, Green 51%, Black 51% and
Blue 48%, against 62%, 45%, 42% and 24% in the stock missions. Snow is
deliberately closer to the other grounds than in the stock missions, so it
keeps the maze of lanes instead of opening into wide fields. The share of
creatures in passages was not measured again after the last change.

Scenery cover in rings around castles (tiles from the walls) is 41% at one
to two tiles, 44% at three to four, 43% at five to six, 47% at seven to nine
and 51% at ten to fourteen. The stock missions have 41%, 43%, 51%, 54% and
55%.

Known differences in version 13:

- Large cliffs make up less of the cover (33% against 50%). Mass edges are
  irregular, so many gaps fit only single-tile props, which brings the mean
  prop footprint down to 2.5 tiles against 4.9.
- Scenery covers more land (50% against 42%), mostly on snow, and roads
  take a little more of it (5.6% against 4.4%).
- Starting areas and the centres of naval maps can still hold a clearing
  wider than any in the stock single and multiplayer missions.
- Creatures within ten steps of a castle are about one level stronger than
  in the stock missions.
- Roads now wind along the lanes, but the shortest walking route between
  castles is still straighter than in the stock missions (1.2 against 1.4).
