class_name ELFirstShoreDecor
extends Node3D
## Etherlords II shore pieces on first-game random maps (version 16): quays
## beside the harbors, moored ships, wrecks and flotsam. The generator only
## lists where they stand (the map's "first_decor" metadata); the pieces are
## the installed second game's own models and textures, read from its files
## like the EL2 ship (ELFirstNavalVisuals). Without the second game, or with
## the "first_shore_objects" option off, nothing is drawn and the harbors
## keep their built-in pier. Decoration only: no piece is a map object,
## blocks a cell, shows a tooltip or changes a route.

## The second-game table each listed name is read from.
const ROWS := {"Dock": "AdditionalBuildings", "Ship_01": "TerrObj", "Ship_02": "TerrObj", "Ship_03": "TerrObj",
	"WaterDust_01": "TerrObj", "WaterDust_02": "TerrObj", "WaterDust_03": "TerrObj", "WaterDust_04": "TerrObj", "Barrel": "TerrObj"}
var map: ELAdventureMap
## {model, cell, level}: the fog of its centre cell shows it.
var pieces: Array[Dictionary] = []
## Harbor ids whose quay was drawn: their built-in pier stays away.
var docked: Dictionary = {}

## The second game's files when they hold the quay and every ship piece.
static func source(profile: ELProfile) -> ELProfile:
	if profile == null or profile.id != "el2": return null
	for name: String in ROWS:
		if profile.table(ROWS[name]).get(name, {}).is_empty(): return null
	return profile

## The listed pieces, or [] for a map from before version 16.
static func items(source_map: ELAdventureMap) -> Array:
	if source_map == null or source_map.profile == null or source_map.profile.id != "el1": return []
	var payload: Variant = source_map.get_meta("first_decor", {})
	if not payload is Dictionary or int(payload.get("version", 0)) != 1 or not payload.get("items") is Array: return []
	return payload.items

## Builds every listed piece from `second`; `added` receives each animated
## model (ELAdventureScene._add_animated). Returns the pieces built.
func build(source_map: ELAdventureMap, second: ELProfile, added: Callable = Callable()) -> int:
	map = source_map
	for piece: Dictionary in pieces: piece.model.free()
	pieces.clear()
	docked.clear()
	if second == null: return 0
	for item: Variant in items(map):
		if not item is Dictionary or not ROWS.has(str(item.get("name", ""))): continue
		var name := str(item.name)
		var row: Dictionary = second.table(ROWS[name]).get(name, {})
		var anim := ELAdventureArt.animated_texture(row)
		var model := ELModel.new()
		model.name = "Shore_%s_%d" % [name, pieces.size()]
		if not model.build(second, str(row.get("Model", "")), "TerrainObjects/" + str(row.get("TextureName", row.get("Texture", ""))), "",
				"TerrainObjects/" + anim if not anim.is_empty() else ""):
			model.free()
			continue
		var at := Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
		add_child(model)
		model.position = ELAdventureScene.world_position(at.x - 0.5, at.y - 0.5)
		model.position.y = map.surface_height(at)
		# Turns count clockwise from map north; the models face local +Z.
		model.rotation.y = deg_to_rad(180.0 - float(item.get("turn", 0)))
		if model.clips.has("cidle") and added.is_valid(): added.call(model)
		model.hide()
		if str(item.get("kind", "")) == "dock": docked[int(item.get("port", -1))] = int(item.get("side", 1))
		pieces.append({"model": model, "cell": Vector2i(floori(at.x), floori(at.y)), "level": -1})
	return pieces.size()

## Shows a piece once its centre cell has been explored, dimmed while it is
## only remembered. `dim` is ELAdventureScene._dim_model.
func set_fog(tiles: PackedByteArray, dim: Callable = Callable()) -> void:
	if map == null: return
	var valid := tiles.is_empty() or tiles.size() == map.width * map.height
	for piece: Dictionary in pieces:
		var level := 255
		if valid:
			var cell: Vector2i = piece.cell.clamp(Vector2i.ZERO, Vector2i(map.width - 1, map.height - 1))
			level = 0 if tiles.is_empty() else tiles[cell.y * map.width + cell.x]
		if piece.level == level: continue
		piece.level = level
		var model: ELModel = piece.model
		model.visible = level < 255
		if dim.is_valid(): dim.call(model, 1.0 if level == 0 else ELAdventureScene.FOG_DIM)
