# Etherlords I stock map survey

This survey measures the 37 original Etherlords I missions so that random maps
can follow the same layout. It covers 20 campaign, 7 single and 10
multiplayer missions. Generator version 13 (`EL1R13:`) is built from the
rules below. The tables compare it with the stock missions.

Run the survey with `tools/first_map_survey.gd`:

```
godot --headless --path game --script ../tools/first_map_survey.gd -- --maps=stock --out=<dir>
godot --headless --path game --script ../tools/first_map_survey.gd -- --maps=generated --presets=frontier,lakes --seeds=212,audit-7 --size=128 --out=<dir>
```

The script writes one JSON file per map. `--png=<dir>` also saves a
schematic of each map, with walkable tiles of clearance 2 in yellow and 3 or
more in orange. All figures use the mission-start state at the middle
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

Version 13 paints its roads the same way. It breaks the network into 10 to
30 pieces per map, the largest 55 to 105 tiles long, and drops short side
spurs. Then 34% of its road tiles are turns and 4% are junctions.

## Comparison with generated maps

Each figure is first measured per map, as a share of that map's land, and
then summarised as the median [lowest–highest] over maps. That keeps a large
map from outweighing a small one. Stock figures come from the 17 single and
multiplayer missions; the story missions of the campaign are left out. The
generated figures come from version 13 maps for all 11 presets at each of the
four sizes (64, 96, 128 and 160 tiles), three seeds each: 132 maps, all of
which generate.

| Measure, per map | Stock | Version 13 |
| --- | ---: | ---: |
| Scenery cover % of land | 47.8 [36–65] | 51.2 [29–68] |
| Walkable tiles with clearance ≤ 1 | 80.7% [68–91] | 82.6% [78–87] |
| Walkable tiles with clearance 2 | 18.8% [10–30] | 16.8% [13–21] |
| Walkable tiles with clearance ≥ 3 | 0.8% [0–3.5] | 0.6% [0.1–1.9] |
| Widest open spot (clearance) | 3 [2–5] | 3 [3–4] |
| Narrow share of castle routes | 81% [67–91] | 85% [74–97] |
| Mean scenery cluster, tiles | 32 [10–138] | 45 [11–156] |
| Mean prop footprint, tiles | 5.1 [2.2–7.9] | 3.1 [2.0–3.9] |

Cover rises with map size: 37% at 64 tiles, 49% at 96, 53% at 128 and 57% at
160. The water presets sit lower (39–47%) because harbors, quays and coasts
keep their ground open.

Further measures, pooled over the maps:

| Measure | Stock | Version 13 |
| --- | ---: | ---: |
| Walkable tiles in a one-tile corridor | 9.7% | 10.8% |
| Walkable tiles in one-tile runs of three or more | 0.4% | 0.9% |
| Cover from single-tile props | 7.7% | 19% |
| Cover from props spanning 5–8 tiles | 47% | 32% |
| Creatures with one of their kind within ten tiles | 3.2% | 0.3% |
| Walkable share of land 3–4 tiles from a castle | 57% | 49% |
| Walkable share of land 10–14 tiles from a castle | 44% | 43% |

### Ground under objects

The stock missions paint the ground by what stands on it. On grass, 91% of
the corners under trees are forest soil (kind 2), rocks stand on cobbles
(kind 3) or grass, and the open ground is plain grass (kind 0, 73%). Red
ground puts rocks on kind 11 and trees on kind 9; tan ground puts rocks and
trees on the brown kinds 15 and 14; snow keeps rocks and pines on snow
(kinds 4 and 5) or ice (18), and lays about a quarter of its pine stands on
brown or dark earth. Forts stand on brick (kind 6). Version 13 follows the
same shares, so forest masses read as dark ground with a lighter rim. The
exception is snow: version 13 lays about 60% of its pine stands on brown or
dark earth, against a quarter in the stock missions, because its snow is
denser and the sparse pine models alone would make a blocked stand look like
open snow.

### Castle approaches

Counted from each castle's walls, by the side the castle faces, the stock
missions keep one side clear: the wall opposite the row where recruits
appear. In 99 of the 114 stock castles, no site, resource pile or creature
stands within eight rows of it, across the width of the walls, and 62 have no
scenery there either. The other sides are busier: within eight rows, 59%
of the castles have a site or creature before the stairs of the castle
model, half behind the walls and four in five along the recruits' row.
Version 13 keeps sites and creatures eight rows from both the clear side and
the stairs, the side the camera shows as the front. They also stay five rows
from the back wall, which the tall castle model overhangs from the camera,
and three rows from the recruits' row. Of 336 castles on 88 sample maps, only a few on
crowded 64-tile island maps have a starting mine or shop closer than that.

Known differences in version 13:

- Large cliffs make up less of the cover (32% against 47%), and more of it
  comes from single-tile props (19% against 8%). Mass edges are irregular, so
  many gaps fit only small props.
- Cover runs a few points higher on the larger land maps, mostly from the
  masses between the narrow lanes.
- Creatures within ten steps of a castle are about one level stronger than
  in the stock missions.
- The back and sides of a castle are kept clearer than in the stock missions.
