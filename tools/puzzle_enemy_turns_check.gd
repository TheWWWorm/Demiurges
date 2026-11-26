extends SceneTree
## Plays the battle puzzles in which the enemy has turns of its own (survive,
## and control with "enemy_turns") through the battle screen, as the player
## opens them, and watches what the computer defender does on those turns.
##
## The first hero plays either nothing at all (--mode=pass: every phase is
## ended at once) or the commands of its own side from the puzzle's reference
## solution (--mode=reference; the enemy commands the solution lists are left
## to the computer player, whose choices are recorded next to them). Once the
## enemy leaves the solution's line, or a command of the solution is refused,
## the compiled engine answers for the first hero, so the attempt tells
## whether the puzzle can still be solved against what the enemy really did.
## Each puzzle reports the enemy's attacks, casts and abilities per turn and
## what they cost the first hero (health, wounded and lost creatures).
##
## A puzzle fails the check when its reference attempt does not end solved,
## when the enemy had a hostile command (an attack it could declare, a spell
## or an ability) on a turn of its own in that attempt and gave none at all,
## or when the pass attempt ends solved. (A pass attempt the enemy wins
## anyway may well see it wait: that is not counted against it.)
##
##   godot --headless --path game --script ../tools/puzzle_enemy_turns_check.gd --
##       --profile=el1|el2 [--mode=pass|reference|engine|both] [--only=N] [--shard=I/N]
##       [--report=/absolute/report.json] [--verbose=true] [--probe=true] [--deep=true]
## --verbose prints each enemy command and how it was found; --probe weighs
## the enemy's first commands of each attack phase on a copy and prints them.
## --mode=engine lets the compiled engine solve from the start (as
## tools/puzzles_check.gd does), and --deep=true gives the enemy the solver's
## settings as well, as that check does.

var view: Node
var failures := 0

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await process_frame

## The puzzles whose objective is settled at the end of enemy turns.
static func enemy_turn_puzzle(entry: Dictionary) -> bool:
	var goal: Dictionary = entry.get("objective", {})
	return goal.get("type") == "survive" or (goal.get("type") == "control" and goal.has("enemy_turns"))

## A reference command made a command the duel takes.
static func _command(duel: ELDuel, raw: Dictionary) -> Dictionary:
	var command := raw.duplicate(true)
	command.erase("side")
	match String(command.get("kind", "")):
		"cast":
			if command.has("card"): command.index = duel.heroes[duel.active_side()].hand.find(String(command.card))
			command.target = int(command.get("target", -1))
			command.grave = int(command.get("grave", -1))
			command.power = int(command.get("power", 0))
		"ability":
			command.target = int(command.get("target", -1))
			command.choice = int(command.get("choice", -1))
			command.amount = int(command.get("amount", -1))
		"attack", "block":
			command.id = int(command.id)
			if command.has("target"): command.target = int(command.target)
	return command

## Whether the hero to act has a command that harms the other side or
## readies a harm: an attack it may declare, or any spell or ability.
static func hostile_available(duel: ELDuel) -> bool:
	if duel.phase != ELDuel.Phase.ATTACK: return false
	for command: Dictionary in ELCombatSearch.legal(duel):
		if String(command.get("kind", "")) in ["attack", "cast", "ability"]: return true
	return false

## What the first hero holds: its health and each creature's damage.
static func _standing(duel: ELDuel) -> Dictionary:
	var army := {}
	for c: Dictionary in duel.army(0): army[int(c.id)] = int(c.damage)
	return {"health": int(duel.heroes[0].health), "army": army}

func _play(entry: Dictionary, mode: String) -> Dictionary:
	var run: ELPuzzles.Run = view.puzzle_mode.run
	var script: Array = []
	var scripted_enemy: Array = []
	for raw: Dictionary in entry.get("solution", []):
		if int(raw.get("side", 0)) == 1: scripted_enemy.append(raw)
		else: script.append(raw)
	var turns: Array = []
	var current := {}
	var last: Variant = null
	var began := Time.get_ticks_msec()
	var note := ""
	# Once the enemy leaves the line the solution expects, or the solution's
	# next command is refused, the compiled engine finds the first hero's
	# answer (as tools/puzzles_check.gd solves), so that a puzzle with an
	# answer to what the enemy did still counts as solved.
	var solving := mode == "engine"
	var expected := scripted_enemy.duplicate()
	var deviations: Array = []
	var solver_commands := 0
	while run.outcome.is_empty() and Time.get_ticks_msec() - began < 600000:
		await process_frame
		var duel: ELDuel = view.duel
		if duel != run.duel: break
		# A decision of the computer player's: the step's last decision is a
		# new dictionary each time.
		var decision: Dictionary = ELPracticeAI.last_decision
		if not current.is_empty() and not is_same(decision, last) and not decision.is_empty():
			last = decision
			var command: Dictionary = decision.get("command", {})
			current.commands.append(command)
			if mode != "pass" and not solving:
				var wanted: Dictionary = expected.pop_front() if not expected.is_empty() else {}
				if not _same(command, wanted):
					deviations.append({"enemy": command, "expected": wanted})
					solving = true
			if _arg("verbose", "") == "true": print("    enemy %s by %s (%d positions)" % [JSON.stringify(command), String(decision.get("engine", "")), int(decision.get("positions", 0))])
			var kind := String(command.get("kind", ""))
			if kind in ["attack", "cast", "ability"]: current[kind + "s"] = int(current.get(kind + "s", 0)) + 1
		var enemy_turn := duel.phase != ELDuel.Phase.FINISHED and duel.attacker == 1
		if enemy_turn and current.is_empty():
			current = {"before": _standing(duel), "commands": [], "attacks": 0, "casts": 0, "abilitys": 0, "hostile_available": false}
			last = ELPracticeAI.last_decision
		if enemy_turn and duel.active_side() == 1 and duel.phase == ELDuel.Phase.ATTACK and not current.hostile_available:
			current.hostile_available = hostile_available(duel)
			# --save=DIR keeps the first such position of a reference attempt
			# as a tools/duel_ai_positions entry, expecting an attack.
			if current.hostile_available and mode != "pass" and not _arg("save", "").is_empty() and turns.is_empty():
				var file := FileAccess.open(_arg("save", "").path_join("%s_puzzle_%s_enemy_attacks.json" % [duel.profile.id, String(entry.id).trim_prefix(duel.profile.id + "_tactical_v2_")]), FileAccess.WRITE)
				file.store_string(JSON.stringify({"format": "etherlords-duel", "version": 1, "about": "puzzle %s: the enemy attacks the solver's prepared defence, though the solution answers it" % String(entry.id),
					"expect": {"kind": "attack", "side": 1}, "state": duel.snapshot()}, "\t"))
			if _arg("probe", "") == "true":
				var copy := duel.search_copy()
				copy.smart_sides.assign([1])
				var probe := {"trace": []}
				var chosen := ELCombatSearch.think(copy, probe)
				print("    probe %s by %s value %s proven %s status %s" % [JSON.stringify(chosen), probe.get("engine"), probe.get("value"), probe.get("proven"), probe.get("status")])
				for item: Dictionary in probe.get("trace", []): print("      %s = %s" % [JSON.stringify(item.command), item.value])
		if not enemy_turn and not current.is_empty():
			current.after = _standing(duel)
			turns.append(current)
			current = {}
		if duel.phase == ELDuel.Phase.FINISHED or duel.active_side() != 0: continue
		if view._melee_busy() or view._cast_busy() or view._overlay_open(): continue
		if mode == "pass":
			duel.end_phase()
			continue
		if not solving and not script.is_empty():
			var command := _command(duel, script.pop_front())
			if ELCombatSearch.apply(duel, command): continue
			note = "reference command %s refused: %s" % [JSON.stringify(command), duel.error]
			solving = true
		if not solving:
			duel.end_phase()
			continue
		solver_commands += 1
		_solve_step(duel)
		if _arg("verbose", "") == "true": print("    solver %s" % _solver_last)
	if not current.is_empty():
		current.after = _standing(view.duel)
		turns.append(current)
	var out := {"outcome": run.outcome, "reason": run.reason, "turns": turns, "scripted_enemy": scripted_enemy, "deviations": deviations, "solver_commands": solver_commands}
	if not note.is_empty(): out.note = note
	return out

## Whether the enemy's command is the one the solution lists for it.
static func _same(command: Dictionary, wanted: Dictionary) -> bool:
	if String(command.get("kind", "")) != String(wanted.get("kind", "")): return false
	for key: String in ["id", "target"]:
		if wanted.has(key) and int(command.get(key, -1)) != int(wanted[key]): return false
	return true

## The settings the solver reads with (those of tools/puzzles_check.gd), set
## only while it thinks: the enemy keeps the game's own.
const DEEP := {"engine": true, "engine_phases": 6, "engine_steps": 24, "engine_budget": 3000000, "engine_table": true, "engine_ms": 0, "engine_prove_share": 50}

var _solver_last := ""

## One command of the first hero's, chosen by the compiled engine.
func _solve_step(duel: ELDuel) -> void:
	var kept := {}
	for name: String in DEEP:
		kept[name] = (ELCombatSearch as Script).get("smart_" + name)
		(ELCombatSearch as Script).set("smart_" + name, DEEP[name])
	var sides: Array[int] = duel.smart_sides.duplicate()
	var smart: Array[int] = [0]
	duel.smart_sides = smart
	var asked := ELCombatSearch.request(duel)
	var command := ELCombatSearch.think(duel, {}, false, asked)
	_solver_last = JSON.stringify(command)
	ELPracticeAI.send(duel, command, false, asked)
	duel.smart_sides = sides
	for name: String in kept: (ELCombatSearch as Script).set("smart_" + name, kept[name])

## One line per enemy turn: what it sent and what the first hero lost.
static func _summary(turns: Array) -> String:
	var parts: Array = []
	for t: Dictionary in turns:
		var lost := int(t.before.health) - int(t.get("after", t.before).health)
		var wounded := 0
		var died := 0
		for id: int in t.before.army:
			if not t.get("after", t.before).army.has(id): died += 1
			elif int(t.after.army[id]) > int(t.before.army[id]): wounded += 1
		parts.append("A%d C%d B%d hero-%d hurt%d died%d%s" % [t.attacks, t.casts, t.abilitys, lost, wounded, died, "" if t.hostile_available else " (no hostile)"])
	return "; ".join(parts)

func _run() -> void:
	var game := _arg("profile", "el2")
	var modes: Array = ["pass", "reference"] if _arg("mode", "both") == "both" else [_arg("mode", "both")]
	ELPuzzles.remember = false
	# --deep=true reads the enemy with the solver's settings too, as
	# tools/puzzles_check.gd does.
	if _arg("deep", "") == "true":
		for name: String in DEEP: (ELCombatSearch as Script).set("smart_" + name, DEEP[name])
	view = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	view.demo = false
	root.add_child(view)
	await _frames(10)
	if not view.profiles.has(game):
		printerr("Game files are required.")
		quit(1)
		return
	if not ELCombatBrain.available:
		printerr("The compiled engine did not load.")
		quit(1)
		return
	var entries := ELPuzzles.list(game)
	var shard := _arg("shard", "0/1")
	var only := int(_arg("only", "0"))
	view._puzzle_mode_ready()
	view.puzzle_mode.open_list(view.profiles[game])
	var results: Array = []
	var picked := 0
	for i in entries.size():
		if only > 0 and i != only - 1: continue
		if not enemy_turn_puzzle(entries[i]): continue
		picked += 1
		if (picked - 1) % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		var result := {"index": i + 1, "id": String(entries[i].id)}
		var ok := true
		for mode: String in modes:
			ELCombatSearch.reset_caches()
			view._begin_puzzle(i)
			await _frames(5)
			if not view._in_puzzle():
				result[mode] = {"outcome": "did not open"}
				ok = false
				continue
			var began := Time.get_ticks_msec()
			var played := await _play(entries[i], mode)
			played.ms = Time.get_ticks_msec() - began
			result[mode] = played
			if mode == "pass":
				# Doing nothing must not solve the puzzle.
				if played.outcome == "solved": ok = false
			else:
				if played.outcome != "solved": ok = false
				# Against the solution the enemy must act: it had an attack,
				# a spell or an ability on a turn of its own, and used one.
				var available := false
				var acted := 0
				for t: Dictionary in played.turns:
					available = available or bool(t.hostile_available)
					acted += int(t.attacks) + int(t.casts) + int(t.abilitys)
				if available and acted == 0: ok = false
			var extra := ""
			if played.has("note"): extra += " | " + String(played.note)
			if not played.get("deviations", []).is_empty(): extra += " | enemy left the solution's line at %s (solution: %s), solver gave %d command(s)" % [JSON.stringify(played.deviations[0].enemy), JSON.stringify(played.deviations[0].expected), int(played.solver_commands)]
			print("  %s %d %s [%s]: %s (%s) | %s%s" % [game, i + 1, String(entries[i].id), mode, played.outcome, played.reason, _summary(played.turns), extra])
		result.ok = ok
		if not ok: failures += 1
		results.append(result)
		print("%s %d %s" % ["OK" if ok else "FAILED", i + 1, String(entries[i].id)])
	view.puzzle_mode.close()
	if not _arg("report", "").is_empty():
		var file := FileAccess.open(_arg("report", ""), FileAccess.WRITE)
		file.store_string(JSON.stringify({"profile": game, "results": results, "failures": failures}, "\t"))
	print("TOTAL puzzles=%d failures=%d" % [results.size(), failures])
	quit(1 if failures > 0 else 0)
