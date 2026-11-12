class_name ELWikiPreview
extends SubViewportContainer
## The live creature beside a wiki card page (as the EI remake's WikiPreview),
## or a story hero beside a guide that lists `heroes` (Diamanda, the White Lord):
## the creature's own model and textures from the installed game, playing its
## idle animation with its own particles (the whirlwind of an air wall, a
## spirit's trail: CreaturesPFX/<model>/idle.pfx, as in battle) in a small
## world of its own. Drag to turn it, use the wheel
## (or pinch) to zoom; Reset restores the view. tools/export_wiki.gd renders the
## same scene into the website's screenshots (ELWikiPreview.stage).

const BACKGROUND := Color("120e0b")
const YAW := deg_to_rad(-28.0)
const PITCH := deg_to_rad(14.0)
## The bounding-sphere framing leaves wide margins; the reader starts closer.
const OPENING_ZOOM := 0.72
const ANIMATIONS := ["cidle", "uattack", "ushot", "uhit", "udeath", "usummon", "utap", "uuntap", "uinstant"]

signal creature_changed
var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var model: ELModel
var _distance := 4.0
var _yaw := YAW
var _pitch := PITCH
var _zoom := OPENING_ZOOM
var _dragging := false
var _sound: AudioStreamPlayer
var _sound_directory := ""
var _profile: ELProfile

func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	resized.connect(_refit)

## A viewport holding `code`'s creature, framed; null when the game has no
## model for it. `transparent` leaves the background clear (screenshots).
static func stage(profile: ELProfile, code: String, size: Vector2i, transparent := false) -> SubViewport:
	var original: Dictionary = profile.table("CombatCreatures").get(code, {})
	if original.is_empty(): return null
	var secondary := "Creatures/" + str(original.SecTexture) if original.has("SecTexture") else ""
	return _stage(profile, str(original.get("Model", "")), "Creatures/" + str(original.get("Texture", "")), secondary,
		float(original.get("Scale", 1.0)), size, transparent)

## A viewport holding the hero of HeroTemplates row `template` (story pages:
## Diamanda, the White Lord), with its battle model and skin; null when the
## game has no such hero.
static func stage_hero(profile: ELProfile, template: String, size: Vector2i, transparent := false) -> SubViewport:
	var row: Dictionary = profile.table("HeroTemplates").get(template, {})
	if row.is_empty(): return null
	var skin := "Heroes/" + str(row.get("Texture", "")).replace("\\", "/")
	var secondary := "Heroes/" + str(row.Texture2).replace("\\", "/") if row.has("Texture2") else ""
	return _stage(profile, str(row.get("Model", "")), skin, secondary, 1.0, size, transparent)

static func _stage(profile: ELProfile, model_name: String, skin: String, secondary: String, scale: float, size: Vector2i, transparent: bool) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.transparent_bg = transparent
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = BACKGROUND
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.62, 0.6, 0.58)
	environment.environment.ambient_light_energy = 0.9
	view.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.1
	view.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-140), 0)
	fill.light_energy = 0.35
	view.add_child(fill)
	var figure := ELModel.new()
	figure.name = "Model"
	view.add_child(figure)
	if not figure.build(profile, model_name, skin, secondary):
		view.free()
		return null
	figure.scale = Vector3.ONE * scale
	# Alpha32 skins (air walls, spirits) fade out in soft alpha: the wall's
	# lower half is a wisp of see-through cloth. Blend them instead of the
	# figure material's alpha cut-off, which drops everything below half.
	if skin.to_lower().trim_prefix("creatures/").trim_prefix("heroes/").begins_with("alpha32"):
		for part: Node in figure.get_children():
			var mesh := part as MeshInstance3D
			if mesh != null and mesh.material_override is StandardMaterial3D:
				var blended: StandardMaterial3D = mesh.material_override.duplicate()
				blended.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				mesh.material_override = blended
	# The figure's own particles start with its clips once the stage is shown.
	var effects := ELCombatEffects.new()
	effects.name = "Effects"
	view.add_child(effects)
	effects.build(profile)
	# The reader may already have moved on to another page by then.
	(func() -> void: if is_instance_valid(figure) and figure.is_inside_tree(): effects.attach(figure)).call_deferred()
	var pivot_node := Node3D.new()
	pivot_node.name = "Pivot"
	view.add_child(pivot_node)
	var eye := Camera3D.new()
	eye.name = "Camera"
	eye.fov = 32.0
	pivot_node.add_child(eye)
	return view

## The bounds of the model's visible parts in its own space.
static func bounds(figure: ELModel) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in figure.get_children():
		var part := node as MeshInstance3D
		if part == null or part.mesh == null or not part.visible: continue
		var local := part.transform * part.mesh.get_aabb()
		local = AABB(local.position * figure.scale, local.size * figure.scale)
		box = local if first else box.merge(local)
		first = false
	# Particles drawn so far (the emitters already carry the figure's scale).
	var effects := figure.get_parent().get_node_or_null("Effects")
	if effects != null:
		for node: Node in effects.get_children():
			var emitter := node as MultiMeshInstance3D
			if emitter == null or not emitter.visible or emitter.multimesh == null or emitter.multimesh.visible_instance_count == 0: continue
			var local := emitter.transform * emitter.multimesh.get_aabb()
			box = local if first else box.merge(local)
			first = false
	return box if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)

## Points the camera of `view` at its model from `yaw`/`pitch`; returns the
## framing distance.
static func frame(view: SubViewport, yaw: float, pitch: float, zoom := 1.0) -> float:
	var figure: ELModel = view.get_node("Model")
	var pivot_node: Node3D = view.get_node("Pivot")
	var eye: Camera3D = pivot_node.get_node("Camera")
	var box := bounds(figure)
	pivot_node.position = box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.2)
	var vertical := deg_to_rad(eye.fov) * 0.5
	var aspect := float(view.size.x) / maxf(1.0, float(view.size.y))
	var limiting := minf(vertical, atan(tan(vertical) * maxf(0.01, aspect)))
	var distance := radius / sin(limiting) * 1.05 * zoom
	pivot_node.rotation = Vector3(-pitch, yaw, 0)
	eye.position = Vector3(0, 0, distance)
	eye.near = maxf(distance * 0.02, 0.01)
	eye.far = distance * 4.0 + radius * 4.0
	return distance

## Shows `code`'s creature; false when it has no model in this game.
func show_creature(profile: ELProfile, code: String) -> bool:
	return _show(profile, stage(profile, code, Vector2i(512, 512)), str(profile.table("CombatCreatures").get(code, {}).get("SndDir", "")))

## Shows the hero of HeroTemplates row `template`; false when the game has none.
func show_hero(profile: ELProfile, template: String) -> bool:
	return _show(profile, stage_hero(profile, template, Vector2i(512, 512)), "")

func _show(profile: ELProfile, staged: SubViewport, sounds: String) -> bool:
	# Switching editions (or heroes) replaces the figure shown.
	if viewport != null:
		remove_child(viewport)
		viewport.queue_free()
		viewport = null
	viewport = staged
	if _sound != null: _sound.stop()
	if viewport == null:
		model = null
		creature_changed.emit()
		return false
	_profile = profile
	_sound_directory = sounds
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 320)
	add_child(viewport)
	model = viewport.get_node("Model")
	model.animation_finished.connect(_resume_idle)
	pivot = viewport.get_node("Pivot")
	camera = pivot.get_node("Camera")
	reset_view()
	# Frame again once the particles have started (they start deferred).
	_settle.call_deferred()
	creature_changed.emit()
	return true

func animations() -> Array:
	return ANIMATIONS.filter(func(clip: String) -> bool: return model != null and model.has_clip(clip))

func play_animation(clip: String, volume: float) -> void:
	if model == null or not clip in ANIMATIONS or not model.play(clip): return
	if _sound == null: return
	_sound.stop()
	if _sound_directory.is_empty() or clip == "cidle" or volume <= 0.0: return
	_sound.stream = ELAudio.sound(_profile, "Creatures/%s/%s.wav" % [_sound_directory, clip.trim_prefix("u")])
	if _sound.stream == null: return
	_sound.volume_db = linear_to_db(volume)
	_sound.play()

func _resume_idle(clip: String) -> void:
	# Let the model finish applying the last pose before changing clips.
	if clip != "udeath": model.play.call_deferred("cidle")

func _settle() -> void:
	if not is_inside_tree() or viewport == null or _dragging: return
	await get_tree().process_frame
	if is_inside_tree() and viewport != null and not _dragging: _refit()

func reset_view() -> void:
	if viewport == null: return
	_yaw = YAW
	_pitch = PITCH
	_zoom = OPENING_ZOOM
	_refit()

func _refit() -> void:
	if viewport == null: return
	var opening := 1.0 / OPENING_ZOOM if viewport.size.x < viewport.size.y else 1.0
	_distance = frame(viewport, _yaw, _pitch, _zoom * opening)

func _apply() -> void:
	pivot.rotation = Vector3(-_pitch, _yaw, 0)
	camera.position = Vector3(0, 0, _distance)

func zoom(factor: float) -> void:
	var before := _zoom
	_zoom = clampf(_zoom * factor, 0.35, 2.5)
	_distance *= _zoom / before
	_apply()

func turn(by: Vector2) -> void:
	_yaw -= by.x * 0.01
	_pitch = clampf(_pitch + by.y * 0.01, deg_to_rad(-20), deg_to_rad(70))
	_apply()

func _gui_input(event: InputEvent) -> void:
	if viewport == null: return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT: _dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP: zoom(0.9)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom(1.1)
		elif button.pressed and button.double_click: reset_view()
		else: return
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		turn((event as InputEventMouseMotion).relative)
		accept_event()
	elif event is InputEventScreenDrag:
		turn((event as InputEventScreenDrag).relative)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / (event as InputEventMagnifyGesture).factor)
		accept_event()
