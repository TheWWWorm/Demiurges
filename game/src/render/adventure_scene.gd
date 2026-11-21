## Modified for the EL1 Naval Worlds release, 18 November 2026.
class_name ELAdventureScene
extends Node3D
## Original adventure figures with chunked static instancing. Simulation and
## camera controls are separate from these visual resources.
var map: ELAdventureMap
var terrain: ELAdventureTerrain
var generated_roads: ELFirstRandomMapRoads
## Explicitly supplied installed EL2 data for its original ship appearance.
var naval_source: ELProfile
var naval_visuals: ELFirstNavalVisuals
var _ship_profile: ELProfile
## First game, version 16 random maps: the installed EL2 the shore pieces
## come from (null draws none; ELFirstShoreDecor).
var decor_source: ELProfile
var shore_decor: ELFirstShoreDecor
var units: Dictionary = {}
var animated: Array[ELModel] = []
## Options "animated objects": false holds map objects still.
var animate_objects := true
var errors: Array[String] = []
var objects_loaded := 0
var batches := 0
var build_usec := 0
var actors: Dictionary = {}
var object_models: Dictionary = {}
var _instances: Dictionary = {}
var _object_keys: Dictionary = {}
var _art: ELAdventureArt
## Fog of war (ELFog) as the local player sees it.
const FOG_DIM := 0.3
var fog_session: ELAdventureSession
var fog_player := 0
var _fog_revision := -1
var _fog_textures: Array[ImageTexture] = []
## Tile levels last applied, and the largest object footprint side (tiles).
var _fog_tiles := PackedByteArray()
var _fog_known := PackedByteArray()
var _fog_seen := PackedByteArray()
var _fog_active := false
var _fog_presence: Dictionary = {}
var _fog_cells: Dictionary = {}
var _fog_object_cells: Dictionary = {}
const PLACEMENT_REVISION := &"adventure_placement_revision"
## Original clip code of the walk clips (as in battles).
const WALK_CODE := 0x80140000
const RUN_CODE := 0x80100000
## Mist opacity per map corner (ELFog levels as the fog pass draws them): the
## value the last change started from, the target and the seconds since.
const FOG_UNEXPLORED := 255
const FOG_REMEMBERED := 133
const FOG_RATE := 150.0
## Tiles of mist drawn beyond each map edge.
const FOG_APRON := 24
var fog_from := PackedByteArray()
var fog_to := PackedByteArray()
var fog_since := 0.0
var _fog_fade_sent := 1.0
## A script's hard cut must hide terrain and figures together.
var snap_fog := false
var mist: ELFogMist
var _fog_apron: MeshInstance3D
## Options "fog animations": false keeps the mist's first frame.
var animate_fog := true
## Object brightness under the fog, as the original's object fade: each map
## object's brightness moves toward its fog target (visible 1, remembered
## FOG_DIM) at FOG_RATE / 255 a second, with the ground's mist, so a revealed
## object comes up out of the dark instead of appearing at full brightness
## over the still fogged ground. Objects the fog hides go at once.
## {uid: brightness}; `_fading` holds {uid: target} until it is reached.
var _fog_level: Dictionary = {}
## Second game: {uid: opacity}, which fades in with the brightness (#270).
var _fog_alpha: Dictionary = {}
var _fading: Dictionary = {}
const PICKUP_FADE := 0.18
var _retiring_pickups: Dictionary = {}
var _look_materials: Dictionary = {}
var _grey_textures: Dictionary = {}
var _pick_images: Dictionary = {}
## Instanced object groups that share one colourless cell value.
var _grey_groups: Array[Dictionary] = []
## Ground blob shadows (Effects/Shadow): one batched quad per object whose
## class draws one, keyed by uid ({index, local, base}).
var blobs: MultiMeshInstance3D
var _blob_slots: Dictionary = {}
const BLOB_ALPHA := 128.0 / 255.0
const BLOB_LIFT := 0.01
## Bushes and forest groups cast foliage silhouettes and a small contact shadow.
const FOLIAGE_BLOB_SCALE := 0.76
const FOLIAGE_BLOB_ALPHA := 0.25
const BLOB_SHADER := preload("res://src/render/adventure_blob_shadow.gdshader")
## How far the silhouette shadows darken the ground, and the sun that throws
## them toward the lower left of the opening view (fitted to original footage).
const SILHOUETTE_STRENGTH := 0.45
const SUN_ROTATION := Vector3(-40, 120, 0)
## Sun energy without and with silhouettes. The compatibility renderer adds
## a shadowed sun in its own pass after display encoding, which lit figures
## ≈8–11% brighter at the same energy; 0.4 keeps them within ≈1–4% of the
## unshadowed look. The terrain shader
## lights the ground itself and ignores the energy.
const SUN_ENERGY := 0.7
const SHADOW_SUN_ENERGY := 0.4
var sun: DirectionalLight3D
## The map's ambient light and background.
var environment: Environment
## Etherlords II colourless zones: the session whose level is shown.
var colorless_session: ELAdventureSession
var colorless_shown := -1

func build(source: ELAdventureMap, session: ELAdventureSession = null) -> bool:
	var started := Time.get_ticks_usec()
	map = source
	terrain = ELAdventureTerrain.new()
	add_child(terrain)
	if not terrain.build(map):
		errors.append_array(terrain.errors)
		return false
	if ELFirstRandomMap.is_random_id(map.id):
		generated_roads = ELFirstRandomMapRoads.new()
		add_child(generated_roads)
		generated_roads.build(map)
	if not ELFirstShoreDecor.items(map).is_empty() and ELFirstShoreDecor.source(decor_source) != null:
		shore_decor = ELFirstShoreDecor.new()
		add_child(shore_decor)
		shore_decor.build(map, decor_source, _add_animated)
	if ELFirstNaval.enabled(map):
		_ship_profile = ELFirstNavalVisuals.ship_source(naval_source)
		naval_visuals = ELFirstNavalVisuals.new()
		if shore_decor != null: naval_visuals.docked = shore_decor.docked
		add_child(naval_visuals)
		naval_visuals.build(map)
	_art = ELAdventureArt.new(map)
	var prototypes := {}
	var groups := {}
	var objects: Array = session.objects.values() if session != null else map.objects
	var fogged := session != null and ELFog.active(session, _fog_viewer(session))
	# Instances are grouped by their colourless cell value so a level switch
	# can grey whole groups.
	var zoned := session != null and map.profile.id == "el2" and map.colorless.size() == map.width * map.height
	var definitions := _prepare_art(objects)
	for index in objects.size():
		var object: Dictionary = objects[index]
		var uid := int(object.get("uid", int(object.permanent_id) - 1))
		# Defeated units leave the map. Script-created corpses are separate
		# objects, with their own appearance and lifetime.
		if object.get("type") in ["hero", "monster"] and not object.get("alive", true): continue
		var definition: Dictionary = definitions[index]
		if definition.get("hidden", false): continue
		if not object.get("visible", true): continue
		if definition.is_empty():
			errors.append("Missing art: %s / %s" % [object.group, object.name])
			continue
		var key := _art_key(definition)
		if not prototypes.has(key):
			var prototype := ELModel.new()
			add_child(prototype)
			if not _build_model(prototype, definition):
				errors.append(prototype.error)
				prototype.queue_free()
				continue
			prototype.hide()
			prototype.set_process(false)
			prototypes[key] = prototype
		var prototype: ELModel = prototypes[key]
		var center := ELAdventureGrid.center(object, definition.row)
		var position := _placement(object, definition.row)
		var transform := Transform3D(_placed_basis(int(object.rotation), float(definition.scale)), position)
		if blob_shadow(map.profile.id, object, definition) or _foliage_shadow(map.profile.id, object, definition):
			var foliage := _foliage_shadow(map.profile.id, object, definition)
			var footprint := FOLIAGE_BLOB_SCALE if foliage else 1.0
			_blob_slots[uid] = {"index": -1, "local": blob_local(prototype, footprint), "base": transform,
				"footprint": footprint, "opacity": FOLIAGE_BLOB_ALPHA if foliage else BLOB_ALPHA}
		var casts := silhouette(map.profile.id, object, definition)
		# Gates and forts need their own figures for their state-dependent poses.
		var gate := _second_gate(object)
		if definition.unit or prototype.clip_frames() > 1 or first_barrier(object) or gate or _movable_portal(object) or object.get("type") == "fort":
			var model := ELModel.new()
			add_child(model)
			if not _build_model(model, definition):
				errors.append(model.error)
				model.queue_free()
				continue
			model.transform = transform
			model.skip_hidden_pose = true
			model.watch_screen()
			model.set_meta("map_object", index)
			model.set_meta("art_key", key)
			if object.get("type") == "corpse" or not object.get("alive", true): _corpse_pose(model)
			if first_barrier(object): barrier_pose(model, bool(object.get("opened", false)), false)
			if gate: _second_gate_pose(model, bool(object.get("opened", false)), false)
			# A garrison hero is inside its fort; its own figure is not drawn.
			if object.get("fortified", false): model.hide()
			if object.get("type") == "fort": fort_flag(model, int(object.get("owner", -1)) >= 1)
			object_models[uid] = model
			if definition.unit:
				units[index] = model
				actors[uid] = model
			else: _add_animated(model)
			for part: MeshInstance3D in model.parts.values(): _shade(part, casts)
		else:
			for name: String in prototype.parts:
				var part: MeshInstance3D = prototype.parts[name]
				if part.mesh == null or not part.visible: continue
				var bits := ELColorless.cell_bits(map, Vector2i(center.floor())) if zoned else 0
				var group := "%d/%d/%s/%s/%d" % [object.x / 16, object.y / 16, key, name, bits]
				if not groups.has(group): groups[group] = {"mesh": part.mesh, "material": part.material_override, "transforms": [], "ids": [], "bits": bits, "casts": casts}
				groups[group].transforms.append(transform * prototype.global_transform.affine_inverse() * part.global_transform)
				groups[group].ids.append(uid)
		_object_keys[uid] = key
		objects_loaded += 1
	_build_blobs()
	for group: Dictionary in groups.values():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		# Fogged maps dim remembered objects through per-instance colours.
		instances.use_colors = fogged
		instances.mesh = group.mesh
		instances.instance_count = group.transforms.size()
		for i in group.transforms.size():
			instances.set_instance_transform(i, group.transforms[i])
			if fogged: instances.set_instance_color(i, Color.WHITE)
		if fogged and group.material is StandardMaterial3D: group.material.vertex_color_use_as_albedo = true
		var node := MultiMeshInstance3D.new()
		node.multimesh = instances
		node.set_meta(PLACEMENT_REVISION, 0)
		node.material_override = group.material
		_shade(node, bool(group.casts))
		add_child(node)
		if int(group.bits) != 0: _grey_groups.append({"node": node, "bits": group.bits, "material": group.material})
		for i in group.ids.size():
			var uid: int = group.ids[i]
			if not _instances.has(uid): _instances[uid] = []
			_instances[uid].append({"node": node, "index": i, "transform": group.transforms[i]})
		batches += 1
	for prototype: ELModel in prototypes.values():
		remove_child(prototype)
		prototype.queue_free()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Beyond the map edge is black; with fog on, the mist apron covers it.
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)
	self.environment = env
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.light_energy = SUN_ENERGY
	# The sun was fitted to the second game's opening view (camera yaw 0).
	# The first game's map camera looks a quarter turn round (yaw 90 degrees),
	# so its sun turns with it: shadows fall toward the lower left of the
	# view, at a figure's feet, instead of behind it.
	sun.rotation_degrees = SUN_ROTATION + (Vector3(0, 90, 0) if map.profile.id == "el1" else Vector3.ZERO)
	# Silhouette shadows: only the ground receives them (see `silhouette`).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	# Only the ground receives these shadows and it casts none, so the sun
	# needs no bias against self-shadowing; the default one lifted the shadows
	# of low figures and bushes off their feet and thinned them.
	sun.shadow_bias = 0.0
	sun.shadow_normal_bias = 0.0
	set_blob_shadows(true)
	enable_fog(session)
	enable_colorless(session)
	build_usec = Time.get_ticks_usec() - started
	return errors.is_empty()

func _art_key(definition: Dictionary) -> String:
	var key := "%s/%s/%s/%s" % [definition.model, definition.texture, definition.secondary, definition.get("wave", "")]
	if definition.get("first_ship", false): key += "/naval/%s/%d" % ["el2" if _ship_profile != null else "local", int(definition.get("ship_owner", 1))]
	return key

func _build_model(model: ELModel, definition: Dictionary) -> bool:
	if definition.get("first_ship", false):
		if _ship_profile != null: return model.build(_ship_profile, definition.model, definition.texture, definition.secondary)
		return ELFirstNavalVisuals.build_boat(model, map.profile, int(definition.get("ship_owner", 1)), str(definition.get("ship_color", "")))
	return model.build(map.profile, definition.model, definition.texture, definition.secondary, definition.get("wave", ""))

## Resolves each object's art (the build loop's `definitions`, by index) and
## reads what it needs on worker threads first: the figures, their idle
## clips and meshes, and the skins, as ELModel.build would read them one
## figure at a time. Everything lands in the profile's shared caches, so the
## figures built after are the same ones.
func _prepare_art(objects: Array) -> Array:
	var definitions := []
	definitions.resize(objects.size())
	var profile := map.profile
	var templates := {}
	var skins := {}
	for index in objects.size():
		var object: Dictionary = objects[index]
		if object.get("type") in ["hero", "monster"] and not object.get("alive", true): continue
		var definition := _art.resolve(object)
		definitions[index] = definition
		if definition.is_empty() or definition.get("hidden", false) or not object.get("visible", true): continue
		# EL1 ships use an explicit second-game profile or local geometry.
		if definition.get("first_ship", false): continue
		templates[ELArchive.key(str(definition.model))] = true
		for name: Variant in [definition.texture, definition.secondary, definition.get("wave", "")]:
			if not str(name).is_empty(): skins[str(name)] = true
	profile.prefetch_textures(skins.keys())
	var parsing: Array[Dictionary] = []
	for template: String in templates:
		if not profile.model_resources.has(template):
			parsing.append({"template": template, "files": ELModel.read_resources(profile, template)})
	_on_workers(parsing, func(job: Dictionary) -> void: job.resources = ELModel.parse_resources(job.template, job.files))
	for job: Dictionary in parsing:
		if not job.resources.has("error"): profile.model_resources[job.template] = job.resources
	var clips: Array[Dictionary] = []
	for template: String in templates:
		var resources: Dictionary = profile.model_resources.get(template, {})
		var animations: ELArchive = resources.get("animations")
		if animations != null and animations.has("cidle") and not resources.clips.has("cidle"): clips.append({"resources": resources})
	_on_workers(clips, func(job: Dictionary) -> void:
		var resources: Dictionary = job.resources
		job.tracks = ELModel.decode_clip(resources.animations, "cidle", resources.links)
		job.meshes = ELModel.clip_meshes(resources.figures, "cidle", job.tracks))
	for job: Dictionary in clips:
		var resources: Dictionary = job.resources
		resources.clips["cidle"] = job.tracks
		for key: String in job.meshes:
			if not resources.meshes.has(key): resources.meshes[key] = job.meshes[key]
	while not profile.finish_textures(): OS.delay_usec(200)
	return definitions

## Runs `work` for each job on worker threads. Without a display the
## placeholder renderer makes meshes, whose ids it does not hand out safely
## across threads, so the jobs run here one by one.
static func _on_workers(jobs: Array[Dictionary], work: Callable) -> void:
	if jobs.is_empty(): return
	if DisplayServer.get_name() == "headless":
		for job: Dictionary in jobs: work.call(job)
		return
	var task := WorkerThreadPool.add_group_task(func(index: int) -> void: work.call(jobs[index]), jobs.size(), -1, true, "Map art")
	WorkerThreadPool.wait_for_group_task_completion(task)

## EL2 always displays the human side. EL1 follows the strategic seat.
static func _fog_viewer(session: ELAdventureSession) -> int:
	return 1 if session.map.profile.id == "el2" else session.current_player

## The profile cache holds reusable atlas resources; this scene owns live
## fog, lighting and reflection state. The fallback also supports lightweight
## scene fixtures which supply only a cached ground material.
func _terrain_material() -> ShaderMaterial:
	if terrain != null: return terrain.material
	if map != null and map.profile.adventure_terrain_cache.get("map") == map.id:
		return map.profile.adventure_terrain_cache.get("material") as ShaderMaterial
	return null

## Turns the terrain and object fog on for the session's local player.
func enable_fog(session: ELAdventureSession) -> void:
	var material := _terrain_material()
	var shadow := blobs.material_override as ShaderMaterial if blobs != null else null
	fog_player = _fog_viewer(session) if session != null else 0
	fog_session = session if session != null and ELFog.active(session, fog_player) else null
	_fog_revision = -1
	if material != null: material.set_shader_parameter("fog_enabled", fog_session != null)
	if shadow != null: shadow.set_shader_parameter("fog_enabled", fog_session != null)
	if _fog_apron != null: _fog_apron.visible = fog_session != null
	if mist != null: mist.render_active = fog_session != null and is_visible_in_tree()
	if fog_session == null:
		if generated_roads != null: generated_roads.set_fog(PackedByteArray())
		if naval_visuals != null: naval_visuals.set_fog(PackedByteArray())
		if shore_decor != null: shore_decor.set_fog(PackedByteArray(), _dim_model)
		return
	if mist == null:
		mist = ELFogMist.new()
		mist.animate = animate_fog
		add_child(mist)
	if _fog_apron == null: _fog_apron = _make_fog_apron()
	_fog_apron.visible = true
	_fog_tiles = fog_tiles()
	if generated_roads != null: generated_roads.set_fog(_fog_tiles)
	if naval_visuals != null: naval_visuals.set_fog(_fog_tiles)
	if shore_decor != null: shore_decor.set_fog(_fog_tiles, _dim_model)
	var masks := _fog_data()
	_fog_known = masks[0].duplicate()
	_fog_seen = masks[1].duplicate()
	_fog_active = true
	fog_to = fog_corners(_fog_tiles)
	fog_from = fog_to
	fog_since = INF
	_fog_fade_sent = 1.0
	_fog_textures.clear()
	for data: PackedByteArray in [fog_from, fog_to]:
		_fog_textures.append(ImageTexture.create_from_image(Image.create_from_data(map.width + 1, map.height + 1, false, Image.FORMAT_R8, data)))
	if material != null:
		material.set_shader_parameter("fog_from", _fog_textures[0])
		material.set_shader_parameter("fog_to", _fog_textures[1])
		material.set_shader_parameter("fog_size", Vector2i(map.width, map.height))
		material.set_shader_parameter("fog_fade", 1.0)
		material.set_shader_parameter("fog_mist", mist.get_texture())
	if shadow != null:
		shadow.set_shader_parameter("fog_from", _fog_textures[0])
		shadow.set_shader_parameter("fog_to", _fog_textures[1])
		shadow.set_shader_parameter("fog_size", Vector2i(map.width, map.height))
		shadow.set_shader_parameter("fog_fade", 1.0)
	_fog_revision = ELFog.revision(fog_session)
	# The fog as loaded shows at once.
	_fog_level.clear()
	_fog_alpha.clear()
	_fog_presence.clear()
	_fading.clear()
	_fog_cells.clear()
	_fog_object_cells.clear()
	for item: Dictionary in fog_session.objects.values():
		_index_fog_object(item)
		fog_object(item, Vector2i(-1, -1), true)
	_sync_mist()

func _make_fog_apron() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(map.width + FOG_APRON * 2, map.height + FOG_APRON * 2) * ELAdventureTerrain.CELL
	var node := MeshInstance3D.new()
	node.mesh = plane
	node.position = Vector3(map.width, 0, -map.height) * ELAdventureTerrain.CELL * 0.5
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load("res://src/render/adventure_fog_apron.gdshader")
	material.set_shader_parameter("map_size", Vector2(map.width, map.height))
	material.set_shader_parameter("fog_mist", mist.get_texture())
	node.material_override = material
	add_child(node)
	return node

## Mist opacity per map corner for the local player: a corner takes its most
## fogged tile (unexplored or beyond the map 255, remembered 133, visible 0).
func fog_corners(tiles := PackedByteArray()) -> PackedByteArray:
	if tiles.is_empty(): tiles = fog_tiles()
	var columns := map.width + 1
	var corners := PackedByteArray()
	corners.resize(columns * (map.height + 1))
	return _update_fog_corners(tiles, corners, Rect2i(0, 0, columns, map.height + 1))

func _update_fog_corners(tiles: PackedByteArray, corners: PackedByteArray, area: Rect2i) -> PackedByteArray:
	var columns := map.width + 1
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var level := 0
			if x == 0 or y == 0 or x == map.width or y == map.height: level = FOG_UNEXPLORED
			else:
				var at := y * map.width + x
				level = maxi(maxi(tiles[at], tiles[at - 1]), maxi(tiles[at - map.width], tiles[at - map.width - 1]))
			corners[y * columns + x] = level
	return corners

## Mist opacity per tile for the local player (visible 0, remembered 133,
## unexplored 255).
func fog_tiles() -> PackedByteArray:
	var data := _fog_data()
	var known: PackedByteArray = data[0]
	var seen: PackedByteArray = data[1]
	var bit := 1 << fog_player
	var tiles := PackedByteArray()
	tiles.resize(map.width * map.height)
	if not ELFog.active(fog_session, fog_player): return tiles
	for i in tiles.size():
		tiles[i] = 0 if seen[i] & bit else (FOG_REMEMBERED if known[i] & bit else FOG_UNEXPLORED)
	return tiles

## The corner opacities shown now, part way from `fog_from` to `fog_to`.
func fog_shown() -> PackedByteArray:
	var step := FOG_RATE * fog_since
	if step >= 255.0: return fog_to.duplicate()
	var shown := fog_to.duplicate()
	var limit := int(step)
	var columns := map.width + 1
	for y in map.height + 1:
		var row := y * columns
		if fog_from.slice(row, row + columns) == fog_to.slice(row, row + columns): continue
		for i in range(row, row + columns):
			shown[i] = fog_from[i] + clampi(fog_to[i] - fog_from[i], -limit, limit)
	return shown

func set_animate_fog(on: bool) -> void:
	animate_fog = on
	if mist != null: mist.animate = on

func _sync_mist() -> void:
	var material := _terrain_material()
	if material != null: material.set_shader_parameter("fog_drift", mist.drift)
	if _fog_apron != null: (_fog_apron.material_override as ShaderMaterial).set_shader_parameter("fog_drift", mist.drift)
	# Drift continues after a reveal. Both materials keep the same completed
	# fade without another shader update until the next reveal changes it.
	var fade := minf(FOG_RATE * fog_since / 255.0, 1.0)
	if fade == _fog_fade_sent: return
	_fog_fade_sent = fade
	if material != null: material.set_shader_parameter("fog_fade", fade)
	if blobs != null: (blobs.material_override as ShaderMaterial).set_shader_parameter("fog_fade", fade)

func _fog_data() -> Array[PackedByteArray]:
	var size := map.width * map.height
	var known := fog_session.explored
	var seen: PackedByteArray = fog_session.fog.get("visible", PackedByteArray())
	if known.size() != size:
		known = PackedByteArray()
		known.resize(size)
	if seen.size() != size:
		seen = PackedByteArray()
		seen.resize(size)
	return [known, seen]

func _process(delta: float) -> void:
	# Noise time continues in the child, but a cached/hidden map does not
	# render its mist texture or send drift uniforms to invisible materials.
	if mist != null: mist.render_active = fog_session != null and is_visible_in_tree()
	if fog_session != null:
		fog_since += delta
		sync_fog()
		if mist != null and mist.render_active: _sync_mist()
		if not _fading.is_empty(): _fade_objects(delta)
	if not _retiring_pickups.is_empty(): _fade_pickups(delta)
	if colorless_session != null and colorless_session.colorless_level != colorless_shown: sync_colorless()

## Colourless zones: terrain corners touching a colourless cell are grey and
## mixed cells blend along the terrain's transition masks (and the
## tile composer); grey is (R+G+B)/3 of the 8-bit colour
## . Map objects whose footprint
## centre is colourless use greyscale copies of their textures.
## Everything is rebuilt on a level switch only.
func enable_colorless(session: ELAdventureSession) -> void:
	var material := _terrain_material()
	colorless_session = session if session != null and map.profile.id == "el2" and map.colorless.size() == map.width * map.height else null
	colorless_shown = -1
	if material != null: material.set_shader_parameter("clrless_enabled", false)
	if colorless_session == null: return
	sync_colorless()

func sync_colorless() -> void:
	var material := _terrain_material()
	colorless_shown = clampi(colorless_session.colorless_level, 0, 3)
	if material != null:
		var layer := ELAdventureTerrain.colorless_layer(map, colorless_shown)
		if not layer.is_empty():
			material.set_shader_parameter("clrless_cells", ImageTexture.create_from_image(layer.cells))
			material.set_shader_parameter("clrless_weights", ImageTexture.create_from_image(layer.weights))
			material.set_shader_parameter("clrless_columns", int(layer.columns))
			material.set_shader_parameter("clrless_atlas", Vector2(layer.weights.get_size()))
			material.set_shader_parameter("clrless_size", Vector2i(map.width, map.height))
			material.set_shader_parameter("clrless_enabled", true)
	for entry: Dictionary in _grey_groups:
		var node: MultiMeshInstance3D = entry.node
		node.material_override = _look_material(entry.material, 1.0, ((int(entry.bits) >> colorless_shown) & 1) == 1)
	for uid: int in object_models: grey_object(uid)

## Whether a map object is currently drawn grey (its footprint centre cell).
func object_greyed(uid: int) -> bool:
	return object_models.has(uid) and object_models[uid].get_meta("look_grey", false)

## Re-checks one modelled object or moving figure against the zone; `cell`
## overrides the object's own cell for a figure between cells.
func grey_object(uid: int, cell := Vector2i(-1, -1)) -> void:
	if colorless_session == null or not object_models.has(uid): return
	var item := colorless_session.object(uid)
	if item.is_empty() or not item.has("x"): return
	if cell.x < 0:
		var definition := _art.resolve(item)
		cell = Vector2i(ELAdventureGrid.center(item, definition.get("row", {})).floor())
	var model: ELModel = object_models[uid]
	var grey := ELColorless.object_grey(map, colorless_shown, cell)
	if model.get_meta("look_grey", false) == grey: return
	model.set_meta("look_grey", grey)
	_model_look(model)

## Applies the fog after any change of the session's masks.
func sync_fog() -> void:
	if fog_session == null or ELFog.revision(fog_session) == _fog_revision: return
	_fog_revision = ELFog.revision(fog_session)
	var scenery := {}
	var changed := _update_fog_tiles(scenery)
	if generated_roads != null and changed.has_area(): generated_roads.set_fog(_fog_tiles)
	if naval_visuals != null and changed.has_area(): naval_visuals.set_fog(_fog_tiles)
	if shore_decor != null and changed.has_area(): shore_decor.set_fog(_fog_tiles, _dim_model)
	if not changed.has_area():
		snap_fog = false
		return
	fog_from = fog_shown()
	var corners := changed.grow_individual(0, 0, 1, 1)
	fog_to = _update_fog_corners(_fog_tiles, fog_to, corners)
	if snap_fog:
		fog_from = fog_to.duplicate()
		snap_fog = false
	fog_since = 0.0
	_fog_textures[0].update(Image.create_from_data(map.width + 1, map.height + 1, false, Image.FORMAT_R8, fog_from))
	_fog_textures[1].update(Image.create_from_data(map.width + 1, map.height + 1, false, Image.FORMAT_R8, fog_to))
	for id: int in scenery: fog_object(fog_session.object(id))
	# The fog can change on either tile while a figure is between steps.
	for id: int in actors:
		var actor := fog_session.object(id)
		var passing := _actor_render_cell(id)
		if not actor.is_empty() and (changed.intersects(ELFog.object_bounds(fog_session, actor)) or changed.has_point(passing)):
			fog_object(actor, passing)

## Fog updates and movement must sample the same rendered position between
## logical steps, or a figure on the mist boundary is hidden and shown again.
func _actor_render_cell(uid: int) -> Vector2i:
	var actor: ELModel = actors.get(uid)
	if map.profile.id != "el2" or actor == null: return Vector2i(-1, -1)
	var cell := Vector2(actor.position.x, -actor.position.z) / ELAdventureTerrain.CELL - Vector2(0.5, 0.5)
	return Vector2i(cell.round())

func _index_fog_object(item: Dictionary) -> void:
	var id := int(item.uid)
	var bounds := Rect2i()
	if not actors.has(id) and (object_models.has(id) or _instances.has(id)):
		bounds = ELFog.object_bounds(fog_session, item).intersection(Rect2i(0, 0, map.width, map.height))
	var previous: Rect2i = _fog_object_cells.get(id, Rect2i())
	if bounds == previous: return
	for y in range(previous.position.y, previous.end.y):
		for x in range(previous.position.x, previous.end.x):
			var cell := Vector2i(x, y)
			_fog_cells[cell].erase(id)
			if _fog_cells[cell].is_empty(): _fog_cells.erase(cell)
	if not bounds.has_area():
		_fog_object_cells.erase(id)
		return
	_fog_object_cells[id] = bounds
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if not _fog_cells.has(cell): _fog_cells[cell] = {}
			_fog_cells[cell][id] = true

## The game stores per-player visibility and exploration as byte masks. An
## unchanged row needs no per-tile work. Use snapshots because exploration
## can also change in place (script observations and discoveries).
func _update_fog_tiles(scenery: Dictionary) -> Rect2i:
	var masks := _fog_data()
	var known := masks[0]
	var seen := masks[1]
	var active := ELFog.active(fog_session, fog_player)
	var all_rows := active != _fog_active
	var bit := 1 << fog_player
	var low := Vector2i(map.width, map.height)
	var high := Vector2i(-1, -1)
	for y in map.height:
		var row := y * map.width
		var end := row + map.width
		if not all_rows and (not active or (_fog_known.slice(row, end) == known.slice(row, end) and _fog_seen.slice(row, end) == seen.slice(row, end))): continue
		for x in map.width:
			var i := row + x
			var level := 0 if not active or seen[i] & bit else (FOG_REMEMBERED if known[i] & bit else FOG_UNEXPLORED)
			if _fog_tiles[i] == level: continue
			_fog_tiles[i] = level
			var cell := Vector2i(x, y)
			if _fog_cells.has(cell): scenery.merge(_fog_cells[cell])
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), y)
	_fog_known = known.duplicate()
	_fog_seen = seen.duplicate()
	_fog_active = active
	return Rect2i() if high.x < 0 else Rect2i(low, high - low + Vector2i.ONE)

## Unexplored objects and remembered heroes, monsters, castles and forts are
## hidden; other remembered objects are dimmed. A moving actor also counts the
## tile it is passing through. Brightening fades (see `_fog_level`) unless
## `instant`.
func fog_object(item: Dictionary, passing := Vector2i(-1, -1), instant := false) -> void:
	if fog_session == null or item.is_empty(): return
	var uid := int(item.uid)
	if _retiring_pickups.has(uid): return
	if not object_models.has(uid) and not _instances.has(uid): return
	if passing.x < 0: passing = _actor_render_cell(uid)
	var mode := ELFog.object_state(fog_session, fog_player, item)
	if passing.x >= 0 and mode != ELFog.VISIBLE: mode = maxi(mode, ELFog.object_state(fog_session, fog_player, item, passing))
	var present := _game_visible(item) and (mode == ELFog.VISIBLE or (mode == ELFog.REMEMBERED and not ELFog.dynamic(item)))
	var target := 0.0 if not present else (1.0 if mode == ELFog.VISIBLE else FOG_DIM)
	var level: float = _fog_level.get(uid, 0.0)
	if map.profile.id == "el2":
		# The second game fades each object's opacity along with its
		# brightness (`_fog_alpha`), and an object hidden in remembered fog
		# keeps the remembered brightness, so a hero or monster coming into
		# sight fades in from transparent at 0.3 brightness, not as a black
		# figure that slowly takes its colour (player report #270). The remake
		# still hides an object at once.
		var dim := 1.0 if mode == ELFog.VISIBLE else (FOG_DIM if mode == ELFog.REMEMBERED else 0.0)
		target = dim if _game_visible(item) else 0.0
		var alpha: float = _fog_alpha.get(uid, 0.0)
		if instant or not present:
			level = target
			alpha = 1.0 if present else 0.0
		_fog_level[uid] = level
		_fog_alpha[uid] = alpha
		if present and (level != target or alpha < 1.0): _fading[uid] = target
		else: _fading.erase(uid)
		_show_fogged(uid, present, level, alpha)
		return
	if instant or not present or target <= level: level = target
	_fog_level[uid] = level
	if level != target: _fading[uid] = target
	else: _fading.erase(uid)
	_show_fogged(uid, present, level)

## Steps the fading objects toward their fog brightness.
func _fade_objects(delta: float) -> void:
	var step := FOG_RATE / 255.0 * delta
	for uid: int in _fading.keys():
		if not object_models.has(uid) and not _instances.has(uid):
			_fading.erase(uid)
			continue
		var target: float = _fading[uid]
		var level := move_toward(float(_fog_level.get(uid, target)), target, step)
		_fog_level[uid] = level
		# Opacity (second game) rises at the same rate as brightness.
		var alpha := 1.0
		if _fog_alpha.has(uid):
			alpha = move_toward(float(_fog_alpha[uid]), 1.0, step)
			_fog_alpha[uid] = alpha
		if level == target and alpha >= 1.0: _fading.erase(uid)
		_show_fogged(uid, true, level, alpha)

func _show_fogged(uid: int, present: bool, level: float, alpha := 1.0) -> void:
	var toggled: bool = _fog_presence.get(uid) != present
	_fog_presence[uid] = present
	if object_models.has(uid):
		var model: ELModel = object_models[uid]
		model.visible = present and not model.get_meta("portal_hidden", false)
		_dim_model(model, level if present else 1.0)
		if map.profile.id == "el2":
			# The original's object opacity, linear like its brightness, in
			# the look materials: the Compatibility renderer ignores
			# GeometryInstance3D.transparency, and Forward+ cuts it at an
			# alpha-scissor part's threshold.
			var opacity := roundf(clampf(alpha, 0.0, 1.0) * 32.0) / 32.0 if present else 1.0
			if float(model.get_meta("look_alpha", 1.0)) != opacity:
				model.set_meta("look_alpha", opacity)
				_model_look(model)
	for entry: Dictionary in _instances.get(uid, []):
		var multimesh: MultiMesh = entry.node.multimesh
		if toggled: _place_instance(entry, entry.transform if present else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		var grey := roundi(level * 255.0) if present else 255
		if multimesh.use_colors and int(entry.get("grey", 255)) != grey:
			entry.grey = grey
			multimesh.set_instance_color(entry.index, Color8(grey, grey, grey))
			_mark_placement(entry.node)
	if toggled or actors.has(uid): _sync_blob(uid, present)

static func _mark_placement(node: MultiMeshInstance3D) -> void:
	node.set_meta(PLACEMENT_REVISION, int(node.get_meta(PLACEMENT_REVISION)) + 1)

static func _place_instance(entry: Dictionary, transform: Transform3D) -> void:
	entry.node.multimesh.set_instance_transform(entry.index, transform)
	_mark_placement(entry.node)

## The rules have already taken the pile. Keep only its on-screen pose for
## a short pickup animation while the hero and camera keep moving.
func retire_pickup(uid: int) -> bool:
	var model: ELModel = object_models.get(uid)
	var entries: Array = _instances.get(uid, [])
	if model == null and entries.is_empty(): return false
	if model != null and not model.visible: return false
	if model == null:
		var entry: Dictionary = entries[0]
		var mesh: MultiMesh = entry.node.multimesh
		if is_zero_approx(mesh.get_instance_transform(entry.index).basis.determinant()): return false
	# A pile may still be brightening after the moving hero revealed its tile.
	_fading.erase(uid)
	_retiring_pickups[uid] = {"elapsed": 0.0, "basis": model.basis if model != null else Basis.IDENTITY}
	return true

func _fade_pickups(delta: float) -> void:
	for uid: int in _retiring_pickups.keys():
		var pickup: Dictionary = _retiring_pickups[uid]
		pickup.elapsed += delta
		var model: ELModel = object_models.get(uid)
		if pickup.elapsed >= PICKUP_FADE:
			if model != null: model.basis = pickup.basis
			_fog_level[uid] = 0.0
			_show_fogged(uid, false, 0.0)
			_retiring_pickups.erase(uid)
			continue
		var shrink := 1.0 - smoothstep(0.0, PICKUP_FADE, pickup.elapsed)
		if model != null:
			var original: Basis = pickup.basis
			model.basis = original.scaled(Vector3.ONE * shrink)
		for entry: Dictionary in _instances.get(uid, []):
			var transform: Transform3D = entry.transform
			transform.basis = transform.basis.scaled(Vector3.ONE * shrink)
			_place_instance(entry, transform)
		_sync_blob(uid, true)

func _game_visible(item: Dictionary) -> bool:
	return item.get("visible", true) and item.get("placed", true) and not item.get("fortified", false) \
		and (not item.get("opened", false) or first_barrier(item) or _second_gate(item)) \
		and (item.get("alive", true) or item.get("type") not in ["hero", "monster"] or map.profile.id == "el2")

## Figure brightness under the fog (1 undimmed), in steps of 1/32 so fading
## figures share a few material copies.
func _dim_model(model: ELModel, level: float) -> void:
	level = roundf(clampf(level, 0.0, 1.0) * 32.0) / 32.0
	if float(model.get_meta("look_dim", 1.0)) == level: return
	model.set_meta("look_dim", level)
	_model_look(model)

## Applies a figure's fog dimming and colourless grey together; each part keeps
## its own material while neither applies.
func _model_look(model: ELModel) -> void:
	var dim: float = model.get_meta("look_dim", 1.0)
	var grey: bool = model.get_meta("look_grey", false)
	# Fog opacity (second game; see _show_fogged).
	var alpha: float = model.get_meta("look_alpha", 1.0)
	var plain := dim >= 1.0 and not grey and alpha >= 1.0
	for node: MeshInstance3D in model.parts.values():
		if not node.has_meta("look_base"):
			if plain or not node.material_override is StandardMaterial3D: continue
			node.set_meta("look_base", node.material_override)
		var base: StandardMaterial3D = node.get_meta("look_base")
		node.material_override = _look_material(base, dim, grey, alpha)
		if plain: node.remove_meta("look_base")

## A figure material at a fog brightness (1 undimmed) and opacity, grey or not.
func _look_material(base: Material, dim: float, grey: bool, alpha := 1.0) -> Material:
	var lit := base as StandardMaterial3D
	if lit == null or (dim >= 1.0 and not grey and alpha >= 1.0): return base
	var key := [lit, dim, grey, alpha]
	if not _look_materials.has(key):
		var copy: StandardMaterial3D = lit.duplicate()
		if dim < 1.0: copy.albedo_color = Color(lit.albedo_color.r * dim, lit.albedo_color.g * dim, lit.albedo_color.b * dim, lit.albedo_color.a)
		if alpha < 1.0:
			copy.albedo_color.a = lit.albedo_color.a * alpha
			# An opaque part keeps writing depth, so a fading figure does not
			# show its own far side.
			if copy.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED: copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
			if copy.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH]:
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if grey and lit.albedo_texture != null: copy.albedo_texture = _grey_texture(lit.albedo_texture)
		_look_materials[key] = copy
	return _look_materials[key]

## A greyscale copy of a texture, made once per texture (ELColorless.grey_image).
func _grey_texture(texture: Texture2D) -> Texture2D:
	if _grey_textures.has(texture): return _grey_textures[texture]
	var image := texture.get_image()
	if image == null: return texture
	var mipmaps := image.has_mipmaps()
	var prepared := mipmaps and (texture.has_meta(ELTexture.AUTHORED_MASK_MIPS) or texture.has_meta(ELTexture.COVERAGE_MASK_MIPS))
	# Rebuilding prepared alpha levels would erase thin silhouettes when a
	# figure enters a colourless zone. Recolour each level's RGB in place on
	# a private image; ordinary textures keep the previous filtering path.
	var grey := ELColorless.grey_image(image, prepared)
	if mipmaps and not prepared: grey.generate_mipmaps()
	var copied := ImageTexture.create_from_image(grey)
	for key: StringName in [ELTexture.ONE_BIT_ALPHA, ELTexture.AUTHORED_MASK_MIPS, ELTexture.COVERAGE_MASK_MIPS]:
		if texture.has_meta(key): copied.set_meta(key, texture.get_meta(key))
	_grey_textures[texture] = copied
	return _grey_textures[texture]

static func _placed_basis(rotation: int, art_scale: float) -> Basis:
	var mirror := Vector3(-1 if rotation & 1 else 1, 1, -1 if rotation & 2 else 1)
	return Basis(Vector3.UP, -float((rotation >> 2) & 3) * PI / 2.0).scaled_local(mirror * art_scale)

func update_object(item: Dictionary, apply_facing := false) -> void:
	if item.is_empty(): return
	var uid: int = item.uid
	_fog_presence.erase(uid)
	var actor: ELModel = actors.get(uid)
	if apply_facing and actor != null:
		actor.basis = _placed_basis(int(item.rotation), actor.basis.x.length())
	if _retiring_pickups.has(uid):
		if object_models.has(uid): object_models[uid].basis = _retiring_pickups[uid].basis
		_retiring_pickups.erase(uid)
	var gate := _second_gate(item)
	var visible := _game_visible(item)
	if not visible:
		if object_models.has(uid):
			var model: ELModel = object_models[uid]
			model.hide()
			if gate: _second_gate_pose(model, bool(item.get("opened", false)), false)
			if item.get("type") in ["hero", "monster"] and not item.get("alive", true):
				model.playing = false
				model.set_process(false)
		for entry: Dictionary in _instances.get(uid, []): _place_instance(entry, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_sync_blob(uid, false)
		return
	var definition := _art.resolve(item)
	if definition.is_empty() or definition.get("hidden", false): return
	var key := _art_key(definition)
	var unit: bool = item.type in ["hero", "monster", "corpse"]
	var own_model := unit or _movable_portal(item) or gate
	var replaceable: bool = own_model or item.type in ["rune_shop", "el1_spell_shop", "resource_mine", "mana_node", "fort"] or ELFirstScenario.is_castle(item)
	var needs_model := own_model and not object_models.has(uid)
	if replaceable and (_object_keys.get(uid, "") != key or needs_model):
		var model := ELModel.new()
		add_child(model)
		if not _build_model(model, definition):
			errors.append(model.error)
			model.queue_free()
			return
		model.skip_hidden_pose = true
		model.watch_screen()
		if object_models.has(uid):
			animated.erase(object_models[uid])
			object_models[uid].queue_free()
		for entry: Dictionary in _instances.get(uid, []): _place_instance(entry, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_instances.erase(uid)
		var art_scale := float(definition.scale)
		model.basis = _placed_basis(int(item.rotation), art_scale)
		# A replacement figure (such as a new costume or ship) keeps the
		# direction the unit had reached before its art changed.
		if unit and actor != null:
			model.basis = actor.basis.orthonormalized().scaled_local(Vector3.ONE * art_scale)
		model.set_meta("art_key", key)
		var casts := silhouette(map.profile.id, item, definition)
		for part: MeshInstance3D in model.parts.values(): _shade(part, casts)
		if _blob_slots.has(uid): _blob_slots[uid]["local"] = blob_local(model, float(_blob_slots[uid].footprint))
		object_models[uid] = model
		_object_keys[uid] = key
		if unit:
			actors[uid] = model
			units[int(item.source_index)] = model
		else: _add_animated(model)
	if fog_session != null: _index_fog_object(item)
	if object_models.has(uid):
		var model: ELModel = object_models[uid]
		model.visible = visible
		model.position = _placement(item, definition.row)
		if item.get("type") == "corpse" or not item.get("alive", true): _corpse_pose(model)
		if first_barrier(item): barrier_pose(model, bool(item.get("opened", false)), true)
		if gate: _second_gate_pose(model, bool(item.get("opened", false)), true)
		if item.get("type") == "fort": fort_flag(model, int(item.get("owner", -1)) >= 1)
		grey_object(uid)
		_sync_blob(uid, visible)
		return
	for entry: Dictionary in _instances.get(uid, []):
		_place_instance(entry, entry.transform if visible else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_sync_blob(uid, visible)

## Scripts swap portals in from off the map. Give each a model whose
## position follows the object instead of baking it into a static batch.
func _movable_portal(item: Dictionary) -> bool:
	return map.profile.id == "el2" and item.get("group") == "additional_buildings" and item.get("name") in ["Teleport", "TeleportReceiver"]

## A first-game runestone barrier (Runestone1/2), drawn as its own figure.
func first_barrier(item: Dictionary) -> bool:
	return map.profile.id == "el1" and item.get("group") == "additional_buildings" and item.get("name") in ["Runestone1", "Runestone2"]

func _second_gate(item: Dictionary) -> bool:
	return map.profile.id == "el2" and ELSecondGates.is_gate(item)

## EL2 runestones use the open and close clips on their own gate models.
## A gate built in either state starts on the last frame of that state's clip.
func _second_gate_pose(model: ELModel, opened: bool, animate: bool) -> void:
	var known := model.has_meta("gate_opened")
	if known and bool(model.get_meta("gate_opened")) == opened: return
	model.set_meta("gate_opened", opened)
	if model.play("uinstant" if opened else "uclose") and not (known and animate and animate_objects):
		_hold_frame(model, float(model.clip_frames() - 1))

## Opening plays the figure's "uinstant" clip, then hides its moving parts
## object02-object10 so the gate stays (end callback).
## Closing shows them at the clip's first frame. A figure built or
## loaded open, or with object animation off, takes the open pose at once.
func barrier_pose(model: ELModel, opened: bool, animate: bool) -> void:
	var known := model.has_meta("barrier_opened")
	if known and bool(model.get_meta("barrier_opened")) == opened: return
	model.set_meta("barrier_opened", opened)
	if not opened:
		if not known: return
		for part: MeshInstance3D in model.parts.values(): part.visible = true
		if model.play("uinstant"): _hold_frame(model, 0.0)
		return
	if animate and known and animate_objects and model.play("uinstant"):
		model.animation_finished.connect(func(clip: String) -> void: if clip == "uinstant" and bool(model.get_meta("barrier_opened")): _barrier_stones(model), CONNECT_ONE_SHOT)
		return
	if model.play("uinstant"): _hold_frame(model, float(model.clip_frames() - 1))
	_barrier_stones(model)

func _barrier_stones(model: ELModel) -> void:
	for name: String in model.parts:
		if name.begins_with("object") and int(name.substr(6)) in range(2, 11): model.parts[name].visible = false

func _hold_frame(model: ELModel, frame: float) -> void:
	model.frame = frame
	model.apply_frame(frame)
	model.playing = false
	model.set_process(false)

func _corpse_pose(model: ELModel) -> void:
	model.set_meta("corpse", true)
	var clip := model.clip_for_code(0x061c0000)
	if clip.is_empty() and model.has_clip("udeath"): clip = "udeath"
	if not clip.is_empty() and model.play(clip):
		_hold_frame(model, maxf(0.0, float(model.timing.get(clip, {}).get("frames", model.clip_frames())) - 1.0))
	else:
		# Some dedicated corpse figures already contain a static body pose.
		_hold_frame(model, 0.0)

## EL2 corpses can be drawn beyond their one-cell interaction footprint.
## Use their held pose so a pointer on the body can still select them.
func corpse_at(origin: Vector3, direction: Vector3) -> int:
	var closest := INF
	var picked := -1
	for id: int in actors:
		var model: ELModel = actors[id]
		if not model.has_meta("corpse") or not model.is_visible_in_tree(): continue
		for surface: Dictionary in _corpse_surfaces(model):
			var part: MeshInstance3D = surface.part
			if not part.visible: continue
			var inverse := part.global_transform.affine_inverse()
			var start := inverse * origin
			var ray := inverse.basis * direction
			if surface.bounds.intersects_ray(start, ray) == null: continue
			var vertices: PackedVector3Array = surface.vertices
			var indices: PackedInt32Array = surface.indices
			var uv: PackedVector2Array = surface.uv
			var material := part.material_override as BaseMaterial3D
			for i in range(0, indices.size(), 3):
				var a := indices[i]
				var b := indices[i + 1]
				var c := indices[i + 2]
				var hit: Variant = Geometry3D.ray_intersects_triangle(start, ray, vertices[a], vertices[b], vertices[c])
				if hit == null: continue
				if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and not _pick_opaque(material, hit, vertices[a], vertices[b], vertices[c], uv[a], uv[b], uv[c]): continue
				var distance := origin.distance_squared_to(part.to_global(hit))
				if distance < closest:
					closest = distance
					picked = id
	if picked >= 0 and _corpse_blocked(origin, origin + direction.normalized() * sqrt(closest)):
		return -1
	return picked

## Opaque scenery can cover a body. Check the current draw instances only
## after a corpse hit, so ordinary map picking pays no scenery traversal cost.
func _corpse_blocked(origin: Vector3, hit: Vector3) -> bool:
	for entries: Array in _instances.values():
		for entry: Dictionary in entries:
			var node: MultiMeshInstance3D = entry.node
			var material := node.material_override as BaseMaterial3D
			if material == null or material.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] or not node.is_visible_in_tree(): continue
			var mesh := node.multimesh.mesh
			var transform: Transform3D = node.global_transform * entry.transform
			if (transform * mesh.get_aabb()).intersects_segment(origin, hit) == null: continue
			if is_zero_approx(node.multimesh.get_instance_transform(entry.index).basis.determinant()): continue
			var inverse := transform.affine_inverse()
			var start := inverse * origin
			var end := inverse * hit
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i in range(0, indices.size(), 3):
				var a := indices[i]
				var b := indices[i + 1]
				var c := indices[i + 2]
				var point: Variant = Geometry3D.segment_intersects_triangle(start, end, vertices[a], vertices[b], vertices[c])
				if point == null: continue
				if material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or _pick_opaque(material, point, vertices[a], vertices[b], vertices[c], uv[a], uv[b], uv[c]):
					return true
	return false

func _pick_opaque(material: BaseMaterial3D, point: Vector3, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> bool:
	var opacity := material.albedo_color.a
	var texture := material.albedo_texture
	if texture != null:
		if not _pick_images.has(texture):
			var image := ELTexture.uncompressed(texture.get_image())
			_pick_images[texture] = image if image != null and image.detect_alpha() != Image.ALPHA_NONE else null
		var image: Image = _pick_images[texture]
		if image != null:
			var ab := b - a
			var ac := c - a
			var normal := ab.cross(ac)
			var weight_b := (point - a).cross(ac).dot(normal) / normal.length_squared()
			var weight_c := ab.cross(point - a).dot(normal) / normal.length_squared()
			var uv := ua + (ub - ua) * weight_b + (uc - ua) * weight_c
			uv = uv * Vector2(material.uv1_scale.x, material.uv1_scale.y) + Vector2(material.uv1_offset.x, material.uv1_offset.y)
			uv = uv.posmod(1.0) if material.texture_repeat else uv.clamp(Vector2.ZERO, Vector2.ONE)
			var size := image.get_size()
			var pixel := Vector2i(uv * Vector2(size)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
			opacity *= image.get_pixelv(pixel).a
	return opacity >= material.alpha_scissor_threshold

func _corpse_surfaces(model: ELModel) -> Array:
	if model.has_meta(&"corpse_surfaces"): return model.get_meta(&"corpse_surfaces")
	var surfaces := []
	for name: String in model.parts:
		var part: MeshInstance3D = model.parts[name]
		if part.mesh == null or not model.figures.has(name): continue
		var arrays: Array = model.figures[name].arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var morph: Array = model._previous_morphs.get(name, [])
		if not morph.is_empty() and part.mesh.has_meta("morph_positions"):
			vertices = part.mesh.get_meta("morph_positions")[morph.front()]
		if vertices.is_empty(): continue
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for vertex: Vector3 in vertices: bounds = bounds.expand(vertex)
		surfaces.append({"part": part, "vertices": vertices, "indices": arrays[Mesh.ARRAY_INDEX], "uv": arrays[Mesh.ARRAY_TEX_UV], "bounds": bounds})
	model.set_meta(&"corpse_surfaces", surfaces)
	return surfaces

func move_actor(uid: int, position: Vector2, moving: bool, tiles_per_second := 0.0, fast := false) -> void:
	if not actors.has(uid): return
	var model: ELModel = actors[uid]
	var next := ground_position(position.x, position.y)
	var delta := next - model.position
	if delta.length_squared() > 0.00001:
		model.rotation.y = atan2(delta.x, delta.z)
	model.position = next
	var clip := walk_clip(model) if moving else "cidle"
	if not model.get_meta("corpse", false):
		if map.profile.id == "el2":
			model.speed = 1.0
			var run := model.clip_for_code(RUN_CODE) if moving and fast else ""
			if moving and fast and run.is_empty() and model.has_clip("crun"): run = "crun"
			if not run.is_empty():
				clip = run
			elif moving:
				# The original advances 15 frames per world unit divided by
				# the authored walk speed. Use that gait at the faster travel
				# rate when a mounted figure only ships a walk clip.
				var stride := float(model.timing.get(clip, {}).get("speed", 0.0)) * model.scale.x
				if stride > 0.0 and tiles_per_second > 0.0:
					model.speed = (15.0 * ELAdventureTerrain.CELL * tiles_per_second) / (model.fps * stride)
				elif fast and clip != "cidle": model.speed = 2.0
		if model.base_clip() != clip: model.play(clip)
	# Movement through fog stays hidden; an actor appears as it steps into view.
	if fog_session != null: fog_object(fog_session.object(uid), Vector2i(roundi(position.x), roundi(position.y)))
	grey_object(uid, Vector2i(roundi(position.x), roundi(position.y)))

## The clip a map figure moves with: the one stored under the original walk
## code (hero and mount models keep "cwalk" there, map creatures their run
## clip), else a "cwalk"/"crun" clip, else its idle. Rider and mount are one
## figure, so the mount's legs move with the same clip.
static func walk_clip(model: ELModel) -> String:
	if model.has_meta("walk_clip"): return model.get_meta("walk_clip")
	var clip := model.clip_for_code(WALK_CODE)
	if clip.is_empty(): clip = "cwalk" if model.has_clip("cwalk") else ("crun" if model.has_clip("crun") else "cidle")
	model.set_meta("walk_clip", clip)
	return clip

## A scripted clip (ExPlayHeroAnimation): the figure plays it once and rests
## again; a death clip keeps its last frame. A figure without the clip is left
## as it is.
func play_actor_clip(uid: int, clip: String) -> void:
	var model: ELModel = actors.get(uid)
	if model == null or not model.has_clip(clip) or not model.play(clip): return
	if clip == "udeath": return
	model.animation_finished.connect(func(finished: String) -> void:
		if is_instance_valid(model) and finished == clip and model.clip == clip: model.play("cidle"), CONNECT_ONE_SHOT)

## The figure's clip with animation code `code` (either form of the high
## bit), played once like play_actor_clip; "" when it has none.
func play_actor_code(uid: int, code: int) -> String:
	var model: ELModel = actors.get(uid)
	if model == null: return ""
	var clip := _coded_clip(model, code)
	if not clip.is_empty(): play_actor_clip(uid, clip)
	return clip

static func _coded_clip(model: ELModel, code: int) -> String:
	var clip := model.clip_for_code(code)
	return model.clip_for_code(code | 0x80000000) if clip.is_empty() else clip

## EL2's Talk selects Enchantment, then Instant, then the generic attack
## (0x6826da, 0x6811d6). The Musician's map model calls its Instant `uattack`.
static func _speech_clip(model: ELModel) -> String:
	for code: int in [0x014c0000, 0x01cc0000, 0x02880000]:
		var clip := _coded_clip(model, code)
		if not clip.is_empty(): return clip
	return ""

func prepare_speech(uid: int) -> void:
	var model: ELModel = actors.get(uid)
	if model != null: model.prefetch_clip(_speech_clip(model))

func speak_actor(uid: int) -> void:
	var model: ELModel = actors.get(uid)
	if model == null: return
	var clip := _speech_clip(model)
	if not clip.is_empty(): play_actor_clip(uid, clip)

func orient_actor(uid: int, direction: Vector2) -> void:
	if actors.has(uid) and direction.length_squared() > 0.0001:
		actors[uid].rotation.y = atan2(direction.x, -direction.y)

## A map object's facing about the vertical axis: a unit's figure turns as it
## moves; other objects keep their placed quarter turn.
func object_yaw(item: Dictionary) -> float:
	var uid := int(item.get("uid", -1))
	if actors.has(uid): return actors[uid].rotation.y
	return -float((int(item.get("rotation", 0)) >> 2) & 3) * PI / 2.0

static func world_position(x: float, y: float) -> Vector3:
	return Vector3((x + 0.5) * ELAdventureTerrain.CELL, 0, -(y + 0.5) * ELAdventureTerrain.CELL)

func ground_position(x: float, y: float) -> Vector3:
	var at := world_position(x, y)
	if map != null: at.y = map.surface_height(Vector2(x + 0.5, y + 0.5))
	return at

## The height step between neighbouring ice sheets (_placement).
const ICE_LIFT := 0.015

func _placement(item: Dictionary, row: Dictionary) -> Vector3:
	var center := ELAdventureGrid.center(item, row)
	var at := ground_position(center.x - 0.5, center.y - 0.5)
	if item.group == "terrain_objects" and str(item.get("name", "")).begins_with("BlueIce_"):
		# Ice sheets lie flat on the snow and reach over their tile, so two
		# side by side shared one plane and flickered where they met. Each
		# of a 2 x 2 block of tiles lifts its sheet by a different hair.
		at.y += ICE_LIFT * float(1 + (int(item.x) & 1) + 2 * (int(item.y) & 1))
	if map.relief.is_empty() or item.group != "terrain_objects": return at
	var span := center - Vector2(item.x, item.y)
	if maxf(span.x, span.y) < 1.5: return at
	# Seat a broad rock or grove partly into the hillside so its downslope
	# edge still meets the ground.
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var edge := center + span * Vector2(sign_x, sign_y) * 0.60
			at.y = minf(at.y, map.surface_height(edge))
	return at

func ground_intersection(origin: Vector3, direction: Vector3) -> Variant:
	var flat: Variant = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	if flat == null or map == null or map.relief.is_empty() or direction.y >= -0.0001: return flat
	var bottom := -origin.y / direction.y
	var top := maxf(0.0, (255.0 * ELAdventureMap.RELIEF_UNIT - origin.y) / direction.y)
	var previous := top
	var steps := maxi(1, ceili((bottom - top) / (ELAdventureTerrain.CELL * 0.5)))
	for step in range(1, steps + 1):
		var next := lerpf(top, bottom, float(step) / steps)
		var point := origin + direction * next
		if point.y > _surface_at(point):
			previous = next
			continue
		for iteration in 12:
			var middle := (next + previous) * 0.5
			var probe := origin + direction * middle
			if probe.y > _surface_at(probe): previous = middle
			else: next = middle
		return origin + direction * next
	return flat

func _surface_at(at: Vector3) -> float:
	return map.surface_height(Vector2(at.x, -at.z) / ELAdventureTerrain.CELL)

## Second-game forts carry a flag their own clips raise ("utap"), wave
## ("cidleintap") and lower ("uuntap"). An owned fort flies it; a new figure
## of an owned fort starts with it already up, a fort taken while shown
## raises it, and one that loses its owner lowers it.
func fort_flag(model: ELModel, owned: bool) -> void:
	if model == null or model._animations == null or not model._animations.has("utap"): return
	var up := bool(model.get_meta("flag_up", false))
	if owned == up and model.has_meta("flag_up"): return
	model.set_meta("flag_up", owned)
	if owned:
		if not model.has_meta("flag_seen"):
			model.play("cidleintap")
		elif model.play("utap"):
			model.animation_finished.connect(func(clip: String):
				if clip == "utap" and is_instance_valid(model) and bool(model.get_meta("flag_up", false)): model.play("cidleintap"), CONNECT_ONE_SHOT)
	elif model.has_meta("flag_seen"):
		model.play("uuntap")
	model.set_meta("flag_seen", true)

func _add_animated(model: ELModel) -> void:
	animated.append(model)
	if not animate_objects: model.speed = 0.0

func set_animate_objects(on: bool) -> void:
	animate_objects = on
	for model: ELModel in animated:
		if not is_instance_valid(model): continue
		model.speed = 1.0 if on else 0.0
		if not on and model.playing and model.has_meta("gate_opened"):
			_hold_frame(model, float(model.clip_frames() - 1))

## Whether an object draws the original ground blob shadow (view flag).
## Second game: terrain objects whose TerrObj
## ShadowType is 2. First game: additional buildings, spell shops, forts and
## mana nodes (their constructors set it; the ingredient shop does not).
static func blob_shadow(edition: String, object: Dictionary, definition: Dictionary) -> bool:
	if definition.get("unit", false): return false
	if edition == "el2": return object.get("group") == "terrain_objects" and str(definition.get("row", {}).get("ShadowType", "1")) == "2"
	if edition == "el1": return object.get("group") in ["additional_buildings", "forts", "mana_nodes"] or object.get("type") == "el1_spell_shop"
	return false

## Bushes and forest groups: besides their silhouette, a small contact blob,
## since their thin leaf cards leave only a faint silhouette. The first game's
## bushes (GreenBush07, blackbush_2) have no blob of their own and get it too.
static func _foliage_shadow(edition: String, object: Dictionary, definition: Dictionary) -> bool:
	if object.get("group") != "terrain_objects" or definition.get("unit", false): return false
	var title := str(definition.get("row", {}).get("METitle", "")).to_lower()
	if edition == "el1": return "bush" in title or "bush" in str(object.get("name", "")).to_lower()
	return edition == "el2" and (".bush" in title or ".forest" in title)

## The blob quad in the model's own frame: the footprint of its mesh bounds
## (the original's model-space rectangle) on the ground.
static func blob_local(model: ELModel, footprint := 1.0) -> Transform3D:
	var bounds := AABB()
	var first := true
	for part: MeshInstance3D in model.parts.values():
		if part.mesh == null or not part.visible: continue
		var to_model := Transform3D.IDENTITY
		var node: Node = part
		while node != model and node is Node3D:
			to_model = (node as Node3D).transform * to_model
			node = node.get_parent()
		var box := to_model * part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var centre := bounds.get_center()
	return Transform3D(Basis.from_scale(Vector3(maxf(bounds.size.x * footprint, 0.001), 1, maxf(bounds.size.z * footprint, 0.001))), Vector3(centre.x, 0, centre.z))

func _build_blobs() -> void:
	if _blob_slots.is_empty(): return
	var texture := ELCombatBlood.atlas(map.profile, "Effects/Shadow")
	if texture == null: return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = BLOB_SHADER
	material.set_shader_parameter("mask_texture", texture)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = quad
	instances.instance_count = _blob_slots.size()
	blobs = MultiMeshInstance3D.new()
	blobs.name = "BlobShadows"
	blobs.multimesh = instances
	blobs.material_override = material
	blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blobs)
	var index := 0
	for uid: int in _blob_slots:
		_blob_slots[uid]["index"] = index
		instances.set_instance_custom_data(index, Color(float(_blob_slots[uid].opacity), 0, 0, 0))
		index += 1
		_sync_blob(uid, true)

func _sync_blob(uid: int, present: bool) -> void:
	if blobs == null or not _blob_slots.has(uid) or int(_blob_slots[uid].index) < 0: return
	var slot: Dictionary = _blob_slots[uid]
	var base: Transform3D = object_models[uid].transform if object_models.has(uid) else slot.base
	var placed := base * (slot.local as Transform3D)
	# A model's basis already contains its pickup shrink. Instanced pickups
	# need the same visual scale applied to their independently batched blob.
	if _retiring_pickups.has(uid) and not object_models.has(uid):
		var shrink := 1.0 - smoothstep(0.0, PICKUP_FADE, float(_retiring_pickups[uid].elapsed))
		var shrinking := base
		shrinking.basis = shrinking.basis.scaled(Vector3.ONE * shrink)
		placed = shrinking * (slot.local as Transform3D)
	if not map.relief.is_empty():
		var ground := Vector2(placed.origin.x, -placed.origin.z) / ELAdventureTerrain.CELL
		placed.origin.y = map.surface_height(ground)
		placed.basis = Basis(Quaternion(Vector3.UP, map.surface_normal(ground, ELAdventureTerrain.CELL))) * placed.basis
	placed.origin.y += BLOB_LIFT
	slot["placed"] = placed
	slot["present"] = present
	blobs.multimesh.set_instance_transform(slot.index, placed if present else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

## The shadows setting hides or shows all ground blobs and the silhouette
## shadows.
func set_blob_shadows(on: bool) -> void:
	if blobs != null: blobs.visible = on
	var silhouettes := on and map != null and map.profile.id in ["el1", "el2"]
	if sun != null:
		# Preserve tracing's ownership when Options reapplies map settings.
		# Its deactivation restores this updated preference from the metadata.
		if sun.has_meta("traced_shadow"):
			sun.set_meta("traced_shadow", silhouettes)
			sun.shadow_enabled = false
		else:
			sun.shadow_enabled = silhouettes
		# Only the compatibility renderer's encoded sun pass needs the lower energy.
		var encoded := silhouettes and ELEffectLook.encoded_sun_pass(environment)
		sun.light_energy = SHADOW_SUN_ENERGY if encoded else SUN_ENERGY
	var material := _terrain_material()
	if material != null:
		material.set_shader_parameter("shadow_strength", SILHOUETTE_STRENGTH if silhouettes else 0.0)
		# EL1 rotates the map sun with its camera convention. Relief and water
		# highlights must follow it instead of retaining EL2's default vector.
		if sun != null: material.set_shader_parameter("detail_sun", sun.basis.z.normalized())

## Whether an object casts the original's silhouette shadow on the ground
## (recorded footage of both games shows them under trees, rocks and
## buildings). Bushes and grouped forests cast shadows beyond the canopy.
## The original draws the silhouette on the ground only, so nothing else
## receives it.
static func silhouette(edition: String, object: Dictionary, definition: Dictionary) -> bool:
	return edition in ["el1", "el2"] and (not blob_shadow(edition, object, definition) or _foliage_shadow(edition, object, definition))

func _shade(node: GeometryInstance3D, casts: bool) -> void:
	var material := node.material_override as BaseMaterial3D
	var wave := material != null and material.has_meta("water_surface")
	if not wave: node.layers |= ELAdventureTerrain.REFLECTION_LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts and not wave else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material != null: material.disable_receive_shadows = true

## World-space bounds of an object's drawn figure (its model parts or
## instanced pieces), or an empty box when it has none.
func object_bounds(uid: int) -> AABB:
	var bounds := AABB()
	var first := true
	if object_models.has(uid):
		var model: ELModel = object_models[uid]
		for part: MeshInstance3D in model.parts.values():
			if part.mesh == null or not part.visible: continue
			var box := global_transform.affine_inverse() * part.global_transform * part.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		return bounds
	for entry: Dictionary in _instances.get(uid, []):
		var box: AABB = entry.transform * entry.node.multimesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

## Highest point of an object's drawn figure (world units above the ground),
## or -1 when the object has no figure.
func object_top(uid: int) -> float:
	var top := -1.0
	if object_models.has(uid):
		var model: ELModel = object_models[uid]
		for part: MeshInstance3D in model.parts.values():
			if part.mesh == null or not part.visible: continue
			var box := part.global_transform * part.mesh.get_aabb()
			top = maxf(top, box.end.y - model.global_position.y)
		return top
	for entry: Dictionary in _instances.get(uid, []):
		var box: AABB = entry.transform * entry.node.multimesh.mesh.get_aabb()
		top = maxf(top, box.end.y)
	return top
