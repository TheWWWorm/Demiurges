class_name ELCombatSearch
extends RefCounted
## The combat opponent's decision: a budgeted lookahead over copies of the duel
## that plays the real rules. Each think returns one command, the first step of
## the best line; the opponent thinks again before its next command.
##
## Moves come in the original order: next phase (priority 1.1), the acting
## hero's hand spells and artifacts (opponent lines never cast), hero
## abilities, then the whole-army attack plan or the four block plans, then each
## creature's abilities and lone attack. Moves are tried by priority; a
## priority under 0.01 is never tried. Positions are scored with nine weights
## drawn from the battle's random sequence without advancing it.

const THRESHOLD := 0.01
const BUDGET := 1000

## Move flags.
const MOVE_FAILED := 1
const MOVE_NEXT := 2
const MOVE_ATTACK := 4
const MOVE_BLOCK := 8
const MOVE_CAST := 0x10
const MOVE_ABILITY := 0x20
const MOVE_ATTACK_PLAN := 0x40
const MOVE_UNLIKELY := 0x80
const MOVE_BLOCK_PLANS := 0x1e00
## Moves tried only after the plain ones of a position.
const MOVE_SECOND_PASS := 0x1e4c
## Line flags: a block plan allows only the next phase after it; one attack
## move per line.
const LINE_ONLY_NEXT := 2
const LINE_ATTACKED := 8

const BLOCK_PLANS := [[0x200, 0.999], [0x400, 0.995], [0x800, 0.997], [0x1000, 0.993]]

## Target-side requirements of hand spells: 1 own creature, 2 enemy creature,
## 4 own hero, 8 enemy hero, 0x10 the chosen enchantment must not be the
## caster's, 0x40 the second chosen enchantment must not be the caster's.
const SPELL_SIDES := {
	"el1": {"AILK": 1, "BLSS": 1, "BRRD": 10, "CLFR": 1, "CLIG": 10, "CLNP": 16, "DISM": 2, "DSIG": 2, "DWND": 2, "ENFL": 2,
		"ERBN": 2, "ETAM": 1, "ETTD": 64, "EXIL": 2, "FAIL": 2, "FLIC": 16, "IRRT": 2, "LSST": 1, "MDNS": 2, "MGHT": 1,
		"OVRL": 1, "PALN": 2, "PRFY": 16, "RDCL": 10, "RDIS": 10, "RDLG": 10, "RIFT": 10, "SCSK": 1, "SGHT": 1, "SHCL": 1,
		"SHSK": 1, "SLRP": 1, "SPBA": 1, "SPBR": 16, "SPRG": 2, "SPWR": 1, "STAT": 1, "STRG": 1, "TGSK": 1, "THIF": 1,
		"UPGD": 1, "WEAK": 2, "WHAS": 64, "WNBL": 1, "ZAPP": 10},
	"el2": {"AILK": 1, "ALNS": 1, "BLSS": 1, "BNSH": 2, "BRRD": 10, "CLFR": 1, "CLIG": 10, "CLNP": 16, "DISM": 2, "DSIG": 2,
		"DWND": 2, "ENBR": 5, "ENFL": 2, "ERBN": 2, "ETAM": 1, "ETTD": 64, "EXIL": 2, "FAIL": 2, "FLIC": 16, "IMMB": 2,
		"IRRT": 2, "LFGR": 5, "LSST": 1, "MDNS": 2, "MGHT": 1, "OBLS": 2, "OCLV": 2, "OCRP": 2, "ORFT": 2, "OVRL": 1,
		"PALN": 2, "PRFY": 16, "PRGD": 1, "PRWR": 10, "RDCL": 10, "RDIS": 10, "RDLG": 10, "RIFT": 10, "SCSK": 1, "SGHT": 1,
		"SHCL": 1, "SHSK": 1, "SLRP": 1, "SPBA": 1, "SPBR": 16, "SPRG": 2, "SPWR": 1, "STAT": 1, "STRG": 1, "STSK": 5,
		"TGSK": 1, "THIF": 1, "UPGD": 1, "WEAK": 2, "WHAS": 64, "WNBL": 1, "ZAPP": 10},
}

## Hero enchantment worth: per copy (EACH), once per kind (KIND), and by copy
## count (COUNT, see `_count_value`). Creature enchantments add only COUNT.
const EACH := {
	"el1": {"BASO": 1.0, "BLKD": 1.0, "FRBL": 1.0, "DOMN": 1.0, "ENWO": 1.0, "ENLH": 0.5, "ENVM": -1.0, "IMML": 0.75, "JYHD": 1.0,
		"LSDS": 1.0, "LSHE": 1.0, "MNTX": 1.0, "QKFX": 0.5, "RNST": 1.0, "SPLK": 1.0, "SPWB": 1.0, "STWO": 1.0, "SWSN": -1.0,
		"STTX": -3.0, "WETX": -1.0, "TRLB": -2.0, "TRSN": -1.0},
	"el2": {"QKFX": 0.5, "WETX": -1.0, "STTX": -3.0, "LSDS": 1.0, "MNTX": 1.0, "LSHE": 1.0, "SPWB": 1.0, "TRLB": -2.0, "STWO": 1.0,
		"ENWO": 1.0, "DOMN": 1.0, "ENVM": -1.0, "FRBL": 1.0, "RNST": 1.0, "JYHD": 1.0, "IMML": 0.75, "BLKD": 1.0, "BASO": 1.0,
		"OEXC": 0.75, "PRWT": 0.75, "PRWR": -0.75, "PRBN": 0.75, "PRGD": 0.75, "PLSL": 0.75, "LCWR": 0.75, "GCWR": 0.75,
		"LSWR": 0.75, "GSWR": 0.75, "LEWR": 0.75, "GEWR": 0.75, "OST1": 1.0, "OST2": 1.0, "OST3": 1.0, "TRSN": -1.0,
		"SWSN": -1.1, "WTX2": -1.0},
}
const KIND := {
	"el1": {"ANFR": 2.0, "BROT": 1.0, "CMBN": 1.0, "COPL": 1.0, "CNAR": 1.0, "CRBL": 1.0, "DRFR": 1.5, "DNFR": 1.0, "ENRG": 1.0,
		"ENVM": -1.0, "ETCH": 1.0, "FTDS": 1.0, "FDBK": 1.7, "FLOD": 1.0, "HAST": 1.0, "HOAM": 1.5, "RBRT": 1.0, "SACR": 1.0,
		"SCBR": 1.0, "SPTR": 1.0, "RPST": 1.0, "TRLB": 3.5, "VTLY": 1.0},
	"el2": {"LNRD": 1.0, "ENRG": 1.0, "RBRT": 1.0, "SCBR": 1.0, "RPST": 1.0, "HOAM": 1.5, "CNAR": 1.0, "FLOD": 1.0, "COPL": 1.0,
		"SPTR": 1.0, "FDBK": 1.7, "SACR": 1.0, "TRLB": 3.5, "HAST": 1.0, "VTLY": 1.0, "FTDS": 1.0, "CMBN": 1.0, "ENVM": -1.0,
		"ANFR": 2.0, "DRFR": 1.5, "DNFR": 1.0, "CRBL": 1.0, "ETCH": 1.0, "LFGR": 3.0},
}

## Second-game cutters, sawers and razors: their resting is part of the design.
const SELF_RESTING := ["CTMN", "SWMN", "RZMN"]

class Line:
	var parent: Line
	var depth := 0
	var phases := 0
	var command := {}
	## The command actually sent: a plan's first successful attack or block.
	var sent := {}
	var budget := -1
	var used := 0
	var prior := -1e6
	var value := 0.0
	var picked := false
	var second_pass := false
	var move := 0
	var flags := 0
	var explored := 0
	var children: Array[Line] = []

class Context:
	var ai := 0
	var w := PackedFloat64Array()
	var limit := 0
	var edition := "el1"
	var second := false
	var registered: Array[Line] = []
	var positions := 0
	## Auto-combat without "use spells": no hero abilities or artifacts, and
	## no spellbook copies that spend charges.
	var restricted := false

## The opponent's next command for the acting side, as a command dictionary
## (see `apply`). `stats`, when given, receives the number of positions.
static func think(duel: ELDuel, stats: Dictionary = {}, restricted := false) -> Dictionary:
	if duel.phase == ELDuel.Phase.FINISHED: return {}
	var ctx := Context.new()
	ctx.restricted = restricted
	ctx.ai = duel.active_side()
	ctx.edition = duel.profile.id
	ctx.second = ctx.edition == "el2"
	ctx.w = weights(duel.rng_state, ctx.second)
	ctx.limit = 1 if duel.phase == ELDuel.Phase.ATTACK else 0
	var root := Line.new()
	root.budget = BUDGET
	_search(ctx, root, duel.search_copy(ctx.second))
	stats.positions = ctx.positions
	var best: Line = null
	for line: Line in ctx.registered:
		if best == null or line.value > best.value: best = line
	if best == null: return {"kind": "end_phase"}
	while best.parent != null and best.parent.parent != null: best = best.parent
	stats.value = best.value
	return best.sent if not best.sent.is_empty() else best.command

## Sends a command to the duel; false when the rules refuse it.
static func apply(d: ELDuel, command: Dictionary) -> bool:
	match String(command.get("kind", "")):
		"end_phase": return d.end_phase()
		"cast": return d.cast(int(command.index), int(command.target), int(command.grave), int(command.power))
		"ability": return d.use_ability(int(command.id), String(command.key), int(command.target), int(command.choice), int(command.amount))
		"attack": return d.toggle_attack(int(command.id))
		"block": return d.assign_block(int(command.id), int(command.target))
	return false

## The nine evaluation weights for one think, drawn from a copy of the battle's
## random state (the battle itself does not advance).
static func weights(state: int, second: bool) -> PackedFloat64Array:
	var ranges := [[-0.1, 0.5, 0.3], [-0.05, 0.0, -0.01], [-0.1, 0.3, 1.5], [0.0, 1.0, 1.5], [-0.1, 0.1, 0.8],
		[-0.1, 0.1, 0.6], [-0.1, 0.1, 1.2], [0.0, 0.2, 0.3], [-0.1, 0.1, 0.8]]
	if not second:
		ranges[3] = [0.0, 1.5, 1.5]
		ranges[7] = [0.0, 0.5, 0.1]
	var result := PackedFloat64Array()
	var x := state & 0xffffffff
	for r: Array in ranges:
		x = (x * 0x343fd + 0x269ec3) & 0xffffffff
		var t := float(((x >> 16) & 0x7fff) % 1000) * 0.001
		result.append(float(r[0]) + t * (float(r[1]) - float(r[0])) + float(r[2]))
	return result

static func _search(ctx: Context, line: Line, before: ELDuel) -> bool:
	var s := before
	if line.parent != null:
		s = before.search_copy()
		if not _execute(ctx, line, s): return false
	ctx.positions += 1
	var finished := s.phase == ELDuel.Phase.FINISHED
	var maximise := s.active_side() == ctx.ai
	line.value = -1e6 if maximise else 1e6
	if line.parent != null and line.parent.phases == 0 and (line.move & MOVE_NEXT or finished): ctx.registered.append(line)
	if line.phases > ctx.limit or finished:
		line.value = _leaf(ctx, line, s)
		return true
	_generate(ctx, line, s)
	while true:
		var child := _pick(line)
		if child == null: break
		if not _allot(line, child): break
		var ok := _search(ctx, child, s)
		line.used += child.used
		if ok:
			line.explored += 1
			line.value = maxf(line.value, child.value) if maximise else minf(line.value, child.value)
	# Lines keep only their parent link once searched (no reference cycles).
	line.children.clear()
	return true

static func _execute(ctx: Context, line: Line, s: ELDuel) -> bool:
	if line.move & (MOVE_ATTACK | MOVE_ATTACK_PLAN):
		if line.flags & LINE_ATTACKED: return _fail(line)
		line.flags |= LINE_ATTACKED
		if line.move & MOVE_ATTACK_PLAN: return _attack_plan(ctx, line, s) or _fail(line)
	elif line.move & MOVE_BLOCK_PLANS:
		if line.flags & LINE_ONLY_NEXT: return _fail(line)
		line.flags |= LINE_ONLY_NEXT
		return _block_plan(ctx, line, s) or _fail(line)
	if line.move & MOVE_NEXT and s.phase == ELDuel.Phase.ATTACK and s.attacks.is_empty(): line.phases += 1
	line.used += 1
	return apply(s, line.command) or _fail(line)

static func _fail(line: Line) -> bool:
	line.move |= MOVE_FAILED
	return false

## Highest priority first among the untried moves (the first wins a tie); plans
## and attacks come after the plain moves of the same position.
static func _pick(line: Line) -> Line:
	for pass_index in [0, 1]:
		if pass_index == 0 and line.second_pass: continue
		var best: Line = null
		for c: Line in line.children:
			if c.picked or c.move & MOVE_FAILED or c.prior < THRESHOLD: continue
			if line.flags & LINE_ONLY_NEXT and not c.move & MOVE_NEXT: continue
			if line.flags & LINE_ATTACKED and c.move & (MOVE_ATTACK | MOVE_ATTACK_PLAN): continue
			if bool(c.move & MOVE_SECOND_PASS) != (pass_index == 1): continue
			if best == null or c.prior > best.prior: best = c
		if best != null:
			best.picked = true
			return best
		line.second_pass = true
	return null

## Shares the position budget: up to a fifth per root move, then half for the
## first reply and a third for later ones; deeper positions try fewer replies.
static func _allot(line: Line, child: Line) -> bool:
	var d := line.depth
	var e := line.explored
	if (d > 0 and e > 2) or (d > 4 and e > 1) or (d > 9 and e > 0): return false
	var share := line.budget / 5 if d == 0 else (line.budget / 3 if e != 0 else line.budget / 2)
	child.budget = maxi(0, mini(share, line.budget - line.used))
	return child.budget > 0 or (e < 2 and d < 20)

static func _add(line: Line, command: Dictionary, prior: float, move: int) -> Line:
	var c := Line.new()
	c.parent = line
	c.depth = line.depth + 1
	c.phases = line.phases + (1 if move & MOVE_NEXT else 0)
	c.flags = line.flags
	c.command = command
	c.prior = prior
	c.move = move | (MOVE_UNLIKELY if prior < THRESHOLD else 0)
	line.children.append(c)
	return c

static func _generate(ctx: Context, line: Line, s: ELDuel) -> void:
	var side := s.active_side()
	_add(line, {"kind": "end_phase"}, 1.1, MOVE_NEXT)
	var restricted := ctx.restricted and side == ctx.ai
	if side == ctx.ai:
		_casts(ctx, line, s, side)
		if not restricted: _artifacts(ctx, line, s, side)
	for ability: Dictionary in s.abilities(side):
		if restricted: break
		if ability.effect == "artifact" or not s.can_use_ability(side, ability.key): continue
		_ability_moves(ctx, line, s, side, side, ability)
	var army := s.army(side)
	if s.phase == ELDuel.Phase.ATTACK:
		for c: Dictionary in army:
			if _free(s, c) and not s.has_flag(c.id, "NoAttack"):
				_add(line, {"kind": "attack_plan"}, 1.0, MOVE_ATTACK_PLAN)
				break
	elif not s.attacks.is_empty() and not army.is_empty():
		for plan: Array in BLOCK_PLANS: _add(line, {"kind": "block_plan", "plan": plan[0]}, plan[1], plan[0])
	for c: Dictionary in army:
		if not s.creatures.has(c.id): continue
		for ability: Dictionary in s.abilities(c.id):
			if s.can_use_ability(c.id, ability.key): _ability_moves(ctx, line, s, side, c.id, ability)
		if s.phase == ELDuel.Phase.ATTACK and _free(s, c) and int(c.power) > 0:
			_add(line, {"kind": "attack", "id": c.id}, _attack_prior(s, c), MOVE_ATTACK)

## Ready, rested and not yet in combat.
static func _free(s: ELDuel, c: Dictionary) -> bool:
	return not c.resting and not c.sick and not s.attacks.has(c.id) and not s.blocks.has(c.id)

# --- Hand spells and artifacts ------------------------------------------------

static func _casts(ctx: Context, line: Line, s: ELDuel, side: int) -> void:
	var hero: Dictionary = s.heroes[side]
	var seen := {}
	for i in hero.hand.size():
		var card: String = hero.hand[i]
		if ctx.restricted and i < hero.hand_slots.size() and int(hero.hand_slots[i]) >= 0: continue
		if seen.has(card): continue
		seen[card] = true
		if s.cost(card) > s.available_mana(side): continue
		var use_in := String(s.profile.table("CombatSpells")[card].get("UseIn", "Both"))
		if (use_in == "Attack" and s.phase != ELDuel.Phase.ATTACK) or (use_in in ["Defence", "Defense"] and s.phase != ELDuel.Phase.DEFENCE): continue
		if card == "STSI":
			var prior := _stasis_prior(s, side, card)
			_add(line, {"kind": "cast", "index": i, "card": card, "target": -1, "grave": -1, "power": 0}, prior, MOVE_CAST)
			continue
		var rule := ELCatalog.rule(s.profile, card)
		if rule.is_empty(): continue
		var effect := String(rule.get("effect", ""))
		var powers: Array[int] = [0]
		if s.variable_power(card):
			powers = []
			if rule.get("x_source") == "health":
				for x in s.maximum_power(card) + 1: powers.append(x)
			else:
				for x in range(s.maximum_power(card), -1, -1): powers.append(x)
		var targets: Array[int] = [-1]
		if s.target_kind(card) != "none": targets = _ordered(s, s.valid_targets(card))
		for power: int in powers:
			for target: int in targets:
				for grave: int in _spell_choices(s, card, effect, target):
					var prior := _spell_prior(ctx, s, side, card, target, grave, power)
					_add(line, {"kind": "cast", "index": i, "card": card, "target": target, "grave": grave, "power": power}, prior, MOVE_CAST)

static func _spell_choices(s: ELDuel, card: String, effect: String, target: int) -> Array:
	match effect:
		"exchange", "pale_revival": return s.valid_grave_targets(card)
		"reanimate", "repair": return s.valid_grave_targets(card, target)
		"dispel", "trade": return s.valid_enchantment_targets(card, target)
		"swap": return s.swap_targets(card, target)
	return [-1]

## Heroes first, then creatures in play order.
static func _ordered(s: ELDuel, ids: Array) -> Array[int]:
	var result: Array[int] = []
	for id: int in [0, 1]:
		if ids.has(id): result.append(id)
	for id: int in s.creatures:
		if ids.has(id): result.append(id)
	return result

static func _artifacts(ctx: Context, line: Line, s: ELDuel, side: int) -> void:
	var items: Array = s.heroes[side].get("artifacts", [])
	for index in items.size():
		if not s.artifact_error(side, index).is_empty(): continue
		var item: Dictionary = items[index]
		var rule := s.artifact_rule(item)
		var ability := {"key": "artifact:%d" % index, "target": rule.get("target", "none"), "card": item.spell}
		for args: Array in _arguments(s, side, ability):
			if rule.get("target", "none") != "none" and ELCatalog.ARTIFACT_EFFECTS.has(item.spell) and not s.artifact_target_error(side, item.spell, args[0], args[1]).is_empty(): continue
			var prior := _spell_prior(ctx, s, side, String(item.spell), int(args[0]), int(args[1]), 0)
			_add(line, {"kind": "ability", "id": side, "key": ability.key, "target": args[0], "choice": args[1], "amount": -1}, prior, MOVE_CAST)

# --- Abilities -----------------------------------------------------------------

static func _ability_moves(ctx: Context, line: Line, s: ELDuel, side: int, id: int, ability: Dictionary) -> void:
	var card := String(ability.get("card", s.creatures[id].card if s.creatures.has(id) else ""))
	if id < 2:
		for e: Dictionary in s.heroes[id].enchantments:
			if e.id == ability.get("enchantment", -1): card = e.card
	for args: Array in _arguments(s, id, ability):
		var prior := _ability_prior(ctx, s, side, id, card, ability, args)
		_add(line, {"kind": "ability", "id": id, "key": ability.key, "target": args[0], "choice": args[1], "amount": args[2]}, prior, MOVE_ABILITY)

## [target, choice, amount] candidates for an ability or artifact.
static func _arguments(s: ELDuel, id: int, ability: Dictionary) -> Array:
	var key := String(ability.key)
	var effect := String(ability.get("effect", key))
	var side := int(s.entity(id).get("owner", id)) if id >= 2 else id
	var targets: Array = []
	match String(ability.get("target", "none")):
		"hero": targets = [[0, -1], [1, -1]]
		"creature":
			for c: int in s.creatures: targets.append([c, -1])
		"any":
			targets = [[0, -1], [1, -1]]
			for c: int in s.creatures: targets.append([c, -1])
		"enchantment":
			for holder: int in [0, 1] + s.creatures.keys():
				for e: Dictionary in s.entity(holder).get("enchantments", []): targets.append([holder, int(e.id)])
		"grave":
			for owner in [0, 1]:
				var indexes: Array = s.grave_ability_targets(id, key, owner)
				if key.begins_with("artifact:") and owner == side and indexes.is_empty():
					for index in s.heroes[side].grave.size():
						if s.profile.table("CombatCreatures").has(s.heroes[side].grave[index]): indexes.append(index)
				for index: int in indexes: targets.append([owner, index])
		_: targets = [[-1, -1]]
	var second := String(ability.get("second", "creature" if effect == "combine" else ""))
	if not second.is_empty():
		var paired: Array = []
		for t: Array in targets:
			var others: Array = ([0, 1] if second == "any" else []) + s.creatures.keys()
			for other: int in others:
				if other != t[0]: paired.append([t[0], other])
		targets = paired
	var amounts: Array = [-1]
	if ability.get("variable", false):
		amounts = []
		for x in range(s.available_mana(side), int(ability.get("minimum", 0)) - 1, -1): amounts.append(x)
	var result: Array = []
	for amount: int in amounts:
		for t: Array in targets: result.append([t[0], t[1], amount])
	return result

## Ability priorities: 0.75 unless the ability names its own rule.
static func _ability_prior(ctx: Context, s: ELDuel, side: int, id: int, card: String, ability: Dictionary, args: Array) -> float:
	var key := String(ability.key).get_slice(":", 0)
	var target := int(args[0])
	match key:
		"fireball", "sting", "spores", "gaze", "hunt":
			return _side_check(s, side, 0xa, target, -1)
		"tap_target", "tap_race":
			if s.creatures.has(target) and (s.creatures[target].resting or s.creatures[target].sick): return 0.0
			return _side_check(s, side, 0xa, target, -1)
		"energize":
			return _side_check(s, side, 5, target, -1)
		"dispel", "disenchant":
			return _side_check(s, side, 0x10, target, int(args[1]))
		"siphon":
			var c: Dictionary = s.creatures[id]
			return 0.5 if not c.resting and not c.sick and not s.attacks.has(id) and int(s.heroes[1 - side].mana) > 0 else 0.0
	if not ctx.second: return 0.75
	match key:
		"slay", "breath", "wall_break": return 0.5
		"dissipate", "cruel": return 0.0
		"illusion": return 0.5 if s.heroes[side].hand.size() >= 3 else 0.0
		"spirit_lock": return 0.45 if int(s.heroes[side].mana) < 7 else 0.0
		"lava_power":
			var mana := int(s.heroes[side].mana)
			if int(args[2]) == mana: return 0.45
			return 0.75 if mana >= 4 and int(args[2]) == mana - 1 else 0.0
		"burnout": return 0.5
	return 0.75

## The shared side test of spells and abilities: 0.75 when the target suits
## the flags (see SPELL_SIDES), else 0.
static func _side_check(s: ELDuel, side: int, flags: int, target: int, choice: int) -> float:
	return 0.75 if _sides_ok(s, side, flags, target, choice, true) else 0.0

static func _sides_ok(s: ELDuel, side: int, flags: int, target: int, choice: int, second: bool) -> bool:
	if flags & 0xf and target >= 0:
		if target < 2:
			# The first game's test reads only the creature requirements, which
			# a hero target never meets.
			if not second: return not bool(flags & 3)
			if target == side and flags & 8: return false
			if target != side and flags & 4: return false
		elif s.creatures.has(target):
			var owner := int(s.creatures[target].owner)
			if owner != side and flags & 1: return false
			if owner == side and flags & 2: return false
		else: return false
	if flags & 0x50 and choice >= 0:
		var holder := s.find_enchantment(choice)
		if holder >= 0:
			var e := s._enchantment_by_id(holder, choice)
			if int(e.get("owner", s.entity(holder).get("owner", holder))) == side: return false
	return true

# --- Spell priorities -------------------------------------------------------------

static func _spell_prior(ctx: Context, s: ELDuel, side: int, card: String, target: int, choice: int, x: int) -> float:
	var flags := int(SPELL_SIDES[ctx.edition].get(card, 0))
	match card:
		"COMT": return _comet_prior(ctx, s, side, target, x)
		"CHNL", "CTST", "ERQA", "FRST", "SNOV", "TPLF", "WNFL":
			return 0.0 if x == 0 else 0.5
		"HEAL":
			if not ctx.second: return 0.0 if x == 0 else 0.5
		"ZAPP", "DSIG":
			var amount := 1000000 if card == "DSIG" else s.effect_amount(ELCatalog.rule(s.profile, card))
			if target < 2:
				if target == side or target < 0: return 0.0
				return 1.0 if amount >= int(s.heroes[target].health) else 0.5
			if not s.creatures.has(target) or int(s.creatures[target].owner) == side: return 0.0
			var c: Dictionary = s.creatures[target]
			return (0.74 if amount >= int(c.toughness) - int(c.damage) else 0.24) + float(_worth(s, c.card)) * 0.01
		"BLSS", "WNBL":
			if s.creatures.has(target):
				var c: Dictionary = s.creatures[target]
				if c.resting or c.sick or s.has_flag(target, "NoAttack"): return 0.0
		"PSBR", "SHFR":
			if not s.creatures.has(target) or int(s.creatures[target].owner) != side: return 0.0
			return 0.5 if x > (3 if card == "PSBR" else 4) else 0.0
		"FRWN": return 0.5 if x >= 2 else 0.0
		"ENBR", "LFGR", "STSK":
			if ctx.second: return 0.5 if target >= 0 and target < 2 and _sides_ok(s, side, flags, target, choice, true) else 0.0
		"ASLT": return _assault_prior(s, side)
		"RDRS":
			if choice < 0 or choice >= s.heroes[side].grave.size(): return 0.0
			return minf(0.9, 0.1 * float(_printed_cost(s, s.heroes[side].grave[choice])) + 0.75)
		"OFLX": return _outer_flux_prior(s, side)
	return 0.5 if _sides_ok(s, side, flags, target, choice, ctx.second) else 0.0

static func _printed_cost(s: ELDuel, card: String) -> int:
	return int(s.profile.table("CombatSpells").get(card, {}).get("Cost", 0))

## Exactly lethal damage first, then overkill; a creature only for an exact kill.
static func _comet_prior(ctx: Context, s: ELDuel, side: int, target: int, x: int) -> float:
	if target < 0: return 0.0
	if target < 2:
		if target == side: return 0.0
		var health := int(s.heroes[target].health)
		if health == x: return 1.0
		if ctx.second:
			if health < x: return 0.95
			return minf(0.9, float(x) * 0.025 + 0.4) if x > 4 else 0.0
		# The first game ranks a wounding blast above overkill.
		if health > x: return 0.95
		return minf(0.9, float(x) * 0.025 + (0.3 if x < 5 else 0.4))
	if not s.creatures.has(target) or int(s.creatures[target].owner) == side: return 0.0
	var c: Dictionary = s.creatures[target]
	if x != int(c.toughness) - int(c.damage): return 0.0
	return minf(0.95, float(_worth(s, c.card)) * 0.05 + 0.4)

## Printed cost, plus one for a rare card and two for a unique one.
static func _worth(s: ELDuel, card: String) -> int:
	var worth := _printed_cost(s, card)
	match String(s.profile.table("CombatSpells").get(card, {}).get("Rarity", "")):
		"Rare": worth += 1
		"Unique": worth += 2
	return worth

## A whole-army boost: enough ready attackers against those still resting.
static func _assault_prior(s: ELDuel, side: int) -> float:
	var ready := 0
	var waiting := 0
	var resting := 0
	for c: Dictionary in s.army(side):
		if s.has_flag(c.id, "NoAttack"): continue
		if not c.resting and not c.sick: ready += 1
		elif c.sick or not s.has_flag(c.id, "NoUntap"):
			waiting += 1
			if c.resting: resting += 1
	return 0.5 if ready != 0 and (ready > 2 or waiting * 3 - resting <= ready * 3) else 0.0

## Worth casting when a pale enemy is no tougher than the caster's army is large.
static func _outer_flux_prior(s: ELDuel, side: int) -> float:
	var count := s.army(side).size()
	if count == 0: return 0.0
	for c: Dictionary in s.army(1 - side):
		if s.in_plane(c.id) and int(c.toughness) <= count: return 0.5
	return 0.0

## Stasis pays off with a larger army and spare ether.
static func _stasis_prior(s: ELDuel, side: int, card: String) -> float:
	var mana := int(s.heroes[side].mana)
	var price := s.cost(card)
	if mana < price + 6: return 0.0
	var lead := float(s.army(side).size() - s.army(1 - side).size()) - float(s.heroes[1 - side].mana) * 0.5
	return clampf(lead * float((mana - price) >> 1) * 0.033, 0.0, 0.95)

## A lone attacker's priority from its cost, evasion and the enemy's ready blockers.
static func _attack_prior(s: ELDuel, c: Dictionary) -> float:
	var power := int(c.power)
	if power == 0: return 0.0
	var worth := float(_printed_cost(s, c.card)) * 0.01
	if s.has_flag(c.id, "UB"): return minf(0.95, worth + 0.84)
	var total := 0
	var largest := 0
	var any_ready := false
	var flier := false
	var wall := false
	for e: Dictionary in s.army(1 - int(c.owner)):
		if e.resting or e.sick: continue
		var left := int(e.toughness) - int(e.damage)
		total += left
		largest = maxi(largest, left)
		any_ready = true
		if s.has_flag(e.id, "Fly"): flier = true
		if s.race(e.id) == "Wall": wall = true
	if not any_ready: return minf(0.95, worth + 0.79)
	if s.has_flag(c.id, "Fly") and not flier: return minf(0.95, worth + 0.79)
	if _elusive(s, c) and not wall: return minf(0.95, worth + 0.79)
	if total < power: return minf(0.95, worth + 0.69)
	if largest < power: return minf(0.95, worth + 0.59)
	return minf(0.95, float(power) * 0.025 + 0.3 - worth)

static func _elusive(s: ELDuel, c: Dictionary) -> bool:
	return c.card in ELCatalog.WALL_BLOCKED or s.has_flag(c.id, "Elusive")

# --- Attack and block plans --------------------------------------------------------

## Every free creature with power attacks, the most promising first.
static func _attack_plan(ctx: Context, line: Line, s: ELDuel) -> bool:
	var order: Array[int] = []
	var top := 0.0
	for c: Dictionary in s.army(s.active_side()):
		if not _free(s, c) or int(c.power) <= 0: continue
		line.used += 1
		var score := _attack_prior(s, c)
		if score > top:
			top = score
			order.push_front(int(c.id))
		else: order.append(int(c.id))
	for id: int in order:
		if s.creatures.has(id) and not s.attacks.has(id) and s.toggle_attack(id) and line.sent.is_empty():
			line.sent = {"kind": "attack", "id": id}
	return not line.sent.is_empty()

static func _block_plan(ctx: Context, line: Line, s: ELDuel) -> bool:
	if s.attacks.is_empty(): return false
	line.used += 2
	match int(line.command.plan):
		0x200: _block_smallest(line, s)
		0x400: _block_scored(line, s, 2)
		0x800: _block_scored(line, s, 3)
		0x1000: _block_scored(line, s, 4)
	return not line.sent.is_empty()

static func _block_now(line: Line, s: ELDuel, blocker: int, attacker: int) -> bool:
	line.used += 1
	var ok := s.assign_block(blocker, attacker)
	if ok and line.sent.is_empty(): line.sent = {"kind": "block", "id": blocker, "target": attacker}
	return ok

static func _can_block(s: ELDuel, attacker: int, blocker: int) -> bool:
	return s.block_problem(blocker, attacker).is_empty()

## Strongest attackers first: the least tough blocker that can stop each, or
## the toughest one against trample. Unblockable attackers are left alone.
static func _block_smallest(line: Line, s: ELDuel) -> void:
	var blockers: Array[Dictionary] = []
	for c: Dictionary in s.army(s.active_side()):
		if _free(s, c): blockers.append(c)
	blockers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.toughness) < int(b.toughness))
	var attackers: Array[Dictionary] = []
	for id: int in s.attacks:
		if s.creatures.has(id): attackers.append(s.creatures[id])
	# Descending power; equal powers keep the later attacker first.
	attackers.reverse()
	attackers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.power) > int(b.power))
	for a: Dictionary in attackers:
		if blockers.is_empty(): break
		if s.has_flag(a.id, "UB"): continue
		var order := blockers.duplicate()
		if s.has_flag(a.id, "Trample"): order.reverse()
		for b: Dictionary in order:
			if not _can_block(s, a.id, b.id): continue
			if _block_now(line, s, b.id, a.id):
				blockers.erase(b)
				break

## An attacker's fight so far: power still to absorb, toughness left, blockers
## and whether it is stopped.
static func _fight(s: ELDuel, a: Dictionary) -> Dictionary:
	return {"id": int(a.id), "power": int(a.power), "toughness": int(a.toughness), "count": 0, "stopped": false}

static func _with_blocker(s: ELDuel, f: Dictionary, b: Dictionary) -> void:
	if not s.has_flag(f.id, "FS") and s.has_flag(b.id, "FS") and f.toughness <= int(b.power):
		f.power = -1
		f.toughness = 0
		f.stopped = true
	else:
		f.power -= int(b.toughness)
		if f.power < 0:
			f.power = -1
			f.toughness -= int(b.power)
			f.stopped = true
		elif not (s.has_flag(f.id, "Trample") and f.power > 0):
			f.stopped = true
	f.count += 1

## Scored block plans: 2 stops each attacker with one blocker that survives or
## kills it; 3 gangs up while the blockers can still kill; 4 gangs up only
## when the attacker dies.
static func _block_scored(line: Line, s: ELDuel, plan: int) -> void:
	var side := s.active_side()
	var fights: Array[Dictionary] = []
	for id: int in s.attacks:
		if not s.creatures.has(id): continue
		var f := _fight(s, s.creatures[id])
		for blocker: int in s.blocks:
			if int(s.blocks[blocker]) == id and s.creatures.has(blocker): _with_blocker(s, f, s.creatures[blocker])
		if f.toughness > 0 and (plan != 2 or f.power > 0): fights.append(f)
	var free: Array[Dictionary] = []
	for c: Dictionary in s.army(side):
		if _free(s, c): free.append(c)
	while not fights.is_empty() and not free.is_empty():
		var at := 0
		for i in fights.size():
			if int(fights[i].power) > int(fights[at].power): at = i
		var f: Dictionary = fights[at]
		fights.remove_at(at)
		if plan == 2 and f.stopped: continue
		var candidates: Array[Dictionary] = []
		for b: Dictionary in free:
			if _can_block(s, f.id, b.id): candidates.append(b)
		if candidates.is_empty(): continue
		var chosen: Array[Dictionary] = []
		while not candidates.is_empty() and (f.count == 0 if plan == 2 else f.toughness > 0):
			var best := -1e6
			var pick: Dictionary = {}
			for b: Dictionary in candidates:
				var trial := f.duplicate()
				var score := -1e6
				if plan == 2:
					_with_blocker(s, trial, b)
					if trial.toughness < 1: score = 3000.0 - float(b.power) * 1.5 - float(b.toughness)
					elif trial.power < 0: score = 2000.0 - float(b.power) * 1.5 - float(b.toughness) - (2.5 if s.has_flag(b.id, "FS") else 0.0)
				else:
					if not (f.power > 0 or int(b.power) > 0): continue
					_with_blocker(s, trial, b)
					if plan == 3 and not (trial.count < 2 or trial.power < 0): continue
					if trial.toughness < 1: score = 3000.0 - float(b.power) * 1.5 - float(b.toughness)
					else:
						if trial.power < 0: score = 2000.0 + float(b.power) * 1.5 - float(b.toughness)
						elif trial.power == 0: score = 1000.0 - float(b.power) * 1.5 - float(b.toughness)
						else: score = float(b.toughness) - float(b.power) * 1.5
						if s.has_flag(b.id, "FS"): score -= 2.5
				if score > best:
					best = score
					pick = b
			if pick.is_empty(): break
			_with_blocker(s, f, pick)
			chosen.append(pick)
			candidates.erase(pick)
		if plan == 4 and f.toughness > 0: continue
		for b: Dictionary in chosen:
			if not _block_now(line, s, b.id, f.id): return
			free.erase(b)

# --- Evaluation ----------------------------------------------------------------

## A finished line counts its length against it; otherwise the position is
## blended with the one after the side to act passes its phase.
static func _leaf(ctx: Context, line: Line, s: ELDuel) -> float:
	var now := side_value(ctx, s, ctx.ai) - side_value(ctx, s, 1 - ctx.ai) + float(line.depth) * ctx.w[1]
	if s.phase == ELDuel.Phase.FINISHED: return now - float(line.depth)
	var after := s.search_copy()
	after.end_phase()
	ctx.positions += 1
	var later := side_value(ctx, after, ctx.ai) - side_value(ctx, after, 1 - ctx.ai)
	var blend := 0.001 if after.phase == ELDuel.Phase.FINISHED else ctx.w[0]
	return blend * later + (1.0 - blend) * now

## One side's position worth: army, health, hand, channels and enchantments.
static func side_value(ctx: Context, s: ELDuel, side: int) -> float:
	if s.phase == ELDuel.Phase.FINISHED:
		var lost := s.winner != side
		if lost: return 0.0 if s.winner < 0 else -10.0 * float(s.turn_serial)
		return 100000.0 if ctx.second else 10000.0
	var w := ctx.w
	var hero: Dictionary = s.heroes[side]
	var value := 0.0
	for c: Dictionary in s.army(side): value += creature_value(ctx, s, c)
	var health := float(hero.health)
	var channels := float(hero.channels)
	value += health * w[2] + float(hero.hand.size()) * w[4]
	if ctx.second:
		var term := channels * w[3]
		if channels > 9.0: term = (channels - 9.0) * 0.5 + 5.0 * w[3] + 3.0
		elif channels > 5.0: term = (channels - 5.0) * 0.75 + 5.0 * w[3]
		var whole := int(term)
		if whole > 20: whole = int(float(whole - 20) * 0.2 + 20.0)
		value += float(whole) + minf(health, 5.0) * 0.3 + minf(health, 8.0) * 0.2 + minf(health, 12.0) * 0.1
	else:
		value += channels * w[3]
	value += _hero_enchantments(ctx, hero)
	return clampf(value, 0.0, 20000.0 if ctx.second else 2000.0)

static func _hero_enchantments(ctx: Context, hero: Dictionary) -> float:
	var each: Dictionary = EACH[ctx.edition]
	var kind: Dictionary = KIND[ctx.edition]
	var counts := {}
	var total := 0.0
	for e: Dictionary in hero.enchantments:
		total += float(each.get(e.card, 0.0))
		counts[e.card] = int(counts.get(e.card, 0)) + 1
	# Forests do not stack: the ancient forest replaces the others, the dark the dense.
	if counts.has("ANFR"):
		counts.erase("DRFR")
		counts.erase("DNFR")
	elif counts.has("DRFR"): counts.erase("DNFR")
	for card: String in counts:
		total += float(kind.get(card, 0.0))
		if ctx.second: total += _count_value(card, int(counts[card]), true)
	return total

static func _count_value(card: String, count: int, on_hero: bool) -> float:
	match card:
		"SPLK": return 1.5 if count == 1 else 2.5
		"BROT": return 1.5
		"OCRP": return -1.5
		"STSK", "ENBR": return float(count - 1) * 2.0 + 3.0 if on_hero else 0.0
	return 0.0

static func _flag_amount(s: ELDuel, c: Dictionary, name: String) -> int:
	var best := 0
	for flag: String in c.flags + c.get("granted", []):
		if flag == name: best = maxi(best, 1)
		elif flag.begins_with(name + "("): best = maxi(best, int(flag.trim_prefix(name + "(").trim_suffix(")")))
	return best

## A creature's worth from its current stats, keywords and readiness (damage
## does not count).
static func creature_value(ctx: Context, s: ELDuel, c: Dictionary) -> float:
	var w := ctx.w
	var id := int(c.id)
	var second := ctx.second
	var base := w[5] + float(c.toughness) * w[8]
	var bonus := 0.0
	var factor := 0.0
	var regeneration := s.regeneration_cost(id)
	if regeneration > 0 and not s.has_flag(id, "NoRegen"):
		if regeneration == 1: bonus += 0.5
		elif regeneration == 2: bonus += 0.1
	match String(s.profile.table("CombatSpells").get(c.card, {}).get("Rarity", "")):
		"Rare": bonus += 0.1
		"Unique": bonus += 0.2
	if s.has_flag(id, "Fly"):
		if second:
			factor = 0.1
			bonus += 0.6
		else: bonus += 0.1
	if s.has_flag(id, "FS"): bonus += 0.1
	if s.has_flag(id, "NoTarget"): bonus += 0.1
	if s.has_flag(id, "NoAffect"): bonus += 1.5
	if s.has_flag(id, "Destroy"): bonus += 0.1
	if second:
		if s.in_plane(id): bonus -= 0.3
		var skins := s._enchantment_count(id, "STSK")
		if skins > 0: bonus += minf(1.5, float(skins) * w[8] * 1.1)
		var barriers := s._enchantment_count(id, "ENBR")
		if barriers > 0: bonus += minf(2.5, float(barriers) * w[8])
		if s._enchantment_count(id, "LFGR") > 0: bonus += 1.5
		if c.card == "OSP1": bonus += 1.0
		elif c.card in ["OSP2", "OSP3"]: bonus += 2.0
	var resting: bool = c.resting
	if not s.has_flag(id, "NoAttack"):
		factor += w[6]
		if s.has_flag(id, "Trample"): factor += 0.05
		if s.has_flag(id, "Lifetap"):
			factor += 0.1
			bonus += 0.1
		if s.has_flag(id, "UB"):
			factor += 0.05
			bonus += 0.1
		bonus += float(_flag_amount(s, c, "Discard")) * 0.05
		if s.has_flag(id, "NSS"): bonus += 0.05
		if s.has_flag(id, "TeamAttack"): factor -= 0.3
		if s.has_flag(id, "Berserk"): bonus -= 0.1
		if resting: bonus -= 0.5
		elif c.sick: bonus -= 0.3
	else:
		factor += w[7]
		if resting: bonus -= 0.5
	var restless := s.has_flag(id, "Restless")
	if restless: bonus += 0.1
	if s.has_flag(id, "NoUntap"):
		if second and c.card in SELF_RESTING:
			base *= 0.8
			factor *= 0.8
			if bonus > 0.0: bonus *= 0.8
		elif not resting:
			if not restless: bonus -= 0.2
		else:
			base *= 0.5
			factor *= 0.5
			if bonus > 0.0: bonus *= 0.5
	var blocked := s._enchantment_count(id, "IRRT") + s._enchantment_count(id, "MDNS") + s._enchantment_count(id, "RDIS") > 0
	if not blocked:
		if second and c.card == "WNHR": bonus += 5.0
		elif second and s._enchantment_count(id, "OCRP") > 0: bonus -= 0.5
		elif second and String(s.profile.table("CombatSpells").get(c.card, {}).get("Color", "")) == "White":
			bonus += 0.1 * float(s.abilities(id).size())
	var power := float(c.power)
	var spores := power * 0.5 if second and c.card == "CAFG" else 0.0
	var value := maxf(power * factor + spores + bonus + base, 0.01)
	if second:
		var counts := {}
		for e: Dictionary in c.enchantments: counts[e.card] = int(counts.get(e.card, 0)) + 1
		for card: String in counts: value += _count_value(card, int(counts[card]), false)
	return value
