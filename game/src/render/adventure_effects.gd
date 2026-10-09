class_name ELAdventureEffects
extends Node3D
## Second game: particle effects started by the adventure scripts, each one
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

static var _files: Dictionary = {}
static var _order: Array[String] = []

var profile: ELProfile
var enabled := true
## Parent of the optional ambience effects; hidden by the preference.
var weather_layer: Node3D
## Effect name -> {entry, file, node, elapsed, frame, optional}.
var effects: Dictionary = {}
var _materials: Dictionary = {}

func build(data: ELProfile, settings: ELSettings, state: ELAdventureSession) -> void:
	profile = data
	weather_layer = Node3D.new()
	add_child(weather_layer)
	set_enabled(bool(settings.values.get("weather", true)) if settings != null else true)
	# A restored map recreates every running effect from its first frame.
	for name: String in state.ambience.get("effects", {}):
		start(name, state.ambience.effects[name], 0.0)

func set_enabled(value: bool) -> void:
	enabled = value
	weather_layer.visible = value
	for name: String in effects: effects[name].frame = -1

## Ambience the weather preference may hide (see the class description).
static func optional(entry: Dictionary) -> bool:
	return ELSecondAmbience.is_terrain_effect(str(entry.get("file", ""))) and not bool(entry.get("story", false))

## A session "script_effect" event: an empty entry finishes the effect.
func script_event(data: Dictionary) -> void:
	if data.get("kind") != "script_effect": return
	finish(str(data.name))
	if not data.entry.is_empty(): start(str(data.name), data.entry, 0.0)

## Turns a running effect about the vertical axis (the object's facing).
func orient(name: String, yaw: float) -> void:
	if effects.has(name): effects[name].node.rotation.y = yaw

func start(name: String, entry: Dictionary, elapsed: float) -> void:
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
	# ELParticleFile.SPRITE_SIZE_FUNCTION (the size itself on the map's
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
	effects[name] = {"entry": entry.duplicate(), "file": file, "node": node, "elapsed": elapsed, "frame": -1, "optional": hidden}

func finish(name: String) -> void:
	var effect: Variant = effects.get(name)
	if effect == null: return
	effect.node.queue_free()
	effects.erase(name)

func _process(delta: float) -> void:
	for name: String in effects.keys():
		var effect: Dictionary = effects[name]
		effect.elapsed += delta
		var frame := int(effect.elapsed * ELParticleFile.FPS)
		var file: ELParticleFile = effect.file
		var loops := int(effect.entry.get("loops", -1))
		if file.finished(frame, loops):
			finish(name)
			continue
		# Hidden ambience keeps its clock but is not redrawn.
		if frame == effect.frame or (effect.optional and not enabled): continue
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

## Decoded particle files, shared by every view of the same edition.
static func particle_file(data: ELProfile, path: String) -> ELParticleFile:
	var key := data.id + ":" + ELArchive.key(path)
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
