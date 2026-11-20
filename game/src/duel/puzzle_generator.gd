class_name ELPuzzleGenerator
extends RefCounted
## Reproducible tactical challenges, checked with the actual battle rules.
## Recipe randomness proposes positions; only an adversarial proof admits one.
## Work is incremental and stays on the main thread, including web builds.

const VERSION := 5
const MAX_SEED := 2147483647
const MAX_ATTEMPTS := 24
## Caps the whole request, not just one unsuccessful candidate. Difficult
## variants must never multiply a per-proof budget into minutes of retries.
const MAX_TOTAL_NODES := 24000
const MASTER_TOTAL_NODES := 60000
const DIFFICULTIES := [2, 3, 4, 5]
static var _seed_rng: RandomNumberGenerator

static func code(edition: String, difficulty: int, seed_value: int) -> String:
	return "ELP%d:%s:%d:%d" % [VERSION, edition, difficulty, seed_value]

static func parse_code(value: String) -> Dictionary:
	var parts := value.strip_edges().split(":")
	if parts.size() != 4:
		return {"ok": false, "error": "Use a challenge code such as ELP5:el1:3:12345."}
	if parts[0].to_upper() != "ELP%d" % VERSION:
		return {"ok": false, "error": "This challenge code belongs to another generator version. Use an ELP5 code."}
	var edition := parts[1].to_lower()
	if edition not in ["el1", "el2"] or not parts[2].is_valid_int() or not parts[3].is_valid_int():
		return {"ok": false, "error": "Invalid challenge edition, difficulty or seed."}
	# Check length before conversion so oversized pasted integers cannot wrap.
	if parts[2].length() != 1 or parts[3].length() > 10:
		return {"ok": false, "error": "The seed must be between 1 and 2147483647."}
	var difficulty := int(parts[2])
	var seed_value := int(parts[3])
	if difficulty not in DIFFICULTIES or seed_value < 1 or seed_value > MAX_SEED:
		return {"ok": false, "error": "Choose difficulty 2, 3, 4 or 5 and a seed from 1 to 2147483647."}
	return {"ok": true, "edition": edition, "difficulty": difficulty, "seed": seed_value,
		"code": code(edition, difficulty, seed_value)}

static func available_families(edition: String, difficulty: int) -> Array[String]:
	var out: Array[String] = []
	for family: String in ELPuzzleRecipes.families(edition):
		if ELPuzzleRecipes.supports(family, difficulty): out.append(family)
	return out

static func family_for_seed(edition: String, seed_value: int, difficulty := 3) -> String:
	var choices := available_families(edition, difficulty)
	if choices.is_empty() or seed_value < 1: return ""
	return choices[(seed_value - 1) % choices.size()]

## Explicit family cycling remains available to tools. Fresh play uses a
## balanced shuffle, so a learnt carousel of families is not the next puzzle.
static func new_seed(profile: ELProfile, difficulty: int, previous_family := "") -> int:
	var choices := available_families(profile.id, difficulty)
	if choices.is_empty(): return 1
	var prior := choices.find(previous_family)
	var rng := _random_source()
	var index := (prior + 1) % choices.size() if prior >= 0 else rng.randi_range(0, choices.size() - 1)
	return seed_for_family(profile, difficulty, choices[index])

static func _random_source() -> RandomNumberGenerator:
	if _seed_rng == null:
		_seed_rng = RandomNumberGenerator.new()
		_seed_rng.randomize()
	return _seed_rng

static func seed_for_family(profile: ELProfile, difficulty: int, family: String) -> int:
	if profile == null: return 0
	var choices := available_families(profile.id, difficulty)
	var index := choices.find(family)
	if index < 0: return 0
	var groups := (MAX_SEED - choices.size()) / choices.size()
	return int(_random_source().randi() % int(groups)) * choices.size() + index + 1

## Shuffle ties among the least played families at this tier, putting the
## immediately previous family last. Counts include manual codes, so a long
## run of one mechanic is followed by neglected mechanics. Other editions
## never affect this selection. History only chooses codes, not their output.
static func family_schedule(profile: ELProfile, difficulty: int, history: Array) -> Array[String]:
	var choices := available_families(profile.id, difficulty)
	_shuffle(choices, _random_source())
	var counts := {}
	var previous := ""
	for record: Dictionary in history:
		if record.get("edition") != profile.id: continue
		previous = String(record.get("family", ""))
		if int(record.get("difficulty", 0)) == difficulty:
			counts[record.family] = int(counts.get(record.family, 0)) + 1
	choices.sort_custom(func(a: String, b: String) -> bool:
		if (a == previous) != (b == previous): return b == previous
		return int(counts.get(a, 0)) < int(counts.get(b, 0)))
	return choices

static func variant_key(entry: Dictionary) -> String:
	var metadata: Dictionary = entry.get("generated", {})
	return String(metadata.get("family", "")) + ":" + String(metadata.get("variant", "base"))

static func start(profile: ELProfile, seed_value: int, difficulty := 3, preferred_family := "") -> Job:
	var job := Job.new()
	job._start(profile, seed_value, difficulty, preferred_family)
	return job

static func node_limit(difficulty: int) -> int:
	return MASTER_TOTAL_NODES if difficulty == 5 else MAX_TOTAL_NODES

## A coarser, descriptive fingerprint of the recipe's verified reference plan.
## It ignores card numbers, absolute IDs, layout, hand order and the order of
## commands inside one phase. It retains mechanic/variant tags, target roles,
## repeated operations and the boundaries between turns. This is a preference
## for variety, not a claim that two people will experience equal difficulty.
static func plan_signature(profile: ELProfile, entry: Dictionary) -> String:
	var structure := plan_structure(profile, entry)
	return "" if structure.is_empty() else JSON.stringify(structure).sha256_text()

static func plan_structure(profile: ELProfile, entry: Dictionary) -> Dictionary:
	var state: Dictionary = entry.get("state", {})
	var metadata: Dictionary = entry.get("generated", {})
	var duel := ELDuel.new()
	duel.searching = true
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": state.duplicate(true)}): return {}
	var begun := int(duel.heroes[0].turns)
	var first := 1 if duel.attacker == 0 else 0
	var mechanics: Array = metadata.get("mechanics", []).duplicate()
	mechanics.sort()
	var phases: Array = []
	var operations: Array = []
	var segment := {"side": duel.active_side(), "phase": duel.phase, "own_turn": first}
	for raw: Dictionary in metadata.get("recipe_solution", entry.get("solution", [])):
		if int(raw.get("side", duel.active_side())) != duel.active_side(): return {}
		var actual := ELPuzzleProof.command(duel, raw)
		if raw.get("kind") != "end_phase":
			var before := duel.snapshot()
			var operation := {"kind": raw.get("kind"), "side": duel.active_side(),
				"target": _plan_role(before, int(raw.get("target", -1)))}
			if raw.get("kind") == "cast":
				operation["effect"] = _plan_spell(profile, String(raw.get("card", "")))
			elif raw.get("kind") == "ability":
				var key := String(raw.get("key", ""))
				operation["key"] = key.get_slice(":", 0)
				for ability: Dictionary in duel.abilities(int(raw.get("id", -1))):
					if ability.get("key") == key:
						operation["ability_card"] = ability.get("enchantment_card", ability.get("card", ""))
						break
				operation["source"] = _plan_role(before, int(raw.get("id", -1)))
			else:
				operation["source"] = _plan_role(before, int(raw.get("id", -1)))
			operations.append(JSON.stringify(operation))
		if not ELCombatSearch.apply(duel, actual): return {}
		# Empty attacks skip defence in ELDuel. Real replay, not alternation,
		# therefore determines which side and own turn the next segment uses.
		var next := {"side": duel.active_side(), "phase": duel.phase,
			"own_turn": first + int(duel.heroes[0].turns) - begun}
		if raw.get("kind") == "end_phase" or next != segment:
			operations.sort()
			var finished := segment.duplicate()
			finished["operations"] = operations.duplicate()
			phases.append(finished)
			operations.clear()
			segment = next
	if duel.phase != ELDuel.Phase.FINISHED or duel.winner != 0 or first + int(duel.heroes[0].turns) - begun > int(entry.get("turns", 0)): return {}
	if not operations.is_empty():
		operations.sort()
		segment["operations"] = operations
		phases.append(segment)
	var hands: Array = []
	for hero: Dictionary in state.get("heroes", []):
		var effects: Array = []
		for card: String in hero.get("hand", []): effects.append(JSON.stringify(_plan_spell(profile, card)))
		effects.sort()
		hands.append(effects)
	return {"edition": state.get("profile"), "turns": entry.get("turns"),
		"phase": state.get("phase"), "attacker": state.get("attacker"), "mechanics": mechanics,
		"variant": metadata.get("variant", metadata.get("family", "")), "hands": hands, "phases": phases}

static func _plan_role(state: Dictionary, id: int) -> String:
	if id < 0: return "none"
	if id < 2: return "hero_%d" % id
	var creature: Dictionary = state.get("creatures", {}).get(str(id), state.get("creatures", {}).get(id, {}))
	if creature.is_empty(): return "created_creature"
	var flags: Array = creature.get("flags", []).duplicate()
	flags.sort()
	return JSON.stringify({"owner": creature.get("owner"), "flags": flags,
		"wounded": int(creature.get("damage", 0)) > 0, "resting": creature.get("resting", false), "sick": creature.get("sick", false)})

static func _plan_spell(profile: ELProfile, card: String) -> Dictionary:
	var rule := ELCatalog.rule(profile, card)
	var effect := String(rule.get("effect", "summon"))
	var value := {"effect": effect, "target": rule.get("target", "none")}
	if effect in ["enchant", "bless"] and (rule.has("power") or rule.has("toughness")):
		value["power"] = signi(int(rule.get("power", 0)))
		value["toughness"] = signi(int(rule.get("toughness", 0)))
	elif effect in ["damage", "wave", "heal", "mana", "channels", "drain_mana"]:
		value["scope"] = rule.get("scope", "")
		value["variable"] = rule.get("variable", false)
	else:
		# Special enchantments, summons and unusual removals have additional
		# card-specific rules; merging them on effect alone would hide variety.
		value["card"] = card
	return value

## Cross-family, reference-line decision proxy. Unlike plan_signature, this
## has no recipe labels, card codes, numeric magnitudes or presentation IDs.
## Anonymous participant nodes preserve "enhance then consume the SAME piece";
## real replay supplies effects, chosen relationships and phase boundaries.
## This describes one verified reference, not every winning strategy and not
## human originality. Equal graphs deliberately merge some different puzzles.
## The performed cast repertoire is separate from both material and decision
## novelty. Cards that are merely sitting in hand do not count. A semantic
## role groups mechanically equivalent spells; printed codes track genuinely
## different card exposure even when they have equivalent rule signatures.
static func spell_inventory(profile: ELProfile, entry: Dictionary) -> Dictionary:
	var roles: Array[String] = []
	var cards: Array[String] = []
	for action: Dictionary in entry.get("generated", {}).get("recipe_solution", entry.get("solution", [])):
		if action.get("kind") != "cast": continue
		var card := String(action.get("card", ""))
		if card.is_empty(): continue
		var role := JSON.stringify(_decision_spell(profile, card))
		if not roles.has(role): roles.append(role)
		if not cards.has(card): cards.append(card)
	roles.sort()
	cards.sort()
	return {"roles": roles, "cards": cards}

static func decision_signature(profile: ELProfile, entry: Dictionary) -> String:
	var structure := decision_structure(profile, entry)
	return "" if structure.is_empty() else JSON.stringify(structure).sha256_text()

static func decision_structure(profile: ELProfile, entry: Dictionary) -> Dictionary:
	return DecisionTrace.new().build(profile, entry)

## Remove magnitudes and editorial fields from actual rule definitions. The
## remaining directions/flags describe mechanics; unknown card-specific rules
## conservatively coalesce until their observed effects distinguish them.
static func _decision_rule(rule: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["effect", "target", "second", "scope", "variable", "x_source", "self", "opponent", "own", "fixed", "lethal", "dispel", "flying", "ready", "rest", "resting", "unpaid", "pale", "stat", "measure", "reject"]:
		if not rule.has(key): continue
		if rule[key] is int or rule[key] is float: out[key + "_direction"] = signi(int(rule[key]))
		else: out[key] = rule[key]
	# Spell rules use a boolean; live hero abilities overload this field with
	# a cosmetic source-copy ID, represented by a graph relationship instead.
	if rule.get("enchantment") is bool: out["enchantment"] = rule.enchantment
	for key: String in ["power", "toughness", "health_cost", "cost", "amount", "regeneration"]:
		if rule.has(key): out[key + "_direction"] = signi(int(rule[key]))
	if rule.has("key"): out["ability"] = String(rule.key).get_slice(":", 0)
	if rule.has("flags"): out["flags"] = _decision_flags(rule.flags)
	return out

static func _decision_flags(flags: Array) -> Array:
	var out: Array = []
	for flag: String in flags:
		var generic := flag.get_slice("(", 0)
		if not out.has(generic): out.append(generic)
	out.sort()
	return out

static func _decision_spell(profile: ELProfile, card: String) -> Dictionary:
	var out := _decision_rule(ELCatalog.rule(profile, card))
	if ELCatalog.GRANTED_FLAGS.has(card): out["grants"] = _decision_flags(ELCatalog.GRANTED_FLAGS[card])
	if ELCatalog.HERO_ABILITIES.has(card): out["grants_ability"] = _decision_rule(ELCatalog.HERO_ABILITIES[card])
	if ELCatalog.ARMY_AURAS.has(card): out["army_aura"] = _decision_rule(ELCatalog.ARMY_AURAS[card])
	if ELCatalog.HERO_AURAS.has(card): out["hero_aura"] = _decision_rule(ELCatalog.HERO_AURAS[card])
	# These semantic distinctions are implemented explicitly in ELDuel, rather
	# than in the catalog's generic enchant rule. They are not recipe tags.
	if card in ELCatalog.CONTROL: out["changes_controller"] = true
	if card == "DELS": out["stat_transform"] = "exchange_power_toughness"
	if card == "ALST": out["scales_with"] = "printed_power"
	if card == "OVRL": out["duration"] = "decaying"
	elif card in ["BLSS", "ALST", "CMBN"]: out["duration"] = "until_next_own_turn"
	return out

class DecisionTrace:
	extends RefCounted
	var profile: ELProfile
	var initial: Dictionary
	var labels: Array = []
	var links: Array = []
	var entities := {}
	var entity_facts := {}
	var marks := {}
	var events: Array = []
	var phases: Array = []
	var segment := 0

	func _node(label: Dictionary) -> int:
		labels.append(JSON.stringify(label))
		return labels.size() - 1

	func _edge(source: int, target: int, relation: String) -> void:
		if source >= 0 and target >= 0: links.append([source, relation, target])

	func _entity(state: Dictionary, id: int) -> int:
		if id < 0: return -1
		if entities.has(id): return int(entities[id])
		var current := _body(state, id)
		if current.is_empty(): return -1
		var original := _body(initial, id)
		if original.is_empty(): original = current
		var role := {"kind": "hero" if id < 2 else "creature", "owner": int(original.get("owner", id))}
		if id >= 2:
			entity_facts[id] = original
		entities[id] = _node(role)
		return int(entities[id])

	func _combat_role(id: int) -> void:
		if not entities.has(id) or id < 2: return
		var role: Dictionary = JSON.parse_string(labels[int(entities[id])])
		var body: Dictionary = entity_facts[id]
		role["combat_flags"] = ELPuzzleGenerator._decision_flags(body.get("flags", []) + body.get("granted", []))
		labels[int(entities[id])] = JSON.stringify(role)

	func _body(state: Dictionary, id: int) -> Dictionary:
		if id in [0, 1]: return state.heroes[id]
		return state.get("creatures", {}).get(str(id), state.get("creatures", {}).get(id, {}))

	func _mark(state: Dictionary, holder: int, mark: Dictionary) -> int:
		var id := int(mark.get("id", -1))
		if not marks.has(id):
			marks[id] = _node({"kind": "enchantment", "rule": ELPuzzleGenerator._decision_spell(profile, String(mark.get("card", ""))), "owner": mark.get("owner", holder)})
			_edge(int(marks[id]), _entity(state, holder), "held_by")
		return int(marks[id])

	func _selected_mark(state: Dictionary, holder: int, id: int) -> int:
		for mark: Dictionary in _body(state, holder).get("enchantments", []):
			if int(mark.get("id", -1)) == id: return _mark(state, holder, mark)
		return -1

	func _choice(event: int, duel: ELDuel, state: Dictionary, command: Dictionary, rule: Dictionary) -> void:
		var target := int(command.get("target", -1))
		var choice := int(command.get("grave", command.get("choice", -1)))
		var effect := String(rule.get("effect", rule.get("key", ""))).get_slice(":", 0)
		if effect == "swap" or not String(rule.get("second", "creature" if effect == "combine" else "")).is_empty():
			_edge(event, _entity(state, choice), "second_target")
		elif effect in ["dispel", "trade"] or rule.get("target") == "enchantment":
			var holder := duel.find_enchantment(choice) if effect == "trade" else target
			_edge(event, _selected_mark(state, holder, choice), "chosen_enchantment")
		elif rule.get("target") == "grave" or effect in ["exchange", "pale_revival", "revive"]:
			var owner := target if rule.get("target") == "grave" else duel.active_side()
			if effect == "pale_revival":
				owner = choice / ELDuel.GRAVE_SIDE
				choice %= ELDuel.GRAVE_SIDE
			elif effect == "revive": choice = duel.heroes[owner].grave.size() - 1
			if owner in [0, 1] and choice >= 0 and choice < duel.heroes[owner].grave.size():
				var role := {"kind": "grave_choice", "owner": owner,
					"position": "newest" if choice == duel.heroes[owner].grave.size() - 1 else ("oldest" if choice == 0 else "interior")}
				_edge(event, _node(role), "chosen_corpse")

	func _changes(event: int, before: Dictionary, after: Dictionary) -> Dictionary:
		var touched := {}
		var ids: Array = [0, 1]
		for key: Variant in before.creatures:
			if not ids.has(int(key)): ids.append(int(key))
		for key: Variant in after.creatures:
			if not ids.has(int(key)): ids.append(int(key))
		for id: int in ids:
			var a := _body(before, id)
			var b := _body(after, id)
			var body := _entity(before if not a.is_empty() else after, id)
			if a.is_empty() or b.is_empty():
				_edge(event, body, "created" if a.is_empty() else "removed")
				touched["piece:%d" % id] = true
				continue
			for field: String in ["health", "mana", "channels", "power", "toughness", "damage"]:
				var change := signi(int(b.get(field, 0)) - int(a.get(field, 0)))
				if change != 0:
					_edge(event, body, field + ("_increased" if change > 0 else "_decreased"))
					touched["piece:%d" % id if id >= 2 else "hero:%d:%s" % [id, field]] = true
			for field: String in ["owner", "resting", "sick", "plane"]:
				if a.get(field, false) != b.get(field, false):
					_edge(event, body, field + "_to_" + str(b.get(field, false)))
					touched["piece:%d" % id if id >= 2 else "hero:%d:%s" % [id, field]] = true
			var old_flags := ELPuzzleGenerator._decision_flags(a.get("flags", []) + a.get("granted", []))
			var new_flags := ELPuzzleGenerator._decision_flags(b.get("flags", []) + b.get("granted", []))
			for flag: String in old_flags:
				if not new_flags.has(flag): _edge(event, body, "loses_" + flag)
			for flag: String in new_flags:
				if not old_flags.has(flag): _edge(event, body, "gains_" + flag)
			var old_marks := {}
			var new_marks := {}
			for mark: Dictionary in a.get("enchantments", []): old_marks[int(mark.id)] = mark
			for mark: Dictionary in b.get("enchantments", []): new_marks[int(mark.id)] = mark
			for key: int in old_marks:
				if not new_marks.has(key):
					_edge(event, _mark(before, id, old_marks[key]), "removes_enchantment")
				elif old_marks[key] != new_marks[key]:
					_edge(event, _mark(before, id, old_marks[key]), "changes_enchantment")
			for key: int in new_marks:
				if not old_marks.has(key): _edge(event, _mark(after, id, new_marks[key]), "creates_enchantment")
			if old_marks != new_marks: touched["piece:%d" % id if id >= 2 else "hero:%d:enchantments" % id] = true
			if id < 2 and a.get("grave", []) != b.get("grave", []):
				var change := {"kind": "grave_transition", "before": [], "after": []}
				# A wave's simultaneous death order follows board insertion order.
				# Do not call that visual shuffle new thinking. Explicit selectors,
				# top-corpse recovery and replayed ordering dependencies retain the
				# cases where the actual reference uses grave order.
				for _card: String in a.get("grave", []): change.before.append("creature")
				for _card: String in b.get("grave", []): change.after.append("creature")
				var grave := _node(change)
				_edge(event, grave, "changes_grave")
				_edge(grave, body, "grave_owner")
				touched["hero:%d:grave" % id] = true
			if id < 2 and a.get("hand", []) != b.get("hand", []):
				var old_hand: Array = a.get("hand", []).duplicate()
				var new_hand: Array = b.get("hand", []).duplicate()
				for card: String in old_hand.duplicate():
					if new_hand.has(card):
						old_hand.erase(card)
						new_hand.erase(card)
				for zone: String in ["leaves_hand", "enters_hand"]:
					for card: String in (old_hand if zone == "leaves_hand" else new_hand):
						var card_role := ELPuzzleGenerator._decision_spell(profile, card)
						var token := _node({"kind": "hand_change", "rule": card_role})
						_edge(event, token, zone)
						_edge(token, body, "hand_owner")
				touched["hero:%d:hand" % id] = true
		return touched

	func build(owner: ELProfile, entry: Dictionary) -> Dictionary:
		profile = owner
		if profile == null: return {}
		var duel := ELDuel.new()
		duel.searching = true
		if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.get("state", {}).duplicate(true)}): return {}
		initial = duel.snapshot()
		var begun := int(duel.heroes[0].turns)
		var first := 1 if duel.attacker == 0 else 0
		var reference: Array = entry.get("generated", {}).get("recipe_solution", entry.get("solution", []))
		if reference.is_empty() or reference.size() > 64: return {}
		var previous_phase := {}
		for raw: Dictionary in reference:
			if int(raw.get("side", duel.active_side())) != duel.active_side(): return {}
			var phase := {"side": duel.active_side(), "phase": duel.phase, "own_turn": first + int(duel.heroes[0].turns) - begun}
			if phase != previous_phase:
				phases.append(phase)
				segment += 1
				previous_phase = phase
			var command := ELPuzzleProof.command(duel, raw)
			var before := duel.snapshot()
			var saved := duel.search_copy()
			var descriptor := phase.duplicate()
			descriptor["kind"] = String(command.get("kind", ""))
			var rule := {}
			if command.kind == "cast":
				var index := int(command.get("index", -1))
				if index < 0 or index >= duel.heroes[duel.active_side()].hand.size(): return {}
				command["card"] = duel.heroes[duel.active_side()].hand[index]
				rule = ELCatalog.rule(profile, command.card)
				descriptor["rule"] = ELPuzzleGenerator._decision_spell(profile, command.card)
			elif command.kind == "ability":
				for ability: Dictionary in duel.abilities(int(command.id)):
					if ability.key == command.key: rule = ability
				descriptor["rule"] = ELPuzzleGenerator._decision_rule(rule)
				if String(command.key).get_slice(":", 0) == "spores":
					descriptor.rule["scales_with"] = "source_power" if duel.entity(int(command.id)).get("card") == "CAFG" else "fixed_damage"
				if rule.has("enchantment"):
					for mark: Dictionary in duel.entity(int(command.id)).get("enchantments", []):
						if int(mark.id) == int(rule.enchantment): command["_trace_source_mark"] = _without_mark_id(mark)
			var event := _node(descriptor)
			_edge(event, _entity(before, int(command.get("id", -1))), "source")
			_edge(event, _entity(before, int(command.get("target", -1))), "target")
			if command.kind in ["attack", "block"]:
				_combat_role(int(command.get("id", -1)))
				_combat_role(int(command.get("target", -1)))
			_choice(event, duel, before, command, rule)
			if rule.has("enchantment"):
				_edge(event, _selected_mark(before, int(command.get("id", -1)), int(rule.enchantment)), "source_enchantment")
			if not ELCombatSearch.apply(duel, command): return {}
			var touched := _changes(event, before, duel.snapshot())
			for field: String in ["id", "target"]:
				var id := int(command.get(field, -1))
				if id >= 0: touched["piece:%d" % id if id >= 2 else "hero:%d:chosen" % id] = true
			for prior_index in events.size():
				var prior: Dictionary = events[prior_index]
				if prior.segment != segment or command.kind == "end_phase": continue
				var shared := touched.keys().any(func(key: String) -> bool: return prior.touched.has(key))
				if shared and _dependent(prior_index, command, saved): _edge(int(prior.node), event, "precedes_on_shared_material")
			events.append({"node": event, "segment": segment, "command": command, "before": saved, "touched": touched})
		if duel.phase != ELDuel.Phase.FINISHED or duel.winner != 0 or int(duel.heroes[0].health) <= 0 or first + int(duel.heroes[0].turns) - begun > int(entry.get("turns", 0)): return {}
		return _canonical()

	## Test in the enabled context immediately before the later operation. A
	## nonadjacent earlier action may cross only a replay that still reproduces
	## that context. Failure to move it is not evidence of a direct dependency
	## on the later action: intervening operations already carry that ordering.
	func _dependent(index: int, command: Dictionary, current: ELDuel) -> bool:
		var prior: Dictionary = events[index]
		var delayed: ELDuel = prior.before.search_copy()
		for between in range(index + 1, events.size()):
			if not _apply_reordered(delayed, events[between].command): return false
		var restored := delayed.search_copy()
		if not _apply_reordered(restored, prior.command): return false
		if _commutation_state(restored) != _commutation_state(current): return false
		return not _commute(delayed, prior.command, command)

	## Only a fingerprint reduction, never a proof-search pruning rule. Both
	## orders must execute from the same independent position. Exact state is
	## retained except interchangeable enchantment IDs/list order. That exception
	## cannot certify gameplay equivalence; it merely prevents cosmetic buff
	## ordering from claiming decision novelty in this descriptive proxy.
	func _commute(before: ELDuel, a: Dictionary, b: Dictionary) -> bool:
		if a.kind == "end_phase" or b.kind == "end_phase": return false
		var left := before.search_copy()
		var right := before.search_copy()
		if not _apply_reordered(left, a) or not _apply_reordered(left, b) or not _apply_reordered(right, b) or not _apply_reordered(right, a): return false
		return _commutation_state(left) == _commutation_state(right)

	func _apply_reordered(duel: ELDuel, raw: Dictionary) -> bool:
		var command := raw.duplicate(true)
		if command.kind == "cast": command.erase("index")
		elif command.has("_trace_source_mark"):
			# Crossing an independent enchantment cast renumbers newly allocated
			# source IDs. Resolve the same mechanical copy, not its old number.
			var found := false
			for mark: Dictionary in duel.entity(int(command.id)).get("enchantments", []):
				if _without_mark_id(mark) == command._trace_source_mark:
					command.key = String(command.key).get_slice(":", 0) + ":" + str(mark.id)
					found = true
					break
			if not found: return false
		return ELPuzzleProof.apply(duel, command)

	func _without_mark_id(mark: Dictionary) -> Dictionary:
		var value := mark.duplicate(true)
		value.erase("id")
		return value

	func _commutation_state(duel: ELDuel) -> String:
		var state := duel.snapshot()
		for body: Dictionary in state.heroes + state.creatures.values():
			var normalized: Array = []
			for mark: Dictionary in body.get("enchantments", []):
				var value := _without_mark_id(mark)
				normalized.append(JSON.stringify(value))
			normalized.sort()
			body.enchantments = normalized
		return JSON.stringify({"state": state, "next_card": duel.next_card}, "", false)

	## Eight rounds of deterministic labeled-neighborhood refinement preserve
	## graph isomorphisms, including symmetric identical pieces. Some non-isomorphic
	## graphs can still collide: that errs toward merging, not invented novelty.
	func _canonical() -> Dictionary:
		var adjacency: Array = []
		for _label in labels: adjacency.append([])
		for link: Array in links:
			adjacency[int(link[0])].append(["out", link[1], int(link[2])])
			adjacency[int(link[2])].append(["in", link[1], int(link[0])])
		var colors: Array = labels.duplicate()
		for _round in 8:
			var next: Array = []
			for index in labels.size():
				var neighbors: Array = []
				for neighbor: Array in adjacency[index]: neighbors.append(JSON.stringify([neighbor[0], neighbor[1], colors[int(neighbor[2])]]))
				neighbors.sort()
				next.append(JSON.stringify([labels[index], neighbors]).sha256_text())
			colors = next
		var nodes: Array = []
		for index in labels.size():
			var role: Dictionary = JSON.parse_string(labels[index])
			# Unused board padding must not manufacture a different decision.
			# Keep phase/action nodes, including a meaningful empty commitment.
			if adjacency[index].is_empty() and role.get("kind") in ["hero", "creature", "enchantment"]: continue
			nodes.append(JSON.stringify({"role": role, "neighborhood": colors[index]}))
		nodes.sort()
		var relations: Array = []
		for link: Array in links: relations.append(JSON.stringify([colors[int(link[0])], link[1], colors[int(link[2])]]))
		relations.sort()
		return {"schema": 1, "phases": phases, "participants_and_operations": nodes, "relations": relations}

## A session remembers only recently delivered challenges, never progress or
## complete duel states. Explicit seeds bypass it, and remembering a manual
## replay does not change that code's deterministic construction.
class Session:
	extends RefCounted
	const MAX_RECENT := 64
	var _recent: Array = []

	func start(profile: ELProfile, difficulty: int) -> RefCounted:
		var job := FreshJob.new()
		job._start(profile, difficulty, _recent)
		return job

	func note(entry: Dictionary) -> void:
		var metadata: Dictionary = entry.get("generated", {})
		if metadata.get("version") != ELPuzzleGenerator.VERSION or String(metadata.get("tactical_signature", "")).is_empty(): return
		for index in _recent.size():
			if _recent[index].code == metadata.get("code", "") or _recent[index].signature == metadata.tactical_signature:
				_recent.remove_at(index)
				break
		_recent.append({"code": metadata.get("code", ""), "edition": entry.get("state", {}).get("profile", ""),
			"difficulty": metadata.get("difficulty", 3), "family": metadata.get("family", ""),
			"variant": metadata.get("variant", "base"), "variant_key": ELPuzzleGenerator.variant_key(entry),
			"signature": metadata.tactical_signature, "plan": metadata.get("plan_signature", ""),
			"decision": metadata.get("decision_signature", ""),
			"spell_roles": metadata.get("spell_roles", []).duplicate(),
			"spell_cards": metadata.get("spell_cards", []).duplicate()})
		while _recent.size() > MAX_RECENT: _recent.pop_front()

	func recent() -> Array:
		return _recent.duplicate(true)

## Fresh generation selects a code, then runs the ordinary deterministic job.
## Cheap recipe previews prefer a different decision graph across families;
## actual accepted material must not repeat the last 64 delivered positions.
## No history can alter a code's entry. Decision novelty is a soft preference:
## bounded previews may exhaust their alternatives and report a repeated graph.
## At most four jobs and 128 previews bound a fresh request. Each new job must
## fit wholly within two ordinary jobs' worth of nodes. Cheap duplicate results
## can therefore be replaced without raising the worst-case proof-node budget.
class FreshJob:
	extends RefCounted
	const MAX_PROPOSALS := 128
	const MAX_PROOFS := 4
	const NODE_BUDGET_MULTIPLIER := 2
	const DECISION_WINDOW := 12
	const PREVIEWS_PER_FAMILY := 4
	var done := false
	var result: Dictionary = {}
	var progress_text := ""
	var _profile: ELProfile
	var _difficulty := 3
	var _recent: Array = []
	var _signatures := {}
	var _plans := {}
	var _decisions := {}
	var _decision_last := {}
	var _variant_last := {}
	var _spell_role_last := {}
	var _spell_card_last := {}
	var _family_order: Array[String] = []
	var _family_index := 0
	var _preferred_variants: Array[String] = []
	var _current_family := ""
	var _job: RefCounted
	var _proposals := 0
	var _proofs := 0
	var _family_proposals := 0
	var _total_nodes := 0
	var _began := 0
	var _last_error := ""
	var _fallback: Dictionary = {}
	var _preview_fallback: Dictionary = {}
	var _decision_search_complete := false

	func _start(profile: ELProfile, difficulty: int, history: Array) -> void:
		_profile = profile
		_difficulty = difficulty
		_began = Time.get_ticks_usec()
		_recent = history.duplicate(true)
		if profile == null or profile.id not in ["el1", "el2"] or difficulty not in ELPuzzleGenerator.DIFFICULTIES:
			_fail("Invalid random challenge settings.", "Неверные параметры случайной задачи.")
			return
		var decision_history: Array = []
		for index in _recent.size():
			var record: Dictionary = _recent[index]
			if record.edition != profile.id: continue
			_signatures[record.signature] = true
			if not String(record.get("plan", "")).is_empty(): _plans[record.plan] = true
			var decision := String(record.get("decision", ""))
			if not decision.is_empty():
				decision_history.append(decision)
				_decision_last[decision] = index
			_variant_last[String(record.get("variant_key", String(record.family) + ":" + String(record.get("variant", "base"))))] = index
		var seen_same_edition := 0
		for reverse in range(_recent.size() - 1, -1, -1):
			var record: Dictionary = _recent[reverse]
			if record.get("edition") != profile.id: continue
			for role: String in record.get("spell_roles", []): _spell_role_last[role] = reverse
			for card: String in record.get("spell_cards", []): _spell_card_last[card] = reverse
			seen_same_edition += 1
			if seen_same_edition >= DECISION_WINDOW: break
		for decision: String in decision_history.slice(maxi(0, decision_history.size() - DECISION_WINDOW)): _decisions[decision] = true
		_family_order = ELPuzzleGenerator.family_schedule(profile, difficulty, _recent)
		_select_family()
		progress_text = _text("Looking for a different plan…", "Поиск нового замысла…")

	func _select_family() -> void:
		_current_family = _family_order[_family_index % _family_order.size()]
		_family_proposals = 0
		_preferred_variants.clear()
		var oldest := _recent.size()
		for variant: String in ELPuzzleRecipes.variants(_current_family, _difficulty):
			var last := int(_variant_last.get(_current_family + ":" + variant, -1))
			if last < oldest:
				oldest = last
				_preferred_variants.clear()
			if last == oldest: _preferred_variants.append(variant)

	func _advance_family() -> void:
		_family_index += 1
		if _family_index >= _family_order.size(): _decision_search_complete = true
		_select_family()

	func _novel_decision(metadata: Dictionary) -> bool:
		var decision := String(metadata.get("decision_signature", ""))
		return not decision.is_empty() and not _decisions.has(decision)

	func _preference(metadata: Dictionary, preferred: Array) -> int:
		var decision := String(metadata.get("decision_signature", ""))
		var age := _recent.size() - int(_decision_last.get(decision, -1)) if not decision.is_empty() else 0
		var new_roles := 0
		var new_cards := 0
		for role: String in metadata.get("spell_roles", []):
			if not _spell_role_last.has(role): new_roles += 1
		for card: String in metadata.get("spell_cards", []):
			if not _spell_card_last.has(card): new_cards += 1
		return (10000 if _novel_decision(metadata) else 0) + age * 10 \
			+ new_roles * 120 + new_cards * 15 \
			+ (4 if String(metadata.get("variant", "base")) in preferred else 0) \
			+ (2 if not _variant_last.has(String(metadata.get("family", "")) + ":" + String(metadata.get("variant", "base"))) else 0) \
			+ (1 if not _plans.has(String(metadata.get("plan_signature", ""))) else 0)

	func _start_preview(preview: Dictionary) -> void:
		_current_family = String(preview.family)
		_family_index = maxi(0, _family_order.find(_current_family))
		_preferred_variants.assign(preview.preferred)
		_job = ELPuzzleGenerator.start(_profile, int(preview.seed), _difficulty)
		_proofs += 1
		_preview_fallback = {}

	func _can_prove() -> bool:
		# Reserve an entire ordinary request before starting it. We never lower
		# that job's deterministic limits: doing so could change a shared code's
		# accepted candidate. Finished cheap jobs may free room for recovery.
		var allowance := ELPuzzleGenerator.node_limit(_difficulty)
		return _proofs < MAX_PROOFS and _total_nodes + allowance <= NODE_BUDGET_MULTIPLIER * allowance

	func _offer(answer: Dictionary) -> bool:
		var entry: Dictionary = answer.get("entry", {})
		if entry.is_empty() or _signatures.has(entry.generated.tactical_signature): return false
		var metadata: Dictionary = entry.generated
		var matches := String(metadata.get("variant", "base")) in _preferred_variants
		var score := _preference(metadata, _preferred_variants)
		var had_fallback := not _fallback.is_empty()
		if _fallback.is_empty() or score > int(_fallback.score):
			_fallback = {"answer": answer.duplicate(true), "preferred": _preferred_variants.duplicate(), "score": score}
		# A preview can pass yet the deterministic job reject its first recipe
		# and admit a different variant. Seek that alternative at most once
		# after finding a certified fallback, even if cheap jobs left more room.
		if (matches and _novel_decision(metadata)) or had_fallback or not _can_prove() or _decision_search_complete:
			_deliver()
		else:
			# An accepted reroll can have a different graph from its preview.
			# Seek another family once, retaining the certified material fallback.
			_advance_family()
			progress_text = _text("Looking for a different plan…", "Поиск нового замысла…")
		return true

	func _deliver() -> void:
		result = _fallback.answer.duplicate(true)
		var entry: Dictionary = result.entry
		result.nodes = _total_nodes
		result.elapsed_ms = (Time.get_ticks_usec() - _began) / 1000.0
		result.variety = {"previews": _proposals, "proof_jobs": _proofs, "recent_positions": _signatures.size(),
			"proof_node_limit": NODE_BUDGET_MULTIPLIER * ELPuzzleGenerator.node_limit(_difficulty),
			"recent_position_repeated": false, "recent_plan_repeated": _plans.has(entry.generated.plan_signature),
			"recent_variant_repeated": _variant_last.has(ELPuzzleGenerator.variant_key(entry)),
			"decision_window": DECISION_WINDOW, "recent_decisions": _decisions.size(),
			"decision_signature": entry.generated.get("decision_signature", ""),
			"recent_decision_repeated": not _novel_decision(entry.generated),
			"decision_preference_relaxed": not _novel_decision(entry.generated),
			"decision_family_sweep_completed": _decision_search_complete,
			"spell_roles": entry.generated.get("spell_roles", []),
			"spell_cards": entry.generated.get("spell_cards", []),
			"unseen_spell_roles": entry.generated.get("spell_roles", []).filter(func(role: String) -> bool: return not _spell_role_last.has(role)),
			"unseen_spell_cards": entry.generated.get("spell_cards", []).filter(func(card: String) -> bool: return not _spell_card_last.has(card)),
			"preferred_variant_matched": String(entry.generated.get("variant", "base")) in _fallback.preferred,
			"preferred_variants": _fallback.preferred.duplicate()}
		progress_text = _text("Challenge verified.", "Задача проверена.")
		done = true

	func step(node_quota := 32, usec_budget := 6000) -> void:
		if done: return
		var until := Time.get_ticks_usec() + maxi(1, usec_budget)
		var remaining := maxi(1, node_quota)
		while not done and remaining > 0:
			if _job != null:
				_job.step(remaining, maxi(1, until - Time.get_ticks_usec()))
				progress_text = _job.progress_text
				if not _job.done: return
				var answer: Dictionary = _job.result
				_total_nodes += int(answer.get("nodes", 0))
				_job = null
				if _offer(answer):
					if done: return
				else:
					if not _fallback.is_empty():
						_deliver()
						return
					_last_error = String(answer.get("error", ""))
					_advance_family()
					progress_text = _text("Looking for a different plan…", "Поиск нового замысла…")
			else:
				if (_proposals >= MAX_PROPOSALS or _decision_search_complete) and not _preview_fallback.is_empty() and _can_prove():
					_start_preview(_preview_fallback)
					continue
				if _proposals >= MAX_PROPOSALS or not _can_prove():
					if not _fallback.is_empty():
						_deliver()
						return
					_fail("No fresh challenge passed the checks within the search limit. Try again or choose another difficulty.",
						"За отведённый поиск новая задача не прошла проверку. Повторите попытку или выберите другую сложность.")
					return
				var family := _current_family
				var seed_value := ELPuzzleGenerator.seed_for_family(_profile, _difficulty, family)
				_proposals += 1
				_family_proposals += 1
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_value
				var candidate := ELPuzzleRecipes.build(_profile, family, int(rng.randi() & 0x7fffffff), _difficulty)
				var eligible := not candidate.is_empty()
				if eligible: eligible = not _signatures.has(ELPuzzleGenerator.tactical_signature(candidate))
				var plan := ELPuzzleGenerator.plan_signature(_profile, candidate) if eligible else ""
				if eligible: eligible = not plan.is_empty()
				var decision := ELPuzzleGenerator.decision_signature(_profile, candidate) if eligible else ""
				if eligible: eligible = not decision.is_empty()
				if eligible:
					var metadata: Dictionary = candidate.generated.duplicate()
					metadata.plan_signature = plan
					metadata.decision_signature = decision
					var inventory := ELPuzzleGenerator.spell_inventory(_profile, candidate)
					metadata.spell_roles = inventory.roles
					metadata.spell_cards = inventory.cards
					var preview := {"seed": seed_value, "family": family, "preferred": _preferred_variants.duplicate(),
						"score": _preference(metadata, _preferred_variants), "novel": _novel_decision(metadata)}
					if _preview_fallback.is_empty() or int(preview.score) > int(_preview_fallback.score): _preview_fallback = preview
					if preview.novel and String(metadata.get("variant", "base")) in _preferred_variants: _start_preview(preview)
				if _job == null and _family_proposals >= PREVIEWS_PER_FAMILY:
					if not _preview_fallback.is_empty() and _preview_fallback.novel:
						_start_preview(_preview_fallback)
					else:
						_advance_family()
			remaining -= 1
			if Time.get_ticks_usec() >= until: return

	func _fail(english: String, russian: String) -> void:
		progress_text = _text(english, russian)
		result = {"entry": {}, "error": progress_text, "nodes": _total_nodes,
			"elapsed_ms": (Time.get_ticks_usec() - _began) / 1000.0, "last_error": _last_error,
			"variety": {"previews": _proposals, "proof_jobs": _proofs,
				"proof_node_limit": NODE_BUDGET_MULTIPLIER * ELPuzzleGenerator.node_limit(_difficulty)}}
		done = true

	func _text(english: String, russian: String) -> String:
		return russian if _profile != null and ELRemakeText.language(_profile) == "ru" else english

## An equivalence key for diversity checks. Ignores seed, entity identifiers,
## presentation and hand order, while retaining the actual tactical material.
## This is deliberately separate from the exact position hash used in proofs.
static func tactical_signature(entry: Dictionary) -> String:
	var state: Dictionary = entry.get("state", {})
	var heroes: Array = []
	for hero: Dictionary in state.get("heroes", []):
		var hand: Array = hero.get("hand", []).duplicate()
		hand.sort()
		heroes.append({"health": hero.get("health"), "mana": hero.get("mana"),
			"channels": hero.get("channels"), "level": hero.get("level"),
			"hand": hand, "grave": hero.get("grave", []), "skills": hero.get("skills", {}),
			"enchantments": _marks(hero.get("enchantments", []))})
	var creatures: Array = []
	var roles := {}
	for id: Variant in state.get("creatures", {}):
		var creature: Dictionary = state.creatures[id]
		var role := {"card": creature.get("card"), "owner": creature.get("owner"),
			"power": creature.get("power"), "toughness": creature.get("toughness"),
			"damage": creature.get("damage"), "resting": creature.get("resting"),
			"sick": creature.get("sick"), "flags": creature.get("flags", []),
			"enchantments": _marks(creature.get("enchantments", []))}
		var encoded := JSON.stringify(role)
		roles[int(id)] = encoded
		creatures.append(encoded)
	creatures.sort()
	var attackers: Array = []
	for id: Variant in state.get("attacks", []): attackers.append(roles.get(int(id), ""))
	attackers.sort()
	var blocks: Array = []
	for id: Variant in state.get("blocks", {}):
		blocks.append([roles.get(int(id), ""), roles.get(int(state.blocks[id]), "")])
	blocks.sort_custom(func(a: Array, b: Array) -> bool: return JSON.stringify(a) < JSON.stringify(b))
	return JSON.stringify({"edition": state.get("profile"),
		"turns": entry.get("turns"), "objective": entry.get("objective", {"type": "win"}),
		"phase": state.get("phase"), "attacker": state.get("attacker"),
		"heroes": heroes, "creatures": creatures, "attacks": attackers, "blocks": blocks}).sha256_text()

static func _marks(enchantments: Array) -> Array:
	var out: Array = []
	for mark: Dictionary in enchantments:
		var value := mark.duplicate(true)
		value.erase("id")
		out.append(JSON.stringify(value))
	out.sort()
	return out

## Randomize presentation after the tactical construction, so a learnt screen
## slot is not a solution. These permutations never count as tactical novelty.
static func _shuffle_layout(entry: Dictionary, seed_value: int, profile: ELProfile) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x51a7c3
	var state: Dictionary = entry.state
	var order: Array = state.creatures.keys()
	_shuffle(order, rng)
	var remap := {}
	for index in order.size(): remap[int(order[index])] = index + 2
	var creatures := {}
	for old_id: Variant in order:
		var creature: Dictionary = state.creatures[old_id]
		creature.id = remap[int(old_id)]
		creatures[str(creature.id)] = creature
	state.creatures = creatures
	for index in state.attacks.size(): state.attacks[index] = remap.get(int(state.attacks[index]), int(state.attacks[index]))
	var blocks := {}
	for id: Variant in state.blocks:
		blocks[str(remap.get(int(id), int(id)))] = remap.get(int(state.blocks[id]), int(state.blocks[id]))
	state.blocks = blocks
	for body: Dictionary in state.heroes + state.creatures.values():
		for mark: Dictionary in body.get("enchantments", []):
			if mark.has("link"): mark.link = remap.get(int(mark.link), int(mark.link))
			for index in mark.get("exempt", []).size(): mark.exempt[index] = remap.get(int(mark.exempt[index]), int(mark.exempt[index]))
	for raw: Dictionary in entry.get("solution", []): _remap_command(raw, remap, profile)
	for refutation: Dictionary in entry.get("refutations", []):
		for raw: Dictionary in refutation.get("commands", []): _remap_command(raw, remap, profile)
	# Recipes refer to spells by card, not mutable hand indices. Preserve that
	# contract; an externally supplied indexed reference would not be shuffled.
	var indexed := false
	for raw: Dictionary in entry.get("solution", []):
		if raw.get("kind") == "cast" and raw.has("index"): indexed = true
	if indexed: return
	for hero: Dictionary in state.heroes:
		var slots: Array = range(hero.hand.size())
		_shuffle(slots, rng)
		var hand: Array = []
		var hand_slots: Array = []
		for index: int in slots:
			hand.append(hero.hand[index])
			hand_slots.append(hero.hand_slots[index])
		hero.hand = hand
		hero.hand_slots = hand_slots
		hero.hand_view = range(hand.size())

static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var at := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[at]
		values[at] = previous

static func _remap_command(command: Dictionary, ids: Dictionary, profile: ELProfile) -> void:
	for field: String in ["id", "target"]:
		if command.has(field) and ids.has(int(command[field])): command[field] = ids[int(command[field])]
	# The overloaded selector fields are not always grave/enchantment IDs.
	# Trade Creatures uses `grave` as its second creature; hero Combine,
	# Burnout and Ether Recycling use `choice`. Preserve actual grave slots,
	# enchantment-copy IDs and scalar X amounts instead of blindly remapping.
	if command.get("kind") == "cast" and ELCatalog.rule(profile, String(command.get("card", ""))).get("effect") == "swap":
		if ids.has(int(command.get("grave", -1))): command.grave = ids[int(command.grave)]
	elif command.get("kind") == "ability":
		var base := String(command.get("key", "")).get_slice(":", 0)
		for rule: Dictionary in ELCatalog.HERO_ABILITIES.values():
			if rule.get("key") == base and (rule.has("second") or base == "combine"):
				if ids.has(int(command.get("choice", -1))): command.choice = ids[int(command.choice)]
				break

## Check both recipe instructions and solver witnesses through the normal
## runtime observer, without writing progress or disturbing combat AI caches.
static func replay_line(profile: ELProfile, entry: Dictionary, commands: Array) -> Dictionary:
	var run := ELPuzzles.Run.new()
	if commands.is_empty() or not run.begin_entry(profile, entry, false, false):
		return {"ok": false, "error": "Cannot start the reference line.", "tactics": 0}
	var tactics := 0
	for raw: Dictionary in commands:
		if not run.outcome.is_empty() or int(raw.get("side", run.duel.active_side())) != run.duel.active_side():
			return {"ok": false, "error": "Reference side or terminal mismatch.", "tactics": tactics}
		var command := ELPuzzleProof.command(run.duel, raw)
		# Execution accepts a few degenerate abilities that the ordinary UI
		# disables (for example an empty-grave Plague). A playable
		# recipe reference and principal line must not depend on those actions.
		if run.duel.active_side() == 0 and command.get("kind") == "ability" and not run.duel.can_use_ability(int(command.get("id", -1)), String(command.get("key", ""))):
			return {"ok": false, "error": "The suggested ability is not available in the battle interface.", "tactics": tactics}
		if run.duel.active_side() == 0 and command.get("kind") in ["cast", "ability"]: tactics += 1
		if not ELCombatSearch.apply(run.duel, command):
			return {"ok": false, "error": run.duel.error, "tactics": tactics}
		run.watch()
	return {"ok": run.outcome == "solved", "outcome": run.outcome, "tactics": tactics, "turns": run.turn}

## A mistake may commit the player's opening attack, but cannot prescribe an
## opponent's cooperation. Preserve the original runtime deadline when a phase
## boundary makes the resulting position start during the opponent's turn.
static func mistake_position(profile: ELProfile, entry: Dictionary, commands: Array) -> Dictionary:
	if commands.is_empty() or commands.size() > 32: return {"ok": false}
	var attempt := ELPuzzles.Run.new()
	if not attempt.begin_entry(profile, entry, false, false): return {"ok": false}
	attempt.duel.searching = true
	for raw: Dictionary in commands:
		if not attempt.outcome.is_empty() or attempt.duel.active_side() != 0:
			return {"ok": false}
		if raw.get("kind") not in ["cast", "ability", "attack", "block", "end_phase"]:
			return {"ok": false}
		if not ELPuzzleProof.apply(attempt.duel, raw): return {"ok": false}
		attempt.watch()
	if not attempt.outcome.is_empty():
		return {"ok": attempt.outcome == "failed", "terminal_loss": attempt.outcome == "failed"}
	var completed := attempt.turn - (1 if attempt.duel.attacker == 0 else 0)
	var remaining := attempt.allowed - completed
	# The ordinary schema starts at one allowed own turn. Promoting zero to
	# one would wrongly give a doomed continuation another full player turn.
	if remaining < 1: return {"ok": false}
	var altered := entry.duplicate(true)
	altered.state = attempt.duel.snapshot()
	altered.state.setup.erase("puzzle_goal")
	altered.turns = remaining
	altered.erase("solution")
	return {"ok": true, "terminal_loss": false, "remaining_own_turns": remaining, "entry": altered}

class Job:
	extends RefCounted
	var done := false
	var result: Dictionary = {}
	var progress_text := ""
	var attempts := 0
	var rejections: Dictionary = {}
	var _profile: ELProfile
	var _seed := 0
	var _difficulty := 3
	var _family := ""
	var _rng := RandomNumberGenerator.new()
	var _candidate: Dictionary = {}
	var _proof: RefCounted
	var _stage := "candidate"
	var _win: Dictionary = {}
	var _shortcut: Dictionary = {}
	var _horizon: Dictionary = {}
	var _trap: Dictionary = {}
	var _trap_index := 0
	var _began := 0
	var _total_nodes := 0
	var _seen := {}

	func _start(profile: ELProfile, seed_value: int, difficulty: int, preferred_family: String) -> void:
		_profile = profile
		_seed = seed_value
		_difficulty = difficulty
		_began = Time.get_ticks_usec()
		if profile == null or profile.id not in ["el1", "el2"] or difficulty not in ELPuzzleGenerator.DIFFICULTIES or seed_value < 1 or seed_value > ELPuzzleGenerator.MAX_SEED:
			_finish_error("Invalid random challenge settings.", "Неверные параметры случайной задачи.")
			return
		_family = ELPuzzleGenerator.family_for_seed(profile.id, seed_value, difficulty)
		if _family.is_empty() or (not preferred_family.is_empty() and preferred_family != _family):
			_finish_error("This seed does not select the requested puzzle family.", "Этот код не соответствует выбранному типу задачи.")
			return
		_rng.seed = seed_value
		progress_text = _text("Building a tactical position…", "Создание тактической позиции…")

	## A time slice limits UI work; only deterministic node/depth limits affect
	## acceptance. Dropping this job cancels it without threads or global state.
	func step(node_quota := 32, usec_budget := 6000) -> void:
		if done: return
		var until := Time.get_ticks_usec() + maxi(usec_budget, 1)
		var remaining := maxi(node_quota, 1)
		while not done and remaining > 0:
			if _proof != null:
				_proof.step(remaining, maxi(1, until - Time.get_ticks_usec()))
				if not _proof.done: return
				var answer: Dictionary = _proof.result
				_total_nodes += int(answer.get("nodes", 0))
				_proof = null
				if _stage == "win":
					if answer.get("status") != "forced":
						_reject("win_" + str(answer.get("status", "invalid")))
					elif _difficulty == 5 and int(answer.get("strategy", {}).get("max_enemy_decisions", 0)) < 1:
						_reject("no_enemy_decision")
					else:
						_win = answer
						_stage = "difficulty"
						progress_text = _text("Checking for easier solutions…", "Проверка более простых решений…")
						if not _budget_finished(): _proof = ELPuzzleProof.start(_profile, _candidate, _limits(_difficulty - 2))
				elif _stage == "difficulty":
					if answer.get("status") != "refuted":
						_reject("shortcut_" + str(answer.get("status", "invalid")))
					else:
						_shortcut = answer
						if int(_candidate.turns) == 2:
							_stage = "horizon"
							progress_text = _text("Checking that the second turn matters…", "Проверка необходимости второго хода…")
							var shorter := _candidate.duplicate(true)
							shorter.turns = 1
							if not _budget_finished(): _proof = ELPuzzleProof.start(_profile, shorter, _limits())
						else:
							_begin_traps()
				elif _stage == "horizon":
					if answer.get("status") != "refuted":
						_reject("short_horizon_" + str(answer.get("status", "invalid")))
					else:
						_horizon = answer
						_begin_traps()
				elif _stage == "trap":
					if answer.get("status") == "refuted":
						_trap.proof = {"status": "refuted", "nodes": answer.get("nodes", 0)}
						_accept(_shortcut)
					else:
						_start_trap()
			else:
				_candidate_step()
			remaining -= 1
			if Time.get_ticks_usec() >= until: return

	func _candidate_step() -> void:
		if _budget_finished(): return
		if attempts >= ELPuzzleGenerator.MAX_ATTEMPTS:
			_finish_error("No challenge passed the checks within the search limit. Try another seed or difficulty.",
				"За отведённый поиск задача не прошла проверку. Попробуйте другой код или сложность.")
			return
		attempts += 1
		var candidate_seed := int(_rng.randi() & 0x7fffffff)
		_candidate = ELPuzzleRecipes.build(_profile, _family, candidate_seed, _difficulty)
		if _candidate.is_empty() or not ELPuzzles.valid_entry(_candidate, _profile.id):
			_reject("recipe_invalid")
			return
		if int(_candidate.turns) > 2 or (_difficulty == 5 and int(_candidate.turns) != 2) or _candidate.get("objective", {"type": "win"}) != {"type": "win"}:
			_reject("unsupported_goal")
			return
		ELPuzzleGenerator._shuffle_layout(_candidate, candidate_seed, _profile)
		var recipe_meta: Dictionary = _candidate.get("generated", {}).duplicate(true)
		recipe_meta.merge({"version": ELPuzzleGenerator.VERSION, "seed": _seed,
			"candidate_seed": candidate_seed, "difficulty": _difficulty, "family": _family,
			"code": ELPuzzleGenerator.code(_profile.id, _difficulty, _seed)}, true)
		_candidate.generated = recipe_meta
		_candidate.id = "random_v%d_%s_%d_%d" % [ELPuzzleGenerator.VERSION, _profile.id, _difficulty, _seed]
		_candidate.level = _difficulty
		if not ELPuzzleGenerator.replay_line(_profile, _candidate, _candidate.get("solution", [])).ok:
			_reject("recipe_reference_failed")
			return
		var signature := ELPuzzleGenerator.tactical_signature(_candidate)
		if _seen.has(signature):
			_reject("duplicate_candidate")
			return
		_seen[signature] = true
		_candidate.generated.tactical_signature = signature
		_candidate.generated.plan_signature = ELPuzzleGenerator.plan_signature(_profile, _candidate)
		_candidate.generated.decision_signature = ELPuzzleGenerator.decision_signature(_profile, _candidate)
		var inventory := ELPuzzleGenerator.spell_inventory(_profile, _candidate)
		_candidate.generated.spell_roles = inventory.roles
		_candidate.generated.spell_cards = inventory.cards
		if String(_candidate.generated.decision_signature).is_empty():
			_reject("decision_reference_failed")
			return
		_stage = "win"
		progress_text = _text("Checking every legal defence… (%d/%d)", "Проверка всех вариантов защиты… (%d/%d)") % [attempts, ELPuzzleGenerator.MAX_ATTEMPTS]
		_proof = ELPuzzleProof.start(_profile, _candidate, _limits())

	func _limits(max_tactics := -1) -> Dictionary:
		var limit := 4000 if _stage == "win" else (10000 if _difficulty >= 4 else 6000)
		if _difficulty == 5: limit = 18000 if _stage == "win" else (12000 if _stage == "horizon" else 20000)
		return {"budget": mini(limit, maxi(1, ELPuzzleGenerator.node_limit(_difficulty) - _total_nodes)),
			"depth": 24 if int(_candidate.get("turns", 1)) == 1 else 44,
			"max_tactics": max_tactics}

	func _budget_finished() -> bool:
		if _total_nodes < ELPuzzleGenerator.node_limit(_difficulty): return false
		_finish_error("No challenge passed the checks within the search limit. Try another seed or difficulty.",
			"За отведённый поиск задача не прошла проверку. Попробуйте другой код или сложность.")
		return true

	func _reject(reason: String) -> void:
		rejections[reason] = int(rejections.get(reason, 0)) + 1
		_stage = "candidate"
		_proof = null
		_candidate = {}
		_win = {}
		_shortcut = {}
		_horizon = {}
		_trap = {}
		_trap_index = 0

	func _begin_traps() -> void:
		_stage = "trap"
		progress_text = _text("Checking a tempting mistake…", "Проверка заманчивой ошибки…")
		_start_trap()

	## A recipe's wrong idea is only a hypothesis. It must be a legal prefix
	## whose continuation cannot force victory, not an unsupported solver miss.
	func _start_trap() -> void:
		if _budget_finished(): return
		var hypotheses: Array = _candidate.get("refutations", [])
		while _trap_index < mini(hypotheses.size(), 3):
			_trap = hypotheses[_trap_index].duplicate(true)
			_trap_index += 1
			var continuation := ELPuzzleGenerator.mistake_position(_profile, _candidate, _trap.get("commands", []))
			if not continuation.get("ok", false): continue
			if continuation.get("terminal_loss", false):
				_trap.proof = {"status": "refuted", "nodes": 0, "terminal_loss": true}
				_accept(_shortcut)
				return
			_trap.remaining_own_turns = continuation.remaining_own_turns
			_proof = ELPuzzleProof.start(_profile, continuation.entry, _limits())
			return
		_reject("no_proven_mistake")

	func _accept(shortcut: Dictionary) -> void:
		var witness: Array = _win.get("witness", [])
		# A search proof and a runtime replay are independent gates: replay uses
		# Run's normal settled-action observer with no progress or AI-cache writes.
		var replay := ELPuzzleGenerator.replay_line(_profile, _candidate, witness)
		var tactics := int(replay.tactics)
		# A cooperative reply may shorten this one witness. The separately
		# refuted tactic cap is the guarantee over all enemy responses.
		if not replay.ok:
			_reject("witness_not_solved")
			return
		_candidate.generated.recipe_solution = _candidate.solution.duplicate(true)
		_candidate.solution = witness.duplicate(true)
		# Only retain refutations that were actually certified for this variant.
		_candidate.refutations = [_trap.duplicate(true)]
		_candidate.generated.verification = {"forced_win": true, "runtime_replay": true, "recipe_reference_replay": true,
			"reference_and_witness_playable": true,
			"guaranteed_strategy_tactic_floor": _difficulty - 1, "witness_tactical_actions": tactics,
			"guaranteed_strategy_turn_floor": 2 if int(_candidate.turns) == 2 else (1 if int(_candidate.state.attacker) == 0 else 0),
			"witness_player_turns": replay.get("turns", 0),
			"short_horizon_status": _horizon.get("status", "not_applicable"), "short_horizon_nodes": _horizon.get("nodes", 0),
			"strategy": _win.get("strategy", {}).duplicate(true),
			"win_nodes": _win.get("nodes", 0), "shortcut_nodes": shortcut.get("nodes", 0),
			"shortcut_status": shortcut.get("status"), "meaningful_mistake": _trap.duplicate(true), "depth": _limits().depth,
			"position_hash": JSON.stringify({"state": _candidate.state, "turns": _candidate.turns,
				"objective": _candidate.get("objective", {"type": "win"})}, "", false).sha256_text()}
		result = {"entry": _candidate, "error": "", "code": _candidate.generated.code,
			"attempts": attempts, "rejections": rejections.duplicate(), "nodes": _total_nodes,
			"elapsed_ms": (Time.get_ticks_usec() - _began) / 1000.0}
		progress_text = _text("Challenge verified.", "Задача проверена.")
		done = true

	func _finish_error(english: String, russian: String) -> void:
		result = {"entry": {}, "error": _text(english, russian), "code": "" if _profile == null else ELPuzzleGenerator.code(_profile.id, _difficulty, _seed),
			"attempts": attempts, "rejections": rejections.duplicate(), "nodes": _total_nodes,
			"elapsed_ms": (Time.get_ticks_usec() - _began) / 1000.0}
		progress_text = String(result.error)
		done = true

	func _text(english: String, russian: String) -> String:
		return russian if _profile != null and ELRemakeText.language(_profile) == "ru" else english
