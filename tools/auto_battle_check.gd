extends SceneTree
## Battles the game plays by itself, through the code that plays them.
##
## 1. The player's Auto combat, in the battle screen (res://scenes/duel.tscn)
##    against the computer opponent, per game:
##    smart     setting duel_ai = 2, auto combat switched on at the player's
##              first phase and left on: the battle ends, and every command
##              of both sides was found by the smarter opponent
##              (duel.smart_sides holds the side that acted);
##    midway    duel_ai = 2, auto combat switched on phase by phase and off
##              again in between: once after sending an attacker by hand and
##              once after setting a blocker by hand (both are taken back:
##              ELPracticeAI.release_assignments); switched off, the player's
##              side is left alone until the player acts;
##    original  duel_ai = 1: both sides are played by the original opponent;
##    easy      duel_ai = 0: the computer side reads EASY_BUDGET positions,
##              the player's side under auto combat the full original budget;
##    nospells  duel_ai = 2, setting use_spells off, a Defence rod carried:
##              the player's side casts no spell of its book and uses no
##              artifact;
##    nospells_original  the same with duel_ai = 1;
##    demo      the "Watch demo" battle: both sides by the computer.
## 2. The battles no player takes part in:
##    relay     the strategic (online map) battle relay's neutral side
##              (ELStrategicBattleRelay.step_neutral_ai), played to the end;
##    director  the second game's map battle with no side of the local player
##              (ELAdventureDirector auto_fight / resolve_auto_fight), and what
##              the first game does with such a pair.
##
##   godot --headless --path game --script ../tools/auto_battle_check.gd -- \
##       [--game=el1|el2|both] [--only=smart,midway,...] [--seed=N] [--speed=N]
##       [--seconds=N] [--verbose]
##
## --speed is the engine's time scale while the battle screen plays (the
## thinking itself is not sped up). Each battle prints one RESULT line with
## how each side's commands were found; PASS/FAIL lines carry the checks.
## Settings are changed in memory only. Needs the player's game files.

const SMART := ["native", "proof", "plan", "beyond", "search"]
const PHASE_CAP := 80
const BOOKS := {"el1": [["Green", "PRG3", 6], ["Red", "PRR3", 6]], "el2": [["Green", "PRG3", 6], ["Red", "PRR3", 6]]}

class Catcher extends Logger:
	var lock := Mutex.new()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	## Errors of the engine itself (in a headless run mostly the stand-in
	## renderer's), counted apart from the scripts' errors.
	var engine: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		var text := "%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function]
		lock.lock()
		if error_type == Logger.ERROR_TYPE_WARNING: warnings.append(text)
		elif error_type == Logger.ERROR_TYPE_SCRIPT: errors.append(text)
		else: engine.append(text)
		lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func take() -> Array:
		lock.lock()
		var result := [errors.duplicate(), warnings.duplicate(), engine.duplicate()]
		errors.clear()
		warnings.clear()
		engine.clear()
		lock.unlock()
		return result

var view: Node
var catcher := Catcher.new()
var failures: Array[String] = []
var passes := 0
var verbose := false
var paths := {}

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
		if arg == "--" + name: return "1"
	return fallback

func check(ok: bool, what: String) -> void:
	if ok: passes += 1
	else: failures.append(what)
	print(("PASS: " if ok else "FAIL: ") + what)

func _initialize() -> void:
	_run.call_deferred()

func _wanted(name: String) -> bool:
	var only := _arg("only", "")
	return only.is_empty() or name in only.split(",")

func _run() -> void:
	verbose = _arg("verbose", "") == "1"
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if saved is Dictionary: paths = saved
	var games: Array[String] = []
	for game: String in ["el1", "el2"]:
		if _arg("game", "both") in [game, "both"]: games.append(game)
	OS.add_logger(catcher)
	view = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	view.demo = false
	root.add_child(view)
	for i in 10: await process_frame
	catcher.take()
	print("ENGINE compiled=%s speed=%s" % [str(ELCombatBrain.available), _arg("speed", "10")])
	for game: String in games:
		if not view.profiles.has(game):
			print("SKIP %s: no game files" % game)
			continue
		if _wanted("smart"): await _auto(game, "smart", 2, true, "start")
		if _wanted("midway"): await _midway(game)
		if _wanted("original"): await _auto(game, "original", 1, true, "start")
		if _wanted("easy"): await _auto(game, "easy", 0, true, "start")
		if _wanted("nospells"): await _auto(game, "nospells", 2, false, "start")
		if _wanted("nospells_original"): await _auto(game, "nospells_original", 1, false, "start")
		if _wanted("demo"): await _auto(game, "demo", 2, true, "demo")
	Engine.time_scale = 1.0
	ELPracticeAI.finish()
	view.queue_free()
	for i in 5: await process_frame
	for game: String in games:
		if not paths.has(game): continue
		var profile := ELProfile.new()
		if not profile.mount(game, str(paths[game])): continue
		if _wanted("relay"): _relay(profile)
		if _wanted("director"): _director(profile)
	ELPracticeAI.finish()
	print("AUTO BATTLE: %d passed, %d failed" % [passes, failures.size()])
	for what: String in failures: print("  failed: " + what)
	quit(1 if not failures.is_empty() else 0)

func _players(game: String, rod: bool) -> Array:
	var result: Array = []
	for book: Array in BOOKS[game]: result.append({"faction": book[0], "deck": book[1], "level": book[2]})
	if rod: result[0].artifacts = [{"name": "RodOfDefence"}]
	return result

## One battle in the battle screen. `plan`: "start" switches auto combat on
## at the player's first phase, "demo" watches the demo, "midway" is driven by
## `_midway`'s callback (called every frame with the running record).
func _play(game: String, label: String, level: int, use_spells: bool, plan: String, seed_value: int, drive := Callable()) -> Dictionary:
	view.demo = plan == "demo"
	Engine.time_scale = 1.0
	view._start(game, {"players": _players(game, not use_spells)}, null, seed_value)
	# After the start: "use_spells" is kept per game, and starting a battle
	# of the other game switches to that game's stored values.
	view.settings.values["duel_ai"] = level
	view.settings.values["use_spells"] = use_spells
	for i in 5: await process_frame
	var duel: ELDuel = view.duel
	var record := {"label": label, "started": duel != null and duel.accepted_serial == 0 and duel.phase != ELDuel.Phase.FINISHED, "human": 0, "engines": [{}, {}], "smart": [0, 0], "plain": [0, 0],
		"budgets": [{}, {}], "book_casts": [0, 0], "casts": [0, 0], "artifacts": [0, 0], "commands": [0, 0], "auto_commands": 0, "phase_cap": 0, "toggled": false, "ended": "", "duel": duel, "notes": [], "spent": []}
	if not record.started: return record
	record.human = view._battle_player_side(duel)
	Engine.time_scale = float(_arg("speed", "10"))
	var refused := ELPracticeAI.refused
	var empty := ELPracticeAI.empty
	var cycles := ELPracticeAI.cycles
	var seen: Dictionary = ELPracticeAI.last_decision
	var serial := duel.accepted_serial
	var slots: Array = [duel.heroes[0].hand_slots.duplicate(), duel.heroes[1].hand_slots.duplicate()]
	var mark: Array = []
	var in_phase := 0
	var auto_was: bool = view.auto_combat
	var limit := float(_arg("seconds", "900")) * 1000.0
	var began := Time.get_ticks_msec()
	while duel.phase != ELDuel.Phase.FINISHED and view.duel == duel:
		if float(Time.get_ticks_msec() - began) > limit:
			record.ended = "time"
			break
		await process_frame
		# The commands the rules took since the last frame.
		var fresh: Array = []
		for entry: Dictionary in duel.accepted:
			if int(entry.serial) > serial: fresh.append(entry)
		var sender := String(ELPracticeAI.last_decision.get("engine", "?")) if not is_same(ELPracticeAI.last_decision, seen) else "by hand"
		for entry: Dictionary in fresh:
			var side := int(entry.side)
			record.commands[side] += 1
			var key := [duel.turn_serial, side]
			if key != mark:
				mark = key
				in_phase = 0
			in_phase += 1
			if in_phase == PHASE_CAP + 1: record.phase_cap += 1
			if side == record.human and (auto_was or view.auto_combat): record.auto_commands += 1
			if String(entry.kind) == "cast":
				record.casts[side] += 1
				var held: Array = slots[side]
				if int(entry.index) < held.size() and int(held[int(entry.index)]) >= 0:
					record.book_casts[side] += 1
					if not use_spells and side == record.human: record.spent.append("round %d: cast %s from the book, sent by %s" % [duel.round_number, str(entry.get("card", "?")), sender])
			elif String(entry.kind) == "ability" and String(entry.get("key", "")).begins_with("artifact"):
				record.artifacts[side] += 1
				if not use_spells and side == record.human: record.spent.append("round %d: used %s, sent by %s" % [duel.round_number, str(entry.key), sender])
		if not is_same(ELPracticeAI.last_decision, seen):
			seen = ELPracticeAI.last_decision
			if not fresh.is_empty():
				var side := int(fresh[-1].side)
				var engine := String(seen.get("engine", "?"))
				record.engines[side][engine] = int(record.engines[side].get(engine, 0)) + 1
				if duel.smart_sides.has(side): record.smart[side] += 1
				else: record.plain[side] += 1
				var budget := ELCombatSearch.original_budget
				record.budgets[side][budget] = int(record.budgets[side].get(budget, 0)) + 1
				if verbose: print("    side%d %s %s smart_sides=%s" % [side, engine, str(seen.get("command", {})), str(duel.smart_sides)])
		if ELPracticeAI.cycles - cycles > int(record.get("cycles_seen", 0)):
			record.cycles_seen = ELPracticeAI.cycles - cycles
			record.notes.append("led back: round %d, side %d to act, phase %d, attacks %s, blocks %s, then sent %s (%s)" % [duel.round_number, duel.active_side(), duel.phase, str(duel.attacks), str(duel.blocks), str(seen.get("command", {})), str(seen.get("engine", ""))])
		serial = duel.accepted_serial
		slots = [duel.heroes[0].hand_slots.duplicate(), duel.heroes[1].hand_slots.duplicate()]
		auto_was = view.auto_combat
		if duel.phase == ELDuel.Phase.FINISHED: break
		if plan == "start" and not record.toggled and view._human_turn():
			view._toggle_auto()
			record.toggled = view.auto_combat
		elif drive.is_valid(): drive.call(record)
	Engine.time_scale = 1.0
	if record.ended.is_empty(): record.ended = "won" if duel.phase == ELDuel.Phase.FINISHED else "replaced"
	record.refused = ELPracticeAI.refused - refused
	record.empty = ELPracticeAI.empty - empty
	record.cycles = ELPracticeAI.cycles - cycles
	record.seconds = float(Time.get_ticks_msec() - began) / 1000.0
	var logged := catcher.take()
	record.errors = logged[0]
	record.warnings = logged[1]
	record.engine = logged[2]
	print("RESULT %s %s: ended=%s winner=%d rounds=%d seed=%d commands=%s engines player=%s computer=%s smart_side_set player=%d/%d computer=%d/%d budgets=%s casts=%s book_casts=%s artifacts=%s refused=%d empty=%d cycles=%d phase_cap=%d script_errors=%d engine_errors=%d warnings=%d %.0f s" % [
		game, label, record.ended, duel.winner, duel.round_number, seed_value, str(record.commands), str(record.engines[record.human]), str(record.engines[1 - record.human]),
		record.smart[record.human], record.smart[record.human] + record.plain[record.human], record.smart[1 - record.human], record.smart[1 - record.human] + record.plain[1 - record.human],
		str(record.budgets), str(record.casts), str(record.book_casts), str(record.artifacts), record.refused, record.empty, record.cycles, record.phase_cap, record.errors.size(), record.engine.size(), record.warnings.size(), record.seconds])
	for text: String in record.errors.slice(0, 5): print("    script error: " + text)
	var kinds := {}
	for text: String in record.engine: kinds[text] = int(kinds.get(text, 0)) + 1
	for text: String in kinds.keys().slice(0, 6): print("    engine error x%d: %s" % [kinds[text], text])
	for text: String in record.warnings.slice(0, 5): print("    warning: " + text)
	for text: String in record.notes: print("    note: " + text)
	for text: String in record.spent.slice(0, 8): print("    with use_spells off: " + text)
	return record

func _all(found: Dictionary, allowed: Array) -> bool:
	return not found.is_empty() and found.keys().all(func(e: String) -> bool: return e in allowed)

## The checks every battle shares.
func _sound(game: String, record: Dictionary) -> void:
	var name := "%s %s" % [game, record.label]
	check(record.started, "%s: the battle starts" % name)
	if not record.started: return
	check(record.ended == "won" and int(record.duel.winner) >= 0, "%s: the battle is played to its end (%s, winner %d, round %d)" % [name, record.ended, int(record.duel.winner), int(record.duel.round_number)])
	check(record.refused == 0 and record.empty == 0, "%s: no command refused (%d), no step without a command (%d)" % [name, record.refused, record.empty])
	check(record.cycles <= 2, "%s: commands that only led back to a seen position: %d" % [name, record.cycles])
	check(record.phase_cap == 0, "%s: no phase of more than %d commands (%d)" % [name, PHASE_CAP, record.phase_cap])
	check(record.errors.is_empty(), "%s: no script errors logged (%d%s)" % [name, record.errors.size(), "" if record.errors.is_empty() else ": " + str(record.errors[0])])

func _auto(game: String, label: String, level: int, use_spells: bool, plan: String) -> void:
	var record: Dictionary = await _play(game, label, level, use_spells, plan, int(_arg("seed", "7")))
	_sound(game, record)
	if not record.started: return
	var name := "%s %s" % [game, label]
	var human := int(record.human)
	var own: Dictionary = record.engines[human]
	var other: Dictionary = record.engines[1 - human]
	if plan == "demo":
		check(_all(own, ["original"]) and _all(other, ["original"]) and record.smart == [0, 0], "%s: the watched demo is played by the original opponent on both sides whatever duel_ai says (%s, %s)" % [name, own, other])
		return
	check(record.toggled, "%s: auto combat switches on at the player's phase" % name)
	check(int(record.auto_commands) > 0 and int(record.commands[human]) == int(record.auto_commands), "%s: every command of the player's side was the computer's (%d of %d)" % [name, record.auto_commands, record.commands[human]])
	match level:
		2:
			check(_all(own, SMART) and int(record.plain[human]) == 0, "%s: the player's side is played by the smarter opponent (%s; smart_sides held it for %d of %d)" % [name, own, record.smart[human], record.smart[human] + record.plain[human]])
			check(_all(other, SMART) and int(record.plain[1 - human]) == 0, "%s: the computer's side is played by the smarter opponent (%s)" % [name, other])
		1:
			check(_all(own, ["original"]) and int(record.smart[human]) == 0, "%s: the player's side is played by the original opponent (%s)" % [name, own])
			check(_all(other, ["original"]) and int(record.smart[1 - human]) == 0, "%s: the computer's side is played by the original opponent (%s)" % [name, other])
			check(record.budgets[0].keys() == [ELCombatSearch.BUDGET] and record.budgets[1].keys() == [ELCombatSearch.BUDGET], "%s: both sides read the full original budget (%s)" % [name, record.budgets])
		0:
			check(_all(own, ["original"]) and _all(other, ["original"]) and record.smart == [0, 0], "%s: both sides are played by the original opponent (%s, %s)" % [name, own, other])
			check(record.budgets[1 - human].keys() == [ELCombatSearch.EASY_BUDGET], "%s: the computer's side reads the easy budget (%s)" % [name, record.budgets[1 - human]])
			check(record.budgets[human].keys() == [ELCombatSearch.BUDGET], "%s: the player's side under auto combat reads the full budget (%s)" % [name, record.budgets[human]])
	if use_spells:
		check(int(record.book_casts[human]) > 0, "%s: with use_spells on the player's side casts its book (%d casts)" % [name, record.book_casts[human]])
	else:
		check(int(record.book_casts[human]) == 0 and int(record.artifacts[human]) == 0, "%s: with use_spells off the player's side casts no spell of its book (%d) and uses no artifact (%d)%s" % [name, record.book_casts[human], record.artifacts[human], "" if record.spent.is_empty() else "; first: " + str(record.spent[0])])
		check(int(record.book_casts[1 - human]) > 0, "%s: the computer's side still casts (%d)" % [name, record.book_casts[1 - human]])

## Auto combat taken up and put down phase by phase.
func _midway(game: String) -> void:
	var name := "%s midway" % game
	var done := {"attack": "", "block": "", "idle": "", "off": 0, "on": 0, "bad_off": 0, "bad_on": 0}
	var state := {"mode": "manual", "key": [], "was_auto": false, "idle_serial": -1, "idle_began": 0}
	var drive := func(record: Dictionary) -> void:
		var duel: ELDuel = record.duel
		var human := int(record.human)
		var key := [duel.turn_serial, duel.phase, duel.active_side()]
		var finished: bool = not String(done.attack).is_empty() and not String(done.block).is_empty() and not String(done.idle).is_empty()
		match String(state.mode):
			"auto":
				# The phase it was switched on in has passed: control is taken back.
				if key != state.key and not finished:
					view._toggle_auto()
					done.off += 1
					if view.auto_combat or view.auto_off_button.visible: done.bad_off += 1
					state.mode = "manual"
					state.was_auto = true
			"idle":
				# Left alone for a while: nothing may be sent for the player.
				if duel.accepted_serial != int(state.idle_serial) or view.auto_combat or duel.active_side() != human:
					done.idle = "FAILED: a command was sent for the player's side after auto combat was switched off (serial %d -> %d, auto %s, side to act %d)" % [state.idle_serial, duel.accepted_serial, view.auto_combat, duel.active_side()]
					state.mode = "manual"
				elif float(view.ai_clock) >= 3.0 and view._human_turn():
					done.idle = "ok"
					state.mode = "manual"
				elif Time.get_ticks_msec() - int(state.idle_began) > 60000:
					done.idle = "FAILED: the player's turn did not come back within a minute"
					state.mode = "manual"
			"manual":
				if not view._human_turn(): return
				if state.was_auto and String(done.idle).is_empty():
					state.mode = "idle"
					state.idle_serial = duel.accepted_serial
					state.idle_began = Time.get_ticks_msec()
					return
				var by_hand := ""
				if duel.phase == ELDuel.Phase.ATTACK and String(done.attack).is_empty():
					for c: Dictionary in duel.army(human):
						var id := int(c.id)
						if not duel.can_declare_attack(id): continue
						var stays: bool = duel.has_flag(id, "Berserk") or duel.attack_cost(id) > 0
						if not duel.toggle_attack(id) or not duel.attacks.has(id): continue
						view._toggle_auto()
						if not view.auto_combat: done.attack = "FAILED: auto combat did not switch on after an attacker was sent by hand"
						elif duel.attacks.has(id) != stays: done.attack = "FAILED: the attacker #%d sent by hand was %s" % [id, "not taken back" if not stays else "taken back although it had to stay"]
						else: done.attack = "ok (attacker #%d %s sent by hand, taken back when auto combat took over)" % [id, String(c.card)]
						by_hand = "attack"
						break
				elif duel.phase == ELDuel.Phase.DEFENCE and String(done.block).is_empty() and not duel.attacks.is_empty():
					for c: Dictionary in duel.army(human):
						var id := int(c.id)
						if duel.blocks.has(id): continue
						for target: int in duel.attacks:
							var trial := duel.search_copy()
							var legal := trial.assign_block(id, target)
							if trial.scripts != null and trial.scripts.search_only: trial.scripts.close()
							if not legal: continue
							if not duel.assign_block(id, target) or not duel.blocks.has(id): continue
							view._toggle_auto()
							if not view.auto_combat: done.block = "FAILED: auto combat did not switch on after a blocker was set by hand"
							elif duel.blocks.has(id): done.block = "FAILED: the blocker #%d set by hand was not taken back" % id
							else: done.block = "ok (blocker #%d %s set on #%d by hand, taken back when auto combat took over)" % [id, String(c.card), target]
							by_hand = "block"
							break
						if not by_hand.is_empty(): break
				if by_hand.is_empty():
					view._toggle_auto()
					if not view.auto_combat or not view.auto_off_button.visible: done.bad_on += 1
				done.on += 1
				record.toggled = true
				state.mode = "auto"
				state.key = key
	var record := {}
	for attempt in 4:
		for key: String in ["attack", "block", "idle"]: done[key] = ""
		state.mode = "manual"
		state.was_auto = false
		record = await _play(game, "midway", 2, true, "midway", int(_arg("seed", "7")) + attempt, drive)
		if not record.started or (String(done.attack).begins_with("ok") and String(done.block).begins_with("ok") and String(done.idle) == "ok"): break
		if String(done.attack).begins_with("FAILED") or String(done.block).begins_with("FAILED") or String(done.idle).begins_with("FAILED"): break
		print("NOTE %s: seed %d gave no chance for every case (attack '%s', block '%s', idle '%s'); another seed" % [name, int(_arg("seed", "7")) + attempt, done.attack, done.block, done.idle])
	_sound(game, record)
	if not record.started: return
	var human := int(record.human)
	check(String(done.attack).begins_with("ok"), "%s: auto combat taken up after an attacker was sent by hand: %s" % [name, done.attack if not String(done.attack).is_empty() else "never reached"])
	check(String(done.block).begins_with("ok"), "%s: auto combat taken up after a blocker was set by hand: %s" % [name, done.block if not String(done.block).is_empty() else "never reached"])
	check(String(done.idle) == "ok", "%s: switched off, the player's side is left to the player: %s" % [name, done.idle if not String(done.idle).is_empty() else "never reached"])
	check(int(done.off) > 0 and int(done.bad_off) == 0 and int(done.bad_on) == 0, "%s: auto combat switched on %d times and off %d times, each taking effect at once (%d, %d not)" % [name, done.on, done.off, done.bad_on, done.bad_off])
	check(_all(record.engines[human], SMART) and int(record.plain[human]) == 0, "%s: the player's side under auto combat is played by the smarter opponent (%s)" % [name, record.engines[human]])
	check(_all(record.engines[1 - human], SMART) and int(record.plain[1 - human]) == 0, "%s: the computer's side is played by the smarter opponent (%s)" % [name, record.engines[1 - human]])

# --- Battles without a player ----------------------------------------------------

## The strategic battle relay's neutral side. The host's own side is played
## here by the same step, standing in for the host's player.
func _relay(profile: ELProfile) -> void:
	var game := profile.id
	var duel := ELDuel.new()
	if not duel.start(profile, int(_arg("seed", "7")), {"players": _players(game, false)}):
		check(false, "%s relay: the duel starts (%s)" % [game, duel.error])
		return
	var relay := ELStrategicBattleRelay.new()
	check(relay.attach(1, duel, true, 0, -1), "%s relay: the host attaches a battle whose second side nobody plays" % game)
	var sent := [0]
	relay.outbound.connect(func(_id: int, _payload: Array) -> void: sent[0] += 1)
	var found := [{}, {}]
	var smart := [0, 0]
	var refused := ELPracticeAI.refused
	var cycles := ELPracticeAI.cycles
	var empty := ELPracticeAI.empty
	var capped := 0
	var mark: Array = []
	var commands := 0
	var steps := 0
	var began := Time.get_ticks_msec()
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= 60 and Time.get_ticks_msec() - began < 600000 and steps < 5000:
		steps += 1
		var side := duel.active_side()
		var key := [duel.turn_serial, duel.phase, side]
		if key != mark:
			mark = key
			commands = 0
		commands += 1
		if commands == PHASE_CAP + 1: capped += 1
		var before: Dictionary = ELPracticeAI.last_decision
		if side == 0: ELPracticeAI.step(duel)
		else: relay.step_neutral_ai()
		relay.poll(true)
		if not is_same(before, ELPracticeAI.last_decision):
			var engine := String(ELPracticeAI.last_decision.get("engine", "?"))
			found[side][engine] = int(found[side].get(engine, 0)) + 1
			if duel.smart_sides.has(side): smart[side] += 1
		elif side == 1 and commands > 3:
			break
	var logged := catcher.take()
	print("RESULT %s relay: finished=%s winner=%d rounds=%d steps=%d host_side=%s neutral_side=%s smart_side_set=%s packets=%d refused=%d empty=%d cycles=%d phase_cap=%d relay_error='%s' errors=%d %.0f s" % [game, str(duel.phase == ELDuel.Phase.FINISHED), duel.winner, duel.round_number, steps,
		str(found[0]), str(found[1]), str(smart), sent[0], ELPracticeAI.refused - refused, ELPracticeAI.empty - empty, ELPracticeAI.cycles - cycles, capped, relay.error, logged[0].size(), float(Time.get_ticks_msec() - began) / 1000.0])
	check(duel.phase == ELDuel.Phase.FINISHED and duel.winner >= 0 and relay.result_confirmed() and relay.error.is_empty(), "%s relay: the battle with a neutral side runs to a confirmed result (winner %d, round %d, error '%s')" % [game, duel.winner, duel.round_number, relay.error])
	check(not found[1].is_empty() and sent[0] > 0, "%s relay: the neutral side's commands are the host's and go out to the guest (%d packets)" % [game, sent[0]])
	check(ELPracticeAI.refused == refused and ELPracticeAI.empty == empty and ELPracticeAI.cycles - cycles <= 2 and capped == 0, "%s relay: no refused command (%d), none missing (%d), %d led back, %d phase caps" % [game, ELPracticeAI.refused - refused, ELPracticeAI.empty - empty, ELPracticeAI.cycles - cycles, capped])
	check(logged[0].is_empty(), "%s relay: no errors logged (%d%s)" % [game, logged[0].size(), "" if logged[0].is_empty() else ": " + str(logged[0][0])])
	print("LEVEL %s relay: the neutral side was played by %s (duel.smart_sides is never set on this path, so the duel_ai setting does not reach it)" % [game, str(found[1])])
	relay.detach()

## A map battle between two sides that are not the local player's.
func _director(profile: ELProfile) -> void:
	var game := profile.id
	var entry := {}
	for found: Dictionary in ELSingleScenario.maps(profile):
		if str(found.id).to_lower().ends_with("e2mission11" if game == "el2" else "mission20"): entry = found
	var map := ELAdventureMap.new()
	if entry.is_empty() or not map.load_map(profile, str(entry.id)):
		print("SKIP %s director: the map does not open" % game)
		return
	var state := ELAdventureSession.new()
	var director := ELAdventureDirector.new()
	if not state.start(map, 1, 212, "", 1, false) or not director.build(state):
		print("SKIP %s director: the session does not start (%s %s)" % [game, state.error, director.error])
		return
	for frame in 400:
		director.advance(0.05)
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		elif frame > 5 and director.can_move(): break
		if director.encounter != null: break
	# Two living figures that are not the local player's and can fight.
	var pair: Array = []
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var item := state.object(id)
		if item.get("type") not in ["hero", "monster"] or not item.get("alive", false) or int(item.get("owner", -1)) == state.current_player or Array(item.get("cards", [])).is_empty(): continue
		if pair.is_empty() or int(item.get("level", 0)) != int(state.object(pair[0]).get("level", 0)): pair.append(id)
		if pair.size() == 2: break
	if pair.size() < 2:
		print("SKIP %s director: no two figures apart from the player's" % game)
		state.close()
		return
	var first := state.object(pair[0])
	var second := state.object(pair[1])
	var label := "%s director: #%d %s (level %d) against #%d %s (level %d), neither the player's" % [game, pair[0], str(first.get("name")), int(first.get("level", 0)), pair[1], str(second.get("name")), int(second.get("level", 0))]
	var events: Array = []
	var watch := func(data: Dictionary) -> void:
		if data.get("kind") == "battle_finished": events.append(data)
	state.event.connect(watch)
	var shown: Array = []
	var show := func(data: Dictionary) -> void:
		if str(data.get("kind", "")).begins_with("auto_fight") or data.get("kind") == "encounter": shown.append(str(data.kind))
	director.presentation.connect(show)
	director._begin_encounter(first, second)
	if game == "el2":
		check(not director.auto_fight.is_empty() and director.encounter == null, "%s: shown as an automatic fight, no duel is opened" % label)
		var held: ELAdventureEncounter = director.auto_fight.get("encounter")
		check(held != null and held.auto and held.battle == null, "%s: no ELDuel is built for it (no battle opponent plays it)" % label)
		var expected := held.scripted_winner if held != null else -2
		var frames := 0
		while not director.auto_fight.is_empty() and frames < 2000:
			director.advance(0.05)
			frames += 1
		check(director.auto_fight.is_empty() and director.encounter == null and events.size() == 1, "%s: resolves by itself after %d steps of 0.05 s (battle_finished events: %d, shown: %s)" % [label, frames, events.size(), str(shown)])
		if events.size() == 1:
			check(int(events[0].winner) == expected, "%s: the winner is the chapter script's verdict or the higher level (#%d, expected #%d)" % [label, int(events[0].winner), expected])
			check(first.get("alive", false) != second.get("alive", false) or expected < 0, "%s: exactly the loser is removed (alive: %s, %s)" % [label, first.get("alive"), second.get("alive")])
		# Ended at once, as before a save: another pair.
		var others: Array = []
		for id: int in ids:
			var item := state.object(id)
			if id in pair or item.get("type") not in ["hero", "monster"] or not item.get("alive", false) or int(item.get("owner", -1)) == state.current_player or Array(item.get("cards", [])).is_empty(): continue
			others.append(item)
			if others.size() == 2: break
		if others.size() == 2:
			events.clear()
			director._begin_encounter(others[0], others[1])
			var pending := not director.auto_fight.is_empty()
			director.resolve_auto_fight()
			check(pending and director.auto_fight.is_empty() and director.encounter == null and events.size() == 1, "%s director: resolve_auto_fight ends a shown automatic fight at once (#%d against #%d, winner #%d)" % [game, int(others[0].uid), int(others[1].uid), int(events[0].winner) if events.size() == 1 else -9])
		print("LEVEL %s director: a map battle without the local player is never played as a duel: its winner is Hook_OnBattleResult's or the higher level, so no battle opponent (and no duel_ai level) is involved" % game)
	else:
		var open := director.encounter
		if open == null:
			check(events.size() == 1, "%s: resolved at once by the chapter's script (winner #%d)" % [label, int(events[0].winner) if events.size() == 1 else -9])
			print("LEVEL %s director: this pair is decided by the chapter's Hook_OnBattleResult, no duel" % game)
		else:
			check(open.battle != null and not open.auto, "%s: the first game builds an ordinary duel for it and asks for the battle screen (shown: %s)" % [label, str(shown)])
			print("LEVEL %s director: the first game has no automatic resolution: such a pair opens as an ordinary battle in the battle screen (side 0 at the screen, the other side played by the computer opponent at the duel_ai level, as in any battle there)" % game)
			director.encounter = null
	var logged := catcher.take()
	check(logged[0].is_empty(), "%s director: no errors logged (%d%s)" % [game, logged[0].size(), "" if logged[0].is_empty() else ": " + str(logged[0][0])])
	state.close()
