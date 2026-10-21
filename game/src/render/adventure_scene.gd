class_name ELAdventureScene
extends Node3D
## Original adventure figures with chunked static instancing. Simulation and
## camera controls are separate from these visual resources.
var map: ELAdventureMap
var terrain: ELAdventureTerrain
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
## First-game fog of war (ELFog) as the local player sees it.
const FOG_DIM := 0.3
var fog_session: ELAdventureSession
var fog_player := 0
var _fog_revision := -1
var _fog_textures: Array[ImageTexture] = []
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
var mist: ELFogMist
var _fog_apron: MeshInstance3D
## Options "fog animations": false keeps the mist's first frame.
var animate_fog := true
var _look_materials: Dictionary = {}
var _grey_textures: Dictionary = {}
## Instanced object groups that share one colourless cell value.
var _grey_groups: Array[Dictionary] = []
## Ground blob shadows (Effects/Shadow): one batched quad per object whose
## class draws one, keyed by uid ({index, local, base}).
var blobs: MultiMeshInstance3D
var _blob_slots: Dictionary = {}
const BLOB_ALPHA := 128.0 / 255.0
const BLOB_LIFT := 0.01
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
	_art = ELAdventureArt.new(map)
	var prototypes := {}
	var groups := {}
	var objects: Array = session.objects.values() if session != null else map.objects
	var fogged := session != null and ELFog.active(session, session.current_player)
	# Instances are grouped by their colourless cell value so a level switch
	# can grey whole groups.
	var zoned := session != null and map.profile.id == "el2" and map.colorless.size() == map.width * map.height
	for index in objects.size():
		var object: Dictionary = objects[index]
		var uid := int(object.get("uid", int(object.permanent_id) - 1))
		var definition := _art.resolve(object)
		if definition.get("hidden", false): continue
		if not object.get("visible", true): continue
		if definition.is_empty():
			errors.append("Missing art: %s / %s" % [object.group, object.name])
			continue
		var key := "%s/%s/%s" % [definition.model, definition.texture, definition.secondary]
		if not prototypes.has(key):
			var prototype := ELModel.new()
			add_child(prototype)
			if not prototype.build(map.profile, definition.model, definition.texture, definition.secondary):
				errors.append(prototype.error)
				prototype.queue_free()
				continue
			prototype.hide()
			prototype.set_process(false)
			prototypes[key] = prototype
		var prototype: ELModel = prototypes[key]
		var rotation := int(object.rotation)
		var mirror := Vector3(-1 if rotation & 1 else 1, 1, -1 if rotation & 2 else 1)
		var center := ELAdventureGrid.center(object, definition.row)
		var position := Vector3(center.x * ELAdventureTerrain.CELL, 0, -center.y * ELAdventureTerrain.CELL)
		var transform := Transform3D(Basis(Vector3.UP, -float((rotation >> 2) & 3) * PI / 2.0) * Basis.from_scale(mirror * float(definition.scale)), position)
		if blob_shadow(map.profile.id, object, definition): _blob_slots[uid] = {"index": -1, "local": blob_local(prototype), "base": transform}
		var casts := silhouette(map.profile.id, object, definition)
		if definition.unit or prototype.clip_frames() > 1 or first_barrier(object):
			var model := ELModel.new()
			add_child(model)
			if not model.build(map.profile, definition.model, definition.texture, definition.secondary):
				errors.append(model.error)
				model.queue_free()
				continue
			model.transform = transform
			model.set_meta("map_object", index)
			model.set_meta("art_key", key)
			if not object.get("alive", true): _corpse_pose(model)
			if first_barrier(object): barrier_pose(model, bool(object.get("opened", false)), false)
			# A garrison hero is inside its fort; its own figure is not drawn.
			if object.get("fortified", false): model.hide()
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
	sun = DirectionalLight3D.new()
	add_child(sun)
	sun.light_energy = SUN_ENERGY
	sun.rotation_degrees = SUN_ROTATION
	# Silhouette shadows: only the ground receives them (see `silhouette`).
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	set_blob_shadows(true)
	enable_fog(session)
	enable_colorless(session)
	build_usec = Time.get_ticks_usec() - started
	return errors.is_empty()

## Turns the terrain and object fog on for the session's local player, or off
## (Etherlords II, the neutral player, or a scene without a session).
func enable_fog(session: ELAdventureSession) -> void:
	var material := map.profile.adventure_terrain_cache.get("material") as ShaderMaterial if map.profile.adventure_terrain_cache.get("map") == map.id else null
	fog_session = session if session != null and ELFog.active(session, session.current_player) else null
	_fog_revision = -1
	if material != null: material.set_shader_parameter("fog_enabled", fog_session != null)
	if _fog_apron != null: _fog_apron.visible = fog_session != null
	if fog_session == null: return
	fog_player = session.current_player
	if mist == null:
		mist = ELFogMist.new()
		mist.animate = animate_fog
		add_child(mist)
	if _fog_apron == null: _fog_apron = _make_fog_apron()
	_fog_apron.visible = true
	fog_to = fog_corners()
	fog_from = fog_to
	fog_since = INF
	_fog_textures.clear()
	for data: PackedByteArray in [fog_from, fog_to]:
		_fog_textures.append(ImageTexture.create_from_image(Image.create_from_data(map.width + 1, map.height + 1, false, Image.FORMAT_R8, data)))
	if material != null:
		material.set_shader_parameter("fog_from", _fog_textures[0])
		material.set_shader_parameter("fog_to", _fog_textures[1])
		material.set_shader_parameter("fog_size", Vector2i(map.width, map.height))
		material.set_shader_parameter("fog_fade", 1.0)
		material.set_shader_parameter("fog_mist", mist.get_texture())
	_fog_revision = ELFog.revision(fog_session)
	for item: Dictionary in fog_session.objects.values(): fog_object(item)
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
func fog_corners() -> PackedByteArray:
	var data := _fog_data()
	var known: PackedByteArray = data[0]
	var seen: PackedByteArray = data[1]
	var bit := 1 << fog_player
	var tiles := PackedByteArray()
	tiles.resize(map.width * map.height)
	for i in tiles.size():
		tiles[i] = 0 if seen[i] & bit else (FOG_REMEMBERED if known[i] & bit else FOG_UNEXPLORED)
	var columns := map.width + 1
	var corners := PackedByteArray()
	corners.resize(columns * (map.height + 1))
	for y in map.height + 1:
		for x in columns:
			var level := 0
			if x == 0 or y == 0 or x == map.width or y == map.height: level = FOG_UNEXPLORED
			else:
				var at := y * map.width + x
				level = maxi(maxi(tiles[at], tiles[at - 1]), maxi(tiles[at - map.width], tiles[at - map.width - 1]))
			corners[y * columns + x] = level
	return corners

## The corner opacities shown now, part way from `fog_from` to `fog_to`.
func fog_shown() -> PackedByteArray:
	var step := FOG_RATE * fog_since
	if step >= 255.0: return fog_to
	var shown := fog_from.duplicate()
	var limit := int(step)
	for i in shown.size():
		shown[i] = fog_from[i] + clampi(fog_to[i] - fog_from[i], -limit, limit)
	return shown

func set_animate_fog(on: bool) -> void:
	animate_fog = on
	if mist != null: mist.animate = on

func _sync_mist() -> void:
	var material := map.profile.adventure_terrain_cache.get("material") as ShaderMaterial if map.profile.adventure_terrain_cache.get("map") == map.id else null
	if material != null:
		material.set_shader_parameter("fog_drift", mist.drift)
		material.set_shader_parameter("fog_fade", minf(FOG_RATE * fog_since / 255.0, 1.0))
	if _fog_apron != null: (_fog_apron.material_override as ShaderMaterial).set_shader_parameter("fog_drift", mist.drift)

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
	if fog_session != null:
		fog_since += delta
		sync_fog()
		_sync_mist()
	if colorless_session != null and colorless_session.colorless_level != colorless_shown: sync_colorless()

## Colourless zones: terrain corners touching a colourless cell are grey and
## mixed cells blend along the terrain's transition masks (and the
## tile composer); grey is (R+G+B)/3 of the 8-bit colour
## . Map objects whose footprint
## centre is colourless use greyscale copies of their textures.
## Everything is rebuilt on a level switch only.
func enable_colorless(session: ELAdventureSession) -> void:
	var material := map.profile.adventure_terrain_cache.get("material") as ShaderMaterial if map.profile.adventure_terrain_cache.get("map") == map.id else null
	colorless_session = session if session != null and map.profile.id == "el2" and map.colorless.size() == map.width * map.height else null
	colorless_shown = -1
	if material != null: material.set_shader_parameter("clrless_enabled", false)
	if colorless_session == null: return
	sync_colorless()

func sync_colorless() -> void:
	var material := map.profile.adventure_terrain_cache.get("material") as ShaderMaterial if map.profile.adventure_terrain_cache.get("map") == map.id else null
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
		node.material_override = _look_material(entry.material, false, ((int(entry.bits) >> colorless_shown) & 1) == 1)
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
	fog_from = fog_shown()
	fog_to = fog_corners()
	fog_since = 0.0
	_fog_textures[0].update(Image.create_from_data(map.width + 1, map.height + 1, false, Image.FORMAT_R8, fog_from))
	_fog_textures[1].update(Image.create_from_data(map.width + 1, map.height + 1, false, Image.FORMAT_R8, fog_to))
	for item: Dictionary in fog_session.objects.values(): fog_object(item)

## Unexplored objects and remembered heroes, monsters, castles and forts are
## hidden; other remembered objects are dimmed. A moving actor also counts the
## tile it is passing through.
func fog_object(item: Dictionary, passing := Vector2i(-1, -1)) -> void:
	if fog_session == null or item.is_empty(): return
	var uid := int(item.uid)
	if not object_models.has(uid) and not _instances.has(uid): return
	var mode := ELFog.object_state(fog_session, fog_player, item)
	if passing.x >= 0 and mode != ELFog.VISIBLE: mode = maxi(mode, ELFog.object_state(fog_session, fog_player, item, passing))
	var present := _game_visible(item) and (mode == ELFog.VISIBLE or (mode == ELFog.REMEMBERED and not ELFog.dynamic(item)))
	var dim := mode != ELFog.VISIBLE
	if object_models.has(uid):
		var model: ELModel = object_models[uid]
		model.visible = present
		_dim_model(model, present and dim)
	for entry: Dictionary in _instances.get(uid, []):
		var multimesh: MultiMesh = entry.node.multimesh
		multimesh.set_instance_transform(entry.index, entry.transform if present else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		if multimesh.use_colors: multimesh.set_instance_color(entry.index, Color(FOG_DIM, FOG_DIM, FOG_DIM) if dim else Color.WHITE)
	_sync_blob(uid, present)

func _game_visible(item: Dictionary) -> bool:
	return item.get("visible", true) and item.get("placed", true) and not item.get("fortified", false) and (not item.get("opened", false) or first_barrier(item))

func _dim_model(model: ELModel, dim: bool) -> void:
	if model.get_meta("look_dim", false) == dim: return
	model.set_meta("look_dim", dim)
	_model_look(model)

## Applies a figure's fog dimming and colourless grey together; each part keeps
## its own material while neither applies.
func _model_look(model: ELModel) -> void:
	var dim: bool = model.get_meta("look_dim", false)
	var grey: bool = model.get_meta("look_grey", false)
	for node: MeshInstance3D in model.parts.values():
		if not node.has_meta("look_base"):
			if (not dim and not grey) or not node.material_override is StandardMaterial3D: continue
			node.set_meta("look_base", node.material_override)
		var base: StandardMaterial3D = node.get_meta("look_base")
		node.material_override = _look_material(base, dim, grey)
		if not dim and not grey: node.remove_meta("look_base")

func _look_material(base: Material, dim: bool, grey: bool) -> Material:
	var lit := base as StandardMaterial3D
	if lit == null or (not dim and not grey): return base
	var key := [lit, dim, grey]
	if not _look_materials.has(key):
		var copy: StandardMaterial3D = lit.duplicate()
		if dim: copy.albedo_color = Color(lit.albedo_color.r * FOG_DIM, lit.albedo_color.g * FOG_DIM, lit.albedo_color.b * FOG_DIM, lit.albedo_color.a)
		if grey and lit.albedo_texture != null: copy.albedo_texture = _grey_texture(lit.albedo_texture)
		_look_materials[key] = copy
	return _look_materials[key]

## A greyscale copy of a texture, made once per texture (ELColorless.grey_image).
func _grey_texture(texture: Texture2D) -> Texture2D:
	if _grey_textures.has(texture): return _grey_textures[texture]
	var image := texture.get_image()
	if image == null: return texture
	var mipmaps := image.has_mipmaps()
	var grey := ELColorless.grey_image(image)
	if mipmaps: grey.generate_mipmaps()
	_grey_textures[texture] = ImageTexture.create_from_image(grey)
	return _grey_textures[texture]

func update_object(item: Dictionary) -> void:
	if item.is_empty(): return
	var uid: int = item.uid
	# An opened second-game gate has moved out of the way; a first-game
	# runestone keeps its gate (barrier_pose).
	var visible := _game_visible(item)
	if not visible:
		if object_models.has(uid): object_models[uid].hide()
		for entry: Dictionary in _instances.get(uid, []): entry.node.multimesh.set_instance_transform(entry.index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_sync_blob(uid, false)
		return
	var definition := _art.resolve(item)
	if definition.is_empty() or definition.get("hidden", false): return
	var key := "%s/%s/%s" % [definition.model, definition.texture, definition.secondary]
	var unit: bool = item.type in ["hero", "monster", "corpse"]
	if (unit or item.type in ["rune_shop", "el1_spell_shop", "resource_mine", "mana_node", "fort"] or ELFirstScenario.is_castle(item)) and (_object_keys.get(uid, "") != key or (unit and not object_models.has(uid))):
		var model := ELModel.new()
		add_child(model)
		if not model.build(map.profile, definition.model, definition.texture, definition.secondary):
			errors.append(model.error)
			model.queue_free()
			return
		if object_models.has(uid):
			animated.erase(object_models[uid])
			object_models[uid].queue_free()
		for entry: Dictionary in _instances.get(uid, []): entry.node.multimesh.set_instance_transform(entry.index, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_instances.erase(uid)
		model.scale = Vector3.ONE * float(definition.scale)
		if not unit:
			var rotation := int(item.rotation)
			var mirror := Vector3(-1 if rotation & 1 else 1, 1, -1 if rotation & 2 else 1)
			model.basis = Basis(Vector3.UP, -float((rotation >> 2) & 3) * PI / 2.0) * Basis.from_scale(mirror * float(definition.scale))
		model.set_meta("art_key", key)
		var casts := silhouette(map.profile.id, item, definition)
		for part: MeshInstance3D in model.parts.values(): _shade(part, casts)
		if _blob_slots.has(uid): _blob_slots[uid]["local"] = blob_local(model)
		object_models[uid] = model
		_object_keys[uid] = key
		if unit:
			actors[uid] = model
			units[int(item.source_index)] = model
		else: _add_animated(model)
	if object_models.has(uid):
		var model: ELModel = object_models[uid]
		model.visible = visible
		var center := ELAdventureGrid.center(item, definition.row)
		model.position = Vector3(center.x * ELAdventureTerrain.CELL, 0, -center.y * ELAdventureTerrain.CELL)
		if not item.get("alive", true): _corpse_pose(model)
		if first_barrier(item): barrier_pose(model, bool(item.get("opened", false)), true)
		grey_object(uid)
		_sync_blob(uid, visible)
		return
	for entry: Dictionary in _instances.get(uid, []):
		entry.node.multimesh.set_instance_transform(entry.index, entry.transform if visible else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_sync_blob(uid, visible)

## A first-game runestone barrier (Runestone1/2), drawn as its own figure.
func first_barrier(item: Dictionary) -> bool:
	return map.profile.id == "el1" and item.get("group") == "additional_buildings" and item.get("name") in ["Runestone1", "Runestone2"]

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
	if model.play("udeath"):
		model.frame = float(model.clip_frames() - 1)
		model.apply_frame(model.frame)
		model.playing = false
		model.set_process(false)

func move_actor(uid: int, position: Vector2, moving: bool) -> void:
	if not actors.has(uid): return
	var model: ELModel = actors[uid]
	var next := world_position(position.x, position.y)
	var delta := next - model.position
	if delta.length_squared() > 0.00001:
		model.rotation.y = atan2(delta.x, delta.z)
	model.position = next
	var clip := "cmove" if moving else "cidle"
	if model.base_clip() != clip: model.play(clip)
	# Movement through fog stays hidden; an actor appears as it steps into view.
	if fog_session != null: fog_object(fog_session.object(uid), Vector2i(roundi(position.x), roundi(position.y)))
	grey_object(uid, Vector2i(roundi(position.x), roundi(position.y)))

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

func _add_animated(model: ELModel) -> void:
	animated.append(model)
	if not animate_objects: model.speed = 0.0

func set_animate_objects(on: bool) -> void:
	animate_objects = on
	for model: ELModel in animated:
		if is_instance_valid(model): model.speed = 1.0 if on else 0.0

## Whether an object draws the original ground blob shadow (view flag)
## instead of a silhouette. Second game: terrain objects whose TerrObj
## ShadowType is 2. First game: additional buildings, spell shops, forts and
## mana nodes (their constructors set it; the ingredient shop does not).
static func blob_shadow(edition: String, object: Dictionary, definition: Dictionary) -> bool:
	if definition.get("unit", false): return false
	if edition == "el2": return object.get("group") == "terrain_objects" and str(definition.get("row", {}).get("ShadowType", "1")) == "2"
	if edition == "el1": return object.get("group") in ["additional_buildings", "forts", "mana_nodes"] or object.get("type") == "el1_spell_shop"
	return false

## The blob quad in the model's own frame: the footprint of its mesh bounds
## (the original's model-space rectangle) on the ground.
static func blob_local(model: ELModel) -> Transform3D:
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
	return Transform3D(Basis.from_scale(Vector3(maxf(bounds.size.x, 0.001), 1, maxf(bounds.size.z, 0.001))), Vector3(centre.x, 0, centre.z))

func _build_blobs() -> void:
	if _blob_slots.is_empty(): return
	var texture := ELCombatBlood.atlas(map.profile, "Effects/Shadow")
	if texture == null: return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.albedo_color = Color(1, 1, 1, BLOB_ALPHA)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
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
		index += 1
		_sync_blob(uid, true)

func _sync_blob(uid: int, present: bool) -> void:
	if blobs == null or not _blob_slots.has(uid) or int(_blob_slots[uid].index) < 0: return
	var slot: Dictionary = _blob_slots[uid]
	var base: Transform3D = object_models[uid].transform if object_models.has(uid) else slot.base
	var placed := base * (slot.local as Transform3D)
	placed.origin.y += BLOB_LIFT
	slot["placed"] = placed
	slot["present"] = present
	blobs.multimesh.set_instance_transform(slot.index, placed if present else Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))

## The shadows setting hides or shows all ground blobs and, in the second
## game, the silhouette shadows.
func set_blob_shadows(on: bool) -> void:
	if blobs != null: blobs.visible = on
	var silhouettes := on and map != null and map.profile.id == "el2"
	if sun != null:
		sun.shadow_enabled = silhouettes
		sun.light_energy = SHADOW_SUN_ENERGY if silhouettes else SUN_ENERGY
	var material := map.profile.adventure_terrain_cache.get("material") as ShaderMaterial if map != null and map.profile.adventure_terrain_cache.get("map") == map.id else null
	if material != null: material.set_shader_parameter("shadow_strength", SILHOUETTE_STRENGTH if silhouettes else 0.0)

## Whether an object casts the original's silhouette shadow on the ground
## (second game; recorded original footage shows them): every object that
## does not draw a blob, including the volcanoes and rocks of ShadowType 0.
## The original draws the silhouette on the ground only, so nothing else
## receives it.
static func silhouette(edition: String, object: Dictionary, definition: Dictionary) -> bool:
	return edition == "el2" and not blob_shadow(edition, object, definition)

func _shade(node: GeometryInstance3D, casts: bool) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := node.material_override as BaseMaterial3D
	if material != null: material.disable_receive_shadows = true

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
