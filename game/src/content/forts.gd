class_name ELForts
extends RefCounted
## Forts of both games: one garrison hero, authored color, tiers 0-2 and a
## radius-three guard area. Fort battle bonuses are connected separately.
## Second game: a hero or creature placed on a fort's tile garrisons it at
## once, whatever its owner; a hero using an empty fort
## enters it and using its own fort again leaves it (CHeroActionUseFort
## ). The second game has no fort upgrade or Leave control.
const RADIUS := 3
const MAX_LEVEL := 2

static func initialize(profile: ELProfile, fort: Dictionary) -> void:
	fort.type = "fort"
	fort.fort_version = 1
	fort.fort_color = ELXml.value(fort.node, "color")
	fort.fort_level = clampi(int(ELXml.child(fort.node, "upgrade").get("attrs", {}).get("level", 0)), 0, MAX_LEVEL)
	# Shipped maps author every fort without an owner or garrison.
	fort.owner = -1
	fort.garrison = -1
	fort.fort_entry = []

static func definition(profile: ELProfile, fort: Dictionary, level := -1) -> Dictionary:
	var wanted := str(int(fort.get("fort_level", 0)) if level < 0 else level)
	for row: Dictionary in profile.table("Buildings").values():
		# Construction/foundation rows use named levels; only numeric tiers apply.
		if row.get("Type") == "Fort" and row.get("MagicColor") == fort.get("fort_color") and str(row.get("Level", "")) == wanted: return row
	return {}

static func title(profile: ELProfile, fort: Dictionary) -> String:
	return profile.text(str(definition(profile, fort).get("Name", "BldngNmFort")))

static func restore(profile: ELProfile, fort: Dictionary) -> bool:
	if not fort.has("fort_version"):
		var owner := int(fort.get("owner", -1))
		initialize(profile, fort)
		fort.owner = owner if owner > 0 else -1
	if not ELLuaSave._integer(fort.fort_version, 1, 1) or not ELLuaSave._integer(fort.get("fort_level"), 0, MAX_LEVEL) or not ELLuaSave._integer(fort.owner, -1, 32) or not ELLuaSave._integer(fort.get("garrison"), -1, 0x7fffffff): return false
	if fort.get("fort_color") != ELXml.value(fort.node, "color") or not fort.get("fort_entry") is Array: return false
	fort.type = "fort"
	fort.fort_level = int(fort.fort_level)
	fort.garrison = int(fort.garrison)
	if definition(profile, fort).is_empty(): return false
	if fort.garrison < 0: return fort.fort_entry.is_empty()
	if fort.fort_entry.size() != 2 or not ELLuaSave._integer(fort.fort_entry[0], 0, 0x7fffffff) or not ELLuaSave._integer(fort.fort_entry[1], 0, 0x7fffffff): return false
	fort.fort_entry = [int(fort.fort_entry[0]), int(fort.fort_entry[1])]
	return true

## Cross-links must be mutual: a garrison hero names its fort and stands on it.
static func valid_links(objects: Dictionary, map: ELAdventureMap) -> bool:
	for item: Dictionary in objects.values():
		if item.get("type") == "fort" and item.garrison >= 0:
			var hero: Dictionary = objects.get(item.garrison, {})
			if not (hero.get("type") in (["hero", "monster"] if map.profile.id == "el2" else ["hero"])) or not hero.get("alive", false) or not hero.get("fortified", false) or int(hero.get("fort", -1)) != int(item.uid) or hero.owner != item.owner: return false
			if Vector2i(hero.x, hero.y) != Vector2i(item.x, item.y): return false
			if item.fort_entry[0] >= map.width or item.fort_entry[1] >= map.height: return false
		elif item.get("type") in ["hero", "monster"]:
			if not item.has("fort"): item.fort = -1
			if not ELLuaSave._integer(item.fort, -1, 0x7fffffff): return false
			item.fort = int(item.fort)
			if item.get("fortified", false) != (item.fort >= 0): return false
			if item.fort >= 0 and objects.get(item.fort, {}).get("garrison", -1) != item.uid: return false
	return true

static func garrison_of(state: ELAdventureSession, actor: Dictionary) -> Dictionary:
	# Life is not checked: removing a dead garrison must still leave its fort.
	if not actor.get("fortified", false): return {}
	var fort := state.object(actor.get("fort", -1))
	return fort if fort.get("type") == "fort" and int(fort.garrison) == int(actor.uid) else {}

static func enter_problem(state: ELAdventureSession, hero_id: int, fort_id: int) -> String:
	var hero := state.object(hero_id)
	var fort := state.object(fort_id)
	if fort.get("type") != "fort" or not fort.alive or not fort.visible or not fort.enabled: return "This fort is unavailable."
	if hero.is_empty() or hero.type != "hero" or not hero.alive or not state.players.has(hero.owner): return "This hero cannot enter a fort."
	if hero.get("fortified", false): return "This hero is already in a fort."
	if fort.garrison >= 0: return "This fort is already occupied."
	return ""

## Occupation happens in the use phase. An occupied fort ignores the
## request. Entering transfers ownership but keeps the authored fort color.
static func enter(state: ELAdventureSession, hero_id: int, fort_id: int) -> bool:
	if not enter_problem(state, hero_id, fort_id).is_empty(): return false
	occupy(state, state.object(hero_id), state.object(fort_id))
	return true

## Garrisons `hero` without the entry checks; the entry tile is where it stands.
static func occupy(state: ELAdventureSession, hero: Dictionary, fort: Dictionary) -> void:
	var hero_id := int(hero.uid)
	var fort_id := int(fort.uid)
	var previous: int = fort.owner
	fort.owner = hero.owner
	fort.garrison = hero.uid
	fort.fort_entry = [int(hero.x), int(hero.y)]
	hero.fortified = true
	hero.fort = fort.uid
	hero.x = int(fort.x)
	hero.y = int(fort.y)
	hero.strategy_order = {}
	hero.orders.clear()
	if previous != fort.owner: state.event.emit({"kind": "fort_captured", "id": fort_id, "player": fort.owner, "previous": previous})
	state.event.emit({"kind": "fort_entered", "id": fort_id, "hero": hero_id})
	state.event.emit({"kind": "object_changed", "id": hero_id})

## Second game, at map start: every alive hero or creature standing on an
## empty fort's tile becomes its garrison (any owner, monsters included).
static func occupy_placed(state: ELAdventureSession) -> void:
	for fort: Dictionary in state.objects.values():
		if fort.get("type") != "fort" or int(fort.garrison) >= 0: continue
		for item: Dictionary in state.objects.values():
			if item.get("type") in ["hero", "monster"] and item.get("alive", false) and item.get("placed", true) and not item.get("fortified", false) and Vector2i(int(item.x), int(item.y)) == Vector2i(int(fort.x), int(fort.y)):
				occupy(state, item, fort)
				break

## Leaving returns the hero to the exact tile it entered from, without searching
## for a free cell. The fort keeps its owner.
static func leave(state: ELAdventureSession, hero_id: int, notify := true) -> bool:
	var hero := state.object(hero_id)
	var fort := garrison_of(state, hero)
	if fort.is_empty(): return false
	hero.x = int(fort.fort_entry[0])
	hero.y = int(fort.fort_entry[1])
	hero.fortified = false
	hero.fort = -1
	fort.garrison = -1
	fort.fort_entry = []
	if notify:
		state.event.emit({"kind": "fort_left", "id": fort.uid, "hero": hero_id})
		state.event.emit({"kind": "object_changed", "id": hero_id})
	return true

static func upgrade_price(profile: ELProfile, fort: Dictionary) -> Dictionary:
	# The quote uses the fort's own color and current tier. Duplicate
	# resource entries in UpgradeCost are summed.
	return ELResourceSites._vector(profile.id, definition(profile, fort).get("UpgradeCost", []))

static func upgrade_problem(state: ELAdventureSession, fort_id: int, player := -1) -> String:
	var fort := state.object(fort_id)
	if player < 0: player = state.current_player
	if fort.get("type") != "fort" or not fort.alive: return "This fort is unavailable."
	if state.map.profile.id != "el1": return "Forts cannot be upgraded in this game."
	if fort.owner != player or not state.players.has(player): return "Capture this fort before upgrading it."
	if fort.fort_level >= MAX_LEVEL: return "This fort is fully upgraded."
	if definition(state.map.profile, fort, fort.fort_level + 1).is_empty() or not definition(state.map.profile, fort).has("UpgradeCost"): return "No further upgrade is available."
	if not ELResources.can_pay("el1", state.players[player].resources, upgrade_price(state.map.profile, fort)): return "Not enough resources to upgrade this fort."
	return ""

static func upgrade(state: ELAdventureSession, fort_id: int, player := -1) -> bool:
	if not upgrade_problem(state, fort_id, player).is_empty(): return false
	var fort := state.object(fort_id)
	if not ELResources.pay("el1", state.players[fort.owner].resources, upgrade_price(state.map.profile, fort)): return false
	fort.fort_level += 1
	state.event.emit({"kind": "resources_changed", "player": fort.owner})
	state.event.emit({"kind": "object_changed", "id": fort_id})
	return true
