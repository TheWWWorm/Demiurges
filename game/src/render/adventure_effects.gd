class_name ELAdventureEffects
extends Node3D
## Second game: particle effects from adventure scripts and shrines, each one
## MultiMesh of camera-facing quads from a baked .pfx animation
## (ELParticleFile), redrawn when its 30 fps frame changes. Two kinds:
## - ambience: terrain particles (terrainpfx: rain, snow, ash, sand storms,
##   damp, dots of light) a script starts directly: the library weather and a
##   chapter's own scenery. Optional: the "weather" preference hides them.
## - story effects: every other particle file (combat domes, lightning,
##   teleports, global spells, vortices) and anything a cutscene starts through
##   the command queue. Always drawn.
## Effects are presentation only; the script state does not depend on them.
## Effects only sit where they were started; a script may turn one to an
## object's facing (OrientEffectByObject).
const CACHE_LIMIT := 6
const RAIN_FILES := ["terrainpfx/rain.pfx", "terrainpfx/rainnocycle.pfx"]
const SHRINE_EFFECTS := [ELSecondBuildings.SHRINE, "AltarOfChaos", "ShrineOfOrdering", "ShrineOfSynthesis", "SourceOfLife"]

signal rain_changed(areas: PackedVector4Array)

static var _files: Dictionary = {}
static var _order: Array[String] = []
## Files decoded ahead of use (keep_file), never evicted.
static var _kept: Dictionary = {}

var profile: ELProfile
var enabled := true
## Parent of the optional ambience effects; hidden by the preference.
var weather_layer: Node3D
## Effect name -> {entry, file, node, elapsed, frame, optional}.
var effects: Dictionary = {}
## Scripted point lights by name (ExStartLight).
var lights: Dictionary = {}
var _materials: Dictionary = {}
var _rain_on_water := false
var _shrine_session: ELAdventureSession
var _shrines: Dictionary = {}
var _shrine_fog_revision := -1

func build(data: ELProfile, settings: ELSettings, state: ELAdventureSession) -> void:
	profile = data
	weather_layer = Node3D.new()
	add_child(weather_layer)
	_rain_on_water = settings != null and bool(settings.values.get("enhanced_water", false))
	set_enabled(bool(settings.values.get("weather", true)) if settings != null else true)
	# A restored map recreates every running effect from its first frame.
	for name: String in state.ambience.get("effects", {}):
		start(name, state.ambience.effects[name], 0.0)
	for name: String in state.ambience.get("lights", {}):
		_light(name, state.ambience.lights[name])
	if data.id == "el2":
		_shrine_session = state
		for item: Dictionary in state.objects.values():
			if item.get("group") == "additional_buildings" and item.get("name") in SHRINE_EFFECTS:
				_shrines[int(item.uid)] = item
		_sync_shrines()

func set_enabled(value: bool) -> void:
	enabled = value
	weather_layer.visible = value
	for name: String in effects: effects[name].frame = -1
	_publish_rain()

func set_water_ripples(value: bool) -> void:
	if _rain_on_water == value: return
	_rain_on_water = value
	_publish_rain()

## Ambience the weather preference may hide (see the class description).
static func optional(entry: Dictionary) -> bool:
	return ELSecondAmbience.is_terrain_effect(str(entry.get("file", ""))) and not bool(entry.get("story", false))

## Applies scripted particles and changes to placed shrine effects.
func script_event(data: Dictionary) -> void:
	# The shrine use changes its saved used flag before notifying the map.
	if data.kind in ["object_changed", "object_killed"] and _shrines.has(int(data.id)):
		_sync_shrine(_shrines[int(data.id)])
	if data.kind == "script_effect":
		finish(str(data.name))
		if not data.entry.is_empty(): start(str(data.name), data.entry, 0.0)
	if data.kind == "script_light": _light(str(data.name), data.entry)

## Places, moves or (with an empty entry) removes a scripted light.
func _light(name: String, entry: Dictionary) -> void:
	var node: OmniLight3D = lights.get(name)
	if entry.is_empty():
		if node != null: node.queue_free()
		lights.erase(name)
		return
	if node == null:
		node = OmniLight3D.new()
		node.shadow_enabled = false
		add_child(node)
		lights[name] = node
	# Script coordinates: x east, y north, z up, two units per cell.
	node.position = Vector3(float(entry.x), float(entry.z), -float(entry.y))
	node.omni_range = float(entry.radius)
	node.light_color = Color.html(str(entry.color))

func _sync_shrines() -> void:
	_shrine_fog_revision = ELFog.revision(_shrine_session)
	for item: Dictionary in _shrines.values(): _sync_shrine(item)

func _sync_shrine(item: Dictionary) -> void:
	var name := "shrine:%d" % int(item.uid)
	if item.get("used", false) or not item.get("alive", true) or not item.get("visible", true) or not item.get("placed", true) or ELFog.object_state(_shrine_session, 1, item) != ELFog.VISIBLE:
		finish(name)
		return
	var row := ELSecondBuildings.definition(profile, item)
	var file := str(row.get("Effect", ""))
	if file.is_empty(): return
	var center := ELAdventureGrid.center(item, row) * ELAdventureTerrain.CELL
	if effects.has(name):
		effects[name].node.position = Vector3(center.x, 0.0, -center.y)
	else:
		start(name, {"file": file, "x": center.x, "y": center.y, "z": 0.0, "story": true}, 0.0)
	orient(name, -float((int(item.rotation) >> 2) & 3) * PI / 2.0)

## Turns a running effect about the vertical axis (the object's facing).
func orient(name: String, yaw: float) -> void:
	if effects.has(name): effects[name].node.rotation.y = yaw

func start(name: String, entry: Dictionary, elapsed: float, draw_current := false) -> void:
	finish(name)
	var file := particle_file(profile, str(entry.file))
	if file == null or not file.error.is_empty() or file.frames < 1: return
	var material := _material(file)
	if material == null: return
	var copies := 1 if file.loop_end <= 0 else ceili(float(file.frames) / file.loop_end)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	# A unit quad of half-extent 1, scaled in the shader by
	# ELParticleFile.SPRITE_SIZE_FUNCTION (size / cos(pi / 7) on the map's
	# orthographic camera).
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh.mesh = quad
	mesh.instance_count = file.max_count * copies
	mesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Large spells reach about 45 units from their origin.
	node.custom_aabb = AABB(Vector3(-64, -16, -64), Vector3(128, 96, 128))
	# Script coordinates: x east, y north, z up, two units per cell.
	node.position = Vector3(float(entry.x), float(entry.z), -float(entry.y))
	var hidden := optional(entry)
	(weather_layer if hidden else self).add_child(node)
	var rain := hidden and ELArchive.key(str(entry.file)) in RAIN_FILES
	effects[name] = {"entry": entry.duplicate(), "file": file, "node": node, "elapsed": elapsed, "frame": -1, "optional": hidden, "rain": rain}
	if rain and _rain_on_water and enabled: _publish_rain()
	if draw_current: _advance(name, 0.0)

## Decodes a particle file and builds its material while the map loads, so
## its first appearance does not hitch (see keep_file).
func prepare(path: String) -> void:
	keep_file(profile, path)
	var file := particle_file(profile, path)
	if file != null and file.error.is_empty() and file.frames > 0: _material(file)

func finish(name: String) -> void:
	var effect: Variant = effects.get(name)
	if effect == null: return
	effect.node.queue_free()
	effects.erase(name)
	if effect.rain and _rain_on_water and enabled: _publish_rain()

func _publish_rain() -> void:
	var areas := PackedVector4Array()
	if enabled and _rain_on_water:
		for effect: Dictionary in effects.values():
			if not effect.rain: continue
			var area := _rain_bounds(effect.file)
			if not area.has_area(): continue
			var origin: Vector3 = effect.node.position
			var center := area.get_center() + Vector2(origin.x, -origin.z)
			areas.append(Vector4(center.x, center.y, area.size.x * 0.5, area.size.y * 0.5))
	rain_changed.emit(areas)

static func _rain_bounds(file: ELParticleFile) -> Rect2:
	if file.has_meta(&"water_rain_bounds"): return file.get_meta(&"water_rain_bounds")
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in file.alpha.size():
		if file.alpha[i] == 0: continue
		var point := Vector2(file.positions[i * 3], file.positions[i * 3 + 1])
		low = low.min(point)
		high = high.max(point)
	var bounds := Rect2(low, high - low) if low.is_finite() and high.is_finite() else Rect2()
	file.set_meta(&"water_rain_bounds", bounds)
	return bounds

func _process(delta: float) -> void:
	if not _shrines.is_empty() and _shrine_fog_revision != ELFog.revision(_shrine_session): _sync_shrines()
	for name: String in effects.keys():
		_advance(name, delta)

func _advance(name: String, delta: float) -> void:
	var effect: Dictionary = effects[name]
	effect.elapsed += delta
	var frame := int(effect.elapsed * ELParticleFile.FPS)
	var file: ELParticleFile = effect.file
	var loops := int(effect.entry.get("loops", -1))
	if file.finished(frame, loops):
		finish(name)
		return
	# Hidden ambience keeps its clock but is not redrawn.
	if frame == effect.frame or (effect.optional and not enabled): return
	effect.frame = frame
	_draw(effect, file.visible_frames(frame, loops))

## Instance layout: ELParticleFile.instances.
func _draw(effect: Dictionary, frames: PackedInt32Array) -> void:
	var file: ELParticleFile = effect.file
	var mesh: MultiMesh = effect.node.multimesh
	var buffer := PackedFloat32Array()
	for frame: int in frames: buffer.append_array(file.instances(frame))
	var count := mini(buffer.size() / 16, mesh.instance_count)
	buffer.resize(mesh.instance_count * 16)
	mesh.buffer = buffer
	mesh.visible_instance_count = count

## Additive story sprites can light the traced map. Terrain effects use the
## same blend for weather such as rain, so it does not make them light sources.
func glow_sources() -> Array:
	var result := []
	for effect: Dictionary in effects.values():
		var file: ELParticleFile = effect.file
		var node: MultiMeshInstance3D = effect.node
		if effect.frame < 0 or not file.additive or ELSecondAmbience.is_terrain_effect(str(effect.entry.file)) or not node.is_visible_in_tree(): continue
		if effect.get("glow_frame", -1) != effect.frame:
			effect.glow_frame = effect.frame
			var buffer := PackedFloat32Array()
			for frame: int in file.visible_frames(effect.frame, int(effect.entry.get("loops", -1))):
				buffer.append_array(file.instances(frame))
			var atlas := (node.material_override as ShaderMaterial).get_shader_parameter("atlas") as Texture2D
			var tints := ELCombatEffects._atlas_cell_tints(atlas, Vector2i(file.columns, file.rows))
			var glows := ELCombatEffects._glow({"glow_tints": tints}, "", buffer, buffer.size() / 16)
			var total := 0.0
			for glow: Array in glows:
				var colour := ELCombatEffects._saturate(glow[2])
				glow[2] = colour
				total += maxf(colour.x, maxf(colour.y, colour.z))
			var share := minf(1.0, ELCombatEffects.EMITTER_GLOW / maxf(total, 0.0001))
			for glow: Array in glows: glow[2] *= share
			effect.glows = glows
		for glow: Array in effect.get("glows", []):
			result.append([node.global_transform * glow[0], glow[1], glow[2]])
	return result

func _material(file: ELParticleFile) -> ShaderMaterial:
	var key := "%s|%d|%d|%s" % [file.texture, file.columns, file.rows, file.additive]
	if _materials.has(key): return _materials[key]
	var name := file.texture.get_basename() if file.texture.to_lower().ends_with(".bmp") else file.texture
	var texture := profile.texture("Effects/" + name)
	if texture == null:
		_materials[key] = null
		return null
	var shader := Shader.new()
	shader.code = ELParticleFile.sprite_shader(SHADER.replace("BLEND", "blend_add" if file.additive else "blend_mix"))
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas", texture)
	material.set_shader_parameter("grid", Vector2(file.columns, file.rows))
	material.render_priority = 10
	_materials[key] = material
	return material

## Decodes a particle file ahead of its first use and keeps it out of the
## cache's eviction (a large effect such as the battle dome would otherwise
## be decoded on the frame it appears).
static func keep_file(data: ELProfile, path: String) -> void:
	var key := data.id + ":" + ELArchive.key(path)
	if _kept.has(key): return
	var file := particle_file(data, path)
	if file != null and file.error.is_empty(): _kept[key] = file

## Decoded particle files, shared by every view of the same edition.
static func particle_file(data: ELProfile, path: String) -> ELParticleFile:
	var key := data.id + ":" + ELArchive.key(path)
	if _kept.has(key): return _kept[key]
	if _files.has(key):
		_order.erase(key)
		_order.append(key)
		return _files[key]
	var file := ELParticleFile.decode(data.read("pfx", ELArchive.key(path)))
	_files[key] = file
	_order.append(key)
	while _order.size() > CACHE_LIMIT: _files.erase(_order.pop_front())
	return file

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, BLEND;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(1.0);
varying vec4 tint;
SPRITE_SIZE_FUNCTION
void vertex() {
	float size = sprite_half_extent(length(MODEL_MATRIX[0].xyz), PROJECTION_MATRIX);
	float cell = floor(length(MODEL_MATRIX[1].xyz) - 0.5);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec2 slot = vec2(mod(cell, grid.x), floor(cell / grid.x));
	// Cells count up from the bottom row of the stored image; the sprite's top
	// edge shows the lower edge of its cell.
	UV = (UV + slot) / grid;
	UV.y = 1.0 - UV.y;
	tint = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 texel = texture(atlas, UV);
	ALBEDO = texel.rgb * tint.rgb;
	ALPHA = texel.a * tint.a;
}
"""
