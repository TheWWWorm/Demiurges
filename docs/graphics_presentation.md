# Graphics presentation update

> Historical V1 notes. Current cumulative implementation and executed validation
> are described in `graphics_presentation_v4.md` and the V4 package validation report.

Source-only improvements for Demiurges 0.18.5, prepared on 18 November 2026.

Base: `0dc8ff683eaf35942e457f94bdbbbc870b4e7f44` (`main`, “Publish the 0.18.5 browser build”).

This update works with the original assets the player already owns. It contains
GDScript, shaders and reproducible procedural checks; no Etherlords textures,
models, audio, installers or other original game content is included. It does
not change combat rules, AI, balance, progression or save formats. Native
libraries do not need to be rebuilt.

## What changes on screen

### Animated surface lighting

Morph animation previously changed a model's vertex positions while keeping
the normals from its rest pose. Bending surfaces could therefore retain the
rest pose's shading and metal highlights. `morph_normals.gd` now transports the
authored normals through each triangle's deformation when the animation mesh
is prepared. Playback blends the already cached normals alongside positions.

The implementation joins only vertices with the same source vertex and the
same authored normal. This preserves smooth UV seams and deliberately split
hard edges. It retains original normals for a rest pose and falls back safely
for collapsed triangles. It does not smooth the geometry or change animation
positions, timing, bounds, or clips. Preparation costs more CPU time when a
morph mesh first loads; no normal reconstruction occurs during playback.
Some callers build a previously unseen clip's mesh on the main thread, so this
can add a short cold-clip hitch. A synthetic 30-pose mesh with 576 vertices
and 1,058 triangles took about 25–36 ms total to prepare its normals across
the completed checks in the
verification environment. That is not a frame-rate measurement on game assets.

### Cutout edges and hit feedback

Generated mipmaps for eligible one-bit hero, creature and scenery textures
now preserve alpha coverage at the material's cutoff. This reduces thin
features disappearing as the camera pulls back. Invisible RGB is filled before
filtering to reduce dark fringes. Authored arena mipmaps remain authoritative;
UI, effects, generated CombatScenes/Alpha particle sheets and soft-alpha/Alpha32
skins retain ordinary filtering. Texture
dimensions and the normal mip-chain allocation remain unchanged.

Colourless map variants preserve each prepared mip level's alpha mask while
converting its RGB to grey, so entering a grey region does not undo the cutout
improvement. Their authored/generated mask metadata also survives copying.

The path tracer's texture-atlas preparation reuses a prepared 256 px mask
level, including its mip tail, when available. It preserves authored mip
priority and falls back for unsuitable formats, dimensions or incomplete
chains. This is a CPU preparation change, not a rewrite of the ray integrator.

Hits now add a short, fading tint through the figure's real alpha mask rather
than covering cutout cards with a solid material. The tint follows opacity and
animated UV transforms, restarts cleanly on repeated hits, and restores an
existing overlay without clearing a newer effect's overlay. Additive glow
parts retain their own effects.

### Ground, water and atmosphere

With **Terrain detail** enabled, arena detail grain also provides shallow
lighting relief. Screen derivatives reuse the existing texture sample; no
normal-map asset, extra sample or geometry is required. Relief fades when its
texels become small and has a bounded slope. Turning the option off restores
the exact original ground material.

With **Enhanced water** enabled, the Ship arena filters its wave detail by
screen footprint and broadens undersampled sun glints while reducing their
peak. Subtle broken foam follows the existing hull transition. The adventure
map's water uses a conservative highlight filter calculated before the
shoreline branch, avoiding invalid derivatives at mixed water/land pixels.

Enhanced ship water and the existing low arena mist now respond to changes in
the arena's ambient and directional light. Their ordinary palette is kept as
the reference, so a darkening or tinted spell changes them along with the
scene. The calculation is in linear colour on both supported renderers and
has safeguards for zero-valued channels and extreme flashes. Creature mist
wakes and source fog density remain intact.

### Combat readability

The selection marker is a single procedural quad with thin antialiased rings,
four small ticks and a dark keyline. It remains readable on light and dark
ground without bloom. The hover state has a restrained pulse; a selection is
still. Its position uses arena ground height beneath flying figures and a
cached local slope. Five height samples are refreshed after meaningful
movement rather than every stationary frame. The marker remains depth tested,
excluded from the combat watch camera and path-traced geometry, and casts no
shadow.

Original numeric glyphs and their slash gain a one-screen-pixel dark keyline;
other state icons and sword/shield artwork stay as they were. Damage and
healing retain their colours and three-second lifetime, with a fade over the
last 0.45 seconds. Helper captions use the animated number anchor or measured
model height, clear older captions that have already risen, ease upward, and
fade their fill and outline together.

Blood drops retain their original 30 Hz simulation but interpolate their
displayed positions between ticks. The stain pool keeps the newest 256 prints
instead of allowing older prints to hide later impacts. Both pools remain
bounded, and the original blood preference and effect lifetimes still apply.

### Consistent Autochess preferences

Autochess now applies current water, terrain detail, soft shadows and effect
preferences to both the active arena and cached arenas. Returning to a cached
board or reusing the same scene applies the latest choices without rebuilding
the battlefield or deployed models. Missing detail/water preferences default
off consistently with the main settings. While path tracing owns shadows,
changing the shadow preference updates the value to restore without enabling
raster shadows at the same time. The same ownership guard now applies when
the regular duel or adventure-map settings are reapplied, including while
changing the new contact-shading option.

### Optional contact shading

**Contact shading** is a new, initially disabled Forward+ option. It adds
short-range ambient occlusion at contacts and creases on lit surfaces. It
does not change authored ambient colours or light intensities, and does not
attenuate direct sun or spell lights. Unlit materials, including much of the
original adventure scenery, do not receive this effect.

The option is unavailable in Compatibility and on mobile/web. It is disabled
while the current environment is path traced and resumes when raster lighting
returns. This is a subtle grounding aid for the raster renderer, not a
replacement for shadows or path tracing. Both English and Russian UI text
explain its scope. It has a GPU cost; keep it off on devices where that cost
is not worthwhile.

## Seeing the changes

Most fixes apply automatically: animation normals, eligible cutout mipmaps,
hit tint, selection marker, numeric readability, caption placement and blood
interpolation.

In **Options → Remake settings → Graphics**, enable **Terrain detail** and
**Enhanced water** to see the corresponding surface improvements. Existing
choices are preserved. **Contact shading** is optional and requires Forward+;
it does not apply while path tracing is active. Existing Bloom, Soft particles
and Spell light controls remain separate.

## Reproducible verification

Use the project's Godot **4.7** editor. Older stock versions cannot parse the
repository's existing ray-tracing APIs. None of the following new checks
mounts an original game profile or writes player preferences:

```sh
godot --headless --editor --path game --import
godot --headless --path game --script ../tools/arena_presentation_check.gd
godot --headless --path game --script ../tools/combat_presentation_check.gd
godot --headless --path game --script ../tools/material_presentation_check.gd
godot --headless --path game --script ../tools/graphics_integration_check.gd
godot --headless --path game --script ../tools/contact_shading_check.gd
```

Actual shader rendering is a separate check. For example:

```sh
godot --path game --rendering-method gl_compatibility --script ../tools/arena_presentation_check.gd -- --render --shots=/absolute/output
godot --path game --rendering-method forward_plus --rendering-driver vulkan --script ../tools/arena_presentation_check.gd -- --render --shots=/absolute/output
```

The other four new checks support the same `--render --shots=...` arguments.
Use a writable output folder. Their pictures use procedural stand-ins and
generated texture fixtures; they are not screenshots of the original games.
Headless checks verify data, resource and scene lifecycle behavior. Windowed
checks additionally render the real shaders and inspect their output.

The package's `validation/RESULTS.md` records the actual completed runs,
renderer versions, assertions and limitations. Existing effect-look and
path-tracing budget checks are also included in that validation record; the
latter skips hardware ray-tracing tests without a suitable device.

## Review with installed assets

The source and procedural checks do not establish final visual tuning for
every original asset. After importing the update, useful short checks are:

- A creature with feathers, hair or thin blades at near and far zoom; repeated
  hits, a fading departure and both soft and hard alpha skins.
- A bending creature or animated wing under a directional light, including a
  model with deliberately unusual authored normals.
- Terrain detail on/off in a normal arena and Enhanced water on/off in Ship;
  an arena-darkening spell should dim the water or low mist too.
- Hovering and selecting tall and flying figures, a sloping patch of ground,
  several simultaneous damage numbers and a crowded blood-effect sequence.
- Changing graphics preferences during Autochess, switching to a different
  cached arena and returning, then toggling path tracing if supported.
- Contact shading on/off in Forward+, particularly feet, plinths and nearby
  walls; Compatibility and path-traced scenes should show no extra AO pass.

Terrain alignment approximates a local plane, so very irregular geometry can
still intersect a marker. Coverage filtering cannot reproduce an arbitrarily
thin feature once the whole feature is smaller than a pixel. The changes do
not increase model polygon counts or replace low-resolution source textures.
Original-game visual review, browser/mobile device testing, vendor upscalers,
hardware ray tracing and gameplay performance profiling remain unverified in
this source-only environment.
