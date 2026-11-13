extends SceneTree
## Headless check of first-game map details:
## - the minimap draws a castle or site marker only once the local player
##   has explored the building, and every marker with the console's open_fog;
## - a double-click on the player's own castle opens its GlobalSpells screen
##   (the click before it orders nothing), a double-click on bare ground
##   does not;
## - a spell picture on that screen has the picture tooltip with the spell's
##   name and description from the game's texts, and no plain text tooltip.
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
	# A double-click on bare ground beside the castle opens nothing.
	var ground := Vector3(centre.x + (size.x * 0.5 + 6) * ELAdventureTerrain.CELL, 0, centre.z)
	check(not view.castle_double_click(view.camera.unproject_position(ground), ground) and view.global_spells == null, "a double-click away from the castle opens nothing")
	view.queue_free()
	await frames(2)

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
