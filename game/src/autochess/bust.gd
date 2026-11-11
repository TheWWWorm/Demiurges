class_name ELAutochessBust
extends Control
## The hero's own model cropped to head and shoulders on a transparent
## background (the landing's hero choice). The view renders at the bust's
## size on screen so the hero stays sharp. Framing comes from what is drawn:
## first the head alone, so wings, staffs and raised weapons cannot pull the
## crop away from the face.

var profile: ELProfile
var hero := ""
var view: SubViewport
var camera: Camera3D
var model: ELModel
## Head heights shown from the top of the head down.
var heads := 2.3
## How far right of centre the head sits, as a share of the width.
var shift := 0.0
var _framed := 0
var _head := Rect2()
var _measure_size := 0.0
var _measure_center := Vector3.ZERO
var _isolated := false
var _head_part := false
var _tall := 1.8
## The chin: the bottom of the head part (crests, horns and wings grow from
## the head upwards, never below it).
var _chin := -1.0
## Measured heads by hero: a hero shown again is framed at once.
static var _measured: Dictionary = {}

static func is_measured(id: String) -> bool:
	return _measured.has(id)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.gui_disable_input = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.size = Vector2i(64, 64)
	add_child(view)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	view.add_child(camera)
	# A key light from the front, a softer fill from the other side and a
	# rim from behind, so the heroes' dark armour and faces read clearly.
	for setup: Array in [[Vector3(-22, -25, 0), 1.0], [Vector3(-10, 35, 0), 0.7], [Vector3(-15, 160, 0), 0.4]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setup[0]
		light.light_energy = setup[1]
		view.add_child(light)
	var ambient := WorldEnvironment.new()
	ambient.environment = Environment.new()
	ambient.environment.background_mode = Environment.BG_CLEAR_COLOR
	ambient.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambient.environment.ambient_light_color = Color(0.86, 0.84, 0.82)
	# The originals' hero models are dark textured; the preview lifts them.
	ambient.environment.tonemap_exposure = 1.25
	view.add_child(ambient)
	# Wings and staffs leaving the frame fade out instead of ending in a cut.
	var fade := Shader.new()
	fade.code = """shader_type canvas_item;
void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= smoothstep(0.0, 0.1, UV.x) * smoothstep(1.0, 0.9, UV.x) * smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.88, UV.y);
}"""
	material = ShaderMaterial.new()
	material.shader = fade

func _pixels() -> Vector2i:
	var scale_on_screen := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale() if is_inside_tree() else Vector2.ONE
	return Vector2i((size * scale_on_screen.abs()).ceil()).max(Vector2i(16, 16))

func _draw() -> void:
	if _framed > 6: draw_texture_rect(view.get_texture(), Rect2(Vector2.ZERO, size), false)

func show_hero(data: ELProfile, id: String) -> void:
	if id == hero and is_instance_valid(model): return
	profile = data
	hero = id
	if is_instance_valid(model):
		model.hide()
		model.queue_free()
	model = null
	var row := ELAutochessCharacters.row(profile, id)
	if row.is_empty(): return
	model = ELModel.new()
	view.add_child(model)
	if not model.build(profile, String(row.get("Model", "")), "Heroes/" + String(row.get("Texture", "")).replace("\\", "/")):
		model.queue_free()
		model = null
		return
	model.idle_specials = false
	model.rotation_degrees.y = -30.0
	model.play("cidle")
	model.animation_finished.connect(func(clip: String):
		if clip != "udeath" and is_instance_valid(model): model.play.call_deferred("cidle"))
	_framed = 0
	queue_redraw()

func react(clip: String) -> void:
	if _framed <= 6: return
	if is_instance_valid(model) and model.has_clip(clip): model.play(clip)

## Draws only the head while measuring, or the body when the head is part
## of it, never wings, staffs or raised weapons. False when neither exists.
func _isolate_head(on: bool) -> bool:
	var keep := ""
	for wanted: String in ["head", "body"]:
		for node: Node in model.get_children():
			if node is MeshInstance3D and String(node.name).to_lower() == wanted: keep = wanted
		if not keep.is_empty(): break
	if keep.is_empty(): return false
	for node: Node in model.get_children():
		var part := node as MeshInstance3D
		if part == null or String(part.name).to_lower() == keep: continue
		if on:
			part.set_meta("bust_visible", part.visible)
			part.visible = false
		elif part.has_meta("bust_visible"):
			part.visible = bool(part.get_meta("bust_visible"))
			part.remove_meta("bust_visible")
	_head_part = keep == "head"
	_chin = -1.0
	if _head_part:
		for node: Node in model.get_children():
			var part := node as MeshInstance3D
			if part != null and part.mesh != null and String(part.name).to_lower() == "head":
				_chin = (part.transform * part.mesh.get_aabb()).position.y * model.scale.y
	return true

## The hero's standing height: the top of the body (wings, staffs, helmets
## and weapons do not count), so every bust shows the same share of a hero.
func _stature() -> float:
	var top := 0.0
	for node: Node in model.get_children():
		var part := node as MeshInstance3D
		# The body's top (tall helmets and crests would shrink the face).
		if part == null or part.mesh == null or String(part.name).to_lower() != "body": continue
		top = maxf(top, (part.transform * part.mesh.get_aabb()).end.y * model.scale.y)
	return top if top > 0.3 else ELWikiPreview.bounds(model).end.y

func _process(_delta: float) -> void:
	if not is_instance_valid(model) or DisplayServer.get_name() == "headless": return
	var pixels := _pixels()
	if view.size != pixels:
		view.size = pixels
		if _framed > 6: _fit()
	if _framed > 6:
		queue_redraw()
		return
	_framed += 1
	if _framed == 2 and _measured.has(hero):
		var known: Array = _measured[hero]
		_head = known[0]
		_tall = known[1]
		_measure_center = known[2]
		_framed = 7
		_fit()
		queue_redraw()
		return
	if _framed == 3:
		# The whole figure from the front, with only the head drawn.
		var box := ELWikiPreview.bounds(model)
		_measure_size = maxf(box.size.y, box.size.x) * 2.0
		_measure_center = box.get_center()
		camera.size = _measure_size
		camera.h_offset = 0.0
		camera.position = _measure_center + Vector3(0, 0, 8)
		camera.look_at(_measure_center)
		_isolated = _isolate_head(true)
	elif _framed == 6:
		var image := view.get_texture().get_image()
		var used := image.get_used_rect() if image != null else Rect2i()
		_isolate_head(false)
		if used.size.y < 2:
			# Nothing drawn yet: measure again.
			_framed = 2
			return
		var per_pixel := _measure_size / float(view.size.y)
		var middle := Vector2(view.size) * 0.5
		var head := Rect2(used)
		_tall = _stature()
		if not _head_part:
			# No separate head: the top of the body, centred on its densest
			# columns (the neck and head rather than raised shoulders).
			var band := maxi(2, used.size.y / 7)
			var columns := PackedFloat32Array()
			columns.resize(used.size.x)
			for y in range(used.position.y, used.position.y + band):
				for x in used.size.x:
					if image.get_pixel(used.position.x + x, y).a > 0.5: columns[x] += 1.0
			var densest := 0
			for x in used.size.x:
				if columns[x] > columns[densest]: densest = x
			var width := float(band)
			head = Rect2(used.position.x + densest - width * 0.5, used.position.y, width, band)
		var top_left := Vector2(_measure_center.x + (head.position.x - middle.x) * per_pixel, _measure_center.y + (middle.y - head.position.y) * per_pixel)
		_head = Rect2(top_left, head.size * per_pixel)
		if _head_part and _chin > 0.3:
			# Crests, horns and wings belong to the head part: its top is
			# capped above the chin (unless the head is the top of the
			# figure, as on the hunched giants), and the crop is centred on
			# the face, the band just above the chin.
			var top := _head.position.y
			if top > _tall + 0.05: top = minf(top, _chin + _tall * 0.25)
			var face_rows := maxi(2, int(_tall * 0.12 / per_pixel))
			var chin_row := int(middle.y - (_chin - _measure_center.y) / per_pixel)
			var weight := 0.0
			var sum := 0.0
			for y in range(clampi(chin_row - face_rows, 0, image.get_height()), clampi(chin_row, 0, image.get_height())):
				for x in range(used.position.x, used.end.x):
					if image.get_pixel(x, y).a > 0.5:
						weight += 1.0
						sum += x
			var face_x := _measure_center.x + ((sum / weight if weight > 0.0 else Rect2(used).get_center().x) - middle.x) * per_pixel
			var width := minf(_head.size.x, _tall * 0.12)
			_head = Rect2(face_x - width * 0.5, top, width, top - _chin)
		_measured[hero] = [_head, _tall, _measure_center]
		_framed = 7
		_fit()
		queue_redraw()

## Head and shoulders from just above the head, the head centred (moved
## right by `shift`); `heads` scales the crop (2.3 is the usual one).
func _fit() -> void:
	if _head.size == Vector2.ZERO or size.y <= 0.0: return
	# Head and shoulders: the same share of every hero's height.
	var height := _tall * 0.42 * heads / 2.3
	var top := _head.position.y + height * 0.1
	var center := Vector3(_head.position.x + _head.size.x * 0.5, top - height * 0.5, _measure_center.z)
	camera.size = height
	camera.position = center + Vector3(0, 0, 8)
	camera.look_at(center)
	camera.h_offset = -camera.size * shift * size.x / size.y
