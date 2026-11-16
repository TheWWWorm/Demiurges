class_name ELGlobalSpells
extends RefCounted
## First-game adventure global spells. Ether is a daily budget: each settlement
## pays hero upkeep, then the upkeep of active spells in cast order (a spell
## that no longer fits is dropped), runs their daily effects, and invests what
## is left in the single spell under production. A finished spell waits for the
## player to apply it (choosing its targets) or dispel it (resources refunded,
## invested ether lost).
##
## In the original 23 of these spells did nothing: 17 were cast, listed and
## paid for every day but never read, and 6 were used up with no effect. The
## remake gives each what its text promises: castle shields, faster, slower or
## no regeneration, Erosion and Shock Resonance (ELFirstScenario.damage and
## regenerate), Ether Calm, the ethereal-battle rewards of the hero
## enchantments (ethereal_result), Disenchant, Disjunction and Spell Blast
## (which read a spell's protection, the tenth of its extra ether that nothing
## read in the original), Visions, Ether Leak and Terminal Discharge.

const VERSION := 1
## Registry cost columns and the wallet resource each pays.
const COSTS := {"CostM": "Root", "CostL": "Lotus", "CostR": "Ruby", "CostE": "Emerald", "CostS": "Sapphire", "CostD": "Diamond", "CostF": "Stone"}
## Hero enchantments read when the hero fights or assaults a castle.
const HERO_BUFFS := ["MAST", "SPPR", "CNTR", "REGN", "GRSH"]
## Player spells that act as each of the player's battles starts.
const BATTLE_EFFECTS := ["LGWR", "RLWP", "FRGF", "HSTL"]
const CASTLE_DAMAGE := {"METR": 7, "CRMB": 4, "CHLG": 4}
## Repairs lower the caster's own pending damage. The night may lift energy
## above the maximum; it falls back to the maximum at the next day's end.
const REPAIRS := {"REPR": 4, "BNNT": 4, "RGRW": 8}
## Boon of Nature repairs every living castle of the caster and its allies,
## as its text says (the original repaired the caster's alone).
const FRIENDLY_REPAIR := "BNNT"
const RITUALS := {"BLRT": {"Ruby": 5}, "SMRT": {"Diamond": 5}, "SNRT": {"Emerald": 5}, "STRT": {"Sapphire": 5}, "FIRT": {"Stone": 1}}
## Persistent spells the original charged for but never read; each now does
## what its text promises (the constants below). The first five sit on the
## caster's own castle (OWN_CASTLE).
const ENCHANTMENTS := ["AURP", "ERBR", "MSRP", "SHIC", "WTWL", "BLED", "FRGT", "RSNC", "ETSL", "ICBR", "GRIF", "BFDK", "NTLK", "QSTR", "RTRB", "RNBR", "VIGR", "ETWB", "SPWD"]
## Damage each attack on a castle loses, from the texts: Chaos Shield 3 and
## Shield of Ice 5 on the caster's castle, Ice Barriers 3 on every castle of
## the caster and its allies. Several shields add up.
const SHIELDS := {"ERBR": 3, "SHIC": 5}
const FRIENDLY_SHIELDS := {"ICBR": 3}
## Daily regeneration rates as [numerator, denominator], from the texts:
## Continuous Restoration doubles the caster's castle's, Fresh Breeze raises it by
## half, Mass Restoration raises every friendly castle's by half. Each one
## multiplies the amount and rounds up, so a castle that regenerates at all
## gains at least one more.
const REGEN_BOOSTS := {"AURP": [2, 1], "WTWL": [3, 2]}
const FRIENDLY_REGEN := {"MSRP": [3, 2]}
## Decay: the enchanted castle does not regenerate.
const DECAY := "BLED"
## Erosion: the enchanted castle takes half as much again from each attack
## (rounded down), before its shields absorb their share.
const EROSION := "FRGT"
## Shock Resonance: what the enchanted castle takes from an attack, every
## other living castle takes as well (the echo is not itself an attack).
const RESONANCE := "RSNC"
## Ether Calm: no ethereal battle while it lasts. Every Warrior of the Realm
## is called off, whether or not its target has a defender, so the scripted
## attacks and the Ancient Tomb wait as well.
const ETHER_CALM := "ETSL"
## Visions: the caster sees what every other player is creating.
const VISIONS := "ETWB"
## Ether Leak: every spell the target castle's player orders costs half the
## Leak's extra ether more.
const ETHER_LEAK := "SPWD"
## Hero enchantments read when the hero wins an ethereal battle as the
## attacker: added castle damage from the battle's end (Wrath of the Dead:
## one per creature in the loser's graveyard; Biohazard: one per creature the
## loser has in play; Rush Reward: 10 less the round; Blessing of the Forest:
## one per 10 health the winner has left), and Enchanted Herbs, which takes 10
## of each of Mandrake Root and Black Lotus for every point the castle lost.
const ATTACKER_REWARDS := ["GRIF", "BFDK", "NTLK", "QSTR", "VIGR"]
const QUICK_ROUNDS := 10
const HEALTH_STEP := 10
const HERBS := 10
## A battle the computer settles without a duel (two computer players) has no
## graveyards or rounds to count: it counts as won in round QUICK_GUESS with
## the winner's health whole and nothing in play or in the graveyard (chosen).
const QUICK_GUESS := 5
## Hero enchantments read when the hero, defending its castle, wins an
## ethereal battle: Retribution kills the attacker; Retaliation takes
## RUNE_LOSS runes from every spell in the attacker's book that is not a cantrip.
const DEFENDER_REWARDS := ["RTRB", "RNBR"]
const RUNE_LOSS := 5
## Terminal Discharge pays half the caster's castle energy (rounded down;
## chosen, as the text leaves X to the caster and the screen has no number
## to choose) and deals that much to the target castle as one attack.
const DISCHARGE := "CLPS"
## Disenchant removes every other player's spell that acts on the caster's
## castle (Warriors of the Realm aside: those are attacks, not enchantments).
## Disjunction removes the single costliest spell (by ether) of any player not
## allied with the caster. Either removes a spell only when the dispel's own
## protection is at least the spell's.
const DISENCHANT := "DSLC"
const DISJUNCTION := "DSGB"
## Spell Blast dispels what the target castle's player is creating with the
## chance blast / (blast + invested): the ether put into the Blast against
## the ether already invested there (chosen ratio; the text names no formula).
## The dispelled player gets its resources back, as with its own dispel.
const SPELL_BLAST := "SPBS"
## Castle spells meant for an enemy castle.
const HOSTILE_CASTLE := ["BLED", "FRGT", "RSNC", "CLPS", "SPBS", "SPWD"]
## Castle spells registered on the caster's own castle without a target choice.
const OWN_CASTLE := ["AURP", "ERBR", "MSRP", "SHIC", "WTWL"]
const COUNTDOWN := "CNTD"
const SUMMONS := ["SCWR", "SCCH", "SCHR", "SKWR", "SKCH", "SKHR", "SSWR", "SSCH", "SSHR", "SVWR", "SVCH", "SVHR"]
const STRATEGIC_ORDERS := ["global_produce", "global_cancel", "global_cast", "global_dispel"]
const STRATEGIC_WORLD_ORDERS := ["global_cast", "global_dispel"]
## Lesser and Greater Fortification and Bastion act alike: the hero holds its
## tile with a radius-three guard area and takes no orders while it lasts.
const FORT_SPELLS := ["LFTC", "LFTK", "LFTS", "LFTV", "GFTC", "GFTF", "GFTK", "GFTV", "BSNC", "BSNK", "BSNS", "BSNV"]
## Defender of the Realm meets ethereal attacks on its castle; Warrior of the
## Realm makes one such attack on the next night.
const DEFENDER := "DFRL"
const WARRIOR := "WRRL"
## The AncientTomb guardian, reachable by an ethereal attack once the tomb opens.
const TOMB_TARGET := 0
const TOMB_GUARDIAN := "GreenWarlordGhost"
const SUMMON_LEVELS := {"WR": 1, "CH": 3, "HR": 5}
const NO_SPOT := Vector2i(-1, -1)
## Every spell is available; kept for spells a later content import may add.
const PENDING: Array[String] = []
## Remote Use opens a spell shop or component portal for a hero anywhere.
const REMOTE_USE := "RMTU"
const TURNS_UNKNOWN := 999

static func applies(state: ELAdventureSession) -> bool:
	return state.map != null and state.map.profile.id == "el1"

static func row(profile: ELProfile, code: String) -> Dictionary:
	return profile.table("GlobalSpells").get(code, {})

static func title(profile: ELProfile, code: String) -> String:
	return profile.text(str(row(profile, code).get("Name", code)))

static func supported(code: String) -> bool:
	return not PENDING.has(code)

static func persistent(code: String) -> bool:
	return HERO_BUFFS.has(code) or FORT_SPELLS.has(code) or code in [DEFENDER, WARRIOR] or BATTLE_EFFECTS.has(code) or RITUALS.has(code) or ENCHANTMENTS.has(code) or code == COUNTDOWN

## Per-player record, created on first use.
static func data(state: ELAdventureSession, player: int) -> Dictionary:
	var owner: Dictionary = state.players.get(player, {})
	if owner.is_empty(): return {}
	if not owner.has("global_spells"): owner.global_spells = {"version": VERSION, "production": {}, "active": [], "serial": 0, "summons": 0, "spent_today": 0, "dead": []}
	return owner.global_spells

static func resources(profile: ELProfile, code: String) -> Dictionary:
	var price := {}
	var entry := row(profile, code)
	for column: String in COSTS:
		if int(entry.get(column, 0)) > 0: price[COSTS[column]] = int(entry[column])
	return price

## Ether cost with the extra ether the player adds; summons cost more with each one cast.
static func ether_cost(state: ELAdventureSession, player: int, code: String, extra := 0) -> int:
	var base := int(row(state.map.profile, code).get("CostMana", 0))
	if SUMMONS.has(code): base *= int(data(state, player).get("summons", 0)) + 1
	return base + maxi(0, extra) + leak(state, player)

## Ether an Ether Leak on the player's castle adds to each spell it orders.
static func leak(state: ELAdventureSession, player: int) -> int:
	var total := 0
	for owner: int in state.players:
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if spell.code == ETHER_LEAK and int(spell.castle) == player: total += int(spell.get("leak", 0))
	return total

static func protection(state: ELAdventureSession, code: String, cost: int) -> int:
	return maxi(0, cost - int(row(state.map.profile, code).get("CostMana", 0))) / 10

static func upkeep(profile: ELProfile, code: String) -> int:
	return int(row(profile, code).get("Upkeep", 0))

## Today's free ether: income after hero upkeep, spell upkeep and investment.
static func free_ether(state: ELAdventureSession, player: int) -> int:
	return int(ELStrategy.mana_budget(state, player).available)

static func turns_left(state: ELAdventureSession, player: int) -> int:
	var production: Dictionary = data(state, player).get("production", {})
	if production.is_empty(): return 0
	var remaining := int(production.cost) - int(production.spent)
	if remaining <= 0: return 0
	var budget := ELStrategy.mana_budget(state, player)
	var daily := int(budget.income) - int(budget.spent) - spell_upkeep(state, player)
	return TURNS_UNKNOWN if daily <= 0 else ceili(float(remaining) / daily)

static func spell_upkeep(state: ELAdventureSession, player: int) -> int:
	var total := 0
	for spell: Dictionary in data(state, player).get("active", []): total += upkeep(state.map.profile, spell.code)
	return total

static func produce_problem(state: ELAdventureSession, player: int, code: String) -> String:
	if not applies(state) or row(state.map.profile, code).is_empty(): return "Unknown global spell."
	if not ELMapPickups.available_codes(state, player).has(code): return "This global spell is not available."
	if not supported(code): return "This global spell is not available in the remake yet."
	if not ELResources.can_pay(state.map.profile.id, state.players[player].resources, resources(state.map.profile, code)): return "Not enough resources for this global spell."
	return ""

## Orders a spell: resources are paid at once and today's free ether goes into
## it. A new order replaces the current production without a refund.
static func produce(state: ELAdventureSession, player: int, code: String, extra := 0) -> bool:
	var problem := produce_problem(state, player, code)
	if not problem.is_empty(): return state._fail(problem)
	var record := data(state, player)
	ELResources.pay(state.map.profile.id, state.players[player].resources, resources(state.map.profile, code))
	state.event.emit({"kind": "resources_changed", "player": player})
	record.production = {"code": code, "cost": ether_cost(state, player, code, extra), "spent": 0, "state": 1}
	# What an Ether Leak added is kept apart: it is no extra ether of the
	# player's and gives the spell no protection.
	var leaked := leak(state, player)
	if leaked > 0: record.production.leak = leaked
	_invest(state, player)
	state.event.emit({"kind": "global_spells_changed", "player": player})
	return true

## Dispels the production; its resources come back, the ether does not.
static func cancel(state: ELAdventureSession, player: int) -> bool:
	var record := data(state, player)
	if record.is_empty() or record.production.is_empty(): return state._fail("No global spell is being created.")
	state.change_resources(player, resources(state.map.profile, record.production.code))
	record.production = {}
	state.event.emit({"kind": "global_spells_changed", "player": player})
	return true

## Candidate lists for each parameter of a finished spell.
static func targets(state: ELAdventureSession, player: int, code: String) -> Array:
	var params: Variant = row(state.map.profile, code).get("Params", [])
	var kinds: Array = params if params is Array else ([] if str(params).is_empty() else [str(params)])
	var lists: Array = []
	for kind: String in kinds:
		var options: Array[int] = []
		if kind == "Hero":
			for hero: Dictionary in state.objects.values():
				if hero.get("type") != "hero" or not hero.alive or int(hero.owner) != player: continue
				# Heroes inside a fort, a training camp or a fortification spell are
				# not offered (every hero spell with a list filter in the original).
				if (code in ["RCLL", DEFENDER, WARRIOR, REMOTE_USE] or FORT_SPELLS.has(code)) and held(hero): continue
				# The realm's own defender cannot also attack.
				if code == WARRIOR and defender(state, player) == hero: continue
				options.append(int(hero.uid))
		elif kind == "Castle":
			# Every living player's castle, the caster's and allies' included;
			# an ethereal attack offers only other, unallied players and the open tomb.
			var ids: Array = state.scenario.get("castles", {}).keys()
			ids.sort()
			for id: int in ids:
				if code == WARRIOR and (id == player or _allied(state, player, id)): continue
				if id >= 1 and ELFirstScenario.alive(state, id) and not ELFirstScenario.castle_object(state, id).is_empty(): options.append(id)
			if code == WARRIOR and state.scenario.get("tomb_open", false) and not tomb_guardian(state).is_empty(): options.append(TOMB_TARGET)
		elif kind == "Shop":
			# Spell shops and component portals whose origin tile the caster or
			# an ally has explored, whoever owns them.
			var ids: Array = state.objects.keys()
			ids.sort()
			for id: int in ids:
				var shop := state.object(id)
				if shop.get("type") in ["el1_spell_shop", "rune_shop"] and shop.alive and shop.visible and shop.get("enabled", true) and ELFog.explored(state, player, Vector2i(shop.x, shop.y)): options.append(id)
		lists.append(options)
	return lists

## Applies the finished spell to the chosen targets (hero ids or castle owners).
static func cast(state: ELAdventureSession, player: int, chosen: Array = []) -> bool:
	var record := data(state, player)
	if record.is_empty() or record.production.is_empty() or int(record.production.state) != 2: return state._fail("No global spell is ready.")
	var code: String = record.production.code
	var lists := targets(state, player, code)
	if chosen.size() != lists.size(): return state._fail("Choose a target for the global spell.")
	for index in lists.size():
		if not lists[index].has(int(chosen[index])): return state._fail("Choose a target for the global spell.")
	# Protection (a tenth of the extra ether) is shown for the controlled spell
	# and resists the dispels; ether an Ether Leak added does not count.
	var paid := int(record.production.cost) - int(record.production.get("leak", 0))
	var spell := {"serial": int(record.serial) + 1, "code": code, "hero": -1, "castle": -1, "protection": protection(state, code, paid)}
	record.serial = spell.serial
	var params: Variant = row(state.map.profile, code).get("Params", [])
	for index in lists.size():
		var kind: String = params[index] if params is Array else str(params)
		spell["hero" if kind == "Hero" else ("shop" if kind == "Shop" else "castle")] = int(chosen[index])
	if OWN_CASTLE.has(code): spell.castle = player
	var castles: Dictionary = state.scenario.get("castles", {})
	if CASTLE_DAMAGE.has(code):
		var hit: Array[int] = []
		if code == "CHLG":
			for id: int in castles:
				if id >= 1 and id != player and castles[id].alive and not _allied(state, player, id): hit.append(id)
		else: hit.append(int(spell.castle))
		for id: int in hit:
			var dealt := ELFirstScenario.damage(state, id, CASTLE_DAMAGE[code])
			state.event.emit({"kind": "castle_spell", "player": id, "spell": code, "damage": dealt})
	elif REPAIRS.has(code) and castles.has(player):
		for id: int in repaired(state, player, code):
			castles[id].pending -= REPAIRS[code]
			state.event.emit({"kind": "castle_spell", "player": id, "spell": code, "damage": -REPAIRS[code]})
	elif code == DISCHARGE: discharge(state, player, int(spell.castle))
	elif code == DISENCHANT: disenchant(state, player, int(spell.protection))
	elif code == DISJUNCTION: disjoin(state, player, int(spell.protection))
	elif code == SPELL_BLAST: blast(state, player, int(spell.castle), paid)
	elif code == ETHER_LEAK: spell.leak = maxi(0, paid - int(row(state.map.profile, code).get("CostMana", 0))) / 2
	elif RITUALS.has(code): state.change_resources(player, RITUALS[code])
	elif code == COUNTDOWN: spell.counter = 1
	elif SUMMONS.has(code):
		var recruit := summon(state, player, SUMMON_LEVELS[code.substr(2)])
		if recruit >= 0: state.event.emit({"kind": "summon_cast", "id": recruit, "spell": code})
	elif code == "RCLL": recall(state, state.object(spell.hero))
	elif code == "RSSR": resurrect(state, player)
	elif code == REMOTE_USE:
		# The director opens the shop screen for the local caster; the shop is
		# not captured and the hero does not move.
		state.event.emit({"kind": "remote_use", "player": player, "hero": spell.hero, "shop": spell.shop})
	elif FORT_SPELLS.has(code):
		var hero := state.object(spell.hero)
		hero.orders.clear()
		hero.strategy_order = {}
	if code in [DEFENDER, WARRIOR]:
		# A new Defender or Warrior replaces the caster's previous one.
		var kept: Array = []
		for entry: Dictionary in record.active: if entry.code != code: kept.append(entry)
		record.active = kept
		if code == WARRIOR:
			state.object(spell.hero).orders.clear()
			state.object(spell.hero).strategy_order = {}
	record.production = {}
	if persistent(code): record.active.append(spell)
	sync(state)
	state.event.emit({"kind": "global_spell_cast", "player": player, "spell": code, "serial": spell.serial})
	state.event.emit({"kind": "global_spells_changed", "player": player})
	return true

## Removes one of the player's own active spells; no refund.
static func dispel(state: ELAdventureSession, player: int, serial: int) -> bool:
	var record := data(state, player)
	for index in record.get("active", []).size():
		if int(record.active[index].serial) == serial:
			record.active.remove_at(index)
			sync(state)
			state.event.emit({"kind": "global_spells_changed", "player": player})
			return true
	return state._fail("This global spell is not active.")

## Castles a repair spell mends: the caster's, and for Boon of Nature also the
## living castles of its allies.
static func repaired(state: ELAdventureSession, player: int, code: String) -> Array[int]:
	var result: Array[int] = []
	var castles: Dictionary = state.scenario.get("castles", {})
	var ids: Array = castles.keys()
	ids.sort()
	for id: int in ids:
		if id == player or (code == FRIENDLY_REPAIR and id >= 1 and castles[id].alive and _allied(state, player, id)): result.append(id)
	return result

## Terminal Discharge: the caster's castle pays half its energy at once and
## the target castle takes that much as one attack.
static func discharge(state: ELAdventureSession, player: int, target: int) -> int:
	var own: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if own.is_empty() or not own.get("alive", false): return 0
	var paid := int(own.health) / 2
	if paid <= 0: return 0
	var before := ELFirstScenario.stage(own)
	own.health = int(own.health) - paid
	state.event.emit({"kind": "castle_spell", "player": player, "spell": DISCHARGE, "damage": paid, "paid": true})
	if ELFirstScenario.stage(own) != before: state.event.emit({"kind": "castle_changed", "player": player, "stage": ELFirstScenario.stage(own)})
	ELFirstScenario.show_stage(state, player)
	var dealt := ELFirstScenario.damage(state, target, paid)
	state.event.emit({"kind": "castle_spell", "player": target, "spell": DISCHARGE, "damage": dealt})
	return dealt

## Whether a dispel of protection `power` overcomes `spell`.
static func _breaks(power: int, spell: Dictionary) -> bool:
	return power >= int(spell.get("protection", 0))

## Removes the spell `serial` of `owner` for another player's dispel.
static func _remove(state: ELAdventureSession, owner: int, serial: int, by: int) -> void:
	var record := data(state, owner)
	var kept: Array = []
	var code := ""
	for spell: Dictionary in record.get("active", []):
		if int(spell.serial) == serial: code = spell.code
		else: kept.append(spell)
	if code.is_empty(): return
	record.active = kept
	sync(state)
	state.event.emit({"kind": "global_spell_dispelled", "player": owner, "by": by, "spell": code})
	state.event.emit({"kind": "global_spells_changed", "player": owner})

## Disenchant: every other player's spell acting on the caster's castle that
## the dispel overcomes ends. Returns how many ended.
static func disenchant(state: ELAdventureSession, player: int, power: int) -> int:
	var removed := 0
	for entry: Dictionary in acting_on(state, player):
		if int(entry.owner) == player or entry.spell.code == WARRIOR or not _breaks(power, entry.spell): continue
		_remove(state, int(entry.owner), int(entry.spell.serial), player)
		removed += 1
	return removed

## The spell Disjunction would remove for `player`: the costliest active spell
## (by its ether) of a player not allied with it that the dispel overcomes,
## the latest cast on a tie; {} for none. Gives {owner, spell}.
static func disjunction_target(state: ELAdventureSession, player: int, power: int) -> Dictionary:
	var best := {}
	var owners: Array = state.players.keys()
	owners.sort()
	for owner: int in owners:
		if owner == player or owner < 1 or _allied(state, player, owner): continue
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if spell.code == WARRIOR or not _breaks(power, spell): continue
			var cost := int(row(state.map.profile, spell.code).get("CostMana", 0))
			if best.is_empty() or cost >= int(best.cost): best = {"owner": owner, "spell": spell, "cost": cost}
	return best

static func disjoin(state: ELAdventureSession, player: int, power: int) -> bool:
	var target := disjunction_target(state, player, power)
	if target.is_empty(): return false
	_remove(state, int(target.owner), int(target.spell.serial), player)
	return true

## Spell Blast: the target castle's player loses what it is creating (its
## resources come back) with the chance blast / (blast + invested).
static func blast(state: ELAdventureSession, player: int, target: int, power: int) -> bool:
	if target == player or not state.players.has(target): return false
	var production: Dictionary = data(state, target).get("production", {})
	if production.is_empty(): return false
	var invested := maxi(0, int(production.spent))
	var roll := ELAdditionalBuildings._random(state) % maxi(1, power + invested)
	var success := roll < power
	state.event.emit({"kind": "spell_blast", "player": target, "by": player, "spell": str(production.code), "success": success})
	if success: cancel(state, target)
	return success

## Whether a spell with `code` of any player is aimed at castle `player`.
static func on_castle(state: ELAdventureSession, player: int, code: String) -> bool:
	for entry: Dictionary in acting_on(state, player):
		if entry.spell.code == code: return true
	return false

## Damage each attack on castle `player` loses to the shields acting on it.
static func absorption(state: ELAdventureSession, player: int) -> int:
	var total := 0
	for owner: int in state.players:
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if SHIELDS.has(spell.code) and int(spell.castle) == player: total += int(SHIELDS[spell.code])
			elif FRIENDLY_SHIELDS.has(spell.code) and (owner == player or _allied(state, owner, player)): total += int(FRIENDLY_SHIELDS[spell.code])
	return total

## The energy castle `player` regains from `amount` (its free ether's
## regeneration) under the spells acting on it; `extra` is one more boost the
## player would cast (the computer's estimate).
static func regeneration_rate(state: ELAdventureSession, player: int, amount: int, extra := "") -> int:
	if amount <= 0 or on_castle(state, player, DECAY): return 0
	var factors: Array = []
	for owner: int in state.players:
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if REGEN_BOOSTS.has(spell.code) and int(spell.castle) == player: factors.append(REGEN_BOOSTS[spell.code])
			elif FRIENDLY_REGEN.has(spell.code) and (owner == player or _allied(state, owner, player)): factors.append(FRIENDLY_REGEN[spell.code])
	if REGEN_BOOSTS.has(extra): factors.append(REGEN_BOOSTS[extra])
	elif FRIENDLY_REGEN.has(extra): factors.append(FRIENDLY_REGEN[extra])
	for factor: Array in factors: amount = ceili(float(amount * int(factor[0])) / int(factor[1]))
	return amount

## Ether Calm of any player holds.
static func ether_calm(state: ELAdventureSession) -> bool:
	for owner: int in state.players:
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if spell.code == ETHER_CALM: return true
	return false

static func visions(state: ELAdventureSession, player: int) -> bool:
	for spell: Dictionary in data(state, player).get("active", []):
		if spell.code == VISIONS: return true
	return false

## What `other` is creating, as `viewer` sees it through Visions; {} otherwise.
static func seen_production(state: ELAdventureSession, viewer: int, other: int) -> Dictionary:
	if viewer == other or not state.players.has(other) or not visions(state, viewer): return {}
	return state.players[other].get("global_spells", {}).get("production", {})

## What the attacker-reward spells read from a finished duel: the round it
## ended in, the winner's health, and the loser's graveyard and creatures in
## play. {} without a duel.
static func battle_report(battle: ELDuel) -> Dictionary:
	if battle == null or battle.winner not in [0, 1]: return {}
	var loser := 1 - battle.winner
	return {"round": battle.round_number, "health": int(battle.heroes[battle.winner].get("health", 0)), "grave": battle.heroes[loser].get("grave", []).size(), "army": battle.army(loser).size()}

## Castle damage the attacker-reward spells add for a won ethereal battle.
static func battle_bonus(hero: Dictionary, report: Dictionary) -> int:
	if report.is_empty(): report = {"round": QUICK_GUESS, "health": int(hero.get("health", 0)), "grave": 0, "army": 0}
	var bonus := 0
	if hero_has(hero, "GRIF"): bonus += int(report.grave)
	if hero_has(hero, "BFDK"): bonus += int(report.army)
	if hero_has(hero, "QSTR"): bonus += maxi(0, QUICK_ROUNDS - int(report.round))
	if hero_has(hero, "VIGR"): bonus += maxi(0, int(report.health)) / HEALTH_STEP
	return bonus

## Retaliation: every spell of the hero's book that is not a cantrip loses
## `amount` runes; a spent spell gives its slot back to a cantrip under it.
static func drain_runes(state: ELAdventureSession, hero: Dictionary, amount: int) -> void:
	if hero.get("type") != "hero" or not hero.has("cards") or not ELRunes.restore(state.map.profile, hero): return
	var before: Array = hero.rune_uses.duplicate()
	for index in hero.cards.size():
		if int(hero.rune_uses[index]) > 0: hero.rune_uses[index] = maxi(0, int(hero.rune_uses[index]) - amount)
	ELRunes.return_cantrips(hero, before)
	state.event.emit({"kind": "inventory_changed", "id": int(hero.uid)})

## Daily settlement after hero upkeep: spell upkeep in cast order, daily effects,
## removal of spells whose hero died, then investment in the production.
static func settle(state: ELAdventureSession, player: int) -> bool:
	if not applies(state): return false
	var record := data(state, player)
	if record.is_empty(): return false
	var budget := ELStrategy.allocation(state.map.profile, ELResourceSites.mana_income(state, player), _heroes(state, player))
	var income := int(budget.income)
	var used := int(budget.spent)
	var kept: Array = []
	var castles: Dictionary = state.scenario.get("castles", {})
	for spell: Dictionary in record.active:
		var hero := state.object(int(spell.hero))
		if int(spell.hero) >= 0 and (hero.is_empty() or not hero.alive): continue
		# Warrior of the Realm lasts until the next settlement.
		if spell.code == WARRIOR: continue
		# A spell on a castle that has fallen ends with it.
		if int(spell.castle) >= 1 and castles.has(int(spell.castle)) and not bool(castles[int(spell.castle)].get("alive", false)): continue
		var cost := upkeep(state.map.profile, spell.code)
		if income < used + cost:
			state.event.emit({"kind": "global_spell_dropped", "player": player, "spell": spell.code})
			continue
		used += cost
		kept.append(spell)
	record.active = kept
	for spell: Dictionary in record.active:
		if RITUALS.has(spell.code): state.change_resources(player, RITUALS[spell.code])
		elif spell.code == COUNTDOWN:
			var ids: Array = castles.keys()
			ids.sort()
			for id: int in ids:
				if id >= 1 and castles[id].alive: ELFirstScenario.damage(state, id, int(spell.counter))
			spell.counter = int(spell.counter) + 1
	record.spent_today = used - int(budget.spent)
	_invest(state, player, false)
	sync(state)
	state.event.emit({"kind": "global_spells_changed", "player": player})
	# A finished spell asks again at every settlement until applied or dispelled.
	if int(record.production.get("state", 0)) == 2 and player == state.current_player: state.event.emit({"kind": "global_spell_ready", "player": player})
	return true

static func _invest(state: ELAdventureSession, player: int, announce := true) -> void:
	var record := data(state, player)
	var production: Dictionary = record.production
	if production.is_empty() or int(production.state) != 1: return
	var amount := mini(free_ether(state, player), int(production.cost) - int(production.spent))
	production.spent = int(production.spent) + maxi(0, amount)
	record.spent_today = int(record.spent_today) + maxi(0, amount)
	if int(production.spent) >= int(production.cost):
		production.state = 2
		if announce and player == state.current_player: state.event.emit({"kind": "global_spell_ready", "player": player})

## Rebuilds each hero's attached spell codes from the players' active lists.
static func sync(state: ELAdventureSession) -> void:
	if not applies(state): return
	var forts := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero":
			item.global_spells = []
			forts[int(item.uid)] = int(item.get("spell_fort", 0))
	for player: int in state.players:
		for spell: Dictionary in state.players[player].get("global_spells", {}).get("active", []):
			var hero := state.object(int(spell.hero))
			if not hero.is_empty() and not hero.global_spells.has(spell.code): hero.global_spells.append(spell.code)
			if not hero.is_empty() and FORT_SPELLS.has(spell.code): hero.spell_fort = int(spell.serial)
	for id: int in forts:
		var hero := state.object(id)
		var serial := 0
		for code: String in hero.global_spells: if FORT_SPELLS.has(code): serial = int(hero.spell_fort)
		hero.spell_fort = serial
		# A fortification that starts or ends changes the guard areas.
		if serial != forts[id]: state.event.emit({"kind": "object_changed", "id": id})

static func held_in_fort(hero: Dictionary) -> bool:
	return hero.get("fortified", false) or int(hero.get("spell_fort", 0)) > 0

## Inside a fort or a training camp, or holding a fortification spell.
static func held(hero: Dictionary) -> bool:
	return hero.get("fortified", false) or int(hero.get("camp", -1)) >= 0 or int(hero.get("spell_fort", 0)) > 0

static func hero_has(hero: Dictionary, code: String) -> bool:
	return hero.get("global_spells", []).has(code)

## Battle-start spells of a player, in the original side-flag order.
static func battle_effects(state: ELAdventureSession, player: int) -> Array[String]:
	var codes: Array[String] = []
	var active: Array = data(state, player).get("active", []) if state.players.has(player) else []
	for code: String in BATTLE_EFFECTS:
		for spell: Dictionary in active:
			if spell.code == code:
				codes.append(code)
				break
	return codes

## The skill each hero enchantment stands in for: a hero that has the skill
## (at any rank) gains nothing from the spell (battle_choice, ELSpecs).
const BUFF_SKILLS := {"MAST": "MSTR", "SPPR": "SUPR", "CNTR": "CONC", "REGN": "REGN"}

## Whether the hero enchantment `code` would change anything for `hero`.
static func buff_works(hero: Dictionary, code: String) -> bool:
	return not BUFF_SKILLS.has(code) or not hero.get("skills", {}).has(BUFF_SKILLS[code])

## Duel setup for one side: Luck and Suppression act like rank-one masteries,
## Concentration and Regeneration like rank-three skills, unless the hero
## already has that skill.
static func battle_choice(state: ELAdventureSession, actor: Dictionary, choice: Dictionary) -> void:
	if not applies(state) or actor.get("type") != "hero": return
	if hero_has(actor, "MAST"): choice.luck_spell = true
	if hero_has(actor, "SPPR"): choice.suppression_spell = true
	for pair: Array in [["CNTR", "CONC"], ["REGN", "REGN"]]:
		if hero_has(actor, pair[0]) and not choice.skills.has(pair[1]): choice.skills[pair[1]] = 2

## Spells whose target is this player's castle (any caster).
static func acting_on(state: ELAdventureSession, player: int) -> Array:
	var result: Array = []
	for owner: int in state.players:
		for spell: Dictionary in state.players[owner].get("global_spells", {}).get("active", []):
			if int(spell.castle) == player: result.append({"owner": owner, "spell": spell})
	return result

static func restore(state: ELAdventureSession) -> String:
	for player: int in state.players:
		var raw: Variant = state.players[player].get("global_spells")
		if raw == null: continue
		if not raw is Dictionary or raw.get("version") != VERSION or not raw.get("active") is Array or not raw.get("production") is Dictionary: return "Invalid saved global spells."
		for field: String in ["serial", "summons", "spent_today"]:
			if not ELLuaSave._integer(raw.get(field), 0, 1000000): return "Invalid saved global spells."
			raw[field] = int(raw[field])
		var dead: Variant = raw.get("dead", [])
		if not dead is Array or dead.size() > 10000: return "Invalid saved global spells."
		var fallen: Array = []
		for id: Variant in dead:
			if not ELLuaSave._integer(id, 0, 0x7fffffff) or state.object(id).get("type") != "hero" or state.object(id).alive: return "Invalid saved fallen hero."
			fallen.append(int(id))
		raw.dead = fallen
		var production: Dictionary = raw.production
		if not production.is_empty():
			if row(state.map.profile, str(production.get("code", ""))).is_empty() or not ELLuaSave._integer(production.get("state"), 1, 2) or not ELLuaSave._integer(production.get("cost"), 0, 1000000): return "Invalid saved global spell production."
			if not ELLuaSave._integer(production.get("spent"), 0, int(production.cost)): return "Invalid saved global spell production."
			var leaked: Variant = production.get("leak", 0)
			if not ELLuaSave._integer(leaked, 0, int(production.cost)): return "Invalid saved global spell production."
			raw.production = {"code": str(production.code), "cost": int(production.cost), "spent": int(production.spent), "state": int(production.state)}
			if int(leaked) > 0: raw.production.leak = int(leaked)
		var active: Array = []
		for spell: Variant in raw.active:
			if not spell is Dictionary or not persistent(str(spell.get("code", ""))) or not ELLuaSave._integer(spell.get("serial"), 1, 1000000) or not ELLuaSave._integer(spell.get("hero"), -1, 0x7fffffff) or not ELLuaSave._integer(spell.get("castle"), -1, 32): return "Invalid saved global spell."
			var entry := {"serial": int(spell.serial), "code": str(spell.code), "hero": int(spell.hero), "castle": int(spell.castle)}
			# Older saves carry no protection; it then reads as 0.
			if not ELLuaSave._integer(spell.get("protection", 0), 0, 100000): return "Invalid saved global spell."
			entry.protection = int(spell.get("protection", 0))
			if entry.code == WARRIOR:
				if not spell.get("attacked", false) is bool: return "Invalid saved global spell."
				entry.attacked = spell.get("attacked", false)
			if entry.code == ETHER_LEAK:
				# Saves made before Ether Leak worked carry no leak; it reads as 0.
				if not ELLuaSave._integer(spell.get("leak", 0), 0, 1000000): return "Invalid saved global spell."
				entry.leak = int(spell.get("leak", 0))
			if entry.code == COUNTDOWN:
				if not ELLuaSave._integer(spell.get("counter"), 1, 1000000): return "Invalid saved global spell."
				entry.counter = int(spell.counter)
			if entry.hero >= 0 and state.object(entry.hero).get("type") != "hero": return "Invalid saved global spell target."
			if entry.castle >= 0 and not state.scenario.get("castles", {}).has(entry.castle) and not (entry.code == WARRIOR and entry.castle == TOMB_TARGET): return "Invalid saved global spell target."
			active.append(entry)
		raw.active = active
	sync(state)
	return ""

## Ethereal non-aggression (the relation's first aspect) protects a castle.
static func _allied(state: ELAdventureSession, first: int, second: int) -> bool:
	return ELDiplomacy.allied_in(state, first, second, ELDiplomacy.ETHER)

static func _heroes(state: ELAdventureSession, player: int) -> Array[Dictionary]:
	var heroes: Array[Dictionary] = []
	for actor: Dictionary in state.objects.values():
		if actor.type == "hero" and actor.alive and actor.owner == player: heroes.append(actor)
	return heroes

## Free tile beside the player's castle, or NO_SPOT. The middle of the side the
## castle faces comes first, then its neighbours alternately; the first
## candidate off the map ends the search.
static func castle_spot(state: ELAdventureSession, player: int) -> Vector2i:
	var castle := ELFirstScenario.castle_object(state, player)
	var grid := state.grid
	if castle.is_empty() or grid == null or not castle.get("placed", true): return NO_SPOT
	var size: Vector2i = grid.footprints.get(int(castle.uid), {}).get("size", Vector2i.ONE)
	var x := int(castle.x)
	var y := int(castle.y)
	var first: Vector2i
	var axis := Vector2i.RIGHT
	match (int(castle.get("rotation", 0)) >> 2) & 3:
		0: first = Vector2i(x - 1 + size.x / 2, y - 1)
		1:
			first = Vector2i(x - 1, y - 1 + size.y / 2)
			axis = Vector2i.DOWN
		2: first = Vector2i(x - 1 + size.x / 2, y + size.y)
		3:
			first = Vector2i(x + size.x, y - 1 + size.y / 2)
			axis = Vector2i.DOWN
	if not grid.contains(first): return NO_SPOT
	for offset: int in [0, 1, -1, 2, -2, 3]:
		var point := first + axis * offset
		if grid.contains(point) and _free(state, point): return point
	return NO_SPOT

## The free tile nearest the player's castle that its heroes can walk to
## (any free one when it has none), within NEARBY tiles: for castles whose
## front lies off the map.
const NEARBY := 40

static func near_castle(state: ELAdventureSession, player: int) -> Vector2i:
	var castle := ELFirstScenario.castle_object(state, player)
	var grid := state.grid
	if castle.is_empty() or grid == null or not castle.get("placed", true): return NO_SPOT
	var home := Vector2i(int(castle.x), int(castle.y))
	var width: int = state.map.width
	var reached := PackedByteArray()
	reached.resize(width * state.map.height)
	var queue: Array[Vector2i] = []
	for hero: Dictionary in _heroes(state, player):
		var start := Vector2i(hero.x, hero.y)
		if hero.get("visible", false) and hero.get("placed", true) and grid.contains(start) and reached[start.y * width + start.x] == 0:
			reached[start.y * width + start.x] = 1
			queue.append(start)
	var roaming := not queue.is_empty()
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := at + Vector2i(dx, dy)
				if not grid.contains(next) or reached[next.y * width + next.x] != 0 or grid.land.is_point_solid(next): continue
				reached[next.y * width + next.x] = 1
				queue.append(next)
	var tiles: Array[Vector2i] = []
	for y in range(maxi(0, home.y - NEARBY), mini(state.map.height, home.y + NEARBY + 1)):
		for x in range(maxi(0, home.x - NEARBY), mini(width, home.x + NEARBY + 1)):
			if (not roaming or reached[y * width + x] != 0) and grid.passability(Vector2i(x, y)) >= 0: tiles.append(Vector2i(x, y))
	tiles.sort_custom(func(a: Vector2i, b: Vector2i): return (a - home).length_squared() < (b - home).length_squared())
	for tile: Vector2i in tiles:
		if _free(state, tile): return tile
	return NO_SPOT

static func _free(state: ELAdventureSession, point: Vector2i) -> bool:
	if state.grid.passability(point) < 0: return false
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("visible", false) and item.get("placed", true) and int(item.get("x", -1)) == point.x and int(item.get("y", -1)) == point.y: return false
	return true

## A new hero of the caster's colour beside its castle: a random non-quest
## level-one template, a name of its race and gender, and a specialisation of
## its colour, then experience up to the spell's level. Returns the hero, or -1.
## `nearby` falls back to the nearest free tile when the castle's front has none.
static func summon(state: ELAdventureSession, player: int, level: int, nearby := false) -> int:
	var profile := state.map.profile
	var colour := str(state.players.get(player, {}).get("color", ""))
	var templates: Array[String] = []
	var rows: Dictionary = profile.table("HeroTemplates")
	for key: String in rows:
		if str(rows[key].get("Quest", "")) != "Yes" and int(rows[key].get("Level", 1)) == 1 and str(rows[key].get("Color", "")) == colour: templates.append(key)
	if templates.is_empty(): return -1
	var template := templates[ELAdditionalBuildings._random(state) % templates.size()]
	var names: Array[String] = []
	for entry: Dictionary in profile.table("HeroNames").values():
		if str(entry.get("Race", "")) == colour and str(entry.get("Gender", "")) == str(rows[template].get("Gender", "")): names.append(str(entry.Name))
	var title := profile.text(names[ELAdditionalBuildings._random(state) % names.size()]) if not names.is_empty() else ""
	var specs: Array[String] = []
	var spec_rows: Dictionary = profile.table("HeroesSpecs")
	for code: String in spec_rows:
		var colours: Variant = spec_rows[code].get("MagicColor", [])
		if (colours is Array and colours.has(colour)) or str(colours) == colour: specs.append(code)
	var spec := specs[ELAdditionalBuildings._random(state) % specs.size()] if not specs.is_empty() else "NONE"
	var spot := castle_spot(state, player)
	if spot == NO_SPOT and nearby: spot = near_castle(state, player)
	if spot == NO_SPOT: return -1
	var id := ELAdditionalBuildings.spawn_hero(state, template, player, spot.x, spot.y)
	var hero := state.object(id)
	if not title.is_empty(): hero.title = title
	hero.specialization = spec
	if level > 1: state.add_experience(id, ELHeroProgression.threshold(profile, level))
	var record := data(state, player)
	record.summons = int(record.summons) + 1
	state.event.emit({"kind": "hero_placed", "id": id, "recruited": true})
	return id

## Recall: the hero appears beside its castle; its old tile still counts as
## taken during the search.
static func recall(state: ELAdventureSession, hero: Dictionary) -> bool:
	if hero.is_empty() or not hero.get("alive", false): return false
	var spot := castle_spot(state, int(hero.owner))
	if spot == NO_SPOT: return false
	hero.orders.clear()
	hero.strategy_order = {}
	hero.x = spot.x
	hero.y = spot.y
	state.event.emit({"kind": "object_changed", "id": hero.uid})
	return true

## Resurrection revives the caster's most recently fallen hero beside its
## castle. A hero with no room there is lost for good.
static func resurrect(state: ELAdventureSession, player: int) -> int:
	var record := data(state, player)
	var dead: Array = record.get("dead", [])
	if dead.is_empty(): return -1
	var id := int(dead[-1])
	while dead.has(id): dead.erase(id)
	var hero := state.object(id)
	var spot := castle_spot(state, player)
	if hero.is_empty() or spot == NO_SPOT: return -1
	# Back on the map, whatever held it off it (a training camp included).
	if hero.has("camp"): ELAdditionalBuildings.release_camp(state, hero)
	hero.merge({"alive": true, "visible": true, "placed": true, "x": spot.x, "y": spot.y, "strategy_order": {}, "intercepted": false, "fortified": false, "fort": -1}, true)
	hero.orders.clear()
	state._mob_ids.append(id)
	state.event.emit({"kind": "object_changed", "id": id})
	state.event.emit({"kind": "hero_placed", "id": id})
	return id

## A fallen hero's attached spells end at once, and it can be resurrected.
static func hero_died(state: ELAdventureSession, hero: Dictionary) -> void:
	var player := int(hero.get("owner", 0))
	var record := data(state, player)
	if player < 1 or record.is_empty(): return
	if not record.has("dead"): record.dead = []
	record.dead.append(int(hero.uid))
	ELAdditionalBuildings.drop_keys(state, hero)
	var kept: Array = []
	for spell: Dictionary in record.active:
		if int(spell.hero) != int(hero.uid): kept.append(spell)
	if kept.size() == record.active.size(): return
	record.active = kept
	sync(state)
	state.event.emit({"kind": "global_spells_changed", "player": player})

## The hero meeting ethereal attacks on this player's castle: its Defender of
## the Realm, or for a computer player its most experienced hero.
static func defender(state: ELAdventureSession, player: int) -> Dictionary:
	for spell: Dictionary in data(state, player).get("active", []):
		if spell.code == DEFENDER and state.object(spell.hero).get("alive", false): return state.object(spell.hero)
	if ELFirstAI.computer_players(state).has(player):
		var champion := state.object(int(state.players[player].get("ai", {}).get("champion", -1)))
		if champion.get("alive", false) and int(champion.get("owner", -1)) == player: return champion
	return {}

## The AncientTomb's keeper: a neutral hero built from the tomb's template
## (GreenWarlordGhost), never placed on the map. Created on first need; the
## original rebuilds it from the template whenever the map is built.
static func tomb_guardian(state: ELAdventureSession) -> Dictionary:
	var tomb := {}
	for item: Dictionary in state.objects.values():
		if item.get("tomb_keeper", false) and item.get("alive", false): return item
		if item.get("name") == "AncientTomb" and item.get("alive", true): tomb = item
	if tomb.is_empty(): return {}
	var template := str(ELXml.value(tomb.get("node", {}), "params")).strip_edges()
	if template.is_empty(): template = TOMB_GUARDIAN
	if not state.map.profile.table("HeroTemplates").has(template): return {}
	var id := state._next_object
	state._next_object += 1
	var keeper := {"uid": id, "permanent_id": id, "source_index": -1, "id": id, "name": template, "owner": 0, "group": "heroes", "x": int(tomb.x), "y": int(tomb.y), "rotation": 0, "type": "hero",
		"alive": true, "visible": false, "placed": false, "enabled": true, "shape": "", "level": 1, "health": 10, "base_ap": 0, "ap": 0, "experience": 0,
		"cards": [], "spell_stock": {}, "stock_separate": true, "skills": {}, "inventory": [], "orders": [], "node": {}, "fortified": false, "fort": -1, "temp_buffs": [], "tomb_keeper": true}
	ELAdditionalBuildings.apply_template(state.map.profile, keeper, template)
	state.objects[id] = keeper
	return keeper

## The keeper meets every attack fresh from its template.
static func renew_guardian(state: ELAdventureSession, keeper: Dictionary) -> void:
	ELAdditionalBuildings.apply_template(state.map.profile, keeper, str(keeper.name))
	keeper.experience = 0
	keeper.inventory = []

## After the night's moves: each Warrior of the Realm attacks once. A
## defended castle (or the tomb) means an ethereal battle; otherwise the
## castle takes the attacker's value as damage. While Ether Calm holds, every
## Warrior is called off.
static func plan_ethereal(director: ELAdventureDirector) -> void:
	var state := director.state
	if not applies(state): return
	var calm := ether_calm(state)
	var players: Array = state.players.keys()
	players.sort()
	var local_damage := 0
	for player: int in players:
		for spell: Dictionary in data(state, player).get("active", []):
			if spell.code != WARRIOR or spell.get("attacked", false): continue
			spell.attacked = true
			if calm: continue
			var attacker := state.object(spell.hero)
			if not attacker.get("alive", false): continue
			var target := int(spell.castle)
			if target == TOMB_TARGET:
				var guardian := tomb_guardian(state)
				if not guardian.is_empty():
					renew_guardian(state, guardian)
					ELStrategy.queue_combat(director, attacker.uid, guardian.uid, true)
				continue
			if not ELFirstScenario.alive(state, target): continue
			var guard := defender(state, target)
			if not guard.is_empty(): ELStrategy.queue_combat(director, attacker.uid, guard.uid, true)
			else:
				var damage := ELFirstScenario.damage(state, target, ELFirstScenario.hero_value(attacker))
				state.event.emit({"kind": "castle_spell", "player": target, "spell": WARRIOR, "damage": damage})
				if target == state.current_player: local_damage += damage
	# The local player hears once, with the night's summed ethereal damage.
	if local_damage > 0: ELFirstScenario._box(director, ELFirstScenario.text(state, "T_MB_CASTLE_DAMAGED", "Your castle was attacked and lost %d energy.") % local_damage)

## An ethereal battle kills nobody and gives no experience; a beaten defender's
## castle takes the winner's value, raised by the winner's attacker rewards
## (ATTACKER_REWARDS, read from `report`, see battle_report) as one attack.
## A defender that wins strikes back with Counterstrike, as the skill's text
## promises (ELFirstScenario.ether_defense), and with its defender rewards
## (DEFENDER_REWARDS). The original applied neither skill nor spell.
static func ethereal_result(state: ELAdventureSession, defender_id: int, winner_id: int, attacker_id := -1, report := {}) -> void:
	if winner_id < 0: return
	if winner_id == defender_id:
		if attacker_id < 0: return
		var guard := state.object(defender_id)
		var attacker := state.object(attacker_id)
		var back := ELFirstScenario.ether_defense(guard)
		var target := int(attacker.get("owner", 0))
		if back > 0 and target >= 1 and state.scenario.get("castles", {}).has(target) and ELFirstScenario.alive(state, target):
			var dealt := ELFirstScenario.damage(state, target, back)
			state.event.emit({"kind": "castle_spell", "player": target, "spell": WARRIOR, "damage": dealt})
		if hero_has(guard, "RNBR"): drain_runes(state, attacker, RUNE_LOSS)
		if hero_has(guard, "RTRB") and attacker.get("alive", false):
			state._native([float(attacker_id)], "ExKillHero")
			state.event.emit({"kind": "global_spell_effect", "spell": "RTRB", "hero": attacker_id})
		return
	var owner := int(state.object(defender_id).get("owner", 0))
	if owner < 1 or not state.scenario.get("castles", {}).has(owner): return
	var winner := state.object(winner_id)
	var damage := ELFirstScenario.damage(state, owner, ELFirstScenario.hero_value(winner) + battle_bonus(winner, report))
	state.event.emit({"kind": "castle_spell", "player": owner, "spell": WARRIOR, "damage": damage})
	# Enchanted Herbs: ten of each herb for every point the castle lost, as
	# far as the beaten player holds them.
	var taker := int(winner.get("owner", 0))
	if hero_has(winner, "NTLK") and damage > 0 and state.players.has(owner) and state.players.has(taker) and taker != owner:
		var wallet: Dictionary = state.players[owner].resources
		var herbs := {}
		for kind: String in ["Root", "Lotus"]:
			var amount := mini(HERBS * damage, int(wallet.get(kind, 0)))
			if amount > 0: herbs[kind] = amount
		if not herbs.is_empty():
			var loss := {}
			for kind: String in herbs: loss[kind] = -int(herbs[kind])
			state.change_resources(owner, loss)
			state.change_resources(taker, herbs)

## A scripted ethereal attack without a spell (mission13's Kinet leader): it
## acts on the coming night like Warrior of the Realm and ends at settlement.
static func script_attack(state: ELAdventureSession, player: int, hero: Dictionary, target: int) -> void:
	var record := data(state, player)
	var kept: Array = []
	for entry: Dictionary in record.active: if not (entry.code == WARRIOR and int(entry.hero) == int(hero.uid)): kept.append(entry)
	record.serial = int(record.serial) + 1
	kept.append({"serial": record.serial, "code": WARRIOR, "hero": int(hero.uid), "castle": target, "attacked": false})
	record.active = kept
	sync(state)
