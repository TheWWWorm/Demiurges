class_name ELBattleScripts
extends RefCounted
## Second-game battle scripts: a mob's `Script=` chunk and battleground building
## chunks run in independent Lua states, one per (script, side), during a duel.
## The first game has no duel scripts.
##
## Hooks are bound when the chunk loads; return values are ignored. Casts, added
## cards and ether changes are queued and resolve in order before the acting
## side's next decision; everything else acts at once inside the hook.

## The hook table in dispatch order. CHook_OnCreatureCast is not in it.
const HOOKS := ["CHook_BeginMyTurn", "CHook_BeginEnemyTurn", "CHook_OnLogicSummon", "CHook_OnVisualCreatureDeath",
	"CHook_OnVisualPostSpellCast", "CHook_OnVisualHeroDeath", "CHook_OnVisualSummon", "CHook_OnVisualRemoveEnchantment",
	"CHook_OnVisualStartMeleeDestroyFlag", "CHook_OnVisualFinishMeleeDestroyFlag", "CHook_OnVisualStartEnchantmentEndOfTurn",
	"CHook_OnVisualFinishEnchantmentEndOfTurn", "CHook_OnVisualCreatureUseAbility"]
## The 26 natives of a battle state.
const NATIVES := ["ExClearVariables", "ExGetVariable", "ExSetVariable", "ExMessageToScreen", "ExGetTextByID", "ExCastSpell",
	"ExCastSpellWithEffects", "ExAddSpellToHand", "ExAddMana", "ExGetDifficultyLevel", "ExGetNewCreatureBaseStat",
	"ExSetNewCreatureBaseStat", "ExGetManalinks", "ExSetManalinks", "ExAddPlayerDamage", "ExPlayEffect", "ExGetHandSize",
	"ExGetPlayerHealth", "ExGetPlayerMana", "ExGetGraveyardSize", "ExGetPlayerArmySize", "ExGetPlayerLevel",
	"ExGetPlayerOriginalLevel", "ExGetGraveyardCode", "ExGetSpellClass", "ExGetSyncRandom"]
## Base stat vector indices (creature) that map to remake creature flags.
const STAT_FLAGS := {2: "Fly", 3: "FS", 4: "NoAttack", 6: "Trample", 7: "Destroy", 8: "Lifetap", 11: "Disenchant",
	13: "UB", 14: "TeamAttack", 15: "Restless", 16: "NoUntap", 17: "Berserk", 20: "NSS", 21: "NoTarget", 23: "Outerplanar"}
const OPS := ["cast", "cast_fx", "add_card", "set_mana"]
const DRAIN_LIMIT := 200
const NO_COMBAT := "Can not use outside of combat."
const NO_CREATURE := "Can not use outside of hook Hook_OnCreatureCast."

## Loaded states in registration order: {name, side, vm, hooks: {hook: closure}}.
var states: Array[Dictionary] = []
## Pending script actions: {op, side, card, targets, value}.
var queue: Array[Dictionary] = []
## The creature being summoned while summon hooks run, or -1.
var new_creature := -1
## Set at the first turn start; duel natives refuse to act before it.
var in_combat := false
## Mission variables when the duel is not a campaign encounter.
var local_variables: Dictionary = {}
## ExGetDifficultyLevel outside a campaign (0 easy, 1 normal, 2 hard).
var difficulty := 1
## Diagnostics: missing chunks, script errors, dropped or unsupported casts.
var notes: Array[String] = []
var draining := false
## Verification chunks by `chunk_path`, consulted before the scripts archive.
static var fixtures: Dictionary = {}
var _duel: WeakRef
var _running: Dictionary = {}

func _init(owner: ELDuel) -> void:
	_duel = weakref(owner)

func duel() -> ELDuel:
	return _duel.get_ref()

func active() -> bool:
	return not states.is_empty() or not queue.is_empty()

## Loads each {name, side} entry and runs its CHook_Init. A missing chunk is
## skipped like the original archive lookup failure.
func load_all(entries: Array) -> void:
	for entry: Dictionary in entries:
		var state := _open(str(entry.name), int(entry.side))
		if state.is_empty(): continue
		states.append(state)
		var init: Variant = state.vm.globals.get("CHook_Init")
		if init is ELLuaVM.Closure: _call(state, init, [])

func close() -> void:
	for state: Dictionary in states: state.vm.clear()
	states.clear()
	queue.clear()

## `name` resolves like the original: the attribute value plus ".sobj" in the
## scripts archive, case-insensitive.
static func chunk_path(name: String) -> String:
	return ELArchive.key(name.strip_edges()) + ".sobj"

func _open(name: String, side: int) -> Dictionary:
	var d := duel()
	var bytes: PackedByteArray = fixtures.get(chunk_path(name), PackedByteArray())
	if bytes.is_empty() and not name.strip_edges().is_empty(): bytes = d.profile.read("scripts", chunk_path(name))
	if bytes.is_empty():
		notes.append("Battle script %s is not in the scripts archive; skipped." % name)
		return {}
	var vm := ELLuaVM.new()
	vm.globals["exMe"] = float(side)
	vm.globals["exEnemy"] = float(1 - side)
	for native: String in NATIVES: vm.bind(native, _native.bind(native))
	var state := {"name": name, "side": side, "vm": vm, "hooks": {}, "depth": 0}
	var previous := _running
	_running = state
	var loaded := vm.load_script(bytes, name)
	_running = previous
	if not loaded:
		notes.append("Battle script %s failed to load: %s" % [name, vm.error])
		vm.clear()
		return {}
	for hook: String in HOOKS:
		if vm.globals.get(hook) is ELLuaVM.Closure: state.hooks[hook] = vm.globals[hook]
	return state

func _call(state: Dictionary, function: Variant, arguments: Array) -> void:
	var vm: ELLuaVM = state.vm
	var previous := _running
	_running = state
	state.depth += 1
	# A hook reached again from inside its own state keeps the outer budget.
	if state.depth == 1: vm._begin()
	vm._invoke(function, arguments)
	state.depth -= 1
	if state.depth == 0 and not vm.error.is_empty():
		# The original logs hook errors and the battle continues.
		notes.append("Battle script %s (side %d): %s" % [state.name, state.side, vm.error])
		vm.error = ""
	_running = previous

func dispatch(hook: String, arguments: Array) -> void:
	for state: Dictionary in states.duplicate():
		if state.hooks.has(hook): _call(state, state.hooks[hook], arguments)

## Turn starts go only to states whose own or enemy player starts the turn.
func turn_start(side: int, turn: int) -> void:
	in_combat = true
	for state: Dictionary in states.duplicate():
		var hook := "CHook_BeginMyTurn" if int(state.side) == side else "CHook_BeginEnemyTurn"
		if state.hooks.has(hook): _call(state, state.hooks[hook], [float(turn)])

## Logic then visual summon hooks, with the new creature's base stats open.
func summoned(side: int, card: String, id: int) -> void:
	if states.is_empty(): return
	var previous := new_creature
	new_creature = id
	dispatch("CHook_OnLogicSummon", [float(side), card, float(id)])
	dispatch("CHook_OnVisualSummon", [float(side), card, float(id)])
	new_creature = previous

## Pops queued actions until none remain; actions may raise hooks that queue more.
func drain() -> bool:
	if draining or queue.is_empty(): return false
	var d := duel()
	draining = true
	var count := 0
	while not queue.is_empty():
		if d.phase == ELDuel.Phase.FINISHED:
			queue.clear()
			break
		if count >= DRAIN_LIMIT:
			notes.append("Battle script queue exceeded %d actions; the rest were dropped." % DRAIN_LIMIT)
			queue.clear()
			break
		count += 1
		_execute(queue.pop_front())
	draining = false
	return count > 0

func _execute(action: Dictionary) -> void:
	var d := duel()
	var side := int(action.side)
	match action.op:
		"cast", "cast_fx":
			if not d.cast_free(side, str(action.card), action.get("targets", []), action.op == "cast_fx"):
				notes.append("Script %s by side %d dropped: %s" % [action.card, side, d.error])
				d.error = ""
		"add_card":
			d._give_card(side, str(action.card))
			d._emit({"kind": "script_card", "side": side, "card": action.card})
		"set_mana":
			var delta := int(action.value) - int(d.heroes[side].mana)
			d.heroes[side].mana = int(action.value)
			if delta != 0: d._emit({"kind": "ether", "side": side, "amount": delta, "script": true})

func _player(value: Variant) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or int(value) not in [0, 1]:
		_running.vm._fail("Incorrect player: %d" % (int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else -1))
		return -1
	return int(value)

func _integer(value: Variant) -> int:
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else 0

func _error(message: String) -> Array:
	_running.vm._fail(message)
	return []

func _variables(args: Array, name: String) -> Array:
	var session: Variant = duel().adventure_session()
	if session != null and session.variables != null: return session._native(args, name)
	var first: Variant = args[0] if not args.is_empty() else null
	match name:
		"ExClearVariables": local_variables.clear()
		"ExGetVariable": return [local_variables.get(first)]
		"ExSetVariable":
			if args.size() >= 2 and first != null:
				var value: Variant = args[1]
				if value is float: value = float(int(value))
				if value == null: local_variables.erase(first)
				elif typeof(value) in [TYPE_FLOAT, TYPE_STRING]: local_variables[first] = value
	return []

func _native(args: Array, name: String) -> Array:
	var d := duel()
	var first: Variant = args[0] if not args.is_empty() else null
	match name:
		"ExClearVariables", "ExGetVariable", "ExSetVariable": return _variables(args, name)
		"ExMessageToScreen":
			d._emit({"kind": "script_notice", "text": str(first)})
			return []
		"ExGetTextByID": return [d.profile.text(str(first))]
		"ExGetDifficultyLevel":
			var session: Variant = d.adventure_session()
			return [float(clampi(int(session.difficulty) if session != null else difficulty, 0, 2))]
	if not in_combat: return _error(NO_COMBAT)
	match name:
		"ExCastSpell", "ExCastSpellWithEffects", "ExAddSpellToHand":
			if args.size() < 2: return _error("Not enough arguments.")
			var side := _player(first)
			if side < 0: return []
			var card := str(args[1])
			if not d.profile.table("CombatSpells").has(card): return _error("Unknown spell type")
			if name == "ExAddSpellToHand":
				queue.append({"op": "add_card", "side": side, "card": card})
				return []
			var targets: Array = []
			for value: Variant in args.slice(2): targets.append(_integer(value))
			queue.append({"op": "cast_fx" if name == "ExCastSpellWithEffects" else "cast", "side": side, "card": card, "targets": targets})
		"ExAddMana":
			var side := _player(first)
			# SetMana(mana at the call + n), applied when the action resolves.
			if side >= 0: queue.append({"op": "set_mana", "side": side, "value": int(d.heroes[side].mana) + _integer(args[1] if args.size() > 1 else 0)})
		"ExGetNewCreatureBaseStat", "ExSetNewCreatureBaseStat":
			if new_creature < 0 or not d.creatures.has(new_creature): return _error(NO_CREATURE)
			var index := _integer(first)
			if index < 0 or index > 26: return _error("Incorrect stat index: %d" % index)
			if name == "ExGetNewCreatureBaseStat": return [float(base_stat(d, new_creature, index))]
			set_base_stat(d, new_creature, index, _integer(args[1] if args.size() > 1 else 0))
		"ExGetManalinks":
			var side := _player(first)
			if side >= 0: return [float(d.heroes[side].channels)]
		"ExSetManalinks":
			var side := _player(first)
			if side >= 0: d.script_channels(side, maxi(0, _integer(args[1] if args.size() > 1 else 0)))
		"ExAddPlayerDamage":
			var side := _player(first)
			var amount := _integer(args[1] if args.size() > 1 else 0)
			if side >= 0 and amount > 0: d.script_damage(side, amount, clampi(_integer(args[2] if args.size() > 2 else 0), 0, 2))
		"ExPlayEffect":
			d._emit({"kind": "script_effect", "effect": str(first), "target": _integer(args[1] if args.size() > 1 else -1), "attach": str(args[2]) if args.size() > 2 else ""})
		"ExGetHandSize", "ExGetPlayerHealth", "ExGetPlayerMana", "ExGetGraveyardSize", "ExGetPlayerArmySize", "ExGetPlayerLevel", "ExGetPlayerOriginalLevel":
			var side := _player(first)
			if side < 0: return []
			var hero: Dictionary = d.heroes[side]
			match name:
				"ExGetHandSize": return [float(hero.hand.size())]
				"ExGetPlayerHealth": return [float(hero.health)]
				"ExGetPlayerMana": return [float(hero.mana)]
				"ExGetGraveyardSize": return [float(hero.grave.size())]
				"ExGetPlayerArmySize": return [float(d.army(side).size())]
				_: return [float(hero.level)]
		"ExGetGraveyardCode":
			var side := _player(first)
			if side < 0: return []
			var index := _integer(args[1] if args.size() > 1 else -1)
			if index < 0 or index >= d.heroes[side].grave.size():
				_running.vm._fail("Incorrect graveyard index: %d" % index)
				return [""]
			return [d.heroes[side].grave[index]]
		"ExGetSpellClass":
			var row: Dictionary = d.profile.table("CombatSpells").get(str(first), {})
			if row.is_empty(): return _error("Unknown spell type")
			return [str(row.get("Class", ""))]
		"ExGetSyncRandom":
			var low := _integer(first)
			var high := _integer(args[1] if args.size() > 1 else low)
			# The duel's synchronised generator, so scripts share its stream.
			return [float(low + d.random_index(high - low + 1))]
	return []

## Base stat vector: power and toughness, flag indices as 0/1, Discard and Regen counts.
static func base_stat(d: ELDuel, id: int, index: int) -> int:
	var c: Dictionary = d.creatures[id]
	var row: Dictionary = d.profile.table("CombatCreatures")[c.card]
	match index:
		0: return int(c.base[0]) if c.has("base") else int(row.Power)
		1: return int(c.base[1]) if c.has("base") else int(row.Toughness)
		9, 10:
			var prefix := "Discard(" if index == 9 else "Regen("
			for flag: String in c.flags:
				if flag.begins_with(prefix): return int(flag.trim_prefix(prefix).trim_suffix(")"))
			return 0
	return 1 if STAT_FLAGS.has(index) and c.flags.has(STAT_FLAGS[index]) else 0

## Writes the new creature's base vector; the native itself does not clamp.
static func set_base_stat(d: ELDuel, id: int, index: int, value: int) -> void:
	var c: Dictionary = d.creatures[id]
	if index in [0, 1]:
		var row: Dictionary = d.profile.table("CombatCreatures")[c.card]
		var base: Array = c.base.duplicate() if c.has("base") else [int(row.Power), int(row.Toughness)]
		base[index] = value
		c.base = base
		c.script_base = true
		return
	var flags: Array = c.flags
	if index in [9, 10]:
		var prefix := "Discard(" if index == 9 else "Regen("
		for flag: String in flags.duplicate():
			if flag.begins_with(prefix): flags.erase(flag)
		if value > 0: flags.append(prefix + str(value) + ")")
		return
	if not STAT_FLAGS.has(index):
		# Indices without a remake meaning (12, 18, 19, 22, 24-26) are kept out of play.
		return
	var flag: String = STAT_FLAGS[index]
	if value != 0 and not flags.has(flag): flags.append(flag)
	elif value == 0: flags.erase(flag)
	if index == 2: c.flying = flags.has("Fly")
	if index == 20: c.sick = not flags.has("NSS")

## Saved script state: each state's name, side and globals, plus the queue.
func snapshot() -> Dictionary:
	var saved: Array = []
	for state: Dictionary in states:
		saved.append({"name": state.name, "side": state.side, "globals": ELLuaSave.new().encode(state.vm)})
	return {"version": 1, "in_combat": in_combat, "difficulty": difficulty, "states": saved, "queue": queue.duplicate(true), "variables": local_variables.duplicate()}

## Structure check at the save boundary (ELMatchSave); `restore` loads chunks.
static func valid(profile: ELProfile, raw: Variant) -> bool:
	if raw is not Dictionary or raw.get("version") != 1 or raw.get("in_combat") is not bool or raw.get("states") is not Array or raw.get("queue") is not Array or raw.get("variables") is not Dictionary: return false
	if profile.id != "el2" or raw.get("difficulty") not in [0, 1, 2] or raw.states.size() > 32 or raw.queue.size() > DRAIN_LIMIT: return false
	for state: Variant in raw.states:
		if state is not Dictionary or state.get("name") is not String or state.get("side") not in [0, 1] or state.get("globals") is not Dictionary: return false
	for action: Variant in raw.queue:
		if action is not Dictionary or action.get("op") not in OPS or action.get("side") not in [0, 1]: return false
		if action.op == "set_mana" and action.get("value") is not int: return false
		if action.op != "set_mana" and (action.get("card") is not String or not profile.table("CombatSpells").has(action.card)): return false
		if action.op in ["cast", "cast_fx"] and (action.get("targets") is not Array or action.targets.size() > 8 or action.targets.any(func(t: Variant) -> bool: return t is not int)): return false
	for key: Variant in raw.variables:
		if key is not String or typeof(raw.variables[key]) not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]: return false
	return true

## Reloads each chunk without CHook_Init and restores its globals. Returns an
## error message, or "" after replacing this object's state.
func restore(raw: Dictionary) -> String:
	var loaded: Array[Dictionary] = []
	for saved: Dictionary in raw.states:
		var state := _open(saved.name, int(saved.side))
		if state.is_empty():
			for other: Dictionary in loaded: other.vm.clear()
			return "A saved battle script is missing: " + str(saved.name)
		var decoder := ELLuaSave.new()
		if not decoder.decode(state.vm, saved.globals):
			state.vm.clear()
			for other: Dictionary in loaded: other.vm.clear()
			return "Invalid saved battle script %s: %s" % [saved.name, decoder.error]
		# Library constants come from the engine; JSON keeps only 15 digits.
		if state.vm.globals.get("PI") is float and absf(float(state.vm.globals.PI) - PI) < 0.000001: state.vm.globals.PI = PI
		loaded.append(state)
	close()
	states = loaded
	queue.clear()
	for action: Dictionary in raw.queue:
		var entry := action.duplicate(true)
		entry.side = int(entry.side)
		if entry.has("value"): entry.value = int(entry.value)
		if entry.has("targets"): entry.targets = entry.targets.map(func(t: Variant) -> int: return int(t))
		queue.append(entry)
	in_combat = raw.in_combat
	difficulty = int(raw.difficulty)
	local_variables = raw.variables.duplicate()
	for key: Variant in local_variables:
		if typeof(local_variables[key]) == TYPE_INT: local_variables[key] = float(local_variables[key])
	notes.clear()
	return ""

## Second-game battleground buildings (`Combat*` classes in AdditionalBuildings).
## The map's `params` text replaces the registry script name.
static func building_affect(profile: ELProfile, building: Dictionary) -> Dictionary:
	if profile.id != "el2" or building.get("group") != "additional_buildings": return {}
	var row: Dictionary = profile.table("AdditionalBuildings").get(str(building.get("name", "")), {})
	var kind := str(row.get("Class", ""))
	if kind not in ["CombatRange", "CombatTime", "CombatMission"]: return {}
	var script := str(ELXml.value(building.get("node", {}), "params")).strip_edges()
	if script.is_empty(): script = str(row.get("Script", ""))
	if script.is_empty(): return {}
	var affect := {"name": script, "id": "combat:%d" % int(building.get("uid", -1)), "script": script, "kind": {"CombatRange": "range", "CombatTime": "time", "CombatMission": "mission"}[kind], "building": int(building.get("uid", -1))}
	# A time affect counts down from 10.
	if affect.kind == "time": affect.ticks = 10
	return affect

## The actor's battleground affects in order: those granted by activation (time
## and mission entries in `affects`), then every CombatRange building within
## Euclidean distance 10 of the actor's position.
static func battle_affects(state: ELAdventureSession, actor: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in actor.get("affects", []):
		if entry is not Dictionary or str(entry.get("script", "")).is_empty(): continue
		if entry.get("kind") == "time" and int(entry.get("ticks", 0)) <= 0: continue
		if entry.get("kind") in ["time", "mission"]: result.append(entry)
	if not actor.has("x") or not actor.has("y"): return result
	for building: Dictionary in state.objects.values():
		if not building.get("alive", true): continue
		var affect := building_affect(state.map.profile, building)
		if affect.is_empty() or affect.kind != "range": continue
		var dx := int(actor.x) - int(building.get("x", 0))
		var dy := int(actor.y) - int(building.get("y", 0))
		if dx * dx + dy * dy <= 100: result.append(affect)
	return result

## Script load order for a battle: side 0's then side 1's mob script,
## then the hero script lists (the artifact tracker), then each side's battleground affects; a range affect is loaded again for
## the other side when that side is a monster.
static func select(state: ELAdventureSession, ids: Array) -> Array:
	var result: Array = []
	if state.map.profile.id != "el2": return result
	for side in 2:
		var script := str(state.object(ids[side]).get("battle_script", ""))
		if not script.is_empty(): result.append({"name": script, "side": side})
	# Player 1's heroes carry the artifact constructor's tracker in their hero
	# script list (hero, pushed by the hero constructor).
	for side in 2:
		var actor := state.object(ids[side])
		if actor.get("type") == "hero" and int(actor.get("owner", -1)) == 1: result.append({"name": ELSecondArtifacts.TRACKER, "side": side})
	for side in 2:
		var other := state.object(ids[1 - side])
		for affect: Dictionary in battle_affects(state, state.object(ids[side])):
			result.append({"name": str(affect.script), "side": side})
			if affect.kind == "range" and other.get("type") == "monster": result.append({"name": str(affect.script), "side": 1 - side})
	return result
