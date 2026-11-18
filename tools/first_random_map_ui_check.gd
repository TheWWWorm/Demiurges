extends SceneTree
## Setup-screen checks using synthetic first-game content. Pass
## -- --el1=/path/to/Etherlords to check the installed mission selection too.
## godot --headless --path game --script ../tools/first_random_map_ui_check.gd
## Use an isolated XDG_DATA_HOME: this checks the remembered setup on launch.

const Fixture := preload("first_random_map_fixture.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _frames(count := 4) -> void:
	for i in count: await process_frame

func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1000, 740)
	var profile: ELProfile = Fixture.profile()
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		ELRemakeText.use(profile)
		for scale: Vector2i in [Vector2i.ZERO, Vector2i(1440, 900)]:
			await _first_open_bounds(profile, language, scale)
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1000, 740)
		var screen := ELFirstRandomMapScreen.new()
		root.add_child(screen)
		screen.build(profile, 2, {"duel_ai": 2, "world_ai": 2})
		screen.configuration = ELFirstRandomMap.defaults()
		screen.configuration.merge({"seed": "ui-check-" + language, "size": 64, "players": 2}, true)
		screen._sync_fields()
		screen.popup_centered_clamped(Vector2i(920, 680), 0.94)
		await _frames()
		check(ELFirstRandomMap.normalize(screen.options()) == screen.configuration, language + ": fields reproduce the recipe")
		check(screen._presets.item_count >= 4, language + ": usable preset choices")
		for index in range(1, screen._presets.item_count):
			screen._preset_selected(index)
			check(not ELFirstRandomMap.normalize(screen.options()).is_empty(), language + ": preset %d normalizes" % index)
		check(screen._seed.text == "ui-check-" + language, language + ": presets retain the chosen seed")
		screen.configuration = ELFirstRandomMap.defaults()
		screen.configuration.merge({"seed": "ui-check-" + language, "size": 64, "players": 2, "faction": "Blue", "layout": "archipelago", "naval": true, "water": "normal", "coast": "rugged"}, true)
		screen._sync_fields()
		var before := screen.options()
		screen.copy_setup()
		var code := screen._code.text
		check(code.begins_with(ELFirstRandomMapScreen.CODE_PREFIX), language + ": copy produces versioned setup code")
		screen._seed.text = "changed"
		screen._code.text = code
		screen.load_setup()
		check(screen.options() == before, language + ": setup code round-trips all settings")
		check(screen.options().naval == true and screen.options().water == "normal" and screen.options().coast == "rugged", language + ": naval and coastal controls survive sharing")
		screen._code.text = "not a configuration"
		screen.load_setup()
		check(screen.options() == before, language + ": bad setup leaves fields untouched")
		for version: int in [1, 2, 3, 4]:
			var legacy := ELFirstRandomMap.defaults(version)
			legacy.seed = "old-shape-recipe"
			var prefix := "EL1R%d:" % version
			screen._code.text = prefix + Marshalls.utf8_to_base64(JSON.stringify(legacy))
			screen.load_setup()
			check(screen.options() == legacy, language + ": loading an old code preserves its exact generator version and recipe")
			screen.copy_setup()
			check(screen._code.text.begins_with(prefix), language + ": unchanged legacy recipes retain their sharing prefix")
		screen._seed.text = "edited-old-shape"
		screen._changed()
		check(int(screen.options().version) == 5 and screen.options().has("naval"), language + ": editing a legacy recipe explicitly moves it to the current version")
		screen._code.text = code
		screen.load_setup()
		var built: bool = await screen.generate_preview()
		check(built and screen.preview_map != null and screen._preview.texture != null, language + ": real generated preview is available")
		if built:
			check(screen.preview_map.players.size() == 2, language + ": preview matches player count")
			check(ELFirstRandomMap.configuration(screen.preview_map) == before, language + ": preview matches exact recipe")
		# Keep the narrow supported game window usable in both languages.
		root.size = Vector2i(800, 600)
		screen.size = Vector2i(740, 550)
		await _frames()
		check(screen.size.x <= 800 and screen.size.y <= 600, language + ": dialog fits the minimum game window")
		var bounds := Rect2(Vector2.ZERO, Vector2(screen.size))
		for button: Button in [screen._generate, screen._play]:
			check(bounds.encloses(button.get_global_rect()), language + ": action remains inside dialog: " + button.name)
		check(screen._preview.size.x > 100 and screen._preview.size.y > 100, language + ": map preview remains useful at 800 by 600")
		screen._changed()
		check(screen.preview_map == null, language + ": changed settings invalidate the old preview")
		var captured: Array = []
		screen.requested.connect(func(config: Dictionary, level: int, ai: Dictionary): captured.append([config, level, ai]))
		screen._start()
		screen.hide()
		await _frames()
		check(captured.is_empty() and screen.preview_map == null, language + ": closing during queued generation cancels launch")
		screen.popup_centered_clamped(Vector2i(740, 550), 0.94)
		await screen._start()
		check(captured.size() == 1, language + ": start emits one game request")
		if not captured.is_empty():
			check(captured[0][0] == before and captured[0][1] == 2 and captured[0][2].world_ai == 2, language + ": launch carries the checked map and AI options")
		check(not screen.visible, language + ": setup closes after launching")
		screen.queue_free()
		await _frames()
		root.size = Vector2i(1000, 740)
	OS.unset_environment("DEMIURGES_LANGUAGE")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--el1="): await _installed_entry(argument.trim_prefix("--el1="))
	ELRemakeText.release()
	print("FIRST RANDOM MAP UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _first_open_bounds(profile: ELProfile, language: String, scale: Vector2i) -> void:
	root.size = Vector2i(800, 600)
	root.content_scale_size = scale
	await _frames()
	var screen := ELFirstRandomMapScreen.new()
	root.add_child(screen)
	screen.build(profile, 2, {"duel_ai": 2, "world_ai": 2})
	screen.popup_centered_clamped(Vector2i(920, 680), 0.94)
	# This is the first opening: no assignment to screen.size is allowed
	# before these assertions, which catch transient autowrap minimum sizes.
	await _frames(8)
	var label := "%s first opening, content scale%s" % [language, scale]
	var viewport := root.get_visible_rect()
	var popup := Rect2(Vector2(screen.position), Vector2(screen.size))
	check(screen.visible and viewport.encloses(popup), label + ": the entire dialog is on screen (popup=%s, viewport=%s)" % [popup, viewport])
	var bounds := Rect2(Vector2.ZERO, Vector2(screen.size))
	for button: Button in [screen._generate, screen._play]:
		check(bounds.encloses(button.get_global_rect()), label + ": action is visible without manual resizing: " + button.name)
	check(bounds.encloses(screen._preview.get_global_rect()) and screen._preview.size.x > 100 and screen._preview.size.y > 100, label + ": preview is visible at the initial size")
	check(bounds.encloses(screen._code.get_global_rect()), label + ": sharing controls are visible at the initial size")
	screen.queue_free()
	await _frames()

func _installed_entry(folder: String) -> void:
	var profile := ELProfile.new()
	var mounted := profile.mount("el1", folder)
	check(mounted, "installed menu content mounts: " + profile.error)
	if not mounted: return
	ELRemakeText.use(profile)
	var menu := ELFrontMenu.new()
	root.add_child(menu)
	var built := menu.build({"el1": profile}, "el1")
	check(built, "the installed first-game menu builds")
	if built:
		menu.show_screen("single")
		var button: BaseButton = menu.buttons.get("RandomMap")
		check(button != null and button.is_visible_in_tree(), "Single Mission exposes Random map with the original button positions")
		if button != null:
			for key: String in ["SMBack", "SMStart"]:
				check(not button.get_rect().intersects(menu.buttons[key].get_rect()), "Random map leaves %s accessible" % key)
			check(not button.get_rect().intersects(menu.single_ui.slots.get_rect()), "Random map leaves the player slots accessible")
			button.pressed.emit()
			await _frames()
			check(menu.single_ui._random_map_dialog.visible, "the installed menu's Random map button opens setup")
	menu.queue_free()
	await _frames()
