class_name ELFirstSpellShop
extends RefCounted
## EL1 purchases replace equipped slots. Rebuilding the draft in slot order
## retains the original escalating duplicate prices and exact undo behavior.
const COPY_MULTIPLIERS := [1, 2, 3, 5, 10, 20, 40, 80, 160, 320, 640, 1280, 2560, 5120, 10240]
var state: ELAdventureSession
var hero_id := -1
var shop_id := -1
var stock: Array[String] = []
var pending: Array[String] = []
var cards: Array[String] = []
var uses: Array[int] = []
var error := ""
var finished := false
var _before: Dictionary
var _bill: Dictionary

static func hero_color(profile: ELProfile, hero: Dictionary) -> String:
	var row: Dictionary = profile.table("Shapes").get(hero.get("shape", ""), {}) if not str(hero.get("shape", "")).is_empty() else profile.table("HeroTemplates").get(hero.get("name", ""), {})
	return str(row.get("Color", ""))

static func authored_stock(profile: ELProfile, building: Dictionary, color: String) -> Array[String]:
	var result: Array[String] = []
	for tier: Dictionary in ELXml.children(building.node, "spells"):
		if int(tier.attrs.get("level", 1)) > int(building.level) + 1: continue
		for spell: Dictionary in ELXml.children(tier, "spell"):
			var code := str(spell.get("text", "")).strip_edges()
			if ELSpellInventory.is_spell(profile, code) and profile.table("CombatSpells")[code].get("Color") == color: result.append(code)
	return result

static func price(profile: ELProfile, hero: Dictionary, book: Array, card: String, slot: int, free_exchange := false) -> Dictionary:
	var result := ELResources.empty("el1")
	if free_exchange: return result
	var copies := 0
	for index in book.size():
		if index != slot and book[index] == card: copies += 1
	var multiplier: int = COPY_MULTIPLIERS[mini(copies, COPY_MULTIPLIERS.size() - 1)]
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	for kind: String in result:
		result[kind] = ELResources.bargain_price(float(row.get("Cost" + kind, 0)) * multiplier, int(hero.get("skills", {}).get("BARG", -1)))
	return result

## `remote` (Remote Use) opens the screen without capturing the shop.
func open(session: ELAdventureSession, actor: int, building: int, remote := false) -> bool:
	state = session
	hero_id = actor
	shop_id = building
	error = ""
	finished = false
	if state.map.profile.id != "el1": return _fail("This shop belongs to the first edition.")
	error = _access_problem()
	if not error.is_empty(): return false
	var hero := state.object(actor)
	if hero.cards.size() > 15 or not ELRunes.restore(state.map.profile, hero): return _fail("This hero's spellbook is invalid.")
	var shop := state.object(building)
	stock = authored_stock(state.map.profile, shop, hero_color(state.map.profile, hero))
	if not remote: ELBuildings.capture(state, shop, hero.owner)
	_before = {"cards": hero.cards.duplicate(), "uses": hero.rune_uses.duplicate(), "skills": hero.skills.duplicate(), "color": hero_color(state.map.profile, hero), "level": shop.level, "owner": shop.owner, "name": shop.name}
	pending.resize(hero.cards.size())
	pending.fill("")
	_rebuild()
	return true

func _access_problem() -> String:
	var hero := state.object(hero_id)
	var shop := state.object(shop_id)
	if hero.is_empty() or hero.type != "hero" or not hero.alive or hero.owner != state.current_player: return "This hero cannot buy spells."
	if shop.is_empty() or shop.group != "laboratories" or not shop.alive or not shop.visible or not shop.enabled or ELBuildings.definition(state.map.profile, shop).get("Type") not in ["SpellShop", "CreatureShop"]: return "This shop is unavailable."
	if not state.players.has(hero.owner): return "This hero has no resource balance."
	return ""

func _stale_problem() -> String:
	if finished: return "This purchase has already closed."
	var access := _access_problem()
	if not access.is_empty(): return access
	var hero := state.object(hero_id)
	var shop := state.object(shop_id)
	if hero.cards != _before.cards or hero.rune_uses != _before.uses or hero.skills != _before.skills or hero_color(state.map.profile, hero) != _before.color or shop.level != _before.level or shop.owner != _before.owner or shop.name != _before.name: return "The hero or shop changed. Reopen the shop to buy spells."
	return ""

func free_exchange() -> bool:
	return state.map.id.begins_with("mission17") or state.map.id.begins_with("mission27")

func quote(card: String, slot: int) -> Dictionary:
	return price(state.map.profile, state.object(hero_id), cards, card, slot, free_exchange())

func replace(slot: int, card: String) -> bool:
	error = _stale_problem()
	if not error.is_empty(): return false
	if slot < 0 or slot >= pending.size(): return _fail("Select an equipped spell to replace.")
	if not stock.has(card): return _fail("This spell is unavailable at this shop's current level.")
	pending[slot] = card
	_rebuild()
	return true

func clear(slot := -1) -> bool:
	error = _stale_problem()
	if not error.is_empty(): return false
	if slot == -1: pending.fill("")
	elif slot >= 0 and slot < pending.size(): pending[slot] = ""
	else: return _fail("Select an equipped spell.")
	_rebuild()
	return true

func _rebuild() -> void:
	cards.assign(_before.cards)
	uses.assign(_before.uses)
	_bill = ELResources.empty("el1")
	var hero := state.object(hero_id)
	for slot in pending.size():
		var card := pending[slot]
		if card.is_empty(): continue
		var cost := price(state.map.profile, hero, cards, card, slot, free_exchange())
		for kind: String in _bill: _bill[kind] += int(cost[kind])
		cards[slot] = card
		uses[slot] = -1 if ELRunes.unlimited(state.map.profile, hero, card) else (100000 if free_exchange() else 0)

func bill() -> Dictionary:
	return _bill.duplicate()

func problem() -> String:
	var stale := _stale_problem()
	if not stale.is_empty(): return stale
	if not ELResources.can_pay("el1", state.players[state.object(hero_id).owner].resources, _bill): return "Not enough resources for these spells."
	return ""

func commit() -> bool:
	error = problem()
	if not error.is_empty(): return false
	var hero := state.object(hero_id)
	if not ELResources.pay("el1", state.players[hero.owner].resources, _bill): return _fail("Not enough resources for these spells.")
	hero.cards.assign(cards)
	hero.rune_uses.assign(uses)
	finished = true
	state.event.emit({"kind": "resources_changed", "player": hero.owner})
	state.event.emit({"kind": "inventory_changed", "id": hero_id})
	return true

func upgrade_problem() -> String:
	var stale := _stale_problem()
	if not stale.is_empty(): return stale
	if pending.any(func(card: String): return not card.is_empty()): return "Clear pending spell purchases before upgrading."
	return ELBuildings.upgrade_problem(state, hero_id, shop_id)

func upgrade() -> bool:
	error = upgrade_problem()
	if not error.is_empty(): return false
	if not ELBuildings.upgrade(state, hero_id, shop_id): return _fail(state.error)
	return open(state, hero_id, shop_id)

func cancel() -> bool:
	if finished: return false
	finished = true
	return true

func _fail(message: String) -> bool:
	error = message
	return false
