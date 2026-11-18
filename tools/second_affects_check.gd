extends SceneTree
## Headless check of the second game's hero affect icons (ELAffectStrip):
## - an icon index picks its AFFECTS_01/02 sheet (25 each) and its 50 px cell,
##   five columns of five filled top to bottom;
## - on the map, each affect of the hero shows its AffectsList icon at the top
##   right: the first 60 px from the right edge and 10 px down, the next 60 px
##   further left; the tooltip is the row's Tooltip, plus Tooltip2 with the
##   days left for an affect that runs out; without affects there is none;
## - activating a time building or entering a range building's area flips
##   the new icon for 750 ms; HUD refreshes keep its place in the animation;
## - in a map battle the same icons are shown over the arena, the time
##   battleground's script is loaded for the hero's side, and the icons go
##   when the map returns.
##
##   godot --headless --path game --script ../tools/second_affects_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped. Saves the map writes are put back as they were.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _wait(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_cells()
	await _map_and_battle()
	print("SECOND AFFECTS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _cells() -> void:
	var first := ELAffectStrip.cell(7)
	var later := ELAffectStrip.cell(44)
	check(first.sheet == 0 and first.region == Rect2(50, 100, 50, 50), "icon 7 is AFFECTS_01 column 1, row 2: %s" % str(first))
	check(later.sheet == 1 and later.region == Rect2(150, 200, 50, 50), "icon 44 is AFFECTS_02 column 3, row 4: %s" % str(later))
	check(ELAffectStrip.cell(0).region == Rect2(0, 0, 50, 50), "icon 0 is the first cell")

func _map_and_battle() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		return
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await _wait(3)
	if not view.profiles.has("el2"):
		print("SKIP: the second game's files could not be mounted")
		view.queue_free()
		return
	_entrances(view.profiles.el2)
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(view.profiles.el2):
		if str(found.id).to_lower().ends_with("e2mission11"): entry = found
	var saves := _backup(ELSaveSlots.folder("el2"))
	await view._begin_campaign("el2", ELSingleScenario.scenario(entry), 1)
	var map: ELAdventureView = view.campaign_view
	check(map != null, "chapter 11 opens")
	if map == null:
		_restore(ELSaveSlots.folder("el2"), saves)
		view.queue_free()
		return
	var state := map.state
	var director := map.director
	var profile := state.map.profile
	if map._mission_fade != null: await map._mission_fade.tree_exited
	for i in 40:
		if director.dialogue.is_empty(): break
		director.acknowledge("OK")
		await _wait(3)
	var hero := state.object(state.main_hero)
	var strip: ELAffectStrip = map.second_hud.affect_strip if map.second_hud != null else null
	check(strip != null and strip.sheets.size() == 2 and strip.sheets.all(func(t: Texture2D) -> bool: return t != null) and strip.frame != null,
		"the map panel has the affect strip with both icon sheets and the frame")
	if strip == null:
		_restore(ELSaveSlots.folder("el2"), saves)
		view.queue_free()
		return
	hero.affects = []
	map._refresh_hero_info()
	check(strip.entries.is_empty(), "a hero without affects shows no icons")
	var rows := profile.table("AffectsList")
	hero.affects = [{"name": "ShrineOfOrdering", "id": "ShrineOfOrdering"},
		{"name": "VolcanicEruption", "id": "combat:-1", "script": "VolcanicEruption", "kind": "time", "ticks": 7, "building": -1}]
	state.event.emit({"kind": "affects_changed", "id": hero.uid})
	map._refresh_hero_info()
	var icons := strip.entries.map(func(item: Dictionary) -> int: return int(item.icon))
	check(icons == [int(rows.ShrineOfOrdering.Icon), int(rows.VolcanicEruption.Icon)], "each affect shows its AffectsList icon, in order: %s" % str(icons))
	var days := profile.text(str(rows.VolcanicEruption.Tooltip2)).replace("%d", "7")
	check(strip.entries.size() == 2 and strip.entries[0].tooltip == profile.text(str(rows.ShrineOfOrdering.Tooltip))
		and strip.entries[1].tooltip == profile.text(str(rows.VolcanicEruption.Tooltip)) + "\n" + days, "tooltips: the row's Tooltip, and «%s» for the time affect" % days)
	var width := strip.size.x
	check(strip.icon_rect(0) == Rect2(width - 60, 10, 50, 50) and strip.icon_rect(1) == Rect2(width - 120, 10, 50, 50),
		"the first icon is 60 px from the right edge, 10 px down; the next 60 px to its left")
	check(strip._get_tooltip(strip.icon_rect(1).get_center()) == strip.entries[1].tooltip and strip._get_tooltip(Vector2(5, 5)) == "", "hovering an icon gives its tooltip")
	# The battle: the same icons over the arena, the battleground's script loaded.
	var monster := _hostile_monster(state, hero)
	if monster.is_empty():
		print("SKIP: no creature to fight on chapter 11")
	else:
		var scripts := ELBattleScripts.select(state, [hero.uid, monster.uid])
		check(scripts.any(func(item: Dictionary) -> bool: return item.name == "VolcanicEruption" and item.side == 0), "the time battleground's script is loaded for the hero's side: %s" % str(scripts))
		director._begin_encounter(hero, monster)
		await _wait(3)
		map.begin_encounter()
		await _wait(10)
		if view._campaign_battle() == null or view.duel != view._campaign_battle():
			check(false, "the battle opens")
		else:
			var battle_strip: ELAffectStrip = view.affect_strip
			var shown := battle_strip.entries.map(func(item: Dictionary) -> int: return int(item.icon))
			check(battle_strip.is_visible_in_tree() and shown == icons, "the battle shows the hero's affect icons at the top right: %s" % str(shown))
			check(not battle_strip.is_processing(), "the battle displays the established affects immediately")
			check(is_equal_approx(battle_strip.icon_rect(0).position.y, 10.0 * battle_strip.ui_scale) and is_equal_approx(battle_strip.icon_rect(0).end.x, battle_strip.size.x - 10.0 * battle_strip.ui_scale),
				"over the battle the first icon ends 10 px from the right edge at the panel's scale: %s in %s at %s" % [battle_strip.icon_rect(0), battle_strip.size, battle_strip.ui_scale])
			view._surrender_encounter()
			var start := Time.get_ticks_msec()
			while director.encounter != null and Time.get_ticks_msec() - start < 20000: await process_frame
			check(director.encounter == null and battle_strip.entries.is_empty(), "the battle icons go when the map returns")
	_restore(ELSaveSlots.folder("el2"), saves)
	view.queue_free()
	await _wait(3)

func _entrances(profile: ELProfile) -> void:
	var level := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	var director := ELAdventureDirector.new()
	if not level.load_map(profile, "e2mission12_52") or not state.start(level, 1, 212, "Maps/e2mission12") or not director.build(state):
		check(false, "#209: the chapter with time and range battlegrounds opens")
		state.close()
		return
	var hero := state.object(state.main_hero)
	var time_site := {}
	var range_site := {}
	for site: Dictionary in state.objects.values():
		if site.name == "E2Green8": time_site = site
		if site.name == "E2Green6": range_site = site
	if hero.is_empty() or time_site.is_empty() or range_site.is_empty():
		check(false, "#209: the hero, Nature Revolt and Toxin Dump exist")
		state.close()
		return
	var hud := ELSecondAdventureHud.new()
	root.add_child(hud)
	if not hud.build(state):
		check(false, "#209: the adventure HUD opens")
		hud.free()
		state.close()
		return
	var strip := hud.affect_strip
	state._native([float(hero.uid), time_site.x - 1.0, float(time_site.y)], "ExJumpToPos")
	hud.refresh(int(hero.uid), true)
	var activated := ELBattlegrounds.use(director, hero, time_site)
	hud.refresh_affects(hero)
	check(activated and strip.entries.size() == 1 and strip.entries[0].name == "NatureRevolt" and strip._icon_draw_rect(0).size.x == 0.0,
		"#209: activating Nature Revolt starts its icon edge-on")
	if strip.entries.size() == 1:
		strip._process(0.125)
		var part := strip._icon_draw_rect(0)
		check(part.size.x == 35.0 and part.get_center() == strip.icon_rect(0).get_center(), "#209: the face turns around the middle of its slot")
		hero.affects[0].ticks -= 1
		hud.refresh_affects(hero)
		check(strip._icon_draw_rect(0) == part, "#209: updating the days remaining preserves the entrance")
		strip._process(0.625)
		check(strip._icon_draw_rect(0) == strip.icon_rect(0) and not strip.is_processing(), "#209: the icon settles at full width after 750 ms")
	state._native([float(hero.uid), range_site.x + 11.0, float(range_site.y)], "ExJumpToPos")
	hud.refresh_affects(hero)
	check(strip.entries.size() == 1, "#209: Toxin Dump is absent outside its range")
	state._native([float(hero.uid), range_site.x + 10.0, float(range_site.y)], "ExJumpToPos")
	hud.refresh_affects(hero)
	check(strip.entries.size() == 2 and strip.entries[1].name == "ToxinDump" and strip._icon_draw_rect(1).size.x == 0.0
		and strip._icon_draw_rect(0) == strip.icon_rect(0), "#209: entering range animates only the newly acquired Toxin Dump icon")
	strip._process(0.25)
	state._native([float(hero.uid), range_site.x + 11.0, float(range_site.y)], "ExJumpToPos")
	hud.refresh_affects(hero)
	state._native([float(hero.uid), range_site.x + 10.0, float(range_site.y)], "ExJumpToPos")
	hud.refresh_affects(hero)
	check(strip.entries.size() == 2 and strip._icon_draw_rect(1).size.x == 0.0, "#209: returning to range starts a fresh entrance")
	hud.free()
	state.close()

func _hostile_monster(state: ELAdventureSession, hero: Dictionary) -> Dictionary:
	var best := {}
	var best_distance := INF
	for item: Dictionary in state.objects.values():
		if item.get("type") != "monster" or not item.get("alive", false) or not item.get("visible", true) or int(item.get("x", -1)) < 0: continue
		if not state.hostile(hero, item): continue
		var distance := Vector2(float(item.x), float(item.y)).distance_to(Vector2(float(hero.x), float(hero.y)))
		if distance > 0.5 and distance < best_distance:
			best = item
			best_distance = distance
	return best

func _backup(folder: String) -> Dictionary:
	var files := {}
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder): files[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return files

func _restore(folder: String, files: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file: String in DirAccess.get_files_at(folder):
		if not files.has(file): DirAccess.remove_absolute(folder.path_join(file))
	for file: String in files:
		var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		if out != null: out.store_buffer(files[file])
