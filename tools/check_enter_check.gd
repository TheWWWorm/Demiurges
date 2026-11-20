extends SceneTree
## Headless check of Enter on the check (OK) buttons of both games (GitHub
## #264), with real key events sent through the window:
## - first game, campaign choice: with the hero name field focused (as the
##   screen leaves it), Enter starts the chosen campaign as a click on the
##   check button does, with the button's sound;
## - the rule itself on check plates in canvas layers: Enter and keypad Enter
##   press the shown check button once, key repeats do not; a dialog over a
##   check screen gets Enter alone (and one without a check button, or a
##   disabled one, takes it from the screen below); two check buttons side by
##   side are left alone; a text field with its own submit keeps Enter, one
##   without presses the check button; a multi-line text keeps Enter;
## - second game: Enter starts the chosen campaign; a dialog window dressed
##   with the check plate as its OK is closed by it and the screen below is
##   left alone; on the map the notebook's check button closes it, and the
##   bare map has no check button for Enter;
## - Enter keeps its own meaning: the first game's Load Mission loads the
##   chosen save once; the first game's bare map has no check button for it.
##
##   godot --headless --path game --script ../tools/check_enter_check.gd
##
## It needs the games' files (user://profiles.json); a game without them is
## skipped. Saves the map writes are put back as they were.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 960)
	check(root.get_node_or_null("CheckEnter") is ELCheckEnter, "the Enter listener runs as an autoload")
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary: paths = {}
	var first := _mount(paths, "el1")
	var second := _mount(paths, "el2")
	if first != null:
		await _first_campaigns(first)
		await _layers(first)
		await _load_mission(first)
		await _first_map(first)
	else: print("SKIP: no first-game files")
	if second != null:
		await _second_menu(second)
		await _second_map(second)
	else: print("SKIP: no second-game files")
	print("CHECK ENTER: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _mount(paths: Dictionary, edition: String) -> ELProfile:
	if not paths.has(edition): return null
	var profile := ELProfile.new()
	return profile if profile.mount(edition, str(paths[edition])) else null

# --- Input through the window ---------------------------------------------------------

func _key(code: Key, echo := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.echo = echo and pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await frames(2)

func _click(button: Control) -> void:
	var at := root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size * 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await frames(1)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(1)
	await frames(1)

func _menu(profile: ELProfile, edition: String) -> ELFrontMenu:
	var menu := ELFrontMenu.new()
	menu.settings_path = OS.get_user_data_dir().path_join("check_enter_check_settings.json")
	menu.settings = ELSettings.new()
	menu.settings.use_edition(edition)
	root.add_child(menu)
	check(menu.build({edition: profile}, edition), "the %s menu builds" % edition)
	await frames(2)
	return menu

# --- First game: the campaign choice (the report) -----------------------------------

func _first_campaigns(profile: ELProfile) -> void:
	var menu := await _menu(profile, "el1")
	var results := {}
	for way: String in ["click", "enter", "keypad"]:
		menu.show_screen("new")
		menu.show_screen("campaigns")
		await frames(2)
		menu.cards[1].pressed.emit()
		await frames(2)
		var start: BaseButton = menu.buttons.get("SCStart")
		var field: LineEdit = menu.blazon_ui.name_edit
		check(start != null and start.is_in_group(ELCheckEnter.GROUP) and not start.disabled, "campaign choice (%s): the check button is marked and enabled" % way)
		check(field.is_visible_in_tree() and field.has_focus(), "campaign choice (%s): the hero name field has the focus" % way)
		ELUiSounds.history.clear()
		match way:
			"click": await _click(start)
			"enter": await _key(KEY_ENTER)
			"keypad": await _key(KEY_KP_ENTER)
		results[way] = [menu.screen, menu._legend_next, ELUiSounds.history.duplicate()]
		print("  %s -> %s" % [way, str(results[way])])
	check(results.click[0] == "legend" and results.click[1] == "mission", "campaign choice: a click on the check button opens the campaign's story")
	check(results.enter == results.click, "campaign choice: Enter in the name field does what the click does (screen and sound)")
	check(results.keypad == results.click, "campaign choice: keypad Enter does the same")
	# A repeat of a held Enter starts nothing.
	menu.show_screen("campaigns")
	await frames(2)
	menu.cards[0].pressed.emit()
	await frames(2)
	await _key(KEY_ENTER, true)
	check(menu.screen == "campaigns", "campaign choice: a key repeat does not press the check button")
	menu.queue_free()
	await frames(2)

# --- The rule on canvas layers ---------------------------------------------------------

func _plate(profile: ELProfile, parent: Node, control: String, at: Vector2, presses: Array) -> ELCutPartButton:
	var button := ELCutPartButton.new()
	button.build(profile, control, Rect2(at, Vector2(40, 40)))
	button.position = at
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	button.pressed.connect(func(): presses.append(control + "@" + str(parent.name)))
	return button

func _layer(number: int, name: String) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = number
	layer.name = name + "Layer"
	root.add_child(layer)
	var panel := Control.new()
	panel.name = name
	panel.size = Vector2(root.size)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(panel)
	return panel

func _layers(profile: ELProfile) -> void:
	var presses: Array = []
	var screen := _layer(5, "Screen")
	var ok := _plate(profile, screen, "SBOK", Vector2(600, 600), presses)
	var back := _plate(profile, screen, "SBCancel", Vector2(500, 600), presses)
	check(ok.is_in_group(ELCheckEnter.GROUP) and not back.is_in_group(ELCheckEnter.GROUP), "layers: the check plate is marked, the cancel plate is not")
	await frames(1)
	ELUiSounds.history.clear()
	await _key(KEY_ENTER)
	check(presses == ["SBOK@Screen"], "layers: Enter presses the screen's check button once: %s" % str(presses))
	check(ELUiSounds.history.size() == 1, "layers: with its click sound: %s" % str(ELUiSounds.history))
	presses.clear()
	await _key(KEY_KP_ENTER)
	check(presses == ["SBOK@Screen"], "layers: keypad Enter too")
	presses.clear()
	await _key(KEY_ENTER, true)
	check(presses.is_empty(), "layers: a key repeat presses nothing")
	ok.disabled = true
	await _key(KEY_ENTER)
	check(presses.is_empty(), "layers: a disabled check button is not pressed")
	ok.disabled = false

	# A dialog over the screen: only its own check button answers.
	var dialog := _layer(6, "Dialog")
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.size = Vector2(root.size)
	dialog.add_child(backdrop)
	var dialog_ok := _plate(profile, dialog, "MBOK", Vector2(300, 300), presses)
	await frames(1)
	await _key(KEY_ENTER)
	check(presses == ["MBOK@Dialog"], "dialog over a check screen: only the dialog's check button is pressed: %s" % str(presses))
	presses.clear()
	dialog_ok.disabled = true
	await _key(KEY_ENTER)
	check(presses.is_empty(), "dialog over a check screen: its disabled check button keeps Enter from the screen below")
	dialog_ok.queue_free()
	await frames(1)
	await _key(KEY_ENTER)
	check(presses.is_empty(), "dialog without a check button over a check screen: nothing is pressed")
	# Two check buttons side by side on the topmost panel: no guess.
	_plate(profile, dialog, "MBOK", Vector2(200, 300), presses)
	_plate(profile, dialog, "SBOK", Vector2(400, 300), presses)
	await frames(1)
	await _key(KEY_ENTER)
	check(presses.is_empty(), "two check buttons on the topmost panel: neither is pressed")
	dialog.get_parent().queue_free()
	await frames(1)

	# Text fields on the screen.
	var own := LineEdit.new()
	own.position = Vector2(100, 100)
	own.size = Vector2(200, 30)
	screen.add_child(own)
	var submitted: Array = []
	own.text_submitted.connect(func(value: String): submitted.append(value))
	own.text = "own"
	own.grab_focus()
	await frames(1)
	await _key(KEY_ENTER)
	check(submitted == ["own"] and presses.is_empty(), "a field with its own submit keeps Enter: %s %s" % [str(submitted), str(presses)])
	var plain := LineEdit.new()
	plain.position = Vector2(100, 150)
	plain.size = Vector2(200, 30)
	screen.add_child(plain)
	plain.grab_focus()
	await frames(1)
	await _key(KEY_ENTER)
	check(presses == ["SBOK@Screen"], "a field without a submit of its own: Enter presses the check button once: %s" % str(presses))
	presses.clear()
	# A field taken out and put back still presses it once.
	screen.remove_child(plain)
	screen.add_child(plain)
	plain.grab_focus()
	await frames(1)
	await _key(KEY_ENTER)
	check(presses == ["SBOK@Screen"], "a field put back into the tree still presses the check button once: %s" % str(presses))
	presses.clear()
	plain.grab_focus()
	await _key(KEY_ENTER, true)
	check(presses.is_empty(), "a field without a submit: a key repeat presses nothing")
	var notes := TextEdit.new()
	notes.position = Vector2(100, 200)
	notes.size = Vector2(200, 80)
	screen.add_child(notes)
	notes.grab_focus()
	await frames(1)
	await _key(KEY_ENTER)
	check(presses.is_empty() and notes.get_line_count() == 2, "a multi-line text keeps Enter for a new line")
	screen.get_parent().queue_free()
	await frames(2)

# --- Enter that already means something ------------------------------------------------

func _load_mission(profile: ELProfile) -> void:
	var menu := await _menu(profile, "el1")
	menu.mission_load_ui.prepare("load", ELSaveSlots.KIND_SINGLE)
	menu.show_screen("load_mission")
	await frames(1)
	var ui := menu.mission_load_ui
	ui.entries.assign([{"name": "check", "path": "user://check_enter_check.sav", "type": ELSaveSlots.SLOT, "modified": 0, "edition": "el1"}])
	ui.selected = -1
	ui.refresh()
	ui.choose_row(0)
	var loads: Array = []
	for connection: Dictionary in menu.single_load_requested.get_connections(): menu.single_load_requested.disconnect(connection.callable)
	menu.single_load_requested.connect(func(): loads.append(ELSingleScenario.SAVE))
	var kept := ELSingleScenario.SAVE
	await _key(KEY_ENTER)
	check(loads == ["user://check_enter_check.sav"], "Load Mission keeps its Enter: the chosen save is loaded once: %s" % str(loads))
	ELSingleScenario.SAVE = kept
	menu.queue_free()
	await frames(2)

# --- First game: the map --------------------------------------------------------------

func _first_map(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[mini(1, campaign.scenarios.size() - 1)].duplicate()
	row.campaign = "Good"
	var saves := _backup(ELSaveSlots.folder("el1"))
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	check(built, "first game: a mission map builds: " + view.error)
	if built:
		await frames(5)
		if view.tutorial_panel != null and view.tutorial_panel.visible: view.tutorial_panel.close()
		await frames(2)
		check(ELCheckEnter.target(root) == null, "first game: the bare map has no check button for Enter")
		var day := view.state.day if "day" in view.state else -1
		await _key(KEY_ENTER)
		check(view.hero_screen == null and view.spellbook == null and (view.state.day if "day" in view.state else -1) == day, "first game: Enter on the bare map opens and ends nothing")
	view.queue_free()
	await frames(2)
	_restore(ELSaveSlots.folder("el1"), saves)

# --- Second game -------------------------------------------------------------------------

func _second_menu(profile: ELProfile) -> void:
	var menu := await _menu(profile, "el2")
	menu.show_screen("campaign_menu")
	menu.show_screen("campaigns")
	await frames(2)
	menu.cards[0].pressed.emit()
	await frames(2)
	var start: BaseButton = menu.buttons.get("SCStart")
	check(start != null and start.is_in_group(ELCheckEnter.GROUP) and not start.disabled, "second game, campaign choice: the check button is marked and enabled")

	# A dressed dialog window (its OK is the check plate) over the screen.
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "check"
	root.add_child(dialog)
	var kit := ELMenuKit.for_profile(profile)
	check(kit.dress_dialog(dialog, "OK", str(kit.art.get("close", ""))), "second game: a dialog is dressed in the menu kit with the check plate as its OK")
	check(dialog.get_ok_button().is_in_group(ELCheckEnter.GROUP), "second game: the dialog's OK plate is a check button")
	var confirmed: Array = []
	dialog.confirmed.connect(func(): confirmed.append(true))
	dialog.popup_centered()
	await frames(2)
	check(dialog.get_node_or_null("CheckEnter") != null, "second game: the dialog window listens for Enter")
	# Not focused, so it is the listener (not the focused button) that answers.
	dialog.get_ok_button().release_focus()
	ELUiSounds.history.clear()
	await _key(KEY_ENTER)
	check(confirmed == [true] and not dialog.visible, "second game: Enter presses the dialog's check button")
	check(ELUiSounds.history.size() == 1, "second game: with its sound: %s" % str(ELUiSounds.history))
	check(menu.screen == "campaigns", "second game: the check button of the screen below is not pressed")
	dialog.queue_free()
	await frames(2)
	await _key(KEY_ENTER)
	check(menu.screen == "map", "second game: with the dialog gone, Enter starts the chosen campaign (map: %s)" % menu.screen)
	menu.queue_free()
	await frames(2)

func _second_map(profile: ELProfile) -> void:
	var saves := _backup(ELSaveSlots.folder("el2"))
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, {"file_name": "e2mission11"}, settings, 1)
	check(built, "second game: the Vitals map builds: %s" % view.error)
	if built:
		for hook: String in ["Hook_Wake", "Hook_OnStep"]: view.state.vm.bind(hook, func(_args: Array) -> Array: return [])
		if view._mission_fade != null: await view._mission_fade.tree_exited
		await frames(3)
		for attempt in 20:
			if view.director.dialogue.is_empty(): break
			view.director.acknowledge()
			await frames(2)
		check(ELCheckEnter.target(root) == null, "second game: the bare map has no check button for Enter")
		view.open_notebook()
		await frames(2)
		check(view.notebook != null, "second game: the notebook opens")
		if view.notebook != null:
			check(ELCheckEnter.target(root) == view.notebook.buttons.NotebookOkBtn, "second game: the notebook's check button is the one for Enter")
			await _key(KEY_ENTER)
			check(view.notebook == null, "second game: Enter closes the notebook as its check button does")
	view.queue_free()
	await frames(2)
	_restore(ELSaveSlots.folder("el2"), saves)

func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if not kept.has(file):
			DirAccess.remove_absolute(folder.path_join(file))
		elif FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
			var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
			out.store_buffer(kept[file])
