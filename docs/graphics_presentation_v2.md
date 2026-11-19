# Second pass: lightweight visual polish

> Historical V2 notes. Current cumulative implementation and executed validation
> are described in `graphics_presentation_v4.md` and the V4 package validation report.

The source changes are cumulative over the earlier presentation package. For the
original shading and material improvements, see `graphics_presentation.md`.

## Architecture

### `ELArenaDust`

Created by `ELArena.build` once a surface exists, with a palette derived from
arena family (`Green`, `Red`, `Blue`, `Black`, cities, dungeon/fort, ship, ether).
It uses one dynamically updated `MultiMesh` with 64 camera-facing unlit discs
and a cached, procedurally generated 32 px alpha texture. Positions are seeded
by the scene ID so revisiting an arena produces the same distribution. The
centres sit above the arena's `ground_height()` and drift a small amount within
bounds, at a capped 15 Hz instead of every display frame. Per-instance opacity
stays low so motes cannot fill the board with opaque noise.

`ELArena._sync_atmosphere_light()` supplies a bounded RGB gain already used by
enhanced water and low fog. The gain dims the new motes too. Disabling the
**Arena atmosphere** preference hides the mesh and stops processing. The
renderer marks these motes `raster_only` and ELPathTracing's scene collector
skips them, so they never consume BVH triangles or ray atlas entries.

### `ELCombatImpact`

This node is attached to the duel stage or Autochess board on a concrete hit
or heal event. It creates one shared alpha texture representing a short radial
ring, cross-spokes and an inner soft core, used by simple unlit `Sprite3D`
instances. Hit instances are amber, heal instances green, with scale and opacity
changing over a 0.36–0.48 second lifetime. An upper limit of 28 active
instances per host is enforced before adding another, and each frees itself.

Texture generation is prewarmed on entering a battle to avoid a first-hit CPU
cost. The optional **Impact accents** switch prevents new instances from being
created; old, in-flight accents expire naturally. The system does not modify
the original hit sounds, animation clips, blood events or game state.

### Remaining polish

`ELArena` selects 4-split, blended shadow cascades in Forward+, retaining two
cascades in other raster renderers; the preference and path-tracer shadow
ownership logic remain the same. `ELCombatSymbols` draws subtle ink backing
behind numeric/status strips and adds a 0.18 second launch size impulse to
floating numbers. `ELCombatBlood` randomizes the planar yaw of each footprint
without changing source atlases or the print pool. `arena_sea.gdshader` adds
filtered, low-contrast interference to enhanced Ship water, preserving the
original deck/sea UV split.

## Tests

With the project's Godot 4.7 runtime:

```sh
godot --headless --editor --path game --import
godot --headless --path game --script ../tools/graphics_second_pass_check.gd
```

The new suite performs resource, motes, palette, update, light gain,
background/foreground and hit-pulse lifecycle checks without original assets.
The v1 suites should be rerun too. No test here establishes the final colour,
frame rate or compatibility of actual original models and animations. V2 engine
validation was unavailable during preparation, so failures and refinements may
still be found in Godot 4.7 or on particular hardware.
