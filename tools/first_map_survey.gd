extends SceneTree
## Measures Etherlords I maps for docs/first_map_survey.md: object counts,
## scenery masses, corridor widths, creature levels and positions by distance
## from the castles and by ground. Needs the installed first game
## (user://profiles.json). Writes one JSON file per map, optionally a
## top-down picture (walkable ground, scenery, roads, creatures, castles).
##
## Stock maps (all of Maps/, or --only=pmission02,mmission05):
##   godot --headless --path game --script ../tools/first_map_survey.gd --
##       --maps=stock --out=<dir> [--png=<dir>]
## Generated maps (preset ids, optional older generator version):
##   godot --headless --path game --script ../tools/first_map_survey.gd --
##       --maps=generated --presets=frontier,lakes --seeds=212,audit-7
##       [--version=12] --out=<dir> [--png=<dir>]
const SITE_GROUPS := ["mines", "mana_nodes", "laboratories", "factories", "artefacts", "global_spells", "forts", "resource_cuts", "additional_buildings"]
const HOME := 15
const FAR := 30

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.split("=", true, 1)[1]
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	var profile := ELProfile.new()
	if not profile.mount("el1", String(saved.get("el1", ""))):
		printerr("no el1"); quit(1); return
	var out := _arg("out", "")
	DirAccess.make_dir_recursive_absolute(out)
	var jobs: Array = []
	if _arg("maps", "stock") == "stock":
		var only := _arg("only", "")
		for file: String in DirAccess.get_files_at(String(saved.get("el1", "")).path_join("Maps")):
			if not file.ends_with(".map"): continue
			var id := file.get_basename()
			if not only.is_empty() and not id in only.split(","): continue
			jobs.append({"id": id})
	else:
		for seed: String in _arg("seeds", "212").split(","):
			for p: Dictionary in ELFirstRandomMap.presets():
				if not p.id in _arg("presets", "frontier").split(","): continue
				var options: Dictionary = ELFirstRandomMap.defaults().merged(p.options, true)
				options.seed = seed
				if not _arg("version", "").is_empty(): options.version = int(_arg("version", ""))
				jobs.append({"id": "gen_%s_%s_v%d" % [p.id, seed, int(options.version)], "options": options})
	for job: Dictionary in jobs:
		var map: ELAdventureMap
		if job.has("options"):
			var gen := ELFirstRandomMap.new()
			map = gen.generate(profile, job.options)
			if map == null:
				print("FAIL ", job.id, " ", gen.error); continue
		else:
			map = ELAdventureMap.new()
			if not map.load_map(profile, job.id):
				print("FAIL ", job.id, " ", map.error); continue
		var result := _survey(map)
		result.id = job.id
		result.kind = _kind(job.id)
		var f := FileAccess.open(out.path_join(str(job.id) + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(result))
		f.close()
		print("OK ", job.id)
	quit(0)

func _kind(id: String) -> String:
	if id.begins_with("gen_"): return "generated"
	if id.begins_with("pmission"): return "single"
	if id.begins_with("mmission"): return "multi"
	return "campaign"

func _survey(map: ELAdventureMap) -> Dictionary:
	var w := map.width
	var h := map.height
	var objects := {}
	var art := ELAdventureArt.new(map)
	for index in map.objects.size():
		var item: Dictionary = map.objects[index].duplicate()
		item.uid = index
		item.visible = ELXml.child(item.node, "hidden").is_empty()
		item.type = "hero" if item.group == "heroes" else ("monster" if item.group == "np_heroes" else "object")
		objects[index] = item
	var grid := ELAdventureGrid.new()
	if not grid.build(map, objects):
		return {"error": grid.error}
	# Masks: terrain passable (no objects), static blocked by objects, scenery cells.
	var terrain_ok := PackedByteArray(); terrain_ok.resize(w * h)
	var walk := PackedByteArray(); walk.resize(w * h)
	var scenery := PackedByteArray(); scenery.resize(w * h)
	var water := 0
	for y in h:
		for x in w:
			var i := y * w + x
			var corners: Array[int] = [map.tile(x, y), map.tile(x + 1, y), map.tile(x + 1, y + 1), map.tile(x, y + 1)]
			if corners.any(func(t: int) -> bool: return t in ELTileSet.WATER_KINDS): water += 1
			var cost := ELAdventureGrid.strategic_cost(map.profile.terrain_tiles, corners, int(map.roads[i]), false) if not grid.naval else ELFirstNaval.terrain_cost(map, Vector2i(x, y), false, false)
			var wet := corners.any(func(t: int) -> bool: return t in ELTileSet.WATER_KINDS)
			terrain_ok[i] = int(cost > 0 and not (grid.naval and wet))
			walk[i] = int(cost > 0 and grid.blockers[i] == 0)
	var props := 0
	var prop_area := 0
	var prop_names := {}
	for id: int in objects:
		var item: Dictionary = objects[id]
		if item.group != "terrain_objects": continue
		props += 1
		var shape: Dictionary = grid.footprints.get(id, {})
		prop_area += shape.get("cells", []).size()
		var family := str(item.name).to_lower().rstrip("0123456789_ ")
		prop_names[family] = int(prop_names.get(family, 0)) + 1
		for cell: Vector2i in shape.get("cells", []):
			var p := cell + Vector2i(item.x, item.y)
			if grid.contains(p): scenery[p.y * w + p.x] = 1
	var land := 0
	var scenery_land := 0
	var scenery_cells := 0
	for i in w * h:
		land += terrain_ok[i]
		scenery_cells += scenery[i]
		if terrain_ok[i] and scenery[i]: scenery_land += 1
	# Castles and home distance (land steps through walkable cells, objects ignored for reach).
	var castles: Array[Vector2i] = []
	for id: int in objects:
		var item: Dictionary = objects[id]
		if int(item.owner) > 0 and ELFirstScenario.is_castle(item): castles.append(Vector2i(item.x, item.y) + Vector2i(grid.footprints.get(id, {"size": Vector2i.ONE}).size) / 2)
	var steps := _bfs(w, h, terrain_ok, castles)
	var clearance := _clearance(w, h, walk)
	# Terrain colour of each cell.
	var color_land := {}
	var cell_color := []
	cell_color.resize(w * h)
	for y in h:
		for x in w:
			var c := ELAdventureArt.terrain_color(map.tile(x, y))
			cell_color[y * w + x] = c
			if terrain_ok[y * w + x]: color_land[c] = int(color_land.get(c, 0)) + 1
	# Zone accounting.
	var zones := {"home": {"land": 0, "scenery": 0, "sites": 0, "creatures": 0, "road": 0}, "mid": {"land": 0, "scenery": 0, "sites": 0, "creatures": 0, "road": 0}, "far": {"land": 0, "scenery": 0, "sites": 0, "creatures": 0, "road": 0}}
	var by_color := {}
	var clear_hist := {}
	var road := 0
	for y in h:
		for x in w:
			var i := y * w + x
			if not terrain_ok[i]: continue
			var zone := _zone(steps[i])
			zones[zone].land += 1
			zones[zone].scenery += scenery[i]
			var c: String = cell_color[i]
			var bc: Dictionary = by_color.get_or_add(c, {"land": 0, "scenery": 0, "sites": 0, "creatures": 0})
			bc.land += 1
			bc.scenery += scenery[i]
			if map.roads[i] > 4 and map.roads[i] < 9:
				road += 1
				zones[zone].road += 1
			if walk[i]:
				var k := str(mini(clearance[i], 8))
				clear_hist[k] = int(clear_hist.get(k, 0)) + 1
	# Sites and creatures.
	var counts := {}
	var creatures: Array = []
	var sites: Array[Vector2i] = []
	for id: int in objects:
		var item: Dictionary = objects[id]
		counts[item.group] = int(counts.get(item.group, 0)) + 1
		var at := Vector2i(item.x, item.y)
		if not grid.contains(at): continue
		var i := at.y * w + at.x
		if item.group in SITE_GROUPS or (item.group == "buildings" and int(item.owner) == 0):
			sites.append(at)
			zones[_zone(steps[i])].sites += 1
			by_color.get_or_add(cell_color[i], {"land": 0, "scenery": 0, "sites": 0, "creatures": 0}).sites += 1
	for id: int in objects:
		var item: Dictionary = objects[id]
		if item.group != "np_heroes" or not item.visible: continue
		var at := Vector2i(item.x, item.y)
		if not grid.contains(at): continue
		var i := at.y * w + at.x
		var row := ELFirstMonsters.definition(map.profile, str(item.name), 2)
		var near_site := 99
		for s: Vector2i in sites: near_site = mini(near_site, maxi(absi(s.x - at.x), absi(s.y - at.y)))
		var near_road := 99
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var p := at + Vector2i(dx, dy)
				if grid.contains(p) and map.roads[p.y * w + p.x] > 4 and map.roads[p.y * w + p.x] < 9: near_road = mini(near_road, maxi(absi(dx), absi(dy)))
		# Local corridor width: clearance of the cell with the monster removed.
		zones[_zone(steps[i])].creatures += 1
		by_color.get_or_add(cell_color[i], {"land": 0, "scenery": 0, "sites": 0, "creatures": 0}).creatures += 1
		creatures.append({"level": int(row.get("Level", 0)), "color": str(row.get("Color", "")), "ground": cell_color[i], "steps": steps[i],
			"near_site": near_site, "near_road": near_road, "clearance": clearance[i], "x": at.x, "y": at.y})
	var creature_gap: Array = []
	for a: Dictionary in creatures:
		var best := 999
		for b: Dictionary in creatures:
			if a == b: continue
			best = mini(best, maxi(absi(a.x - b.x), absi(a.y - b.y)))
		if best < 999: creature_gap.append(best)
	var site_gap: Array = []
	for a: Vector2i in sites:
		var best := 999
		for b: Vector2i in sites:
			if a != b: best = mini(best, maxi(absi(a.x - b.x), absi(a.y - b.y)))
		if best < 999: site_gap.append(best)
	# Scenery clusters (8-connected components of scenery cells).
	var clusters := _components(w, h, scenery)
	# Routes between castles: min/median clearance along the land path.
	var routes: Array = []
	for a in castles.size():
		for b in range(a + 1, castles.size()):
			var path := _route(w, h, walk, castles[a], castles[b])
			if path.is_empty(): continue
			var cl: Array = []
			for p: Vector2i in path: cl.append(clearance[p.y * w + p.x])
			cl.sort()
			routes.append({"length": path.size(), "straight": maxi(absi(castles[a].x - castles[b].x), absi(castles[a].y - castles[b].y)),
				"min_clear": cl[0], "median_clear": cl[cl.size() / 2], "narrow_pct": 100.0 * cl.filter(func(v: int) -> bool: return v <= 1).size() / cl.size()})
	# Terrain tile patches: number of distinct tile ids and mean patch size on land.
	if not _arg("png", "").is_empty():
		var img := Image.create(w * 4, h * 4, false, Image.FORMAT_RGB8)
		for y in h:
			for x in w:
				var i := y * w + x
				var c := Color("2b4f6b")
				if terrain_ok[i]: c = Color("c9c19a")
				if terrain_ok[i] and map.roads[i] > 4 and map.roads[i] < 9: c = Color("8a6a44")
				if scenery[i]: c = Color("2f4a22")
				elif grid.blockers[i] > 0: c = Color("6b5b8f")
				img.fill_rect(Rect2i(x * 4, (h - 1 - y) * 4, 4, 4), c)
		for cr: Dictionary in creatures:
			img.fill_rect(Rect2i(cr.x * 4, (h - 1 - cr.y) * 4, 4, 4), Color("e02020"))
		for c in castles:
			img.fill_rect(Rect2i(c.x * 4 - 6, (h - 1 - c.y) * 4 - 6, 12, 12), Color.WHITE)
		img.save_png(_arg("png", "").path_join(str(map.id).get_file() + ".png"))
	var max_open := 0
	for i in w * h: if walk[i]: max_open = maxi(max_open, clearance[i])
	return {"kind": _kind(map.id), "size": [w, h], "players": map.players.size(), "castles": castles.size(),
		"land": land, "water_pct": 100.0 * water / (w * h), "road_pct": 100.0 * road / maxi(land, 1),
		"scenery_props": props, "scenery_cover_pct": 100.0 * scenery_land / maxi(land, 1), "scenery_map_pct": 100.0 * scenery_cells / (w * h), "prop_mean_area": float(prop_area) / maxi(props, 1), "prop_families": prop_names,
		"scenery_clusters": clusters.count, "scenery_cluster_mean": clusters.mean, "scenery_cluster_max": clusters.max,
		"counts": counts, "zones": zones, "by_color": by_color, "color_land": color_land,
		"clearance_hist": clear_hist, "max_open": max_open, "creatures": creatures,
		"creature_gap": creature_gap, "site_gap": site_gap, "routes": routes, "relief": not map.relief.is_empty()}

func _zone(step: int) -> String:
	if step < 0: return "far"
	return "home" if step <= HOME else ("mid" if step <= FAR else "far")

func _bfs(w: int, h: int, ok: PackedByteArray, sources: Array[Vector2i]) -> PackedInt32Array:
	var d := PackedInt32Array(); d.resize(w * h); d.fill(-1)
	var q: Array[Vector2i] = []
	for s in sources:
		# Castles occupy their own cells; start from the nearest passable neighbour ring.
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var p := s + Vector2i(dx, dy)
				if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or not ok[p.y * w + p.x] or d[p.y * w + p.x] >= 0: continue
				d[p.y * w + p.x] = 0
				q.append(p)
	var head := 0
	while head < q.size():
		var c := q[head]; head += 1
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n := c + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h: continue
				var i := n.y * w + n.x
				if not ok[i] or d[i] >= 0: continue
				d[i] = d[c.y * w + c.x] + 1
				q.append(n)
	return d

## Chebyshev distance from each walkable cell to the nearest blocked cell or map edge.
func _clearance(w: int, h: int, walk: PackedByteArray) -> PackedInt32Array:
	var d := PackedInt32Array(); d.resize(w * h); d.fill(-1)
	var q: Array[Vector2i] = []
	for y in h:
		for x in w:
			if not walk[y * w + x] or x == 0 or y == 0 or x == w - 1 or y == h - 1:
				d[y * w + x] = 0
				q.append(Vector2i(x, y))
	var head := 0
	while head < q.size():
		var c := q[head]; head += 1
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n := c + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h: continue
				var i := n.y * w + n.x
				if d[i] >= 0: continue
				d[i] = d[c.y * w + c.x] + 1
				q.append(n)
	return d

func _components(w: int, h: int, mask: PackedByteArray) -> Dictionary:
	var seen := PackedByteArray(); seen.resize(w * h)
	var sizes: Array[int] = []
	for start in w * h:
		if not mask[start] or seen[start]: continue
		var q: Array[int] = [start]
		seen[start] = 1
		var head := 0
		while head < q.size():
			var c := q[head]; head += 1
			var cx := c % w
			var cy := c / w
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = cx + dx
					var ny: int = cy + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					var i := ny * w + nx
					if mask[i] and not seen[i]:
						seen[i] = 1
						q.append(i)
		sizes.append(q.size())
	if sizes.is_empty(): return {"count": 0, "mean": 0, "max": 0}
	var total := 0
	for s in sizes: total += s
	return {"count": sizes.size(), "mean": float(total) / sizes.size(), "max": sizes.max()}

func _route(w: int, h: int, walk: PackedByteArray, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, w, h)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.update()
	for y in h:
		for x in w:
			if not walk[y * w + x]: grid.set_point_solid(Vector2i(x, y), true)
	var from := _nearest_open(w, h, walk, a)
	var to := _nearest_open(w, h, walk, b)
	if from.x < 0 or to.x < 0: return []
	return grid.get_id_path(from, to)

func _nearest_open(w: int, h: int, walk: PackedByteArray, at: Vector2i) -> Vector2i:
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := at + Vector2i(dx, dy)
				if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and walk[p.y * w + p.x]: return p
	return Vector2i(-1, -1)
