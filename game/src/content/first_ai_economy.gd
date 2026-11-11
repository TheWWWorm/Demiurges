class_name ELFirstAIEconomy
extends RefCounted
## Remake option "smarter computer players" (first game, single player): the
## original computer players only walk to targets and never pick skills, buy
## spells or runes, or cast global spells. With the option they do all of it,
## through the same rules and prices as the player's screens.

## Skills a computer hero learns first; Ethereal Attack and Counterstrike
## have no effect and are never taken while anything else is offered.
const SKILL_PRIORITY := ["HEAL", "CONC", "REGN", "PRVD", "MSTR", "ARTF", "SUPR", "CNLG", "LEAR", "MOBL", "BARG", "SRCH", "ADPT"]
## Share of each resource one visit may spend, so the next visit and the
## global spells still have some left.
const SPEND_SHARE := 0.6
const RARITY_WEIGHT := {"Cantrip": 0.8, "Common": 1.0, "Rare": 1.6, "Unique": 2.4}
## A new spell must be clearly stronger than the copy it replaces.
const UPGRADE_FACTOR := 1.4
const SPELLS_PER_VISIT := 3
## Shops further than this many days of walking are not worth the trip.
const SHOP_DAYS := 3

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
	global_spells(director, player)

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

static func spell_value(profile: ELProfile, card: String) -> float:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	return (float(row.get("Cost", 1)) + 1.0) * float(RARITY_WEIGHT.get(row.get("Rarity", ""), 1.0))

static func _budget(state: ELAdventureSession, player: int) -> Dictionary:
	var result := {}
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock: result[kind] = int(floor(int(stock[kind]) * SPEND_SHARE))
	return result

static func _affordable(state: ELAdventureSession, player: int, bill: Dictionary) -> bool:
	return ELResources.can_pay("el1", _budget(state, player), bill)

## How many purchases a visit to `shop` would make now (0: no reason to go).
static func wants(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> int:
	if not applies(director) or not is_shop(shop): return 0
	return _shop(director.state, hero, shop, false)

## The hero stands beside the shop: buy, as the player's screen would.
static func visit(director: ELAdventureDirector, hero: Dictionary, shop: Dictionary) -> void:
	var state := director.state
	if not applies(director):
		ELBuildings.capture(state, shop, int(hero.owner))
		return
	if _shop(state, hero, shop, true) == 0: ELBuildings.capture(state, shop, int(hero.owner))

static func _shop(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, commit: bool) -> int:
	if hero.get("type") != "hero" or not hero.get("alive", false) or not state.players.has(int(hero.owner)): return 0
	return _spells(state, hero, shop, commit) if shop.type == "el1_spell_shop" else _runes(state, hero, shop, commit)

## Spell shop: the strongest stock spells replace the weakest copies (a copy
## without runes counts for little). Spells that need runes are bought only
## when the player knows a component portal to refill them.
static func _spells(state: ELAdventureSession, hero: Dictionary, shop: Dictionary, commit: bool) -> int:
	var profile := state.map.profile
	var player := int(hero.owner)
	var trade := ELFirstSpellShop.new()
	if not trade.open(state, int(hero.uid), int(shop.uid), not commit, player): return 0
	var portal := _knows_portal(state, player)
	var stock: Array[String] = []
	for card: String in trade.stock: if not stock.has(card): stock.append(card)
	stock.sort_custom(func(a: String, b: String): return spell_value(profile, a) > spell_value(profile, b))
	var worth: Array[float] = []
	var loaded: Array[bool] = []
	for slot in trade.cards.size():
		var card: String = trade.cards[slot]
		var live := ELRunes.unlimited(profile, hero, card) or int(trade.uses[slot]) > 0
		loaded.append(live)
		# A copy without runes counts for little unless a known portal can refill it.
		worth.append(spell_value(profile, card) * (1.0 if live else (0.8 if portal else 0.25)))
	var bought := 0
	for card: String in stock:
		if bought >= SPELLS_PER_VISIT: break
		var cantrip := ELRunes.unlimited(profile, hero, card)
		if not portal and not cantrip: continue
		var weakest := -1
		for slot in worth.size():
			# A new spell needing runes arrives empty: it replaces only empty
			# copies; a cantrip (never empty) may replace any weaker copy.
			if not trade.pending[slot].is_empty() or (loaded[slot] and not cantrip): continue
			if weakest < 0 or worth[slot] < worth[weakest]: weakest = slot
		if weakest < 0 or trade.cards[weakest] == card or spell_value(profile, card) < worth[weakest] * UPGRADE_FACTOR: continue
		if not trade.replace(weakest, card): continue
		if not _affordable(state, player, trade.bill()):
			trade.clear(weakest)
			continue
		bought += 1
	if bought > 0 and commit and not trade.commit(): return 0
	if not commit: trade.cancel()
	return bought

## Component portal: refill the most valuable spells first, within budget.
static func _runes(state: ELAdventureSession, hero: Dictionary, portal: Dictionary, commit: bool) -> int:
	var profile := state.map.profile
	var player := int(hero.owner)
	var trade := ELRuneShop.new()
	if not trade.open(state, int(hero.uid), int(portal.uid), not commit, player): return 0
	var slots: Array = range(hero.cards.size())
	slots.sort_custom(func(a: int, b: int): return spell_value(profile, hero.cards[a]) > spell_value(profile, hero.cards[b]))
	var capacity := ELRunes.capacity(hero)
	var total := 0
	for slot: int in slots:
		var uses := int(hero.rune_uses[slot])
		if uses < 0 or uses >= capacity: continue
		var amount := capacity - uses
		while amount > 0:
			if trade.set_amount(slot, amount) and _affordable(state, player, trade.bill()): break
			amount -= 1
		if amount <= 0: trade.set_amount(slot, 0)
		total += maxi(0, amount)
	if total > 0 and commit and not trade.commit(): return 0
	if not commit: trade.cancel()
	return total

static func _knows_portal(state: ELAdventureSession, player: int) -> bool:
	for item: Dictionary in state.objects.values():
		if item.get("type") == "rune_shop" and is_shop(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)): return true
	return false

## Share of the hero's rune-using copies that still have runes (1: all full or none needed).
static func rune_health(state: ELAdventureSession, hero: Dictionary) -> float:
	var used := 0
	var total := 0
	for slot in hero.get("cards", []).size():
		var uses := int(hero.rune_uses[slot]) if slot < hero.get("rune_uses", []).size() else -1
		if uses < 0: continue
		total += ELRunes.capacity(hero)
		used += uses
	return 1.0 if total == 0 else float(used) / total

# --- Global spells -------------------------------------------------------------

## Spells the computer leaves alone: forts, ethereal duels, remote shops,
## recalls and the rest whose use needs a player's judgement.
static func _usable(code: String) -> bool:
	return ELGlobalSpells.REPAIRS.has(code) or ELGlobalSpells.CASTLE_DAMAGE.has(code) or ELGlobalSpells.RITUALS.has(code) or ELGlobalSpells.SUMMONS.has(code) or ELGlobalSpells.HERO_BUFFS.has(code) or ELGlobalSpells.BATTLE_EFFECTS.has(code)

static func global_spells(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	if not ELGlobalSpells.applies(state): return
	var record := ELGlobalSpells.data(state, player)
	if record.is_empty(): return
	if not record.production.is_empty():
		if int(record.production.get("state", 0)) == 2: _cast(director, player)
		return
	var budget := ELStrategy.mana_budget(state, player)
	var daily := int(budget.income) - int(budget.spent) - ELGlobalSpells.spell_upkeep(state, player)
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
	if ELGlobalSpells.SUMMONS.has(code): return 50.0 if ELFirstAI.heroes_of(state, player).size() < 3 else 0.0
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
