extends SceneTree
## Headless check of Enter on the first game's menu screens (GitHub #47):
## - Load Mission: Enter loads the chosen save (the check button), Esc closes;
##   with no save chosen, Enter does nothing;
## - Options: Enter presses OK (the settings are written to a scratch file);
## - a screen without a check button ignores Enter.
##
##   godot --headless --path game --script ../tools/dialog_enter_check.gd
##
## It needs the first game's files (user://profiles.json, as set up by the
## game); without them it is skipped. The player's settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _menu_part()
	print("DIALOG ENTER: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _menu_part() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured (user://profiles.json)")
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		return
	var menu := ELFrontMenu.new()
	menu.settings_path = OS.get_user_data_dir().path_join("dialog_enter_check_settings.json")
	menu.settings = ELSettings.new()
	menu.settings.use_edition("el1")
	root.add_child(menu)
	check(menu.build({"el1": profile}, "el1"), "the first game's menu builds")
	await frames(2)

	# Load Mission with one save row (nothing is really loaded).
	menu.mission_load_ui.prepare("load", ELSaveSlots.KIND_SINGLE)
	menu.show_screen("load_mission")
	await frames(1)
	var ui := menu.mission_load_ui
	ui.entries.assign([{"name": "check", "path": "user://dialog_enter_check.sav", "type": ELSaveSlots.SLOT, "modified": 0, "edition": "el1"}])
	ui.selected = -1
	ui.refresh()
	var loads: Array = []
	for connection: Dictionary in menu.single_load_requested.get_connections(): menu.single_load_requested.disconnect(connection.callable)
	menu.single_load_requested.connect(func(): loads.append(ELSingleScenario.SAVE))
	var kept_save := ELSingleScenario.SAVE
	menu._input(_key(KEY_ENTER))
	check(loads.is_empty(), "Load Mission: Enter with no save chosen loads nothing")
	ui.choose_row(0)
	menu._input(_key(KEY_ENTER))
	check(loads == ["user://dialog_enter_check.sav"], "Load Mission: Enter presses the check button and loads the chosen save")
	loads.clear()
	menu._input(_key(KEY_KP_ENTER))
	check(loads.size() == 1, "Load Mission: keypad Enter does the same")
	ELSingleScenario.SAVE = kept_save
	menu._input(_key(KEY_ESCAPE))
	check(menu.screen != "load_mission", "Load Mission: Esc presses X (back)")

	# Options: Enter is OK.
	menu.options_ui.open("menu")
	await frames(1)
	check(menu.screen == "options", "Options opens")
	var closed: Array = []
	menu.options_closed.connect(func(applied: bool, _command: String): closed.append(applied))
	menu._input(_key(KEY_ENTER))
	await frames(1)
	check(closed == [true] and menu.screen != "options", "Options: Enter presses the check button (OK)")
	if FileAccess.file_exists(menu.settings_path): DirAccess.remove_absolute(menu.settings_path)

	# The main menu has no check button.
	menu.show_screen("main")
	await frames(1)
	check(not menu.press_default(), "the main menu has no check button for Enter")
	menu.queue_free()
	await frames(2)
