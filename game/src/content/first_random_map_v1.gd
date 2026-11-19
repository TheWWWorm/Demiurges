class_name ELFirstRandomMapV1
extends RefCounted
## Versioned, deterministic Etherlords I skirmish maps. Only topology and
## placements are generated here: models, spellbooks, production, shops and
## monster difficulty variants come from the user's mounted first game.
##
## API: generate(profile, options) returns a complete ELAdventureMap or null.
## `config`, `report` and `error` describe the last attempt. The canonical
## configuration is attached as random_map metadata for save regeneration.

const VERSION := 1
const PREFIX := "el1_random_v"
const COLORS := ["Green", "Blue", "Red", "Black"]
const SIZES := [64, 96, 128, 160]
const LAYOUTS := ["frontier", "lakes", "crossroads", "archipelago", "inland_sea", "river_delta", "ring", "peninsulas"]
const ECONOMIES := ["scarce", "normal", "rich"]
const GUARDS := ["none", "normal", "strong"]
const GEMS := {"Green": "Emerald", "Blue": "Sapphire", "Red": "Ruby", "Black": "Diamond"}
const SUMMONS := {"Green": "SVWR", "Blue": "SKWR", "Red": "SCWR", "Black": "SSWR"}
const NO_SPOT := Vector2i(-1, -1)

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

static func defaults() -> Dictionary:
	return {"version": VERSION, "seed": "212", "size": 96, "players": 4,
		"layout": "frontier", "biome": "mixed", "resources": "normal",
		"starting_resources": "normal", "guards": "normal", "faction": "Green",
		"roads": true, "scenery": 1, "castle_health": 30}

## Bad imported configurations fail explicitly. JSON represents integers as
## doubles, so integral finite doubles are accepted, but booleans never are.
static func normalize(options: Dictionary) -> Dictionary:
	var result := defaults()
	for key: Variant in options:
		if key is not String or not result.has(key): return {}
	for key: String in ["version", "size", "players", "scenery", "castle_health"]:
		var value: Variant = options.get(key, result[key])
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)): return {}
		result[key] = int(value)
	if result.version != VERSION or result.size not in SIZES or result.players < 2 or result.players > 4 or result.scenery < 0 or result.scenery > 2 or result.castle_health not in [20, 30, 60]: return {}
	for key: String in ["seed", "layout", "biome", "resources", "starting_resources", "guards", "faction"]:
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
	return result

static func presets() -> Array[Dictionary]:
	return [
		{"id": "quick", "name": "Quick duel", "description": "Two castles and short approaches on a compact frontier.", "options": {"size": 64, "players": 2, "layout": "frontier", "castle_health": 20}},
		{"id": "frontier", "name": "Frontier", "description": "Four rivals, open borders and several routes into the contested interior.", "options": {"size": 96, "players": 4, "layout": "frontier"}},
		{"id": "lakes", "name": "Lake country", "description": "Broad lakes, winding shores and guaranteed land connections.", "options": {"size": 128, "players": 4, "layout": "lakes"}},
		{"id": "crossroads", "name": "Crossroads", "description": "Separated homelands meet at a valuable central crossroads.", "options": {"size": 96, "players": 4, "layout": "crossroads"}},
		{"id": "archipelago", "name": "Island chains", "description": "Separate island homelands, narrow land bridges and a contested island center. Land-only until naval movement is implemented.", "options": {"size": 128, "players": 4, "layout": "archipelago"}},
		{"id": "inland_sea", "name": "Inland sea", "description": "A broad central sea separates coastal kingdoms, with strategic causeways.", "options": {"size": 128, "players": 4, "layout": "inland_sea"}},
		{"id": "delta", "name": "River delta", "description": "A braided river network with contested crossings and pockets of dry land.", "options": {"size": 96, "players": 4, "layout": "river_delta"}},
		{"id": "ring", "name": "Ring of kingdoms", "description": "A circular continent with a lake in the middle and flanking roads.", "options": {"size": 128, "players": 4, "layout": "ring"}},
		{"id": "peninsulas", "name": "Peninsulas", "description": "Long winding coastal fingers converging on a central battlefield.", "options": {"size": 128, "players": 4, "layout": "peninsulas"}},
		{"id": "scarcity", "name": "Scarcity", "description": "Fewer spare resources, stronger frontier guards and a lean treasury.", "options": {"size": 96, "players": 4, "resources": "scarce", "starting_resources": "scarce", "guards": "strong"}},
		{"id": "conquest", "name": "Rich conquest", "description": "Abundant mines and rewards support longer wars between fortified castles.", "options": {"size": 128, "players": 4, "resources": "rich", "starting_resources": "rich", "castle_health": 60}}
	]

static func is_random_id(id: String) -> bool:
	return id.begins_with(PREFIX)

static func id_for_config(options: Dictionary) -> String:
	var normalized := normalize(options)
	return "" if normalized.is_empty() else PREFIX + str(VERSION) + "_" + JSON.stringify(normalized, "", true).sha256_text().left(24)

static func seed_for_config(options: Dictionary) -> int:
	var normalized := normalize(options)
	if normalized.is_empty(): return 1
	return 1 + (int(("el1-random-map-v1:" + str(normalized.seed)).sha256_text().left(8).hex_to_int()) & 0x7fffffff) % 2147483646

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
	_map.set_meta("random_map", {"version": VERSION, "config": config.duplicate(true)})
	_map.document = _node("scenario", {}, "", [_node("title", {}, _map.title), _node("objective", {}, _map.objective),
		_node("win_condition", {}, "Destroy every rival castle."), _node("lose_condition", {}, "Your castle loses all of its energy."),
		_node("description", {}, "Expand from your homeland, capture mines and shops, and discover the scrolls that summon stronger heroes."),
		_node("random_map", {"version": str(VERSION), "config": JSON.stringify(config, "", true), "catalog_hash": _catalog_hash()})])
	_next_id = 1
	_important.clear()
	_starts.clear()
	_anchors.clear()
	_colors.clear()
	_shop_stocks.clear()
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
	if not _make_players(): return null
	_make_routes()
	if not _make_homelands(): return null
	if not _make_frontiers(): return null
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
	var center := Vector2(_map.width, _map.height) * 0.5
	var angle := PI + float(_next(2001) - 1000) / 10000.0
	if int(config.players) == 4: angle += PI * 0.25
	var radius := float(_map.width) * (0.34 if int(config.players) == 4 else 0.32)
	for index in int(config.players):
		var point := center + Vector2.from_angle(angle + TAU * index / int(config.players)) * radius
		_anchors.append(Vector2i(point.round()))

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

## Shape fields are deterministic and smooth; each layout uses geography
## rather than a random water threshold alone. The noise perturbs boundaries
## without destroying the large-scale silhouette.
func _water_field(point: Vector2i) -> bool:
	var center := Vector2(_map.width, _map.height) * 0.5
	var relative := Vector2(point) - center
	var r := relative.length() / (float(_map.width) * 0.5)
	var theta := atan2(relative.y, relative.x)
	var low := _noise(point.x, point.y, float(_map.width) / 5.0, 17)
	var detail := _noise(point.x, point.y, 8.0, 61)
	var jitter := (low - 0.5) * 0.15 + (detail - 0.5) * 0.075
	match str(config.layout):
		"lakes": return low * 0.78 + detail * 0.22 > 0.48
		"crossroads":
			return (absf(sin(theta * int(config.players) * 0.5 + 0.6)) < 0.18 and relative.length() > 9.0) or low > 0.86
		"archipelago":
			var island := 1.0
			for anchor: Vector2i in _anchors:
				var distance := Vector2(point - anchor).length() / (float(_map.width) * 0.19)
				island = minf(island, distance)
			var middle := relative.length() / (float(_map.width) * 0.16)
			return minf(island, middle) + jitter > 0.90
		"inland_sea":
			var coast := 0.44 + 0.09 * sin(theta * 3.0 + 0.7) + jitter
			return r < coast
		"river_delta":
			var meander := sin(float(point.y) / 11.0 + sin(float(point.x) / 19.0)) * float(_map.width) * 0.12
			var stream := absf(relative.x - meander)
			var branch := absf(relative.x + relative.y * 0.65 - sin(float(point.y) / 14.0) * 9.0)
			return stream < 3.0 + detail * 3.0 or branch < 2.0 + low * 3.0
		"ring":
			return r < 0.29 + jitter or r > 0.94 + jitter
		"peninsulas":
			var waves := cos(theta * float(config.players) + 0.25)
			return r > 0.45 + waves * 0.32 + jitter
		_: return low * 0.8 + detail * 0.2 > 0.73

func _make_terrain() -> void:
	for y in range(_map.height + 1):
		for x in range(_map.width + 1):
			var point := Vector2i(x, y)
			var tile := _ground(point, true)
			if _water >= 0 and _water_field(point): tile = _water
			_map.terrain[y * (_map.width + 1) + x] = tile
	for anchor: Vector2i in _anchors: _paint_disk(anchor, 11, false)

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

	return true

func _add_scroll(desired: Vector2i, home: int, code: String, tier: int) -> int:
	var row: Dictionary = _profile.table("GlobalSpellCut")["FullSpell"]
	var size: Vector2i = ELAdventureGrid.footprint(row, 0).size
	var pos := _find_spot(desired, size, 20, -1, false, true)
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

func _make_scenery() -> void:
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

static func _node(tag: String, attrs: Dictionary = {}, text := "", children: Array = []) -> Dictionary:
	return {"tag": tag, "attrs": attrs, "text": text, "children": children}

func _place(group: String, name: String, position: Vector2i, row: Dictionary, owner := 0, color := "", extra: Array = [], attrs: Dictionary = {}) -> Dictionary:
	var id := _next_id
	_next_id += 1
	var properties := attrs.duplicate()
	properties.permanent_id = str(id)
	properties.id = str(id)
	var children: Array = [_node("place", {"x": str(position.x), "y": str(position.y), "mr": "0"}), _node("template", {}, name)]
	if not color.is_empty(): children.append(_node("color", {}, color))
	children.append_array(extra)
	var node := _node("hero" if group in ["heroes", "np_heroes"] else "object", properties, "", children)
	var item := {"group": group, "owner": owner, "node": node, "x": position.x, "y": position.y, "rotation": 0,
		"permanent_id": id, "id": id, "name": name}
	_map.objects.append(item)
	var size := Vector2i.ONE if group in ["heroes", "np_heroes"] else Vector2i(ELAdventureGrid.footprint(row, 0).size)
	for y in range(position.y - 1, position.y + size.y + 1):
		for x in range(position.x - 1, position.x + size.x + 1):
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
			if int(_profile.terrain_tiles.types.get(_map.tile(point.x + dx, point.y + dy), {}).get("movement", -1)) < 0: return false
	return true

func _fits(at: Vector2i, size: Vector2i, require_land: bool, avoid_roads: bool) -> bool:
	if at.x < 2 or at.y < 2 or at.x + size.x >= _map.width - 2 or at.y + size.y >= _map.height - 2: return false
	for y in range(at.y, at.y + size.y):
		for x in range(at.x, at.x + size.x):
			var offset := y * _map.width + x
			if _reserved[offset] != 0 or (avoid_roads and _corridor[offset] != 0): return false
			if require_land and not _walkable(Vector2i(x, y)): return false
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
				if _fits(point, size, require_land, avoid_roads): return point
	return NO_SPOT

func _paint_disk(center: Vector2i, radius: int, road: bool) -> void:
	for y in range(maxi(0, center.y - radius), mini(_map.height, center.y + radius) + 1):
		for x in range(maxi(0, center.x - radius), mini(_map.width, center.x + radius) + 1):
			if Vector2i(x, y).distance_squared_to(center) > radius * radius: continue
			_map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))
	if road and _inside(center) and config.roads:
		_map.roads[center.y * _map.width + center.x] = 5

func _clear_footprint(at: Vector2i, size: Vector2i) -> void:
	for y in range(at.y - 2, at.y + size.y + 3):
		for x in range(at.x - 2, at.x + size.x + 3):
			if x >= 0 and y >= 0 and x <= _map.width and y <= _map.height: _map.terrain[y * (_map.width + 1) + x] = _ground(Vector2i(x, y))

func _connect(from: Vector2i, to: Vector2i, width: int, road: bool) -> void:
	# Route against object bounding boxes, ignoring terrain so the resulting
	# causeway can connect separated land without requiring boats or portals.
	if not _route_grid.region.has_point(from) or not _route_grid.region.has_point(to): return
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

func _connect_site(from: Vector2i, item: Dictionary, size: Vector2i) -> void:
	var approach := Vector2i(item.x, item.y) - Vector2i.ONE
	var best := 1.0e30
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and x < size.x and y >= 0 and y < size.y: continue
			var point := Vector2i(item.x + x, item.y + y)
			if not _inside(point) or _occupied[point.y * _map.width + point.x] != 0: continue
			var distance := point.distance_squared_to(from)
			if distance < best:
				best = distance
				approach = point
	# A short spur joins the existing connected network. Repeatedly drawing
	# a new direct road all the way home made crowded parallel spokes.
	var junction := from
	var distance := approach.distance_squared_to(from)
	for point: Vector2i in _network_points:
		var offset := point.y * _map.width + point.x
		if _occupied[offset] != 0 or _reserved[offset] != 0: continue
		var candidate := approach.distance_squared_to(point)
		if candidate < distance:
			distance = candidate
			junction = point
	_connect(junction, approach, 1, bool(config.roads))

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

func _check_access() -> bool:
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
				reached[offset] = 1
				queue.append(next)
	var targets: Array[int] = _important.duplicate()
	for start: Dictionary in _starts:
		targets.append(int(start.castle_id))
		targets.append(int(start.hero_id))
	for id: int in targets:
		var item: Dictionary = objects[id]
		var size: Vector2i = grid.footprints.get(id, {}).get("size", Vector2i.ONE)
		var reachable := false
		for y in range(-1, size.y + 1):
			for x in range(-1, size.x + 1):
				if x >= 0 and x < size.x and y >= 0 and y < size.y: continue
				var point := Vector2i(item.x + x, item.y + y)
				if grid.contains(point) and reached[point.y * _map.width + point.x] != 0: reachable = true
		if not reachable:
			error = "Generated map contains an unreachable %s (%d). Try a different seed." % [str(item.group), id]
			return false
	for start: Dictionary in _starts: start.reachable_sites = _important.size()
	report.reachable = true
	report.reachable_cells = queue.size()
	return true
