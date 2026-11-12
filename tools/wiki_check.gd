extends SceneTree
## Checks the in-game wiki (ELWikiScreen) with the generated articles:
## every page in every language converts to BBCode without stray tags, every
## internal link opens its page, history and the language switch work, and
## the game is paused only while the wiki is open. Rendered runs (without
## --headless) also save screenshots: pass `-- --wiki-shots=<folder>`.
##
##   godot --headless --path game --script /path/to/tools/wiki_check.gd

var failures: Array[String] = []
## Encyclopedia pages the guides link to ({lang: {page: guide}}), checked
## against the encyclopedia of the installed games.
var guide_cards := {}

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
				# Encyclopedia lists and cards come from the installed games (checked below).
				var listed: bool = target in ELWikiCatalog.LISTS.values()
				if target.begins_with("card-") or target.begins_with("skill-") or target.begins_with("spec-"):
					listed = true
					guide_cards.get_or_add(lang, {})[target] = row.key
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
		var catalog := ELWikiCatalog.build(profiles, lang)
		check(catalog.pages.size() > 100, "%s has encyclopedia pages" % lang)
		var keys := {}
		for row: Dictionary in catalog.pages: keys[row.key] = true
		check(keys.size() == catalog.pages.size(), "%s: every encyclopedia page has its own name" % lang)
		var link := RegEx.create_from_string("wiki://([a-z0-9-]+)")
		for row: Dictionary in catalog.pages:
			for found: RegExMatch in link.search_all(row.html):
				check(keys.has(found.get_string(1)), "%s: %s links to %s" % [lang, row.key, found.get_string(1)])
		if profiles.size() > 1:
			var cards: Dictionary = guide_cards.get(lang, {})
			for target: String in cards:
				check(keys.has(target), "%s/%s links to %s" % [lang, cards[target], target])
		for kind: String in ELWikiCatalog.KINDS:
			screen.navigate(ELWikiCatalog.LISTS[kind])
			check(screen.page == ELWikiCatalog.LISTS[kind], "%s: the %s list opens" % [lang, kind])
		if profiles.size() > 1:
			var merged := 0
			var single := 0
			for row: Dictionary in catalog.pages:
				if row.kind == "list": continue
				if row.games.size() > 1: merged += 1
				else: single += 1
			check(merged > 100 and single > 0, "%s: cards of both games share a page, others name their game" % lang)
	screen.set_language("en")
	# Story pages show their heroes' models from the installed games.
	for story: String in ["diamanda", "white-lord"]:
		screen.navigate(story)
		check(screen._preview != null and screen._preview.model != null, "the %s page shows its hero" % story)
	var creature := ""
	var sorcery := ""
	var artifact_creature := ""
	var two_models := ""
	for row: Dictionary in screen._pages():
		if creature.is_empty() and row.get("kind") == "creature": creature = row.key
		if sorcery.is_empty() and row.get("kind") == "card": sorcery = row.key
		if artifact_creature.is_empty() and row.get("kind") == "creature" and row.category == ELWikiCatalog.LISTS.artifacts: artifact_creature = row.key
		if two_models.is_empty() and row.get("models", []).size() > 1: two_models = row.key
	for key: String in [creature, artifact_creature]:
		if key.is_empty(): continue
		screen.navigate(key)
		await process_frame
		check(screen._preview != null and screen._preview.model != null, "%s: a creature page shows the live model" % key)
	if screen._preview != null:
		var before := screen._preview.pivot.rotation.y
		screen._preview.turn(Vector2(60, 0))
		check(not is_equal_approx(before, screen._preview.pivot.rotation.y), "dragging turns the model")
		var distance := screen._preview.camera.position.z
		screen._preview.zoom(0.8)
		check(screen._preview.camera.position.z < distance, "the wheel zooms")
		screen._preview.reset_view()
	await _shot(shots, "artifact-creature")
	if profiles.has("el1"):
		# An air wall: its lower half is see-through cloth in soft alpha, which
		# the preview blends (an alpha cut-off would drop it).
		screen.navigate("card-wlbz")
		for i in 4: await process_frame
		var blended := false
		var effects: Node = null
		if screen._preview != null:
			effects = screen._preview.viewport.get_node_or_null("Effects")
			for part: Node in screen._preview.model.get_children():
				if part is MeshInstance3D and part.material_override is StandardMaterial3D:
					blended = blended or part.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		check(blended, "card-wlbz: the air wall's see-through skin is blended")
		check(effects is ELCombatEffects, "card-wlbz: the creature's own particles run with its clips")
		await _shot(shots, "air-wall")
	if not two_models.is_empty():
		screen.navigate(two_models)
		await process_frame
		check(screen._visual.get_child(0) is HBoxContainer, "%s: both editions' models can be shown" % two_models)
		await _shot(shots, "two-models")
	if profiles.has("el2"):
		screen.navigate("card-orwr")
		await process_frame
		_check_animations(screen)
		await _shot(shots, "creature-animation-controls")
	screen.navigate(sorcery)
	check(screen._preview == null and screen._visual.visible, "%s: a spell page shows its icon" % sorcery)
	await _shot(shots, "spell")
	screen.set_language("ru")
	screen.navigate("all-creatures")
	await _shot(shots, "ru-creature-list")
	screen.set_language("en")

func _check_animations(screen: ELWikiScreen) -> void:
	var preview := screen._preview
	check(preview != null, "Orc Warrior has an animation preview")
	if preview == null: return
	var controls := preview.get_parent().get_child(preview.get_index() + 1) as HBoxContainer
	check(controls != null, "The animation menu and Play button appear below the model")
	if controls == null: return
	var options := controls.get_child(0) as OptionButton
	var play := controls.get_child(1) as Button
	var settings := ELSettings.new()
	settings.load_file()
	var volume := float(settings.values.get("effects", 0.8))
	for label: String in ["Attack", "Death", "Idle"]:
		var index := -1
		for i in options.item_count:
			if options.get_item_text(i) == label:
				index = i
				break
		check(index >= 0, "Orc Warrior offers %s" % label)
		if index < 0: continue
		options.select(index)
		play.pressed.emit()
		check(preview.model.clip == options.get_selected_metadata(), "Play starts the %s clip" % label)
		if label == "Idle" or volume <= 0.0:
			check(not preview._sound.playing, "%s stops the previous sound" % label)
		else:
			check(preview._sound.playing and preview._sound.stream is AudioStreamWAV, "%s plays an original creature sound" % label)
