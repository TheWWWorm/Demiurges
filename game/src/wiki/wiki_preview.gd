class_name ELWikiPreview
extends SubViewportContainer
## The live creature beside a wiki card page (as the EI remake's WikiPreview):
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

var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var model: ELModel
var _distance := 4.0
var _yaw := YAW
var _pitch := PITCH
var _dragging := false

## A viewport holding `code`'s creature, framed; null when the game has no
## model for it. `transparent` leaves the background clear (screenshots).
static func stage(profile: ELProfile, code: String, size: Vector2i, transparent := false) -> SubViewport:
	var original: Dictionary = profile.table("CombatCreatures").get(code, {})
	if original.is_empty(): return null
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
	var secondary := "Creatures/" + str(original.SecTexture) if original.has("SecTexture") else ""
	if not figure.build(profile, str(original.get("Model", "")), "Creatures/" + str(original.get("Texture", "")), secondary):
		view.free()
		return null
	figure.scale = Vector3.ONE * float(original.get("Scale", 1.0))
	# Alpha32 skins (air walls, spirits) fade out in soft alpha: the wall's
	# lower half is a wisp of see-through cloth. Blend them instead of the
	# figure material's alpha cut-off, which drops everything below half.
	if str(original.get("Texture", "")).to_lower().begins_with("alpha32"):
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
	effects.attach.call_deferred(figure)
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
	var distance := radius / sin(deg_to_rad(eye.fov) * 0.5) * 1.05 * zoom
	pivot_node.rotation = Vector3(-pitch, yaw, 0)
	eye.position = Vector3(0, 0, distance)
	eye.near = maxf(distance * 0.02, 0.01)
	eye.far = distance * 4.0 + radius * 4.0
	return distance

## Shows `code`'s creature; false when it has no model in this game.
func show_creature(profile: ELProfile, code: String) -> bool:
	# Switching editions replaces the creature shown.
	if viewport != null:
		remove_child(viewport)
		viewport.queue_free()
		viewport = null
	viewport = stage(profile, code, Vector2i(512, 512))
	if viewport == null: return false
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 320)
	add_child(viewport)
	model = viewport.get_node("Model")
	pivot = viewport.get_node("Pivot")
	camera = pivot.get_node("Camera")
	reset_view()
	# Frame again once the particles have started (they start deferred).
	_settle.call_deferred()
	return true

func _settle() -> void:
	if viewport == null or _dragging: return
	await get_tree().process_frame
	if viewport != null and not _dragging: reset_view()

func reset_view() -> void:
	_yaw = YAW
	_pitch = PITCH
	_distance = frame(viewport, _yaw, _pitch, OPENING_ZOOM)

func _apply() -> void:
	pivot.rotation = Vector3(-_pitch, _yaw, 0)
	camera.position = Vector3(0, 0, _distance)

func zoom(factor: float) -> void:
	var base := frame(viewport, _yaw, _pitch)
	_distance = clampf(_distance * factor, base * 0.35, base * 2.5)
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
