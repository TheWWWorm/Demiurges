extends RefCounted
## Reverse land routes to the nearest usable site, bounded by a fresh day's
## movement. Reuse the same field when a cache adds another destination.

var map: ELAdventureMap
var grid: ELAdventureGrid
var budget: int
var costs := PackedInt32Array()
var distance := PackedInt32Array()

func build(board: ELAdventureMap, navigation: ELAdventureGrid, objects: Dictionary, reached: PackedByteArray, day_ap: int) -> void:
	map = board
	grid = navigation
	budget = day_ap
	costs.resize(reached.size())
	costs.fill(-1)
	distance.resize(reached.size())
	distance.fill(budget + 1)
	for offset in reached.size():
		if reached[offset] == 0 or (grid.naval and grid.naval_water[offset] != 0): continue
		costs[offset] = grid.passability(Vector2i(offset % map.width, offset / map.width))
	var sources := PackedInt32Array()
	for item: Dictionary in objects.values():
		if item.group in ["buildings", "mines", "mana_nodes", "laboratories", "factories", "resource_cuts", "artefacts", "np_heroes"] or ELAdditionalBuildings.supported(item):
			_add_sources(item, grid.footprints.get(item.uid, {}).get("size", Vector2i.ONE), sources)
	_spread(sources)

func add_cache(item: Dictionary) -> void:
	var sources := PackedInt32Array()
	_add_sources(item, Vector2i.ONE, sources)
	_spread(sources)

func _add_sources(item: Dictionary, extent: Vector2i, sources: PackedInt32Array) -> void:
	var body := Rect2i(Vector2i(item.x, item.y), extent)
	var approaches := body.grow(1).intersection(Rect2i(0, 0, map.width, map.height))
	for y in range(approaches.position.y, approaches.end.y):
		for x in range(approaches.position.x, approaches.end.x):
			if body.has_point(Vector2i(x, y)) and not ELAdventureMap.is_trail_cache(item): continue
			var offset := y * map.width + x
			if costs[offset] < 1 or distance[offset] == 0: continue
			distance[offset] = 0
			sources.append(offset)

func _spread(sources: PackedInt32Array) -> void:
	var buckets: Array[Array] = []
	for cost in budget + 1: buckets.append([])
	buckets[0].assign(sources)
	for cost in buckets.size():
		for offset: int in buckets[cost]:
			if distance[offset] != cost: continue
			# A route into this cell pays this cell's entry cost. The field
			# expands in reverse, from the destination to possible starts.
			var total := cost + costs[offset]
			if total > budget: continue
			var point := Vector2i(offset % map.width, offset / map.width)
			for delta: Vector2i in ELFirstNaval.DIRECTIONS:
				var next := point + delta
				if not grid.contains(next): continue
				var index := next.y * map.width + next.x
				if costs[index] < 1 or distance[index] <= total: continue
				if grid.naval and not ELFirstNaval.connected(grid, next, point, true, true): continue
				distance[index] = total
				buckets[total].append(index)
