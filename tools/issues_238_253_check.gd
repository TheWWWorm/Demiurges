extends SceneTree
## Regression checks for second-game adventure reports:
## - #238: a level gained in a battle is chosen before the dialogue that
##   battle's script starts; the dialogue opens once the level-up dialog closes;
## - #239: the menu used for saving over the map is built hidden, so the main
##   menu never shows while the first save of a session takes its picture;
## - #248: ExAddCommandText's fourth argument names the voice of a line whose
##   text the script formatted itself (chapter 41's "%d days" line);
## - #249: script commands queued after a move-and-use that starts a battle
##   between two computer sides wait until that battle has ended;
## - #253: the first-specialisation hint follows only the first specialisation
##   of a playthrough, for a hero that held none.
##
##   godot --headless --path game --script ../tools/issues_238_253_check.gd
##
## The checks need the second game configured in user://profiles.json; without
## it they are skipped. Saves of the second game are restored afterwards.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, caption: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + caption)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await process_frame

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await frames(3)
	if not view.profiles.has("el2"):
		print("SKIP: no second-game files configured")
		view.queue_free()
		quit(0)
		return
	var profile: ELProfile = view.profiles.el2
	_voice_key(profile)
	_specialization_hint(profile)
	_auto_fight_holds_commands(profile)
	await _map_view(view)
	view.queue_free()
	await frames(2)
	print("ADVENTURE REPORTS 238-253: %d failure(s)" % failures)
	quit(int(failures > 0))

func _session(profile: ELProfile, map_id: String) -> Array:
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(profile):
		if str(found.id).to_lower() == map_id: entry = found
	var map := ELAdventureMap.new()
	if entry.is_empty() or not map.load_map(profile, str(entry.id)): return []
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false): return []
	var director := ELAdventureDirector.new()
	if not director.build(state): return []
	return [state, director]

func _voice_key(profile: ELProfile) -> void:
	var pair := _session(profile, "e2mission23")
	if pair.is_empty():
		check(false, "#248: chapter 23 loads")
		return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	var key := "MV_M41_S02_P03_MS_TRAPPEDHERO_41"
	var formatted := profile.text(key).replace("%d", "55")
	director.dialogue = {}
	director._execute({"kind": "Text", "arguments": [float(state.main_hero), formatted, 1.0, key]})
	check(director.dialogue.get("text_id") == key and director.dialogue.get("text") == formatted, "#248: a formatted line keeps its own text and speaks its key's voice")
	check(not profile.read("sfx", "MissionVoices/" + key + ".mp3").is_empty(), "#248: the line's Russian voice is in the installed archives")
	director.dialogue = {}
	director._execute({"kind": "Text", "arguments": [float(state.main_hero), key, 1.0]})
	check(director.dialogue.get("text_id") == key, "#248: a plain text key still names its own voice")

func _specialization_hint(profile: ELProfile) -> void:
	var pair := _session(profile, "e2mission23")
	if pair.is_empty():
		check(false, "#253: chapter 23 loads")
		return
	var state: ELAdventureSession = pair[0]
	var hero := state.object(state.main_hero)
	var hint := profile.text("T_MB_RECEIVE_NEW_SPEC_FIRST")
	var codes: Array[String] = []
	for code: String in profile.table("HeroesSpecs"):
		if code != "NONE" and ELSpecs.valid(profile, code): codes.append(code)
	# Inside a campaign: the first specialisation of the playthrough only.
	state.scenario[ELSecondCampaign.KEY] = ELSecondCampaign.new_game()
	hero.specialization = "NONE"
	hero.specializations = []
	var texts: Array[String] = []
	state.event.connect(func(data: Dictionary): if data.kind == "specialization_learned": texts.append(str(data.text)))
	check(state.learn_specialization(int(hero.uid), codes[0]) and texts[-1].ends_with(hint), "#253: a hero's first specialisation of the playthrough adds the hint")
	check(bool(ELSecondCampaign.progress(state).get("spec_hint", false)) and ELSecondCampaign.valid(ELSecondCampaign.progress(state)), "#253: the shown hint is kept in the campaign progress")
	check(state.learn_specialization(int(hero.uid), codes[1]) and not texts[-1].contains(hint), "#253: a second specialisation has no hint")
	# A later chapter's hero (another campaign of the same playthrough).
	hero.specialization = "NONE"
	hero.specializations = []
	check(state.learn_specialization(int(hero.uid), codes[2]) and not texts[-1].contains(hint), "#253: a later campaign's first specialisation has no hint")
	# A hero starting with its own specialisation (chapter 41's Alpha).
	state.scenario[ELSecondCampaign.KEY] = ELSecondCampaign.new_game()
	hero.specialization = codes[0]
	hero.specializations = []
	check(state.learn_specialization(int(hero.uid), codes[3]) and not texts[-1].contains(hint), "#253: a hero with a starting specialisation gets no hint (#253's Synthet chapter)")
	# The altar's message follows the same rule.
	var shrine := {}
	for item: Dictionary in state.objects.values():
		if ELSecondBuildings.kind(item) == "specialization" and not ELSecondBuildings.shrine_code(profile, item).is_empty(): shrine = item
	if shrine.is_empty():
		check(false, "#253: chapter 23 has a specialisation altar")
		return
	state.scenario[ELSecondCampaign.KEY] = ELSecondCampaign.new_game()
	hero.specialization = "NONE"
	hero.specializations = []
	var boxes: Array[String] = []
	var director: ELAdventureDirector = pair[1]
	director.presentation.connect(func(data: Dictionary): if data.kind == "building_message": boxes.append(str(data.text)))
	hero.travel_day = state.day
	ELSecondBuildings.use(director, hero, shrine)
	check(not boxes.is_empty() and boxes[-1].ends_with(hint), "#253: the altar's first specialisation of the playthrough adds the hint (Eilin's altar)")
	shrine.used = false
	hero.specialization = codes[0]
	hero.specializations = []
	state.scenario.erase(ELSecondCampaign.KEY)
	ELSecondBuildings.use(director, hero, shrine)
	check(not boxes.is_empty() and not boxes[-1].contains(hint), "#253: the altar adds no hint for a hero that already holds one")

func _auto_fight_holds_commands(profile: ELProfile) -> void:
	var pair := _session(profile, "e2mission23")
	if pair.is_empty():
		check(false, "#249: chapter 23 loads")
		return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	for f in 400:
		director.advance(0.05)
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		elif f > 5 and director.can_move(): break
	# Two sides without a local player: a neutral creature walks into another.
	var monsters: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		if item.get("type") in ["hero", "monster"] and item.get("alive", false) and item.get("placed", true) and int(item.get("x", -1)) >= 0 and int(item.get("owner", -1)) != 1: monsters.append(item)
	var actor := {}
	var target := {}
	for first: Dictionary in monsters:
		for second: Dictionary in monsters:
			if first == second or not state.hostile(first, second): continue
			var next := ELAdventureEncounter.new()
			if next.prepare(state, int(first.uid), int(second.uid)) and next.auto:
				actor = first
				target = second
				break
		if not actor.is_empty(): break
	if actor.is_empty():
		print("SKIP: #249 found no pair of computer sides for a shown battle")
		return
	# The actor stands next to its target, so the move ends at once.
	var cell := Vector2i(int(target.x), int(target.y))
	for dir: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var near := cell + dir
		if director.grid.passability(near, false) >= 0:
			actor.x = near.x
			actor.y = near.y
			director.grid.update_actor(actor)
			break
	state.commands.append({"kind": "MoveAndUseObject", "arguments": [float(actor.uid), float(target.uid)]})
	state.commands.append({"kind": "CameraToObject", "arguments": [float(state.main_hero)]})
	var fought := false
	var waited := true
	for f in 600:
		director.advance(0.05)
		if not director.auto_fight.is_empty():
			fought = true
			if state.commands.is_empty() or state.commands[0].kind != "CameraToObject": waited = false
		if fought and director.auto_fight.is_empty(): break
	for f in 20:
		if state.commands.is_empty() or not director.dialogue.is_empty(): break
		director.advance(0.05)
	check(fought, "#249: the move-and-use starts a shown battle between computer sides")
	check(fought and waited, "#249: the next script command waits while that battle is shown")
	check(fought and (state.commands.is_empty() or state.commands[0].kind != "CameraToObject"), "#249: the waiting command runs once the battle has ended")

func _map_view(view: Node) -> void:
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(view.profiles.el2):
		if str(found.id).to_lower().ends_with("e2mission23"): entry = found
	var saves := _backup(ELSaveSlots.folder("el2"))
	await view._begin_campaign("el2", ELSingleScenario.scenario(entry), 1)
	var map: ELAdventureView = view.campaign_view
	if map == null:
		_restore(ELSaveSlots.folder("el2"), saves)
		check(false, "chapter 23 opens on the map")
		return
	var director := map.director
	for i in 40:
		if director.dialogue.is_empty(): break
		director.acknowledge("OK")
		await frames(3)
	# The chapter opens behind a fade; the map waits for it.
	for i in 600:
		if map._mission_fade == null: break
		await process_frame
	# #239: the save screen's menu is built hidden.
	if map.extras == null:
		check(map._extras_ready(), "#239: the original menus build over the map")
		check(map.extras_layer != null and not map.extras_layer.visible, "#239: the menu built for a save stays hidden (no main menu over the map)")
		check(map.open_extras("save_game", true, Callable(), ELSaveSlots.kind_of(map.state)) and map.extras_layer.visible and map.extras.screen == "save_game", "#239: the save screen itself still shows")
		map.extras.leave_screen()
		check(not map.extras_layer.visible, "#239: leaving the save screen hides the menu again")
	# #238: a battle's level is chosen before the battle's dialogue.
	var state := map.state
	var hero := state.object(state.main_hero)
	hero.skill_points = 1
	hero.skill_offers = []
	if ELHeroSkills.prepare(state.map.profile, hero).is_empty():
		check(false, "#238: the main hero has skills to offer")
	else:
		map._battle_level_hero = state.main_hero
		var speech := {"actor": -1, "title": "", "text_id": "", "text": "After the battle", "question": false, "arguments": [], "box": "text", "speaker_box": false}
		director.dialogue = speech
		map._present({"kind": "dialogue", "dialogue": speech})
		check(not map._pending_speech.is_empty() and not map.second_dialogue.visible, "#238: the battle's dialogue waits for the level-up")
		await frames(3)
		check(map.skills != null and map.skills is ELSecondLevelUpView, "#238: the level-up dialog opens first")
		check(not map.second_dialogue.visible, "#238: the dialogue stays closed under the level-up dialog")
		map._close_skills()
		await frames(60)
		check(map.skills == null and map.second_dialogue.visible, "#238: the dialogue opens once the level-up dialog closes")
		director.acknowledge("OK")
		await frames(3)
	_restore(ELSaveSlots.folder("el2"), saves)

func _backup(folder: String) -> Dictionary:
	var files := {}
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder): files[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return files

func _restore(folder: String, files: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file: String in DirAccess.get_files_at(folder):
		if not files.has(file): DirAccess.remove_absolute(folder.path_join(file))
	for file: String in files:
		var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		if out != null: out.store_buffer(files[file])
