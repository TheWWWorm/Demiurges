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
			var rank := SKILL_PRIORITY.find(code)
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

## The hero stands beside the shop: buy, as the player's screen would. A
## player with resources to spare then upgrades the shop.
static func visit(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> void:
	var state := director.state
	if not applies(director):
		ELBuildings.capture(state, shop, int(hero.owner))
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

## How many spells the shop's next level adds that are worth buying for this hero.
static func _next_stock_helps(state: ELAdventureSession, hero: Dictionary, shop: Dictionary) -> int:
	var profile := state.map.profile
	if int(shop.level) >= 2 or hero.get("cards", []).is_empty(): return 0
	var weakest := INF
	for slot in hero.cards.size():
		var points := spell_value(profile, hero.cards[slot])
		if slot < hero.get("rune_uses", []).size() and int(hero.rune_uses[slot]) > 0: points += KEEP
		weakest = minf(weakest, points)
	var next := shop.duplicate()
	next.level = int(shop.level) + 1
	var colour := ELFirstSpellShop.hero_color(profile, hero)
	var now := ELFirstSpellShop.authored_stock(profile, shop, colour)
	var count := 0
	for card: String in ELFirstSpellShop.authored_stock(profile, next, colour):
		if not now.has(card) and spell_value(profile, card) >= weakest + MIN_GAIN: count += 1
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

## A hero with spells waiting for runes leaves its errand for a portal.
static func urgent(director: ELAdventureDirector, hero: Dictionary) -> bool:
	return applies(director) and empty_copies(hero) > 0 and not _portals(director.state, int(hero.owner), hero).is_empty()

# --- Global spells -------------------------------------------------------------

## Spells the computer leaves alone: forts, ethereal duels, remote shops,
## recalls and the rest whose use needs a player's judgement.
static func _usable(code: String) -> bool:
	return ELGlobalSpells.REPAIRS.has(code) or ELGlobalSpells.CASTLE_DAMAGE.has(code) or ELGlobalSpells.RITUALS.has(code) or ELGlobalSpells.SUMMONS.has(code) or ELGlobalSpells.HERO_BUFFS.has(code) or ELGlobalSpells.BATTLE_EFFECTS.has(code)

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
## then end_night). A large number when the player has no castle record.
static func night_health(state: ELAdventureSession, player: int, spend := 0, repair := 0) -> int:
	var castle: Dictionary = state.scenario.get("castles", {}).get(player, {})
	if castle.is_empty() or not castle.get("alive", false): return 1 << 20
	var free := ELGlobalSpells.free_ether(state, player)
	var regenerated := mini(int(castle.max), int(castle.health) + ELFirstScenario.regeneration(maxi(0, free - spend)))
	return clampi(regenerated - (int(castle.pending) - repair), 0, int(castle.max))

## Once a day: a finished spell is cast, then the next one is chosen and, when
## today's ether completes it, cast at once (a few rounds at most).
static func global_spells(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	if not ELGlobalSpells.applies(state): return
	var record := ELGlobalSpells.data(state, player)
	if record.is_empty(): return
	for round in 3:
		if not record.production.is_empty():
			if int(record.production.get("state", 0)) == 2:
				_cast(director, player)
				continue
			# A spell the ether income can no longer finish gives its resources back.
			if ELGlobalSpells.turns_left(state, player) <= STALL_DAYS or not ELGlobalSpells.cancel(state, player): return
		var best := _choose(director, player)
		if best.is_empty() or not ELGlobalSpells.produce(state, player, best): return
		if int(record.production.get("state", 0)) != 2: return

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
		# The recruit joins at the end of the upkeep order: when its upkeep no
		# longer fits it goes unpaid, which costs nothing (ELStrategy.allocation).
		var left := forecast(state, player, [{"type": "hero", "level": level, "skills": {}}])
		if count >= MORE_HEROES or (count >= HEROES and left < SPARE_ETHER): return 0.0
		return (90.0 if count < 2 else 50.0) + level
	if ELGlobalSpells.RITUALS.has(code):
		for spell: Dictionary in active: if spell.code == code: return 0.0
		return 40.0 if int(state.day) < 25 else 10.0
	if ELGlobalSpells.HERO_BUFFS.has(code):
		var champion := state.object(ELFirstAI.commander_id(state, player))
		return 30.0 if not champion.is_empty() and not ELGlobalSpells.hero_has(champion, code) else 0.0
	if ELGlobalSpells.BATTLE_EFFECTS.has(code):
		for spell: Dictionary in active: if spell.code == code: return 0.0
		return 25.0
	return 0.0

## The living, unallied enemy castle with the least energy left.
static func _weakest_enemy(state: ELAdventureSession, player: int) -> int:
	var castles: Dictionary = state.scenario.get("castles", {})
	var best := -1
	for id: int in castles:
		if id < 1 or id == player or not castles[id].alive or ELGlobalSpells._allied(state, player, id): continue
		if best < 0 or int(castles[id].health) - int(castles[id].pending) < int(castles[best].health) - int(castles[best].pending): best = id
	return best

static func _cast(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var record := ELGlobalSpells.data(state, player)
	var code := str(record.production.code)
	var lists := ELGlobalSpells.targets(state, player, code)
	var params: Variant = ELGlobalSpells.row(state.map.profile, code).get("Params", [])
	var chosen: Array = []
	for index in lists.size():
		var options: Array = lists[index]
		if options.is_empty():
			ELGlobalSpells.cancel(state, player)
			return
		var kind: String = params[index] if params is Array else str(params)
		var pick: int = options[0]
		if kind == "Hero":
			var champion := ELFirstAI.commander_id(state, player)
			if options.has(champion): pick = champion
		elif kind == "Castle" and ELGlobalSpells.CASTLE_DAMAGE.has(code):
			# An attack is aimed at enemies only: with no enemy castle left
			# (ruined or allied since the spell was begun) it is dispelled.
			var enemy := _weakest_enemy(state, player)
			if not options.has(enemy):
				ELGlobalSpells.cancel(state, player)
				return
			pick = enemy
		elif kind == "Castle":
			if options.has(player): pick = player
		chosen.append(pick)
	if not ELGlobalSpells.cast(state, player, chosen):
		state.error = ""
		ELGlobalSpells.cancel(state, player)
