# Graphics presentation V3

> Historical V3 notes. The current cumulative implementation and verification
> are described in `graphics_presentation_v4.md` and the V4 package validation report.

Prepared 18 November 2026 for Demiurges 0.18.5, based on commit
`0dc8ff683eaf35942e457f94bdbbbc870b4e7f44`.

This is a cumulative source update. It retains the first two presentation
passes and extends the work to strategic-map markers, fogged ground shadows,
reflections, particle filtering and culling, dynamic spell lighting, and
post-processing. It also corrects rendering defects in the previously unrun
V2 additions. No original-game installation, models, textures, maps, sounds,
or other original data were used or included.

## Strategic-map selection rings

`selection_ring.gd` and `selection_ring.gdshader` use the existing selection
art. Consecutive frames blend continuously while preserving the 32-frame,
64-millisecond-per-frame cycle. Frame 31 wraps to frame 0 inside the current
race colour's half of the atlas. The danger pulse retains its period and
extremes but now moves continuously between its original ticks.

Each frame sample stays within its own half-texel boundaries. Frame colours
are blended with premultiplied alpha, avoiding a dark fringe when one frame
contains a transparent pixel and the next contains artwork. A narrow dark
contour follows the original silhouette to improve contrast on bright ground.
The centre stays transparent; marker sizes and input behavior are unchanged.

Bilinear texture filtering happens before the shader receives a sample.
Therefore the two selection atlases also receive private RGB edge repair,
one frame at a time. Repair cannot borrow another frame or race's colour.
The original texture, visible pixels, and every alpha value remain unchanged.
The prepared texture is cached on its source resource, so it is reused without
an unbounded global cache. Irregular atlas dimensions retain their original
texture. The shader does not use mipmaps, matching the original ring sampler.

Cost: up to ten texture samples per fragment on the two marker quads, and one
prepared copy per selection atlas. These are small local markers, not a
fullscreen effect. The repaired copy is prepared once, not every frame.

## Fog and pickup shadows

`adventure_blob_shadow.gdshader` samples the same fog masks and interpolated
fade as the terrain. A shadow no longer remains fully dark over a ground area
still covered by mist. Complete fog suppresses it; revealing terrain brings
it back gradually. The ordinary shadow switch still disables the layer.

Both modelled and instanced pickups now shrink their separately batched blob
shadows with the existing pickup retirement animation. The shadow's local
offset shrinks with its footprint, and completion hides it as before.

## Water reflections and map material ownership

`adventure_terrain.gd` keeps atlas pixels, composition plans, and generated
water/colourless masks reusable, while each live map view owns its material.
Fog, sunlight, colourless state and a live reflection texture no longer share
mutable material state across reopened or overlapping map views.

Reflection changes include:

- At most 2x MSAA when the main viewport uses MSAA; AA off remains off.
- The existing reflection resolution cap remains in place.
- Mirrored asymmetric frustum offsets and camera-specific environments.
- Disabled rendering and released sampler bindings on removal from the tree.
- Rebinding the existing viewport on re-entry, including a changed World3D.
- Disabled reflection rendering when enhanced water is off or water is out of view.

This does not add another reflection pass. It refines the existing enhanced
water option. Reflection MSAA adds GPU work when AA is enabled; actual-game
performance was not measured on a hardware GPU.

The first game's map sun is rotated relative to the second game's sun.
Terrain detail and enhanced-water highlights now receive the actual sun
direction, instead of retaining the second game's default vector.

## Particle atlases and culling

`particle_file.gd`, `combat_effects.gd`, and `adventure_effects.gd` now protect
animation atlas frames both when enlarged and when minified. A half-texel
clamp alone is insufficient: a lower mip may already average several frames.
The shared sampler calculates the last mip whose texels align with the frame
grid, stops there, and constrains each sample to that mip's frame interior.
Fractional mip levels interpolate between two independently bounded samples.

This applies to combat sprites, adventure sprites, and their shadow-only
twins. Source images, existing mip bytes, frame indices, and animation timing
remain unchanged. Single-frame sheets retain their ordinary sampler. For
multi-frame sheets, magnification and exact mip levels use one fetch;
fractional minification uses two. Soft-particle and additive-light behavior
continues through the existing shader functions.

Combat material-cache keys now include the atlas grid dimensions. Effects
sharing an image but using different frame grids no longer share an incorrect
material. Private fading materials inherit the corresponding mip limit.

Adventure effects use cached bounds calculated from their complete decoded
animation, including the full billboard diagonal. Negative recorded sizes
are treated by magnitude, as in rendering. The same bounds serve the GPU and
manual culling. This keeps broad sprites visible when their centres are just
outside the view and avoids the former fixed, arena-sized box on small effects.
The scan occurs once during the existing preparation path.

Cost: the additional minification sample can matter for a screen filled with
large transparent effects. The software-renderer checks establish correctness,
not real-game frame-rate improvements.

## Dynamic spell lighting

`glow_lights.gd` preserves the six-light budget and limits the actual pool to
six OmniLight3D nodes, including fading slots. It matches continuing sources
before recycling any other slot, so a new spell cannot steal the lamp still
needed by another source. Spell, character-aura and standing-fire priorities
remain distinct even when their positions overlap.

A newly arriving spell can take a slot when all six slots contain lingering
character glows. Other auras keep their slower fade when space permits. A
spell beside a bright standing fire remains eligible for its own lighting and
shadow instead of being merged into the fire's non-shadowing classification.

The current shadow-casting spell keeps the shadow until another eligible lamp
is over 25% brighter in its actual smoothed energy. This prevents small
particle fluctuations from moving the shadow back and forth. A clearly
brighter spell takes over, and a vanished source immediately yields. There is
still at most one spell shadow in a supported renderer, and none for these
lights in Compatibility. Existing path-tracing suppression is unchanged.

## Sharpening

The optional sharpening pass in `sharpen_layer.gd` now bounds its result by
the local neighbourhood's colour range. Soft texture details still gain
contrast, but flat high-contrast edges no longer acquire artificial light or
dark outlines. Off still skips the pass; the default is unchanged.

Tests cover interface exclusion and simultaneous gamma adjustment. The
existing gamma composition passed in both renderers without an extra copy,
so `gamma_layer.gd` was left unchanged.

## Corrections to V2 atmosphere and impact accents

### Arena motes

`arena_dust.gd` now preserves each MultiMesh instance's scale during
billboarding. The previous material could turn centimetre-sized motes into
much larger translucent cards. The procedural disc now has mipmaps and
rotation/drift-aware bounds, and is excluded from shadows and GI.

Arena lighting supplies a linear RGB multiplier. It is now encoded for the
StandardMaterial3D colour property exactly once, so a quarter-light arena
produces approximately quarter-light mote brightness instead of excessive
darkening. The original palette and opacity remain separate.

`arena.gd` creates the mesh lazily when Arena atmosphere is enabled. Off does
not allocate it or run its terrain-height queries. A later enable immediately
receives the arena's current lighting. Cached Autochess arenas reuse it.

Directional-shadow splits now distinguish desktop Forward+'s four-cascade
layout from the two-cascade layout on lighter renderers. The latter receives
a suitable wider near region instead of reusing the four-split near fraction.

### Impact accents

`combat_impact.gd` keeps at most 28 nodes per stage/board, including inactive
ones. Finished accents hide and stop processing; future hits reuse them. At
saturation, the oldest accent is recycled for the newest event. Even a large
single-frame burst does not allocate a growing set of queued sprites. No
global node cache retains a finished stage.

Hit/heal textures now have mipmaps. Shared body-point placement prefers the
authored soul anchor; otherwise it uses the visible body's current posed
bounds, excluding helper anchors. The point is transformed into the receiving
stage or board's coordinates. This supports differently scaled, nested, and
flying models instead of applying a fixed Autochess height.

The lifetime, colour distinction, original hit/heal timing, sounds, and
underlying original effects are retained. Turning Impact accents off prevents
new accents while existing ones finish normally.

### Blood

The varied stain yaw introduced by V2 now derives from existing visual state
without advancing the established blood RNG stream. An independent seeded
comparison against the delivered V1 renderer matched every drop, every print
field except yaw, and the ending RNG state across two successive bursts.

## Retained earlier improvements

The cumulative package also retains the earlier prepared morph normals,
cutout coverage mipmaps, preserved greyscale alpha chains, alpha-aware model
hit flashes, optional terrain relief, filtered water, light-aware water/mist,
combat selection markers, readout contrast and number motion, interpolated
blood, optional Forward+ contact shading, and consistent live graphics
settings across duel, map and Autochess views.

The earlier documents are historical descriptions of their respective passes.
Use this document and the package's `validation/RESULTS.md` for the current
implementation and verification status.

## Verification and its limits

The package contains ten asset-free presentation suites, plus the existing
effect-look and path-tracing-budget checks. They run with the matching Godot
4.7 runtime. Real OpenGL Compatibility and Vulkan Forward+ render passes
compile the actual shaders and compare captured pixels on generated fixtures.
See `validation/RESULTS.md` and `validation/results.json` for the exact final
counts, commands, logs, and measured examples.

Typical local commands, run from the repository root:

```sh
godot --headless --editor --path game --import
godot --headless --path game --script ../tools/adventure_presentation_check.gd
godot --headless --path game --script ../tools/effects_presentation_check.gd
godot --headless --path game --script ../tools/graphics_second_pass_check.gd
godot --headless --path game --script ../tools/lighting_presentation_check.gd
godot --headless --path game --script ../tools/post_processing_check.gd
```

For actual rendered probes, use a windowed renderer and add the test's
arguments after `--`:

```sh
godot --path game --rendering-method gl_compatibility --script ../tools/adventure_presentation_check.gd -- --render --shots=/absolute/output
godot --path game --rendering-method forward_plus --rendering-driver vulkan --script ../tools/effects_presentation_check.gd -- --render --shots=/absolute/output
```

No original game profiles were mounted. The supplied images are labelled
synthetic diagnostics, not original-game screenshots. Software GPU drivers
were used; original-art appearance, hardware frame rate, hardware ray tracing,
DLSS/FSR/frame generation, browser, and mobile behavior remain unmeasured.
The focused checks do not replace a playthrough with the original files.
