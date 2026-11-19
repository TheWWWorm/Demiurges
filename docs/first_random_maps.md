# Etherlords I random maps

Demiurges can generate local Etherlords I single missions with eight world
layouts, eleven presets, configurable economies and real naval travel. The
generated world uses the normal heroes, shops, combat, strategic AI, fog,
castle warfare and save system. Enable ships for islands and sea routes, or
leave them off for an overland game.

See [Naval maps](first_naval_maps.md) for boarding, movement costs, coastal
battles, ship appearance and the developer harbor contract.

## Start a game

Mount your Etherlords I installation using the [game files setup](../README.md).
To run from source, open `game/project.godot` in Godot 4.7.

1. Open **Single Mission**, then **Random map…** at the bottom of the mission panel.
2. Select a preset. **Island chains** provides separated island kingdoms with
   ships enabled; **Frontier** provides a straightforward land game.
3. Adjust the **World** and **Players and rules** tabs. The **Enable ships and
   harbors** checkbox controls naval travel independently of the layout.
4. Choose **Generate preview** to build and check the actual world. **New seed**
   changes the seed and generates another preview.
5. Choose **Play this map**, or **Generate and play** without previewing first.

The preview is a schematic of the whole terrain and its placed objectives.
Harbors have cyan markers; the human castle marker is gold. Normal exploration
fog begins when the game starts. Defeat every hostile castle while preserving
your own. This is a local single mission, with no campaign chapter progression.

### Give movement orders

Select a hero and click a destination to plan its route. With the usual free
movement option, clicking that planned destination again executes the order.
With movement resolved at the end of the day, plan your orders and use **Next
day** (`N`). `Backspace` cancels the selected hero's order.

On a naval world, the route can include walking to a harbor, boarding, sailing,
landing at another harbor and continuing inland. There is no separate boat
purchase or boarding command. A voyage can continue across several days, and a
hero can be saved while at sea. Your own Etherlords II installation is optional:
it supplies the original boat model when available; otherwise a built-in
sailboat model is used.

## Presets and geography

| Preset | Size and players | Ships | Geography or rules |
| --- | --- | --- | --- |
| Quick duel | 64 × 64; 2 players | Off | Short overland approaches; 20 castle energy. |
| Frontier | 96 × 96; 4 players | Off | A broad continent, organic bays and several routes between rivals. |
| Island chains | 128 × 128; 4 players | On | Separate island kingdoms and outlying islands; high water coverage. |
| Inland sea | 128 × 128; 4 players | On | Coastal kingdoms around a central sea and its islands. |
| River delta | 96 × 96; 4 players | On | Navigable channels, provinces and delta islands. |
| Ring of kingdoms | 128 × 128; 4 players | On | An island ring with straits around a contested central sea. |
| Peninsulas | 128 × 128; 4 players | On | Coastal fingers, central land routes and seaborne flanking routes. |
| Lake country | 128 × 128; 4 players | On | Linked lakes and rivers form an inland sailing network. |
| Crossroads | 96 × 96; 4 players | Off | Approaches converge on a valuable central crossroads. |
| Scarcity | 96 × 96; 4 players | Off | Frontier layout, scarce resources and treasury, strong guards. |
| Rich conquest | 128 × 128; 4 players | Off | Frontier layout, rich resources and treasury, 60 castle energy. |

Choosing a preset preserves the seed and human faction. Other world fields
reset to that preset's settings and the current defaults. All remain editable.

The eight layout identifiers are `frontier`, `lakes`, `crossroads`,
`archipelago`, `inland_sea`, `river_delta`, `ring` and `peninsulas`. Changing the
layout dropdown alone does not automatically change the ships checkbox.

**Water coverage** changes the amount of water within the selected geography.
**Coastline** selects smoother or more rugged shores. These are relative
controls, not exact water percentages: space for playable homelands and valid
routes also affects the result. With ships enabled, connected seas and explicit
harbors provide the connections between islands. Roads stop on land at harbor
approaches. With ships disabled, required objectives remain accessible through
the overland route network.

### Opening economy and strategic opportunities

Every player starts with a castle and a valid level-one hero from the chosen
faction's installed templates. Each homeland has the same categories of nearby
neutral infrastructure: a matching mana node, root and lotus mines, the
faction's gem mine, and rune, creature and spell shops. These sites must be
captured; they are not automatically granted as owned income.

Frontier and island content adds mines, resource caches, difficulty-aware
guards, artifact rewards and global-spell scrolls. Higher recruitment ranks
are discovered on the map. Shops use actual installed combat spells and the
normal stock and purchase rules. Naval homelands have multiple harbor
approaches, giving opponents alternate routes and coastal objectives to contest.

Main roads link markets, recruitment scrolls, and harbors. Neutral forts stand
beside these routes where the terrain leaves room for an approach and a way
past. Heroes can garrison them using the usual fort controls. Mines follow
their terrain and many caches, artifacts, and optional scrolls sit off the road.
When guards are enabled, optional frontier prizes favor alcoves where a
creature can cover every approach. Shorelines, trees, and rocks help define the
entrance. Crowded areas and content without suitable blockers can get a prize
with an alternate approach. The economy and recruitment paths leave room to
expand without starting a fight.

Starting opportunities are comparable, while coastlines, approaches and faction
strengths can differ. The generator validates actual object footprints and
reachable approaches after placing scenery and other content.

### Exploring the wilderness

Look behind your castle for springs and mentors. Springs give a visiting hero
a weekly health or movement bonus. Mentors award experience or teach skills.
Traveling merchants, training camps and alchemists can appear away from the
main roads. Remote banks and islands get discoveries based on the distance
from nearby sites along the same land. Lairs start occupied and can restock
each week. The strongest lairs are intended for experienced heroes.

A Seer can reveal a distant crystal ball and the area around it through fog.
Larger naval worlds can have small outlying islands with artifacts and lairs.
Use the violet markers in the setup preview to spot regions with discoveries.

Woodland thins into brush and meadows at its edges. Hills rise above low
riverbanks and beaches, and buildings sit on terraces cut into the ground.
Shops gather along the same approach. Root and lotus production favor woods
and riverbanks respectively, while gems and stone favor ridges. Roads and
footpaths follow the terrain. Normal scenery uses native trees and rocks
in groves, on slopes, and along road verges. **Dense** adds heavier cover.

On a fresh version 9 map, every reachable land tile has a pickup, usable site,
or encounter within about a day and a half of travel for the slowest starting
hero. The check uses actual movement costs, shorelines, and final scenery.
Quiet stretches gain small resource caches where needed. Monster searches
count creatures out in the world separately from occupied lairs.

Each homeland has its own recruitment scrolls and access to its starting
economy. With guards enabled, a nearby optional encounter is drawn from a
pool tested against the four starting spellbooks. Stronger creatures appear
farther from the starting heroes, near optional mines, scrolls, and relics.
The difficulty setting uses the original creatures' corresponding spellbooks.
The computer can lead a siege with a level-five recruit when it can wear down
the target castle's restoration.

### Placement in the original missions

The placement survey used the 37 maps read from a Steam installation of
Etherlords I. That includes 20 campaign entries, some of them alternate
versions of the same chapter, plus seven single missions and ten multiplayer
missions. The survey measured distances in tiles from object anchors, counting
a diagonal as one tile. The generated comparison used the same two seeds,
`212` and `placement-41`, for each of the 11 presets in versions 6 and 7.

| Placement measure | Stock single | Stock multiplayer | Generated v6 | Generated v7 |
| --- | ---: | ---: | ---: | ---: |
| Scrolls and artifacts within four tiles of a neutral creature | 73% | 91% | 10% | 62% |
| Median distance from a scroll or artifact to its nearest neutral creature | 3 | 2 | 11 | 2 |
| Mines and mana nodes within three tiles of a road | 28% | 34% | 100% | 53% |
| Shops within three tiles of a road | 66% | 44% | 100% | 100% |
| Visit sites within three tiles of a road | 63% | 51% | 20% | 35% |
| Forts within three tiles of a road | 100% | 86% | — | 75% |

Road percentages are medians of the per-map percentages among maps with
roads and the relevant objects. The creature measurements pool objects across
maps with neutral creatures. Those distances describe placement and include
every scroll. The runtime check separately tests whether each generated reward
guard can intercept a hero on an actual interaction tile.

Stock missions put scrolls and artifacts farther from starting positions than
shops or income sites, and commonly place guards beside them. Roads favor
services and forts. The generator uses these patterns to separate the opening
economy, travel routes, and optional discoveries. Recruitment scrolls remain
part of each player's opening progression. Compact maps may have no suitable
site for a frontier fort.

### Supplies, terrain, and decoration

In the broader placement survey, 52 of 65 resource piles in the stock single
missions and 239 of 304 in multiplayer sat within four tiles of a neutral
creature. About three in ten piles had another pile within four tiles. Version 8
groups frontier supplies in pairs or single caches by a nearby reward guard
where the approaches fit. Each homeland still gets its own opening supplies.

All 17 stock single and multiplayer maps had more dry than wet boundary
samples. Median wet-edge coverage was 19% for single missions and 9% for
multiplayer. Version 8 gives overland Frontier a seed-dependent bay and inland
pools, Lake country a group of distinct basins, and Crossroads a dry central
junction with water between some of the approaches. Island chains and other
naval recipes use the connected water routes.

Stock decoration also clusters. In single and multiplayer maps respectively,
75% and 78% of tree objects had another tree group within two tiles. About
48% and 38% of tree objects on maps with roads stood within three tiles of a
road. Rocks clustered even more tightly. The generator now adds biome-matched
trees to broader groves and fills some of the road verges with trees and rocks.
It preserves the roads, actual paths to objectives, and harbor approaches.

The same 22 preset runs measured the effect of the second pass. Overland
boundary figures use the ten runs from the five overland presets.

| Measure | Generated v7 | Generated v8 |
| --- | ---: | ---: |
| Resource piles within four tiles of a neutral creature | 16% | 32% |
| Median wet-edge coverage on overland presets | 100% | 15% |
| Median scenery objects per 100 map cells | 8.5 | 21.7 |
| Tree objects within three tiles of a road | 18% | 32% |

### Creature placement and passability

The creature survey loaded all 37 stock missions and the same 22 generated
presets and seeds at the middle of the five difficulty levels. It used the
game's terrain costs, rotated object footprints, active creature zones, and
naval crossings at mission start, with the standard interception radius.
Hidden creatures, dungeon occupants, and later scripted spawns are outside
the survey.

A creature occupies one tile. Its interception zone usually reaches the
eight neighboring tiles that a hero can stand on. Entering a hostile zone
stops movement and queues a duel. Shore, scenery, structures, and other
actors can trim this zone. A tile can therefore be legal to enter and still
trigger combat. On naval maps the land guard's zone stays on land, and the
route search also checks both sides of a diagonal and the exact harbor links.

| Measure at mission start | Stock single | Stock multiplayer | Generated v8 |
| --- | ---: | ---: | ---: |
| Creatures whose occupied tile alone cuts a crossing | 6/321 | 15/881 | 0/700 |
| Creatures whose interception zone separates two usable areas | 86/321 | 168/881 | 7/700 |
| Creatures whose zone touches a road, among maps with roads | 151/309 | 208/769 | 3/700 |
| Scroll and artifact sites whose every open approach is guarded | 13/50 | 80/206 | 0/336 |

A crossing connects two walkable exits beside the guard or zone. The test
checks for a detour anywhere on the map with that one zone avoided. The
second row requires two separated areas with at least twelve traversable
tiles each, which excludes guards that only seal small pockets. The full
survey found this effect around 234 of 1,006 visible campaign creatures as
well. The last row measures the tiles directly around a site, while a guard
farther along the route can also prevent safe access.

With all field creature zones avoided, 235 of 252 otherwise reachable stock
single and multiplayer scroll and artifact sites lost their route from every
opening hero or castle approach. This happened at 9 of 336 generated sites,
counting legal harbor transfers. In the generated sample, all 756 opening
economy and recruitment targets remained reachable from their own starting
hero by land. These are mission-start routes on an explored board.

The stock single and multiplayer missions also have about 22–24 creatures
per thousand passable land tiles at the median map. Generated maps have
about six. Stock guards within twelve tiles of a starting hero or castle
have median creature level two in both groups, rising to four farther out.
In the generated sample, the median rises from two to three on land and
stays at two on naval maps. The nearest other creature is typically five
or six tiles away in stock missions, five on generated land maps, and ten
on generated naval maps. About 45% of stock single and multiplayer creatures
match the faction of their ground tile, compared with 49% in the generator.

Two stock spot checks reproduced the geometry in the game's pathfinder. In
`pmission02`, the Medium Tick Hive at `(37, 30)` closes a crossing with its
interception zone, and the Lake Snake at `(57, 100)` does the same in
`mmission01`. Each has a geometric path around its occupied tile that
enters the zone. Removing the guard opens a fight-free route.

Stock placement uses creatures for encounters beside roads, shortcuts through
narrow passes, and prizes with guarded entrances. Generated v8 mostly places
creatures near side objectives and leaves several ways to approach. The opening
economy and recruitment routes are especially well protected from interception.

### Guarded prizes and room between sites

Version 9 places fewer frontier mines, service stops and supply piles, and
leaves more space between optional sites. Each homeland has one larger
starting cache and its complete starting economy. Frontier supplies are more
occasional, and one reward guard can have a single nearby cache. The scenery
setting still controls trees, rock formations, and other decoration.

Across the same 22 matched maps, the median count of interactable sites fell
from 155.5 to 97, excluding starting heroes and castles. The typical
interactable site had three other sites within six tiles in version 8 and
one in version 9. In the actual movement grid, 149 of 151 optional scrolls
and artifacts had every usable approach covered by their assigned field
creature. Version 8 had no such prizes in this sample. Recruitment scrolls
remain part of the starting progression.

### Whole-map access

Version 9 checks every passable tile after placing scenery. It opens short
connections around buildings and through decoration, and adds a legal
landing when a dry part of a naval map lacks a route. A shore at a guarded
prize has a clearing around its approach so the route is visible at normal
camera angles. Water on overland maps and the occupied footprints of static
objects are outside the walkable grid.

All 192,806 passable tiles across the 22 final maps belonged to their map's
travel network after creatures and heroes were cleared for the test. All 756
opening economy and recruitment targets also had a land route from their
own starting hero with every creature zone still active.

## World configuration

These are the keys accepted by `ELFirstRandomMap.generate(profile, options)`.
Omitted keys use the defaults below.

| Key | Default | Supported values and effect |
| --- | --- | --- |
| `version` | `9` | `9` adds guarded prize entrances and fewer, more widely spaced interactable sites. Versions 1–8 reproduce their original worlds. Version 1 uses its own schema. |
| `seed` | `"212"` | A string of 1–64 characters, not blank-only, without control characters. Whitespace in a valid seed is significant. |
| `size` | `96` | `64`, `96`, `128`, `160` tiles per side. |
| `players` | `4` | `2`, `3`, `4`: one human and the remaining seats controlled by AI. |
| `layout` | `"frontier"` | One of the eight layout identifiers listed above. |
| `biome` | `"mixed"` | `"mixed"`, `"Green"`, `"Blue"`, `"Red"`, `"Black"`: regional faction terrain or one terrain family. |
| `resources` | `"normal"` | `"scarce"`, `"normal"`, `"rich"`: frontier economy and cache abundance. Essential opening sites are retained. |
| `starting_resources` | `"normal"` | `"scarce"`, `"normal"`, `"rich"`: initial treasury, applied equally to every player. |
| `guards` | `"normal"` | `"none"`, `"normal"`, `"strong"`: neutral guard presence and strength. |
| `faction` | `"Green"` | `"Green"`, `"Blue"`, `"Red"`, `"Black"`: Vitals, Kinets, Chaots, Synthets. The human is player 1. |
| `roads` | `true` | Boolean; generated road ribbons and their normal land movement bonuses. |
| `scenery` | `1` | `0` skips decorative terrain props, `1` adds groves, rock formations and roadside scenery, and `2` fills more of the available land. |
| `castle_health` | `30` | `20`, `30`, `60`: starting and maximum castle energy for every player. |
| `naval` | `false` | Boolean; enable navigable seas and explicit harbors. |
| `water` | `"normal"` | `"low"`, `"normal"`, `"high"`: relative water coverage. |
| `coast` | `"rugged"` | `"smooth"`, `"rugged"`: coastline variation. |

Unknown keys, unsupported values, incorrect types and fractional integer
settings are rejected. Integral finite JSON numbers are accepted for integer
fields; booleans are accepted only for boolean fields.

**Game difficulty**, **Duel AI** and **World AI** use the existing game options
and are separate from the map recipe. Original, Smarter and Living world AI all
use the naval route system. Their usual differences in economic planning,
exploration and combat priorities remain. The existing **AI fights neutral
monsters** option also keeps its normal rules.

## Share and remember a setup

**Copy setup** creates an `EL1R9:` code for a new world in the code field and clipboard. Paste a
complete code and press **Load setup** to restore its seed and world settings.
Choose difficulty and AI separately. The code is a prefix followed by Base64
encoded UTF-8 JSON; it is a recipe, not a map archive.

`EL1R1:` through `EL1R8:` codes reproduce their original worlds when loaded and played
without editing. Changing a world setting or choosing a new preset switches to
the current generator.

The last launched settings carry forward to the current generator in
`user://el1_random_map_setup.json`. Plain JSON examples are in
[`examples/first_random_maps/`](../examples/first_random_maps/). Neither action
modifies the installed original game's files.

## Developer API

```gdscript
var generator := ELFirstRandomMap.new()
var map := generator.generate(profile, {
    "version": 9,
    "seed": "island-expedition",
    "size": 128,
    "players": 4,
    "layout": "archipelago",
    "biome": "mixed",
    "resources": "rich",
    "starting_resources": "normal",
    "guards": "normal",
    "faction": "Blue",
    "roads": true,
    "scenery": 1,
    "castle_health": 30,
    "naval": true,
    "water": "high",
    "coast": "rugged",
})
if map == null:
    push_error(generator.error)
    return

var session := ELAdventureSession.new()
if not session.start(map, 2, ELFirstRandomMap.seed_for_config(generator.config), "", 1, false):
    push_error(session.error)
    return
var director := ELAdventureDirector.new()
if not director.build(session):
    push_error(director.error)
    session.close()
    return
```

`generate()` returns an `ELAdventureMap`, or `null` with a readable `error`.
`config` contains the canonical complete recipe. `report` includes starts,
object counts, water fraction, landmasses, ports, sea connectivity and the map
fingerprint, as applicable to the selected generator version.

| Helper | Result |
| --- | --- |
| `ELFirstRandomMap.defaults()` | Current defaults. |
| `ELFirstRandomMap.defaults(version)` | Defaults for the given generator version. |
| `ELFirstRandomMap.presets()` | Current preset names, descriptions and option overrides. |
| `ELFirstRandomMap.normalize(options)` | Complete validated recipe, or an empty dictionary on failure. |
| `ELFirstRandomMap.id_for_config(options)` | Deterministic identifier safe for the existing engine. |
| `ELFirstRandomMap.seed_for_config(options)` | Deterministic session seed. |
| `ELFirstRandomMap.configuration(map)` | Copy of the generated map's immutable recipe. |
| `ELFirstRandomMap.content_hash(map)` | Fingerprint of the immutable generated source state. |
| `ELFirstRandomMapScreen.preview_image(map)` | A schematic `Image`. |

The frontend launch signal carries `scenario.random_map`. The adventure view
generates that recipe before starting the usual EL1 session. Harbor metadata
and runtime navigation APIs are documented in [Naval maps](first_naval_maps.md).

## Determinism, saves and compatibility

Generation uses a private integer PRNG, sorted content keys and its own terrain
noise. It does not consume the gameplay RNG or Godot's global random stream.
The complete normalized recipe determines the map ID. Reproduction requires
the same recipe, generator version and compatible installed content.

Final validation checks terrain transitions against the installed tileset,
object footprints, essential site approaches and the actual navigation grid.
Naval generation also validates harbor transitions and the navigable sea
network. A world that cannot satisfy these requirements reports an error at
generation rather than starting with inaccessible required content.

Generated saves embed a versioned recipe and content fingerprint. Loading
regenerates the immutable world, verifies its identity and fingerprint, then
restores mutable objects, ownership, fog, turn state and any battle. For naval
games this includes hero ship state and queued travel, including a voyage
paused at sea. Harbors are reconstructed from the same recipe and covered by
the generated document's fingerprint. No separate generated map file is needed.

Version 6 records terrain elevation in its generated-map fingerprint.
Movement still follows terrain and road costs. Saves from each version
regenerate with their original rules. Missing recipe fields, unsupported
versions or incompatible generated content produce a load error.

Ordinary campaign/custom maps retain their existing behavior. This feature does
not add random maps to the multiplayer lobby or export original-editor
`.map`/`.ebm` packages.

## Validation and reproducible checks

Run with Godot 4.7 from the repository root. The first command imports a fresh
checkout and builds its global class cache. Use a separate user-data directory
for save and UI checks so your normal preferences remain separate.

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script ../tools/first_random_map_check.gd
godot --headless --path game --script ../tools/first_random_map_shapes_check.gd
godot --headless --path game --script ../tools/first_random_map_ui_check.gd
godot --headless --path game --script ../tools/first_random_map_roads_check.gd
godot --headless --path game --script ../tools/first_naval_check.gd
godot --headless --path game --script ../tools/first_naval_battle_check.gd
godot --headless --path game --script ../tools/first_naval_exploration_check.gd
godot --headless --path game --script ../tools/first_naval_visuals_check.gd
```

The main property suite accepts `-- --stress` and an optional installed-content
pass, `-- --el1=/path/to/Etherlords`. The shape suite supports `-- --quick` for
a smaller matrix. `first_naval_check.gd -- --runtime-only` skips its generated
save section during focused runtime development.

The automated suites execute the real generator, grid, director, AI, fog,
save and duel code using synthetic content. The fog exploration check starts
the foreign island and its objective unseen, then requires actual AI sailing,
landing and capture through normal day turns. Battle checks prepare and play
EL1 duels for open-water and harbor-edge encounters.

Use the installed-content pass to exercise real terrain, table definitions,
navigation and checkpoint regeneration. It checks the new forts and guard
zones in a land and a naval mission, including guard-free land approaches
to each player's opening sites. Pass the same `-- --el1=...` argument
to `first_random_map_ui_check.gd` to test the entry point in the installed
game's Single Mission menu.
