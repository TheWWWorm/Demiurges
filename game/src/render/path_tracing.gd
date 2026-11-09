class_name ELPathTracing
extends Node
## Experimental path-traced lighting for battles and the adventure map
## (desktop Forward+ on Vulkan with a ray-tracing GPU). F7 switches it on and
## off, Shift+F7 shows the traced light alone.
##
## The raster view keeps its geometry, textures, effects and backdrop. A
## ray pass after the opaque pass traces, per pixel, a soft sun shadow, light
## from glowing effects and one diffuse bounce against a snapshot of the scene
## (figures' morph frames and placements are refreshed each frame), smooths
## the noise over time and space, and swaps the raster light for the traced
## light. Each scene registers its camera; tracing follows the current one.

signal changed(active: bool)

const LAYER_SIZE := 256
const LAYER_MIPMAPS := 9
const LAYERS := 192
## Angular radius of the sun's disc (tangent), which sets shadow softness.
const SUN_RADIUS := 0.02
## Effect lights traced at once (the brightest are kept).
const LIGHT_LIMIT := 64
## Light given off per unit of summed particle colour, and its reach.
const GLOW_STRENGTH := 1.0
## Brightest colour component one effect light may reach.
const GLOW_LIMIT := 10.0
const GLOW_REACH := 8.0
## Bloom while tracing: glowing particles draw this much brighter, and only
## what passes white blooms, so daylit scenery stays as it was.
const EFFECT_HDR := 2.5
const BLOOM_THRESHOLD := 1.0
const BLOOM_INTENSITY := 0.9
## Scene membership is re-read this often (seconds).
const SCAN_INTERVAL := 0.5

var enabled := false
var lighting_view := false
var settings: ELSettings
## Puts the on-screen messages into the game's language (English as given).
var translate: Callable

var _effect: Effect
# Registered scenes: {camera, root, sun, environment, effects, arena}.
var _contexts: Array[Dictionary] = []
var _active := false     # tracing set up on the current context
var _camera: Camera3D
var _root: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _arena: ELArena
var _effects: ELCombatEffects
var _models: Array[ELModel] = []
var _static_nodes: Array[GeometryInstance3D] = []
var _static_entries := []
var _static_cache := {}   # node id -> [global transform, instance count, entries]
var _static_version := 0
var _scan := 0.0
var _label: Label
var _label_time := 0.0
# Main-thread snapshot state, cleared together with the GPU side on a reset.
var _slots := {}          # node id -> {mesh, frame, vertices, layer, flags}
var _layers := {}         # [texture, solid] -> [layer, has alpha]
var _mesh_data := {}      # Mesh -> {vertex, index, uv}
var _benchmarking := false
# Development check (--path-tracing-fx=Effect): repeats an effect from the
# player's hero at the other every three seconds.
var _fx_name := ""
var _fx_clock := 1.0
var _fx_plays := 0
var _fx_shot := ""         # --path-tracing-fx-shot=file: a screenshot of the second play
var _fx_delay := 0.8       # --path-tracing-fx-delay=seconds after it starts
var _fx_shot_at := 0.0
var _snapshot_us := 0
var _saved_msaa := -1
var _saved_aa := -1

static func available() -> bool:
	if DisplayServer.get_name() == "headless": return false
	if RenderingServer.get_current_rendering_method() != "forward_plus": return false
	if RenderingServer.get_current_rendering_driver_name() != "vulkan": return false
	var rd := RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE)

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.visible = false
	layer.add_child(_label)
	if available(): _effect = Effect.new()
	enabled = available() and (OS.get_cmdline_user_args().has("--path-tracing") or (settings != null and bool(settings.values.get("path_tracing", false))))
	lighting_view = enabled and OS.get_cmdline_user_args().has("--path-tracing-light")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path-tracing-fx="): _fx_name = arg.get_slice("=", 1)
		elif arg.begins_with("--path-tracing-fx-shot="): _fx_shot = arg.get_slice("=", 1)
		elif arg.begins_with("--path-tracing-fx-delay="): _fx_delay = float(arg.get_slice("=", 1))
	# Runs after the scenes' own cameras have moved each frame.
	process_priority = 1000

## A battle: its stage (arena and figures), arena, camera and effects.
func attach(stage: Node3D, arena: ELArena, camera: Camera3D, effects: ELCombatEffects = null) -> void:
	register(camera, stage, arena.light, arena.environment_settings, effects, arena)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path-tracing-bench") and not _benchmarking: _benchmark(arg.get_slice("=", 1))

## A scene to trace while `camera` is the current one: everything drawn under
## `root`, lit by `sun` and `environment`. `effects` adds glowing effects;
## `arena` its scenery light limit.
func register(camera: Camera3D, root: Node3D, sun: DirectionalLight3D, environment: Environment, effects: ELCombatEffects = null, arena: ELArena = null) -> void:
	_contexts = _contexts.filter(func(c: Dictionary) -> bool: return is_instance_valid(c.camera) and c.camera != camera)
	_contexts.append({"camera": camera, "root": root, "sun": sun, "environment": environment, "effects": effects, "arena": arena})
	if _effect == null: return
	var compositor := Compositor.new()
	compositor.compositor_effects = [_effect]
	camera.compositor = compositor
	if camera.is_current(): _switch(_contexts.back())

func _switch(context: Dictionary) -> void:
	_deactivate()
	_camera = context.camera
	_root = context.root
	_sun = context.sun
	_env = context.environment
	_effects = context.effects if is_instance_valid(context.effects) else null
	_arena = context.arena if is_instance_valid(context.arena) else null
	_models.clear()
	_static_nodes.clear()
	_static_entries.clear()
	_static_cache.clear()
	_scan = 0.0
	_reset()
	if enabled: _activate()

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F7: return
	if not is_instance_valid(_camera): return
	if _effect == null:
		_say(_t("Path tracing needs the Forward+ (Vulkan) renderer and a ray-tracing GPU"))
		return
	if key.shift_pressed:
		if not enabled: return
		lighting_view = not lighting_view
		_say(_t("Traced light only" if lighting_view else "Path tracing: on"))
	else:
		set_enabled(not enabled)
		if settings != null: settings.values.path_tracing = enabled
		_say(_t("Path tracing: on" if enabled else "Path tracing: off"))
	get_viewport().set_input_as_handled()

## Switches tracing on or off (where the renderer and GPU allow it).
func set_enabled(on: bool) -> void:
	on = on and _effect != null
	if on == enabled: return
	enabled = on
	if not on: lighting_view = false
	if enabled: _activate()
	else: _deactivate()

func _t(text: String) -> String:
	return translate.call(text) if translate.is_valid() else text

func _say(text: String) -> void:
	_label.text = text + "   " + _t("(F7 on/off, Shift+F7 light view)")
	_label.visible = true
	_label_time = 3.0

## Shadow maps and multisampling give way to the traced shadows while on;
## everything returns to the scene's own settings when tracing stops.
func _activate() -> void:
	if _effect == null or _active or not is_instance_valid(_camera): return
	_active = true
	_effect.enabled = true
	_effect.history_reset = true
	var viewport := get_viewport()
	if _saved_msaa < 0:
		_saved_msaa = viewport.msaa_3d
		_saved_aa = viewport.screen_space_aa
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	if is_instance_valid(_sun):
		_sun.set_meta("traced_shadow", _sun.shadow_enabled)
		_sun.shadow_enabled = false
	_bloom(true)
	changed.emit(true)

func _deactivate() -> void:
	if not _active: return
	_active = false
	_effect.enabled = false
	var viewport := get_viewport()
	if _saved_msaa >= 0:
		viewport.msaa_3d = _saved_msaa as Viewport.MSAA
		viewport.screen_space_aa = _saved_aa as Viewport.ScreenSpaceAA
		_saved_msaa = -1
	if is_instance_valid(_sun) and _sun.has_meta("traced_shadow"):
		# A battle's shadows follow the options, which may change meanwhile.
		_sun.shadow_enabled = bool(settings.values.get("shadows", true)) if _arena != null and settings != null else bool(_sun.get_meta("traced_shadow"))
		_sun.remove_meta("traced_shadow")
	_restore_effect_lights()
	_bloom(false)
	changed.emit(false)

func _process(delta: float) -> void:
	if _label.visible:
		_label_time -= delta
		_label.visible = _label_time > 0.0
	if _effect == null: return
	var current := get_viewport().get_camera_3d()
	if current != _camera:
		for context: Dictionary in _contexts:
			if context.camera == current and is_instance_valid(current):
				_switch(context)
				break
	if not _fx_name.is_empty(): _effect_check(delta)
	if not enabled or not _active or not is_instance_valid(_root) or current != _camera: return
	var started := Time.get_ticks_usec()
	_snapshot(delta)
	_snapshot_us = Time.get_ticks_usec() - started

func _snapshot(delta: float) -> void:
	# Options or scene effects may turn the shadow map back on.
	if is_instance_valid(_sun) and _sun.shadow_enabled: _sun.shadow_enabled = false
	if _effect.take_overflow(): _reset()
	_scan -= delta
	var ops := []
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		_models.clear()
		_static_nodes.clear()
		_collect(_root)
		_scan_statics(ops)
	var instances := []
	var live := {}
	for node: GeometryInstance3D in _static_nodes:
		if is_instance_valid(node): live[node.get_instance_id()] = true
	for model: ELModel in _models:
		if not is_instance_valid(model) or not model.is_visible_in_tree(): continue
		var morphs: Dictionary = model._previous_morphs
		for part_name: String in model.parts:
			var node: MeshInstance3D = model.parts[part_name]
			if node.mesh == null or not node.is_visible_in_tree(): continue
			var look := _surface(node)
			if look.is_empty(): continue
			var mesh: Mesh = node.mesh
			var frame := -1
			var pair: Array = morphs.get(part_name, [])
			if pair.size() == 2 and mesh.has_meta("morph_positions"):
				frame = pair[1] if node.get_blend_shape_value(pair[1]) > 0.5 else pair[0]
			var id := node.get_instance_id()
			if not _update_slot(ops, id, mesh, frame, look): continue
			live[id] = true
			instances.append([id, node.global_transform])
	for id: int in _slots.keys():
		if not live.has(id):
			ops.append(["free", id])
			_slots.erase(id)
	var sun_on := is_instance_valid(_sun) and _sun.is_visible_in_tree() and _sun.light_energy > 0.0
	var sun := _sun.light_color.srgb_to_linear() * _sun.light_energy if sun_on else Color.BLACK
	var ambient := _env.ambient_light_color.srgb_to_linear() * _env.ambient_light_energy if _env != null else Color.BLACK
	var toward := _sun.global_transform.basis.z.normalized() if is_instance_valid(_sun) else Vector3.UP
	_effect.submit(ops, instances, {
		"statics": _static_entries,
		"static_version": _static_version,
		"lights": _effect_lights(),
		"sun_direction": Vector4(toward.x, toward.y, toward.z, SUN_RADIUS),
		"sun_color": Vector4(sun.r, sun.g, sun.b, 1.0 if sun_on else 0.0),
		"ambient": Vector4(ambient.r, ambient.g, ambient.b, _arena.light_limit if _arena != null else 1000.0),
		"lighting_view": lighting_view})

## Defines a slot for a node's mesh (and the morph frame it shows) when new or
## changed. False when the mesh has nothing to trace.
func _update_slot(ops: Array, id: int, mesh: Mesh, frame: int, look: Dictionary) -> bool:
	var data := _arrays(mesh)
	if data.is_empty(): return false
	var vertices: PackedVector3Array = data.vertex
	var slot: Dictionary = _slots.get(id, {})
	var layer: Array = _layer(look.texture, look.get("solid", false))
	var flags := (1 if look.alpha and layer[1] else 0) | (2 if look.scenery else 0)
	if slot.is_empty() or slot.vertices != vertices.size() or slot.layer != layer[0] or slot.flags != flags:
		ops.append(["define", id, vertices.size(), data.index.to_byte_array(), data.uv.to_byte_array(), layer[0], flags])
		slot = {"vertices": vertices.size(), "layer": layer[0], "flags": flags, "mesh": null, "frame": -2}
		_slots[id] = slot
	if slot.mesh != mesh or slot.frame != frame:
		var positions: PackedVector3Array = vertices if frame < 0 else mesh.get_meta("morph_positions")[frame]
		ops.append(["pose", id, positions.to_byte_array()])
		slot.mesh = mesh
		slot.frame = frame
	return true

## Unmoving scenery (instanced map objects, the map's ground): its placements
## are gathered on each scan and sent only when they change.
func _scan_statics(ops: Array) -> void:
	var entries := []
	for node: GeometryInstance3D in _static_nodes:
		var look := _surface(node)
		var id := node.get_instance_id()
		var mesh: Mesh = node.multimesh.mesh if node is MultiMeshInstance3D else (node as MeshInstance3D).mesh
		if look.is_empty() or mesh == null or not _update_slot(ops, id, mesh, -1, look): continue
		var cached: Array = _static_cache.get(id, [])
		var count := 1
		if node is MultiMeshInstance3D:
			var multimesh: MultiMesh = node.multimesh
			count = multimesh.instance_count if multimesh.visible_instance_count < 0 else multimesh.visible_instance_count
		if cached.is_empty() or cached[0] != node.global_transform or cached[1] != count:
			var placed := []
			if node is MultiMeshInstance3D:
				for i in count: placed.append([id, node.global_transform * node.multimesh.get_instance_transform(i)])
			else:
				placed.append([id, node.global_transform])
			cached = [node.global_transform, count, placed]
			_static_cache[id] = cached
		entries.append_array(cached[2])
	if entries != _static_entries:
		_static_entries = entries
		_static_version += 1

func _effect_check(delta: float) -> void:
	if not is_instance_valid(_effects) or not is_instance_valid(_root) or not is_instance_valid(_camera): return
	var heroes: Array[ELModel] = []
	for child in _root.get_children():
		if child is ELModel and child.has_meta("voice"): heroes.append(child)
	if heroes.size() < 2: return
	# A fixed side view of both heroes, after the battle camera has moved.
	var from := heroes[0].global_position
	var to := heroes[1].global_position
	var middle := (from + to) * 0.5
	var span := from.distance_to(to)
	_camera.global_position = middle + (to - from).normalized().cross(Vector3.UP) * span * 0.9 + Vector3(0, span * 0.45, 0)
	_camera.look_at(middle)
	_camera.fov = 55.0
	_fx_clock -= delta
	if _fx_shot_at > 0.0:
		_fx_shot_at -= delta
		if _fx_shot_at <= 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_fx_shot)
			get_tree().quit()
	if _fx_clock > 0.0: return
	_fx_clock = 3.0
	_fx_plays += 1
	var played := _effects.play(_fx_name, {"Start": [heroes[0]], "Caster": [heroes[0]], "Source": [heroes[0]], "Target": [heroes[1]], "Finish": [heroes[1]]})
	print("Effect check: %s parts=%d" % [_fx_name, played])
	if _fx_plays == 2 and not _fx_shot.is_empty(): _fx_shot_at = _fx_delay

## Development measurement (--path-tracing-bench): alternates raster and
## traced windows in the current scene and prints GPU and CPU frame costs.
func _benchmark(window_size: String) -> void:
	_benchmarking = true
	if window_size.contains("x"):
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(int(window_size.get_slice("x", 0)), int(window_size.get_slice("x", 1)))
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var rd := RenderingServer.get_rendering_device()
	await get_tree().create_timer(15.0).timeout
	var totals := {false: [], true: []}
	for round in 6:
		enabled = round % 2 == 1
		if enabled: _activate()
		else: _deactivate()
		for i in 60: await get_tree().process_frame
		var gpu := 0.0; var cpu := 0.0; var trace := 0.0; var snap := 0.0; var traced := 0
		for i in 120:
			await RenderingServer.frame_post_draw
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
			snap += _snapshot_us / 1000.0 if enabled else 0.0
			var begin := -1
			for t in rd.get_captured_timestamps_count():
				var label := rd.get_captured_timestamp_name(t)
				if label == "Path trace begin": begin = rd.get_captured_timestamp_gpu_time(t)
				elif label == "Path trace end" and begin >= 0:
					trace += (rd.get_captured_timestamp_gpu_time(t) - begin) / 1000000.0
					traced += 1
		totals[enabled].append([gpu / 120.0, cpu / 120.0, trace / maxf(traced, 1), snap / 120.0])
	var size := Vector2(_effect._size)
	for on: bool in [false, true]:
		var rows: Array = totals[on]
		var mean := [0.0, 0.0, 0.0, 0.0]
		for row: Array in rows:
			for k in 4: mean[k] += row[k] / rows.size()
		print("PTBENCH %dx%d %s gpu_frame_ms=%.3f render_cpu_ms=%.3f trace_gpu_ms=%.3f snapshot_cpu_ms=%.3f slots=%d instances=%d" % [
			size.x, size.y, "on " if on else "off", mean[0], mean[1], mean[2], mean[3], _slots.size(), _static_entries.size()])
	get_tree().quit()

## The effects' light: each glowing particle system as one soft source, and
## the effects' own point lights (their raster light is held back meanwhile,
## so it is not counted twice). Returns packed place/colour pairs.
func _effect_lights() -> PackedFloat32Array:
	var found := []
	if is_instance_valid(_effects):
		for glow: Array in _effects.glow_sources():
			var colour: Vector3 = glow[2] * GLOW_STRENGTH
			var peak := maxf(colour.x, maxf(colour.y, colour.z))
			if peak > GLOW_LIMIT: colour *= GLOW_LIMIT / peak
			var extent := clampf(glow[1], 0.1, 3.0)
			found.append([glow[0], extent, colour, GLOW_REACH + extent * 3.0])
		for item: Dictionary in _effects.lights:
			var omni: OmniLight3D = item.node
			if omni.light_cull_mask != 0:
				omni.set_meta("cull_mask", omni.light_cull_mask)
				omni.light_cull_mask = 0
			if not item.active or not omni.is_visible_in_tree(): continue
			var c := omni.light_color.srgb_to_linear() * omni.light_energy
			found.append([omni.global_position, 0.15, Vector3(c.r, c.g, c.b), omni.omni_range])
	if found.size() > LIGHT_LIMIT:
		found.sort_custom(func(a, b): return a[2].length_squared() > b[2].length_squared())
		found.resize(LIGHT_LIMIT)
	var data := PackedFloat32Array()
	for light: Array in found:
		var p: Vector3 = light[0]
		var c: Vector3 = light[2]
		data.append_array([p.x, p.y, p.z, light[1], c.x, c.y, c.z, light[3]])
	return data

## Bloom on the scene's environment and HDR glowing particles while tracing;
## the previous settings return when it stops.
func _bloom(on: bool) -> void:
	if is_instance_valid(_effects): _effects.set_glow(EFFECT_HDR if on else 1.0)
	if _env == null: return
	var env := _env
	if on:
		if not env.has_meta("bloom_saved"):
			env.set_meta("bloom_saved", [env.glow_enabled, env.glow_hdr_threshold, env.glow_intensity, env.glow_blend_mode, env.glow_bloom])
		env.glow_enabled = true
		env.glow_hdr_threshold = BLOOM_THRESHOLD
		env.glow_intensity = BLOOM_INTENSITY
		env.glow_bloom = 0.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level in 7: env.set_glow_level(level, 1.0 if level in [1, 2, 3, 4] else 0.0)
	elif env.has_meta("bloom_saved"):
		var saved: Array = env.get_meta("bloom_saved")
		env.glow_enabled = saved[0]
		env.glow_hdr_threshold = saved[1]
		env.glow_intensity = saved[2]
		env.glow_blend_mode = saved[3]
		env.glow_bloom = saved[4]
		env.remove_meta("bloom_saved")

func _restore_effect_lights() -> void:
	if not is_instance_valid(_effects): return
	for item: Dictionary in _effects.lights:
		var omni: OmniLight3D = item.node
		if omni.has_meta("cull_mask"): omni.light_cull_mask = omni.get_meta("cull_mask")

## Figures (ELModel, traced part by part each frame) and unmoving scenery
## (instanced objects and the map's ground) under `node`.
func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is ELModel:
			_models.append(child)
			continue
		if child is Node3D and not (child as Node3D).visible: continue
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).multimesh != null and (child as MultiMeshInstance3D).multimesh.mesh != null:
			_static_nodes.append(child)
		elif child is MeshInstance3D and node is ELAdventureTerrain:
			_static_nodes.append(child)
		_collect(child)

## The traced look of a part: its albedo texture, cut-out and kind, or empty
## for parts drawn unlit or blended (left to their raster light).
func _surface(node: GeometryInstance3D) -> Dictionary:
	var material := node.material_override
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		if standard.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or standard.albedo_texture == null: return {}
		if standard.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]: return {}
		return {"texture": standard.albedo_texture, "alpha": standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "scenery": false}
	if material is ShaderMaterial and node.has_meta("albedo"):
		var texture := node.get_meta("albedo") as Texture2D
		if texture == null: return {}
		return {"texture": texture, "alpha": (material as ShaderMaterial).shader == ELArena.LIT_SHADER, "scenery": true}
	# The map's ground: its tile atlas gives one average colour for bounces.
	if node.get_parent() is ELAdventureTerrain and material is ShaderMaterial:
		var tiles := (material as ShaderMaterial).get_shader_parameter("tiles") as Texture2D
		if tiles == null: return {}
		return {"texture": tiles, "alpha": false, "scenery": false, "solid": true}
	return {}

func _arrays(mesh: Mesh) -> Dictionary:
	if _mesh_data.has(mesh): return _mesh_data[mesh]
	var result := {}
	if mesh.get_surface_count() > 0:
		var arrays := mesh.surface_get_arrays(0)
		var vertex: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			index.resize(vertex.size() - vertex.size() % 3)
			for i in index.size(): index[i] = i
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uv.size() != vertex.size(): uv.resize(vertex.size())
		if not vertex.is_empty() and not index.is_empty():
			result = {"vertex": vertex, "index": index, "uv": uv}
	_mesh_data[mesh] = result
	return result

## The texture-array layer holding a texture (uploaded on first use), and
## whether its alpha cuts anything out. `solid` stores its average colour only.
func _layer(texture: Texture2D, solid := false) -> Array:
	var key := [texture, solid]
	if _layers.has(key): return _layers[key]
	var entry := [0, false]
	if _layers.size() < LAYERS and texture != null:
		var image := texture.get_image()
		if image != null:
			image = image.duplicate()
			if image.is_compressed(): image.decompress()
			image.clear_mipmaps()
			image.convert(Image.FORMAT_RGBA8)
			if solid:
				image.resize(16, 16, Image.INTERPOLATE_BILINEAR)
				image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				var average := image.get_pixel(0, 0)
				average.a = 1.0
				image = Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
				image.fill(average)
			else:
				image.resize(LAYER_SIZE, LAYER_SIZE, Image.INTERPOLATE_BILINEAR)
			var alpha := image.detect_alpha() != Image.ALPHA_NONE
			image.generate_mipmaps()
			entry = [_layers.size(), alpha]
			_effect.queue_layer(entry[0], image.get_data())
	_layers[key] = entry
	return entry

func _reset() -> void:
	_slots.clear()
	_layers.clear()
	_mesh_data.clear()
	_static_entries = []
	_static_cache.clear()
	_static_version += 1
	_effect.queue_reset()

func _exit_tree() -> void:
	if _effect != null: _effect.release()


## The render-thread half: owns every GPU resource and runs the passes.
class Effect extends CompositorEffect:
	const SHADERS := preload("res://src/render/path_trace_shaders.gd")
	const VERTEX_CAPACITY := 1 << 20
	const CORNER_CAPACITY := 3 << 20
	const SLOT_CAPACITY := 8192
	const FRAME_BYTES := 304

	var history_reset := true
	var _mutex := Mutex.new()
	var _ops := []
	var _instances := []
	var _frame := {}
	var _overflow := false

	var _rd: RenderingDevice
	var _ready_state := 0   # 0 untried, 1 ready, -1 failed
	var _expand_shader := RID()
	var _expand_pipeline := RID()
	var _trace_shader := RID()
	var _trace_pipeline := RID()
	var _filter_shader := RID()
	var _filter_pipeline := RID()
	var _source := RID()
	var _source_uv := RID()
	var _indices := RID()
	var _corners := RID()
	var _corner_uv := RID()
	var _slot_buffer := RID()
	var _frame_buffer := RID()
	var _light_buffer := RID()
	var _albedo := RID()
	var _linear := RID()
	var _nearest := RID()
	var _tlas := RID()
	var _sbt := RID()
	var _hit_range := 0
	var _tlas_capacity := 0
	var _images: Array[RID] = []   # light 0/1, guide 0/1, filter 0/1
	var _size := Vector2i.ZERO
	var _parity := 0
	var _frame_number := 0
	var _previous_view_projection := Projection.IDENTITY
	var _previous_camera := Vector3.ZERO
	# Allocation state.
	var _next_vertex := 0
	var _next_index := 0
	var _next_corner := 0
	var _slots := {}   # id -> {index, vertex, first_index, corner, corners, vertices, blas, geometry}
	var _free_indices: Array[int] = []
	var _next_slot := 0
	var _dirty: Array[int] = []
	var _pending_layers := []
	# Unmoving scenery: its entries and their reusable instance descriptions.
	var _statics := []
	var _static_version := -1
	var _static_dirty := true
	var _static_list: Array[RDAccelerationStructureInstance] = []

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
		needs_normal_roughness = true
		enabled = false

	func submit(ops: Array, instances: Array, frame: Dictionary) -> void:
		_mutex.lock()
		_ops.append_array(ops)
		_instances = instances
		_frame = frame
		_mutex.unlock()

	func queue_layer(layer: int, data: PackedByteArray) -> void:
		_mutex.lock()
		_ops.append(["layer", layer, data])
		_mutex.unlock()

	func queue_reset() -> void:
		_mutex.lock()
		_ops.append(["reset"])
		_mutex.unlock()

	func take_overflow() -> bool:
		_mutex.lock()
		var result := _overflow
		_overflow = false
		_mutex.unlock()
		return result

	func release() -> void:
		RenderingServer.call_on_render_thread(_free_all)

	func _render_callback(_type: int, render_data: RenderData) -> void:
		if _ready_state == 0: _ready_state = 1 if _prepare() else -1
		if _ready_state < 0: return
		_mutex.lock()
		var ops := _ops
		_ops = []
		var instances := _instances
		var frame := _frame
		_mutex.unlock()
		if not frame.is_empty() and int(frame.static_version) != _static_version:
			_static_version = int(frame.static_version)
			_statics = frame.statics
			_static_dirty = true
		if not _apply_ops(ops) or frame.is_empty(): return
		var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
		var scene := render_data.get_render_scene_data()
		if buffers == null or scene == null: return
		var size := buffers.get_internal_size()
		if size.x <= 0 or size.y <= 0: return
		if size != _size: _resize(size)
		_rd.capture_timestamp("Path trace begin")
		_run(instances, buffers, scene, frame, size)
		_rd.capture_timestamp("Path trace end")

	## Scene updates (morphs, acceleration structures), tracing and filtering.
	func _run(instances: Array, buffers: RenderSceneBuffersRD, scene: RenderSceneData, frame: Dictionary, size: Vector2i) -> void:
		_expand()
		if not _build_scene(instances): return
		_trace(buffers, scene, frame, size)

	# -- setup --------------------------------------------------------------

	func _prepare() -> bool:
		_rd = RenderingServer.get_rendering_device()
		if _rd == null or not _rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE): return false
		var computes := [[SHADERS.EXPAND, "Path trace expand"], [SHADERS.FILTER, "Path trace filter"]]
		var made: Array[RID] = []
		for program: Array in computes:
			var source := RDShaderSource.new()
			source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
			source.source_compute = program[0]
			made.append(_compile(source, [RenderingDevice.SHADER_STAGE_COMPUTE], program[1]))
		var rays := RDShaderSource.new()
		rays.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		rays.set_stage_source(RenderingDevice.SHADER_STAGE_RAYGEN, SHADERS.RAYGEN)
		rays.set_stage_source(RenderingDevice.SHADER_STAGE_ANY_HIT, SHADERS.ANY_HIT)
		rays.set_stage_source(RenderingDevice.SHADER_STAGE_CLOSEST_HIT, SHADERS.CLOSEST_HIT)
		rays.set_stage_source(RenderingDevice.SHADER_STAGE_MISS, SHADERS.MISS)
		made.append(_compile(rays, [RenderingDevice.SHADER_STAGE_RAYGEN, RenderingDevice.SHADER_STAGE_ANY_HIT,
			RenderingDevice.SHADER_STAGE_CLOSEST_HIT, RenderingDevice.SHADER_STAGE_MISS], "Path trace"))
		for shader in made:
			if not shader.is_valid(): return false
		_expand_shader = made[0]; _filter_shader = made[1]; _trace_shader = made[2]
		_expand_pipeline = _rd.compute_pipeline_create(_expand_shader)
		_filter_pipeline = _rd.compute_pipeline_create(_filter_shader)
		var program := RDPipelineShader.new()
		program.shader = _trace_shader
		var group := RDHitGroup.new()
		group.closest_hit_shader = program
		group.any_hit_shader = program
		_trace_pipeline = _rd.raytracing_pipeline_create([program], [program], [group], 1)
		if not _trace_pipeline.is_valid(): return false
		_sbt = _rd.hit_sbt_create(_trace_pipeline, 1)
		if not _sbt.is_valid(): return false
		_hit_range = _rd.hit_sbt_range_alloc(_sbt, 1)
		_rd.hit_sbt_range_update(_sbt, _hit_range, 0, [0])
		_source = _rd.storage_buffer_create(VERTEX_CAPACITY * 12)
		_source_uv = _rd.storage_buffer_create(VERTEX_CAPACITY * 8)
		_indices = _rd.storage_buffer_create(CORNER_CAPACITY * 4)
		_corner_uv = _rd.storage_buffer_create(CORNER_CAPACITY * 8)
		_corners = _rd.vertex_buffer_create(CORNER_CAPACITY * 12, PackedByteArray(),
			RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT |
			RenderingDevice.BUFFER_CREATION_DEVICE_ADDRESS_BIT | RenderingDevice.BUFFER_CREATION_AS_STORAGE_BIT)
		_slot_buffer = _rd.storage_buffer_create(SLOT_CAPACITY * 16)
		_frame_buffer = _rd.storage_buffer_create(FRAME_BYTES)
		_light_buffer = _rd.storage_buffer_create(ELPathTracing.LIGHT_LIMIT * 32)
		var format := RDTextureFormat.new()
		format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
		format.width = ELPathTracing.LAYER_SIZE
		format.height = ELPathTracing.LAYER_SIZE
		format.array_layers = ELPathTracing.LAYERS
		format.mipmaps = ELPathTracing.LAYER_MIPMAPS
		format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		_albedo = _rd.texture_create(format, RDTextureView.new())
		var sampler := RDSamplerState.new()
		sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		_linear = _rd.sampler_create(sampler)
		_nearest = _rd.sampler_create(RDSamplerState.new())
		for rid: RID in [_expand_pipeline, _trace_pipeline, _filter_pipeline, _source, _source_uv, _indices, _corner_uv, _corners, _slot_buffer, _frame_buffer, _light_buffer, _albedo, _linear, _nearest]:
			if not rid.is_valid(): return false
		return true

	func _compile(source: RDShaderSource, stages: Array, label: String) -> RID:
		var spirv := _rd.shader_compile_spirv_from_source(source)
		for stage: int in stages:
			var error := spirv.get_stage_compile_error(stage)
			if not error.is_empty():
				push_error("%s: %s" % [label, error])
				return RID()
		return _rd.shader_create_from_spirv(spirv, label)

	func _resize(size: Vector2i) -> void:
		for rid in _images: if rid.is_valid(): _rd.free_rid(rid)
		_images.clear()
		var format := RDTextureFormat.new()
		format.width = size.x
		format.height = size.y
		format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		for i in 6:
			var image := _rd.texture_create(format, RDTextureView.new())
			_rd.texture_clear(image, Color(0, 0, 0, 0), 0, 1, 0, 1)
			_images.append(image)
		_size = size
		history_reset = true

	# -- scene snapshot -----------------------------------------------------

	func _apply_ops(ops: Array) -> bool:
		for op: Array in ops:
			match op[0]:
				"reset": _clear_scene()
				"layer":
					if _rd.texture_update(_albedo, op[1], op[2]) != OK: push_warning("Path tracing: texture layer upload failed")
				"define": if not _define(op): return _overflowed()
				"pose": _pose(op[1], op[2])
				"free": _free_slot(op[1])
		return true

	func _overflowed() -> bool:
		_clear_scene()
		_mutex.lock()
		_overflow = true
		_ops.clear()
		_mutex.unlock()
		return false

	func _clear_scene() -> void:
		for id: int in _slots.keys(): _free_slot(id)
		_next_vertex = 0
		_next_index = 0
		_next_corner = 0
		_next_slot = 0
		_free_indices.clear()
		_dirty.clear()
		history_reset = true

	func _define(op: Array) -> bool:
		var id: int = op[1]
		_free_slot(id)
		var vertices: int = op[2]
		var index_bytes: PackedByteArray = op[3]
		var uv_bytes: PackedByteArray = op[4]
		var corners := index_bytes.size() / 4
		if corners == 0 or corners % 3 != 0: return true
		if _next_vertex + vertices > VERTEX_CAPACITY or _next_corner + corners > CORNER_CAPACITY: return false
		var slot_index: int = _free_indices.pop_back() if not _free_indices.is_empty() else _next_slot
		if slot_index == _next_slot:
			if _next_slot >= SLOT_CAPACITY: return false
			_next_slot += 1
		var slot := {"index": slot_index, "vertex": _next_vertex, "first_index": _next_corner, "corner": _next_corner,
			"corners": corners, "vertices": vertices, "uv": true, "posed": false, "flags": op[6]}
		_next_vertex += vertices
		_next_corner += corners
		_rd.buffer_update(_indices, slot.first_index * 4, index_bytes.size(), index_bytes)
		_rd.buffer_update(_source_uv, slot.vertex * 8, mini(uv_bytes.size(), vertices * 8), uv_bytes)
		var record := PackedInt32Array([slot.corner, op[5], op[6], 0]).to_byte_array()
		_rd.buffer_update(_slot_buffer, slot_index * 16, 16, record)
		var geometry := RDAccelerationStructureGeometry.new()
		if (op[6] & 1) == 0: geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
		geometry.vertex_buffer = _corners
		geometry.vertex_offset = slot.corner * 12
		geometry.vertex_stride = 12
		geometry.vertex_count = corners
		geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
		var geometries: Array[RDAccelerationStructureGeometry] = [geometry]
		slot.blas = _rd.blas_create(geometries, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT)
		if not slot.blas.is_valid(): return false
		_slots[id] = slot
		return true

	func _pose(id: int, positions: PackedByteArray) -> void:
		var slot: Dictionary = _slots.get(id, {})
		if slot.is_empty(): return
		_rd.buffer_update(_source, slot.vertex * 12, mini(positions.size(), slot.vertices * 12), positions)
		if not _dirty.has(id): _dirty.append(id)

	func _free_slot(id: int) -> void:
		var slot: Dictionary = _slots.get(id, {})
		if slot.is_empty(): return
		_static_dirty = true
		if slot.blas.is_valid(): _rd.free_rid(slot.blas)
		_free_indices.append(slot.index)
		_slots.erase(id)
		_dirty.erase(id)

	func _expand() -> void:
		if _dirty.is_empty(): return
		var uniforms: Array[RDUniform] = [_storage(0, _source), _storage(1, _indices), _storage(2, _corners), _storage(3, _source_uv), _storage(4, _corner_uv)]
		var set := UniformSetCacheRD.get_cache(_expand_shader, 0, uniforms)
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _expand_pipeline)
		_rd.compute_list_bind_uniform_set(list, set, 0)
		for id in _dirty:
			var slot: Dictionary = _slots[id]
			var count: int = slot.corners | (0x80000000 if slot.uv else 0)
			var push := PackedInt32Array([slot.vertex, slot.first_index, slot.corner, count]).to_byte_array()
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, (slot.corners + 63) / 64, 1, 1)
			slot.uv = false
		_rd.compute_list_end()
		for id in _dirty:
			var slot: Dictionary = _slots[id]
			if _rd.blas_build(slot.blas) == OK:
				if not slot.posed: _static_dirty = true
				slot.posed = true
		_dirty.clear()

	func _build_scene(instances: Array) -> bool:
		if _static_dirty:
			_static_dirty = false
			_static_list = _describe(_statics)
		var list := _static_list.duplicate()
		list.append_array(_describe(instances))
		if list.is_empty(): return false
		if list.size() > _tlas_capacity:
			if _tlas.is_valid(): _rd.free_rid(_tlas)
			_tlas_capacity = maxi(1024, nearest_po2(list.size()))
			_tlas = _rd.tlas_create(_tlas_capacity, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT)
		return _tlas.is_valid() and _rd.tlas_build(_tlas, list) == OK

	func _describe(entries: Array) -> Array[RDAccelerationStructureInstance]:
		var list: Array[RDAccelerationStructureInstance] = []
		for entry: Array in entries:
			var slot: Dictionary = _slots.get(entry[0], {})
			if slot.is_empty() or not slot.posed: continue
			var instance := RDAccelerationStructureInstance.new()
			instance.transform = entry[1]
			instance.id = slot.index
			instance.mask = 0xFF
			instance.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
			instance.blas = slot.blas
			instance.hit_sbt_range = _hit_range
			list.append(instance)
		return list

	# -- passes -------------------------------------------------------------

	func _trace(buffers: RenderSceneBuffersRD, scene: RenderSceneData, frame: Dictionary, size: Vector2i) -> void:
		var camera := scene.get_cam_transform()
		var projection := scene.get_cam_projection()
		var view_projection := projection * Projection(camera.affine_inverse())
		var flags := (1 if history_reset else 0) | (2 if frame.lighting_view else 0) | (4 if OS.get_cmdline_user_args().has("--path-tracing-debug") else 0)
		history_reset = false
		var data := PackedByteArray()
		data.resize(FRAME_BYTES)
		var at := 0
		for matrix: Projection in [projection.inverse(), Projection(camera), _previous_view_projection]:
			for column: Vector4 in [matrix.x, matrix.y, matrix.z, matrix.w]:
				at = _put4(data, at, column)
		at = _put4(data, at, Vector4(camera.origin.x, camera.origin.y, camera.origin.z, 1.0))
		at = _put4(data, at, Vector4(_previous_camera.x, _previous_camera.y, _previous_camera.z, 1.0))
		for key in ["sun_direction", "sun_color", "ambient"]: at = _put4(data, at, frame[key])
		var lights: PackedFloat32Array = frame.lights
		var light_count := lights.size() / 8
		if light_count > 0: _rd.buffer_update(_light_buffer, 0, lights.size() * 4, lights.to_byte_array())
		# Effect light changes quickly: a shorter history keeps it from smearing.
		for value in [_frame_number, size.x, size.y, flags, light_count, 12 if light_count > 0 else 48, 0, 0]:
			data.encode_u32(at, value)
			at += 4
		_rd.buffer_update(_frame_buffer, 0, FRAME_BYTES, data)
		_previous_view_projection = view_projection
		_previous_camera = camera.origin
		_frame_number += 1

		var albedo := RDUniform.new()
		albedo.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		albedo.binding = 5
		albedo.add_id(_linear)
		albedo.add_id(_albedo)
		var tlas := RDUniform.new()
		tlas.uniform_type = RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE
		tlas.binding = 1
		tlas.add_id(_tlas)
		var frame_uniform := RDUniform.new()
		frame_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		frame_uniform.binding = 0
		frame_uniform.add_id(_frame_buffer)
		var common: Array[RDUniform] = [frame_uniform, tlas, _storage(2, _corners), _storage(3, _corner_uv), _storage(4, _slot_buffer), albedo, _storage(6, _light_buffer)]

		var previous := _parity
		var current := 1 - _parity
		_parity = current
		var light: Array[RID] = [_images[0], _images[1]]
		var guide: Array[RID] = [_images[2], _images[3]]
		var depth := RDUniform.new()
		depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth.binding = 0
		depth.add_id(_nearest)
		depth.add_id(buffers.get_depth_layer(0))
		var normal := RDUniform.new()
		normal.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		normal.binding = 1
		normal.add_id(_nearest)
		normal.add_id(buffers.get_texture("forward_clustered", "normal_roughness"))
		var trace_set: Array[RDUniform] = [depth, normal, _image(2, light[previous]), _image(3, guide[previous]), _image(4, light[current]), _image(5, guide[current])]
		var groups := Vector3i((size.x + 7) / 8, (size.y + 7) / 8, 1)
		var rays := _rd.raytracing_list_begin()
		_rd.raytracing_list_bind_raytracing_pipeline(rays, _trace_pipeline)
		_rd.raytracing_list_bind_uniform_set(rays, UniformSetCacheRD.get_cache(_trace_shader, 0, common), 0)
		_rd.raytracing_list_bind_uniform_set(rays, UniformSetCacheRD.get_cache(_trace_shader, 1, trace_set), 1)
		_rd.raytracing_list_trace_rays(rays, 0, _sbt, size.x, size.y, 1)
		_rd.raytracing_list_end()

		var frame_only: Array[RDUniform] = [frame_uniform]
		var color := buffers.get_color_layer(0)
		var passes := [[light[current], _images[4], 1, 0], [_images[4], _images[5], 2, 0], [_images[5], _images[4], 4, 1]]
		for step: Array in passes:
			var filter_set: Array[RDUniform] = [_image(0, step[0]), _image(1, guide[current]), _image(2, step[1]), _image(3, color)]
			var push := PackedInt32Array([step[2], step[3], 0, 0]).to_byte_array()
			var list := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(list, _filter_pipeline)
			_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_filter_shader, 0, frame_only), 0)
			_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_filter_shader, 1, filter_set), 1)
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
			_rd.compute_list_end()

	static func _put4(data: PackedByteArray, at: int, v: Vector4) -> int:
		data.encode_float(at, v.x)
		data.encode_float(at + 4, v.y)
		data.encode_float(at + 8, v.z)
		data.encode_float(at + 12, v.w)
		return at + 16

	static func _storage(binding: int, buffer: RID) -> RDUniform:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffer)
		return uniform

	static func _image(binding: int, texture: RID) -> RDUniform:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = binding
		uniform.add_id(texture)
		return uniform

	func _free_all() -> void:
		if _rd == null: return
		_clear_scene()
		var owned: Array[RID] = [_tlas, _sbt, _expand_pipeline, _trace_pipeline, _filter_pipeline, _expand_shader, _trace_shader, _filter_shader,
			_source, _source_uv, _indices, _corner_uv, _corners, _slot_buffer, _frame_buffer, _light_buffer, _albedo, _linear, _nearest]
		owned.append_array(_images)
		for rid in owned:
			if rid.is_valid(): _rd.free_rid(rid)
		_images.clear()
		_tlas = RID()
		_sbt = RID()
		_tlas_capacity = 0
		_ready_state = 0
