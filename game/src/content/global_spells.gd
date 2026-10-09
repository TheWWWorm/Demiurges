class_name ELGlobalSpells
extends RefCounted
## First-game adventure global spells. Ether is a daily budget: each settlement
## pays hero upkeep, then the upkeep of active spells in cast order (a spell
## that no longer fits is dropped), runs their daily effects, and invests what
## is left in the single spell under production. A finished spell waits for the
## player to apply it (choosing its targets) or dispel it (resources refunded,
## invested ether lost). Several spells only charge upkeep or are consumed with
## no effect in the original; they behave the same here.

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
const RITUALS := {"BLRT": {"Ruby": 5}, "SMRT": {"Diamond": 5}, "SNRT": {"Emerald": 5}, "STRT": {"Sapphire": 5}, "FIRT": {"Stone": 1}}
## Registered and paid for every day, but nothing reads them: castle absorption,
## extra damage taken, regeneration rates and post-battle bonuses stay unchanged.
const UPKEEP_ONLY := ["AURP", "ERBR", "MSRP", "SHIC", "WTWL", "BLED", "FRGT", "RSNC", "ETSL", "ICBR", "GRIF", "BFDK", "NTLK", "QSTR", "RTRB", "RNBR", "VIGR"]
## Applying these clears the production and does nothing else.
const CONSUMED := ["CLPS", "DSGB", "DSLC", "ETWB", "SPBS", "SPWD"]
## Castle spells registered on the caster's own castle without a target choice.
const OWN_CASTLE := ["AURP", "ERBR", "MSRP", "SHIC", "WTWL"]
const COUNTDOWN := "CNTD"
const SUMMONS := ["SCWR", "SCCH", "SCHR", "SKWR", "SKCH", "SKHR", "SSWR", "SSCH", "SSHR", "SVWR", "SVCH", "SVHR"]
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
	return HERO_BUFFS.has(code) or FORT_SPELLS.has(code) or code in [DEFENDER, WARRIOR] or BATTLE_EFFECTS.has(code) or RITUALS.has(code) or UPKEEP_ONLY.has(code) or code == COUNTDOWN

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
	return base + maxi(0, extra)

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
	# Protection (a tenth of the extra ether) is shown for the controlled spell.
	var spell := {"serial": int(record.serial) + 1, "code": code, "hero": -1, "castle": -1, "protection": protection(state, code, int(record.production.cost))}
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
			castles[id].pending += CASTLE_DAMAGE[code]
			state.event.emit({"kind": "castle_spell", "player": id, "spell": code, "damage": CASTLE_DAMAGE[code]})
	elif REPAIRS.has(code) and castles.has(player):
		castles[player].pending -= REPAIRS[code]
		state.event.emit({"kind": "castle_spell", "player": player, "spell": code, "damage": -REPAIRS[code]})
	elif RITUALS.has(code): state.change_resources(player, RITUALS[code])
	elif code == COUNTDOWN: spell.counter = 1
	elif SUMMONS.has(code): summon(state, player, SUMMON_LEVELS[code.substr(2)])
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
	for spell: Dictionary in record.active:
		var hero := state.object(int(spell.hero))
		if int(spell.hero) >= 0 and (hero.is_empty() or not hero.alive): continue
		# Warrior of the Realm lasts until the next settlement.
		if spell.code == WARRIOR: continue
		var cost := upkeep(state.map.profile, spell.code)
		if income < used + cost:
			state.event.emit({"kind": "global_spell_dropped", "player": player, "spell": spell.code})
			continue
		used += cost
		kept.append(spell)
	record.active = kept
	var castles: Dictionary = state.scenario.get("castles", {})
	for spell: Dictionary in record.active:
		if RITUALS.has(spell.code): state.change_resources(player, RITUALS[spell.code])
		elif spell.code == COUNTDOWN:
			for id: int in castles:
				if id >= 1 and castles[id].alive: castles[id].pending += int(spell.counter)
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
			raw.production = {"code": str(production.code), "cost": int(production.cost), "spent": int(production.spent), "state": int(production.state)}
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

static func _free(state: ELAdventureSession, point: Vector2i) -> bool:
	if state.grid.passability(point) < 0: return false
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("visible", false) and item.get("placed", true) and int(item.get("x", -1)) == point.x and int(item.get("y", -1)) == point.y: return false
	return true

## A new hero of the caster's colour beside its castle: a random non-quest
## level-one template, a name of its race and gender, and a specialisation of
## its colour, then experience up to the spell's level. Returns the hero, or -1.
static func summon(state: ELAdventureSession, player: int, level: int) -> int:
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
	if spot == NO_SPOT: return -1
	var id := ELAdditionalBuildings.spawn_hero(state, template, player, spot.x, spot.y)
	var hero := state.object(id)
	if not title.is_empty(): hero.title = title
	hero.specialization = spec
	if level > 1: state.add_experience(id, ELHeroProgression.threshold(profile, level))
	var record := data(state, player)
	record.summons = int(record.summons) + 1
	state.event.emit({"kind": "hero_placed", "id": id})
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
	hero.merge({"alive": true, "visible": true, "x": spot.x, "y": spot.y, "strategy_order": {}, "intercepted": false, "fortified": false, "fort": -1}, true)
	hero.orders.clear()
	if hero.has("camp"): hero.camp = -1
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
## castle takes the attacker's value as damage.
static func plan_ethereal(director: ELAdventureDirector) -> void:
	var state := director.state
	if not applies(state): return
	var players: Array = state.players.keys()
	players.sort()
	var local_damage := 0
	for player: int in players:
		for spell: Dictionary in data(state, player).get("active", []):
			if spell.code != WARRIOR or spell.get("attacked", false): continue
			spell.attacked = true
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
				var damage := ELFirstScenario.hero_value(attacker)
				state.scenario.castles[target].pending += damage
				state.event.emit({"kind": "castle_spell", "player": target, "spell": WARRIOR, "damage": damage})
				if target == state.current_player: local_damage += damage
	# The local player hears once, with the night's summed ethereal damage.
	if local_damage > 0: ELFirstScenario._box(director, ELFirstScenario.text(state, "T_MB_CASTLE_DAMAGED", "Your castle was attacked and lost %d energy.") % local_damage)

## An ethereal battle kills nobody and gives no experience; a beaten defender's
## castle takes the winner's value.
static func ethereal_result(state: ELAdventureSession, defender_id: int, winner_id: int) -> void:
	if winner_id < 0 or winner_id == defender_id: return
	var owner := int(state.object(defender_id).get("owner", 0))
	if owner < 1 or not state.scenario.get("castles", {}).has(owner): return
	var damage := ELFirstScenario.hero_value(state.object(winner_id))
	state.scenario.castles[owner].pending += damage
	state.event.emit({"kind": "castle_spell", "player": owner, "spell": WARRIOR, "damage": damage})

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
