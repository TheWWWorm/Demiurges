class_name ELFirstMapPresentation
extends Node3D
## First game: map presentation that does not change the simulation.
##
## Ownership blazons. Every owned castle, hero, mine, mana node, fort, shop
## and captured shrine or citadel carries its owner's blazon: a 41 px cell of
## Interface/Blazon/color (the blazon colour, a 6 x 6 grid) under a cell of
## Interface/Blazon/logo00/logo01 (the blazon, 36 per sheet), as a
## camera-facing quad 1.3 units above the figure's top. A capture changes it
## at once. Options "Show blazons" switches them all off.
##
## Building sounds. A building whose table row names a sound folder
## (ResourceMine/NewBuildings SoundDir, AdditionalBuildings SndDir; mana
## nodes <Colour>ManaNode, castles <Colour>Castle) loops
## Buildings/<folder>/cycle.wav while it exists, and plays
## Buildings/<folder>/Idle00.wav each time its idle animation (cidle) comes
## round. Both are positional: full volume within 10 units of the listener,
## falling as 10 / distance, silent beyond 25. They use the effects volume.
##
## Building particles. Mana nodes, volcano rocks and several additional
## buildings keep a looping map effect (SPEC_EFFECTS); a figure with
## BuildingsPFX/<model>/Idle.pfx plays it once with each idle round.
##
## Terrain ambience. While ambient sounds are on, the terrain in view is
## counted by colour (red, green, blue, black, lava, water; lava and water
## cells count 40 times), as percentages. Each colour at 30 % or more loops
## Ambient/<Colour>/circle.wav at that percentage of full volume. Each 64 ms
## step has a 64 x 0.0003 chance of one random Ambient/<Colour>/<n>.wav: the
## colour is chosen in proportion to its percentage among the first four
## (no sound for the rest), the file uniformly from 1..count.
const BLAZON_CELL := 41.0
## World size of the blazon quad (measured against original map captures).
const BLAZON_SIZE := 1.5
const BLAZON_LIFT := 1.3
const SOUND_NEAR := 10.0
const SOUND_FAR := 25.0
const STEP := 0.064
const AMBIENT_RATE := 0.0003
const AMBIENT_LOOP_MIN := 30
const AMBIENT_FOLDERS := ["Red", "Green", "Blue", "Black", "Lava", "Water"]
const WEIGHTED := 40
const MAX_ONE_SHOTS := 8
## Map effects started with a building figure (file name under the pfx root).
const SPEC_EFFECTS := {"Teacher": "Teacher00", "Master": "Master00", "Magister": "Magister00",
	"SpringOfStrength": "SpringStrength", "SpringOfDexterity": "SpringDexterity", "HealersCitadel": "HealersCitadel",
	"WanderersCitadel": "ShrineCraftingRd", "ShrineMagic": "ShrineMagicRd", "WardingStone": "WardingStone"}
## Table SpecEffect kinds of mana nodes and terrain objects.
const SPEC_KINDS := {1: "ManaNodeRed", 2: "ManaNodeBlack", 7: "BlueManaNode",
	3: "Voulcan2x2_1", 4: "Voulcan2x2_2", 5: "Voulcan2x2_3", 6: "Voulcan2x2_4"}
const OWNED_KINDS := ["hero", "resource_mine", "mana_node", "fort", "rune_shop", "el1_spell_shop"]

var profile: ELProfile
var settings: ELSettings
var state: ELAdventureSession
var world: ELAdventureScene
var camera: Camera3D
## Ground point the map is heard from (the camera target).
var listener := Vector3.ZERO
var effects: ELAdventureEffects
var show_blazons := true
var ambient_on := true
var _volumes := {}
var _art: ELAdventureArt
var _blazon_layer: Node3D
## uid -> {back, fore, owner, top}
var blazons: Dictionary = {}
var _textures: Dictionary = {}
var _dirty := true
## uid -> {folder, position, cycle (player or null)}
var sounding: Dictionary = {}
var _one_shots: Array[AudioStreamPlayer] = []
## uid -> spec effect file; started only near the camera.
var spec_effects: Dictionary = {}
var _connected: Dictionary = {}
var _clock := 0.0
var _spec_clock := 0.0
var random := RandomNumberGenerator.new()
## Terrain percentages of the view (Red, Green, Blue, Black, Lava, Water).
var percentages := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _ambient_counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
var ambient_loops: Dictionary = {}
## Random terrain sounds still playing.
var ambient_players: Array[AudioStreamPlayer] = []
## Started sound paths (latest 40), for checks.
var played: Array[String] = []
var _view_key := ""

func build(data: ELProfile, preferences: ELSettings, session: ELAdventureSession, scene: ELAdventureScene, view_camera: Camera3D) -> void:
	profile = data
	settings = preferences
	state = session
	world = scene
	camera = view_camera
	random.randomize()
	_art = ELAdventureArt.new(state.map)
	_blazon_layer = Node3D.new()
	add_child(_blazon_layer)
	effects = ELAdventureEffects.new()
	add_child(effects)
	effects.build(profile, settings, state)
	for name: String in ["color", "logo00", "logo01"]: _textures[name] = profile.texture("Interface/Blazon/" + name)
	for i in 4: _ambient_counts[i] = ambient_count(profile, AMBIENT_FOLDERS[i])
	if not state.event.is_connected(_state_event): state.event.connect(_state_event)
	apply(settings.values if settings != null else {})
	sync()

func apply(values: Dictionary) -> void:
	show_blazons = bool(values.get("show_blazons", true))
	ambient_on = bool(values.get("ambient_sounds", true))
	_volumes = values
	if _blazon_layer != null: _blazon_layer.visible = show_blazons
	if not ambient_on: _stop_ambience()

func _state_event(_data: Dictionary) -> void:
	_dirty = true

## Number of Ambient/<folder>/<n>.wav files from 1 upwards without a gap.
static func ambient_count(data: ELProfile, folder: String) -> int:
	var archive: ELArchive = data.archives.get("sfx")
	if archive == null: return 0
	var count := 0
	while archive.has("Ambient/%s/%d.wav" % [folder, count + 1]): count += 1
	return count

## Terrain colour of a map tile: 0 red, 1 green, 2 blue, 3 black, 4 lava,
## 5 water.
static func terrain_category(kind: int) -> int:
	if kind == 0x10 or kind == 0x13: return 5
	if kind == 0x11: return 4
	match ELAdventureArt.terrain_color(kind):
		"Red": return 0
		"Green": return 1
		"Blue": return 2
		"Black": return 3
	return 4

## Percentages of the counted tiles; lava and water count 40 times.
static func terrain_percentages(counts: PackedInt32Array) -> PackedInt32Array:
	var weighted := counts.duplicate()
	weighted[4] *= WEIGHTED
	weighted[5] *= WEIGHTED
	var total := 0
	for value: int in weighted: total += value
	var result := PackedInt32Array([0, 0, 0, 0, 0, 0])
	if total <= 0: return result
	for i in 6: result[i] = weighted[i] * 100 / total
	return result

## The random sound's colour for a roll of 1..100, or -1 for none.
static func ambient_colour(shares: PackedInt32Array, roll: int) -> int:
	var left := roll
	for i in 4:
		left -= shares[i]
		if left <= 0: return i
	return -1

## Owner whose blazon an object shows, or -1.
static func blazon_owner(session: ELAdventureSession, item: Dictionary) -> int:
	if item.is_empty() or not item.get("alive", true) or not item.get("visible", true) or not item.get("placed", true): return -1
	var owner := int(item.get("owner", -1))
	if owner <= 0 or not session.players.has(owner): return -1
	if item.get("type") == "hero": return -1 if item.get("fortified", false) else owner
	if item.get("type") in OWNED_KINDS or ELFirstScenario.is_castle(item): return owner
	if item.get("group") == "additional_buildings" and str(item.get("name", "")) in ELAdditionalBuildings.OWNED: return owner
	return -1

## A player's blazon (x) and blazon colour (y) from the map, -1 when unset.
static func player_blazon(session: ELAdventureSession, owner: int) -> Vector2i:
	return ELPlayerProfile.player_blazon(session, owner)

## Sound folder of a building, "" for none.
static func sound_folder(data: ELProfile, item: Dictionary, row: Dictionary) -> String:
	match str(item.get("group", "")):
		"mines", "laboratories", "factories": return str(row.get("SoundDir", ""))
		"additional_buildings": return str(row.get("SndDir", ""))
		"mana_nodes": return str(row.get("MagicColor", "")) + "ManaNode" if not str(row.get("MagicColor", "")).is_empty() else ""
	if ELFirstScenario.is_castle(item) and not str(row.get("MagicColor", "")).is_empty(): return str(row.MagicColor) + "Castle"
	return ""

## Persistent map effect file of an object, "" for none.
static func spec_effect(item: Dictionary, row: Dictionary) -> String:
	if item.get("group") == "additional_buildings": return str(SPEC_EFFECTS.get(str(item.get("name", "")), ""))
	if item.get("group") in ["mana_nodes", "terrain_objects"]: return str(SPEC_KINDS.get(int(row.get("SpecEffect", 0)), ""))
	# First-game castles: <Colour>Castle, then D1-D3 as the castle is damaged.
	if item.has("castle_stage") and ELFirstScenario.is_castle(item) and not str(row.get("MagicColor", "")).is_empty():
		return str(row.MagicColor) + "Castle" + ["", "D1", "D2", "D3"][clampi(int(item.castle_stage), 0, 3)]
	return ""

## Linear gain of a positional building sound at a ground distance.
static func distance_gain(distance: float) -> float:
	if distance <= SOUND_NEAR: return 1.0
	if distance >= SOUND_FAR: return 0.0
	return SOUND_NEAR / distance

func _object_position(item: Dictionary, row: Dictionary) -> Vector3:
	var uid := int(item.uid)
	if world.actors.has(uid): return world.actors[uid].position
	var center := ELAdventureGrid.center(item, row)
	return Vector3(center.x * ELAdventureTerrain.CELL, 0, -center.y * ELAdventureTerrain.CELL)

## Rebuilds blazons, sounds and effects from the objects.
func sync() -> void:
	_dirty = false
	var seen := {}
	for item: Dictionary in state.objects.values():
		var uid := int(item.get("uid", -1))
		var definition := _art.resolve(item)
		if definition.is_empty() or definition.get("hidden", false): continue
		var row: Dictionary = definition.get("row", {})
		seen[uid] = true
		_sync_blazon(item, row)
		var alive: bool = item.get("alive", true) and item.get("visible", true) and not item.get("opened", false)
		var folder := sound_folder(profile, item, row) if alive else ""
		if folder.is_empty(): _drop_sound(uid)
		elif not sounding.has(uid): sounding[uid] = {"folder": folder, "position": _object_position(item, row), "cycle": null}
		else: sounding[uid].folder = folder
		var file := spec_effect(item, row) if alive else ""
		if file.is_empty():
			if spec_effects.has(uid):
				effects.finish("spec:%d" % uid)
				spec_effects.erase(uid)
		elif spec_effects.get(uid, {}).get("file", "") != file:
			effects.finish("spec:%d" % uid)
			spec_effects[uid] = {"file": file, "position": _object_position(item, row), "yaw": world.object_yaw(item), "running": false}
		_connect_model(uid)
	for uid: int in blazons.keys():
		if not seen.has(uid): _drop_blazon(uid)
	for uid: int in sounding.keys():
		if not seen.has(uid): _drop_sound(uid)
	for uid: int in spec_effects.keys():
		if not seen.has(uid):
			effects.finish("spec:%d" % uid)
			spec_effects.erase(uid)

func _connect_model(uid: int) -> void:
	var model: ELModel = world.object_models.get(uid)
	if model == null or world.actors.has(uid): return
	if _connected.get(uid) == model: return
	_connected[uid] = model
	model.animation_looped.connect(_idle_round.bind(uid))

func _sync_blazon(item: Dictionary, row: Dictionary) -> void:
	var uid := int(item.uid)
	var owner := blazon_owner(state, item)
	var picture := player_blazon(state, owner) if owner > 0 else Vector2i(-1, -1)
	if owner <= 0 or picture.x < 0 or picture.y < 0:
		_drop_blazon(uid)
		return
	var entry: Dictionary = blazons.get(uid, {})
	if entry.get("picture", Vector2i(-2, -2)) != picture:
		_drop_blazon(uid)
		entry = {"back": _sprite("color", picture.y, 0), "fore": _sprite("logo%02d" % (picture.x / 36), picture.x % 36, 1), "picture": picture, "owner": owner}
		blazons[uid] = entry
	entry.top = maxf(world.object_top(uid), 0.0)
	entry.row = row
	_place_blazon(uid, item)

func _sprite(sheet: String, cell: int, layer: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _textures.get(sheet)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(BLAZON_CELL * (cell % 6), BLAZON_CELL * (cell / 6), BLAZON_CELL, BLAZON_CELL)
	sprite.pixel_size = BLAZON_SIZE / BLAZON_CELL
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.render_priority = 20 + layer
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blazon_layer.add_child(sprite)
	return sprite

func _place_blazon(uid: int, item: Dictionary) -> void:
	var entry: Dictionary = blazons[uid]
	var at := _object_position(item, entry.row) + Vector3(0, float(entry.top) + BLAZON_LIFT + BLAZON_SIZE * 0.5, 0)
	var shown := true
	if world.actors.has(uid): shown = world.actors[uid].visible
	for key: String in ["back", "fore"]:
		entry[key].position = at
		entry[key].visible = shown

func _drop_blazon(uid: int) -> void:
	var entry: Dictionary = blazons.get(uid, {})
	for key: String in ["back", "fore"]:
		if entry.has(key) and is_instance_valid(entry[key]): entry[key].queue_free()
	blazons.erase(uid)

func _drop_sound(uid: int) -> void:
	var entry: Dictionary = sounding.get(uid, {})
	if entry.get("cycle") != null and is_instance_valid(entry.cycle):
		entry.cycle.stop()
		entry.cycle.queue_free()
	sounding.erase(uid)

func _effects_db() -> float:
	return linear_to_db(maxf(0.0001, float(_volumes.get("effects", 0.8))))

func _ambience_db() -> float:
	return linear_to_db(maxf(0.0001, float(_volumes.get("ambience", 0.55))))

func _ground_distance(at: Vector3) -> float:
	return Vector2(at.x - listener.x, at.z - listener.z).length()

## A building's idle animation came round: its Idle00 sound and Idle effect.
func _idle_round(clip: String, uid: int) -> void:
	if clip != "cidle": return
	var item := state.object(uid)
	if item.is_empty(): return
	var definition := _art.resolve(item)
	var entry: Dictionary = sounding.get(uid, {})
	if not entry.is_empty() and _ground_distance(entry.position) < SOUND_FAR:
		_play_one_shot("Buildings/%s/Idle00.wav" % entry.folder, entry.position)
	var model := str(definition.get("model", ""))
	var file := "BuildingsPFX/%s/Idle.pfx" % model
	var archive: ELArchive = profile.archives.get("pfx")
	if not model.is_empty() and archive != null and archive.has(file) and _near_view(_object_position(item, definition.get("row", {}))):
		var at := _object_position(item, definition.get("row", {}))
		effects.start("idle:%d" % uid, {"file": file, "x": at.x, "y": -at.z, "z": at.y, "loops": 1}, 0.0)
		effects.orient("idle:%d" % uid, world.object_yaw(item))

func _play_one_shot(path: String, at: Vector3) -> void:
	var stream := ELAudio.sound(profile, path)
	if stream == null: return
	var player: AudioStreamPlayer = null
	for candidate: AudioStreamPlayer in _one_shots:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		if _one_shots.size() >= MAX_ONE_SHOTS: return
		player = AudioStreamPlayer.new()
		add_child(player)
		_one_shots.append(player)
	player.stream = stream
	player.set_meta("at", at)
	player.volume_db = _effects_db() + linear_to_db(maxf(0.0001, distance_gain(_ground_distance(at))))
	player.play()
	_note(path)

func _note(path: String) -> void:
	played.append(path)
	if played.size() > 40: played.pop_front()

func _near_view(at: Vector3) -> bool:
	var radius := (camera.size if camera != null else 42.0) * 1.2 + 16.0
	return _ground_distance(at) <= radius

func _process(delta: float) -> void:
	if state == null: return
	if _dirty: sync()
	for uid: int in blazons:
		_place_blazon(uid, state.object(uid))
	_update_cycles()
	_spec_clock += delta
	if _spec_clock >= 0.5:
		_spec_clock = 0.0
		_update_spec_effects()
	for player: AudioStreamPlayer in _one_shots:
		if player.playing: player.volume_db = _effects_db() + linear_to_db(maxf(0.0001, distance_gain(_ground_distance(player.get_meta("at", listener)))))
	_clock += delta
	while _clock >= STEP:
		_clock -= STEP
		_ambient_step()

func _update_cycles() -> void:
	for uid: int in sounding:
		var entry: Dictionary = sounding[uid]
		var distance := _ground_distance(entry.position)
		if entry.cycle == null and distance < SOUND_FAR:
			var source := ELAudio.sound(profile, "Buildings/%s/cycle.wav" % entry.folder)
			if source == null:
				entry.cycle = false
				continue
			var loop: AudioStreamWAV = source.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = int(loop.get_length() * loop.mix_rate)
			var player := AudioStreamPlayer.new()
			add_child(player)
			player.stream = loop
			player.volume_db = _effects_db() + linear_to_db(maxf(0.0001, distance_gain(distance)))
			player.play()
			entry.cycle = player
			_note("Buildings/%s/cycle.wav" % entry.folder)
		elif entry.cycle is AudioStreamPlayer:
			if distance > SOUND_FAR + 5.0:
				entry.cycle.stop()
				entry.cycle.queue_free()
				entry.cycle = null
			else: entry.cycle.volume_db = _effects_db() + linear_to_db(maxf(0.0001, distance_gain(distance)))

func _update_spec_effects() -> void:
	for uid: int in spec_effects:
		var entry: Dictionary = spec_effects[uid]
		var near := _near_view(entry.position)
		if near and not entry.running:
			effects.start("spec:%d" % uid, {"file": entry.file + ".pfx", "x": entry.position.x, "y": -entry.position.z, "z": entry.position.y, "loops": -1}, 0.0)
			effects.orient("spec:%d" % uid, float(entry.yaw))
			entry.running = effects.effects.has("spec:%d" % uid)
		elif not near and entry.running:
			effects.finish("spec:%d" % uid)
			entry.running = false

## Ground cells under the view: the corners of the viewport on the ground.
func view_cells() -> Rect2i:
	if camera == null or not camera.is_inside_tree(): return Rect2i()
	var size := camera.get_viewport().get_visible_rect().size
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
		if hit == null: continue
		var cell := Vector2(hit.x, -hit.z) / ELAdventureTerrain.CELL
		low = low.min(cell)
		high = high.max(cell)
	if low.x == INF: return Rect2i()
	var first := Vector2i(maxi(0, floori(low.x)), maxi(0, floori(low.y)))
	var last := Vector2i(mini(state.map.width - 1, floori(high.x)), mini(state.map.height - 1, floori(high.y)))
	return Rect2i(first, (last - first + Vector2i.ONE).max(Vector2i.ZERO))

## Recounts the terrain colours of the view.
func count_view() -> void:
	var cells := view_cells()
	var key := str(cells)
	if key == _view_key: return
	_view_key = key
	var counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
	for y in range(cells.position.y, cells.end.y):
		for x in range(cells.position.x, cells.end.x):
			var kind := state.map.tile(x, y)
			if kind >= 0: counts[terrain_category(kind)] += 1
	percentages = terrain_percentages(counts)

func _ambient_step() -> void:
	if not ambient_on:
		return
	count_view()
	if random.randf() < STEP * 1000.0 * AMBIENT_RATE:
		var colour := ambient_colour(percentages, random.randi_range(1, 100))
		if colour >= 0 and _ambient_counts[colour] > 0:
			var path := "Ambient/%s/%d.wav" % [AMBIENT_FOLDERS[colour], random.randi_range(1, _ambient_counts[colour])]
			var stream := ELAudio.sound(profile, path)
			# Earlier random sounds keep playing; a new one starts beside them.
			if stream != null and ambient_players.size() < MAX_ONE_SHOTS:
				var player := AudioStreamPlayer.new()
				add_child(player)
				player.stream = stream
				player.volume_db = _ambience_db()
				player.finished.connect(_ambient_finished.bind(player))
				player.play()
				ambient_players.append(player)
				_note(path)
	for i in 6:
		var folder: String = AMBIENT_FOLDERS[i]
		var player: AudioStreamPlayer = ambient_loops.get(folder)
		if percentages[i] < AMBIENT_LOOP_MIN:
			if player != null:
				player.stop()
				player.queue_free()
				ambient_loops.erase(folder)
			continue
		if player == null:
			var source := ELAudio.sound(profile, "Ambient/%s/circle.wav" % folder)
			if source == null: continue
			var loop: AudioStreamWAV = source.duplicate()
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = int(loop.get_length() * loop.mix_rate)
			player = AudioStreamPlayer.new()
			add_child(player)
			player.stream = loop
			player.play()
			ambient_loops[folder] = player
			_note("Ambient/%s/circle.wav" % folder)
		player.volume_db = _ambience_db() + linear_to_db(percentages[i] / 100.0)

func _ambient_finished(player: AudioStreamPlayer) -> void:
	ambient_players.erase(player)
	player.queue_free()

func _stop_ambience() -> void:
	for folder: String in ambient_loops:
		ambient_loops[folder].stop()
		ambient_loops[folder].queue_free()
	ambient_loops.clear()
	for player: AudioStreamPlayer in ambient_players: player.queue_free()
	ambient_players.clear()
	_view_key = ""

## The map behind a battle or window: its sounds pause with it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		var paused := what == NOTIFICATION_DISABLED
		for child: Node in get_children():
			if child is AudioStreamPlayer: child.stream_paused = paused
		for uid: int in sounding:
			if sounding[uid].cycle is AudioStreamPlayer: sounding[uid].cycle.stream_paused = paused

func _exit_tree() -> void:
	for child: Node in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
