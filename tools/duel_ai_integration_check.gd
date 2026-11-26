extends SceneTree
## Checks how the computer opponent is wired into play, beyond what it
## chooses: a duel shown on screen (which thinks on a worker thread) must get
## the same opponent and the same command as a direct think; a refused
## command must be thought over, not turn into the end of the phase; what the
## opponent remembers between thinks must belong to one duel; lines read ahead
## must not share battle-script state; repeated thinks must not leak; the
## whole decision must keep to its time; tracing must see the engine's
## decisions without changing them; and a phase must get on - no position
## comes twice in it, however the opponent values going back on a block.
##
##   godot --headless --path game --script ../tools/duel_ai_integration_check.gd -- \
##       [--game=el1|el2|both] [--only=worker,refused,...] [--positions=N]
##
## Prints PASS or FAIL per check and exits 1 on any failure. Needs the
## player's game files (user://profiles.json or --el1=/--el2=).

## A stand-in for the battle screen: a node listening to the duel.
class Display:
	extends Node
	func seen() -> void: pass

const CHECKS := ["worker", "refused", "proofs", "plans", "scripts", "cycles", "deadline", "trace", "likely", "sacrifice", "progress"]
## Positions with a forced win (tools/duel_ai_puzzles) in which the opponent
## once went round in circles: see `_check_progress`.
const WON := {"el1": ["el1_win2_303_29", "el1_win2_310_17", "el1_win2_158_19"], "el2": ["el2_win2_20_11", "el2_win2_120_17", "el2_win2_141_21"]}
## The most commands one hero may give in one phase of those duels.
const PHASE_COMMANDS := 40
## Quick engine settings for the checks that compare commands: no time cap,
## so that a busy machine does not change an answer.
const LIGHT := {"smart_engine_budget": 300000, "smart_engine_ms": 0}
## Quick engine duels for finding the engine's spells the original would not
## cast (see `_unlikely_positions`).
const UNLIKELY := {"smart_engine_budget": 200000, "smart_engine_ms": 0, "smart_engine_beyond": 0}

var defaults := {}
var failures := 0
var profile: ELProfile
var _positions_cache := {}

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
		if arg == "--" + name: return "1"
	return fallback

func _initialize() -> void:
	for line: String in (ELCombatSearch as Script).source_code.split("\n"):
		if not line.begins_with("static var smart_"): continue
		var name := line.trim_prefix("static var ").get_slice(" ", 0).get_slice(":", 0)
		defaults[name] = (ELCombatSearch as Script).get(name)
	var games: Array = ["el1", "el2"] if _arg("game", "both") == "both" else [_arg("game", "el1")]
	var only: Array = Array(_arg("only", "").split(",", false))
	for game: String in games:
		profile = _mount(game)
		if profile == null:
			printerr("Game files are required: pass --%s=<folder>" % game)
			quit(1)
			return
		if not ELCombatBrain.available: _fail(game, "engine", "the compiled engine did not load")
		_positions_cache.clear()
		for check: String in CHECKS:
			if not only.is_empty() and check not in only: continue
			_use({})
			_reset()
			call("_check_" + check, game)
	ELPracticeAI.finish()
	print("TOTAL failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func _mount(game: String) -> ELProfile:
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(game, ""))
	var p := ELProfile.new()
	if folder.is_empty() or not p.mount(game, folder): return null
	return p

func _fail(game: String, check: String, why: String) -> void:
	failures += 1
	print("FAIL %s %s: %s" % [game, check, why])

func _pass(game: String, check: String, what: String) -> void:
	print("PASS %s %s: %s" % [game, check, what])

func _use(settings: Dictionary) -> void:
	for name: String in defaults: (ELCombatSearch as Script).set(name, settings.get(name, defaults[name]))

## What the opponent remembers between thinks, forgotten.
func _reset() -> void:
	ELCombatSearch._plans.clear()
	ELCombatSearch._proofs.clear()

func _restore(snapshot: Dictionary) -> ELDuel:
	var d := ELDuel.new()
	if not d.restore(profile, {"format": "etherlords-duel", "version": 1, "state": snapshot.duplicate(true)}):
		printerr("restore: " + d.error)
		return null
	return d

func _smart(d: ELDuel) -> void:
	var sides: Array[int] = [d.active_side()]
	d.smart_sides = sides

## Positions from a few quick computer-vs-computer duels (every third
## command), `count` of them spread evenly over the pool.
func _positions(count: int) -> Array:
	if not _positions_cache.has("pool"):
		var pool: Array = []
		var pairs := [["Red", 4, "Blue", 4], ["Green", 3, "Black", 3], ["Blue", 5, "Red", 5], ["Black", 6, "Green", 6], ["Red", 6, "Green", 6], ["Blue", 3, "Black", 3]]
		var letter := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
		for p: Array in pairs:
			var players := [{"faction": p[0], "deck": "PR%s%d" % [letter[p[0]], p[1]], "level": int(p[1]) * 2}, {"faction": p[2], "deck": "PR%s%d" % [letter[p[2]], p[3]], "level": int(p[3]) * 2}]
			var duel := ELDuel.new()
			if not duel.start(profile, 1000 + pool.size(), {"players": players}): continue
			_use({"smart_engine": false, "smart_budget": 300})
			var sent := 0
			var taken := 0
			while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= 20 and taken < 25:
				_smart(duel)
				sent += 1
				if sent % 3 == 0:
					pool.append(duel.snapshot())
					taken += 1
				var command := ELCombatSearch.think(duel, {"fresh": true})
				if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
			_use({})
		_reset()
		_positions_cache.pool = pool
	var all: Array = _positions_cache.pool
	var out: Array = []
	for i in mini(count, all.size()): out.append(all[i * all.size() / mini(count, all.size())])
	return out

func _engine_of(stats: Dictionary) -> String:
	if stats.has("engine"): return String(stats.engine)
	return "native" if stats.has("far") else "search"

func _after(snapshot: Dictionary, command: Dictionary) -> Dictionary:
	var d := _restore(snapshot)
	if command.is_empty() or not ELCombatSearch.apply(d, command): d.end_phase()
	return d._snapshot()

# --- 1: the worker thread thinks like a direct call ----------------------------

func _check_worker(game: String) -> void:
	var positions := _positions(int(_arg("positions", "8")))
	var same := 0
	var differ := 0
	var problems: Array = []
	for snapshot: Dictionary in positions:
		_use(LIGHT)
		_reset()
		var direct := _restore(snapshot)
		_smart(direct)
		var stats := {}
		var command := ELCombatSearch.think(direct, stats)
		var engine := _engine_of(stats)
		var expected := _after(snapshot, command)
		_reset()
		var shown := _restore(snapshot)
		_smart(shown)
		var display := Display.new()
		root.add_child(display)
		shown.changed.connect(display.seen)
		var before := shown._snapshot()
		var began := Time.get_ticks_msec()
		while shown._snapshot() == before and Time.get_ticks_msec() - began < 120000:
			ELPracticeAI.step(shown)
			OS.delay_msec(2)
		ELPracticeAI.finish()
		var last: Variant = (ELPracticeAI as Script).get("last_decision")
		var worker_engine: String = String(last.get("engine", "?")) if last is Dictionary and bool(last.get("worker", false)) else "unknown"
		display.free()
		var matched: bool = shown._snapshot() == expected
		if not matched: differ += 1
		if engine != worker_engine: problems.append("round %d: direct engine %s, worker %s%s" % [int(snapshot.round), engine, worker_engine, "" if matched else ", different command"])
		elif not matched: problems.append("round %d: different command (direct %s)" % [int(snapshot.round), str(command)])
		elif engine == "forced_pass":
			var legal := ELPuzzleProof.legal_moves(direct)
			if command.get("kind") != "end_phase" or legal.size() != 1 or legal[0].kind != "end_phase":
				problems.append("round %d: defence had another legal command" % int(snapshot.round))
		elif engine in ["native", "proof", "beyond", "plan"]: same += 1
		else: problems.append("round %d: engine %s, not the compiled one" % [int(snapshot.round), engine])
	if problems.is_empty() and same > 0: _pass(game, "worker", "%d positions, same engine and command on the worker thread" % same)
	else: _fail(game, "worker", "%d of %d commands differ; %s" % [differ, positions.size(), "; ".join(problems)])

# --- 2: a refused command is thought over -------------------------------------

func _check_refused(game: String) -> void:
	if not (ELPracticeAI as Script).get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "send"):
		_fail(game, "refused", "no ELPracticeAI.send: a refused command ends the phase")
		return
	for snapshot: Dictionary in _positions(8):
		_use(LIGHT)
		_reset()
		var clean := _restore(snapshot)
		_smart(clean)
		var command := ELCombatSearch.think(clean, {"fresh": true})
		if String(command.get("kind", "end_phase")) == "end_phase": continue
		var expected := _after(snapshot, command)
		_reset()
		var d := _restore(snapshot)
		_smart(d)
		_check_displayed_retry(game, snapshot, expected)
		_reset()
		var before := int((ELPracticeAI as Script).get("refused"))
		(ELPracticeAI as Script).call("send", d, {"kind": "attack", "id": 9999})
		if int((ELPracticeAI as Script).get("refused")) != before + 1: _fail(game, "refused", "the refusal was not counted")
		elif d._snapshot() != expected: _fail(game, "refused", "after the refusal the duel did not take the opponent's own command %s" % str(command))
		else:
			# A remembered step the duel would refuse is dropped, not sent.
			var e := _restore(snapshot)
			_smart(e)
			var place: Array = ((ELCombatSearch as Script).call("_place", e) as Array).duplicate(true)
			ELCombatSearch._plans[hash(place)] = {"at": place, "command": {"kind": "attack", "id": 9999}}
			var again := ELCombatSearch.think(e, {})
			if String(again.get("kind", "")) == "attack" and int(again.get("id", 0)) == 9999: _fail(game, "refused", "a remembered step the rules refuse was sent")
			elif ELCombatSearch._plans.has(hash(place)): _fail(game, "refused", "the refused remembered step was kept")
			else: _pass(game, "refused", "a refused command was counted and thought over (%s)" % str(command))
		return
	_fail(game, "refused", "no position where the opponent plays something other than the end of the phase")

func _check_displayed_retry(game: String, snapshot: Dictionary, expected: Dictionary) -> void:
	var duel := _restore(snapshot)
	_smart(duel)
	var display := Display.new()
	root.add_child(display)
	duel.changed.connect(display.seen)
	ELPracticeAI.step(duel)
	while ELPracticeAI.thinking(duel): OS.delay_msec(1)
	var job: ELPracticeAI.Job = ELPracticeAI._jobs[duel.get_instance_id()]
	job.result.command = {"kind": "attack", "id": 9999}
	var initial := duel._snapshot()
	ELPracticeAI.step(duel)
	job = ELPracticeAI._jobs.get(duel.get_instance_id())
	if job == null or not job.request.has("retry_command") or duel._snapshot() != initial:
		_fail(game, "refused", "the displayed refusal did not leave a retry on the background worker")
	else:
		while ELPracticeAI.thinking(duel): OS.delay_msec(1)
		ELPracticeAI.step(duel)
		if duel._snapshot() != expected: _fail(game, "refused", "the displayed retry chose a different recovery")
		else: _pass(game, "refused", "a displayed refusal returned before recovery and applied the worker's command")
	ELPracticeAI.finish()
	display.free()

# --- 3: what the proofs settled belongs to one duel ----------------------------

func _check_proofs(game: String) -> void:
	var entries := ELPuzzles.list(game)
	var tried := 0
	for entry: Dictionary in entries:
		if int(entry.turns) != 1: continue
		var won: Dictionary = entry.state
		var empty: Dictionary = won.duplicate(true)
		var mover := int(won.attacker) if int(won.phase) == 0 else 1 - int(won.attacker)
		# The same turn, phase and chance, with nothing to win with.
		empty.creatures = {}
		empty.heroes[1 - mover].health = 99
		_use(LIGHT)
		_reset()
		var fresh := _restore(won)
		_smart(fresh)
		var alone := {}
		ELCombatSearch.think(fresh, alone)
		if int(alone.get("proven", 0)) == 0: continue
		tried += 1
		_reset()
		var first := _restore(empty)
		_smart(first)
		ELCombatSearch.think(first, {})
		var after := _restore(won)
		_smart(after)
		var stats := {}
		ELCombatSearch.think(after, stats)
		if int(stats.get("proven", 0)) == 0:
			_fail(game, "proofs", "puzzle %s: a win proven alone (%d positions) is not proven after another duel at the same turn (%d positions)" % [String(entry.id), int(alone.get("positions", 0)), int(stats.get("positions", 0))])
			return
		if tried >= 3: break
	if tried == 0: _fail(game, "proofs", "no puzzle with a proven first-turn win")
	else: _pass(game, "proofs", "%d puzzles proven alike alone and after another duel's think" % tried)
	var cleared := (ELCombatSearch as Script).get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "reset_caches")
	if not cleared: _fail(game, "proofs", "no ELCombatSearch.reset_caches")
	else:
		ELCombatSearch._proofs[1] = {}
		ELCombatSearch._plans[1] = {}
		(ELCombatSearch as Script).call("reset_caches")
		if ELCombatSearch._proofs.is_empty() and ELCombatSearch._plans.is_empty(): _pass(game, "proofs", "reset_caches forgets proofs and plans")
		else: _fail(game, "proofs", "reset_caches left something behind")

# --- 3b: a remembered plan belongs to one duel and its chance -------------------

## A position, a duel at it with a plan remembered for its next step, and the
## command that led there, with the settings left in force. The engine's lines
## mostly stop at a card, so the search's attack plans are tried too. Empty
## when none is found.
func _planned() -> Array:
	var search := LIGHT.duplicate()
	search.smart_engine = false
	for settings: Dictionary in [LIGHT, search]:
		for snapshot: Dictionary in _positions(40):
			_use(settings)
			_reset()
			var d := _restore(snapshot)
			_smart(d)
			var command := ELCombatSearch.think(d, {})
			if not ELCombatSearch.apply(d, command) or d.phase == ELDuel.Phase.FINISHED: continue
			_smart(d)
			if not ELCombatSearch._recall(d).is_empty(): return [snapshot, d, command]
	return []

func _check_plans(game: String) -> void:
	var found := _planned()
	if found.is_empty():
		_fail(game, "plans", "no position with a remembered plan")
		return
	var other := _restore(found[0])
	ELCombatSearch.apply(other, found[2])
	_smart(other)
	if not ELCombatSearch._recall(other).is_empty():
		_fail(game, "plans", "another duel at the same position followed the first duel's plan")
		return
	var d: ELDuel = found[1]
	d.rng_state += 1
	var changed := ELCombatSearch._recall(d)
	d.rng_state -= 1
	if not changed.is_empty(): _fail(game, "plans", "a plan was followed after the state of chance changed")
	else: _pass(game, "plans", "a plan is followed only in its own duel and state of chance")
	var defence := preload("res://../tools/duel_fixtures.gd").build(profile, {
		"phase": "defence", "attacks": [2], "heroes": [{"health": 3}, {"health": 10}],
		"creatures": [{"owner": 0, "card": "KBWR", "power": 1, "toughness": 1},
			{"owner": 1, "card": "GROG", "power": 4, "toughness": 4}],
	})
	if defence == null:
		_fail(game, "plans", "could not build the defence-to-attack position")
		return
	var end := {"kind": "end_phase"}
	ELCombatSearch._remember(defence, [end, end])
	if not defence.end_phase() or defence.attacker != 1 or defence.phase != ELDuel.Phase.ATTACK:
		_fail(game, "plans", "defender did not reach its attack phase")
	elif not ELCombatSearch._recall(defence).is_empty():
		_fail(game, "plans", "the defender carried a pass into its own attack turn")
	else: _pass(game, "plans", "the former defender chooses a fresh plan on its attack turn")

# --- 4: lines read ahead keep their own battle-script state ----------------------

func _check_scripts(game: String) -> void:
	if game != "el2": return
	ELBattleScripts.fixtures[ELBattleScripts.chunk_path("ai_counter")] = "counter = 0\nfunction CHook_OnLogicSummon(side, card, id)\n  counter = counter + 1\n  ExSetNewCreatureBaseStat(0, counter)\nend\n".to_utf8_buffer()
	var players := [{"faction": "Red", "deck": "PRR4", "level": 8}, {"faction": "Blue", "deck": "PRU4", "level": 8}]
	var duel := ELDuel.new()
	if not duel.start(profile, 77, {"players": players}):
		_fail(game, "scripts", "cannot start: " + duel.error)
		return
	duel.scripts = ELBattleScripts.new(duel)
	duel.scripts.load_all([{"name": "ai_counter", "side": 0}])
	duel.scripts.in_combat = true
	if duel.scripts.states.is_empty():
		_fail(game, "scripts", "the fixture script did not load: %s" % str(duel.scripts.notes))
		return
	var card := ""
	for c: String in duel.heroes[0].deck + duel.heroes[0].hand:
		if profile.table("CombatCreatures").has(c):
			card = c
			break
	var root_copy := duel.search_copy()
	var a := root_copy.search_copy()
	var b := root_copy.search_copy()
	a._summon(0, card)
	b._summon(0, card)
	var pa := int(a.creatures[a.next_id - 1].power)
	var pb := int(b.creatures[b.next_id - 1].power)
	# And the duel itself counts from where it stood.
	duel._summon(0, card)
	var real := int(duel.creatures[duel.next_id - 1].power)
	if pa != pb or real != pa: _fail(game, "scripts", "a summon-counting script gave powers %d and %d in two lines read ahead, %d in the duel" % [pa, pb, real])
	else: _pass(game, "scripts", "each line read ahead keeps its own script state (power %d in both, and in the duel)" % pa)
	# Copies dropped after a summon leave nothing of their scripts behind.
	a = null
	b = null
	for i in 3: root_copy.search_copy()._summon(0, card)
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 50: root_copy.search_copy()._summon(0, card)
	var grown := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - before
	if grown > 20: _fail(game, "scripts", "50 dropped copies with a summon kept %d objects alive" % grown)
	else: _pass(game, "scripts", "50 dropped copies with a summon kept %d objects" % grown)
	root_copy.scripts.close()
	ELBattleScripts.fixtures.clear()

# --- 5: no reference cycles left by trying the engine's unmodelled moves ----------

func _check_cycles(game: String) -> void:
	var positions := _positions(8)
	var d := _restore(positions[mini(4, positions.size() - 1)])
	var ctx := ELCombatSearch.plain_context(d, d.active_side())
	ctx.set("smart", true)
	ctx.set("budget", 8000)
	_use({"smart_engine_budget": 8000, "smart_engine_ms": 0})
	var found := ELCombatBrain.choose(ctx, d, 4, 8000, 16, 16)
	for i in 5: ELCombatSearch._beyond(ctx, d, found)
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 100: ELCombatSearch._beyond(ctx, d, found)
	var grown := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - before
	if grown > 20: _fail(game, "cycles", "100 tries of the unmodelled moves kept %d objects alive" % grown)
	else: _pass(game, "cycles", "100 tries of the unmodelled moves kept %d objects" % grown)

# --- 6: the whole decision keeps to its time ------------------------------------

func _check_deadline(game: String) -> void:
	var ms := int(_arg("deadline_ms", "300"))
	var worst := 0
	var thinks := 0
	# The fullest boards, where the engine and the moves it does not model
	# take longest to read, and positions where the engine's spell is one the
	# original would not cast, which the engine weighs again.
	var boards := _positions(60).duplicate()
	boards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.creatures.size() > b.creatures.size())
	for snapshot: Dictionary in boards.slice(0, 8) + _unlikely_positions(UNLIKELY, 4):
		_use({"smart_engine_ms": ms, "smart_engine_budget": 8000000})
		_reset()
		var d := _restore(snapshot)
		_smart(d)
		var began := Time.get_ticks_usec()
		ELCombatSearch.think(d, {"fresh": true})
		worst = maxi(worst, int(Time.get_ticks_usec() - began) / 1000)
		thinks += 1
	# The engine's own readings stop at the time cap; what the wrapper adds
	# around them may run over by a little.
	if worst > ms + maxi(100, ms / 2): _fail(game, "deadline", "a %d ms decision took %d ms" % [ms, worst])
	else: _pass(game, "deadline", "%d thinks at %d ms, the longest %d ms" % [thinks, ms, worst])
	# A decision is the think and the sending: a command the duel refuses is
	# thought over in what the decision has left of its time (and a short
	# while at the least), not in a fresh think limit. The whole stays within
	# the limit and half a second (tools/duel_ai_latency_check.gd measures
	# this over many positions and limits).
	var longest := 0
	var decisions := 0
	var before := int((ELPracticeAI as Script).get("refused"))
	for snapshot: Dictionary in boards.slice(0, 4):
		_use({"smart_engine_ms": ms, "smart_engine_budget": 8000000})
		_reset()
		var d := _restore(snapshot)
		_smart(d)
		var began := Time.get_ticks_usec()
		var asked := ELCombatSearch.request(d)
		ELCombatSearch.think(d, {"fresh": true}, false, asked)
		ELPracticeAI.send(d, {"kind": "attack", "id": 99999}, false, asked)
		longest = maxi(longest, int(Time.get_ticks_usec() - began) / 1000)
		decisions += 1
	var thought_over := int((ELPracticeAI as Script).get("refused")) - before
	if thought_over != decisions: _fail(game, "deadline", "%d of %d refused commands were thought over" % [thought_over, decisions])
	elif longest > ms + 500: _fail(game, "deadline", "a %d ms decision with a refused command took %d ms" % [ms, longest])
	else: _pass(game, "deadline", "%d decisions at %d ms, each thought over after a refused command, the longest %d ms" % [decisions, ms, longest])
	# After the engine's own reading, the moves it does not model are read
	# with fresh engine calls; those must fit into what is left. Every card in
	# hand is passed off as unmodelled so that there are many such moves, and
	# 60 ms are left of the decision.
	var richest: Dictionary = boards[0]
	var means := -1
	for snapshot: Dictionary in boards:
		var mover: Dictionary = snapshot.heroes[int(snapshot.attacker) if int(snapshot.phase) == 0 else 1 - int(snapshot.attacker)]
		var held := mini(mover.hand.size(), int(mover.mana))
		if held > means:
			means = held
			richest = snapshot
	var d := _restore(richest)
	var ctx := ELCombatSearch.plain_context(d, d.active_side())
	ctx.set("smart", true)
	ctx.set("budget", 8000000)
	ctx.set("rate", 1.0)
	for card: String in d.heroes[d.active_side()].hand: ctx.cards[card] = []
	_use({"smart_engine_ms": ms, "smart_engine_budget": 8000000})
	var found := ELCombatBrain.choose(ctx, d, 4, 20000, 16, 16)
	found.value = -1e6
	var began := Time.get_ticks_usec()
	ctx.set("deadline_usec", began + 60000)
	ELCombatSearch._beyond(ctx, d, found)
	var taken := int(Time.get_ticks_usec() - began) / 1000
	if taken > 60 + 100: _fail(game, "deadline", "with 60 ms left, reading the unmodelled moves took %d ms" % taken)
	else: _pass(game, "deadline", "with 60 ms left, reading the unmodelled moves took %d ms" % taken)

# --- 7, 8: traces see the engine and do not change what it plays -------------------

func _check_trace(game: String) -> void:
	var traced := 0
	for snapshot: Dictionary in _positions(8):
		_use(LIGHT)
		_reset()
		var d := _restore(snapshot)
		_smart(d)
		var stats := {"trace": []}
		var command := ELCombatSearch.think(d, stats)
		if _engine_of(stats) not in ["native", "beyond"]: continue
		var trace: Array = stats.get("trace", [])
		if trace.is_empty() or not trace.any(func(t: Dictionary) -> bool: return t.command == command):
			_fail(game, "trace", "an engine decision (%s) left no trace with its command" % _engine_of(stats))
			return
		traced += 1
	if traced == 0: _fail(game, "trace", "no engine decision traced")
	else: _pass(game, "trace", "%d engine decisions traced with their command" % traced)
	# A proven win gives its line too.
	for entry: Dictionary in ELPuzzles.list(game):
		if int(entry.turns) != 1: continue
		_reset()
		var d := _restore(entry.state)
		_smart(d)
		var stats := {"line": PackedInt32Array()}
		ELCombatSearch.think(d, stats)
		if int(stats.get("proven", 0)) == 0: continue
		if (stats.line as PackedInt32Array).size() <= 8: _fail(game, "trace", "a proven win (%s) gave no line" % String(entry.id))
		else: _pass(game, "trace", "a proven win gives its line")
		break
	# Tracing does not turn plan following off.
	var found := _planned()
	if found.is_empty():
		_fail(game, "trace", "no position with a remembered plan")
		return
	var d: ELDuel = found[1]
	var planned := ELCombatSearch._recall(d)
	var stats := {"trace": []}
	var command := ELCombatSearch.think(d, stats)
	if command != planned or not bool(stats.get("followed", false)): _fail(game, "trace", "with a trace the remembered plan was not followed")
	else: _pass(game, "trace", "a traced think follows the remembered plan")

# --- 9: the original's spell reckoning does not veto the engine -------------------

func _check_likely(game: String) -> void:
	var settings := UNLIKELY
	var fired := 0
	var differ := 0
	for snapshot: Dictionary in _unlikely_positions(settings, 4):
		var commands: Array = []
		var counted := {}
		for likely: bool in [false, true]:
			var chosen := settings.duplicate()
			chosen.smart_engine_likely = likely
			_use(chosen)
			_reset()
			var d := _restore(snapshot)
			_smart(d)
			var stats := {"fresh": true}
			commands.append(ELCombatSearch.think(d, stats))
			counted = stats
		if int(counted.get("unlikely", 0)) == 0: continue
		fired += 1
		if commands[0] != commands[1]: differ += 1
		if commands[0] != commands[1] and int(counted.get("likely", 0)) == 0:
			_fail(game, "likely", "round %d: the engine's %s was replaced by %s" % [int(snapshot.round), str(commands[0]), str(commands[1])])
			return
	if fired == 0: print("SKIP %s likely: no position where the engine casts a spell the original would not" % game)
	else: _pass(game, "likely", "%d engine spells the original would not cast, %d replaced, each by a command weighed as good" % [fired, differ])

## Positions, from quick engine duels, where the engine's command is a spell
## the original's reckoning would not cast.
func _unlikely_positions(settings: Dictionary, count: int) -> Array:
	if _positions_cache.has("unlikely"): return _positions_cache.unlikely
	var out: Array = []
	var letter := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
	for p: Array in [["Blue", 5, "Black", 5], ["Red", 6, "Green", 6], ["Black", 4, "Blue", 4], ["Green", 5, "Red", 5], ["Blue", 6, "Blue", 6], ["Black", 6, "Red", 6]]:
		var players := [{"faction": p[0], "deck": "PR%s%d" % [letter[p[0]], p[1]], "level": int(p[1]) * 2}, {"faction": p[2], "deck": "PR%s%d" % [letter[p[2]], p[3]], "level": int(p[3]) * 2}]
		var duel := ELDuel.new()
		if not duel.start(profile, 2000 + out.size(), {"players": players}): continue
		var thinks := 0
		while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= 20 and thinks < 400 and out.size() < count:
			thinks += 1
			_use(settings)
			_smart(duel)
			var before := duel.snapshot()
			var stats := {"fresh": true}
			var command := ELCombatSearch.think(duel, stats)
			if int(stats.get("unlikely", 0)) > 0: out.append(before)
			if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
	_use({})
	_reset()
	_positions_cache.unlikely = out
	return out

func _check_sacrifice(game: String) -> void:
	var players := [{"faction": "Red", "deck": "PRR4", "level": 8}, {"faction": "Blue", "deck": "PRU4", "level": 8}]
	var duel := ELDuel.new()
	if not duel.start(profile, 5, {"players": players}): return
	var card := ""
	for c: String in ELCombatSearch.SACRIFICE_PRIOR:
		if profile.table("CombatCreatures").has(c): card = c
	if card.is_empty():
		print("SKIP %s sacrifice: no sacrificing creature in this game" % game)
		return
	duel._summon(0, card)
	var cutter := duel.next_id - 1
	var cheap := ""
	var dear := ""
	for c: String in profile.table("CombatCreatures"):
		if not profile.table("CombatSpells").has(c): continue
		var cost := duel.cost(c)
		if cost == 1 and cheap.is_empty(): cheap = c
		if cost >= 4 and dear.is_empty(): dear = c
	duel._summon(0, cheap)
	var a := duel.next_id - 1
	duel._summon(0, dear)
	var b := duel.next_id - 1
	var ability := {"key": "sacrifice", "effect": "sacrifice", "target": "creature"}
	var priors := {}
	for smart: bool in [false, true]:
		var ctx := ELCombatSearch.plain_context(duel, 0)
		ctx.set("smart", smart)
		priors[smart] = [ELCombatSearch._ability_prior(ctx, duel, 0, cutter, card, ability, [a, -1, -1]), ELCombatSearch._ability_prior(ctx, duel, 0, cutter, card, ability, [b, -1, -1])]
	if priors[false][0] != priors[false][1]: _fail(game, "sacrifice", "the original opponent's quirk (pricing creature 2) changed: %s" % str(priors[false]))
	elif priors[true][0] == priors[true][1]: _fail(game, "sacrifice", "the smarter player prices every victim alike: %s" % str(priors[true]))
	else: _pass(game, "sacrifice", "original %s, smarter %s" % [str(priors[false]), str(priors[true])])

# --- 11: a phase gets on --------------------------------------------------------

## Both heroes of a won position played by the smarter opponent, as a puzzle
## is. To a proof every command of a won position is as good as another, and
## to a hero that is lost whatever it does so is every command it has: a
## block taken back and set again changes nothing, and an opponent that
## chose such commands held its phase for ever. No position may come twice
## in one phase, and no phase may take more than PHASE_COMMANDS commands.
func _check_progress(game: String) -> void:
	var folder := ProjectSettings.globalize_path("res://").path_join("../tools/duel_ai_puzzles").simplify_path()
	var played := 0
	for name: String in WON.get(game, []):
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(name + ".json")))
		var d := ELDuel.new()
		if document is not Dictionary or not d.restore(profile, document):
			_fail(game, "progress", "%s does not restore" % name)
			return
		_use(LIGHT)
		_reset()
		var both: Array[int] = [0, 1]
		var until := d.round_number + 3
		var phase := -1
		var seen := {}
		var commands := 0
		var longest := 0
		var sent := 0
		while d.phase != ELDuel.Phase.FINISHED and d.round_number <= until and sent < 600:
			var now := hash([d.turn_serial, d.phase, d.attacker, d.active_side()])
			if now != phase:
				phase = now
				seen = {}
				commands = 0
			var here: int = (ELCombatSearch as Script).call("_position", d)
			if seen.has(here):
				_fail(game, "progress", "%s: a position came twice in one phase (round %d, command %d of the phase)" % [name, d.round_number, commands])
				return
			seen[here] = true
			d.smart_sides = both
			var command := ELCombatSearch.think(d, {})
			(ELPracticeAI as Script).call("send", d, command)
			commands += 1
			sent += 1
			longest = maxi(longest, commands)
			if commands > PHASE_COMMANDS:
				_fail(game, "progress", "%s: more than %d commands in one phase (round %d)" % [name, PHASE_COMMANDS, d.round_number])
				return
		played += 1
		print("     %s: %d commands, at most %d in a phase" % [name, sent, longest])
	if played > 0: _pass(game, "progress", "%d won positions played on with no position twice in a phase" % played)
	else: _fail(game, "progress", "no won positions to play")
