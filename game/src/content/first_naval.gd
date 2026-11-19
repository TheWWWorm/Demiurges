class_name ELFirstNaval
extends RefCounted
## Opt-in first-game voyages. As in EL2, a ship is the hero's travel form;
## harbors supply the vessel, and the hero brings it to the destination harbor.
## No detached boat is cloned, left at its old position or silently reused.
const WATER := 16
const SAIL_COST := 1
const TRANSFER_COST := 3
const DIRECTIONS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
const NO_COST := 0x3fffffff

static func enabled(map: ELAdventureMap) -> bool:
	if map == null or map.profile == null or map.profile.id != "el1": return false
	var ports: Variant = map.get_meta("first_naval", {})
	if ports is Dictionary and ELLuaSave._integer(ports.get("version"), 1, 1) and ports.get("ports") is Array: return true
	var recipe: Variant = map.get_meta("random_map", {})
	if not recipe is Dictionary: return false
	var config: Variant = recipe.get("config", {})
	return config is Dictionary and config.get("naval", false) == true

## Mixed shore cells belong to the sea. This closes the impassable one-cell
## seam between the all-land cells and the deep-water cells of corner terrain.
static func is_water(map: ELAdventureMap, point: Vector2i) -> bool:
	if point.x < 0 or point.y < 0 or point.x >= map.width or point.y >= map.height: return false
	return map.tile(point.x, point.y) == WATER or map.tile(point.x + 1, point.y) == WATER \
		or map.tile(point.x + 1, point.y + 1) == WATER or map.tile(point.x, point.y + 1) == WATER

static func terrain_cost(map: ELAdventureMap, point: Vector2i, blocked: bool, ship_only := false) -> int:
	if blocked: return -1
	var wet := false
	for corner: Vector2i in [point, point + Vector2i.RIGHT, point + Vector2i.ONE, point + Vector2i.DOWN]:
		var kind := map.tile(corner.x, corner.y)
		if kind == WATER: wet = true
		elif int(map.profile.terrain_tiles.types.get(kind, {}).get("movement", -1)) < 0: return -1
	if wet: return SAIL_COST
	if ship_only: return -1
	var corners: Array[int] = [map.tile(point.x, point.y), map.tile(point.x + 1, point.y), map.tile(point.x + 1, point.y + 1), map.tile(point.x, point.y + 1)]
	return ELAdventureGrid.strategic_cost(map.profile.terrain_tiles, corners, int(map.roads[point.y * map.width + point.x]), false)

## Build the immutable coast links once. Dynamic occupancies and fog remain
## in grid.land and are checked whenever a route or a step is requested.
static func configure(grid: ELAdventureGrid) -> bool:
	grid.naval_links.clear()
	grid.naval_water.resize(grid.map.width * grid.map.height)
	for y in grid.map.height:
		for x in grid.map.width:
			grid.naval_water[y * grid.map.width + x] = 1 if is_water(grid.map, Vector2i(x, y)) else 0
	var metadata: Variant = grid.map.get_meta("first_naval", {})
	if not metadata is Dictionary or not ELLuaSave._integer(metadata.get("version"), 1, 1) or not metadata.get("ports") is Array:
		grid.error = "This naval map has no harbor connections."
		return false
	for port: Variant in metadata.ports:
		if not port is Dictionary or not _coordinate(port.get("land"), grid.map) or not _coordinate(port.get("water"), grid.map):
			grid.error = "This naval map has an invalid harbor."
			return false
		var shore := Vector2i(int(port.land[0]), int(port.land[1]))
		var sea := Vector2i(int(port.water[0]), int(port.water[1]))
		if absi(shore.x - sea.x) + absi(shore.y - sea.y) != 1 or is_water(grid.map, shore) or not is_water(grid.map, sea) \
			or terrain_cost(grid.map, shore, false) < 0 or terrain_cost(grid.map, sea, false) < 0:
			grid.error = "A harbor must connect adjacent, passable land and water cells."
			return false
		var a := shore.y * grid.map.width + shore.x
		var b := sea.y * grid.map.width + sea.x
		if not grid.naval_links.has(a): grid.naval_links[a] = {}
		if not grid.naval_links.has(b): grid.naval_links[b] = {}
		grid.naval_links[a][b] = true
		grid.naval_links[b][a] = true
	if grid.naval_links.is_empty():
		grid.error = "This naval map needs at least one harbor."
		return false
	return true

static func _coordinate(value: Variant, map: ELAdventureMap) -> bool:
	return value is Array and value.size() == 2 and ELLuaSave._integer(value[0], 0, map.width - 1) and ELLuaSave._integer(value[1], 0, map.height - 1)

## Geometric edge validity, independent of destination occupancy. A diagonal
## cannot cut a coastal corner, a building corner, or a blocked channel.
static func connected(grid: ELAdventureGrid, from: Vector2i, to: Vector2i, actors := true, planning := false) -> bool:
	if not grid.contains(from) or not grid.contains(to): return false
	var delta := to - from
	if delta == Vector2i.ZERO or absi(delta.x) > 1 or absi(delta.y) > 1: return false
	var a := from.y * grid.map.width + from.x
	var b := to.y * grid.map.width + to.x
	if grid.naval_water[a] != grid.naval_water[b]: return grid.naval_links.get(a, {}).has(b)
	if delta.x == 0 or delta.y == 0: return true
	for side: Vector2i in [from + Vector2i(delta.x, 0), from + Vector2i(0, delta.y)]:
		if grid.naval_water[side.y * grid.map.width + side.x] != grid.naval_water[a]: return false
		if planning:
			if grid.land.is_point_solid(side): return false
		elif grid.passability(side, false, actors) < 0: return false
	return true

static func step_cost(grid: ELAdventureGrid, from: Vector2i, to: Vector2i, actors := true) -> int:
	if not grid.naval: return grid.passability(to, false, actors)
	if not connected(grid, from, to, actors): return -1
	var cost := grid.passability(to, false, actors)
	if cost < 0: return -1
	return cost + (TRANSFER_COST if grid.naval_water[from.y * grid.map.width + from.x] != grid.naval_water[to.y * grid.map.width + to.x] else 0)

## Objects on land must be approached on land. Opposing units may fight
## across the two ends of a harbor, so an occupied landing is contestable;
## the survivor stays in its current travel form until it actually moves.
static func interaction_mode(grid: ELAdventureGrid, point: Vector2i, target: Dictionary) -> bool:
	var unit: bool = target.get("type") in ["hero", "monster", "corpse"]
	var target_ship := bool(target.get("ship", false)) if unit else false
	if is_water(grid.map, point) == target_ship: return true
	var at := Vector2i(int(target.get("x", -1)), int(target.get("y", -1)))
	return target.get("type") in ["hero", "monster"] and grid.contains(point) and grid.contains(at) and grid.naval_links.get(point.y * grid.map.width + point.x, {}).has(at.y * grid.map.width + at.x)

static func path(grid: ELAdventureGrid, from: Vector2i, goals: Array[Vector2i], avoid: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not grid.contains(from): return result
	var goal_ids := {}
	var bounds := Rect2i()
	for goal: Vector2i in goals:
		if not grid.contains(goal): continue
		if goal == from: return [from]
		if grid.land.is_point_solid(goal): continue
		goal_ids[goal.y * grid.map.width + goal.x] = true
		bounds = Rect2i(goal, Vector2i.ONE) if goal_ids.size() == 1 else bounds.expand(goal)
	if goal_ids.is_empty(): return result
	var avoided := {}
	for point: Vector2i in avoid:
		if point != from and grid.contains(point) and not goal_ids.has(point.y * grid.map.width + point.x): avoided[point.y * grid.map.width + point.x] = true
	var count := grid.map.width * grid.map.height
	var costs := PackedInt32Array()
	costs.resize(count)
	costs.fill(NO_COST)
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-1)
	var settled := PackedByteArray()
	settled.resize(count)
	var start := from.y * grid.map.width + from.x
	costs[start] = 0
	var heap: Array[Vector3i] = []
	_push(heap, Vector3i(_estimate(from, bounds), start, 0))
	while not heap.is_empty():
		var entry := _pop(heap)
		var id := entry.y
		if settled[id] != 0 or entry.z != costs[id]: continue
		settled[id] = 1
		if goal_ids.has(id):
			while id >= 0:
				result.append(Vector2i(id % grid.map.width, id / grid.map.width))
				id = parent[id]
			result.reverse()
			return result
		var here := Vector2i(id % grid.map.width, id / grid.map.width)
		for direction: Vector2i in DIRECTIONS:
			var next := here + direction
			if not grid.contains(next) or grid.land.is_point_solid(next): continue
			var next_id := next.y * grid.map.width + next.x
			if settled[next_id] != 0 or avoided.has(next_id) or not connected(grid, here, next, true, true): continue
			var cost := costs[id] + int(grid.land.get_point_weight_scale(next))
			if grid.naval_water[id] != grid.naval_water[next_id]: cost += TRANSFER_COST
			if cost >= costs[next_id]: continue
			costs[next_id] = cost
			parent[next_id] = id
			_push(heap, Vector3i(cost + _estimate(next, bounds), next_id, cost))
	return result

static func _estimate(point: Vector2i, area: Rect2i) -> int:
	return maxi(maxi(0, maxi(area.position.x - point.x, point.x - area.end.x + 1)), maxi(0, maxi(area.position.y - point.y, point.y - area.end.y + 1)))

static func _less(a: Vector3i, b: Vector3i) -> bool:
	return a.x < b.x or (a.x == b.x and (a.z > b.z or (a.z == b.z and a.y < b.y)))

static func _push(heap: Array[Vector3i], value: Vector3i) -> void:
	var at := heap.size()
	heap.append(value)
	while at > 0:
		var above := (at - 1) / 2
		if not _less(value, heap[above]): break
		heap[at] = heap[above]
		at = above
	heap[at] = value

static func _pop(heap: Array[Vector3i]) -> Vector3i:
	var result := heap[0]
	var last: Vector3i = heap.pop_back()
	if heap.is_empty(): return result
	var at := 0
	while at * 2 + 1 < heap.size():
		var child := at * 2 + 1
		if child + 1 < heap.size() and _less(heap[child + 1], heap[child]): child += 1
		if not _less(heap[child], last): break
		heap[at] = heap[child]
		at = child
	heap[at] = last
	return result
