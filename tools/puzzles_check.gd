extends SceneTree
## Plays the game's battle puzzles through the battle screen itself.
##
## Each puzzle of game/puzzles/<game>.json is opened as the player opens it
## (ELPuzzleMode over the duel view). The compiled engine then plays the
## first hero's side, the game's own computer player defends, and the
## attempt must end solved within the puzzle's turns. One more attempt in
## which the first hero only ends its phases must end unsolved.
##
## Two things are reported apart: whether the engine won (a statement about
## the solver: it must have decided every command itself, with the compiled
## engine, not the search it falls back to) and whether the puzzle is valid
## (its attempt opens, the result is shown, and doing nothing fails).
##
##   godot --headless --path game --script ../tools/puzzles_check.gd --
##       --profile=el1|el2 [--only=N] [--shard=I/N] [--folder=DIR]

const DEEP := {"engine": true, "engine_phases": 6, "engine_steps": 24, "engine_budget": 3000000, "engine_table": true, "engine_ms": 0, "engine_prove_share": 50}

var view: Node
var failures := 0
## The ways the solving side's commands were found in the current attempt.
var engines := {}

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await process_frame

## Plays the open puzzle to its end: `solve` with the engine's commands for
## the first hero, otherwise only ending its phases. Returns the outcome.
func _play(solve: bool) -> String:
	var mode: ELPuzzleMode = view.puzzle_mode
	var began := Time.get_ticks_msec()
	while mode.run != null and mode.run.outcome.is_empty() and Time.get_ticks_msec() - began < 600000:
		await process_frame
		var duel: ELDuel = view.duel
		if duel.phase == ELDuel.Phase.FINISHED or duel.active_side() != 0: continue
		if view._melee_busy() or view._cast_busy() or view._overlay_open(): continue
		var command := {}
		if solve:
			var smart: Array[int] = [0]
			duel.smart_sides = smart
			var stats := {}
			command = ELCombatSearch.think(duel, stats)
			var engine := String(stats.get("engine", "?"))
			engines[engine] = int(engines.get(engine, 0)) + 1
		if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	# The result box follows once the battle has been shown to its end.
	began = Time.get_ticks_msec()
	while mode.run != null and not mode._result.visible and Time.get_ticks_msec() - began < 60000:
		await process_frame
	return mode.run.outcome if mode.run != null else "closed"

func _run() -> void:
	var game := _arg("profile", "el2")
	# The player's own list of solved puzzles stays as it is.
	ELPuzzles.remember = false
	# --folder=DIR: another set of puzzle lists (an earlier release's).
	ELPuzzles.folder = _arg("folder", ELPuzzles.FOLDER)
	for name: String in DEEP: (ELCombatSearch as Script).set("smart_" + name, DEEP[name])
	view = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	view.demo = false
	root.add_child(view)
	await _frames(10)
	if not view.profiles.has(game):
		printerr("Game files are required.")
		quit(1)
		return
	var entries := ELPuzzles.list(game)
	var shard := _arg("shard", "0/1")
	var only := int(_arg("only", "0"))
	view._puzzle_mode_ready()
	view.puzzle_mode.open_list(view.profiles[game])
	var tried := 0
	var won := 0
	var valid := 0
	if not ELCombatBrain.available:
		printerr("The compiled engine did not load: the puzzles cannot be checked with it.")
		quit(1)
		return
	for i in entries.size():
		if only > 0 and i != only - 1: continue
		if i % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
		tried += 1
		var began := Time.get_ticks_msec()
		# Each attempt starts with nothing remembered from another.
		ELCombatSearch.reset_caches()
		engines = {}
		view._begin_puzzle(i)
		await _frames(5)
		if not view._in_puzzle():
			failures += 1
			print("FAILED %d %s: did not open" % [i + 1, String(entries[i].id)])
			continue
		var solved: String = await _play(true)
		var turn: int = view.puzzle_mode.run.turn if view.puzzle_mode.run != null else 0
		var shown: bool = view.puzzle_mode._result.visible
		var used := engines.duplicate()
		ELCombatSearch.reset_caches()
		view._begin_puzzle(i)
		await _frames(5)
		var passed: String = await _play(false)
		# The solver: the compiled engine decided every command and won in time.
		var native := not used.is_empty() and used.keys().all(func(e: String) -> bool: return e in ["native", "proof", "beyond", "plan"])
		var engine_won: bool = solved == "solved" and native
		# The puzzle: a result is shown, and doing nothing does not solve it.
		var sound: bool = shown and passed == "failed" and view.puzzle_mode._result.visible
		if engine_won: won += 1
		if sound: valid += 1
		var ok: bool = engine_won and sound
		if not ok: failures += 1
		print("%s %d %s: engine %s in turn %d of %d (decided by %s) | puzzle %s (result shown %s, passing %s), %d ms" % ["OK" if ok else "FAILED", i + 1, String(entries[i].id), solved, turn, int(entries[i].turns), str(used),
			"valid" if sound else "INVALID", str(shown), passed, Time.get_ticks_msec() - began])
	view.puzzle_mode.close()
	print("TOTAL puzzles=%d engine_won=%d valid=%d failures=%d" % [tried, won, valid, failures])
	quit(1 if failures > 0 else 0)
