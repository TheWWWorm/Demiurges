extends SceneTree
## Headless check of campaign state that must survive a save, and of the
## map director's timing, on the installed games' maps:
## - second game: a direct script message box open with an empty command
##   queue, a queued Text message (its close runs Hook_OnCloseMessageBox and
##   finishes that command only), a scripted move whose queue a script cleared
##   or cleared and replaced (finishing the old move leaves the new command
##   alone), a move restored from an older save without the running-command
##   field, and a huge saved camera angle: each save its writer accepts reads
##   back;
## - second game: the mission update runs 15 ticks per second at any frame
##   length (60, 20 and 7.5 frames per second), at most four per frame;
## - second game: a hero walking into a guard's zone is stopped on the first
##   zone tile it enters, at any frame length and in fast mode (Hook_OnStep
##   runs on every tile entered);
## - second game: MoveAndUseObject whose target a script moved meanwhile ends
##   at the old place without a battle; unmoved, it still starts one;
## - first game: a hero dismissed or killed inside a training camp frees the
##   camp and stays placed, the world saves and loads, and a resurrected camp
##   hero is placed again; a save from before the fix (fallen hero left
##   unplaced) loads;
## - first game: a reserve spell goes over an occupied book slot (a cantrip
##   waits underneath, another spell goes to the reserve with its runes);
## - the Lua VM frees temporary tables, still saves its tables, and charges
##   built-in loops to the instruction budget.
##
##   godot --headless --path game --script ../tools/campaign_state_check.gd
##
## Needs the original games' files (user://profiles.json); a game without
## them is skipped (the Lua VM part runs regardless). Nothing is saved.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary: paths = {}
	_lua_vm()
	var second := _mount("el2", paths)
	if second != null:
		_dialogue_saves(second)
		_dialogue_loot(second)
		_kinet_sighting(second)
		_command_identity(second)
		_tick_rate(second)
		_tile_interception(second)
		_moved_target(second)
	var first := _mount("el1", paths)
	if first != null:
		_training_camp(first)
		_book_slots(first)
	print("CAMPAIGN STATE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _mount(edition: String, paths: Dictionary) -> ELProfile:
	var profile := ELProfile.new()
	if not paths.has(edition) or not profile.mount(edition, str(paths[edition])):
		print("SKIP: %s files are not configured" % edition)
		return null
	return profile

# --- helpers ----------------------------------------------------------------

func _second_session(profile: ELProfile, map_id: String) -> Array:
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

func _settle(director: ELAdventureDirector, frames := 600) -> void:
	for f in frames:
		director.advance(0.05)
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		elif f > 5 and director.can_move(): return
		if director.encounter != null: return

## encode -> JSON -> decode, as a quick save and its load do; {} when either
## side refuses (the reason is in `why`).
func _round_trip(director: ELAdventureDirector, why: Array, edit := Callable()) -> Dictionary:
	var codec := ELAdventureSave.new()
	var document := codec.encode(director, {})
	if document.is_empty():
		why.append("encode: " + codec.error)
		return {}
	var raw: Variant = JSON.parse_string(JSON.stringify(document, "", true, true))
	if edit.is_valid(): edit.call(raw)
	var restored := codec.decode(raw, {director.state.map.profile.id: director.state.map.profile})
	if restored.is_empty(): why.append("decode: " + codec.error)
	return restored

## Counts Hook_OnCloseMessageBox calls (in place of the map's hook).
func _count_closes(state: ELAdventureSession) -> Array:
	var count := [0]
	state.vm.bind("Hook_OnCloseMessageBox", func(_arguments: Array) -> Array:
		count[0] += 1
		return [])
	return count

func _free_cell_near(director: ELAdventureDirector, at: Vector2i, reach := 6) -> Vector2i:
	for radius in range(1, reach + 1):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := at + Vector2i(x, y)
				if director.grid.contains(cell) and director.grid.passability(cell, false) >= 0: return cell
	return Vector2i(-1, -1)

# --- 1. dialogues -------------------------------------------------------------

func _dialogue_saves(profile: ELProfile) -> void:
	var pair := _second_session(profile, "e2mission11")
	if pair.is_empty():
		print("SKIP: chapter 11 does not open")
		return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	var hero := state.object(state.main_hero)
	# A direct script box with no queued command.
	state.commands.clear()
	state.event.emit({"kind": "message_box", "speaker": float(hero.uid), "text": "Direct line", "question": false, "hook": true})
	check(director.dialogue.get("direct", false) and state.commands.is_empty(), "el2: a direct message box is open with an empty command queue")
	var why: Array = []
	var restored := _round_trip(director, why)
	check(not restored.is_empty(), "el2: a save with a direct box open and no command reads back %s" % [why])
	if not restored.is_empty():
		var next: ELAdventureDirector = restored.director
		var closed := _count_closes(next.state)
		check(next.dialogue.get("direct", false) and next.dialogue.text == "Direct line", "el2: the restored direct box is the one saved")
		check(next.acknowledge("OK") and next.dialogue.is_empty() and next.state.commands.is_empty(), "el2: the restored direct box closes and finishes no command")
		check(closed[0] == 1, "el2: closing the restored direct box runs Hook_OnCloseMessageBox")
		next.state.close()
	director.acknowledge("OK")
	# A queued Text with a command after it.
	var text := {"kind": "Text", "arguments": [float(hero.uid), "T_CHECK_LINE"]}
	var after := {"kind": "Wait", "arguments": [60000.0]}
	state.commands.append(text)
	state.commands.append(after)
	for frame in 30:
		director.advance(0.05)
		if not director.dialogue.is_empty(): break
	check(not director.dialogue.is_empty() and not director.dialogue.get("direct", false), "el2: a queued Text message opens")
	restored = _round_trip(director, why)
	check(not restored.is_empty(), "el2: a save with a queued message open reads back %s" % [why])
	if not restored.is_empty():
		var next: ELAdventureDirector = restored.director
		var closed := _count_closes(next.state)
		check(next.running_command() == "head", "el2: the restored message is still the queue's running command")
		next.acknowledge("OK")
		check(next.state.commands.size() == 1 and next.state.commands[0].kind == "Wait", "el2: closing the restored message finishes it alone")
		check(closed[0] == 1, "el2: closing the restored message runs Hook_OnCloseMessageBox")
		next.state.close()
	# The script cleared the queue while the message was open.
	state.commands.clear()
	restored = _round_trip(director, why)
	check(not restored.is_empty(), "el2: a save with a message open after the queue was cleared reads back %s" % [why])
	if not restored.is_empty():
		var next: ELAdventureDirector = restored.director
		next.state.commands.append({"kind": "Wait", "arguments": [60000.0]})
		next.acknowledge("OK")
		check(next.state.commands.size() == 1, "el2: closing that restored message leaves a later command alone")
		next.state.close()
	director.acknowledge("OK")
	# A huge camera angle (older builds let it grow without bound).
	state.commands.clear()
	director._waiting = false
	restored = _round_trip(director, why, func(raw: Dictionary) -> void: raw.world.camera_rotation = 3.6e9 + 90.0)
	check(not restored.is_empty() and is_equal_approx(restored.state.camera_rotation, 90.0), "el2: a save with a huge camera angle reads back within one turn (%s) %s" % [restored.state.camera_rotation if not restored.is_empty() else "-", why])
	if not restored.is_empty(): restored.state.close()
	check(is_equal_approx(ELAdventureSave.normal_degrees(-90.0), 270.0) and ELAdventureSave.normal_degrees(720.0) == 0.0, "camera angles normalise into [0, 360)")
	state.close()

func _dialogue_loot(profile: ELProfile) -> void:
	var pair := _second_session(profile, "e2mission11")
	if pair.is_empty():
		check(false, "#231: chapter 11 opens")
		return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	state.commands.clear()
	state._native([], "ExStartLootMessage")
	state._native(["GRSN"], "ExAddLootMessageSpell")
	state._native(["ExSendLootMessage"], "ExAddCommandExecuteScriptFunction")
	state._native([float(state.main_hero), "T_CHECK_AFTER_LOOT"], "ExAddCommandText")
	director.advance(0.1)
	director.advance(0.1)
	check(director.dialogue.get("box") == "loot" and director.dialogue.get("items", []).size() == 1
		and state.commands.size() == 1 and state.commands[0].kind == "Text", "#231: scripted loot holds the next dialogue line")
	var why: Array = []
	var restored := _round_trip(director, why)
	check(not restored.is_empty(), "#231: the open loot report and waiting line survive a save %s" % [why])
	if not restored.is_empty():
		var next: ELAdventureDirector = restored.director
		var closed := _count_closes(next.state)
		next.acknowledge()
		next.advance(0.1)
		check(next.dialogue.get("text_id") == "T_CHECK_AFTER_LOOT" and closed[0] == 0,
			"#231: acknowledging the restored loot opens the next line without a dialogue close hook")
		next.state.close()
	state.close()

func _kinet_sighting(profile: ELProfile) -> void:
	var pair := _second_session(profile, "e2mission13")
	if pair.is_empty():
		check(false, "#222: chapter 13 opens")
		return
	var state: ELAdventureSession = pair[0]
	var kinet := state.object(state.vm.globals.get("ID_KINET_HERO"))
	var heroes: ELLuaVM.Table = state.vm.globals.Heroes
	var avatar: ELLuaVM.Table = heroes.values.Avatar
	var seen := func(command: Dictionary) -> bool:
		return command.kind == "Text" and str(command.arguments[1]).begins_with("MV_M13_S26_P01")
	state._native([float(state.main_hero), float(kinet.x), float(kinet.y)], "ExJumpToPos")
	state.commands.clear()
	avatar.values.KinetHero = "Start"
	check(state.hook("Hook_OnStep") and state.commands.any(seen), "#222: nearing the living Kinet queues the sighting dialogue")
	state._native([float(kinet.uid)], "ExKillHero")
	state.commands.clear()
	avatar.values.KinetHero = "Start"
	check(state.hook("Hook_OnStep") and not state.commands.any(seen), "#222: nearing the fallen Kinet skips the sighting dialogue")
	state.close()

# --- 4. the running command's identity -----------------------------------------

func _scripted_move(state: ELAdventureSession, director: ELAdventureDirector, hero: Dictionary) -> bool:
	var at := Vector2i(int(hero.x), int(hero.y))
	var goal := Vector2i(-1, -1)
	for distance in range(8, 3, -1):
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell := at + dir * distance
			if director.grid.contains(cell) and director.grid.path(at, cell).size() > 3:
				goal = cell
				break
		if goal.x >= 0: break
	if goal.x < 0: return false
	state.commands.append({"kind": "Moving", "arguments": [float(hero.uid), float(goal.x), float(goal.y)]})
	for frame in 20:
		director.advance(1.0 / 60.0)
		if not director.movement.is_empty() and int(director.movement.index) >= 1: break
	return director.movement.get("queued", false)

func _command_identity(profile: ELProfile) -> void:
	var pair := _second_session(profile, "e2mission11")
	if pair.is_empty(): return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	var hero := state.object(state.main_hero)
	var home := Vector2i(int(hero.x), int(hero.y))
	var why: Array = []
	for case: String in ["cleared", "replaced", "kept", "legacy"]:
		state.commands.clear()
		director._complete_movement(false)
		hero.x = home.x
		hero.y = home.y
		director.grid.update_actor(hero)
		if not _scripted_move(state, director, hero):
			check(false, "el2: a scripted move starts (%s)" % case)
			continue
		if case in ["cleared", "replaced"]: state.commands.clear()
		if case == "replaced": state.commands.append({"kind": "Wait", "arguments": [60000.0]})
		if case in ["kept", "legacy"]: state.commands.append({"kind": "Wait", "arguments": [60000.0]})
		var edit := func(raw: Dictionary) -> void: raw.director.erase("running")
		var restored := _round_trip(director, why, edit if case == "legacy" else Callable())
		check(not restored.is_empty(), "el2: a save during a scripted move whose queue was %s reads back %s" % [case, why])
		if restored.is_empty(): continue
		var next: ELAdventureDirector = restored.director
		for frame in 600:
			next.advance(1.0 / 60.0)
			if next.movement.is_empty(): break
		var commands: Array = next.state.commands
		match case:
			"cleared": check(commands.is_empty() and next.error.is_empty(), "el2: the restored move of a cleared queue finishes without a command")
			"replaced": check(commands.size() == 1 and commands[0].kind == "Wait", "el2: the restored move of a replaced queue leaves the new command alone")
			# The move was the head: finishing it starts the Wait after it.
			"kept", "legacy": check(commands.size() == 1 and commands[0].kind == "Wait" and next._waiting, "el2: the restored move (%s) finishes itself and the next command runs" % case)
		next.state.close()
	state.close()

# --- 5. tick rate -----------------------------------------------------------------

func _tick_rate(profile: ELProfile) -> void:
	var pair := _second_session(profile, "e2mission11")
	if pair.is_empty(): return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	var ticks := [0]
	# Only the timing is measured: the map's own step hooks do nothing here.
	state.vm.bind("Hook_Wake", func(_arguments: Array) -> Array: return [])
	state.vm.bind("Hook_OnStep", func(_arguments: Array) -> Array: return [])
	state.vm.bind("Hook_OnPostStep", func(_arguments: Array) -> Array:
		ticks[0] += 1
		return [])
	for rate: Array in [[60, 900], [20, 900], [7.5, 900], [2, 480]]:
		ticks[0] = 0
		var frames := int(round(60.0 * float(rate[0])))
		for frame in frames: director.advance(1.0 / float(rate[0]))
		check(absi(ticks[0] - int(rate[1])) <= 2 and director.error.is_empty(), "el2: %s frames per second run %d script ticks a minute (%d)" % [rate[0], rate[1], ticks[0]])
	state.close()

# --- 6. interception on every tile -------------------------------------------------

func _tile_interception(profile: ELProfile) -> void:
	var stops := {}
	var expected := Vector2i(-1, -1)
	for mode: Array in [[1.0 / 60.0, false], [0.133, false], [0.4, false], [0.133, true], [0.4, true]]:
		var pair := _second_session(profile, "e2mission11")
		if pair.is_empty(): return
		var state: ELAdventureSession = pair[0]
		var director: ELAdventureDirector = pair[1]
		var hero := state.object(state.main_hero)
		var plan := _guard_walk(state, director, hero)
		if plan.is_empty():
			check(false, "el2 ch11: a guard to walk into")
			state.close()
			return
		hero.x = plan.start.x
		hero.y = plan.start.y
		hero.ap = 50
		director.grid.update_actor(hero)
		director.fast_mode = mode[1]
		check(director.request_move(int(hero.uid), plan.goal), "el2 ch11: the walk into the zone starts")
		var path: Array = director.movement.get("path", [])
		var hostile := director.interception.hostile_cells(state, hero)
		if expected.x < 0:
			for cell: Vector2i in path:
				if hostile.has(cell):
					expected = cell
					break
		var stop := Vector2i(-1, -1)
		for frame in 400:
			director.advance(mode[0])
			if not director.dialogue.is_empty(): director.acknowledge("OK")
			if stop.x < 0 and (not state.commands.is_empty() or director.movement.get("queued", false) or director.encounter != null):
				stop = Vector2i(int(hero.x), int(hero.y))
			if director.encounter != null: break
		stops[str(mode)] = stop
		check(director.encounter != null, "el2 ch11: the walk into the zone ends in a battle (frame %.3f s%s)" % [mode[0], ", fast" if mode[1] else ""])
		check(stop == expected, "el2 ch11: the hero is stopped on the first zone tile it enters, %s (frame %.3f s%s: %s)" % [expected, mode[0], ", fast" if mode[1] else "", stop])
		state.close()

## A straight walk from outside a guard's widened zone to the tile beside it.
func _guard_walk(state: ELAdventureSession, director: ELAdventureDirector, hero: Dictionary) -> Dictionary:
	for gid: int in director.interception.zones.keys():
		var guard := state.object(gid)
		if guard.get("type") != "monster" or not guard.get("alive", false) or not state.hostile(hero, guard) or ELForts.garrison_of(state, guard).size() > 0: continue
		if not ELInterception.allows(state, hero.uid, gid): continue
		guard.zone_radius = 3
		director.interception.rebuild(state, director.grid)
		var at := Vector2i(int(guard.x), int(guard.y))
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var line: Array[Vector2i] = []
			for k in range(1, 9): line.append(at + dir * k)
			if not line.all(func(cell: Vector2i) -> bool: return director.grid.passability(cell) >= 0): continue
			var outside := line.filter(func(cell: Vector2i) -> bool: return director.interception.enemies(state, hero, cell).is_empty())
			if outside.size() < 5 or not director.interception.enemies(state, hero, line[1]).size() > 0: continue
			return {"start": line[7], "goal": line[0], "guard": gid}
		guard.erase("zone_radius")
		director.interception.rebuild(state, director.grid)
	return {}

# --- 7. MoveAndUseObject after the target moved -----------------------------------

func _moved_target(profile: ELProfile) -> void:
	for moved: bool in [false, true]:
		var pair := _second_session(profile, "e2mission11")
		if pair.is_empty(): return
		var state: ELAdventureSession = pair[0]
		var director: ELAdventureDirector = pair[1]
		var hero := state.object(state.main_hero)
		# A hostile creature, and a free tile outside every zone some way off
		# it that the hero is set down on.
		var target := {}
		for id: int in director.interception.zones.keys():
			var item := state.object(id)
			if item.get("type") != "monster" or not item.get("alive", false) or not state.hostile(hero, item) or not target.is_empty(): continue
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
				var cell := Vector2i(int(item.x), int(item.y)) + dir * 7
				if not director.grid.contains(cell) or director.grid.passability(cell) < 0 or not director.interception.enemies(state, hero, cell).is_empty(): continue
				if director.grid.approach(cell, item).size() < 5: continue
				hero.x = cell.x
				hero.y = cell.y
				director.grid.update_actor(hero)
				target = item
				break
		if target.is_empty():
			check(false, "el2 ch11: a hostile creature to walk to")
			state.close()
			return
		var home := Vector2i(int(hero.x), int(hero.y))
		state.commands.append({"kind": "MoveAndUseObject", "arguments": [float(hero.uid), float(target.uid)]})
		var shifted := false
		var finished := false
		for frame in 1200:
			director.advance(1.0 / 60.0)
			if not director.dialogue.is_empty(): director.acknowledge("OK")
			if moved and not shifted and not director.movement.is_empty() and int(director.movement.index) >= 2:
				# The script sends the target to where the hero set out from.
				state._native([float(target.uid), float(home.x), float(home.y)], "ExJumpToPos")
				shifted = true
			if director.encounter != null or not director.auto_fight.is_empty(): break
			if frame > 2 and director.movement.is_empty() and state.commands.is_empty():
				finished = true
				break
		if moved:
			check(shifted and finished and director.encounter == null and director.auto_fight.is_empty() and director.error.is_empty(), "el2 ch11: MoveAndUseObject to a creature a script moved away ends without a battle from afar")
		else:
			check(director.encounter != null or not director.auto_fight.is_empty(), "el2 ch11: MoveAndUseObject to a creature that stays starts the battle")
		state.close()

# --- 2. training camp ---------------------------------------------------------------

func _camp_map(profile: ELProfile) -> Array:
	var ids: Array[String] = []
	for path: String in profile.files_under("Maps/"):
		if path.ends_with(".map") and path.count("/") == 1: ids.append(path.get_file().get_basename())
	ids.sort()
	for id: String in ids:
		var map := ELAdventureMap.new()
		if not map.load_map(profile, id): continue
		if not map.objects.any(func(item: Dictionary) -> bool: return item.get("name") == ELAdditionalBuildings.CAMP): continue
		var state := ELAdventureSession.new()
		if not state.start(map, 1, 212, "", 1, id.begins_with("mission")):
			state.close()
			continue
		var director := ELAdventureDirector.new()
		if not director.build(state):
			state.close()
			continue
		for frame in 100:
			if not director.dialogue.is_empty(): director.acknowledge("OK")
			if director.can_move(): break
			director.advance(0.1)
		return [state, director, id]
	return []

## A new hero of the local player beside the camp.
func _camp_guest(state: ELAdventureSession, director: ELAdventureDirector, camp: Dictionary) -> Dictionary:
	var main := state.object(state.main_hero)
	var size: Vector2i = director.grid.footprints.get(int(camp.uid), {}).get("size", Vector2i.ONE)
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			var cell := Vector2i(int(camp.x) + x, int(camp.y) + y)
			if Rect2i(int(camp.x), int(camp.y), size.x, size.y).has_point(cell) or director.grid.passability(cell, false) < 0: continue
			var id := ELAdditionalBuildings.spawn_hero(state, str(main.name), state.current_player, cell.x, cell.y)
			return state.object(id)
	return {}

func _training_camp(profile: ELProfile) -> void:
	var found := _camp_map(profile)
	if found.is_empty():
		print("SKIP: no first-game map with a training camp opens")
		return
	var state: ELAdventureSession = found[0]
	var director: ELAdventureDirector = found[1]
	print("NOTE: training camp on %s" % found[2])
	var camp := {}
	for item: Dictionary in state.objects.values():
		if item.get("name") == ELAdditionalBuildings.CAMP and item.get("alive", false): camp = item
	var why: Array = []
	# Enter, then dismiss.
	var guest := _camp_guest(state, director, camp)
	check(not guest.is_empty(), "el1 camp: a hero stands beside the camp")
	if guest.is_empty():
		state.close()
		return
	ELAdditionalBuildings.visit(director, guest, camp)
	check(int(camp.guest) == int(guest.uid) and not guest.placed, "el1 camp: the hero enters the training camp")
	check(ELHeroExchange.dismiss(director, int(guest.uid)), "el1 camp: the hero in the camp can be dismissed")
	check(int(camp.guest) == -1 and int(guest.camp) == -1 and guest.placed, "el1 camp: dismissal frees the camp and leaves the hero placed")
	var restored := _round_trip(director, why)
	check(not restored.is_empty(), "el1 camp: the world after the dismissal saves and loads %s" % [why])
	if not restored.is_empty(): restored.state.close()
	# A save from before the fix: the fallen guest left unplaced.
	restored = _round_trip(director, why, func(raw: Dictionary) -> void:
		for record: Dictionary in raw.objects:
			if int(record.uid) == int(guest.uid): record.placed = false)
	check(not restored.is_empty(), "el1 camp: an older save with the dismissed guest unplaced loads %s" % [why])
	if not restored.is_empty(): restored.state.close()
	# Enter, die, resurrect.
	var second := _camp_guest(state, director, camp)
	ELAdditionalBuildings.visit(director, second, camp)
	check(int(camp.guest) == int(second.uid) and not second.placed, "el1 camp: another hero enters the camp")
	state._native([float(second.uid)], "ExKillHero")
	check(not second.alive and int(camp.guest) == -1 and second.placed, "el1 camp: death in the camp frees it and leaves the hero placed")
	restored = _round_trip(director, why)
	check(not restored.is_empty(), "el1 camp: the world after the death saves and loads %s" % [why])
	if not restored.is_empty(): restored.state.close()
	if ELGlobalSpells.applies(state) and ELGlobalSpells.castle_spot(state, state.current_player) != ELGlobalSpells.NO_SPOT:
		# The dismissed hero fell first; resurrection takes the last to fall.
		var back := ELGlobalSpells.resurrect(state, state.current_player)
		check(back == int(second.uid) and second.alive and second.placed and int(second.camp) == -1, "el1 camp: the resurrected camp hero is alive and placed")
		restored = _round_trip(director, why)
		check(not restored.is_empty(), "el1 camp: the world after the resurrection saves and loads %s" % [why])
		if not restored.is_empty(): restored.state.close()
		# A hero that fell unplaced (an older save) comes back placed too.
		second.placed = false
		state._native([float(second.uid)], "ExKillHero")
		second.placed = false
		check(ELGlobalSpells.resurrect(state, state.current_player) == int(second.uid) and second.placed, "el1 camp: a hero resurrected from an unplaced fall is placed")
	else: print("SKIP: no castle for resurrection on %s" % found[2])
	check(ELAdditionalBuildings.valid_links(state.objects), "el1 camp: the lair and camp links hold")
	state.close()

# --- 8. book slots ----------------------------------------------------------------

func _book_slots(profile: ELProfile) -> void:
	var found := _camp_map(profile)
	if found.is_empty(): return
	var state: ELAdventureSession = found[0]
	var hero := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player: hero = item
	var size := ELSpellInventory.book_size(profile)
	var cantrips: Array[String] = []
	var spells: Array[String] = []
	var codes: Array = profile.table("CombatSpells").keys()
	codes.sort()
	for code: String in codes:
		if hero.is_empty() or not ELSpellInventory.is_spell(profile, code) or not ELSpellInventory.allows(profile, hero, code): continue
		if ELRunes.unlimited(profile, hero, code): cantrips.append(code)
		elif spells.size() < 2: spells.append(code)
	if cantrips.is_empty() or spells.size() < 2:
		print("SKIP: the hero has no cantrip or too few spells")
		state.close()
		return
	hero.cards.clear()
	hero.rune_uses.clear()
	hero.erase("rune_under")
	for i in size:
		hero.cards.append(cantrips[i % cantrips.size()])
		hero.rune_uses.append(-1)
	ELSpellInventory.add(profile, hero, spells[0])
	hero.rune_stock[spells[0]][0] = 3
	var cantrip := str(hero.cards[2])
	check(not state.move_spell(int(hero.uid), spells[0], -1, 0), "el1 book: a full book of cantrips takes no spell at its end")
	check(state.move_spell(int(hero.uid), spells[0], -1, 0, -1, 2) and hero.cards[2] == spells[0] and int(hero.rune_uses[2]) == 3 and ELRunes.under(hero)[2] == cantrip, "el1 book: a reserve spell goes over a cantrip, which waits underneath")
	check(state.move_spell(int(hero.uid), "", 2) and hero.cards[2] == cantrip and int(hero.rune_stock[spells[0]][0]) == 3, "el1 book: stored again, it gives the slot back with its runes kept")
	check(state.move_spell(int(hero.uid), spells[0], -1, 0, -1, 2) and hero.cards[2] == spells[0], "el1 book: it can be equipped over the cantrip again")
	ELSpellInventory.add(profile, hero, spells[1])
	check(state.move_spell(int(hero.uid), spells[1], -1, 0, -1, 2) and hero.cards[2] == spells[1] and ELRunes.under(hero)[2] == cantrip and int(hero.rune_stock[spells[0]][0]) == 3, "el1 book: another spell over it sends it to the reserve with its runes")
	check(ELRunes.restore(profile, hero) and hero.cards.size() == size, "el1 book: the inventory stays valid")
	var codec := ELAdventureSave.new()
	var director: ELAdventureDirector = found[1]
	var document := codec.encode(director, {})
	check(not document.is_empty() and not codec.decode(JSON.parse_string(JSON.stringify(document, "", true, true)), {"el1": profile}).is_empty(), "el1 book: the book with a spell over a cantrip saves and loads " + codec.error)
	state.close()

# --- 9, 10. Lua VM ------------------------------------------------------------------

func _lua_vm() -> void:
	var vm := ELLuaVM.new()
	var source := """
function temporary() local t = {1, 2, 3} t.x = t[1] return t.x end
function insert_front(n) local t = {n = n} tinsert(t, 1, 5) return 1 end
function append(n) local t = {n = n} tinsert(t, 5) return t.n end
KEPT = {}
function keep() KEPT[getn(KEPT) + 1] = {} end
"""
	check(vm.load_script(source.to_utf8_buffer(), "vm_check"), "lua: the check script compiles " + vm.error)
	var start := vm.live_tables().size()
	for i in 20000: vm.invoke("temporary")
	check(vm.error.is_empty() and vm.live_tables().size() <= start + 1 and vm._tables.size() < 4096, "lua: 20000 calls making a temporary table keep none (%d alive, %d tracked)" % [vm.live_tables().size(), vm._tables.size()])
	for i in 10: vm.invoke("keep")
	check(vm.live_tables().size() == start + 10, "lua: tables the script keeps stay alive")
	var codec := ELLuaSave.new()
	var saved := codec.encode(vm)
	var other := ELLuaVM.new()
	other.load_script(source.to_utf8_buffer(), "vm_check")
	check(not saved.is_empty() and codec.decode(other, JSON.parse_string(JSON.stringify(saved))), "lua: the script state saves and loads " + codec.error)
	check(other.globals.get("KEPT") is ELLuaVM.Table and other.globals.KEPT.values.size() == 10, "lua: the kept tables come back")
	other.invoke("keep")
	check(other.error.is_empty() and other.globals.KEPT.values.size() == 11, "lua: the restored state runs on")
	vm.invoke("insert_front", [100.0])
	check(vm.error.is_empty() and vm.instructions >= 100, "lua: tinsert's shifting counts against the budget (%d instructions)" % vm.instructions)
	vm.invoke("insert_front", [100000000.0])
	check(vm.error.contains("budget"), "lua: tinsert with a huge script-supplied n fails on the budget: " + vm.error)
	vm.invoke("append", [100000000.0])
	check(vm.error.is_empty() and vm.instructions < 100, "lua: appending with a huge n stays cheap")
	vm.clear()
	other.clear()
	check(vm.live_tables().is_empty(), "lua: clear() releases every table")
