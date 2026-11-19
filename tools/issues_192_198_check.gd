extends SceneTree
## Requires both game installations configured in user://profiles.json.
## Use an isolated project user directory for the mission-start autosave.

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1

func run() -> void:
	root.size = Vector2i(1440, 900)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if paths is not Dictionary or not paths.has("el1") or not paths.has("el2"):
		check(false, "Configure both games in user://profiles.json")
		quit(1)
		return
	var profile := ELProfile.new()
	if profile.mount("el1", paths.el1): await map_checks(profile)
	else: check(false, "Mount Etherlords I")
	await battle_checks()
	print("ISSUES #192–#198: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

func battle_checks() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	for edition: String in ["el1", "el2"]:
		view._start(edition)
		view.set_process(false)
		view.demo = false
		view.settings.values.cast_icons = true
		var notices: ELCombatNotices = view.notices
		notices.clear()
		var card: String = view.duel.heroes[0].deck[0]
		view._cast_notice(0, card)
		view._cast_notice(1, card)
		if edition == "el1":
			check(notices.icons.size() == 2 and notices.icons[0].side == 0 and notices.icons[1].side == 1,
				"el1 #196/#197: the same card cast by both heroes retains each caster")
		else:
			# The second game lists only the opponent's casts (#243).
			var rival: int = 1 - int(view._displayed_side())
			check(notices.icons.size() == 1 and notices.icons[0].side == rival,
				"el2 #196/#197/#243: of the same card cast by both heroes only the opponent's is listed")
		if edition != "el1": continue
		for i in 27: view._cast_notice(i % 2, card)
		view.log_text.show()
		for screen: Vector2i in [Vector2i(800, 600), Vector2i(1920, 1080)]:
			root.size = screen
			await process_frame
			for choice in ELHudFrame.SIZES.size() + 1:
				view.settings.values.battle_interface = choice
				view._layout_hud()
				var log_rect: Rect2 = view.log_text.get_rect()
				check(log_rect.position.x > notices.icon_column_right() and log_rect.size.x > 0 and log_rect.end.x <= view.ui.size.x,
					"#192: text log clears five cast columns at %s, interface size %d" % [screen, choice])
	var settings: ELSettings = view.settings
	view.queue_free()
	await process_frame
	settings.remove_meta("first_tutorial")

func map_checks(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, campaign.scenarios[1], settings, 1)
	check(built, "Build the second Etherlords I campaign mission")
	if built:
		view.set_process(false)
		await _shop(view)
		_fog(view)
		_skills(view)
	view.queue_free()
	await process_frame
	settings.remove_meta("first_tutorial")

func _fog(view: ELAdventureView) -> void:
	var state := view.state
	var player := state.current_player
	var castle := {}
	var site := {}
	for item: Dictionary in state.objects.values():
		var owner := int(item.get("owner", -1))
		if owner > 0 and owner != player and ELFirstScenario.is_castle(item): castle = item
		if site.is_empty() and item.get("type") == "resource_mine": site = item
	check(not castle.is_empty() and not site.is_empty(), "The map contains an enemy castle and a capturable mine")
	if castle.is_empty() or site.is_empty(): return
	site.owner = castle.owner
	state.players[castle.owner].blazon = [0, 0]
	var mask := ELFog.bit(player)
	var seen := PackedByteArray()
	seen.resize(state.map.width * state.map.height)
	state.explored.fill(mask)
	state.fog.visible = seen
	view.presentation.sync()
	for item: Dictionary in [castle, site]:
		var blazon: Dictionary = view.presentation.blazons.get(item.uid, {})
		check(not blazon.is_empty() and not blazon.back.visible and not blazon.fore.visible,
			"#194: remembered %s hides both layers of the enemy blazon" % item.name)
		seen[item.y * state.map.width + item.x] = mask
	state.fog.visible = seen
	view.presentation.sync()
	check(view.presentation.blazons[castle.uid].fore.visible and view.presentation.blazons[site.uid].fore.visible,
		"#194: enemy ownership is visible again in line of sight")

	var path := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	seen.fill(0)
	seen[state.map.width + 2] = mask
	state.fog.visible = seen
	view._draw_route(path, castle.uid)
	var marks := view.route.get_children()
	check(marks.size() == 2 and marks[0].visible and not marks[1].visible, "#193: only the visible segment of an enemy route is drawn")
	ELFog.reveal_for_console(state, player, true)
	view._sync_route_fog()
	check(marks.size() == 2 and marks[1].visible, "#193: lifting fog reveals the route without rebuilding it")
	ELFog.reveal_for_console(state, player, false)
	view._sync_route_fog()
	check(marks.size() == 2 and not marks[1].visible, "#193: restoring fog hides the enemy route again")
	view._draw_route(path, state.main_hero)
	check(view.route.get_child_count() == 2 and view.route.get_child(1).visible, "#193: the local hero can still see its own route")

func _skills(view: ELAdventureView) -> void:
	var state := view.state
	var profile := state.map.profile
	var hero := state.object(state.main_hero)
	var before := hero.duplicate(true)
	var xp := ELHeroProgression.threshold(profile, int(hero.level) + 1) - int(hero.experience)
	var rolls := {}
	for i in 8:
		var copy := before.duplicate(true)
		ELHeroProgression.award(profile, copy, xp, state.random_skill_offers)
		copy.skill_offers.sort()
		rolls["+".join(copy.skill_offers)] = true
	check(rolls.size() > 1, "#198: the same hero can get different offers when reaching the same level")
	state.add_experience(hero.uid, xp)
	var pending: Array = hero.skill_offers.duplicate()
	check(pending.size() == 3 and ELHeroSkills.prepare(profile, hero, true) == pending, "#198: opening an earned offer again keeps it")
	var learned: Dictionary = hero.skills.duplicate()
	var points := int(hero.skill_points)
	var codec := ELAdventureSave.new()
	var saved := codec.encode(view.director, view.camera_state())
	var restored := codec.decode(saved, {"el1": profile})
	check(not restored.is_empty(), "#198: the checkpoint with a pending choice still decodes")
	if restored.is_empty(): return
	var restored_state: ELAdventureSession = restored.state
	var loaded := restored_state.object(hero.uid)
	check(loaded.skill_offers == pending, "#198: decoding a checkpoint retains its offers for strategic sessions")
	rolls.clear()
	for i in 8:
		restored_state.reroll_pending_skill_offers()
		var offered: Array = loaded.skill_offers.duplicate()
		offered.sort()
		rolls["+".join(offered)] = true
	check(rolls.size() > 1 and loaded.skills == learned and loaded.skill_points == points,
		"#198: a solo load can reroll pending choices and keeps learned skills and points")
	restored_state.close()

func _shop(view: ELAdventureView) -> void:
	var state := view.state
	for item: Dictionary in state.objects.values():
		if not ELBuildingScreen.has_spells(item): continue
		item.owner = state.current_player
		var tiers := ELBuildingScreen.spell_tiers(state, item)
		if tiers[1].is_empty() and tiers[2].is_empty(): continue
		item.level = 0
		view.open_building_screen(item.uid)
		var shop := view.building_screen
		var entries := shop.spell_entries()
		var index := entries.find_custom(func(entry: Dictionary) -> bool: return not entry.open)
		var card := str(entries[index].code)
		var description := state.map.profile.card_description(card)
		var cell := shop.spell_rect(index).get_center()
		check(not description.is_empty() and shop.sheet.get_tooltip(cell).contains(description),
			"#195: the upgrade screen supplies the description even for locked spells")
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_RIGHT
		press.pressed = true
		await process_frame
		await process_frame
		press.position = shop.sheet.get_global_transform_with_canvas() * cell
		var motion := InputEventMouseMotion.new()
		motion.position = press.position
		root.push_input(motion, true)
		root.push_input(press, true)
		var tips: ELCombatTooltip = shop.get_child(-1)
		tips._process(0.0)
		check(tips.panel.visible, "#195: right press opens the upgrade screen's spell tooltip immediately")
		press.pressed = false
		root.push_input(press, true)
		view._close_building_screen()
		return
	check(false, "#195: find a laboratory with a locked spell on the map")
