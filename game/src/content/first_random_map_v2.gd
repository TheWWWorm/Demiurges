class_name ELFirstRandomMapV2
extends RefCounted
## Versioned, deterministic Etherlords I skirmish maps. Only topology and
## placements are generated here: models, spellbooks, production, shops and
## monster difficulty variants come from the user's mounted first game.
##
## API: generate(profile, options) returns a complete ELAdventureMap or null.
## `config`, `report` and `error` describe the last attempt. The canonical
## configuration is attached as random_map metadata for save regeneration.

const VERSION := 2
const SCENERY_VERSION := 3
const PREFIX := "el1_random_v"
const COLORS := ["Green", "Blue", "Red", "Black"]
const SIZES := [64, 96, 128, 160]
const LAYOUTS := ["frontier", "lakes", "crossroads", "archipelago", "inland_sea", "river_delta", "ring", "peninsulas"]
const ECONOMIES := ["scarce", "normal", "rich"]
const GUARDS := ["none", "normal", "strong"]
const GEMS := {"Green": "Emerald", "Blue": "Sapphire", "Red": "Ruby", "Black": "Diamond"}
const SUMMONS := {"Green": "SVWR", "Blue": "SKWR", "Red": "SCWR", "Black": "SSWR"}
const NO_SPOT := Vector2i(-1, -1)
const SCENERY_PATCH_SIZE := 12
const SCENERY_FAMILIES := {
	"Green": [["greenforest", "greentree", "greenbush"], ["greenstone", "greenrock"]],
	"Blue": [["bluepine", "blueel"], ["blueice", "bluestone", "blue_hill", "blue_rock"]],
	"Red": [["red_bush", "red_tree"], ["redhill", "red_stone", "red_rock", "red_voulcan"]],
	"Black": [["blacktree", "blackbush"], ["blackcrater", "blackhill", "blackstone", "rock_"]],
}

var error := ""
var config: Dictionary = {}
var report: Dictionary = {}
var _map: ELAdventureMap
var _profile: ELProfile
var _rng := 1
var _terrain_seed := 1
var _catalog: Dictionary = {}
var _land: Array[int] = []
var _palette: Dictionary = {}
var _base := 0
var _water := -1
var _occupied := PackedByteArray()
var _reserved := PackedByteArray()
var _corridor := PackedByteArray()
var _anchors: Array[Vector2i] = []
var _colors: Array[String] = []
var _starts: Array[Dictionary] = []
var _next_id := 1
var _important: Array[int] = []
var _route_grid: AStarGrid2D
var _shop_stocks: Dictionary = {}
var _network := PackedByteArray()
var _network_points: Array[Vector2i] = []
var _shape_phase := 0.0
var _home_radius := 14.0
var _reward_centers: Array[Dictionary] = []
var _land_labels := PackedInt32Array()
var _sea_labels := PackedInt32Array()
var _land_regions: Array = []
var _sea_regions: Array = []
var _ports: Array[Dictionary] = []

static func defaults(version := VERSION) -> Dictionary:
	return {"version": version, "seed": "212", "size": 96, "players": 4,
		"layout": "frontier", "biome": "mixed", "resources": "normal",
		"starting_resources": "normal", "guards": "normal", "faction": "Green",
		"roads": true, "scenery": 1, "castle_health": 30, "naval": false, "water": "normal", "coast": "rugged"}

## Bad imported configurations fail explicitly. JSON represents integers as
## doubles, so integral finite doubles are accepted, but booleans never are.
static func normalize(options: Dictionary, version := VERSION) -> Dictionary:
	var result := defaults(version)
	for key: Variant in options:
		if key is not String or not result.has(key): return {}
	for key: String in ["version", "size", "players", "scenery", "castle_health"]:
		var value: Variant = options.get(key, result[key])
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)): return {}
		result[key] = int(value)
	if result.version not in [VERSION, SCENERY_VERSION] or result.size not in SIZES or result.players < 2 or result.players > 4 or result.scenery < 0 or result.scenery > 2 or result.castle_health not in [20, 30, 60]: return {}
	for key: String in ["seed", "layout", "biome", "resources", "starting_resources", "guards", "faction", "water", "coast"]:
		var value: Variant = options.get(key, result[key])
		if value is not String: return {}
		result[key] = value
	if result.seed.strip_edges().is_empty() or result.seed.length() > 64: return {}
	for at in result.seed.length():
		if result.seed.unicode_at(at) < 32 or result.seed.unicode_at(at) == 127: return {}
	if result.layout not in LAYOUTS or (result.biome != "mixed" and result.biome not in COLORS) or result.resources not in ECONOMIES or result.starting_resources not in ECONOMIES or result.guards not in GUARDS or result.faction not in COLORS: return {}
	var roads: Variant = options.get("roads", true)
	if roads is not bool: return {}
	result.roads = roads
	var naval: Variant = options.get("naval", false)
	if naval is not bool or result.water not in ["low", "normal", "high"] or result.coast not in ["smooth", "rugged"]: return {}
	result.naval = naval
	return result

static func presets() -> Array[Dictionary]:
	return [
		{"id": "quick", "name": "Quick duel", "description": "Two castles, nearby mines and short overland approaches.", "options": {"size": 64, "players": 2, "layout": "frontier", "castle_health": 20}},
		{"id": "frontier", "name": "Frontier", "description": "A broad continent with organic bays and several routes between rivals.", "options": {"size": 96, "players": 4, "layout": "frontier"}},
		{"id": "archipelago", "name": "Island chains", "description": "Independent island kingdoms and rich outlying islands. Ships are essential.", "options": {"size": 128, "players": 4, "layout": "archipelago", "naval": true, "water": "high"}},
		{"id": "inland_sea", "name": "Inland sea", "description": "Coastal kingdoms compete around a central sea and its valuable islands.", "options": {"size": 128, "players": 4, "layout": "inland_sea", "naval": true}},
		{"id": "delta", "name": "River delta", "description": "Meandering navigable rivers separate fertile provinces and delta islands.", "options": {"size": 96, "players": 4, "layout": "river_delta", "naval": true}},
		{"id": "ring", "name": "Ring of kingdoms", "description": "An island ring broken by navigable straits encloses a contested central sea.", "options": {"size": 128, "players": 4, "layout": "ring", "naval": true}},
		{"id": "peninsulas", "name": "Peninsulas", "description": "Long coastal fingers allow a central land war and seaborne flanking routes.", "options": {"size": 128, "players": 4, "layout": "peninsulas", "naval": true}},
		{"id": "lakes", "name": "Lake country", "description": "Linked lakes and rivers create an inland sailing network.", "options": {"size": 128, "players": 4, "layout": "lakes", "naval": true}},
		{"id": "crossroads", "name": "Crossroads", "description": "Four approaches meet at a valuable contested crossroads.", "options": {"size": 96, "players": 4, "layout": "crossroads"}},
		{"id": "scarcity", "name": "Scarcity", "description": "Fewer spare resources, stronger frontier guards and a lean treasury.", "options": {"size": 96, "players": 4, "resources": "scarce", "starting_resources": "scarce", "guards": "strong"}},
		{"id": "conquest", "name": "Rich conquest", "description": "Abundant mines and rewards support longer wars between fortified castles.", "options": {"size": 128, "players": 4, "resources": "rich", "starting_resources": "rich", "castle_health": 60}}
	]

static func is_random_id(id: String) -> bool:
	return id.begins_with(PREFIX)

static func id_for_config(options: Dictionary) -> String:
	var normalized := normalize(options)
	return "" if normalized.is_empty() else PREFIX + str(normalized.version) + "_" + JSON.stringify(normalized, "", true).sha256_text().left(24)

static func seed_for_config(options: Dictionary) -> int:
	var normalized := normalize(options)
	if normalized.is_empty(): return 1
	return 1 + (int(("el1-random-map-v2:" + str(normalized.seed)).sha256_text().left(8).hex_to_int()) & 0x7fffffff) % 2147483646

static func configuration(map: ELAdventureMap) -> Dictionary:
	if map == null or not map.has_meta("random_map"): return {}
	var value: Variant = map.get_meta("random_map")
	return value.get("config", {}).duplicate(true) if value is Dictionary and value.get("config") is Dictionary else {}

## Hash the actual regenerated data, so changing installed templates cannot
## silently load a save onto different object positions or inventories.
static func content_hash(map: ELAdventureMap) -> String:
	if map == null: return ""
	return JSON.stringify({"id": map.id, "width": map.width, "height": map.height,
		"terrain": map.terrain.hex_encode(), "roads": map.roads.hex_encode(),
		"creeks": map.creeks.hex_encode(), "colorless": map.colorless.hex_encode(),
		"players": map.players, "objects": map.objects, "mobs": map.mobs,
		"document": map.document}, "", true).sha256_text()

func generate(profile: ELProfile, options: Dictionary = {}) -> ELAdventureMap:
	error = ""
	report = {}
	config = normalize(options)
	if config.is_empty(): return _fail("Invalid random-map configuration. Choose a supported preset or correct the imported settings.")
	if profile == null or profile.id != "el1": return _fail("Random maps require Etherlords I game files.")
	_profile = profile
	_rng = seed_for_config(config)
	_terrain_seed = _rng
	if not _read_catalog(): return null
	_map = ELAdventureMap.new()
	_map.profile = profile
	_map.id = id_for_config(config)
	_map.width = config.size
	_map.height = config.size
	_map.title = "Random map · %s · %s" % [str(config.layout).capitalize(), config.seed]
	_map.objective = "Destroy every rival castle. Keep your own castle standing."
	_map.set_meta("random_map", {"version": config.version, "config": config.duplicate(true)})
	_map.document = _node("scenario", {}, "", [_node("title", {}, _map.title), _node("objective", {}, _map.objective),
		_node("win_condition", {}, "Destroy every rival castle."), _node("lose_condition", {}, "Your castle loses all of its energy."),
		_node("description", {}, "Expand from your homeland, capture mines and shops, and discover the scrolls that summon stronger heroes."),
		_node("random_map", {"version": str(config.version), "config": JSON.stringify(config, "", true), "catalog_hash": _catalog_hash()})])
	_next_id = 1
	_important.clear()
	_starts.clear()
	_anchors.clear()
	_colors.clear()
	_shop_stocks.clear()
	_ports.clear()
	_land_regions.clear()
	_sea_regions.clear()
	_land_labels.clear()
	_sea_labels.clear()
	_map.terrain.resize((_map.width + 1) * (_map.height + 1))
	_map.roads.resize(_map.width * _map.height)
	_map.creeks.resize(_map.roads.size())
	_map.colorless.resize(_map.roads.size())
	_occupied.resize(_map.roads.size())
	_occupied.fill(0)
	_reserved.resize(_map.roads.size())
	_reserved.fill(0)
	_corridor.resize(_map.roads.size())
	_corridor.fill(0)
	_network.resize(_map.roads.size())
	_network.fill(0)
	_network_points.clear()
	_route_grid = AStarGrid2D.new()
	_route_grid.region = Rect2i(1, 1, _map.width - 2, _map.height - 2)
	_route_grid.cell_size = Vector2.ONE
	_route_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_route_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_route_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_route_grid.update()
	_start_points()
	_make_terrain()
	if config.naval and not _prepare_naval_terrain(): return null
	if not _make_players(): return null
	if config.naval and not _make_ports(): return null
	_make_routes()
	if not _make_homelands(): return null
	if not _make_frontiers(): return null
	if config.naval: _populate_islands()
	if config.scenery > 0:
		if config.version == VERSION:
			_make_legacy_scenery()
		else:
			# Keep a route to every strategic target before adding blockers.
			if not _check_access(true): return null
			_make_scenery()
	if not _check_terrain(): return null
	if not _check_access(): return null
	_map.document.children.append(_node("support", {"last_permanent_id": str(_next_id)}))
	report.starts = _starts.duplicate(true)
	report.seed = config.seed
	report.size = config.size
	report.objects = _map.objects.size()
	report.counts = {}
	for item: Dictionary in _map.objects:
		report.counts[item.group] = int(report.counts.get(item.group, 0)) + 1
	var water_cells := 0
	if _water >= 0:
		for y in _map.height:
			for x in _map.width:
				if _map.tile(x, y) == _water: water_cells += 1
	report.water_fraction = float(water_cells) / float(_map.width * _map.height)
	report.naval = config.naval
	report.ports = _ports.size() if config.naval else 0
	report.landmasses = _land_regions.size() if config.naval else _components(false).regions.size()
	report.water_components = _sea_regions.size() if config.naval else _components(true).regions.size()
	report.water_connected = int(report.water_components) == 1
	report.fingerprint = content_hash(_map)
	_map.set_meta("random_map_report", report.duplicate(true))
	return _map

func _fail(message: String) -> ELAdventureMap:
	error = message
	return null

func _next(limit: int) -> int:
	# Park-Miller, using a 64-bit product: stable across platform and Godot
	# releases, independent of the gameplay and global random streams.
	_rng = (_rng * 48271) % 2147483647
	return _rng % maxi(1, limit)

func _shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var other := _next(i + 1)
		var kept: Variant = values[i]
		values[i] = values[other]
		values[other] = kept

static func _keys(table: Dictionary) -> Array:
	var result := table.keys()
	result.sort()
	return result

static func _model(row: Dictionary, actor := false) -> bool:
	return not str(row.get("AdvMod", row.get("Model", "")) if actor else row.get("Model", "")).is_empty()

func _read_catalog() -> bool:
	if _profile.terrain_tiles == null:
		var tiles := ELTileSet.new()
		if not tiles.load_file(_profile.file("Resources/tileset.tsr")):
			error = "Cannot generate terrain: " + tiles.error
			return false
		_profile.terrain_tiles = tiles
	_land.clear()
	_palette.clear()
	_water = -1
	for kind: int in _keys(_profile.terrain_tiles.types):
		var row: Dictionary = _profile.terrain_tiles.types[kind]
		if int(row.get("movement", -1)) >= 0 and kind < 32: _land.append(kind)
		elif kind == 16: _water = kind
	if _land.is_empty():
		error = "The installed tileset has no walkable terrain."
		return false
	_base = _land[0]
	for color: String in COLORS:
		var choices: Array[int] = []
		for kind: int in _land:
			if ELAdventureArt.terrain_color(kind) == color: choices.append(kind)
		if choices.is_empty(): choices.append(_base)
		choices.sort_custom(func(a: int, b: int):
			var am := int(_profile.terrain_tiles.types[a].movement)
			var bm := int(_profile.terrain_tiles.types[b].movement)
			return a < b if am == bm else am < bm)
		_palette[color] = choices
	_catalog = {"heroes": {}, "castles": {}, "mines": {}, "shops": {}, "monsters": [], "scenery": [], "cuts": {}, "artifacts": [], "spells": {}}
	var heroes := _profile.table("HeroTemplates")
	var spells := _profile.table("CombatSpells")
	for color: String in COLORS:
		var found: Array[String] = []
		for key: String in _keys(heroes):
			var row: Dictionary = heroes[key]
			if row.get("Color", "") != color or str(row.get("Quest", "")) == "Yes" or int(row.get("Level", 1)) != 1 or int(row.get("Sight", 0)) < 1 or not _model(row, true): continue
			var cards := ELCatalog.deck(_profile, str(row.get("StartDeck", "")))
			if cards.size() < 8 or cards.size() > 15: continue
			var valid := true
			var creatures := 0
			for card: String in cards:
				if not ELSpellInventory.is_spell(_profile, card): valid = false
				if spells.get(card, {}).get("Class") == "Creature": creatures += 1
			if valid and creatures > 0: found.append(key)
		if found.is_empty():
			error = "No playable level-one %s hero template with a valid starting spellbook was found." % color
			return false
		_catalog.heroes[color] = found
		var castle := _building_row("MainTower", color)
		if castle.is_empty():
			error = "Missing %s castle definition in the installed game." % color
			return false
		_catalog.castles[color] = castle
		if not _model(_profile.table("ManaNodes").get("ManaNode." + color, {})):
			error = "Missing %s mana-node definition in the installed game." % color
			return false
		_catalog.spells[color] = {"Creature": [[], [], []], "Spell": [[], [], []]}
	for key: String in _keys(spells):
		var row: Dictionary = spells[key]
		var color := str(row.get("Color", ""))
		if color not in COLORS or not ELSpellInventory.is_spell(_profile, key) or row.get("IsArtifact", "False") in ["True", "Yes", true]: continue
		var tier := ["Cantrip", "Common", "Rare", "Unique"].find(str(row.get("Rarity", "")))
		if tier < 0: continue
		tier = maxi(0, tier - 1)
		var family := "Creature" if row.get("Class") == "Creature" else "Spell"
		if row.get("Class") not in ["Creature", "Sorcery", "Enchantment"]: continue
		_catalog.spells[color][family][tier].append(key)
	for key: String in _keys(_profile.table("ResourceMine")):
		var row: Dictionary = _profile.table("ResourceMine")[key]
		if int(row.get("Level", -1)) != 0 or not _model(row): continue
		var production := ELResourceSites._vector("el1", row.get("Production", []))
		for kind: String in ELResources.ORIGINAL:
			if int(production[kind]) > 0 and not _catalog.mines.has(kind): _catalog.mines[kind] = row
	for kind: String in ELResources.ORIGINAL:
		if not _catalog.mines.has(kind):
			error = "No productive %s mine definition was found in the installed game." % kind
			return false
	for color: String in COLORS:
		_catalog.shops[color] = {}
		for type: String in ["IngredientShop", "CreatureShop", "SpellShop"]:
			var best: Dictionary = {}
			var best_score := -1
			for key: String in _keys(_profile.table("NewBuildings")):
				var row: Dictionary = _profile.table("NewBuildings")[key]
				if row.get("Type") != type or int(row.get("Level", -1)) != 0 or not _model(row): continue
				var score := 2 if row.get("MagicColor", row.get("Color", "")) == color else 0
				if row.get("Rarity") == "Common": score += 4
				if score > best_score:
					best = row
					best_score = score
			if best.is_empty():
				error = "Missing %s definition in the installed game." % type
				return false
			_catalog.shops[color][type] = best
	var monsters := _profile.table("Monsters")
	var names := {}
	for key: String in _keys(monsters):
		var row: Dictionary = monsters[key]
		var name := str(row.get("Name", ""))
		if name.is_empty() or not _model(row, true): continue
		if not names.has(name): names[name] = {}
		names[name][int(row.get("DifficultyLevel", -1))] = row
	for name: String in _keys(names):
		var valid := true
		for difficulty in 5:
			var row: Dictionary = names[name].get(difficulty, {})
			if row.is_empty() or int(row.get("Level", 0)) < 1 or int(row.get("Health", 0)) < 1:
				valid = false
				continue
			var book := ELFirstMonsters.book(row)
			if book.cards.is_empty(): valid = false
			for card: String in book.cards:
				if not ELSpellInventory.is_spell(_profile, card): valid = false
		if valid: _catalog.monsters.append({"name": name, "level": int(names[name][0].Level)})
	_catalog.monsters.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.name) < str(b.name) if a.level == b.level else int(a.level) < int(b.level))
	if config.guards != "none" and _catalog.monsters.is_empty():
		error = "No playable neutral-creature definitions covering all five difficulties were found."
		return false
	for key: String in _keys(_profile.table("ResourceCut")):
		var row: Dictionary = _profile.table("ResourceCut")[key]
		if _model(row): _catalog.cuts[key] = row
	for key: String in _keys(_profile.table("TerrObj")):
		var row: Dictionary = _profile.table("TerrObj")[key]
		var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
		if _model(row) and size.x <= 4 and size.y <= 4 and not row.get("Bridge", 0): _catalog.scenery.append({"name": key, "row": row})
	for key: String in _keys(_profile.table("Artefacts")):
		if _model(_profile.table("Artefacts")[key]): _catalog.artifacts.append(key)
	var globals := _profile.table("GlobalSpells")
	for color: String in COLORS:
		for suffix: String in ["WR", "CH", "HR"]:
			var code: String = str(SUMMONS[color]).left(2) + suffix
			if not globals.has(code) or globals[code].get("Color") not in [color, "Colorless"]:
				error = "Missing %s hero-summoning spell %s in the installed game." % [color, code]
				return false
	if not _model(_profile.table("GlobalSpellCut").get("FullSpell", {})):
		error = "Missing global-spell scroll definition in the installed game."
		return false
	return true

func _catalog_hash() -> String:
	var data := {"terrain": _profile.terrain_tiles.types}
	for name: String in ["HeroTemplates", "CombatDecks", "CombatSpells", "Buildings", "ManaNodes", "ResourceMine", "NewBuildings", "ResourceCut", "Monsters", "TerrObj", "Artefacts", "GlobalSpells", "GlobalSpellCut"]:
		data[name] = _profile.table(name)
	return JSON.stringify(data, "", true).sha256_text()

func _building_row(name: String, color: String) -> Dictionary:
	var rows := _profile.table("Buildings")
	for key: String in _keys(rows):
		var row: Dictionary = rows[key]
		if (row.get("Type") == name or str(row.get("Name", key)) == name) and row.get("MagicColor", color) == color and int(row.get("Level", 0)) == 0 and _model(row): return row
	return {}

func _start_points() -> void:
	_colors.append(config.faction)
	var rest: Array = COLORS.duplicate()
	rest.erase(config.faction)
	_shuffle(rest)
	for index in range(1, int(config.players)): _colors.append(rest[index - 1])
	var positions: Array[Vector2] = [Vector2(0.22, 0.5), Vector2(0.78, 0.5)]
	if int(config.players) == 3: positions = [Vector2(0.5, 0.20), Vector2(0.22, 0.73), Vector2(0.78, 0.73)]
	elif int(config.players) == 4: positions = [Vector2(0.225, 0.225), Vector2(0.775, 0.225), Vector2(0.775, 0.775), Vector2(0.225, 0.775)]
	var quarter := _next(4)
	var turn := float(_next(701) - 350) / 10000.0
	for point: Vector2 in positions:
		var relative := (point - Vector2(0.5, 0.5)).rotated(quarter * PI * 0.5 + turn)
		_anchors.append(Vector2i(((relative + Vector2(0.5, 0.5)) * _map.width).round()))
	_shape_phase = float(_next(6284)) / 1000.0
	var fraction: float = {"low": 0.205, "normal": 0.18, "high": 0.155}[config.water]
	_home_radius = maxf(14.0, _map.width * fraction)
	# Keep two to four islands apart even in compact four-player worlds.
	if int(config.players) >= 3: _home_radius = minf(_home_radius, _anchors[0].distance_to(_anchors[1]) * 0.43)
	_reward_centers.clear()
	var center := Vector2(_map.width, _map.height) * 0.5
	var radius := maxf(5.0, _map.width * 0.075)
	if str(config.layout) in ["archipelago", "inland_sea", "ring", "lakes", "crossroads"]:
		var reward_center := center
		if config.layout == "archipelago" and int(config.players) == 2:
			var axis := (Vector2(_anchors[1]) - Vector2(_anchors[0])).normalized()
			reward_center += Vector2(-axis.y, axis.x) * _map.width * 0.28
		elif config.layout == "archipelago" and int(config.players) == 3:
			reward_center += (center - Vector2(_anchors[0])).normalized() * _map.width * 0.045
		_reward_centers.append({"point": reward_center, "radius": radius})
	elif config.layout == "river_delta":
		_reward_centers.append({"point": center + Vector2(_map.width * 0.04, _map.width * 0.22), "radius": maxf(4.0, radius * 0.75)})
	else:
		# Outlying islands make sailing worthwhile even around an unbroken
		# frontier continent or a connected set of peninsulas.
		_reward_centers.append({"point": Vector2(_map.width * 0.085, _map.width * 0.085), "radius": maxf(4.0, radius * 0.75)})
		_reward_centers.append({"point": Vector2(_map.width * 0.915, _map.width * 0.915), "radius": maxf(4.0, radius * 0.75)})


func _hash(x: int, y: int, salt: int) -> float:
	var value := (x * 73856093) ^ (y * 19349663) ^ (_terrain_seed * 83492791) ^ (salt * 2654435761)
	value &= 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return float(value) / 2147483647.0

func _noise(x: float, y: float, scale: float, salt: int) -> float:
	var ax := floori(x / scale)
	var ay := floori(y / scale)
	var sx := fposmod(x / scale, 1.0)
	var sy := fposmod(y / scale, 1.0)
	sx = sx * sx * (3.0 - 2.0 * sx)
	sy = sy * sy * (3.0 - 2.0 * sy)
	return lerpf(lerpf(_hash(ax, ay, salt), _hash(ax + 1, ay, salt), sx), lerpf(_hash(ax, ay + 1, salt), _hash(ax + 1, ay + 1, salt), sx), sy)

func _owner(point: Vector2i) -> int:
	var chosen := 0
	var best := 1.0e30
	for index in _anchors.size():
		var distance := point.distance_squared_to(_anchors[index])
		if distance < best:
			chosen = index
			best = distance
	return chosen

func _ground(point: Vector2i, varied := false) -> int:
	var color := str(config.biome)
	if color == "mixed": color = _colors[_owner(point)]
	var choices: Array = _palette[color]
	if varied and choices.size() > 1 and _noise(point.x, point.y, 8.0, 97) > 0.58: return int(choices[mini(1, choices.size() - 1)])
	return int(choices[0])

func _home_land(point: Vector2) -> bool:
	# The same coastline budget is rotated around every kingdom. Large
	# rugged islands gain broad lobes and coves; a compact inner disk still
	# fits the full opening economy. A strict neighbor bound preserves sea
	# lanes even on the smallest four-player archipelago.
	var detail := clampf(float(_map.width - 64) / 64.0, 0.0, 1.0)
	var amplitude := 0.025 if config.coast == "smooth" else 0.075 + detail * 0.16
	for index in _anchors.size():
		var offset := point - Vector2(_anchors[index])
		var angle := offset.angle() - TAU * index / _anchors.size()
		var outline := 0.48 * sin(angle * 2.0 + _shape_phase)
		outline += 0.27 * sin(angle * 3.0 - _shape_phase * 0.7)
		outline += 0.18 * sin(angle * 5.0 + _shape_phase * 1.3)
		outline += 0.22 * sin(angle + _shape_phase * 0.4)
		var limit := float(_map.width)
		for other in _anchors.size():
			if other != index: limit = minf(limit, _anchors[index].distance_to(_anchors[other]) * 0.445)
		var shore := clampf(_home_radius * (1.0 + amplitude * outline), maxf(12.8, _home_radius * 0.82), limit)
		if offset.length() < shore: return true
	return false

func _water_field(point: Vector2i) -> bool:
	var n := float(_map.width)
	var center := Vector2(n, n) * 0.5
	var relative := Vector2(point) - center
	var radius := relative.length() / n
	var angle := relative.angle()
	var amount: float = {"low": -0.035, "normal": 0.0, "high": 0.035}[config.water]
	var rough := 0.007 if config.coast == "smooth" else 0.020
	var jitter := (_noise(point.x, point.y, n / 7.0, 317) - 0.5) * rough * 2.0
	jitter += sin(angle * 7.0 + _shape_phase) * rough * 0.25
	var wet := false
	match str(config.layout):
		"archipelago":
			wet = true
		"inland_sea":
			var ellipse := Vector2(relative.x / 1.12, relative.y / 0.9).length() / n
			wet = ellipse < 0.285 + amount + jitter or radius > 0.56 - amount * 0.3 + jitter
		"river_delta":
			var river := relative.x - sin(float(point.y) / n * TAU + _shape_phase) * n * 0.045
			var braid := relative.y - sin(float(point.x) / n * TAU * 0.8 + _shape_phase) * n * 0.035
			var mouth := float(point.y) / n > 0.68 and absf(relative.x) < n * (0.14 + (float(point.y) / n - 0.68) * 0.6)
			wet = absf(river) / n < 0.035 + amount * 0.3 + jitter * 0.4 or absf(braid) / n < 0.030 + amount * 0.3 + jitter * 0.3 or mouth
		"ring":
			var gap_angle := angle - (Vector2(_anchors[0]) - center).angle() - PI / _anchors.size()
			var strait := absf(sin(gap_angle * _anchors.size() * 0.5)) < 0.055
			wet = radius < 0.255 + amount + jitter or radius > 0.47 - amount * 0.3 + jitter or (strait and radius > 0.16)
		"peninsulas":
			wet = radius > 0.135 - amount * 0.3 + jitter
			for anchor: Vector2i in _anchors:
				var tip := Vector2(anchor) - center
				var fraction := clampf(relative.dot(tip) / maxf(1.0, tip.length_squared()), 0.0, 1.0)
				var nearest := tip * fraction
				var width := n * (0.055 - amount * 0.4 + jitter * 0.5) * (1.2 - fraction * 0.3)
				if relative.distance_to(nearest) < width: wet = false
		"crossroads":
			var bend := sin(radius * 12.0 + _shape_phase) * 0.12
			var split := absf(sin((angle + bend - (Vector2(_anchors[0]) - center).angle() - PI / _anchors.size()) * _anchors.size() * 0.5))
			wet = split < 0.10 + amount or radius > 0.49 + jitter or radius < 0.15 + amount
		"lakes":
			var field := _noise(point.x, point.y, n / 3.5, 17) * 0.7 + _noise(point.x, point.y, n / 6.0, 81) * 0.3
			wet = field > 0.48 - amount or radius < 0.16 + amount
			wet = wet or radius > 0.56 + jitter
		_:
			var coastline := 0.435 - amount + 0.045 * sin(angle * 3.0 + _shape_phase) + jitter
			wet = radius > coastline
	# Organic homelands have a fixed minimum usable area and a common
	# resource budget. No road later fills the separating sea.
	if _home_land(Vector2(point)): wet = false
	for island: Dictionary in _reward_centers:
		var offset: Vector2 = Vector2(point) - Vector2(island.point)
		var shore := float(island.radius) * (1.0 + 0.07 * sin(offset.angle() * 5.0 + _shape_phase))
		if offset.length() < shore: wet = false
		elif config.layout == "archipelago" and offset.length() < shore + 3.0: wet = true
	# An ocean rim gives every waterway an off-shore route. Homelands and
	# harbors sit clear of it, so a coastal voyage never leaves map bounds.
	if config.naval and (point.x <= 1 or point.y <= 1 or point.x >= _map.width - 1 or point.y >= _map.height - 1): wet = true
	return wet

func _make_terrain() -> void:
	for y in range(_map.height + 1):
		for x in range(_map.width + 1):
			var point := Vector2i(x, y)
			_map.terrain[y * (_map.width + 1) + x] = _water if _water >= 0 and _water_field(point) else _ground(point, true)
	if not config.naval:
		for anchor: Vector2i in _anchors: _paint_disk(anchor, 11, false)

func _sea_cell(point: Vector2i) -> bool:
	if not _inside(point): return false
	for dy in 2:
		for dx in 2:
			if _map.tile(point.x + dx, point.y + dy) == 16: return true
	return false

func _components(sea: bool) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(_map.width * _map.height)
	labels.fill(-1)
	var regions: Array[Dictionary] = []
	for y in _map.height:
		for x in _map.width:
			var at := Vector2i(x, y)
			if labels[y * _map.width + x] >= 0 or (_sea_cell(at) if sea else _walkable(at)) == false: continue
			var id := regions.size()
			var cells: Array[Vector2i] = [at]
			labels[y * _map.width + x] = id
			var head := 0
			var total := Vector2.ZERO
			while head < cells.size():
				var point := cells[head]
				head += 1
				total += Vector2(point)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var next := point + Vector2i(dx, dy)
						if not _inside(next): continue
						var offset := next.y * _map.width + next.x
						if labels[offset] >= 0 or (_sea_cell(next) if sea else _walkable(next)) == false: continue
						# Match ELFirstNaval.connected: a diagonal cannot cut the
						# corner of the other terrain domain.
						if dx != 0 and dy != 0:
							var side_x := point + Vector2i(dx, 0)
							var side_y := point + Vector2i(0, dy)
							if sea and (not _sea_cell(side_x) or not _sea_cell(side_y)): continue
							if not sea and (not _walkable(side_x) or not _walkable(side_y)): continue
						labels[offset] = id
						cells.append(next)
			regions.append({"id": id, "cells": cells, "center": total / cells.size()})
	return {"labels": labels, "regions": regions}

func _prepare_naval_terrain() -> bool:
	if _water != 16:
		error = "The installed tileset has no suitable water terrain for sailing."
		return false
	# Join natural lakes to the ocean by actual waterways. The channel
	# search cannot enter the protected castle regions.
	var sea := _components(true)
	var main := 0
	for index in sea.regions.size():
		if sea.regions[index].cells.size() > sea.regions[main].cells.size(): main = index
	if sea.regions.is_empty():
		error = "The chosen world has no navigable sea."
		return false
	if sea.regions.size() > 1:
		var channels := AStarGrid2D.new()
		channels.region = Rect2i(0, 0, _map.width, _map.height)
		channels.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
		channels.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
		channels.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
		channels.update()
		for y in _map.height:
			for x in _map.width:
				var point := Vector2i(x, y)
				var home_closed := false
				for anchor: Vector2i in _anchors:
					if point.distance_to(anchor) < _home_radius + 1.0: home_closed = true
				channels.set_point_solid(point, home_closed and not _sea_cell(point))
				channels.set_point_weight_scale(point, 1.0 if _sea_cell(point) else 7.0)
		for index in sea.regions.size():
			if index == main: continue
			var start: Vector2i = sea.regions[index].cells[0]
			var target: Vector2i = sea.regions[main].cells[0]
			var best := 1.0e30
			for point: Vector2i in sea.regions[main].cells:
				var distance := start.distance_squared_to(point)
				if distance < best:
					best = distance
					target = point
			var route := channels.get_id_path(start, target)
			if route.is_empty():
				error = "Could not join the world's waterways without cutting into a homeland."
				return false
			for point: Vector2i in route:
				for dy in 2:
					for dx in 2: _map.terrain[(point.y + dy) * (_map.width + 1) + point.x + dx] = 16
		sea = _components(true)
	var land := _components(false)
	_land_labels = land.labels
	_land_regions = land.regions
	_sea_labels = sea.labels
	_sea_regions = sea.regions
	for y in range(1, _map.height - 1):
		for x in range(1, _map.width - 1): _route_grid.set_point_solid(Vector2i(x, y), not _walkable(Vector2i(x, y)))
	for anchor: Vector2i in _anchors:
		if _land_labels[anchor.y * _map.width + anchor.x] < 0:
			error = "A homeland was lost while shaping the coast."
			return false
	return true

func _region_at(point: Vector2i) -> int:
	return int(_land_labels[point.y * _map.width + point.x]) if _inside(point) and _land_labels.size() == _map.width * _map.height else -1

func _make_ports() -> bool:
	_ports.clear()
	var candidates: Dictionary = {}
	for region: Dictionary in _land_regions:
		var choices: Array[Dictionary] = []
		for point: Vector2i in region.cells:
			if point.x < 2 or point.y < 2 or point.x > _map.width - 3 or point.y > _map.height - 3 or _reserved[point.y * _map.width + point.x] != 0: continue
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var water := point + direction
				if _sea_cell(water): choices.append({"land": point, "water": water})
		candidates[region.id] = choices
	var homes: Dictionary = {}
	for start: Dictionary in _starts:
		var region := _region_at(Vector2i(start.x, start.y))
		start.island = region
		homes[region] = true
		var chosen: Array[Vector2i] = []
		for number in 2:
			var best: Dictionary = {}
			var score := 1.0e30
			for candidate: Dictionary in candidates.get(region, []):
				var land: Vector2i = candidate.land
				if _reserved[land.y * _map.width + land.x] != 0: continue
				if not chosen.is_empty() and land.distance_to(chosen[0]) < maxf(6.0, _home_radius * 0.7): continue
				var cost := land.distance_squared_to(Vector2i(start.x, start.y))
				if cost < score:
					score = cost
					best = candidate
			if best.is_empty():
				error = "Could not create two accessible harbors for player %d." % int(start.player)
				return false
			chosen.append(best.land)
			_register_port(best.land, best.water, region, int(start.player))
	for region: Dictionary in _land_regions:
		if homes.has(region.id) or region.cells.size() < 36: continue
		var chosen: Array[Vector2i] = []
		for number in 2:
			var best: Dictionary = {}
			var score := -1.0
			for candidate: Dictionary in candidates.get(region.id, []):
				var land: Vector2i = candidate.land
				if _reserved[land.y * _map.width + land.x] != 0: continue
				var cost: float = land.distance_squared_to(chosen[0]) if not chosen.is_empty() else 1.0 / (1.0 + Vector2(land).distance_squared_to(region.center))
				if cost > score:
					score = cost
					best = candidate
			if best.is_empty(): break
			chosen.append(best.land)
			_register_port(best.land, best.water, int(region.id), 0)
		if chosen.is_empty():
			error = "A resource island has no usable landing coast."
			return false
	var payload := {"version": 1, "water_type": 16, "ports": _ports.duplicate(true)}
	_map.set_meta("first_naval", payload)
	_map.document.children.append(_node("first_naval", {"data": JSON.stringify(payload, "", true)}))
	return true

func _register_port(land: Vector2i, water: Vector2i, island: int, owner: int) -> void:
	var id := _ports.size()
	_ports.append({"id": id, "land": [land.x, land.y], "water": [water.x, water.y], "island": island, "owner": owner, "name": "Harbor %d" % (id + 1)})
	for point: Vector2i in [land, water]:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var at := point + Vector2i(dx, dy)
				if _inside(at): _reserved[at.y * _map.width + at.x] = 1
	_corridor[land.y * _map.width + land.x] = 1

func _region_root(region: int) -> Vector2i:
	if region < 0 or region >= _land_regions.size(): return NO_SPOT
	var best := NO_SPOT
	var distance := 1.0e30
	for point: Vector2i in _land_regions[region].cells:
		if _occupied[point.y * _map.width + point.x] != 0: continue
		var cost := Vector2(point).distance_squared_to(_land_regions[region].center)
		if cost < distance:
			distance = cost
			best = point
	return best

func _served_island(region: int) -> bool:
	if not config.naval: return true
	for port: Dictionary in _ports:
		if int(port.island) == region: return true
	return false

func _populate_islands() -> void:
	var homes := {}
	for start: Dictionary in _starts: homes[int(start.island)] = true
	var placed_regions := {}
	for port: Dictionary in _ports:
		var region := int(port.island)
		if homes.has(region) or placed_regions.has(region): continue
		placed_regions[region] = true
		var center: Vector2 = _land_regions[region].center
		var source := _region_root(region)
		if source == NO_SPOT: continue
		for index in (2 if config.resources == "scarce" else 3):
			var kind: String = ["Stone", "Diamond", "Lotus"][index]
			var row: Dictionary = _catalog.mines[kind]
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var pos := _find_spot(Vector2i(center) + Vector2i(index * 3 - 3, 1), size, 12, -1, true, true)
			if pos == NO_SPOT or _region_at(pos) != region: continue
			var item := _place("mines", str(row.Name), pos, row, 0, _colors[index % _colors.size()], [_node("level", {}, "0")])
			_clear_footprint(pos, size)
			_connect_site(source, item, size)
			_important.append(int(item.permanent_id) - 1)
			if config.guards != "none": _add_guard(pos - Vector2i(2, 1), index % _colors.size(), 4 + index)
		_add_pickup(Vector2i(center) + Vector2i(1, -2), -1, 25 if config.resources != "scarce" else 12)

func _make_players() -> bool:
	var center := Vector2(_map.width, _map.height) * 0.5
	for index in int(config.players):
		var color := _colors[index]
		var player := index + 1
		var treasury: int = {"scarce": 8, "normal": 20, "rich": 50}[config.starting_resources]
		var balances := {}
		for kind: String in ELResources.ORIGINAL: balances[kind] = str(treasury if kind in ["Root", "Lotus"] else maxi(2, int(treasury) / 2))
		var relations: Array = []
		for rival in int(config.players): relations.append(_node("opponent", {"id": str(rival + 1), "relations": "255" if rival == index else "0"}))
		var global: Array = []
		for code: String in _keys(_profile.table("GlobalSpells")):
			var row: Dictionary = _profile.table("GlobalSpells")[code]
			if row.get("Color", "Colorless") in [color, "Colorless"] and (code == SUMMONS[color] or code in [ELGlobalSpells.DEFENDER, ELGlobalSpells.WARRIOR] or ELGlobalSpells.RITUALS.has(code)):
				global.append(_node("spell", {"code": code}))
		var node := _node("player", {"id": str(player), "health": str(config.castle_health), "blazon": str(index), "blazon_color": str(index)}, "", [
			_node("color", {}, color), _node("name", {}, "Commander %d" % player), _node("start_resources", balances),
			_node("diplomacy", {}, "", relations), _node("global_spells", {}, "", global)])
		_map.players.append(node)
		var row: Dictionary = _catalog.castles[color]
		var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
		var castle_at := _anchors[index] - size / 2
		var castle := _place("buildings", "MainTower", castle_at, row, player, color, [_node("level", {}, "0")], {"mana_income": "50"})
		var inward := (center - Vector2(_anchors[index])).normalized()
		var expected := Vector2i((Vector2(_anchors[index]) + inward * (maxi(size.x, size.y) * 0.5 + 3.0)).round())
		var hero_at := _find_spot(expected, Vector2i.ONE, 6, index, false, false)
		if hero_at == NO_SPOT:
			error = "Could not place a hero beside castle %d." % player
			return false
		var heroes: Array = _catalog.heroes[color]
		var hero_name: String = heroes[_next(heroes.size())]
		var hero := _place("heroes", hero_name, hero_at, _profile.table("HeroTemplates")[hero_name], player, color)
		_paint_disk(hero_at, 4, false)
		_starts.append({"player": player, "color": color, "x": hero_at.x, "y": hero_at.y, "hero": [hero_at.x, hero_at.y],
			"castle": [castle_at.x, castle_at.y], "hero_id": int(hero.permanent_id) - 1, "castle_id": int(castle.permanent_id) - 1, "sites": []})
	return true

func _make_routes() -> void:
	if config.naval:
		for port: Dictionary in _ports:
			var land := Vector2i(port.land[0], port.land[1])
			var source := _region_root(int(port.island))
			if int(port.owner) > 0:
				var start: Dictionary = _starts[int(port.owner) - 1]
				source = Vector2i(start.x, start.y)
			if source != NO_SPOT: _connect(source, land, 1, true)
		for index in _starts.size():
			var first := Vector2i(_starts[index].x, _starts[index].y)
			var next: Dictionary = _starts[(index + 1) % _starts.size()]
			var second := Vector2i(next.x, next.y)
			if _region_at(first) == _region_at(second): _connect(first, second, 1, true)
		return
	var hub := Vector2i(_map.width / 2, _map.height / 2)
	_paint_disk(hub, 7, false)
	for index in _starts.size():
		var start := Vector2i(_starts[index].x, _starts[index].y)
		_connect(start, hub, 2, true)
		if config.layout not in ["crossroads", "archipelago", "inland_sea", "peninsulas"]:
			var next: Dictionary = _starts[(index + 1) % _starts.size()]
			_connect(start, Vector2i(next.x, next.y), 2, true)

func _make_homelands() -> bool:
	var center := Vector2(_map.width, _map.height) * 0.5
	for index in _starts.size():
		var start: Dictionary = _starts[index]
		var origin := Vector2(start.x, start.y)
		var inward := (center - origin).normalized()
		var side := Vector2(-inward.y, inward.x)
		var color: String = start.color
		var entries: Array = [
			{"group": "mana_nodes", "name": "ManaNode", "row": _profile.table("ManaNodes")["ManaNode." + color], "forward": 1, "side": 6},
			{"group": "mines", "name": _catalog.mines.Root.Name, "row": _catalog.mines.Root, "forward": 0, "side": -7},
			{"group": "mines", "name": _catalog.mines.Lotus.Name, "row": _catalog.mines.Lotus, "forward": 6, "side": -8},
			{"group": "mines", "name": _catalog.mines[GEMS[color]].Name, "row": _catalog.mines[GEMS[color]], "forward": 12, "side": -7},
			{"group": "factories", "name": _catalog.shops[color].IngredientShop.Name, "row": _catalog.shops[color].IngredientShop, "forward": 6, "side": 6},
			{"group": "laboratories", "name": _catalog.shops[color].CreatureShop.Name, "row": _catalog.shops[color].CreatureShop, "forward": 10, "side": 8},
			{"group": "laboratories", "name": _catalog.shops[color].SpellShop.Name, "row": _catalog.shops[color].SpellShop, "forward": -5, "side": 6},
		]
		for entry: Dictionary in entries:
			var desired := Vector2i((origin + inward * float(entry.forward) + side * float(entry.side)).round())
			var size: Vector2i = ELAdventureGrid.footprint(entry.row, 0).size
			var position := _find_spot(desired, size, 16, index, false, true)
			if position == NO_SPOT:
				error = "Could not fit a complete starting economy for player %d. Try a larger map." % int(start.player)
				return false
			var children: Array = [_node("level", {}, "0")]
			if entry.group == "laboratories": children.append_array(_shop_stock(entry.row.Type))
			var item := _place(entry.group, str(entry.name), position, entry.row, 0, color, children)
			start.sites.append(int(item.permanent_id) - 1)
			_important.append(int(item.permanent_id) - 1)
			_clear_footprint(position, size)
			_connect_site(Vector2i(start.x, start.y), item, size)
		for number in 3:
			var desired := Vector2i((origin + inward * (4 + number * 4) - side * 3).round())
			_add_pickup(desired, index, 15 if config.resources == "normal" else (7 if config.resources == "scarce" else 30))
	return true

func _shop_stock(type: String) -> Array:
	if _shop_stocks.has(type): return _shop_stocks[type].duplicate(true)
	var nodes: Array = []
	var family := "Creature" if type == "CreatureShop" else "Spell"
	for tier in 3:
		var children: Array = []
		for color: String in COLORS:
			var choices: Array = _catalog.spells[color][family][tier].duplicate()
			_shuffle(choices)
			for code: String in choices.slice(0, 6): children.append(_node("spell", {}, code))
		if not children.is_empty(): nodes.append(_node("spells", {"level": str(tier + 1)}, "", children))
	_shop_stocks[type] = nodes
	return nodes.duplicate(true)

func _make_frontiers() -> bool:
	var center := Vector2(_map.width, _map.height) * 0.5
	# Each commander gets the same two recruitment upgrades in the frontier;
	# optional extra castle spells make exploration useful after the opening.
	for index in _starts.size():
		var start: Dictionary = _starts[index]
		var home := Vector2(start.x, start.y)
		var inward := (center - home).normalized()
		var side := Vector2(-inward.y, inward.x)
		start.rewards = []
		for tier in 2:
			var code: String = str(SUMMONS[start.color]).left(2) + ("CH" if tier == 0 else "HR")
			var desired := Vector2i(home.lerp(center, 0.48 + tier * 0.3) + side * (8 if tier == 0 else -5))
			var placed := _add_scroll(desired, index, code, tier + 2)
			if placed < 0:
				error = "Could not place a recruitment scroll for player %d. Try a larger map." % int(start.player)
				return false
			start.rewards.append(placed)
		var pool: Array[String] = []
		for code: String in _keys(_profile.table("GlobalSpells")):
			var row: Dictionary = _profile.table("GlobalSpells")[code]
			if row.get("Color") not in [start.color, "Colorless"] or code in ELGlobalSpells.SUMMONS or not ELGlobalSpells.supported(code): continue
			if code in [ELGlobalSpells.DEFENDER, ELGlobalSpells.WARRIOR] or ELGlobalSpells.RITUALS.has(code): continue
			pool.append(code)
		if not pool.is_empty(): _add_scroll(Vector2i(home.lerp(center, 0.65) + side * 10), index, pool[_next(pool.size())], 3)

	var abundance := ECONOMIES.find(config.resources)
	var per_player := 2 + abundance * 2 + maxi(0, (_map.width - 64) / 32)
	for index in _starts.size():
		var start: Dictionary = _starts[index]
		var home := Vector2(start.x, start.y)
		var forward := (center - home).normalized()
		var side := Vector2(-forward.y, forward.x)
		for number in per_player:
			var fraction := 0.45 + float(number % 3) * 0.15
			var desired := Vector2i((home.lerp(center, fraction) + side * ((_next(13) - 6) + (8 if number % 2 == 0 else -8))).round())
			var kind: String = ELResources.ORIGINAL[(number + index + 2) % ELResources.ORIGINAL.size()]
			if number == 0: kind = "Stone"
			var row: Dictionary = _catalog.mines[kind]
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var pos := _find_spot(desired, size, 14, -1, false, true)
			if pos == NO_SPOT: continue
			var item := _place("mines", str(row.Name), pos, row, 0, start.color, [_node("level", {}, "0")])
			_clear_footprint(pos, size)
			_connect_site(Vector2i(start.x, start.y), item, size)
			_important.append(int(item.permanent_id) - 1)
			if config.guards != "none": _add_guard(Vector2i((Vector2(pos) - forward * 2).round()), index, 1 + number / 2)
			_add_pickup(pos + size + Vector2i(2, 2), -1, 10 + abundance * 10)
		# Optional adventure rewards use genuine installed artifact rows.
		if not _catalog.artifacts.is_empty():
			var name: String = _catalog.artifacts[_next(_catalog.artifacts.size())]
			var row: Dictionary = _profile.table("Artefacts")[name]
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var pos := _find_spot(Vector2i(home.lerp(center, 0.7)), size, 12, -1, false, true)
			if pos != NO_SPOT:
				var item := _place("artefacts", name, pos, row)
				_clear_footprint(pos, size)
				_connect_site(Vector2i(start.x, start.y), item, size)
				_important.append(int(item.permanent_id) - 1)
				if config.guards != "none": _add_guard(pos - Vector2i(2, 1), index, 4)
		if config.guards != "none":
			for number in (2 if config.guards == "normal" else 3):
				_add_guard(Vector2i(home.lerp(center, 0.6 + number * 0.1) + side * (5 + number * 3)), index, 2 + number)


	return true

func _add_scroll(desired: Vector2i, home: int, code: String, tier: int) -> int:
	var row: Dictionary = _profile.table("GlobalSpellCut")["FullSpell"]
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var pos := _find_spot(desired, size, 20, -1, false, true)
	if pos == NO_SPOT and config.naval:
		pos = _find_spot(Vector2i(_starts[home].x, _starts[home].y), size, _map.width / 2, home, true, true)
	if pos == NO_SPOT: return -1
	var item := _place("global_spells", "FullSpell", pos, row, 0, _colors[home], [_node("spells", {}, "", [_node("spell", {"code": code})])])
	_clear_footprint(pos, size)
	_connect_site(Vector2i(_starts[home].x, _starts[home].y), item, size)
	_important.append(int(item.permanent_id) - 1)
	if config.guards != "none": _add_guard(pos - Vector2i(2, 1), home, tier)
	return int(item.permanent_id) - 1

func _add_pickup(desired: Vector2i, home: int, amount: int) -> void:
	if _catalog.cuts.is_empty(): return
	var keys := _keys(_catalog.cuts)
	var name: String = keys[_next(keys.size())]
	var row: Dictionary = _catalog.cuts[name]
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var pos := _find_spot(desired, size, 8, home, false, true)
	if pos == NO_SPOT: return
	var resources: Array = []
	# A visible pile gives a small mixed cache, avoiding a dead opening when
	# an installed pile's display name is not one of the resource constants.
	for kind: String in ELResources.ORIGINAL: resources.append(_node("resource", {"type": kind, "amount": str(amount if kind in ["Root", "Lotus"] else maxi(1, amount / 3))}))
	var item := _place("resource_cuts", name, pos, row, 0, "", [_node("resources", {}, "", resources)])
	_clear_footprint(pos, size)
	var seat := home if home >= 0 else _owner(pos)
	_connect_site(Vector2i(_starts[seat].x, _starts[seat].y), item, size)
	_important.append(int(item.permanent_id) - 1)

func _add_guard(desired: Vector2i, home: int, tier: int) -> void:
	var pos := _find_spot(desired, Vector2i.ONE, 7, -1, true, false)
	if pos == NO_SPOT: return
	if config.naval and not _served_island(_region_at(pos)): return
	for start: Dictionary in _starts:
		if pos.distance_to(Vector2i(start.x, start.y)) < 12.0: return
	var target := (2 + tier) if config.guards == "strong" else maxi(1, tier)
	var pool: Array = []
	var best := 1000
	for entry: Dictionary in _catalog.monsters:
		var delta := absi(int(entry.level) - target)
		if delta < best:
			best = delta
			pool.clear()
		if delta == best: pool.append(entry)
	if pool.is_empty(): return
	var chosen: Dictionary = pool[_next(pool.size())]
	var row := ELFirstMonsters.definition(_profile, chosen.name, 0)
	var item := _place("np_heroes", chosen.name, pos, row, 0, _colors[home], [_node("monster")])
	_paint_disk(pos, 2, false)
	_important.append(int(item.permanent_id) - 1)

func _make_legacy_scenery() -> void:
	if int(config.scenery) == 0 or _catalog.scenery.is_empty(): return
	var target := _map.width * _map.height * int(config.scenery) / 180
	for attempt in target * 5:
		if target <= 0: break
		var pos := Vector2i(2 + _next(_map.width - 5), 2 + _next(_map.height - 5))
		var near_home := false
		for start: Dictionary in _starts:
			if pos.distance_to(Vector2i(start.x, start.y)) < 7: near_home = true
		if near_home or _noise(pos.x, pos.y, 12.0, 821) < 0.45: continue
		var entry: Dictionary = _catalog.scenery[_next(_catalog.scenery.size())]
		var size: Vector2i = ELAdventureGrid.footprint(entry.row, 0).size
		if not _fits(pos, size, true, true): continue
		_place("terrain_objects", entry.name, pos, entry.row)
		target -= 1

func _scenery_catalog() -> Dictionary:
	var pools := {}
	var rows := _profile.table("TerrObj")
	var keys := _keys(rows)
	for color: String in COLORS:
		var plants: Array[Dictionary] = []
		var stones: Array[Dictionary] = []
		var landmarks: Array[Dictionary] = []
		var families: Array = SCENERY_FAMILIES[color]
		for key: String in keys:
			var name := key.to_lower()
			var plant: bool = families[0].any(func(prefix: String) -> bool: return name.begins_with(prefix))
			if not plant and not families[1].any(func(prefix: String) -> bool: return name.begins_with(prefix)): continue
			var row: Dictionary = rows[key]
			if not _model(row) or row.get("Bridge", 0): continue
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var span := maxi(size.x, size.y)
			var entry := {"name": key, "row": row}
			if span > 4:
				if span <= 8: landmarks.append(entry)
			elif plant: plants.append(entry)
			else: stones.append(entry)
		# A content pack can use different terrain object names.
		if plants.is_empty() and stones.is_empty(): plants.assign(_catalog.scenery)
		pools[color] = {"plants": plants, "stones": stones, "landmarks": landmarks}
	return pools

func _make_scenery() -> void:
	var pools := _scenery_catalog()
	var land := PackedByteArray()
	land.resize(_map.width * _map.height)
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			if _walkable(Vector2i(x, y)): land[y * _map.width + x] = 1
	# Give each patch of land its own budget. Coastlines and the backs of
	# homelands get coverage even when most of the world is water.
	for top in range(2, _map.height - 2, SCENERY_PATCH_SIZE):
		for left in range(2, _map.width - 2, SCENERY_PATCH_SIZE):
			var area := Rect2i(left, top, SCENERY_PATCH_SIZE, SCENERY_PATCH_SIZE)
			_make_scenery_patch(area, land, pools)

func _make_scenery_patch(area: Rect2i, land: PackedByteArray, pools: Dictionary) -> void:
	var points: Array[Vector2i] = []
	var dry := 0
	for y in range(area.position.y, mini(area.end.y, _map.height - 2)):
		for x in range(area.position.x, mini(area.end.x, _map.width - 2)):
			var offset := y * _map.width + x
			if land[offset] == 0: continue
			dry += 1
			if _reserved[offset] == 0 and _corridor[offset] == 0: points.append(Vector2i(x, y))
	if points.is_empty() or dry < 4: return
	_shuffle(points)
	var focus := points[0]
	var density := lerpf(0.065, 0.135, _noise(focus.x, focus.y, 24.0, 821))
	if config.scenery == 2: density *= 1.45
	var remaining := maxi(1, roundi(dry * density))
	# A patch has one dominant form and some contrasting details. Its
	# scattered props continue into the next patch instead of forming a grid.
	var rocky := _noise(focus.x, focus.y, 28.0, 1567) > 0.59
	if points.size() >= 50 and _hash(focus.x, focus.y, 237) < 0.42:
		for point: Vector2i in points:
			if _place_scenery(point, _scenery_pool(point, pools).landmarks, land):
				remaining -= 1
				break
	var cluster := points.duplicate()
	cluster.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var first := focus.distance_squared_to(a)
		var second := focus.distance_squared_to(b)
		return a.y * _map.width + a.x < b.y * _map.width + b.x if first == second else first < second)
	var clustered := ceili(remaining * 0.7)
	for point: Vector2i in cluster:
		if clustered <= 0 or point.distance_squared_to(focus) > 25: break
		if _place_scenery_detail(point, pools, land, rocky):
			remaining -= 1
			clustered -= 1
	for point: Vector2i in points:
		if remaining <= 0: break
		if _place_scenery_detail(point, pools, land, not rocky): remaining -= 1

func _scenery_pool(point: Vector2i, pools: Dictionary) -> Dictionary:
	var color := ELAdventureArt.terrain_color(_map.tile(point.x, point.y))
	return pools[color] if pools.has(color) else pools[_colors[_owner(point)]]

func _place_scenery_detail(point: Vector2i, pools: Dictionary, land: PackedByteArray, rocky: bool) -> bool:
	var pool := _scenery_pool(point, pools)
	var primary: Array = pool.stones if rocky else pool.plants
	var secondary: Array = pool.plants if rocky else pool.stones
	return _place_scenery(point, primary, land) or _place_scenery(point, secondary, land)

func _place_scenery(point: Vector2i, pool: Array, land: PackedByteArray) -> bool:
	if pool.is_empty(): return false
	var first := _next(pool.size())
	var rotation := _next(4) * 4
	for attempt in mini(pool.size(), 5):
		var entry: Dictionary = pool[(first + attempt) % pool.size()]
		var size: Vector2i = ELAdventureGrid.footprint(entry.row, rotation).size
		var origin := point - size / 2
		if not _scenery_fits(origin, size, land): continue
		_place("terrain_objects", entry.name, origin, entry.row, 0, "", [], {}, rotation)
		return true
	return false

func _scenery_fits(origin: Vector2i, size: Vector2i, land: PackedByteArray) -> bool:
	if origin.x < 2 or origin.y < 2 or origin.x + size.x > _map.width - 2 or origin.y + size.y > _map.height - 2: return false
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var offset := y * _map.width + x
			if land[offset] == 0 or _reserved[offset] != 0 or _corridor[offset] != 0: return false
	return true

static func _node(tag: String, attrs: Dictionary = {}, text := "", children: Array = []) -> Dictionary:
	return {"tag": tag, "attrs": attrs, "text": text, "children": children}

func _place(group: String, name: String, position: Vector2i, row: Dictionary, owner := 0, color := "", extra: Array = [], attrs: Dictionary = {}, rotation := 0) -> Dictionary:
	var id := _next_id
	_next_id += 1
	var properties := attrs.duplicate()
	properties.permanent_id = str(id)
	properties.id = str(id)
	var children: Array = [_node("place", {"x": str(position.x), "y": str(position.y), "mr": str(rotation)}), _node("template", {}, name)]
	if not color.is_empty(): children.append(_node("color", {}, color))
	children.append_array(extra)
	var node := _node("hero" if group in ["heroes", "np_heroes"] else "object", properties, "", children)
	var item := {"group": group, "owner": owner, "node": node, "x": position.x, "y": position.y, "rotation": rotation,
		"permanent_id": id, "id": id, "name": name}
	_map.objects.append(item)
	var size := Vector2i.ONE if group in ["heroes", "np_heroes"] else Vector2i(ELAdventureGrid.footprint(row, rotation).size)
	# Original groves combine adjacent terrain props. Sites and legacy maps
	# keep their one-cell placement margin.
	var margin := 0 if group == "terrain_objects" and config.version >= SCENERY_VERSION else 1
	for y in range(position.y - margin, position.y + size.y + margin):
		for x in range(position.x - margin, position.x + size.x + margin):
			if not _inside(Vector2i(x, y)): continue
			_reserved[y * _map.width + x] = 1
			if x >= position.x and x < position.x + size.x and y >= position.y and y < position.y + size.y:
				_occupied[y * _map.width + x] = 1
				if _route_grid.region.has_point(Vector2i(x, y)): _route_grid.set_point_solid(Vector2i(x, y), true)
	return item

func _inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < _map.width and point.y < _map.height

func _walkable(point: Vector2i) -> bool:
	if not _inside(point): return false
	for dy in 2:
		for dx in 2:
			if (config.naval and _map.tile(point.x + dx, point.y + dy) == 16) or int(_profile.terrain_tiles.types.get(_map.tile(point.x + dx, point.y + dy), {}).get("movement", -1)) < 0: return false
	return true

func _fits(at: Vector2i, size: Vector2i, require_land: bool, avoid_roads: bool) -> bool:
	if at.x < 2 or at.y < 2 or at.x + size.x >= _map.width - 2 or at.y + size.y >= _map.height - 2: return false
	if config.naval and not _ports.is_empty() and not _served_island(_region_at(at)): return false
	for y in range(at.y, at.y + size.y):
		for x in range(at.x, at.x + size.x):
			var offset := y * _map.width + x
			if _reserved[offset] != 0 or (avoid_roads and _corridor[offset] != 0): return false
			if (require_land or config.naval) and not _walkable(Vector2i(x, y)): return false
	if config.naval and not _ports.is_empty():
		var sources: Array[Dictionary] = []
		for port: Dictionary in _ports:
			if int(port.island) != _region_at(at): continue
			var source := Vector2i(port.land[0], port.land[1])
			sources.append({"point": source, "distance": source.distance_squared_to(at)})
		sources.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
		for source: Dictionary in sources:
			if not _route_grid.get_id_path(source.point, at).is_empty(): return true
		return false
	return true

func _find_spot(near: Vector2i, size: Vector2i, radius: int, home: int, require_land: bool, avoid_roads: bool) -> Vector2i:
	# Deterministic expanding rings preserve the desired strategic distance.
	var turn := _next(4)
	for distance in range(radius + 1):
		for edge in 4:
			for step in range(-distance, distance + 1):
				var delta := Vector2i(step, -distance)
				for rotation in (edge + turn) % 4: delta = Vector2i(-delta.y, delta.x)
				var point := near + delta
				if home >= 0 and _owner(point + size / 2) != home: continue
				if config.naval and home >= 0 and _region_at(point + size / 2) != _region_at(_anchors[home]): continue
				if _fits(point, size, require_land, avoid_roads): return point
	return NO_SPOT

func _paint_disk(center: Vector2i, radius: int, road: bool) -> void:
	for y in range(maxi(0, center.y - radius), mini(_map.height, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(_map.width, center.x + radius) + 1):
			if Vector2i(x, y).distance_squared_to(center) > radius * radius: continue
			if not config.naval or _map.tile(x, y) != 16: _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))
	if road and _inside(center) and config.roads:
		_map.roads[center.y * _map.width + center.x] = 5

func _clear_footprint(at: Vector2i, size: Vector2i) -> void:
	for y in range(at.y - 2, at.y + size.y + 3):
		for x in range(at.x - 2, at.x + size.x + 3):
			if x >= 0 and y >= 0 and x <= _map.width and y <= _map.height and (not config.naval or _map.tile(x, y) != 16): _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))

func _connect(from: Vector2i, to: Vector2i, width: int, road: bool) -> bool:
	# Naval roads stay on pure land; land-only recipes may raise causeways.
	# Return whether the route exists so a coastal object can try its other
	# land-side approaches without ever creating a hidden sea crossing.
	if not _route_grid.region.has_point(from) or not _route_grid.region.has_point(to): return false
	if config.naval and (not _walkable(from) or not _walkable(to)): return false
	var from_solid := _route_grid.is_point_solid(from)
	var to_solid := _route_grid.is_point_solid(to)
	_route_grid.set_point_solid(from, false)
	_route_grid.set_point_solid(to, false)
	var path := _route_grid.get_id_path(from, to)
	_route_grid.set_point_solid(from, from_solid)
	_route_grid.set_point_solid(to, to_solid)
	for point: Vector2i in path:
		var offset := point.y * _map.width + point.x
		if _network[offset] == 0:
			_network[offset] = 1
			_network_points.append(point)
		_paint_disk(point, width + 1, road)
		for y in range(maxi(0, point.y - width), mini(_map.height, point.y + width + 1)):
			for x in range(maxi(0, point.x - width), mini(_map.width, point.x + width + 1)):
				_corridor[y * _map.width + x] = 1
	return not path.is_empty()

func _connect_site(from: Vector2i, item: Dictionary, size: Vector2i) -> void:
	var approaches: Array[Dictionary] = []
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and x < size.x and y >= 0 and y < size.y: continue
			var point := Vector2i(item.x + x, item.y + y)
			if not _route_grid.region.has_point(point) or _occupied[point.y * _map.width + point.x] != 0: continue
			if config.naval and not _walkable(point): continue
			approaches.append({"point": point, "distance": point.distance_squared_to(from)})
	approaches.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
	# Preserve a real path to a land-side approach. A geometric nearest
	# corner can be water, or lie beyond a narrow neck blocked by the site.
	# Trying the other faces prevents ordinary coastlines from producing an
	# unreachable mine or a spur that disappears into the sea.
	for entry: Dictionary in approaches:
		var approach: Vector2i = entry.point
		var junction := from
		if config.naval and _region_at(from) != _region_at(approach): junction = _region_root(_region_at(approach))
		if junction == NO_SPOT: continue
		var distance := approach.distance_squared_to(junction)
		for point: Vector2i in _network_points:
			if config.naval and _region_at(point) != _region_at(approach): continue
			var offset := point.y * _map.width + point.x
			if _occupied[offset] != 0 or _reserved[offset] != 0: continue
			var candidate := approach.distance_squared_to(point)
			if candidate < distance:
				distance = candidate
				junction = point
		if _connect(junction, approach, 1, bool(config.roads)): return
	# Ports are an authoritative connected backbone even if a newly placed
	# object divided a thin island and its geometric center is on the far side.
	if config.naval:
		for entry: Dictionary in approaches:
			for port: Dictionary in _ports:
				if int(port.island) != _region_at(entry.point): continue
				if _connect(Vector2i(port.land[0], port.land[1]), entry.point, 1, bool(config.roads)): return

func _check_terrain() -> bool:
	var checked := {}
	for y in _map.height:
		for x in _map.width:
			var corners: Array[int] = [_map.tile(x, y), _map.tile(x + 1, y), _map.tile(x + 1, y + 1), _map.tile(x, y + 1)]
			var key := str(corners)
			if checked.has(key): continue
			checked[key] = true
			if _profile.terrain_tiles.plan(corners, 0).is_empty():
				error = "The installed tileset cannot render generated terrain transition %s. Try a single-biome map." % key
				return false
	report.terrain_combinations = checked.size()
	return true

func _check_access(protect_routes := false) -> bool:
	var objects := {}
	for item: Dictionary in _map.objects:
		var copy := item.duplicate()
		copy.uid = int(item.permanent_id) - 1
		copy.alive = true
		copy.visible = true
		copy.placed = true
		copy.level = 0
		copy.type = ("monster" if item.group == "np_heroes" else "hero") if item.group in ["heroes", "np_heroes"] else "object"
		objects[copy.uid] = copy
	var grid := ELAdventureGrid.new()
	if not grid.build(_map, objects):
		error = "Generated map navigation could not be built: " + grid.error
		return false
	# One eight-neighbour flood uses precisely the built grid's solid cells
	# and diagonal policy, avoiding thousands of individual A* approaches.
	var first := Vector2i(_starts[0].x, _starts[0].y)
	var reached := PackedByteArray()
	reached.resize(_map.width * _map.height)
	var previous := PackedInt32Array()
	if protect_routes:
		previous.resize(reached.size())
		previous.fill(-1)
	var queue: Array[Vector2i] = [first]
	reached[first.y * _map.width + first.x] = 1
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := at + Vector2i(dx, dy)
				if not grid.contains(next): continue
				var offset := next.y * _map.width + next.x
				if reached[offset] != 0 or grid.land.is_point_solid(next): continue
				if config.naval and not ELFirstNaval.connected(grid, at, next, true, true): continue
				reached[offset] = 1
				if protect_routes: previous[offset] = at.y * _map.width + at.x
				queue.append(next)
	var targets: Array[int] = _important.duplicate()
	for start: Dictionary in _starts:
		targets.append(int(start.castle_id))
		targets.append(int(start.hero_id))
	for id: int in targets:
		var item: Dictionary = objects[id]
		var size: Vector2i = grid.footprints.get(id, {}).get("size", Vector2i.ONE)
		var approach := -1
		var distance := INF
		for y in range(-1, size.y + 1):
			for x in range(-1, size.x + 1):
				if x >= 0 and x < size.x and y >= 0 and y < size.y: continue
				var point := Vector2i(item.x + x, item.y + y)
				if not grid.contains(point): continue
				var offset := point.y * _map.width + point.x
				if reached[offset] == 0 or (config.naval and _sea_cell(point)): continue
				var cost := first.distance_squared_to(point)
				if cost < distance:
					distance = cost
					approach = offset
		if approach < 0:
			error = "Generated map contains an unreachable %s (%d). Try a different seed." % [str(item.group), id]
			return false
		if protect_routes: _protect_route(approach, previous)
	if config.naval:
		for port: Dictionary in _ports:
			for key: String in ["land", "water"]:
				var point := Vector2i(port[key][0], port[key][1])
				var offset := point.y * _map.width + point.x
				if reached[offset] == 0:
					error = "A harbor is disconnected from the playable travel network."
					return false
				if protect_routes: _protect_route(offset, previous)
	for start: Dictionary in _starts: start.reachable_sites = _important.size()
	report.reachable = true
	report.reachable_cells = queue.size()
	return true

func _protect_route(offset: int, previous: PackedInt32Array) -> void:
	while offset >= 0:
		_corridor[offset] = 1
		var parent := previous[offset]
		if config.naval and parent >= 0:
			# A naval diagonal requires both orthogonal neighbors to stay clear.
			var x := offset % _map.width
			var y := offset / _map.width
			var parent_x := parent % _map.width
			var parent_y := parent / _map.width
			if x != parent_x and y != parent_y:
				_corridor[y * _map.width + parent_x] = 1
				_corridor[parent_y * _map.width + x] = 1
		offset = parent
