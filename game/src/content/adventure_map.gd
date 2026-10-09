class_name ELAdventureMap
extends RefCounted
## Reads the XML scenario's terrain, placed objects, players and encounter data.
## The separate EBM file is not required by this reader.
var profile: ELProfile
var id := ""
var width := 0
var height := 0
var title := ""
var objective := ""
var terrain := PackedByteArray()
var roads := PackedByteArray()
var creeks := PackedByteArray()
var colorless := PackedByteArray()
var players: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var mobs: Dictionary = {}
var document: Dictionary = {}
var error := ""

func load_map(data: ELProfile, map_id: String) -> bool:
	profile = data
	id = map_id
	error = ""
	players.clear()
	objects.clear()
	mobs.clear()
	# Ids with a folder (the second game's "Tutorial/Adventure/e2tutorial")
	# are relative to the installation; plain ids live in Maps/.
	var path := profile.file((id if id.contains("/") else "Maps/" + id) + ".map")
	if path.is_empty(): return _fail("Missing scenario: " + id)
	document = ELXml.parse(FileAccess.get_file_as_bytes(path))
	if document.get("tag") != "scenario": return _fail(String(document.get("error", "Invalid scenario document.")))
	title = profile.text(ELXml.value(document, "title", id))
	objective = profile.text(ELXml.value(document, "objective"))
	var map := ELXml.child(document, "map")
	var size: Dictionary = ELXml.child(map, "size").get("attrs", {})
	width = int(size.get("x", 0))
	height = int(size.get("y", 0))
	if width < 1 or height < 1 or width > 512 or height > 512: return _fail("Invalid map dimensions.")
	terrain = _grid(map, "tiles", width + 1, height + 1)
	roads = _grid(map, "roads", width, height)
	creeks = _grid(map, "creeks", width, height)
	colorless = _grid(map, "clrless", width, height, true)
	if not error.is_empty(): return false
	for player: Dictionary in ELXml.children(ELXml.child(document, "players"), "player"):
		players.append(player)
		for group: String in ["heroes", "buildings"]:
			for node: Dictionary in ELXml.child(player, group).get("children", []):
				_add_object(node, group, int(player.attrs.get("id", 0)))
	for group: String in ["mana_nodes", "mines", "resource_cuts", "laboratories", "factories", "artefacts", "global_spells", "forts", "terrain_objects", "np_heroes", "additional_buildings"]:
		for node: Dictionary in ELXml.child(document, group).get("children", []): _add_object(node, group)
	for node: Dictionary in ELXml.children(ELXml.child(document, "mdm_mobs"), "mdm_mob"):
		var key: String = node.attrs.get("Name", "")
		if not mobs.has(key): mobs[key] = {}
		mobs[key][int(node.attrs.get("DifLvl", 0))] = node
	return true

func _grid(map: Dictionary, name: String, columns: int, rows: int, optional := false) -> PackedByteArray:
	var result := PackedByteArray()
	var lines := ELXml.children(ELXml.child(map, name), "row")
	if optional and lines.is_empty():
		result.resize(columns * rows)
		return result
	# The originals call these XML elements rows, but serialize one X column
	# per element and Y values within it. Keep our runtime grids row-major.
	if lines.size() != columns:
		_fail("Wrong number of rows in " + name)
		return result
	result.resize(columns * rows)
	for x in columns:
		var line: Dictionary = lines[x]
		var text := String(line.text).strip_edges()
		if text.length() != rows * 2 or not text.is_valid_hex_number(false):
			_fail("Invalid hex tile row in " + name)
			return PackedByteArray()
		var values := text.hex_decode()
		for y in rows: result[y * columns + x] = values[y]
	return result

func _add_object(node: Dictionary, group: String, owner := 0) -> void:
	var place: Dictionary = ELXml.child(node, "place").get("attrs", {})
	if place.is_empty(): return
	objects.append({"group": group, "owner": owner, "node": node,
		"x": int(place.get("x", 0)), "y": int(place.get("y", 0)), "rotation": int(place.get("mr", 0)),
		"permanent_id": int(node.attrs.get("permanent_id", -1)),
		"id": int(node.attrs.get("id", -1)), "name": ELXml.value(node, "template", ELXml.value(node, "name", ELXml.value(node, "type", node.tag)))})

func tile(x: int, y: int) -> int:
	return int(terrain[y * (width + 1) + x]) if x >= 0 and y >= 0 and x <= width and y <= height else -1

func _fail(message: String) -> bool:
	error = message
	return false
