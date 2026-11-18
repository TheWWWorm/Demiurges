class_name ELFirstAIEconomy
extends RefCounted
## Remake option "smarter computer players" (first game, single player): the
## original computer players only walk to targets and never pick skills, buy
## spells or runes, or cast global spells. With the option they do all of it,
## through the same rules and prices as the player's screens.

## Skills a computer hero learns first; Ethereal Attack and Counterstrike
## have no effect and are never taken while anything else is offered.
## Adaptation (hero upkeep) and Mobility come early: the ether left after
## upkeep is what pays for recruits and global spells.
const SKILL_PRIORITY := ["HEAL", "CONC", "ADPT", "MOBL", "REGN", "PRVD", "MSTR", "ARTF", "SUPR", "CNLG", "LEAR", "BARG", "SRCH"]
## Share of each resource one visit may spend, so the next visit and the
## global spells still have some left.
const SPEND_SHARE := 0.6
## The same for heroes other than the player's leading one, who does the fighting.
const SIDE_SHARE := 0.3
## Purchases that make a trip worthwhile: spells at a shop more than a day
## away, runes at a portal.
const MIN_SPELLS := 2
const MIN_RUNES := 3
## Runes a new spell is priced with at most (the capacity without Provision).
const RUNE_LOAD := 5
const RARITY_WEIGHT := {"Cantrip": 0.8, "Common": 1.0, "Rare": 1.6, "Unique": 2.4}
## Spells are weighed in points: their relative worth among shop spells
## (ELFirstSpellRatings, roughly percentage points of win chance near an
## even duel; a ranking more than an absolute measure). A purchase must
## add at least MIN_GAIN over the copy it replaces. A bought copy that still
## has runes is worth KEEP more than its rating, since replacing it throws
## the runes away; a copy without runes EMPTY less; a second copy of a spell
## SECOND less than the first.
const MIN_GAIN := 5.0
const KEEP := 4.0
const EMPTY := 6.0
const SECOND := 5.0
const SPELLS_PER_VISIT := 3
## Copies of one spell a book may hold (each further copy costs far more).
const MAX_COPIES := 2
## Copies that may wait for runes at once: the rest of the book still works
## if a battle comes before the portal.
const MAX_EMPTY := 4
## Spells of this ether cost or more, and how many a book of fifteen may hold.
const HEAVY_COST := 5
const MAX_HEAVY := 5
## Shops further than this many days of walking are not worth the trip; a
## portal for spells that wait for runes is worth a longer one, and so are
## the first spells of a hero that still has its starting book.
const SHOP_DAYS := 3
const URGENT_DAYS := 6
## A portal asking more than this many times the best known price is left
## for another day: for a copy that still has runes, and for an empty one.
const DEAR_TOP_UP := 2
const DEAR_EMPTY := 6
## Share of each resource a shop upgrade may cost.
const UPGRADE_SHARE := 0.35
## A global spell further than this many days from completion is dropped.
const STALL_DAYS := 12
## Heroes a player keeps, and the daily ether a further one must leave free.
const HEROES := 3
const MORE_HEROES := 4
const SPARE_ETHER := 15
## Reinforcements paid with resources: a player below HEROES whose ether does
## not reach a summoning spell hires one hero every HIRE_DAYS days, at the
## spell's resource price and without its ether. The recruit's level follows
## the leading hero's (champion from REINFORCE_LEVELS[3], hero from [5]).
const HIRE_DAYS := 4
const SUMMON_PREFIX := {"Red": "SC", "Blue": "SK", "Black": "SS", "Green": "SV"}
const REINFORCE_LEVELS := {5: 8, 3: 5, 1: 0}

static func applies(director: ELAdventureDirector) -> bool:
	var state := director.state
	return director.smart_ai and state.map.profile.id == "el1" and director._strategic_players.is_empty() and not state.tutorial

static func is_shop(item: Dictionary) -> bool:
	return item.get("type") in ["el1_spell_shop", "rune_shop"] and item.get("alive", false) and item.get("visible", true) and item.get("enabled", true)

## Once a day per computer player: skills for every hero, then global spells.
static func daily(director: ELAdventureDirector, player: int) -> void:
	if not applies(director): return
	var state := director.state
	for hero: Dictionary in ELFirstAI.heroes_of(state, player): learn_skills(state, hero)
	reinforce(director, player)
	global_spells(director, player)
	upgrade_mines(director, player)

# --- Investment ----------------------------------------------------------------

## Mine upgrades pay back within this many days of the extra output (a first
## upgrade of a root or lotus mine takes about three weeks), and may cost this
## share of each resource held.
const PAYBACK_DAYS := 30
const MINE_SHARE := 0.4

## A held mine is upgraded from the player's own screen (no hero goes there,
## as ELBuildingScreen allows) when the extra output repays the price soon:
## the price over the daily gain, counting only the payments a mine with a
## limited number of them has left.
static func upgrade_mines(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var profile := state.map.profile
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var site := state.object(id)
		if site.get("group") != "mines" or int(site.get("owner", -1)) != player or not site.get("alive", false): continue
		if not ELBuildingScreen.upgrade_problem(state, player, id, true).is_empty(): continue
		var price := ELBuildingScreen.upgrade_price(state, site)
		var cost := _total(price)
		if cost <= 0: continue
		var next := site.duplicate()
		next.level = int(site.level) + 1
		var gain := _total(ELResourceSites.production(profile, next)) - _total(ELResourceSites.production(profile, site))
		if gain <= 0: continue
		var days := PAYBACK_DAYS
		if site.has("mine_remaining"): days = mini(days, int(site.mine_remaining))
		if gain * days < cost: continue
		var stock: Dictionary = state.players[player].resources
		var spare := {}
		for kind: String in stock: spare[kind] = int(floor(int(stock[kind]) * MINE_SHARE))
		if not ELResources.can_pay("el1", spare, price): continue
		ELBuildingScreen.upgrade(state, player, id, true)

# --- Reinforcements ----------------------------------------------------------

## The original gives a computer player a free recruit only when it is down
## to one hero, and the summoning spells need ether that hero upkeep has
## usually eaten. A player short of heroes hires with the resources it holds.
static func reinforce(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var ai := ELFirstAI.data(state, player)
	if ELFirstAI.heroes_of(state, player).size() >= HEROES or int(state.day) - int(ai.get("hired", -HIRE_DAYS)) < HIRE_DAYS: return
	var record := ELGlobalSpells.data(state, player)
	if record.is_empty() or ELGlobalSpells.SUMMONS.has(str(record.production.get("code", ""))): return
	# Only when the ether does not reach a summoning spell: one the player
	# knows and can pay for, whose ether today's and HIRE_DAYS days' income
	# cover, is cast instead (global_spells).
	var reach := ELGlobalSpells.free_ether(state, player) + forecast(state, player) * HIRE_DAYS
	for code: String in ELMapPickups.available_codes(state, player):
		if ELGlobalSpells.SUMMONS.has(code) and ELGlobalSpells.produce_problem(state, player, code).is_empty() and ELGlobalSpells.ether_cost(state, player, code) <= reach: return
	var profile := state.map.profile
	var prefix: String = SUMMON_PREFIX.get(str(state.players[player].get("color", "")), "")
	var lead := int(state.object(int(ai.get("champion", -1))).get("level", 1))
	for level: int in [5, 3, 1]:
		if lead < int(REINFORCE_LEVELS[level]): continue
		var price := {}
		for code: String in ELGlobalSpells.SUMMONS:
			if code.begins_with(prefix) and not prefix.is_empty() and int(ELGlobalSpells.SUMMON_LEVELS.get(code.right(2), 0)) == level: price = ELGlobalSpells.resources(profile, code)
		if level > 1 and price.is_empty(): continue
		if not ELResources.can_pay("el1", state.players[player].resources, price): continue
		# With no room by the castle the search waits for the next turn of hiring.
		ai.hired = int(state.day)
		if ELGlobalSpells.summon(state, player, level, true) < 0: return
		ELResources.pay("el1", state.players[player].resources, price)
		state.event.emit({"kind": "resources_changed", "player": player})
		return

# --- Skills ------------------------------------------------------------------

static func learn_skills(state: ELAdventureSession, hero: Dictionary) -> void:
	var profile := state.map.profile
	for guard in 16:
		var offers: Array = ELHeroSkills.prepare(profile, hero)
		if offers.is_empty(): return
		var best := ""
		var best_rank := 1 << 30
		for code: String in offers:
			var rank := SKILL_PRIORITY.find(code) * 2
			# Ethereal Attack raises the castle damage every siege counts on;
			# Counterstrike only pays when the castle is attacked ethereally.
			if code == "ETAT": rank = SKILL_PRIORITY.find("MOBL") * 2 + 1
			elif code == "ETDF": rank = SKILL_PRIORITY.size() * 2
			if rank < 0: rank = 1000
			if rank < best_rank:
				best_rank = rank
				best = code
		if not ELHeroSkills.choose(profile, hero, best).is_empty(): return
		state.event.emit({"kind": "skill_learned", "id": hero.uid, "code": best, "rank": hero.skills[best]})

# --- Shops -------------------------------------------------------------------

## Worth of a spell from its ether cost and rarity alone.
static func base_value(profile: ELProfile, card: String) -> float:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	return (float(row.get("Cost", 1)) + 1.0) * float(RARITY_WEIGHT.get(row.get("Rarity", ""), 1.0))

## Worth of a spell in points. Starting spells (cantrips) are the baseline,
## the cheapest lowest so that they are replaced first. A shop spell without
## a measurement is guessed from its cost and rarity.
static func spell_value(profile: ELProfile, card: String) -> float:
	if ELFirstSpellRatings.POINTS.has(card): return float(ELFirstSpellRatings.POINTS[card]) / 10.0
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	if row.get("Rarity") == "Cantrip": return (float(row.get("Cost", 1)) - 1.0) * 0.5
	return clampf(base_value(profile, card) - 3.0, -2.0, 8.0)

static func _budget(state: ELAdventureSession, hero: Dictionary) -> Dictionary:
	var result := {}
	var player := int(hero.owner)
	var share := SPEND_SHARE if ELFirstAI.commander_id(state, player) == int(hero.uid) else SIDE_SHARE
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock: result[kind] = int(floor(int(stock[kind]) * share))
	return result

static func _total(bill: Dictionary) -> int:
	var result := 0
	for kind: String in bill: result += int(bill[kind])
	return result

## How many purchases a visit to `shop` would make now (0: no reason to go).
## A spell shop whose stock offers nothing is still worth a visit when the
## visit can upgrade it to stock that helps (see visit).
static func wants(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> int:
	if not applies(director) or not is_shop(shop): return 0
	var count := _shop(director.state, hero, shop, false)
	if count == 0 and shop.type == "el1_spell_shop" and _upgrade_affordable(director.state, hero, shop): count = mini(SPELLS_PER_VISIT, _next_stock_helps(director.state, hero, shop))
	return count

## Whether a visit could pay for this shop's next level once it has captured
## it (the visit captures before it upgrades).
static func _upgrade_affordable(state: ELAdventureSession, hero: Dictionary, shop: Dictionary) -> bool:
	var player := int(hero.owner)
	if int(shop.get("level", 0)) >= 2 or not state.players.has(player): return false
	var colour := str(state.players[player].get("color", ""))
	var row := ELBuildings.definition(state.map.profile, shop)
	if row.is_empty() or not row.has(colour + "UpgradeCost"): return false
	var next := shop.duplicate()
	next.level = int(shop.level) + 1
	if ELBuildings.definition(state.map.profile, next).is_empty(): return false
	var spare := {}
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock: spare[kind] = int(floor(int(stock[kind]) * UPGRADE_SHARE))
	return ELResources.can_pay("el1", spare, ELBuildings.upgrade_price(state.map.profile, shop, colour))

## Quote a small number of purchases against the guard that blocks expansion.
## Return purchases supported by trial duels, including an interim upgrade
## when paired trials improve enough. Price the spell and its runes together.
static func matchup_purchase(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary, guard: Dictionary, refill: Array = []) -> Dictionary:
	if not is_shop(shop) or not guard.get("alive", false): return {}
	var state := director.state
	var goal := {"kind": "monster", "target": int(guard.uid)}
	if ELFirstAI.forecast_objective(director, hero, goal): return {}
	var profile := state.map.profile
	var budget := _budget(state, hero)
	var attempts := {"remaining": 2}
	if shop.type == "rune_shop":
		var slots: Array = range(hero.cards.size())
		slots.sort_custom(func(a: int, b: int): return spell_value(profile, hero.cards[a]) > spell_value(profile, hero.cards[b]))
		var preferred := -1
		if refill.size() == 3 and int(refill[0]) in slots and hero.cards[int(refill[0])] == refill[1]:
			preferred = int(refill[0])
			slots.erase(preferred)
			slots.push_front(preferred)
		for slot: int in slots:
			var uses := int(hero.rune_uses[slot])
			if uses < 0 or uses >= ELRunes.capacity(hero): continue
			var price := ELRuneShop.price(profile, hero, shop, hero.cards[slot])
			if _total(price) <= 0: continue
			var limit := ELRunes.capacity(hero) - uses
			if slot == preferred: limit = mini(limit, maxi(0, int(refill[2]) - uses))
			var amount := _affordable_runes(budget, price, limit)
			if amount == 0: continue
			var preview := hero.duplicate(true)
			preview.rune_uses[slot] += amount
			ELFirstAI.note_stat(director, int(hero.owner), "affordable_upgrade")
			if ELFirstAI.upgrade_improves_guard(director, hero, preview, guard, attempts): return {"slot": slot, "amount": amount}
			if int(attempts.remaining) <= 0: break
		return {}
	var stock := ELFirstSpellShop.authored_stock(profile, shop, ELFirstSpellShop.hero_color(profile, hero))
	stock.sort_custom(func(a: String, b: String): return spell_value(profile, a) > spell_value(profile, b))
	var portals: Variant = null
	var checked := {}
	for card: String in stock:
		if checked.has(card) or hero.cards.count(card) >= MAX_COPIES or ELCatalog.rule(profile, card).is_empty(): continue
		checked[card] = true
		var slot := _replacement_slot(state, hero, card)
		if slot < 0: continue
		var price := ELFirstSpellShop.price(profile, hero, hero.cards, card, slot, state.map.id.begins_with("mission17") or state.map.id.begins_with("mission27"))
		if not ELResources.can_pay("el1", budget, price): continue
		var after := budget.duplicate()
		ELResources.pay("el1", after, price)
		var uses := -1
		var portal_id := -1
		if not ELRunes.unlimited(profile, hero, card):
			if state.map.id.begins_with("mission17") or state.map.id.begins_with("mission27"): uses = 100000
			else:
				if portals == null: portals = _portals(state, int(hero.owner), hero)
				uses = 0
				for portal: Dictionary in portals:
					var unit := ELRuneShop.price(profile, hero, portal, card)
					if _total(unit) <= 0: continue
					var amount := _affordable_runes(after, unit, mini(RUNE_LOAD, ELRunes.capacity(hero)))
					if amount <= uses or ELFirstAI._route_cost(director, hero, portal, true, true) == ELFirstAI.NONE: continue
					uses = amount
					portal_id = int(portal.uid)
				if uses == 0: continue
		var preview := hero.duplicate(true)
		var under := ELRunes.under(hero)
		if uses < 0: under[slot] = ""
		elif ELRunes.unlimited(profile, hero, hero.cards[slot]): under[slot] = hero.cards[slot]
		preview.cards[slot] = card
		preview.rune_uses[slot] = uses
		ELRunes.set_under(preview, under)
		ELFirstAI.note_stat(director, int(hero.owner), "affordable_upgrade")
		if ELFirstAI.upgrade_improves_guard(director, hero, preview, guard, attempts): return {"slot": slot, "spell": card, "portal": portal_id, "uses": uses}
		if int(attempts.remaining) <= 0: break
	return {}

static func _affordable_runes(budget: Dictionary, unit: Dictionary, limit: int) -> int:
	var amount := limit
	for resource: String in unit:
		if int(unit[resource]) > 0: amount = mini(amount, int(budget.get(resource, 0)) / int(unit[resource]))
	return amount

static func _replacement_slot(state: ELAdventureSession, hero: Dictionary, card: String) -> int:
	var slot := -1
	var weakest := INF
	for index in hero.cards.size():
		if hero.cards[index] == card: continue
		var points := spell_value(state.map.profile, hero.cards[index])
		if int(hero.rune_uses[index]) == 0: points -= EMPTY
		elif int(hero.rune_uses[index]) > 0: points += KEEP
		if points < weakest:
			weakest = points
			slot = index
	return slot

## Requote on arrival. A lost guard or changed price invalidates the old
## plan. Actual purchases go through the ordinary shop transactions.
static func _visit_for_matchup(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary, task: Dictionary, assigned: Array) -> void:
	var state := director.state
	var guard := state.object(task.guard)
	var plan := matchup_purchase(director, hero, shop, guard, task.get("refill", []))
	var purchased := false
	if plan.has("spell"):
		var trade := ELFirstSpellShop.new()
		purchased = trade.open(state, int(hero.uid), int(shop.uid), true, int(hero.owner)) and trade.replace(int(plan.slot), str(plan.spell)) and trade.commit()
	elif plan.has("amount"):
		var trade := ELRuneShop.new()
		purchased = trade.open(state, int(hero.uid), int(shop.uid), true, int(hero.owner)) and trade.set_amount(int(plan.slot), int(plan.amount)) and trade.commit()
	if purchased:
		ELBuildings.capture(state, shop, int(hero.owner))
		ELFirstAI.note_stat(director, int(hero.owner), "matchup_purchase")
	var next := int(plan.get("portal", -1))
	var kind := "shop" if next >= 0 else "monster"
	if next < 0: next = int(task.guard)
	var reserved := assigned.any(func(pair: Array) -> bool: return int(pair[0]) != int(hero.uid) and pair[1].get("kind") == kind and int(pair[1].get("target", -1)) == next)
	var kept: Dictionary = {"kind": kind, "target": next}
	if kind == "shop":
		kept.guard = int(task.guard)
		kept.refill = [int(plan.slot), str(plan.spell), int(plan.uses)]
	var ready: bool = purchased or (guard.get("alive", false) and ELFirstAI.forecast_objective(director, hero, kept))
	for index in assigned.size():
		var pair: Array = assigned[index]
		if int(pair[0]) != int(hero.uid): continue
		if ready and not reserved: pair[1] = kept
		else: assigned.remove_at(index)
		break

## The hero stands beside the shop: buy, as the player's screen would. A
## player with resources to spare then upgrades the shop.
static func visit(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> void:
	var state := director.state
	if not applies(director):
		ELBuildings.capture(state, shop, int(hero.owner))
		return
	var assigned: Array = ELFirstAI.data(state, int(hero.owner)).assigned
	for pair: Array in assigned:
		var task: Dictionary = pair[1]
		if int(pair[0]) == int(hero.uid) and task.get("kind") == "shop" and int(task.get("target", -1)) == int(shop.uid) and task.has("guard"):
			_visit_for_matchup(director, hero, shop, task, assigned)
			return
	# A portal whose upgrade the visit would pay anyway is upgraded first when
	# its cheaper runes buy at least as many.
	if shop.type == "rune_shop" and _upgrade_first(state, hero, shop):
		ELBuildings.capture(state, shop, int(hero.owner))
		if _upgrade(state, hero, shop):
			_shop(state, hero, shop, true)
			return
	var bought := _shop(state, hero, shop, true)
	ELBuildings.capture(state, shop, int(hero.owner))
	# A spell shop is upgraded for what its next level sells this hero, a
	# portal once it has sold runes (its next level sells them cheaper).
	if shop.type == "el1_spell_shop":
		if _next_stock_helps(state, hero, shop) > 0 and _upgrade(state, hero, shop): _shop(state, hero, shop, true)
	elif bought > 0: _upgrade(state, hero, shop)

## Whether upgrading the portal before buying its runes does better than
## buying first: both orders are priced (the second on the portal one level
## up, with the upgrade's price already paid), and the upgrade comes first
## when it is affordable now and its runes are at least as many.
static func _upgrade_first(state: ELAdventureSession, hero: Dictionary, portal: Dictionary) -> bool:
	var player := int(hero.owner)
	if int(portal.get("level", 0)) >= 2 or not state.players.has(player): return false
	var colour := str(state.players[player].get("color", ""))
	var row := ELBuildings.definition(state.map.profile, portal)
	if row.is_empty() or not row.has(colour + "UpgradeCost"): return false
	var next := portal.duplicate()
	next.level = int(portal.level) + 1
	if ELBuildings.definition(state.map.profile, next).is_empty(): return false
	var price := ELBuildings.upgrade_price(state.map.profile, portal, colour)
	var stock: Dictionary = state.players[player].resources
	var spare := {}
	for kind: String in stock: spare[kind] = int(floor(int(stock[kind]) * UPGRADE_SHARE))
	if not ELResources.can_pay("el1", spare, price): return false
	var now := _runes(state, hero, portal, false)
	if now <= 0: return false
	# The other order, priced on plain data: the portal a level up and the
	# purchase budget after the upgrade (restored at once; no script runs).
	var saved := stock.duplicate()
	var level := int(portal.level)
	ELResources.pay("el1", stock, price)
	portal.level = level + 1
	var later := _runes(state, hero, portal, false)
	portal.level = level
	for kind: String in saved: stock[kind] = saved[kind]
	return later >= now

## How many spells this hero would buy at the shop's next level: the
## purchase rules of _spells (a spell that needs runes only with a reachable
## portal, the budget, the copy limits), priced on plain data with the shop a
## level up and the upgrade's price already paid (restored at once; no
## script runs).
static func _next_stock_helps(state: ELAdventureSession, hero: Dictionary, shop: Dictionary) -> int:
	var player := int(hero.get("owner", -1))
	if int(shop.get("level", 0)) >= 2 or hero.get("cards", []).is_empty() or not state.players.has(player): return 0
	var next := shop.duplicate()
	next.level = int(shop.level) + 1
	if ELBuildings.definition(state.map.profile, next).is_empty(): return 0
	var price := ELBuildings.upgrade_price(state.map.profile, shop, str(state.players[player].get("color", "")))
	var stock: Dictionary = state.players[player].resources
	if not ELResources.can_pay("el1", stock, price): return 0
	var saved := stock.duplicate()
	var level := int(shop.level)
	ELResources.pay("el1", stock, price)
	shop.level = level + 1
	var count := _spells(state, hero, shop, false)
	shop.level = level
	for kind: String in saved: stock[kind] = saved[kind]
	return count

static func _upgrade(state: ELAdventureSession, hero: Dictionary, shop: Dictionary) -> bool:
	var player := int(hero.owner)
	if not ELBuildings.upgrade_problem(state, int(hero.uid), int(shop.uid), player).is_empty(): return false
	var spare := {}
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock: spare[kind] = int(floor(int(stock[kind]) * UPGRADE_SHARE))
	if not ELResources.can_pay("el1", spare, ELBuildings.upgrade_price(state.map.profile, shop, str(state.players[player].color))): return false
	return ELBuildings.upgrade(state, int(hero.uid), int(shop.uid), player)

static func _shop(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, commit: bool) -> int:
	if hero.get("type") != "hero" or not hero.get("alive", false) or not state.players.has(int(hero.owner)): return 0
	return _spells(state, hero, shop, commit) if shop.type == "el1_spell_shop" else _runes(state, hero, shop, commit)

## Spell shop: the stock spells that add most to the book (see MIN_GAIN)
## replace its weakest copies. A spell that needs runes arrives empty, so it is bought only when the player knows
## a component portal and can also pay for its runes there, and never while
## too many copies of the book are already waiting for runes. Expensive
## spells are kept to a third of the book.
static func _spells(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, commit: bool) -> int:
	var profile := state.map.profile
	var player := int(hero.owner)
	var trade := ELFirstSpellShop.new()
	if not trade.open(state, int(hero.uid), int(shop.uid), not commit, player): return 0
	var portals := _portals(state, player, hero)
	var budget := _budget(state, hero)
	var spells: Dictionary = profile.table("CombatSpells")
	var stock: Array[String] = []
	for card: String in trade.stock: if not stock.has(card): stock.append(card)
	stock.sort_custom(func(a: String, b: String): return spell_value(profile, a) > spell_value(profile, b))
	var worth: Array[float] = []
	var loaded: Array[bool] = []
	var empty := 0
	var heavy := 0
	for slot in trade.cards.size():
		var card: String = trade.cards[slot]
		var live := ELRunes.unlimited(profile, hero, card) or int(trade.uses[slot]) > 0
		loaded.append(live)
		if not live: empty += 1
		if int(spells.get(card, {}).get("Cost", 0)) >= HEAVY_COST: heavy += 1
		# A copy without runes is dead weight unless a known portal can refill it.
		var points := spell_value(profile, card)
		if not live: points -= EMPTY if not portals.is_empty() else 100.0
		elif int(trade.uses[slot]) > 0: points += KEEP
		worth.append(points)
	var bought := 0
	var refill := ELResources.empty("el1")
	for card: String in stock:
		if bought >= SPELLS_PER_VISIT: break
		var cantrip := ELRunes.unlimited(profile, hero, card)
		if not cantrip and portals.is_empty(): continue
		if trade.cards.count(card) >= MAX_COPIES: continue
		var costly := int(spells.get(card, {}).get("Cost", 0)) >= HEAVY_COST
		var weakest := -1
		for slot in worth.size():
			if not trade.pending[slot].is_empty(): continue
			if weakest < 0 or worth[slot] < worth[weakest]: weakest = slot
		var gain := spell_value(profile, card) - (SECOND if trade.cards.has(card) else 0.0)
		if weakest < 0 or trade.cards[weakest] == card or gain < worth[weakest] + MIN_GAIN: continue
		var replaced_costly := int(spells.get(trade.cards[weakest], {}).get("Cost", 0)) >= HEAVY_COST
		if costly and not replaced_costly and heavy >= MAX_HEAVY: continue
		# The new copy takes the place of a working one: one more waits for runes.
		if not cantrip and loaded[weakest] and empty >= MAX_EMPTY: continue
		if not trade.replace(weakest, card): continue
		var bill := trade.bill()
		var runes := ELResources.empty("el1")
		var total := {}
		# A spell that needs runes is priced with as many as the budget allows
		# beside it: a base load at most (more room for runes never makes a
		# purchase dearer) and one at least. The portal visit buys the rest.
		var unit := _rune_price(state, hero, portals, card) if not cantrip else ELResources.empty("el1")
		var fits := false
		for count in range(mini(ELRunes.capacity(hero), RUNE_LOAD) if not cantrip else 0, -1 if cantrip else 0, -1):
			total = {}
			for kind: String in bill: total[kind] = int(bill[kind]) + int(refill.get(kind, 0)) + int(unit.get(kind, 0)) * count
			if ELResources.can_pay("el1", budget, total):
				for kind: String in runes: runes[kind] = int(unit[kind]) * count
				fits = true
				break
		if not fits:
			trade.clear(weakest)
			continue
		for kind: String in refill: refill[kind] = int(refill[kind]) + int(runes[kind])
		if not cantrip and loaded[weakest]: empty += 1
		if costly and not replaced_costly: heavy += 1
		bought += 1
	if bought > 0 and commit and not trade.commit(): return 0
	if not commit: trade.cancel()
	return bought

## Component portal: refill the most valuable spells first, within budget.
## Each portal sells runes of its own rarity cheaply and the others dearly:
## a copy that still works waits for the right portal, an empty one accepts
## a moderately dearer price.
static func _runes(state: ELAdventureSession, hero: Dictionary, portal: Dictionary, commit: bool) -> int:
	var profile := state.map.profile
	var player := int(hero.owner)
	var trade := ELRuneShop.new()
	if not trade.open(state, int(hero.uid), int(portal.uid), not commit, player): return 0
	var portals := _portals(state, player, hero)
	var budget := _budget(state, hero)
	var slots: Array = range(hero.cards.size())
	slots.sort_custom(func(a: int, b: int): return spell_value(profile, hero.cards[a]) > spell_value(profile, hero.cards[b]))
	var capacity := ELRunes.capacity(hero)
	var total := 0
	for slot: int in slots:
		var uses := int(hero.rune_uses[slot])
		if uses < 0 or uses >= capacity: continue
		var here := _total(trade.quote(slot))
		var best := _total(_rune_price(state, hero, portals, hero.cards[slot]))
		if here > best * (DEAR_EMPTY if uses == 0 else DEAR_TOP_UP): continue
		var amount := capacity - uses
		while amount > 0:
			if trade.set_amount(slot, amount) and ELResources.can_pay("el1", budget, trade.bill()): break
			amount -= 1
		if amount <= 0: trade.set_amount(slot, 0)
		total += maxi(0, amount)
	if total > 0 and commit and not trade.commit(): return 0
	if not commit: trade.cancel()
	return total

## Component portals the player has seen and, with `hero`, that the hero can
## walk to: a spell priced with its runes is no use if no portal is reachable.
static func _portals(state: ELAdventureSession, player: int, hero := {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		if item.get("type") == "rune_shop" and is_shop(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)):
			if hero.is_empty() or reachable(state, hero, item): result.append(item)
	return result

## Reachability answers of the current planning pass (ELFirstAI.plan_player
## opens and closes it); outside a pass every question walks the grid.
static var _reach: Variant = null

static func begin_pass() -> void:
	_reach = {}

static func end_pass() -> void:
	_reach = null

## Whether `hero` has a route beside `item` (over the tiles open now).
static func reachable(state: ELAdventureSession, hero: Dictionary, item: Dictionary) -> bool:
	if state.grid == null: return true
	var from := Vector2i(int(hero.x), int(hero.y))
	var key := "%d:%d:%d" % [int(item.uid), from.x, from.y]
	if _reach is Dictionary and _reach.has(key): return _reach[key]
	var size: Vector2i = state.grid.footprints.get(int(item.uid), {}).get("size", Vector2i.ONE)
	var found := Rect2i(int(item.x) - 1, int(item.y) - 1, size.x + 2, size.y + 2).has_point(from) or not state.grid.approach(from, item).is_empty()
	if _reach is Dictionary: _reach[key] = found
	return found

## The lowest price of one rune of `card` among `portals`.
static func _rune_price(state: ELAdventureSession, hero: Dictionary, portals: Array[Dictionary], card: String) -> Dictionary:
	var best := ELResources.empty("el1")
	var found := false
	for portal: Dictionary in portals:
		var price := ELRuneShop.price(state.map.profile, hero, portal, card)
		if not found or _total(price) < _total(best): best = price
		found = true
	return best

## Copies of the hero's book that need runes and have none.
static func empty_copies(hero: Dictionary) -> int:
	var count := 0
	for uses: Variant in hero.get("rune_uses", []):
		if int(uses) == 0: count += 1
	return count

## Whether the book holds nothing but spells that need no runes.
static func starting_book(hero: Dictionary) -> bool:
	for uses: Variant in hero.get("rune_uses", []):
		if int(uses) >= 0: return false
	return true

## Share of the hero's rune-using copies that still have runes (1: all full or none needed).
static func rune_health(state: ELAdventureSession, hero: Dictionary) -> float:
	var used := 0
	var total := 0
	for slot in hero.get("cards", []).size():
		var uses := int(hero.rune_uses[slot]) if slot < hero.get("rune_uses", []).size() else -1
		if uses < 0: continue
		total += ELRunes.capacity(hero)
		used += mini(uses, ELRunes.capacity(hero))
	return 1.0 if total == 0 else float(used) / total

## Planning cost of a trip `route` movement points long to a shop that would
## sell `count` spells or runes (-1: not worth it). A hero whose new spells
## wait for runes goes to a portal before anything else and from further
## away; otherwise runes are topped up once half are gone, or on the way
## (within half a day) whenever any are missing. A spell shop is
## worth a detour for several spells, or for one when it is close by.
static func trip_cost(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, route: int, count: int) -> int:
	var day := maxi(1, int(hero.get("strategy_capacity", 1)))
	if shop.get("type") == "rune_shop":
		# A few runes are worth a stop on the spot or close by, and within a
		# day when they bring an empty spell back.
		if count <= 0: return -1
		if empty_copies(hero) > 0:
			if count < MIN_RUNES and route > day: return -1
			return route / 8 if route <= URGENT_DAYS * day else -1
		if route <= day / 2: return route / 4
		if count < MIN_RUNES: return -1
		return route / 4 if rune_health(state, hero) < 0.5 and route <= SHOP_DAYS * day else -1
	# A hero that has never shopped goes further for its first spells.
	if count >= MIN_SPELLS and starting_book(hero): return route / 4 if route <= URGENT_DAYS * day else -1
	if route > SHOP_DAYS * day or (count < MIN_SPELLS and route > day): return -1
	return route

## A hero with spells waiting for runes leaves its errand for a portal, when
## a portal it can reach would refill one of them within its budget. An
## empty copy is not a dead card (an EL1 draw of it gives a cantrip instead,
## ELSpellCharges.choose_el1), so a refill that cannot happen yet changes no
## errand.
static func urgent(director: ELAdventureDirector, hero: Dictionary) -> bool:
	if not applies(director) or empty_copies(hero) == 0: return false
	var state := director.state
	var portals := _portals(state, int(hero.owner), hero)
	if portals.is_empty(): return false
	var budget := _budget(state, hero)
	for slot in hero.get("cards", []).size():
		if slot >= hero.rune_uses.size() or int(hero.rune_uses[slot]) != 0: continue
		var price := _rune_price(state, hero, portals, str(hero.cards[slot]))
		if _total(price) > 0 and ELResources.can_pay("el1", budget, price): return true
	return false

# --- Global spells -------------------------------------------------------------

## Spells the computer leaves alone: forts, ethereal duels, remote shops,
## recalls and the rest whose use needs a player's judgement. Of the castle
## enchantments it casts the shields, the regeneration boosts, Decay, Erosion,
## Terminal Discharge, Disenchant and Disjunction; it leaves Shock Resonance
## (which strikes its own castle too), Ether Calm (which would also stop the
## Warriors it leaves to the players, and the tomb), Visions, Ether Leak
## (worthless without extra ether), Spell Blast (it would need Visions to
## aim) and the ethereal-battle rewards (it makes no ethereal attacks, and
## an attack on it is seen only the night it comes).
const ENCHANTMENTS := ["ERBR", "SHIC", "ICBR", "AURP", "WTWL", "MSRP", "BLED", "FRGT", "CLPS", "DSLC", "DSGB"]

static func _usable(code: String) -> bool:
	return ELGlobalSpells.REPAIRS.has(code) or ELGlobalSpells.CASTLE_DAMAGE.has(code) or ELGlobalSpells.RITUALS.has(code) or ELGlobalSpells.SUMMONS.has(code) or ELGlobalSpells.HERO_BUFFS.has(code) or ELGlobalSpells.BATTLE_EFFECTS.has(code) or ENCHANTMENTS.has(code)

## Whether the computer ever casts the global spell `code` (global_spells).
static func castable(code: String) -> bool:
	return _usable(code)

## Ether a player keeps each day after hero and spell upkeep (see forecast).
static func _daily_ether(state: ELAdventureSession, player: int) -> int:
	return forecast(state, player)

## The free ether of the next settlement, as the rules will pay it: hero
## upkeep in the owned-hero order of ELStrategy.allocation (a hero whose upkeep
## no longer fits is skipped and costs nothing), then the upkeep of active
## spells in cast order as ELGlobalSpells.settle keeps them (a spell that no
## longer fits is dropped). `extra` heroes ({level, skills}) join at the end
## of the hero order, as a recruit does; `extra_spell` is the upkeep of one
## more spell cast last.
static func forecast(state: ELAdventureSession, player: int, extra: Array = [], extra_spell := 0) -> int:
	if not state.players.has(player): return 0
	var heroes: Array = []
	for actor: Dictionary in state.objects.values():
		if actor.get("type") == "hero" and actor.get("alive", false) and int(actor.get("owner", -1)) == player: heroes.append(actor)
	heroes.append_array(extra)
	var budget := ELStrategy.allocation(state.map.profile, ELResourceSites.mana_income(state, player), heroes)
	var income := int(budget.income)
	var used := int(budget.spent)
	for spell: Dictionary in ELGlobalSpells.data(state, player).get("active", []):
		var hero := state.object(int(spell.get("hero", -1)))
		if int(spell.get("hero", -1)) >= 0 and not hero.get("alive", false): continue
		if spell.get("code") == ELGlobalSpells.WARRIOR: continue
		var cost := ELGlobalSpells.upkeep(state.map.profile, str(spell.code))
		if income >= used + cost: used += cost
	if extra_spell > 0 and income >= used + extra_spell: used += extra_spell
	return maxi(0, income - used)

## The player's castle energy after tonight when `spend` of today's free
## ether goes elsewhere (the rest regenerates the castle before the night) and
## a cast lowers the pending damage by `repair` (ELFirstScenario.regenerate,
## then end_night). The assaults that may still come tonight count as well
## (impending). A large number when the player has no castle record.
static func night_health(state: ELAdventureSession, player: int, spend := 0, repair := 0) -> int:
	var castle: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if castle.is_empty() or not castle.get("alive", false): return 1 << 20
	var free := ELGlobalSpells.free_ether(state, player)
	var regenerated := mini(int(castle.max), int(castle.health) + ELFirstScenario.regained(state, player, maxi(0, free - spend)))
	return clampi(regenerated - (int(castle.pending) + impending(state, player) - repair), 0, int(castle.max))

## Castle damage the enemy heroes the player sees may still deal tonight: each
## one beside its castle, or within its movement left of it (a point a tile
## at least), strikes once with its value (ELFirstScenario.assault).
static func impending(state: ELAdventureSession, player: int) -> int:
	var castle := ELFirstScenario.castle_object(state, player)
	if castle.is_empty(): return 0
	var size: Vector2i = state.grid.footprints.get(int(castle.uid), {}).get("size", Vector2i.ONE) if state.grid != null else Vector2i.ONE
	var area := Rect2i(int(castle.x), int(castle.y), size.x, size.y)
	var total := 0
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or not item.get("alive", false) or int(item.get("owner", -1)) < 1 or int(item.owner) == player: continue
		if not ELFirstAI.observed(state, player, item) or not state.hostile(item, castle) or ELGlobalSpells.held(item): continue
		if ELFirstAIPlanner._lower_bound(item, area) <= maxi(0, int(item.get("ap", 0))): total += ELFirstScenario.taken(state, player, ELFirstScenario.hero_value(item))
	return total

## Once a day: a finished spell is cast, then the next one is chosen and, when
## today's ether completes it, cast at once. Each production is followed by
## its cast, so a spell finished today (an emergency repair) is never left
## waiting; SPELL_ROUNDS bounds the day's productions.
const SPELL_ROUNDS := 4

static func global_spells(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	if not ELGlobalSpells.applies(state): return
	var record := ELGlobalSpells.data(state, player)
	if record.is_empty(): return
	_prune(state, player)
	var produced := 0
	for step in 2 * SPELL_ROUNDS + 1:
		if not record.production.is_empty():
			if int(record.production.get("state", 0)) == 2:
				# A spell that cannot act now (a summons with no room by the
				# castle) waits, finished, for another day.
				if not _cast(director, player): return
				continue
			# A spell the ether income can no longer finish gives its resources
			# back (the ether invested is lost).
			if turns_left(state, player) <= STALL_DAYS or not ELGlobalSpells.cancel(state, player): return
		if produced >= SPELL_ROUNDS: return
		var best := _choose(director, player)
		if best.is_empty() or not ELGlobalSpells.produce(state, player, best): return
		produced += 1
		if int(record.production.get("state", 0)) != 2: return

## Days until the production is finished, with the ether forecast() expects
## each day (the spells whose upkeep no longer fits are dropped, as the
## settlement drops them); TURNS_UNKNOWN when no ether comes.
static func turns_left(state: ELAdventureSession, player: int) -> int:
	var production: Dictionary = ELGlobalSpells.data(state, player).get("production", {})
	if production.is_empty(): return 0
	var remaining := int(production.cost) - int(production.spent)
	if remaining <= 0: return 0
	var daily := forecast(state, player)
	return ELGlobalSpells.TURNS_UNKNOWN if daily <= 0 else ceili(float(remaining) / daily)

## The spell to produce now, or "". Today's free ether (what is left to invest
## now) and the daily forecast are weighed apart: a day without income can
## still finish a spell with the ether in hand. Spending must not cost the
## castle the night when keeping the ether for regeneration would save it.
static func _choose(director: ELAdventureDirector, player: int) -> String:
	var state := director.state
	var daily := forecast(state, player)
	var free := ELGlobalSpells.free_ether(state, player)
	if daily <= 0 and free <= 0: return ""
	var keep := night_health(state, player)
	var best := ""
	var best_score := 0.0
	for code: String in ELMapPickups.available_codes(state, player):
		if not _usable(code) or not ELGlobalSpells.produce_problem(state, player, code).is_empty(): continue
		var cost := ELGlobalSpells.ether_cost(state, player, code)
		# Upkeep must leave most of the income, and the ether must come within about a week.
		var upkeep := ELGlobalSpells.upkeep(state.map.profile, code)
		if upkeep > 0 and upkeep * 2 > daily: continue
		if cost - free > daily * 8: continue
		var spend := mini(free, cost)
		var repair := int(ELGlobalSpells.REPAIRS.get(code, 0)) if cost <= free else 0
		var after := night_health(state, player, spend, repair)
		if after <= 0 and keep > 0: continue
		var score := _score(director, player, code)
		# A repair finished today must beat the energy the ether would regenerate.
		if repair > 0 and after <= keep: score = 0.0
		if score > best_score:
			best_score = score
			best = code
	return best

static func _score(director: ELAdventureDirector, player: int, code: String) -> float:
	var state := director.state
	var castles: Dictionary = state.scenario.get("castles", {})
	var own: Dictionary = castles.get(player, {})
	var active: Array = ELGlobalSpells.data(state, player).get("active", [])
	if ELGlobalSpells.REPAIRS.has(code):
		return 100.0 if not own.is_empty() and int(own.max) - int(own.health) + int(own.pending) >= int(ELGlobalSpells.REPAIRS[code]) else 0.0
	if ELGlobalSpells.CASTLE_DAMAGE.has(code): return 60.0 + int(ELGlobalSpells.CASTLE_DAMAGE[code]) if _weakest_enemy(state, player) >= 0 else 0.0
	if ELGlobalSpells.SUMMONS.has(code):
		# The most experienced recruit the ether allows; its upkeep must fit the
		# income, and a hero beyond the usual number must leave ether to spare.
		var count := ELFirstAI.heroes_of(state, player).size()
		var level := int(ELGlobalSpells.SUMMON_LEVELS.get(code.right(2), 1))
		# The recruit needs a free tile beside the castle (or the spell is
		# used up with no hero).
		if ELGlobalSpells.castle_spot(state, player) == ELGlobalSpells.NO_SPOT: return 0.0
		# The recruit joins at the end of the upkeep order: when its upkeep no
		# longer fits it goes unpaid, which costs nothing (ELStrategy.allocation).
		var left := forecast(state, player, [{"type": "hero", "level": level, "skills": {}}])
		if count >= MORE_HEROES or (count >= HEROES and left < SPARE_ETHER): return 0.0
		return (90.0 if count < 2 else 50.0) + level
	if ELGlobalSpells.RITUALS.has(code):
		for spell: Dictionary in active: if spell.code == code: return 0.0
		return 40.0 if int(state.day) < 25 else 10.0
	if ELGlobalSpells.HERO_BUFFS.has(code):
		# None for a commander whose own skill already gives what the spell
		# would (ELGlobalSpells.battle_choice).
		var champion := state.object(ELFirstAI.commander_id(state, player))
		return 30.0 if not champion.is_empty() and not ELGlobalSpells.hero_has(champion, code) and ELGlobalSpells.buff_works(champion, code) else 0.0
	if ELGlobalSpells.BATTLE_EFFECTS.has(code):
		for spell: Dictionary in active: if spell.code == code: return 0.0
		return 25.0
	if not ENCHANTMENTS.has(code) or own.is_empty(): return 0.0
	for spell: Dictionary in active:
		# One of each on the own castle is enough.
		if spell.code == code and not ELGlobalSpells.HOSTILE_CASTLE.has(code): return 0.0
	if ELGlobalSpells.SHIELDS.has(code) or ELGlobalSpells.FRIENDLY_SHIELDS.has(code):
		return 35.0 + int(ELGlobalSpells.SHIELDS.get(code, ELGlobalSpells.FRIENDLY_SHIELDS.get(code, 0))) if _threatened(state, player) else 0.0
	if ELGlobalSpells.REGEN_BOOSTS.has(code) or ELGlobalSpells.FRIENDLY_REGEN.has(code):
		# The upkeep comes out of the very ether that regenerates the castle:
		# only a boost that still regains more than today's rate is worth it.
		if int(own.health) - int(own.pending) >= int(own.max): return 0.0
		var now := ELFirstScenario.regained(state, player, forecast(state, player))
		var boosted := ELFirstScenario.regained(state, player, forecast(state, player, [], ELGlobalSpells.upkeep(state.map.profile, code)), code)
		return 20.0 if boosted > now else 0.0
	if code == ELGlobalSpells.DECAY or code == ELGlobalSpells.EROSION:
		# On the weakest enemy castle, once it is damaged and not already cursed so.
		var enemy := _weakest_enemy(state, player)
		if enemy < 0 or ELGlobalSpells.on_castle(state, enemy, code): return 0.0
		var castle: Dictionary = castles[enemy]
		return (30.0 if code == ELGlobalSpells.DECAY else 28.0) if int(castle.health) - int(castle.pending) < int(castle.max) else 0.0
	if code == ELGlobalSpells.DISCHARGE:
		# Half the own energy goes: only from a castle well out of danger.
		var paid := int(own.health) / 2
		if _weakest_enemy(state, player) < 0 or paid < 3 or _threatened(state, player): return 0.0
		return 55.0 if night_health(state, player) - paid > int(own.max) / 2 else 0.0
	if code == ELGlobalSpells.DISENCHANT:
		for entry: Dictionary in ELGlobalSpells.acting_on(state, player):
			if int(entry.owner) != player and entry.spell.code != ELGlobalSpells.WARRIOR and int(entry.spell.get("protection", 0)) <= 0: return 70.0
		return 0.0
	if code == ELGlobalSpells.DISJUNCTION:
		var target := ELGlobalSpells.disjunction_target(state, player, 0)
		return 30.0 + int(target.cost) / 10.0 if not target.is_empty() and int(target.cost) >= 75 else 0.0
	return 0.0

## The castle is damaged, or an attack on it is on its way: pending damage,
## an enemy hero within reach, a Warrior of the Realm aimed at it.
static func _threatened(state: ELAdventureSession, player: int) -> bool:
	var own: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if own.is_empty(): return false
	if int(own.pending) > 0 or impending(state, player) > 0: return true
	for entry: Dictionary in ELGlobalSpells.acting_on(state, player):
		if entry.spell.code == ELGlobalSpells.WARRIOR and int(entry.owner) != player: return true
	return false

## Own castle enchantments with nothing left to do are dispelled, so their
## upkeep stops: a regeneration boost once the castle is whole, a shield once
## it is whole and no attack is in sight.
static func _prune(state: ELAdventureSession, player: int) -> void:
	var own: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if own.is_empty() or not own.get("alive", false): return
	var whole := int(own.health) >= int(own.max) and int(own.pending) <= 0
	if not whole: return
	var quiet := not _threatened(state, player)
	for spell: Dictionary in ELGlobalSpells.data(state, player).get("active", []).duplicate():
		var boost := ELGlobalSpells.REGEN_BOOSTS.has(spell.code) or ELGlobalSpells.FRIENDLY_REGEN.has(spell.code)
		var shield := ELGlobalSpells.SHIELDS.has(spell.code) or ELGlobalSpells.FRIENDLY_SHIELDS.has(spell.code)
		if boost or (shield and quiet): ELGlobalSpells.dispel(state, player, int(spell.serial))

## The living, unallied enemy castle with the least energy left.
static func _weakest_enemy(state: ELAdventureSession, player: int) -> int:
	var castles: Dictionary = state.scenario.get("castles", {})
	var best := -1
	for id: int in castles:
		if id < 1 or id == player or not castles[id].alive or ELGlobalSpells._allied(state, player, id): continue
		if best < 0 or int(castles[id].health) - int(castles[id].pending) < int(castles[best].health) - int(castles[best].pending): best = id
	return best

## Casts the finished spell, or dispels one with no target left. False when
## it waits instead: a summons with no free tile beside the castle would be
## used up with no hero (ELGlobalSpells.summon).
static func _cast(director: ELAdventureDirector, player: int) -> bool:
	var state := director.state
	var record := ELGlobalSpells.data(state, player)
	var code := str(record.production.code)
	if ELGlobalSpells.SUMMONS.has(code) and ELGlobalSpells.castle_spot(state, player) == ELGlobalSpells.NO_SPOT: return false
	var lists := ELGlobalSpells.targets(state, player, code)
	var params: Variant = ELGlobalSpells.row(state.map.profile, code).get("Params", [])
	var chosen: Array = []
	for index in lists.size():
		var options: Array = lists[index]
		if options.is_empty():
			ELGlobalSpells.cancel(state, player)
			return true
		var kind: String = params[index] if params is Array else str(params)
		var pick: int = options[0]
		if kind == "Hero":
			var champion := ELFirstAI.commander_id(state, player)
			if options.has(champion): pick = champion
		elif kind == "Castle" and (ELGlobalSpells.CASTLE_DAMAGE.has(code) or ELGlobalSpells.HOSTILE_CASTLE.has(code)):
			# An attack is aimed at enemies only: with no enemy castle left
			# (ruined or allied since the spell was begun) it is dispelled.
			var enemy := _weakest_enemy(state, player)
			if not options.has(enemy):
				ELGlobalSpells.cancel(state, player)
				return true
			pick = enemy
		elif kind == "Castle":
			if options.has(player): pick = player
		chosen.append(pick)
	if not ELGlobalSpells.cast(state, player, chosen):
		state.error = ""
		ELGlobalSpells.cancel(state, player)
	return true
