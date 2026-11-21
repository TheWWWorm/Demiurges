## Modified for the EL1 Naval Worlds release, 18 November 2026.
class_name ELAdventureGrid
extends RefCounted
## Shared terrain/footprint geometry for movement, picking and world placement.
var map: ELAdventureMap
var land := AStarGrid2D.new()
var water := AStarGrid2D.new()
var blockers := PackedInt32Array()
var bridges := PackedByteArray()
var footprints: Dictionary = {}
var occupied: Dictionary = {}
var actor_blockers := PackedInt32Array()
var error := ""
## Naval maps expose their combined walking/sailing mask through land so
## the strategic AI's fog and guard closures also apply to voyages. The
## route search still enforces every harbor edge (ELFirstNaval).
var naval := false
var naval_water := PackedByteArray()
var naval_links: Dictionary = {}
## First game, the adventure's own grid (build with `keep_costs`): each
## cell's movement cost with nothing on it, on foot and by ship, measured by
## _update_cell. The terrain and roads of a map in play never change (checks
## that edit them update those cells), and the computer players' route
## searches close and reopen thousands of cells a turn. Empty: measured on
## every call (the map generators edit terrain between their own builds).
var _bare_land := PackedInt32Array()
var _bare_ship := PackedInt32Array()
## The same grid's object footprints from earlier rebuilds: id -> [the
## object's fields its art row depends on (ELAdventureArt.resolve), footprint,
## bridge, authored node]. A rebuild resolves again only objects whose fields changed.
var _shapes: Dictionary = {}
## An actor's occupied tile changed (a step, placement or removal).
signal actor_moved(actor: Dictionary)

func build(source: ELAdventureMap, objects: Dictionary, keep_costs := false) -> bool:
	map = source
	if map.profile.terrain_tiles == null:
		var tiles := ELTileSet.new()
		if not tiles.load_file(map.profile.file("Resources/tileset.tsr")):
			error = tiles.error
			return false
		map.profile.terrain_tiles = tiles
	naval = ELFirstNaval.enabled(map)
	if naval and not ELFirstNaval.configure(self): return false
	if not naval:
		naval_water.clear()
		naval_links.clear()
	for grid: AStarGrid2D in [land, water]:
		grid.region = Rect2i(0, 0, map.width, map.height)
		grid.cell_size = Vector2.ONE
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
		grid.update()
	_bare_land = PackedInt32Array()
	_bare_ship = PackedInt32Array()
	_shapes.clear()
	if keep_costs and map.profile.id == "el1": _keep_bare_costs()
	rebuild(objects)
	if naval:
		for id: int in naval_links:
			if blockers[id] != 0:
				error = "A building or terrain object blocks this map's harbor connection."
				return false
	return true

func rebuild(objects: Dictionary) -> void:
	blockers.resize(map.width * map.height)
	blockers.fill(0)
	bridges.resize(blockers.size())
	bridges.fill(0)
	footprints.clear()
	occupied.clear()
	actor_blockers.resize(blockers.size())
	actor_blockers.fill(0)
	var art := ELAdventureArt.new(map)
	var keep := _bare_land.size() == map.width * map.height
	for id: int in objects:
		var item: Dictionary = objects[id]
		if item.get("type") in ["hero", "monster", "corpse"]:
			if occupies(item):
				var position := Vector2i(item.x, item.y)
				occupied[id] = position
				actor_blockers[position.y * map.width + position.x] += 1
			continue
		var shape: Dictionary
		var bridge := false
		var signature: Array = _shape_inputs(item) if keep else []
		var known: Array = _shapes.get(id, []) if keep else []
		if not known.is_empty() and known[0] == signature and is_same(known[3], item.get("node")):
			shape = known[1]
			bridge = known[2]
		else:
			var definition := art.resolve(item)
			var row: Dictionary = definition.get("row", {})
			shape = footprint(row, int(item.rotation))
			if ELAdventureMap.is_trail_cache(item): shape.cells.clear()
			bridge = bool(row.get("Bridge", 0))
			if keep and item.get("group") not in ["heroes", "np_heroes"]: _shapes[id] = [signature, shape, bridge, item.get("node")]
		footprints[id] = shape
		# An opened runestone barrier no longer blocks its cells.
		if not item.get("visible", true) or not item.get("placed", true) or item.get("opened", false): continue
		if map.profile.id == "el2" and item.get("group") == "resource_cuts" and not bridge:
			shape.pickup_origin = Vector2i(item.x, item.y)
		for cell: Vector2i in shape.cells:
			var position := cell + Vector2i(item.x, item.y)
			if contains(position): blockers[position.y * map.width + position.x] += 1
		if bridge:
			for y in shape.size.y:
				for x in shape.size.x:
					var position := Vector2i(item.x + x, item.y + y)
					if contains(position): bridges[position.y * map.width + position.x] = 1
	for y in map.height:
		for x in map.width:
			var pos := Vector2i(x, y)
			_update_cell(pos)

## Every field ELAdventureArt.resolve reads from a non-hero object (the rest
## comes from its authored node and the map, which do not change), and the
## footprint's rotation and trail-cache flag. The node itself is compared by
## identity in rebuild.
static func _shape_inputs(item: Dictionary) -> Array:
	return [item.get("visible"), item.get("type"), item.get("alive"), item.get("shape"), item.get("group"), item.get("ship"), item.get("owner"),
		item.get("x"), item.get("y"), item.get("fort_level"), item.get("level"), item.get("castle_stage"), item.get("monster_difficulty"),
		item.get("name"), item.get("rotation")]

## Release just the cells this pile blocked, preserving overlapping blockers.
## Return false for other shapes so the caller handles them with a rebuild.
func release_pickup(id: int) -> bool:
	var shape: Dictionary = footprints.get(id, {})
	if not shape.has("pickup_origin"): return false
	var origin: Vector2i = shape.pickup_origin
	shape.erase("pickup_origin")
	for offset: Vector2i in shape.cells:
		var cell := origin + offset
		if not contains(cell): continue
		blockers[cell.y * map.width + cell.x] -= 1
		_update_cell(cell)
	return true

func occupies(actor: Dictionary) -> bool:
	# A garrison leaves map occupancy; the fort keeps its own footprint.
	return actor.get("type") in ["hero", "monster"] and actor.get("alive", false) and actor.get("visible", false) and actor.get("placed", true) and not actor.get("fortified", false) and contains(Vector2i(actor.x, actor.y))

## Returns whether the actor's cell changed (actor_moved was emitted).
func update_actor(actor: Dictionary) -> bool:
	var before: Vector2i = occupied.get(int(actor.uid), Vector2i(-1, -1))
	var after := Vector2i(actor.x, actor.y) if occupies(actor) else Vector2i(-1, -1)
	if before == after: return false
	if contains(before):
		actor_blockers[before.y * map.width + before.x] -= 1
		occupied.erase(int(actor.uid))
		_update_cell(before)
	if contains(after):
		actor_blockers[after.y * map.width + after.x] += 1
		occupied[int(actor.uid)] = after
		_update_cell(after)
	actor_moved.emit(actor)
	return true

func _update_cell(pos: Vector2i) -> void:
	# Checks edit terrain and then update the cells they changed: the cell's
	# own unobstructed cost is measured again (see _bare_land).
	if _bare_land.size() == map.width * map.height and contains(pos): _measure_bare(pos)
	var land_cost := passability(pos, false)
	var water_cost := land_cost if map.profile.id == "el1" and not naval else passability(pos, true)
	land.set_point_solid(pos, land_cost < 0)
	water.set_point_solid(pos, water_cost < 0)
	land.set_point_weight_scale(pos, maxi(1, land_cost))
	water.set_point_weight_scale(pos, maxi(1, water_cost))

## Reopens cells a route search closed in `land` alone (unexplored ground,
## guard areas). Only their land flag can be stale: any change to a cell's
## contents meanwhile went through _update_cell, which set the rest.
func reopen(cells: Array[Vector2i]) -> void:
	for pos: Vector2i in cells: land.set_point_solid(pos, passability(pos, false) < 0)

func contains(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < map.width and pos.y < map.height

## `actors` false ignores heroes and monsters (the second game's guard-zone
## fill counts terrain and objects only).
func passability(pos: Vector2i, ship := false, actors := true) -> int:
	if not contains(pos): return -1
	var index := pos.y * map.width + pos.x
	if _bare_land.size() == map.width * map.height:
		# The same answer as below: a dry-land map counts actors always and
		# has one cost for both kinds of travel.
		if blockers[index] != 0 or ((actors or not naval) and actor_blockers[index] != 0): return -1
		return _bare_ship[index] if ship else _bare_land[index]
	if naval: return ELFirstNaval.terrain_cost(map, pos, blockers[index] != 0 or (actors and actor_blockers[index] != 0), ship)
	var corners: Array[int] = [map.tile(pos.x, pos.y), map.tile(pos.x + 1, pos.y), map.tile(pos.x + 1, pos.y + 1), map.tile(pos.x, pos.y + 1)]
	if map.profile.id == "el1": return strategic_cost(map.profile.terrain_tiles, corners, int(map.roads[index]), blockers[index] != 0 or actor_blockers[index] != 0)
	# Both games count heroes and monsters on a cell as blocking it.
	return terrain_passability(map.profile.terrain_tiles, corners, int(map.roads[index]), bridges[index] != 0, blockers[index] != 0 or (actors and actor_blockers[index] != 0), ship)

## Room for every cell's unobstructed first-game cost (see _bare_land); the
## rebuild that follows measures each cell through _update_cell.
func _keep_bare_costs() -> void:
	var size := map.width * map.height
	_bare_land = PackedInt32Array()
	_bare_land.resize(size)
	_bare_ship = PackedInt32Array()
	_bare_ship.resize(size)

## A cell's first-game cost with nothing on it, on foot and by ship.
func _measure_bare(pos: Vector2i) -> void:
	var index := pos.y * map.width + pos.x
	if naval:
		_bare_land[index] = ELFirstNaval.terrain_cost(map, pos, false, false)
		_bare_ship[index] = ELFirstNaval.terrain_cost(map, pos, false, true)
		return
	var corners: Array[int] = [map.tile(pos.x, pos.y), map.tile(pos.x + 1, pos.y), map.tile(pos.x + 1, pos.y + 1), map.tile(pos.x, pos.y + 1)]
	_bare_land[index] = strategic_cost(map.profile.terrain_tiles, corners, int(map.roads[index]), false)
	_bare_ship[index] = _bare_land[index]

static func strategic_cost(tiles: ELTileSet, corners: Array[int], road: int, blocked: bool) -> int:
	if blocked: return -1
	if road > 4 and road < 9: return 1
	var total := 0
	for kind: int in corners:
		var cost := int(tiles.types.get(kind, {}).get("movement", -1))
		if cost < 0: return -1
		total += cost
	return int(total / 4.0) + 1

func path_cost(points: Array[Vector2i], ship := false) -> int:
	var cost := 0
	if naval:
		for index in range(1, points.size()):
			var step := ELFirstNaval.step_cost(self, points[index - 1], points[index])
			if step < 0: return -1
			cost += step
		return cost
	for point: Vector2i in points.slice(1): cost += passability(point, ship)
	return cost

static func terrain_passability(tiles: ELTileSet, corners: Array[int], road: int, bridge: bool, blocked: bool, ship: bool) -> int:
	if blocked: return -1
	if bridge: return -1 if ship else 1
	if ship: return 1 if corners.count(16) > 2 else -1
	if road > 4 and road < 9: return 1
	for kind: int in corners:
		if int(tiles.types.get(kind, {}).get("movement", -1)) < 0: return -1
	return 1

## `avoid` cells are tried as blocked first (second-game guard zones); with no
## such route the unrestricted search is used.
func path(from: Vector2i, to: Vector2i, ship := false, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	if not contains(from) or not contains(to): return []
	if naval:
		var route := ELFirstNaval.path(self, from, [to], avoid)
		return ELFirstNaval.path(self, from, [to]) if route.is_empty() and not avoid.is_empty() else route
	if not avoid.is_empty():
		var grid_used := water if ship else land
		var closed: Array[Vector2i] = []
		for point: Vector2i in avoid:
			if point != from and point != to and contains(point) and not grid_used.is_point_solid(point):
				grid_used.set_point_solid(point, true)
				closed.append(point)
		var detour := path(from, to, ship)
		for point: Vector2i in closed: grid_used.set_point_solid(point, false)
		if not detour.is_empty(): return detour
	var grid := water if ship else land
	if from == to and map.profile.id == "el1": return [from]
	if grid.is_point_solid(to): return []
	# Some authored heroes begin inside their own scripted scenery.
	var start_solid := grid.is_point_solid(from)
	if start_solid: grid.set_point_solid(from, false)
	var result := grid.get_id_path(from, to)
	if start_solid: grid.set_point_solid(from, true)
	return result

func approach(from: Vector2i, target: Dictionary, ship := false, avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	if map.profile.id == "el2" and target.get("type") == "corpse" and from == Vector2i(target.x, target.y): return [from]
	var size: Vector2i = footprints.get(int(target.uid), {}).get("size", Vector2i.ONE)
	var cache := ELAdventureMap.is_trail_cache(target)
	if naval:
		var goals: Array[Vector2i] = []
		var safe_goals: Array[Vector2i] = []
		for y in range(-1, size.y + 1):
			for x in range(-1, size.x + 1):
				if not cache and x >= 0 and x < size.x and y >= 0 and y < size.y: continue
				var point := Vector2i(int(target.x) + x, int(target.y) + y)
				if not contains(point) or not ELFirstNaval.interaction_mode(self, point, target): continue
				goals.append(point)
				if not avoid.has(point): safe_goals.append(point)
		var route := ELFirstNaval.path(self, from, safe_goals, avoid)
		return ELFirstNaval.path(self, from, goals) if route.is_empty() else route
	var best: Array[Vector2i] = []
	var best_cost := 0x7fffffff
	var best_guarded := true
	# An arrival cell outside the avoided cells beats a guarded one: path()
	# never closes its own end cell, so a guarded end is otherwise as good.
	var guarded := {}
	for point: Vector2i in avoid: guarded[point] = true
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if not cache and x >= 0 and x < size.x and y >= 0 and y < size.y: continue
			var point := Vector2i(target.x + x, target.y + y)
			# The moving hero already occupies this approach cell.
			if point == from and map.profile.id == "el2" and passability(from, ship, false) >= 0: return [from]
			var candidate := path(from, point, ship, avoid)
			if not candidate.is_empty():
				var cost := path_cost(candidate, ship)
				var risky := guarded.has(point)
				if (best.is_empty() or (best_guarded and not risky)) or (risky == best_guarded and cost < best_cost):
					best = candidate
					best_cost = cost
					best_guarded = risky
	return best

## The two-cell strip outside a tunnel mouth and its preferred exit cell.
func tunnel_exit(target: Dictionary, ship: bool) -> Vector2i:
	var size: Vector2i = footprints.get(int(target.uid), {}).get("size", Vector2i(4, 4))
	var origin := Vector2i(target.x, target.y)
	var area: Rect2i
	var preferred: Vector2i
	match (int(target.rotation) >> 2) & 3:
		0:
			area = Rect2i(0, -2, size.x, 2)
			preferred = Vector2i(2, -1)
		1:
			area = Rect2i(-2, 0, 2, size.y)
			preferred = Vector2i(-1, 1)
		2:
			area = Rect2i(0, size.y, size.x, 2)
			preferred = Vector2i(1, size.y)
		3:
			area = Rect2i(size.x, 0, 2, size.y)
			preferred = Vector2i(size.x, 2)
	area.position += origin
	preferred += origin
	return _closest_exit(area, preferred, ship)

## Native square rings choose the lowest x, then lowest y within a ring.
func _closest_exit(area: Rect2i, preferred: Vector2i, ship: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var distance := 0x7fffffff
	for x in range(area.position.x, area.end.x):
		for y in range(area.position.y, area.end.y):
			var point := Vector2i(x, y)
			var steps := maxi(absi(x - preferred.x), absi(y - preferred.y))
			if steps < distance and passability(point, ship) >= 0:
				best = point
				distance = steps
	return best

func dock_exit(target: Dictionary, ship: bool) -> Vector2i:
	var size: Vector2i = footprints.get(int(target.uid), {}).get("size", Vector2i(3, 3))
	var turn := ((int(target.rotation) >> 2) + (0 if ship else 2)) & 3
	var area: Rect2i
	var preferred: Vector2i
	match turn:
		0:
			area = Rect2i(target.x - 1, target.y - 1, size.x + 2, 3)
			preferred = Vector2i(target.x, target.y - 1)
		1:
			area = Rect2i(target.x - 1, target.y - 1, 3, size.y + 2)
			preferred = Vector2i(target.x - 1, target.y + 1)
		2:
			area = Rect2i(target.x - 1, target.y + 2, size.x + 2, 3)
			preferred = Vector2i(target.x + 1, target.y + 4)
		3:
			area = Rect2i(target.x + 2, target.y - 1, 3, size.y + 2)
			preferred = Vector2i(target.x + 4, target.y)
	if map.profile.id == "el2":
		return find_landing(area, preferred, ship)
	var best := Vector2i(-1, -1)
	var distance := INF
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var point := Vector2i(x, y)
			if passability(point, ship) >= 0 and point.distance_squared_to(preferred) < distance:
				best = point
				distance = point.distance_squared_to(preferred)
	return best

## EL2 docks and portals clip the landing rectangle before searching its rings.
func find_landing(area: Rect2i, preferred: Vector2i, ship: bool) -> Vector2i:
	var bounds := Rect2i(0, 0, map.width, map.height)
	area = area.intersection(bounds)
	if not area.has_area(): return Vector2i(-1, -1)
	preferred = preferred.clamp(bounds.position, bounds.end - Vector2i.ONE)
	if not area.has_point(preferred): preferred = area.position
	return _closest_exit(area, preferred, ship)

static func footprint(row: Dictionary, rotation: int) -> Dictionary:
	var dimensions: Array = row.get("TileSize", [int(row.get("SizeX", 1)), int(row.get("SizeY", 1))])
	var size := Vector2i(maxi(1, int(dimensions[0])), maxi(1, int(dimensions[1])))
	var cells: Array[Vector2i] = []
	for y in size.y:
		var line: Variant = row.get("Substrate" + str(y + 1), [])
		if not line is Array: line = [line]
		for x in size.x:
			if x < line.size() and int(line[x]) != 0: continue
			var pos := Vector2i(size.x - 1 - x if rotation & 1 else x, size.y - 1 - y if rotation & 2 else y)
			var rotated_size := size
			for turn in (rotation >> 2) & 3:
				pos = Vector2i(pos.y, rotated_size.x - 1 - pos.x)
				rotated_size = Vector2i(rotated_size.y, rotated_size.x)
			cells.append(pos)
	if (rotation >> 2) & 1: size = Vector2i(size.y, size.x)
	return {"size": size, "cells": cells}

static func center(item: Dictionary, row: Dictionary = {}) -> Vector2:
	var size: Vector2i = footprint(row, int(item.get("rotation", 0))).size
	return Vector2(item.x, item.y) + Vector2(size) * 0.5
