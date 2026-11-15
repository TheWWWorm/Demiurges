extends SceneTree
## Blind benchmark of the compiled duel engine on the authored puzzles.
##
## Each packed puzzle of res://puzzles/<game>.json is started as the game
## starts it (ELPuzzles.Run) and played through: wherever the player's hero
## is to act, the compiled engine is asked to prove a win within the own
## turns the puzzle has left (ELCombatBrain.prove) and the first command of
## the line it proves is played; the other hero is the puzzle defender as the
## game ships it (the smarter computer player, read by positions rather than
## by the clock). A puzzle's reference solution, hints and refutations are
## never read: nothing here orders the search by them.
##
##   godot --headless --path game --script ../tools/duel_puzzle_bench.gd --
##       [--game=el1|el2] [--only=<id>] [--shard=I/N] [--budget=N] [--out=<abs path>]
##
## --budget is the positions each proof may read (default 5000000). --out
## writes a JSON line of settings, then one line per puzzle. Each puzzle ends
## in one class:
##   unsupported         the position does not fit the engine's model
##   search_limit        no win found and the budget ran out
##   exhaustive_failure  the bounded search was complete and found no forced win
##   illegal             the game refused a command of a proven line
##   objective_failure   a proven win was played but the puzzle failed
##   verified            the puzzle was solved
## "lost_proof" marks a puzzle whose win was proved at the start but not again
## later in the line; the rest is then played by the engine's ordinary choice.
## Results are data: the tool exits 0 whenever it ran.

const SIDE := ELPuzzles.Run.SIDE
const STEPS := 400
const CLASSES := ["verified", "objective_failure", "illegal", "exhaustive_failure", "search_limit", "unsupported"]

var profile: ELProfile
var budget := 5000000

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return fallback

## What the engine is told of the player's hero when it is asked for a proof:
## a fresh context every time, nothing carried from an earlier call.
func _context() -> ELCombatSearch.Context:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = SIDE
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.chosen_weights(ctx.second)
	ctx.remember = true
	ctx.foe_health = ELCombatSearch.smart_foe_health
	ctx.brain_cards = ELCombatSearch.smart_brain_cards
	return ctx

## The player's own turns left, the one under way counted.
func _turns_left(run: ELPuzzles.Run) -> int:
	return run.allowed - run.turn + (1 if run.duel.attacker == SIDE else 0)

## A command in plain fields, with the card it concerns.
func _said(duel: ELDuel, command: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["kind", "index", "id", "key", "target", "grave", "power", "choice", "amount"]:
		if command.has(key): out[key] = command[key]
	if command.has("card"): out.card = String(command.card)
	elif duel.creatures.has(int(command.get("id", -1))): out.card = String(duel.creatures[int(command.id)].card)
	if duel.creatures.has(int(command.get("target", -99))): out.target_card = String(duel.creatures[int(command.target)].card)
	return out

## The game's command for the first step of a proven line, or {} when the
## step names nothing the game can play. A whole attack is given one
## creature at a time, guards last, as the game gives it.
func _first(duel: ELDuel, step: Array) -> Dictionary:
	var ids: Array = duel.creatures.keys()
	var kind := int(step[0])
	if kind == 0: return {"kind": "end_phase"}
	if kind == 5:
		var mask := (int(step[1]) & 0xffff) | (int(step[2]) << 16)
		var plain: Array = []
		var guards: Array = []
		for i in ids.size():
			if mask & (1 << i) and not duel.attacks.has(int(ids[i])):
				(guards if duel.has_flag(int(ids[i]), "TeamAttack") else plain).append({"kind": "attack", "id": int(ids[i])})
		var sending := plain + guards
		return sending[0] if not sending.is_empty() else {}
	var command := ELCombatBrain._command_of(duel, ids, kind, int(step[1]), int(step[2]), int(step[3]))
	if String(command.get("kind", "end_phase")) == "end_phase": return {}
	return command

func _prove(duel: ELDuel, turns: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var proof := ELCombatBrain.prove(_context(), duel, turns, budget)
	proof.ms = Time.get_ticks_msec() - started
	return proof

func _won(proof: Dictionary) -> bool:
	return int(proof.get("turns", 0)) > 0 and not (proof.get("line", []) as Array).is_empty()

## The defender's command, as the game asks for it in a puzzle.
func _defend(duel: ELDuel) -> Dictionary:
	var smart: Array[int] = [duel.active_side()]
	duel.smart_sides = smart
	return ELCombatSearch.think(duel, {})

func _bench(index: int, entry: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	ELCombatSearch._proofs.clear()
	ELCombatSearch._plans.clear()
	var goal: Dictionary = entry.get("objective", {"type": "win"})
	var row := {"id": String(entry.id), "objective": String(goal.get("type", "win")), "turns": int(entry.turns)}
	var run := ELPuzzles.Run.new()
	if not run.begin(profile, index):
		row["class"] = "unsupported"
		row.error = run.error
		return row
	var duel := run.duel
	var played: Array = []
	var proofs := 0
	var positions := 0
	var lost := false
	var refused := {}
	var root := {}
	var steps := 0
	while run.outcome.is_empty() and duel.phase != ELDuel.Phase.FINISHED and steps < STEPS:
		steps += 1
		var applied := false
		if duel.active_side() == SIDE:
			var command := {}
			if not lost:
				var proof := _prove(duel, maxi(1, _turns_left(run)))
				proofs += 1
				positions += int(proof.get("positions", 0))
				if root.is_empty(): root = proof
				if _won(proof):
					command = _first(duel, (proof.line as Array)[0])
					if command.is_empty():
						refused = {"step": (proof.line as Array)[0], "why": "unmapped"}
						break
				elif proofs == 1:
					# No win at the start: nothing to play.
					break
				else:
					lost = true
					row.lost_proof = {"at": played.size(), "turns_left": _turns_left(run), "aborted": bool(proof.get("aborted", false)), "positions": int(proof.get("positions", 0))}
			if lost:
				var smart: Array[int] = [SIDE]
				duel.smart_sides = smart
				command = ELCombatSearch.think(duel, {})
				if command.is_empty(): command = {"kind": "end_phase"}
			var said := _said(duel, command)
			applied = duel.end_phase() if String(command.kind) == "end_phase" else ELCombatSearch.apply(duel, command)
			if not applied and not lost:
				refused = {"command": said, "error": String(duel.error)}
				break
			said.side = SIDE
			if lost: said.fallback = true
			played.append(said)
			if not applied: duel.end_phase()
		else:
			var command := _defend(duel)
			if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
		run.watch()
	var won := _won(root)
	row.proof_turns = int(root.get("turns", 0))
	row.root_positions = int(root.get("positions", 0))
	row.root_ms = int(root.get("ms", 0))
	row.aborted = bool(root.get("aborted", false))
	row.proofs = proofs
	row.positions = positions
	row.outcome = run.outcome
	row.reason = run.reason
	row.steps = steps
	row.played = played
	if proofs > 0 and not won and (not root.has("turns") or bool(root.get("unknown", false)) or bool(root.get("incomplete", false))):
		row["class"] = "unsupported"
	elif not won and proofs == 0:
		row["class"] = "unsupported"
		row.error = "the player's hero never came to act"
	elif not won:
		row["class"] = "search_limit" if row.aborted else "exhaustive_failure"
	elif not refused.is_empty():
		row["class"] = "illegal"
		row.refused = refused
	elif run.outcome == "solved":
		row["class"] = "verified"
	else:
		row["class"] = "objective_failure"
		if run.outcome.is_empty(): row.reason = "unfinished after %d steps" % steps
	row.ms = Time.get_ticks_msec() - started
	if duel.scripts != null and duel.scripts.search_only: duel.scripts.close()
	return row

func _initialize() -> void:
	var game := _arg("game", "el1")
	budget = int(_arg("budget", "5000000"))
	var only := _arg("only", "")
	var shard := _arg("shard", "0/1")
	var part := int(shard.get_slice("/", 0))
	var parts := maxi(1, int(shard.get_slice("/", 1)))
	if not ELCombatBrain.available or not ClassDB.class_exists(&"ELNativeDuelBrain"):
		printerr("The compiled engine is not loaded.")
		quit(1)
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	profile = ELProfile.new()
	if saved is not Dictionary or not profile.mount(game, String(saved.get(game, ""))):
		printerr("Game files are required.")
		quit(1)
		return
	ELPuzzles.remember = false
	# The defender reads by positions, not by the clock, so results do not
	# depend on how busy the machine is.
	ELCombatSearch.smart_engine_ms = 0
	var settings := {"settings": true, "game": game, "budget": budget, "shard": shard, "only": only,
		"defender": "ELCombatSearch.think, smart_sides=[defender]",
		"smart_engine_ms": ELCombatSearch.smart_engine_ms, "smart_engine_budget": ELCombatSearch.smart_engine_budget,
		"smart_engine_phases": ELCombatSearch.smart_engine_phases, "smart_engine_steps": ELCombatSearch.smart_engine_steps,
		"smart_engine_width": ELCombatSearch.smart_engine_width, "smart_engine_prove": ELCombatSearch.smart_engine_prove,
		"smart_engine_prove_share": ELCombatSearch.smart_engine_prove_share, "smart_engine_guard": ELCombatSearch.smart_engine_guard,
		"smart_engine_sight": ELCombatSearch.smart_engine_sight, "smart_engine_blind": ELCombatSearch.smart_engine_blind,
		"smart_engine_even": ELCombatSearch.smart_engine_even, "smart_engine_ordered": ELCombatSearch.smart_engine_ordered,
		"smart_engine_sets": ELCombatSearch.smart_engine_sets, "smart_engine_plans": ELCombatSearch.smart_engine_plans,
		"smart_engine_table": ELCombatSearch.smart_engine_table, "smart_foe_health": ELCombatSearch.smart_foe_health,
		"smart_brain_cards": ELCombatSearch.smart_brain_cards}
	print("SETTINGS " + JSON.stringify(settings))
	var file: FileAccess = null
	var out := _arg("out", "")
	if not out.is_empty():
		file = FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write %s" % out)
			quit(1)
			return
		file.store_line(JSON.stringify(settings))
		file.flush()
	var entries := ELPuzzles.list(game)
	var rows: Array = []
	for i in entries.size():
		if not only.is_empty() and String(entries[i].id) != only: continue
		if only.is_empty() and i % parts != part: continue
		var row := _bench(i, entries[i])
		rows.append(row)
		print("PUZZLE %-48s %-8s turns=%d %-18s proof=%d positions=%d aborted=%s ms=%d outcome=%s %s%s" % [row.id, row.objective, int(row.turns), row["class"],
			int(row.get("proof_turns", 0)), int(row.get("root_positions", 0)), str(row.get("aborted", false)), int(row.get("ms", 0)),
			String(row.get("outcome", "")), String(row.get("reason", "")), " lost_proof" if row.has("lost_proof") else ""])
		if row.has("refused"): print("  REFUSED " + JSON.stringify(row.refused))
		if file != null:
			file.store_line(JSON.stringify(row))
			file.flush()
	_summary(rows)
	print("DONE")
	quit(0)

func _summary(rows: Array) -> void:
	var counts := {}
	for name: String in CLASSES: counts[name] = {"all": 0, "win": 0, "other": 0}
	for row: Dictionary in rows:
		var kind := "win" if String(row.objective) == "win" else "other"
		counts[row["class"]].all += 1
		counts[row["class"]][kind] += 1
	print("SUMMARY %d puzzles" % rows.size())
	print("  %-20s %5s %5s %5s" % ["class", "all", "win", "other"])
	for name: String in CLASSES:
		print("  %-20s %5d %5d %5d" % [name, int(counts[name].all), int(counts[name].win), int(counts[name].other)])
	var lost := rows.filter(func(row: Dictionary) -> bool: return row.has("lost_proof")).size()
	if lost > 0: print("  lost_proof           %5d" % lost)
