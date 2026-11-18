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
const STARTER_ENCOUNTERS := ["Carnivorous Fingus", "Lesser Bee Hive", "Mech Worm", "River Halo", "Small Velos"]
const JOURNEY_ENCOUNTERS := ["OrcShaman", "Sea Halo"]
const WILDERNESS_ENCOUNTERS := ["Giant Fingus", "OrcGuard", "Small Bee Hive", "Mech Wyrm"]
const FRONTIER_ENCOUNTERS := ["Small Tick Hive", "Gibberling Gang", "Medium Bee Hive"]
const STARTER_LAIR := "Starter encounter"
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
var _exploration_access := PackedInt32Array()
var _outlying_regions := {}
var _guard_queue: Array[Dictionary] = []
var _home_lairs: Array[Dictionary] = []

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
	if result.version < VERSION or result.version > WILDERNESS_VERSION or result.size not in SIZES or result.players < 2 or result.players > 4 or result.scenery < 0 or result.scenery > 2 or result.castle_health not in [20, 30, 60]: return {}
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
	if config.version >= LANDSCAPE_VERSION:
		_build_landscape()
		_add_outlying_islands()
	_make_terrain()
	if config.naval and not _prepare_naval_terrain(): return null
	if config.version >= LANDSCAPE_VERSION: _weight_landscape_routes()
	if not _make_players(): return null
	if config.naval and not _make_ports(): return null
	_make_routes()
	if not _make_homelands(): return null
	if not _make_frontiers(): return null
	if config.naval: _populate_islands()
	if config.version >= LANDSCAPE_VERSION:
		if not _check_access(true): return null
		_make_exploration_sites()
	if config.version >= WILDERNESS_VERSION and config.guards != "none":
		_make_encounters()
		if not _check_access(true): return null
	if config.scenery > 0:
		if config.version == VERSION:
			_make_legacy_scenery()
		else:
			# Keep a route to every strategic target before adding blockers.
			if config.version == SCENERY_VERSION and not _check_access(true): return null
			_make_scenery()
	if not _check_terrain(): return null
	if not _check_access(): return null
	if config.version >= WILDERNESS_VERSION: _paint_wilderness_detail()
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
				_canopy[index] = smoothstep(0.37, 0.73, undergrowth) * (1.0 - rock * 0.65)
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

func _landform(point: Vector2i) -> int:
	return _landscape[point.y * (_map.width + 1) + point.x]

func _ground(point: Vector2i, varied := false) -> int:
	var color := str(config.biome)
	if color == "mixed":
		var sample := point
		if config.version >= LANDSCAPE_VERSION and varied:
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
		return native if native in choices else int(choices[mini(form, choices.size() - 1)])
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

func _water_field(point: Vector2i) -> bool:
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
	for island: Dictionary in _reward_centers:
		if not island.get("outlying", false): continue
		var region := _region_at(Vector2i(island.point))
		if region >= 0: _outlying_regions[region] = true
	return true

func _weight_landscape_routes() -> void:
	# Roads gravitate to clear valley floors and only use causeways when
	# necessary. The weights shape placement, not the cost of hero movement.
	for y in range(1, _map.height - 1):
		for x in range(1, _map.width - 1):
			var point := Vector2i(x, y)
			var weight: float = [1.0, 1.22, 2.2][_landform(point)] if _walkable(point) else 5.0
			_route_grid.set_point_weight_scale(point, weight + 0.21 * _noise(x, y, 15.0, 1091))

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
		if homes.has(region) or placed_regions.has(region) or _outlying_regions.has(region): continue
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
			var recruit_rank := -1
			if config.version >= WILDERNESS_VERSION:
				recruit_rank = tier
				desired = Vector2i((home + inward * 9.0 + side * 5.0).round()) if tier == 0 else Vector2i((home + inward * 17.0 - side * 11.0).round())
			var placed := _add_scroll(desired, index, code, tier + 2, recruit_rank)
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

func _add_scroll(desired: Vector2i, home: int, code: String, tier: int, recruit_rank := -1) -> int:
	var row: Dictionary = _profile.table("GlobalSpellCut")["FullSpell"]
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var origin := Vector2i(_starts[home].x, _starts[home].y)
	var pos := _find_spot(desired, size, 20, -1, false, true) if recruit_rank < 0 else _homeland_scroll(origin, desired, size, home, recruit_rank)
	if pos == NO_SPOT and (config.naval or recruit_rank >= 0):
		pos = _find_spot(origin, size, _map.width / 2, home, true, true)
	if pos == NO_SPOT: return -1
	var item := _place("global_spells", "FullSpell", pos, row, 0, _colors[home], [_node("spells", {}, "", [_node("spell", {"code": code})])])
	_clear_footprint(pos, size)
	_connect_site(origin, item, size)
	_important.append(int(item.permanent_id) - 1)
	if config.guards != "none" and recruit_rank != 0: _add_guard(pos - Vector2i(2, 1), home, tier)
	return int(item.permanent_id) - 1

func _homeland_scroll(origin: Vector2i, desired: Vector2i, size: Vector2i, home: int, rank: int) -> Vector2i:
	var best := NO_SPOT
	var best_score := INF
	var radius := OPENING_DISTANCE if rank == 0 else 23
	var best_distance := 10 if rank == 0 else 18
	var region := _region_at(origin)
	_route_grid.set_point_solid(origin, false)
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
	return best

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
	if config.version >= WILDERNESS_VERSION:
		_guard_queue.append({"at": desired, "home": home, "tier": tier})
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

func _place_guard(pos: Vector2i, name: String, home: int) -> int:
	var row := ELFirstMonsters.definition(_profile, name, 0)
	if config.version >= LANDSCAPE_VERSION and config.naval:
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
	_paint_disk(pos, 2, false)
	var id := int(item.permanent_id) - 1
	_important.append(id)
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
		var toward := Vector2i((Vector2(origin) + side * (9 if _next(2) == 0 else -9) + outward * 2.0).round())
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
	# These threats follow their rewards, after both the opening economy
	# and wilderness routes have been laid out. Their zones stay off the
	# shared travel network, so a stronger draw cannot strand one player.
	for encounter: Dictionary in _guard_queue:
		var pos := _encounter_cell(encounter.at, 7)
		if pos == NO_SPOT: continue
		var level := int(encounter.tier) + (1 if config.guards == "strong" else 0)
		var choices: Array = tiers[clampi(level - 1, 0, tiers.size() - 1)] if level <= 5 else []
		_place_guard(pos, _regional_guard(pos, choices, level), int(encounter.home))

func _regional_guard(pos: Vector2i, choices: Array, level: int) -> String:
	if choices.is_empty():
		var best := absi(int(_catalog.monsters[0].level) - level)
		for row: Dictionary in _catalog.monsters: best = mini(best, absi(int(row.level) - level))
		choices = _catalog.monsters.filter(func(row: Dictionary) -> bool: return absi(int(row.level) - level) == best)
	var favored: Array[Dictionary] = []
	var color := ELAdventureArt.terrain_color(_map.tile(pos.x, pos.y))
	for row: Dictionary in choices:
		if ELFirstMonsters.definition(_profile, row.name, 0).get("Color") == color: favored.append(row)
	if not favored.is_empty() and _next(3) != 0: choices = favored
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
		_add_exploration_site(spring, Vector2i(home + outward * outer_reach + side * 6.0), 8, index)
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
	for visit in _map.width * _map.height / 60:
		var point := NO_SPOT
		var score := -INF
		var index := candidates.size() - 1
		while index >= 0:
			var candidate := candidates[index]
			var offset := candidate.y * _map.width + candidate.x
			if distance[offset] <= WILDERNESS_SPACING or _reserved[offset] != 0:
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
		for name: String in pool:
			site = _add_exploration_site(name, point, 5, -1, _region_at(point))
			if not site.is_empty(): break
		if site.is_empty():
			# The selected point may be unusable because of a narrow coast.
			# Drop it without falsely filling the surrounding distance field.
			candidates.erase(point)
		else:
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
	var cursor := 0
	while cursor < origins.size():
		var at := origins[cursor]
		cursor += 1
		var next_distance := distance[at.y * _map.width + at.x] + 1
		for direction: Vector2i in CARDINAL:
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

func _add_exploration_site(name: String, near: Vector2i, radius: int, home := -1, region := -1, params := "", group := "additional_buildings") -> Dictionary:
	var table := "Artefacts" if group == "artefacts" else "AdditionalBuildings"
	var row: Dictionary = _profile.table(table).get(name, {})
	if not _model(row): return {}
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var pos := _find_spot(near, size, radius, home, true, true, true, region)
	if pos == NO_SPOT: return {}
	var approach := _expedition_trail(Rect2i(pos, size))
	var children: Array = [] if params.is_empty() else [_node("params", {}, params)]
	var item := _place(group, name, pos, row, 0, "", children)
	_important.append(int(item.permanent_id) - 1)
	_protect_route(approach, _exploration_access)
	return item

## Find a reachable stand beside the prospective site. Its footprint must
## leave its own route intact, including the side cells of a naval diagonal.
func _expedition_trail(footprint: Rect2i) -> int:
	var perimeter := footprint.grow(1)
	for y in range(perimeter.position.y, perimeter.end.y):
		for x in range(perimeter.position.x, perimeter.end.x):
			var point := Vector2i(x, y)
			if footprint.has_point(point) or not _walkable(point): continue
			var approach := y * _map.width + x
			if _exploration_access[approach] < -1: continue
			var offset := approach
			while offset >= 0:
				var tile := Vector2i(offset % _map.width, offset / _map.width)
				var parent := _exploration_access[offset]
				if footprint.has_point(tile) or (_occupied[offset] != 0 and parent >= 0): break
				if config.naval and parent >= 0:
					var from := Vector2i(parent % _map.width, parent / _map.width)
					if tile.x != from.x and tile.y != from.y:
						if footprint.has_point(Vector2i(tile.x, from.y)) or footprint.has_point(Vector2i(from.x, tile.y)): break
						if _occupied[from.y * _map.width + tile.x] != 0 or _occupied[tile.y * _map.width + from.x] != 0: break
				offset = parent
			if offset == -1: return approach
	return -1

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
				if not plant and span <= 10: cliffs.append(entry)
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

func _make_scenery() -> void:
	var pools := _scenery_catalog()
	var land := PackedByteArray()
	land.resize(_map.width * _map.height)
	for y in range(2, _map.height - 2):
		for x in range(2, _map.width - 2):
			if _walkable(Vector2i(x, y)): land[y * _map.width + x] = 1
	if config.version >= WILDERNESS_VERSION:
		_make_groves(land, pools)
		return
	# Give each patch of land its own budget. Coastlines and the backs of
	# homelands get coverage even when most of the world is water.
	for top in range(2, _map.height - 2, SCENERY_PATCH_SIZE):
		for left in range(2, _map.width - 2, SCENERY_PATCH_SIZE):
			var area := Rect2i(left, top, SCENERY_PATCH_SIZE, SCENERY_PATCH_SIZE)
			_make_scenery_patch(area, land, pools)

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
		if _place_scenery(point, pool.cliffs, land):
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
	return not config.naval or _ports.is_empty() or not _port_route(at).is_empty()

func _port_route(at: Vector2i) -> Array[Vector2i]:
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

func _find_spot(near: Vector2i, size: Vector2i, radius: int, home: int, require_land: bool, avoid_roads: bool, expedition := false, region := -1) -> Vector2i:
	# Deterministic expanding rings preserve the desired strategic distance.
	var turn := _next(4)
	for distance in range(radius + 1):
		for edge in 4:
			for step in range(-distance, distance + 1):
				var delta := Vector2i(step, -distance)
				for rotation in (edge + turn) % 4: delta = Vector2i(-delta.y, delta.x)
				var point := near + delta
				if not expedition and not _outlying_regions.is_empty() and _outlying_regions.has(_region_at(point + size / 2)): continue
				if home >= 0 and _owner(point + size / 2) != home: continue
				if config.naval and home >= 0 and _region_at(point + size / 2) != _region_at(_anchors[home]): continue
				if region >= 0 and _region_at(point + size / 2) != region: continue
				if not _fits(point, size, require_land, avoid_roads): continue
				if expedition and _expedition_trail(Rect2i(point, size)) < 0: continue
				return point
	return NO_SPOT

func _paint_disk(center: Vector2i, radius: int, road: bool, trunk := false) -> void:
	for y in range(maxi(0, center.y - radius), mini(_map.height, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(_map.width, center.x + radius) + 1):
			if Vector2i(x, y).distance_squared_to(center) > radius * radius: continue
			var tile := _map.tile(x, y)
			if config.version >= WILDERNESS_VERSION and tile != _water: continue
			if not config.naval or tile != 16: _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))
	if road and _inside(center) and config.roads:
		var index := center.y * _map.width + center.x
		_map.roads[index] = maxi(_map.roads[index], 6 if trunk and config.version >= WILDERNESS_VERSION else 5)

func _clear_footprint(at: Vector2i, size: Vector2i) -> void:
	for y in range(at.y - 2, at.y + size.y + 3):
		for x in range(at.x - 2, at.x + size.x + 3):
			if x < 0 or y < 0 or x > _map.width or y > _map.height: continue
			var tile := _map.tile(x, y)
			if config.version >= WILDERNESS_VERSION and tile != _water: continue
			if not config.naval or tile != 16: _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))

func _connect(from: Vector2i, to: Vector2i, width: int, road: bool, trunk := false) -> bool:
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
		_paint_disk(point, width + 1, road, trunk)
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
	if protect_routes and config.version >= LANDSCAPE_VERSION: _exploration_access = previous
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
