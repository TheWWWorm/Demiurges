extends SceneTree
## Headless check of first-game map details:
## - the minimap draws a castle or site marker only once the local player
##   has explored the building, and every marker with the console's open_fog;
## - a double-click on the player's own castle opens its GlobalSpells screen
##   (the click before it orders nothing), a double-click on bare ground
##   does not;
## - a spell picture on that screen has the picture tooltip with the spell's
##   name and description from the game's texts, and no plain text tooltip;
## - a long camera turn keeps the angle (and the saved one) within one turn;
## - #169: the cross of a created spell's "choose a hero" prompt keeps the
##   spell ready (a click on its picture asks again, its cost is not lost);
##   a right click on a hero's portrait there opens that hero's screen over
##   the prompt, and closing it goes back to the prompt;
## - #170: choosing a hero's destination leaves the view where it is (on the
##   destination), it does not swing back to the hero;
## - #171: with free movement a right click stops the walking hero on the
##   tile it is stepping onto; its unspent movement points stay;
## - #220: the walking hero's markers disappear as it reaches them;
## - #221: a new mission's camera opens on the local player's castle;
## - #172: a right click on an artifact on the hero screen holds up its
##   tooltip until the button is let go;
## - #168: a map tooltip held up with the right button fits its text whatever
##   tooltip was shown before it (a building's after a monster's stretched).
##
##   godot --headless --path game --script ../tools/first_map_check.gd
##
## It needs the first game's files (user://profiles.json, as set up by the
## game); without them it is skipped. Settings are never written, and the
## mission-start autosave the map writes is put back as it was.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _map_part()
	print("FIRST MAP: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

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
	# The second mission has enemy castles under the fog.
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
	_restore(ELSaveSlots.folder("el1"), saves)
	check(built, "a first-game mission map builds: " + view.error)
	if not built: return
	await frames(5)
	if view.tutorial_panel != null and view.tutorial_panel.visible: view.tutorial_panel.close()
	await frames(2)
	var state := view.state
	var hud := view.hud
	var player := state.current_player
	check(ELFog.active(state, player), "the map has fog for the local player")

	# Minimap markers.
	var hidden := {}
	for item: Dictionary in state.objects.values():
		var marked: bool = ELFirstScenario.is_castle(item) or str(item.get("group", "")) in ["mana_nodes", "mines", "forts"]
		if marked and item.get("alive", false) and ELFog.object_state(state, player, item) == ELFog.UNEXPLORED:
			hidden = item
			if ELFirstScenario.is_castle(item): break
	check(not hidden.is_empty(), "the map has an unexplored castle or site")
	if not hidden.is_empty():
		check(not hud.minimap_known(hidden), "the minimap hides the unexplored %s" % hidden.name)
		ELFog.reveal_for_console(state, player, true)
		check(hud.minimap_known(hidden), "open_fog shows it on the minimap")
		ELFog.reveal_for_console(state, player, false)
		check(not hud.minimap_known(hidden), "hide_fog hides it again")
		var index := int(hidden.y) * state.map.width + int(hidden.x)
		var before := state.explored[index]
		state.explored[index] = before | ELFog.bit(player)
		check(hud.minimap_known(hidden), "an explored cell of it shows it on the minimap")
		state.explored[index] = before
	var own := ELFirstScenario.castle_object(state, player)
	check(not own.is_empty() and hud.minimap_known(own), "the player's own castle is on the minimap")
	if not own.is_empty():
		var size: Vector2i = view.director.grid.footprints[int(own.uid)].size
		var centre := ELAdventureScene.world_position(own.x + (size.x - 1) * 0.5, own.y + (size.y - 1) * 0.5)
		check(view.camera_goal().is_equal_approx(centre) and view.following == -1, "the new mission opens and stays centred on the player's castle")

	# Turning the camera for a long time keeps the saved angle within one turn
	# (an angle past the save's old limit made the save unloadable).
	var yaw := view.yaw
	view.yaw += 2000.0 * TAU + 0.5
	view._update_camera()
	check(view.yaw >= 0.0 and view.yaw < TAU and is_equal_approx(view.yaw, fposmod(yaw + 0.5, TAU)) and state.camera_rotation >= 0.0 and state.camera_rotation < 360.0, "a long camera turn keeps the angle within one turn (%.3f rad, %.1f degrees)" % [view.yaw, state.camera_rotation])
	view.yaw = yaw
	view._update_camera()
	await _tooltip_part(view)
	await _route_camera_part(view)
	_actor_facing(view)
	await _artifact_tip_part(view, profile)

	# Castle double-click.
	check(not own.is_empty(), "the player has a castle")
	if own.is_empty(): return
	_castle_stage_part(view, profile)
	var size: Vector2i = view.director.grid.footprints.get(int(own.uid), {}).get("size", Vector2i.ONE)
	var centre := Vector3((float(own.x) + size.x * 0.5) * ELAdventureTerrain.CELL, 0, -(float(own.y) + size.y * 0.5) * ELAdventureTerrain.CELL)
	view.following = -1
	view.target = centre
	view._update_camera()
	var at := view.camera.unproject_position(centre)
	var hero := state.object(view._hero_id())
	var order: Dictionary = hero.get("strategy_order", {}).duplicate(true)
	view._unhandled_input(_click(at, false))
	check(view.global_spells == null and hero.get("strategy_order", {}) == order, "a single click on the own castle orders nothing and opens nothing")
	view._unhandled_input(_click(at, true))
	check(view.global_spells != null, "a double-click on the own castle opens its GlobalSpells screen")
	if view.global_spells == null: return
	await frames(2)
	var screen := view.global_spells
	var tip := screen.spell_tip("SVWR", Rect2(screen.cell(0, 0)), ELGlobalSpellsView.icon(profile, 0))
	var description := profile.text(str(ELGlobalSpells.row(profile, "SVWR").Description))
	check(tip.title == ELGlobalSpells.title(profile, "SVWR") and tip.text == description and not description.begins_with("GlSp"), "a spell's tooltip has its name and description texts")
	if not screen.entries[0].is_empty():
		var point := screen.cell(0, 0).get_center()
		screen._hover(point)
		var entry: Dictionary = screen.entries[0][0]
		check(screen.picture_tip.visible and screen.picture_tip.title == ELGlobalSpells.title(profile, str(entry.code)) and screen.picture_tip.picture != null, "hovering an available spell opens its picture tooltip")
		check(screen.picture_tip.size.x > 150 and screen.picture_tip.position.x >= screen.cell(0, 0).end.x, "the tooltip opens beside the cell")
		check(screen._tooltip(point) == "", "the spell cell has no plain text tooltip")
		screen._hover(Vector2(-INF, -INF))
		check(not screen.picture_tip.visible, "leaving the cell hides it")
	else:
		print("NOTE: no spell is available on this map; the tooltip is checked on its content alone")
	# Enter presses the screen's check button (GitHub #47).
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	view._unhandled_input(enter)
	await frames(3)
	check(view.global_spells == null, "Enter presses the check button and the screen closes")
	if view.global_spells != null:
		screen.closed.emit()
		await frames(3)
	await _ready_spell_part(view, profile)
	# A double-click on bare ground beside the castle opens nothing.
	var ground := Vector3(centre.x + (size.x * 0.5 + 6) * ELAdventureTerrain.CELL, 0, centre.z)
	check(not view.castle_double_click(view.camera.unproject_position(ground), ground) and view.global_spells == null, "a double-click away from the castle opens nothing")
	view.queue_free()
	await frames(2)

## #169: a created spell that goes to a hero, its prompt, and the hero's
## screen from a right click on a portrait.
func _ready_spell_part(view: ELAdventureView, profile: ELProfile) -> void:
	var state := view.state
	var player := state.current_player
	var code := ""
	for candidate: String in profile.table("GlobalSpells"):
		var params: Variant = ELGlobalSpells.row(profile, candidate).get("Params", [])
		if ELGlobalSpells.supported(candidate) and (params == "Hero" or params == ["Hero"]) and ELGlobalSpells.targets(state, player, candidate).size() == 1 and not ELGlobalSpells.targets(state, player, candidate)[0].is_empty():
			code = candidate
			break
	check(not code.is_empty(), "a global spell goes to one of the player's heroes")
	if code.is_empty(): return
	var record := ELGlobalSpells.data(state, player)
	record.production = {"code": code, "cost": 10, "spent": 10, "state": 2}
	var resources: Dictionary = state.players[player].resources.duplicate()
	view.open_global_spells(true)
	await frames(2)
	var screen := view.global_spells
	check(screen != null and screen.prompt.visible, "a created spell opens the prompt to choose its hero")
	if screen == null: return
	var portrait := screen.prompt_cell(0, 0).get_center()
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = portrait
	screen.prompt._gui_input(right)
	await frames(2)
	var hero_id := int(ELGlobalSpells.targets(state, player, code)[0][0])
	check(view.hero_screen != null and view.hero_screen.heroes == [hero_id], "a right click on a hero's portrait opens that hero's screen")
	if view.hero_screen != null:
		view.hero_screen.closed.emit()
		await frames(2)
	check(view.hero_screen == null and view.global_spells == screen and screen.prompt.visible and view.paused, "closing the hero's screen goes back to the prompt, the map still held")
	screen.prompt_buttons.SelectCancel.pressed.emit()
	await frames(1)
	check(not screen.prompt.visible and int(screen.production().get("state", 0)) == 2 and str(screen.production().get("code", "")) == code and state.players[player].resources == resources,
		"the prompt's cross keeps the created spell ready, nothing paid is lost")
	screen._press(screen.PRODUCTION + screen.CELL * 0.5)
	check(screen.prompt.visible, "a click on the ready spell's picture asks for its hero again")
	screen.prompt_buttons.SelectOK.pressed.emit()
	await frames(1)
	check(screen.production().is_empty() and ELGlobalSpells.data(state, player).active.any(func(spell: Dictionary) -> bool: return spell.code == code), "the spell then goes to the chosen hero")
	screen.closed.emit()
	await frames(2)

## #170: the view stays on a destination the player picks far from the hero.
func _route_camera_part(view: ELAdventureView) -> void:
	var state := view.state
	var hero := state.object(view._hero_id())
	await frames(2)
	var from := Vector2i(int(hero.x), int(hero.y))
	var goal := Vector2i(-1, -1)
	for radius in range(12, 4, -1):
		for step: Vector2i in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
			var tile := from + step
			if goal.x < 0 and tile.x >= 0 and tile.y >= 0 and tile.x < state.map.width and tile.y < state.map.height and view.director.grid.path(from, tile).size() > 3 and ELFog.explored(state, state.current_player, tile): goal = tile
	check(goal.x >= 0, "the hero can walk to a tile some way off")
	if goal.x < 0: return
	var spot := Vector3((goal.x + 0.5) * ELAdventureTerrain.CELL, 0, -(goal.y + 0.5) * ELAdventureTerrain.CELL)
	# The player scrolls there and picks the tile.
	view.following = -1
	view.view_moved = true
	view.target = spot
	view._update_camera()
	view._unhandled_input(_click(view.camera.unproject_position(spot), false))
	for i in 30: await process_frame
	var planned: Dictionary = hero.get("strategy_order", {})
	check(not planned.is_empty() and Vector2i(planned.destination[0], planned.destination[1]) == goal, "a click far from the hero plans its route there")
	check(view.following < 0 and Vector2(view.target.x - spot.x, view.target.z - spot.z).length() < 0.5, "planning the route leaves the view on the destination (%.1f from it, following %d)" % [Vector2(view.target.x - spot.x, view.target.z - spot.z).length(), view.following])
	# #171: chosen again, the hero sets off (free movement); a right click
	# stops it on the way.
	var start := Vector2i(int(hero.x), int(hero.y))
	var points := int(hero.ap)
	check(ELStrategy.free_mode(view.director), "free movement is on")
	view._unhandled_input(_click(view.camera.unproject_position(spot), false))
	var markers := _route_cells(view)
	var waited := 0
	while waited < 600 and Vector2i(int(hero.x), int(hero.y)) == start:
		await process_frame
		waited += 1
	check(not view.director.movement.is_empty() and view.director.strategy.get("free", "") == "act", "the hero sets off on the second choice")
	var reached := Vector2i(int(hero.x), int(hero.y))
	var remaining_markers := _route_cells(view)
	check(markers.has(reached) and not remaining_markers.has(reached) and not remaining_markers.is_empty(), "reaching a route tile removes its marker and keeps the ones ahead")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.position = Vector2(200, 200)
	right.pressed = true
	view._unhandled_input(right)
	right = right.duplicate()
	right.pressed = false
	view._unhandled_input(right)
	waited = 0
	while waited < 600 and (not view.director.movement.is_empty() or not view.director.strategy.is_empty()):
		await process_frame
		waited += 1
	var at := Vector2i(int(hero.x), int(hero.y))
	var walked := maxi(absi(at.x - start.x), absi(at.y - start.y))
	check(view.director.movement.is_empty() and at != goal and walked >= 1 and walked <= 2 and hero.get("strategy_order", {}).is_empty(), "a right click stops the walking hero within a step (%d tiles walked of %d)" % [walked, maxi(absi(goal.x - start.x), absi(goal.y - start.y))])
	check(int(hero.ap) > 0 and int(hero.ap) < points, "it keeps the movement points it did not spend (%d of %d)" % [int(hero.ap), points])
	view._cancel_map_order()
	view.following = view._hero_id()
	await frames(2)

func _route_cells(view: ELAdventureView) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for mark: Node in view.route.get_children():
		if mark.has_meta("route_cell"): cells.append(mark.get_meta("route_cell"))
	return cells

func _actor_facing(view: ELAdventureView) -> void:
	var hero := view.state.object(view._hero_id())
	var id := int(hero.uid)
	var before: ELModel = view.world.actors[id]
	view.world.orient_actor(id, Vector2.RIGHT)
	var heading := view.world.object_yaw(hero)
	view.world._object_keys.erase(id)
	view.state.event.emit({"kind": "shape_changed", "id": id})
	check(view.world.actors[id] != before and is_equal_approx(view.world.object_yaw(hero), heading) and is_equal_approx(heading, PI / 2.0), "the first game's hero keeps its facing when its model is rebuilt")

## #172: the hero screen's artifact tooltip on a right click.
func _artifact_tip_part(view: ELAdventureView, profile: ELProfile) -> void:
	var hero := view.state.object(view._hero_id())
	var name := ""
	for row: String in profile.table("Artefacts"):
		if not ELMapPickups.artifact_title(profile, row).is_empty():
			name = row
			break
	check(not name.is_empty(), "the game has an artifact with a name")
	if name.is_empty(): return
	var kept: Array = hero.get("artifacts", []).duplicate(true)
	hero.artifacts = [{"name": name, "charges": 2}]
	view.open_hero_screen(int(hero.uid))
	await frames(2)
	var screen := view.hero_screen
	check(screen != null, "the hero screen opens")
	if screen == null:
		hero.artifacts = kept
		return
	var at := screen.slot_rect(0, 0).get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = at
	screen.sheet._gui_input(press)
	await frames(1)
	var tip := screen.skill_tip
	var text := (tip.get_child(0) as Label).text if tip != null and is_instance_valid(tip) else ""
	check(text.begins_with(ELMapPickups.artifact_title(profile, name)) and text == screen.tooltip_at(at), "a right click on an artifact holds up its tooltip (%s)" % text.replace("
", " / "))
	if tip != null and is_instance_valid(tip): check(tip.size.y <= tip.get_combined_minimum_size().y + 0.5 and tip.get_rect().position.y >= 0, "the held tooltip fits its text (%.0f for %.0f)" % [tip.size.y, tip.get_combined_minimum_size().y])
	var release := press.duplicate()
	release.pressed = false
	screen.sheet._gui_input(release)
	await frames(1)
	check(screen.skill_tip == null, "letting the button go closes it")
	screen.closed.emit()
	await frames(2)
	hero.artifacts = kept

## #168: every map object's tooltip, one after another in a mixed order,
## is as tall as its own content and no taller.
func _tooltip_part(view: ELAdventureView) -> void:
	var hud := view.hud
	var contents: Array = []
	for item: Dictionary in view.state.objects.values():
		var content := hud.describe(item, view._art.resolve(item).get("row", {}))
		if not content.is_empty(): contents.append(content)
	var wrapped := contents.filter(func(c: Dictionary) -> bool: return hud.tooltip_body.get_theme_font("font").get_multiline_string_size(str(c.text), HORIZONTAL_ALIGNMENT_LEFT, -1, hud.tooltip_body.get_theme_font_size("font_size")).x > ELTooltipWidth.MAX_WIDTH)
	check(not wrapped.is_empty() and contents.size() > wrapped.size(), "the map has tooltips with wrapped text (%d) and others (%d)" % [wrapped.size(), contents.size() - wrapped.size()])
	var loose: Array[String] = []
	for i in contents.size() * 3:
		var content: Dictionary = contents[(i * 7) % contents.size()]
		hud.show_tooltip(1, content, Vector2(300, 300))
		await process_frame
		var needed := hud.tooltip.get_combined_minimum_size()
		if hud.tooltip.size.y > needed.y + 0.5 and loose.size() < 5: loose.append("%s %.0f for %.0f" % [content.title, hud.tooltip.size.y, needed.y])
	hud.show_tooltip(-1, {}, Vector2.ZERO)
	check(loose.is_empty(), "each map tooltip is as tall as its text, whichever came before (%s)" % ", ".join(loose))

## Castle damage stage (GitHub #48): a saved and loaded castle keeps the model
## of its stage (the save brings the stage back as a float).
func _castle_stage_part(view: ELAdventureView, profile: ELProfile) -> void:
	var codec := ELAdventureSave.new()
	var castles: Dictionary = view.state.scenario.castles
	var player := view.state.current_player
	var saved: Dictionary = castles[player].duplicate()
	for health: int in [int(saved.max), 1]:
		castles[player].health = health
		ELFirstScenario.show_stage(view.state, player)
		var raw: Variant = JSON.parse_string(JSON.stringify(codec.encode(view.director)))
		var back := codec.decode(raw, {"el1": profile})
		check(not back.is_empty(), "a castle save loads: " + codec.error)
		if back.is_empty(): continue
		var castle := ELFirstScenario.castle_object(back.state, player)
		var stage := ELFirstScenario.stage(back.state.scenario.castles[player])
		var art := ELAdventureArt.new(back.state.map)
		var row: Dictionary = art.resolve(castle).get("row", {})
		check(castle.get("castle_stage") is int and int(castle.castle_stage) == stage and int(row.get("Level", -1)) == stage,
			"a loaded castle at %d/%d energy shows its stage %d model (row level %s)" % [health, int(saved.max), stage, row.get("Level")])
		check(ELFirstMapPresentation.spec_effect(castle, row).ends_with(["Castle", "CastleD1", "CastleD2", "CastleD3"][stage]), "its castle effect is the stage %d one" % stage)
	castles[player] = saved
	ELFirstScenario.show_stage(view.state, player)

func _click(at: Vector2, double: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double
	event.position = at
	return event

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
