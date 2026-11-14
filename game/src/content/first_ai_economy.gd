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
const RARITY_WEIGHT := {"Cantrip": 0.8, "Common": 1.0, "Rare": 1.6, "Unique": 2.4}
## Spells are weighed in points: percentage points of a duel's outcome that
## the spell adds to a starting book (ELFirstSpellRatings). A purchase must
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
	var share := SPEND_SHARE if int(ELFirstAI.data(state, player).get("champion", -1)) == int(hero.uid) else SIDE_SHARE
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock: result[kind] = int(floor(int(stock[kind]) * share))
	return result

static func _total(bill: Dictionary) -> int:
	var result := 0
	for kind: String in bill: result += int(bill[kind])
	return result

## How many purchases a visit to `shop` would make now (0: no reason to go).
static func wants(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> int:
	if not applies(director) or not is_shop(shop): return 0
	return _shop(director.state, hero, shop, false)

## The hero stands beside the shop: buy, as the player's screen would. A
## player with resources to spare then upgrades the shop.
static func visit(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> void:
	var state := director.state
	if not applies(director):
		ELBuildings.capture(state, shop, int(hero.owner))
		return
	var bought := _shop(state, hero, shop, true)
	ELBuildings.capture(state, shop, int(hero.owner))
	# A spell shop is upgraded for what its next level sells this hero, a
	# portal once it has sold runes (its next level sells them cheaper).
	if shop.type == "el1_spell_shop":
		if _next_stock_helps(state, hero, shop) and _upgrade(state, hero, shop): _shop(state, hero, shop, true)
	elif bought > 0: _upgrade(state, hero, shop)

## Whether the shop's next level stocks a spell worth buying for this hero.
static func _next_stock_helps(state: ELAdventureSession, hero: Dictionary, shop: Dictionary) -> bool:
	var profile := state.map.profile
	if int(shop.level) >= 2 or hero.get("cards", []).is_empty(): return false
	var weakest := INF
	for slot in hero.cards.size():
		var points := spell_value(profile, hero.cards[slot])
		if slot < hero.get("rune_uses", []).size() and int(hero.rune_uses[slot]) > 0: points += KEEP
		weakest = minf(weakest, points)
	var next := shop.duplicate()
	next.level = int(shop.level) + 1
	var colour := ELFirstSpellShop.hero_color(profile, hero)
	var now := ELFirstSpellShop.authored_stock(profile, shop, colour)
	for card: String in ELFirstSpellShop.authored_stock(profile, next, colour):
		if not now.has(card) and spell_value(profile, card) >= weakest + MIN_GAIN: return true
	return false

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
	var portals := _portals(state, player)
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
		var total := trade.bill()
		var runes := ELResources.empty("el1")
		if not cantrip:
			var unit := _rune_price(state, hero, portals, card)
			for kind: String in runes: runes[kind] = int(unit[kind]) * ELRunes.capacity(hero)
		for kind: String in total: total[kind] = int(total[kind]) + int(refill[kind]) + int(runes[kind])
		if not ELResources.can_pay("el1", budget, total):
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
	var portals := _portals(state, player)
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

## Component portals the player has seen.
static func _portals(state: ELAdventureSession, player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in state.objects.values():
		if item.get("type") == "rune_shop" and is_shop(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)): result.append(item)
	return result

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
## away; otherwise runes are topped up once half are gone. A spell shop is
## worth a detour for several spells, or for one when it is close by.
static func trip_cost(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, route: int, count: int) -> int:
	var day := maxi(1, int(hero.get("strategy_capacity", 1)))
	if shop.get("type") == "rune_shop":
		if count < MIN_RUNES: return -1
		if empty_copies(hero) > 0: return route / 8 if route <= URGENT_DAYS * day else -1
		return route / 4 if rune_health(state, hero) < 0.5 and route <= SHOP_DAYS * day else -1
	# A hero that has never shopped goes further for its first spells.
	if count >= MIN_SPELLS and starting_book(hero): return route / 4 if route <= URGENT_DAYS * day else -1
	if route > SHOP_DAYS * day or (count < MIN_SPELLS and route > day): return -1
	return route

## A hero with spells waiting for runes leaves its errand for a portal.
static func urgent(director: ELAdventureDirector, hero: Dictionary) -> bool:
	return applies(director) and empty_copies(hero) > 0 and not _portals(director.state, int(hero.owner)).is_empty()

# --- Global spells -------------------------------------------------------------

## Spells the computer leaves alone: forts, ethereal duels, remote shops,
## recalls and the rest whose use needs a player's judgement.
static func _usable(code: String) -> bool:
	return ELGlobalSpells.REPAIRS.has(code) or ELGlobalSpells.CASTLE_DAMAGE.has(code) or ELGlobalSpells.RITUALS.has(code) or ELGlobalSpells.SUMMONS.has(code) or ELGlobalSpells.HERO_BUFFS.has(code) or ELGlobalSpells.BATTLE_EFFECTS.has(code)

## Ether a player gains each day after hero and spell upkeep.
static func _daily_ether(state: ELAdventureSession, player: int) -> int:
	var budget := ELStrategy.mana_budget(state, player)
	return int(budget.income) - int(budget.spent) - ELGlobalSpells.spell_upkeep(state, player)

static func global_spells(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	if not ELGlobalSpells.applies(state): return
	var record := ELGlobalSpells.data(state, player)
	if record.is_empty(): return
	if not record.production.is_empty():
		if int(record.production.get("state", 0)) == 2:
			_cast(director, player)
			return
		# A spell the ether income can no longer finish gives its resources back.
		if ELGlobalSpells.turns_left(state, player) <= STALL_DAYS or not ELGlobalSpells.cancel(state, player): return
	var daily := _daily_ether(state, player)
	if daily <= 0: return
	var best := ""
	var best_score := 0.0
	for code: String in ELMapPickups.available_codes(state, player):
		if not _usable(code) or not ELGlobalSpells.produce_problem(state, player, code).is_empty(): continue
		# Upkeep must leave most of the income, and the ether must come within about a week.
		if ELGlobalSpells.upkeep(state.map.profile, code) * 2 > daily or ELGlobalSpells.ether_cost(state, player, code) > daily * 8: continue
		var score := _score(director, player, code)
		if score > best_score:
			best_score = score
			best = code
	if not best.is_empty(): ELGlobalSpells.produce(state, player, best)

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
		var left := _daily_ether(state, player) - int(state.map.profile.table("HeroesStats").get("ManaUpkeep", {}).get("Level%d" % level, 0))
		if count >= MORE_HEROES or left < 0 or (count >= HEROES and left < SPARE_ETHER): return 0.0
		return (90.0 if count < 2 else 50.0) + level
	if ELGlobalSpells.RITUALS.has(code):
		for spell: Dictionary in active: if spell.code == code: return 0.0
		return 40.0 if int(state.day) < 25 else 10.0
	if ELGlobalSpells.HERO_BUFFS.has(code):
		var champion := state.object(int(ELFirstAI.data(state, player).get("champion", -1)))
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
			var champion := int(ELFirstAI.data(state, player).get("champion", -1))
			if options.has(champion): pick = champion
		elif kind == "Castle":
			var enemy := _weakest_enemy(state, player)
			if ELGlobalSpells.CASTLE_DAMAGE.has(code) and options.has(enemy): pick = enemy
			elif options.has(player): pick = player
		chosen.append(pick)
	if not ELGlobalSpells.cast(state, player, chosen):
		state.error = ""
		ELGlobalSpells.cancel(state, player)
