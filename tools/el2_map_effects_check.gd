extends SceneTree
## Headless check of the second game's object effects on the map (table
## SpecEffect kinds of terrain objects and mana nodes):
## - every object whose kind has an effect in the original runs that file
##   at its figure's centre, turned with it, in sight and in explored fog;
##   an object of another kind runs none;
## - the volcano smoke and the springs' water throw a particle shadow (a
##   blended smoke or water sheet), the glows and the ash cloud do not;
## - the weather preference leaves them (they are the object's own), and
##   unexplored fog hides them;
## - an effect whose reach is out of the camera's view is hidden and not
##   redrawn, one in view is drawn;
## - #157: a building figure with a BuildingsPFX/<model>/Idle.pfx (chapter
##   11's teleport altar) plays it with each round of its idle clip.
##
##   godot --headless --path game --script ../tools/el2_map_effects_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped. Saves the maps write are put back as they were.

## The original's effect of each SpecEffect kind (pfx name).
const ORIGINAL := {1: "ManaNodeRed", 2: "ManaNodeBlack", 7: "BlueManaNode",
	3: "Voulcan2x2_1", 4: "Voulcan2x2_2", 5: "Voulcan2x2_3", 6: "Voulcan2x2_4",
	100: "BlueLightHouse", 101: "GreenLightHouse", 102: "RedLightHouse", 103: "BlackLightHouse",
	104: "Dock", 105: "Boat", 106: "Teleport", 110: "Bridge",
	111: "GreenBridgePier", 112: "GreenBridgeAbutment", 113: "BlackBridgePier", 114: "BlackBridgeAbutment",
	115: "RedBridgePier", 116: "RedBridgeAbutment", 117: "BlueBridgePier", 118: "BlueBridgeAbutment",
	119: "SpringMind", 120: "DungeonLvl1", 121: "DungeonLvl2", 122: "DungeonLvl3", 123: "SpringStrength",
	124: "AltarOfWar", 125: "TerrainPFX/ConvulsionOfNature"}
## Maps that between them hold every kind the shipped tables use but the
## green bridges (second_map_feedback_check covers those).
const MAPS := ["Maps/Custom/Null Cycle", "e2mission33", "e2mission22_53"]
## Kinds whose effect throws a particle shadow.
const SHADOWED := [3, 4, 5, 6, 119, 123]

var failures: Array[String] = []
var seen_kinds := {}

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		print("EL2 MAP EFFECTS: 0 failure(s)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths.el2)):
		print("SKIP: the second game's files could not be mounted")
		print("EL2 MAP EFFECTS: 0 failure(s)")
		quit(0)
		return
	_tables(profile)
	var saves := _backup(ELSaveSlots.folder("el2"))
	for map_id: String in MAPS: await _map(profile, map_id)
	await _map(profile, "e2mission11", true)
	var used := {}
	for table: String in ["TerrObj", "ManaNodes"]:
		for name: String in profile.table(table):
			var kind := int(profile.table(table)[name].get("SpecEffect", 0))
			if ORIGINAL.has(kind) and not kind in [111, 112] and table == "TerrObj": used[kind] = true
	var missing := used.keys().filter(func(kind: int) -> bool: return not seen_kinds.has(kind))
	check(missing.is_empty(), "the maps show every TerrObj kind with an effect (missing %s)" % str(missing))
	_restore(ELSaveSlots.folder("el2"), saves)
	print("EL2 MAP EFFECTS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## The remake's kind list is the original's, and every file exists; the
## kinds the shipped tables use loop.
func _tables(profile: ELProfile) -> void:
	check(ELAdventureEffects.SPEC_EFFECTS == ORIGINAL, "the remake's SpecEffect list is the original's")
	var absent: Array = []
	for kind: int in ORIGINAL:
		if not profile.archives.pfx.has(ELArchive.key(str(ORIGINAL[kind]) + ".pfx")): absent.append(ORIGINAL[kind])
	check(absent.is_empty(), "every SpecEffect file exists (missing %s)" % str(absent))
	var once: Array = []
	for name: String in profile.table("TerrObj"):
		var kind := int(profile.table("TerrObj")[name].get("SpecEffect", 0))
		if not ORIGINAL.has(kind): continue
		var file := ELAdventureEffects.particle_file(profile, str(ORIGINAL[kind]) + ".pfx")
		if file == null or file.loop_end <= 0: once.append(name)
	check(once.is_empty(), "every TerrObj effect loops (not: %s)" % str(once))

## With `idle_only` only the building idle effects (#157) are checked.
func _map(profile: ELProfile, map_id: String, idle_only := false) -> void:
	var row := {}
	# A chapter map from its campaign (its script lives there), else a single map.
	for campaign_id: String in ["Green", "Red", "Blue", "Black"]:
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id): continue
		for scenario: Dictionary in campaign.scenarios:
			if row.is_empty() and str(scenario.file_name).to_lower() == map_id.to_lower():
				row = scenario.duplicate()
				row.campaign = campaign_id
				var progress := ELSecondCampaign.for_chapter(profile, campaign_id, row, campaign.scenarios.find(scenario) + 1)
				if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
	for found: Dictionary in ELSingleScenario.maps(profile):
		if row.is_empty() and str(found.id).to_lower() == map_id.to_lower(): row = ELSingleScenario.scenario(found)
	if row.is_empty():
		print("SKIP: no map %s" % map_id)
		return
	var settings := ELSettings.new()
	settings.use_edition("el2")
	settings.values.weather = true
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	check(built, "%s builds: %s" % [map_id, view.error])
	if built and idle_only:
		await frames(5)
		ELFog.reveal_for_console(view.state, 1, true)
		await _idle(view, profile, map_id)
	elif built:
		await frames(5)
		ELFog.reveal_for_console(view.state, 1, true)
		await frames(3)
		_placed(view, profile, map_id)
		_shadows(view, profile, map_id)
		await _weather(view, map_id)
		await _cull(view, map_id)
		await _fog(view, profile, map_id)
	view.queue_free()
	await frames(2)

## #157: the teleport altar's column of light, BuildingsPFX/tebuad132/Idle.pfx,
## as its idle clip comes round (the map's own effects draw it).
func _idle(view: ELAdventureView, profile: ELProfile, map_id: String) -> void:
	var kit := {}
	for item: Dictionary in view.state.objects.values():
		if item.get("name") == "TeleportKit" and item.get("alive", false): kit = item
	if kit.is_empty(): return
	var model: ELModel = view.world.object_models.get(int(kit.uid))
	check(model != null and model.has_clip("cidle") and profile.archives.pfx.has(ELArchive.key("BuildingsPFX/tebuad132/Idle.pfx")), "%s: the teleport altar has an idle clip and an idle effect file" % map_id)
	if model == null: return
	var at := ELAdventureGrid.center(kit, ELSecondBuildings.definition(profile, kit)) * ELAdventureTerrain.CELL
	view.following = -1
	view.target = Vector3(at.x, 0, -at.y)
	view._update_camera()
	await frames(3)
	var name := "idle:%d" % int(kit.uid)
	model.animation_looped.emit("cidle")
	await frames(2)
	var effect: Dictionary = view.effects.effects.get(name, {})
	check(not effect.is_empty() and ELArchive.key(str(effect.entry.file)) == ELArchive.key("BuildingsPFX/tebuad132/Idle.pfx") and Vector2(float(effect.entry.x), float(effect.entry.y)).distance_to(at) < 0.5,
		"%s: the teleport altar's idle round raises its column of light at the altar (#157)" % map_id)

## Each object's effect: the original's file at the figure, or none.
func _placed(view: ELAdventureView, profile: ELProfile, map_id: String) -> void:
	var effects := view.effects
	var wrong: Array = []
	var counts := {}
	var expected_names := {}
	for item: Dictionary in view.state.objects.values():
		var row := ELAdventureEffects.spec_row(profile, item)
		var kind := int(row.get("SpecEffect", 0))
		var name := "spec:%d" % int(item.uid)
		if not ORIGINAL.has(kind):
			if effects.effects.has(name): wrong.append("%s(%d) has %s" % [item.name, kind, effects.effects[name].entry.file])
			continue
		if not item.get("alive", true) or not item.get("visible", true) or not item.get("placed", true): continue
		var expected := str(ORIGINAL[kind]) + ".pfx"
		expected_names[name] = true
		if not effects.effects.has(name) or str(effects.effects[name].entry.file) != expected:
			wrong.append("%s(%d)@%d,%d lacks %s" % [item.name, kind, item.x, item.y, expected])
			continue
		var center := ELAdventureGrid.center(item, row) * ELAdventureTerrain.CELL
		var node: Node3D = effects.effects[name].node
		if node.position.distance_to(Vector3(center.x, 0, -center.y)) > 0.01 or not is_equal_approx(node.rotation.y, -float((int(item.get("rotation", 0)) >> 2) & 3) * PI / 2.0):
			wrong.append("%s placed at %s" % [item.name, node.position])
		counts[kind] = int(counts.get(kind, 0)) + 1
		seen_kinds[kind] = true
	for name: String in effects.effects:
		if name.begins_with("spec:") and not expected_names.has(name): wrong.append("stray " + name)
	check(not counts.is_empty() and wrong.is_empty(), "%s: every object with an original effect runs it at its figure, others none (kinds %s; wrong %s)" % [map_id, str(counts), str(wrong.slice(0, 6))])

func _shadows(view: ELAdventureView, profile: ELProfile, map_id: String) -> void:
	var wrong: Array = []
	for name: String in view.effects.effects:
		if not name.begins_with("spec:"): continue
		var item := view.state.object(int(name.trim_prefix("spec:")))
		var kind := int(ELAdventureEffects.spec_row(profile, item).get("SpecEffect", 0))
		var twin := (view.effects.effects[name].node as Node).get_node_or_null("Shadow") as MultiMeshInstance3D
		if ELParticleFile.twin_casts(twin) != (kind in SHADOWED): wrong.append("%s(%d)" % [item.get("name"), kind])
	check(wrong.is_empty(), "%s: volcano smoke and spring water throw a shadow, the rest none (wrong %s)" % [map_id, str(wrong.slice(0, 6))])

func _weather(view: ELAdventureView, map_id: String) -> void:
	view.effects.set_enabled(false)
	await frames(1)
	var hidden: Array = []
	for name: String in view.effects.effects:
		var effect: Dictionary = view.effects.effects[name]
		if name.begins_with("spec:") and (effect.optional or (effect.node as Node).get_parent() == view.effects.weather_layer): hidden.append(effect.entry.file)
	check(hidden.is_empty(), "%s: the weather preference leaves the object effects (%s)" % [map_id, str(hidden.slice(0, 4))])
	view.effects.set_enabled(true)

## Out of the view an effect is hidden and not redrawn; in view it is drawn.
func _cull(view: ELAdventureView, map_id: String) -> void:
	var effects := view.effects
	var names: Array = effects.effects.keys().filter(func(name: String) -> bool: return name.begins_with("spec:"))
	if names.is_empty(): return
	var near: String = names[0]
	var target: Vector3 = effects.effects[near].node.position
	view.following = -1
	view._scroll_to(target, true)
	await frames(2)
	effects._cull_all()
	var far := ""
	for name: String in names:
		if (effects.effects[name].node.position as Vector3).distance_to(target) > 120.0: far = name
	await frames(3)
	var near_effect: Dictionary = effects.effects[near]
	check(near_effect.node.visible and near_effect.frame >= 0, "%s: an effect in view is drawn (%s)" % [map_id, near_effect.entry.file])
	if far.is_empty():
		print("SKIP: %s has no object effect far from %s" % [map_id, near])
		return
	var far_effect: Dictionary = effects.effects[far]
	var frame: int = far_effect.frame
	await frames(4)
	check(not far_effect.node.visible and far_effect.frame == frame, "%s: one out of view is hidden and not redrawn (%s)" % [map_id, far_effect.entry.file])
	view._scroll_to(far_effect.node.position, true)
	await frames(2)
	effects._cull_all()
	await frames(2)
	check(far_effect.node.visible and far_effect.frame != frame, "%s: and drawn again once the view comes to it" % map_id)

## Unexplored fog hides an object's effect; explored again it returns.
func _fog(view: ELAdventureView, profile: ELProfile, map_id: String) -> void:
	var state := view.state
	var item := {}
	# The object farthest from the player's heroes, whose sight is not on it.
	var best := -1.0
	for name: String in view.effects.effects:
		if not name.begins_with("spec:"): continue
		var candidate := state.object(int(name.trim_prefix("spec:")))
		var nearest := INF
		for other: Dictionary in state.objects.values():
			if other.get("type") == "hero" and int(other.get("owner", -1)) == 1 and other.get("alive", true):
				nearest = minf(nearest, Vector2(float(other.x), float(other.y)).distance_to(Vector2(float(candidate.x), float(candidate.y))))
		if nearest > best:
			best = nearest
			item = candidate
	if item.is_empty(): return
	ELFog.reveal_for_console(state, 1, false)
	if not ELFog.active(state, 1):
		print("SKIP: %s has no fog" % map_id)
		ELFog.reveal_for_console(state, 1, true)
		return
	var name := "spec:%d" % int(item.uid)
	var seen: PackedByteArray = state.fog.get("visible", PackedByteArray())
	for y in range(int(item.y) - 1, int(item.y) + 4):
		for x in range(int(item.x) - 1, int(item.x) + 4):
			if x < 0 or y < 0 or x >= state.map.width or y >= state.map.height: continue
			var index := y * state.map.width + x
			state.explored[index] &= ~ELFog.bit(1)
			if index < seen.size(): seen[index] &= ~ELFog.bit(1)
	state.fog.visible = seen
	state.fog.revision = ELFog.revision(state) + 1
	await frames(2)
	check(not view.effects.effects.has(name), "%s: under unexplored fog %s has no effect" % [map_id, item.get("name")])
	ELFog.reveal_for_console(state, 1, true)
	await frames(2)
	check(view.effects.effects.has(name), "%s: explored again it runs it" % map_id)

func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if kept.has(file):
			if FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
				var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
				out.store_buffer(kept[file])
		else: DirAccess.remove_absolute(folder.path_join(file))
