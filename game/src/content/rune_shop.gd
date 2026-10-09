class_name ELRuneShop
extends RefCounted
## EL1 component portals refill individual equipped spell copies. All additions
## remain a draft until one atomic payment; reserve copies are not refilled.
const RARITIES := ["Common", "Rare", "Unique"]
const MULTIPLIERS := [[1, 5, 25], [2, 1, 5], [4, 2, 1]]
var state: ELAdventureSession
var hero_id := -1
var shop_id := -1
var pending: Array[int] = []
var error := ""
var finished := false
var _before: Dictionary
var _quotes: Array[Dictionary] = []

static func definition(profile: ELProfile, portal: Dictionary) -> Dictionary:
	var row := ELBuildings.definition(profile, portal)
	return row if row.get("Type") == "IngredientShop" else {}

static func unit_price(base: int, multiplier: int, level: int, bargaining: int) -> int:
	if base <= 0: return 0
	# The original stores intermediate prices as single precision, then uses
	# extended precision for Bargaining and truncates after adding one half.
	var value := float(PackedFloat32Array([float(base)])[0])
	value = float(PackedFloat32Array([value * multiplier])[0])
	if level > 0:
		var factor := float(PackedFloat32Array([0.85 if level == 1 else 0.6])[0])
		value = float(PackedFloat32Array([value * factor])[0])
	return ELResources.bargain_price(value, bargaining)

static func price(profile: ELProfile, hero: Dictionary, portal: Dictionary, card: String) -> Dictionary:
	var result := ELResources.empty("el1")
	var spell: Dictionary = profile.table("CombatSpells").get(card, {})
	var rarity := RARITIES.find(spell.get("Rarity", ""))
	var portal_rarity := RARITIES.find(definition(profile, portal).get("Rarity", ""))
	if rarity < 0 or portal_rarity < 0: return result
	for kind: String in result:
		result[kind] = unit_price(int(spell.get("Charge" + kind, 0)), MULTIPLIERS[portal_rarity][rarity], int(portal.level), int(hero.get("skills", {}).get("BARG", -1)))
	return result

## `remote` (Remote Use) opens the screen without capturing the portal.
func open(session: ELAdventureSession, actor: int, building: int, remote := false) -> bool:
	state = session
	hero_id = actor
	shop_id = building
	error = ""
	finished = false
	if state.map.profile.id != "el1": return _fail("Component portals belong to the first edition.")
	var problem := _access_problem()
	if not problem.is_empty(): return _fail(problem)
	var hero := state.object(hero_id)
	var portal := state.object(shop_id)
	if not ELRunes.restore(state.map.profile, hero): return _fail("This hero's rune inventory is invalid.")
	for card: String in hero.cards:
		if not ELSpellInventory.is_spell(state.map.profile, card): return _fail("The spellbook contains an unknown spell.")
	if not remote: ELBuildings.capture(state, portal, hero.owner)
	_before = {"cards": hero.cards.duplicate(), "uses": hero.rune_uses.duplicate(), "skills": hero.skills.duplicate(), "level": portal.level, "name": portal.name, "owner": portal.owner}
	pending.resize(hero.cards.size())
	pending.fill(0)
	_quotes.clear()
	for card: String in hero.cards: _quotes.append(price(state.map.profile, hero, portal, card))
	return true

func _access_problem() -> String:
	var hero := state.object(hero_id)
	var portal := state.object(shop_id)
	if hero.is_empty() or hero.type != "hero" or not hero.alive or hero.owner != state.current_player: return "This hero cannot buy runes."
	if portal.is_empty() or portal.group != "factories" or not portal.alive or not portal.visible or not portal.enabled or definition(state.map.profile, portal).is_empty(): return "This component portal is unavailable."
	if not state.players.has(hero.owner): return "This hero has no resource balance."
	return ""

func _stale_problem() -> String:
	if finished: return "This purchase has already closed."
	var access := _access_problem()
	if not access.is_empty(): return access
	var hero := state.object(hero_id)
	var portal := state.object(shop_id)
	if hero.cards != _before.cards or hero.rune_uses != _before.uses or hero.skills != _before.skills or portal.level != _before.level or portal.name != _before.name or portal.owner != _before.owner: return "The hero or portal changed. Reopen the portal to buy runes."
	return ""

func quote(slot: int) -> Dictionary:
	return _quotes[slot].duplicate() if slot >= 0 and slot < _quotes.size() else ELResources.empty("el1")

func can_add(slot: int) -> bool:
	if not _stale_problem().is_empty() or slot < 0 or slot >= pending.size(): return false
	return int(_before.uses[slot]) >= 0 and int(_before.uses[slot]) + pending[slot] < ELRunes.capacity(state.object(hero_id))

func change(slot: int, amount: int) -> bool:
	error = _stale_problem()
	if not error.is_empty(): return false
	if slot < 0 or slot >= pending.size() or amount not in [-1, 1]: return _fail("Select a spell to refill.")
	if amount > 0 and not can_add(slot): return _fail("This spell needs no additional runes.")
	pending[slot] = maxi(0, pending[slot] + amount)
	return true

func fill(slot: int) -> bool:
	error = _stale_problem()
	if not error.is_empty(): return false
	if slot < 0 or slot >= pending.size(): return _fail("Select a spell to refill.")
	if int(_before.uses[slot]) >= 0 and int(_before.uses[slot]) < ELRunes.capacity(state.object(hero_id)):
		pending[slot] = ELRunes.capacity(state.object(hero_id)) - int(_before.uses[slot])
	return true

func fill_all() -> bool:
	for slot in pending.size():
		if not fill(slot): return false
	return true

func clear(slot := -1) -> bool:
	error = _stale_problem()
	if not error.is_empty(): return false
	if slot == -1: pending.fill(0)
	elif slot >= 0 and slot < pending.size(): pending[slot] = 0
	else: return _fail("Select a spell to refill.")
	return true

func bill() -> Dictionary:
	var result := ELResources.empty("el1")
	for slot in pending.size():
		for kind: String in result: result[kind] += int(_quotes[slot][kind]) * pending[slot]
	return result

func problem() -> String:
	var stale := _stale_problem()
	if not stale.is_empty(): return stale
	if not ELResources.can_pay("el1", state.players[state.object(hero_id).owner].resources, bill()): return "Not enough resources for these runes."
	return ""

func commit() -> bool:
	error = problem()
	if not error.is_empty(): return false
	var hero := state.object(hero_id)
	if not ELResources.pay("el1", state.players[hero.owner].resources, bill()): return _fail("Not enough resources for these runes.")
	for slot in pending.size(): hero.rune_uses[slot] += pending[slot]
	finished = true
	state.event.emit({"kind": "resources_changed", "player": hero.owner})
	state.event.emit({"kind": "inventory_changed", "id": hero_id})
	return true

func cancel() -> bool:
	if finished: return false
	finished = true
	return true

func upgrade_problem() -> String:
	var stale := _stale_problem()
	if not stale.is_empty(): return stale
	if pending.any(func(amount: int): return amount > 0): return "Clear pending rune purchases before upgrading."
	return ELBuildings.upgrade_problem(state, hero_id, shop_id)

func upgrade() -> bool:
	error = upgrade_problem()
	if not error.is_empty(): return false
	if not ELBuildings.upgrade(state, hero_id, shop_id): return _fail(state.error)
	return open(state, hero_id, shop_id)

func _fail(message: String) -> bool:
	error = message
	return false
