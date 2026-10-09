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
## An actor's occupied tile changed (a step, placement or removal).
signal actor_moved(actor: Dictionary)

func build(source: ELAdventureMap, objects: Dictionary) -> bool:
	map = source
	if map.profile.terrain_tiles == null:
		var tiles := ELTileSet.new()
		if not tiles.load_file(map.profile.file("Resources/tileset.tsr")):
			error = tiles.error
			return false
		map.profile.terrain_tiles = tiles
	for grid: AStarGrid2D in [land, water]:
		grid.region = Rect2i(0, 0, map.width, map.height)
		grid.cell_size = Vector2.ONE
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
		grid.update()
	rebuild(objects)
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
	for id: int in objects:
		var item: Dictionary = objects[id]
		if item.get("type") in ["hero", "monster", "corpse"]:
			if occupies(item):
				var position := Vector2i(item.x, item.y)
				occupied[id] = position
				actor_blockers[position.y * map.width + position.x] += 1
			continue
		var definition := art.resolve(item)
		var row: Dictionary = definition.get("row", {})
		var shape := footprint(row, int(item.rotation))
		footprints[id] = shape
		# An opened runestone barrier no longer blocks its cells.
		if not item.get("visible", true) or not item.get("placed", true) or item.get("opened", false): continue
		for cell: Vector2i in shape.cells:
			var position := cell + Vector2i(item.x, item.y)
			if contains(position): blockers[position.y * map.width + position.x] += 1
		if row.get("Bridge", 0):
			for y in shape.size.y:
				for x in shape.size.x:
					var position := Vector2i(item.x + x, item.y + y)
					if contains(position): bridges[position.y * map.width + position.x] = 1
	for y in map.height:
		for x in map.width:
			var pos := Vector2i(x, y)
			_update_cell(pos)

func occupies(actor: Dictionary) -> bool:
	# A garrison leaves map occupancy; the fort keeps its own footprint.
	return map.profile.id == "el1" and actor.get("type") in ["hero", "monster"] and actor.get("alive", false) and actor.get("visible", false) and actor.get("placed", true) and not actor.get("fortified", false) and contains(Vector2i(actor.x, actor.y))

func update_actor(actor: Dictionary) -> void:
	if map.profile.id != "el1": return
	var before: Vector2i = occupied.get(int(actor.uid), Vector2i(-1, -1))
	var after := Vector2i(actor.x, actor.y) if occupies(actor) else Vector2i(-1, -1)
	if before == after: return
	if contains(before):
		actor_blockers[before.y * map.width + before.x] -= 1
		occupied.erase(int(actor.uid))
		_update_cell(before)
	if contains(after):
		actor_blockers[after.y * map.width + after.x] += 1
		occupied[int(actor.uid)] = after
		_update_cell(after)
	actor_moved.emit(actor)

func _update_cell(pos: Vector2i) -> void:
	var land_cost := passability(pos, false)
	var water_cost := land_cost if map.profile.id == "el1" else passability(pos, true)
	land.set_point_solid(pos, land_cost < 0)
	water.set_point_solid(pos, water_cost < 0)
	land.set_point_weight_scale(pos, maxi(1, land_cost))
	water.set_point_weight_scale(pos, maxi(1, water_cost))

func contains(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < map.width and pos.y < map.height

func passability(pos: Vector2i, ship := false) -> int:
	if not contains(pos): return -1
	var index := pos.y * map.width + pos.x
	var corners: Array[int] = [map.tile(pos.x, pos.y), map.tile(pos.x + 1, pos.y), map.tile(pos.x + 1, pos.y + 1), map.tile(pos.x, pos.y + 1)]
	if map.profile.id == "el1": return strategic_cost(map.profile.terrain_tiles, corners, int(map.roads[index]), blockers[index] != 0 or actor_blockers[index] != 0)
	return terrain_passability(map.profile.terrain_tiles, corners, int(map.roads[index]), bridges[index] != 0, blockers[index] != 0, ship)

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
	var size: Vector2i = footprints.get(int(target.uid), {}).get("size", Vector2i.ONE)
	var best: Array[Vector2i] = []
	var best_cost := 0x7fffffff
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and x < size.x and y >= 0 and y < size.y: continue
			var candidate := path(from, Vector2i(target.x + x, target.y + y), ship, avoid)
			if not candidate.is_empty():
				var cost := path_cost(candidate, ship)
				if cost < best_cost:
					best = candidate
					best_cost = cost
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
	var best := Vector2i(-1, -1)
	var distance := INF
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var point := Vector2i(x, y)
			if passability(point, ship) >= 0 and point.distance_squared_to(preferred) < distance:
				best = point
				distance = point.distance_squared_to(preferred)
	return best

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
