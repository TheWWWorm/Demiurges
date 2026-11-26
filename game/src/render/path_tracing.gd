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
##
## With NVIDIA DLSS upscaling and the "ray_reconstruction" setting (engines
## with the SDK, ELGraphicsSDK), DLSS Ray Reconstruction removes the noise
## instead: one fresh sample a pixel, no temporal or spatial smoothing, rays cast
## with the renderer's jittered camera, and the relit colour handed over with
## four guides at the internal size (diffuse albedo, specular albedo, world
## normal and roughness, specular hit distance).
##
## The traced scene has fixed budgets (geometry ranges, objects, texture
## layers). Freed geometry is reused, a fragmented budget is packed by a
## rebuild, and what cannot fit at all keeps its raster light (warned once).
## limits_report holds the counts; --path-tracing-stats prints them.

signal changed(active: bool)

const LAYER_SIZE := 256
const LAYER_MIPMAPS := 9
const LAYERS := 192
const SURFACE_ALPHA := 1
const SURFACE_SCENERY := 2
const SURFACE_GROUND := 4
const SURFACE_EMISSION := 8
const SURFACE_EMISSION_MULTIPLY := 16
const SURFACE_FULLBRIGHT := 64
const SURFACE_SOFT_EMITTER := 128
const SURFACE_SOFT_CUTOUT := 256
const SURFACE_ARENA_FLOOR := 512
const SURFACE_ARENA_SCENERY := 1024
const SURFACE_PRIMARY_CULL_BACK := 2048
const SURFACE_PRIMARY_CULL_FRONT := 4096
## Unlit adventure-map scenery, which takes the traced sun's shadow.
const SURFACE_UNLIT_SHADOWED := 8192
## Metal (ELFigure.metal_material), traced with a glossy reflection where
## its mask (in the emission layer's place) says.
const SURFACE_METAL := 16384
## A figure's feather, hair or cloth card (ELFigure.is_soft_part, cut out):
## thin, so it passes some sun to its far side and some through its cuts.
const SURFACE_THIN := 32768
const SURFACE_CLAMP_UV := 32
## Angular radius of the sun's disc (tangent), which sets shadow softness.
const SUN_RADIUS := 0.02
## Effect lights traced at once. Authored point lights have priority over glow.
const LIGHT_LIMIT := 64
## Light given off per unit of summed particle colour, and its reach.
const GLOW_STRENGTH := 1.0
## Brightest colour component one effect light may reach. A dense aura sums
## to a very bright source (a hero's glowing weapon passes 8), which bleached
## the ground around it; capped, it still lights its surroundings.
const GLOW_LIMIT := 2.5
## The same for a spell's passing fire (not the arena's own fires, not a
## figure's glow): a wall of fire sweeping over a hero outshines the sun
## beside it, and the hero's shadow swings away from it as it passes.
const SPELL_GLOW_LIMIT := 8.0
## A spell's patches closer than this are one light (ELGlowLights.merged):
## a wall of fire stays a row of lights a patch apart, so the stretch nearest
## a figure lights it and the figure's shadow falls straight away from it.
## Joined at the raster lamps' distance it was four lights a few metres
## apart, none of them behind the figure, and its shadow was a faint streak.
const SPELL_MERGE := 1.0
## How far an effect's light carries, before its own size: two units are a
## metre, and a wall of fire lights the ground several metres around it, so
## a figure beside one stands in its light and throws a shadow from it.
const GLOW_REACH := 9.0
## A spell's large fire carries further: a bolt or a wall of fire lights the
## ring around it, not only the figure it strikes.
const SPELL_GLOW_REACH := 20.0
## The arena's own fires and glows (steady sources) are its lamps, hung high
## and far apart: their light carries across the ring.
const ARENA_GLOW_REACH := 14.0
## Scene membership is re-read this often (seconds).
const SCAN_INTERVAL := 0.5
## The adventure map traces only the ground the camera sees and this much
## round it (world units; a map cell is 2): sun rays from tall objects and
## light bounced off their sides reach no further worth seeing. A revealed
## map otherwise sends every object on it to the ray scene each frame.
const TRACE_MARGIN := 40.0
## The region moves in steps of this size, so a scrolling camera rarely
## changes what is traced.
const TRACE_STEP := 16.0
## Where rays along the view's edges that miss the ground are cut short.
const TRACE_FAR := 240.0

var enabled := false
var lighting_view := false
var settings: ELSettings
## Puts the on-screen messages into the game's language (English as given).
var translate: Callable

var _effect: Effect
# Registered scenes: {camera, root, sun, environment, effects, arena}.
var _contexts: Array[Dictionary] = []
var _active := false     # tracing asked for on the current context
var _committed := false  # its GPU side is ready and the lighting switched over
## Why the GPU side could not be set up, once it failed ("" while it has not).
var failure_report := ""
var _camera: Camera3D
var _root: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _arena: ELArena
var _effects: ELCombatEffects
var _adventure_effects: ELAdventureEffects
var _models: Array[ELModel] = []
var _static_nodes: Array[GeometryInstance3D] = []
var _static_entries := []
## The scan's placements before the trace region is applied: the map's
## ground (always traced) and the instanced map objects (cut to the region).
var _static_ground := []
var _static_objects := []
var _static_cache := {}   # node id -> [global transform, instance count, entries]
var _static_version := 0
## The adventure map's traced region (x, z in world units); empty traces all.
var _region := Rect2()
## Map objects (figures on the adventure map) unchanged since they were last
## read: model id -> [global transform, pose count, parts, part states, live
## ids, group]. A fully revealed map holds hundreds of them, nearly all still
## (off screen their poses wait), and reading every part each frame cost more
## than the tracing. A held model is read again when it moves, changes pose,
## swaps a part's mesh or material or shows or hides a part (HELD_PART_CHECK),
## and one model a frame in turn regardless.
var _held_models := {}
## Held objects' parts are compared every this many frames (a quarter each
## frame): a swapped material or a hidden part is traced a few frames late.
const HELD_PART_CHECK := 4
var _held_version := 0
## The held objects' group versions last sent, and the count that names them.
var _held_key := PackedInt64Array()
var _held_list := 0
var _verify_next := 0
var _scan := 0.0
## The figures' own lights as last traced: [place, extent, colour, reach].
var _figure_lights := []
var _label: Label
var _label_time := 0.0
# Main-thread snapshot state, cleared together with the GPU side on a reset.
var _slots := {}          # node id -> {mesh, pose, look, flags}
var _layers := {}         # [texture, solid] -> [layer (-1 none), has alpha]
var _texture_revision := 0
var _next_layer := 0
var _layer_keys := []     # layer -> its [texture, solid] key (null when free)
var _free_layers: Array[int] = []
var _averages := {}       # [texture, solid] -> linear average colour
# Layers handed out during the current snapshot, which no slot holds yet.
var _pinned := {}
# Material records re-sent because their texture gave its layer up.
var _layer_ops := []
var _layer_counts := {"textures": 0, "evicted": 0, "given_up": 0, "without_layer": 0}
var _stats_clock := 0.0
static var _layers_warned := false
## The traced scene's budget as last read (geometry ranges, objects, texture
## layers, rebuilds), for the status file and --path-tracing-stats.
static var limits_report := {}
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
## DLSS Ray Reconstruction this run, for the graphics status file: whether it
## was asked for last frame and how many frames' guides the engine took or
## refused.
static var ray_reconstruction_report := {}

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
		elif arg.begins_with("--path-tracing-fail="): Effect.test_failure = arg.get_slice("=", 1)
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
	_adventure_effects = null
	if _arena == null:
		for child: Node in _root.get_children():
			if child is ELAdventureEffects and child.profile != null and child.profile.id == "el2":
				_adventure_effects = child
				break
	_models.clear()
	_static_nodes.clear()
	_static_entries.clear()
	_static_cache.clear()
	_held_models.clear()
	_scan = 0.0
	_reset()
	if enabled: _activate()

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F7: return
	if _effect == null:
		# Said even where no scene is traced (the Compatibility renderer has none).
		if RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_current_rendering_driver_name() != "vulkan":
			_say(_t("Path tracing needs Vulkan: choose Forward+ (Vulkan) in Options and restart the game"))
		else:
			_say(_t("Path tracing needs a GPU with hardware ray tracing"))
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(_camera): return
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
	on = on and _effect != null and _effect.state() != Effect.FAILED
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
## everything returns to the scene's own settings when tracing stops. The
## GPU side is set up on the render thread first (its programs, buffers and
## images): the lighting switches over only once that has worked (_commit),
## and a failure leaves the raster lighting as it was (_give_up).
func _activate() -> void:
	if _effect == null or _active or not is_instance_valid(_camera): return
	_active = true
	# The traced scene is rebuilt from scratch whenever tracing starts: the
	# scene may have changed meanwhile, and a stale copy lost its objects
	# (no shadows on a map after switching tracing off and on).
	_reset()
	_scan = 0.0
	_effect.enabled = true
	_effect.history_reset = true
	if _effect.state() == Effect.READY: _commit()

func _commit() -> void:
	if _committed: return
	_committed = true
	var viewport := get_viewport()
	if _saved_msaa < 0:
		_saved_msaa = viewport.msaa_3d
		_saved_aa = viewport.screen_space_aa
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = _traced_antialiasing()
	if is_instance_valid(_sun):
		_sun.set_meta("traced_shadow", _sun.shadow_enabled)
		_sun.shadow_enabled = false
	_bloom(true)
	if is_instance_valid(_arena): _arena.set_secondary_traced(true)
	changed.emit(true)

## After the display options were applied again (closing the original
## Options or a question box does this): the options' anti-aliasing becomes
## the one restored when tracing stops, and tracing keeps multisampling off,
## which the traced image cannot be composed onto.
func display_applied() -> void:
	if not _committed: return
	var viewport := get_viewport()
	_saved_msaa = viewport.msaa_3d
	_saved_aa = viewport.screen_space_aa
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = _traced_antialiasing()
	_effect.history_reset = true

func _traced_antialiasing() -> Viewport.ScreenSpaceAA:
	# Small changes in traced light make post AA switch abruptly between the
	# bright wood and the dark sides of Ship's thin rigging and railings.
	if is_instance_valid(_arena) and _arena.scene_id == "Ship.001": return Viewport.SCREEN_SPACE_AA_DISABLED
	# An SDK upscaler smooths the whole image itself.
	if settings != null and ELGraphicsSDK.active_upscaler(settings.values) != ELGraphicsSDK.OFF: return Viewport.SCREEN_SPACE_AA_DISABLED
	return Viewport.SCREEN_SPACE_AA_FXAA

## The GPU side could not be set up (or lost its images): tracing stops,
## the raster lighting and anti-aliasing come back, and nothing more is
## sent to the render thread.
func _give_up() -> void:
	_deactivate()
	enabled = false
	lighting_view = false
	failure_report = _effect.failure()
	push_warning("Path tracing stopped: " + failure_report)
	_say(_t("Path tracing could not start on this GPU"))

func _deactivate() -> void:
	if not _active: return
	_active = false
	_effect.enabled = false
	if not _committed: return
	_committed = false
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
	if is_instance_valid(_arena): _arena.set_secondary_traced(false)
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
	if _active:
		match _effect.state():
			Effect.READY: _commit()
			Effect.FAILED: _give_up()
	if not enabled or not _committed or not is_instance_valid(_root) or current != _camera: return
	var started := Time.get_ticks_usec()
	_snapshot(delta)
	_snapshot_us = Time.get_ticks_usec() - started

func _snapshot(delta: float) -> void:
	if _texture_revision != ELIconUpscale.texture_revision:
		_reset()
		_scan = 0.0
		_effect.history_reset = true
	# Options or scene effects may turn the shadow map back on.
	if is_instance_valid(_sun) and _sun.shadow_enabled: _sun.shadow_enabled = false
	if _effect.take_overflow():
		# The render thread's ranges are fragmented: every object is sent anew
		# (the textures stay), packed, in this frame's batch.
		_slots.clear()
		_held_models.clear()
		_effect.queue_reset(false)
		_scan = 0.0
	_scan -= delta
	_pinned.clear()
	var ops := []
	var region := _trace_region()
	var region_moved := region != _region
	_region = region
	if _scan <= 0.0:
		_scan = SCAN_INTERVAL
		_models.clear()
		_static_nodes.clear()
		_collect(_root)
		_scan_statics(ops)
	elif region_moved: _cut_statics()
	var instances := []
	var groups := []
	var held_key := PackedInt64Array()
	var held_now := {}
	var live := {}
	for node: GeometryInstance3D in _static_nodes:
		if is_instance_valid(node) and _slots.has(node.get_instance_id()): live[node.get_instance_id()] = true
	var verify := _verify_next % maxi(_models.size(), 1)
	_verify_next += 1
	var model_index := -1
	for model: ELModel in _models:
		model_index += 1
		if not is_instance_valid(model) or not model.is_visible_in_tree(): continue
		var map_object := model.get_parent() is ELAdventureScene
		var model_id := model.get_instance_id()
		if map_object and region.has_area() and not region.has_point(Vector2(model.global_position.x, model.global_position.z)):
			# Beyond the region: kept (slots and all) but not traced.
			var away: Array = _held_models.get(model_id, [])
			if not away.is_empty():
				live.merge(away[4])
				held_now[model_id] = away
			continue
		if map_object and model_index != verify:
			var held: Array = _held_models.get(model_id, [])
			if not held.is_empty() and _still_held(model, held, (model_index + _verify_next) % HELD_PART_CHECK == 0):
				live.merge(held[4])
				groups.append(held[5])
				held_key.append(held[5][1])
				held_now[model_id] = held
				continue
		var morphs: Dictionary = model._previous_morphs
		var effect := model.get_parent() is ELCombatEffects
		var arena_floor := is_instance_valid(_arena) and _arena.is_surface(model)
		var looks := {}
		# A map object drawn entirely unlit is scenery (a figure's unlit parts
		# are its magic glow, which shadows would dim).
		var unlit_scenery := map_object
		# Soft (blended) looks can fade in place, unseen by _still_held.
		var holdable := map_object
		for part_name: String in model.parts:
			var node: MeshInstance3D = model.parts[part_name]
			if node.mesh == null or not node.is_visible_in_tree(): continue
			var look := _surface(node, effect)
			if look.is_empty(): continue
			looks[part_name] = look
			if (int(look.flags) & SURFACE_FULLBRIGHT) == 0: unlit_scenery = false
			if (int(look.flags) & SURFACE_SOFT_EMITTER) != 0: holdable = false
		var entries := []
		var entry_live := {}
		for part_name: String in looks:
			var node: MeshInstance3D = model.parts[part_name]
			var look: Dictionary = looks[part_name]
			if unlit_scenery: look.flags |= SURFACE_UNLIT_SHADOWED
			if look.has("cutoff") and ELFigure.is_soft_part(part_name): look.flags |= SURFACE_THIN
			if arena_floor:
				look.flags |= SURFACE_ARENA_FLOOR
			elif is_instance_valid(_arena) and _arena.is_normal_secondary_receiver(model, node):
				look.flags |= SURFACE_ARENA_SCENERY
			var mesh: Mesh = node.mesh
			var frame := -1
			var next_frame := -1
			var weight := 0.0
			var pair: Array = morphs.get(part_name, [])
			if pair.size() == 2 and mesh.has_meta("morph_positions"):
				frame = pair[0]
				if pair[1] != frame:
					next_frame = pair[1]
					weight = node.get_blend_shape_value(next_frame)
			var id := node.get_instance_id()
			if not _update_slot(ops, id, mesh, frame, look, next_frame, weight): continue
			entry_live[id] = true
			entries.append([id, node.global_transform])
		live.merge(entry_live)
		if holdable:
			var nodes := []
			var states := []
			for node: MeshInstance3D in model.parts.values():
				nodes.append(node)
				states.append_array([node.mesh, node.material_override, node.visible])
			var before: Array = _held_models.get(model_id, [])
			if not before.is_empty() and before[5][2] == entries:
				# Read again in turn (or re-dressed in place): placed as it was.
				held_now[model_id] = [model.global_transform, model.sample_count, nodes, states, entry_live, before[5]]
				groups.append(before[5])
				held_key.append(before[5][1])
				continue
			_held_version += 1
			held_now[model_id] = [model.global_transform, model.sample_count, nodes, states, entry_live, [model_id, _held_version, entries]]
		# Read anew this frame (likely to change again): traced as moving.
		instances.append_array(entries)
	_held_models = held_now
	if held_key != _held_key:
		_held_key = held_key
		_held_list += 1
	# Everything live holds a slot, so equal counts mean nothing to free.
	if live.size() != _slots.size():
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
		"groups": groups,
		"held_list": _held_list,
		"lights": _effect_lights(delta),
		"secondary_lights": _secondary_lights(),
		"sun_direction": Vector4(toward.x, toward.y, toward.z, SUN_RADIUS),
		"sun_color": Vector4(sun.r, sun.g, sun.b, 1.0 if sun_on else 0.0),
		"ambient": Vector4(ambient.r, ambient.g, ambient.b, _arena.light_limit if _arena != null else 1000.0),
		"lighting_view": lighting_view,
		"sky_light": float(settings.values.get("sky_light", 1.0)) if settings != null else 1.0,
		"backdrop": _arena.backdrop_colour if _arena != null else Color.BLACK,
		"bounces": clampi(int(settings.values.get("light_bounces", 2)), 1, 4) if settings != null else 2,
		"ray_reconstruction": _ray_reconstruction()})
	ray_reconstruction_report = _effect.reconstruction_report()
	_stats_clock -= delta
	if _stats_clock <= 0.0:
		_stats_clock = 2.0
		_update_limits()

## Whether a held map object still shows what was read: the same place and
## pose and, when `parts`, part by part the same mesh, material and visibility
## (every part hangs from the model itself, which the caller found visible).
func _still_held(model: ELModel, held: Array, parts: bool) -> bool:
	if held[1] != model.sample_count or held[0] != model.global_transform: return false
	if not parts: return true
	var nodes: Array = held[2]
	if nodes.size() != model.parts.size(): return false
	var states: Array = held[3]
	var k := 0
	for node: Variant in nodes:
		if not is_instance_valid(node): return false
		var part := node as MeshInstance3D
		if part.mesh != states[k] or part.material_override != states[k + 1] or part.visible != states[k + 2]: return false
		k += 3
	return true

## Reads the budget (limits_report) and, with --path-tracing-stats, prints it.
func _update_limits() -> void:
	var report := _effect.limits()
	var held := {}
	for slot: Dictionary in _slots.values():
		for layer: int in slot.get("layers", []):
			if layer >= 0: held[layer] = true
	report.layers = {"used": held.size(), "allocated": _next_layer - _free_layers.size(), "capacity": LAYERS}
	report.textures = _layer_counts.duplicate()
	limits_report = report
	if not OS.get_cmdline_user_args().has("--path-tracing-stats") or report.is_empty() or not report.has("vertices"): return
	var line := "PTLIMITS"
	for name: String in ["vertices", "corners", "normals", "objects", "layers"]:
		var part: Dictionary = report[name]
		line += " %s=%d/%d/%d" % [name, part.used, part.allocated, part.capacity]
	line += " rebuilds=%d skipped=%d over_budget=%d textures=%d evicted=%d given_up=%d without_layer=%d" % [report.rebuilds, report.skipped,
		report.skipped_over_budget, report.textures.textures, report.textures.evicted, report.textures.given_up, report.textures.without_layer]
	print(line)

## DLSS Ray Reconstruction replaces the tracer's own smoothing: chosen, with
## DLSS upscaling rendering on an engine that takes the guides, and the
## ordinary picture shown (not the light view or the debug view).
func _ray_reconstruction() -> bool:
	if settings == null or lighting_view or not bool(settings.values.get("ray_reconstruction", false)): return false
	if OS.get_cmdline_user_args().has("--path-tracing-debug"): return false
	return ELGraphicsSDK.ray_reconstruction_active(settings.values)

## Defines a slot for a node's mesh (and the morph pose it shows) when new or
## changed. False when the mesh has nothing to trace.
func _update_slot(ops: Array, id: int, mesh: Mesh, frame: int, look: Dictionary, next_frame := -1, weight := 0.0) -> bool:
	var data := _arrays(mesh)
	if data.is_empty(): return false
	var vertices: PackedVector3Array = data.vertex
	var slot: Dictionary = _slots.get(id, {})
	if slot.is_empty() or slot.mesh != mesh or slot.look != look:
		var material := _material(look)
		# Records of slots whose texture gave its layer up here, in order.
		ops.append_array(_layer_ops)
		_layer_ops.clear()
		var record: PackedByteArray = material[0]
		var flags: int = material[1]
		var geometry_flags := SURFACE_ARENA_SCENERY
		if slot.is_empty() or slot.mesh != mesh or (slot.flags & geometry_flags) != (flags & geometry_flags):
			var normals := PackedByteArray()
			if (flags & SURFACE_ARENA_SCENERY) != 0:
				normals = _secondary_corner_normals(mesh, data.index)
			ops.append(["define", id, vertices.size(), data.index.to_byte_array(), data.uv.to_byte_array(), normals])
			slot = {}
		ops.append(["material", id, record])
		slot.look = look
		slot.flags = flags
		slot.layers = material[2]
		slot.mesh = mesh
		_slots[id] = slot
	var pose := Vector3(frame, next_frame, weight)
	if slot.get("pose") != pose:
		var positions: PackedVector3Array = vertices if frame < 0 else mesh.get_meta("morph_positions")[frame]
		if next_frame >= 0 and weight > 0.0:
			# Match the raster mesh's normalized blend between the two frames.
			var next: PackedVector3Array = mesh.get_meta("morph_positions")[next_frame]
			positions = positions.duplicate()
			for i in positions.size(): positions[i] = positions[i].lerp(next[i], weight)
		ops.append(["pose", id, positions.to_byte_array()])
		slot.pose = pose
	return true

static func _secondary_corner_normals(mesh: Mesh, indices: PackedInt32Array) -> PackedByteArray:
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var corners := PackedVector3Array()
	corners.resize(indices.size())
	for corner in indices.size():
		corners[corner] = normals[indices[corner]]
	return corners.to_byte_array()

## A surface's material record, its flags (with SURFACE_ALPHA where its
## texture's alpha cuts) and the two layers it samples: [record, flags, layers].
## A texture left without a layer (the array is full) is traced in its
## average colour and keeps its alpha classification, though without texels
## to test its cut is traced solid (cutouts take layers first, see _layer).
func _material(look: Dictionary) -> Array:
	var flags: int = look.get("flags", 0)
	var texture: Texture2D = look.texture
	var albedo := _layer(texture, look.get("solid", false))
	var cutoff: float = look.get("cutoff", 0.0)
	if cutoff > 1.0 or (cutoff > 0.0 and albedo[1]) or (flags & SURFACE_SOFT_EMITTER) != 0:
		flags |= SURFACE_ALPHA
	# Metal has no emission: that layer carries where its texels are metal.
	var second_texture: Texture2D = look.get("emission_texture") if (flags & SURFACE_EMISSION) != 0 else look.get("metal_texture")
	var second := _layer(second_texture)
	var shown := look.duplicate()
	if albedo[0] < 0 and texture != null:
		var average := _average(texture, look.get("solid", false))
		var tint: Color = look.get("tint", Color.WHITE)
		shown.tint = Color(tint.r * average.r, tint.g * average.g, tint.b * average.b, tint.a)
		# Metal judged from texel colours has none to judge: diffuse instead.
		if (flags & SURFACE_METAL) != 0 and second[0] < 0: flags &= ~SURFACE_METAL
	if second[0] < 0 and second_texture != null and (flags & SURFACE_EMISSION) != 0:
		var average := _average(second_texture, false)
		var emission: Color = look.get("emission", Color.BLACK)
		if (flags & SURFACE_EMISSION_MULTIPLY) != 0:
			shown.emission = Color(emission.r * average.r, emission.g * average.g, emission.b * average.b)
			flags &= ~SURFACE_EMISSION_MULTIPLY
		else:
			shown.emission = Color(emission.r + average.r, emission.g + average.g, emission.b + average.b)
	return [_material_record(shown, albedo[0], second[0], flags), flags, [albedo[0], second[0]]]

static func _material_record(look: Dictionary, layer: int, emission_layer: int, flags: int) -> PackedByteArray:
	var tint: Color = look.get("tint", Color.WHITE)
	var emission: Color = look.get("emission", Color.BLACK)
	var uv: Vector4 = look.get("uv", Vector4(1, 1, 0, 0))
	# The render thread fills the first corner. The remaining fields match Slot
	# in the ray shaders, with all vectors aligned to 16 bytes.
	var record := PackedInt32Array([0, layer, flags, emission_layer]).to_byte_array()
	record.append_array(PackedFloat32Array([
		tint.r, tint.g, tint.b, look.get("opacity", look.get("cutoff", 0.0)),
		emission.r, emission.g, emission.b, look.get("emission_energy", 0.0),
		uv.x, uv.y, uv.z, uv.w]).to_byte_array())
	return record

## Unmoving scenery (instanced map objects, the map's ground): its placements
## are gathered on each scan and sent only when they change.
func _scan_statics(ops: Array) -> void:
	var ground := []
	var objects := []
	for node: GeometryInstance3D in _static_nodes:
		var look := _surface(node)
		if not look.is_empty() and (int(look.flags) & SURFACE_FULLBRIGHT) != 0 and node.get_parent() is ELAdventureScene:
			look.flags |= SURFACE_UNLIT_SHADOWED
		var id := node.get_instance_id()
		var mesh: Mesh = node.multimesh.mesh if node is MultiMeshInstance3D else (node as MeshInstance3D).mesh
		if look.is_empty() or mesh == null or not _update_slot(ops, id, mesh, -1, look): continue
		var cached: Array = _static_cache.get(id, [])
		var count := 1
		var fog_colours := false
		# Instances change in place too: map objects hidden under the fog are
		# shown by their instance transforms, which the count does not see.
		var placement := 0
		if node is MultiMeshInstance3D:
			var multimesh: MultiMesh = node.multimesh
			count = multimesh.instance_count if multimesh.visible_instance_count < 0 else multimesh.visible_instance_count
			var material := node.material_override as BaseMaterial3D
			fog_colours = node.get_parent() is ELAdventureScene and multimesh.use_colors and material != null and material.vertex_color_use_as_albedo
			# The map records updates as they are written. Static batches need
			# no render-server buffer readback just to check whether they moved.
			if node.has_meta(ELAdventureScene.PLACEMENT_REVISION):
				placement = int(node.get_meta(ELAdventureScene.PLACEMENT_REVISION)) * 2 + int(fog_colours)
			else: placement = hash([multimesh.buffer, fog_colours])
		if cached.is_empty() or cached[0] != node.global_transform or cached[1] != count or cached[3] != placement:
			var placed := []
			if node is MultiMeshInstance3D:
				var multimesh: MultiMesh = node.multimesh
				for i in count:
					var transform := multimesh.get_instance_transform(i)
					# The adventure map hides undiscovered objects with zero scale.
					if transform.basis == Basis.from_scale(Vector3.ZERO): continue
					var placement_row := [id, node.global_transform * transform]
					if fog_colours: placement_row.append(roundi(multimesh.get_instance_color(i).r * 255.0))
					placed.append(placement_row)
			else:
				placed.append([id, node.global_transform])
			cached = [node.global_transform, count, placed, placement]
			_static_cache[id] = cached
		if node is MultiMeshInstance3D and node.get_parent() is ELAdventureScene: objects.append_array(cached[2])
		else: ground.append_array(cached[2])
	_static_ground = ground
	_static_objects = objects
	_cut_statics()

## The scanned placements within the trace region, sent when they change.
func _cut_statics() -> void:
	var entries := _static_ground.duplicate()
	if not _region.has_area(): entries.append_array(_static_objects)
	else:
		for row: Array in _static_objects:
			var at: Vector3 = (row[1] as Transform3D).origin
			if _region.has_point(Vector2(at.x, at.z)): entries.append(row)
	if entries != _static_entries:
		_static_entries = entries
		_static_version += 1

## The adventure map's trace region: where the view's corners and centre meet
## the ground, grown by TRACE_MARGIN and snapped out to TRACE_STEP. Empty in
## battles, which trace everything.
func _trace_region() -> Rect2:
	if is_instance_valid(_arena) or not _root is ELAdventureScene or not is_instance_valid(_camera): return Rect2()
	var size := _camera.get_viewport().get_visible_rect().size
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size, size * 0.5]:
		var origin := _camera.project_ray_origin(corner)
		var direction := _camera.project_ray_normal(corner)
		var reach := TRACE_FAR
		if direction.y < -0.0001: reach = minf(reach, -origin.y / direction.y)
		var at := origin + direction * maxf(reach, 0.0)
		low = Vector2(minf(low.x, at.x), minf(low.y, at.z))
		high = Vector2(maxf(high.x, at.x), maxf(high.y, at.z))
	low = ((low - Vector2.ONE * TRACE_MARGIN) / TRACE_STEP).floor() * TRACE_STEP
	high = ((high + Vector2.ONE * TRACE_MARGIN) / TRACE_STEP).ceil() * TRACE_STEP
	return Rect2(low, high - low)

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
## the effects' own point lights. Only transparent additive models keep their
## raster light while the opaque pass traces it. Returns packed place/colour pairs.
func _effect_lights(delta := 0.0) -> PackedFloat32Array:
	var found := []
	var figure := []
	var glows := _effects.glow_sources(ELCombatEffects.TRACED_SPELL_GLOW, false) if is_instance_valid(_effects) else []
	if is_instance_valid(_adventure_effects): glows.append_array(_adventure_effects.glow_sources())
	# One effect splits into patches; close ones are one source of light, as
	# the raster lamps already see them. Fewer, stronger lights make the one
	# shadow ray a pixel spends on them land on the light that matters.
	glows = ELGlowLights.merged(glows, SPELL_MERGE)
	for glow: Array in glows:
		var colour: Vector3 = glow[2] * GLOW_STRENGTH
		var peak := maxf(colour.x, maxf(colour.y, colour.z))
		var steady: bool = glow.size() > 3 and glow[3]
		var kind := int(glow[4]) if glow.size() > 4 else 0
		# Only a spell's large fire (ELCombatEffects.FIRE_PATCHES) takes the
		# fire's strength and falloff. The map's glows and a spell wrapped
		# round one figure light as lamps do: given a wall of fire's strength
		# that close, they bleached the figure and, flickering as their
		# sprites regrouped, flashed on a mount's shell.
		var fire: bool = not steady and kind == 0 and glow.size() > 5 and glow[5]
		var limit := SPELL_GLOW_LIMIT if fire else GLOW_LIMIT
		if peak > limit: colour *= limit / peak
		var extent := clampf(glow[1], 0.1, 3.0)
		var reach := (ARENA_GLOW_REACH if steady else (SPELL_GLOW_REACH if fire else GLOW_REACH)) + extent * 3.0
		# A figure's own glow (a Kinet hero's blade and wings) lights at the
		# raster lamps' share and reach: at a spell's strength it lifted the
		# snow of the Kinet arenas into a white haze around the hero.
		if kind > 0:
			colour *= ELGlowLights.figure_share(kind)
			reach *= ELGlowLights.figure_reach(kind)
			figure.append([glow[0], extent, colour, reach])
			continue
		# A spell's fire falls off with the distance squared (the tracer reads
		# a negative reach so): see SPELL_FALLOFF_DISTANCE in the ray program.
		found.append([glow[0], extent, colour, -reach if fire else reach])
	found.append_array(_steady_figure_lights(figure, delta))
	var authored := []
	if is_instance_valid(_effects):
		for item: Dictionary in _effects.lights:
			var omni: OmniLight3D = item.node
			if not omni.has_meta("cull_mask"):
				omni.set_meta("cull_mask", omni.light_cull_mask)
				omni.light_cull_mask &= ELCombatEffects.LIT_ADDITIVE_LAYER
			if not item.active or not omni.is_visible_in_tree(): continue
			var c := omni.light_color.srgb_to_linear() * omni.light_energy
			authored.append([omni.global_position, 0.15, Vector3(c.r, c.g, c.b), omni.omni_range])
	# Preserve authored light keys before filling the budget with inferred glow.
	var glow_limit := maxi(LIGHT_LIMIT - authored.size(), 0)
	if found.size() > glow_limit:
		found.sort_custom(func(a, b): return a[2].length_squared() > b[2].length_squared())
		found.resize(glow_limit)
	found.append_array(authored)
	var data := PackedFloat32Array()
	for light: Array in found:
		var p: Vector3 = light[0]
		var c: Vector3 = light[2]
		data.append_array([p.x, p.y, p.z, light[1], c.x, c.y, c.z, light[3]])
	return data

## A figure's own lights, steadied as the raster lamps are (ELGlowLights): a
## Kinet hero's wing sparkles regroup from frame to frame and leave a gap of a
## few frames each time the idle clip starts over, and traced as they came,
## the wings' light hopped about and blinked out. Each light eases towards
## where its glow now stands, and fades over FIGURE_FADE when it is gone.
const FIGURE_MATCH := 1.5
func _steady_figure_lights(lights: Array, delta: float) -> Array:
	var blend := 1.0 - exp(-delta / ELGlowLights.SMOOTHING) if delta > 0.0 else 1.0
	var slow := 1.0 - exp(-delta / ELGlowLights.FIGURE_FADE) if delta > 0.0 else 1.0
	var left := _figure_lights.duplicate()
	var result := []
	for light: Array in lights:
		var nearest := -1
		for i in left.size():
			var d: float = left[i][0].distance_to(light[0])
			if d < FIGURE_MATCH and (nearest < 0 or d < left[nearest][0].distance_to(light[0])): nearest = i
		if nearest >= 0:
			var held: Array = left[nearest]
			left.remove_at(nearest)
			light = [held[0].lerp(light[0], blend), lerpf(held[1], light[1], blend), held[2].lerp(light[2], blend), lerpf(held[3], light[3], blend)]
		result.append(light)
	for held: Array in left:
		var colour: Vector3 = held[2].lerp(Vector3.ZERO, slow)
		if maxf(colour.x, maxf(colour.y, colour.z)) > 0.01: result.append([held[0], held[1], colour, held[3]])
	_figure_lights = result
	return result

func _secondary_lights() -> PackedFloat32Array:
	return _effects.secondary_light_sources() if is_instance_valid(_effects) else PackedFloat32Array()

## Bloom on the scene's environment and HDR glowing particles while tracing
## (ELEffectLook); the bloom preference decides again when it stops.
func _bloom(on: bool) -> void:
	if _env == null:
		if is_instance_valid(_effects): _effects.set_glow(ELEffectLook.EFFECT_HDR if on or ELEffectLook.bloom else 1.0)
		return
	if on: _env.set_meta(ELEffectLook.TRACED, true)
	elif _env.has_meta(ELEffectLook.TRACED): _env.remove_meta(ELEffectLook.TRACED)
	ELEffectLook.sync(_env, _effects)

func _restore_effect_lights() -> void:
	if not is_instance_valid(_effects): return
	for item: Dictionary in _effects.lights:
		var omni: OmniLight3D = item.node
		if not omni.has_meta("cull_mask"): continue
		omni.light_cull_mask = omni.get_meta("cull_mask")
		omni.remove_meta("cull_mask")

## Figures (ELModel, traced part by part each frame) and unmoving scenery
## (instanced objects and the map's ground) under `node`.
func _collect(node: Node) -> void:
	for child in node.get_children():
		# Ambient dressing is raster-only and should not consume ray geometry,
		# even when the renderer scans an arena rebuilt from its cache.
		if child.has_meta("raster_only"): continue
		if child is ELCombatEffects:
			for pool: Array[Dictionary] in [child.objects, child.arena_objects]:
				for item: Dictionary in pool:
					if not item.magic_materials.is_empty(): _models.append(item.node)
			continue
		if child is ELAdventureEffects: continue
		if child is ELModel:
			_models.append(child)
			continue
		if child is Node3D and not (child as Node3D).visible: continue
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).multimesh != null and (child as MultiMeshInstance3D).multimesh.mesh != null:
			_static_nodes.append(child)
		elif child is MeshInstance3D and node is ELAdventureTerrain:
			_static_nodes.append(child)
		_collect(child)

## Authored full-bright blends and effects participate in diffuse bounces only.
func _surface(node: GeometryInstance3D, effect := false) -> Dictionary:
	var material := node.material_override
	if material == null:
		if node is MeshInstance3D and node.mesh != null and node.mesh.get_surface_count() > 0:
			material = node.get_active_material(0)
		elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var mesh: Mesh = node.multimesh.mesh
			if mesh.get_surface_count() > 0: material = mesh.surface_get_material(0)
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		var fullbright := base.has_meta(ELFigure.AUTHORED_FULLBRIGHT)
		if effect and not fullbright: return {}
		if base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not fullbright: return {}
		var soft := fullbright and base.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and (effect or base.transparency in [
			BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS])
		if not soft and base.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]: return {}
		var look := {"texture": base.albedo_texture, "tint": base.albedo_color.srgb_to_linear(),
			"uv": Vector4(base.uv1_scale.x, base.uv1_scale.y, base.uv1_offset.x, base.uv1_offset.y),
			"flags": 0 if base.texture_repeat else SURFACE_CLAMP_UV}
		match base.cull_mode:
			BaseMaterial3D.CULL_BACK: look.flags |= SURFACE_PRIMARY_CULL_BACK
			BaseMaterial3D.CULL_FRONT: look.flags |= SURFACE_PRIMARY_CULL_FRONT
		var cutout := base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		if cutout:
			look.cutoff = base.alpha_scissor_threshold / maxf(base.albedo_color.a, 0.000001)
		if fullbright: look.flags |= SURFACE_FULLBRIGHT
		elif base.metallic > 0.0:
			look.flags |= SURFACE_METAL
			look.metal_texture = base.metallic_texture
		if soft:
			if base.albedo_color.a <= 0.0: return {}
			look.flags |= SURFACE_SOFT_EMITTER
			if cutout: look.flags |= SURFACE_SOFT_CUTOUT
			else: look.opacity = base.albedo_color.a
		if base.emission_enabled and base.emission_energy_multiplier > 0.0:
			look.flags |= SURFACE_EMISSION
			if base.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY: look.flags |= SURFACE_EMISSION_MULTIPLY
			look.emission = base.emission.srgb_to_linear()
			look.emission_energy = base.emission_energy_multiplier
			look.emission_texture = base.emission_texture
		return look
	if material is ShaderMaterial and node.has_meta("albedo"):
		# Blended scenery (soft-alpha water sheets) keeps its raster light, as
		# effects do: as solid surfaces they shut the light off what lies below.
		var shader := material as ShaderMaterial
		if shader.shader == ELArena.LIT_BLEND_SHADER: return {}
		var texture := node.get_meta("albedo") as Texture2D
		if texture == null: return {}
		var look := {"texture": texture, "flags": SURFACE_SCENERY}
		if shader.shader == ELArena.LIT_SHADER:
			look.flags |= SURFACE_PRIMARY_CULL_BACK
			var authored: Variant = shader.get_shader_parameter("albedo_tint")
			var tint: Color = authored if authored is Color else Color.WHITE
			var cutoff: Variant = shader.get_shader_parameter("alpha_cutoff")
			look.tint = tint.srgb_to_linear()
			look.cutoff = (cutoff if cutoff is float else 0.5) / maxf(tint.a, 0.000001)
		return look
	# The map's ground: its tile atlas gives one average colour for bounces.
	if node.get_parent() is ELAdventureTerrain and material is ShaderMaterial:
		var tiles := (material as ShaderMaterial).get_shader_parameter("tiles") as Texture2D
		if tiles == null: return {}
		return {"texture": tiles, "flags": SURFACE_GROUND, "solid": true}
	return {}

func _arrays(mesh: Mesh) -> Dictionary:
	if _mesh_data.has(mesh): return _mesh_data[mesh]
	var result := {}
	if mesh.get_surface_count() > 0:
		# Figure meshes keep the arrays they were built from; reading a
		# surface back waits on the GPU.
		var arrays: Array = mesh.get_meta("source_arrays") if mesh.has_meta("source_arrays") else mesh.surface_get_arrays(0)
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
##
## Past LAYERS textures, a layer no slot uses any more is taken over. When
## every layer is in use, a texture whose alpha cuts takes the layer of one
## that does not (that one is traced in its average colour from then on, and
## its slots' records are sent again), so cutout shadows stay right. A
## texture left without a layer keeps its alpha classification.
func _layer(texture: Texture2D, solid := false) -> Array:
	if texture == null: return [-1, false]
	var key := [texture, solid]
	if _layers.has(key):
		var known: Array = _layers[key]
		if known[0] >= 0: _pinned[known[0]] = true
		return known
	_layer_counts.textures += 1
	var entry := [-1, false]
	var image := _layer_image(texture, solid)
	if image != null:
		var alpha := image.detect_alpha() != Image.ALPHA_NONE
		var layer := _free_layer(alpha)
		entry = [layer, alpha]
		if layer >= 0:
			if not image.has_mipmaps(): image.generate_mipmaps()
			_layer_keys[layer] = key
			_pinned[layer] = true
			_effect.queue_layer(layer, image.get_data())
		else:
			_layer_counts.without_layer += 1
			if not _layers_warned:
				_layers_warned = true
				push_warning("Path tracing: more than %d textures in view; the rest are traced in their average colour" % LAYERS)
	_layers[key] = entry
	return entry

## A texture as one RGBA8 layer (mipmaps not yet made, unless authored).
## `solid` fills the layer with its average colour.
func _layer_image(texture: Texture2D, solid: bool) -> Image:
	var image := texture.get_image()
	if image == null: return null
	var authored := _authored_layer(texture, image) if not solid else null
	if authored != null: return authored
	image = image.duplicate()
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	if solid:
		var average := _average_of(image)
		image = Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(average)
	else:
		image.resize(LAYER_SIZE, LAYER_SIZE, Image.INTERPOLATE_BILINEAR)
	return image

## An RGBA8 image's average colour (as stored, opaque).
static func _average_of(image: Image) -> Color:
	var small := image.duplicate() as Image
	if small.has_mipmaps(): small.clear_mipmaps()
	small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	small.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var average := small.get_pixel(0, 0)
	average.a = 1.0
	return average

## A texture's average colour in linear light, for tracing it without a layer.
func _average(texture: Texture2D, solid: bool) -> Color:
	var key := [texture, solid]
	if not _averages.has(key):
		var image := _layer_image(texture, solid)
		_averages[key] = _average_of(image).srgb_to_linear() if image != null else Color.WHITE
	return _averages[key]

## A layer for a new texture: unused, else one no slot holds any more, else
## (for a texture whose alpha cuts) one holding a texture that does not cut.
## -1 when there is none.
func _free_layer(alpha: bool) -> int:
	if _next_layer < LAYERS:
		_next_layer += 1
		_layer_keys.resize(LAYERS)
		return _next_layer - 1
	if not _free_layers.is_empty(): return _free_layers.pop_back()
	var held := _pinned.duplicate()
	for slot: Dictionary in _slots.values():
		for layer: int in slot.get("layers", []):
			if layer >= 0: held[layer] = true
	for layer in LAYERS:
		if held.has(layer): continue
		_layers.erase(_layer_keys[layer])
		_layer_keys[layer] = null
		_layer_counts.evicted += 1
		# Any other unheld layer is free as well.
		for other in range(layer + 1, LAYERS):
			if held.has(other) or _layer_keys[other] == null: continue
			_layers.erase(_layer_keys[other])
			_layer_keys[other] = null
			_free_layers.append(other)
			_layer_counts.evicted += 1
		return layer
	if not alpha: return -1
	# Prefer a ground's single colour, then any texture without a cut.
	var chosen := -1
	for layer in LAYERS:
		var key: Variant = _layer_keys[layer]
		if _pinned.has(layer) or key == null or bool(_layers[key][1]): continue
		if chosen < 0 or bool(key[1]): chosen = layer
		if bool(key[1]): break
	if chosen < 0: return -1
	var given: Array = _layer_keys[chosen]
	_layers[given] = [-1, false]
	_layer_keys[chosen] = null
	_layer_counts.given_up += 1
	_layer_counts.without_layer += 1
	for id: int in _slots:
		var slot: Dictionary = _slots[id]
		if not (slot.get("layers", []) as Array).has(chosen): continue
		var material := _material(slot.look)
		slot.layers = material[2]
		_layer_ops.append(["material", id, material[0]])
	return chosen

## Keep a prepared mask at the ray atlas's resolution. Authored levels take
## priority, followed by the coverage-preserving chain made when a cutout
## texture loads. Resizing its full-resolution mask here would erase the
## thin silhouettes that the raster mipmaps preserve. Reuse those bytes;
## no mask filtering or coverage search belongs on the tracing hot path.
static func _authored_layer(texture: Texture2D, image: Image) -> Image:
	if image == null or image.get_width() != image.get_height(): return null
	if image.is_compressed() or image.get_format() != Image.FORMAT_RGBA8: return null
	# Metadata can outlive a replaced image. A traced array layer needs the
	# complete mip chain; a base-only image must use the ordinary fallback.
	if not image.has_mipmaps(): return null
	var levels := int(texture.get_meta(ELTexture.AUTHORED_MASK_MIPS,
		texture.get_meta(ELTexture.COVERAGE_MASK_MIPS, 0)))
	levels = mini(levels, image.get_mipmap_count() + 1)
	var side := image.get_width()
	for level in levels:
		if side == LAYER_SIZE:
			return Image.create_from_data(side, side, true, Image.FORMAT_RGBA8, image.get_data().slice(image.get_mipmap_offset(level)))
		side /= 2
	return null

func _reset() -> void:
	_texture_revision = ELIconUpscale.texture_revision
	_figure_lights.clear()
	_slots.clear()
	_layers.clear()
	_next_layer = 0
	_layer_keys.clear()
	_free_layers.clear()
	_averages.clear()
	_pinned.clear()
	_layer_ops.clear()
	for key: String in _layer_counts: _layer_counts[key] = 0
	_mesh_data.clear()
	_static_entries = []
	_static_ground = []
	_static_objects = []
	_static_cache.clear()
	_held_models.clear()
	_static_version += 1
	_effect.queue_reset()

func _exit_tree() -> void:
	if _effect != null: _effect.release()


## First-fit ranges of a fixed-size buffer (vertices, corners). Freed ranges
## merge with their free neighbours, and a range ending at the top lowers it,
## so a scene whose objects come and go keeps reusing the same space.
class Ranges extends RefCounted:
	var capacity := 0
	## Units held by live ranges.
	var used := 0
	## The end of the highest live range.
	var high := 0
	var _holes: Array[Vector2i] = []   # free [start, size] below `high`, by start

	func _init(units: int) -> void:
		capacity = units

	func clear() -> void:
		used = 0
		high = 0
		_holes.clear()

	## The start of `size` free units, or -1 when no free run is that long.
	func allocate(size: int) -> int:
		if size <= 0: return 0
		for i in _holes.size():
			var hole := _holes[i]
			if hole.y < size: continue
			if hole.y == size: _holes.remove_at(i)
			else: _holes[i] = Vector2i(hole.x + size, hole.y - size)
			used += size
			return hole.x
		if high + size > capacity: return -1
		var start := high
		high += size
		used += size
		return start

	func release(start: int, size: int) -> void:
		if size <= 0: return
		used -= size
		var at := 0
		while at < _holes.size() and _holes[at].x < start: at += 1
		var hole := Vector2i(start, size)
		# Merge with the free run after it, then the one before it.
		if at < _holes.size() and hole.x + hole.y == _holes[at].x:
			hole.y += _holes[at].y
			_holes.remove_at(at)
		if at > 0 and _holes[at - 1].x + _holes[at - 1].y == hole.x:
			at -= 1
			hole = Vector2i(_holes[at].x, _holes[at].y + hole.y)
			_holes.remove_at(at)
		if hole.x + hole.y >= high: high = hole.x
		else: _holes.insert(at, hole)

	## Whether `size` more units would fit once the live ranges were packed.
	func fits_packed(size: int) -> bool:
		return used + size <= capacity

	func largest_free() -> int:
		var best := capacity - high
		for hole in _holes: best = maxi(best, hole.y)
		return best

	func report() -> Dictionary:
		return {"used": used, "allocated": high, "capacity": capacity, "holes": _holes.size()}


## The render-thread half: owns every GPU resource and runs the passes.
class Effect extends CompositorEffect:
	const SHADERS := preload("res://src/render/path_trace_shaders.gd")
	const VERTEX_CAPACITY := 1 << 20
	const CORNER_CAPACITY := 3 << 20
	const SLOT_CAPACITY := 8192
	const NORMAL_HEADER_BYTES := SLOT_CAPACITY * 4
	const SLOT_BYTES := 64
	const FRAME_BYTES := 320
	const DOUBLE_SIDED := RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
	const REBUILD_INTERVAL := 120
	## state(): the GPU side not tried yet, set up, or failed for good.
	const UNTRIED := 0
	const READY := 1
	const FAILED := -1
	## Checks: "prepare" or "resize" makes that step fail as a GPU without
	## the memory would (--path-tracing-fail=...).
	static var test_failure := ""

	var history_reset := true
	var _mutex := Mutex.new()
	var _ops := []
	var _instances := []
	var _frame := {}
	# A geometry rebuild asked of the main thread (take_overflow).
	var _overflow := false
	var _stats := {}

	var _rd: RenderingDevice
	var _ready_state := UNTRIED   # written on the render thread under _mutex
	var _failure := ""
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
	var _corner_normals := RID()
	var _normal_capacity := 0
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
	var _images: Array[RID] = []   # light 0/1, guide 0/1, filter 0/1, primary surface, secondary, sun 0/1
	var _size := Vector2i.ZERO
	var _parity := 0
	var _frame_number := 0
	var _previous_view_projection := Projection.IDENTITY
	var _previous_camera := Vector3.ZERO
	# Allocation state. Corners index the index, corner, corner UV and corner
	# normal buffers alike (one entry per triangle corner).
	var _vertex_ranges := ELPathTracing.Ranges.new(VERTEX_CAPACITY)
	var _corner_ranges := ELPathTracing.Ranges.new(CORNER_CAPACITY)
	var _normal_ranges := ELPathTracing.Ranges.new(CORNER_CAPACITY)
	var _slots := {}   # id -> {index, vertex, first_index, corner, corners, vertices, normal, normals, blas, geometry}
	# Objects left out because the scene does not fit even packed: they keep
	# their raster light until the next rebuild. Warned about once a run.
	var _skipped := {}
	var _skipped_total := 0
	var _warned := false
	# A rebuild packs the ranges again (the main thread sends every object
	# anew). Asked for when a define fits only once packed, at most once per
	# REBUILD_INTERVAL callbacks; one wanted sooner waits for it.
	var _rebuilds := 0
	var _rebuild_wanted := false
	var _callbacks := 0
	var _last_rebuild := -REBUILD_INTERVAL
	var _free_indices: Array[int] = []
	var _next_slot := 0
	var _dirty: Array[int] = []
	var _pending_layers := []
	# Unmoving scenery: its entries and their reusable instance descriptions.
	var _statics := []
	var _static_version := -1
	var _static_dirty := true
	## Map object id -> [group version, its described instances].
	var _group_lists := {}
	## _static_list plus the held objects, for the held list numbered _steady_for.
	var _steady_list: Array[RDAccelerationStructureInstance] = []
	var _steady_for := -1
	var _static_list: Array[RDAccelerationStructureInstance] = []
	# DLSS Ray Reconstruction: the guide-writing composing program (compiled
	# on first use), its four guides at the internal size, and counters.
	var _rr_shader := RID()
	var _rr_pipeline := RID()
	var _rr_state := 0   # 0 untried, 1 ready, -1 failed
	var _rr_images: Array[RID] = []   # diffuse albedo, specular albedo, normal/roughness, hit distance
	var _rr_size := Vector2i.ZERO
	var _rr_was := false
	var _rr_counts := {"requested": false, "submitted_frames": 0, "refused_frames": 0, "resets": 0, "guides_failed": false}

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
		needs_normal_roughness = true
		enabled = false

	## Whether the GPU side is set up (main thread; UNTRIED, READY or FAILED).
	func state() -> int:
		_mutex.lock()
		var result := _ready_state
		_mutex.unlock()
		return result

	## Why the GPU side failed, or "".
	func failure() -> String:
		_mutex.lock()
		var result := _failure
		_mutex.unlock()
		return result

	# Updates sent after a failure are dropped: nothing would ever take them.
	func submit(ops: Array, instances: Array, frame: Dictionary) -> void:
		_mutex.lock()
		if _ready_state != FAILED:
			_ops.append_array(ops)
			_instances = instances
			_frame = frame
		_mutex.unlock()

	func queue_layer(layer: int, data: PackedByteArray) -> void:
		_mutex.lock()
		if _ready_state != FAILED: _ops.append(["layer", layer, data])
		_mutex.unlock()

	## `full`: everything, history included; otherwise the geometry only (the
	## objects are sent again right after it).
	func queue_reset(full := true) -> void:
		_mutex.lock()
		if _ready_state != FAILED: _ops.append(["reset", full])
		_mutex.unlock()

	## Render thread: frees whatever was made, drops the queued updates and
	## marks the effect failed for good.
	func _fail(reason: String) -> void:
		push_warning("Path tracing: " + reason)
		_free_all()
		_mutex.lock()
		_ready_state = FAILED
		_failure = reason
		_ops = []
		_instances = []
		_frame = {}
		_mutex.unlock()

	func take_overflow() -> bool:
		_mutex.lock()
		var result := _overflow
		_overflow = false
		_mutex.unlock()
		return result

	func release() -> void:
		RenderingServer.call_on_render_thread(_free_all)

	## A copy of the Ray Reconstruction counters (main thread).
	func reconstruction_report() -> Dictionary:
		_mutex.lock()
		var result := _rr_counts.duplicate()
		_mutex.unlock()
		return result

	func _render_callback(_type: int, render_data: RenderData) -> void:
		if _ready_state == UNTRIED:
			# The forced failure comes after everything was made, so that
			# freeing it is checked too.
			if _prepare() and test_failure != "prepare":
				_mutex.lock()
				_ready_state = READY
				_mutex.unlock()
			else:
				_fail("the GPU resources could not be created")
		if _ready_state != READY: return
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
		if size != _size and not _resize(size):
			_fail("the %d×%d images could not be created" % [size.x, size.y])
			return
		_rd.capture_timestamp("Path trace begin")
		_run(instances, buffers, scene, frame, size)
		_rd.capture_timestamp("Path trace end")

	## Scene updates (morphs, acceleration structures), tracing and filtering.
	func _run(instances: Array, buffers: RenderSceneBuffersRD, scene: RenderSceneData, frame: Dictionary, size: Vector2i) -> void:
		_expand()
		if not _build_scene(instances, frame.get("groups", []), int(frame.get("held_list", -1))): return
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
		rays.set_stage_source(RenderingDevice.SHADER_STAGE_CLOSEST_HIT, SHADERS.CLOSEST_HIT)
		rays.set_stage_source(RenderingDevice.SHADER_STAGE_MISS, SHADERS.MISS)
		made.append(_compile(rays, [RenderingDevice.SHADER_STAGE_RAYGEN,
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
		_corner_normals = _rd.storage_buffer_create(NORMAL_HEADER_BYTES)
		if not _corner_normals.is_valid(): return false
		_corners = _rd.vertex_buffer_create(CORNER_CAPACITY * 12, PackedByteArray(),
			RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT |
			RenderingDevice.BUFFER_CREATION_DEVICE_ADDRESS_BIT | RenderingDevice.BUFFER_CREATION_AS_STORAGE_BIT)
		_slot_buffer = _rd.storage_buffer_create(SLOT_CAPACITY * SLOT_BYTES)
		_frame_buffer = _rd.storage_buffer_create(FRAME_BYTES)
		var authored_limit := ELCombatEffects.LIGHT_POOL
		_light_buffer = _rd.storage_buffer_create((maxi(ELPathTracing.LIGHT_LIMIT, authored_limit) + authored_limit) * 32)
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
		for rid: RID in [_expand_pipeline, _trace_pipeline, _filter_pipeline, _source, _source_uv, _indices, _corner_uv, _corner_normals, _corners, _slot_buffer, _frame_buffer, _light_buffer, _albedo, _linear, _nearest]:
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

	## The ten full-size images (light, guide and filter pairs, surfaces, sun
	## pair). False, with none kept, when any could not be made.
	func _resize(size: Vector2i) -> bool:
		for rid in _images: if rid.is_valid(): _rd.free_rid(rid)
		_images.clear()
		_size = Vector2i.ZERO
		var format := RDTextureFormat.new()
		format.width = size.x
		format.height = size.y
		format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		for i in 10:
			var image := RID() if test_failure == "resize" and i == 6 else _rd.texture_create(format, RDTextureView.new())
			if not image.is_valid() or _rd.texture_clear(image, Color(0, 0, 0, 0), 0, 1, 0, 1) != OK:
				if image.is_valid(): _rd.free_rid(image)
				for made in _images: _rd.free_rid(made)
				_images.clear()
				return false
			_images.append(image)
		_size = size
		history_reset = true
		return true

	# -- scene snapshot -----------------------------------------------------

	func _apply_ops(ops: Array) -> bool:
		for op: Array in ops:
			match op[0]:
				"reset": _clear_scene(op[1])
				"layer":
					if _rd.texture_update(_albedo, op[1], op[2]) != OK: push_warning("Path tracing: texture layer upload failed")
				"define": _define(op)
				"material": _update_material(op[1], op[2])
				"pose": _pose(op[1], op[2])
				"free":
					_free_slot(op[1])
					_skipped.erase(op[1])
		_callbacks += 1
		if _rebuild_wanted and _callbacks - _last_rebuild >= REBUILD_INTERVAL:
			_rebuild_wanted = false
			_last_rebuild = _callbacks
			_rebuilds += 1
			_mutex.lock()
			_overflow = true
			_mutex.unlock()
		if not ops.is_empty(): _publish_stats()
		return true

	## `full`: the whole traced scene starts again (its history too). Otherwise
	## only the geometry, which the main thread sends again in the same batch.
	func _clear_scene(full := true) -> void:
		for id: int in _slots.keys(): _free_slot(id)
		_vertex_ranges.clear()
		_corner_ranges.clear()
		_normal_ranges.clear()
		_next_slot = 0
		_free_indices.clear()
		_dirty.clear()
		_skipped.clear()
		if full: history_reset = true

	func _define(op: Array) -> void:
		var id: int = op[1]
		_free_slot(id)
		_skipped.erase(id)
		var vertices: int = op[2]
		var index_bytes: PackedByteArray = op[3]
		var uv_bytes: PackedByteArray = op[4]
		var normals: PackedByteArray = op[5]
		var corners := index_bytes.size() / 4
		if corners == 0 or corners % 3 != 0: return
		var normal_corners := normals.size() / 12
		var slot_room := not _free_indices.is_empty() or _next_slot < SLOT_CAPACITY
		var vertex := _vertex_ranges.allocate(vertices) if slot_room else -1
		var corner := _corner_ranges.allocate(corners) if vertex >= 0 else -1
		var normal := _normal_ranges.allocate(normal_corners) if corner >= 0 else -1
		if normal < 0 or not _grow_normals():
			if normal >= 0: _normal_ranges.release(normal, normal_corners)
			if corner >= 0: _corner_ranges.release(corner, corners)
			if vertex >= 0: _vertex_ranges.release(vertex, vertices)
			# Space that packing would free: a rebuild is asked for, and the
			# object waits for it untraced while the rest goes on as it was.
			var packed := slot_room and _vertex_ranges.fits_packed(vertices) and _corner_ranges.fits_packed(corners) and _normal_ranges.fits_packed(normal_corners)
			if packed and normal >= 0:
				# Packed ranges fit but the normals buffer could not grow.
				packed = false
			if packed: _rebuild_wanted = true
			_skip(id, not packed)
			return
		var slot_index: int = _free_indices.pop_back() if not _free_indices.is_empty() else _next_slot
		if slot_index == _next_slot: _next_slot += 1
		var slot := {"index": slot_index, "vertex": vertex, "first_index": corner, "corner": corner,
			"corners": corners, "vertices": vertices, "normal": normal, "normals": normal_corners, "uv": true, "posed": false, "blas": RID()}
		_slots[id] = slot
		_rd.buffer_update(_indices, slot.first_index * 4, index_bytes.size(), index_bytes)
		_rd.buffer_update(_source_uv, slot.vertex * 8, mini(uv_bytes.size(), vertices * 8), uv_bytes)
		if normal_corners > 0:
			var start := NORMAL_HEADER_BYTES + normal * 12
			var offset := PackedInt32Array([start / 4]).to_byte_array()
			_rd.buffer_update(_corner_normals, start, normals.size(), normals)
			_rd.buffer_update(_corner_normals, slot_index * 4, offset.size(), offset)
		var geometry := RDAccelerationStructureGeometry.new()
		geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
		geometry.vertex_buffer = _corners
		geometry.vertex_offset = slot.corner * 12
		geometry.vertex_stride = 12
		geometry.vertex_count = corners
		geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
		var geometries: Array[RDAccelerationStructureGeometry] = [geometry]
		slot.blas = _rd.blas_create(geometries, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT)
		if not slot.blas.is_valid():
			_free_slot(id)
			_skip(id, true)

	## Leaves an object out of the traced scene (it keeps its raster light).
	## `for_good`: it cannot fit even packed, said once a run.
	func _skip(id: int, for_good: bool) -> void:
		if not _skipped.has(id): _skipped_total += 1
		_skipped[id] = for_good
		if for_good and not _warned:
			_warned = true
			push_warning("Path tracing: the scene is larger than the traced geometry budget (vertices %d/%d, corners %d/%d, objects %d/%d); what does not fit keeps its raster light" % [
				_vertex_ranges.used, _vertex_ranges.capacity, _corner_ranges.used, _corner_ranges.capacity, _slots.size(), SLOT_CAPACITY])

	## Binding 7 starts with a word offset for every slot, followed by the
	## normal-aware receivers' corner normals (each in the order of its
	## expanded triangles). It grows to hold the highest allocated range.
	func _grow_normals() -> bool:
		var required := _normal_ranges.high * 12
		if required <= _normal_capacity: return true
		var capacity := mini(maxi(required, _normal_capacity * 2), CORNER_CAPACITY * 12)
		var grown := _rd.storage_buffer_create(NORMAL_HEADER_BYTES + capacity)
		if not grown.is_valid(): return false
		if _rd.buffer_copy(_corner_normals, grown, 0, 0, NORMAL_HEADER_BYTES + _normal_capacity) != OK:
			_rd.free_rid(grown)
			return false
		_rd.free_rid(_corner_normals)
		_corner_normals = grown
		_normal_capacity = capacity
		return true

	## The budget for ELPathTracing.limits_report.
	func _publish_stats() -> void:
		var over := 0
		for value: bool in _skipped.values(): over += 1 if value else 0
		var stats := {"vertices": _vertex_ranges.report(), "corners": _corner_ranges.report(), "normals": _normal_ranges.report(),
			"objects": {"used": _slots.size(), "allocated": _next_slot, "capacity": SLOT_CAPACITY},
			"rebuilds": _rebuilds, "skipped": _skipped.size(), "skipped_over_budget": over, "skipped_total": _skipped_total}
		_mutex.lock()
		_stats = stats
		_mutex.unlock()

	## A copy of the geometry budget (main thread).
	func limits() -> Dictionary:
		_mutex.lock()
		var result := _stats.duplicate(true)
		_mutex.unlock()
		return result

	func _update_material(id: int, record: PackedByteArray) -> void:
		var slot: Dictionary = _slots.get(id, {})
		if slot.is_empty(): return
		var flags := record.decode_u32(8)
		var mask := 2 if (flags & ELPathTracing.SURFACE_SOFT_EMITTER) != 0 else 1
		var facing := DOUBLE_SIDED
		# Vulkan's ray-facing test sees Godot's raster fronts with reversed winding.
		if (flags & ELPathTracing.SURFACE_PRIMARY_CULL_BACK) != 0:
			facing = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FLIP_FACING_BIT
		elif (flags & ELPathTracing.SURFACE_PRIMARY_CULL_FRONT) != 0:
			facing = 0
		if slot.get("mask", 1) != mask or slot.get("facing", DOUBLE_SIDED) != facing: _static_dirty = true
		slot.mask = mask
		slot.facing = facing
		record.encode_u32(0, slot.corner)
		_rd.buffer_update(_slot_buffer, slot.index * SLOT_BYTES, SLOT_BYTES, record)

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
		_vertex_ranges.release(slot.vertex, slot.vertices)
		_corner_ranges.release(slot.corner, slot.corners)
		_normal_ranges.release(slot.normal, slot.normals)
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

	func _build_scene(instances: Array, groups: Array, held_list: int) -> bool:
		if _static_dirty:
			_static_dirty = false
			_static_list = _describe(_statics)
			_group_lists.clear()
			_steady_for = -1
		if held_list != _steady_for:
			_steady_for = held_list
			_steady_list = _held_instances(groups)
		var list := _steady_list.duplicate()
		list.append_array(_describe(instances))
		if list.is_empty(): return false
		if list.size() > _tlas_capacity:
			if _tlas.is_valid(): _rd.free_rid(_tlas)
			_tlas_capacity = maxi(1024, nearest_po2(list.size()))
			_tlas = _rd.tlas_create(_tlas_capacity, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT)
		return _tlas.is_valid() and _rd.tlas_build(_tlas, list) == OK

	## The unmoving scenery and the held map objects, each object's instances
	## described again only when its group version changed.
	func _held_instances(groups: Array) -> Array[RDAccelerationStructureInstance]:
		var list := _static_list.duplicate()
		# Held map objects keep their described instances while their
		# version (and every slot) is unchanged.
		var described := {}
		for group: Array in groups:
			var held: Array = _group_lists.get(group[0], [])
			if held.is_empty() or held[0] != group[1]: held = [group[1], _describe(group[2])]
			described[group[0]] = held
			list.append_array(held[1])
		_group_lists = described
		return list

	func _describe(entries: Array) -> Array[RDAccelerationStructureInstance]:
		var list: Array[RDAccelerationStructureInstance] = []
		for entry: Array in entries:
			var slot: Dictionary = _slots.get(entry[0], {})
			if slot.is_empty() or not slot.posed: continue
			var instance := RDAccelerationStructureInstance.new()
			instance.transform = entry[1]
			# Vulkan's 24-bit custom index carries the 16-bit slot and an
			# 8-bit grayscale fog multiplier. All instances still share the BLAS.
			var tint := clampi(int(entry[2]), 0, 255) if entry.size() > 2 else 255
			instance.id = slot.index | (tint << 16)
			instance.mask = slot.mask
			instance.flags = slot.get("facing", DOUBLE_SIDED)
			instance.blas = slot.blas
			instance.hit_sbt_range = _hit_range
			list.append(instance)
		return list

	# -- passes -------------------------------------------------------------

	func _trace(buffers: RenderSceneBuffersRD, scene: RenderSceneData, frame: Dictionary, size: Vector2i) -> void:
		var camera := scene.get_cam_transform()
		var projection := scene.get_cam_projection()
		# DLSS Ray Reconstruction: the engine checks the guides (size, format,
		# DLSS on this view) before any ray is cast; they are filled below,
		# ahead of the upscale. Refused, this frame renders as without it.
		var rr := false
		var rr_reset := history_reset or not _rr_was
		if bool(frame.get("ray_reconstruction", false)) and buffers.get_view_count() == 1 \
				and buffers.has_method("set_dlss_ray_reconstruction") and _rr_ready(size):
			rr = bool(buffers.call("set_dlss_ray_reconstruction", _rr_images[0], _rr_images[1], _rr_images[2], _rr_images[3], rr_reset))
			_mutex.lock()
			_rr_counts.submitted_frames += 1 if rr else 0
			_rr_counts.refused_frames += 0 if rr else 1
			_rr_counts.resets += 1 if rr and rr_reset else 0
			_mutex.unlock()
		_mutex.lock()
		_rr_counts.requested = bool(frame.get("ray_reconstruction", false))
		_mutex.unlock()
		# The camera projection already carries the renderer's depth correction
		# and its jitter (the jittered picture the raster drew, which the
		# reconstruction works on). get_ray_projection lacks the correction:
		# every primary ray missed with it, so nothing was traced and the
		# reconstruction showed the raster without traced shadows.
		var view_projection := projection * Projection(camera.affine_inverse())
		var flags := (1 if history_reset else 0) | (2 if frame.lighting_view else 0) | (4 if OS.get_cmdline_user_args().has("--path-tracing-debug") else 0)
		# Ray Reconstruction gets one fresh sample a pixel (no accumulation),
		# and the tracer's history starts again when it stops.
		if rr or _rr_was: flags |= 1
		# The ray program keeps the metal share and reflection length for the guides.
		if rr: flags |= 8
		_rr_was = rr
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
		var secondary: PackedFloat32Array = frame.secondary_lights
		var secondary_count := secondary.size() / 8
		if secondary_count > 0: _rd.buffer_update(_light_buffer, lights.size() * 4, secondary.size() * 4, secondary.to_byte_array())
		# Effect light changes quickly: a shorter history keeps it from smearing.
		for value in [_frame_number, size.x, size.y, flags, light_count, 12 if light_count > 0 else 48, secondary_count, frame.bounces]:
			data.encode_u32(at, value)
			at += 4
		var backdrop: Color = frame.backdrop
		at = _put4(data, at, Vector4(frame.sky_light, backdrop.r, backdrop.g, backdrop.b))
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
		var common: Array[RDUniform] = [frame_uniform, tlas, _storage(2, _corners), _storage(3, _corner_uv), _storage(4, _slot_buffer), albedo, _storage(6, _light_buffer), _storage(7, _corner_normals)]

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
		var trace_set: Array[RDUniform] = [depth, normal, _image(2, light[previous]), _image(3, guide[previous]),
			_image(4, light[current]), _image(5, guide[current]), _image(6, _images[6]), _image(7, _images[7]),
			_image(8, _images[8 + previous]), _image(9, _images[8 + current])]
		var groups := Vector3i((size.x + 7) / 8, (size.y + 7) / 8, 1)
		var rays := _rd.raytracing_list_begin()
		_rd.raytracing_list_bind_raytracing_pipeline(rays, _trace_pipeline)
		_rd.raytracing_list_bind_uniform_set(rays, UniformSetCacheRD.get_cache(_trace_shader, 0, common), 0)
		_rd.raytracing_list_bind_uniform_set(rays, UniformSetCacheRD.get_cache(_trace_shader, 1, trace_set), 1)
		_rd.raytracing_list_trace_rays(rays, 0, _sbt, size.x, size.y, 1)
		_rd.raytracing_list_end()

		var frame_only: Array[RDUniform] = [frame_uniform]
		var color := buffers.get_color_layer(0)
		if rr:
			_reconstruction_pass(buffers, frame_only, light[current], guide[current], color, groups)
			return
		var passes := [[light[current], _images[4], 1, 0], [_images[4], _images[5], 2, 0], [_images[5], _images[4], 4, 1]]
		for step: Array in passes:
			var filter_set: Array[RDUniform] = [_image(0, step[0]), _image(1, guide[current]), _image(2, step[1]), _image(3, color), _image(4, _images[6]), _image(5, _images[7])]
			var push := PackedInt32Array([step[2], step[3], 0, 0]).to_byte_array()
			var list := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(list, _filter_pipeline)
			_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_filter_shader, 0, frame_only), 0)
			_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_filter_shader, 1, filter_set), 1)
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
			_rd.compute_list_end()

	## With DLSS Ray Reconstruction: one composing pass of the unsmoothed light
	## (the same relighting as the last smoothing pass), writing the guides.
	func _reconstruction_pass(buffers: RenderSceneBuffersRD, frame_only: Array[RDUniform], light: RID, guide: RID, color: RID, groups: Vector3i) -> void:
		var depth := RDUniform.new()
		depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth.binding = 10
		depth.add_id(_nearest)
		depth.add_id(buffers.get_depth_layer(0))
		var normal := RDUniform.new()
		normal.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		normal.binding = 11
		normal.add_id(_nearest)
		normal.add_id(buffers.get_texture("forward_clustered", "normal_roughness"))
		var filter_set: Array[RDUniform] = [_image(0, light), _image(1, guide), _image(2, _images[4]), _image(3, color), _image(4, _images[6]), _image(5, _images[7]),
			_image(6, _rr_images[0]), _image(7, _rr_images[1]), _image(8, _rr_images[2]), _image(9, _rr_images[3]), depth, normal]
		var push := PackedInt32Array([4, 1, 0, 0]).to_byte_array()
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _rr_pipeline)
		_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_rr_shader, 0, frame_only), 0)
		_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_rr_shader, 1, filter_set), 1)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
		_rd.compute_list_end()

	## The guide program and the four guides at `size` (made when first needed).
	func _rr_ready(size: Vector2i) -> bool:
		if _rr_state == 0:
			_rr_state = -1
			var source := RDShaderSource.new()
			source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
			source.source_compute = SHADERS.reconstruction_filter()
			_rr_shader = _compile(source, [RenderingDevice.SHADER_STAGE_COMPUTE], "Path trace reconstruction guides")
			if _rr_shader.is_valid(): _rr_pipeline = _rd.compute_pipeline_create(_rr_shader)
			if _rr_pipeline.is_valid(): _rr_state = 1
			else:
				_mutex.lock()
				_rr_counts.guides_failed = true
				_mutex.unlock()
		if _rr_state < 0: return false
		if size != _rr_size:
			_free_rr_images()
			for i in 4:
				var format := RDTextureFormat.new()
				format.width = size.x
				format.height = size.y
				format.format = RenderingDevice.DATA_FORMAT_R16_SFLOAT if i == 3 else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
				format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
				var image := _rd.texture_create(format, RDTextureView.new())
				if not image.is_valid():
					_free_rr_images()
					return false
				_rr_images.append(image)
			_rr_size = size
		return true

	func _free_rr_images() -> void:
		for rid in _rr_images: if rid.is_valid(): _rd.free_rid(rid)
		_rr_images.clear()
		_rr_size = Vector2i.ZERO

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
			_source, _source_uv, _indices, _corner_uv, _corner_normals, _corners, _slot_buffer, _frame_buffer, _light_buffer, _albedo, _linear, _nearest]
		owned.append_array(_images)
		_free_rr_images()
		owned.append_array([_rr_pipeline, _rr_shader])
		for rid in owned:
			if rid.is_valid(): _rd.free_rid(rid)
		_images.clear()
		_rr_shader = RID()
		_rr_pipeline = RID()
		_rr_state = 0
		_rr_was = false
		_tlas = RID()
		_sbt = RID()
		_tlas_capacity = 0
		_normal_capacity = 0
		_size = Vector2i.ZERO
		for rid_name: StringName in [&"_expand_shader", &"_expand_pipeline", &"_trace_shader", &"_trace_pipeline", &"_filter_shader", &"_filter_pipeline",
				&"_source", &"_source_uv", &"_indices", &"_corners", &"_corner_uv", &"_corner_normals", &"_slot_buffer", &"_frame_buffer", &"_light_buffer",
				&"_albedo", &"_linear", &"_nearest"]:
			set(rid_name, RID())
		_mutex.lock()
		_ready_state = UNTRIED
		_mutex.unlock()
