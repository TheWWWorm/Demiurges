extends SceneTree
## Regression checks for #182-#191. Needs both installed games configured in
## user://profiles.json. Run in an isolated user directory: mission transitions
## write their normal campaign autosave.
var failures: Array[String] = []
var profiles := {}

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	for edition: String in ["el1", "el2"]:
		var profile := ELProfile.new()
		assert(profile.mount(edition, paths[edition]))
		profiles[edition] = profile
	await _shops()
	await _campaigns()
	await _maps()
	await _battle()
	print("PATCH 0.18.3: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _shops() -> void:
	var p: ELProfile = profiles.el1
	var c := ELCampaign.new()
	c.load_campaign(p, "Good")
	var state: ELAdventureSession
	var trade: ELRuneShop
	for row: Dictionary in c.scenarios:
		var map := ELAdventureMap.new()
		if not map.load_map(p, row.file_name): continue
		state = ELAdventureSession.new()
		assert(state.start(map, 1))
		for item: Dictionary in state.objects.values():
			if item.group != "factories": continue
			trade = ELRuneShop.new()
			if trade.open(state, state.main_hero, item.uid, true): break
		if trade != null and trade.error.is_empty(): break
		state.close()
	assert(trade != null and trade.error.is_empty())
	var hero := state.object(state.main_hero)
	var spell := ""
	var cantrip := ""
	for code: String in p.table("CombatSpells"):
		var row: Dictionary = p.table("CombatSpells")[code]
		if not ELSpellInventory.is_spell(p, code): continue
		if row.get("Rarity") == "Common" and spell.is_empty(): spell = code
		if row.get("Rarity") == "Cantrip" and cantrip.is_empty(): cantrip = code
	hero.cards.assign([cantrip, spell, spell, spell])
	hero.rune_uses.assign([-1, 1, ELRunes.capacity(hero) - 1, ELRunes.capacity(hero)])
	hero.erase("rune_under")
	assert(trade.open(state, hero.uid, trade.shop_id, true))
	var director := ELAdventureDirector.new()
	assert(director.build(state))
	var hud := ELAdventureHud.new()
	root.add_child(hud)
	hud.build(state)
	var view := ELRuneShopView.new()
	root.add_child(view)
	view.build_shop(director, hud, trade)
	var before: Array = hero.rune_uses.duplicate()
	view.buttons.BuyOneEach.pressed.emit()
	check(trade.pending == [0, 1, 1, 0] and hero.rune_uses == before, "#184: buy one each skips cantrips/full copies and leaves the hero unchanged until payment")
	view.buttons.BuyOneEach.pressed.emit()
	check(trade.pending == [0, 2, 1, 0], "#184: repeated bulk purchases respect each copy's capacity")
	view.buttons.ReturnOneEach.pressed.emit()
	check(trade.pending == [0, 1, 0, 0], "#184: return one each removes one pending rune per copy")
	view.buttons.ReturnOneEach.pressed.emit()
	view.buttons.ReturnOneEach.pressed.emit()
	check(trade.pending == [0, 0, 0, 0] and hero.rune_uses == before, "#184: returning runes cannot remove previously owned runes")
	view.slot = 1
	view.refresh()
	for i in 3: await process_frame
	await _capture("portal")
	check(view.sheet.get_tooltip(Vector2(330, 100)).strip_edges().is_empty(), "#185: portal background has no blank tooltip")
	for row in 7:
		check(not view.tooltip_at(Vector2(428, view.PRICE_TOP + row * view.PRICE_STEP + 5)).is_empty(), "#186: portal resource %d has a tooltip" % row)
	view.queue_free()
	await process_frame
	var book := ELFirstBookView.new()
	root.add_child(book)
	book.build_book(director, hud, hero.uid)
	check(book.sheet.get_tooltip(Vector2(330, 100)).is_empty(), "#185: spell reserve background has no blank tooltip")
	book.queue_free()
	var hero_view := ELHeroScreenView.new()
	root.add_child(hero_view)
	hero_view.build(director, hud, [int(hero.uid)], false)
	check(hero_view.sheet.get_tooltip(Vector2(330, 100)).is_empty(), "#185: hero screen background has no blank tooltip")
	hero_view.queue_free()
	for item: Dictionary in state.objects.values():
		if item.get("type") != "el1_spell_shop": continue
		var laboratory := ELFirstSpellShop.new()
		if not laboratory.open(state, hero.uid, item.uid, true): continue
		var shop := ELFirstSpellShopView.new()
		root.add_child(shop)
		shop.build_shop(director, hud, laboratory)
		check(shop.sheet.get_tooltip(Vector2(330, 100)).is_empty(), "#185: laboratory background has no blank tooltip")
		for row in 7:
			check(not shop.tooltip_at(Vector2(362, shop.PRICE_TOP + row * shop.PRICE_STEP + 5)).is_empty(), "#186: laboratory resource %d has a tooltip" % row)
		for i in 3: await process_frame
		await _capture("laboratory")
		shop.queue_free()
		break
	hud.queue_free()
	await process_frame
	state.close()

func _campaigns() -> void:
	var menu := ELFrontMenu.new()
	root.add_child(menu)
	assert(menu.build(profiles, "el2"))
	var requested: Array = []
	menu.campaign_requested.connect(func(edition: String, row: Dictionary, difficulty: int): requested.append([edition, row, difficulty]))
	for pair: Array in [["Green", "Black"], ["Red", "Blue"], ["Black", "White"], ["Blue", "White"]]:
		var progress := ELSecondCampaign.new_game(2)
		if pair[0] not in ELSecondCampaign.FIRST: progress.possible = [pair[0]]
		assert(ELSecondCampaign.begin(progress, pair[0]))
		progress.counter = 1 if pair[1] == "White" else 0
		assert(ELSecondCampaign.next_campaign(progress) == "campaign")
		assert(menu.show_campaign_map(progress))
		check(menu.screen == "campaigns" and menu.cards.size() == 1 and menu.cards[0].campaign == pair[1], "#187: %s presents the %s campaign card" % pair)
		for i in 3: await process_frame
		await _capture("campaign-" + pair[1])
		menu.select_campaign(pair[1], true)
		menu._confirm_campaign()
		if pair[1] == "White":
			check(not requested.is_empty() and requested[-1][1].script == "maps\\e2mission50" and menu.screen == "campaigns", "#189: White starts the interlude directly, without showing its map")
		else:
			check(menu.screen == "map" and menu.difficulty == 2, "#187: confirming the card preserves difficulty and opens the mission map")
	menu.queue_free()
	await process_frame

func _maps() -> void:
	var p: ELProfile = profiles.el2
	var c := ELCampaign.new()
	c.load_campaign(p, "White")
	var settings := ELSettings.new()
	settings.use_edition("el2")
	for index in 2:
		var row: Dictionary = c.scenarios[index].duplicate()
		row.campaign = "White"
		var progress := ELSecondCampaign.for_chapter(p, "White", row, 1)
		row[ELSecondCampaign.KEY] = progress
		var view := ELAdventureView.new()
		root.add_child(view)
		assert(view.build(p, row, settings, 1))
		view.set_process(false)
		var state := view.state
		if index == 0:
			var lord := state.object(state.main_hero)
			var count := 0
			for item: Dictionary in state.objects.values():
				if item.name not in ["BlackHero", "RedHero", "GreenHero", "BlueHero"]: continue
				var art := ELAdventureArt.new(state.map).resolve(item)
				check(not item.alive and not art.is_empty() and view.world.object_models.has(item.uid), "#191: %s remains as a corpse in the sacrifice scene" % item.name)
				count += 1
			check(count == 4, "#191: all four sacrificed heroes exist")
			if view._mission_fade != null: await view._mission_fade.tree_exited
			for i in 24:
				if state.observations.has("WhiteLord"): break
				view._process(1.0 / 15.0)
				view.world._process(1.0 / 15.0)
			check(not ELFog.visible(state, 1, Vector2i(lord.x + 7, lord.y)) and ELFog.visible(state, 1, Vector2i(lord.x, lord.y)), "#191: the White Lord is visible only through the script's small observation")
			await _capture("interlude-opening")
			# Run the authored interlude to its sacrifice scene, including the
			# original fog clears and instant camera jumps.
			for tick in 1800:
				if not view.director.dialogue.is_empty():
					if str(view.director.dialogue.text_id).contains("S02_P04"): break
					view.director.acknowledge()
				view._process(1.0 / 15.0)
				view.world._process(1.0 / 15.0)
			check(str(view.director.dialogue.get("text_id", "")).contains("S02_P04"), "#191: the authored interlude reaches the sacrifice scene")
			var bodies := 0
			for item: Dictionary in state.objects.values():
				if item.name in ["BlackHero", "RedHero", "GreenHero", "BlueHero"] and view.world.object_models.has(item.uid) and view.world.object_models[item.uid].visible: bodies += 1
			check(bodies == 4, "#191: all four bodies are actually visible in the sacrifice scene")
			await _capture("interlude-sacrifice")
			state._native([], "ExHideExploration")
			view.world.sync_fog()
			check(view.world.fog_from == view.world.fog_to, "#191: a scripted fog cut hides terrain and scenery in the same frame")
			var next: Array = []
			view.campaign_map_requested.connect(func(data: Dictionary): next.append(data))
			state.outcome = "win"
			view._show_result()
			await process_frame
			check(view.win_lose == null and next.size() == 1 and int(next[0].row) == 1, "#191: finishing the interlude advances to White mission one without a victory screen")
		view.queue_free()
		await process_frame
	# Shared maps must select the Kinet hero before they become visible.
	c.load_campaign(p, "Blue")
	for index: int in [1, 3]:
		var view := ELAdventureView.new()
		root.add_child(view)
		assert(view.build(p, c.scenarios[index], settings, 1))
		view.set_process(false)
		var hero := view.state.object(view.state.main_hero)
		check(str(hero.shape).begins_with("BlueMainHero") and view.target.distance_to(ELAdventureScene.world_position(hero.x, hero.y)) < 0.1, "#188: Kinet mission %d opens on the Kinet hero at the correct location" % (index + 1))
		check(view.director.movement.is_empty() and view.director.dialogue.is_empty() and view.director._clock == 0.0,
			"#206: Kinet mission %d keeps the scene's movement and dialogue queued during the fade" % (index + 1))
		for i in 3: await process_frame
		var curtain := view.ui.get_node_or_null("MissionFade")
		if curtain != null: curtain.hide()
		await _capture("kinet-" + str(index + 1))
		view.queue_free()
		await process_frame

func _capture(label: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(label + ".png"))

func _battle() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	view._start("el2", {}, null, -1, true)
	check(view.battle_audio.get_child_count() == 0 and not view.duel.has_meta("start_sound"), "startup: menu preview creates no playback players or opening cue")
	view._start("el2")
	check(view.battle_audio.get_child_count() > 0 and view.duel.has_meta("start_sound"), "startup: a real duel retains its music and opening cue")
	view.demo = false
	view.mode_select.select(0)
	for i in 3: await process_frame
	var duel: ELDuel = view.duel
	for faction: String in ["Red", "Green", "Black", "Blue"]:
		duel.heroes[0].faction = faction
		check(view.hero_death_effect_name(0) == faction + "LordDeath" and view.hero_death_effect_name(1).is_empty(), "#183: %s uses its lord effect only for the human hero" % faction)
		view.effects.requested.clear()
		view._hero_death_effect(0)
		check(view.effects.requested.has(faction + "LordDeath"), "#183: the original %s lord effect starts on the figure" % faction)
		view.effects.finish_transients()
	duel.setup.adventure = true
	duel.setup.players = [{"main_hero": false}, {"main_hero": false}]
	check(view.hero_death_effect_name(0).is_empty(), "#183: an ordinary adventure hero has no ether burst")
	duel.setup.players[0].main_hero = true
	check(view.hero_death_effect_name(0) == "BlueLordDeath", "#183: the campaign's main hero retains its lord effect")
	duel.heroes[0].kind = "monster"
	check(view.hero_death_effect_name(0).is_empty(), "#183: a creature cannot receive the hero death effect")
	duel.heroes[0].kind = "hero"
	for i in 30: duel._give_card(0, "ORSH")
	view._refresh()
	for i in 4: await process_frame
	view.card_scroll.scroll_horizontal = 0
	var distance: float = view.camera_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = view.card_scroll.get_global_rect().get_center()
	root.push_input(wheel, true)
	for i in 12: await process_frame
	check(view.card_scroll.scroll_horizontal > 0 and view.camera_distance == distance, "#190: the wheel scrolls the hand without zooming the camera")
	view.card_scroll.scroll_horizontal = 100000
	root.push_input(wheel, true)
	await process_frame
	check(view.camera_distance == distance, "#190: wheel events at the hand's scroll limit also leave the camera still")
	view.queue_free()
	await process_frame
