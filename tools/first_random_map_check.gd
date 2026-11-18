extends SceneTree
## Asset-free integration/property checks for Etherlords I random maps.
## Run with the project's Godot version (4.7):
##   godot --headless --editor --path game --quit
##   godot --headless --path game --script ../tools/first_random_map_check.gd
## Optional --stress repeats the full configuration matrix with more seeds.
## Optional --el1=/path/to/Etherlords also checks the real installed tables.
## The synthetic fixtures contain no original game assets. Existing user
## settings, saves and Hall of Fame data are not changed.

const Fixture = preload("first_random_map_fixture.gd")
const SIZES := [64, 96, 128, 160]
const LAYOUTS := ["frontier", "lakes", "crossroads"]
const AMOUNTS := ["scarce", "normal", "rich"]
const GUARDS := ["none", "normal", "strong"]
const COLORS := ["Green", "Blue", "Red", "Black"]

var failures: Array[String] = []
var checks := 0
var generated := 0
var label := ""
var completed: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var began := Time.get_ticks_msec()
	var profile := Fixture.profile()
	_configuration()
	_missing_content(profile)
	_matrix(profile)
	_reproducibility(profile)
	_option_effects(profile)
	_persistence(profile)
	_strategy(profile)
	_installed_content()
	label = "suite completion"
	check(completed.size() >= 7 and generated >= 47 and checks >= 100, "every required test section completed (script errors must not produce a false pass)")
	print("FIRST RANDOM MAP: %d checks, %d generated maps, %d failure(s), %.2f s" % [checks, generated, failures.size(), (Time.get_ticks_msec() - began) / 1000.0])
	for failure: String in failures: printerr("  " + failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: return
	var full := (label + ": " if not label.is_empty() else "") + what
	failures.append(full)
	printerr("FAIL: " + full)

func _configuration() -> void:
	label = "configuration"
	var defaults := ELFirstRandomMap.defaults()
	check(not defaults.is_empty(), "defaults exist")
	check(ELFirstRandomMap.normalize(defaults) == defaults, "defaults are canonical")
	check(ELFirstRandomMap.normalize(JSON.parse_string(JSON.stringify(defaults))) == defaults, "canonical settings survive JSON numeric conversion")
	check(ELFirstRandomMap.normalize({}) == defaults, "omitted options use defaults")
	for options: Dictionary in [
		{"size": 65}, {"size": 96.5}, {"size": true}, {"size": "96"},
		{"players": 1}, {"players": 5}, {"players": 2.5}, {"players": true},
		{"layout": "unknown"}, {"layout": []}, {"biome": "unknown"},
		{"guards": "unknown"}, {"resources": "unknown"}, {"starting_resources": "unknown"},
		{"faction": "White"}, {"roads": 1}, {"roads": "false"},
		{"scenery": -1}, {"scenery": 3}, {"scenery": true},
		{"castle_health": 0}, {"castle_health": 31},
		{"version": 999}, {"version": 1.5}, {"version": true},
		{"seed": []}, {"seed": "a".repeat(65)}, {"seed": "   "}]:
		check(ELFirstRandomMap.normalize(options).is_empty(), "malformed options rejected: " + JSON.stringify(options))
	var seed := defaults.duplicate(true)
	seed.seed = "A seed with spaces / 123"
	var normalized := ELFirstRandomMap.normalize(seed)
	check(not normalized.is_empty(), "text seeds are supported")
	if normalized.is_empty(): return
	var id := ELFirstRandomMap.id_for_config(normalized)
	check(id.is_valid_identifier() and ELFirstRandomMap.is_random_id(id), "generated IDs satisfy the existing save ID validation")
	check(id == ELFirstRandomMap.id_for_config(JSON.parse_string(JSON.stringify(normalized))), "IDs are stable across JSON")
	check(not ELFirstRandomMap.is_random_id("mission11") and not ELFirstRandomMap.is_random_id("Maps/../random"), "authored IDs and traversal strings are not random maps")
	print("PASS: strict configuration validation and stable map identities")
	completed.append("configuration")

func _missing_content(profile: ELProfile) -> void:
	label = "missing content"
	var generator := ELFirstRandomMap.new()
	check(generator.generate(null) == null and not generator.error.is_empty(), "a missing profile fails explicitly")
	var sequel := ELProfile.new()
	sequel.id = "el2"
	check(generator.generate(sequel) == null and not generator.error.is_empty(), "Etherlords II content cannot be used")
	var missing := Fixture.profile()
	missing.tables.HeroTemplates.clear()
	check(generator.generate(missing) == null and not generator.error.is_empty(), "missing starting heroes fail explicitly")
	missing = Fixture.profile()
	missing.tables.Buildings.clear()
	check(generator.generate(missing) == null and not generator.error.is_empty(), "missing castles fail explicitly")
	check(generator.generate(profile, {"players": 1000000}) == null and not generator.error.is_empty(), "invalid generation settings fail explicitly")
	print("PASS: incomplete installations and wrong editions fail cleanly")
	completed.append("missing content")

func _matrix(profile: ELProfile) -> void:
	var rounds := 4 if "--stress" in OS.get_cmdline_user_args() else 1
	for round_index in rounds:
		for layout_index in LAYOUTS.size():
			for players in range(2, 5):
				for size_index in SIZES.size():
					var variation := round_index * 36 + layout_index * 12 + (players - 2) * 4 + size_index
					var config := {"seed": "property-%d" % variation, "size": SIZES[size_index], "players": players,
						"layout": LAYOUTS[layout_index], "resources": AMOUNTS[(variation + 1) % 3],
						"starting_resources": AMOUNTS[variation % 3], "guards": GUARDS[variation % 3],
						"biome": "mixed" if variation % 5 == 0 else COLORS[variation % 4],
						"faction": COLORS[(variation + 1) % 4], "roads": variation % 2 == 0,
						"scenery": variation % 3, "castle_health": [20, 30, 60][variation % 3]}
					label = "%s/%d/%d/%s" % [config.layout, config.size, players, config.seed]
					var generator := ELFirstRandomMap.new()
					var map := _generate(generator, profile, config)
					if map == null: continue
					_geometry(map, config)
			print("PASS: generation/navigation matrix %s (round %d)" % [LAYOUTS[layout_index], round_index + 1])
	completed.append("matrix")

func _generate(generator: ELFirstRandomMap, profile: ELProfile, options: Dictionary) -> ELAdventureMap:
	var map := generator.generate(profile, options)
	generated += 1
	check(map != null, "generation succeeds: " + generator.error)
	return map

func _geometry(map: ELAdventureMap, options: Dictionary) -> void:
	var config := ELFirstRandomMap.normalize(options)
	check(map.width == config.size and map.height == config.size, "configured dimensions are used")
	check(map.terrain.size() == (map.width + 1) * (map.height + 1), "terrain uses corner dimensions")
	check(map.roads.size() == map.width * map.height and map.creeks.size() == map.width * map.height and map.colorless.size() == map.width * map.height, "cell grids use the correct dimensions")
	check(map.players.size() == config.players, "configured player count is used")
	check(ELFirstRandomMap.configuration(map) == config, "the complete recipe is attached to the map")
	var identifiers := {}
	var positions := true
	for item: Dictionary in map.objects:
		positions = positions and int(item.x) >= 0 and int(item.x) < map.width and int(item.y) >= 0 and int(item.y) < map.height
		if identifiers.has(int(item.permanent_id)): positions = false
		identifiers[int(item.permanent_id)] = true
	check(positions, "objects have unique IDs and valid origins")
	var state := ELAdventureSession.new()
	if not state.start(map, 1, ELFirstRandomMap.seed_for_config(config), "", 1, false):
		check(false, "the real adventure session starts: " + state.error)
		state.close()
		return
	check(not state.scenario.campaign and state.current_player == 1 and state.main_hero >= 0, "the map starts as a playable single mission")
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "the real navigation director builds: " + director.error)
		state.close()
		return
	var grid := director.grid
	var collision_free := true
	for count in grid.blockers:
		if count > 1: collision_free = false
	for count in grid.actor_blockers:
		if count > 1: collision_free = false
	for uid: int in grid.footprints:
		var item := state.object(uid)
		for cell: Vector2i in grid.footprints[uid].cells:
			if not grid.contains(Vector2i(item.x, item.y) + cell): collision_free = false
	check(collision_free, "real building and scenery footprints fit without overlaps")
	var hero_positions: Array[Vector2i] = []
	var initial_resources := {}
	var enough_heroes := true
	var enough_castles := true
	var fair_wallets := true
	for player in range(1, int(config.players) + 1):
		var heroes: Array[Dictionary] = []
		var castles := 0
		for item: Dictionary in state.objects.values():
			if int(item.owner) != player: continue
			if item.type == "hero": heroes.append(item)
			if ELFirstScenario.is_castle(item): castles += 1
		enough_heroes = enough_heroes and heroes.size() == 1
		enough_castles = enough_castles and castles == 1 and int(state.scenario.castles[player].health) == config.castle_health
		if initial_resources.is_empty(): initial_resources = state.players[player].resources.duplicate()
		fair_wallets = fair_wallets and initial_resources == state.players[player].resources
		for hero: Dictionary in heroes:
			var at := Vector2i(hero.x, hero.y)
			hero_positions.append(at)
			check(grid.blockers[at.y * map.width + at.x] == 0 and _terrain_cost(map, at) >= 0, "hero %d starts on legal, unblocked land" % player)
			check(int(hero.ap) > 0 and hero.cards.size() >= 8 and hero.cards.size() <= 15, "hero %d can move and has an EL1 spellbook" % player)
			check(hero.cards.all(func(card: String) -> bool: return ELSpellInventory.is_spell(map.profile, card)), "hero %d has registered spells" % player)
	check(enough_heroes and enough_castles, "every player owns exactly one hero and castle of the configured health")
	check(fair_wallets, "all players receive identical starting resources")
	check(state.players[1].color == config.faction, "the selected faction controls the human starting army")
	_opening_economy(map, state)
	var neutral_count := 0
	for item: Dictionary in state.objects.values():
		if item.type == "monster": neutral_count += 1
	check(neutral_count == 0 if config.guards == "none" else neutral_count > 0, "guard settings affect actual runtime encounters")
	if not hero_positions.is_empty():
		var reachable := _reachable(map, grid, hero_positions[0])
		var disconnected: Array[String] = []
		for item: Dictionary in state.objects.values():
			if item.group == "terrain_objects" or not item.get("visible", true): continue
			if item.type in ["hero", "monster"]:
				if not reachable[int(item.y) * map.width + int(item.x)]: disconnected.append(str(item.name))
			elif not _approachable(grid, item, reachable): disconnected.append(str(item.name))
		check(disconnected.is_empty(), "all heroes, guards and strategic sites have reachable approaches: " + ", ".join(disconnected.slice(0, 5)))
		var target := ELFirstScenario.castle_object(state, int(config.players))
		check(not grid.approach(hero_positions[0], target).is_empty(), "the actual AStar grid can route to the rival castle")
	state.close()

func _opening_economy(map: ELAdventureMap, state: ELAdventureSession) -> void:
	var details: Dictionary = map.get_meta("random_map_report", {})
	var starts: Array = details.get("starts", [])
	check(starts.size() == map.players.size(), "all starts have an auditable opening economy")
	for start: Dictionary in starts:
		var production := ELResources.empty("el1")
		var stock := {"IngredientShop": 0, "CreatureShop": 0, "SpellShop": 0, "ManaNode": 0}
		var improvement := false
		for id: int in start.get("sites", []):
			var site := state.object(id)
			if site.get("group") == "mines":
				var amounts := ELResourceSites.production(map.profile, site)
				for kind: String in amounts: production[kind] += int(amounts[kind])
			elif site.get("group") in ["factories", "laboratories"]:
				var type := str(ELBuildings.definition(map.profile, site).get("Type", ""))
				if stock.has(type): stock[type] += 1
				if type == "CreatureShop":
					for card: String in ELFirstSpellShop.authored_stock(map.profile, site, str(start.color)):
						if map.profile.table("CombatSpells")[card].get("Rarity") != "Cantrip": improvement = true
			elif site.get("group") == "mana_nodes" and ELXml.value(site.node, "color") == start.color:
				stock.ManaNode += 1
		var gem: String = {"Green": "Emerald", "Blue": "Sapphire", "Red": "Ruby", "Black": "Diamond"}[start.color]
		check(production.Root > 0 and production.Lotus > 0 and int(production[gem]) > 0, "player %d has roots, lotus and the matching faction gem" % int(start.player))
		check(stock == {"IngredientShop": 1, "CreatureShop": 1, "SpellShop": 1, "ManaNode": 1}, "player %d has a complete opening shop/mana set" % int(start.player))
		check(improvement, "player %d can purchase a non-cantrip creature at the starting shop" % int(start.player))
		var prefix: String = {"Green": "SV", "Blue": "SK", "Red": "SC", "Black": "SS"}[start.color]
		var known := ELMapPickups.available_codes(state, int(start.player))
		check(prefix + "WR" in known and not prefix + "CH" in known and not prefix + "HR" in known, "player %d starts with warrior recruitment and can discover higher summons" % int(start.player))
		var scrolls := {}
		for item: Dictionary in state.objects.values():
			if item.group != "global_spells": continue
			for code: String in ELMapPickups.scroll_spells(map.profile, item): scrolls[code] = true
		check(scrolls.has(prefix + "CH") and scrolls.has(prefix + "HR"), "player %d has both advanced recruitment scrolls to discover" % int(start.player))

func _terrain_cost(map: ELAdventureMap, at: Vector2i) -> int:
	var corners: Array[int] = [map.tile(at.x, at.y), map.tile(at.x + 1, at.y), map.tile(at.x + 1, at.y + 1), map.tile(at.x, at.y + 1)]
	return ELAdventureGrid.strategic_cost(map.profile.terrain_tiles, corners, map.roads[at.y * map.width + at.x], false)

func _reachable(map: ELAdventureMap, grid: ELAdventureGrid, start: Vector2i) -> PackedByteArray:
	# Independent flood fill: use the real terrain cost and real static
	# footprints, ignoring actors because defeating a guard clears its cell.
	var passable := PackedByteArray()
	passable.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			var index := y * map.width + x
			passable[index] = 1 if grid.blockers[index] == 0 and _terrain_cost(map, Vector2i(x, y)) >= 0 else 0
	var seen := PackedByteArray()
	seen.resize(passable.size())
	var queue := PackedInt32Array([start.y * map.width + start.x])
	seen[queue[0]] = 1
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		var at := Vector2i(index % map.width, index / map.width)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var point := at + Vector2i(dx, dy)
				if not grid.contains(point): continue
				var next := point.y * map.width + point.x
				if not passable[next] or seen[next]: continue
				seen[next] = 1
				queue.append(next)
	return seen

func _approachable(grid: ELAdventureGrid, item: Dictionary, reachable: PackedByteArray) -> bool:
	var shape: Dictionary = grid.footprints.get(int(item.uid), {"size": Vector2i.ONE})
	var size: Vector2i = shape.size
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and y >= 0 and x < size.x and y < size.y: continue
			var point := Vector2i(item.x + x, item.y + y)
			if grid.contains(point) and reachable[point.y * grid.map.width + point.x]: return true
	return false

func _fingerprint(map: ELAdventureMap) -> String:
	return JSON.stringify({"id": map.id, "terrain": map.terrain.hex_encode(), "roads": map.roads.hex_encode(),
		"creeks": map.creeks.hex_encode(), "colorless": map.colorless.hex_encode(), "players": map.players,
		"objects": map.objects, "mobs": map.mobs, "document": map.document}, "", true, true).sha256_text()

func _reproducibility(profile: ELProfile) -> void:
	label = "reproducibility"
	var generator := ELFirstRandomMap.new()
	var config := ELFirstRandomMap.normalize({"seed": "Repeat / seed 420", "size": 96, "players": 4, "layout": "lakes", "scenery": 2})
	var first := _generate(generator, profile, config)
	var second := _generate(generator, profile, JSON.parse_string(JSON.stringify(config)))
	if first == null or second == null: return
	check(_fingerprint(first) == _fingerprint(second), "same seed/config reproduces every grid, object and XML record")
	check(ELFirstRandomMap.content_hash(first) == ELFirstRandomMap.content_hash(second), "content hashes are repeatable")
	var other := config.duplicate()
	other.seed = "Different seed"
	var different := _generate(generator, profile, other)
	if different != null:
		check(first.id != different.id and _fingerprint(first) != _fingerprint(different), "a different seed creates a different map")
	seed(7123)
	var expected := randf()
	seed(7123)
	_generate(generator, profile, config)
	check(randf() == expected, "generation does not consume the game's global RNG")
	print("PASS: deterministic recipes, varied seeds, isolated RNG")
	completed.append("reproducibility")

func _option_effects(profile: ELProfile) -> void:
	label = "configuration effects"
	var generator := ELFirstRandomMap.new()
	var low := _generate(generator, profile, {"seed": "options", "size": 64, "players": 2, "roads": false, "scenery": 0, "guards": "none", "resources": "scarce", "starting_resources": "scarce"})
	var high := _generate(generator, profile, {"seed": "options", "size": 64, "players": 2, "roads": true, "scenery": 2, "guards": "strong", "resources": "rich", "starting_resources": "rich"})
	if low == null or high == null: return
	check(low.roads.count(0) == low.roads.size() and high.roads.count(0) < high.roads.size(), "the roads switch changes road tiles")
	check(_group_count(low, "terrain_objects") == 0 and _group_count(high, "terrain_objects") > 0, "the scenery switch changes placed scenery")
	check(high.objects.size() > low.objects.size(), "richer, guarded maps contain additional content")
	var low_resources := ELResources.read_node("el1", ELXml.child(low.players[0], "start_resources"))
	var high_resources := ELResources.read_node("el1", ELXml.child(high.players[0], "start_resources"))
	var richer := true
	for kind: String in ELResources.ORIGINAL: richer = richer and int(high_resources[kind]) > int(low_resources[kind])
	check(richer, "starting economy settings change every resource allowance")
	var hashes := {}
	for layout: String in LAYOUTS:
		var map := _generate(generator, profile, {"seed": "same-layout-seed", "layout": layout, "size": 64, "scenery": 0})
		if map != null: hashes[map.terrain.hex_encode().sha256_text()] = true
	check(hashes.size() == LAYOUTS.size(), "the three layouts create different terrain")
	print("PASS: options change terrain, roads, economy, scenery and guards")
	completed.append("options")

func _group_count(map: ELAdventureMap, group: String) -> int:
	var result := 0
	for item: Dictionary in map.objects:
		if item.group == group: result += 1
	return result

func _persistence(profile: ELProfile) -> void:
	label = "save/load"
	var generator := ELFirstRandomMap.new()
	var map := _generate(generator, profile, {"seed": "checkpoint", "size": 64, "players": 3, "guards": "normal"})
	if map == null: return
	var state := ELAdventureSession.new()
	if not state.start(map, 2, ELFirstRandomMap.seed_for_config(generator.config)):
		check(false, "session starts for persistence: " + state.error)
		state.close()
		return
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "director starts for persistence: " + director.error)
		state.close()
		return
	state.players[1].resources.Root += 17
	var prefix: String = {"Green": "SV", "Blue": "SK", "Red": "SC", "Black": "SS"}[state.players[1].color]
	var learned := ""
	var hero := state.object(state.main_hero)
	for item: Dictionary in state.objects.values():
		if item.group != "global_spells" or not prefix + "CH" in ELMapPickups.scroll_spells(profile, item): continue
		var route := director.grid.approach(Vector2i(hero.x, hero.y), item)
		if route.is_empty(): continue
		hero.x = route[-1].x
		hero.y = route[-1].y
		director.grid.update_actor(hero)
		if not ELMapPickups.take(director, hero, item).is_empty(): learned = prefix + "CH"
		break
	check(not learned.is_empty() and learned in ELMapPickups.available_codes(state, 1), "collecting an actual generated scroll unlocks advanced recruitment")
	check(ELSaveSlots.current_row(state).get("title", "") == map.title, "save-slot rows display the generated map title")
	check(ELHallOfFame.title(profile, "scenario", map.id) == ELRemakeText.t("Random map", profile), "Hall of Fame recognizes generated map identities in the game's language")
	var codec := ELAdventureSave.new()
	var encoded := codec.encode(director)
	check(not encoded.is_empty(), "checkpoint encodes: " + codec.error)
	if encoded.is_empty():
		state.close()
		return
	check(encoded.has("random_map"), "save embeds the canonical recipe")
	var json: Dictionary = JSON.parse_string(JSON.stringify(encoded, "", true, true))
	var restored := codec.decode(json, {"el1": profile})
	check(not restored.is_empty(), "saved JSON regenerates and restores: " + codec.error)
	if not restored.is_empty():
		var loaded: ELAdventureSession = restored.state
		check(_fingerprint(loaded.map) == _fingerprint(map), "restored terrain, placement and identities match exactly")
		check(loaded.players[1].resources == state.players[1].resources and loaded.difficulty == state.difficulty, "mutable resources and difficulty survive save/load")
		check(loaded.objects.size() == state.objects.size() and loaded.main_hero == state.main_hero, "object and hero identities survive save/load")
		check(not learned.is_empty() and learned in ELMapPickups.available_codes(loaded, 1), "collected progression scrolls survive save/load")
		loaded.close()
	var damaged: Array[Dictionary] = []
	var copy := json.duplicate(true)
	copy.erase("random_map")
	damaged.append(copy)
	copy = json.duplicate(true)
	copy.random_map.config.seed = "changed seed"
	damaged.append(copy)
	copy = json.duplicate(true)
	copy.random_map.config.erase("size")
	damaged.append(copy)
	copy = json.duplicate(true)
	copy.random_map.config.unexpected = 1
	damaged.append(copy)
	copy = json.duplicate(true)
	copy.random_map.version = 1.5
	damaged.append(copy)
	copy = json.duplicate(true)
	copy.map_hash = "wrong hash"
	damaged.append(copy)
	copy = json.duplicate(true)
	copy.map = "mission11"
	damaged.append(copy)
	for index in damaged.size():
		var rejected := codec.decode(damaged[index], {"el1": profile})
		check(rejected.is_empty() and not codec.error.is_empty(), "corrupt checkpoint %d is rejected safely" % index)
		if not rejected.is_empty(): rejected.state.close()
	if profile.root.is_empty():
		var changed := Fixture.profile()
		changed.tables.ResourceMine.Root0.Production = ["Root(3)"]
		var rejected := codec.decode(json, {"el1": changed})
		check(rejected.is_empty() and not codec.error.is_empty(), "changed source content cannot silently alter a saved map")
		if not rejected.is_empty(): rejected.state.close()
	state.close()
	print("PASS: checkpoint round trip and corrupt-recipe rejection")
	completed.append("persistence")

func _strategy(profile: ELProfile) -> void:
	label = "strategic rules"
	var generator := ELFirstRandomMap.new()
	var map := _generate(generator, profile, {"seed": "strategy", "size": 64, "players": 2, "guards": "none"})
	if map == null: return
	var state := ELAdventureSession.new()
	if not state.start(map):
		check(false, "strategic session starts")
		state.close()
		return
	var director := ELAdventureDirector.new()
	if not director.build(state):
		check(false, "strategic director builds")
		state.close()
		return
	check(ELFirstScenario.evaluate(director).is_empty(), "a new map has neither immediate victory nor defeat")
	# The legacy planner reserves its first hero for fighting and gives
	# economic orders to the free recruit supplied by the daily pass. The
	# next pass includes that recruit, exactly as an ordinary turn does.
	ELFirstAI.plan_player(director, 2, true)
	ELFirstAI.plan_player(director, 2, false)
	check(state.error.is_empty() and director.error.is_empty() and state.players[2].get("ai", {}).get("built", false), "the existing world AI can plan on generated maps")
	var orders := 0
	for hero: Dictionary in ELFirstAI.heroes_of(state, 2):
		if not hero.get("strategy_order", {}).is_empty(): orders += 1
	check(ELFirstAI.heroes_of(state, 2).size() >= 2 and orders > 0, "the legacy AI recruits a worker and gives actionable orders")
	director.smart_ai = true
	ELFirstAI.plan_player(director, 2, false)
	orders = 0
	for hero: Dictionary in ELFirstAI.heroes_of(state, 2):
		if not hero.get("strategy_order", {}).is_empty(): orders += 1
	check(orders > 0 and state.error.is_empty() and director.error.is_empty(), "the smarter world AI plans on the same generated economy")
	var recruit := state.object(generator.report.starts[1].hero_id)
	state.add_experience(recruit.uid, ELHeroProgression.threshold(profile, 5) - int(recruit.experience))
	var enemy := ELFirstScenario.castle_object(state, 1)
	var assault := {"kind": "tower", "target": enemy.uid}
	check(recruit.level == 5 and ELFirstAIPlanner.siege_ready(recruit, 0, map), "a recruited level-five hero leads sieges on current maps")
	check(not ELFirstAIPlanner.siege_ready(recruit, 0) and not ELFirstAIPlanner.siege_ready(recruit, 1, map), "earlier siege rules and support roles retain their limits")
	check(ELFirstAIPlanner.siege_nights(director, recruit, enemy) > 0 and ELFirstAI.cost(director, recruit, 0, assault) < ELFirstAI.NONE, "the AI makes a viable siege plan with the recruited hero")
	# A simulated strategic seat suppresses the Hall of Fame write while
	# using the same castle defeat and last-rival victory code.
	director._strategic_players = [1]
	ELFirstScenario.damage(state, 2, 100000)
	ELFirstScenario.end_night(director)
	check(ELFirstScenario.evaluate(director) == "win" and state.outcome == "win", "destroying the rival castle wins")
	state.close()
	state = ELAdventureSession.new()
	if state.start(map):
		director = ELAdventureDirector.new()
		if director.build(state):
			ELFirstScenario.damage(state, 1, 100000)
			ELFirstScenario.end_night(director)
			check(ELFirstScenario.evaluate(director) == "lose" and state.outcome == "lose", "losing the human castle loses")
	state.close()
	print("PASS: world AI planning and existing castle victory/defeat rules")
	completed.append("strategy")

func _installed_content() -> void:
	var folder := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--el1="): folder = argument.trim_prefix("--el1=")
	if folder.is_empty():
		print("SKIP: original-content integration (pass --el1=/path/to/Etherlords)")
		return
	label = "installed content"
	var profile := ELProfile.new()
	if not profile.mount("el1", folder):
		check(false, "mount first-game content: " + profile.error)
		return
	for layout: String in ELFirstRandomMap.LAYOUTS:
		var generator := ELFirstRandomMap.new()
		var options := {"seed": "installed-content-check", "layout": layout, "size": 96, "players": 4}
		var map := _generate(generator, profile, options)
		if map != null: _geometry(map, options)
	for version: int in [1, 2]:
		var options := {"version": version, "seed": "steam-compatibility", "size": 64, "players": 2}
		if version == 2: options.merge({"layout": "archipelago", "naval": true})
		var map := _generate(ELFirstRandomMap.new(), profile, options)
		if map != null:
			check(ELFirstNaval.enabled(map) == (version == 2), "installed catalog supports legacy maps and new harbor layouts")
	_persistence(profile)
