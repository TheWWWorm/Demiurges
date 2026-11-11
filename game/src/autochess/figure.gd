class_name ELAutochessFigure
extends Control
## A live creature in the interface: the creature's own model and textures,
## playing its idle animation on a transparent background. Used by the shop
## offers, reserves, inspector and evolution notice. `glow` draws an outline
## around the figure itself (an offer that completes an evolution pulses).
## The view renders at the figure's size on screen (the interface is scaled
## up on large displays), so the creature stays sharp.

## World size (in the largest projected extent) that fills a figure's view.
const LARGE := 2.3
const GLOW_SHADER := preload("res://src/autochess/upgrade_glow.gdshader")

var profile: ELProfile
var code := ""
var yaw := deg_to_rad(-28.0)
var pitch := deg_to_rad(10.0)
var zoom := 0.88
## Keep the creatures' relative sizes (shop, reserves, notices).
var relative := true
var view: SubViewport
var model: ELModel
var _framed := 0
var _glow_material: ShaderMaterial
## Settled framings by creature and view shape: a creature shown again is
## framed at once, without reading pixels back from the graphics card.
static var _framings: Dictionary = {}

func _framing_key() -> String:
	return "%s|%.3f|%.3f|%.3f|%s" % [code, yaw, pitch, zoom, relative]

## Whether `code` was framed already (the loading screen frames them all).
static func is_framed(code: String, figure_yaw := deg_to_rad(-28.0), figure_pitch := deg_to_rad(10.0), figure_zoom := 0.88, figure_relative := true) -> bool:
	return _framings.has("%s|%.3f|%.3f|%.3f|%s" % [code, figure_yaw, figure_pitch, figure_zoom, figure_relative])

## Places the camera from a settled framing for this view's shape.
func _apply_framing(known: Dictionary) -> void:
	var pivot_node: Node3D = view.get_node("Pivot")
	var eye: Camera3D = pivot_node.get_node("Camera")
	pivot_node.transform = known.pivot
	var extent: Vector2 = known.extent
	var aspect := float(view.size.x) / maxf(1.0, float(view.size.y))
	var reach := 2.0 * tan(deg_to_rad(eye.fov) * 0.5) * float(known.fill)
	var distance := maxf(extent.y, extent.x / maxf(0.01, aspect)) / maxf(0.001, reach)
	eye.position = Vector3(known.center.x, known.center.y, distance)
	eye.near = maxf(distance * 0.02, 0.01)
	eye.far = distance * 4.0 + extent.length() * 8.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Pixels on screen for the figure's rectangle.
func _pixels() -> Vector2i:
	var scale_on_screen := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale() if is_inside_tree() else Vector2.ONE
	return Vector2i((size * scale_on_screen.abs()).ceil()).max(Vector2i(32, 32))

func _draw() -> void:
	# Shown once framed, so the creature does not jump into place.
	if is_instance_valid(view) and _framed >= 24: draw_texture_rect(view.get_texture(), Rect2(Vector2.ZERO, size), false)

## Frames the figure's meshes (not its particles) so the creature fills
## `fill` of the view's height or width, whichever limits first.
static func aim(view: SubViewport, yaw: float, pitch: float, fill := 0.86) -> void:
	var figure: ELModel = view.get_node("Model")
	var pivot_node: Node3D = view.get_node("Pivot")
	var eye: Camera3D = pivot_node.get_node("Camera")
	var box := AABB()
	var first := true
	for node: Node in figure.get_children():
		var part := node as MeshInstance3D
		if part == null or part.mesh == null or not part.visible: continue
		var local := part.transform * part.mesh.get_aabb()
		local = AABB(local.position * figure.scale, local.size * figure.scale)
		box = local if first else box.merge(local)
		first = false
	if first: box = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	# Fit the box's corners as the camera sees them, not its bounding sphere:
	# long creatures seen at an angle are much narrower than their diagonal.
	pivot_node.position = box.get_center()
	pivot_node.rotation = Vector3(-pitch, yaw, 0)
	var facing := pivot_node.basis.inverse()
	var low := Vector3.INF
	var high := -Vector3.INF
	for corner in 8:
		var point := facing * (box.get_endpoint(corner) - box.get_center())
		low = low.min(point)
		high = high.max(point)
	var vertical := tan(deg_to_rad(eye.fov) * 0.5)
	var aspect := float(view.size.x) / maxf(1.0, float(view.size.y))
	var half := (high - low) * 0.5
	var reach := maxf(half.y / vertical, half.x / (vertical * maxf(0.01, aspect))) / fill
	var distance := reach + high.z
	var middle := (high + low) * 0.5
	eye.position = Vector3(middle.x, middle.y, distance)
	eye.near = maxf(distance * 0.02, 0.01)
	eye.far = distance * 4.0 + half.length() * 8.0

## Built creature views no figure shows, by code: a reroll or a new round
## takes one instead of building the creature again.
static var _spare: Dictionary = {}
static var _spare_count := 0
const SPARE_LIMIT := 96
var _idle_back: Callable

## Shows `value`'s creature (empty clears). Keeps the figure when unchanged.
func show_code(data: ELProfile, value: String) -> void:
	if value == code and is_instance_valid(view): return
	profile = data
	release()
	code = value
	if value.is_empty(): return
	var spares: Array = _spare.get(value, [])
	while not spares.is_empty() and view == null:
		var kept: SubViewport = spares.pop_back()
		_spare_count -= 1
		if is_instance_valid(kept): view = kept
	if view == null:
		view = ELWikiPreview.stage(profile, value, _pixels(), true)
		if view == null: return
		view.gui_disable_input = true
		for node: Node in view.get_children():
			if node is WorldEnvironment:
				var environment: Environment = (node as WorldEnvironment).environment
				environment.background_mode = Environment.BG_CLEAR_COLOR
				environment.tonemap_exposure = maxf(environment.tonemap_exposure, 1.3)
	# Always while framing (the figure is not drawn yet), then only on screen.
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	model = view.get_node("Model")
	model.idle_specials = false
	model.play("cidle")
	_idle_back = func(clip: String): if clip != "udeath" and is_instance_valid(model): model.play.call_deferred("cidle")
	model.animation_finished.connect(_idle_back)
	_framed = 0

## Gives the shown creature's view back: kept for the next figure of the
## same creature once it is framed, otherwise freed.
func release() -> void:
	if not is_instance_valid(view):
		view = null
		model = null
		return
	if is_instance_valid(model) and _idle_back.is_valid() and model.animation_finished.is_connected(_idle_back):
		model.animation_finished.disconnect(_idle_back)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if (_framed >= 24 or _framings.has(_framing_key())) and _framed >= 2 and _spare_count < SPARE_LIMIT and not code.is_empty() and is_instance_valid(model):
		model.play("cidle")
		remove_child(view)
		if not _spare.has(code): _spare[code] = []
		_spare[code].append(view)
		_spare_count += 1
	else:
		# Freed at the end of the frame, still in the tree for the effects'
		# deferred setup.
		view.queue_free()
	view = null
	model = null
	code = ""

## Frees the kept views (they are outside the tree, so nothing else does).
static func free_spares() -> void:
	for views: Array in _spare.values():
		for spare: Node in views:
			if is_instance_valid(spare): spare.free()
	_spare.clear()
	_spare_count = 0

## A new recruit's arrival: its summon clip where it has one, rising into
## view in a glow of its colour's summon (the shop has no particles).
func arrive(glow: Color) -> void:
	if is_instance_valid(model) and model.has_clip("usummon"): model.play("usummon")
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2(0.55, 0.55)
	modulate.a = 0.0
	set_glow(glow, 1.0, false)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.chain().tween_method(func(strength: float): set_glow(glow, strength, false), 1.0, 0.0, 0.8)

## Plays a one-off clip (an evolution's summon), then returns to idle.
func act(clip: String) -> void:
	if is_instance_valid(model) and model.has_clip(clip): model.play(clip)

func set_glow(color: Color, strength: float, pulse: bool) -> void:
	if strength <= 0.0:
		material = null
		return
	if _glow_material == null:
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = GLOW_SHADER
	_glow_material.set_shader_parameter("glow_color", color)
	_glow_material.set_shader_parameter("glow_strength", strength)
	_glow_material.set_shader_parameter("upgrade_pulse", pulse)
	material = _glow_material

## Re-centres and zooms from what was actually drawn: the opaque pixels of
## the last frame, so every creature fills `fill` of the view whatever its
## parts' bounds claim. False when nothing was drawn yet.
## With `relative`, smaller creatures fill less of the view (a rat stays
## smaller than an ogre), down to a readable minimum.
## The rectangle of solid pixels (alpha above one half): faint particles and
## soft glows around a creature do not count.
static func solid_rect(image: Image) -> Rect2i:
	# Measured on a small copy: a full-size scan in script stalls the frame.
	var full := Vector2(image.get_width(), image.get_height())
	var ratio := minf(1.0, 96.0 / maxf(full.x, full.y))
	var small := image
	if ratio < 1.0:
		small = image.duplicate()
		small.resize(maxi(1, roundi(full.x * ratio)), maxi(1, roundi(full.y * ratio)), Image.INTERPOLATE_BILINEAR)
	var low := Vector2i(small.get_width(), small.get_height())
	var high := Vector2i(-1, -1)
	for y in small.get_height():
		for x in small.get_width():
			if small.get_pixel(x, y).a > 0.5:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	if high.x < 0: return Rect2i()
	var start := (Vector2(low) / ratio).floor()
	var finish := (Vector2(high + Vector2i.ONE) / ratio).ceil().min(full)
	return Rect2i(Vector2i(start), Vector2i(finish - start))

static func refine(view: SubViewport, fill := 0.86, relative := false) -> float:
	# Nothing is drawn without a display (headless checks).
	if DisplayServer.get_name() == "headless": return 1.0
	var image := view.get_texture().get_image()
	if image == null or image.is_empty(): return 0.0
	var used := solid_rect(image)
	if used.size.x < 2 or used.size.y < 2: return 0.0
	var eye: Camera3D = view.get_node("Pivot/Camera")
	var area := Vector2(view.size)
	var per_pixel := 2.0 * eye.position.z * tan(deg_to_rad(eye.fov) * 0.5) / area.y
	var shift := (Vector2(used.get_center()) - area * 0.5) * per_pixel
	if relative:
		var world := maxf(used.size.x, used.size.y) * per_pixel
		fill *= clampf(world / LARGE, 0.68, 1.0)
	var factor := maxf(used.size.x / area.x, used.size.y / area.y) / fill
	# The creature's drawn size in world units: the same for any view shape.
	view.set_meta("extent", Vector2(used.size) * per_pixel)
	view.set_meta("fill", fill)
	eye.position.x += shift.x
	eye.position.y -= shift.y
	eye.position.z *= clampf(factor, 0.2, 2.0)
	return factor

func _process(_delta: float) -> void:
	if not is_instance_valid(view): return
	var pixels := _pixels()
	if view.size != pixels:
		view.size = pixels
		_framed = 0
	if is_visible_in_tree(): queue_redraw()
	# Frame after the model and its particles have shown a few poses.
	# Then refine from the drawn pixels every other frame until it settles.
	if _framed < 24 and view.size.x > 8 and view.size.y > 8:
		_framed += 1
		var pivot_node: Node3D = view.get_node("Pivot")
		var eye: Camera3D = pivot_node.get_node("Camera")
		if _framed == 1 and _framings.has(_framing_key()):
			_apply_framing(_framings[_framing_key()])
			# One frame later the view holds the framed creature.
			_framed = 23
			return
		if _framed == 2: aim(view, yaw, pitch, zoom)
		elif _framed >= 4 and _framed % 2 == 0:
			var factor := refine(view, zoom, relative)
			if factor > 0.0 and absf(factor - 1.0) < 0.04:
				_framed = 24
				if view.has_meta("extent"):
					_framings[_framing_key()] = {"pivot": pivot_node.transform, "center": Vector2(eye.position.x, eye.position.y),
						"extent": view.get_meta("extent"), "fill": float(view.get_meta("fill"))}
		if _framed >= 24: view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
