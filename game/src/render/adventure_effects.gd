class_name ELAdventureEffects
extends Node3D
## Second game: particle effects from adventure scripts and shrines, each one
## MultiMesh of camera-facing quads from a baked .pfx animation
## (ELParticleFile), redrawn when its 30 fps frame changes. Two kinds:
## - ambience: terrain particles (terrainpfx: rain, snow, ash, sand storms,
##   damp, dots of light) a script starts directly: the library weather and a
##   chapter's own scenery. Optional: the "weather" preference hides them.
## - story effects: every other particle file (combat domes, lightning,
##   teleports, global spells, vortices) and anything a cutscene starts through
##   the command queue. Always drawn.
## Effects are presentation only; the script state does not depend on them.
## Effects only sit where they were started; a script may turn one to an
## object's facing (OrientEffectByObject).
const CACHE_LIMIT := 6
const RAIN_FILES := ["terrainpfx/rain.pfx", "terrainpfx/rainnocycle.pfx"]
## Second game: every additional building whose AdditionalBuildings row names
## an Effect runs it from the moment the building is made, whoever owns it
## and whether or not it was visited (sacred places, battleground altars,
## the White Lord's portals). Only the Specialization shrine lets it go once
## used.
static func building_effect(profile: ELProfile, item: Dictionary) -> String:
	if item.get("group") != "additional_buildings": return ""
	return str(ELSecondBuildings.definition(profile, item).get("Effect", "")).strip_edges()
## Second game: the looping effect a terrain object's (or mana node's) table
## SpecEffect kind starts with its figure, at the figure's place and turned
## with it (pfx file names, from the game's own kind list):
## - 1, 2, 7: the red, black and blue mana nodes;
## - 3-6: the Red and Black volcanoes' smoke (Voulcan2x2_1-4, as in the first
##   game);
## - 100-106, 110: lighthouses by colour, the dock, the boat (Ship_01), the
##   teleport and the plain bridge;
## - 111-118: the magic bridges' piers and abutments, by colour;
## - 119 and 123: the springs' water (Spring_01 SpringMind, Spring_02
##   SpringStrength);
## - 120-122: the dungeon caves' glow (DungeonLvl1-3);
## - 124: the altar of war;
## - 125: the volcano ashes' drifting cloud (TerrainPFX ConvulsionOfNature).
## Only 3-6, 105 and 111-125 have TerrObj rows; the rest are kept for maps
## of one's own that might use them.
const SPEC_EFFECTS := {1: "ManaNodeRed", 2: "ManaNodeBlack", 7: "BlueManaNode",
	3: "Voulcan2x2_1", 4: "Voulcan2x2_2", 5: "Voulcan2x2_3", 6: "Voulcan2x2_4",
	100: "BlueLightHouse", 101: "GreenLightHouse", 102: "RedLightHouse", 103: "BlackLightHouse",
	104: "Dock", 105: "Boat", 106: "Teleport", 110: "Bridge",
	111: "GreenBridgePier", 112: "GreenBridgeAbutment", 113: "BlackBridgePier", 114: "BlackBridgeAbutment",
	115: "RedBridgePier", 116: "RedBridgeAbutment", 117: "BlueBridgePier", 118: "BlueBridgeAbutment",
	119: "SpringMind", 120: "DungeonLvl1", 121: "DungeonLvl2", 122: "DungeonLvl3", 123: "SpringStrength",
	124: "AltarOfWar", 125: "TerrainPFX/ConvulsionOfNature"}
## The object groups whose table rows carry a SpecEffect kind.
const SPEC_TABLES := {"terrain_objects": "TerrObj", "mana_nodes": "ManaNodes"}
## Object effects (SpecEffect) are drawn only while their reach is in the
## camera's view, checked this often (seconds); a big map has scores of
## volcanoes, springs and ash clouds.
const CULL_STEP := 0.2
## Room (units) added round an effect's own reach before it counts as out
## of view.
const CULL_MARGIN := 6.0

## Second game: the table row and SpecEffect file ("" for none) of a map
## object.
static func spec_effect(profile: ELProfile, item: Dictionary) -> String:
	var row := spec_row(profile, item)
	var kind := int(row.get("SpecEffect", 0))
	return str(SPEC_EFFECTS[kind]) + ".pfx" if SPEC_EFFECTS.has(kind) else ""

static func spec_row(profile: ELProfile, item: Dictionary) -> Dictionary:
	var table := str(SPEC_TABLES.get(str(item.get("group", "")), ""))
	return profile.table(table).get(str(item.get("name", "")), {}) if not table.is_empty() else {}
## Second game: an occupied fort's guard zone is ringed by twelve looping
## pieces, Intercept5x5_NN.pfx, one on each zone cell two cells from the
## fort that is not a corner of the 5 x 5 square (only zones of a fort
## garrison mark their cells for it). Rows run north to south from the
## garrison's row + 2; -1 is no piece.
const RING_PIECES := [-1, 11, 0, 1, -1, 10, -1, -1, -1, 2, 9, -1, -1, -1, 3, 8, -1, -1, -1, 4, -1, 7, 6, 5, -1]

signal rain_changed(areas: PackedVector4Array)

static var _files: Dictionary = {}
static var _order: Array[String] = []
## The two particle shaders (blended, additive) every sprite sheet shares.
static var _shaders: Dictionary = {}
## Brightness of glowing (additive) particles (see ELCombatEffects.glow_level)
## and the additive materials that take it.
static var glow_level := 1.0
static var _glowing: Array = []
## Files decoded ahead of use (keep_file), never evicted.
static var _kept: Dictionary = {}

var profile: ELProfile
var enabled := true
## Parent of the optional ambience effects; hidden by the preference.
var weather_layer: Node3D
## Effect name -> {entry, file, node, elapsed, frame, optional}.
var effects: Dictionary = {}
## Scripted point lights by name (ExStartLight).
var lights: Dictionary = {}
var _materials: Dictionary = {}
var _rain_on_water := false
var _shrine_session: ELAdventureSession
var _shrines: Dictionary = {}
var _shrine_fog_revision := -1
## Terrain objects with a SpecEffect (uid -> {item, row, file}).
var _spec_objects: Dictionary = {}
var _cull_clock := 0.0
## Effect names of the garrisons shown now; rebuilt after fort changes.
var _garrisons: Dictionary = {}
var _garrisons_dirty := false

func build(data: ELProfile, settings: ELSettings, state: ELAdventureSession) -> void:
	profile = data
	weather_layer = Node3D.new()
	add_child(weather_layer)
	_rain_on_water = settings != null and bool(settings.values.get("enhanced_water", false))
	set_enabled(bool(settings.values.get("weather", true)) if settings != null else true)
	# A restored map recreates every running effect from its first frame.
	for name: String in state.ambience.get("effects", {}):
		start(name, state.ambience.effects[name], 0.0)
	for name: String in state.ambience.get("lights", {}):
		_light(name, state.ambience.lights[name])
	if data.id == "el2":
		_shrine_session = state
		for item: Dictionary in state.objects.values():
			if not building_effect(data, item).is_empty():
				_shrines[int(item.uid)] = item
			else:
				var file := spec_effect(data, item)
				if not file.is_empty(): _spec_objects[int(item.uid)] = {"item": item, "row": spec_row(data, item), "file": file}
		_garrisons_dirty = true
		_sync_shrines()

func set_enabled(value: bool) -> void:
	enabled = value
	weather_layer.visible = value
	for name: String in effects: effects[name].frame = -1
	_publish_rain()

func set_water_ripples(value: bool) -> void:
	if _rain_on_water == value: return
	_rain_on_water = value
	_publish_rain()

## Ambience the weather preference may hide (see the class description).
static func optional(entry: Dictionary) -> bool:
	return ELSecondAmbience.is_terrain_effect(str(entry.get("file", ""))) and not bool(entry.get("story", false))

## Applies scripted particles and changes to placed shrine effects.
func script_event(data: Dictionary) -> void:
	# The shrine use changes its saved used flag before notifying the map.
	# A building a script makes (a portal swapped in) starts its effect too.
	if data.kind == "object_created" and _shrine_session != null and not _shrines.has(int(data.get("id", -1))):
		var made := _shrine_session.object(int(data.get("id", -1)))
		if not made.is_empty() and not building_effect(profile, made).is_empty(): _shrines[int(made.uid)] = made
		elif not made.is_empty() and not _spec_objects.has(int(made.uid)) and not spec_effect(profile, made).is_empty():
			_spec_objects[int(made.uid)] = {"item": made, "row": spec_row(profile, made), "file": spec_effect(profile, made)}
	if data.kind in ["object_changed", "object_killed", "object_created"] and _shrines.has(int(data.get("id", -1))):
		_sync_shrine(_shrines[int(data.id)])
	if data.kind in ["object_changed", "object_killed", "object_created"] and _spec_objects.has(int(data.get("id", -1))):
		_sync_spec(int(data.id))
	if _shrine_session != null and data.kind in ["fort_entered", "fort_left", "fort_captured", "object_changed", "object_killed", "object_created"]:
		_garrisons_dirty = true
	if data.kind == "script_effect":
		finish(str(data.name))
		if not data.entry.is_empty(): start(str(data.name), data.entry, 0.0)
	if data.kind == "script_light": _light(str(data.name), data.entry)

## Places, moves or (with an empty entry) removes a scripted light.
func _light(name: String, entry: Dictionary) -> void:
	var node: OmniLight3D = lights.get(name)
	if entry.is_empty():
		if node != null: node.queue_free()
		lights.erase(name)
		return
	if node == null:
		node = OmniLight3D.new()
		node.shadow_enabled = false
		add_child(node)
		lights[name] = node
	# Script coordinates: x east, y north, z up, two units per cell.
	node.position = Vector3(float(entry.x), float(entry.z), -float(entry.y))
	node.omni_range = float(entry.radius)
	node.light_color = Color.html(str(entry.color))

func _sync_shrines() -> void:
	_shrine_fog_revision = ELFog.revision(_shrine_session)
	for item: Dictionary in _shrines.values(): _sync_shrine(item)
	for uid: int in _spec_objects: _sync_spec(uid)
	_sync_garrisons()

## A terrain object's SpecEffect runs wherever the figure is drawn for the
## local player, in sight or in explored fog (a destroyed bridge, hidden by
## its script, has none). Building effects follow the same rule. It is part
## of the object, not weather: the weather preference keeps it (the ash
## cloud's file sits among the terrain effects).
func _sync_spec(uid: int) -> void:
	var entry: Dictionary = _spec_objects[uid]
	var item: Dictionary = entry.item
	var name := "spec:%d" % uid
	if not item.get("alive", true) or not item.get("visible", true) or not item.get("placed", true) or not ELFog.shown(_shrine_session, 1, item):
		finish(name)
		return
	if effects.has(name): return
	var center := ELAdventureGrid.center(item, entry.row) * ELAdventureTerrain.CELL
	keep_file(profile, entry.file)
	start(name, {"file": entry.file, "x": center.x, "y": center.y, "z": 0.0, "story": true}, 0.0)
	if not effects.has(name): return
	orient(name, -float((int(item.get("rotation", 0)) >> 2) & 3) * PI / 2.0)
	var effect: Dictionary = effects[name]
	var reach := _reach(effect.file)
	effect.cull = Vector4(reach.position.x, reach.position.y, reach.position.z, reach.size.length() * 0.5 + CULL_MARGIN)
	_cull(effect, get_viewport().get_camera_3d() if is_inside_tree() else null)

## The box (effect space: x east, y up, z south) the particles of a file
## ever reach.
static func _reach(file: ELParticleFile) -> AABB:
	if file.has_meta(&"map_reach"): return file.get_meta(&"map_reach")
	var low := Vector3(INF, INF, INF)
	var high := -low
	for i in file.alpha.size():
		var point := Vector3(file.positions[i * 3], file.positions[i * 3 + 2], -file.positions[i * 3 + 1])
		low = low.min(point)
		high = high.max(point)
	var box := AABB(low, high - low) if low.is_finite() and high.is_finite() else AABB()
	file.set_meta(&"map_reach", box)
	return box

## Hides an object effect whose reach (its "cull" sphere: centre in effect
## space, radius) is out of the camera's view, and shows it again when it
## comes in; a hidden one keeps its clock but is not redrawn.
func _cull(effect: Dictionary, camera: Camera3D) -> void:
	var sphere: Vector4 = effect.cull
	var node: MultiMeshInstance3D = effect.node
	var inside := true
	if camera != null:
		var center := (node.global_transform if node.is_inside_tree() else node.transform) * Vector3(sphere.x, sphere.y, sphere.z)
		for plane: Plane in camera.get_frustum():
			if plane.distance_to(center) > sphere.w:
				inside = false
				break
	if inside == node.visible: return
	node.visible = inside
	if inside: effect.frame = -1

func _cull_all() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	for effect: Dictionary in effects.values():
		if effect.has("cull"): _cull(effect, camera)

## The guard-zone ring of every occupied fort in sight (RING_PIECES), each
## piece at its cell's centre on the ground.
func _sync_garrisons() -> void:
	_garrisons_dirty = false
	var wanted := {}
	var map := _shrine_session.map
	for fort: Dictionary in _shrine_session.objects.values():
		if fort.get("type") != "fort" or not fort.get("alive", true) or not fort.get("placed", true): continue
		var garrison := _shrine_session.object(int(fort.get("garrison", -1)))
		if garrison.is_empty() or not garrison.get("alive", false) or not garrison.get("fortified", false): continue
		if ELFog.object_state(_shrine_session, 1, fort) != ELFog.VISIBLE: continue
		var origin := Vector2i(int(fort.x), int(fort.y))
		for index in RING_PIECES.size():
			var piece: int = RING_PIECES[index]
			if piece < 0: continue
			var cell := origin + Vector2i(index % 5 - 2, 2 - index / 5)
			if cell.x < 0 or cell.y < 0 or cell.x >= map.width or cell.y >= map.height: continue
			var name := "ring:%d:%d" % [int(fort.uid), piece]
			wanted[name] = true
			if effects.has(name): continue
			var at := ELAdventureScene.world_position(float(cell.x), float(cell.y))
			keep_file(profile, "Intercept5x5_%02d.pfx" % piece)
			start(name, {"file": "Intercept5x5_%02d.pfx" % piece, "x": at.x, "y": -at.z, "z": 0.0, "story": true}, 0.0)
	for name: String in _garrisons:
		if not wanted.has(name): finish(name)
	_garrisons = wanted

func _sync_shrine(item: Dictionary) -> void:
	var name := "shrine:%d" % int(item.uid)
	if (item.get("used", false) and item.get("name") == ELSecondBuildings.SHRINE) or not item.get("alive", true) or not item.get("visible", true) or not item.get("placed", true) or not ELFog.shown(_shrine_session, 1, item):
		finish(name)
		return
	var row := ELSecondBuildings.definition(profile, item)
	var file := str(row.get("Effect", ""))
	if file.is_empty(): return
	var center := ELAdventureGrid.center(item, row) * ELAdventureTerrain.CELL
	if effects.has(name):
		effects[name].node.position = Vector3(center.x, 0.0, -center.y)
	else:
		start(name, {"file": file, "x": center.x, "y": center.y, "z": 0.0, "story": true}, 0.0)
	orient(name, -float((int(item.rotation) >> 2) & 3) * PI / 2.0)

## Turns a running effect about the vertical axis (the object's facing).
func orient(name: String, yaw: float) -> void:
	if effects.has(name): effects[name].node.rotation.y = yaw

## `source`: the edition whose files hold the effect, when it is not this map's
## own (the first game's battle dome borrows the second game's).
func start(name: String, entry: Dictionary, elapsed: float, draw_current := false, source: ELProfile = null) -> void:
	finish(name)
	var data := source if source != null else profile
	var file := particle_file(data, str(entry.file))
	if file == null or not file.error.is_empty() or file.frames < 1: return
	var material := _material(file, data)
	if material == null: return
	var copies := 1 if file.loop_end <= 0 else ceili(float(file.frames) / file.loop_end)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	# A unit quad of half-extent 1, scaled in the shader by
	# ELParticleFile.SPRITE_SIZE_FUNCTION (size / cos(pi / 7) on the map's
	# orthographic camera).
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh.mesh = quad
	mesh.instance_count = file.max_count * copies
	mesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mesh
	node.material_override = material
	# The original drew effects without shadows; a shadow-only twin below
	# gives the blended ones a soft one.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Large spells reach about 45 units from their origin.
	node.custom_aabb = AABB(Vector3(-64, -16, -64), Vector3(128, 96, 128))
	# Script coordinates: x east, y north, z up, two units per cell.
	node.position = Vector3(float(entry.x), float(entry.z), -float(entry.y))
	var hidden := optional(entry)
	# Smoke, mist and water spray throw a soft shadow (a remake addition, see
	# ELParticleFile.SHADOW_SHEETS); the weather layers do not.
	var strength := 0.0 if hidden else ELParticleFile.shadow_strength(file)
	if strength > 0.0:
		var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
		ELParticleFile.shade_twin(ELParticleFile.shadow_twin(node, false), material.get_shader_parameter("atlas"), Vector2(file.columns, file.rows), strength, ELParticleFile.camera_extent(camera))
	(weather_layer if hidden else self).add_child(node)
	var rain := hidden and ELArchive.key(str(entry.file)) in RAIN_FILES
	effects[name] = {"entry": entry.duplicate(), "file": file, "node": node, "elapsed": elapsed, "frame": -1, "optional": hidden, "rain": rain}
	if rain and _rain_on_water and enabled: _publish_rain()
	if draw_current: _advance(name, 0.0)

## Decodes a particle file and builds its material while the map loads, so
## its first appearance does not hitch (see keep_file).
func prepare(path: String, source: ELProfile = null) -> void:
	var data := source if source != null else profile
	keep_file(data, path)
	var file := particle_file(data, path)
	if file != null and file.error.is_empty() and file.frames > 0: _material(file, data)

func finish(name: String) -> void:
	var effect: Variant = effects.get(name)
	if effect == null: return
	effect.node.queue_free()
	effects.erase(name)
	if effect.rain and _rain_on_water and enabled: _publish_rain()

func _publish_rain() -> void:
	var areas := PackedVector4Array()
	if enabled and _rain_on_water:
		for effect: Dictionary in effects.values():
			if not effect.rain: continue
			var area := _rain_bounds(effect.file)
			if not area.has_area(): continue
			var origin: Vector3 = effect.node.position
			var center := area.get_center() + Vector2(origin.x, -origin.z)
			areas.append(Vector4(center.x, center.y, area.size.x * 0.5, area.size.y * 0.5))
	rain_changed.emit(areas)

static func _rain_bounds(file: ELParticleFile) -> Rect2:
	if file.has_meta(&"water_rain_bounds"): return file.get_meta(&"water_rain_bounds")
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in file.alpha.size():
		if file.alpha[i] == 0: continue
		var point := Vector2(file.positions[i * 3], file.positions[i * 3 + 1])
		low = low.min(point)
		high = high.max(point)
	var bounds := Rect2(low, high - low) if low.is_finite() and high.is_finite() else Rect2()
	file.set_meta(&"water_rain_bounds", bounds)
	return bounds

func _process(delta: float) -> void:
	if _shrine_session != null and _shrine_fog_revision != ELFog.revision(_shrine_session): _sync_shrines()
	elif _garrisons_dirty: _sync_garrisons()
	_cull_clock += delta
	if _cull_clock >= CULL_STEP:
		_cull_clock = 0.0
		_cull_all()
	for name: String in effects.keys():
		_advance(name, delta)

func _advance(name: String, delta: float) -> void:
	var effect: Dictionary = effects[name]
	effect.elapsed += delta
	var frame := int(effect.elapsed * ELParticleFile.FPS)
	var file: ELParticleFile = effect.file
	var loops := int(effect.entry.get("loops", -1))
	if file.finished(frame, loops):
		finish(name)
		return
	# Hidden ambience and object effects out of view keep their clock but are
	# not redrawn.
	if frame == effect.frame or (effect.optional and not enabled) or (effect.has("cull") and not effect.node.visible): return
	effect.frame = frame
	_draw(effect, file.visible_frames(frame, loops))

## Instance layout: ELParticleFile.instances.
func _draw(effect: Dictionary, frames: PackedInt32Array) -> void:
	var file: ELParticleFile = effect.file
	var mesh: MultiMesh = effect.node.multimesh
	var buffer := PackedFloat32Array()
	for frame: int in frames: buffer.append_array(file.instances(frame))
	var count := mini(buffer.size() / 16, mesh.instance_count)
	buffer.resize(mesh.instance_count * 16)
	mesh.buffer = buffer
	mesh.visible_instance_count = count

## Additive story sprites can light the traced map. Terrain effects use the
## same blend for weather such as rain, so it does not make them light sources.
func glow_sources() -> Array:
	var result := []
	for effect: Dictionary in effects.values():
		var file: ELParticleFile = effect.file
		var node: MultiMeshInstance3D = effect.node
		if effect.frame < 0 or not file.additive or ELSecondAmbience.is_terrain_effect(str(effect.entry.file)) or not node.is_visible_in_tree(): continue
		if effect.get("glow_frame", -1) != effect.frame:
			effect.glow_frame = effect.frame
			var buffer := PackedFloat32Array()
			for frame: int in file.visible_frames(effect.frame, int(effect.entry.get("loops", -1))):
				buffer.append_array(file.instances(frame))
			var atlas := (node.material_override as ShaderMaterial).get_shader_parameter("atlas") as Texture2D
			var tints := ELCombatEffects._atlas_cell_tints(atlas, Vector2i(file.columns, file.rows))
			var glows := ELCombatEffects._glow({"glow_tints": tints}, "", buffer, buffer.size() / 16)
			var total := 0.0
			for glow: Array in glows:
				var colour := ELCombatEffects._saturate(glow[2])
				glow[2] = colour
				total += maxf(colour.x, maxf(colour.y, colour.z))
			var share := minf(1.0, ELCombatEffects.EMITTER_GLOW / maxf(total, 0.0001))
			for glow: Array in glows: glow[2] *= share
			effect.glows = glows
		for glow: Array in effect.get("glows", []):
			result.append([node.global_transform * glow[0], glow[1], glow[2]])
	return result

func _material(file: ELParticleFile, data: ELProfile = null) -> ShaderMaterial:
	if data == null: data = profile
	var key := "%s|%s|%d|%d|%s" % [data.id, file.texture, file.columns, file.rows, file.additive]
	if _materials.has(key): return _materials[key]
	var name := file.texture.get_basename() if file.texture.to_lower().ends_with(".bmp") else file.texture
	var texture := data.texture("Effects/" + name)
	if texture == null:
		_materials[key] = null
		return null
	var material := ShaderMaterial.new()
	material.shader = _shader(file.additive)
	material.set_shader_parameter("atlas", texture)
	material.set_shader_parameter("grid", Vector2(file.columns, file.rows))
	material.render_priority = 10
	if file.additive:
		material.set_shader_parameter("glow", glow_level)
		_glowing.append(weakref(material))
	_materials[key] = material
	return material

static func _shader(additive: bool) -> Shader:
	if not _shaders.has(additive):
		_shaders[additive] = ELParticleFile.make_sprite_shader(SHADER.replace("BLEND", "blend_add" if additive else "blend_mix").replace("SPRITE_ADD", "sprite_add" if additive else ""))
	return _shaders[additive]

## Sets how bright glowing particles draw, running ones too.
static func set_glow_level(value: float) -> void:
	if glow_level == value: return
	glow_level = value
	var live := []
	for reference: WeakRef in _glowing:
		var material := reference.get_ref() as ShaderMaterial
		if material == null: continue
		material.set_shader_parameter("glow", value)
		live.append(reference)
	_glowing = live

## Decodes a particle file ahead of its first use and keeps it out of the
## cache's eviction (a large effect such as the battle dome would otherwise
## be decoded on the frame it appears).
static func keep_file(data: ELProfile, path: String) -> void:
	var key := data.id + ":" + ELArchive.key(path)
	if _kept.has(key): return
	var file := particle_file(data, path)
	if file != null and file.error.is_empty(): _kept[key] = file

## Decoded particle files, shared by every view of the same edition.
static func particle_file(data: ELProfile, path: String) -> ELParticleFile:
	var key := data.id + ":" + ELArchive.key(path)
	if _kept.has(key): return _kept[key]
	if _files.has(key):
		_order.erase(key)
		_order.append(key)
		return _files[key]
	var file := ELParticleFile.decode(data.read("pfx", ELArchive.key(path)))
	_files[key] = file
	_order.append(key)
	while _order.size() > CACHE_LIMIT: _files.erase(_order.pop_front())
	return file

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, BLEND;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(1.0);
uniform float glow = 1.0;
varying vec4 tint;
varying float sprite_extent;
SPRITE_SIZE_FUNCTION
SOFT_FUNCTION
ADD_FUNCTION
void vertex() {
	float size = sprite_half_extent(length(MODEL_MATRIX[0].xyz), PROJECTION_MATRIX);
	sprite_extent = size;
	float cell = floor(length(MODEL_MATRIX[1].xyz) - 0.5);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	vec2 slot = vec2(mod(cell, grid.x), floor(cell / grid.x));
	// Cells count up from the bottom row of the stored image; the sprite's top
	// edge shows the lower edge of its cell.
	UV = (UV + slot) / grid;
	UV.y = 1.0 - UV.y;
	tint = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 texel = texture(atlas, UV);
	ALBEDO = texel.rgb * tint.rgb * glow;
	ALPHA = SPRITE_ADD(texel.a * tint.a * sprite_soft(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX, sprite_extent));
}
"""
