class_name ELAutochessFigure
extends Control
## A live figure in the interface: the original model and textures,
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
## Figures given the same dictionary are drawn at one common scale, standing
## on one baseline: the view height is what the tallest member needs. Each
## member is shown once all `count` members are framed.
var scale_group: Dictionary = {}
var _scale_base := Vector3.ZERO
var _scale_extent := Vector2.ZERO
var _scale_height := 0.0
var view: SubViewport
var model: ELModel
var _framed := 0
var _source_generation := -1
var _hero := false
var _glow_material: ShaderMaterial
## Compatibility index for unprofiled callers. Production framing records
## belong to the source profile and are invalidated by its mount generation.
static var _framings: Dictionary = {}

func _framing_key() -> String:
	var key := "hero:" + code if _hero else code
	return "%s|%.3f|%.3f|%.3f|%s" % [key, yaw, pitch, zoom, relative]

## Whether `code` was framed already (the loading screen frames them all).
static func is_framed(code: String, figure_yaw := deg_to_rad(-28.0), figure_pitch := deg_to_rad(10.0), figure_zoom := 0.88, figure_relative := true, source: ELProfile = null) -> bool:
	var key := "%s|%.3f|%.3f|%.3f|%s" % [code, figure_yaw, figure_pitch, figure_zoom, figure_relative]
	return _framings.has(key) if source == null else _profile_framings(source).has(key)

static func _profile_framings(source: ELProfile) -> Dictionary:
	if source == null: return {}
	var cache: Dictionary = source.get_meta("autochess_figure_framings", {})
	if int(cache.get("generation", -1)) != source.generation:
		cache = {"generation": source.generation, "figures": {}}
		source.set_meta("autochess_figure_framings", cache)
	return cache.figures

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
	set_process(false)

func _ready() -> void:
	_sync_activity()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_sync_activity()
	elif what == NOTIFICATION_EXIT_TREE:
		if is_instance_valid(view):
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			view.process_mode = Node.PROCESS_MODE_DISABLED
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()

func _sync_activity() -> void:
	var framing := is_instance_valid(view) and _framed < 24
	# Loading-screen figures finish framing even before their canvas texture
	# is shown. Afterwards hidden shop/reserve views stop their whole stage.
	var active := is_inside_tree() and is_instance_valid(view) and (framing or is_visible_in_tree())
	if is_instance_valid(view):
		view.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		view.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if framing else SubViewport.UPDATE_WHEN_VISIBLE) if active else SubViewport.UPDATE_DISABLED
	set_process(active)
	if active: queue_redraw()

## Pixels on screen for the figure's rectangle.
func _pixels() -> Vector2i:
	var scale_on_screen := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale() if is_inside_tree() else Vector2.ONE
	return Vector2i((size * scale_on_screen.abs()).ceil()).max(Vector2i(32, 32))

func _draw() -> void:
	# Shown once framed, so the creature does not jump into place.
	if is_instance_valid(view) and _framed >= 24 and (scale_group.is_empty() or _scale_height > 0.0):
		draw_texture_rect(view.get_texture(), Rect2(Vector2.ZERO, size), false)

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
	_show(data, value, false)

## Full-body hero preview using the same lighting and framing as creatures.
func show_hero(data: ELProfile, template: String) -> void:
	_show(data, template, true)

func _show(data: ELProfile, value: String, hero: bool) -> void:
	if value == code and hero == _hero and profile == data and data != null and data.generation == _source_generation and is_instance_valid(view): return
	release()
	profile = data
	_source_generation = data.generation if data != null else -1
	code = value
	_hero = hero
	if value.is_empty() or profile == null: return
	var spares: Array = _spare.get(_spare_key(), [])
	while not spares.is_empty() and view == null:
		var kept: SubViewport = spares.pop_back()
		_spare_count -= 1
		if is_instance_valid(kept): view = kept
	if spares.is_empty(): _spare.erase(_spare_key())
	if view == null:
		view = ELWikiPreview.stage_hero(profile, value, _pixels(), true) if hero else ELWikiPreview.stage(profile, value, _pixels(), true)
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
	_sync_activity()

func _spare_key() -> String:
	return "%d|%d|%s|%s" % [profile.get_instance_id(), _source_generation, _hero, code]

## Gives the shown creature's view back: kept for the next figure of the
## same creature once it is framed, otherwise freed.
func release() -> void:
	if not is_instance_valid(view):
		view = null
		model = null
		code = ""
		set_process(false)
		queue_redraw()
		return
	if is_instance_valid(model) and _idle_back.is_valid() and model.animation_finished.is_connected(_idle_back):
		model.animation_finished.disconnect(_idle_back)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.process_mode = Node.PROCESS_MODE_DISABLED
	if profile != null and profile.generation == _source_generation and (_framed >= 24 or _profile_framings(profile).has(_framing_key())) and _framed >= 2 and _spare_count < SPARE_LIMIT and not code.is_empty() and is_instance_valid(model):
		model.play("cidle")
		remove_child(view)
		var key := _spare_key()
		if not _spare.has(key): _spare[key] = []
		_spare[key].append(view)
		_spare_count += 1
	else:
		# Freed at the end of the frame, still in the tree for the effects'
		# deferred setup.
		view.queue_free()
	view = null
	model = null
	code = ""
	set_process(false)
	queue_redraw()

## Frees the kept views (they are outside the tree, so nothing else does).
static func free_spares() -> void:
	for views: Array in _spare.values():
		for spare: Node in views:
			if is_instance_valid(spare): spare.free()
	_spare.clear()
	_spare_count = 0

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
	if profile != null and profile.generation != _source_generation:
		_show(profile, code, _hero)
		return
	var pixels := _pixels()
	if view.size != pixels:
		view.size = pixels
		_framed = 0
		_sync_activity()
	# Frame after the model and its particles have shown a few poses.
	# Then refine from the drawn pixels every other frame until it settles.
	if _framed < 24 and view.size.x > 8 and view.size.y > 8:
		_framed += 1
		var pivot_node: Node3D = view.get_node("Pivot")
		var eye: Camera3D = pivot_node.get_node("Camera")
		var framings := _profile_framings(profile)
		if _framed == 1 and framings.has(_framing_key()):
			_apply_framing(framings[_framing_key()])
			# One frame later the view holds the framed creature.
			_framed = 23
			return
		if _framed == 2: aim(view, yaw, pitch, zoom)
		elif _framed >= 4 and _framed % 2 == 0:
			var factor := refine(view, zoom, relative)
			if factor > 0.0 and absf(factor - 1.0) < 0.04:
				_framed = 24
				if view.has_meta("extent"):
					framings[_framing_key()] = {"pivot": pivot_node.transform, "center": Vector2(eye.position.x, eye.position.y),
						"extent": view.get_meta("extent"), "fill": float(view.get_meta("fill"))}
					_framings[_framing_key()] = true
		_scale_height = 0.0
		if not scale_group.is_empty(): Dictionary(scale_group.get("heights", {})).erase(get_instance_id())
		if _framed >= 24: _sync_activity()
	if _framed >= 24 and not scale_group.is_empty(): _share_scale()

func _share_scale() -> void:
	var eye: Camera3D = view.get_node("Pivot/Camera")
	var reach := 2.0 * tan(deg_to_rad(eye.fov) * 0.5)
	var aspect := float(view.size.x) / maxf(1.0, float(view.size.y))
	var heights: Dictionary = scale_group.get_or_add("heights", {})
	if _scale_height <= 0.0 and not heights.has(get_instance_id()):
		# The camera as this figure's own framing left it, centred on it.
		_scale_base = eye.position
		_scale_extent = view.get_meta("extent", Vector2.ZERO)
		heights[get_instance_id()] = maxf(_scale_extent.y, _scale_extent.x / maxf(0.01, aspect)) / maxf(0.05, zoom)
	if heights.size() < int(scale_group.get("count", 1)): return
	var height: float = heights.values().max()
	# A member far wider than the rest still fits its own view.
	height = maxf(height, _scale_extent.x / maxf(0.01, aspect) / maxf(0.05, zoom))
	if is_equal_approx(height, _scale_height): return
	_scale_height = height
	eye.position.z = height / reach
	# Feet on a shared line: the figure's lowest point a margin above the bottom.
	var margin := height * (1.0 - zoom) * 0.5
	eye.position.y = _scale_base.y - _scale_extent.y * 0.5 + height * 0.5 - margin
	eye.near = maxf(eye.position.z * 0.02, 0.01)
	eye.far = eye.position.z * 4.0 + height * 8.0
	queue_redraw()
