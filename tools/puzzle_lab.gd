extends SceneTree
## Headless content laboratory. Normally invoked by tools/puzzle_lab.py, which
## makes the asset-free profile and copies the real battle rules into isolation.
## --file=/absolute/pack.json [--only=id] [--normalize] [--search]
## --commands=/absolute/commands.json replays a custom line for --only.
## --report=/absolute/report.json writes machine-readable results.

const RuntimeChecks = preload("puzzle_lab_checks.gd")

var failures := 0
var nodes := 0
var exhausted := false
var budget := 30000
var memo := {}
var active_path := {}
var chosen := {}
var reference_moves := {}
var reference_policy_moves := {}
var initial: Dictionary = {}
var current_entry: Dictionary = {}
var maximum_depth := 14

func _arg(name: String, fallback := "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value == "--" + name: return "true"
		if value.begins_with("--" + name + "="): return value.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _profile(edition: String, entries: Array) -> ELProfile:
	var profile := ELProfile.new()
	profile.id = edition
	profile.title = "Etherlords I" if edition == "el1" else "Etherlords II"
	if not _arg("installed").is_empty():
		if not profile.mount(edition, _arg("installed")):
			printerr(profile.error)
			return null
		return profile
	if not FileAccess.file_exists("res://fixture.json"):
		printerr("Use tools/puzzle_lab.py for offline fixtures, or pass --installed=/path/to/your/game.")
		return null
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var data: Dictionary = fixtures[edition]
	profile.tables = data.duplicate(true)
	profile.texts = data.texts.duplicate()
	var levels := {}
	for n in range(1, 21): levels["Level%d" % n] = 0
	profile.tables.CombatManaIncome = {"1": levels}
	profile.tables.CombatSceneDB = {"Green.001": {}}
	profile.tables.HeroTemplates = {}
	for entry: Dictionary in entries:
		var state: Dictionary = entry.state
		profile.tables.CombatSceneDB[state.setup.get("arena", "Green.001")] = {}
		for hero: Dictionary in state.heroes:
			if not data.get("HeroTemplateSources", {}).has(hero.template):
				printerr("Unverified %s hero template in %s: %s. Add an edition-specific repository source or use installed-data validation." % [edition, entry.id, hero.template])
				return null
			profile.tables.HeroTemplates[hero.template] = {"BaseHealth": int(hero.maximum), "HealthIncrease": 0}
	return profile

func _supported(entry: Dictionary) -> String:
	if entry.state.has("scripts"): return "Campaign-script fixtures are unsupported."
	if _arg("inspect") != "true" and (entry.state.setup.get("puzzle_fixed_hands", false) != true or entry.state.setup.get("puzzle_fixed_channels", false) != true):
		return "This offline fixture requires fixed puzzle hands and natural channels; use installed-data checks for ordinary duel snapshots."
	for hero: Dictionary in entry.state.heroes:
		if hero.get("spec", "NONE") != "NONE": return "Random specialization fixtures are unsupported."
		for skill: String in hero.get("skills", {}):
			if skill not in ["REGN", "CNLG"]: return "Only deterministic Regeneration and Channeling skill fixtures are supported."
		if not hero.get("artifacts", []).is_empty(): return "Artifact fixtures are unsupported."
		if hero.has("monster_name"): return "Campaign monster fixtures are unsupported."
	return ""

func _restore(profile: ELProfile, entry: Dictionary) -> ELDuel:
	var duel := ELDuel.new()
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.state.duplicate(true)}):
		printerr("RESTORE %s: %s" % [entry.id, duel.error])
		return null
	duel.searching = true
	return duel

func _command(duel: ELDuel, raw: Dictionary) -> Dictionary:
	var command := raw.duplicate(true)
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
	return command

func _terminal(duel: ELDuel) -> int:
	# 1 objective reached, -1 objective failed, 0 live. The runtime's watch
	# remains authoritative; this separate check also supports copied DFS states.
	var objective: Dictionary = current_entry.get("objective", {})
	if int(duel.heroes[0].health) <= 0: return -1
	if int(duel.heroes[0].health) < int(objective.get("min_health", 0)): return -1
	for id: Variant in objective.get("protect", []):
		if not duel.creatures.has(int(id)) or int(duel.creatures[int(id)].owner) != 0: return -1
	if String(objective.get("type", "win")) == "control":
		for id: Variant in objective.get("targets", []):
			if not duel.creatures.has(int(id)): return -1
	var turn := (1 if int(initial.attacker) == 0 else 0) + int(duel.heroes[0].turns) - int(initial.heroes[0].turns)
	var completed := int(duel.heroes[1].turns) - int(initial.heroes[1].turns) + (1 if int(initial.attacker) == 1 else 0) - (1 if duel.attacker == 1 else 0)
	var primary := false
	match String(objective.get("type", "win")):
		"clear":
			primary = duel.army(1).is_empty()
		"control":
			primary = not objective.get("targets", []).is_empty() and completed >= int(objective.get("enemy_turns", 0))
			for id: Variant in objective.get("targets", []):
				if int(duel.creatures[int(id)].owner) != 0: primary = false
		"survive":
			primary = (duel.phase == ELDuel.Phase.FINISHED and duel.winner == 0) or completed >= int(objective.get("enemy_turns", 1))
		"win":
			primary = duel.phase == ELDuel.Phase.FINISHED and duel.winner == 0
	var satisfied := int(duel.heroes[0].health) >= int(objective.get("finish_health", 1)) and int(duel.heroes[0].mana) >= int(objective.get("finish_mana", 0)) and duel.army(0).size() >= int(objective.get("min_allies", 0))
	var boundary: bool = objective.get("type") == "survive" or (objective.get("type") == "control" and objective.has("enemy_turns"))
	if turn > int(current_entry.get("turns", 1)) and not (boundary and primary and satisfied): return -1
	if primary and satisfied: return 1
	if duel.phase == ELDuel.Phase.FINISHED: return -1
	return 0

func _replay(duel: ELDuel, commands: Array, attempt: ELPuzzles.Run = null) -> Dictionary:
	var trace: Array = []
	for index in commands.size():
		var raw: Dictionary = commands[index]
		if raw.has("side") and int(raw.side) != duel.active_side():
			return {"ok": false, "step": index + 1, "error": "Wrong acting side", "active": duel.active_side(), "trace": trace}
		if _terminal(duel) != 0:
			return {"ok": false, "step": index + 1, "error": "Line continues after objective ended", "terminal": _terminal(duel), "trace": trace}
		var command := _command(duel, raw)
		# This is an optional search-order hint, never a replacement for legal
		# move generation or for checking every opponent response. The default
		# uses exact snapshots; policy mode also permits a resource-context hint.
		if attempt != null and (_arg("reference-order") == "true" or _arg("reference-policy") == "true") and duel.active_side() == 0:
			var hint := _ordering_command(duel, command)
			reference_moves[_key(duel)] = hint
			if _arg("reference-policy") == "true": reference_policy_moves[_reference_context(duel)] = hint
		if not ELCombatSearch.apply(duel, command):
			return {"ok": false, "step": index + 1, "error": duel.error, "command": command, "trace": trace}
		if attempt != null:
			attempt.watch()
			var expected := "solved" if _terminal(duel) == 1 else ("failed" if _terminal(duel) == -1 else "")
			if attempt.outcome != expected:
				return {"ok": false, "step": index + 1, "error": "Runtime outcome mismatch", "runtime": attempt.outcome, "independent": expected, "trace": trace}
		trace.append({"command": command, "health": [duel.heroes[0].health, duel.heroes[1].health], "mana": [duel.heroes[0].mana, duel.heroes[1].mana], "units": duel.creatures.keys(), "terminal": _terminal(duel)})
	return {"ok": true, "terminal": _terminal(duel), "runtime": attempt.outcome if attempt != null else "not requested", "trace": trace}

func _legal_moves(duel: ELDuel) -> Array:
	var commands: Array = []
	var side := duel.active_side()
	var hero: Dictionary = duel.heroes[side]
	# Every card of the hand is a decision of its own, copies of one card
	# included: each spends its own book place (its uses left) and leaves the
	# rest of the hand in its own order.
	for i in hero.hand.size():
		var card: String = hero.hand[i]
		if duel.cost(card) > duel.available_mana(side) or not duel.phase_allows(card): continue
		var rule := ELCatalog.rule(duel.profile, card)
		var powers: Array = [0]
		if duel.variable_power(card): powers = range(duel.maximum_power(card), -1, -1)
		var targets: Array = [-1]
		if duel.target_kind(card) != "none": targets = duel.valid_targets(card)
		for target: int in targets:
			for grave: int in ELCombatSearch._spell_choices(duel, card, String(rule.get("effect", "")), target):
				for power: int in powers:
					commands.append({"kind": "cast", "index": i, "card": card, "target": target, "grave": grave, "power": power})
	for id: int in [side] + duel.creatures.keys():
		if id >= 2 and int(duel.creatures[id].owner) != side: continue
		for ability: Dictionary in duel.abilities(id):
			if not duel.can_use_ability(id, String(ability.key)): continue
			for args: Array in ELCombatSearch._arguments(duel, id, ability):
				commands.append({"kind": "ability", "id": id, "key": ability.key, "target": args[0], "choice": args[1], "amount": args[2]})
	if duel.phase == ELDuel.Phase.ATTACK:
		for c: Dictionary in duel.army(side):
			if duel.attacks.has(int(c.id)) or duel.can_declare_attack(int(c.id)):
				commands.append({"kind": "attack", "id": c.id})
	else:
		for c: Dictionary in duel.army(side):
			for target: int in duel.attacks:
				if duel.block_problem(int(c.id), target).is_empty(): commands.append({"kind": "block", "id": c.id, "target": target})
	commands.append({"kind": "end_phase"})
	if side == 0 and not reference_moves.is_empty():
		var preferred: Dictionary = reference_moves.get(_key(duel), {})
		if preferred.is_empty() and not reference_policy_moves.is_empty(): preferred = reference_policy_moves.get(_reference_context(duel), {})
		if not preferred.is_empty():
			for i in commands.size():
				if _same_action(commands[i], preferred):
					var command: Dictionary = commands.pop_at(i)
					commands.push_front(command)
					break
	return commands

func _same_action(first: Dictionary, second: Dictionary) -> bool:
	# Descriptive card names and a reference's optional side assertion do not
	# change the command. Every field used by apply must still agree.
	for key: String in ["kind", "index", "target", "grave", "power", "id", "key", "choice", "amount"]:
		if first.get(key) != second.get(key): return false
	return true

## Some authored demonstrations name an implicit hero target for readability.
## Canonicalize only the ordering hint where the actual rule has no target;
## the replay and reported command retain their supplied arguments unchanged.
func _ordering_command(duel: ELDuel, command: Dictionary) -> Dictionary:
	var hint := command.duplicate(true)
	if hint.get("kind") == "cast":
		var card := str(duel.heroes[duel.active_side()].hand[int(hint.index)])
		if duel.target_kind(card) == "none": hint.target = -1
	elif hint.get("kind") == "ability":
		for definition: Dictionary in duel.abilities(int(hint.id)):
			if definition.get("key") == hint.get("key") and definition.get("target", "none") == "none":
				hint.target = -1
				break
	return hint

## An optional ordering hint, NEVER a search/memo equivalence. The defender's
## choices can change hero health or enemy readiness without changing the
## player's preparation. Transfer a reference move only if it is still among
## the fully enumerated legal actions. Every result is searched normally.
func _reference_context(duel: ELDuel) -> String:
	var hero: Dictionary = duel.heroes[0].duplicate(true)
	hero.erase("health")
	var army: Array = []
	for creature: Dictionary in duel.army(0):
		var body := creature.duplicate(true)
		body.erase("hit")
		if duel.phase == ELDuel.Phase.DEFENCE: body.erase("damage")
		army.append(body)
	army.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first.id) < int(second.id))
	return JSON.stringify({"phase": duel.phase, "active_side": duel.active_side(),
		"own_hero": hero, "own_army": army, "enemy_turns": duel.heroes[1].turns,
		"attacks": [] if duel.phase == ELDuel.Phase.DEFENCE else duel.attacks, "blocks": duel.blocks}, "", false)

func _key(duel: ELDuel) -> String:
	var state := duel.snapshot()
	# Block insertion order decides damage assignment, so it is state too.
	return JSON.stringify(state, "", false)

func _search(duel: ELDuel, remaining: int) -> int:
	var terminal := _terminal(duel)
	if terminal != 0: return terminal
	if remaining <= 0: return 0
	nodes += 1
	if nodes > budget:
		exhausted = true
		return 0
	var position := _key(duel)
	var key := position + "/" + str(remaining)
	if memo.has(key): return int(memo[key])
	active_path[position] = true
	var own := duel.active_side() == 0
	var uncertain := false
	for command: Dictionary in _legal_moves(duel):
		var copy := duel.search_copy()
		if not ELCombatSearch.apply(copy, command): continue
		# UI order toggles may return to the identical position indefinitely.
		# Ignore only exact repeated positions, not distinct orders or RNG states.
		if active_path.has(_key(copy)): continue
		var result := _search(copy, remaining - 1)
		if (own and result == 1) or (not own and result == -1):
			memo[key] = result
			chosen[key] = command
			active_path.erase(position)
			return result
		if result == 0: uncertain = true
		if exhausted:
			active_path.erase(position)
			return 0
	var result := 0 if uncertain else (-1 if own else 1)
	memo[key] = result
	active_path.erase(position)
	return result

func _proof(duel: ELDuel) -> Dictionary:
	nodes = 0
	exhausted = false
	memo.clear()
	chosen.clear()
	active_path.clear()
	var result := _search(duel, maximum_depth)
	return {"result": "forced" if result == 1 else ("refuted" if result == -1 else "unknown"), "nodes": nodes, "budget": budget, "budget_exhausted": exhausted, "depth": maximum_depth,
		"move_order": "reference-first at exact snapshots, then matching own resource/army context; all legal replies searched" if _arg("reference-policy") == "true" else ("reference-first at exact matching player snapshots" if _arg("reference-order") == "true" else "legal enumeration")}

func _charge(duel: ELDuel) -> Dictionary:
	if duel.phase == ELDuel.Phase.ATTACK:
		for creature: Dictionary in duel.army(duel.active_side()):
			if not duel.attacks.has(int(creature.id)) and duel.can_declare_attack(int(creature.id)):
				return {"kind": "attack", "id": int(creature.id)}
	return {"kind": "end_phase"}

func _baseline(profile: ELProfile, entry: Dictionary, mode: String) -> Dictionary:
	var duel := _restore(profile, entry)
	var trace: Array = []
	ELCombatSearch._plans.clear()
	# Same real opponent/search as the game, with a reproducible node budget.
	# These are heuristic challenge checks, separate from the adversarial proof.
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_budget = 200000
	duel.smart_sides.assign([1])
	for step in 200:
		var terminal := _terminal(duel)
		if terminal != 0:
			return {"outcome": "solved" if terminal == 1 else "failed", "steps": step, "trace": trace}
		var command: Dictionary
		var side := duel.active_side()
		if side != 0:
			command = ELCombatSearch.think(duel, {})
		elif mode == "pass": command = {"kind": "end_phase"}
		elif mode == "charge": command = _charge(duel)
		else:
			command = ELCombatSearch.think(duel, {})
			if mode == "obvious" and duel.phase == ELDuel.Phase.ATTACK and not String(command.get("kind", "")) in ["cast", "ability"]:
				command = _charge(duel)
		if command.is_empty(): command = {"kind": "end_phase"}
		if not ELCombatSearch.apply(duel, command):
			return {"outcome": "error", "steps": step, "error": duel.error, "command": command}
		trace.append({"side": side, "command": command})
	return {"outcome": "unknown", "steps": 200, "trace": trace}

func _run() -> void:
	var path := _arg("file")
	if path.is_empty():
		printerr("Pass --file=/absolute/puzzle-pack.json")
		quit(2)
		return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if document is not Dictionary or document.get("puzzles") is not Array:
		printerr("Not a puzzle pack: " + path)
		quit(2)
		return
	var edition := String(document.get("game", "el2"))
	var profile := _profile(edition, document.puzzles)
	if profile == null:
		quit(2)
		return
	ELPuzzles.remember = false
	ELPuzzles._lists[edition] = document.puzzles
	if _arg("regression") == "true":
		var checks := RuntimeChecks.run(profile, document.puzzles[0])
		# The search's own move list names every card of the hand, two
		# copies of one card each with its own casts.
		var twin := RuntimeChecks._entry(profile, document.puzzles[0])
		for hero: Dictionary in twin.state.heroes:
			hero.hand = ["ZAPP", "ZAPP"]
			hero.hand_slots = [-1, -1]
		var twin_duel := _restore(profile, twin)
		var copies := {}
		if twin_duel != null:
			for command: Dictionary in _legal_moves(twin_duel):
				if String(command.get("kind", "")) == "cast": copies[int(command.index)] = int(copies.get(int(command.index), 0)) + 1
		var both: bool = copies.size() == 2 and copies.values()[0] == copies.values()[1]
		print(("OK " if both else "FAILED ") + "search lists both copies of a card in hand (%s)" % str(copies))
		if not both: checks.failures = int(checks.failures) + 1
		if not _arg("report").is_empty():
			var file := FileAccess.open(_arg("report"), FileAccess.WRITE)
			file.store_string(JSON.stringify(checks, "\t"))
		quit(1 if int(checks.failures) > 0 else 0)
		return
	var results: Array = []
	var selected := _arg("only")
	budget = int(_arg("budget", "30000"))
	maximum_depth = int(_arg("depth", "14"))
	for entry: Dictionary in document.puzzles:
		if not selected.is_empty() and String(entry.id) != selected: continue
		var failures_before := failures
		current_entry = entry
		reference_moves.clear()
		reference_policy_moves.clear()
		initial = entry.state
		var result := {"id": entry.id, "edition": edition}
		if not ELPuzzles.valid_entry(entry, edition):
			result.error = "Entry rejected by the game's puzzle schema"
			results.append(result)
			failures += 1
			continue
		var unsupported := _supported(entry)
		if not unsupported.is_empty():
			result.error = unsupported
			results.append(result)
			failures += 1
			continue
		var duel := _restore(profile, entry)
		if duel == null:
			result.error = "State rejected by ELDuel.restore"
			results.append(result)
			failures += 1
			continue
		if _arg("normalize") == "true":
			for creature: Dictionary in duel.creatures.values():
				creature.flags = ELCatalog.flags(profile.table("CombatCreatures")[creature.card])
				creature.flying = "Fly" in creature.flags
			duel._refresh_armies()
			entry.state = duel.snapshot()
			initial = entry.state
			result.normalized = true
		var unsettled := ""
		for creature: Dictionary in duel.creatures.values():
			if int(creature.toughness) <= 0 or int(creature.damage) >= int(creature.toughness):
				unsettled = "Starting creature %d is already lethally wounded" % int(creature.id)
		if not unsettled.is_empty():
			result.error = unsettled
			results.append(result)
			failures += 1
			continue
		# Evidence travels with its exact gameplay input, so a later content
		# edit cannot accidentally inherit a proof for a different position.
		result.definition = {"state": entry.state.duplicate(true), "turns": entry.turns,
			"objective": entry.get("objective", {"type": "win"}).duplicate(true),
			"solution": entry.get("solution", []).duplicate(true),
			"refutations": entry.get("refutations", []).duplicate(true)}
		var commands: Array = entry.get("solution", [])
		if not _arg("commands").is_empty(): commands = JSON.parse_string(FileAccess.get_file_as_string(_arg("commands")))
		if not commands.is_empty():
			var attempt := ELPuzzles.Run.new()
			if not attempt.begin(profile, document.puzzles.find(entry)):
				result.error = attempt.error
				results.append(result)
				failures += 1
				continue
			duel = attempt.duel
			var replay := _replay(duel, commands, attempt)
			result.solution = replay
			result.final_state = duel.snapshot()
			if not replay.ok or int(replay.get("terminal", 0)) != 1: failures += 1
		elif _arg("inspect") != "true":
			result.error = "No reference solution"
			failures += 1
		if _arg("search") == "true":
			result.proof = _proof(_restore(profile, entry))
			if result.proof.result == "refuted": failures += 1
			var refs: Array = []
			var requested_refs: Array = [] if _arg("root-only") == "true" else entry.get("refutations", [])
			result.search_scope = "root-only; authored prefixes were not searched in this run" if _arg("root-only") == "true" else "root and authored prefixes"
			for refutation: Dictionary in requested_refs:
				var altered := _restore(profile, entry)
				var prefix := _replay(altered, refutation.get("commands", []))
				var tested := {"label": refutation.get("label", ""), "prefix": prefix}
				if prefix.ok:
					tested.proof = _proof(altered)
					if tested.proof.result == "forced": failures += 1
				else: failures += 1
				refs.append(tested)
			result.refutations = refs
		if _arg("native") == "true":
			# This engine proves hero victory only, not the added clear/protect/
			# control/health objectives. Keep it separate from objective checks.
			var start := _restore(profile, entry)
			var context := ELCombatSearch.plain_context(start, 0)
			result.native_win_proof = ELCombatBrain.prove(context, start, int(entry.turns), int(_arg("native_budget", "1000000")))
		if _arg("baselines") == "true":
			result.baselines = {}
			for mode in ["pass", "charge", "plain", "obvious"]:
				result.baselines[mode] = _baseline(profile, entry, mode)
		result.ok = failures == failures_before and not result.has("error")
		results.append(result)
		print("%s %s%s" % ["OK" if result.ok else "FAILED", entry.id, " " + JSON.stringify(result.get("proof", {})) if result.has("proof") else ""])
	if _arg("normalize") == "true":
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(document, "\t"))
	var report := {"fixture": "Player's installed game tables; actual ELDuel GDScript rules" if not _arg("installed").is_empty() else "Checked-in wiki card data; actual ELDuel GDScript rules", "count": results.size(), "failures": failures, "results": results}
	if not _arg("report").is_empty():
		var file := FileAccess.open(_arg("report"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	if results.is_empty(): failures += 1
	print("TOTAL puzzles=%d failures=%d" % [results.size(), failures])
	quit(1 if failures > 0 else 0)
