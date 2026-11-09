extends SceneTree
## Checks the in-game wiki (ELWikiScreen) with the generated articles:
## every page in every language converts to BBCode without stray tags, every
## internal link opens its page, history and the language switch work, and
## the game is paused only while the wiki is open. Rendered runs (without
## --headless) also save screenshots: pass `-- --wiki-shots=<folder>`.
##
##   godot --headless --path game --script /path/to/tools/wiki_check.gd

var failures: Array[String] = []

func check(condition: bool, what: String) -> void:
	if not condition:
		failures.append(what)
		printerr("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _shots() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--wiki-shots="): return arg.trim_prefix("--wiki-shots=")
	return ""

func _shot(folder: String, name: String) -> void:
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func _run() -> void:
	var shots := _shots()
	# The player's own remembered language is restored at the end.
	var saved := FileAccess.get_file_as_bytes(ELWikiScreen.SETTINGS) if FileAccess.file_exists(ELWikiScreen.SETTINGS) else PackedByteArray()
	DirAccess.remove_absolute(ELWikiScreen.SETTINGS)
	root.size = Vector2i(1440, 900)
	var keys := {}
	for lang: String in ELWikiData.LANGUAGES:
		var names: Array = []
		for row: Dictionary in ELWikiData.PAGES[lang]: names.append(row.key)
		keys[lang] = names
		check(names.has("home"), "%s has a home page" % lang)
	check(keys.en == keys.ru, "English and Russian list the same pages in the same order")
	var link := RegEx.create_from_string("wiki://([a-z0-9-]+)")
	var probe := RichTextLabel.new()
	probe.bbcode_enabled = true
	root.add_child(probe)
	var links := 0
	for lang: String in ELWikiData.LANGUAGES:
		for row: Dictionary in ELWikiData.PAGES[lang]:
			var code := ELWikiHtml.to_bbcode(row.html)
			probe.clear()
			probe.parse_bbcode(code)
			var shown := probe.get_parsed_text()
			check(shown.begins_with(row.title), "%s/%s starts with its title" % [lang, row.key])
			check(not "[/" in shown and not "[url" in shown and not "[b]" in shown, "%s/%s has no unparsed BBCode" % [lang, row.key])
			check(not "&amp;" in shown and not "&lt;" in shown and not "&quot;" in shown, "%s/%s has no HTML entities left" % [lang, row.key])
			for found: RegExMatch in link.search_all(row.html):
				links += 1
				var target := found.get_string(1)
				# Encyclopedia lists come from the installed games (checked below).
				var listed := target.substr(0, 4) in ["el1-", "el2-"] and target.substr(4) in ELWikiCatalog.KINDS
				check(keys[lang].has(target) or listed, "%s/%s links to %s" % [lang, row.key, target])
	probe.queue_free()
	check(ELWikiHtml.key_from_url("wiki://combat") == "combat", "internal links resolve")
	check(ELWikiHtml.key_from_url("wiki://x]y") == "" and ELWikiHtml.key_from_url("wiki://../a") == "", "unsafe links are refused")
	check(ELWikiHtml.to_bbcode("<p>[b]x</p>") == "[lb]b]x", "article text cannot open BBCode tags")

	check(not paused, "the tree starts unpaused")
	var screen := ELWikiScreen.open(root, "", "Новая игра")
	await process_frame
	check(paused, "the game is paused while the wiki is open")
	check(ELWikiScreen.is_open(), "the wiki reports itself open")
	screen.set_language("en")
	check(screen.page == "home" and screen._article.get_parsed_text().begins_with("Demiurges wiki"), "the English home page opens")
	await _shot(shots, "en-home")
	# Follow every link of every page once, in both languages.
	for lang: String in ELWikiData.LANGUAGES:
		screen.set_language(lang)
		for key: String in keys[lang]:
			screen.navigate(key)
			check(screen.page == key, "%s: %s opens" % [lang, key])
			check(screen._article.get_parsed_text().length() > 200, "%s: %s has text" % [lang, key])
	screen.set_language("en")
	screen.navigate("home")
	screen._link("wiki://combat")
	check(screen.page == "combat", "an article link navigates")
	await _shot(shots, "en-combat")
	screen._link("wiki://controls")
	screen.go_back()
	check(screen.page == "combat", "Back returns to the previous page")
	screen.go_forward()
	check(screen.page == "controls", "Forward returns again")
	screen.set_language("ru")
	check(screen.page == "controls" and screen._title.text == "Вики Demiurges", "the language switch keeps the page")
	check(screen._article.get_parsed_text().begins_with("Управление"), "the Russian page is shown")
	await _shot(shots, "ru-controls")
	check(ELWikiScreen.remembered_language() == "ru", "the language choice is remembered")
	screen._search.text = "фаз"
	screen._fill_list()
	var first := screen._tree.get_root().get_first_child()
	check(first != null and first.get_first_child() != null and first.get_first_child().get_metadata(0) != null, "Russian search finds pages")
	await _shot(shots, "ru-search")
	screen._search.text = "zzzzqqq"
	screen._fill_list()
	check(screen._tree.get_root().get_first_child().get_metadata(0) == null, "an empty search says nothing was found")
	screen.navigate("no-such-page")
	check(screen.page == "home", "an unknown page shows the contents")
	await _catalog(screen, shots)
	root.size = Vector2i(800, 600)
	await process_frame
	screen.navigate("combat-phases")
	await _shot(shots, "ru-narrow")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key)
	await process_frame
	await process_frame
	check(not ELWikiScreen.is_open(), "Esc closes the wiki")
	check(not paused, "closing the wiki resumes the game")
	DirAccess.remove_absolute(ELWikiScreen.SETTINGS)
	if not saved.is_empty():
		var file := FileAccess.open(ELWikiScreen.SETTINGS, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	print("wiki check: %d pages per language, %d links, %d failures" % [keys.en.size(), links, failures.size()])
	quit(1 if not failures.is_empty() else 0)

## Encyclopedia pages of the installed games (Steam copies are found
## automatically; otherwise pass `-- --wiki-el1=<folder> --wiki-el2=<folder>`).
func _catalog(screen: ELWikiScreen, shots: String) -> void:
	var folders := ELContentLibrary.steam_folders()
	for arg: String in OS.get_cmdline_user_args():
		for edition: String in ["el1", "el2"]:
			if arg.begins_with("--wiki-%s=" % edition): folders[edition] = arg.get_slice("=", 1)
	if folders.is_empty():
		print("wiki check: no installed game; encyclopedia pages not checked")
		return
	var profiles := {}
	for edition: String in folders:
		var profile := ELProfile.new()
		check(profile.mount(edition, folders[edition]), "%s mounts from %s" % [edition, folders[edition]])
		profiles[edition] = profile
	ELWikiScreen.profiles = profiles
	screen._content.clear()
	for lang: String in ELWikiData.LANGUAGES:
		screen.set_language(lang)
		for edition: String in profiles:
			var catalog := ELWikiCatalog.build(profiles[edition], lang)
			check(catalog.pages.size() > 100, "%s/%s has encyclopedia pages" % [edition, lang])
			var keys := {}
			for row: Dictionary in catalog.pages: keys[row.key] = true
			var link := RegEx.create_from_string("wiki://([a-z0-9-]+)")
			for row: Dictionary in catalog.pages:
				for found: RegExMatch in link.search_all(row.html):
					check(keys.has(found.get_string(1)), "%s: %s links to %s" % [lang, row.key, found.get_string(1)])
			for kind: String in ELWikiCatalog.KINDS:
				screen.navigate("%s-%s" % [edition, kind])
				check(screen.page == "%s-%s" % [edition, kind], "%s: the %s %s list opens" % [lang, edition, kind])
	screen.set_language("en")
	for edition: String in profiles:
		var creature := ""
		var sorcery := ""
		for row: Dictionary in screen._pages():
			if row.get("game") != edition: continue
			if creature.is_empty() and row.get("kind") == "creature": creature = row.key
			if sorcery.is_empty() and row.get("kind") == "card": sorcery = row.key
		screen.navigate(creature)
		await process_frame
		check(screen._preview != null and screen._preview.model != null, "%s: a creature page shows the live model" % creature)
		if screen._preview != null:
			var before := screen._preview.pivot.rotation.y
			screen._preview.turn(Vector2(60, 0))
			check(not is_equal_approx(before, screen._preview.pivot.rotation.y), "%s: dragging turns the model" % creature)
			var distance := screen._preview.camera.position.z
			screen._preview.zoom(0.8)
			check(screen._preview.camera.position.z < distance, "%s: the wheel zooms" % creature)
			screen._preview.reset_view()
		await _shot(shots, "%s-creature" % edition)
		screen.navigate(sorcery)
		check(screen._preview == null and screen._visual.visible, "%s: a spell page shows its icon" % sorcery)
		await _shot(shots, "%s-spell" % edition)
	screen.set_language("ru")
	screen.navigate("el1-creatures" if profiles.has("el1") else "el2-creatures")
	await _shot(shots, "ru-creature-list")
	screen.set_language("en")
