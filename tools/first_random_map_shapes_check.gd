extends SceneTree
## Synthetic topology, fairness, recipe, and legacy replay checks.
## Run with Godot4.7: --headless --path game --script ../tools/first_random_map_shapes_check.gd
## --quick uses one water amount per layout; default covers all three.
## Independent floods below read terrain and real collision footprints;
## they do not call the generator's validation or naval path finder.

const Fixture = preload("first_random_map_fixture.gd")
const DailyCoverage = preload("../game/src/content/first_daily_coverage.gd")
const LAYOUTS := ["frontier", "lakes", "crossroads", "archipelago", "inland_sea", "river_delta", "ring", "peninsulas"]
const SIZES := [64, 96, 128, 160]
const WATER := ["low", "normal", "high"]
var checks := 0
var generated := 0
var validated := 0
var failures: Array[String] = []
var completed: Array[String] = []
var label := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var began := Time.get_ticks_msec()
	_configuration()
	_legacy_replay()
	_matrix()
	_regressions()
	_scenery()
	_exploration()
	_reproduction()
	label = "completion"
	check(completed.size() == 7, "every required test section completed")
	print("FIRST MAP SHAPES: %d checks, %d generated maps, %d failure(s), %.2f s" % [checks, generated, failures.size(), (Time.get_ticks_msec() - began) / 1000.0])
	for failure: String in failures: printerr("  " + failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: return
	var message := label + ": " + what
	failures.append(message)
	printerr("FAIL: " + message)

func _configuration() -> void:
	label = "shape settings"
	var defaults := ELFirstRandomMap.defaults()
	check(defaults.version == ELFirstRandomMapV2.LIVING_WILDS_VERSION and defaults.has("naval") and defaults.has("water") and defaults.has("coast"), "new recipes use guard posts and keep the naval settings schema")
	check(ELFirstRandomMap.normalize(JSON.parse_string(JSON.stringify(defaults))) == defaults, "settings survive JSON numeric conversion")
	for options: Dictionary in [{"naval": 1}, {"naval": "true"}, {"water": true}, {"water": "huge"}, {"coast": []}, {"coast": "straight"}, {"version": 1, "naval": true}]:
		check(ELFirstRandomMap.normalize(options).is_empty(), "malformed or wrong-version settings are rejected: " + JSON.stringify(options))
	for layout: String in LAYOUTS:
		check(not ELFirstRandomMap.normalize({"layout": layout, "naval": true, "water": "high", "coast": "rugged"}).is_empty(), "layout is selectable: " + layout)
	completed.append("configuration")

func _legacy_replay() -> void:
	label = "version1 replay"
	var path: String = get_script().resource_path.get_base_dir().path_join("first_random_map_v1_snapshots.json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(data is Dictionary and data.get("maps") is Array, "the pre-change synthetic snapshot fixture is readable")
	if not data is Dictionary or not data.get("maps") is Array: return
	check(data.maps.size() == 11, "snapshots cover the original three layouts and the independently recovered five layouts")
	var profile := Fixture.profile()
	for row: Dictionary in data.maps:
		var map := _generate(profile, row.config)
		if map == null: continue
		check(map.id == row.id and ELFirstRandomMap.content_hash(map) == row.hash, "original seed reproduces byte-for-byte: " + str(row.config.layout) + "/" + str(row.config.seed))
	completed.append("legacy")

func _generate(profile: ELProfile, config: Dictionary) -> ELAdventureMap:
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(profile, config)
	generated += 1
	check(map != null, "generation succeeds: " + generator.error)
	return map

func _matrix() -> void:
	var profile := Fixture.profile()
	var amounts: Array = ["normal"] if "--quick" in OS.get_cmdline_user_args() else WATER
	var index := 0
	for layout: String in LAYOUTS:
		for naval: bool in [false, true]:
			for water: String in amounts:
				var config := {"seed": "shape-matrix-%d" % index, "size": SIZES[index % SIZES.size()], "players": 2 + index % 3,
					"layout": layout, "naval": naval, "water": water, "coast": "smooth" if index % 2 == 0 else "rugged",
					"roads": index % 3 != 0, "scenery": index % 3, "guards": "none" if index % 2 == 0 else "normal"}
				label = "%s/naval%s/%s/%d/%d/%s" % [layout, naval, water, config.size, config.players, config.seed]
				var map := _generate(profile, config)
				if map != null: _geometry(map, ELFirstRandomMap.normalize(config))
				index += 1
		print("PASS: shape matrix " + layout)
	label = "shape matrix completion"
	check(index == (16 if "--quick" in OS.get_cmdline_user_args() else 48) and validated == index, "all configuration cases complete their independent geometry checks")
	completed.append("matrix")

func _regressions() -> void:
	# The two repaired archipelago cases remain in the main matrix and the
	# topology-options loop. This coast had a dry-looking approach separated
	# by diagonal shoreline cells; it must reach its actual harbor at runtime.
	label = "lakes coastal-access regression"
	var config := ELFirstRandomMap.normalize({"seed": "naval-worlds", "size": 128, "players": 4, "layout": "lakes", "naval": true})
	var before := validated
	var map := _generate(Fixture.profile(), config)
	if map != null: _geometry(map, config)
	check(validated == before + 1, "the repaired coastal-access case completes all independent geometry checks")
	completed.append("regressions")

func _listed_scenery(map: ELAdventureMap) -> Array[Dictionary]:
	return map.objects.filter(func(item: Dictionary) -> bool: return item.group == "terrain_objects")

func _scenery() -> void:
	label = "scenery versioning and coverage"
	var profile := Fixture.profile()
	var recipe := {"version": 2, "seed": "breakwater-41", "size": 128, "players": 4, "layout": "archipelago", "naval": true, "water": "high"}
	var original := _generate(profile, recipe)
	if original == null: return
	check(ELFirstRandomMap.content_hash(original) == "2228b1508c9cfa27dec544f7d3efe4026a0e77de076b860e0dded7ed9955bad1", "the original v2 island recipe still reproduces exactly")
	var second_legacy := _generate(profile, {"version": 2, "seed": "scenery-regression", "size": 64, "players": 4, "layout": "crossroads"})
	if second_legacy == null: return
	check(ELFirstRandomMap.content_hash(second_legacy) == "4ecfa7abd3b2844cc6e9ea7aea4e8d73ecea5917816154b3d7563d0ba1f1f450", "the original v2 land recipe still reproduces exactly")
	recipe.version = 3
	var standard := _generate(profile, recipe)
	var dense := _generate(profile, recipe.merged({"scenery": 2}, true))
	var minimal := _generate(profile, recipe.merged({"scenery": 0}, true))
	if standard == null or dense == null or minimal == null: return
	check(ELFirstRandomMap.content_hash(standard) == "06fd34be5df4eb9667a2ba5a7c914a0e5261b7a35c816c44a397a0f86ae958fd", "the previous scenery pass still reproduces version-3 saves")
	var decor := _listed_scenery(standard)
	check(decor.size() >= 3 * _listed_scenery(original).size(), "normal scenery substantially increases terrain detail on the sparse island seed")
	check(_listed_scenery(dense).size() > decor.size() and _listed_scenery(minimal).is_empty(), "the density control produces three distinct scenery levels")
	check(standard.terrain == original.terrain and standard.roads == original.roads and standard.get_meta("first_naval") == original.get_meta("first_naval"), "scenery preserves the original terrain, roads and harbor locations")
	check(standard.objects.filter(func(item: Dictionary) -> bool: return item.group != "terrain_objects") == original.objects.filter(func(item: Dictionary) -> bool: return item.group != "terrain_objects"), "all strategic objects and guards keep their placements")
	var center := Vector2(standard.width, standard.height) / 2.0
	for start: Dictionary in standard.get_meta("random_map_report").starts:
		var castle := Vector2(start.castle[0], start.castle[1])
		var rear := (castle - center).normalized()
		var count := 0
		for item: Dictionary in decor:
			var away := Vector2(item.x, item.y) - castle
			if away.dot(rear) > 0.0 and away.length_squared() < 15.0 * 15.0: count += 1
		check(count >= 5, "each compact homeland has scenery behind its castle")
	completed.append("scenery")

func _exploration() -> void:
	label = "landscape exploration"
	var profile := Fixture.profile()
	var map := _generate(profile, {"version": 4, "seed": "breakwater-41", "size": 128, "players": 4, "layout": "archipelago", "naval": true, "water": "high"})
	if map == null: return
	var stops: Array[Dictionary] = map.objects.filter(func(item: Dictionary) -> bool: return item.group == "additional_buildings")
	var center := Vector2(map.width, map.height) / 2.0
	for start: Dictionary in map.get_meta("random_map_report").starts:
		var castle := Vector2(start.castle[0], start.castle[1])
		var outward := (castle - center).normalized()
		var behind := stops.filter(func(item: Dictionary) -> bool:
			var direction := Vector2(item.x, item.y) - castle
			return direction.length() < 26.0 and direction.dot(outward) > 3.0 and item.name in ["SpringOfStrength", "SpringOfDexterity", "Teacher", "Magister"])
		check(behind.size() >= 2, "each homeland has two usable destinations in the backcountry")
	var state := ELAdventureSession.new()
	check(state.start(map, 2, ELFirstRandomMap.seed_for_config(ELFirstRandomMap.configuration(map))), "the expedition world starts")
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "the expedition navigation builds: " + director.error)
		state.close()
		return
	var hero := state.object(state.main_hero)
	var from := Vector2i(hero.x, hero.y)
	var lake := {}
	var lake_path: Array[Vector2i] = []
	var bowl := {}
	var lairs := 0
	for item: Dictionary in state.objects.values():
		if item.name == ELAdditionalBuildings.BOWL: bowl = item
		if item.name == ELAdditionalBuildings.LAKE:
			var candidate := director.grid.approach(from, item)
			if not candidate.is_empty() and (lake_path.is_empty() or candidate.size() < lake_path.size()):
				lake = item
				lake_path = candidate
		if ELAdditionalBuildings.DUNGEONS.has(item.name):
			var inhabitant := state.object(item.monster)
			check(inhabitant.get("alive", false) and not inhabitant.get("placed", true) and inhabitant.get("dungeon") == item.uid, "the standard lair restock populates generated dungeons")
			lairs += 1
	check(lairs >= 4, "both homelands and neutral islands offer lair encounters")
	check(not lake.is_empty() and not bowl.is_empty() and ELAdditionalBuildings.barrier_key(lake) == ELAdditionalBuildings.barrier_key(bowl), "the reachable Seer points to a remote discovery")
	if not lake_path.is_empty() and not bowl.is_empty():
		hero.x = lake_path[-1].x
		hero.y = lake_path[-1].y
		director.grid.update_actor(hero)
		director.use_object(hero.uid, lake.uid)
		check(state.players[1].get("scry", []).has(bowl.uid) and ELFog.shown(state, 1, bowl), "visiting the Seer reveals the remote crystal ball through fog")
		var codec := ELAdventureSave.new()
		var restored := codec.decode(JSON.parse_string(JSON.stringify(codec.encode(director), "", true, true)), {"el1": profile})
		check(not restored.is_empty(), "expedition discoveries and lair occupants survive a save: " + codec.error)
		if not restored.is_empty():
			check(restored.state.players[1].get("scry", []).has(bowl.uid), "the discovered sight source is restored")
			restored.state.close()
	state.close()
	completed.append("exploration")

func _geometry(map: ELAdventureMap, config: Dictionary) -> void:
	check(map.width == config.size and map.height == config.size and map.players.size() == config.players, "size and player count match the recipe")
	check(ELFirstRandomMap.configuration(map) == config, "the complete canonical recipe is attached")
	if config.version >= ELFirstRandomMapV2.FRONTIERS_VERSION and not config.naval and config.layout in ["frontier", "crossroads", "lakes"]:
		var wet_edges := 0
		for i in map.width + 1:
			for point: Vector2i in [Vector2i(i, 0), Vector2i(i, map.height), Vector2i(0, i), Vector2i(map.width, i)]:
				if map.tile(point.x, point.y) in ELTileSet.WATER_KINDS: wet_edges += 1
		check(wet_edges < (map.width + 1) * 2, "the land layout keeps most of its boundary dry")
		if config.layout == "crossroads":
			var center := Vector2i(map.width, map.height) / 2
			check(map.tile(center.x, center.y) not in ELTileSet.WATER_KINDS, "the central crossroads is on dry land")
			check(map.terrain.count(16) > map.width, "water still separates some of the outer approaches")
	var state := ELAdventureSession.new()
	if not state.start(map, 1, ELFirstRandomMap.seed_for_config(config)):
		check(false, "the generated session starts: " + state.error)
		state.close()
		return
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "the real navigation graph builds: " + director.error)
		state.close()
		return
	var grid := director.grid
	check(grid.naval == config.naval, "naval movement is enabled only when requested")
	var modes := _modes(map, grid)
	var collision_free := true
	for count: int in grid.blockers:
		if count > 1: collision_free = false
	for count: int in grid.actor_blockers:
		if count > 1: collision_free = false
	check(collision_free, "actual static and actor footprints do not overlap")
	var ports: Array = map.get_meta("first_naval", {}).get("ports", [])
	var links := _links(map, ports)
	var first := state.object(state.main_hero)
	var from := Vector2i(int(first.x), int(first.y))
	var reachable := _flood(map, modes, from, links, bool(config.naval))
	if config.version >= ELFirstRandomMapV2.GUARDED_PRIZES_VERSION:
		var passable := modes.count(1) + (modes.count(2) if config.naval else 0)
		check(reachable.count(1) == passable and int(map.get_meta("random_map_report").connected_passable_cells) == passable,
			"all passable tiles connect to the travel network after occupants clear")
	if config.version >= ELFirstRandomMapV2.RELIEF_VERSION:
		var travel: Dictionary = map.get_meta("random_map_report")
		var budget := int(travel.get("wilderness_travel_ap", travel.daily_travel_ap))
		var coverage := DailyCoverage.new()
		var residents := {}
		for item: Dictionary in state.objects.values():
			if item.get("alive", false) and item.get("visible", false) and item.get("placed", true): residents[item.uid] = item
		coverage.build(map, grid, residents, reachable, budget, config.version >= ELFirstRandomMapV2.GUARDED_PRIZES_VERSION)
		var missed := 0
		for index in coverage.costs.size():
			if coverage.costs[index] > 0 and coverage.distance[index] > budget: missed += 1
		check(missed == 0, "final runtime grid has an encounter or interaction within the travel budget on each reachable land tile")
	var unreachable: Array[String] = []
	for item: Dictionary in state.objects.values():
		if item.group == "terrain_objects" or not item.get("visible", true): continue
		if item.type in ["hero", "monster"]:
			if not reachable[int(item.y) * map.width + int(item.x)]: unreachable.append(str(item.name))
		elif not _approachable(map, grid, item, reachable): unreachable.append(str(item.name))
	check(unreachable.is_empty(), "independent terrain/footprint flood reaches all strategic objects: " + ", ".join(unreachable.slice(0, 4)))
	var generation: Dictionary = map.get_meta("random_map_report", {})
	if config.version >= ELFirstRandomMapV2.GUARD_POSTS_VERSION: _field_guards(director, generation, modes, links)
	var starts: Array = generation.get("starts", [])
	check(starts.size() == config.players, "every homeland exposes its opening economy")
	if config.version >= ELFirstRandomMapV2.RELIEF_VERSION:
		check(map.relief.size() == map.terrain.size() and map.relief.count(0) < map.relief.size(), "new maps have a varied surface on the corner grid")
		var level_water := true
		for index in map.terrain.size():
			if int(map.terrain[index]) in ELTileSet.WATER_KINDS and map.relief[index] != 0: level_water = false
		check(level_water, "rivers and harbors retain a flat water surface")
	var safe_modes := modes.duplicate()
	if config.version >= ELFirstRandomMapV2.WILDERNESS_VERSION:
		var field: PackedByteArray = map.get_meta("wilderness_detail", PackedByteArray())
		check(field.size() == (map.width + 1) * (map.height + 1) * 3, "continuous ground detail covers the entire map")
		var limit := 34 if config.version >= ELFirstRandomMapV2.GUARDED_PRIZES_VERSION else 22
		check(int(generation.get("wilderness_distance", 0x7fff)) < limit, "reachable wilderness has nearby activities across the playable land")
		for point: Vector2i in director.interception.cells: safe_modes[point.y * map.width + point.x] = 0
	var balances := {}
	var wallet_fair := true
	var homes_valid := true
	var port_counts: Array[int] = []
	for start: Dictionary in starts:
		var hero := state.object(int(start.hero_id))
		var at := Vector2i(int(hero.x), int(hero.y))
		homes_valid = homes_valid and modes[at.y * map.width + at.x] == 1 and not hero.ship
		var land := _flood(map, safe_modes, at, {}, bool(config.naval), 1)
		var nearby_ports := 0
		for port: Dictionary in ports:
			if land[int(port.land[1]) * map.width + int(port.land[0])]: nearby_ports += 1
		port_counts.append(nearby_ports)
		var sites: Array = start.get("sites", [])
		var local_economy := sites.size() == 7
		for uid: int in sites: local_economy = local_economy and _approachable(map, grid, state.object(uid), land)
		check(local_economy, "player%d can reach all seven opening economy sites by land" % int(start.player))
		if config.version >= ELFirstRandomMapV2.WILDERNESS_VERSION:
			check(start.rewards.all(func(uid: int) -> bool: return _approachable(map, grid, state.object(uid), land)), "player%d can recruit without an opening duel or sea crossing" % int(start.player))
			if config.guards != "none":
				var guard := state.object(start.get("opening_guard", -1))
				if guard.is_empty():
					var lair := state.object(start.get("opening_lair", -1))
					guard = state.object(lair.get("monster", -1))
					check(_approachable(map, grid, lair, land), "player%d can visit their starter lair easily" % int(start.player))
				check(guard.get("alive", false) and guard.get("level") == 1, "player%d has a level-one opening encounter" % int(start.player))
		var wallet: Dictionary = state.players[int(start.player)].resources
		if balances.is_empty(): balances = wallet.duplicate()
		wallet_fair = wallet_fair and wallet == balances
	check(homes_valid and wallet_fair, "all starting heroes occupy legal land and every player receives equal resources")
	if config.naval:
		check(ports.size() >= config.players * 2 and port_counts.all(func(value: int) -> bool: return value >= 2), "each inhabited homeland has at least two usable harbors")
		var valid_ports := true
		var unique := {}
		for port: Dictionary in ports:
			var a := Vector2i(int(port.land[0]), int(port.land[1]))
			var b := Vector2i(int(port.water[0]), int(port.water[1]))
			var key := "%s/%s" % [a, b]
			valid_ports = valid_ports and not unique.has(key) and abs(a.x - b.x) + abs(a.y - b.y) == 1 and modes[a.y * map.width + a.x] == 1 and modes[b.y * map.width + b.x] == 2
			unique[key] = true
		check(valid_ports, "all harbor endpoints are unique, adjacent, unblocked land/sea pairs")
		if not ports.is_empty():
			var sea := _flood(map, modes, Vector2i(ports[0].water[0], ports[0].water[1]), {}, true, 2)
			check(ports.all(func(port: Dictionary) -> bool: return sea[int(port.water[1]) * map.width + int(port.water[0])] != 0), "all harbors share an independently connected sea")
		if config.layout == "archipelago":
			var land := _flood(map, modes, from, {}, true, 1)
			var separated := false
			for start: Dictionary in starts:
				var hero := state.object(int(start.hero_id))
				if not land[int(hero.y) * map.width + int(hero.x)]: separated = true
			check(separated, "archipelago players occupy genuinely separate islands requiring a voyage")
	else:
		check(ports.is_empty(), "non-naval maps do not advertise unusable harbors")
	state.close()
	validated += 1

func _field_guards(director: ELAdventureDirector, generation: Dictionary, modes: PackedByteArray, links: Dictionary) -> void:
	var map := director.state.map
	var grid := director.grid
	var guards := director.interception.zones
	var posts := {}
	for site_id: int in generation.get("reward_guards", {}):
		var id: int = generation.reward_guards[site_id]
		var site := director.state.object(site_id)
		var body := Rect2i(Vector2i(site.x, site.y), grid.footprints[site_id].size)
		var zone: Array = guards.get(id, {}).get("cells", [])
		var covers_approach := zone.any(func(point: Vector2i) -> bool:
			return not body.has_point(point) and body.grow(1).has_point(point) and grid.passability(point) > 0
		)
		check(covers_approach, "a site guard's real interception area includes an interaction tile")
		posts[id] = true
	for id: int in generation.get("passage_guards", {}):
		var zone: Dictionary = guards[id]
		var ends: Array = generation.passage_guards[id]
		var bounds := Rect2i(zone.origin - Vector2i.ONE * 6, Vector2i.ONE * 13)
		var endpoint: Vector2i = ends[1]
		var index := endpoint.y * map.width + endpoint.x
		var open := modes.duplicate()
		for at: int in open.size():
			if grid.actor_blockers[at] > 0: open[at] = 0
		var walked := _flood(map, open, ends[0], links, grid.naval, 1, bounds)
		for at: Vector2i in zone.cells: open[at.y * map.width + at.x] = 0
		var safe := _flood(map, open, ends[0], links, grid.naval, 1, bounds)
		check(walked[index] != 0 and safe[index] == 0, "a passage has two connected sides and crossing the gap enters the creature's zone")
		posts[id] = true
	# Version 12 roaming creatures stand in the open, clear of the map edge.
	for id: int in generation.get("roaming_creatures", []):
		var origin: Vector2i = guards[id].origin
		check(origin.x >= 4 and origin.y >= 4 and origin.x < map.width - 4 and origin.y < map.height - 4, "a roaming creature stands clear of the map edge")
		posts[id] = true
	check(posts.size() == guards.size() and guards.keys().all(func(id: int) -> bool: return posts.has(id)),
		"every field creature controls a site approach or a navigable passage, or roams the wilderness")

func _modes(map: ELAdventureMap, grid: ELAdventureGrid) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var index := y * map.width + x
			if grid.blockers[index] > 0: continue
			if not grid.naval and int(map.get_meta("random_map").version) >= ELFirstRandomMapV2.GUARDED_PRIZES_VERSION:
				var corners: Array[int] = [map.tile(x,y), map.tile(x+1,y), map.tile(x+1,y+1), map.tile(x,y+1)]
				result[index] = int(ELAdventureGrid.strategic_cost(map.profile.terrain_tiles, corners, map.roads[index], false) > 0)
				continue
			var wet := false
			var valid := true
			for dy in 2:
				for dx in 2:
					var kind := map.tile(x + dx, y + dy)
					if kind == 16: wet = true
					elif int(map.profile.terrain_tiles.types.get(kind, {}).get("movement", -1)) < 0: valid = false
			if valid: result[index] = 2 if wet else 1
	return result

func _links(map: ELAdventureMap, ports: Array) -> Dictionary:
	var result := {}
	for port: Dictionary in ports:
		var a := int(port.land[1]) * map.width + int(port.land[0])
		var b := int(port.water[1]) * map.width + int(port.water[0])
		result.get_or_add(a, {})[b] = true
		result.get_or_add(b, {})[a] = true
	return result

func _flood(map: ELAdventureMap, modes: PackedByteArray, start: Vector2i, links: Dictionary, naval: bool, only_mode := 0, bounds := Rect2i()) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(modes.size())
	var initial := start.y * map.width + start.x
	if initial < 0 or initial >= modes.size() or modes[initial] == 0: return seen
	var queue := PackedInt32Array([initial])
	seen[initial] = 1
	var cursor := 0
	while cursor < queue.size():
		var id := queue[cursor]
		cursor += 1
		var x := id % map.width
		var y := id / map.width
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= map.width or ny >= map.height: continue
				if bounds.has_area() and not bounds.has_point(Vector2i(nx, ny)): continue
				var next := ny * map.width + nx
				if seen[next] or modes[next] == 0 or (only_mode > 0 and modes[next] != only_mode) or (not naval and modes[next] != 1): continue
				if modes[id] != modes[next] and not links.get(id, {}).has(next): continue
				if naval and dx != 0 and dy != 0:
					if modes[y * map.width + nx] != modes[id] or modes[ny * map.width + x] != modes[id]: continue
				seen[next] = 1
				queue.append(next)
	return seen

func _approachable(map: ELAdventureMap, grid: ELAdventureGrid, item: Dictionary, seen: PackedByteArray) -> bool:
	if item.is_empty(): return false
	var size: Vector2i = grid.footprints.get(int(item.uid), {}).get("size", Vector2i.ONE)
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and y >= 0 and x < size.x and y < size.y: continue
			var nx := int(item.x) + x
			var ny := int(item.y) + y
			if nx >= 0 and ny >= 0 and nx < map.width and ny < map.height and seen[ny * map.width + nx]: return true
	return false

func _reproduction() -> void:
	label = "shape determinism and variation"
	var profile := Fixture.profile()
	var terrains := {}
	for layout: String in LAYOUTS:
		label = "shape reproduction/" + layout
		var config := {"seed": "repeatable-shapes", "layout": layout, "naval": true, "size": 96, "players": 4, "coast": "rugged", "water": "normal"}
		var first := _generate(profile, config)
		var repeated := _generate(profile, JSON.parse_string(JSON.stringify(config)))
		if first == null or repeated == null: continue
		check(ELFirstRandomMap.content_hash(first) == ELFirstRandomMap.content_hash(repeated) and first.get_meta("first_naval", {}) == repeated.get_meta("first_naval", {}), "same JSON recipe reproduces terrain, content, and harbors for " + layout)
		terrains[first.terrain.hex_encode().sha256_text()] = true
	check(terrains.size() == LAYOUTS.size(), "all eight layouts create distinct geography with the same seed and settings")
	var hashes := {}
	for water: String in WATER:
		for coast: String in ["smooth", "rugged"]:
			label = "topology options/" + water + "/" + coast
			var map := _generate(profile, {"seed": "topology-options", "size": 96, "layout": "archipelago", "naval": true, "water": water, "coast": coast})
			if map != null: hashes[map.terrain.hex_encode().sha256_text()] = true
	label = "topology options"
	check(hashes.size() == 6, "water amount and coastline controls change actual terrain")
	completed.append("reproducibility")
