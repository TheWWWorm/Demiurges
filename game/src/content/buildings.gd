class_name ELBuildings
extends RefCounted
## First-game shops share capture, upgrade costs and three authored levels.
const TYPES := {"IngredientShop": "rune_shop", "SpellShop": "el1_spell_shop", "CreatureShop": "el1_spell_shop"}

static func definition(profile: ELProfile, building: Dictionary) -> Dictionary:
	for row: Dictionary in profile.table("NewBuildings").values():
		if TYPES.has(row.get("Type", "")) and row.get("Name") == building.get("name") and int(row.get("Level", -1)) == int(building.get("level", -1)): return row
	return {}

static func initialize(profile: ELProfile, building: Dictionary) -> void:
	building.level = int(ELXml.value(building.node, "level", "0"))
	building.owner = -1
	building.building_version = 1
	building.type = TYPES.get(definition(profile, building).get("Type", ""), "object")

static func restore(profile: ELProfile, building: Dictionary) -> bool:
	if not building.has("building_version"):
		if building.type not in TYPES.values(): building.level = int(ELXml.value(building.node, "level", "0"))
		# Earlier saves had placeholder ownership, without a capture system.
		building.owner = -1
		building.building_version = 1
	if not ELLuaSave._integer(building.building_version, 1, 1) or not ELLuaSave._integer(building.owner, -1, 32): return false
	var row := definition(profile, building)
	if row.is_empty(): return false
	if (building.group == "factories") != (row.Type == "IngredientShop"): return false
	building.type = TYPES[row.Type]
	return true

static func capture(state: ELAdventureSession, building: Dictionary, player: int) -> void:
	if building.owner == player: return
	var previous := int(building.owner)
	building.owner = player
	state.event.emit({"kind": "object_changed", "id": building.uid})
	state.event.emit({"kind": "shop_captured", "id": building.uid, "player": player, "previous": previous})

static func upgrade_price(profile: ELProfile, building: Dictionary, color: String) -> Dictionary:
	var result := ELResources.empty("el1")
	var entries: Variant = definition(profile, building).get(color + "UpgradeCost", [])
	if entries is String: entries = [entries]
	for entry: String in entries:
		var kind := entry.get_slice("(", 0)
		if result.has(kind): result[kind] += int(entry.get_slice("(", 1).trim_suffix(")"))
	return result

static func upgrade_problem(state: ELAdventureSession, actor: int, id: int) -> String:
	if state.map.profile.id != "el1": return "This building cannot be upgraded."
	var hero := state.object(actor)
	var building := state.object(id)
	if hero.is_empty() or hero.type != "hero" or not hero.alive or hero.owner != state.current_player: return "This hero cannot upgrade a building."
	if building.is_empty() or building.type not in TYPES.values() or not building.alive or not building.visible or not building.enabled or building.owner != hero.owner: return "Visit this building to capture it before upgrading."
	if building.level >= 2: return "This building is fully upgraded."
	var player: Dictionary = state.players.get(hero.owner, {})
	var row := definition(state.map.profile, building)
	if row.is_empty() or not row.has(str(player.get("color", "")) + "UpgradeCost"): return "No upgrade is available for this player."
	var next := building.duplicate()
	next.level += 1
	if definition(state.map.profile, next).is_empty(): return "No further upgrade is available."
	if not ELResources.can_pay("el1", player.get("resources", {}), upgrade_price(state.map.profile, building, player.color)): return "Not enough resources to upgrade this building."
	return ""

static func upgrade(state: ELAdventureSession, actor: int, id: int) -> bool:
	if not upgrade_problem(state, actor, id).is_empty(): return false
	var building := state.object(id)
	var player: Dictionary = state.players[building.owner]
	if not ELResources.pay("el1", player.resources, upgrade_price(state.map.profile, building, player.color)): return false
	building.level += 1
	state.event.emit({"kind": "resources_changed", "player": building.owner})
	state.event.emit({"kind": "object_changed", "id": id})
	return true
