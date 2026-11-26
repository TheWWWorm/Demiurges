extends SceneTree
## Exercises the actual Arena screen with an in-memory run. It never writes
## or replaces the player's Arena save. Optional --capture=<folder> captures
## rendered PNGs when a graphical display is available.
##
## godot --headless --path game --script ../tools/arena_screen_check.gd \
##   -- --el2=<installation>
## Add --images=<repository>/wiki/catalog/images/el2 to use catalog art in
## the asset-free fixture. The production screen reads installed spell icons.

const DraftCheck := preload("arena_draft_check.gd")
var failures: Array[String] = []
var checks := 0
var screen: ELArenaScreen
var source: ELProfile
var active: ELArenaRun
var captured_seed := -2
var captured_rules := -1
var captured_level := 0
var picked := -1
var requested_battle := false
var requested_continue := false


func _initialize() -> void:
	_run.call_deferred()


func _arg(name: String) -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="): return value.substr(name.length() + 3)
	return ""


func check(ok: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + description)
	if not ok: failures.append(description)


func frames(count := 4) -> void:
	for i in count: await process_frame


func _run() -> void:
	var installation := _arg("el2")
	if installation.is_empty():
		source = DraftCheck.synthetic_profile(_arg("fixture"))
	else:
		source = ELProfile.new()
		if not source.mount("el2", installation):
			check(false, "Mount Etherlords II: " + source.error)
			quit(1)
			return
	if source == null:
		check(false, "Card fixture is readable")
		quit(1)
		return
	var images := _arg("images")
	if not images.is_empty():
		for code: String in source.table("CombatSpells"):
			var path := images.path_join(code + ".webp")
			if FileAccess.file_exists(path):
				var image := Image.load_from_file(path)
				if image != null: source._icons[code] = ImageTexture.create_from_image(image)
	root.size = Vector2i(1440, 900)
	screen = ELArenaScreen.new()
	root.add_child(screen)
	screen.build(source)
	screen.started.connect(func(seed: int, rules: int, level: int):
		captured_seed = seed
		captured_rules = rules
		captured_level = level)
	screen.hero_chosen.connect(func(faction: String):
		check(active.choose_hero(faction), "Hero intent advances the real run")
		screen.show_run(active))
	screen.loadout_picked.connect(func(index: int):
		check(active.choose_loadout(index), "Specialization or artifact intent advances the real run")
		screen.show_run(active))
	screen.card_picked.connect(func(index: int):
		picked = index
		check(active.pick(index), "Card intent advances the real draft")
		screen.show_run(active))
	screen.battle_requested.connect(func(): requested_battle = true)
	screen.continued.connect(func(): requested_continue = true)
	await frames()
	if not source.file("Resources/Music/interface.mp3").is_empty():
		var music := screen.get_node("ArenaMusic") as AudioStreamPlayer
		check(music.playing and music.stream.loop, "Arena music loops while the screen is open")
		screen.hide()
		check(not music.playing, "Leaving the Arena screen stops its music")
		screen.show()
	check(_button("ArenaNewRun") != null, "Landing offers a new run")
	await _capture("landing-1440")
	var pool := screen.find_child("ArenaPool", true, false) as OptionButton
	check(pool != null and pool.item_count == 2 and pool.get_selected_id() == ELArenaRules.OPEN_RULES, "Both card pools are available when starting a run")
	pool.select(pool.get_item_index(ELArenaRules.FACTION_RULES))
	var player := screen.find_child("ArenaPlayerLevel", true, false) as OptionButton
	check(player.item_count == 13 and screen.find_child("ArenaOpponentLevel", true, false) == null, "One selector offers levels 1 to 13 for both sides")
	player.select(player.get_item_index(3))
	var seed: LineEdit = screen.get("_seed_field")
	seed.text = "2147483648"
	_button("ArenaNewRun").pressed.emit()
	check(captured_seed == -2 and bool(screen.get("_seed_error").visible), "Invalid seed is shown without starting a run")
	seed.text = "20261118"
	_button("ArenaNewRun").pressed.emit()
	if _button("ArenaConfirm") != null and bool(screen.get("_modal").visible): _button("ArenaConfirm").pressed.emit()
	check(captured_seed == 20261118, "A specific seed reaches the host")
	check(captured_rules == ELArenaRules.FACTION_RULES, "The selected card pool reaches the host")
	check(captured_level == 3, "The shared hero level reaches the host")
	active = ELArenaRun.new()
	active.auto_save = false
	check(active.create(source, 20261118, ELArenaRules.OPEN_RULES, Vector2i.ONE * captured_level), "A real in-memory Arena run is created")
	screen.show_run(active)
	await frames(28 if DisplayServer.get_name() != "headless" else 4)
	await _capture("hero-1440")
	var heroes := screen.find_children("ArenaHero_*", "Button", true, false)
	check(heroes.size() == 3, "Exactly three hero choices are displayed")
	if not installation.is_empty() and DisplayServer.get_name() != "headless":
		var previews := screen.find_children("ArenaHeroPreview", "Control", true, false)
		check(previews.size() == 3 and previews.all(func(figure: ELAutochessFigure) -> bool: return figure.model != null and figure.size.y > 380.0), "All three hero cards have tall live models")
		var group: Dictionary = previews[0].scale_group
		check(previews.all(func(figure: ELAutochessFigure) -> bool: return figure.scale_group == group) and int(group.get("count", 0)) == 3 and Dictionary(group.get("heights", {})).size() == 3, "The three heroes are drawn at one shared scale")
		var codes := previews.map(func(figure: ELAutochessFigure) -> String: return figure.code)
		check(codes.all(func(template: String) -> bool: return codes.count(template) == 1), "Each card shows a different hero figure")
		for viewport: Vector2i in [Vector2i(1024, 768), Vector2i(800, 600), Vector2i(390, 844)]:
			root.size = viewport
			await frames(28 if not _arg("capture").is_empty() else 6)
			await _capture("hero-%d" % viewport.x)
		root.size = Vector2i(1440, 900)
		await frames(28)
	await _click_offer(heroes[0], "Hero")
	await frames()
	if not installation.is_empty():
		check(active.phase == "spec", "Hero selection opens the specialization step")
		check(screen.find_children("ArenaSpecPick*", "Button", true, false).size() == 3, "Three specializations are offered as cards")
		await frames(6)
		await _capture("spec-1440")
		await _click_offer(_button("ArenaSpecPick1"), "Specialization")
		await frames()
		check(active.phase == "artifact" and active.specialization == active.spec_offer()[1], "The clicked specialization is kept")
		check(screen.find_children("ArenaArtifactPick*", "Button", true, false).size() == 3 and screen.find_child("ArenaSpec_" + active.specialization, true, false) != null, "Three artifacts are offered beside the chosen specialization")
		await frames(6)
		await _capture("artifact-1440")
		await _click_offer(_button("ArenaArtifactPick2"), "Artifact")
		await frames()
		check(active.artifacts == [active.artifact_offer()[2]], "The clicked artifact is kept")
	check(active.phase == "draft", "Hero selection opens drafting")
	await _click_offer(_button("ArenaPick1"), "Draft")
	await frames()
	check(picked == 1 and active.draft.cards.size() == 1, "The selected offer is committed exactly once")
	while active.draft.cards.size() < 10:
		active.pick(ELArenaDraftBot.choose(active.draft))
	screen.show_run(active)
	await frames()
	if not installation.is_empty() and DisplayServer.get_name() != "headless":
		var expected := active.draft.offer.filter(func(code: String) -> bool: return source.table("CombatCreatures").has(code))
		var figures := screen.find_children("ArenaCreaturePreview", "Control", true, false)
		check(not expected.is_empty() and figures.size() == expected.size(), "Every installed creature on offer uses a live 3D model")
		check(screen.find_children("ArenaCreatureStats", "HBoxContainer", true, false).size() == expected.size(), "Creatures show the combat power/toughness readout")
	for viewport: Vector2i in [Vector2i(1440, 900), Vector2i(1024, 768), Vector2i(800, 600), Vector2i(600, 900), Vector2i(390, 844)]:
		root.size = viewport
		await frames(28 if not _arg("capture").is_empty() else 6)
		_layout_check(viewport)
		await _capture("draft-%d" % viewport.x)
	root.size = Vector2i(1440, 900)
	await frames()
	screen.show_run(active, "Test: saving is unavailable")
	await frames()
	check(_button("ArenaPick0").disabled and _button("ArenaRetrySave") != null, "Save failure blocks picks and exposes retry")
	screen.show_run(active)
	while active.phase == "draft": active.pick(ELArenaDraftBot.choose(active.draft))
	screen.show_run(active)
	await frames()
	check(_button("ArenaBattle") != null and active.draft.cards.size() == 16, "A complete draft offers entry to battle")
	await _capture("ready-1440")
	_button("ArenaBattle").pressed.emit()
	check(requested_battle, "Battle intent reaches the host")
	var duel := active.build_battle()
	check(duel != null, "A real Arena opponent and battle can be built")
	if duel != null:
		check(duel.heroes[0].level == 3 and duel.heroes[1].level == 3, "Both heroes fight at the selected level")
		duel.winner = 0
		duel.phase = ELDuel.Phase.FINISHED
		check(active.resolve_battle(duel), "A completed battle reaches the run result")
		screen.show_run(active)
		await frames()
		check(_button("ArenaContinue") != null, "The result offers the next match")
		await _capture("result-1440")
		_button("ArenaOpponent0").pressed.emit()
		await frames()
		check(bool(screen.get("_modal").visible), "Completed opponents can be inspected")
		var tiles := screen.get("_modal").find_child("ArenaDeckTiles", true, false) as VBoxContainer
		check(tiles != null and tiles.get_child_count() > 0, "Opponent deck uses a square tile grid")
		await _capture("opponent-deck-1440")
		_button("ArenaOpponentDraft").pressed.emit()
		await frames()
		check(_button("ArenaCloseDetails") != null, "The opponent draft transcript opens")
		await _capture("opponent-draft-1440")
		_button("ArenaCloseDetails").pressed.emit()
		_button("ArenaContinue").pressed.emit()
		check(requested_continue, "Continue intent reaches the host")
		screen.show_run(active)
		_button("ArenaRetire").pressed.emit()
		await frames()
		check(_button("ArenaConfirm") != null and bool(screen.get("_modal").visible), "Retirement requires a deliberate confirmation")
		screen.show_run(active)
		check(active.retire(), "The test run can be retired")
		screen.show_run(active)
		await frames()
		check(_button("ArenaNewRun") != null, "A finished run offers another draft")
	print("ARENA SCREEN: %d checks, %d failure(s)" % [checks, failures.size()])
	screen.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)


func _button(node_name: String) -> Button:
	return screen.find_child(node_name, true, false) as Button


func _click_offer(offer: Button, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		offer.pressed.emit()
		return
	var point := offer.get_global_transform_with_canvas() * (offer.size * Vector2(0.5, 0.42))
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await frames(2)
	check(offer.get_node("CardOutline").visible, label + " preview hover outlines the full card")
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = down
		root.push_input(click, true)


func _layout_check(viewport: Vector2i) -> void:
	var offers := screen.find_children("ArenaPick*", "Button", true, false)
	check(offers.size() == 3, "%s: all three cards remain available" % viewport)
	var previous := Rect2()
	var inside := true
	var separate := true
	for offer: Button in offers:
		var to_screen := root.get_final_transform() * offer.get_global_transform_with_canvas()
		var box := to_screen * Rect2(Vector2.ZERO, offer.size)
		inside = inside and box.position.x >= -1 and box.end.x <= viewport.x + 1
		if previous.has_area(): separate = separate and not previous.intersects(box)
		previous = box
	check(inside and separate, "%s: offer cards fit horizontally without overlap" % viewport)
	var scroll: ScrollContainer = screen.get("_scroll")
	check(scroll.size.y >= 180, "%s: navigation leaves usable content space" % viewport)
	var columns := int(screen.get("_offer_grid").columns)
	check(columns == (3 if viewport.x >= 780 else 1), "%s: offer layout responds to width" % viewport)
	var deck := screen.find_child("ArenaDeckTiles", true, false) as VBoxContainer
	var square := deck != null and deck.get_child_count() > 0
	if deck != null:
		for tile: TextureButton in deck.find_children("ArenaTile_*", "TextureButton", true, false):
			square = square and is_equal_approx(tile.size.x, tile.size.y)
	check(square, "%s: drafted cards are square tiles" % viewport)


func _capture(label: String) -> void:
	var folder := _arg("capture")
	if folder.is_empty(): return
	if DisplayServer.get_name() == "headless":
		print("SKIP screenshot: headless renderer")
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered image is available for " + label)
	if image != null and not image.is_empty():
		check(image.save_png(folder.path_join(label + ".png")) == OK, "Saved screenshot " + label)
