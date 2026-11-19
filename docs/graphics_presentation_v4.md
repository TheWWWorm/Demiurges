# Graphics and performance V4

Prepared 18 November 2026 for Demiurges 0.18.5, based on commit
`0dc8ff683eaf35942e457f94bdbbbc870b4e7f44`. This cumulative update retains V1–V3
and extends the source-only presentation work to rendering costs, model
playback, HUD updates and preview viewports. Original-game data was not used.

The applied 0.18.5 build restores the stock combat selection marker, floating
damage and healing numbers, and helper captions. It removes added impact
accents and arena motes. Overhead numbers draw each glyph once and use a
single unbordered backing per number row. Settled map fog fades retain their
shader value until the next change.

## Campaign script performance

The Lua interpreter records the current bytecode location and formats it only
when reporting an error. Static opcode dispatch now checks stack requirements
in place of repeated opcode-list tests. Script ticks, instruction limits and
nested interception keep their existing behavior. In a Vulkan Forward+ replay
of `e2mission12_52`, alternating the two interpreters in the same process
reduced average Lua hook time per frame from 1.65 ms to 1.21 ms and the
95th-percentile frame interval from 14.74 ms to 12.24 ms.

The same chapter’s opening dialogue was building thousands of morph normals
in its first visible frame. The camera approach now gives worker threads time
to prepare each deforming part of the speaking clip. The opening uses the
authored clip and the prepared mesh from the existing model cache.

## Animation playback and mesh memory

`figure.gd` prepares coordinate-converted position/scale keys and normalized
quaternion keys during the existing animation decode/warm-up path. Instances
share these immutable prepared arrays. Exactly repeated channels retain one
prepared value, while the original channel lengths and encoded bytes remain
available. Playback no longer decodes the same floats and normalizes the same
quaternions for every model part on every sample.

Fractional interpolation, uneven channel lengths, held final keys, missing
channels, event timing, hidden-pose catch-up and playback speed are retained.
The new asset-free suite compares against the V3 byte-sampling algorithm and
renders both rigid and morphing meshes on both renderers.

`model.gd` now creates clip-specific meshes only for actual vertex deformation.
Rigid parts reuse their existing base `ArrayMesh`; idle, movement and attack
clips no longer each own another copy of identical geometry. Morph playback
zeros only departed blend shapes and reuses its two active-frame indices.

That reused pair must not be borrowed by a frozen afterimage. The actual
`MovementTrail` implementation in `melee_playback.gd` now copies the pair when
capturing a snapshot. Recycled afterimages clear their own previous weights;
the established three-snapshot budget and source-destruction behavior remain.

Cost: an additional shared set of transform keys per decoded track. Repeated
channels compress to one value; removing duplicate rigid clip meshes reduces
mesh allocations. No visible animation-rate reduction is used.

## Arena ground queries

`ground_height_index.gd` indexes the arena's authored triangles into a bounded
grid on first use. `arena.gd` reuses the index until its ground model changes.
Grounding figures, probing a clear spawn position, positioning markers and
placing atmosphere use local candidates instead of rescanning every triangle.

The index preserves source order, so overlapping surfaces return the same
first hit as before. Degenerate triangles use the same rejection threshold.
Its bounds include the full original barycentric edge tolerance; simply
indexing unexpanded triangle AABBs would miss some accepted edge points.
Outside points retain the original zero-height fallback.

Cost: one lazy preparation and copied triangle positions plus bucket indices
per arena. Grid dimensions adapt to large geometry rather than allocating
one cell per square world unit. Very large triangles can occur in many
buckets; the benchmark reports preparation separately from query time.

## Strategic-map HUDs and minimaps

The first game's HUD previously scanned the object collection separately for
the hero roster, income, each of five building categories, the selected
building category and minimap invalidation. `_refresh_overview()` combines
these into one pass. It reads the current dictionaries each refresh, retaining
immediate script changes without depending on a new invalidation event.

It also prepares the small castle/site/actor marker lists, so minimap drawing
does not scan decorative scenery three more times. Roster order, building
order, production calculation and resource caps match the original helpers.
Assigning an unchanged tab's active state no longer queues a redraw.

Both HUDs include visibility, placement, ownership and player-colour changes
in their minimap drawing keys. The first game's key also includes fortification.
These changes prevent stale dots when an object disappears without moving.
The second game's key uses compact numeric values instead of concatenating
a growing string. Its existing selected-hero arc is antialiased.

The first-game minimap uploads only fog masks whose bytes changed. Movement
that only changes current sight leaves its explored-mask texture untouched.
Changing the current player updates the shader's bit even if the fog revision
did not change. Both HUDs hide their fog overlay for the existing console
reveal and restore it afterward; the second game's old unchanged-image path
failed to update visibility. Hidden overlays defer image uploads.

## Fog viewport scheduling

The fog shader receives an integer blend weight. `fog_mist.gd` now requests
one viewport render only when that byte weight or its noise grids change.
At high display refresh rates, identical intermediate images are retained.
With FogAnimations disabled, the unchanged texture is rendered once; terrain
drift remains independent and continues at the original rate.

`adventure_scene.gd` suspends mist output and drift-uniform uploads while the
map is hidden. The mist's original clock and noise RNG continue. Reshowing
the map requests its current image immediately. Disabling fog also disables
an already existing mist viewport. The existing pause/process-mode semantics
are retained.

## Particle preparation, uploads and cache ownership

Repeated map emitters share prepared combined loop buffers for the same
source and visible phase set. Glow extraction reuses that preparation too;
each emitter receives its own copy of the small glow records before applying
its colour/energy adjustment. The new per-map cache holds at most 8 MiB of
expanded instance buffers and 4,096 entries, plus entry/glow metadata. Source
instance IDs in its keys do not keep decoded files alive after their own
cache releases them.

The existing source-frame instance cache is retained. Testing a working set
larger than 8 MiB showed that removing it caused repeated per-particle script
decoding after combined-buffer eviction. The final implementation preserves
V3's preparation behavior for that case. The 8 MiB limit is the additional
combined-buffer cache, not a bound on all particle memory in the game.

The map renderer allocates each MultiMesh once using the exact largest number
of particles visible together across its looping phases. This replaces the
looser maximum-single-frame count multiplied by overlapping cycle count.
Closing-frame exclusion and finite tails use the existing playback rules.
Allocation stays stable throughout playback; varying particle counts do not
resize GPU storage each frame. Fewer unused capacity slots reduce padding
and upload bytes on effects for which the old bound was loose.

Adventure decoded-file caches now distinguish profile content generations,
like the battle renderer. A remount removes old pinned/LRU entries; an older
view cannot repopulate the newest generation. The new combined cache remains
owned by its live map and is released with it.

Hidden map effects, combat attachments and arena motes retain their clocks
without submitting invisible instance updates. Showing them resumes at their
current phase. Finite effects still expire while hidden. Scenery visibility
is applied after track opacity so an opacity update cannot reveal a hidden
effect prop.

## Blood rendering and lifetime work

Blood drops and stains now use the same protected atlas sampling as the other
particle renderers. Each four-by-four cell stays isolated when enlarged or
minified, including a mip limit before neighbouring cells have already mixed.
The authored texture, cells, colours, trajectory and fade timings are retained.
Fractional minification can require two texture samples, as in the V3 shared
particle sampler; this is a filtering-quality cost, not a GPU-speed claim.

The drop/print arrays compact in place. Empty layers stop processing and a
new burst wakes them. Hidden blood continues aging and simulating without
rebuilding visible instance data; reveal publishes the latest size/opacity.
Exact seeded comparisons retain V3's RNG state, ordering and mixed-delta
simulation behavior. The existing per-instance upload API remains: a proposed
GDScript bulk-buffer rewrite measured slower and was not included.

## Combat readouts, notices and cursors

`combat_symbols.gd` retains draw commands while figure data and camera/canvas
projection are unchanged. Visible moving anchors and floating numbers still
update at the display rate. Hidden floating numbers continue aging without
building draw commands, and empty readouts stop processing. Lifetime arrays
compact in place, and uniform-colour glyph rows avoid per-glyph wrapper arrays.
Offscreen rows are skipped with a margin for keylines and plates.

Icon hit testing identifies the relevant cell rather than allocating every
icon rectangle. Adjacent cells are checked at floating-point boundaries to
preserve the drawn `Rect2` hit behavior and nearest-figure precedence.

`combat_notices.gd` stops its frame callbacks after notices settle, retains
static icon history, and draws only visible history entries. Hover picking
uses the row index rather than scanning all recorded casts. It keeps original
notice lifetimes, transitions and scroll behavior.

`cursor_driver.gd` includes hotspot coordinates in its hardware-cursor cache.
Reusing an image with a different hotspot now updates the pointer correctly.
Hotspots are constrained to valid image pixels, including carried scroll
cursors at the screen edge.

## Autochess previews and still portraits

Hero busts and creature previews retain their canvas drawing commands while
their viewport textures continue animating. They redraw the canvas when
framing, size, content or visibility changes. Settled hidden previews pause
the entire stage, including model animation and attached effects, and disable
its viewport. Showing them resumes the stage and visible-only rendering.

The loading screen's hidden preparation is a necessary exception: unframed
previews finish their original finite measurement sequence even before their
texture is displayed. Missing models do not hold the loading queue open.
The still-portrait cache stops callbacks after all portraits finish framing
and freezes the whole stage rather than only the model animation.

Framing records belong to the source profile and mount generation. Reusing
a hero/creature name in another content installation cannot reuse the other
installation's crop. The spare-stage pool includes source identity and
generation; a remounted profile rebuilds an in-progress preview before it
can write stale measurements. The existing spare count limit is retained.

The shared wiki preview stage now uses weak references for its deferred
effect attachment. Creating and freeing a preview in the same frame no longer
leaves a callable carrying freed model/effect objects. This also protects the
Autochess views constructed by the same stage factory.

## Verification

See the package's `validation/RESULTS.md`, `validation/results.json` and
`validation/performance.json` for final counts, logs and measured workloads.
Comparative CPU checks use generated fixtures and retained V3 algorithms;
they report interleaved repeated measurements after warm-up. Real OpenGL and
Vulkan tests verify shader compilation and captured pixel behavior with
software GPU drivers. No original asset profiles are configured.

Run focused checks from the repository root:

```sh
godot --headless --editor --path game --import
godot --headless --path game --script ../tools/model_performance_check.gd -- --benchmark
godot --headless --path game --script ../tools/world_presentation_performance_check.gd -- --benchmark
godot --headless --path game --script ../tools/effects_performance_check.gd -- --benchmark
godot --headless --path game --script ../tools/ui_presentation_performance_check.gd -- --benchmark
godot --headless --path game --script ../tools/portrait_presentation_performance_check.gd
```

For GPU checks, omit `--headless`, select a renderer and pass `--render` after
the argument separator. Output screenshots are generated diagnostic scenes,
not original-game screenshots. The software timings do not establish hardware
GPU performance or full-game FPS. Original-art playthroughs, hardware ray
tracing, vendor upscalers, browser and mobile remain outside this environment.
