extends RefCounted
## Synthetic two-shore world. No file from either original game is used.
## The sea spans the full height, so every cross-shore route must embark
## and land at an explicit port. Ground movement costs two points per cell.

const Content = preload("first_random_map_fixture.gd")
const WIDTH := 64
const HEIGHT := 32
const LEFT_LAND := Vector2i(22, 16)
const LEFT_WATER := Vector2i(23, 16)
const RIGHT_WATER := Vector2i(33, 16)
const RIGHT_LAND := Vector2i(34, 16)

static func world(naval := true) -> ELAdventureMap:
	var map := ELAdventureMap.new()
	map.profile = Content.profile()
	map.profile.tables.TerrObj.FixtureBlock = {"Name": "FixtureBlock", "Model": "fixture_block", "TileSize": [1, 1]}
	map.id = "fixture_naval"
	map.title = "Synthetic naval crossing"
	map.width = WIDTH
	map.height = HEIGHT
	map.terrain.resize((WIDTH + 1) * (HEIGHT + 1))
	map.terrain.fill(4)
	for y in HEIGHT + 1:
		for x in range(24, 34): map.terrain[y * (WIDTH + 1) + x] = 16
	for field: String in ["roads", "creeks", "colorless"]:
		var cells := PackedByteArray()
		cells.resize(WIDTH * HEIGHT)
		map.set(field, cells)
	map.document = node("scenario", {}, "", [node("support", {"last_permanent_id": "5"})])
	for player in range(1, 3):
		var color: String = ["Green", "Blue"][player - 1]
		var balances := {}
		for resource: String in ELResources.ORIGINAL: balances[resource] = "20"
		var relations: Array = []
		for rival in range(1, 3): relations.append(node("opponent", {"id": str(rival), "relations": "255" if rival == player else "0"}))
		map.players.append(node("player", {"id": str(player), "health": "30"}, "", [
			node("color", {}, color), node("start_resources", balances), node("diplomacy", {}, "", relations)]))
	place(map, "heroes", ELCatalog.HEROES.Green, LEFT_LAND, 1, "Green")
	place(map, "heroes", ELCatalog.HEROES.Blue, Vector2i(52, 17), 2, "Blue")
	place(map, "buildings", "MainTower", Vector2i(4, 3), 1, "Green", [node("level", {}, "0")], {"mana_income": "50"})
	place(map, "buildings", "MainTower", Vector2i(52, 23), 2, "Blue", [node("level", {}, "0")], {"mana_income": "50"})
	place(map, "mines", "FixtureRootMine", Vector2i(17, 15), 0, "", [node("level", {}, "0")])
	if naval:
		map.set_meta("first_naval", {"version": 1, "water_type": 16, "ports": [
			{"id": 1, "land": [22, 16], "water": [23, 16], "island": 1, "owner": 1, "name": "West harbor"},
			{"id": 2, "land": [34, 16], "water": [33, 16], "island": 2, "owner": 2, "name": "East harbor"}]})
	return map

static func place(map: ELAdventureMap, group: String, template: String, at: Vector2i, owner := 0, color := "", extra: Array = [], attrs: Dictionary = {}) -> Dictionary:
	var id := map.objects.size() + 1
	var properties := attrs.duplicate()
	properties.permanent_id = str(id)
	properties.id = str(id)
	var children: Array = [node("place", {"x": str(at.x), "y": str(at.y), "mr": "0"}), node("template", {}, template)]
	if not color.is_empty(): children.append(node("color", {}, color))
	children.append_array(extra)
	var record := {"group": group, "owner": owner,
		"node": node("hero" if group in ["heroes", "np_heroes"] else "object", properties, "", children),
		"x": at.x, "y": at.y, "rotation": 0, "permanent_id": id, "id": id, "name": template}
	map.objects.append(record)
	return record

static func node(tag: String, attrs: Dictionary = {}, text := "", children: Array = []) -> Dictionary:
	return {"tag": tag, "attrs": attrs, "text": text, "children": children}
