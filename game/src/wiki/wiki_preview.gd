class_name ELWikiPreview
extends Control
## The live creature beside a wiki card page (as the EI remake's WikiPreview),
## or a story hero beside a guide that lists `heroes` (Diamanda, the White Lord),
## or a map object (a mine, a shop, a shrine) beside a guide that shows `!objects`:
## the creature's own model and textures from the installed game, playing its
## idle animation with its own particles (the whirlwind of an air wall, a
## spirit's trail: CreaturesPFX/<model>/idle.pfx, as in battle) in a small
## world of its own. Drag to turn it, use the wheel
## (or pinch) to zoom; Reset restores the view. tools/export_wiki.gd renders the
## same scene into the website's screenshots (ELWikiPreview.stage).

const BACKGROUND := Color("120e0b")
const YAW := deg_to_rad(-28.0)
const PITCH := deg_to_rad(14.0)
## Map objects are seen from above on the map: a steeper opening view.
const OBJECT_PITCH := deg_to_rad(30.0)
## The tables a map object (`!objects` marker) may name, as the adventure map
## resolves them (ELAdventureArt): their models wear TerrainObjects skins.
const OBJECT_TABLES := ["ResourceMine", "ResourceCut", "ManaNodes", "Buildings", "AdditionalBuildings",
	"NewBuildings", "GlobalSpellCut", "Artefacts", "TerrObj"]
## Other things an `!objects` marker may show (the cut-content pages): a
## CombatCreatures row by code, a HeroTemplates row, a bare model with skins,
## "Model/<model>@<texture>[@<second texture>]", for figures no table names, or
## a flat picture: "Icon/<code>", the spell icon of a card that has no page of
## its own, or "Portrait/<index>", a cell of the hero portrait sheets.
const FIGURE_TABLES := ["CombatCreatures", "HeroTemplates", "Model", "Icon", "Portrait"]
## The opening view: the whole model in its frame (see frame).
const OPENING_ZOOM := 1.0
## Clip frames sampled for a model's envelope.
const ENVELOPE_SAMPLES := 16
## Room left around a model that just fits its view.
const FIT_MARGIN := 1.03
## The opening view stands this much farther than a tight fit.
const OPENING_ROOM := 1.12
## The envelope radius of a man-sized figure (an orc warrior, a shaman):
## smaller models open smaller in their frame (opening_room).
const REFERENCE_RADIUS := 1.5
## The pitch the reader can turn the model to.
const MIN_PITCH_DEGREES := -20.0
const MAX_PITCH_DEGREES := 70.0
const RENDER_SCALE := 2.0
const MAX_RENDER_SIDE := 1536
const ANIMATIONS := ["cidle", "uattack", "ushot", "uhit", "udeath", "usummon", "utap", "uuntap", "uinstant"]

signal creature_changed
## The directions _extreme_points looks along.
static var _directions := PackedVector3Array()
var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var model: ELModel
var _distance := 4.0
var _yaw := YAW
var _pitch := PITCH
var _opening_pitch := PITCH
var _zoom := OPENING_ZOOM
var _dragging := false
var _sound: AudioStreamPlayer
var _picture: TextureRect
var _sound_directory := ""
var _profile: ELProfile

func _ready() -> void:
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if viewport != null: _picture.texture = viewport.get_texture()
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	resized.connect(_refit)
	get_viewport().size_changed.connect(_refit)
	_refit()

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

## The table row of map object `id` ("<Table>/<row>", or "<Table>/<Name>@<Level>"
## and "<Table>/<Name>" for tables keyed by number); empty when the game has none.
static func object_row(profile: ELProfile, id: String) -> Dictionary:
	var table_name := id.get_slice("/", 0)
	var key := id.substr(table_name.length() + 1)
	if key.is_empty(): return {}
	if table_name == "Model":
		var parts := key.split("@")
		if parts.size() < 2 or parts[0].is_empty() or profile.locate_figure(parts[0] + ".mod").is_empty(): return {}
		return {"Model": parts[0], "Texture": parts[1], "SecTexture": parts[2] if parts.size() > 2 else ""}
	if table_name == "Icon":
		var card: Dictionary = profile.table("CombatSpells").get(key, {})
		return {"Icon": key} if int(card.get("Icon", 0)) > 0 else {}
	if table_name == "Portrait":
		if not key.is_valid_int() or int(key) < 0: return {}
		return {"Portrait": int(key)} if profile.texture("Interface/heroes/photo_%02d" % (int(key) / 6 + 1)) != null else {}
	if table_name in FIGURE_TABLES: return profile.table(table_name).get(key, {})
	if not table_name in OBJECT_TABLES: return {}
	var table := profile.table(table_name)
	if table.has(key): return table[key]
	var name := key.get_slice("@", 0)
	var level := key.get_slice("@", 1) if "@" in key else ""
	for row: Dictionary in table.values():
		if str(row.get("Name", "")) == name and (level.is_empty() or str(row.get("Level", "")) == level): return row
	return {}

## A viewport holding map object `id` (see object_row) with its adventure-map
## model and skins; null when the game has no such object.
static func stage_object(profile: ELProfile, id: String, size: Vector2i, transparent := false) -> SubViewport:
	var table_name := id.get_slice("/", 0)
	var key := id.substr(table_name.length() + 1)
	if table_name == "CombatCreatures": return stage(profile, key, size, transparent)
	if table_name == "HeroTemplates": return stage_hero(profile, key, size, transparent)
	if is_flat(id): return null
	var row := object_row(profile, id)
	if table_name == "Model":
		if row.is_empty(): return null
		return _stage(profile, row.Model, row.Texture, row.SecTexture, 1.0, size, transparent)
	var model_name := str(row.get("Model", ""))
	if model_name.is_empty(): return null
	var skin := "TerrainObjects/" + str(row.get("TextureName", row.get("Texture", "")))
	var secondary := "TerrainObjects/" + str(row.SecTexture) if not str(row.get("SecTexture", "")).is_empty() else ""
	var wave := ELAdventureArt.animated_texture(row)
	return _stage(profile, model_name, skin, secondary, 1.0, size, transparent, "TerrainObjects/" + wave if not wave.is_empty() else "")

static func _stage(profile: ELProfile, model_name: String, skin: String, secondary: String, scale: float, size: Vector2i, transparent: bool, wave := "") -> SubViewport:
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
	if not figure.build(profile, model_name, skin, secondary, wave):
		view.free()
		return null
	figure.scale = Vector3.ONE * scale
	# Alpha32 skins (air walls, spirits) fade out in soft alpha: the wall's
	# lower half is a wisp of see-through cloth. Blend them instead of the
	# figure material's alpha cut-off, which drops everything below half.
	if skin.to_lower().trim_prefix("creatures/").trim_prefix("heroes/").trim_prefix("terrainobjects/").begins_with("alpha32"):
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
	# Capture weak references: a lambda's captured Node can already be freed
	# before its validity guard runs, which itself produces a script error.
	var figure_ref: WeakRef = weakref(figure)
	var effects_ref: WeakRef = weakref(effects)
	(func() -> void:
		var live_figure := figure_ref.get_ref() as ELModel
		var live_effects := effects_ref.get_ref() as ELCombatEffects
		if is_instance_valid(live_figure) and is_instance_valid(live_effects) and live_figure.is_inside_tree():
			live_effects.attach(live_figure)).call_deferred()
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

## The outline of the model's meshes through its current clip (its idle when
## staged): the outermost points of every part, posed at frames sampled
## across the clip, in the stage's space. Particles do not count: their
## instances carry billboard sizes and atlas cells in their axes, so their
## boxes reached tens of metres above a shaman's torch and shrank him to a
## speck (player report #262). Measured once per figure and kept.
static func outline(figure: ELModel) -> PackedVector3Array:
	if figure.has_meta("wiki_outline"): return figure.get_meta("wiki_outline")
	var points := PackedVector3Array()
	var extremes := {}
	var frames := figure.clip_frames()
	var at := figure.frame
	var samples := mini(frames, ENVELOPE_SAMPLES)
	for sample in samples:
		if frames > 1: figure.apply_frame(float(sample) * float(frames - 1) / float(maxi(1, samples - 1)))
		for name: String in figure.parts:
			var part: MeshInstance3D = figure.parts[name]
			if part.mesh == null or not part.visible: continue
			var local := PackedVector3Array()
			var posed := figure.posed_part_bounds(name)
			if posed != part.get_aabb():
				# A morphing part: the corners of its pose's box.
				for corner in 8: local.append(posed.get_endpoint(corner))
			else:
				if not extremes.has(part.mesh): extremes[part.mesh] = _extremes(part.mesh)
				local = extremes[part.mesh]
			for point in local: points.append(part.transform * point)
	if frames > 1: figure.apply_frame(at)
	points = _extreme_points(points)
	if points.is_empty():
		for corner in 8: points.append(AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE).get_endpoint(corner))
	for i in points.size(): points[i] *= figure.scale
	figure.set_meta("wiki_outline", points)
	return points

## The box around `figure`'s outline.
static func envelope(figure: ELModel) -> AABB:
	var points := outline(figure)
	var box := AABB(points[0], Vector3.ZERO)
	for point in points: box = box.expand(point)
	return box

## The outermost vertices of `mesh`.
static func _extremes(mesh: Mesh) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	for surface in mesh.get_surface_count():
		vertices.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return _extreme_points(vertices)

## The points of `points` farthest along each of a spread of directions: the
## corners of their hull, enough to frame them from any side.
static func _extreme_points(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() <= 32: return points
	if _directions.is_empty():
		for x in range(-2, 3):
			for y in range(-2, 3):
				for z in range(-2, 3):
					var direction := Vector3(x, y, z).normalized()
					if absi(x) + absi(y) + absi(z) in [1, 2, 3] and not direction in _directions: _directions.append(direction)
	var directions := _directions
	var best := PackedFloat32Array()
	best.resize(directions.size())
	best.fill(-INF)
	var chosen := PackedInt32Array()
	chosen.resize(directions.size())
	for i in points.size():
		var point := points[i]
		for d in directions.size():
			var reach := point.dot(directions[d])
			if reach > best[d]:
				best[d] = reach
				chosen[d] = i
	var result := PackedVector3Array()
	var seen := {}
	for i in chosen:
		if seen.has(i): continue
		seen[i] = true
		result.append(points[i])
	return result

## The camera distance at which the whole outline of `view`'s model shows,
## seen from `yaw`/`pitch` around its box's centre: every outline point
## inside the frustum.
static func fit_distance(view: SubViewport, yaw: float, pitch: float) -> float:
	var figure: ELModel = view.get_node("Model")
	var eye: Camera3D = view.get_node("Pivot/Camera")
	var vertical := tan(deg_to_rad(eye.fov) * 0.5)
	var aspect := float(view.size.x) / maxf(1.0, float(view.size.y))
	var horizontal := vertical * maxf(0.01, aspect)
	var facing := Basis.from_euler(Vector3(-pitch, yaw, 0)).inverse()
	var centre := envelope(figure).get_center()
	var distance := 0.0
	for point in outline(figure):
		var seen := facing * (point - centre)
		distance = maxf(distance, maxf(absf(seen.x) / horizontal, absf(seen.y) / vertical) + seen.z)
	return maxf(distance, 0.05) * FIT_MARGIN

## How much farther than a tight fit the opening view stands: room to zoom in,
## and a model smaller than a man framed as if it were between its size and a
## man's, so a Gibberling stands smaller in its frame than an orc.
static func opening_room(view: SubViewport) -> float:
	var size := envelope(view.get_node("Model")).size.length() * 0.5
	return OPENING_ROOM * sqrt(maxf(1.0, REFERENCE_RADIUS / maxf(0.05, size)))

## The nearest zoom (see frame) that still shows the whole model of `view`.
static func closest_zoom(view: SubViewport) -> float:
	return 1.0 / opening_room(view)

## Points the camera of `view` at its model from `yaw`/`pitch`; returns the
## framing distance. Zoom 1 is the opening view (opening_room); closest_zoom
## fits the whole model to the view.
static func frame(view: SubViewport, yaw: float, pitch: float, zoom := 1.0) -> float:
	var figure: ELModel = view.get_node("Model")
	var pivot_node: Node3D = view.get_node("Pivot")
	var eye: Camera3D = pivot_node.get_node("Camera")
	var box := envelope(figure)
	pivot_node.position = box.get_center()
	pivot_node.rotation = Vector3(-pitch, yaw, 0)
	var distance := fit_distance(view, yaw, pitch) * opening_room(view) * zoom
	var radius := maxf(box.size.length() * 0.5, 0.2)
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

## Shows map object `id` (see object_row); false when the game has none.
func show_object(profile: ELProfile, id: String) -> bool:
	if is_flat(id):
		# A card icon or a portrait: a flat picture instead of a model.
		_show(profile, null, "")
		var picture := flat_picture(profile, id)
		if picture == null or _picture == null: return false
		_picture.texture = picture
		custom_minimum_size = Vector2(320, 320)
		return true
	return _show(profile, stage_object(profile, id, Vector2i(512, 512)), "", object_pitch(id))

## True for `!objects` entries that are flat pictures, not models.
static func is_flat(id: String) -> bool:
	return id.begins_with("Icon/") or id.begins_with("Portrait/")

## The picture of a flat `!objects` entry (see is_flat); null when the game
## has none.
static func flat_picture(profile: ELProfile, id: String) -> Texture2D:
	if object_row(profile, id).is_empty(): return null
	if id.begins_with("Icon/"): return profile.card_icon(id.trim_prefix("Icon/"))
	if id.begins_with("Portrait/"): return profile.portrait(int(id.trim_prefix("Portrait/")))
	return null

## The opening view of `!objects` entry `id`: from above for buildings and
## terrain models, level with creatures and heroes.
static func object_pitch(id: String) -> float:
	var table_name := id.get_slice("/", 0)
	if table_name in ["CombatCreatures", "HeroTemplates"]: return PITCH
	if table_name == "Model": return OBJECT_PITCH if id.get_slice("/", 1).to_lower().begins_with("te") else PITCH
	return OBJECT_PITCH

func _show(profile: ELProfile, staged: SubViewport, sounds: String, pitch := PITCH) -> bool:
	# Switching editions (or heroes) replaces the figure shown.
	if viewport != null:
		remove_child(viewport)
		viewport.queue_free()
		viewport = null
	viewport = staged
	if _picture != null: _picture.texture = viewport.get_texture() if viewport != null else null
	if _sound != null: _sound.stop()
	if viewport == null:
		model = null
		creature_changed.emit()
		return false
	_profile = profile
	_sound_directory = sounds
	_opening_pitch = pitch
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 320)
	add_child(viewport)
	model = viewport.get_node("Model")
	model.animation_finished.connect(_resume_idle)
	pivot = viewport.get_node("Pivot")
	camera = pivot.get_node("Camera")
	reset_view()
	# Frame again once the panel is laid out.
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
	_pitch = _opening_pitch
	_zoom = OPENING_ZOOM
	_refit()

func _refit() -> void:
	if viewport == null: return
	var area := size
	if is_inside_tree(): area *= (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().abs()
	var longest := maxf(area.x, area.y)
	if longest > 0.0:
		var scale := minf(RENDER_SCALE, MAX_RENDER_SIDE / longest)
		var pixels := Vector2i((area * scale).round()).max(Vector2i(2, 2))
		if viewport.size != pixels: viewport.size = pixels
	_distance = frame(viewport, _yaw, _pitch, _zoom)

func zoom(factor: float) -> void:
	_zoom = clampf(_zoom * factor, closest_zoom(viewport), 2.5)
	_keep_whole()

func turn(by: Vector2) -> void:
	_yaw -= by.x * 0.01
	_pitch = clampf(_pitch + by.y * 0.01, deg_to_rad(MIN_PITCH_DEGREES), deg_to_rad(MAX_PITCH_DEGREES))
	_keep_whole()

## Keeps the zoom the reader chose, measured from the fit seen from this
## side, so the model never leaves its frame (player report #262).
func _keep_whole() -> void:
	_distance = frame(viewport, _yaw, _pitch, _zoom)

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
