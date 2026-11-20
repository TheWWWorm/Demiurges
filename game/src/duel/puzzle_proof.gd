class_name ELPuzzleProof
extends RefCounted
## Incremental, bounded proof of a fixed-supply victory puzzle using ELDuel.
## Player choices are OR nodes; every legal opponent reply is an AND child.
## A depth/node cutoff is unknown, never a loss or evidence of difficulty.
## Exact repeated positions within a line are omitted: attack/block UI toggles
## can otherwise postpone the end of a phase indefinitely. Full snapshots keep
## RNG, attack order and blocker insertion order. No AI priority prunes moves.
## Campaign scripts and custom spell artifacts are outside this verifier's
## scope; their extra command choices must never be silently certified.

const DEFAULT_BUDGET := 12000
const DEFAULT_DEPTH := 24

## Start without changing puzzle lists, progress, or the combat AI's caches.
## limits: budget, depth, max_tactics (-1: unlimited). max_tactics restricts
## player-zero casts and abilities over the entire line, including later turns.
## A refuted restricted search says only that no strategy under that restriction
## survived the completed search; an unfinished search remains unknown.
## Development audits may additionally use without_player, a dictionary with
## casts (card codes), effects (cast effect names), and abilities (base keys).
## Each list excludes matching player actions only. Enemy choices are unchanged.
static func start(profile: ELProfile, entry: Dictionary, limits: Dictionary = {}) -> Job:
	var job := Job.new()
	job._begin(profile, entry, limits)
	return job

## Continue from an actual battle, retaining runtime fields a save omits (for
## example next_card). The independent copy has no listeners or replay gate.
## `allowed_own_turns` includes the current own turn when attacker == 0. Zero
## permits a victory during the current enemy turn, but never another own turn.
## This is a fixed-supply, ordinary-win analysis, just like start().
static func from_position(duel: ELDuel, allowed_own_turns: int, limits: Dictionary = {}) -> Job:
	var job := Job.new()
	job._started = Time.get_ticks_usec()
	if duel == null or duel.profile == null or allowed_own_turns < 0 or allowed_own_turns > 12:
		job._finish("invalid", null, "Invalid current position or remaining turn allowance.")
		return job
	if duel.expected_specs or duel.fair_specs or duel.scripts_in_combat() or duel.scripted_turns:
		job._finish("invalid", null, "An exact, unscripted battle position is required.")
		return job
	var entry := {"id": "current-position", "turns": maxi(1, allowed_own_turns),
		"objective": {"type": "win"}, "state": duel.snapshot()}
	job._begin(duel.profile, entry, limits, duel, allowed_own_turns)
	return job

## Resolve authoring conveniences without changing the supplied dictionary.
## A supplied index is kept, so two copies with different charges stay distinct.
static func command(duel: ELDuel, raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	match String(result.get("kind", "")):
		"cast":
			if not result.has("index"):
				result.index = duel.heroes[duel.active_side()].hand.find(String(result.get("card", "")))
			result.target = int(result.get("target", -1))
			result.grave = int(result.get("grave", -1))
			result.power = int(result.get("power", 0))
		"ability":
			result.id = int(result.get("id", -1))
			result.key = String(result.get("key", ""))
			result.target = int(result.get("target", -1))
			result.choice = int(result.get("choice", -1))
			result.amount = int(result.get("amount", -1))
	return result

## Replay a command, including an optional explicit acting-side assertion.
static func apply(duel: ELDuel, raw: Dictionary) -> bool:
	if raw.has("side") and int(raw.side) != duel.active_side(): return false
	return ELCombatSearch.apply(duel, command(duel, raw))

## All legal commands, checked on independent copies. Unlike the combat AI's
## legal(), this does not use its priorities or merge duplicate hand cards.
static func legal_moves(duel: ELDuel) -> Array:
	var result: Array = []
	for action: Dictionary in _candidates(duel):
		if ELCombatSearch.apply(duel.search_copy(), action): result.append(action)
	return result

## Candidate enumeration is separate so incremental proof need only apply one
## edge at a time. ELDuel remains the authority on every candidate's legality.
static func _candidates(duel: ELDuel) -> Array:
	var result: Array = []
	if duel.phase == ELDuel.Phase.FINISHED: return result
	var side := duel.active_side()
	var hero: Dictionary = duel.heroes[side]
	for index in hero.hand.size():
		var card := String(hero.hand[index])
		if duel.cost(card) > duel.available_mana(side) or not duel.phase_allows(card): continue
		var rule := ELCatalog.rule(duel.profile, card)
		var powers: Array = [0]
		if duel.variable_power(card): powers = range(duel.maximum_power(card), -1, -1)
		var targets: Array = [-1]
		if duel.target_kind(card) != "none": targets = duel.valid_targets(card)
		for target: int in targets:
			for choice: int in ELCombatSearch._spell_choices(duel, card, String(rule.get("effect", "")), target):
				for power: int in powers:
					result.append({"kind": "cast", "side": side, "index": index, "card": card,
						"target": target, "grave": choice, "power": power})
	for id: int in [side] + duel.creatures.keys():
		if id >= 2 and int(duel.creatures[id].owner) != side: continue
		for ability: Dictionary in duel.abilities(id):
			# UI/AI availability may omit apparently unproductive uses (EL2's
			# Plague on an empty grave, for example). Spending ether or resting
			# can matter to other effects, so only actual execution rejects them.
			var arguments := ELCombatSearch._arguments(duel, id, ability)
			# The AI omits identical paired targets. Combine explicitly permits
			# sacrificing a creature to itself, with no surviving recipient.
			if String(ability.get("effect", ability.key)) == "combine":
				for target: int in duel.creatures: arguments.append([target, target, -1])
			for args: Array in arguments:
				var action := {"kind": "ability", "side": side, "id": id, "key": ability.key,
					"target": args[0], "choice": args[1], "amount": args[2]}
				if id >= 2: action.card = String(duel.creatures[id].card)
				elif ability.has("enchantment_card"): action.card = String(ability.enchantment_card)
				elif ability.has("card"): action.card = String(ability.card)
				result.append(action)
	if duel.phase == ELDuel.Phase.ATTACK:
		for creature: Dictionary in duel.army(side):
			if duel.attacks.has(int(creature.id)) or duel.can_declare_attack(int(creature.id)):
				result.append({"kind": "attack", "side": side, "id": int(creature.id), "card": creature.card})
	else:
		for creature: Dictionary in duel.army(side):
			for target: int in duel.attacks:
				if duel.block_problem(int(creature.id), target).is_empty():
					result.append({"kind": "block", "side": side, "id": int(creature.id), "target": target, "card": creature.card})
	result.append({"kind": "end_phase", "side": side})
	return result

static func _position(duel: ELDuel) -> String:
	var state := duel.snapshot()
	# next_card is presentation identity, but retaining it also keeps a copy's
	# full future hand state distinct. Never sort dictionary keys: block order
	# participates in combat damage assignment.
	state["_proof_next_card"] = duel.next_card
	return JSON.stringify(state, "", false)

## Attack/block declarations can be reordered without changing material. A
## canonical segment enumerates every resulting subset and insertion order,
## while avoiding repeatedly assigning then recalling the same creature.
## TeamAttack can need a temporary partner to reach an order, so dependency
## flags deliberately disable this reduction. Scripts were rejected at entry.
static func _assignment_segment(duel: ELDuel, enabled: bool) -> Dictionary:
	var independent := enabled
	for creature: Dictionary in duel.army(duel.active_side()):
		if duel.has_flag(int(creature.id), "TeamAttack") or duel.has_flag(int(creature.id), "Berserk"):
			independent = false
	var initial := {}
	var assigned: Array = duel.attacks if duel.phase == ELDuel.Phase.ATTACK else duel.blocks.keys()
	for id: int in assigned: initial[id] = true
	return {"enabled": independent, "initial": initial, "touched": {}}

static func _material(duel: ELDuel) -> String:
	var state := duel.snapshot()
	state.erase("attacks")
	state.erase("blocks")
	state["_proof_next_card"] = duel.next_card
	return JSON.stringify(state, "", false)

static func _tactic(action: Dictionary) -> bool:
	return int(action.get("side", -1)) == 0 and String(action.get("kind", "")) in ["cast", "ability"]

## An operation-removal audit tests whether a mechanism is necessary to force
## victory. It does not remove cards/entities, change costs, or rewrite rules.
static func _excluded_player_action(duel: ELDuel, action: Dictionary, excluded: Dictionary) -> bool:
	if not _tactic(action): return false
	if action.kind == "cast":
		var card := String(action.get("card", ""))
		return card in excluded.get("casts", []) or String(ELCatalog.rule(duel.profile, card).get("effect", "summon")) in excluded.get("effects", [])
	return String(action.get("key", "")).get_slice(":", 0) in excluded.get("abilities", [])

## Constant-size aggregates of the selected winning strategy, including every
## retained opponent continuation. These are descriptive bounds of this proof,
## not a minimum over all possible winning strategies. Own turns use Run's
## counting convention: an initial enemy turn consumes zero own turns.
## Enemy replies count retained legal commands (including pass/declarations).
## Enemy decisions count nodes with at least two replies along a branch; their
## maximum and each other maximum may come from different branches. Tactical
## actions/replies count casts and abilities only, for their respective side.
static func _strategy_leaf(turn: int) -> Dictionary:
	return {"min_actions": 0, "max_actions": 0, "min_tactics": 0, "max_tactics": 0,
		"min_player_turns": turn, "max_player_turns": turn,
		"max_enemy_replies": 0, "max_enemy_tactical_replies": 0,
		"max_enemy_decisions": 0, "max_enemy_tactics": 0}

static func _strategy_step(strategy: Dictionary, action: Dictionary) -> Dictionary:
	var result := strategy.duplicate()
	result.min_actions += 1
	result.max_actions += 1
	if _tactic(action):
		result.min_tactics += 1
		result.max_tactics += 1
	elif int(action.get("side", -1)) == 1 and String(action.get("kind", "")) in ["cast", "ability"]:
		result.max_enemy_tactics += 1
	return result

static func _strategy_merge(combined: Dictionary, branch: Dictionary) -> Dictionary:
	if combined.is_empty(): return branch
	for key: String in combined:
		combined[key] = mini(int(combined[key]), int(branch[key])) if key.begins_with("min_") else maxi(int(combined[key]), int(branch[key]))
	return combined

class Line:
	extends RefCounted
	var action: Dictionary = {}
	var next: Line
	var length := 1
	func _init(move: Dictionary = {}, tail: Line = null) -> void:
		action = move
		next = tail
		length = 1 + (tail.length if tail != null else 0)

class Frame:
	extends RefCounted
	var duel: ELDuel
	var remaining := 0
	var tactics := 0
	var position := ""
	var key := ""
	var cycle_key := ""
	var segment: Dictionary = {}
	var material := ""
	var entered := false
	var own := false
	var moves: Array = []
	var at := 0
	var waiting: Dictionary = {}
	var root_option := -1
	var uncertain := false
	var path_sensitive := false
	var longest: Line
	var strategy: Dictionary = {}
	var replies := 0
	var tactical_replies := 0
	func _init(state: ELDuel, left: int, spent: int, identity: String, assignments: Dictionary = {}) -> void:
		duel = state
		remaining = left
		tactics = spent
		position = identity
		segment = assignments
		cycle_key = identity + "/assignments=" + JSON.stringify(assignments)
		key = cycle_key + "/tactics=" + str(spent)
		own = state.active_side() == 0

class Job:
	extends RefCounted
	var done := false
	var result: Dictionary = {}
	var nodes := 0
	var _budget := DEFAULT_BUDGET
	var _depth := DEFAULT_DEPTH
	var _max_tactics := -1
	var _without_player: Dictionary = {}
	var _canonical_assignments := true
	var _allowed := 0
	var _first := 0
	var _begun := 0
	var _started := 0
	var _stack: Array = []
	var _memo := {}
	var _active := {}
	var _ordering := {}
	var _root_options: Array = []
	var _cache_hits := 0
	var _cycles := 0
	var _edges := 0
	var _assignment_repeats := 0

	func _begin(profile: ELProfile, entry: Dictionary, limits: Dictionary, current: ELDuel = null, remaining_own_turns := -1) -> void:
		_started = Time.get_ticks_usec()
		if profile == null or not ELPuzzles.valid_entry(entry, profile.id):
			_finish("invalid", null, "Invalid puzzle definition.")
			return
		var objective: Dictionary = entry.get("objective", {"type": "win"})
		if String(objective.get("type", "win")) != "win" or objective.keys().any(func(key: Variant) -> bool: return key != "type"):
			_finish("invalid", null, "This proof supports an ordinary victory objective only.")
			return
		for name: String in ["budget", "depth", "max_tactics"]:
			if not limits.has(name): continue
			var value: Variant = limits[name]
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)):
				_finish("invalid", null, "Proof limits must be integers.")
				return
		_budget = int(limits.get("budget", DEFAULT_BUDGET))
		_depth = int(limits.get("depth", DEFAULT_DEPTH))
		_max_tactics = int(limits.get("max_tactics", -1))
		_canonical_assignments = bool(limits.get("canonical_assignments", true))
		if _budget < 1 or _depth < 1 or _depth > 128 or _max_tactics < -1:
			_finish("invalid", null, "Invalid proof bounds.")
			return
		if limits.has("without_player"):
			var excluded: Variant = limits.without_player
			if excluded is not Dictionary:
				_finish("invalid", null, "Player operation exclusions must be a dictionary.")
				return
			for key: Variant in excluded:
				var values: Variant = excluded[key]
				if key not in ["casts", "effects", "abilities"] or values is not Array or values.size() > 64:
					_finish("invalid", null, "Invalid player operation exclusion group.")
					return
				for value: Variant in values:
					if value is not String or value.is_empty():
						_finish("invalid", null, "Player operation exclusions must contain nonempty strings.")
						return
			_without_player = excluded.duplicate(true)
		var state: Dictionary = entry.state
		var setup: Variant = state.get("setup", {})
		if setup is not Dictionary or setup.get("puzzle_fixed_hands", false) != true or setup.get("puzzle_fixed_channels", false) != true:
			_finish("invalid", null, "Generated proofs require fixed hands and channels.")
			return
		if state.has("scripts"):
			_finish("invalid", null, "Campaign script states are not supported.")
			return
		# Custom artifacts can wrap spells with second creature/grave choices;
		# the ordinary artifact argument helper does not enumerate those choices.
		var heroes: Variant = state.get("heroes", [])
		if heroes is Array:
			for hero: Variant in heroes:
				if hero is not Dictionary: continue
				var artifacts: Variant = hero.get("artifacts", [])
				if artifacts is Array and artifacts.any(func(item: Variant) -> bool: return item is Dictionary and item.has("custom")):
					_finish("invalid", null, "Custom spell artifacts are not supported by this verifier.")
					return
		var duel: ELDuel
		if current != null:
			duel = current.search_copy()
			# search_copy normally shares immutable setup. The advice boundary
			# owns its whole root so no later change to a live setup can leak in.
			duel.setup = current.setup.duplicate(true)
		else:
			duel = ELDuel.new()
			if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": state.duplicate(true)}):
				_finish("invalid", null, duel.error)
				return
		duel.searching = true
		_allowed = remaining_own_turns if current != null else int(entry.turns)
		_first = 1 if duel.attacker == 0 else 0
		_begun = int(duel.heroes[0].turns)
		if _terminal(duel) != 0:
			_finish("invalid", null, "A generated puzzle must begin in an unfinished position.")
			return
		# Reference moves affect ordering only. They cannot create a legal move,
		# suppress a reply, or transfer a proof to a different position.
		var reference := duel.search_copy()
		for raw: Variant in entry.get("solution", []):
			if raw is not Dictionary or _terminal(reference) != 0: break
			var action := ELPuzzleProof.command(reference, raw)
			if action.has("side") and int(action.side) != reference.active_side(): break
			var position := ELPuzzleProof._position(reference)
			var own := reference.active_side() == 0
			if not ELCombatSearch.apply(reference, action): break
			if own: _ordering[position] = action
		_stack.append(Frame.new(duel, _depth, 0, ELPuzzleProof._position(duel), ELPuzzleProof._assignment_segment(duel, _canonical_assignments)))

	## Advance a bounded number of traversal operations and yield to the UI.
	## The clock controls yielding only; it never changes proof acceptance.
	func step(node_quota: int = 32, usec_budget: int = 6000) -> void:
		if done: return
		var began := Time.get_ticks_usec()
		var quota := maxi(1, node_quota)
		for operation in quota:
			if done: return
			if operation > 0 and Time.get_ticks_usec() - began >= maxi(1, usec_budget): return
			_advance()

	func _terminal(duel: ELDuel) -> int:
		if int(duel.heroes[0].health) <= 0: return -1
		var turn := _first + int(duel.heroes[0].turns) - _begun
		if turn > _allowed: return -1
		if duel.phase == ELDuel.Phase.FINISHED: return 1 if duel.winner == 0 else -1
		return 0

	func _winning_leaf(duel: ELDuel) -> Dictionary:
		return ELPuzzleProof._strategy_leaf(_first + int(duel.heroes[0].turns) - _begun)

	func _advance() -> void:
		var frame: Frame = _stack.back()
		if not frame.entered:
			var terminal := _terminal(frame.duel)
			if terminal != 0:
				_return(terminal, null, _winning_leaf(frame.duel) if terminal == 1 else {})
				return
			if frame.remaining <= 0:
				_return(0, null)
				return
			if _memo.has(frame.key):
				var remembered: Dictionary = _memo[frame.key]
				# A complete refutation resolved every continuation, so a different
				# remaining depth cannot uncover a win. A forced strategy is reusable
				# only when its longest opponent branch fits the current depth.
				if int(remembered.value) == -1 or remembered.line == null or remembered.line.length <= frame.remaining:
					_cache_hits += 1
					_return(int(remembered.value), remembered.line, remembered.strategy)
					return
			if nodes >= _budget:
				_finish("unknown", null, "Position budget exhausted.")
				return
			nodes += 1
			frame.entered = true
			_active[frame.cycle_key] = true
			frame.moves = ELPuzzleProof._candidates(frame.duel)
			if frame.own and _max_tactics >= 0 and frame.tactics >= _max_tactics:
				frame.moves = frame.moves.filter(func(action: Dictionary) -> bool: return not ELPuzzleProof._tactic(action))
			if frame.own and not _without_player.is_empty():
				frame.moves = frame.moves.filter(func(action: Dictionary) -> bool: return not ELPuzzleProof._excluded_player_action(frame.duel, action, _without_player))
			# A quiet reply often already refutes an exhausted player. Between
			# own turns, try substantial enemy attacks before a quiet pass; once
			# one is declared, test its combat promptly. This changes only order:
			# a win must still survive every legal spell, ability and assignment.
			if not frame.own:
				var quiet: Dictionary = frame.moves.pop_back()
				var turn := _first + int(frame.duel.heroes[0].turns) - _begun
				if frame.duel.phase == ELDuel.Phase.ATTACK and frame.duel.attacks.is_empty() and turn > 0 and turn < _allowed:
					var attacks: Array = []
					var others: Array = []
					for action: Dictionary in frame.moves:
						if action.kind == "attack": attacks.append(action)
						else: others.append(action)
					attacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
						var ap := int(frame.duel.creatures[int(a.id)].power)
						var bp := int(frame.duel.creatures[int(b.id)].power)
						return ap > bp if ap != bp else int(a.id) < int(b.id))
					frame.moves = attacks + [quiet] + others
				else:
					frame.moves.push_front(quiet)
			var preferred: Dictionary = _ordering.get(frame.position, {})
			if not preferred.is_empty():
				for index in frame.moves.size():
					if _same_action(frame.moves[index], preferred):
						var selected: Dictionary = frame.moves.pop_at(index)
						frame.moves.push_front(selected)
						break
			return
		if frame.at >= frame.moves.size():
			var value := 0 if frame.uncertain else (-1 if frame.own else 1)
			if value == 1:
				frame.strategy.max_enemy_replies = maxi(int(frame.strategy.max_enemy_replies), frame.replies)
				frame.strategy.max_enemy_tactical_replies = maxi(int(frame.strategy.max_enemy_tactical_replies), frame.tactical_replies)
				if frame.replies > 1: frame.strategy.max_enemy_decisions += 1
			_return(value, frame.longest, frame.strategy if value == 1 else {})
			return
		var action: Dictionary = frame.moves[frame.at]
		frame.at += 1
		var child := frame.duel.search_copy()
		_edges += 1
		if not ELCombatSearch.apply(child, action): return
		var segment: Dictionary
		if bool(frame.segment.get("enabled", false)) and String(action.kind) in ["attack", "block"]:
			if frame.material.is_empty(): frame.material = ELPuzzleProof._material(frame.duel)
			# Attack taxes and their secondary damage are material changes. Even
			# when a declaration was touched before, resource-spending repetitions
			# remain legal and start a new segment; no such tactic is removed.
			if ELPuzzleProof._material(child) == frame.material:
				var id := int(action.id)
				var touched := int(frame.segment.touched.get(id, 0))
				var assigned: bool = frame.duel.attacks.has(id) if action.kind == "attack" else frame.duel.blocks.has(id)
				var can_restore: bool = frame.segment.initial.has(id) and touched == 1 and not assigned
				if touched > 0 and not can_restore:
					_assignment_repeats += 1
					return
				segment = frame.segment.duplicate(true)
				segment.touched[id] = touched + 1
		if segment == null or segment.is_empty(): segment = ELPuzzleProof._assignment_segment(child, _canonical_assignments)
		var position := ELPuzzleProof._position(child)
		# Returning to the same board with different assignment permissions is
		# not a cycle of the reduced graph. In particular, removing and restoring
		# an inherited attacker consumes its available pure reordering steps.
		if _active.has(position + "/assignments=" + JSON.stringify(segment)):
			_cycles += 1
			frame.path_sensitive = true
			return
		frame.waiting = action
		if not frame.own:
			frame.replies += 1
			if String(action.kind) in ["cast", "ability"]: frame.tactical_replies += 1
		if _stack.size() == 1:
			frame.root_option = _root_options.size()
			_root_options.append({"command": action.duplicate(true), "status": "unknown"})
		var spent := frame.tactics + (1 if ELPuzzleProof._tactic(action) else 0)
		_stack.append(Frame.new(child, frame.remaining - 1, spent, position, segment))

	func _same_action(first: Dictionary, second: Dictionary) -> bool:
		for name: String in ["kind", "index", "target", "grave", "power", "id", "key", "choice", "amount"]:
			if first.get(name) != second.get(name): return false
		return true

	func _return(value: int, line: Line, strategy: Dictionary = {}) -> void:
		var frame: Frame = _stack.pop_back()
		if frame.entered: _active.erase(frame.cycle_key)
		# A result that skipped an ancestor is valid only in that path context.
		# Do not cache it as a context-free transposition or it could erase a
		# useful route when reached later from a different sequence of toggles.
		# Cutoffs are depth-dependent and provide no completed proof to reuse.
		if not frame.path_sensitive and value != 0:
			_memo[frame.key] = {"value": value, "line": line, "strategy": strategy}
		if _stack.is_empty():
			_finish("forced" if value == 1 else ("refuted" if value == -1 else "unknown"), line,
				"Action depth exhausted on an unresolved continuation." if value == 0 else "", strategy)
			return
		var parent: Frame = _stack.back()
		parent.path_sensitive = parent.path_sensitive or frame.path_sensitive
		if _stack.size() == 1 and parent.root_option >= 0:
			_root_options[parent.root_option].status = "forced" if value == 1 else ("refuted" if value == -1 else "unknown")
			parent.root_option = -1
		if value == 0: parent.uncertain = true
		var next_line: Line
		var next_strategy: Dictionary = {}
		if value == 1:
			next_line = Line.new(parent.waiting.duplicate(true), line)
			next_strategy = ELPuzzleProof._strategy_step(strategy, parent.waiting)
		if parent.own and value == 1:
			_return(1, next_line, next_strategy)
		elif not parent.own and value == -1:
			_return(-1, null)
		elif not parent.own and value == 1:
			if parent.longest == null or next_line.length > parent.longest.length: parent.longest = next_line
			parent.strategy = ELPuzzleProof._strategy_merge(parent.strategy, next_strategy)

	func _finish(status: String, line: Line, reason: String = "", strategy: Dictionary = {}) -> void:
		var witness: Array = []
		var tactics := 0
		if status == "forced":
			while line != null:
				witness.append(line.action.duplicate(true))
				if ELPuzzleProof._tactic(line.action): tactics += 1
				line = line.next
		result = {"status": status, "nodes": nodes, "elapsed_ms": float(Time.get_ticks_usec() - _started) / 1000.0,
			"budget": _budget, "depth": _depth, "max_tactics": _max_tactics, "without_player": _without_player.duplicate(true),
			"strategy": strategy.duplicate() if status == "forced" else {},
			"witness": witness, "witness_tactics": tactics, "root_options": _root_options.duplicate(true),
			"root_options_complete": status == "refuted", "cache_hits": _cache_hits,
			"edges": _edges, "repeated_positions": _cycles, "canonical_assignments": _canonical_assignments,
			"equivalent_assignments_skipped": _assignment_repeats,
			"scope": "All material decisions and ordered combat assignments within bounds; equivalent pure assignment histories and exact repeated positions omitted."}
		if not _without_player.is_empty():
			result.scope += " Listed player operation groups are excluded for a development audit; enemy choices are unchanged."
		if not reason.is_empty(): result.reason = reason
		done = true
		_stack.clear()
		_active.clear()
		_memo.clear()
		_ordering.clear()
