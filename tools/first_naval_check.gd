extends SceneTree
## Asset-free integration checks for opt-in first-game naval movement.
##   godot --headless --path game --script ../tools/first_naval_check.gd
## --runtime-only skips the generated-map checkpoint section during development.
## No original game assets, settings, user saves, or Hall of Fame are written.

const Fixture = preload("first_naval_fixture.gd")
const Content = preload("first_random_map_fixture.gd")
var failures: Array[String] = []
var checks := 0
var completed: Array[String] = []
var label := ""
var trace: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var began := Time.get_ticks_msec()
	_geometry()
	_free_movement()
	_normal_turns()
	_blocked_routes()
	_legacy_modes()
	_ai_crossing(false)
	_ai_crossing(true)
	if "--runtime-only" not in OS.get_cmdline_user_args(): _persistence()
	label = "completion"
	check(completed.size() == (7 if "--runtime-only" in OS.get_cmdline_user_args() else 8), "every required section reached its end")
	print("FIRST NAVAL: %d checks, %d sections, %d failure(s), %.2f s" % [checks, completed.size(), failures.size(), (Time.get_ticks_msec() - began) / 1000.0])
	for failure: String in failures: printerr("  " + failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: return
	var message := label + ": " + what
	failures.append(message)
	printerr("FAIL: " + message)

func _world(map: ELAdventureMap = null, free := false) -> ELAdventureDirector:
	if map == null: map = Fixture.world()
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 217):
		check(false, "synthetic session starts: " + state.error)
		state.close()
		return null
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "synthetic navigation builds: " + director.error)
		state.close()
		return null
	director.free_movement = free
	director.fast_mode = true
	state.explored.fill(0xff)
	ELFog.refresh(state)
	ELFog.reveal_for_console(state, 1, true)
	director.presentation.connect(_record.bind(director))
	trace.clear()
	return director

func _record(data: Dictionary, director: ELAdventureDirector) -> void:
	if data.get("kind") != "actor_moving": return
	var hero := director.state.object(int(data.get("id", -1)))
	if hero.is_empty(): return
	trace.append({"id": int(hero.uid), "x": int(hero.x), "y": int(hero.y), "ship": bool(hero.get("ship", false)), "ap": int(hero.ap)})

func _drive(director: ELAdventureDirector, limit := 8000) -> bool:
	for frame in limit:
		if not director.error.is_empty() or not director.state.error.is_empty() or director.encounter != null or not director.state.outcome.is_empty(): return false
		if director.strategy.is_empty() and director.movement.is_empty() and director.free_queue.is_empty(): return true
		director.advance(0.05)
	return false

func _position(hero: Dictionary) -> Vector2i:
	return Vector2i(int(hero.x), int(hero.y))

func _put(director: ELAdventureDirector, hero: Dictionary, at: Vector2i) -> void:
	hero.x = at.x
	hero.y = at.y
	hero.ship = ELFirstNaval.enabled(director.state.map) and ELFirstNaval.is_water(director.state.map, at)
	hero.intercepted = false
	hero.strategy_order = {}
	director.grid.update_actor(hero)
	director.interception.rebuild(director.state, director.grid)

func _free_order(director: ELAdventureDirector, hero: Dictionary, destination: Vector2i, use := -1) -> bool:
	if not director.request_move(int(hero.uid), destination, use): return false
	if not director.request_move(int(hero.uid), destination, use): return false
	return _drive(director)

func _geometry() -> void:
	label = "navigation geometry"
	var director := _world()
	if director == null: return
	var grid := director.grid
	check(grid.naval and ELFirstNaval.enabled(director.state.map), "explicit first-game metadata enables naval routing")
	check(not ELFirstNaval.is_water(grid.map, Fixture.LEFT_LAND) and ELFirstNaval.is_water(grid.map, Fixture.LEFT_WATER), "mixed shoreline cells form a contiguous sea edge")
	var path := grid.path(Fixture.LEFT_LAND, Fixture.RIGHT_LAND)
	check(not path.is_empty(), "a route connects the two shores through their harbors")
	check(path.has(Fixture.LEFT_WATER) and path.has(Fixture.RIGHT_WATER), "the route actually sails across the sea")
	check(path.size() == 13 and grid.path_cost(path) == 19, "crossing costs embark4 + sea10 + landing5 = 19")
	check(ELFirstNaval.step_cost(grid, Fixture.LEFT_LAND, Fixture.LEFT_WATER) == 4, "boarding charges sea cost plus transfer")
	check(ELFirstNaval.step_cost(grid, Fixture.RIGHT_WATER, Fixture.RIGHT_LAND) == 5, "landing charges ground cost plus transfer")
	check(ELFirstNaval.step_cost(grid, Vector2i(22, 15), Vector2i(23, 15)) < 0, "an unregistered coast is not an embarkation point")
	check(ELFirstNaval.step_cost(grid, Vector2i(22, 15), Fixture.LEFT_WATER) < 0, "a diagonal coastal move cannot bypass a harbor")
	check(ELFirstNaval.step_cost(grid, Vector2i(25, 15), Vector2i(27, 15)) < 0, "sailing never skips cells")
	var legal := true
	for index in range(1, path.size()): legal = legal and ELFirstNaval.step_cost(grid, path[index - 1], path[index]) > 0
	check(legal, "every planned path edge is executable")
	director.state.close()
	completed.append("geometry")

func _free_movement() -> void:
	label = "human free movement"
	var director := _world(null, true)
	if director == null: return
	var hero := director.state.object(director.state.main_hero)
	check(not hero.ship and int(hero.ap) == 12, "hero begins on foot with the template's movement points")
	check(_free_order(director, hero, Vector2i(29, 16)), "ordinary player move requests execute a voyage immediately")
	check(_position(hero) == Vector2i(29, 16) and hero.ship and int(hero.ap) == 2, "boarding and six sea steps cost exactly ten points")
	check(_free_order(director, hero, Fixture.RIGHT_LAND), "an over-budget voyage advances only as far as available points allow")
	# Equal-cost eight-way sea routes may use either diagonal; every such
	# shortest route reaches column31 after the eight remaining sea steps.
	check(_position(hero).x == 31 and hero.ship and int(hero.ap) == 0 and not hero.strategy_order.is_empty(), "exhausted hero remains at sea with its destination retained (position=%s, ship=%s, ap=%s)" % [_position(hero), hero.ship, hero.ap])
	_put(director, hero, Fixture.RIGHT_WATER)
	hero.ap = 4
	check(_free_order(director, hero, Fixture.RIGHT_LAND), "an affordable route can remain planned while landing is unaffordable")
	check(_position(hero) == Fixture.RIGHT_WATER and hero.ship and int(hero.ap) == 4, "four points cannot pay a five-point landing")
	hero.ap = 5
	check(director.request_move(int(hero.uid), Fixture.RIGHT_LAND) and _drive(director), "the pending landing executes when enough points are available")
	check(_position(hero) == Fixture.RIGHT_LAND and not hero.ship and int(hero.ap) == 0, "landing restores the hero form and spends its exact cost")
	check(trace.any(func(row: Dictionary) -> bool: return row.id == hero.uid and row.ship), "movement events include the sailing form")
	check(trace.all(func(row: Dictionary) -> bool: return row.ap >= 0), "movement never produces negative action points")
	director.state.close()
	completed.append("free")

func _normal_turns() -> void:
	label = "human turn-based voyage"
	var director := _world()
	if director == null: return
	director._strategic_players = [1, 2]
	var state := director.state
	var hero := state.object(state.main_hero)
	var destination := Vector2i(35, 16)
	check(director.request_move(int(hero.uid), destination), "the normal turn system accepts a distant shore order")
	check(_position(hero) == Fixture.LEFT_LAND and not hero.ship, "planning alone does not move or board the hero")
	var day := int(state.day)
	check(director.submit_strategy_turn(1, day) and director.submit_strategy_turn(2, day) and _drive(director), "the actual strategic turn resolves the first voyage segment")
	check(state.day == day + 1 and _position(hero).x == 31 and hero.ship, "a turn can end with a hero sailing between shores (day=%s, position=%s, ship=%s, ap=%s)" % [state.day, _position(hero), hero.ship, hero.ap])
	check(int(hero.ap) == int(hero.strategy_capacity) and not hero.strategy_order.is_empty(), "daily refresh restores movement without clearing the voyage")
	day = int(state.day)
	check(director.submit_strategy_turn(1, day) and director.submit_strategy_turn(2, day) and _drive(director), "the next real turn resumes the queued voyage")
	check(_position(hero) == destination and not hero.ship and hero.strategy_order.is_empty(), "the continued order lands and reaches its final ground destination")
	check(trace.all(func(row: Dictionary) -> bool: return row.ap >= 0), "both turns respect their movement budgets")
	state.close()
	completed.append("turns")

func _blocked_routes() -> void:
	label = "blocked coasts and dynamic occupancy"
	var map := Fixture.world()
	Fixture.place(map, "heroes", ELCatalog.HEROES.Green, Fixture.LEFT_WATER, 1, "Green")
	var director := _world(map, true)
	if director == null: return
	var hero := director.state.object(director.state.main_hero)
	check(director.grid.path(Fixture.LEFT_LAND, Fixture.RIGHT_LAND).is_empty(), "a blocked only harbor makes the distant shore unreachable")
	check(not director.request_move(int(hero.uid), Fixture.RIGHT_LAND) and _position(hero) == Fixture.LEFT_LAND, "the player receives a refused route rather than walking through a blocked harbor")
	director.state.close()
	director = _world(null, true)
	if director == null: return
	hero = director.state.object(director.state.main_hero)
	check(director.request_move(int(hero.uid), Vector2i(29, 16)) and director.request_move(int(hero.uid), Vector2i(29, 16)), "a voyage is queued before a new obstruction arrives")
	ELStrategy.advance(director)
	var blocker: Dictionary = hero.duplicate(true)
	blocker.uid = 1001
	blocker.x = Fixture.LEFT_WATER.x
	blocker.y = Fixture.LEFT_WATER.y
	blocker.ship = true
	blocker.strategy_order = {}
	director.state.objects[1001] = blocker
	director.grid.update_actor(blocker)
	check(_drive(director), "a dynamic obstruction stops the in-flight route safely")
	check(_position(hero) == Fixture.LEFT_LAND and not hero.ship and int(hero.ap) == 12, "occupied embarkation does not overlap actors or spend movement")
	director.state.close()
	director = _world()
	if director == null: return
	hero = director.state.object(director.state.main_hero)
	var enemy := director.state.object(1)
	_put(director, hero, Fixture.RIGHT_WATER)
	_put(director, enemy, Fixture.RIGHT_LAND)
	check(director.grid.approach(Fixture.RIGHT_WATER, enemy) == [Fixture.RIGHT_WATER] and ELStrategy.adjacent(director, hero, enemy), "a hostile landing blockade can be contested across the registered harbor edge")
	check(director.grid.path(Fixture.RIGHT_WATER, Fixture.RIGHT_LAND).is_empty(), "contesting a harbor does not permit entering an occupied landing tile")
	_put(director, hero, Vector2i(33, 15))
	_put(director, enemy, Vector2i(34, 15))
	check(not ELStrategy.adjacent(director, hero, enemy), "an arbitrary shore does not allow a cross-mode attack")
	director.state.close()
	map = Fixture.world()
	Fixture.place(map, "terrain_objects", "FixtureBlock", Fixture.LEFT_WATER)
	var blocked := ELAdventureSession.new()
	check(blocked.start(map), "a static-blocker validation fixture starts")
	var blocked_grid := ELAdventureGrid.new()
	check(not blocked_grid.build(map, blocked.objects) and not blocked_grid.error.is_empty(), "permanently obstructed harbor metadata is rejected clearly at initialization")
	blocked.close()
	var invalid := Fixture.world()
	invalid.set_meta("first_naval", {"version": 1, "ports": [{"land": [22, 16], "water": [24, 16]}]})
	var grid := ELAdventureGrid.new()
	check(not grid.build(invalid, {}) and not grid.error.is_empty(), "nonadjacent harbor endpoints are rejected at map initialization")
	invalid = Fixture.world()
	invalid.set_meta("first_naval", {"version": 1, "ports": []})
	grid = ELAdventureGrid.new()
	check(not grid.build(invalid, {}) and not grid.error.is_empty(), "a naval map without a harbor fails explicitly")
	completed.append("blocked")

func _legacy_modes() -> void:
	label = "ordinary map compatibility"
	var map := Fixture.world(false)
	var director := _world(map)
	if director == null: return
	check(not ELFirstNaval.enabled(map) and not director.grid.naval, "an ordinary first-game map keeps naval movement disabled")
	check(director.grid.path(Fixture.LEFT_LAND, Fixture.RIGHT_LAND).is_empty() and director.grid.path(Fixture.LEFT_LAND, Fixture.RIGHT_LAND, true).is_empty(), "ordinary first-game heroes cannot cross water in either legacy grid")
	check(director.grid.passability(Vector2i(10, 10)) == 2 and director.grid.passability(Vector2i(28, 16)) < 0, "ordinary first-game movement costs and water blocking stay unchanged")
	director.state.close()
	map = Fixture.world()
	map.profile.id = "el2"
	var grid := ELAdventureGrid.new()
	check(grid.build(map, {}) and not grid.naval and not ELFirstNaval.enabled(map), "second-game maps ignore first-game naval metadata")
	check(grid.passability(Vector2i(10, 10)) == 1 and grid.passability(Vector2i(28, 16), true) == 1, "second-game land and ship costs remain one point")
	check(grid.passability(Fixture.LEFT_WATER, true) < 0 and grid.passability(Vector2i(24, 16), true) == 1, "second-game ships retain their deep-water corner threshold")
	check(grid.path(Vector2i(24, 16), Vector2i(32, 16), true).size() == 9 and grid.path(Fixture.LEFT_LAND, Fixture.RIGHT_LAND).is_empty(), "second-game ship and land searches remain separate")
	completed.append("legacy")

func _ai_crossing(smart: bool) -> void:
	label = "AI crossing (smart=%s)" % smart
	var director := _world()
	if director == null: return
	director.smart_ai = smart
	var state := director.state
	var worker := state.object(1)
	_put(director, worker, Vector2i(36, 16))
	_put(director, state.object(state.main_hero), Vector2i(9, 28))
	var champion_id := ELAdditionalBuildings.spawn_hero(state, ELCatalog.HEROES.Blue, 2, 55, 17)
	var champion := state.object(champion_id)
	if champion.is_empty():
		check(false, "a second computer hero is available for the legacy economic role")
		state.close()
		return
	champion.experience = 150
	var target := state.object(4)
	ELFirstAI.plan_player(director, 2, false)
	check(int(worker.get("strategy_order", {}).get("use", -1)) == int(target.uid), "the actual planner assigns the mine across the sea")
	var completed_days := 0
	for day in 6:
		if int(target.owner) == 2: break
		if not director.end_day() or not _drive(director): break
		completed_days += 1
	check(completed_days > 0 and int(target.owner) == 2, "ordinary AI turns sail to and capture the cross-shore objective")
	check(trace.any(func(row: Dictionary) -> bool: return row.id == worker.uid and row.ship), "the worker actually enters ship mode during execution")
	check(_position(worker).x < Fixture.LEFT_WATER.x and not worker.ship, "the worker lands on the objective's island")
	check(state.error.is_empty() and director.error.is_empty() and trace.all(func(row: Dictionary) -> bool: return row.ap >= 0), "AI voyages complete without runtime errors or negative movement")
	state.close()
	completed.append("smart_ai" if smart else "legacy_ai")

func _persistence() -> void:
	label = "naval checkpoint"
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(Content.profile(), {"seed": "naval-checkpoint", "size": 64, "players": 2, "layout": "archipelago", "naval": true, "guards": "none"})
	check(map != null, "a real generated naval map is available: " + generator.error)
	if map == null: return
	var director := _world(map, true)
	if director == null: return
	var state := director.state
	var hero := state.object(state.main_hero)
	var ports: Array = map.get_meta("first_naval", {}).get("ports", [])
	check(not ports.is_empty(), "the generated map contains embarkation points")
	if ports.is_empty():
		state.close()
		return
	var port: Dictionary = ports[0]
	var shore := Vector2i(int(port.land[0]), int(port.land[1]))
	var sea := Vector2i(int(port.water[0]), int(port.water[1]))
	_put(director, hero, shore)
	hero.ap = int(hero.strategy_capacity)
	check(_free_order(director, hero, sea) and hero.ship, "an actual generated harbor boards the hero")
	var codec := ELAdventureSave.new()
	var save := codec.encode(director)
	check(not save.is_empty(), "the sailing state encodes: " + codec.error)
	if save.is_empty():
		state.close()
		return
	var json: Dictionary = JSON.parse_string(JSON.stringify(save, "", true, true))
	var loaded := codec.decode(json, {"el1": map.profile})
	check(not loaded.is_empty(), "JSON checkpoint regenerates the naval map: " + codec.error)
	if not loaded.is_empty():
		var resumed: ELAdventureDirector = loaded.director
		var sailor := resumed.state.object(resumed.state.main_hero)
		check(sailor.ship is bool and sailor.ship and _position(sailor) == sea and int(sailor.ap) == int(hero.ap), "ship form, sea position, and spent movement survive JSON round trip")
		check(resumed.grid.naval and resumed.grid.naval_links == director.grid.naval_links, "the saved recipe reconstructs the same harbor graph")
		resumed.free_movement = true
		ELFog.reveal_for_console(resumed.state, 1, true)
		check(_free_order(resumed, sailor, shore) and not sailor.ship and _position(sailor) == shore, "a restored ship can land through the normal player action")
		resumed.state.close()
	for invalid_ship: Variant in [null, 1, "true", false]:
		var damaged: Dictionary = json.duplicate(true)
		for item: Dictionary in damaged.objects:
			if int(item.uid) != int(hero.uid): continue
			if invalid_ship == null: item.erase("ship")
			else: item.ship = invalid_ship
		var rejected := codec.decode(damaged, {"el1": map.profile})
		check(rejected.is_empty() and not codec.error.is_empty(), "missing, nonboolean, or incorrect sailing form is rejected: " + str(invalid_ship))
		if not rejected.is_empty(): rejected.state.close()
	var mismatched: Dictionary = json.duplicate(true)
	mismatched.random_map.version = 1
	var rejected := codec.decode(mismatched, {"el1": map.profile})
	check(rejected.is_empty() and not codec.error.is_empty(), "a mismatched generator envelope version is rejected")
	if not rejected.is_empty(): rejected.state.close()
	# Save during the boarding animation, while the logical hero is still
	# on the land endpoint. On resume the unpaid transfer must execute once.
	_put(director, hero, shore)
	hero.ap = int(hero.strategy_capacity)
	check(director.request_move(int(hero.uid), sea) and director.request_move(int(hero.uid), sea), "boarding is queued for an in-flight checkpoint")
	ELStrategy.advance(director)
	director.advance(0.005)
	check(not director.movement.is_empty() and float(director.movement.progress) > 0.0 and float(director.movement.progress) < 1.0 and _position(hero) == shore and not hero.ship, "boarding animation retains the source cell and form until arrival")
	var moving_json: Dictionary = JSON.parse_string(JSON.stringify(codec.encode(director), "", true, true))
	loaded = codec.decode(moving_json, {"el1": map.profile})
	check(not loaded.is_empty(), "an actual mid-edge checkpoint reloads: " + codec.error)
	if not loaded.is_empty():
		var resumed: ELAdventureDirector = loaded.director
		var sailor := resumed.state.object(resumed.state.main_hero)
		check(not resumed.movement.is_empty() and is_equal_approx(float(resumed.movement.progress), float(director.movement.progress)), "fractional movement progress survives JSON")
		check(_drive(resumed) and sailor.ship and _position(sailor) == sea and int(sailor.ap) == int(hero.ap) - ELFirstNaval.TRANSFER_COST - ELFirstNaval.SAIL_COST, "resuming boarding commits the transfer and charges it exactly once")
		resumed.state.close()
	mismatched = moving_json.duplicate(true)
	if mismatched.get("director", {}).get("movement", {}).has("path"):
		mismatched.director.movement.path[1] = [(shore.x + 4) % map.width, shore.y]
		rejected = codec.decode(mismatched, {"el1": map.profile})
		check(rejected.is_empty() and not codec.error.is_empty(), "a saved voyage with an illegal coastal jump is rejected")
		if not rejected.is_empty(): rejected.state.close()
	# Another friendly actor can occupy a future route cell after planning.
	# Loading such a checkpoint must retain it and stop safely on execution.
	var blocker := {}
	for item: Dictionary in state.objects.values():
		if item.type == "hero" and int(item.uid) != int(hero.uid):
			blocker = item
			break
	if not blocker.is_empty():
		blocker.owner = 1
		_put(director, blocker, sea)
		var obstructed: Dictionary = JSON.parse_string(JSON.stringify(codec.encode(director), "", true, true))
		loaded = codec.decode(obstructed, {"el1": map.profile})
		check(not loaded.is_empty(), "a checkpoint with a newly occupied future route cell remains loadable: " + codec.error)
		if not loaded.is_empty():
			var resumed: ELAdventureDirector = loaded.director
			var sailor := resumed.state.object(resumed.state.main_hero)
			check(_drive(resumed) and _position(sailor) == shore and not sailor.ship and int(sailor.ap) == int(hero.ap), "restored movement rechecks occupancy without overlap or a duplicate transfer charge")
			resumed.state.close()
	else: check(false, "a second generated hero exists for the occupied-route checkpoint")
	state.close()
	check(_legacy_checkpoint(), "the complete legacy checkpoint compatibility section ran")
	completed.append("save")

func _legacy_checkpoint() -> bool:
	var profile := Content.profile()
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(profile, {"version": 1, "seed": "legacy-checkpoint", "size": 64, "players": 2})
	check(map != null, "a version1 map still generates for checkpoint compatibility")
	if map == null: return false
	var director := _world(map)
	if director == null: return false
	var codec := ELAdventureSave.new()
	var document: Dictionary = JSON.parse_string(JSON.stringify(codec.encode(director), "", true, true))
	for item: Dictionary in document.objects: item.erase("ship")
	var loaded := codec.decode(document, {"el1": profile})
	check(not loaded.is_empty(), "a version1 checkpoint without new ship fields remains loadable: " + codec.error)
	if not loaded.is_empty(): loaded.state.close()
	for item: Dictionary in document.objects:
		if int(item.uid) == director.state.main_hero: item.ship = true
	loaded = codec.decode(document, {"el1": profile})
	check(loaded.is_empty() and not codec.error.is_empty(), "an ordinary first-game checkpoint cannot introduce a ship")
	if not loaded.is_empty(): loaded.state.close()
	director.state.close()
	return true
