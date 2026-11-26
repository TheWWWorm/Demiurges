extends SceneTree
## Headless check of two second-game player reports on map transitions:
##
## - #327: the Vitals' first chapter opens behind a black fade and its script
##   (a 2 s wait, then the hero's first line) runs on under the fade, as the
##   original's mission tick does: the first line opens as the fade ends, not
##   2 s later. The box never shows while the map is still covered.
## - #329: a won map battle closes as the winner's victory clip ends, with no
##   wait after it: the battle fades to black over 1 s, the battle's results
##   are applied under the black and the map fades in from it over 1 s. The
##   after-battle report waits for the map to be uncovered. The first game's
##   battles still return at once when the clip ends.
##
##   godot --headless --path game --script ../tools/issues_327_329_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Map saves the chapters write are put back as they were.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is Dictionary and paths.has("el2"):
		var saves := _backup(ELSaveSlots.folder("el2"))
		await _vitals_opening(str(paths.el2))
		await _battle_end("el2")
		await _battle_end("el2", true)
		_restore(ELSaveSlots.folder("el2"), saves)
	else: print("SKIP: no second-game files configured (user://profiles.json)")
	if paths is Dictionary and paths.has("el1"):
		var saves := _backup(ELSaveSlots.folder("el1"))
		await _battle_end("el1")
		_restore(ELSaveSlots.folder("el1"), saves)
	else: print("SKIP: no first-game files configured (user://profiles.json)")
	print("ISSUES 327 329: %d failure(s)" % failures)
	quit(int(failures > 0))

## #327: the Vitals' first chapter, as the campaign starts it.
func _vitals_opening(folder: String) -> void:
	var profile := ELProfile.new()
	if not profile.mount("el2", folder):
		print("SKIP: the second game's files could not be mounted")
		return
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(profile, "Green"):
		print("SKIP: no Vitals campaign")
		return
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Green"
	var progress := ELSecondCampaign.for_chapter(profile, "Green", row, 1)
	if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	var built := view.build(profile, row, settings, 1)
	check(built and str(row.file_name).to_lower() == "e2mission11", "#327: the Vitals' first chapter (e2mission11) builds: %s" % view.error)
	if not built:
		view.queue_free()
		return
	var curtain := view._mission_fade
	check(curtain != null and curtain.color.a == 1.0, "#327: the chapter opens behind a black fade")
	var director := view.director
	var waited := false
	var box_during_fade := false
	var start := Time.get_ticks_msec()
	while view._mission_fade != null and Time.get_ticks_msec() - start < 6000:
		await process_frame
		if director._waiting and director.wait_remaining < 1.9: waited = true
		if view.second_dialogue.visible: box_during_fade = true
	var remaining := director.wait_remaining if director._waiting else 0.0
	print("  #327: fade over after %.2f s; the script's opening wait has %.2f s left" % [(Time.get_ticks_msec() - start) / 1000.0, remaining])
	check(waited, "#327: the opening script's 2 s wait runs under the fade")
	check(not box_during_fade, "#327: no dialogue box shows while the map is covered")
	check(remaining < 0.5, "#327: the opening wait is (nearly) over when the fade ends (%.2f s left)" % remaining)
	var shown := false
	var frames_after := 0
	for i in 600:
		await process_frame
		frames_after += 1
		if view.second_dialogue.visible:
			shown = true
			break
		if not director.dialogue.is_empty() and frames_after > 120: break
	check(shown and str(director.dialogue.get("text_id", "")).contains("MAINHERO_11"), "#327: the hero's first line opens right after the fade (%d frames)" % frames_after)
	check(frames_after <= 60, "#327: no 2 s pause between the fade and the first line (%d frames)" % frames_after)
	view.queue_free()
	await process_frame
	await process_frame

## #329: a campaign battle won by the player.
func _battle_end(edition: String, monster := false) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return
	view.settings.values.show_tutorial = false
	var row := {}
	if edition == "el2": row = {"file_name": "Maps/e2mission13", "script": "Maps/e2mission13"}
	else:
		ELFirstTutorial.for_settings(view.settings).persist = false
		var campaign := ELCampaign.new()
		campaign.load_campaign(view.profiles.el1, "Good")
		row = campaign.scenarios[0].duplicate()
		row.campaign = "Good"
	await view._begin_campaign(edition, row, 1)
	var map: ELAdventureView = view.campaign_view
	var label := "%s %s" % [edition, "monster" if monster or edition == "el1" else "boss"]
	if map == null:
		check(false, "#329 %s: the campaign map loads" % label)
		await _close(view)
		return
	for i in 600:
		await process_frame
		if map._mission_fade == null and map.director.dialogue.is_empty(): break
		if not map.director.dialogue.is_empty(): map.director.acknowledge()
	var state := map.state
	var opponent := -1
	if edition == "el2" and not monster: opponent = int(state.vm.globals.ID_C_BOSS)
	else:
		for id: int in state.objects:
			var item: Dictionary = state.objects[id]
			if item.get("type") == "monster" and item.alive and int(item.get("owner", 0)) != 1:
				opponent = id
				break
	var encounter := ELAdventureEncounter.new()
	var prepared := opponent >= 0 and encounter.prepare(state, state.main_hero, opponent)
	check(prepared, "#329 %s: a map battle is set up (%s)" % [label, encounter.error])
	if not prepared:
		await _close(view)
		return
	map.director.encounter = encounter
	view._begin_encounter(state.main_hero, opponent)
	var duel: ELDuel = view.duel
	var side: int = view._battle_player_side(duel)
	for i in 3000:
		await process_frame
		if view._human_turn() and not view.end_button.disabled: break
	duel.heroes[1 - side].health = 1
	duel.heroes[side].mana = 20
	if not duel.cast_free(side, "ZAPP", [1 - side], true):
		check(false, "#329 %s: the deciding cast is legal (%s)" % [label, duel.error])
		await _close(view)
		return
	# Timeline in wall-clock seconds (the battle's own clock stops when it closes).
	var marks := {}
	var clip_length := 0.0
	var map_alpha_at_show := -1.0
	var report_under_fade := false
	var darkest := 0.0
	var map_seen_under_battle := false
	var start := Time.get_ticks_msec()
	for i in 6000:
		view.ai_clock = -1000.0
		await process_frame
		var t := (Time.get_ticks_msec() - start) / 1000.0
		var stage := "" if view.ending.is_empty() else String(view.ending.stage)
		if stage == "victory" and not marks.has("victory"):
			marks.victory = t
			clip_length = float(view.ending.length)
		if stage == "over" and not marks.has("over"): marks.over = t
		var fade: ColorRect = view._battle_fade
		if fade != null and not marks.has("fade_start"): marks.fade_start = t
		if fade != null: darkest = maxf(darkest, fade.color.a)
		if fade != null and map.visible: map_seen_under_battle = true
		if map.visible and not marks.has("map"):
			marks.map = t
			map_alpha_at_show = map._mission_fade.color.a if map._mission_fade != null else 0.0
		if marks.has("map") and map._mission_fade == null and not marks.has("map_clear"): marks.map_clear = t
		if map._mission_fade != null and (map.building_message != null or map.second_dialogue.visible): report_under_fade = true
		if marks.has("map_clear") and (map.building_message != null or t - float(marks.map_clear) > 4.0): break
		if t > 40.0: break
	print("  #329 %s: victory clip %.2f s; marks %s" % [label, clip_length, marks])
	check(marks.has("victory") and marks.has("over") and marks.has("map"), "#329 %s: the winner celebrates and the map comes back" % label)
	if not (marks.has("victory") and marks.has("over") and marks.has("map")):
		await _close(view)
		return
	var after_clip := float(marks.over) - float(marks.victory)
	check(after_clip <= clip_length + 0.1, "#329 %s: the battle is over when the victory clip ends (%.2f s for a %.2f s clip)" % [label, after_clip, clip_length])
	if edition == "el2":
		check(marks.has("fade_start") and float(marks.fade_start) - float(marks.over) <= 0.1, "#329 %s: the fade to black starts as the clip ends" % label)
		var out := float(marks.map) - float(marks.get("fade_start", marks.over))
		check(darkest >= 0.85 and not map_seen_under_battle, "#329 %s: the battle fades to black before the map shows (alpha %.2f seen)" % [label, darkest])
		check(out >= 0.9, "#329 %s: the fade to black lasts about 1 s (%.2f s to the map, results applied under the black)" % [label, out])
		check(map_alpha_at_show >= 0.8, "#329 %s: the map shows from black (alpha %.2f)" % [label, map_alpha_at_show])
		var fade_in := float(marks.get("map_clear", 0.0)) - float(marks.map)
		check(marks.has("map_clear") and fade_in >= 0.8 and fade_in <= 1.4, "#329 %s: the map fades in over about 1 s (%.2f s)" % [label, fade_in])
		check(not report_under_fade, "#329 %s: the after-battle report waits for the map to be uncovered" % label)
	else:
		check(not marks.has("fade_start") and float(marks.map) - float(marks.over) <= 0.2, "#329 %s: the first game's battle returns at once when the clip ends" % label)
	await _close(view)

func _close(view: Node) -> void:
	if view.campaign_view != null: view._leave_campaign()
	view.queue_free()
	await process_frame
	await process_frame

func _backup(folder: String) -> Dictionary:
	var kept := {}
	if not DirAccess.dir_exists_absolute(folder): return kept
	for file in DirAccess.get_files_at(folder): kept[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return kept

func _restore(folder: String, kept: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file in DirAccess.get_files_at(folder):
		if kept.has(file):
			if FileAccess.get_file_as_bytes(folder.path_join(file)) != kept[file]:
				var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
				out.store_buffer(kept[file])
		else: DirAccess.remove_absolute(folder.path_join(file))
