class_name ELCombatBrain
extends RefCounted
## The computer opponent's link to the compiled combat lookahead
## (el_duel_brain.c): packs a duel position into the compact model that
## library searches (armies with their combat keywords, health, ether and the
## creature cards to come) and reads back its answer. ELCombatSearch plays the
## real rules for the move it is choosing and asks here what the fighting of
## the next turns leads to. Without the library (the browser version) nothing
## is asked.
##
## With `ELCombatSearch.smart_brain_cards` (off: it measured no stronger) the
## model's sides also play cards. It knows the computer's own creature cards
## in hand. Of the other hand it knows only what a player sees: how many
## cards it holds and the hero's colour, so it expects a typical creature of
## that colour as often as that colour's cards are creatures.

static var available := ClassDB.class_exists(&"ELNativeDuelBrain")

const HEADER := 15
const HERO_FIELDS := 16
const COSTS := 8
const TYPICAL_FIELDS := 4
const HAND := 6
const CARD_FIELDS := 8
const UNIT_FIELDS := 13
const FIXED := HEADER + 2 * (HERO_FIELDS + COSTS * TYPICAL_FIELDS + HAND * CARD_FIELDS)
const MAX_UNITS := 32
## Own turns whose channel income the model is told.
const INCOME_TURNS := 6

## Creature flags the model knows, by the rules' names.
const FLAGS := {"Fly": 1, "FS": 2, "Trample": 4, "UB": 8, "Elusive": 16, "NoAttack": 64, "Restless": 128, "NoUntap": 256,
	"Destroy": 512, "Lifetap": 1024, "Berserk": 2048, "TeamAttack": 4096, "NoRegen": 1 << 17}
const F_ELUSIVE := 16
const F_WALL := 32
const F_NO_UNTAP := 256
const F_RESTING := 8192
const F_SICK := 16384
const F_PLANE := 32768
const F_ATTACKING := 65536
const F_HELD := 1 << 18
const F_DESTROY_UNWALLED := 1 << 19
const F_STINGER := 1 << 20
## Ether that breaks a creature's enfeeblement (ELDuel's "wake" ability).
const WAKE_COST := 3

## The typical creature of a colour by cost, per game: {"share": creature
## cards per thousand, "stats": [[power, toughness] for costs 1..8]}.
static var _typical := {}

## What the fighting of the next `turns` turns leads to from `s`, where the
## side to move chooses its attackers (attack phase) or the defender its
## blocks (defence phase):
##   status  1 the computer wins within those turns, -1 it loses, else 0
##   turns   with a status, the turn that decides it (1 = the one to play)
##   value   the worth gained or lost against the position as it stands
##   ids     the attackers to send, or (blocker, attacker) pairs still to assign
## Empty when the library is missing or the armies do not fit the model.
## `budget` is the number of fights played; `wide` looks at more choices, for
## picking a move rather than scoring a line.
static func ask(ctx: ELCombatSearch.Context, s: ELDuel, turns: int, budget: int, wide: bool) -> Dictionary:
	if not available or s.creatures.size() > MAX_UNITS or s.phase == ELDuel.Phase.FINISHED: return {}
	var state := PackedInt32Array()
	state.resize(FIXED + s.creatures.size() * UNIT_FIELDS)
	state[0] = 3
	state[1] = ctx.ai
	state[2] = s.attacker
	state[3] = 0 if s.phase == ELDuel.Phase.ATTACK else 1
	state[4] = turns
	state[5] = budget
	state[6] = 1 if ctx.second else 0
	state[7] = int(ctx.w[2] * 1000.0)
	state[8] = s.global_enchantment_count("LSDS")
	state[9] = 1 if s.global_enchantment_count("FOGG") + s.global_enchantment_count("WLDT") + s.global_enchantment_count("EWLD") > 0 else 0
	state[10] = 1 if wide else 0
	state[11] = s.creatures.size()
	state[12] = 1 if ctx.brain_cards else 0
	# The side to move still has its cards of this turn to play.
	state[13] = 1 if s.phase == ELDuel.Phase.ATTACK else 0
	state[14] = int(ctx.foe_health * 100.0)
	# A forest on a hero holds the weak creatures of the other army.
	var held := [-1, -1]
	var auras := [0, 0]
	var income: Dictionary = s.profile.table("CombatManaIncome")
	for side in 2:
		var hero: Dictionary = s.heroes[side]
		var at := HEADER + side * HERO_FIELDS
		var skins := 0
		var guards := 0
		var reflects := 0
		var mirrors := 0
		var cards: Array = []
		for e: Dictionary in hero.enchantments:
			cards.append(e.card)
			match String(e.card):
				"STSK": skins += 1
				"LFGR": guards += 1
				"FDBK", "LNRD": reflects += 1
				"ETCH": mirrors += 1
				"DNFR", "DRFR", "ANFR": held[side] = maxi(held[side], s.forest_limit(e.card))
		auras[side] = cards.hash()
		state[at] = int(hero.health)
		state[at + 1] = s.available_mana(side)
		state[at + 2] = int(hero.channels)
		state[at + 3] = skins
		state[at + 4] = guards
		state[at + 5] = reflects
		state[at + 6] = mini(mirrors, 1) if ctx.second else mirrors
		if not ctx.brain_cards: continue
		var typical := _typical_of(s.profile, String(hero.faction))
		var share := int(typical.share) if ELCombatSearch.smart_brain_typical else 0
		state[at + 8] = share
		if side != ctx.ai:
			# The other hand is unknown: any of its cards may be a creature.
			state[at + 7] = hero.hand.size()
			state[at + 9] = maxi(0, mini(1000, hero.hand.size() * share) - share)
		for turn in INCOME_TURNS:
			var number := int(hero.turns) + 1 + turn
			if number < income.size(): state[at + 10 + turn] = int(income.get(str(number), {}).get("Level%d" % int(hero.level), 0))
		var slot := HEADER + 2 * HERO_FIELDS + side * COSTS * TYPICAL_FIELDS
		for stats: Array in typical.stats:
			if int(stats[0]) + int(stats[1]) > 0:
				var worth := ctx.w[5] + float(stats[1]) * ctx.w[8] + float(stats[0]) * ctx.w[6]
				state[slot] = int(stats[0])
				state[slot + 1] = int(stats[1])
				state[slot + 2] = _card_worth(ctx, worth)
				state[slot + 3] = _card_worth(ctx, worth - 0.5)
			slot += TYPICAL_FIELDS
	var hand := HEADER + 2 * (HERO_FIELDS + COSTS * TYPICAL_FIELDS)
	for i in 2 * HAND: state[hand + i * CARD_FIELDS] = -1
	if ctx.brain_cards and ELCombatSearch.smart_brain_own:
		# The computer's own creature cards, as far as the model has room.
		var own: Dictionary = s.heroes[ctx.ai]
		var slot := hand + ctx.ai * HAND * CARD_FIELDS
		var held_cards := 0
		for card: String in own.hand:
			if held_cards >= HAND: break
			var record: Variant = ctx.cards.get(card)
			if record == null:
				record = _card(ctx, s, card)
				ctx.cards[card] = record
			if record.is_empty() or s.channel_cost(card) > 0: continue
			state[slot] = s.cost(card)
			for i in record.size(): state[slot + 1 + i] = int(record[i])
			slot += CARD_FIELDS
			held_cards += 1
	var at := FIXED
	for c: Dictionary in s.creatures.values():
		var owner := int(c.owner)
		# A creature's own record does not change while it stands as it is under the
		# same hero enchantments.
		var key := [c.hash(), auras[owner]].hash()
		var unit: Variant = ctx.units.get(key)
		if unit == null:
			unit = _unit(ctx, s, c)
			ctx.units[key] = unit
		var flags := int(unit[0])
		if s.attacks.has(int(c.id)): flags |= F_ATTACKING
		if int(c.power) <= int(held[1 - owner]): flags |= F_HELD
		state[at] = int(c.id)
		state[at + 1] = owner
		state[at + 2] = int(c.power)
		state[at + 3] = int(c.toughness)
		state[at + 4] = flags
		state[at + 5] = int(unit[1])
		state[at + 6] = int(unit[2])
		state[at + 7] = int(unit[3])
		state[at + 8] = int(unit[4])
		state[at + 9] = int(unit[5])
		state[at + 10] = int(unit[6])
		state[at + 11] = int(s.blocks.get(int(c.id), -1))
		state[at + 12] = int(unit[7])
		at += UNIT_FIELDS
	var bytes := state.to_byte_array()
	var position := hash(bytes)
	var asked: Variant = ctx.asked.get(position)
	if asked != null: return asked
	var out: PackedInt32Array = (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", bytes) as PackedByteArray).to_int32_array()
	var result := {}
	if out.size() >= 5 and int(out[3]) > 0:
		var ids: Array[int] = []
		for i in int(out[4]): ids.append(int(out[5 + i]))
		var decided := int(out[0]) != 0
		result = {"status": int(out[0]), "value": 0.0 if decided else float(out[1]) * 0.001, "turns": int(out[1]) if decided else 0, "ids": ids}
	ctx.asked[position] = result
	ctx.fights += int(out[2]) if out.size() >= 5 else 0
	return result

## Fills the shared tables a think reads, before one starts on another thread.
static func prepare(duel: ELDuel) -> void:
	for hero: Dictionary in duel.heroes: _typical_of(duel.profile, String(hero.faction))

## A card's worth once summoned, in thousandths: a creature still to be played
## counts for less than one in play, and its card leaves the hand.
static func _card_worth(ctx: ELCombatSearch.Context, worth: float) -> int:
	return int((worth - ctx.w[4]) * ELCombatSearch.smart_brain_discount * 1000.0)

## [flags, regeneration cost, stone skins, lifeguards, worth ready, worth
## resting (thousandths), race number, wake cost] of one creature.
static func _unit(ctx: ELCombatSearch.Context, s: ELDuel, c: Dictionary) -> Array:
	var id := int(c.id)
	var flags := 0
	for flag: String in c.flags + c.get("granted", []):
		flags |= int(FLAGS.get(flag, 0))
	var race := s.race(id)
	if race == "Wall": flags |= F_WALL
	if c.card in ELCatalog.WALL_BLOCKED: flags |= F_ELUSIVE
	if c.card in ELCatalog.MECHOS: flags |= F_DESTROY_UNWALLED
	if c.card in ELCatalog.STINGERS: flags |= F_STINGER
	if s.cannot_rise(id): flags |= F_NO_UNTAP
	if c.resting: flags |= F_RESTING
	if c.sick: flags |= F_SICK
	if s.in_plane(id): flags |= F_PLANE
	# The search's own worth of the creature, ready and resting.
	var probe := c.duplicate()
	probe.resting = false
	probe.sick = false
	var ready_worth := ELCombatSearch.creature_value(ctx, s, probe)
	probe.resting = true
	var resting_worth := ELCombatSearch.creature_value(ctx, s, probe)
	return [flags, s.regeneration_cost(id), s._enchantment_count(id, "STSK"), s._enchantment_count(id, "LFGR"),
		int(ready_worth * 1000.0), int(resting_worth * 1000.0), race.hash() & 0x7f, WAKE_COST if s.enfeebled(id) else 0]

## [power, toughness, flags, regeneration cost, worth ready, worth resting,
## race number] of a creature card in hand; empty for any other card.
static func _card(ctx: ELCombatSearch.Context, s: ELDuel, card: String) -> Array:
	if ELCatalog.rule(s.profile, card).get("effect", "") != "summon": return []
	var row: Dictionary = s.profile.table("CombatCreatures").get(card, {})
	if row.is_empty(): return []
	var flags := 0
	var regeneration := 0
	var names := ELCatalog.flags(row)
	for flag: String in names:
		flags |= int(FLAGS.get(flag, 0))
		if flag.begins_with("Regen("): regeneration = int(flag.trim_prefix("Regen(").trim_suffix(")"))
	if not names.has("NSS"): flags |= F_SICK
	var race := str(row.get("Race", ""))
	if race == "Wall": flags |= F_WALL
	if card in ELCatalog.WALL_BLOCKED: flags |= F_ELUSIVE
	if card in ELCatalog.MECHOS: flags |= F_DESTROY_UNWALLED
	if card in ELCatalog.STINGERS: flags |= F_STINGER
	var power := int(row.Power)
	var toughness := int(row.Toughness)
	var worth := ctx.w[5] + float(toughness) * ctx.w[8] + float(power) * (ctx.w[7] if names.has("NoAttack") else ctx.w[6])
	if names.has("Fly"): worth += (0.6 + float(power) * 0.1) if ctx.second else 0.1
	return [power, toughness, flags, regeneration, _card_worth(ctx, worth), _card_worth(ctx, worth - 0.5), race.hash() & 0x7f]

## The average creature of `faction` for each cost, and how many of the
## colour's cards are creatures.
static func _typical_of(profile: ELProfile, faction: String) -> Dictionary:
	var key := profile.id + ":" + faction
	if _typical.has(key): return _typical[key]
	var sums: Array = []
	for cost in COSTS: sums.append([0, 0, 0])
	var cards := ELCatalog.available_cards(profile, faction)
	var creatures := 0
	for card: String in cards:
		if ELCatalog.rule(profile, card).get("effect", "") != "summon": continue
		var row: Dictionary = profile.table("CombatCreatures").get(card, {})
		if row.is_empty(): continue
		creatures += 1
		var cost := int(profile.table("CombatSpells")[card].Cost)
		if cost < 1 or cost > COSTS: continue
		sums[cost - 1][0] += int(row.Power)
		sums[cost - 1][1] += int(row.Toughness)
		sums[cost - 1][2] += 1
	var stats: Array = []
	for sum: Array in sums:
		stats.append([roundi(float(sum[0]) / float(sum[2])), roundi(float(sum[1]) / float(sum[2]))] if int(sum[2]) > 0 else [0, 0])
	var result := {"share": creatures * 1000 / maxi(1, cards.size()), "stats": stats}
	_typical[key] = result
	return result
