extends SceneTree
## Measures how long the smarter computer opponent takes over one decision in
## hard positions, and checks that none runs past its think limit.
##
## A decision is everything between the request for a command and the duel
## taking one: the think (ELCombatSearch.think) and the sending
## (ELPracticeAI.send), with any second thought the sending needs. Each
## position is decided at each think limit of --caps (thousandths of a
## second; `smart_engine_ms`, and `search_ms` for the search written in the
## game's language), with the engine's usual budget of positions, in these
## ways:
##   plain    thought out and sent, as a duel off screen is played;
##   refused  thought out, then a command the rules refuse is sent in its
##            place, so that the position is thought over again in what the
##            decision has left: the longest a decision can get;
##   search   the same as plain with the compiled engine switched off (only
##            the crowded positions: what the browser version plays);
##   worker   through ELPracticeAI.step for a duel on screen, which thinks on
##            a worker thread (a few positions; --worker=0 leaves it out).
## The positions:
##   puzzle   authored puzzles from their start (the longest proofs: those
##            with the most turns, and el2 "bank discount"), the solver's
##            first decisions and the defender's;
##   kept     the fullest boards of tools/duel_ai_positions;
##   played   the fullest boards and the richest hands met in a few quick
##            computer-against-computer duels;
##   crowd    boards of twelve creatures with fifty copies of one enchantment
##            on each hero (tools/duel_fixtures.gd), one of them with a hand
##            of nine cards, which the engine's model has no room for, and
##            one with twenty creatures (the most the rules allow).
##
##   godot --headless --path game --script ../tools/duel_ai_latency_check.gd -- \
##       [--game=el1|el2|both] [--caps=100,500,2500,5000] [--slack=500] [--steps=2]
##       [--only=puzzle,kept,played,crowd] [--ways=plain,refused,search,worker]
##       [--limit=N] [--worker=3] [--verbose]
##
## One CAP line per think limit and way: the decisions, their median, 95th
## percentile and longest, and how far the longest ran past the limit; a SLOW
## line for every decision more than 300 ms past its limit, with the stages
## of its think (ELCombatSearch.think's "stages", in ms). PASS when no
## decision took longer than the limit plus --slack ms, FAIL otherwise; exits
## 1 on any failure. Needs the player's game files (user://profiles.json or
## --el1=/--el2=).

const Fixtures := preload("res://../tools/duel_fixtures.gd")
const POSITIONS := "res://../tools/duel_ai_positions"
const CROWD := {"el1": ["SACR", "FRBL", "LSHE"], "el2": ["MNTX", "CMBN"]}

## A stand-in for the battle screen: a node listening to the duel.
class Display:
	extends Node
	func seen() -> void: pass

var defaults := {}
var search_ms_default := 0
var failures := 0
var profile: ELProfile
var verbose := false
var send_shares := true

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
	search_ms_default = ELCombatSearch.search_ms
	verbose = _arg("verbose", "") == "1"
	for method: Dictionary in (ELPracticeAI as Script).get_script_method_list():
		if String(method.name) == "send": send_shares = (method.args as Array).size() >= 4
	ELPuzzles.remember = false
	var games: Array = ["el1", "el2"] if _arg("game", "both") == "both" else [_arg("game", "el1")]
	for game: String in games:
		profile = _mount(game)
		if profile == null:
			printerr("Game files are required: pass --%s=<folder>" % game)
			quit(1)
			return
		if not ELCombatBrain.available:
			failures += 1
			print("FAIL %s: the compiled engine did not load" % game)
			continue
		_measure(game)
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

func _use(settings: Dictionary) -> void:
	for name: String in defaults: (ELCombatSearch as Script).set(name, settings.get(name, defaults[name]))

func _restore(snapshot: Dictionary) -> ELDuel:
	var d := ELDuel.new()
	if not d.restore(profile, {"format": "etherlords-duel", "version": 1, "state": snapshot.duplicate(true)}):
		printerr("restore: " + d.error)
		return null
	return d

# --- the positions, each {name, kind, state (a snapshot)} ------------------------

func _puzzles(game: String) -> Array:
	var entries := ELPuzzles.list(game)
	var order: Array = range(entries.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var x: Dictionary = entries[a]
		var y: Dictionary = entries[b]
		if int(x.turns) != int(y.turns): return int(x.turns) > int(y.turns)
		return (x.state.creatures as Dictionary).size() > (y.state.creatures as Dictionary).size())
	var chosen: Array = order.slice(0, 3)
	for i in entries.size():
		if String(entries[i].id).ends_with("bank_discount") and i not in chosen: chosen.append(i)
	var out: Array = []
	for index: int in chosen:
		var run := ELPuzzles.Run.new()
		if not run.begin(profile, index): continue
		out.append({"name": "puzzle:" + String(entries[index].id), "kind": "puzzle", "state": run.duel.snapshot()})
	return out

func _kept(game: String) -> Array:
	var folder := ProjectSettings.globalize_path("res://").path_join("../tools/duel_ai_positions").simplify_path()
	var found: Array = []
	for file: String in DirAccess.get_files_at(folder):
		if not file.begins_with(game + "_") or not file.ends_with(".json"): continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
		if document is not Dictionary or document.get("state") is not Dictionary: continue
		var d := ELDuel.new()
		if not d.restore(profile, {"format": "etherlords-duel", "version": 1, "state": document.state}): continue
		found.append({"name": "kept:" + file.get_basename(), "kind": "kept", "state": d.snapshot()})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.state.creatures as Dictionary).size() > (b.state.creatures as Dictionary).size())
	return found.slice(0, 4)

func _played(_game: String) -> Array:
	var pool: Array = []
	var pairs := [["Red", 6, "Green", 6], ["Black", 6, "Green", 6], ["Blue", 5, "Red", 5], ["Green", 4, "Black", 4], ["Blue", 6, "Black", 6], ["Red", 4, "Blue", 4]]
	var letter := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}
	for p: Array in pairs:
		var players := [{"faction": p[0], "deck": "PR%s%d" % [letter[p[0]], p[1]], "level": int(p[1]) * 2}, {"faction": p[2], "deck": "PR%s%d" % [letter[p[2]], p[3]], "level": int(p[3]) * 2}]
		var duel := ELDuel.new()
		if not duel.start(profile, 2000 + pool.size(), {"players": players}): continue
		_use({"smart_engine": false, "smart_budget": 300})
		var sent := 0
		var taken := 0
		while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= 24 and taken < 40:
			var sides: Array[int] = [duel.active_side()]
			duel.smart_sides = sides
			sent += 1
			if sent % 3 == 0:
				pool.append({"name": "played:%s%d-%s%d r%d" % [letter[p[0]], p[1], letter[p[2]], p[3], duel.round_number], "kind": "played", "state": duel.snapshot()})
				taken += 1
			var command := ELCombatSearch.think(duel, {"fresh": true})
			if command.is_empty() or not ELCombatSearch.apply(duel, command): duel.end_phase()
		_use({})
	ELCombatSearch.reset_caches()
	var full := pool.duplicate()
	full.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.state.creatures as Dictionary).size() > (b.state.creatures as Dictionary).size())
	var rich := pool.duplicate()
	rich.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _means(a.state) > _means(b.state))
	var out: Array = full.slice(0, 5)
	for row: Dictionary in rich:
		if out.size() >= 8: break
		if row not in out: out.append(row)
	return out

## What the hero to move has to spend and to spend it on.
func _means(state: Dictionary) -> int:
	var mover: Dictionary = state.heroes[int(state.attacker) if int(state.phase) == 0 else 1 - int(state.attacker)]
	return mini(mover.hand.size(), int(mover.mana)) * 100 + (state.creatures as Dictionary).size()

func _crowd(game: String) -> Array:
	var out: Array = []
	var known: Dictionary = profile.table("CombatCreatures")
	var army: Array = []
	for owner in 2:
		for card: String in ["GROG", "GROG", "KBWR", "GROG", "KBWR", "GROG"]:
			if known.has(card): army.append({"card": card, "owner": owner})
	var hand: Array = []
	for card: String in ["GROG", "KBWR", "GROG", "KBWR"]:
		if known.has(card): hand.append(card)
	var cards: Array = CROWD.get(game, [])
	for i in cards.size() + 1:
		# The last one holds nine cards: more than the engine's model has room for.
		var card := String(cards[mini(i, cards.size() - 1)])
		var crowded_hand := i == cards.size()
		var worn: Array = []
		for k in 50: worn.append(card)
		var held: Array = hand.duplicate()
		if crowded_hand:
			while held.size() < 9 and not hand.is_empty(): held.append(hand[held.size() % hand.size()])
		for phase: String in ["attack", "defence"]:
			if crowded_hand and phase == "defence": continue
			var creatures: Array = army.duplicate(true)
			var attacks: Array = []
			if phase == "defence":
				# The first three of hero 0's creatures are sent.
				attacks = [2, 3, 4]
			var duel := Fixtures.build(profile, {"fixed": false, "phase": phase, "attacks": attacks,
				"heroes": [{"health": 30, "mana": 12, "enchantments": worn, "hand": held}, {"health": 30, "mana": 12, "enchantments": worn, "hand": held}], "creatures": creatures})
			if duel == null: continue
			out.append({"name": "crowd:%s x50 %s%s" % [card, phase, " hand of nine" if crowded_hand else ""], "kind": "crowd", "state": duel.snapshot()})
	# And a board near the most the engine's model holds: ten creatures a side, the most a hero may have.
	if not cards.is_empty() and not army.is_empty():
		var many: Array = []
		for owner in 2:
			for k in 10: many.append({"card": String(army[k % 6].card), "owner": owner})
		var worn: Array = []
		for k in 50: worn.append(String(cards[0]))
		var duel := Fixtures.build(profile, {"fixed": false, "heroes": [{"health": 30, "mana": 12, "enchantments": worn, "hand": hand}, {"health": 30, "mana": 12, "enchantments": worn, "hand": hand}], "creatures": many})
		if duel != null: out.append({"name": "crowd:%s x50 attack, 20 creatures" % String(cards[0]), "kind": "crowd", "state": duel.snapshot()})
	return out

# --- one decision -----------------------------------------------------------------

## Decides `steps` commands in a row from the position, each one timed:
## [{ms, engine, status, stages, think_ms}].
func _decide(position: Dictionary, way: String, steps: int) -> Array:
	var rows: Array = []
	ELCombatSearch.reset_caches()
	var d := _restore(position.state)
	if d == null: return rows
	var display: Display = null
	if way == "worker":
		display = Display.new()
		root.add_child(display)
		d.changed.connect(display.seen)
	for step in steps:
		if d.phase == ELDuel.Phase.FINISHED: break
		var sides: Array[int] = [0, 1]
		d.smart_sides = sides
		var stats := {}
		var began := Time.get_ticks_usec()
		var think_usec := 0
		if way == "worker":
			var before := d._snapshot()
			while d._snapshot() == before and Time.get_ticks_usec() - began < 120000000:
				ELPracticeAI.step(d)
				OS.delay_msec(1)
			var last: Dictionary = ELPracticeAI.last_decision
			stats = {"engine": last.get("engine", "?")}
		else:
			var asked := ELCombatSearch.request(d)
			var command := ELCombatSearch.think(d, stats, false, asked)
			think_usec = Time.get_ticks_usec() - began
			if way == "refused": command = {"kind": "attack", "id": 99999}
			# An older ELPracticeAI.send knows nothing of the request (called
			# by name, so that this tool also measures such a copy of the game).
			if send_shares: (ELPracticeAI as Script).call("send", d, command, false, asked)
			else: (ELPracticeAI as Script).call("send", d, command)
		var taken := Time.get_ticks_usec() - began
		var stages := {}
		for name: String in stats.get("stages", {}): stages[name] = int(stats.stages[name]) / 1000
		rows.append({"ms": taken / 1000, "think_ms": think_usec / 1000, "engine": String(stats.get("engine", "?")), "status": String(stats.get("status", "")), "stages": stages,
			"positions": int(stats.get("positions", 0))})
	if display != null:
		ELPracticeAI.finish()
		display.free()
	if d.scripts != null and d.scripts.search_only: d.scripts.close()
	return rows

func _percentile(sorted: Array, q: float) -> int:
	if sorted.is_empty(): return 0
	return int(sorted[clampi(int(ceil(q * float(sorted.size()))) - 1, 0, sorted.size() - 1)])

func _measure(game: String) -> void:
	var only: Array = Array(_arg("only", "puzzle,kept,played,crowd").split(",", false))
	var ways: Array = Array(_arg("ways", "plain,refused,search,worker").split(",", false))
	var caps: Array = Array(_arg("caps", "100,500,2500,5000").split(",", false)).map(func(text: String) -> int: return int(text))
	var slack := int(_arg("slack", "500"))
	var steps := int(_arg("steps", "2"))
	var positions: Array = []
	if "puzzle" in only: positions.append_array(_puzzles(game))
	if "kept" in only: positions.append_array(_kept(game))
	if "played" in only: positions.append_array(_played(game))
	if "crowd" in only: positions.append_array(_crowd(game))
	var limit := int(_arg("limit", "0"))
	if limit > 0: positions = positions.slice(0, limit)
	print("POSITIONS %s %d: %s" % [game, positions.size(), ", ".join(positions.map(func(p: Dictionary) -> String: return "%s (%d creatures)" % [p.name, (p.state.creatures as Dictionary).size()]))])
	var workers := int(_arg("worker", "3"))
	for cap: int in caps:
		for way: String in ways:
			var settings := {"smart_engine_ms": cap, "smart_engine_ms_handheld": cap}
			if way == "search": settings.smart_engine = false
			_use(settings)
			ELCombatSearch.search_ms = cap if way == "search" else search_ms_default
			var times: Array = []
			var worst := {}
			var tried := 0
			for position: Dictionary in positions:
				if way == "search" and String(position.kind) != "crowd": continue
				if way == "worker":
					if tried >= workers: break
					if String(position.kind) not in ["kept", "crowd"]: continue
				tried += 1
				for row: Dictionary in _decide(position, way, steps):
					times.append(int(row.ms))
					if worst.is_empty() or int(row.ms) > int(worst.ms):
						worst = row.duplicate()
						worst.name = position.name
					if verbose: print("  %s %d ms %s: %d ms by %s %s" % [way, cap, position.name, row.ms, row.engine, str(row.stages)])
					if int(row.ms) > cap + 300:
						print("SLOW %s cap=%d way=%s %s: decision %d ms (think %d ms) engine=%s status=%s positions=%d stages=%s" % [game, cap, way, position.name, row.ms, row.think_ms, row.engine, row.status, row.positions, str(row.stages)])
			times.sort()
			var longest := int(times[-1]) if not times.is_empty() else 0
			print("CAP %s cap=%d way=%s decisions=%d p50=%d ms p95=%d ms max=%d ms over=%+d ms (%s by %s)" % [game, cap, way, times.size(), _percentile(times, 0.5), _percentile(times, 0.95), longest, longest - cap,
				str(worst.get("name", "-")), str(worst.get("engine", "-"))])
			if times.is_empty(): continue
			if longest > cap + slack:
				failures += 1
				print("FAIL %s cap=%d way=%s: a decision took %d ms, %d ms past the limit (allowed %d)" % [game, cap, way, longest, longest - cap, slack])
			else: print("PASS %s cap=%d way=%s: %d decisions, the longest %d ms" % [game, cap, way, times.size(), longest])
	_use({})
	ELCombatSearch.search_ms = search_ms_default
