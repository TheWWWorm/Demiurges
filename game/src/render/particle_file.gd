class_name ELParticleFile
extends RefCounted
## Baked particle animation (.pfx in pfx.res), 30 frames a second.
##
##   u32, u32 frames
##   per frame: u32 n; n x u32 particle id; n x (x, y, z) f32; n x f32 size;
##              n x u16 atlas cell; n x (r, g, b) u8; n x u8 alpha
##   u16 length + texture name; u32 atlas columns; u32 atlas rows;
##   u16 blend (1 additive, 0 alpha); u32 loop start; u32 loop end
## The packed format uses u16 frame and particle counts, omits particle IDs,
## and stores positions as s16 hundredths and sizes as s16 fiftieths. Its
## texture-name length is u32 and its loop start is u8. Sizes are signed as in
## the float format: particles shrinking past zero (circle.pfx) and the shrine
## glow cores (-1.0) store small negatives, which read unsigned would be
## sprites 1310 units wide covering the whole map view. Renderers draw the
## magnitude.
## Coordinates are relative to the effect origin, z up, two units per map cell.
## A non-zero loop end makes the effect cyclic: the emission repeats every
## (loop end) frames while earlier cycles play their tail to the last frame.
## Most of the cyclic files end one frame past their loop. That frame closes
## the loop rather than playing anything out: drawn beside the new cycle, as
## a tail would be, it put 1.9 to 2.1 times the particles on screen for one
## frame in all but five of the shipped files, which flashed the picture
## every time round (closing_frame). A longer tail is a real one and plays.
const MAGIC := 0x1468fcca
const PACKED_MAGIC := 0x1478fcca
const FPS := 30.0
const MAX_FRAMES := 4096
## Largest frame in the shipped files: Ublockable.pfx (combat), 18,645.
const MAX_PARTICLES := 32768

## Camera-facing particle quads in every renderer (combat effects, figure
## clips, adventure script effects and weather, combat blood drops) share this
## size rule. A particle's size is a screen measure in the originals: the
## sprite is size / w wide in normalized device units on both axes, where w
## comes from the originals' own projection, which is the usual perspective
## matrix scaled by sin(h) (h = half the horizontal field of view). As a
## view-space half-extent that is size / (2 cos(h)). A 4:3 view is assumed so
## sprites keep their size in wider windows. The remake's adventure map uses an
## orthographic camera; there the original map camera's field of view
## (pi / 3.5 horizontal) gives size / (2 cos(pi / 7)).
## Shaders name SPRITE_SIZE_FUNCTION on its own line; `sprite_shader` inserts
## the function there.
const SPRITE_SIZE_FUNCTION := """float sprite_half_extent(float size, mat4 projection) {
	if (projection[3][3] == 1.0) return size * 0.5549581;
	float t = 4.0 / (3.0 * projection[1][1]);
	return size * 0.5 * sqrt(1.0 + t * t);
}"""

## Optional soft particles (the "soft_particles" preference; a remake
## addition, after Cursed Lands' particle shader): a sprite fades out where
## it meets the ground, walls and figures behind it, instead of ending in a
## hard line. The fade runs over SOFT_RANGE of view depth, or the sprite's own
## half-size if that is smaller, so small sparks lying on the ground stay
## visible. Shaders name SOFT_FUNCTION on its own line and multiply their
## ALPHA by sprite_soft(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, the
## sprite's view-space half-extent). With the preference off the function is
## a constant and the shader reads no scene depth (a depth read makes the
## renderer copy its depth buffer).
const SOFT_RANGE := 0.45
const SOFT_FUNCTION := """uniform sampler2D sprite_scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
float sprite_soft(vec2 screen_uv, float view_z, mat4 inverse_projection, float extent) {
	float depth = texture(sprite_scene_depth, screen_uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 scene = inverse_projection * vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	float gap = view_z - scene.z / scene.w;
	float soft = clamp(gap / max(min(SOFT_RANGE, extent), 0.02), 0.0, 1.0);
	return soft * soft * (3.0 - 2.0 * soft);
}"""
const HARD_FUNCTION := """float sprite_soft(vec2 screen_uv, float view_z, mat4 inverse_projection, float extent) {
	return 1.0;
}"""
static var soft := false

## Glowing (additive) sprites were authored for a picture that adds colours
## as they are displayed. A scene that adds them as light instead (the
## Forward+ renderer, path tracing, and the Compatibility renderer while it
## blooms) shows the faint outer skirt of a sprite several times stronger, so
## a flame's soft halo turns into a flat pale slab with the sprite's own edge
## showing. There an additive sprite's opacity passes through a knee that
## takes that skirt down (about four times at a tenth of opacity) and leaves
## the flame itself nearly as it was (a twentieth off where it is opaque), so
## fire keeps its body and loses only the glare around it. Shaders name
## ADD_FUNCTION on its own line and pass an additive sprite's ALPHA through
## sprite_add.
const ADD_KNEE := 0.3
const ADD_FUNCTION := """float sprite_add(float alpha) {
	alpha = clamp(alpha, 0.0, 1.0);
	return alpha * (alpha + ADD_KNEE) / (1.0 + ADD_KNEE);
}"""
const ADD_PLAIN_FUNCTION := """float sprite_add(float alpha) {
	return alpha;
}"""
static var add_knee := 0.0
## Atlas cells share an image, but must never borrow colour or opacity from
## their neighbours. At smaller sizes the ordinary sampler can reach a mip
## that has already averaged several cells together. Keep the original mip
## chain and stop at the last level that still has whole texels per cell.
## The two neighbouring mip levels are sampled inside their own half-texel
## borders; this also avoids a visible step whenever the mip level changes.
const ATLAS_FUNCTION := """uniform float atlas_max_lod = 0.0;
vec4 sprite_atlas_level(sampler2D sheet, vec2 uv, vec2 slot, vec2 cells, float level) {
	vec2 pixels = vec2(textureSize(sheet, int(level)));
	vec2 inset = vec2(0.5) / pixels;
	vec2 low = slot / cells + inset;
	vec2 high = (slot + vec2(1.0)) / cells - inset;
	return textureLod(sheet, clamp(uv, low, max(low, high)), level);
}
vec4 sprite_atlas(sampler2D sheet, vec2 uv, vec2 slot, vec2 cells) {
	if (cells.x == 1.0 && cells.y == 1.0) return texture(sheet, uv);
	vec2 pixels = vec2(textureSize(sheet, 0));
	vec2 dx = dFdx(uv) * pixels;
	vec2 dy = dFdy(uv) * pixels;
	float lod = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1.0)), 0.0, atlas_max_lod);
	float lower = floor(lod);
	float upper = min(lower + 1.0, atlas_max_lod);
	vec4 a = sprite_atlas_level(sheet, uv, slot, cells, lower);
	float blend = lod - lower;
	if (upper == lower || blend == 0.0) return a;
	vec4 b = sprite_atlas_level(sheet, uv, slot, cells, upper);
	return mix(a, b, blend);
}"""

## Pure size calculation; odd cell dimensions stop before a mip would mix
## adjacent frames. A single-cell sheet can use its complete original chain.
static func atlas_lod_limit(size: Vector2i, grid: Vector2i) -> int:
	if size.x < 1 or size.y < 1 or grid.x < 1 or grid.y < 1: return 0
	var level := 0
	while size.x > 1 or size.y > 1:
		var next := Vector2i(maxi(size.x / 2, 1), maxi(size.y / 2, 1))
		if (grid.x > 1 and (size.x % (grid.x * 2) != 0 or next.x < grid.x)) or (grid.y > 1 and (size.y % (grid.y * 2) != 0 or next.y < grid.y)): break
		level += 1
		size = next
	return level

static func set_atlas(material: ShaderMaterial, texture: Texture2D, grid: Vector2) -> void:
	material.set_shader_parameter("atlas", texture)
	material.set_shader_parameter("grid", grid)
	var limit := 0
	if texture != null:
		# ImageTexture retains the source image; do this only when a material
		# is made/reused, never per particle or render frame.
		var image := texture.get_image()
		if image != null:
			limit = mini(atlas_lod_limit(image.get_size(), Vector2i(grid)), image.get_mipmap_count())
	material.set_shader_parameter("atlas_max_lod", float(limit))

## Shaders made by make_sprite_shader: [WeakRef, source], rebuilt by set_soft
## and set_add_knee.
static var _sprite_shaders: Array = []

static func sprite_shader(code: String) -> String:
	var function := SOFT_FUNCTION.replace("SOFT_RANGE", str(SOFT_RANGE)) if soft else HARD_FUNCTION
	var add := ADD_FUNCTION.replace("ADD_KNEE", str(add_knee)) if add_knee > 0.0 else ADD_PLAIN_FUNCTION
	return code.replace("SPRITE_SIZE_FUNCTION", SPRITE_SIZE_FUNCTION).replace("SOFT_FUNCTION", function).replace("ADD_FUNCTION", add).replace("ATLAS_FUNCTION", ATLAS_FUNCTION)

## A sprite shader that follows the soft particles preference while it lives.
static func make_sprite_shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = sprite_shader(code)
	_sprite_shaders.append([weakref(shader), code])
	return shader

## Switches soft particles for every sprite shader, running ones too.
static func set_soft(on: bool) -> void:
	if soft == on: return
	soft = on
	_rebuild()

## Tells the sprite shaders whether the scene adds colours as light (see
## ADD_KNEE), running ones too.
static func set_linear_blend(on: bool) -> void:
	set_add_knee(ADD_KNEE if on else 0.0)

static func set_add_knee(value: float) -> void:
	if add_knee == value: return
	add_knee = value
	_rebuild()

static func _rebuild() -> void:
	var live := []
	for entry: Array in _sprite_shaders:
		var shader := entry[0].get_ref() as Shader
		if shader == null: continue
		shader.code = sprite_shader(entry[1])
		live.append(entry)
	_sprite_shaders = live

## Particle shadows (a remake addition: both original games drew every
## particle effect without a shadow, so a spring's water or a volcano's smoke
## stood unshadowed beside its stone building). The renderer has no
## translucent shadows, so a blended sprite sheet of matter that stops light
## (smoke, gas, mist, water spray, falling rubble and dust) gets a shadow-only
## twin of its quads (shadow_twin) that draws into the sun's shadow map only.
## It keeps a share of the sprite's pixels by a dither against the
## sprite's opacity times the sheet's strength below, and the shadow filter
## blurs that pattern into a soft, partial shadow. The twin's quads face the
## sun, as the visible ones face the camera, so the shadow is the puff's
## round outline thrown along the light. Glowing (additive) sheets give light
## and cast none, and nor do the other blended sheets, which are glows drawn
## with plain blending (mana, shrine and portal lights, lightning balls,
## magma glow, fire) or weather (rain, snow, leaves, sand storms; the callers
## also leave out every weather layer). Sheets are matched by name; the
## strength is the most of the light a fully opaque part of the sprite stops.
const SHADOW_SHEETS := {"smoke": 0.6, "gas": 0.5, "fog": 0.35, "water": 0.7, "destr": 0.6, "hurricane": 0.5}
## Effects shorter than this many frames cast none (a flash of a shadow
## reads as a flicker, and is not worth its shadow draw).
const SHADOW_MIN_FRAMES := 20
## The sprite size factor on an orthographic camera (see
## SPRITE_SIZE_FUNCTION). The shadow pass draws through the sun's own camera,
## so a twin is told the factor of the camera its sprite is seen through
## (camera_extent).
const ORTHO_EXTENT := 0.5549581
const SHADOW_GROUP := &"particle_shadows"
## Whether twins cast: the "shadows" preference (set_shadows).
static var shadows := false
static var _shadow_shader: Shader

## The share of the light a sheet's opaque parts stop in its shadow; 0 for
## a sheet that casts none (see SHADOW_SHEETS).
static func shadow_strength(file: ELParticleFile) -> float:
	if file == null or file.additive or file.frames < SHADOW_MIN_FRAMES: return 0.0
	var sheet := file.texture.to_lower()
	for word: String in SHADOW_SHEETS:
		if sheet.contains(word): return SHADOW_SHEETS[word]
	return 0.0

## Switches particle shadows for every twin, running ones too. They follow
## the "shadows" preference in every renderer: the Compatibility renderer
## (phones, and the default desktop renderer) blurs the dither as smoothly
## as Forward+, and a twin costs one more draw of its quads per shadow split.
static func set_shadows(on: bool) -> void:
	if shadows == on: return
	shadows = on
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	for node: Node in tree.get_nodes_in_group(SHADOW_GROUP): (node as GeometryInstance3D).visible = on

## A shadow-only copy of `node`'s quads (the same MultiMesh, so it follows
## every redraw), added as its child so it moves and hides with it. It casts
## nothing until shade_twin gives it a sheet. `cells_scaled`: the instance
## layout's atlas cell is scaled by its basis x (the battle effects' layout)
## rather than stored plain (the map's).
static func shadow_twin(node: MultiMeshInstance3D, cells_scaled: bool) -> MultiMeshInstance3D:
	var twin := MultiMeshInstance3D.new()
	twin.name = "Shadow"
	twin.multimesh = node.multimesh
	twin.custom_aabb = node.custom_aabb
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var material := ShaderMaterial.new()
	material.shader = shadow_shader()
	material.set_shader_parameter("cells_scaled", cells_scaled)
	twin.material_override = material
	twin.visible = false
	node.add_child(twin)
	return twin

## Points a twin at a sprite sheet: its atlas and grid, the strength
## (shadow_strength; 0 casts nothing) and the camera's sprite size factor
## (camera_extent).
static func shade_twin(twin: MultiMeshInstance3D, atlas: Texture2D, grid: Vector2, strength: float, extent: float) -> void:
	var casts := strength > 0.0 and atlas != null
	if casts:
		var material := twin.material_override as ShaderMaterial
		set_atlas(material, atlas, grid)
		material.set_shader_parameter("strength", strength)
		material.set_shader_parameter("extent", extent)
		if not twin.is_in_group(SHADOW_GROUP): twin.add_to_group(SHADOW_GROUP)
	elif twin.is_in_group(SHADOW_GROUP):
		twin.remove_from_group(SHADOW_GROUP)
	twin.visible = casts and shadows

## Whether a twin is set to cast (shade_twin), whatever the preference.
static func twin_casts(twin: MultiMeshInstance3D) -> bool:
	return twin != null and twin.is_in_group(SHADOW_GROUP)

## The sprite size factor of the camera `camera` (SPRITE_SIZE_FUNCTION).
static func camera_extent(camera: Camera3D) -> float:
	if camera == null or camera.projection == Camera3D.PROJECTION_ORTHOGONAL: return ORTHO_EXTENT
	var t := 4.0 / (3.0 * camera.get_camera_projection().y.y)
	return 0.5 * sqrt(1.0 + t * t)

static func shadow_shader() -> Shader:
	if _shadow_shader == null:
		_shadow_shader = Shader.new()
		_shadow_shader.code = SHADOW_SHADER.replace("ATLAS_FUNCTION", ATLAS_FUNCTION)
	return _shadow_shader

## Drawn in the shadow pass only. The quads face the pass's camera (the
## sun's). Each shadow map pixel is kept where the sprite's opacity beats a
## hashed threshold of that pixel: a regular dither (a Bayer matrix, or
## interleaved gradient noise) left stripes and hatching on the ground
## through the sun's few filter taps, where plain noise blurs into an even
## grain. The threshold is shifted per puff, so overlapping puffs stop light
## together as the drawn smoke thickens.
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(1.0);
uniform float strength = 0.5;
uniform float opacity = 1.0;
uniform float extent = 0.5549581;
uniform bool cells_scaled = false;
varying float fade;
varying flat float seed;
varying flat vec2 atlas_slot;
ATLAS_FUNCTION
void vertex() {
	float stretch = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	float cell = floor(length(MODEL_MATRIX[1].xyz) / (cells_scaled ? stretch : 1.0) - 0.5);
	float size = length(MODEL_MATRIX[2].xyz) * extent;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec2 slot = vec2(mod(cell, grid.x), floor(cell / grid.x));
	atlas_slot = vec2(slot.x, grid.y - 1.0 - slot.y);
	UV = (UV + slot) / grid;
	UV.y = 1.0 - UV.y;
	fade = INSTANCE_CUSTOM.a * opacity * strength;
	seed = fract(float(INSTANCE_ID) * 0.618034);
}
void fragment() {
	float cover = sprite_atlas(atlas, UV, atlas_slot, grid).a * fade;
	// A hashed threshold per shadow map pixel, shifted per puff.
	uvec2 q = uvec2(FRAGCOORD.xy);
	uint h = q.x * 1664525u + q.y * 1013904223u;
	h ^= h >> 16u; h *= 2246822519u; h ^= h >> 13u; h *= 3266489917u; h ^= h >> 16u;
	float noise = fract(float(h & 65535u) / 65536.0 + seed);
	if (cover <= noise) discard;
	ALBEDO = vec3(0.0);
}
"""

var frames := 0
## Set while the file ends one frame past its loop, which makes that frame
## the loop's closing frame rather than a tail (see visible_frames).
var closing_frame := false
## First particle of each frame (frames + 1 entries).
var starts := PackedInt32Array()
var positions := PackedFloat32Array()
var sizes := PackedFloat32Array()
## Atlas cell per particle (u16 little-endian pairs).
var cells := PackedByteArray()
## RGB bytes per particle, and alpha bytes.
var rgb := PackedByteArray()
var alpha := PackedByteArray()
var texture := ""
var columns := 1
var rows := 1
var additive := false
var loop_start := 0
var loop_end := 0
var max_count := 0
var error := ""
## MultiMesh instance data of each frame (16 floats per particle), built the
## first time the frame is drawn and shared by every effect using this file.
var _instances: Dictionary = {}
var _bounds_ready := false
var _centre_bounds := AABB()
var _largest_size := 0.0
var _visible_capacity := -1

## Stable map emitter capacity: the largest set of particles that can be
## visible together. Summing each loop phase avoids the much looser bound
## max_count * cycle_count, while retaining one GPU allocation for life.
func visible_capacity() -> int:
	if _visible_capacity >= 0: return _visible_capacity
	_visible_capacity = max_count
	if loop_end <= 0: return _visible_capacity
	var phases := PackedInt32Array()
	phases.resize(loop_end)
	var last := mini(loop_end, frames) if closing_frame else frames
	for frame in last:
		phases[frame % loop_end] += starts[frame + 1] - starts[frame]
	_visible_capacity = 0
	for count: int in phases: _visible_capacity = maxi(_visible_capacity, count)
	return _visible_capacity

## Local bounds for shader-expanded billboard quads, including their full
## diagonals for every camera/sun orientation. A MultiMesh's automatic bounds
## see the packed atlas index as a scale and miss this custom shader geometry.
## The map uses an orthographic camera, so this extent does not change with
## zoom. Only source positions/sizes are scanned, once per decoded file.
func sprite_bounds(extent := ORTHO_EXTENT) -> AABB:
	if not _bounds_ready:
		var low := Vector3(INF, INF, INF)
		var high := -low
		for i in mini(sizes.size(), positions.size() / 3):
			var point := Vector3(positions[i * 3], positions[i * 3 + 2], -positions[i * 3 + 1])
			if not point.is_finite() or not is_finite(sizes[i]): continue
			low = low.min(point)
			high = high.max(point)
			_largest_size = maxf(_largest_size, absf(sizes[i]))
		_centre_bounds = AABB(low, high - low) if low.is_finite() else AABB()
		_bounds_ready = true
	return _centre_bounds.grow(_largest_size * maxf(extent, 0.0) * sqrt(2.0) + 0.05)

static func decode(bytes: PackedByteArray) -> ELParticleFile:
	var file := ELParticleFile.new()
	file._parse(bytes)
	return file

func _parse(bytes: PackedByteArray) -> void:
	var magic := bytes.decode_u32(0) if bytes.size() >= 8 else 0
	if magic != MAGIC and magic != PACKED_MAGIC:
		error = "Not a particle file"
		return
	var packed := magic == PACKED_MAGIC
	frames = bytes.decode_u16(4) if packed else bytes.decode_u32(4)
	if frames < 1 or frames > MAX_FRAMES:
		error = "Invalid particle frame count"
		return
	var count_width := 2 if packed else 4
	var particle_width := 14 if packed else 26
	var at := 4 + count_width
	starts.resize(frames + 1)
	var total := 0
	for frame in frames:
		starts[frame] = total
		if at + count_width > bytes.size(): return _bad()
		var count := bytes.decode_u16(at) if packed else bytes.decode_u32(at)
		at += count_width
		if count > MAX_PARTICLES or at + count * particle_width > bytes.size(): return _bad()
		max_count = maxi(max_count, count)
		if packed:
			positions.resize((total + count) * 3)
			for i in count * 3:
				positions[total * 3 + i] = bytes.decode_s16(at + i * 2) * 0.01
			at += count * 6
			sizes.resize(total + count)
			for i in count:
				sizes[total + i] = bytes.decode_s16(at + i * 2) * 0.02
			at += count * 2
		else:
			at += count * 4
			positions.append_array(bytes.slice(at, at + count * 12).to_float32_array())
			at += count * 12
			sizes.append_array(bytes.slice(at, at + count * 4).to_float32_array())
			at += count * 4
		cells.append_array(bytes.slice(at, at + count * 2))
		at += count * 2
		rgb.append_array(bytes.slice(at, at + count * 3))
		alpha.append_array(bytes.slice(at + count * 3, at + count * 4))
		at += count * 4
		total += count
	starts[frames] = total
	var length_width := 4 if packed else 2
	if at + length_width > bytes.size(): return _bad()
	var length := bytes.decode_u32(at) if packed else bytes.decode_u16(at)
	at += length_width
	if at + length + (15 if packed else 18) > bytes.size(): return _bad()
	texture = bytes.slice(at, at + length).get_string_from_ascii()
	at += length
	columns = clampi(bytes.decode_u32(at), 1, 64)
	rows = clampi(bytes.decode_u32(at + 4), 1, 64)
	additive = bytes.decode_u16(at + 8) == 1
	loop_start = bytes[at + 10] if packed else bytes.decode_u32(at + 10)
	loop_end = bytes.decode_u32(at + (11 if packed else 14))
	if loop_end >= frames or loop_start > loop_end: loop_end = 0
	closing_frame = loop_end > 0 and frames - loop_end == 1

func _bad() -> void:
	error = "Truncated particle file"
	frames = 0

## The frames drawn together `frame` frames after the start: one per cycle
## still playing. `loops` is the script's loop count (-1 unlimited).
func visible_frames(frame: int, loops := -1) -> PackedInt32Array:
	var result := PackedInt32Array()
	if frames < 1 or frame < 0: return result
	if loop_end <= 0:
		if frame < frames: result.append(frame)
		return result
	var period := loop_end
	var cycle := frame / period
	var phase := frame % period
	var newest := cycle if loops < 0 else mini(cycle, loops)
	# The loop's closing frame is not drawn over the new cycle, which showed
	# every particle twice for one frame.
	var last := loop_end if closing_frame else frames
	for back in range(0, cycle + 1):
		var at := phase + back * period
		if at >= last: break
		# Cycles past the loop count are not started again.
		if cycle - back > newest: continue
		result.append(at)
	return result

## Whether the effect has played out (non-cyclic, or cyclic with its loops used).
func finished(frame: int, loops := -1) -> bool:
	if loop_end <= 0: return frame >= frames
	return loops >= 0 and frame >= frames + loops * loop_end

## The frame's particles as MultiMesh instance data: the transform carries the
## size (basis x and z), the atlas cell + 1 (basis y) and the position in
## map-scene axes (x east, y up, z south); the custom data is RGBA.
func instances(frame: int) -> PackedFloat32Array:
	var cached: Variant = _instances.get(frame)
	if cached != null: return cached
	var first := starts[frame]
	var count := starts[frame + 1] - first
	var buffer := PackedFloat32Array()
	buffer.resize(count * 16)
	buffer.fill(0.0)
	for n in count:
		var i := first + n
		var o := n * 16
		var size: float = sizes[i]
		buffer[o] = size
		buffer[o + 3] = positions[i * 3]
		buffer[o + 5] = float(cells.decode_u16(i * 2) + 1)
		buffer[o + 7] = positions[i * 3 + 2]
		buffer[o + 10] = size
		buffer[o + 11] = -positions[i * 3 + 1]
		buffer[o + 12] = rgb[i * 3] / 255.0
		buffer[o + 13] = rgb[i * 3 + 1] / 255.0
		buffer[o + 14] = rgb[i * 3 + 2] / 255.0
		buffer[o + 15] = alpha[i] / 255.0
	_instances[frame] = buffer
	return buffer
