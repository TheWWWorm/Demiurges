# Naval maps in Etherlords I

Naval random maps connect land regions through real water routes. Human and
computer heroes walk to a harbor, change to ship form, sail, and land at another
harbor before continuing their normal objectives. Movement, occupancy, action
points, fog, battles and saving all use the adventure runtime.

## Choose and start a naval world

Open **Single Mission → Random map…** and choose **Island chains** for a world
where ships are essential. **Inland sea**, **River delta**, **Ring of kingdoms**,
**Peninsulas** and **Lake country** also enable ships in their presets.

In the **World** tab, check **Enable ships and harbors**. Adjust water coverage,
coastline, size and other settings, then generate a preview and play. Choosing
a different layout manually leaves the checkbox at its current value. The full
schema and preset list are in [Random maps](first_random_maps.md).

Your own Etherlords I files are required for the terrain, creatures, spells,
objects and normal game content. Etherlords II is optional: if its mounted
content provides the boat model `he551` and texture `Heroes/Boat00`, naval heroes
use that appearance. Otherwise they use the included wooden sailboat model,
with a faction-colored pennant. This source choice is independent of the
separate preference for using second-game dome art. No original assets are
redistributed with the release.

## Sail with the usual movement controls

1. Select a hero and click a reachable destination, including one across the
   water. The route includes the necessary harbors automatically.
2. With free movement enabled, click the planned destination again to execute
   it. With ordinary end-of-day movement, finish your orders and use **Next
   day** (`N`).
3. The hero walks to the harbor, boards while crossing its land-to-water edge,
   and continues along the sea route in ship form.
4. At the destination harbor the hero lands, changes back to the normal hero
   model, and continues inland if movement points permit.

`Backspace` cancels the selected hero's current order. Harbors are marked by
piers and beacons in the world and cyan marks in the setup preview. They are
part of the route; no separate harbor dialog or boat purchase is required.

You can embark and land only across the two adjacent cells of a registered
harbor. An ordinary beach, including a diagonal coastal corner, is not a
boarding point. Different harbors are open to every player; the faction marker
identifies the homeland, not exclusive access rights.

### Movement costs

| Move | Action-point cost |
| --- | --- |
| Walk to another land cell | That destination cell's normal EL1 terrain/road cost. |
| Sail to another water cell | 1 point. |
| Board from the harbor's land cell | 3 transfer points + 1 point for the water destination: 4 total. |
| Land from the harbor's water cell | 3 transfer points + the destination land cell's normal cost. |

For example, landing on ground that normally costs 2 points costs 5 points in
total. A hero with only 4 points remains aboard until enough movement is
available. Transfer costs are charged once, on the actual crossing. A route's
displayed cost includes those crossings.

Long voyages retain their orders across days. If a hero runs out of points at
sea, the hero stays on that cell in ship form and can resume after the normal
daily refresh. An occupied next cell or a newly blocked harbor stops movement
safely; the hero does not overlap the obstruction or receive a free crossing.

### What a ship represents

A ship is the hero's travel form, following the existing EL2 representation.
The hero remains the same actor, with the same owner, spellbook, experience,
health, resources and current order. Harbors supply the transport when the hero
boards. Landing returns the hero to its normal form.

There is no independently selectable fleet, passenger roster, ship inventory or
abandoned boat at the departure point. A vessel is not left behind and reused
while its hero is somewhere else. The persistent state is the hero's actual
position and `ship` flag.

Existing recall, resurrection, fort and scripted-placement mechanics preserve
their own rules and update travel form to match the resulting placement.
Recall or recruitment beside a castle places the hero on valid land. A sailing
hero must land before entering a land fort.

## Battles, blockades and land objectives

Sailing heroes can engage other adjacent sailing units. A hero or monster
occupying one end of a harbor can also be attacked from its other end: a ship
can contest an enemy blocking the landing, and a hero on shore can challenge
the ship at that harbor. This exception applies only to the exact registered
harbor edge, not to arbitrary adjacent coast cells.

The winner stays on the cell from which the battle began, in the corresponding
travel form. Winning a landing battle does not automatically move the ship
ashore or waive its landing cost. The defeated actor stops blocking movement;
the survivor can then cross normally if the cell is free and the remaining
movement budget permits.

Mines, shops, buildings and castles remain land objectives. A hero must land
before capturing, visiting or besieging them. Diagonal approaches from the
water do not bypass this rule. The ordinary diplomacy and interaction checks
still decide which hero interactions are available.

Combat uses the normal EL1 hero templates, spellbooks, runes, difficulty and
duel engine. When Etherlords II is installed, a battle in which either side is
at sea takes place in its `Ship.001` arena. Without it, open-water terrain
selects the existing EL1 `Ether.001` arena and shore battles select the normal
EL1 terrain arena. The arena does not change the hero's battle rules, and a
hero at sea keeps their own portrait. The battle test prepares actual duels for open-water combat and
both directions of a harbor assault, casts a spell, advances phases, restores
a duel snapshot, and returns the result to the adventure map.

## Computer players and fog

Original, Smarter and Living world AI use the same legal land/sea graph and
movement costs as human heroes. Their existing priorities decide what to
explore, capture, buy, fight and defend. The route planner can connect those
objectives across islands through explicit harbors, and execution uses the
same occupancy checks and action-point budget as player orders.

Unknown terrain is not treated as an already known route. Computer exploration
can travel to a visible frontier at sea, reveal more of the water and distant
shore through ordinary sight, and then pursue the newly reachable objective.
The focused exploration regression starts an opposing island's harbor and mine
unseen and requires both Original and Smarter AI to sail, land and capture the
mine through real day turns without revealing the map by console or test setup.

Ships reveal their surroundings through the normal hero sight rules. Harbor
geometry stays hidden until both its endpoints have been explored and is dimmed
when remembered outside current sight. The setup preview shows the complete
world intentionally; its information is not transferred to the in-game fog.

## Saves and older maps

Save, quick-save and ordinary generated-game loading use the existing mission
save interface. A generated save embeds its recipe and source fingerprint,
then stores the mutable session state. Loading reconstructs the same harbors
and terrain before restoring actors, exploration, orders and battles.

Ship flags and active movement paths are validated. A living placed hero cannot
load as a ship on land or as a walking hero on water. Mid-voyage saves retain
position, current movement points and queued destination. The boat appearance
is selected from the available local assets when the scene is built; the save
does not contain copyrighted model files.

Naval movement is explicitly enabled for these maps. Ordinary EL1 campaign and
custom maps keep their existing land rules, and EL2 retains its own movement
and dock behavior. Version-1 random recipes still use the preserved version-1
generator and its original overland geometry. To make a new naval world, use a
current setup with ships enabled.

## Troubleshooting

| Observation | What to check |
| --- | --- |
| There is water but no sailing route. | Confirm **Enable ships and harbors** is checked. A changed layout alone does not enable it. Use a naval preset to start. |
| Clicking a destination shows a route but the hero stays still. | The first click plans the order. Click the planned destination again in free movement, or resolve the next day. |
| A ship stops beside a landing. | Landing requires 3 extra points plus the land tile's cost. Check the remaining budget and whether another actor occupies the landing. |
| A visible beach cannot be used. | Embark and land at a marked harbor; ordinary coastline is not a transport connection. |
| A harbor is blocked by an enemy hero. | Attack across its registered harbor edge, or use another harbor. A victory still leaves the normal landing move to be paid. |
| A distant island is not yet a valid known route. | Explore the sea and its shoreline so the route becomes known. |
| The boat differs from the original EL2 model. | The fallback sailboat is used when the optional EL2 boat assets are unavailable. EL1 naval rules still work. |
| A generated save reports a fingerprint mismatch. | Load with the generator version and compatible installed content that created it; do not edit the recipe or saved actor state. |
| Generation reports that a valid placement could not be found. | Try a new seed, a larger map or less scenery. A rejected generation has not started a broken mission. |

## Developer integration

### Opt-in and harbor metadata

`ELFirstNaval.enabled(map)` applies only to an EL1 profile. It recognizes the
versioned `first_naval` metadata or a generated recipe with `naval: true`.
Navigation initialization still requires valid explicit harbor metadata; setting
the recipe flag alone does not manufacture a coast connection.

```gdscript
map.set_meta("first_naval", {
    "version": 1,
    "water_type": 16,
    "ports": [
        {
            "id": 0,
            "land": [22, 16],
            "water": [23, 16],
            "island": 0,
            "owner": 1,
            "name": "West harbor",
        },
    ],
})
```

The metadata's schema version **1** is separate from random-map generator
version **2**. `ports` must be a nonempty array. Each `land`/`water` value is a
two-element integer array within map bounds; endpoints must be cardinally
adjacent, correctly classified and passable. Static object footprints cannot
block either endpoint. Dynamic occupants are allowed and can block or contest
the harbor during play. IDs, island indices, owner and name describe generated
ports; owner does not restrict access.

EL1 terrain is stored at cell corners. A naval cell is water when any of its
four corners is terrain type `16`; this includes the mixed shoreline cells and
prevents an impassable seam between pure land and deep sea. Other impassable
terrain corners remain blocking. A land endpoint must contain no water corner.
The `water_type` field documents the fixed EL1 type; it is not a configurable
alternate terrain-class mechanism.

The generator also writes a canonical copy of the harbor payload into the map
document. That copy contributes to `content_hash()` and is regenerated with the
saved recipe. Setting metadata on an in-memory map is a runtime integration
hook, not a new import/export format for the original editor.

### Navigation and state APIs

| API | Purpose |
| --- | --- |
| `ELFirstNaval.enabled(map)` | Check whether the explicit EL1 naval rules apply. |
| `ELFirstNaval.is_water(map, point)` | Classify a cell using its terrain corners. |
| `ELFirstNaval.terrain_cost(map, point, blocked, ship_only)` | Compute destination terrain cost; negative means impassable. |
| `ELFirstNaval.connected(grid, from, to, actors, planning)` | Validate a single edge's geometry and diagonal clearances, including exact harbor transitions. Destination occupancy is the caller's separate responsibility. |
| `ELFirstNaval.step_cost(grid, from, to, actors)` | Validate the move and destination passability, including the transfer surcharge; negative means illegal. |
| `ELFirstNaval.interaction_mode(grid, point, target)` | Enforce land-object approaches and the harbor-edge unit interaction exception. |
| `grid.path(from, destination)` | Find a complete walking/sailing route on an enabled map. |
| `grid.approach(from, target)` | Find a legal interaction approach, respecting target mode. |
| `grid.path_cost(path)` | Sum actual per-edge costs, including boarding and landing. |

On a naval map, `grid.land` is the combined traversable land/sea mask used by
the existing fog and guard closures. `grid.water` remains the water-only mask.
Do not call its raw AStar search or flood directly across neighboring cells:
the legal edge relation must also apply, or the code could cross an unregistered
shore. The ordinary nonnaval grids keep their previous semantics.

The naval route search uses deterministic A* with a binary heap and supports
multiple approach goals. It respects the temporary planning mask for unknown
terrain and guard avoidance. Actual movement rechecks collision and budget
before taking each edge; a cached route is not permission to ignore new actors.

The director updates the hero's `ship` flag on the actual crossing and emits
the usual model-change and dock presentation events after charging movement.
Saving uses this actor state rather than a separate detached-vessel registry.
AI objectives continue through the existing planner and strategy-order system.

## Verification scope

The automated suites cover actual routing, free and end-of-day human movement,
multiple-day voyages, Original and Smarter AI voyages and unknown-fog
exploration, blocked harbors, budget accounting, naval save restoration,
ordinary-map compatibility, boat/dock presentation and actual EL1 duel
construction. They use synthetic content and the production runtime.

See [Random maps](first_random_maps.md#validation-and-reproducible-checks) for
the regression commands and the installed-content generation check.
