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
const LANDSCAPE_VERSION := 4
const WILDERNESS_VERSION := 5
const RELIEF_VERSION := 6
const PLACEMENT_VERSION := 7
const FRONTIERS_VERSION := 8
const GUARDED_PRIZES_VERSION := 9
const REGIONAL_LANDSCAPES_VERSION := 10
const GUARD_POSTS_VERSION := 11
const LIVING_WILDS_VERSION := 12
const STOCK_LAYOUT_VERSION := 13
const DailyCoverage := preload("first_daily_coverage.gd")
const Reachability := preload("first_map_reachability.gd")
const EncounterPlacement := preload("first_encounter_placement.gd")
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
const OPENING_DISTANCE := 12
const WILDERNESS_SPACING := 12
const FRONTIER_SITE_GAP := 8
const STARTER_ENCOUNTERS := ["Carnivorous Fingus", "Lesser Bee Hive", "Mech Worm", "River Halo", "Small Velos"]
const JOURNEY_ENCOUNTERS := ["OrcShaman", "Sea Halo"]
const WILDERNESS_ENCOUNTERS := ["Giant Fingus", "OrcGuard", "Small Bee Hive", "Mech Wyrm"]
const FRONTIER_ENCOUNTERS := ["Small Tick Hive", "Gibberling Gang", "Medium Bee Hive"]
const STARTER_LAIR := "Starter encounter"
const ROAD_SERVICES := ["SpringOfStrength", "SpringOfDexterity", "Teacher", "Magister", "MageWagon",
	"TraderWagon", "GnomeMerchant", "GnomeAlchemist"]
const CARDINAL := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
enum Landform { MEADOW, WOODS, RIDGE }
const LAND_GROUND := {
	"Green": [1, 0, 3], "Blue": [4, 7, 18], "Red": [11, 8, 10], "Black": [13, 15, 12],
}
const SCENERY_FAMILIES := {
	"Green": [["greenforest", "greentree", "greenbush"], ["greenstone", "greenrock"]],
	"Blue": [["bluepine", "blueel"], ["blueice", "bluestone", "blue_hill", "blue_rock"]],
	"Red": [["red_bush", "red_tree"], ["redhill", "red_stone", "red_rock", "red_voulcan"]],
	"Black": [["blacktree", "blackbush"], ["blackcrater", "blackhill", "blackstone", "rock_"]],
}

## Version 13 scenery mix: each prop's share (per mille) of the scenery
## cover on each ground across the 37 stock missions (docs/first_map_survey.md).
## Prop names follow the art sets, not the ground: the dark Chaot ground
## carries the grey cliffs and black trees, the tan Synthet ground the red
## rocks and bushes. Large cliffs make up half the cover outside the snow.
const STOCK_SCENERY := {
	"Green": {"GreenRock04": 101, "GreenForest04": 86, "GreenRock00": 83, "GreenForest05": 80, "GreenRock03": 71,
		"GreenForest06": 71, "GreenRock01": 52, "GreenStone_9": 44, "GreenForest02": 43, "GreenForest03": 38,
		"GreenBush07": 32, "GreenRock05": 29, "GreenStone_8": 26, "GreenRock02": 26, "GreenForest01": 22,
		"GreenStone_1": 15, "GreenTree01": 15, "GreenStone_2": 13, "GreenTree02": 12, "GreenBush08": 11,
		"GreenStone_10": 11, "GreenStone_5": 10, "GreenBush02": 8},
	"Blue": {"BluePine1_4": 405, "BluePine1_2": 116, "BluePine1_3": 115, "BluePine1_5": 113, "Blue_rock1_6": 62,
		"BluePine1_1": 33, "BlueIce_4": 33, "BlueIce_3": 16, "BlueIce_2": 16, "Blue_rock1_7": 8, "BlueIce_1": 8,
		"BlueIce_10": 8},
	"Red": {"rock_2": 186, "rock_1": 144, "rock_4": 135, "BlackTree_22": 53, "rock_3": 51, "BlackHill_1": 32,
		"BlackTree_23": 31, "rock_5": 29, "BlackStone_1": 24, "Blue_rock1_5": 24, "rock_6": 23, "rock_7": 21,
		"rock_8": 18, "Blue_rock1_6": 18, "BlackTree_21": 18, "BlackHill_2": 14, "Blue_rock1_1": 13,
		"BlackStone_2": 8, "BlueStone_1": 8, "BlackStone_4": 8, "Blue_rock1_7": 8},
	"Black": {"Red_rock_2": 130, "Red_Bush_1": 109, "Red_Stone_1": 85, "Red_rock_4": 82, "Red_rock_6": 66,
		"Red_Stone_2": 59, "Red_Bush_4": 58, "Red_rock_1": 52, "Red_rock_3": 48, "Red_rock_5": 44, "Red_Stone_4": 35,
		"Red_Bush_2": 28, "Red_Bush_3": 24, "Red_Stone_3": 20, "Red_rock_7": 18, "BluePine1_5": 10,
		"Red_Voulcan_5": 10, "Red_Voulcan_6": 9, "BluePine1_3": 8},
}

## Single-tile stock props for each ground, used to close the last gaps
## inside a mass so it does not hold sealed pockets.
const STOCK_FILLERS := {
	"Green": ["GreenForest03", "GreenBush07", "GreenBush08", "GreenStone_10", "GreenStone_5"],
	"Blue": ["BluePine1_1", "BlueIce_3", "BlueIce_2", "BlueIce_1", "BlueStone_5"],
	"Red": ["blackbush_6", "BlackTree_13", "BlackStone_5", "blackbush_5", "BlackStone_7"],
	"Black": ["Red_Stone_6", "Red_Voulcan_2", "Red_Voulcan_1", "Red_Tree_9", "Red_Tree_7"],
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
var _landscape := PackedByteArray()
var _canopy := PackedFloat32Array()
var _relief := PackedFloat32Array()
var _rock := PackedFloat32Array()
var _shore := PackedByteArray()
var _exploration_access := PackedInt32Array()
var _outlying_regions := {}
var _guard_queue: Array[Dictionary] = []
var _home_lairs: Array[Dictionary] = []
var _trunk_points: Array[Vector2i] = []
var _guard_safe := PackedByteArray()
var _scenery_paths := PackedByteArray()
# Memo of the footprint-independent part of _expedition_trail: the depth of
# each cell in the route tree and whether its walk to the root is clear.
# Invalidated whenever occupancy or the route tree changes.
var _trail_depth := PackedInt32Array()
var _trail_clear := PackedByteArray()
var _trail_stale := true
# Harbor routes by destination cell; cleared whenever the route grid changes.
var _port_routes := {}
# Where the last failed access check found an unreachable site.
var _unreached := Vector2i(-1, -1)
## Version 13 woods: a diagonal step between two blocking objects is no way in.
var _strict_corners := false
var _reward_guards := {}
var _basins: Array[Transform2D] = []
var _frontier_supplies: Array[Dictionary] = []
var _site_clearance := PackedByteArray()
var _prize_scenery := {}
var _gated_prizes := {}
var _approach_clearings := PackedByteArray()
var _uplands := PackedFloat32Array()
var _summits: Array[Vector2i] = []

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
	if result.version < VERSION or result.version > STOCK_LAYOUT_VERSION or result.size not in SIZES or result.players < 2 or result.players > 4 or result.scenery < 0 or result.scenery > 2 or result.castle_health not in [20, 30, 60]: return {}
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
	var data := {"id": map.id, "width": map.width, "height": map.height,
		"terrain": map.terrain.hex_encode(), "roads": map.roads.hex_encode(),
		"creeks": map.creeks.hex_encode(), "colorless": map.colorless.hex_encode(),
		"players": map.players, "objects": map.objects, "mobs": map.mobs,
		"document": map.document}
	if map.has_meta("wilderness_detail"):
		var field: PackedByteArray = map.get_meta("wilderness_detail")
		data["wilderness_detail"] = field.hex_encode()
	if not map.relief.is_empty(): data["relief"] = map.relief.hex_encode()
	return JSON.stringify(data, "", true).sha256_text()

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
	_outlying_regions.clear()
	_guard_queue.clear()
	_home_lairs.clear()
	_trunk_points.clear()
	_guard_safe.clear()
	_scenery_paths.clear()
	_reward_guards.clear()
	_basins.clear()
	_frontier_supplies.clear()
	_site_clearance.clear()
	_prize_scenery.clear()
	_gated_prizes.clear()
	_approach_clearings.clear()
	_map.terrain.resize((_map.width + 1) * (_map.height + 1))
	_map.roads.resize(_map.width * _map.height)
	_map.creeks.resize(_map.roads.size())
	_map.colorless.resize(_map.roads.size())
	_occupied.resize(_map.roads.size())
	_occupied.fill(0)
	_trail_stale = true
	_port_routes.clear()
	_reserved.resize(_map.roads.size())
	_reserved.fill(0)
	_corridor.resize(_map.roads.size())
	_corridor.fill(0)
	if config.version >= PLACEMENT_VERSION: _guard_safe.resize(_map.roads.size())
	if config.version >= FRONTIERS_VERSION: _scenery_paths.resize(_map.roads.size())
	if config.version >= GUARDED_PRIZES_VERSION:
		_site_clearance.resize(_map.roads.size())
		_site_clearance.fill(255)
		_approach_clearings.resize(_map.roads.size())
		if config.scenery > 0: _read_prize_scenery()
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
	if config.version >= FRONTIERS_VERSION and not config.naval: _build_basins()
	if config.version >= LANDSCAPE_VERSION:
		_build_landscape()
		_add_outlying_islands()
	_make_terrain()
	if config.naval and not _prepare_naval_terrain(): return null
	if config.version >= RELIEF_VERSION: _shore = _shore_distance()
	if config.version >= REGIONAL_LANDSCAPES_VERSION: _build_uplands()
	if config.version >= LANDSCAPE_VERSION: _weight_landscape_routes()
	if not _make_players(): return null
	if config.naval and not _make_ports(): return null
	_make_routes()
	if config.version >= PLACEMENT_VERSION: _trunk_points.assign(_network_points)
	if not _make_homelands(): return null
	if not _make_frontiers(): return null
	if config.naval: _populate_islands()
	var cliff_ids := Vector2i.ZERO
	if config.version >= LANDSCAPE_VERSION:
		if not _check_access(true): return null
		if config.version >= REGIONAL_LANDSCAPES_VERSION and config.scenery > 0:
			# Claim room for the mountains before optional sites and encounters
			# use up their slopes. The opening sites already have clear paths.
			cliff_ids.x = _next_id
			_place_regional_cliffs(_scenery_land(), _scenery_catalog())
			cliff_ids.y = _next_id
			if cliff_ids.x != cliff_ids.y and not _check_access(true): return null
		if config.version >= PLACEMENT_VERSION:
			_make_frontier_forts()
			_make_frontier_prizes()
		_make_exploration_sites()
	if config.version >= WILDERNESS_VERSION and config.guards != "none":
		if config.version >= GUARD_POSTS_VERSION: _prepare_starter_lairs()
		else: _make_encounters()
		if not _check_access(true): return null
	if config.version >= FRONTIERS_VERSION:
		_place_frontier_supplies()
	var first_decoration := _next_id
	if config.scenery > 0:
		if config.version == VERSION:
			_make_legacy_scenery()
		else:
			# Keep a route to every strategic target before adding blockers.
			if config.version == SCENERY_VERSION and not _check_access(true): return null
			_make_scenery()
	if config.version >= GUARDED_PRIZES_VERSION and not _reconnect_landscape(first_decoration, cliff_ids): return null
	if config.version >= STOCK_LAYOUT_VERSION and config.scenery > 0 and not _open_corner_gaps(first_decoration, cliff_ids): return null
	if config.version >= STOCK_LAYOUT_VERSION and config.scenery > 0:
		# The woods closed over the old opening routes. Find them again on
		# the finished ground so guards still leave every opening site free.
		_guard_safe.fill(0)
		var opened := false
		_strict_corners = true
		for attempt in 8:
			_unreached = Vector2i(-1, -1)
			if _check_access(true):
				opened = true
				break
			if _unreached.x < 0: return null
			# Clear the generated woods around a sealed-off site and join
			# the freed ground again.
			var site := _unreached
			_map.objects = _map.objects.filter(func(item: Dictionary) -> bool:
				return item.group != "terrain_objects" or int(item.permanent_id) < first_decoration or Vector2i(item.x, item.y).distance_squared_to(site) > (6 + attempt * 3) * (6 + attempt * 3))
			if not _reconnect_landscape(first_decoration, cliff_ids): return null
		# A gap between two fixed objects stays; the game's diagonal step
		# still crosses it.
		_strict_corners = false
		if not opened and not _check_access(true): return null
	if not _check_terrain(): return null
	if config.version >= GUARD_POSTS_VERSION and config.guards != "none":
		if not _post_field_guards(): return null
	if not _check_access(false, config.version >= RELIEF_VERSION): return null
	# Stock maps are flat; their hills are props and rock tiles. Version 13
	# keeps the ground level instead of sculpting mesas and shelves.
	if config.version >= WILDERNESS_VERSION and config.version < STOCK_LAYOUT_VERSION: _paint_wilderness_detail()
	if config.version >= RELIEF_VERSION and config.version < STOCK_LAYOUT_VERSION: _shape_relief()
	_map.document.children.append(_node("support", {"last_permanent_id": str(_next_id)}))
	report.starts = _starts.duplicate(true)
	if config.version >= PLACEMENT_VERSION: report.reward_guards = _reward_guards.duplicate()
	if config.version >= GUARDED_PRIZES_VERSION: report.gated_prizes = _gated_prizes.duplicate()
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
	if config.version >= LANDSCAPE_VERSION: data["AdditionalBuildings"] = _profile.table("AdditionalBuildings")
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

func _build_landscape() -> void:
	var stride := _map.width + 1
	_landscape.resize(stride * (_map.height + 1))
	if config.version >= WILDERNESS_VERSION:
		_canopy.resize(_landscape.size())
		_relief.resize(_landscape.size())
		_rock.resize(_landscape.size())
	# Follow a contour of a broad, bent field for ridges. Moisture varies at
	# a different scale so woodland trails off into meadows between them.
	for y in range(_map.height + 1):
		for x in range(stride):
			var bend := (_noise(x, y, 32.0, 1621) - 0.5) * 18.0
			var contour := absf(_noise(x + bend, y - bend, 29.0, 2633) - 0.52)
			var relief := _noise(x, y, 39.0, 721)
			var moisture := 0.72 * _noise(x - bend, y, 24.0, 4309) + 0.28 * _noise(x, y, 9.0, 5311)
			var form := Landform.MEADOW
			if contour < 0.085 and relief > 0.43: form = Landform.RIDGE
			elif moisture > 0.48: form = Landform.WOODS
			var index := y * stride + x
			if config.version >= WILDERNESS_VERSION:
				var rock := (1.0 - smoothstep(0.015, 0.16, contour)) * smoothstep(0.32, 0.66, relief)
				var undergrowth := 0.78 * moisture + 0.22 * _noise(x + bend, y - bend, 5.0, 2365)
				var cover := smoothstep(0.37, 0.73, undergrowth) * (1.0 - rock * 0.65)
				if config.version >= REGIONAL_LANDSCAPES_VERSION:
					cover = clampf(0.69 * cover + 0.57 * _noise(x, y, 17.0, 7957), 0.0, 1.0)
				_canopy[index] = cover
				_relief[index] = clampf(0.69 * relief + 0.31 * rock, 0.0, 1.0)
				_rock[index] = rock
				form = Landform.RIDGE if rock > 0.42 else (Landform.WOODS if _canopy[index] > 0.44 else Landform.MEADOW)
			_landscape[index] = form

func _paint_wilderness_detail() -> void:
	var size := Vector2i(_map.width + 1, _map.height + 1)
	var field := PackedByteArray()
	field.resize(size.x * size.y * 3)
	for y in size.y:
		for x in size.x:
			var index := y * size.x + x
			var cover := _canopy[index]
			var height := _relief[index]
			var ground := int(_map.tile(x, y) not in ELTileSet.WATER_KINDS)
			field[3 * index] = roundi(255.0 * cover)
			field[3 * index + 1] = roundi(255.0 * height)
			field[3 * index + 2] = ground * 255
	_map.set_meta("wilderness_detail", field)

func _shore_distance() -> PackedByteArray:
	var stride := _map.width + 1
	var distance := PackedByteArray()
	distance.resize(_map.terrain.size())
	distance.fill(255)
	var queue := PackedInt32Array()
	for index in distance.size():
		if int(_map.terrain[index]) not in ELTileSet.WATER_KINDS: continue
		distance[index] = 0
		queue.append(index)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		if distance[index] >= 12: continue
		var at := Vector2i(index % stride, index / stride)
		for delta: Vector2i in CARDINAL:
			var next := at + delta
			if next.x < 0 or next.x > _map.width or next.y < 0 or next.y > _map.height: continue
			var neighbor := next.y * stride + next.x
			if distance[neighbor] != 255: continue
			distance[neighbor] = distance[index] + 1
			queue.append(neighbor)
	return distance

func _build_uplands() -> void:
	var stride := _map.width + 1
	_uplands.resize(_map.terrain.size())
	_uplands.fill(0.0)
	_summits.clear()
	var candidates: Array[Dictionary] = []
	var dry := 0
	var hub := Vector2i(_map.width, _map.height) / 2
	for y in range(3, _map.height - 2):
		for x in range(3, _map.width - 2):
			var index := y * stride + x
			if int(_map.terrain[index]) in ELTileSet.WATER_KINDS: continue
			dry += 1
			if _shore[index] < 5 or _hash(x, y, 7819) > 0.16: continue
			var point := Vector2i(x, y)
			if point.distance_squared_to(_anchors[_owner(point)]) < 9 * 9: continue
			if not config.naval and point.distance_squared_to(hub) < 9 * 9: continue
			var edge := mini(mini(x, _map.width - x), mini(y, _map.height - y))
			var prominence := _relief[index] * 0.8 + _rock[index] * 0.25
			prominence += 0.62 * smoothstep(3.0, 17.0, edge) + mini(_shore[index], 12) * 0.035 + _hash(x, y, 7823) * 0.37
			candidates.append({"point": point, "prominence": prominence})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.prominence) > float(b.prominence))
	var ranges := maxi(2, roundi(dry / 1100.0))
	var separation := clampi(_map.width / 5, 17, 24)
	for candidate: Dictionary in candidates:
		var point: Vector2i = candidate.point
		if _summits.any(func(other: Vector2i) -> bool: return point.distance_squared_to(other) < separation * separation): continue
		_summits.append(point)
		_raise_ridge(point)
		if _summits.size() >= ranges: break
	for y in _map.height + 1:
		for x in stride:
			var index := y * stride + x
			var height := _uplands[index]
			_rock[index] = maxf(_rock[index] * 0.55, smoothstep(0.22, 0.88, height))
			_canopy[index] *= 1.0 - 0.78 * smoothstep(0.24, 0.81, height)
			var edge := 0.24 + 0.17 * (_noise(x, y, 6.0, 7937) - 0.5)
			if height < edge or int(_map.terrain[index]) in ELTileSet.WATER_KINDS: continue
			_landscape[index] = Landform.RIDGE
			_map.terrain[index] = _ground(Vector2i(x, y), true)

func _raise_ridge(center: Vector2i) -> void:
	var heading := TAU * _hash(center.x, center.y, 7877)
	var length := lerpf(11.0, 18.0, _hash(center.x, center.y, 7883))
	var width := lerpf(7.5, 11.0, _hash(center.x, center.y, 7901))
	var amplitude := lerpf(0.84, 1.0, _hash(center.x, center.y, 7907))
	var radius := ceili(length + 3.0)
	for y in range(maxi(0, center.y - radius), mini(_map.height, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(_map.width, center.x + radius) + 1):
			var local := Vector2(Vector2i(x, y) - center).rotated(-heading)
			var along := local.x / length
			var across := (local.y - 2.2 * sin(along * PI)) / width
			var contour := Vector2(along, across).length()
			var crest := 1.0 - smoothstep(0.28, 1.0, contour)
			var saddle := 0.84 + 0.20 * _noise(x, y, 5.0, 7927)
			var index := y * (_map.width + 1) + x
			_uplands[index] = maxf(_uplands[index], amplitude * crest * saddle)

func _shape_relief() -> void:
	var shore := _shore_distance()
	var stride := _map.width + 1
	var sculpted := PackedFloat32Array()
	sculpted.resize(shore.size())
	for index in shore.size():
		# Lower the intertidal shelf and valleys. The ridge field rises out
		# of the same ground that controls the rock and woodland masks.
		var inland := smoothstep(2.0, 9.0, float(shore[index]))
		var mass := pow(clampf((_relief[index] - 0.20) / 0.75, 0.0, 1.0), 1.45)
		if config.version >= REGIONAL_LANDSCAPES_VERSION:
			var bank := smoothstep(0.0, 7.0, float(shore[index]))
			sculpted[index] = bank * (0.32 + 4.1 * mass + 9.4 * _uplands[index])
		else:
			sculpted[index] = inland * (0.40 + 7.4 * mass + 2.6 * pow(_rock[index], 2.0))
	var original := sculpted.duplicate()
	var art := ELAdventureArt.new(_map)
	for item: Dictionary in _map.objects:
		var cliff: bool = config.version >= REGIONAL_LANDSCAPES_VERSION and item.group == "terrain_objects"
		if not cliff and item.group not in ["buildings", "factories", "laboratories", "mines", "additional_buildings", "mana_nodes"]: continue
		var definition := art.resolve(item)
		var shape := ELAdventureGrid.footprint(definition.get("row", {}), int(item.rotation))
		if cliff:
			if maxi(shape.size.x, shape.size.y) < 5: continue
		elif shape.size == Vector2i.ONE and item.group != "buildings": continue
		var origin := Vector2i(item.x, item.y)
		var end: Vector2i = origin + shape.size
		var height := INF
		for y in range(origin.y, end.y + 1):
			for x in range(origin.x, end.x + 1): height = minf(height, original[y * stride + x])
		# Seat buildings and the broad native cliffs on a shelf. The
		# neighboring slopes blend out from the shelf to the original grade.
		for y in range(maxi(0, origin.y - 3), mini(_map.height, end.y + 3) + 1):
			for x in range(maxi(0, origin.x - 3), mini(_map.width, end.x + 3) + 1):
				var distance := maxi(maxi(origin.x - x, x - end.x), maxi(origin.y - y, y - end.y))
				var index := y * stride + x
				var pad := lerpf(minf(height, original[index]), original[index], smoothstep(0.0, 3.5, distance))
				sculpted[index] = minf(pad, sculpted[index])
	_map.relief.resize(sculpted.size())
	for index in sculpted.size(): _map.relief[index] = clampi(roundi(sculpted[index] / ELAdventureMap.RELIEF_UNIT), 0, 255)

func _landform(point: Vector2i) -> int:
	return _landscape[point.y * (_map.width + 1) + point.x]

func _ground(point: Vector2i, varied := false) -> int:
	var color := str(config.biome)
	if color == "mixed":
		var sample := point
		if config.version >= LIVING_WILDS_VERSION:
			sample = _climate_sample(point)
		elif config.version >= REGIONAL_LANDSCAPES_VERSION:
			# Give neighboring climates broad tongues and smaller breaks
			# without changing which player owns the corner of the map.
			var drift := Vector2(_noise(point.x, point.y, 26.0, 2081), _noise(point.x, point.y, 26.0, 2347))
			var edge := Vector2(_noise(point.x, point.y, 9.0, 2087), _noise(point.x, point.y, 9.0, 2351))
			sample += Vector2i((drift - Vector2.ONE * 0.5) * 22.0 + (edge - Vector2.ONE * 0.5) * 8.0)
		elif config.version >= LANDSCAPE_VERSION and varied:
			sample += Vector2i((_noise(point.x, point.y, 23.0, 2081) - 0.5) * 12.0, (_noise(point.x, point.y, 23.0, 2347) - 0.5) * 12.0)
		color = _colors[_owner(sample)]
	var choices: Array = _palette[color]
	if config.version >= LANDSCAPE_VERSION:
		var form := _landform(point)
		var native: int = LAND_GROUND[color][form]
		if config.version >= WILDERNESS_VERSION and color == "Green" and 2 in choices:
			var stone := _rock[point.y * (_map.width + 1) + point.x]
			# Moss and gravel fringe the exposed bedrock. A narrow shoulder
			# reads as one ridge with a ragged edge instead of a tiled strip.
			if stone > 0.29 and stone < 0.67: native = 2
			if config.version >= RELIEF_VERSION and stone > 0.29:
				var fracture := _noise(point.x, point.y, 4.0, 817)
				native = 3 if stone > 0.60 + fracture * 0.27 and 3 in choices else 2
		return native if native in choices else int(choices[mini(form, choices.size() - 1)])
	if varied and choices.size() > 1 and _noise(point.x, point.y, 8.0, 97) > 0.58: return int(choices[mini(1, choices.size() - 1)])
	return int(choices[0])

## Version 12 climate lookup. Equal-distance borders between castles are
## straight lines, so the sample point is warped at three scales. The warp
## fades out around each castle, which keeps the homeland's own climate. A
## reward island far from every castle takes the single climate of its
## center instead of a slice of each neighbor.
func _climate_sample(point: Vector2i) -> Vector2i:
	for island: Dictionary in _reward_centers:
		var center: Vector2 = island.point
		if Vector2(point).distance_to(center) < float(island.radius) * 1.9:
			return Vector2i(center)
	var nearest := 1.0e30
	for anchor: Vector2i in _anchors: nearest = minf(nearest, Vector2(point).distance_to(Vector2(anchor)))
	var freedom := smoothstep(_home_radius * 0.45, _home_radius * 0.95, nearest)
	var warp := Vector2(_noise(point.x, point.y, 37.0, 2081) - 0.5, _noise(point.x, point.y, 37.0, 2347) - 0.5) * 46.0
	warp += Vector2(_noise(point.x, point.y, 13.0, 2087) - 0.5, _noise(point.x, point.y, 13.0, 2351) - 0.5) * 18.0
	warp += Vector2(_noise(point.x, point.y, 4.0, 2089) - 0.5, _noise(point.x, point.y, 4.0, 2357) - 0.5) * 5.0
	return point + Vector2i((warp * freedom).round())

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
		if config.version >= LANDSCAPE_VERSION:
			outline += (_noise(point.x, point.y, 10.0, 491) - 0.5) * 0.9
		if config.version >= WILDERNESS_VERSION:
			var headland := TAU * _hash(index, _map.width, 7253)
			var room := clampf((_map.width - 64) / 64.0, 0.0, 1.0)
			outline += room * (0.60 * cos(angle * 2.0 + headland) + 0.46 * sin(angle * 4.0 + headland))
			outline += room * 0.40 * (_noise(point.x, point.y, 6.0, 7577) - 0.5)
		var limit := float(_map.width)
		for other in _anchors.size():
			if other != index: limit = minf(limit, _anchors[index].distance_to(_anchors[other]) * 0.445)
		var shore := clampf(_home_radius * (1.0 + amplitude * outline), maxf(12.8, _home_radius * 0.82), limit)
		if offset.length() < shore: return true
	return false

func _build_basins() -> void:
	var shore := floorf(_hash(3, 8, 614) * 4.0) * PI * 0.5
	var offset := (_hash(3, 8, 881) - 0.5) * 0.26
	var width: float = {"low": 0.76, "normal": 1.0, "high": 1.23}[config.water]
	match str(config.layout):
		"frontier":
			# A long bay on one edge and a few inland pools leave most of
			# the border as open countryside. The seed chooses the coast.
			_add_basin(Vector2(offset, -0.50).rotated(shore), Vector2(0.30, 0.19) * width, shore + offset)
			_add_basin(Vector2(-0.21, 0.10 + offset).rotated(shore), Vector2(0.13, 0.083) * width, shore + _shape_phase)
			_add_basin(Vector2(0.28, 0.23 - offset).rotated(shore), Vector2(0.095, 0.066) * width, _shape_phase)
			if _hash(3, 8, 879) > 0.50:
				_add_basin(Vector2(-0.14, 0.49).rotated(shore), Vector2(0.22, 0.11) * width, shore)
		"lakes":
			var count := 4 + floori(_hash(3, 8, 945) * 3.0)
			var main_lake := Vector2.from_angle(_shape_phase + 1.3) * lerpf(0.03, 0.13, _hash(3, 8, 788))
			_add_basin(main_lake, Vector2(0.155, 0.105) * width, _shape_phase)
			for index in count:
				var angle := TAU * index / count + _shape_phase
				var reach := lerpf(0.19, 0.36, _hash(index, 8, 462))
				var radius := lerpf(0.095, 0.153, _hash(index, 8, 654))
				_add_basin(Vector2.from_angle(angle) * reach, Vector2(radius * 1.3, radius * 0.82) * width, angle + offset)
		"crossroads":
			for index in 4:
				var angle := shore + PI * 0.5 * index
				var reach := lerpf(0.28, 0.39, _hash(index, 8, 421))
				var radius := lerpf(0.10, 0.15, _hash(index, 8, 238))
				_add_basin(Vector2.from_angle(angle + offset) * reach, Vector2(radius, radius * 0.64) * width, angle)

func _add_basin(offset: Vector2, extent: Vector2, angle: float) -> void:
	var basin := Transform2D(angle, extent, 0.0, Vector2(0.5, 0.5) + offset)
	_basins.append(basin.affine_inverse())

func _basin_water(point: Vector2i) -> bool:
	var n := float(_map.width)
	var sample := Vector2(point) / n
	if config.layout == "crossroads" and sample.distance_squared_to(Vector2(0.5, 0.5)) < 0.10 * 0.10: return false
	var roughness := 0.11 if config.coast == "smooth" else 0.33
	var edge := 1.0 + (_noise(point.x, point.y, n * 0.12, 671) - 0.5) * roughness
	for basin: Transform2D in _basins:
		if (basin * sample).length_squared() < edge: return not _home_land(Vector2(point))
	return false

func _water_field(point: Vector2i) -> bool:
	if not _basins.is_empty(): return _basin_water(point)
	var n := float(_map.width)
	var center := Vector2(n, n) * 0.5
	var sample := Vector2(point)
	if config.version >= LANDSCAPE_VERSION:
		var amplitude := n * (0.075 if config.coast == "rugged" else 0.040)
		sample += Vector2(_noise(point.x, point.y, n * 0.28, 2801) - 0.5, _noise(point.x, point.y, n * 0.28, 3889) - 0.5) * amplitude
	var relative := sample - center
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
			if config.version >= LANDSCAPE_VERSION: wet = _river_channels(sample / n, amount, jitter)
			else:
				var river := relative.x - sin(sample.y / n * TAU + _shape_phase) * n * 0.045
				var braid := relative.y - sin(sample.x / n * TAU * 0.8 + _shape_phase) * n * 0.035
				var mouth := sample.y / n > 0.68 and absf(relative.x) < n * (0.14 + (sample.y / n - 0.68) * 0.6)
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
		if config.version >= WILDERNESS_VERSION and _map.width >= 96:
			var turn := TAU * _hash(roundi(island.point.x), roundi(island.point.y), 2359)
			shore += float(island.radius) * (0.15 * cos(offset.angle() * 2.0 + turn) + 0.14 * sin(offset.angle() * 3.0 - turn))
		if offset.length() < shore: wet = false
		elif config.layout == "archipelago" and offset.length() < shore + 3.0: wet = true
	# An ocean rim gives every waterway an off-shore route. Homelands and
	# harbors sit clear of it, so a coastal voyage never leaves map bounds.
	if config.naval and (point.x <= 1 or point.y <= 1 or point.x >= _map.width - 1 or point.y >= _map.height - 1): wet = true
	return wet

func _river_channels(point: Vector2, amount: float, jitter: float) -> bool:
	var trunk := 0.50 + 0.081 * sin(point.y * TAU + _shape_phase) + 0.029 * sin(point.y * TAU * 2.0 + _shape_phase * 0.7)
	var branch := 0.49 + 0.072 * sin(point.x * TAU * 0.85 - _shape_phase) + 0.028 * sin(point.x * TAU * 1.75 + _shape_phase * 0.4)
	var bank := 0.025 + amount * 0.26 + jitter * 0.35
	var fork := maxf(0.0, point.y - 0.63)
	var mouth := trunk + fork * (0.68 + 0.24 * sin(point.y * TAU + _shape_phase))
	return absf(point.x - trunk) < bank + fork * 0.048 or absf(point.y - branch) < bank or (fork > 0.0 and absf(point.x - mouth) < bank * 0.85)

func _add_outlying_islands() -> void:
	if not config.naval or _map.width < 96 or config.layout not in ["archipelago", "inland_sea", "peninsulas"]: return
	var n := float(_map.width)
	var center := Vector2(n, n) * 0.5
	var radius := n * 0.066
	var added: Array[Vector2] = []
	for step in 24:
		var angle := _shape_phase + step * TAU / 24.0
		var distance := n * lerpf(0.32, 0.45, _hash(step, _map.width, 1873))
		var point := center + Vector2.from_angle(angle) * distance
		var margin := radius + 6.0
		if not Rect2(Vector2.ONE * margin, Vector2.ONE * (n - 2 * margin)).has_point(point): continue
		if added.any(func(other: Vector2) -> bool: return point.distance_to(other) < n * 0.28): continue
		var water := _water_field(Vector2i(point))
		for direction in 16:
			if not water: break
			water = _water_field(Vector2i(point + Vector2.from_angle(direction * TAU / 16.0) * margin))
		if not water: continue
		_reward_centers.append({"point": point, "radius": radius, "outlying": true})
		added.append(point)
		if added.size() == 2: break

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
				var cut := 7.0
				# Version 12 channels follow the lie of the land instead of a ruler.
				if config.version >= LIVING_WILDS_VERSION: cut *= 0.45 + 1.1 * _noise(x, y, 7.0, 6151)
				channels.set_point_weight_scale(point, 1.0 if _sea_cell(point) else cut)
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
			if route.is_empty() and config.version >= LIVING_WILDS_VERSION:
				# A lake sealed inside a homeland becomes meadow instead of
				# failing the whole world.
				for cell: Vector2i in sea.regions[index].cells:
					for dy in 2:
						for dx in 2:
							var corner := cell + Vector2i(dx, dy)
							var at := corner.y * (_map.width + 1) + corner.x
							if _map.terrain[at] == 16: _map.terrain[at] = _ground(corner, true)
				continue
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
	_port_routes.clear()
	for anchor: Vector2i in _anchors:
		if _land_labels[anchor.y * _map.width + anchor.x] < 0:
			error = "A homeland was lost while shaping the coast."
			return false
	for island: Dictionary in _reward_centers:
		if not island.get("outlying", false): continue
		var region := _region_at(Vector2i(island.point))
		if region >= 0: _outlying_regions[region] = true
	return true

func _weight_landscape_routes() -> void:
	# Roads gravitate to clear valley floors and only use causeways when
	# necessary. The weights shape placement, not the cost of hero movement.
	var wet_weight := 14.0 if not _basins.is_empty() else 5.0
	for y in range(1, _map.height - 1):
		for x in range(1, _map.width - 1):
			var point := Vector2i(x, y)
			var weight: float = [1.0, 1.22, 2.2][_landform(point)] if _walkable(point) else wet_weight
			if config.version >= REGIONAL_LANDSCAPES_VERSION:
				weight += 2.6 * _uplands[y * (_map.width + 1) + x]
			var wander := 0.21 * _noise(x, y, 15.0, 1091)
			# Stock routes run about 1.4 times the straight distance.
			if config.version >= STOCK_LAYOUT_VERSION: wander = 5.0 * pow(_noise(x, y, 11.0, 1093), 2.0) + 1.6 * _noise(x, y, 4.0, 1097)
			_route_grid.set_point_weight_scale(point, weight + wander)

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
	_publish_harbors()
	return true

func _publish_harbors() -> void:
	var payload := {"version": 1, "water_type": 16, "ports": _ports.duplicate(true)}
	_map.set_meta("first_naval", payload)
	var node := ELXml.child(_map.document, "first_naval")
	if node.is_empty():
		_map.document.children.append(_node("first_naval", {"data": JSON.stringify(payload, "", true)}))
	else:
		node.attrs.data = JSON.stringify(payload, "", true)

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
		if homes.has(region) or placed_regions.has(region) or _outlying_regions.has(region): continue
		placed_regions[region] = true
		var center: Vector2 = _land_regions[region].center
		var source := _region_root(region)
		if source == NO_SPOT: continue
		var mines := 2 if config.resources == "scarce" else 3
		if config.version >= GUARDED_PRIZES_VERSION: mines = 2 if config.resources == "rich" else 1
		for index in mines:
			var kind: String = ["Stone", "Diamond", "Lotus"][index]
			var row: Dictionary = _catalog.mines[kind]
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var pos := _find_spot(Vector2i(center) + Vector2i(index * 3 - 3, 1), size, 12, -1, true, true,
				false, -1, _site_gap())
			if pos == NO_SPOT or _region_at(pos) != region: continue
			var item := _place("mines", str(row.Name), pos, row, 0, _colors[index % _colors.size()], [_node("level", {}, "0")])
			_clear_footprint(pos, size)
			_connect_site(source, item, size, config.version < PLACEMENT_VERSION, config.version < PLACEMENT_VERSION)
			_important.append(int(item.permanent_id) - 1)
			if config.guards != "none": _add_guard(pos - Vector2i(2, 1), index % _colors.size(), 4 + index, item, size)
		if config.version < GUARDED_PRIZES_VERSION:
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
			if source != NO_SPOT: _connect(source, land, 1, true, int(port.owner) > 0)
		for index in _starts.size():
			var first := Vector2i(_starts[index].x, _starts[index].y)
			var next: Dictionary = _starts[(index + 1) % _starts.size()]
			var second := Vector2i(next.x, next.y)
			if _region_at(first) == _region_at(second): _connect(first, second, 1, true, true)
		return
	var hub := Vector2i(_map.width / 2, _map.height / 2)
	_paint_disk(hub, 7, false)
	for index in _starts.size():
		var start := Vector2i(_starts[index].x, _starts[index].y)
		_connect(start, hub, 2, true, true)
		if config.layout not in ["crossroads", "archipelago", "inland_sea", "peninsulas"]:
			var next: Dictionary = _starts[(index + 1) % _starts.size()]
			_connect(start, Vector2i(next.x, next.y), 2, true, true)

func _make_frontier_forts() -> void:
	# Empty forts belong on the marches. Leave an open lane beside their
	# footprint so the player can decide whether to stop and garrison them.
	var rows := {}
	for color: String in ["Red", "Black"]:
		var row := ELForts.definition(_profile, {"fort_color": color}, 0)
		if _model(row): rows[color] = row
	if rows.is_empty(): return
	var forts: Array[Vector2i] = []
	var center := Vector2(_map.width, _map.height) * 0.5
	for index in _starts.size():
		var origin := Vector2i(_starts[index].x, _starts[index].y)
		var region := _region_at(origin)
		var desired := Vector2i(Vector2(origin).lerp(center, 0.63))
		var color: String = rows.keys()[index % rows.size()]
		var row: Dictionary = rows[color]
		var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
		var candidates: Array[Vector2i] = []
		for point: Vector2i in _trunk_points:
			if config.naval and _region_at(point) != region: continue
			if _starts.any(func(start: Dictionary) -> bool:
				return point.distance_squared_to(Vector2i(start.x, start.y)) < (81 if config.naval else 169)
			): continue
			if forts.any(func(at: Vector2i) -> bool: return at.distance_squared_to(point) < 15 * 15): continue
			candidates.append(point)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.distance_squared_to(desired) < b.distance_squared_to(desired)
		)
		for point: Vector2i in candidates:
			var pos := _find_spot(point - size / 2, size, 4, -1, true, true, true, region)
			if pos == NO_SPOT: continue
			var approach := _expedition_trail(Rect2i(pos, size))
			var item := _place("forts", "Fort", pos, row, 0, color)
			_important.append(int(item.permanent_id) - 1)
			_protect_route(approach, _exploration_access, true)
			forts.append(point)
			break

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
		if config.version >= RELIEF_VERSION and (_map.width >= 96 or config.version >= PLACEMENT_VERSION):
			var bias := signf(_hash(index, _map.width, 1927) - 0.5)
			var trade_bank := side * bias
			for entry: Dictionary in entries:
				var habitat := str(entry.group)
				if habitat == "mines":
					if entry.name == _catalog.mines.Root.Name: habitat = "woods"
					elif entry.name == _catalog.mines.Lotus.Name: habitat = "bank"
					else: habitat = "ridge"
				var place := origin + inward * float(entry.forward) + side * float(entry.side)
				if habitat in ["factories", "laboratories"]:
					# Shops follow the same lane into town. Extraction sites
					# spread into the places that produce their resources.
					place = origin + inward * float(entry.forward) * 0.68 + trade_bank * (5.0 + (_hash(index, int(entry.forward), 893) - 0.5) * 3.0)
				entry.desired = _habitat_anchor(Vector2i(place.round()), habitat)
		for entry: Dictionary in entries:
			var desired := Vector2i((origin + inward * float(entry.forward) + side * float(entry.side)).round())
			desired = entry.get("desired", desired)
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
			_connect_site(Vector2i(start.x, start.y), item, size, config.version < PLACEMENT_VERSION or entry.group != "mines")
		for number in (1 if config.version >= GUARDED_PRIZES_VERSION else 3):
			var desired := Vector2i((origin + inward * (4 + number * 4) - side * 3).round())
			var amount := 15 if config.resources == "normal" else (7 if config.resources == "scarce" else 30)
			_add_pickup(desired, index, amount * (2 if config.version >= GUARDED_PRIZES_VERSION else 1))
	return true

func _habitat_anchor(desired: Vector2i, habitat: String) -> Vector2i:
	var best := desired
	var score := -INF
	for y in range(desired.y - 4, desired.y + 5):
		for x in range(desired.x - 4, desired.x + 5):
			var at := Vector2i(x, y)
			if not _walkable(at): continue
			var index := y * (_map.width + 1) + x
			var habitat_score := 1.0 - _rock[index]
			match habitat:
				"woods": habitat_score = _canopy[index]
				"bank": habitat_score = 1.0 - smoothstep(2.0, 11.0, float(_shore[index]))
				"ridge": habitat_score = _rock[index]
			var priority := habitat_score * 11.0 - desired.distance_squared_to(at) * 0.38
			if priority <= score: continue
			score = priority
			best = at
	return best

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
			var recruit_rank := -1
			if config.version >= WILDERNESS_VERSION:
				recruit_rank = tier
				desired = Vector2i((home + inward * 9.0 + side * 5.0).round()) if tier == 0 else Vector2i((home + inward * 17.0 - side * 11.0).round())
			var placed := _add_scroll(desired, index, code, tier + 2, recruit_rank)
			if placed < 0:
				error = "Could not place a recruitment scroll for player %d. Try a larger map." % int(start.player)
				return false
			start.rewards.append(placed)
		if config.version < PLACEMENT_VERSION:
			var pool := _frontier_spells(start.color)
			if not pool.is_empty(): _add_scroll(Vector2i(home.lerp(center, 0.65) + side * 10), index, pool[_next(pool.size())], 3)

	var abundance := ECONOMIES.find(config.resources)
	var per_player := 2 + abundance * 2 + maxi(0, (_map.width - 64) / 32)
	if config.version >= GUARDED_PRIZES_VERSION: per_player = 1 + abundance + maxi(0, (_map.width - 96) / 48)
	# Stock maps carry about 2.3 mines per thousand land tiles.
	if config.version >= STOCK_LAYOUT_VERSION: per_player = 2 + abundance + maxi(0, (_map.width - 64) / 32)
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
			if config.version >= PLACEMENT_VERSION:
				var habitat := "woods" if kind == "Root" else ("bank" if kind == "Lotus" else "ridge")
				desired = _habitat_anchor(desired, habitat)
			var row: Dictionary = _catalog.mines[kind]
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var pos := _find_spot(desired, size, 14, -1, config.version >= PLACEMENT_VERSION, true,
				false, -1, _site_gap())
			if pos == NO_SPOT: continue
			var item := _place("mines", str(row.Name), pos, row, 0, start.color, [_node("level", {}, "0")])
			_clear_footprint(pos, size)
			_connect_site(Vector2i(start.x, start.y), item, size, config.version < PLACEMENT_VERSION, config.version < PLACEMENT_VERSION)
			_important.append(int(item.permanent_id) - 1)
			if config.guards != "none": _add_guard(Vector2i((Vector2(pos) - forward * 2).round()), index, 1 + number / 2, item, size)
			var supply_at := pos + size + Vector2i(2, 2)
			var amount := 10 + abundance * 10
			if config.version < FRONTIERS_VERSION:
				_add_pickup(supply_at, -1, amount)
			elif config.version < GUARDED_PRIZES_VERSION or config.version >= STOCK_LAYOUT_VERSION or number % 2 == 0:
				_frontier_supplies.append({"mine": int(item.permanent_id) - 1, "fallback": supply_at, "amount": amount})
		# Optional adventure rewards use genuine installed artifact rows.
		if config.version < PLACEMENT_VERSION and not _catalog.artifacts.is_empty():
			var name: String = _catalog.artifacts[_next(_catalog.artifacts.size())]
			var row: Dictionary = _profile.table("Artefacts")[name]
			var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
			var pos := _find_spot(Vector2i(home.lerp(center, 0.7)), size, 12, -1, false, true)
			if pos != NO_SPOT:
				var item := _place("artefacts", name, pos, row)
				_clear_footprint(pos, size)
				_connect_site(Vector2i(start.x, start.y), item, size)
				_important.append(int(item.permanent_id) - 1)
				if config.guards != "none": _add_guard(pos - Vector2i(2, 1), index, 4, item, size)
		if config.guards != "none" and config.version < GUARD_POSTS_VERSION:
			for number in (2 if config.guards == "normal" else 3):
				_add_guard(Vector2i(home.lerp(center, 0.6 + number * 0.1) + side * (5 + number * 3)), index, 2 + number)


	return true

func _frontier_spells(color: String) -> Array[String]:
	var pool: Array[String] = []
	for code: String in _keys(_profile.table("GlobalSpells")):
		var row: Dictionary = _profile.table("GlobalSpells")[code]
		if row.get("Color") not in [color, "Colorless"] or code in ELGlobalSpells.SUMMONS or not ELGlobalSpells.supported(code): continue
		if code in [ELGlobalSpells.DEFENDER, ELGlobalSpells.WARRIOR] or ELGlobalSpells.RITUALS.has(code): continue
		pool.append(code)
	return pool

func _make_frontier_prizes() -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	var relics: Array = _catalog.artifacts.filter(func(name: String) -> bool: return not ELDuel.artifact_entry(_profile, {"name": name}).is_empty())
	for home in _starts.size():
		var start: Dictionary = _starts[home]
		var origin := Vector2(start.x, start.y)
		var inward := (center - origin).normalized()
		var side := Vector2(-inward.y, inward.x) * (-1.0 if _hash(home, _map.width, 681) < 0.5 else 1.0)
		var spells := _frontier_spells(start.color)
		if not relics.is_empty():
			var name: String = relics[_next(relics.size())]
			_place_frontier_prize(home, Vector2i(origin + inward * 20.0 + side * 10.0), "artefacts",
				name, _profile.table("Artefacts")[name], [], 4)
		if not spells.is_empty():
			var nodes := [_node("spells", {}, "", [_node("spell", {"code": spells[_next(spells.size())]})])]
			_place_frontier_prize(home, Vector2i(origin + inward * 16.0 - side * 10.0), "global_spells",
				"FullSpell", _profile.table("GlobalSpellCut")["FullSpell"], nodes, 3)

func _place_frontier_prize(home: int, desired: Vector2i, group: String, name: String, row: Dictionary, nodes: Array, tier: int) -> void:
	var start: Dictionary = _starts[home]
	var origin := Vector2i(start.x, start.y)
	var region := _region_at(origin)
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var search := Rect2i(desired - Vector2i.ONE * 20, Vector2i.ONE * 41).intersection(Rect2i(3, 3, _map.width - 6, _map.height - 6))
	var best := NO_SPOT
	var best_score := INF
	var best_approach := -1
	var best_guard := {}
	for y in range(search.position.y, search.end.y):
		for x in range(search.position.x, search.end.x):
			var at := Vector2i(x, y)
			if _owner(at) != home or (config.naval and _region_at(at) != region): continue
			if at.distance_squared_to(origin) < 12 * 12: continue
			if config.version >= GUARDED_PRIZES_VERSION and not _clears_sites(at + size / 2, _site_gap()): continue
			var score := float(at.distance_squared_to(desired))
			if score >= best_score or not _fits(at, size, true, true): continue
			var footprint := Rect2i(at, size)
			var approach := _expedition_trail(footprint)
			if approach < 0: continue
			var preferred := at + (origin - at).sign() * 2
			var guard := {}
			if config.guards != "none":
				if config.version >= GUARDED_PRIZES_VERSION: guard = _prize_gate(footprint, preferred)
				if guard.is_empty():
					guard = _reward_guard(footprint, preferred)
					if config.version >= GUARDED_PRIZES_VERSION: score += 550.0
			# A guardable alcove is worth a longer walk. Crowded homelands
			# can still hide a reward when there is no safe place for its guard.
			if config.guards != "none" and guard.is_empty(): score += 400.0
			if score >= best_score: continue
			best = at
			best_score = score
			best_approach = approach
			best_guard = guard
	if best == NO_SPOT: return
	var item := _place(group, name, best, row, 0, _colors[home], nodes)
	var id := int(item.permanent_id) - 1
	_important.append(id)
	if best_guard.has("blocks"):
		best_approach = best_guard.approach.y * _map.width + best_guard.approach.x
		for point: Vector2i in best_guard.blocks:
			var prop := _prize_prop(point)
			_place("terrain_objects", prop.name, point, prop.row, 0, "", [], {}, floori(_hash(point.x, point.y, 1601) * 4.0) * 4)
		_clear_prize_approach(best_approach)
	_protect_route(best_approach, _exploration_access)
	if not best_guard.is_empty():
		var level := tier + (1 if config.guards == "strong" else 0)
		var choices: Array = _catalog.monsters.filter(func(entry: Dictionary) -> bool: return entry.name in (FRONTIER_ENCOUNTERS if level >= 4 else WILDERNESS_ENCOUNTERS))
		_record_reward_guard(id, best_guard.guard, best_guard.approach, _regional_guard(best_guard.guard, choices, level), home)
		if best_guard.has("blocks"): _gated_prizes[id] = _reward_guards[id]

func _clear_prize_approach(approach: int) -> void:
	# Larger models overhang their footprints. Clear the shoulders near the
	# prize so that the walkable path still reads as a gap in the forest.
	var offset := approach
	for step in 10:
		if offset < 0: break
		var at := Vector2i(offset % _map.width, offset / _map.width)
		if not _walkable(at): break
		var margin := Rect2i(at - Vector2i.ONE, Vector2i(3, 3)).intersection(Rect2i(0, 0, _map.width, _map.height))
		for y in range(margin.position.y, margin.end.y):
			for x in range(margin.position.x, margin.end.x): _approach_clearings[y * _map.width + x] = 1
		if config.roads and _map.roads[offset] == 0: _map.roads[offset] = 7
		offset = _exploration_access[offset]

func _read_prize_scenery() -> void:
	var pools := _scenery_catalog()
	for color: String in COLORS:
		var pool: Dictionary = pools[color]
		var choices: Array = pool.canopy + pool.stones + pool.plants
		if config.version >= REGIONAL_LANDSCAPES_VERSION and not pool.stones.is_empty():
			choices = pool.stones if color in ["Red", "Black"] else pool.canopy + pool.stones
		_prize_scenery[color] = choices.filter(func(prop: Dictionary) -> bool:
			var shape := ELAdventureGrid.footprint(prop.row, 0)
			return shape.size == Vector2i.ONE and shape.cells.size() == 1
		)

func _prize_prop(point: Vector2i) -> Dictionary:
	var color := ELAdventureArt.terrain_color(_map.tile(point.x, point.y))
	var choices: Array = _prize_scenery.get(color, [])
	if choices.is_empty(): return {}
	return choices[floori(_hash(point.x, point.y, 1627) * choices.size()) % choices.size()]

func _prize_gate(site: Rect2i, preferred: Vector2i) -> Dictionary:
	var best := {}
	var best_score := INF
	var stands: Array[Vector2i] = []
	var ring := site.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var point := Vector2i(x, y)
			if site.has_point(point) or not _inside(point): continue
			var offset := y * _map.width + x
			var road: bool = not config.naval and _map.roads[offset] in [5, 6, 7, 8]
			if _occupied[offset] == 0 and (road or _walkable(point)): stands.append(point)
	for guard: Vector2i in stands:
		var guard_offset := guard.y * _map.width + guard.x
		if _guard_safe[guard_offset] != 0 or _scenery_paths[guard_offset] != 0 or not _fits(guard, Vector2i.ONE, true, true): continue
		if _starts.any(func(start: Dictionary) -> bool: return guard.distance_squared_to(Vector2i(start.x, start.y)) < 121): continue
		if ELInterception.DIRECTIONS.any(func(direction: Vector2i) -> bool:
			var point := guard + direction
			return _guard_safe[point.y * _map.width + point.x] != 0
		): continue
		var approaches: Array[Vector2i] = []
		var blocks: Array[Vector2i] = []
		var legal := true
		for point: Vector2i in stands:
			if point == guard: continue
			if point.distance_squared_to(guard) <= 2:
				approaches.append(point)
				continue
			var offset := point.y * _map.width + point.x
			var protected := _reserved[offset] != 0 or _scenery_paths[offset] != 0 or _guard_safe[offset] != 0
			if blocks.size() >= 4 or protected or _map.roads[offset] != 0 or _prize_prop(point).is_empty():
				legal = false
				break
			blocks.append(point)
		if not legal or approaches.is_empty(): continue
		var score := float(guard.distance_squared_to(preferred) + blocks.size() * 3)
		if score >= best_score: continue
		var obstacles := {guard: true}
		for point: Vector2i in blocks: obstacles[point] = true
		var reach := _expedition_trail(site, obstacles, approaches)
		if reach < 0: continue
		best_score = score
		best = {"guard": guard, "approach": Vector2i(reach % _map.width, reach / _map.width), "blocks": blocks}
	return best

func _add_scroll(desired: Vector2i, home: int, code: String, tier: int, recruit_rank := -1) -> int:
	var row: Dictionary = _profile.table("GlobalSpellCut")["FullSpell"]
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var origin := Vector2i(_starts[home].x, _starts[home].y)
	var pos := _find_spot(desired, size, 20, -1, config.version >= PLACEMENT_VERSION, true) if recruit_rank < 0 else _homeland_scroll(origin, desired, size, home, recruit_rank)
	if pos == NO_SPOT and (config.naval or recruit_rank >= 0):
		pos = _find_spot(origin, size, _map.width / 2, home, true, true)
	if pos == NO_SPOT: return -1
	var item := _place("global_spells", "FullSpell", pos, row, 0, _colors[home], [_node("spells", {}, "", [_node("spell", {"code": code})])])
	_clear_footprint(pos, size)
	var road: bool = config.version < PLACEMENT_VERSION or recruit_rank >= 0
	_connect_site(origin, item, size, road, road)
	_important.append(int(item.permanent_id) - 1)
	if config.guards != "none" and (recruit_rank < 0 or (config.version < PLACEMENT_VERSION and recruit_rank != 0)):
		_add_guard(pos - Vector2i(2, 1), home, tier, item, size)
	return int(item.permanent_id) - 1

func _homeland_scroll(origin: Vector2i, desired: Vector2i, size: Vector2i, home: int, rank: int) -> Vector2i:
	var best := NO_SPOT
	var best_score := INF
	var radius := OPENING_DISTANCE if rank == 0 else 23
	var best_distance := 10 if rank == 0 else 18
	var region := _region_at(origin)
	_route_grid.set_point_solid(origin, false)
	_port_routes.clear()
	for y in range(origin.y - radius, origin.y + radius + 1):
		for x in range(origin.x - radius, origin.x + radius + 1):
			var at := Vector2i(x, y)
			var distance := at.distance_squared_to(origin)
			if distance > radius * radius or distance < 5 * 5 or (config.naval and _region_at(at) != region): continue
			var score := float(at.distance_squared_to(desired)) * 0.26
			if score >= best_score or _owner(at) != home or not _fits(at, size, true, true): continue
			var path := _route_grid.get_id_path(origin, at)
			if path.is_empty() or path.size() > radius + 3: continue
			score += pow(absi(path.size() - best_distance), 2) * 0.8
			if score >= best_score: continue
			best = at
			best_score = score
	_route_grid.set_point_solid(origin, true)
	_port_routes.clear()
	return best

func _place_frontier_supplies() -> void:
	var counts := {}
	var pairs := {}
	for supply: Dictionary in _frontier_supplies:
		var mine: Dictionary = _map.objects[supply.mine]
		var source := Vector2i(mine.x, mine.y)
		var region := _region_at(source)
		var candidates: Array[Dictionary] = []
		for guard_id: int in _reward_guards.values():
			var limit := 1 if config.version >= GUARDED_PRIZES_VERSION else 2
			if int(counts.get(guard_id, 0)) >= limit: continue
			var guard: Dictionary = _map.objects[guard_id]
			var at := Vector2i(guard.x, guard.y)
			var distance := at.distance_squared_to(source)
			if distance > 14 * 14 or _region_at(at) != region: continue
			candidates.append({"guard": guard_id, "at": at, "score": distance - (14 * 14 if _reward_guards.get(supply.mine, -1) == guard_id else 0)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score if a.score != b.score else a.guard < b.guard)
		var placed := false
		for candidate: Dictionary in candidates:
			var at: Vector2i = candidate.at
			var direction := (at - source).sign()
			var id := _add_pickup(at + direction * 2, -1, supply.amount, 2, true, region)
			if id < 0: continue
			counts[candidate.guard] = int(counts.get(candidate.guard, 0)) + 1
			pairs[id] = candidate.guard
			placed = true
			break
		if not placed:
			_add_pickup(supply.fallback, -1, supply.amount, 8, true, region)
	report.guarded_supplies = pairs

func _add_pickup(desired: Vector2i, home: int, amount: int, radius := 8, expedition := false, region := -1) -> int:
	if _catalog.cuts.is_empty(): return -1
	var keys := _keys(_catalog.cuts)
	var name: String = keys[_next(keys.size())]
	var row: Dictionary = _catalog.cuts[name]
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var gap := 5 if config.version >= GUARDED_PRIZES_VERSION else 0
	var pos := _find_spot(desired, size, radius, home, config.version >= PLACEMENT_VERSION, true, expedition, region, gap)
	if pos == NO_SPOT: return -1
	var resources: Array = []
	# A visible pile gives a small mixed cache, avoiding a dead opening when
	# an installed pile's display name is not one of the resource constants.
	for kind: String in ELResources.ORIGINAL: resources.append(_node("resource", {"type": kind, "amount": str(amount if kind in ["Root", "Lotus"] else maxi(1, amount / 3))}))
	var approach := _expedition_trail(Rect2i(pos, size)) if expedition else -1
	var item := _place("resource_cuts", name, pos, row, 0, "", [_node("resources", {}, "", resources)])
	if expedition:
		_protect_route(approach, _exploration_access)
	else:
		_clear_footprint(pos, size)
		var seat := home if home >= 0 else _owner(pos)
		_connect_site(Vector2i(_starts[seat].x, _starts[seat].y), item, size, config.version < PLACEMENT_VERSION, home >= 0 or config.version < PLACEMENT_VERSION)
	var id := int(item.permanent_id) - 1
	_important.append(id)
	return id

func _add_guard(desired: Vector2i, home: int, tier: int, site := {}, size := Vector2i.ONE) -> void:
	if config.version >= GUARD_POSTS_VERSION: return
	if config.version >= WILDERNESS_VERSION:
		var encounter := {"at": desired, "home": home, "tier": tier}
		if config.version >= PLACEMENT_VERSION and not site.is_empty():
			encounter.site = Rect2i(Vector2i(site.x, site.y), size)
			encounter.site_id = int(site.permanent_id) - 1
		_guard_queue.append(encounter)
		return
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
	_place_guard(pos, chosen.name, home)

func _place_guard(pos: Vector2i, name: String, home: int, reserve_naval_route := true) -> int:
	var row := ELFirstMonsters.definition(_profile, name, 0)
	if config.version >= LANDSCAPE_VERSION and config.naval and reserve_naval_route:
		# Later guards and buildings must leave at least one coastal approach.
		var path := _port_route(pos)
		for index in range(path.size() - 1):
			var at := path[index]
			var next := path[index + 1]
			_reserved[at.y * _map.width + at.x] = 1
			if at.x != next.x and at.y != next.y:
				_reserved[at.y * _map.width + next.x] = 1
				_reserved[next.y * _map.width + at.x] = 1
	var item := _place("np_heroes", name, pos, row, 0, _colors[home], [_node("monster")])
	if config.version < GUARDED_PRIZES_VERSION: _paint_disk(pos, 2, false)
	var id := int(item.permanent_id) - 1
	_important.append(id)
	return id

func _prepare_starter_lairs() -> void:
	for home in _starts.size():
		var start: Dictionary = _starts[home]
		var lair: Dictionary = _home_lairs[home]
		if lair.is_empty(): lair = _add_exploration_site("Dungeon1", Vector2i(start.x, start.y), 19, home)
		if lair.is_empty(): continue
		lair.node.children.append(_node("params", {}, STARTER_LAIR))
		start.opening_lair = int(lair.permanent_id) - 1

func _post_field_guards() -> bool:
	var objects := _navigation_objects()
	var grid := ELAdventureGrid.new()
	if not grid.build(_map, objects):
		error = "Encounter placement could not build the movement grid: " + grid.error
		return false
	var placement := EncounterPlacement.new(grid, _guard_safe, _scenery_paths)
	var travel := _home_travel(placement) if config.version >= LIVING_WILDS_VERSION else PackedInt32Array()
	var spacing := 4 if config.guards == "strong" else 5
	var spaced := PackedByteArray()
	spaced.resize(_map.roads.size())
	var opening := {}
	for start: Dictionary in _starts:
		for id: int in start.sites + start.rewards: opening[id] = true
	var ranks := {"artefacts": 4, "global_spells": 3, "mines": 3, "mana_nodes": 3, "additional_buildings": 2, "resource_cuts": 1}
	var sites: Array[Dictionary] = []
	for id: int in objects:
		var item: Dictionary = objects[id]
		var at := Vector2i(item.x, item.y)
		if item.type == "monster":
			_mark_radius(spaced, at, spacing)
			continue
		if not ranks.has(item.group) or opening.has(id) or _reward_guards.has(id): continue
		if item.group == "additional_buildings" and (not ELAdditionalBuildings.supported(item) or ELAdditionalBuildings.DUNGEONS.has(item.name)): continue
		if _starts.any(func(start: Dictionary) -> bool: return at.distance_squared_to(Vector2i(start.x, start.y)) < 12 * 12): continue
		sites.append(item)
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.group == b.group or ranks[a.group] == ranks[b.group]: return int(a.uid) < int(b.uid)
		return int(ranks[a.group]) > int(ranks[b.group]))
	for site: Dictionary in sites:
		var at := Vector2i(site.x, site.y)
		var home := _owner(at)
		var start: Dictionary = _starts[home]
		var spot := placement.site_guard(site, Vector2i(start.x, start.y), spaced)
		if spot.is_empty(): continue
		var level := maxi(2, int(ranks[site.group])) + (1 if config.guards == "strong" else 0)
		if not travel.is_empty():
			# Prizes near a castle get a gentler guard; distant ones a sterner one.
			var steps := travel[spot.guard.y * _map.width + spot.guard.x]
			var band := -1 if steps >= 0 and steps < 22 else (1 if steps < 0 or steps >= 40 else 0)
			level = clampi(int(ranks[site.group]) + band, 2, 5) + (1 if config.guards == "strong" else 0)
			if config.version >= STOCK_LAYOUT_VERSION:
				level = _stock_level(steps) + (1 if site.group == "artefacts" else 0) + (1 if config.guards == "strong" else 0)
		var id := _station_guard(grid, spot.guard, level, home)
		_reward_guards[site.uid] = id
		if spot.full and site.group in ["artefacts", "global_spells"]: _gated_prizes[site.uid] = id
		_mark_radius(spaced, spot.guard, spacing)
	_post_pass_guards(placement)
	if config.version >= LIVING_WILDS_VERSION: _post_wilderness_creatures(placement, travel)
	return true

## Land steps from the nearest castle on the finished grid; -1 where no
## castle can walk (outlying islands).
func _home_travel(placement: RefCounted) -> PackedInt32Array:
	var steps := PackedInt32Array()
	steps.resize(_map.width * _map.height)
	steps.fill(-1)
	var queue: Array[Vector2i] = []
	for start: Dictionary in _starts:
		var origin := Vector2i(start.x, start.y)
		steps[origin.y * _map.width + origin.x] = 0
		queue.append(origin)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		var next_step := steps[at.y * _map.width + at.x] + 1
		for delta: Vector2i in ELInterception.DIRECTIONS:
			var next := at + delta
			if not _inside(next) or steps[next.y * _map.width + next.x] >= 0 or not placement._land(next): continue
			steps[next.y * _map.width + next.x] = next_step
			queue.append(next)
	return steps

## Stock missions keep a creature every few screens: around 22 per thousand
## passable tiles, level two near a castle and about four farther out. Add
## roaming creatures on the finished grid toward a lighter share of that,
## favoring roadsides, clearings, ridges and shores, never on a protected
## opening route or a harbor approach.
func _post_wilderness_creatures(placement: RefCounted, travel: PackedInt32Array) -> void:
	var strong: bool = config.guards == "strong"
	var gap := 3 if strong else 4
	var spaced := PackedByteArray()
	spaced.resize(_map.roads.size())
	var placed := 0
	for item: Dictionary in _map.objects:
		if item.group != "np_heroes": continue
		_mark_radius(spaced, Vector2i(item.x, item.y), gap)
		placed += 1
	var land := 0
	var candidates: Array[Dictionary] = []
	for y in range(4, _map.height - 4):
		for x in range(4, _map.width - 4):
			var at := Vector2i(x, y)
			if not placement._land(at): continue
			land += 1
			var offset := y * _map.width + x
			var steps := travel[offset]
			if steps >= 0 and steps < 10: continue
			if not placement.field_cell(at, spaced, 4): continue
			var field := y * (_map.width + 1) + x
			var roadside := 0.0
			for delta: Vector2i in ELInterception.DIRECTIONS:
				var near := at + delta
				if _map.roads[near.y * _map.width + near.x] != 0: roadside = 0.3
			var score := _hash(x, y, 9157) + roadside + 0.22 * (1.0 - _canopy[field]) + 0.2 * float(_landform(at) == Landform.RIDGE) + (0.15 if _shore[field] <= 3 else 0.0)
			candidates.append({"at": at, "score": score})
	var target := ceili(float(land) / (70.0 if strong else 85.0))
	if config.version >= STOCK_LAYOUT_VERSION:
		# Stock: about ten creatures per thousand tiles of dry ground,
		# counting ground under woods, as common far out as near home.
		var ground := 0
		for y in range(_map.height):
			for x in range(_map.width): ground += int(_walkable(Vector2i(x, y)))
		target = ceili(float(ground) / (82.0 if strong else 100.0))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score) if a.score != b.score else _index(a.at) < _index(b.at))
	var roaming: Array[int] = []
	for candidate: Dictionary in candidates:
		if placed >= target: break
		var at: Vector2i = candidate.at
		if spaced[at.y * _map.width + at.x] != 0 or not placement.field_cell(at, spaced, 4): continue
		var steps := travel[at.y * _map.width + at.x]
		var level := 4 if steps < 0 else (1 if steps < 16 else (2 if steps < 28 else (3 if steps < 42 else 4)))
		if config.version >= STOCK_LAYOUT_VERSION:
			# Stock median levels by walking distance from a castle.
			level = _stock_level(steps)
		elif level < 4 and _landform(at) == Landform.RIDGE and _hash(at.x, at.y, 9173) > 0.5: level += 1
		if strong: level += 1
		roaming.append(_station_guard(placement.grid, at, level, _owner(at)))
		_mark_radius(spaced, at, gap)
		placed += 1
	if config.version >= STOCK_LAYOUT_VERSION:
		var watched: Array[int] = roaming.duplicate()
		for id: int in report.get("passage_guards", {}): watched.append(id)
		var dropped := _drop_sealed_creatures(placement.grid, watched)
		roaming.assign(roaming.filter(func(id: int) -> bool: return not dropped.has(id)))
		for id: int in dropped: report.passage_guards.erase(id)
	report.roaming_creatures = roaming

## In narrow woods one roaming creature can close the only way to another.
## Remove roaming creatures no hero can reach on the finished grid, nearest
## the start last, until every remaining one has a reachable neighbor.
func _drop_sealed_creatures(grid: ELAdventureGrid, roaming: Array[int]) -> Dictionary:
	var removed := {}
	_strict_corners = config.version >= STOCK_LAYOUT_VERSION
	var by_id := {}
	for item: Dictionary in _map.objects:
		if item.group == "np_heroes": by_id[int(item.permanent_id) - 1] = item
	for round in 6:
		var reached := PackedByteArray()
		reached.resize(_map.width * _map.height)
		var first := Vector2i(_starts[0].x, _starts[0].y)
		var queue: Array[Vector2i] = [first]
		reached[_index(first)] = 1
		var head := 0
		while head < queue.size():
			var at := queue[head]
			head += 1
			for delta: Vector2i in ELInterception.DIRECTIONS:
				var next := at + delta
				if not grid.contains(next) or reached[_index(next)] != 0 or grid.land.is_point_solid(next): continue
				if config.naval and not ELFirstNaval.connected(grid, at, next, true, true): continue
				if _corner_gap(grid, at, next): continue
				reached[_index(next)] = 1
				queue.append(next)
		var sealed: Array[int] = []
		for id: int in roaming:
			var item: Dictionary = by_id[id]
			var open := false
			for delta: Vector2i in ELInterception.DIRECTIONS:
				var near := Vector2i(item.x, item.y) + delta
				# The final access check does not count shore cells as stands.
				if grid.contains(near) and reached[_index(near)] != 0 and not (config.naval and _sea_cell(near)): open = true
			if not open: sealed.append(id)
		if sealed.is_empty(): break
		for id: int in sealed:
			var item: Dictionary = by_id[id]
			grid.update_actor({"uid": id, "x": item.x, "y": item.y, "type": "monster", "alive": false, "visible": false})
			roaming.erase(id)
			_important.erase(id)
		for id: int in sealed: removed[id] = true
		_map.objects = _map.objects.filter(func(item: Dictionary) -> bool: return not removed.has(int(item.permanent_id) - 1))
	_strict_corners = false
	return removed

## Median creature level in the stock missions by land steps from the
## nearest castle (-1: no land route, such as an outlying island).
func _stock_level(steps: int) -> int:
	if steps < 0: return 6
	return 1 if steps <= 10 else (3 if steps <= 20 else (4 if steps <= 30 else (5 if steps <= 45 else 6)))

func _index(at: Vector2i) -> int:
	return at.y * _map.width + at.x

func _post_pass_guards(placement: RefCounted) -> void:
	var spaced := PackedByteArray()
	spaced.resize(_map.roads.size())
	for item: Dictionary in _map.objects:
		if item.group == "np_heroes": _mark_radius(spaced, Vector2i(item.x, item.y), 7)
	var candidates: Array[Dictionary] = []
	var land := 0
	for y in range(3, _map.height - 3):
		for x in range(3, _map.width - 3):
			var at := Vector2i(x, y)
			if not _walkable(at): continue
			land += 1
			if not _clears_sites(at, 4) or not placement.pass_candidate(at, spaced): continue
			var field := y * (_map.width + 1) + x
			var score := _rock[field] + (0.45 if _shore[field] <= 4 else 0.0) + _hash(x, y, 8069) * 0.3
			candidates.append({"at": at, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	var passes := {}
	var budget := ceili(land / 1800.0)
	for candidate: Dictionary in candidates:
		if passes.size() >= budget: break
		var at: Vector2i = candidate.at
		if spaced[at.y * _map.width + at.x] != 0: continue
		var ends: Array[Vector2i] = placement.crossing(at)
		if ends.is_empty(): continue
		var level := 4 if config.guards == "strong" else 3
		var id := _station_guard(placement.grid, at, level, _owner(at))
		passes[id] = ends
		_mark_radius(spaced, at, 12)
	report.passage_guards = passes

func _station_guard(grid: ELAdventureGrid, at: Vector2i, level: int, home: int) -> int:
	var id := _place_guard(at, _regional_guard(at, [], level), home, false)
	grid.update_actor({"uid": id, "x": at.x, "y": at.y, "type": "monster", "alive": true, "visible": true})
	return id

func _make_encounters() -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	var starter: Array = _catalog.monsters.filter(func(row: Dictionary) -> bool: return row.name in STARTER_ENCOUNTERS)
	var journey: Array = _catalog.monsters.filter(func(row: Dictionary) -> bool: return row.name in JOURNEY_ENCOUNTERS)
	var wilderness: Array = _catalog.monsters.filter(func(row: Dictionary) -> bool: return row.name in WILDERNESS_ENCOUNTERS)
	var frontier: Array = _catalog.monsters.filter(func(row: Dictionary) -> bool: return row.name in FRONTIER_ENCOUNTERS)
	var tiers := [starter, journey, wilderness, frontier]
	for index in _starts.size():
		var start: Dictionary = _starts[index]
		var origin := Vector2i(start.x, start.y)
		var outward := (Vector2(origin) - center).normalized()
		var side := Vector2(-outward.y, outward.x)
		var distance := 7 if config.version >= RELIEF_VERSION else 9
		var toward := Vector2i((Vector2(origin) + side * (distance if _next(2) == 0 else -distance) + outward * 2.0).round())
		var pos := _encounter_cell(toward, 12, index)
		if pos == NO_SPOT: pos = _encounter_cell(origin, 19, index)
		if pos != NO_SPOT:
			var name := _regional_guard(pos, starter, 1)
			start.opening_guard = _place_guard(pos, name, index)
		else:
			# A crowded island still gets an optional fight in its local lair.
			# The harbor and recruitment approaches stay clear.
			var lair: Dictionary = _home_lairs[index]
			if lair.is_empty(): lair = _add_exploration_site("Dungeon1", origin, 19, index)
			if not lair.is_empty():
				lair.node.children.append(_node("params", {}, STARTER_LAIR))
				start.opening_lair = int(lair.permanent_id) - 1
	# Resolve these encounters after the routes and sites have been placed.
	if config.version >= PLACEMENT_VERSION:
		_guard_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.tier) > int(b.tier) if a.tier != b.tier else int(a.get("site_id", -1)) < int(b.get("site_id", -1))
		)
	for encounter: Dictionary in _guard_queue:
		var approach := NO_SPOT
		var pos: Vector2i
		if encounter.has("site"):
			var placement := _reward_guard(encounter.site, encounter.at)
			pos = placement.get("guard", NO_SPOT)
			approach = placement.get("approach", NO_SPOT)
		else:
			pos = _encounter_cell(encounter.at, 7)
		if pos == NO_SPOT: continue
		var level := int(encounter.tier) + (1 if config.guards == "strong" else 0)
		var choices: Array = tiers[clampi(level - 1, 0, tiers.size() - 1)] if level <= 5 else []
		var name := _regional_guard(pos, choices, level)
		if approach != NO_SPOT:
			_record_reward_guard(encounter.site_id, pos, approach, name, encounter.home)
		else:
			_place_guard(pos, name, int(encounter.home))
	if config.version >= REGIONAL_LANDSCAPES_VERSION:
		_populate_regional_encounters()
	elif config.version >= RELIEF_VERSION:
		_populate_roaming_creatures(journey, wilderness)

func _record_reward_guard(id: int, guard: Vector2i, approach: Vector2i, name: String, home: int) -> void:
	_reward_guards[id] = _place_guard(guard, name, home)
	var offset := approach.y * _map.width + approach.x
	_corridor[offset] = 1
	if not _scenery_paths.is_empty(): _scenery_paths[offset] = 1

func _reward_guard(site: Rect2i, preferred: Vector2i) -> Dictionary:
	var best := {}
	var best_score := INF
	var ring := site.grow(1)
	var search := site.grow(2).intersection(Rect2i(2, 2, _map.width - 4, _map.height - 4))
	for y in range(search.position.y, search.end.y):
		for x in range(search.position.x, search.end.x):
			var point := Vector2i(x, y)
			if ring.has_point(point) or not _fits(point, Vector2i.ONE, true, true): continue
			if _exploration_access[y * _map.width + x] < -1 or _guard_safe[y * _map.width + x] != 0: continue
			if _starts.any(func(start: Dictionary) -> bool: return point.distance_squared_to(Vector2i(start.x, start.y)) < 121): continue
			var approach := NO_SPOT
			var covered := 0
			var unsafe := false
			for delta: Vector2i in ELInterception.DIRECTIONS:
				var next := point + delta
				var offset := next.y * _map.width + next.x
				if _guard_safe[offset] != 0:
					unsafe = true
					break
				if not ring.has_point(next) or site.has_point(next) or _occupied[offset] != 0 or _exploration_access[offset] < -1 or not _walkable(next): continue
				covered += 1
				approach = next
			if unsafe or covered == 0: continue
			var score := float(point.distance_squared_to(preferred)) - 3.0 * float(covered)
			if score >= best_score: continue
			best_score = score
			best = {"guard": point, "approach": approach}
	return best

func _populate_regional_encounters() -> void:
	var spaced := PackedByteArray()
	spaced.resize(_map.roads.size())
	var verges := PackedByteArray()
	verges.resize(spaced.size())
	var gap := 5 if config.guards == "strong" else 6
	var placed := 0
	for item: Dictionary in _map.objects:
		if item.group != "np_heroes": continue
		_mark_radius(spaced, Vector2i(item.x, item.y), gap)
		placed += 1
	for point: Vector2i in _network_points: _mark_radius(verges, point, 4)
	var land := 0
	var candidates: Array[Dictionary] = []
	for y in range(3, _map.height - 3):
		for x in range(3, _map.width - 3):
			var offset := y * _map.width + x
			var point := Vector2i(x, y)
			if _exploration_access[offset] < -1 or not _walkable(point): continue
			land += 1
			if spaced[offset] or _reserved[offset] or _corridor[offset]: continue
			var field := y * (_map.width + 1) + x
			var verge := 0.17 * verges[offset]
			var clearing := 1.0 - smoothstep(0.45, 0.77, _canopy[field])
			var score := _hash(x, y, 8011) + verge + 0.16 * clearing
			candidates.append({"point": point, "score": score})
	var target := ceili(float(land) / (110.0 if config.guards == "strong" else 128.0))
	if placed >= target: return
	var by_level := {}
	for entry: Dictionary in _catalog.monsters: by_level.get_or_add(entry.level, []).append(entry)
	# Give some optional stops a creature that actually threatens their
	# approach, then use the rest of the space for encounters between sites.
	var site_budget := ceili((target - placed) * 0.45)
	placed += _guard_regional_sites(spaced, gap, by_level, site_budget)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	for candidate: Dictionary in candidates:
		if placed >= target: break
		var point: Vector2i = candidate.point
		var offset := point.y * _map.width + point.x
		if spaced[offset] or not _open_encounter_cell(point): continue
		var home := _owner(point)
		var start: Dictionary = _starts[home]
		var distance := point.distance_squared_to(Vector2i(start.x, start.y))
		if distance < 11 * 11: continue
		var level := 2 if distance < 22 * 22 else (4 if _landform(point) == Landform.RIDGE else 3)
		if config.guards == "strong": level += 1
		_place_guard(point, _regional_guard(point, by_level.get(level, []), level), home)
		_mark_radius(spaced, point, gap)
		placed += 1

func _guard_regional_sites(spaced: PackedByteArray, gap: int, by_level: Dictionary, budget: int) -> int:
	var sites := _map.objects.filter(func(item: Dictionary) -> bool:
		return item.group in ["additional_buildings", "mines", "mana_nodes", "artefacts", "global_spells"] and not _reward_guards.has(int(item.permanent_id) - 1)
	)
	_shuffle(sites)
	var art := ELAdventureArt.new(_map)
	var count := 0
	for site: Dictionary in sites:
		if count >= budget: break
		var point := Vector2i(site.x, site.y)
		if spaced[point.y * _map.width + point.x]: continue
		var home := _owner(point)
		var start: Dictionary = _starts[home]
		var origin := Vector2i(start.x, start.y)
		if point.distance_squared_to(origin) < 15 * 15: continue
		var size: Vector2i = ELAdventureGrid.footprint(art.resolve(site).get("row", {}), int(site.rotation)).size
		var spot := _reward_guard(Rect2i(point, size), point + (origin - point).sign() * 2)
		if spot.is_empty(): continue
		var at: Vector2i = spot.guard
		if spaced[at.y * _map.width + at.x] or not _open_encounter_cell(at): continue
		var level := 4 if config.guards == "strong" else 3
		_record_reward_guard(int(site.permanent_id) - 1, at, spot.approach, _regional_guard(at, by_level.get(level, []), level), home)
		_mark_radius(spaced, at, gap)
		count += 1
	return count

func _open_encounter_cell(point: Vector2i) -> bool:
	if not _fits(point, Vector2i.ONE, true, true): return false
	for delta: Vector2i in ELInterception.DIRECTIONS:
		var near := point + delta
		if _guard_safe[near.y * _map.width + near.x] != 0: return false
	var exits := 0
	for delta: Vector2i in CARDINAL:
		var near := point + delta
		var offset := near.y * _map.width + near.x
		if _exploration_access[offset] >= -1 and _occupied[offset] == 0 and _walkable(near): exits += 1
	return exits >= 3

func _populate_roaming_creatures(journey: Array, wilderness: Array) -> void:
	var points: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	var land := 0
	for item: Dictionary in _map.objects:
		if item.group == "np_heroes": points.append(Vector2i(item.x, item.y))
	for y in range(3, _map.height - 3):
		for x in range(3, _map.width - 3):
			var index := y * _map.width + x
			var point := Vector2i(x, y)
			if _exploration_access[index] < -1 or not _walkable(point): continue
			land += 1
			if _reserved[index] == 0 and _corridor[index] == 0 and _hash(x, y, 1531) > 0.55: candidates.append(point)
	_shuffle(candidates)
	if _map.width >= 96:
		for index in _starts.size():
			var start: Dictionary = _starts[index]
			var origin := Vector2i(start.x, start.y)
			var sight := int(_profile.table("HeroTemplates")[_map.objects[start.hero_id].name].Sight)
			for point: Vector2i in candidates:
				var distance := point.distance_squared_to(origin)
				if distance < 9 * 9 or distance > sight * sight or _owner(point) != index: continue
				if points.any(func(other: Vector2i) -> bool: return point.distance_squared_to(other) < 7 * 7): continue
				if _encounter_cell(point, 0, index) == NO_SPOT: continue
				_place_guard(point, _regional_guard(point, journey, 2), index)
				points.append(point)
				break
	var desired := ceili(float(land) / (210.0 if config.guards == "strong" else 250.0))
	for point: Vector2i in candidates:
		if points.size() >= desired: break
		if points.any(func(other: Vector2i) -> bool: return point.distance_squared_to(other) < 10 * 10): continue
		var close := _encounter_cell(point, 0)
		if close == NO_SPOT: continue
		var strong: bool = config.guards == "strong" or (_landform(close) == Landform.RIDGE and _next(3) == 0)
		_place_guard(close, _regional_guard(close, wilderness if strong else journey, 3 if strong else 2), _owner(close))
		points.append(close)

func _regional_guard(pos: Vector2i, choices: Array, level: int) -> String:
	if choices.is_empty():
		var best := absi(int(_catalog.monsters[0].level) - level)
		for row: Dictionary in _catalog.monsters: best = mini(best, absi(int(row.level) - level))
		choices = _catalog.monsters.filter(func(row: Dictionary) -> bool: return absi(int(row.level) - level) == best)
	var favored: Array[Dictionary] = []
	var color := ELAdventureArt.terrain_color(_map.tile(pos.x, pos.y))
	for row: Dictionary in choices:
		if ELFirstMonsters.definition(_profile, row.name, 0).get("Color") == color: favored.append(row)
	# Stock creatures match their ground about a third of the time.
	# The roll is only drawn when there is a choice, as in earlier versions.
	if not favored.is_empty():
		var roll := _next(3)
		if (roll == 0) if config.version >= STOCK_LAYOUT_VERSION else (roll != 0): choices = favored
	return str(choices[_next(choices.size())].name)

func _encounter_cell(desired: Vector2i, radius: int, home := -1) -> Vector2i:
	var best := NO_SPOT
	var score := radius * radius + 1
	var origin := Vector2i(_starts[home].x, _starts[home].y) if home >= 0 else NO_SPOT
	var island := _region_at(origin)
	var reach := maxi(15, radius)
	for y in range(maxi(2, desired.y - radius), mini(_map.height - 2, desired.y + radius + 1)):
		for x in range(maxi(2, desired.x - radius), mini(_map.width - 2, desired.x + radius + 1)):
			var point := Vector2i(x, y)
			var cost := desired.distance_squared_to(point)
			if cost >= score or _exploration_access[y * _map.width + x] < -1: continue
			if home >= 0 and (_owner(point) != home or point.distance_squared_to(origin) > reach * reach or (config.naval and _region_at(point) != island)): continue
			var safe := true
			for start: Dictionary in _starts:
				var clearance := 6 if home >= 0 else 17
				if point.distance_squared_to(Vector2i(start.x, start.y)) < clearance * clearance: safe = false
			if not safe or not _fits(point, Vector2i.ONE, true, true): continue
			# The neutral creature can intercept any adjacent cell, including
			# diagonals. Keep those cells clear on protected approaches too.
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if _corridor[(y + dy) * _map.width + x + dx] != 0: safe = false
			if not safe: continue
			best = point
			score = cost
	return best

func _make_exploration_sites() -> void:
	var center := Vector2(_map.width, _map.height) * 0.5
	var spring := "SpringOfStrength" if _next(2) == 0 else "SpringOfDexterity"
	var lesson := "Teacher" if _next(2) == 0 else "Magister"
	var local_challenge := "Dungeon1" if config.guards != "none" else "TrainingCamp"
	var outer_reach := minf(_home_radius * 0.62, 14.0)
	for index in _starts.size():
		var home := Vector2(_anchors[index])
		var outward := (home - center).normalized()
		var side := Vector2(-outward.y, outward.x)
		# Visit sites behind and beside the castle put a useful journey in
		# each direction from the starting cluster.
		if config.version < GUARDED_PRIZES_VERSION or index % 2 == 0:
			_add_exploration_site(spring, Vector2i(home + outward * outer_reach + side * 6.0), 8, index)
		if config.version < GUARDED_PRIZES_VERSION or index % 2 != 0:
			_add_exploration_site(lesson, Vector2i(home + outward * outer_reach - side * 6.0), 8, index)
		var lair := _add_exploration_site(local_challenge, Vector2i(home + side * outer_reach + outward * 4.0), 7, index)
		if config.version >= WILDERNESS_VERSION: _home_lairs.append(lair)

	var destination := Vector2i(center)
	var neutral_regions := {}
	if config.naval:
		var home_regions := {}
		for start: Dictionary in _starts: home_regions[start.island] = true
		for port: Dictionary in _ports:
			var region := int(port.island)
			if home_regions.has(region) or neutral_regions.has(region): continue
			neutral_regions[region] = true
			var island := _region_root(region)
			if island == NO_SPOT: continue
			var outlying := _outlying_regions.has(region)
			var challenge := "Dungeon1" if outlying and config.guards == "normal" else "Dungeon2"
			if config.guards == "none": challenge = "Master"
			_add_exploration_site(challenge, island, 8, -1, region)
			if config.version < GUARDED_PRIZES_VERSION:
				_add_exploration_site("GnomeAlchemist", island + Vector2i(2, 2), 8, -1, region)
			if outlying:
				var relics: Array = _catalog.artifacts.filter(func(name: String) -> bool: return not ELDuel.artifact_entry(_profile, {"name": name}).is_empty())
				if not relics.is_empty(): _add_exploration_site(relics[_next(relics.size())], island + Vector2i(-2, 2), 8, -1, region, "", "artefacts")
				destination = island
			elif destination == Vector2i(center): destination = island
	var prize: String = ["ShrineMagic", "HealersCitadel", "WanderersCitadel"][_next(3)]
	var shrine := _add_exploration_site(prize, destination, 14, -1, _region_at(destination))
	if config.version >= WILDERNESS_VERSION and config.naval and _region_at(destination) < 0 and not shrine.is_empty():
		destination = Vector2i(shrine.x, shrine.y)
	var clue := "Lost expedition"
	var search := 13 if config.naval else mini(28, _map.width / 3)
	if not _add_exploration_site(ELAdditionalBuildings.BOWL, destination, search, -1, _region_at(destination), clue).is_empty():
		for index in _starts.size():
			var home := Vector2(_anchors[index])
			var outward := (home - center).normalized()
			var side := Vector2(-outward.y, outward.x)
			_add_exploration_site(ELAdditionalBuildings.LAKE, Vector2i(home - side * outer_reach), 7, index, -1, clue)
	if config.version >= WILDERNESS_VERSION: _fill_wilderness()
	else: _make_wilderness_stops()

func _fill_wilderness() -> void:
	# Measure the way along dry land, so a town across a river never counts
	# as coverage for an empty bank or an island of its own.
	var current_paths: bool = config.version >= RELIEF_VERSION
	if current_paths and not _check_access(true): return
	var distance := PackedInt32Array()
	distance.resize(_map.width * _map.height)
	distance.fill(0x7fff)
	var dry := PackedByteArray()
	dry.resize(distance.size())
	for y in _map.height:
		for x in _map.width: dry[y * _map.width + x] = int(_walkable(Vector2i(x, y)))
	var origins: Array[Vector2i] = []
	var options := [["SpringOfStrength", "GnomeMerchant", "MageWagon", "TraderWagon", "TrainingCamp"],
		["Teacher", "SpringOfDexterity", "MageWagon", "GnomeTinkerer"], ["Master", "GnomeAlchemist", "Dungeon1", "WanderersCitadel"]]
	var variety := {}
	for item: Dictionary in _map.objects:
		if item.group in ["buildings", "additional_buildings", "artefacts", "mines", "global_spells", "laboratories"]:
			origins.append(Vector2i(item.x, item.y))
		if item.group == "additional_buildings": variety.get_or_add(item.name, []).append(Vector2i(item.x, item.y))
	_spread_wilderness(distance, origins, dry)
	var candidates: Array[Vector2i] = []
	for y in range(3, _map.height - 3):
		for x in range(3, _map.width - 3):
			var at := y * _map.width + x
			if _exploration_access[at] >= -1 and _reserved[at] == 0 and dry[at] != 0:
				candidates.append(Vector2i(x, y))
	var paths_dirty := false
	var spacing := 17 if config.version >= GUARDED_PRIZES_VERSION else WILDERNESS_SPACING
	# Stock sites are four or five tiles apart and as common far from a
	# castle as near one.
	if config.version >= STOCK_LAYOUT_VERSION: spacing = 9
	for visit in _map.width * _map.height / 60:
		var point := NO_SPOT
		var score := -INF
		var index := candidates.size() - 1
		while index >= 0:
			var candidate := candidates[index]
			var offset := candidate.y * _map.width + candidate.x
			if distance[offset] <= spacing or _reserved[offset] != 0:
				candidates[index] = candidates[-1]
				candidates.pop_back()
			else:
				var priority := mini(80, distance[offset]) + _hash(candidate.x, candidate.y, 5281) * 3.0
				if priority > score:
					score = priority
					point = candidate
			index -= 1
		if point == NO_SPOT: break
		var pool: Array = options[_landform(point)].duplicate()
		if config.guards == "none": pool.erase("Dungeon1")
		_shuffle(pool)
		var scores := {}
		for name: String in pool:
			var placed: Array = variety.get(name, [])
			var repeat := placed.any(func(site: Vector2i) -> bool: return site.distance_squared_to(point) < 22 * 22)
			scores[name] = placed.size() + (5 if repeat else 0)
		pool.sort_custom(func(a: String, b: String) -> bool: return int(scores[a]) < int(scores[b]))
		var site := {}
		# Stock maps scatter about four resource piles per thousand land
		# tiles between their buildings. Every third stop is a pile.
		if config.version >= STOCK_LAYOUT_VERSION and visit % 3 == 2:
			var amount := 6 + 6 * ECONOMIES.find(config.resources)
			var pile := _add_pickup(point, -1, amount, 4, true, _region_at(point))
			if pile >= 0:
				paths_dirty = true
				var placed: Dictionary = _map.objects[pile]
				_spread_wilderness(distance, [Vector2i(placed.x, placed.y)], dry)
				continue
		for name: String in pool:
			site = _add_exploration_site(name, point, 5, -1, _region_at(point))
			if not site.is_empty(): break
		if site.is_empty():
			if current_paths and paths_dirty:
				# A new site can cross a branch of the old search tree.
				# Find the paths around it before giving up this area.
				if not _check_access(true): return
				paths_dirty = false
				continue
			# The selected point may be unusable because of a narrow coast.
			# Drop it without falsely filling the surrounding distance field.
			# Version 12 also drops its immediate neighbors: they share the
			# same search area and would fail the same way, one by one.
			if config.version >= LIVING_WILDS_VERSION:
				candidates.assign(candidates.filter(func(other: Vector2i) -> bool: return absi(other.x - point.x) > 2 or absi(other.y - point.y) > 2))
			else: candidates.erase(point)
		else:
			paths_dirty = true
			variety.get_or_add(site.name, []).append(Vector2i(site.x, site.y))
			_spread_wilderness(distance, [Vector2i(site.x, site.y)], dry)
	var farthest := 0
	for y in range(3, _map.height - 3):
		for x in range(3, _map.width - 3):
			var index := y * _map.width + x
			if _exploration_access[index] >= -1 and dry[index] != 0:
				farthest = maxi(farthest, distance[index])
	report.wilderness_distance = farthest

func _spread_wilderness(distance: PackedInt32Array, origins: Array[Vector2i], dry: PackedByteArray) -> void:
	for at: Vector2i in origins: distance[at.y * _map.width + at.x] = 0
	var directions := ELInterception.DIRECTIONS if config.version >= RELIEF_VERSION and not config.naval else CARDINAL
	var cursor := 0
	while cursor < origins.size():
		var at := origins[cursor]
		cursor += 1
		var next_distance := distance[at.y * _map.width + at.x] + 1
		for direction: Vector2i in directions:
			var next := at + direction
			if not _inside(next): continue
			var index := next.y * _map.width + next.x
			if distance[index] <= next_distance or dry[index] == 0: continue
			distance[index] = next_distance
			origins.append(next)

func _make_wilderness_stops() -> void:
	var options := ["GnomeMerchant", "MageWagon", "Master", "SpringOfStrength", "SpringOfDexterity"]
	for y in range(10, _map.height - 5, 20):
		for x in range(10, _map.width - 5, 20):
			var desired := NO_SPOT
			var best := 9 * 9
			# Find an empty pocket instead of copying the opening resource
			# cluster. Sample offsets inside each stretch of wilderness.
			for offset_y in [-6, -2, 2, 6]:
				for offset_x in [-6, -2, 2, 6]:
					var point := Vector2i(x + offset_x, y + offset_y)
					if not _walkable(point) or _exploration_access[point.y * _map.width + point.x] < -1: continue
					var distance := 20 * 20
					for item: Dictionary in _map.objects:
						distance = mini(distance, point.distance_squared_to(Vector2i(item.x, item.y)))
						if distance <= best: break
					if distance <= best: continue
					desired = point
					best = distance
			if desired != NO_SPOT:
				_add_exploration_site(options[_next(options.size())], desired, 4, -1, _region_at(desired))

func _site_gap() -> int:
	if config.version >= STOCK_LAYOUT_VERSION: return 5
	return FRONTIER_SITE_GAP if config.version >= GUARDED_PRIZES_VERSION else 0

func _add_exploration_site(name: String, near: Vector2i, radius: int, home := -1, region := -1, params := "", group := "additional_buildings") -> Dictionary:
	var table := "Artefacts" if group == "artefacts" else "AdditionalBuildings"
	var row: Dictionary = _profile.table(table).get(name, {})
	if not _model(row): return {}
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var gap := _site_gap()
	if config.version >= GUARDED_PRIZES_VERSION and ELAdditionalBuildings.DUNGEONS.has(name) and home >= 0:
		gap = 5
	var pos := _find_spot(near, size, radius, home, true, true, true, region, gap)
	if pos == NO_SPOT and config.version >= GUARDED_PRIZES_VERSION and name == "Dungeon1" and home >= 0:
		pos = _find_spot(near, size, radius, home, true, true, true, region)
	if pos == NO_SPOT: return {}
	var approach := _expedition_trail(Rect2i(pos, size))
	var children: Array = [] if params.is_empty() else [_node("params", {}, params)]
	var item := _place(group, name, pos, row, 0, "", children)
	_important.append(int(item.permanent_id) - 1)
	_protect_route(approach, _exploration_access)
	if config.version >= PLACEMENT_VERSION and name in ROAD_SERVICES:
		if home >= 0:
			var origin := Vector2i(_starts[home].x, _starts[home].y)
			_connect_site(origin, item, size)
		elif config.roads and config.version >= STOCK_LAYOUT_VERSION:
			# Wind the track in from the road network instead of following
			# the straight search tree.
			_connect_site(Vector2i(approach % _map.width, approach / _map.width), item, size, true, false)
		elif config.roads:
			_join_wilderness_track(approach)
	elif config.version >= RELIEF_VERSION and config.version < PLACEMENT_VERSION and config.roads:
		_join_wilderness_track(approach)
	if config.version >= PLACEMENT_VERSION and group == "artefacts" and config.guards != "none":
		_add_guard(pos - Vector2i(2, 1), _owner(pos), 4, item, size)
	return item

func _join_wilderness_track(approach: int) -> void:
	var offset := approach
	var trail := PackedInt32Array()
	for step in 12:
		if offset < 0 or not _walkable(Vector2i(offset % _map.width, offset / _map.width)): return
		if _map.roads[offset] > 4:
			for at: int in trail: _map.roads[at] = 7
			return
		trail.append(offset)
		offset = _exploration_access[offset]

## Find a reachable stand beside the prospective site. Its footprint must
## leave its own route intact, including the side cells of a naval diagonal.
func _expedition_trail(footprint: Rect2i, obstacles := {}, approaches: Array[Vector2i] = []) -> int:
	var perimeter := footprint.grow(1)
	# -2 disables the shortcut (custom obstacles are not part of the memo).
	var shallowest := -2
	if obstacles.is_empty() and _exploration_access.size() == _map.width * _map.height:
		shallowest = 1 << 30
		for y in range(footprint.position.y, footprint.end.y):
			for x in range(footprint.position.x, footprint.end.x):
				if not _inside(Vector2i(x, y)): continue
				var cell := y * _map.width + x
				if _exploration_access[cell] >= -1: shallowest = mini(shallowest, _trail_depth_at(cell))
	for y in range(perimeter.position.y, perimeter.end.y):
		for x in range(perimeter.position.x, perimeter.end.x):
			var point := Vector2i(x, y)
			if footprint.has_point(point) or not _walkable(point): continue
			if not approaches.is_empty() and point not in approaches: continue
			var approach := y * _map.width + x
			if _exploration_access[approach] < -1: continue
			var offset := approach
			while offset >= 0:
				# Below the shallowest footprint cell the walk can no longer
				# meet the footprint, so the memoized remainder decides.
				if shallowest > -2 and _trail_depth_at(offset) < shallowest:
					offset = -1 if _trail_clear[offset] == 1 else -3
					break
				var tile := Vector2i(offset % _map.width, offset / _map.width)
				var parent := _exploration_access[offset]
				if footprint.has_point(tile) or obstacles.has(tile) or (_occupied[offset] != 0 and parent >= 0): break
				if config.naval and parent >= 0:
					var from := Vector2i(parent % _map.width, parent / _map.width)
					if tile.x != from.x and tile.y != from.y:
						var side_a := Vector2i(tile.x, from.y)
						var side_b := Vector2i(from.x, tile.y)
						if footprint.has_point(side_a) or footprint.has_point(side_b) or obstacles.has(side_a) or obstacles.has(side_b): break
						if _occupied[from.y * _map.width + tile.x] != 0 or _occupied[tile.y * _map.width + from.x] != 0: break
				offset = parent
			if offset == -1: return approach
	return -1

## Route-tree depth of a reached cell (the root is 0), memoized together
## with whether every step to the root avoids occupied cells.
func _trail_depth_at(cell: int) -> int:
	if _trail_stale:
		_trail_depth.resize(_map.width * _map.height)
		_trail_depth.fill(-1)
		_trail_clear.resize(_trail_depth.size())
		_trail_clear.fill(0)
		_trail_stale = false
	if _trail_depth[cell] >= 0: return _trail_depth[cell]
	var chain := PackedInt32Array()
	var offset := cell
	while offset >= 0 and _trail_depth[offset] < 0:
		chain.append(offset)
		offset = _exploration_access[offset]
	var depth := -1 if offset < 0 else _trail_depth[offset]
	var clear := 1 if offset < 0 else _trail_clear[offset]
	for index in range(chain.size() - 1, -1, -1):
		var at := chain[index]
		var parent := _exploration_access[at]
		depth += 1
		if parent >= 0 and clear == 1:
			if _occupied[at] != 0: clear = 2
			elif config.naval:
				var x := at % _map.width
				var y := at / _map.width
				var px := parent % _map.width
				var py := parent / _map.width
				if x != px and y != py and (_occupied[y * _map.width + px] != 0 or _occupied[py * _map.width + x] != 0): clear = 2
		_trail_depth[at] = depth
		_trail_clear[at] = clear
	return _trail_depth[cell]

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
		var brush: Array[Dictionary] = []
		var canopy: Array[Dictionary] = []
		var groves: Array[Dictionary] = []
		var rocks: Array[Dictionary] = []
		var cliffs: Array[Dictionary] = []
		var undergrowth: Array[Dictionary] = []
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
			if span == 1 and plant and ELAdventureGrid.footprint(row, 0).cells.is_empty(): undergrowth.append(entry)
			if span > 4:
				if span <= 8: landmarks.append(entry)
				if not plant and span <= (12 if config.version >= REGIONAL_LANDSCAPES_VERSION else 10): cliffs.append(entry)
			elif plant:
				plants.append(entry)
				if name.contains("bush"): brush.append(entry)
				else:
					canopy.append(entry)
					if span >= 3: groves.append(entry)
			else:
				stones.append(entry)
				if span >= 3: rocks.append(entry)
		# A content pack can use different terrain object names.
		if plants.is_empty() and stones.is_empty(): plants.assign(_catalog.scenery)
		pools[color] = {"plants": plants, "stones": stones, "landmarks": landmarks, "brush": brush, "canopy": canopy,
			"groves": groves, "landscape_rocks": rocks, "cliffs": cliffs, "undergrowth": undergrowth}
	return pools

func _scenery_land() -> PackedByteArray:
	var land := PackedByteArray()
	land.resize(_map.width * _map.height)
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			if _walkable(Vector2i(x, y)): land[y * _map.width + x] = 1
	return land

func _make_scenery() -> void:
	var pools := _scenery_catalog()
	var land := _scenery_land()
	if config.version >= STOCK_LAYOUT_VERSION:
		_make_vein_scenery(land, pools)
		return
	if config.version >= REGIONAL_LANDSCAPES_VERSION:
		_make_regional_scenery(land, pools)
		return
	if config.version >= WILDERNESS_VERSION:
		_make_groves(land, pools)
		if config.version >= FRONTIERS_VERSION: _fill_scenery_between_groves(land, pools)
		return
	# Give each patch of land its own budget. Coastlines and the backs of
	# homelands get coverage even when most of the world is water.
	for top in range(2, _map.height - 2, SCENERY_PATCH_SIZE):
		for left in range(2, _map.width - 2, SCENERY_PATCH_SIZE):
			var area := Rect2i(left, top, SCENERY_PATCH_SIZE, SCENERY_PATCH_SIZE)
			_make_scenery_patch(area, land, pools)

## Version 13 follows the stock maps: about half the land is solid cliff and
## wood in rounded masses, and travel runs along a maze of lanes two to four
## tiles wide between them. Roads keep a three-tile lane, every site, creature
## and enclosed yard gets a winding lane to the network, and the rest is
## filled with the stock prop mix of its ground, the largest cliffs first.
## Gaps left inside a mass get single-tile props so it holds no sealed pocket.
## (Content without the stock props keeps the older noise veins.)
func _make_vein_scenery(land: PackedByteArray, pools: Dictionary) -> void:
	var w := _map.width
	var h := _map.height
	var art := ELAdventureArt.new(_map)
	var open := PackedByteArray()
	open.resize(w * h)
	var mixes := _stock_scenery_mix()
	var lanes := _cell_lanes() if not mixes.is_empty() else PackedByteArray()
	for y in h:
		for x in w:
			var i := y * w + x
			if land[i] == 0: continue
			# Site trails are straight search lines; the woods may close over
			# them. Reconnection and the access checks run on the result.
			var keep := _map.roads[i] != 0
			if not lanes.is_empty():
				# Stock layout: solid masses between a network of lanes.
				if keep: _mark_radius(open, Vector2i(x, y), 1)
				elif lanes[i] != 0: open[i] = 1
				continue
			# Stock cover by ground: Red about 62%, Green 45%, Black 42%,
			# Blue 24%. Lighter ground gets more channels and glades.
			var openness: float = {"Blue": 1.9, "Green": 1.0, "Black": 1.1, "Red": 0.55}.get(ELAdventureArt.terrain_color(_map.tile(x, y)), 1.0)
			var warp := Vector2(_noise(x, y, 17.0, 6311) - 0.5, _noise(x, y, 17.0, 6317) - 0.5) * 9.0
			var ridge := absf(_noise(x + warp.x, y + warp.y, 13.0, 6323) - 0.5)
			if ridge < 0.03 * openness: keep = true
			if _noise(x, y, 5.0, 6329) > 1.0 - 0.14 * openness: keep = true
			if keep: _mark_radius(open, Vector2i(x, y), 1)
	# Sites keep a two-tile apron, castles a homeland yard, harbors a quay.
	for item: Dictionary in _map.objects:
		if item.group in ["terrain_objects", "np_heroes"]: continue
		var size := Vector2i.ONE if item.group == "heroes" else Vector2i(ELAdventureGrid.footprint(art.resolve(item).get("row", {}), int(item.rotation)).size)
		var area := Rect2i(Vector2i(item.x, item.y), size).grow(1).intersection(Rect2i(0, 0, w, h))
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x): open[y * w + x] = 1
	for anchor: Vector2i in _anchors: _mark_radius(open, anchor, 4)
	for port: Dictionary in _ports: _mark_radius(open, Vector2i(port.land[0], port.land[1]), 2)
	if not lanes.is_empty():
		for item: Dictionary in _map.objects:
			if item.group == "np_heroes": open[int(item.y) * w + int(item.x)] = 1
		_join_open_ground(open, land)
	var fill := PackedByteArray()
	fill.resize(w * h)
	var order: Array[Vector2i] = []
	for y in h:
		for x in w:
			var i := y * w + x
			if land[i] != 0 and open[i] == 0 and _occupied[i] == 0:
				fill[i] = 1
				order.append(Vector2i(x, y))
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _hash(a.x, a.y, 6337) < _hash(b.x, b.y, 6337))
	var sized := {}
	for color: String in COLORS:
		var pool: Dictionary = pools[color]
		var bands := {"woods": [[], [], []], "rocks": [[], [], []]}
		for kind: String in ["plants", "stones"]:
			for entry: Dictionary in pool[kind]:
				var shape := ELAdventureGrid.footprint(entry.row, 0)
				if shape.cells.is_empty(): continue
				var span := maxi(shape.size.x, shape.size.y)
				if span > 8: continue
				var band := 0 if span >= 3 else (1 if span == 2 else 2)
				bands["woods" if kind == "plants" else "rocks"][band].append(entry)
		for kind: String in ["landscape_rocks"]:
			for entry: Dictionary in pool[kind]:
				if not bands.rocks[0].has(entry): bands.rocks[0].append(entry)
		sized[color] = bands
	# Naval guards reserve straight harbor lanes. The woods only need to
	# avoid real footprints and a one-tile margin; the access checks after
	# this pass see the finished grid.
	var reserved := _reserved
	_reserved = PackedByteArray()
	_reserved.resize(w * h)
	# Old site trails are straight search lines, so the woods may cover them.
	var trails := _scenery_paths
	_scenery_paths = PackedByteArray()
	_scenery_paths.resize(w * h)
	for item: Dictionary in _map.objects:
		var size := Vector2i.ONE if item.group in ["heroes", "np_heroes"] else Vector2i(ELAdventureGrid.footprint(art.resolve(item).get("row", {}), int(item.rotation)).size)
		var margin := 0 if item.group == "terrain_objects" else 1
		var area := Rect2i(Vector2i(item.x, item.y), size).grow(margin).intersection(Rect2i(0, 0, w, h))
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x): _reserved[y * w + x] = 1
	if not mixes.is_empty():
		# Stock mix, strictly largest first so the big cliffs find room.
		# Rocky ground favours cliffs and stones, the rest favours trees,
		# so each mass keeps one character.
		for tier in 5:
			for point: Vector2i in order:
				if _occupied[point.y * w + point.x] != 0: continue
				var color := ELAdventureArt.terrain_color(_map.tile(point.x, point.y))
				if not mixes.has(color): color = _colors[_owner(point)]
				if not mixes.has(color): continue
				var choices: Array = mixes[color][tier]
				if choices.is_empty(): continue
				var rocky := _rock[point.y * (w + 1) + point.x] > 0.45 or _noise(point.x, point.y, 11.0, 6343) > (0.48 if color in ["Red", "Black"] else 0.78)
				_place_stock_prop(point, choices, rocky, fill, 6 if tier < 3 else 3)
		_fill_mass_gaps(land, open, fill)
	else:
		# Stock props average about five cells: try the large band twice.
		for band in [0, 0, 1, 2]:
			for point: Vector2i in order:
				if _occupied[point.y * w + point.x] != 0: continue
				var color := ELAdventureArt.terrain_color(_map.tile(point.x, point.y))
				if not sized.has(color): color = _colors[_owner(point)]
				var field := point.y * (w + 1) + point.x
				# Stock green and snow land is mostly forest; dry land mixes rock.
				var rocky := _rock[field] > 0.45 or _noise(point.x, point.y, 11.0, 6343) > (0.48 if color in ["Red", "Black"] else 0.78)
				var bands: Dictionary = sized[color]
				var pool: Array = bands.rocks[band] if rocky else bands.woods[band]
				if pool.is_empty(): pool = bands.woods[band] if rocky else bands.rocks[band]
				if band == 0:
					# Big masses first: try every large prop before giving up.
					for attempt in ceili(pool.size() / 5.0):
						if _occupied[point.y * w + point.x] != 0 or _place_scenery(point, pool, fill, true): break
				else: _place_scenery(point, pool, fill, true)
	for i in w * h: _reserved[i] = maxi(_reserved[i], reserved[i])
	_scenery_paths = trails

## Stock masses are rounded blocks ten to twenty tiles across, parted by
## lanes two to four tiles wide. Seeds on a jittered grid split the land
## into cells; the border between two cells becomes a lane unless that
## border is closed, which leaves long walls and dead ends. Lanes widen
## into small yards where three cells meet. Snow is the most open ground,
## with open fields between its stands of pine, and the dark Chaot ground
## the tightest.
func _cell_lanes() -> PackedByteArray:
	var w := _map.width
	var h := _map.height
	var spacing := 24
	var columns := ceili(float(w) / spacing) + 1
	var rows := ceili(float(h) / spacing) + 1
	var seeds: Array[Vector2] = []
	for gy in rows:
		for gx in columns:
			var jitter := Vector2(_hash(gx, gy, 6353), _hash(gx, gy, 6359)) * 0.8 + Vector2.ONE * 0.1
			seeds.append((Vector2(gx, gy) - Vector2.ONE * 0.5 + jitter) * spacing)
	var lanes := PackedByteArray()
	lanes.resize(w * h)
	for y in h:
		for x in w:
			var warp := Vector2(_noise(x, y, 9.0, 6367) - 0.5, _noise(x, y, 9.0, 6373) - 0.5) * 6.0
			var at := Vector2(x, y) + warp
			var gx := floori(at.x / spacing + 0.5)
			var gy := floori(at.y / spacing + 0.5)
			var near: Array = [[INF, -1], [INF, -1], [INF, -1]]
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var cx := gx + ox
					var cy := gy + oy
					if cx < 0 or cy < 0 or cx >= columns or cy >= rows: continue
					var index := cy * columns + cx
					var d := at.distance_to(seeds[index])
					if d < near[0][0]: near = [[d, index], near[0], near[1]]
					elif d < near[1][0]: near = [near[0], [d, index], near[1]]
					elif d < near[2][0]: near[2] = [d, index]
			var ground := ELAdventureArt.terrain_color(_map.tile(x, y))
			var width: float = {"Blue": 4.6, "Green": 1.9, "Black": 1.6, "Red": 1.3}.get(ground, 1.9)
			# Stock snow is mostly open field with stands of pine.
			if ground == "Blue" and _noise(x, y, 7.0, 6401) > 0.58:
				lanes[y * w + x] = 1
				continue
			var a: int = mini(near[0][1], near[1][1])
			var b: int = maxi(near[0][1], near[1][1])
			var border: bool = near[1][0] - near[0][0] < width and _hash(a, b, 6379) >= 0.22
			var yard: bool = near[2][0] - near[0][0] < width * 1.4
			if border or yard: lanes[y * w + x] = 1
	return lanes

## Every pocket of open ground (a site apron, a creature, a yard behind
## closed borders) gets a lane two tiles wide to the nearest open ground
## joined to the first castle, before the masses are filled.
func _join_open_ground(open: PackedByteArray, land: PackedByteArray) -> void:
	var w := _map.width
	var h := _map.height
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	# Open ground joined to the first castle, 4-connected.
	var main := PackedByteArray()
	main.resize(w * h)
	var start := Vector2i(_starts[0].x, _starts[0].y)
	var queue: Array[Vector2i] = [start]
	main[start.y * w + start.x] = 1
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for step: Vector2i in steps:
			var next: Vector2i = at + step
			if not _inside(next): continue
			var i := next.y * w + next.x
			if main[i] != 0 or open[i] == 0 or land[i] == 0: continue
			main[i] = 1
			queue.append(next)
	# Noisy walking cost over land from that ground (so the new lanes
	# wind), then each other open cell walks downhill to it.
	var distance := PackedInt32Array()
	distance.resize(w * h)
	distance.fill(-1)
	var buckets: Array = [queue.duplicate()]
	for at: Vector2i in queue: distance[at.y * w + at.x] = 0
	var cost := 0
	while cost < buckets.size():
		var bucket: Array = buckets[cost]
		var k := 0
		while k < bucket.size():
			var at: Vector2i = bucket[k]
			k += 1
			if distance[at.y * w + at.x] != cost: continue
			for step: Vector2i in steps:
				var next: Vector2i = at + step
				if not _inside(next): continue
				var i := next.y * w + next.x
				if land[i] == 0: continue
				var total := cost + 1 + int(4.0 * _noise(next.x, next.y, 5.0, 6397))
				if distance[i] >= 0 and distance[i] <= total: continue
				distance[i] = total
				while buckets.size() <= total: buckets.append([])
				buckets[total].append(next)
		cost += 1
	var joined := main.duplicate()
	for y in h:
		for x in w:
			var i := y * w + x
			if open[i] == 0 or land[i] == 0 or joined[i] != 0 or distance[i] <= 0: continue
			var at := Vector2i(x, y)
			while distance[at.y * w + at.x] > 0:
				var index := at.y * w + at.x
				joined[index] = 1
				open[index] = 1
				var best := at
				for step: Vector2i in steps:
					var next: Vector2i = at + step
					if _inside(next) and distance[next.y * w + next.x] >= 0 and distance[next.y * w + next.x] < distance[best.y * w + best.x]: best = next
				if best == at: break
				at = best
				if joined[at.y * w + at.x] != 0: break

## Mass ground no larger prop fitted, and free ground the masses closed off
## from every lane, gets single-tile props: the masses stay solid, and the
## reconnection pass does not break a cliff to reach a sealed pocket.
func _fill_mass_gaps(land: PackedByteArray, open: PackedByteArray, fill: PackedByteArray) -> void:
	var w := _map.width
	var h := _map.height
	var rows := _profile.table("TerrObj")
	var lookup := {}
	for key: String in rows: lookup[key.to_lower()] = key
	var fillers := {}
	for color: String in STOCK_FILLERS:
		var found: Array[Dictionary] = []
		for name: String in STOCK_FILLERS[color]:
			var key: String = lookup.get(name.to_lower(), "")
			if key.is_empty() or not _model(rows[key]): continue
			var shape := ELAdventureGrid.footprint(rows[key], 0)
			if shape.size == Vector2i.ONE and not shape.cells.is_empty(): found.append({"name": key, "row": rows[key]})
		fillers[color] = found
	var reached := PackedByteArray()
	reached.resize(w * h)
	var queue: Array[Vector2i] = []
	for y in h:
		for x in w:
			var i := y * w + x
			if open[i] != 0 and land[i] != 0 and _occupied[i] == 0:
				reached[i] = 1
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = at + step
			if not _inside(next): continue
			var i := next.y * w + next.x
			if reached[i] != 0 or land[i] == 0 or _occupied[i] != 0: continue
			reached[i] = 1
			queue.append(next)
	for y in h:
		for x in w:
			var i := y * w + x
			if land[i] == 0 or _occupied[i] != 0 or (reached[i] != 0 and fill[i] == 0): continue
			if reached[i] != 0 and (_reserved[i] != 0 or _map.roads[i] != 0): continue
			if reached[i] != 0 and not _approach_clearings.is_empty() and _approach_clearings[i] != 0: continue
			var color := ELAdventureArt.terrain_color(_map.tile(x, y))
			var choices: Array = fillers.get(color, [])
			if choices.is_empty(): choices = fillers.get(_colors[_owner(Vector2i(x, y))], [])
			if choices.is_empty(): continue
			var entry: Dictionary = choices[_next(choices.size())]
			_place("terrain_objects", entry.name, Vector2i(x, y), entry.row, 0, "", [], {}, _next(4) * 4)

## The stock scenery mix for each ground, split by span into tiers: 8 and
## more, 6-7, 5, 3-4 and small props. Grounds whose props are missing
## from the content fall back to the family pools.
func _stock_scenery_mix() -> Dictionary:
	var rows := _profile.table("TerrObj")
	var lookup := {}
	for key: String in rows: lookup[key.to_lower()] = key
	var mixes := {}
	for color: String in STOCK_SCENERY:
		var bands: Array = [[], [], [], [], []]
		var found := 0
		for name: String in STOCK_SCENERY[color]:
			var key: String = lookup.get(name.to_lower(), "")
			if key.is_empty() or not _model(rows[key]): continue
			var shape := ELAdventureGrid.footprint(rows[key], 0)
			if shape.cells.is_empty(): continue
			var span := maxi(shape.size.x, shape.size.y)
			var lower := key.to_lower()
			var plant := ["tree", "forest", "bush", "pine"].any(func(word: String) -> bool: return lower.contains(word))
			bands[0 if span >= 8 else (1 if span >= 6 else (2 if span >= 5 else (3 if span >= 3 else 4)))].append({"name": key, "row": rows[key], "weight": int(STOCK_SCENERY[color][name]), "plant": plant})
			found += 1
		if found * 2 >= STOCK_SCENERY[color].size(): mixes[color] = bands
	return mixes

func _place_stock_prop(point: Vector2i, choices: Array, rocky: bool, fill: PackedByteArray, attempts: int) -> bool:
	var total := 0
	for entry: Dictionary in choices: total += _stock_weight(entry, rocky)
	if total <= 0: return false
	for attempt in attempts:
		var roll := _next(total)
		var entry: Dictionary = choices[0]
		for candidate: Dictionary in choices:
			roll -= _stock_weight(candidate, rocky)
			if roll < 0:
				entry = candidate
				break
		var rotation := _next(4) * 4
		var shape := ELAdventureGrid.footprint(entry.row, rotation)
		var origin: Vector2i = point - shape.size / 2
		if not _stock_prop_fits(origin, shape, fill): continue
		_place("terrain_objects", entry.name, origin, entry.row, 0, "", [], {}, rotation)
		return true
	return false

func _stock_weight(entry: Dictionary, rocky: bool) -> int:
	return int(entry.weight) * (1 if bool(entry.plant) == rocky else 4)

## Only the solid cells of a stock prop need free ground, so cliffs and
## trees interlock as they do in the original missions.
func _stock_prop_fits(origin: Vector2i, shape: Dictionary, fill: PackedByteArray) -> bool:
	var size: Vector2i = shape.size
	if origin.x < 0 or origin.y < 0 or origin.x + size.x > _map.width or origin.y + size.y > _map.height: return false
	var middle := Vector2(origin) + Vector2(size) * 0.5
	# Stock castles stand among cliffs; keep only their silhouette clear.
	var reach := 4.0 + maxi(size.x, size.y) * 0.6
	for anchor: Vector2i in _anchors:
		if middle.distance_to(Vector2(anchor)) < reach: return false
	for cell: Vector2i in shape.cells:
		var offset := (origin.y + cell.y) * _map.width + origin.x + cell.x
		if fill[offset] == 0 or _occupied[offset] != 0 or _reserved[offset] != 0: return false
		if _scenery_paths[offset] != 0 or _map.roads[offset] != 0: return false
		if not _approach_clearings.is_empty() and _approach_clearings[offset] != 0: return false
	return true

func _make_regional_scenery(land: PackedByteArray, pools: Dictionary) -> void:
	for color: String in COLORS:
		var pool: Dictionary = pools[color]
		var dry := color in ["Red", "Black"]
		var timber: Array = [] if dry else pool.canopy.filter(func(entry: Dictionary) -> bool:
			return not str(entry.name).to_lower().begins_with("blueel")
		)
		if timber.is_empty() and pool.stones.is_empty() and not dry: timber = pool.plants
		pool.groves = timber.filter(func(entry: Dictionary) -> bool:
			return ELAdventureGrid.footprint(entry.row, 0).size != Vector2i.ONE
		)
		pool.edge_trees = timber.filter(func(entry: Dictionary) -> bool:
			var size: Vector2i = ELAdventureGrid.footprint(entry.row, 0).size
			return size.x <= 2 and size.y <= 2
		)
		var plants: Array = pool.plants if dry else pool.brush
		var accent_size := 2 if dry else 1
		pool.accents = plants.filter(func(entry: Dictionary) -> bool:
			var size: Vector2i = ELAdventureGrid.footprint(entry.row, 0).size
			return size.x <= accent_size and size.y <= accent_size
		)
		pool.pebbles = pool.stones.filter(func(entry: Dictionary) -> bool:
			var size: Vector2i = ELAdventureGrid.footprint(entry.row, 0).size
			return size.x <= 2 and size.y <= 2
		)
	_place_regional_woods(land, pools)
	_scatter_ground_detail(land, pools)

func _place_regional_cliffs(land: PackedByteArray, pools: Dictionary) -> void:
	var dense: bool = config.scenery == 2
	for summit: Vector2i in _summits:
		var search := Rect2i(summit - Vector2i.ONE * 12, Vector2i.ONE * 25).intersection(Rect2i(2, 2, _map.width - 4, _map.height - 4))
		var candidates: Array[Dictionary] = []
		for y in range(search.position.y, search.end.y):
			for x in range(search.position.x, search.end.x):
				var offset := y * _map.width + x
				var crest := _uplands[y * (_map.width + 1) + x]
				if crest < 0.24 or land[offset] == 0 or _reserved[offset] != 0: continue
				var point := Vector2i(x, y)
				if not _clears_sites(point, 4): continue
				var score := crest + _hash(x, y, 7933) * 0.31
				candidates.append({"point": point, "score": score})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
		var silhouettes := 0
		for candidate: Dictionary in candidates:
			var point: Vector2i = candidate.point
			if not _place_scenery(point, _scenery_pool(point, pools).cliffs, land, true): continue
			silhouettes += 1
			if silhouettes >= (3 if dense else 2): break
		var outcrops := 0
		for candidate: Dictionary in candidates:
			var point: Vector2i = candidate.point
			if not _place_scenery(point, _scenery_pool(point, pools).landscape_rocks, land, true): continue
			outcrops += 1
			if outcrops >= (5 if dense else 4): break

func _place_regional_woods(land: PackedByteArray, pools: Dictionary) -> void:
	var dense: bool = config.scenery == 2
	var stride := _map.width + 1
	var interiors: Array[Vector2i] = []
	var edges: Array[Vector2i] = []
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			var offset := y * _map.width + x
			if land[offset] == 0 or _reserved[offset] != 0 or _corridor[offset] != 0: continue
			var field := y * stride + x
			if _uplands[field] > 0.53: continue
			var cover := _canopy[field]
			if _shore[field] >= 4 and _shore[field] <= 8: cover += 0.13
			var point := Vector2i(x, y)
			var pool := _scenery_pool(point, pools)
			var draw := _hash(x, y, 7951)
			if not pool.groves.is_empty() and cover > (0.46 if dense else 0.51) and draw < cover * (0.76 if dense else 0.57):
				interiors.append(point)
			elif not pool.edge_trees.is_empty() and cover > 0.35 and draw < (0.21 if dense else 0.15):
				edges.append(point)
	_shuffle(interiors)
	var margins := PackedByteArray()
	margins.resize(land.size())
	for point: Vector2i in interiors:
		if _place_scenery(point, _scenery_pool(point, pools).groves, land, true):
			_mark_radius(margins, point, 5)
	_shuffle(edges)
	for point: Vector2i in edges:
		var pool := _scenery_pool(point, pools)
		if margins[point.y * _map.width + point.x] == 0 and _hash(point.x, point.y, 7963) >= 0.24: continue
		_place_scenery(point, pool.edge_trees, land, true)

func _scatter_ground_detail(land: PackedByteArray, pools: Dictionary) -> void:
	var candidates: Array[Vector2i] = []
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			var offset := y * _map.width + x
			if land[offset] != 0 and _reserved[offset] == 0 and _hash(x, y, 7973) < 0.24:
				candidates.append(Vector2i(x, y))
	_shuffle(candidates)
	var spaced := PackedByteArray()
	spaced.resize(land.size())
	for point: Vector2i in candidates:
		var offset := point.y * _map.width + point.x
		if spaced[offset] != 0 or _reserved[offset] != 0: continue
		var field := point.y * (_map.width + 1) + point.x
		var color := ELAdventureArt.terrain_color(_map.tile(point.x, point.y))
		var draw := _hash(point.x, point.y, 7993)
		var rocky := _rock[field] > 0.17
		var shore := _shore[field] <= 4
		var dry := color in ["Red", "Black"]
		var pool := _scenery_pool(point, pools)
		var stone := rocky or (shore and draw < 0.45) or (color == "Blue" and draw < 0.27)
		var incidence := 0.82 if rocky else (0.43 if dry else 0.49)
		if config.scenery == 2: incidence *= 1.28
		if draw >= incidence: continue
		var moisture := 0.69 * _canopy[field] + 0.31 * _noise(point.x, point.y, 12.0, 8009)
		if dry and not stone and moisture < 0.29 and not shore: continue
		if _place_scenery(point, pool.pebbles if stone else pool.accents, land, true):
			var spacing := 2 if rocky else (4 if dry and not stone else 3)
			_mark_radius(spaced, point, spacing)

func _mark_radius(mask: PackedByteArray, point: Vector2i, radius: int) -> void:
	for y in range(maxi(0, point.y - radius), mini(_map.height - 1, point.y + radius) + 1):
		for x in range(maxi(0, point.x - radius), mini(_map.width - 1, point.x + radius) + 1):
			if point.distance_squared_to(Vector2i(x, y)) <= radius * radius: mask[y * _map.width + x] = 1

func _make_groves(land: PackedByteArray, pools: Dictionary) -> void:
	# A single landscape-wide field drives shape and scale. Place the ridge
	# silhouettes and large woodland groves before filling in the edges.
	var ground := _map.width + 1
	var density := 1.28 if config.scenery == 2 else 1.0
	var occupied_ridges: Array[Vector2i] = []
	var hills: Array[Vector2i] = []
	var canopy: Array[Vector2i] = []
	var details: Array[Vector2i] = []
	var shoulders: Array[Vector2i] = []
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			var cell := y * _map.width + x
			if land[cell] == 0 or _reserved[cell] != 0: continue
			var point := Vector2i(x, y)
			var cover := _canopy[y * ground + x]
			var form := _landform(point)
			var draw := _hash(x, y, 6143)
			if _corridor[cell] != 0:
				if _map.roads[cell] == 0 and draw < (0.05 + cover * 0.12) * density: shoulders.append(point)
				continue
			if form == Landform.RIDGE and draw < 0.13: hills.append(point)
			if cover > 0.32 and draw < cover * 0.62 * density: canopy.append(point)
			if _hash(x, y, 8179) < (0.25 if form == Landform.RIDGE else 0.12 + cover * 0.22) * density:
				details.append(point)
	_shuffle(hills)
	for point: Vector2i in hills:
		if occupied_ridges.any(func(other: Vector2i) -> bool: return point.distance_squared_to(other) < 11 * 11): continue
		var pool := _scenery_pool(point, pools)
		var high_ridge: bool = config.version < RELIEF_VERSION or _relief[point.y * ground + point.x] > 0.62
		if high_ridge and _place_scenery(point, pool.cliffs, land):
			occupied_ridges.append(point)
			_extend_ridge(point, pool.landscape_rocks, land)
		elif _place_scenery(point, pool.landscape_rocks, land): occupied_ridges.append(point)
	_shuffle(canopy)
	for point: Vector2i in canopy:
		var pool := _scenery_pool(point, pools)
		if not _place_scenery(point, pool.groves, land):
			if not _place_scenery(point, pool.canopy, land) and pool.canopy.is_empty(): _place_scenery(point, pool.plants, land)
	_dress_wilderness_sites(land, pools)
	_shuffle(details)
	for point: Vector2i in details:
		var pool := _scenery_pool(point, pools)
		var rocky := _landform(point) == Landform.RIDGE
		var choice: Array = pool.stones if rocky else pool.brush
		if not _place_scenery(point, choice, land): _place_scenery_detail(point, pools, land, rocky)
	for point: Vector2i in shoulders:
		var plants: Array = _scenery_pool(point, pools).undergrowth
		if plants.is_empty() or _reserved[point.y * _map.width + point.x] != 0: continue
		var grass: Dictionary = plants[_next(plants.size())]
		_place("terrain_objects", grass.name, point, grass.row, 0, "", [], {}, _next(4) * 4)

func _fill_scenery_between_groves(land: PackedByteArray, pools: Dictionary) -> void:
	# Cluster smaller trees around the big groves and dress the road
	# shoulders, including the foreground between nearby strategic sites.
	# The route and harbor masks still apply to every blocking footprint.
	for color: String in COLORS:
		var pool: Dictionary = pools[color]
		var trees: Array = pool.canopy if not pool.canopy.is_empty() else pool.plants
		pool.small_trees = trees.filter(func(entry: Dictionary) -> bool:
			var size: Vector2i = ELAdventureGrid.footprint(entry.row, 0).size
			return maxi(size.x, size.y) <= 2
		)
	var candidates: Array[Dictionary] = []
	var verges := PackedByteArray()
	verges.resize(land.size())
	for index in _map.roads.size():
		if _map.roads[index] == 0: continue
		var road := Vector2i(index % _map.width, index / _map.width)
		for y in range(maxi(2, road.y - 3), mini(_map.height - 2, road.y + 4)):
			for x in range(maxi(2, road.x - 3), mini(_map.width - 2, road.x + 4)):
				verges[y * _map.width + x] = 1
	var density := 0.24 if config.scenery == 2 else 0.16
	var remaining := roundi(land.count(1) * density)
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			var offset := y * _map.width + x
			if land[offset] == 0 or _reserved[offset] != 0 or _scenery_paths[offset] != 0 or _map.roads[offset] != 0: continue
			var point := Vector2i(x, y)
			var cover := _canopy[y * (_map.width + 1) + x]
			var grove := _noise(x, y, 8.0, 1739)
			var draw := _hash(x, y, 3929)
			var score := 0.37 * cover + 0.40 * grove + 0.32 * draw + (0.28 if verges[offset] else 0.0)
			if score < (0.24 if config.scenery == 2 else 0.32): continue
			candidates.append({"point": point, "score": score, "stone": draw < (0.44 if _landform(point) == Landform.RIDGE else 0.15)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	for candidate: Dictionary in candidates:
		if remaining <= 0: break
		var point: Vector2i = candidate.point
		if _reserved[point.y * _map.width + point.x] != 0: continue
		var pool := _scenery_pool(point, pools)
		var primary: Array = pool.stones if candidate.stone else pool.small_trees
		var secondary: Array = pool.small_trees if candidate.stone else pool.brush
		if _place_scenery(point, primary, land, true) or _place_scenery(point, secondary, land, true): remaining -= 1

func _dress_wilderness_sites(land: PackedByteArray, pools: Dictionary) -> void:
	var sites := _map.objects.filter(func(item: Dictionary) -> bool: return item.group == "additional_buildings")
	for site: Dictionary in sites:
		var natural: bool = site.name in ELAdditionalBuildings.WEEKLY_VISITED or site.name in [ELAdditionalBuildings.LAKE, ELAdditionalBuildings.BOWL]
		var ruined: bool = ELAdditionalBuildings.DUNGEONS.has(site.name) or site.name in ELAdditionalBuildings.OWNED
		if not natural and not ruined: continue
		var center := Vector2i(site.x, site.y)
		var phase := TAU * _hash(center.x, center.y, 2017)
		var ornaments := 0
		# Extend the local vegetation or rock around the back of the site.
		# The reserved approach remains a usable clearing.
		for step in 8:
			var angle := phase + TAU * (step % 4) * 0.078
			var point := center + Vector2i((Vector2.from_angle(angle) * (3.0 + step / 4 * 2.0)).round())
			if not _inside(point): continue
			var pool := _scenery_pool(point, pools)
			var edge: Array = pool.canopy if natural and ornaments == 0 else (pool.brush if natural else pool.stones)
			if _place_scenery(point, edge, land): ornaments += 1
			if ornaments >= 2: break

func _extend_ridge(peak: Vector2i, stones: Array, land: PackedByteArray) -> void:
	if stones.is_empty(): return
	var landmark: Dictionary = _map.objects[-1]
	var row: Dictionary = _profile.table("TerrObj")[landmark.name]
	var box := Rect2i(int(landmark.x), int(landmark.y), 0, 0)
	box.size = ELAdventureGrid.footprint(row, int(landmark.rotation)).size
	var border := box.grow(3).intersection(Rect2i(2, 2, _map.width - 4, _map.height - 4))
	var candidates: Array[Dictionary] = []
	for y in range(border.position.y, border.end.y):
		for x in range(border.position.x, border.end.x):
			var at := Vector2i(x, y)
			if box.has_point(at) or land[y * _map.width + x] == 0: continue
			var rock := _rock[y * (_map.width + 1) + x]
			if rock < 0.30: continue
			candidates.append({"at": at, "grade": rock + _hash(x, y, 1741) * 0.17})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.grade) > float(b.grade))
	var last := Vector2.ZERO
	for candidate: Dictionary in candidates:
		var direction := (Vector2(candidate.at) - Vector2(peak)).normalized()
		if last.dot(direction) > 0.45 or not _place_scenery(candidate.at, stones, land): continue
		if last != Vector2.ZERO: break
		last = direction

func _make_scenery_patch(area: Rect2i, land: PackedByteArray, pools: Dictionary) -> void:
	var points: Array[Vector2i] = []
	var dry := 0
	var cover := 0.0
	for y in range(area.position.y, mini(area.end.y, _map.height - 2)):
		for x in range(area.position.x, mini(area.end.x, _map.width - 2)):
			var offset := y * _map.width + x
			if land[offset] == 0: continue
			dry += 1
			if config.version >= LANDSCAPE_VERSION: cover += [0.085, 0.23, 0.155][_landform(Vector2i(x, y))]
			if _reserved[offset] == 0 and _corridor[offset] == 0: points.append(Vector2i(x, y))
	if points.is_empty() or dry < 4: return
	_shuffle(points)
	if config.version >= LANDSCAPE_VERSION:
		_dress_landscape(points, land, pools, maxi(1, roundi(cover * (1.27 if config.scenery == 2 else 1.0))))
		return
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

func _dress_landscape(points: Array[Vector2i], land: PackedByteArray, pools: Dictionary, remaining: int) -> void:
	var ridge: Array[Vector2i] = []
	for point: Vector2i in points:
		if _landform(point) == Landform.RIDGE: ridge.append(point)
	# Tall rocks mark the continuous ridges. Dense woods use the original
	# multi-tree models, while meadows keep scattered brush and stones.
	if ridge.size() >= 16:
		for point: Vector2i in ridge:
			if _place_scenery(point, _scenery_pool(point, pools).landmarks, land):
				remaining -= 1
				break
	for point: Vector2i in points:
		if remaining <= 0: break
		var form := _landform(point)
		if _hash(point.x, point.y, 6143) > [0.43, 0.94, 0.74][form]: continue
		var pool := _scenery_pool(point, pools)
		var detail: Array = [pool.brush, pool.canopy, pool.stones][form]
		if _place_scenery(point, detail, land) or _place_scenery_detail(point, pools, land, form == Landform.RIDGE): remaining -= 1

func _scenery_pool(point: Vector2i, pools: Dictionary) -> Dictionary:
	var color := ELAdventureArt.terrain_color(_map.tile(point.x, point.y))
	return pools[color] if pools.has(color) else pools[_colors[_owner(point)]]

func _place_scenery_detail(point: Vector2i, pools: Dictionary, land: PackedByteArray, rocky: bool) -> bool:
	var pool := _scenery_pool(point, pools)
	var primary: Array = pool.stones if rocky else pool.plants
	var secondary: Array = pool.plants if rocky else pool.stones
	return _place_scenery(point, primary, land) or _place_scenery(point, secondary, land)

func _place_scenery(point: Vector2i, pool: Array, land: PackedByteArray, allow_verges := false) -> bool:
	if pool.is_empty(): return false
	var first := _next(pool.size())
	var rotation := _next(4) * 4
	for attempt in mini(pool.size(), 5):
		var entry: Dictionary = pool[(first + attempt) % pool.size()]
		var size: Vector2i = ELAdventureGrid.footprint(entry.row, rotation).size
		var origin := point - size / 2
		if not _scenery_fits(origin, size, land, allow_verges): continue
		_place("terrain_objects", entry.name, origin, entry.row, 0, "", [], {}, rotation)
		return true
	return false

func _scenery_fits(origin: Vector2i, size: Vector2i, land: PackedByteArray, allow_verges := false) -> bool:
	# Stock woods run to the map's edge; earlier versions kept a clear rim.
	var rim := 0 if config.version >= STOCK_LAYOUT_VERSION else 2
	if origin.x < rim or origin.y < rim or origin.x + size.x > _map.width - rim or origin.y + size.y > _map.height - rim: return false
	if config.version >= LIVING_WILDS_VERSION:
		# Mesas and boulders read much larger than their footprint. Keep the
		# castle's silhouette clear, more so for bigger props.
		var middle := Vector2(origin) + Vector2(size) * 0.5
		var reach := 1.5 + 2.0 * maxi(size.x, size.y)
		# Version 13 woods close in around the castle like the stock yards.
		if config.version >= STOCK_LAYOUT_VERSION: reach = 1.5 + maxi(size.x, size.y) * (2.0 if maxi(size.x, size.y) >= 5 else 0.8)
		for anchor: Vector2i in _anchors:
			if middle.distance_to(Vector2(anchor)) < reach + 2.5: return false
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var offset := y * _map.width + x
			if land[offset] == 0 or _reserved[offset] != 0: return false
			if not _approach_clearings.is_empty() and _approach_clearings[offset] != 0: return false
			if allow_verges:
				if _scenery_paths[offset] != 0 or _map.roads[offset] != 0: return false
			elif _corridor[offset] != 0: return false
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
	if not _site_clearance.is_empty() and group not in ["heroes", "np_heroes", "terrain_objects"]:
		_mark_site_clearance(Rect2i(position, size))
	# Original groves combine adjacent terrain props. Sites and legacy maps
	# keep their one-cell placement margin.
	var margin := 0 if group == "terrain_objects" and config.version >= SCENERY_VERSION else 1
	if group == "terrain_objects" and config.version >= STOCK_LAYOUT_VERSION:
		# Version 13 props hold only their solid cells, so they can interlock.
		for cell: Vector2i in ELAdventureGrid.footprint(row, rotation).cells:
			var at := position + cell
			if not _inside(at): continue
			_reserved[at.y * _map.width + at.x] = 1
			_occupied[at.y * _map.width + at.x] = 1
			_trail_stale = true
			if _route_grid.region.has_point(at):
				_route_grid.set_point_solid(at, true)
				_port_routes.clear()
		return item
	for y in range(position.y - margin, position.y + size.y + margin):
		for x in range(position.x - margin, position.x + size.x + margin):
			if not _inside(Vector2i(x, y)): continue
			_reserved[y * _map.width + x] = 1
			if x >= position.x and x < position.x + size.x and y >= position.y and y < position.y + size.y:
				_occupied[y * _map.width + x] = 1
				_trail_stale = true
				if _route_grid.region.has_point(Vector2i(x, y)):
					_route_grid.set_point_solid(Vector2i(x, y), true)
					_port_routes.clear()
	return item

func _mark_site_clearance(footprint: Rect2i) -> void:
	var area := footprint.grow(FRONTIER_SITE_GAP).intersection(Rect2i(0, 0, _map.width, _map.height))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var dx := maxi(0, maxi(footprint.position.x - x, x - footprint.end.x + 1))
			var dy := maxi(0, maxi(footprint.position.y - y, y - footprint.end.y + 1))
			var offset := y * _map.width + x
			_site_clearance[offset] = mini(_site_clearance[offset], maxi(dx, dy))

func _clears_sites(point: Vector2i, gap: int) -> bool:
	return gap <= 0 or (_inside(point) and _site_clearance[point.y * _map.width + point.x] >= gap)

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
	return not config.naval or _ports.is_empty() or not _port_route(at).is_empty()

func _port_route(at: Vector2i) -> Array[Vector2i]:
	if _port_routes.has(at): return _port_routes[at]
	var path := _find_port_route(at)
	_port_routes[at] = path
	return path

func _find_port_route(at: Vector2i) -> Array[Vector2i]:
	var sources: Array[Dictionary] = []
	var region := _region_at(at)
	for port: Dictionary in _ports:
		if int(port.island) != region: continue
		var source := Vector2i(port.land[0], port.land[1])
		sources.append({"point": source, "distance": source.distance_squared_to(at)})
	sources.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.distance) < float(b.distance))
	for source: Dictionary in sources:
		var path := _route_grid.get_id_path(source.point, at)
		if not path.is_empty(): return path
	return []

func _find_spot(near: Vector2i, size: Vector2i, radius: int, home: int, require_land: bool, avoid_roads: bool, expedition := false, region := -1, gap := 0) -> Vector2i:
	# Deterministic expanding rings preserve the desired strategic distance.
	var turn := _next(4)
	for distance in range(radius + 1):
		for edge in 4:
			for step in range(-distance, distance + 1):
				var delta := Vector2i(step, -distance)
				for rotation in (edge + turn) % 4: delta = Vector2i(-delta.y, delta.x)
				var point := near + delta
				if not _clears_sites(point + size / 2, gap): continue
				if not expedition and not _outlying_regions.is_empty() and _outlying_regions.has(_region_at(point + size / 2)): continue
				if home >= 0 and _owner(point + size / 2) != home: continue
				if config.naval and home >= 0 and _region_at(point + size / 2) != _region_at(_anchors[home]): continue
				if region >= 0 and _region_at(point + size / 2) != region: continue
				if not _fits(point, size, require_land, avoid_roads): continue
				if expedition and _expedition_trail(Rect2i(point, size)) < 0: continue
				return point
	return NO_SPOT

func _paint_disk(center: Vector2i, radius: int, road: bool, trunk := false, track := false) -> void:
	for y in range(maxi(0, center.y - radius), mini(_map.height, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(_map.width, center.x + radius) + 1):
			if Vector2i(x, y).distance_squared_to(center) > radius * radius: continue
			var tile := _map.tile(x, y)
			if config.version >= WILDERNESS_VERSION and tile != _water: continue
			if not config.naval or tile != 16: _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))
	if road and _inside(center) and config.roads:
		var index := center.y * _map.width + center.x
		var grade := 6 if trunk and config.version >= WILDERNESS_VERSION else (7 if track else 5)
		var current := _map.roads[index]
		if current == 0 or grade == 6 or (grade == 5 and current == 7): _map.roads[index] = grade

func _clear_footprint(at: Vector2i, size: Vector2i) -> void:
	for y in range(at.y - 2, at.y + size.y + 3):
		for x in range(at.x - 2, at.x + size.x + 3):
			if x < 0 or y < 0 or x > _map.width or y > _map.height: continue
			var tile := _map.tile(x, y)
			if config.version >= WILDERNESS_VERSION and tile != _water: continue
			if not config.naval or tile != 16: _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))

func _connect(from: Vector2i, to: Vector2i, width: int, road: bool, trunk := false, track := false, guard_route := true) -> bool:
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
	if from_solid or to_solid: _port_routes.clear()
	if not _scenery_paths.is_empty():
		var previous := from
		for at: Vector2i in path:
			_scenery_paths[at.y * _map.width + at.x] = 1
			if config.naval and at.x != previous.x and at.y != previous.y:
				_scenery_paths[at.y * _map.width + previous.x] = 1
				_scenery_paths[previous.y * _map.width + at.x] = 1
			previous = at
	var corners := _road_corners(path) if config.version >= LIVING_WILDS_VERSION else {}
	for point: Vector2i in path:
		var offset := point.y * _map.width + point.x
		if guard_route and _network[offset] == 0:
			_network[offset] = 1
			_network_points.append(point)
		_paint_disk(point, width + 1, road and not corners.has(point), trunk, track and _walkable(point))
		# Later routes share an existing road instead of running a parallel
		# track beside it and closing a small loop.
		if road and config.version >= STOCK_LAYOUT_VERSION and _route_grid.region.has_point(point):
			_route_grid.set_point_weight_scale(point, 0.25)
		for y in range(maxi(0, point.y - width), mini(_map.height, point.y + width + 1)):
			for x in range(maxi(0, point.x - width), mini(_map.width, point.x + width + 1)):
				var cell := y * _map.width + x
				_corridor[cell] = 1
				if guard_route and not _guard_safe.is_empty(): _guard_safe[cell] = 1
	return not path.is_empty()

## Cells where a grid path turns through an L between two diagonal
## neighbors. Leaving them unpaved lets the road run diagonally instead of
## climbing a staircase. Alternate cells only, so the road stays joined, and
## only where both sides of the diagonal are dry land.
func _road_corners(path: Array[Vector2i]) -> Dictionary:
	var corners := {}
	var index := 1
	while index < path.size() - 1:
		var before := path[index - 1]
		var after := path[index + 1]
		var turn := after - before
		if absi(turn.x) == 1 and absi(turn.y) == 1:
			var other := before + after - path[index]
			if _walkable(other) and _walkable(path[index]):
				corners[path[index]] = true
				index += 2
				continue
		index += 1
	return corners

func _connect_site(from: Vector2i, item: Dictionary, size: Vector2i, road := true, guard_route := true) -> void:
	var approaches: Array[Dictionary] = []
	var track: bool = config.version >= RELIEF_VERSION and item.group in ["resource_cuts", "artefacts", "global_spells"]
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
		if _connect(junction, approach, 1, road and config.roads, false, track, guard_route): return
	# Ports are an authoritative connected backbone even if a newly placed
	# object divided a thin island and its geometric center is on the far side.
	if config.naval:
		for entry: Dictionary in approaches:
			for port: Dictionary in _ports:
				if int(port.island) != _region_at(entry.point): continue
				if _connect(Vector2i(port.land[0], port.land[1]), entry.point, 1, road and config.roads, false, track, guard_route): return

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

func _navigation_objects(include_actors := true) -> Dictionary:
	var objects := {}
	for item: Dictionary in _map.objects:
		var copy := item.duplicate()
		copy.uid = int(item.permanent_id) - 1
		copy.alive = true
		copy.visible = true
		copy.placed = include_actors or item.group not in ["heroes", "np_heroes"]
		copy.level = 0
		copy.type = ("monster" if item.group == "np_heroes" else "hero") if item.group in ["heroes", "np_heroes"] else "object"
		objects[copy.uid] = copy
	return objects

func _reconnect_landscape(first_decoration: int, cliff_ids: Vector2i) -> bool:
	var objects := _navigation_objects(false)
	var grid := ELAdventureGrid.new()
	if not grid.build(_map, objects):
		error = grid.error
		return false
	var props := {}
	var actors := {}
	for id: int in objects:
		var item: Dictionary = objects[id]
		var at := Vector2i(item.x, item.y)
		var permanent_id := int(item.permanent_id)
		var scenic_cliff := permanent_id >= cliff_ids.x and permanent_id < cliff_ids.y
		if item.group == "terrain_objects" and (permanent_id >= first_decoration or scenic_cliff): props[id] = at
		if item.type in ["hero", "monster"]: actors[at] = true
	var ports_before := _ports.size()
	var start := Vector2i(_starts[0].x, _starts[0].y)
	var reach: Dictionary = Reachability.new().repair(grid, start, props, actors, _widen_land_connection, _add_repair_landing)
	if reach.has("error"):
		error = str(reach.error)
		return false
	var removed: Dictionary = reach.removed
	if not removed.is_empty():
		_map.objects = _map.objects.filter(func(item: Dictionary) -> bool: return not removed.has(int(item.permanent_id) - 1))
	if _ports.size() > ports_before: _publish_harbors()
	report.connected_passable_cells = reach.passable
	report.reopened_connections = reach.connections
	return true

## Version 13: a diagonal step between two cells blocked by objects or
## impassable ground. The game allows it, but among dense props it reads as
## walking through a wall, so the generator does not count it as a way in.
## A road drawn across the corner shows the way and still counts.
func _corner_gap(grid: ELAdventureGrid, at: Vector2i, next: Vector2i) -> bool:
	if not _strict_corners or at.x == next.x or at.y == next.y: return false
	if _map.roads[_index(at)] != 0 and _map.roads[_index(next)] != 0: return false
	return _corner_blocked(grid, Vector2i(next.x, at.y)) and _corner_blocked(grid, Vector2i(at.x, next.y))

func _corner_blocked(grid: ELAdventureGrid, cell: Vector2i) -> bool:
	var index := _index(cell)
	return grid.blockers[index] > 0 or (grid.land.is_point_solid(cell) and grid.actor_blockers[index] == 0)

## Version 13: open land that the woods leave reachable only through a
## diagonal gap between two objects. Remove the smaller generated prop at
## each such gap until every pocket has a visible way in.
func _open_corner_gaps(first_decoration: int, cliff_ids: Vector2i) -> bool:
	_strict_corners = true
	var opened := 0
	for round in 32:
		var objects := _navigation_objects(false)
		var grid := ELAdventureGrid.new()
		if not grid.build(_map, objects):
			error = grid.error
			return false
		var owner := {}
		var area := {}
		for id: int in objects:
			var item: Dictionary = objects[id]
			var permanent_id := int(item.permanent_id)
			if item.group != "terrain_objects" or not (permanent_id >= first_decoration or (permanent_id >= cliff_ids.x and permanent_id < cliff_ids.y)): continue
			var cells: Array = grid.footprints.get(id, {}).get("cells", [])
			area[permanent_id] = cells.size()
			for cell: Vector2i in cells:
				var point := cell + Vector2i(item.x, item.y)
				if grid.contains(point): owner[_index(point)] = permanent_id
		var first := Vector2i(_starts[0].x, _starts[0].y)
		var reached := PackedByteArray()
		reached.resize(_map.width * _map.height)
		reached[_index(first)] = 1
		var queue: Array[Vector2i] = [first]
		var head := 0
		while head < queue.size():
			var at := queue[head]
			head += 1
			for delta: Vector2i in ELInterception.DIRECTIONS:
				var next := at + delta
				if not grid.contains(next) or reached[_index(next)] != 0 or grid.land.is_point_solid(next): continue
				if config.naval and not ELFirstNaval.connected(grid, at, next, true, true): continue
				if _corner_gap(grid, at, next): continue
				reached[_index(next)] = 1
				queue.append(next)
		var removed := {}
		for at: Vector2i in queue:
			if config.naval and _sea_cell(at): continue
			for delta: Vector2i in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var next := at + delta
				if not grid.contains(next) or reached[_index(next)] != 0 or grid.land.is_point_solid(next): continue
				if config.naval and _sea_cell(next): continue
				if not _corner_gap(grid, at, next): continue
				var a: int = owner.get(_index(Vector2i(next.x, at.y)), -1)
				var b: int = owner.get(_index(Vector2i(at.x, next.y)), -1)
				if (a < 0 and b < 0) or removed.has(a) or removed.has(b): continue
				removed[a if b < 0 or (a >= 0 and int(area[a]) <= int(area[b])) else b] = true
		if removed.is_empty(): break
		opened += removed.size()
		_map.objects = _map.objects.filter(func(item: Dictionary) -> bool: return not removed.has(int(item.permanent_id)))
	_strict_corners = false
	report.opened_corner_gaps = opened
	# Recount the joined ground with the freed cells.
	return opened == 0 or _reconnect_landscape(first_decoration, cliff_ids)

func _widen_land_connection(at: Vector2i) -> void:
	for y in range(at.y, at.y + 2):
		for x in range(at.x, at.x + 2):
			if int(_profile.terrain_tiles.types.get(_map.tile(x, y), {}).get("movement", -1)) >= 0: continue
			_map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y), true)

func _add_repair_landing(land: Vector2i, water: Vector2i) -> void:
	_register_port(land, water, _region_at(land), 0)

func _check_access(protect_routes := false, enforce_daily := false) -> bool:
	var objects := _navigation_objects()
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
		previous.fill(-2)
		previous[first.y * _map.width + first.x] = -1
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
				if _corner_gap(grid, at, next): continue
				reached[offset] = 1
				if protect_routes: previous[offset] = at.y * _map.width + at.x
				queue.append(next)
	var targets: Array[int] = _important.duplicate()
	var opening := {}
	for start: Dictionary in _starts:
		targets.append(int(start.castle_id))
		targets.append(int(start.hero_id))
		if not _guard_safe.is_empty():
			for id: int in start.sites + start.rewards: opening[id] = true
			if config.version >= GUARD_POSTS_VERSION and start.has("opening_lair"): opening[start.opening_lair] = true
	for id: int in targets:
		var item: Dictionary = objects[id]
		var safe: bool = not _guard_safe.is_empty() and (id in opening or item.group in ["buildings", "heroes", "forts"])
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
				if protect_routes and safe: _guard_safe[offset] = 1
				var cost := first.distance_squared_to(point)
				if cost < distance:
					distance = cost
					approach = offset
		if approach < 0:
			error = "Generated map contains an unreachable %s (%d). Try a different seed." % [str(item.group), id]
			_unreached = Vector2i(item.x, item.y)
			return false
		if protect_routes: _protect_route(approach, previous, safe)
	if config.naval:
		for port: Dictionary in _ports:
			for key: String in ["land", "water"]:
				var point := Vector2i(port[key][0], port[key][1])
				var offset := point.y * _map.width + point.x
				if reached[offset] == 0:
					error = "A harbor is disconnected from the playable travel network."
					return false
				if protect_routes: _protect_route(offset, previous, not _guard_safe.is_empty())
	for start: Dictionary in _starts: start.reachable_sites = _important.size()
	if protect_routes and config.version >= LANDSCAPE_VERSION:
		_exploration_access = previous
		_trail_stale = true
	if not protect_routes and not _gated_prizes.is_empty(): _verify_gated_prizes(grid, objects, reached)
	report.reachable = true
	report.reachable_cells = queue.size()
	return not enforce_daily or _fill_daily_gaps(grid, objects, reached)

func _verify_gated_prizes(grid: ELAdventureGrid, objects: Dictionary, reached: PackedByteArray) -> void:
	for id: int in _gated_prizes.keys():
		var prize: Dictionary = objects[id]
		var guard: Dictionary = objects[_gated_prizes[id]]
		var body := Rect2i(Vector2i(prize.x, prize.y), grid.footprints[id].size)
		var zone := ELInterception.flood(grid, Vector2i(guard.x, guard.y), 2)
		var reach := false
		var shortcut := false
		var ring := body.grow(1)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				var at := Vector2i(x, y)
				if body.has_point(at) or not grid.contains(at) or grid.passability(at) < 1: continue
				var offset := y * _map.width + x
				if grid.naval and grid.naval_water[offset] != 0: continue
				shortcut = shortcut or at not in zone
				reach = reach or reached[offset] != 0
		if shortcut or not reach: _gated_prizes.erase(id)

func _fill_daily_gaps(grid: ELAdventureGrid, objects: Dictionary, reached: PackedByteArray) -> bool:
	var day := 100000
	for start: Dictionary in _starts:
		var hero: Dictionary = objects[start.hero_id].duplicate()
		var name: String = hero.name
		day = mini(day, int(_profile.table("HeroTemplates")[name].Sight))
		# Include the tile beneath each starting hero in the survey.
		reached[hero.y * _map.width + hero.x] = 1
		hero.placed = false
		grid.update_actor(hero)
	var coverage := DailyCoverage.new()
	var budget := day + day / 2 if config.version >= GUARDED_PRIZES_VERSION else day
	coverage.build(_map, grid, objects, reached, budget, config.version >= GUARDED_PRIZES_VERSION)
	var cache_models: Array[String] = []
	for name: String in _keys(_catalog.cuts):
		if ELAdventureGrid.footprint(_catalog.cuts[name], 0).size == Vector2i.ONE: cache_models.append(name)
	var added := 0
	for index in coverage.distance.size():
		if coverage.costs[index] < 1 or coverage.distance[index] <= budget: continue
		if cache_models.is_empty():
			error = "The installed map objects have no small resource cache for a remote land area."
			return false
		var gap := Vector2i(index % _map.width, index / _map.width)
		var pos := gap
		var score := -INF
		for direction: Vector2i in [Vector2i.ZERO] + ELFirstNaval.DIRECTIONS:
			var at := gap + direction
			if not _inside(at): continue
			var offset := at.y * _map.width + at.x
			if coverage.costs[offset] < 1: continue
			var value := _hash(at.x, at.y, 5521) - float(_occupied[offset]) * 4.0 - float(_map.roads[offset] != 0) * 2.0
			if value <= score: continue
			score = value
			pos = at
		var name := cache_models[_next(cache_models.size())]
		var resource: String = ["Root", "Lotus", "Stone"][_next(3)]
		var amount := 3 if config.resources == "scarce" else (8 if config.resources == "rich" else 5)
		var nodes := [_node("resources", {}, "", [_node("resource", {"type": resource, "amount": str(amount)})])]
		var cache := _place("resource_cuts", name, pos, _catalog.cuts[name], 0, "", nodes, {"trail_cache": "1"})
		coverage.add_cache(cache)
		if coverage.distance[index] > budget:
			error = "A resource cache could not cover the route from %s." % str(gap)
			return false
		added += 1
	report.daily_travel_ap = day
	if config.version >= GUARDED_PRIZES_VERSION: report.wilderness_travel_ap = budget
	report.daily_caches = added
	return true

func _protect_route(offset: int, previous: PackedInt32Array, guard_safe := false) -> void:
	while offset >= 0:
		_corridor[offset] = 1
		if not _scenery_paths.is_empty(): _scenery_paths[offset] = 1
		if guard_safe: _guard_safe[offset] = 1
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
				if not _scenery_paths.is_empty():
					_scenery_paths[y * _map.width + parent_x] = 1
					_scenery_paths[parent_y * _map.width + x] = 1
				if guard_safe:
					_guard_safe[y * _map.width + parent_x] = 1
					_guard_safe[parent_y * _map.width + x] = 1
		offset = parent
