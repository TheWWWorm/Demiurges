extends SceneTree
## Headless check of the first game's tutorial gating (ELFirstTutorial) and
## the level-up HeroScreen (ELAdventureView):
## - a fresh profile has the tutorial on; each hint shows once, as its event
##   happens; with the option off nothing is shown or marked; switching it
##   back on replays nothing (only the screen's unseen introduction);
## - a shown hint stays over windows opened after it;
## - a level gained by the player's hero opens the HeroScreen with its skill
##   offers once the map is idle, once per level; a computer hero's level
##   opens nothing.
##
##   godot --headless --path game --script ../tools/first_tutorial_check.gd
##
## The map part needs the first game's files (user://profiles.json, as set up
## by the game); without them it is skipped. Settings are never written, and
## the mission-start autosave the map writes is put back as it was.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_gating()
	await _map_part()
	print("FIRST TUTORIAL: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _fresh_settings() -> ELSettings:
	var settings := ELSettings.new()
	settings.use_edition("el1")
	return settings

func _gating() -> void:
	var settings := _fresh_settings()
	check(settings.values.show_tutorial == true and str(settings.values.tutorial_events) == "", "a fresh profile has the tutorial on and nothing seen")
	ELFirstTutorial.automatic = true
	var tutorial := ELFirstTutorial.new()
	tutorial.settings = settings
	tutorial.persist = false
	tutorial.reload()
	var adventure := ELFirstTutorial.ADVENTURE
	check(tutorial.fire("ADVENTURE_SCREEN", adventure) and tutorial.current_name() == "ADVENTURE_SCREEN", "the first map shows the welcome hint")
	check(not tutorial.fire("ADVENTURE_SCREEN", adventure), "a hint shows only once")
	check(tutorial.fire("HERO_CLICK", adventure) and tutorial.shown_list.size() == 2, "the next event shows its own hint")
	settings.values.show_tutorial = false
	check(not tutorial.fire("LEVEL_UP", adventure) and not tutorial.is_seen(ELFirstTutorial.id_of("LEVEL_UP")), "with the option off a hint is neither shown nor marked seen")
	settings.values.show_tutorial = true
	var before := tutorial.history.duplicate()
	check(not tutorial.resumed(adventure) and tutorial.history == before, "switching the option back on replays nothing already seen on the map")
	check(tutorial.resumed(ELFirstTutorial.COMBAT) and tutorial.current_name() == "COMBAT_SCREEN" and tutorial.shown_list.size() == 1, "in battle it shows only the unseen battle introduction")
	check(tutorial.fire("LEVEL_UP", adventure) and tutorial.current_name() == "LEVEL_UP", "a hint skipped while the option was off shows at its next event")
	check(str(settings.values.tutorial_events).count("1") == 4, "the seen string records each shown hint")
	ELFirstTutorial.automatic = false

func _map_part() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured (user://profiles.json)")
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		return
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	var settings := _fresh_settings()
	ELFirstTutorial.for_settings(settings).persist = false
	ELFirstTutorial.automatic = true
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	_restore(ELSaveSlots.folder("el1"), saves)
	check(built, "the first mission's map builds: " + view.error)
	if not built: return
	await frames(5)
	var panel := view.tutorial_panel
	check(panel.visible and panel.tutorial.current_name() == "ADVENTURE_SCREEN", "a fresh profile sees the welcome hint on the first map")
	# A window opened after the hint stays under it.
	var window := Control.new()
	panel.get_parent().add_child(window)
	await frames(2)
	check(panel.get_index() == panel.get_parent().get_child_count() - 1, "the hint stays over a window opened after it")
	window.queue_free()
	panel.close()
	await frames(2)
	await _free_movement_note(view, profile)

	var state := view.state
	var hero := state.object(view._hero_id())
	var start_level := int(hero.level)
	hero.experience = ELHeroProgression.threshold(profile, start_level + 1) - 1
	view.paused = true
	state.add_experience(int(hero.uid), 20)
	check(int(hero.level) == start_level + 1 and int(hero.skill_points) == 1 and not (hero.skill_offers as Array).is_empty(), "the hero gains a level with skill offers")
	check(panel.visible and panel.tutorial.current_name() == "LEVEL_UP", "the LEVEL_UP hint shows")
	await frames(3)
	check(view.hero_screen == null, "the HeroScreen waits while the map is busy")
	view.paused = false
	await frames(3)
	check(view.hero_screen == null, "the HeroScreen waits for the hint to close")
	panel.close()
	await frames(3)
	check(view.hero_screen != null and view.hero_screen.heroes == [int(hero.uid)] and not view.hero_screen.exchange, "the HeroScreen opens for the hero with its level-up offers")
	if view.hero_screen != null:
		view.hero_screen.closed.emit()
		await frames(5)
	if panel.visible: panel.close()
	await frames(5)
	check(view.hero_screen == null and int(hero.skill_points) == 1, "closing it without a choice keeps the offer and does not reopen")

	var other := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) > 0 and int(item.owner) != state.current_player: other = item
	if other.is_empty():
		print("NOTE: the map has no computer hero; its level-up is checked on the event alone")
		view._note_first_level_up({"id": -7, "levels": 1})
		check(view.first_level_ups.is_empty(), "a level of another player's hero opens nothing")
	else:
		other.experience = ELHeroProgression.threshold(profile, int(other.level) + 1)
		state.add_experience(int(other.uid), 1)
		await frames(3)
		check(view.first_level_ups.is_empty() and view.hero_screen == null, "a computer hero's level opens nothing")
	view.queue_free()
	await frames(2)
	ELFirstTutorial.automatic = false

## The hero orders hint («Управление героями», GitHub #42) ends with the
## remake's note on free movement only where free movement applies.
func _free_movement_note(view: ELAdventureView, profile: ELProfile) -> void:
	var id := ELFirstTutorial.id_of("HERO_CLICK")
	var plain: Dictionary = ELFirstTutorial.texts(profile, id)
	var noted: Dictionary = ELFirstTutorial.texts(profile, id, true)
	var note := ELRemakeText.t(ELFirstTutorial.FREE_MOVEMENT_NOTE, profile)
	check(not plain.body.is_empty() and not plain.body.contains(note), "the hero orders hint has the original text alone without free movement")
	check(noted.body == plain.body + "\n\n" + note, "with free movement it ends with the remake's note")
	var level_up := ELFirstTutorial.id_of("LEVEL_UP")
	check(ELFirstTutorial.texts(profile, level_up, true) == ELFirstTutorial.texts(profile, level_up), "other hints get no note")
	var russian := ELRemakeText.russian(ELFirstTutorial.FREE_MOVEMENT_NOTE)
	check(russian != ELFirstTutorial.FREE_MOVEMENT_NOTE and russian.contains("«Свободное перемещение»") and russian.contains("«Интерфейс»"), "the note has its Russian text, naming the option and its page")
	var panel := view.tutorial_panel
	var kept := [view.director.free_movement, view.state.tutorial]
	# Free movement applies with the option on, outside the tutorial map.
	for case: Array in [[true, false], [false, false], [true, true]]:
		view.director.free_movement = case[0]
		view.state.tutorial = case[1]
		var expected := ELStrategy.free_mode(view.director)
		var shown := panel.tutorial.fire("HERO_CLICK", ELFirstTutorial.ADVENTURE, true)
		if shown: panel.present()
		await frames(1)
		var text := panel.shown_text()
		check(shown and text.ends_with(note) == expected and text.begins_with(plain.body.substr(0, 40)),
			"the map's hint %s the note (option %s%s)" % ["shows" if expected else "leaves out", "on" if case[0] else "off", ", tutorial map" if case[1] else ""])
		panel.close()
		await frames(1)
	view.director.free_movement = kept[0]
	view.state.tutorial = kept[1]
	# Enter presses the panel's check button (GitHub #47).
	if panel.tutorial.fire("HERO_CLICK", ELFirstTutorial.ADVENTURE, true): panel.present()
	await frames(1)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	check(panel.visible and panel.handle_input(enter) and not panel.visible, "Enter closes the hint (its check button)")
	if panel.visible: panel.close()
	await frames(1)

## The mission-start autosave the map writes: kept as it was.
func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder):
		if file.begins_with("auto-t_autosave_start_mission"): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if not file.begins_with("auto-t_autosave_start_mission"): continue
		if kept.has(file):
			var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
			out.store_buffer(kept[file])
		else: DirAccess.remove_absolute(folder.path_join(file))
