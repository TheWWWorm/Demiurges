extends RefCounted
## Join all free terrain to the hero's travel network. Prefer walking around
## obstacles, then remove the decoration along a short connection. Named
## sites and the scenery that forms a guarded prize's entrance stay fixed.

var _grid: ELAdventureGrid
var _reached := PackedByteArray()
var _possible := PackedByteArray()
var _scenery := PackedInt32Array()
var _previous := PackedInt32Array()
var _seen := PackedInt32Array()
var _attempt := 0
var _removed := {}
var _widen: Callable
var _landing: Callable
var _props := {}
var _actors := {}

func repair(grid: ELAdventureGrid, start: Vector2i, props: Dictionary, actors: Dictionary, widen: Callable, landing: Callable) -> Dictionary:
	_grid = grid
	_widen = widen
	_landing = landing
	_props = props
	_actors = actors
	var count := grid.map.width * grid.map.height
	_reached.resize(count)
	_possible.resize(count)
	_scenery.resize(count)
	_scenery.fill(-1)
	_previous.resize(count)
	_seen.resize(count)
	for id: int in props:
		var footprint: Dictionary = grid.footprints[id]
		var body: Vector2i = props[id]
		for offset: Vector2i in footprint.cells:
			var cell := body + offset
			if grid.contains(cell): _scenery[_id(cell)] = id
	for id in count: _refresh_possible(id)
	var root := _id(start)
	if not _possible[root] or grid.land.is_point_solid(start): return {"error": "The starting hero has no free ground."}
	_reached[root] = 1
	_extend([root])
	var joined := 0
	var id := 0
	while id < count:
		while id < count and (_reached[id] or grid.land.is_point_solid(_point(id))): id += 1
		if id >= count: break
		var link := _find_link(id, false)
		if link.is_empty() and not grid.naval: link = _find_link(id, true)
		if link.is_empty(): return {"error": "A passable part of the map is disconnected at %s." % _point(id)}
		var earliest := _open_link(link)
		if not _reached[id]: return {"error": "Could not open the connection at %s." % _point(id)}
		joined += 1
		# A removed model or terrain corner can uncover an earlier tile.
		id = mini(id + 1, earliest)
	return {"removed": _removed, "passable": _reached.count(1), "connections": joined}

func _id(point: Vector2i) -> int:
	return point.y * _grid.map.width + point.x

func _point(id: int) -> Vector2i:
	return Vector2i(id % _grid.map.width, id / _grid.map.width)

func _refresh_possible(id: int) -> void:
	var point := _point(id)
	if not _grid.land.is_point_solid(point):
		_possible[id] = 1
		return
	_possible[id] = 0
	if _scenery[id] < 0 or _grid.blockers[id] != 1: return
	if _grid.naval:
		_possible[id] = int(ELFirstNaval.terrain_cost(_grid.map, point, false) > 0)
	else:
		var map := _grid.map
		var corners: Array[int] = [map.tile(point.x, point.y), map.tile(point.x + 1, point.y),
			map.tile(point.x + 1, point.y + 1), map.tile(point.x, point.y + 1)]
		_possible[id] = int(ELAdventureGrid.strategic_cost(map.profile.terrain_tiles, corners, map.roads[id], false) > 0)

func _extend(seeds: Array[int]) -> void:
	var cursor := 0
	while cursor < seeds.size():
		var from := _point(seeds[cursor])
		cursor += 1
		for direction: Vector2i in ELInterception.DIRECTIONS:
			var to := from + direction
			if not _grid.contains(to) or _grid.land.is_point_solid(to): continue
			var next := _id(to)
			if _reached[next]: continue
			if _grid.naval and not ELFirstNaval.connected(_grid, from, to, false, true): continue
			_reached[next] = 1
			seeds.append(next)

func _find_link(start: int, ground_connection: bool) -> Dictionary:
	_attempt += 1
	var queue := PackedInt32Array([start])
	var cursor := 0
	var candidate_landing := {}
	_seen[start] = _attempt
	_previous[start] = -1
	while cursor < queue.size():
		var id := queue[cursor]
		var from := _point(id)
		cursor += 1
		for direction: Vector2i in ELInterception.DIRECTIONS:
			var to := from + direction
			if not _grid.contains(to): continue
			var next := _id(to)
			if _seen[next] == _attempt: continue
			if _grid.naval and not _naval_step(from, to, id, next):
				var shore := _grid.naval_water[id] == 0 and _grid.naval_water[next] != 0
				var cardinal := direction.x == 0 or direction.y == 0
				if candidate_landing.is_empty() and shore and cardinal and _reached[next] and not _actors.has(from) and not _actors.has(to) and not _grid.land.is_point_solid(from):
					candidate_landing = {"land": id, "water": next}
				continue
			if not _possible[next] and not (ground_connection and _grid.blockers[next] <= int(_scenery[next] >= 0)): continue
			_previous[next] = id
			if _reached[next]: return {"path": _path(next)}
			_seen[next] = _attempt
			queue.append(next)
	if candidate_landing.is_empty(): return {}
	candidate_landing.path = _path(candidate_landing.land)
	return candidate_landing

func _naval_step(from: Vector2i, to: Vector2i, id: int, next: int) -> bool:
	var mode := _grid.naval_water[id]
	if _grid.naval_water[next] != mode: return _grid.naval_links.get(id, {}).has(next)
	if from.x == to.x or from.y == to.y: return true
	for side: Vector2i in [Vector2i(from.x, to.y), Vector2i(to.x, from.y)]:
		var index := _id(side)
		if not _possible[index] or _grid.naval_water[index] != mode: return false
	return true

func _path(end: int) -> Array[int]:
	var result: Array[int] = []
	while end >= 0:
		result.append(end)
		end = _previous[end]
	return result

func _open_link(link: Dictionary) -> int:
	var changed := {}
	var previous := -1
	for id: int in link.path:
		_open_tile(id, changed)
		if _grid.naval and previous >= 0:
			var from := _point(previous)
			var to := _point(id)
			if from.x != to.x and from.y != to.y:
				_open_tile(_id(Vector2i(from.x, to.y)), changed)
				_open_tile(_id(Vector2i(to.x, from.y)), changed)
		previous = id
	if link.has("land"):
		_landing.call(_point(link.land), _point(link.water))
		_grid.naval_links.get_or_add(link.land, {})[link.water] = true
		_grid.naval_links.get_or_add(link.water, {})[link.land] = true
		changed[link.land] = true
	var seeds: Array[int] = []
	var earliest := _reached.size()
	for id: int in changed:
		earliest = mini(earliest, id)
		var from := _point(id)
		_grid._update_cell(from)
		_refresh_possible(id)
		for direction: Vector2i in ELInterception.DIRECTIONS:
			var to := from + direction
			if _grid.contains(to) and _reached[_id(to)] and _id(to) not in seeds: seeds.append(_id(to))
	_extend(seeds)
	return earliest

func _open_tile(id: int, changed: Dictionary) -> void:
	var prop := _scenery[id]
	if prop >= 0 and not _removed.has(prop):
		_removed[prop] = true
		var origin: Vector2i = _props[prop]
		for offset: Vector2i in _grid.footprints[prop].cells:
			var tile := _id(origin + offset)
			_grid.blockers[tile] -= 1
			_scenery[tile] = -1
			changed[tile] = true
	if _possible[id] or _grid.naval: return
	var point := _point(id)
	_widen.call(point)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var neighbor := point + Vector2i(dx, dy)
			if _grid.contains(neighbor): changed[_id(neighbor)] = true
