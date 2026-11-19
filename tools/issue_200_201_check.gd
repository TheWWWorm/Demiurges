extends SceneTree
## Regression checks for the campaign setup, EL2 battle status icons and arena close-ups.
## Run with godot --headless --path game --script ../tools/issue_200_201_check.gd.
## A windowed run with -- --shots=<folder> also captures the campaign setup and arena.

var failures := 0
var shots := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, caption: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + caption)
	if not ok: failures += 1

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.trim_prefix("--shots=")
	root.size = Vector2i(1440, 900)
	_check(ELSettings.new().values.window_mode == 1, "Fresh preferences use borderless fullscreen")
	_check(ELFigure.is_cloth("he401", "body"), "The Vital sorceress's painted body stays matte")
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	view.set_process(false)
	if view.profiles.has("el1"):
		await _campaign(view)
		_saved_ai(view)
	if view.profiles.has("el2"):
		await _affects(view)
		await _arena(view.profiles.el2, "VitalsCity.001")
		await _ship_portrait(view.profiles.el2)
	print("CAMPAIGN AND BATTLE REPORTS: %d failure(s)" % failures)
	quit(int(failures > 0))

func _campaign(view: Node) -> void:
	var menu := ELFrontMenu.new()
	menu.profiles = view.profiles
	menu.settings = ELSettings.new()
	root.add_child(menu)
	_check(menu.build(view.profiles, "el1"), "First-game menus are available")
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(view.profiles.el1, "Evil") or campaign.scenarios.is_empty():
		_check(false, "First-game campaign is available")
		menu.queue_free()
		return
	var chapter: Dictionary = campaign.scenarios[0].duplicate()
	chapter.campaign = "Evil"
	var opened := menu.show_chapter_info(chapter, 0)
	_check(opened, "Campaign difficulty screen opens")
	await process_frame
	var box := menu.find_child("FightNeutralMonsters", true, false) as CheckBox
	var pick := menu.find_child("WorldAi", true, false) as OptionButton
	var help := menu.find_child("NeutralMonsterHelp", true, false) as Button
	var back := menu.find_child("CIBack", true, false) as Button
	_check(box != null and pick != null and help != null and back != null, "Difficulty screen has the checkbox, world AI picker, help and Back button")
	if box != null and pick != null and help != null and back != null:
		_check(not box.button_pressed and not pick.disabled and pick.selected == 0,
			"Easy starts with neutral monster duels off and Original world AI available")
		menu.set_difficulty(4)
		_check(not box.button_pressed and not pick.disabled, "Higher difficulty also defaults to monster duels off")
		menu.set_difficulty(0)
		_check(help.tooltip_text.contains("higher difficulties") or help.tooltip_text.contains("более высокой сложности"), "Help advises against enabling the option on higher difficulties")
		_check(help.tooltip_text.contains("automatically") or help.tooltip_text.contains("автоматически"), "Help explains the original automatic win")
		help.pressed.emit()
		_check(menu.duel_ui.message_open(), "Clicking the question mark opens the help")
		menu.duel_ui.close_message()
		box.button_pressed = true
		_check(pick.disabled and pick.selected == ELAIChoice.LIVING_WORLD, "Checking the box selects and locks Living world")
		menu.set_difficulty(4)
		_check(box.button_pressed and pick.disabled, "Changing difficulty keeps the explicit monster setting")
		_check(menu.with_ai(chapter).ai.get(ELAIChoice.FIGHT_MONSTERS), "Starting the chapter carries the checkbox")
		await _capture("campaign-ai")
		box.button_pressed = false
		_check(not pick.disabled and pick.selected == menu.settings.values.world_ai, "Clearing the box restores the difficulty's world AI picker")
		back.pressed.emit()
		_check(menu.screen == "campaigns", "Back returns to campaign selection")
	menu.queue_free()
	await process_frame
	var fallback := ELCampaignSetup.new()
	fallback.settings = ELSettings.new()
	root.add_child(fallback)
	fallback.build(view.profiles, "el1")
	var fallback_box := fallback.find_child("FightNeutralMonsters", true, false) as CheckBox
	_check(fallback_box != null and not fallback_box.button_pressed, "The alternate campaign setup also starts unchecked")
	if fallback_box != null:
		fallback_box.button_pressed = true
		_check(fallback.ai_picks.world_ai.disabled and fallback.ai_picks.world_ai.selected == ELAIChoice.LIVING_WORLD,
			"The alternate setup locks Living world as well")
	fallback.queue_free()
	await process_frame

func _saved_ai(view: Node) -> void:
	var map := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	if not map.load_map(view.profiles.el1, "mmission02") or not state.start(map, 1):
		_check(false, "First-game scenario loads for the save check")
		return
	var director := ELAdventureDirector.new()
	if not director.build(state):
		_check(false, "First-game scenario director is ready")
		return
	ELAIChoice.store(state, {"duel_ai": 2, "world_ai": 1, ELAIChoice.FIGHT_MONSTERS: true})
	var codec := ELAdventureSave.new()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(codec.encode(director)))
	var restored := codec.decode(saved, {"el1": view.profiles.el1})
	_check(not restored.is_empty() and restored.state.fight_neutral_monsters and restored.state.world_ai == ELAIChoice.LIVING_WORLD,
		"Saving and loading keeps the checked option and Living world")
	saved.world.ai.erase(ELAIChoice.FIGHT_MONSTERS)
	var legacy := codec.decode(saved, {"el1": view.profiles.el1})
	_check(not legacy.is_empty() and not legacy.state.fight_neutral_monsters, "An older save loads with the checkbox off")
	var map_view := ELAdventureView.new()
	map_view.state = state
	view.campaign_view = map_view
	var page := VBoxContainer.new()
	root.add_child(page)
	view._interface_page(page)
	var world := page.find_child("WorldAi", true, false) as OptionButton
	_check(world != null and world.disabled and world.selected == ELAIChoice.LIVING_WORLD, "In-game Options also locks the world AI setting")
	view.campaign_view = null
	map_view.free()
	page.queue_free()

func _affects(view: Node) -> void:
	view._start("el2")
	if is_instance_valid(view.front_menu): view.front_menu.hide()
	view.menu_button.hide()
	view.menu.hide()
	for model: ELModel in view.models.values(): model.set_process(false)
	await process_frame
	var strip: ELAffectStrip = view.affect_strip
	strip.setup(view.profile)
	strip.set_entries([{"name": "Another affect", "icon": 1, "tooltip": "Another effect"},
		{"name": "Test affect", "icon": 25, "tooltip": "Global effect\nDays left 1"}])
	var tip: ELCombatTooltip = view.combat_tip
	var point := root.get_final_transform() * strip.get_global_transform_with_canvas() * strip.icon_rect(1).get_center()
	_check(tip._owns(strip), "Battle status icons use the framed battle tooltip")
	if DisplayServer.get_name() != "headless": return
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	Input.parse_input_event(move)
	Input.flush_buffered_events()
	for i in 3: await process_frame
	_check(root.gui_get_hovered_control() == strip, "Pointer reaches the battle status icon (%s)" % str(root.gui_get_hovered_control().get_path()) if root.gui_get_hovered_control() != null else "none")
	await create_timer(ELCombatTooltip.DELAY + 0.1).timeout
	_check(tip.panel.visible and tip.panel._labels.size() == 2, "Hover shows the effect text and duration in the battle frame")
	tip.hide_tip()
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	for i in 3: await process_frame
	_check(tip.panel.visible and tip.panel._labels.size() == 2 and not view.right_down,
		"Right-click opens the same tooltip immediately without orbiting (visible=%s, lines=%d, dragging=%s)" %
		[tip.panel.visible, tip.panel._labels.size(), view.right_down])
	click.pressed = false
	click.button_mask = 0
	Input.parse_input_event(click)
	Input.flush_buffered_events()

func _arena(profile: ELProfile, id: String) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1000, 660)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.own_world_3d = true
	root.add_child(view)
	var arena := ELArena.new()
	view.add_child(arena)
	if not arena.build(profile, id):
		_check(false, id + " loads")
		view.queue_free()
		return
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.current = true
	camera.fov = 44.0
	var eye := Vector3(-25.0, 1.4, 6.0)
	var focus := Vector3(-6.0, 0.75, 7.0)
	camera.look_at_from_position(eye, focus)
	arena.clear_camera_view(eye, focus, [focus])
	var blocked := arena._closeup_hidden.duplicate()
	_check(not blocked.is_empty(), id + " detects scenery crossing a low close-up")
	_check(arena._ground.visible, id + " keeps the arena surface")
	if not shots.is_empty() and DisplayServer.get_name() != "headless":
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png(shots.path_join(id + "-clear.png"))
	arena.clear_camera_view(Vector3(0, 22, 15), Vector3(0, 1, 0))
	_check(arena._closeup_hidden.is_empty() and blocked.all(func(part: MeshInstance3D): return part.visible),
		id + " restores the close-up scenery for the normal camera")
	view.queue_free()
	await process_frame

func _ship_portrait(profile: ELProfile) -> void:
	var map := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	if not map.load_map(profile, "e2mission11") or not state.start(map, 0):
		_check(false, "Second-game campaign map loads for the ship portrait")
		return
	var hud := ELSecondAdventureHud.new()
	root.add_child(hud)
	if not hud.build(state):
		_check(false, "Second-game map HUD loads")
		hud.queue_free()
		return
	var hero := state.object(state.main_hero)
	hud.refresh(state.main_hero, true)
	var before := hud.portrait_texture
	hero.ship = true
	hud.refresh(state.main_hero, true)
	_check(before != null and hud.portrait_texture == before, "Boarding keeps the hero's portrait")
	hud.queue_free()

func _capture(name: String) -> void:
	if shots.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shots.path_join(name + ".png"))
