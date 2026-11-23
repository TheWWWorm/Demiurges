extends SceneTree
## Second-game encounter checks on the installed chapters:
##
## - Declining a battle (PreCombatCancel) knocks the hero back out of every
##   hostile zone, so it can walk away: walking into a guard's zone from each
##   neighbouring direction; a guard that walked up and attacked (its zone
##   reaches three tiles, so no tile next to the hero is free); a last legal
##   place never recorded (a portal exit or a jump into the zone: the library
##   jumped the hero to (-1, -1)); a last legal place the guard now stands on;
##   a fort garrison's battle. The hero must stand on the map, outside every
##   hostile zone, and no battle may start again by itself.
## - A battle script's summons (chapter 13's Musician calls four dragons on its
##   first turn) rise in their summon effect like cast creatures, both when the
##   script runs before the battle opens and during it.
## - Chapter 54's White Lord waits offstage at sea, so he counts as aboard a
##   ship. The portal's remote attack is still fought on the Ether arena (the
##   original's remote attack is an ethereal battle with no script arena); an
##   ordinary attack on the same actor keeps the ship arena.
## - #305, the final island (chapters 44 and 54, map e2mission34_44_54):
##   entering the White Lord's portal offers the remote battle in the
##   pre-battle panel (the original's remote action creates its battle
##   through the routine that opens PrecombatScreen) and declining it returns
##   the hero; the hidden hero keeps its sight (ExHideHero only sinks the
##   model); the teleport effect stands on the portal's footprint centre
##   (ExGetObjectPoint is the figure's point); the closed and collapsed
##   portals show the cancel cursor (a "Simple" building is usable only while
##   its script allows it); the closed portal's one-shot effect plays once
##   when it is placed and not again on later fog refreshes.
##
##   godot --headless --path game --script ../tools/el2_encounter_check.gd -- [--el2=DIR] [--verbose]

const DIRS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
const DRAGON_SCRIPT := "maps\\e2mission13cDragonBoss.scp"

var failures: Array[String] = []
var passes := 0
var verbose := false

func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
		if verbose: print("PASS: ", what)
	else:
		failures.append(what)
		printerr("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _folder() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--el2="): return arg.trim_prefix("--el2=")
	if FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: return String(saved.get("el2", ""))
	return ""

func _run() -> void:
	verbose = "--verbose" in OS.get_cmdline_user_args()
	var profile := ELProfile.new()
	if _folder().is_empty() or not profile.mount("el2", _folder()):
		print("SKIP: no second-game folder")
		quit(0)
		return
	_declines(profile)
	_remote_arena(profile)
	await _final_island(profile)
	await _script_summons()
	if profile.metal_masks != null: profile.metal_masks.stop()
	print("EL2 encounter check: %d passed, %d failed" % [passes, failures.size()])
	quit(1 if not failures.is_empty() else 0)

# --- Declining a battle ------------------------------------------------------

func _settle(director: ELAdventureDirector, frames := 600) -> void:
	for f in frames:
		director.advance(0.05)
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		elif f > 5 and director.can_move(): return
		if director.encounter != null: return

func _set_legal(state: ELAdventureSession, cell: Vector2i) -> void:
	var legal: Variant = state.vm.globals.get("g_MainHeroLastLegalState") if state.vm != null else null
	if legal is ELLuaVM.Table:
		legal.values["x"] = float(cell.x)
		legal.values["y"] = float(cell.y)

func _put(director: ELAdventureDirector, hero: Dictionary, cell: Vector2i) -> void:
	hero.x = cell.x
	hero.y = cell.y
	hero.ap = 50
	hero.intercepted = false
	director.grid.update_actor(hero)
	director._stepped_from.erase(int(hero.uid))

## Declines the open battle and checks the hero is free to leave.
func _decline_frees(state: ELAdventureSession, director: ELAdventureDirector, hero: Dictionary, label: String) -> void:
	var fought := Vector2i(int(hero.x), int(hero.y))
	check(director.decline_encounter(), "%s: the battle can be declined" % label)
	var at := Vector2i(int(hero.x), int(hero.y))
	var again := false
	for frame in 40:
		director.advance(0.05)
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		if director.encounter != null:
			again = true
			director.decline_encounter()
			break
	check(director.grid.contains(at) and director.grid.passability(at, hero.get("ship", false), false) >= 0, "%s: the hero stands on a walkable map tile after declining (%s)" % [label, at])
	check(director.interception.enemies(state, hero, at).is_empty() and not hero.get("intercepted", false), "%s: declining knocks the hero out of every hostile zone (fought at %s, now %s)" % [label, fought, at])
	check(not again, "%s: no battle starts again by itself after declining" % label)

func _session(profile: ELProfile, map_id: String) -> Array:
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(profile):
		if str(found.id).to_lower().ends_with(map_id): entry = found
	var map := ELAdventureMap.new()
	if entry.is_empty() or not map.load_map(profile, str(entry.id)): return []
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, false): return []
	var director := ELAdventureDirector.new()
	if not director.build(state): return []
	_settle(director, 900)
	return [state, director]

## The open approaches into a guard's zone: {dir: [outside cell, zone cell]}.
func _approaches(state: ELAdventureSession, director: ELAdventureDirector, hero: Dictionary, guard: Dictionary) -> Dictionary:
	var result := {}
	var at := Vector2i(int(guard.x), int(guard.y))
	for dir: Vector2i in DIRS:
		for k in range(1, 6):
			var cell := at + dir * k
			if director.grid.passability(cell) < 0: break
			if director.interception.enemies(state, hero, cell).is_empty():
				if director.grid.passability(cell - dir) >= 0 and cell - dir != at: result[dir] = [cell, cell - dir]
				break
	return result

func _declines(profile: ELProfile) -> void:
	var pair := _session(profile, "e2mission11")
	if pair.is_empty():
		print("SKIP: chapter 11 does not open")
		return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	var hero := state.object(state.main_hero)
	# The guard with the most open approaches whose zone intercepts.
	var guard := {}
	var ways := {}
	for gid: int in director.interception.zones.keys():
		var item := state.object(gid)
		if item.get("type") != "monster" or not item.get("alive", false) or not state.hostile(hero, item) or ELForts.garrison_of(state, item).size() > 0: continue
		if not ELInterception.allows(state, hero.uid, gid): continue
		var found := _approaches(state, director, hero, item)
		if found.size() > ways.size():
			guard = item
			ways = found
	check(ways.size() >= 4, "el2 ch11: a guard with open approaches from several sides (%d)" % ways.size())
	if guard.is_empty():
		state.close()
		return
	var home := Vector2i(int(guard.x), int(guard.y))
	# Walking into the zone from each side, straight and diagonal.
	for dir: Vector2i in ways:
		var start: Vector2i = ways[dir][0]
		var enter: Vector2i = ways[dir][1]
		_put(director, hero, start)
		_settle(director)
		if director.encounter != null: director.decline_encounter()
		director.request_move(int(hero.uid), enter)
		for frame in 300:
			director.advance(0.05)
			if not director.dialogue.is_empty(): director.acknowledge("OK")
			if director.encounter != null: break
		var label := "el2 ch11 walking in from %s" % [dir]
		check(director.encounter != null, "%s: entering the zone starts the battle" % label)
		if director.encounter != null: _decline_frees(state, director, hero, label)
	# The guard walked up to the hero and attacked: its zone now reaches three
	# tiles, every tile next to the hero is inside it, and the library's last
	# legal place is where the hero stood.
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(1, 1)]:
		var near := home + dir
		if director.grid.passability(near) < 0: continue
		_put(director, hero, near)
		guard.zone_radius = 3
		director.interception.rebuild(state, director.grid)
		_set_legal(state, near)
		director._begin_encounter(guard, hero)
		var label := "el2 ch11 a guard that walked up attacks from %s" % [dir]
		check(director.encounter != null, "%s: the battle opens" % label)
		if director.encounter != null: _decline_frees(state, director, hero, label)
		guard.erase("zone_radius")
		director.interception.rebuild(state, director.grid)
	# A last legal place never recorded (a portal exit or a scripted jump into
	# the zone): the library jumps the main hero to (-1, -1).
	var beside := home + Vector2i(ways.keys()[0]) if not ways.is_empty() else home + Vector2i(1, 0)
	_put(director, hero, beside)
	_set_legal(state, Vector2i(-1, -1))
	director._begin_encounter(hero, guard)
	if director.encounter != null: _decline_frees(state, director, hero, "el2 ch11 no last legal place (portal exit)")
	# A last legal place the guard itself now stands on.
	_put(director, hero, beside)
	_set_legal(state, home)
	director._begin_encounter(hero, guard)
	if director.encounter != null: _decline_frees(state, director, hero, "el2 ch11 last legal place taken by the guard")
	# A fort garrison's battle: its zone reaches three tiles round the fort.
	for fort: Dictionary in state.objects.values():
		if fort.get("type") != "fort": continue
		var garrison := state.object(fort.get("garrison", -1))
		if not garrison.get("alive", false) or not state.hostile(hero, garrison): continue
		var spot := Vector2i(-1, -1)
		var area := ELInterception.fort_area(director.grid, fort)
		for cell: Vector2i in ELInterception.disc(director.grid, area.position, 2):
			if director.grid.passability(cell) >= 0 and not area.has_point(cell):
				spot = cell
				break
		if spot.x < 0: continue
		_put(director, hero, spot)
		_set_legal(state, spot)
		director._begin_encounter(hero, garrison, -1, int(fort.uid))
		if director.encounter != null: _decline_frees(state, director, hero, "el2 ch11 a fort garrison's battle")
		break
	state.close()

# --- Remote attack arena -----------------------------------------------------

func _remote_arena(profile: ELProfile) -> void:
	for remote: bool in [false, true]:
		var map := ELAdventureMap.new()
		var state := ELAdventureSession.new()
		if not map.load_map(profile, "Maps/e2mission34_44_54") or not state.start(map, 1, 212, "Maps/e2mission54", 1, true):
			check(false, "el2 ch54 loads")
			return
		var director := ELAdventureDirector.new()
		if not director.build(state):
			check(false, "el2 ch54 director builds")
			return
		var lord := {}
		for id: int in state.objects:
			if str(state.objects[id].get("name", "")) == "m54 - White Lord": lord = state.objects[id]
		var hero := state.object(state.main_hero)
		if lord.is_empty() or hero.is_empty():
			check(false, "el2 ch54 has the White Lord and the main hero")
			return
		if not remote: check(bool(lord.get("ship", false)), "el2 ch54 the offstage White Lord counts as aboard a ship")
		director._begin_encounter(hero, lord, int(lord.uid), -1, remote)
		var arena := str(director.encounter.battle.setup.get("arena", "")) if director.encounter != null and director.encounter.battle != null else ""
		if remote: check(arena == "Ether.001", "el2 ch54 the portal's remote attack on the White Lord uses the Ether arena (got %s)" % arena)
		else: check(arena == "Ship.001", "el2 ch54 an ordinary attack on an actor at sea uses the ship arena (got %s)" % arena)
		state.close()

# --- #305: the final island ----------------------------------------------------

const PORTAL_ACTIVE := 50846
const PORTAL_CLOSED := 50847
const PORTAL_COLLAPSE := 50848

func _chapter_row(profile: ELProfile, campaign_id: String, script: String) -> Dictionary:
	var campaign := ELCampaign.new()
	if not campaign.load_campaign(profile, campaign_id): return {}
	for scenario: Dictionary in campaign.scenarios:
		if not str(scenario.script).to_lower().ends_with(script): continue
		var row := scenario.duplicate()
		row.campaign = campaign_id
		var progress := ELSecondCampaign.for_chapter(profile, campaign_id, row, campaign.scenarios.find(scenario) + 1)
		if not progress.is_empty(): row[ELSecondCampaign.KEY] = progress
		return row
	return {}

func _chapter_view(profile: ELProfile, campaign_id: String, script: String) -> ELAdventureView:
	var row := _chapter_row(profile, campaign_id, script)
	if row.is_empty():
		check(false, "#305 %s chapter %s found" % [campaign_id, script])
		return null
	var settings := ELSettings.new()
	settings.use_edition("el2")
	var view := ELAdventureView.new()
	root.add_child(view)
	if not view.build(profile, row, settings, 1):
		check(false, "#305 %s builds: %s" % [script, view.error])
		view.queue_free()
		return null
	if view._mission_fade != null: await view._mission_fade.tree_exited
	for i in 240:
		if not view.director.dialogue.is_empty(): view.director.acknowledge("OK")
		await process_frame
	return view

func _final_island(profile: ELProfile) -> void:
	var saves := _backup(ELSaveSlots.folder("el2"))
	await _final_portal(profile)
	await _closed_portal(profile)
	_restore(ELSaveSlots.folder("el2"), saves)

## Chapter 54 (Diamanda): the active portal and the remote battle it starts.
func _final_portal(profile: ELProfile) -> void:
	var view := await _chapter_view(profile, "White", "e2mission54")
	if view == null: return
	var state := view.state
	var hero := state.object(state.main_hero)
	var portal := state.object(PORTAL_ACTIVE)
	var centre := ELAdventureGrid.center(portal, ELAdventureArt.new(state.map).resolve(portal).get("row", {})) * 2.0
	var point: Array = state._native([float(PORTAL_ACTIVE)], "ExGetObjectPoint")
	check(point.size() == 3 and Vector2(point[0], point[1]) == centre, "#305 ch54 ExGetObjectPoint of the 2 x 2 portal is its figure's footprint centre %s (got %s)" % [centre, point])
	check(ELCursors._second_object(state, hero, portal) == "use", "#305 ch54 the portal the script made usable shows the use cursor")
	# Into the portal: hidden, the teleport effect, then the remote battle.
	hero.x = int(portal.x) - 1
	hero.y = int(portal.y) + 3
	ELFog.refresh(state)
	view.director.use_object(state.main_hero, PORTAL_ACTIVE)
	var hidden_sight := true
	var hidden_seen := false
	var effect_at := Vector3.INF
	var t := 0.0
	while t < 20.0 and not (view.second_precombat != null and view.second_precombat.visible):
		if not view.director.dialogue.is_empty(): view.director.acknowledge("OK")
		if not hero.visible:
			hidden_seen = true
			if not ELFog.visible(state, 1, Vector2i(hero.x, hero.y)) or not ELFog.visible(state, 1, Vector2i(portal.x, portal.y)): hidden_sight = false
		if view.effects.effects.has("TeleportToWhiteLord"): effect_at = view.effects.effects["TeleportToWhiteLord"].node.position
		await process_frame
		t += 1.0 / 60.0
	check(hidden_seen and hidden_sight, "#305 ch54 the hero hidden in the portal keeps its sight of the island (hidden: %s)" % hidden_seen)
	check(effect_at == Vector3(centre.x, 0.0, -centre.y), "#305 ch54 the teleport effect stands on the portal's centre %s (got %s)" % [centre, effect_at])
	var offered := view.second_precombat != null and view.second_precombat.visible and view.director.encounter != null and view.director.encounter.remote
	check(offered, "#305 ch54 the portal's remote battle with the White Lord is offered in the pre-battle panel, not started at once")
	if offered:
		view.decline_encounter()
		await process_frame
		check(view.director.encounter == null and not view.second_precombat.visible and hero.visible, "#305 ch54 declining the portal's battle returns the hero to the island")
	view.queue_free()
	await process_frame

## Chapter 44 (Synthets): the collapsed and the closed portal.
func _closed_portal(profile: ELProfile) -> void:
	var view := await _chapter_view(profile, "Black", "e2mission44")
	if view == null: return
	var state := view.state
	ELFog.reveal_for_console(state, 1, true)
	for i in 3: await process_frame
	var hero := state.object(state.main_hero)
	var collapse := state.object(PORTAL_COLLAPSE)
	var closed := state.object(PORTAL_CLOSED)
	check(ELCursors._second_object(state, hero, collapse) == "cancel", "#305 ch44 the collapsing portal shows the cancel cursor")
	# The script's swap after Diamanda's death.
	var at := Vector2i(collapse.x, collapse.y)
	var away := Vector2i(closed.x, closed.y)
	for call: Array in [[[PORTAL_COLLAPSE], "ExTakeObject"], [[PORTAL_CLOSED], "ExTakeObject"], [[PORTAL_COLLAPSE, away.x, away.y], "ExPlaceObject"], [[PORTAL_CLOSED, at.x, at.y], "ExPlaceObject"]]:
		state._native(call[0].map(func(v: int) -> float: return float(v)), call[1])
	await process_frame
	check(ELCursors._second_object(state, hero, closed) == "cancel", "#305 ch44 the closed portal shows the cancel cursor")
	var name := "shrine:%d" % PORTAL_CLOSED
	check(view.effects.effects.has(name), "#305 ch44 the closed portal plays its closing effect when it is set down")
	var t := 0.0
	while view.effects.effects.has(name) and t < 30.0:
		await process_frame
		t += 1.0 / 60.0
	var replayed := false
	for step in 3:
		state.fog.revision = ELFog.revision(state) + 1
		for i in 3: await process_frame
		replayed = replayed or view.effects.effects.has(name)
	check(t < 30.0 and not replayed, "#305 ch44 the closing effect plays once and not again with later fog refreshes (moves)")
	state._native([float(PORTAL_CLOSED)], "ExTakeObject")
	state._native([float(PORTAL_CLOSED), float(at.x), float(at.y)], "ExPlaceObject")
	await process_frame
	check(view.effects.effects.has(name), "#305 ch44 a portal placed again plays its effect anew")
	view.queue_free()
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

# --- Battle script summons ---------------------------------------------------

func _dragons(view: Node) -> Array[int]:
	var ids: Array[int] = []
	for id: int in view.duel.creatures:
		if String(view.duel.creatures[id].card) in ["BLDG", "GRDG", "RDDG", "BUDG"]: ids.append(id)
	return ids

func _script_summons() -> void:
	for opening: bool in [true, false]:
		var view: Node = load("res://scenes/duel.tscn").instantiate()
		view.demo = true
		root.add_child(view)
		for i in 3: await process_frame
		var profile: ELProfile = view.profiles.get("el2")
		if profile == null:
			view.queue_free()
			return
		var hero := {"faction": "Green", "level": 7, "health": 28, "cards": ELCatalog.available_cards(profile, "Green").slice(0, 12), "kind": "hero"}
		var dragon := {"faction": "Blue", "shape": "DragonGreen", "kind": "hero", "title": "Musician", "level": 16, "health": 140, "cards": ELCatalog.available_cards(profile, "Blue").slice(0, 12)}
		view._start("el2", {"arena": "Green.001", "adventure": true, "players": [hero, dragon], "scripts": [{"name": DRAGON_SCRIPT, "side": 1}], "first_side": 1 if opening else 0})
		var label := "el2 Musician's dragons (%s)" % ("summoned before the battle opens" if opening else "summoned on its first turn")
		var seen_hidden := {}
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 40000:
			for id: int in _dragons(view):
				if view.models.has(id) and not view.models[id].visible and view.models[id].get_meta("arriving", false): seen_hidden[id] = true
			if _dragons(view).size() >= 4 and view._arrivals.is_empty() and _dragons(view).all(func(id: int) -> bool: return view.models.has(id) and view.models[id].visible): break
			await process_frame
		var ids := _dragons(view)
		check(ids.size() == 4, "%s: the script summons four dragons (%d)" % [label, ids.size()])
		check(seen_hidden.size() == ids.size() and not ids.is_empty(), "%s: each dragon waits for its summon effect instead of standing there at once (%d of %d)" % [label, seen_hidden.size(), ids.size()])
		check(not ids.is_empty() and ids.all(func(id: int) -> bool: return view.models.has(id) and view.models[id].visible), "%s: every dragon appears in the end" % label)
		view.queue_free()
		for i in 3: await process_frame
