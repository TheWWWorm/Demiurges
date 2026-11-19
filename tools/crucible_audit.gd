extends "puzzle_lab.gd"
## Supplemental authoring audit; exact full-state search, never a difficulty certificate.
## --file=/abs/pack.json --report=/abs/report.json [--only=id]
## --native --native-budget=N: native proof and all shorter own-turn horizons.
## --parity: compare each reference action in native/GDScript rules.
## --shorter: objective-aware GDScript proof at each shorter own-turn horizon.
## --openings: objective-aware GDScript proof after each generated opening.
## --native-openings: native proof after each legal GDScript opening.
## --native-refutations: native proof after every authored wrong-plan prefix.
## --policies: idle, attack-all, plain and obvious-player attempts against game AI.
## --engine-policy: also try the game's stronger native AI as the player.
## Unknowns remain unknown. Opening ordering commutations do not measure human difficulty.
## Compare helpers below follow tools/duel_rules_check.gd at 5d39ca49b07b0fd65adc7eaca4ce89d70c704c6c.

var profile: ELProfile
var blamed := {}
var dealt_again := false

func _evidence() -> Dictionary:
	var hashes := {}
	for path: String in ["state.gd", "catalog.gd", "match_save.gd", "specs.gd", "spell_charges.gd", "hero_effects.gd", "combat_search.gd", "combat_brain.gd", "puzzles.gd", "runes.gd", "hero_skills.gd", "hero_progression.gd", "safe_file.gd", "profile.gd", "fixture.json", "puzzle_lab.gd", "crucible_audit.gd", "native_bridge.c", "native_bridge", "native_bridge.sha256"]:
		if FileAccess.file_exists("res://" + path): hashes[path] = FileAccess.get_sha256("res://" + path)
	return {"runtime": Engine.get_version_info(), "lab_file_sha256": hashes,
		"native_build_fingerprint": FileAccess.get_file_as_string("res://native_bridge.sha256").strip_edges() if FileAccess.file_exists("res://native_bridge.sha256") else "unavailable",
		"fixture": "Checked-in wiki card tables; actual GDScript battle logic with narrow offline fixtures"}

func _write_report(results: Array) -> void:
	if _arg("report").is_empty(): return
	var out := FileAccess.open(_arg("report"), FileAccess.WRITE)
	if out == null:
		printerr("Cannot write audit report: " + _arg("report"))
		failures += 1
		return
	out.store_string(JSON.stringify({"count": results.size(), "failures": failures, "results": results,
		"evidence": _evidence(),
		"scope": "Reference replay, optional native parity and bounded search. Unknown is neither a win nor a loss; this is not a human difficulty rating."}, "\t"))

func _fresh(entry: Dictionary) -> ELPuzzles.Run:
	ELPuzzles._lists[profile.id] = [entry]
	var attempt := ELPuzzles.Run.new()
	if not attempt.begin(profile, 0):
		printerr(attempt.error)
		return null
	attempt.duel.searching = true
	return attempt

func _policy_attempt(entry: Dictionary, mode: String) -> Dictionary:
	var attempt := _fresh(entry)
	if attempt == null: return {"outcome": "error", "error": "Restore failed"}
	var duel := attempt.duel
	duel.smart_sides.assign([0, 1] if mode == "native" else [1])
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_budget = int(_arg("policy-budget", "200000"))
	var trace: Array = []
	for step in 200:
		var terminal := _terminal(duel)
		if terminal != 0:
			return {"outcome": "solved" if terminal == 1 else "failed", "steps": step, "trace": trace,
				"opponent": "Goal-aware game AI", "engine_budget": ELCombatSearch.smart_engine_budget}
		var side := duel.active_side()
		var command: Dictionary
		if side != 0 or mode == "native": command = ELCombatSearch.think(duel, {})
		elif mode == "pass": command = {"kind": "end_phase"}
		elif mode == "charge": command = _charge(duel)
		else:
			command = ELCombatSearch.think(duel, {})
			if mode == "obvious" and duel.phase == ELDuel.Phase.ATTACK and not String(command.get("kind", "")) in ["cast", "ability"]:
				command = _charge(duel)
		if command.is_empty(): command = {"kind": "end_phase"}
		if not ELCombatSearch.apply(duel, command):
			return {"outcome": "error", "steps": step, "command": command, "error": duel.error, "trace": trace}
		attempt.watch()
		trace.append({"side": side, "command": command, "health": [duel.heroes[0].health, duel.heroes[1].health], "turn": attempt.turn})
	return {"outcome": "unknown", "steps": 200, "trace": trace}

func _native_proof(duel: ELDuel, horizon: int) -> Dictionary:
	var terminal := _terminal(duel)
	if terminal != 0: return {"status": "terminal_win" if terminal == 1 else "terminal_loss", "turns": 0, "positions": 0}
	var proof := ELCombatBrain.prove(_context(0), duel, horizon, int(_arg("native-budget", "3000000")))
	if proof.is_empty(): return {"status": "unsupported", "note": "No answer from native solver: unavailable or unsupported position; no win/loss claim."}
	if proof.get("status") == "proven" and not proof.get("line", []).is_empty():
		var first: Array = proof.line[0]
		proof.first_native_instruction = first.duplicate()
		var decoded := ELCombatBrain._command_of(duel, duel.creatures.keys(), int(first[0]), int(first[1]), int(first[2]), int(first[3]))
		# The native proof may begin with an aggregate attacker/blocker choice.
		# _command_of uses end_phase as its fallback for these internal records;
		# that is not evidence that ending the phase is the winning first move.
		if int(first[0]) == 0 or String(decoded.get("kind", "")) != "end_phase": proof.first_command = decoded
		else: proof.first_command_note = "Native aggregate instruction; retain the raw instruction rather than mislabel its decoder fallback as end_phase."
	return proof

func _native_reference(entry: Dictionary) -> Dictionary:
	var attempt := _fresh(entry)
	if attempt == null: return {"ok": false, "error": "Restore failed"}
	var duel := attempt.duel
	var rows: Array = []
	var okay := true
	var before_blind := ELCombatBrain.fight_blind
	ELCombatBrain.fight_blind = false
	for index in entry.solution.size():
		var command := _command(duel, entry.solution[index])
		var side := duel.active_side()
		var matches: Array = []
		for move: Array in _native_moves(duel, side, true):
			if command.kind == "end_phase" and int(move[0]) != 0: continue
			var decoded := ELCombatBrain._command_of(duel, duel.creatures.keys(), int(move[0]), int(move[1]), int(move[2]), int(move[3]))
			if _same_command(duel, decoded, command): matches.append(move)
		var row := {"step": index + 1, "command": command, "native_listed": not matches.is_empty()}
		var before := _board(duel)
		var start := duel.search_copy()
		if not ELCombatSearch.apply(duel, command):
			row.error = duel.error
			rows.append(row)
			okay = false
			break
		attempt.watch()
		if matches.is_empty():
			row.error = "No matching move in native proof move list"
			okay = false
		else:
			var model := ELCombatBrain.fight(_context(side), start, 4, [matches[0]])
			if model.is_empty():
				row.error = "No native replay reply"
				okay = false
			else:
				var trouble := _compare(duel, model, before, true)
				if int(model.played) != 1: trouble.append("Native model rejected the command")
				if int(model.get("limit", 0)) != 0: trouble.append("Native model storage limit")
				if int(model.get("blind", 0)) != 0: trouble.append("Native model followed hidden/random card effects")
				if duel.phase != ELDuel.Phase.FINISHED and int(model.phase) != (0 if duel.phase == ELDuel.Phase.ATTACK else 1):
					trouble.append("Native phase differs")
				row.differences = trouble
				row.same = trouble.is_empty()
				if not row.same: okay = false
		rows.append(row)
	ELCombatBrain.fight_blind = before_blind
	return {"ok": okay, "actions": rows.size(), "rows": rows,
		"scope": "Each reference action starts from the actual GDScript state; listed native command and compared public resulting state. Not every branch or full model equivalence."}

func _run() -> void:
	var path := _arg("file")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if document is not Dictionary or document.get("puzzles") is not Array or document.puzzles.is_empty():
		printerr("Expected a nonempty puzzle pack")
		quit(2)
		return
	profile = _profile(String(document.game), document.puzzles)
	if profile == null:
		quit(2)
		return
	ELPuzzles.remember = false
	budget = int(_arg("budget", "90000"))
	maximum_depth = int(_arg("depth", "40"))
	var selected := _arg("only")
	var results: Array = []
	for entry: Dictionary in document.puzzles:
		if not selected.is_empty() and String(entry.id) != selected: continue
		current_entry = entry
		initial = entry.state
		reference_moves.clear()
		reference_policy_moves.clear()
		var row := {"id": entry.id, "definition": {"state": entry.state.duplicate(true), "turns": entry.turns,
			"objective": entry.get("objective", {"type": "win"}).duplicate(true),
			"solution": entry.solution.duplicate(true), "refutations": entry.get("refutations", []).duplicate(true)}}
		var unsupported := _supported(entry)
		if not ELPuzzles.valid_entry(entry, profile.id) or not unsupported.is_empty():
			row.error = unsupported if not unsupported.is_empty() else "Invalid puzzle schema"
			results.append(row)
			failures += 1
			_write_report(results)
			continue
		var attempt := _fresh(entry)
		if attempt == null:
			row.error = "Cannot restore puzzle"
			results.append(row)
			failures += 1
			_write_report(results)
			continue
		row.initial_terminal = _terminal(attempt.duel)
		row.reference = _replay(attempt.duel, entry.solution, attempt)
		if row.initial_terminal != 0 or not row.reference.ok or int(row.reference.get("terminal", 0)) != 1:
			failures += 1
		if _arg("parity") == "true":
			row.native_parity = _native_reference(entry)
			if not row.native_parity.ok: failures += 1
		if _arg("native") == "true":
			row.native_horizons = []
			for horizon in range(1, int(entry.turns) + 1):
				var short := entry.duplicate(true)
				short.turns = horizon
				attempt = _fresh(short)
				current_entry = short
				row.native_horizons.append({"turns": horizon, "proof": _native_proof(attempt.duel, horizon)})
			current_entry = entry
		if _arg("shorter") == "true":
			row.shorter_horizons = []
			for horizon in range(1, int(entry.turns)):
				var short := entry.duplicate(true)
				short.turns = horizon
				current_entry = short
				attempt = _fresh(short)
				var proof := _proof(attempt.duel)
				row.shorter_horizons.append({"turns": horizon, "proof": proof})
				print("SHORTER %s %d %s" % [entry.id, horizon, proof.result])
			current_entry = entry
		if _arg("openings") == "true":
			row.openings = []
			attempt = _fresh(entry)
			var seen := {}
			for command: Dictionary in _legal_moves(attempt.duel):
				var after := attempt.duel.search_copy()
				if not ELCombatSearch.apply(after, command): continue
				var fingerprint := _key(after)
				# Only skip byte-identical resulting states, retain the command in the report.
				var proof: Dictionary = seen.get(fingerprint, {})
				var reused := not proof.is_empty()
				if proof.is_empty():
					proof = _proof(after)
					seen[fingerprint] = proof
				row.openings.append({"command": command, "proof": proof, "identical_state_reused": reused})
				print("OPENING %s %s %s" % [entry.id, JSON.stringify(command), proof.result])
		if _arg("native-openings") == "true":
			row.native_openings = []
			attempt = _fresh(entry)
			var seen := {}
			for command: Dictionary in _legal_moves(attempt.duel):
				var after := attempt.duel.search_copy()
				if not ELCombatSearch.apply(after, command): continue
				var fingerprint := _key(after)
				var proof: Dictionary = seen.get(fingerprint, {})
				var reused := not proof.is_empty()
				if proof.is_empty():
					proof = _native_proof(after, int(entry.turns))
					seen[fingerprint] = proof
				row.native_openings.append({"command": command, "proof": proof, "identical_state_reused": reused})
				print("NATIVE OPENING %s %s %s" % [entry.id, JSON.stringify(command), proof.get("status", "unknown")])
		if _arg("native-refutations") == "true":
			row.native_refutations = []
			for refutation: Dictionary in entry.get("refutations", []):
				attempt = _fresh(entry)
				var replay := _replay(attempt.duel, refutation.get("commands", []), attempt)
				var branch := {"label": refutation.get("label", ""), "prefix": replay}
				if replay.ok:
					branch.proof = _native_proof(attempt.duel, int(entry.turns))
					branch.native_win_found = branch.proof.get("status") in ["proven", "terminal_win"]
				else: failures += 1
				row.native_refutations.append(branch)
				print("NATIVE PREFIX %s %s %s" % [entry.id, branch.label, branch.get("proof", {}).get("status", "illegal")])
		if _arg("policies") == "true" or _arg("engine-policy") == "true":
			row.policies = {}
			var modes: Array = ["pass", "charge", "plain", "obvious"] if _arg("policies") == "true" else []
			if _arg("engine-policy") == "true": modes.append("native")
			for mode: String in modes:
				row.policies[mode] = _policy_attempt(entry, mode)
				if row.policies[mode].outcome == "error": failures += 1
				print("POLICY %s %s %s" % [entry.id, mode, row.policies[mode].outcome])
		results.append(row)
		print("AUDITED " + String(entry.id))
		_write_report(results)
	print("AUDIT puzzles=%d failures=%d" % [results.size(), failures])
	quit(1 if failures > 0 or results.is_empty() else 0)

func _compare(duel: ELDuel, model: Dictionary, before: Dictionary, whole_turn: bool) -> Array[String]:
	var said: Array[String] = []
	for id: int in before.units:
		var card: String = before.units[id].card
		var theirs: int = int(model.units.get(id, -2))
		var ours := -1 if not duel.creatures.has(id) else int(duel.creatures[id].damage)
		if theirs != ours:
			said.append("#%d %s %s: the game says %s, the model %s" % [id, card, before.units[id].stats, _damage(ours), _damage(theirs)])
			blamed[card] = int(blamed.get(card, 0)) + 1
		elif ours >= 0 and duel.phase != ELDuel.Phase.FINISHED and bool(model.resting.get(id, false)) != bool(duel.creatures[id].resting):
			said.append("#%d %s %s: the game leaves it %s, the model %s" % [id, card, before.units[id].stats, "resting" if duel.creatures[id].resting else "ready", "resting" if model.resting.get(id, false) else "ready"])
			blamed[card] = int(blamed.get(card, 0)) + 1
	if whole_turn:
		for side in 2:
			if int(duel.heroes[side].channels) != int(model.channels[side]):
				said.append("hero %d: the game leaves %d channels, the model %d" % [side, int(duel.heroes[side].channels), int(model.channels[side])])
		if duel.attacker != int(model.attacker):
			said.append("the game gives the turn to side %d, the model to %d" % [duel.attacker, int(model.attacker)])
		# What the two count beside: cards held, cards buried, creatures in play.
		var counts: Dictionary = model.get("counts", {})
		if not counts.is_empty() and duel.phase != ELDuel.Phase.FINISHED:
			for side in 2:
				if int(duel.heroes[side].hand.size()) != int(counts.hands[side]):
					said.append("hero %d: the game leaves %d cards in hand, the model %d" % [side, duel.heroes[side].hand.size(), int(counts.hands[side])])
				if int(duel.heroes[side].grave.size()) != int(counts.graves[side]):
					said.append("hero %d: the game leaves %d cards buried, the model %d" % [side, duel.heroes[side].grave.size(), int(counts.graves[side])])
				if duel.army(side).size() != int(counts.armies[side]):
					said.append("hero %d: the game leaves %d creatures, the model %d" % [side, duel.army(side).size(), int(counts.armies[side])])
	for side in 2:
		if int(duel.heroes[side].health) != int(model.health[side]):
			said.append("hero %d: the game leaves %d health, the model %d" % [side, int(duel.heroes[side].health), int(model.health[side])])
		if int(duel.heroes[side].mana) != int(model.ether[side]):
			said.append("hero %d: the game leaves %d ether, the model %d" % [side, int(duel.heroes[side].mana), int(model.ether[side])])
	if model.has("stats") and duel.phase != ELDuel.Phase.FINISHED: said.append_array(_compare_rest(duel, model, before, whole_turn))
	return said

func _compare_rest(duel: ELDuel, model: Dictionary, before: Dictionary, whole_turn: bool) -> Array[String]:
	var said: Array[String] = []
	var stats: Dictionary = model.stats
	for id: int in before.units:
		if not duel.creatures.has(id) or int(model.units.get(id, -2)) < 0 or not stats.has(id): continue
		var c: Dictionary = duel.creatures[id]
		var told: Dictionary = stats[id]
		var card: String = before.units[id].card
		if int(c.power) != int(told.power) or int(c.toughness) != int(told.toughness):
			said.append("#%d %s: the game makes it %d/%d, the model %d/%d" % [id, card, int(c.power), int(c.toughness), int(told.power), int(told.toughness)])
			blamed[card] = int(blamed.get(card, 0)) + 1
		var done: Dictionary = c.get("ability_used", {})
		var spent: bool = done.get("rouse", false) or done.get("illusion", false)
		if spent != bool(told.spent):
			said.append("#%d %s: the game has its ability %s, the model %s" % [id, card, "spent" if spent else "ready", "spent" if told.spent else "ready"])
			blamed[card] = int(blamed.get(card, 0)) + 1
		# Marks fixed for good (a snake's bite) the model folds into the
		# creature's points, which are held above; the rest it keeps as laid.
		var laid := 0
		for e: Dictionary in c.enchantments:
			if not e.get("fixed", false): laid += 1
		var told_laid := int(told.worn)
		if laid != told_laid and not (laid < told_laid and (c.enchantments as Array).size() == told_laid):
			said.append("#%d %s: the game has it wear %d enchantments, the model %d" % [id, card, laid, told_laid])
			blamed[card] = int(blamed.get(card, 0)) + 1
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		# Cards by name, where the model names every card it counts.
		var counts: Dictionary = model.get("counts", {})
		var named: Array = model.named[side]
		if whole_turn and not dealt_again and not counts.is_empty() and named.size() == int(counts.hands[side]) and hero.hand.size() <= ELCombatBrain.HAND:
			var ours: Array = []
			for card: String in hero.hand: ours.append(ELCombatBrain._code(profile, card))
			ours.sort()
			var theirs := named.duplicate()
			theirs.sort()
			if ours != theirs: said.append("hero %d: the game's hand is %s, the model's %s" % [side, ",".join(hero.hand), _card_names(theirs)])
		var worn: Array = model.hero_worn[side]
		var used: Array = model.hero_used[side]
		for k in ELCombatBrain.CHARMS.size():
			var charm: String = ELCombatBrain.CHARMS[k]
			var count := 0
			var spent := 0
			for e: Dictionary in hero.enchantments:
				# Twins are told as the one they work like.
				if String(ELCombatBrain.CHARM_TWINS.get(String(e.card), String(e.card))) != charm: continue
				count += 1
				if e.get("used", false): spent += 1
			if k < worn.size() and count != int(worn[k]):
				said.append("hero %d: the game has it wear %d %s, the model %d" % [side, count, charm, int(worn[k])])
			if k < used.size() and k < ELCombatBrain.HERO_KEYS.size() and spent != int(used[k]):
				said.append("hero %d: the game has %d %s used, the model %d" % [side, spent, charm, int(used[k])])
	return said

func _card_names(codes: Array) -> String:
	var names: Array = []
	for code: int in codes:
		var name := "?"
		for card: String in profile.table("CombatSpells"):
			if ELCombatBrain._code(profile, card) == code:
				name = card
				break
		names.append(name)
	return ",".join(names)

func _context(side: int) -> ELCombatSearch.Context:
	var ctx := ELCombatSearch.Context.new()
	ctx.ai = side
	ctx.edition = profile.id
	ctx.second = profile.id == "el2"
	ctx.w = ELCombatSearch.steady_weights(ctx.second)
	ctx.remember = true
	return ctx

func _damage(amount: int) -> String:
	return "it died" if amount < 0 else "%d damage" % amount

func _board(duel: ELDuel) -> Dictionary:
	var units := {}
	var text := "side %d attacks with %s, blocks %s" % [duel.attacker, str(duel.attacks), str(duel.blocks)]
	for side in 2:
		text += "\n      hero %d: %d health, %d ether" % [side, int(duel.heroes[side].health), int(duel.heroes[side].mana)]
		for c: Dictionary in duel.army(side):
			var flags: Array = ELCatalog.flags(profile.table("CombatCreatures").get(c.card, {}))
			var stats := "%d/%d%s%s" % [int(c.power), int(c.toughness), "" if int(c.get("damage", 0)) == 0 else " dmg%d" % int(c.damage), "" if flags.is_empty() else " " + " ".join(flags)]
			units[int(c.id)] = {"card": String(c.card), "stats": stats}
			text += "\n         #%d %s %s%s" % [int(c.id), c.card, stats, "r" if c.resting else ""]
	return {"units": units, "text": text}

func _native_moves(duel: ELDuel, side: int, proof: bool) -> Array:
	var raw: PackedInt32Array = ELCombatBrain.ask(_context(side), duel, 1, 1, true, 11 if proof else 10).get("raw", PackedInt32Array())
	var out: Array = []
	# A library that does not list answers something else, of another length.
	if raw.size() < 1 or raw.size() != 1 + 4 * int(raw[0]): return out
	for i in int(raw[0]):
		var at := 1 + i * 4
		if at + 3 >= raw.size(): break
		out.append([int(raw[at]), int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3])])
	return out

func _same_command(duel: ELDuel, ours: Dictionary, wanted: Dictionary) -> bool:
	var kind := String(wanted.get("kind", ""))
	if String(ours.get("kind", "")) != kind: return false
	var side := duel.active_side()
	match kind:
		"end_phase": return true
		"attack": return int(ours.id) == int(wanted.id)
		"block": return int(ours.id) == int(wanted.id) and int(ours.target) == int(wanted.target)
		"cast":
			var hand: Array = duel.heroes[side].hand
			if int(ours.index) < 0 or int(ours.index) >= hand.size() or int(wanted.index) < 0: return false
			var card := String(hand[int(wanted.index)])
			if String(hand[int(ours.index)]) != card: return false
			var aimed := duel.target_kind(card) != "none"
			if aimed and int(ours.target) != int(wanted.target): return false
			if int(ours.get("grave", -1)) != int(wanted.get("grave", -1)) and (int(ours.get("grave", -1)) >= 0 or int(wanted.get("grave", -1)) >= 0): return false
			if duel.variable_power(card) and int(ours.get("power", 0)) != int(wanted.get("power", 0)): return false
			return true
		"ability":
			var id := int(wanted.id)
			if int(ours.id) != id: return false
			var key := String(wanted.key)
			var theirs := String(ours.key)
			if id < 2:
				key = key.get_slice(":", 0)
				theirs = theirs.get_slice(":", 0)
			if key != theirs: return false
			var aimed := true
			for definition: Dictionary in duel.abilities(id):
				if String(definition.get("key", "")) == String(wanted.key) and String(definition.get("target", "none")) == "none": aimed = false
			if aimed and int(ours.target) != int(wanted.target): return false
			if int(ours.choice) != int(wanted.choice) and (int(ours.choice) >= 0 or int(wanted.choice) >= 0): return false
			if int(ours.amount) != int(wanted.amount) and (int(ours.amount) >= 0 or int(wanted.amount) >= 0): return false
			return true
	return false
