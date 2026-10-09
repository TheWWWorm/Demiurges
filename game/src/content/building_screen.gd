class_name ELBuildingScreen
extends RefCounted
## First-game buildings as the adventure panel lists them (BuildingsMode) and
## as the BuildingScreen shows them: the five categories of the BuildingType
## buttons, the upgrade cost of the next level and the upgrade itself. The
## screen upgrades for the owning player, without a hero, like the original's
## upgrade command.
## Categories in BuildingType1..5 order: glades and mines, forts, portals,
## laboratories, other owned buildings.
const CATEGORIES := 5

static func category(item: Dictionary) -> int:
	match str(item.get("group", "")):
		"mines", "mana_nodes": return 0
		"forts": return 1
		"factories": return 2 if item.get("type") == "rune_shop" else -1
		"laboratories": return 3 if item.get("type") == "el1_spell_shop" else -1
		"additional_buildings": return 4 if item.get("name") in ELAdditionalBuildings.OWNED and item.get("addition_version") == ELAdditionalBuildings.VERSION else -1
	return -1

## The player's living buildings of one category, in map order.
static func owned(state: ELAdventureSession, player: int, kind: int) -> Array[int]:
	var result: Array[int] = []
	if state.map.profile.id != "el1": return result
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false) or int(item.get("owner", -1)) != player or category(item) != kind: continue
		result.append(int(item.uid))
	return result

## Laboratories show their spell list (the panel's Type1 layout).
static func has_spells(item: Dictionary) -> bool:
	return category(item) == 3

static func level(item: Dictionary) -> int:
	return int(item.get("fort_level", 0)) if category(item) == 1 else int(item.get("level", 0))

static func title(profile: ELProfile, item: Dictionary) -> String:
	match category(item):
		0: return ELResourceSites.title(profile, item)
		1: return ELForts.title(profile, item)
		2, 3: return profile.text(str(ELBuildings.definition(profile, item).get("ELKName", item.get("name", ""))))
		4: return ELAdditionalBuildings.title(profile, item)
	return str(item.get("name", ""))

static func description(profile: ELProfile, item: Dictionary) -> String:
	var row := {}
	match category(item):
		0: row = ELResourceSites.definition(profile, item)
		1: row = ELForts.definition(profile, item)
		2, 3: row = ELBuildings.definition(profile, item)
		4: row = ELAdditionalBuildings.definition(profile, item)
	var key := str(row.get("ELKDesc", row.get("ToolTip", "")))
	var text := profile.text(key)
	return "" if key.is_empty() or text == key else text

## Whether the building has a next level for its owner (costs are shown),
## regardless of the owner's resources.
static func upgradable(state: ELAdventureSession, item: Dictionary) -> bool:
	var profile := state.map.profile
	var player: Dictionary = state.players.get(int(item.get("owner", -1)), {})
	if player.is_empty() or not item.get("alive", false): return false
	match category(item):
		0:
			if item.group != "mines" or item.level >= 2 or not ELResourceSites.definition(profile, item).has("UpgradeCost"): return false
			var next := item.duplicate()
			next.level += 1
			return not ELResourceSites.definition(profile, next).is_empty()
		1:
			return item.get("type") == "fort" and item.fort_level < ELForts.MAX_LEVEL and ELForts.definition(profile, item).has("UpgradeCost") and not ELForts.definition(profile, item, item.fort_level + 1).is_empty()
		2, 3:
			if item.level >= 2 or not ELBuildings.definition(profile, item).has(str(player.get("color", "")) + "UpgradeCost"): return false
			var next := item.duplicate()
			next.level += 1
			return not ELBuildings.definition(profile, next).is_empty()
	return false

static func upgrade_price(state: ELAdventureSession, item: Dictionary) -> Dictionary:
	var profile := state.map.profile
	match category(item):
		0: return ELResourceSites.upgrade_price(profile, item)
		1: return ELForts.upgrade_price(profile, item)
		2, 3: return ELBuildings.upgrade_price(profile, item, str(state.players.get(int(item.owner), {}).get("color", "")))
	return ELResources.empty("el1")

## The cost entries in resource order, at most four, as {kind, amount}.
static func cost_entries(state: ELAdventureSession, item: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var price := upgrade_price(state, item)
	for kind: String in ELResources.types("el1"):
		if int(price.get(kind, 0)) > 0 and result.size() < 4: result.append({"kind": kind, "amount": int(price[kind])})
	return result

static func upgrade_problem(state: ELAdventureSession, player: int, id: int) -> String:
	var item := state.object(id)
	if item.is_empty() or int(item.get("owner", -1)) != player or player != state.current_player: return "This building does not belong to the current player."
	if not upgradable(state, item): return "This building cannot be upgraded."
	if not ELResources.can_pay("el1", state.players[player].resources, upgrade_price(state, item)): return "Not enough resources to upgrade this building."
	return ""

## Pays and raises the level; the world and HUD follow the emitted events.
static func upgrade(state: ELAdventureSession, player: int, id: int) -> bool:
	if not upgrade_problem(state, player, id).is_empty(): return false
	var item := state.object(id)
	if category(item) == 1: return ELForts.upgrade(state, id, player)
	if not ELResources.pay("el1", state.players[player].resources, upgrade_price(state, item)): return false
	item.level += 1
	state.event.emit({"kind": "resources_changed", "player": player})
	state.event.emit({"kind": "object_changed", "id": id})
	return true

## A laboratory's spells for the owner's colour, tier by tier (levels 1..3).
static func spell_tiers(state: ELAdventureSession, item: Dictionary) -> Array:
	var profile := state.map.profile
	var color := str(state.players.get(int(item.get("owner", -1)), {}).get("color", ""))
	var tiers: Array = [[], [], []]
	for tier: Dictionary in ELXml.children(item.node, "spells"):
		var index := int(tier.attrs.get("level", 1)) - 1
		if index < 0 or index > 2: continue
		for spell: Dictionary in ELXml.children(tier, "spell"):
			var code := str(spell.get("text", "")).strip_edges()
			if ELSpellInventory.is_spell(profile, code) and profile.table("CombatSpells")[code].get("Color") == color: tiers[index].append(code)
	return tiers

## Picture index on the building-icon sheets, or -1.
static func icon(profile: ELProfile, item: Dictionary) -> int:
	var row := {}
	match category(item):
		0: row = ELResourceSites.definition(profile, item)
		1: row = ELForts.definition(profile, item)
		2, 3: row = ELBuildings.definition(profile, item)
		4: row = ELAdditionalBuildings.definition(profile, item)
	return int(row.get("Icon", -1))
