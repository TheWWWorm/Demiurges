extends RefCounted
## Evaluate field encounters on the finished movement grid.
const AXES := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1)]
const NO_CELL := Vector2i(-1, -1)

var grid: ELAdventureGrid
var protected: PackedByteArray
var paths: PackedByteArray

func _init(navigation: ELAdventureGrid, safe_cells: PackedByteArray, travel_paths: PackedByteArray) -> void:
	grid = navigation
	protected = safe_cells
	paths = travel_paths

func site_guard(site: Dictionary, origin: Vector2i, spaced: PackedByteArray) -> Dictionary:
	var body := Rect2i(Vector2i(site.x, site.y), grid.footprints[site.uid].size)
	var stands: Array[Vector2i] = []
	for at: Vector2i in _cells(body.grow(1)):
		if not body.has_point(at) and _land(at): stands.append(at)
	if stands.is_empty(): return {}
	stands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var first := origin.distance_squared_to(a)
		var second := origin.distance_squared_to(b)
		return first < second if first != second else _index(a) < _index(b))
	var candidates: Array[Dictionary] = []
	for at: Vector2i in _cells(body.grow(2)):
		if body.has_point(at) or not _available(at, spaced): continue
		var zone := ELInterception.flood(grid, at, 2)
		var covered := 0
		var remaining := 0
		var score := 0.0
		for index in stands.size():
			var stand := stands[index]
			if stand == at: continue
			remaining += 1
			if stand not in zone: continue
			covered += 1
			score += 2.0 + (2.0 if paths[_index(stand)] != 0 else 0.0) + (2.0 if index == 0 else 0.0)
		if covered == 0: continue
		var full := covered == remaining
		score += (10.0 if full else 0.0) - origin.distance_squared_to(at) * 0.004
		candidates.append({"guard": at, "full": full, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.score > b.score if a.score != b.score else _index(a.guard) < _index(b.guard))
	for candidate: Dictionary in candidates:
		if _body_leaves_route(candidate.guard): return candidate
	return {}

func pass_candidate(at: Vector2i, spaced: PackedByteArray) -> bool:
	if not _available(at, spaced): return false
	for axis: Vector2i in AXES:
		if _wall(at, axis) and _wall(at, -axis): return true
	return false

## The zone must separate two usable sides locally. The actor's occupied
## tile alone must leave both sides connected.
func crossing(at: Vector2i) -> Array[Vector2i]:
	if not _body_leaves_route(at): return []
	var bounds := Rect2i(at - Vector2i.ONE * 6, Vector2i.ONE * 13)
	var zone := {}
	for cell: Vector2i in ELInterception.flood(grid, at, 2): zone[cell] = true
	var fringe := {}
	for cell: Vector2i in zone:
		if cell == at: continue
		for next: Vector2i in _neighbors(cell, at):
			if not zone.has(next): fringe[next] = true
	var ends: Array[Vector2i] = []
	while not fringe.is_empty():
		var entrance: Vector2i = fringe.keys()[0]
		var region := _flood(entrance, bounds, at, zone)
		for cell: Vector2i in region: fringe.erase(cell)
		if region.size() < 12: continue
		# On a coast, the interception ring can reach over a diagonal
		# that the movement grid cannot traverse. Check both sides with
		# the body present before treating the zone as the separator.
		var walked := _flood(entrance, bounds, at)
		for other: Vector2i in ends:
			if walked.has(other): return [other, entrance]
		ends.append(entrance)
	return []

## A roaming creature's post: open land away from the map edge, outside
## every protected opening route and its interception zone, off harbor
## links, and with a local detour around its occupied tile. Unlike guard
## posts it may stand on tracks and roads, as stock creatures often do.
func field_cell(at: Vector2i, spaced: PackedByteArray, margin: int) -> bool:
	if at.x < margin or at.y < margin or at.x >= grid.map.width - margin or at.y >= grid.map.height - margin: return false
	if not _land(at) or spaced[_index(at)] != 0 or protected[_index(at)] != 0: return false
	for delta: Vector2i in ELInterception.DIRECTIONS:
		var near := at + delta
		if not grid.contains(near) or protected[_index(near)] != 0 or grid.naval_links.has(_index(near)): return false
	return _body_leaves_route(at)

func _wall(at: Vector2i, direction: Vector2i) -> bool:
	for distance: int in [1, 2]:
		var point := at + direction * distance
		if grid.contains(point) and grid.actor_blockers[_index(point)] == 0 and not _land(point): return true
	return false

func _available(at: Vector2i, spaced: PackedByteArray) -> bool:
	if at.x < 2 or at.y < 2 or at.x >= grid.map.width - 2 or at.y >= grid.map.height - 2 or not _land(at): return false
	if spaced[_index(at)] != 0 or paths[_index(at)] != 0 or protected[_index(at)] != 0: return false
	for delta: Vector2i in ELInterception.DIRECTIONS:
		if protected[_index(at + delta)] != 0: return false
	return true

func _body_leaves_route(at: Vector2i) -> bool:
	# A harbor edge would need a mixed-mode detour, so its endpoints are
	# kept free independently of the land check.
	if grid.naval_links.has(_index(at)): return false
	var neighbors := _neighbors(at)
	if neighbors.is_empty(): return false
	var bounds := Rect2i(at - Vector2i.ONE * 4, Vector2i.ONE * 9)
	var reached := _flood(neighbors[0], bounds, at)
	return neighbors.all(func(cell: Vector2i) -> bool: return reached.has(cell))

func _flood(start: Vector2i, bounds: Rect2i, body: Vector2i, closed := {}) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var at := queue[cursor]
		cursor += 1
		for next: Vector2i in _neighbors(at, body):
			if bounds.has_point(next) and not seen.has(next) and not closed.has(next):
				seen[next] = true
				queue.append(next)
	return seen

func _neighbors(at: Vector2i, body := NO_CELL) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction: Vector2i in ELInterception.DIRECTIONS:
		var next := at + direction
		if next == body or not _land(next): continue
		if grid.naval and direction.x != 0 and direction.y != 0:
			var side_x := Vector2i(next.x, at.y)
			var side_y := Vector2i(at.x, next.y)
			if side_x == body or side_y == body or not _land(side_x) or not _land(side_y): continue
		result.append(next)
	return result

func _cells(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var bounds := area.intersection(Rect2i(0, 0, grid.map.width, grid.map.height))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x): cells.append(Vector2i(x, y))
	return cells

func _land(at: Vector2i) -> bool:
	return grid.contains(at) and not grid.land.is_point_solid(at) and (not grid.naval or grid.naval_water[_index(at)] == 0)

func _index(at: Vector2i) -> int:
	return at.y * grid.map.width + at.x
