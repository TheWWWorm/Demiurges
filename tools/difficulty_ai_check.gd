extends SceneTree
## Headless check that each campaign and single scenario keeps its own
## computer players' strength (ELAIChoice), set by its difficulty:
## - the defaults: the lowest difficulty of both games gives the original duel
##   opponent and the original map players, the others the Options choices;
## - a new map takes the levels its chapter row brings, else its difficulty's;
## - the levels survive a save and its load; a save from before them gets
##   the lowest difficulty's originals, at another difficulty the Options
##   choices; a broken value is refused;
## - the campaign setup panel and the front menu reset the dropdowns when the
##   difficulty changes, keep a manual change, hand the shown levels to the
##   chapter row and leave the Options choices alone;
## - a chapter's end carries them to the next chapter (first game: the next
##   rows and a branch choice; second game: the campaign progress and its
##   between-chapter autosave, old progress without them still valid);
## - the map players' switches and the duel level follow the game, a network
##   game and a duel without a game the Options choices.
##
##   godot --headless --path game --script ../tools/difficulty_ai_check.gd
##
## The map parts need the games' files (user://profiles.json); without them
## they are skipped. Settings files are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_defaults()
	_progress()
	_front_menu()
	var profiles := _profiles()
	for id: String in ["el1", "el2"]:
		if profiles.has(id): _maps(profiles[id])
		else: print("SKIP: %s map checks (no game files)" % id)
	if not profiles.is_empty(): _setup_panel(profiles)
	else: print("SKIP: campaign setup panel (no game files)")
	if profiles.has("el1"): await _menu_screens(profiles.el1)
	else: print("SKIP: front menu screens (no first game files)")
	for profile: ELProfile in profiles.values():
		if profile.metal_masks != null: profile.metal_masks.stop()
	print("DIFFICULTY AI: %d failure(s)" % failures.size())
	quit(1 if failures.size() > 0 else 0)

func _profiles() -> Dictionary:
	var result := {}
	if not FileAccess.file_exists("user://profiles.json"): return result
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if saved is not Dictionary: return result
	for id: String in ["el1", "el2"]:
		var folder := String(saved.get(id, ""))
		var profile := ELProfile.new()
		if not folder.is_empty() and profile.mount(id, folder): result[id] = profile
	return result

## Options choices that differ from every difficulty default.
func _odd_settings() -> ELSettings:
	var settings := ELSettings.new()
	settings.values.duel_ai = 0
	settings.values.world_ai = 2
	return settings

func _levels(duel: int, world: int) -> Dictionary:
	return {"duel_ai": duel, "world_ai": world}

func _defaults() -> void:
	var fresh := ELSettings.new()
	for edition: String in ["el1", "el2"]:
		var count := 5 if edition == "el1" else ELSecondCampaign.DIFFICULTIES
		for difficulty in count:
			var expected := _levels(1, 0) if difficulty == 0 else _levels(2, 1)
			check(ELAIChoice.defaults(difficulty, fresh) == expected, "%s difficulty %d defaults to %s" % [edition, difficulty, expected])
	var odd := _odd_settings()
	check(ELAIChoice.defaults(0, odd) == _levels(1, 0), "the lowest difficulty ignores the Options choices")
	check(ELAIChoice.defaults(2, odd) == _levels(0, 2), "another difficulty takes the Options choices")
	check(ELAIChoice.defaults(1, null) == _levels(2, 1), "without preferences: the smarter levels")
	check(ELAIChoice.valid(_levels(0, 2)) and not ELAIChoice.valid(_levels(3, 0)) and not ELAIChoice.valid({"duel_ai": 1}) and not ELAIChoice.valid({"duel_ai": 1.5, "world_ai": 0}) and not ELAIChoice.valid("x"), "levels are validated")
	check(ELAIChoice.from_scenario({"ai": {"duel_ai": 2.0, "world_ai": 0.0}}) == _levels(2, 0), "a chapter row's levels are read as integers")
	check(ELAIChoice.from_scenario({ELSecondCampaign.KEY: {"ai": _levels(0, 1)}}) == _levels(0, 1), "a second-game row brings its progress' levels")
	check(ELAIChoice.from_scenario({"ai": _levels(5, 0)}).is_empty() and ELAIChoice.from_scenario({}).is_empty(), "a row with none or broken ones brings none")

func _progress() -> void:
	var data := ELSecondCampaign.new_game(0)
	ELSecondCampaign.begin(data, "Green")
	check(ELSecondCampaign.valid(data), "second game: progress without levels (older autosaves) is valid")
	var state := ELAdventureSession.new()
	state.duel_ai = 0
	state.world_ai = 2
	ELAIChoice.carry_progress(state, data)
	check(ELSecondCampaign.valid(data) and data.get("ai") == _levels(0, 2), "second game: a chapter's end puts the game's levels in the progress")
	var path := "user://difficulty_ai_check.json"
	check(ELSecondCampaign.write(path, data), "second game: the progress with levels is autosaved")
	var read := ELSecondCampaign.read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(read.get("ai") == _levels(0, 2) and typeof(read.ai.duel_ai) == TYPE_INT, "second game: the between-chapter autosave keeps the levels")
	var broken := data.duplicate(true)
	broken.ai = {"duel_ai": 9, "world_ai": 0}
	check(not ELSecondCampaign.valid(broken), "second game: progress with broken levels is refused")
	var rows := ELAIChoice.carry_rows(state, [{"file_name": "a"}, {"file_name": "b"}])
	check(rows.size() == 2 and rows.all(func(row: Dictionary) -> bool: return row.get("ai") == _levels(0, 2)), "first game: the next chapter rows (and both of a branch choice) carry the levels")
	check(ELAIChoice.carry_rows(ELAdventureSession.new(), [{"file_name": "a"}])[0].has("ai") == false, "a game without levels carries none")

func _front_menu() -> void:
	var menu := ELFrontMenu.new()
	menu.edition = "el1"
	menu.settings = _odd_settings()
	menu.difficulty = 1
	check(menu.with_ai({"file_name": "x"}).get("ai") == _levels(0, 2), "front menu: a game begun at Normal takes the Options choices")
	menu.set_difficulty(0)
	check(menu.ai_levels == _levels(1, 0), "front menu: choosing the lowest difficulty shows the originals")
	menu.ai_levels.duel_ai = 2
	check(menu.with_ai({"file_name": "x"}).get("ai") == _levels(2, 0), "front menu: a manual change goes with the chapter row")
	menu.set_difficulty(3)
	check(menu.ai_levels == _levels(0, 2), "front menu: another difficulty puts its levels back")
	menu.use_ai(_levels(1, 1))
	check(menu.with_ai({}).get("ai") == _levels(1, 1), "front menu: a chapter's carried levels are shown")
	check(int(menu.settings.values.duel_ai) == 0 and int(menu.settings.values.world_ai) == 2, "front menu: the Options choices are unchanged")
	menu.free()

func _setup_panel(profiles: Dictionary) -> void:
	var panel := ELCampaignSetup.new()
	var settings := _odd_settings()
	panel.settings = settings
	get_root().add_child(panel)
	panel.build(profiles, "el1" if profiles.has("el1") else "el2")
	var duel: OptionButton = panel.ai_picks.get("duel_ai")
	var world: OptionButton = panel.ai_picks.get("world_ai")
	check(duel != null and world != null, "setup panel: both dropdowns are shown")
	if duel == null or world == null:
		panel.free()
		return
	check(panel.difficulty.selected == 1 and duel.selected == 0 and world.selected == 2, "setup panel: Normal shows the Options choices")
	panel.difficulty.select(0)
	panel.difficulty.item_selected.emit(0)
	check(duel.selected == 1 and world.selected == 0 and panel.ai_levels == _levels(1, 0), "setup panel: the lowest difficulty resets the dropdowns to the originals")
	duel.select(2)
	duel.item_selected.emit(2)
	check(panel.ai_levels == _levels(2, 0), "setup panel: a manual change sticks")
	var begun := []
	panel.begin.connect(func(_edition: String, row: Dictionary, difficulty: int): begun.append([row, difficulty]))
	panel.chapter.select(0)
	for button: Node in panel.find_children("*", "Button", true, false):
		if button is Button and not button is OptionButton and (button as Button).text == "Begin chapter": (button as Button).pressed.emit()
	check(begun.size() == 1 and Dictionary(begun[0][0]).get("ai") == _levels(2, 0) and int(begun[0][1]) == 0, "setup panel: Begin hands the shown levels to the chapter row: %s" % [begun])
	panel.difficulty.select(2)
	panel.difficulty.item_selected.emit(2)
	check(duel.selected == 0 and world.selected == 2, "setup panel: another difficulty puts the Options choices back")
	check(int(settings.values.duel_ai) == 0 and int(settings.values.world_ai) == 2, "setup panel: the Options choices are unchanged")
	panel.free()

## The first game's real Single and campaign info screens: the strip of
## dropdowns follows the difficulty radios and a chapter's carried levels, and
## Start hands the shown levels on.
func _menu_screens(profile: ELProfile) -> void:
	var menu := ELFrontMenu.new()
	menu.settings = _odd_settings()
	menu.settings_path = "user://difficulty_ai_check_unused.json"
	get_root().add_child(menu)
	if not menu.build({"el1": profile}, "el1"):
		check(false, "front menu: the first game's menu builds")
		menu.queue_free()
		return
	await process_frame
	menu.show_screen("new")
	menu.difficulty = 1
	menu.show_screen("single")
	var shown := func() -> Array:
		var strip: Variant = menu.labels.get("ai_choices")
		if not strip is Control or not is_instance_valid(strip): return []
		var result := []
		for pick: Node in (strip as Control).find_children("*", "OptionButton", true, false): result.append((pick as OptionButton).selected)
		return result
	check(shown.call() == [0, 2], "Single screen at Normal shows the Options choices: %s" % [shown.call()])
	menu.single_ui.set_difficulty(0)
	check(shown.call() == [1, 0], "Single screen: the lowest difficulty radio shows the originals: %s" % [shown.call()])
	menu.show_screen("new")
	check(menu.ai_levels.is_empty(), "front menu: leaving the screens forgets the levels")
	var row := _chapter(profile)
	if not row.is_empty():
		var carried := row.duplicate()
		carried.ai = _levels(2, 0)
		check(menu.show_chapter_info(carried, 0), "campaign info screen opens for a chapter")
		check(shown.call() == [2, 0], "campaign info screen: a chapter's carried levels are shown at the lowest difficulty: %s" % [shown.call()])
		for pick: OptionButton in menu.labels.ai_choices.find_children("*", "OptionButton", true, false):
			var arrow_space := pick.get_theme_icon("arrow").get_width() + maxi(0, pick.get_theme_constant("h_separation"))
			var centered := pick.alignment == HORIZONTAL_ALIGNMENT_CENTER
			for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var plate := pick.get_theme_stylebox(state)
				centered = centered and is_equal_approx(plate.get_margin(SIDE_LEFT), plate.get_margin(SIDE_RIGHT) + arrow_space)
			check(centered, "campaign info screen: %s caption is centred in every button state" % pick.name)
		var begun := []
		menu.campaign_requested.connect(func(_edition: String, scenario: Dictionary, difficulty: int): begun.append([scenario.get("ai"), difficulty]))
		menu.start_campaign()
		check(begun.size() == 1 and begun[0][0] == _levels(2, 0), "campaign info screen: Start hands the carried levels on: %s" % [begun])
		menu.set_difficulty(2)
		check(shown.call() == [0, 2], "campaign info screen: another difficulty puts its levels back: %s" % [shown.call()])
	menu.queue_free()
	await process_frame

## A real chapter of `profile`'s first campaign.
func _chapter(profile: ELProfile) -> Dictionary:
	for id: String in ELCampaign.available(profile):
		var data := ELCampaign.new()
		if data.load_campaign(profile, id) and not data.scenarios.is_empty():
			var row: Dictionary = data.scenarios[0].duplicate()
			row.campaign = id
			return row
	return {}

func _session(profile: ELProfile, row: Dictionary, difficulty: int) -> Array:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, str(row.file_name)): return []
	var state := ELAdventureSession.new()
	if not state.start(map, difficulty, 212, str(row.get("script", "")), int(str(row.get("player", "1"))), row.has("number")): return []
	var director := ELAdventureDirector.new()
	if not director.build(state): return []
	return [state, director]

func _round_trip(director: ELAdventureDirector, edit := Callable()) -> Dictionary:
	var codec := ELAdventureSave.new()
	var document := codec.encode(director, {})
	if document.is_empty():
		print("  encode: " + codec.error)
		return {}
	var raw: Variant = JSON.parse_string(JSON.stringify(document, "", true, true))
	if edit.is_valid(): edit.call(raw)
	var restored := codec.decode(raw, {director.state.map.profile.id: director.state.map.profile})
	if restored.is_empty(): print("  decode: " + codec.error)
	return restored

func _maps(profile: ELProfile) -> void:
	var edition := profile.id
	var row := _chapter(profile)
	check(not row.is_empty(), "%s: a campaign chapter is found" % edition)
	if row.is_empty(): return
	var odd := _odd_settings()
	var top := 4 if edition == "el1" else ELSecondCampaign.DIFFICULTIES - 1
	# A new game: the chosen levels, else the difficulty's.
	var chosen := row.duplicate()
	chosen.ai = _levels(0, 2)
	var built := _session(profile, chosen, 0)
	check(not built.is_empty(), "%s: the chapter starts" % edition)
	if built.is_empty(): return
	var state: ELAdventureSession = built[0]
	var director: ELAdventureDirector = built[1]
	check(ELAIChoice.of(state).is_empty(), "%s: a new session has no levels before the view sets them" % edition)
	ELAIChoice.adopt(state, chosen, odd)
	check(ELAIChoice.of(state) == _levels(0, 2), "%s: a new game at the lowest difficulty stores the levels chosen on its screen" % edition)
	# Save and load keep them.
	var restored := _round_trip(director)
	check(not restored.is_empty() and ELAIChoice.of(restored.state) == _levels(0, 2), "%s: save and load keep the game's levels" % edition)
	if not restored.is_empty():
		ELAIChoice.adopt(restored.state, {}, ELSettings.new())
		check(ELAIChoice.of(restored.state) == _levels(0, 2), "%s: a loaded game keeps its own levels over the defaults" % edition)
		restored.state.close()
	# A save from before games kept their levels, at the lowest difficulty.
	var old := _round_trip(director, func(raw: Dictionary): raw.world.erase("ai"))
	check(not old.is_empty() and ELAIChoice.of(old.state).is_empty(), "%s: a save without levels still loads" % edition)
	if not old.is_empty():
		ELAIChoice.adopt(old.state, {"file_name": row.file_name}, odd)
		check(ELAIChoice.of(old.state) == _levels(1, 0), "%s: an old save at the lowest difficulty plays the originals" % edition)
		old.state.close()
	var broken := _round_trip(director, func(raw: Dictionary): raw.world.ai = {"duel_ai": 7, "world_ai": 0})
	check(broken.is_empty(), "%s: a save with broken levels is refused" % edition)
	# The director's switches follow the game.
	ELAIChoice.apply_world(director, odd)
	check(director.smart_ai and director.living_world, "%s: the game's living world turns both map switches on" % edition)
	state.world_ai = 0
	ELAIChoice.apply_world(director, odd)
	check(not director.smart_ai and not director.living_world, "%s: the game's original map players turn them off" % edition)
	state.world_ai = 1
	ELAIChoice.apply_world(director, odd)
	check(director.smart_ai and not director.living_world, "%s: the game's smarter map players" % edition)
	ELAIChoice.apply_world(director, odd, true)
	check(director.smart_ai and director.living_world, "%s: a network game uses the Options choice" % edition)
	check(ELAIChoice.duel_level(state, odd) == 0 and ELAIChoice.duel_level(null, odd) == 0, "%s: the duel level (game's 0, Options 0)" % edition)
	state.duel_ai = 2
	check(ELAIChoice.duel_level(state, odd) == 2 and ELAIChoice.duel_level(null, ELSettings.new()) == 2, "%s: a game's battle uses its level, a duel without one the Options choice" % edition)
	state.close()
	# An old save at another difficulty: the Options choices.
	var higher := _session(profile, row, top)
	check(not higher.is_empty(), "%s: the chapter starts at difficulty %d" % [edition, top])
	if higher.is_empty(): return
	var high_old := _round_trip(higher[1], func(raw: Dictionary): raw.world.erase("ai"))
	if not high_old.is_empty():
		ELAIChoice.adopt(high_old.state, {}, odd)
		check(ELAIChoice.of(high_old.state) == _levels(0, 2), "%s: an old save at difficulty %d takes the Options choices" % [edition, top])
		high_old.state.close()
	else: check(false, "%s: an old save at difficulty %d loads" % [edition, top])
	# A new game without chosen levels (a path with no dropdowns).
	ELAIChoice.adopt(higher[0], row, ELSettings.new())
	check(ELAIChoice.of(higher[0]) == _levels(2, 1), "%s: a new game at difficulty %d without a choice takes the smarter defaults" % [edition, top])
	# The next chapter starts with the carried levels.
	higher[0].duel_ai = 1
	higher[0].world_ai = 2
	var next_rows := ELAIChoice.carry_rows(higher[0], [row])
	higher[0].close()
	var next := _session(profile, next_rows[0], top)
	if not next.is_empty():
		ELAIChoice.adopt(next[0], next_rows[0], ELSettings.new())
		check(ELAIChoice.of(next[0]) == _levels(1, 2), "%s: the next chapter keeps the game's levels" % edition)
		next[0].close()
	if edition == "el2":
		var progress := ELSecondCampaign.for_chapter(profile, str(row.campaign), row, 0)
		progress.ai = _levels(2, 0)
		var chapter_row := ELSecondCampaign.chapter(profile, progress)
		var carried := _session(profile, chapter_row, 0)
		if not carried.is_empty():
			ELAIChoice.adopt(carried[0], chapter_row, ELSettings.new())
			check(ELAIChoice.of(carried[0]) == _levels(2, 0), "el2: a chapter opened from the campaign progress takes its levels")
			carried[0].close()
		else: check(false, "el2: the chapter opens from the campaign progress")
