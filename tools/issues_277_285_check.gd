extends SceneTree
## Regression checks for first-game adventure reports:
## - #277: the side panel's hero portrait carries the crossed swords of the
##   hero states sheet while the hero's order attacks an enemy castle (as for an
##   enemy hero or creature, or a hero stopped by a guard zone), the lock for an
##   order to capture a site and the shield inside a fort;
## - the world-view guard warning clears when the hero can move again in
##   free movement, when the night ends and when a stale warning is loaded;
## - #283: a hero the chapter places on a fort's origin starts as its garrison
##   (the fort its owner's), guards the fort's zone and stops an enemy hero
##   walking into it; the fort's zone is ringed by the Intercept5x5 pieces,
##   each on the side of the fort it faces (#333);
## - #284: the castle regains floor(sqrt(unused ether / 6)) energy at the end
##   of the day on single missions and random maps as in the chapters;
## - #285: in the spell shop and the component portal a zero price stays
##   white, a price paid is green, one that cannot be paid is red.
##
##   godot --headless --path game --script ../tools/issues_277_285_check.gd
##
## Needs the first game configured in user://profiles.json; without it the
## checks are skipped. Nothing is saved.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, caption: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + caption)
	if not ok: failures += 1

func _run() -> void:
	await process_frame
	_price_ink()
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured")
		_finish()
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		_finish()
		return
	_forts(profile)
	_portrait_states(profile)
	_regeneration(profile)
	_finish()

func _finish() -> void:
	print("ADVENTURE REPORTS 277-285: %d failure(s)" % failures)
	quit(int(failures > 0))

func _session(profile: ELProfile, map_id: String, campaign: bool) -> Array:
	var map := ELAdventureMap.new()
	if map_id == "random":
		var options := ELFirstRandomMap.defaults()
		options.seed = "277"
		map = ELFirstRandomMap.new().generate(profile, options)
		if map == null: return []
	elif not map.load_map(profile, map_id): return []
	var state := ELAdventureSession.new()
	if not state.start(map, 1, 212, "", 1, campaign): return []
	var director := ELAdventureDirector.new()
	if not director.build(state): return []
	director.fast_mode = true
	return [state, director]

# --- #285 --------------------------------------------------------------------

func _price_ink() -> void:
	var white := Color(1, 1, 1)
	var green := Color(0, 1, 0)
	var red := Color(1, 0, 0)
	var price := {"Ruby": 0, "Emerald": 12}
	check(ELHeroScreenView.price_ink({}, "Ruby", false) == white, "#285: no price (\"-\") is white")
	check(ELHeroScreenView.price_ink(price, "Ruby", false) == white, "#285: a zero price is white")
	check(ELHeroScreenView.price_ink(price, "Ruby", true) == white, "#285: a zero price stays white even past the stock")
	check(ELHeroScreenView.price_ink(price, "Emerald", false) == green, "#285: a price paid is green")
	check(ELHeroScreenView.price_ink(price, "Emerald", true) == red, "#285: a price that cannot be paid is red")

# --- #283 --------------------------------------------------------------------

func _forts(profile: ELProfile) -> void:
	var pair := _session(profile, "mission21", true)
	if pair.is_empty():
		check(false, "#283: chapter mission21 loads")
		return
	var state: ELAdventureSession = pair[0]
	var director: ELAdventureDirector = pair[1]
	var fort := {}
	var hero := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "fort" and Vector2i(int(item.x), int(item.y)) == Vector2i(23, 16): fort = item
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and str(item.get("name", "")) == "Hogning": hero = item
	check(not fort.is_empty() and not hero.is_empty(), "#283: mission21 has the fort at (23,16) and Hogning")
	if fort.is_empty() or hero.is_empty():
		state.close()
		return
	check(hero.get("fortified", false) and int(hero.get("fort", -1)) == int(fort.uid) and int(fort.garrison) == int(hero.uid), "#283: the hero authored on the fort's origin starts as its garrison")
	check(int(fort.owner) == int(hero.owner), "#283: the fort belongs to its garrison's owner (%d)" % int(fort.owner))
	check(ELForts.valid_links(state.objects, state.map), "#283: the fort and its garrison link both ways")
	var zone: Dictionary = director.interception.zones.get(int(hero.uid), {})
	check(not zone.is_empty() and zone.area == ELInterception.fort_area(director.grid, fort), "#283: the garrison guards a zone around the fort")
	var reach := 0
	for cell: Vector2i in zone.get("cells", []): reach = maxi(reach, maxi(absi(cell.x - int(fort.x)), absi(cell.y - int(fort.y))))
	check(reach == ELInterception.FIRST_FORT_RADIUS - 1, "#283: the zone reaches %d tiles out (%d)" % [ELInterception.FIRST_FORT_RADIUS - 1, reach])
	# A human hero two tiles off the fort is in the zone and would be stopped.
	var walker := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.get("alive", false) and int(item.owner) == state.current_player and not item.get("fortified", false): walker = item
	var inside := Vector2i(-1, -1)
	for cell: Vector2i in zone.get("cells", []):
		if maxi(absi(cell.x - int(fort.x)), absi(cell.y - int(fort.y))) == 2 and director.grid.passability(cell) >= 0:
			inside = cell
			break
	check(not walker.is_empty() and inside.x >= 0 and director.interception.enemies(state, walker, inside).has(int(hero.uid)), "#283: an enemy hero stepping into the fort's zone meets the garrison")
	# The original's ring: twelve pieces on the zone's cells two tiles out.
	var presentation := ELFirstMapPresentation.new()
	presentation.state = state
	var ring := presentation.ring_cells(fort)
	var pieces := {}
	for cell: Vector2i in ring: pieces[ring[cell]] = true
	check(ring.size() >= 8 and pieces.size() == ring.size(), "#283: the occupied fort gets %d distinct guard-zone ring pieces" % ring.size())
	var all_out := true
	for cell: Vector2i in ring: all_out = all_out and maxi(absi(cell.x - int(fort.x)), absi(cell.y - int(fort.y))) == 2
	check(all_out, "#283: every ring piece sits two tiles off the fort's origin")
	# #333: each piece traces the side of its cell facing away from the fort
	# (00 north, 03 east, 06 south, 09 west; map y grows northwards), so the
	# square's top row of pieces belongs on the garrison's row + 2.
	var facing := {0: Vector2i(0, 1), 3: Vector2i(1, 0), 6: Vector2i(0, -1), 9: Vector2i(-1, 0)}
	var outward := true
	var straight := 0
	for cell: Vector2i in ring:
		if not facing.has(ring[cell]): continue
		straight += 1
		outward = outward and cell - Vector2i(int(fort.x), int(fort.y)) == facing[ring[cell]] * 2
	check(straight > 0 and outward, "#333: the ring's %d straight pieces sit on the side of the fort they face" % straight)
	presentation.free()
	# A fort nobody holds keeps no ring.
	var empty := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "fort" and int(item.garrison) < 0: empty = item
	if not empty.is_empty():
		var other := ELFirstMapPresentation.new()
		other.state = state
		check(other.ring_cells(empty).is_empty(), "#283: an empty fort has no ring")
		other.free()
	if not walker.is_empty() and inside.x >= 0: _guard_warning(director, walker, inside)
	state.close()
	# Neutral creatures do not garrison: only heroes enter a first-game fort.
	var monsters := _session(profile, "mission14", true)
	if not monsters.is_empty():
		var garrisoned := 0
		for item: Dictionary in monsters[0].objects.values():
			if item.get("type") == "monster" and item.get("fortified", false): garrisoned += 1
		check(garrisoned == 0, "#283: creatures beside first-game forts stay outside")
		monsters[0].close()

func _guard_warning(director: ELAdventureDirector, hero: Dictionary, inside: Vector2i) -> void:
	var original := Vector2i(hero.x, hero.y)
	var map := director.state.map
	hero.x = inside.x
	hero.y = inside.y
	director.strategy = {"phase": "movement", "actors": [hero.uid], "index": 0, "combats": [], "legacy_orders": false}
	ELStrategy.entered(director, hero)
	check(hero.intercepted and hero.get("danger_pulse", false), "a hostile guard zone raises the world warning")
	var checkpoint := hero.duplicate(true)
	check(ELStrategy.restore(map.profile, checkpoint, map) and checkpoint.get("danger_pulse", false), "a save made during an interception keeps the active warning")

	ELStrategy._finish_act(director, {"actors": [hero.uid]})
	check(hero.intercepted and hero.get("danger_pulse", false), "the free-movement warning stays while the hero is stopped")
	hero.x = original.x
	hero.y = original.y
	ELStrategy._finish_act(director, {"actors": [hero.uid]})
	check(not hero.intercepted and not hero.has("danger_pulse"), "the free-movement warning clears once the hero is free")

	hero.x = inside.x
	hero.y = inside.y
	director.strategy = {"phase": "movement", "actors": [hero.uid], "index": 0, "combats": [], "legacy_orders": false}
	ELStrategy.entered(director, hero)
	director.strategy.phase = "use"
	director.strategy.index = 1
	ELStrategy.advance(director)
	check(director.strategy.is_empty() and not hero.intercepted and not hero.has("danger_pulse"), "the world warning clears when the night ends")

	checkpoint.intercepted = false
	check(ELStrategy.restore(map.profile, checkpoint, map) and not checkpoint.has("danger_pulse"), "a stale world warning is removed from older saves")

# --- #277 --------------------------------------------------------------------

func _portrait_states(profile: ELProfile) -> void:
	var pair := _session(profile, "mmission01", false)
	if pair.is_empty():
		check(false, "#277: mmission01 loads")
		return
	var state: ELAdventureSession = pair[0]
	var hero := {}
	var enemy_castle := {}
	var own_castle := {}
	var mine := {}
	for item: Dictionary in state.objects.values():
		if ELFirstScenario.is_castle(item):
			if int(item.owner) == state.current_player: own_castle = item
			elif enemy_castle.is_empty() and int(item.owner) >= 1: enemy_castle = item
		if mine.is_empty() and item.get("group") == "mines": mine = item
	var at := ELGlobalSpells.near_castle(state, state.current_player)
	var template := ""
	var rows: Dictionary = profile.table("HeroTemplates")
	for key: String in rows:
		if str(rows[key].get("Quest", "")) != "Yes" and int(rows[key].get("Level", 1)) == 1 and str(rows[key].get("Color", "")) == str(state.players[state.current_player].color):
			template = key
			break
	hero = state.object(ELAdditionalBuildings.spawn_hero(state, template, state.current_player, at.x, at.y))
	check(not hero.is_empty() and not enemy_castle.is_empty() and not mine.is_empty(), "#277: a hero, an enemy castle and a mine to order")
	if hero.is_empty() or enemy_castle.is_empty() or mine.is_empty():
		state.close()
		return
	check(ELAdventureHud.hero_states(state, hero).is_empty(), "#277: a hero without an order has no state mark")
	hero.strategy_order = {"destination": [int(enemy_castle.x), int(enemy_castle.y)], "use": int(enemy_castle.uid)}
	check(ELAdventureHud.hero_states(state, hero) == [ELAdventureHud.STATE_SWORDS], "#277: attacking an enemy castle shows the crossed swords")
	if not own_castle.is_empty():
		hero.strategy_order = {"destination": [int(own_castle.x), int(own_castle.y)], "use": int(own_castle.uid)}
		check(ELAdventureHud.hero_states(state, hero).is_empty(), "#277: an order to its own castle shows no swords")
	hero.strategy_order = {"destination": [int(mine.x), int(mine.y)], "use": int(mine.uid)}
	check(ELAdventureHud.hero_states(state, hero) == [ELAdventureHud.STATE_LOCK], "#277: capturing a mine shows the lock")
	hero.strategy_order = {"destination": [int(hero.x) + 1, int(hero.y)], "use": -1}
	check(ELAdventureHud.hero_states(state, hero).is_empty(), "#277: a plain move shows nothing")
	hero.intercepted = true
	check(ELAdventureHud.hero_states(state, hero) == [ELAdventureHud.STATE_SWORDS], "#277: a hero stopped by a guard zone shows the swords")
	hero.intercepted = false
	hero.strategy_order = {}
	hero.fortified = true
	check(ELAdventureHud.hero_states(state, hero) == [ELAdventureHud.STATE_SHIELD], "#277: a hero inside a fort shows the shield")
	hero.fortified = false
	state.close()

# --- #284 --------------------------------------------------------------------

func _regeneration(profile: ELProfile) -> void:
	for entry: Array in [["mission10", true], ["mmission01", false], ["mmission05", false], ["random", false]]:
		var pair := _session(profile, entry[0], entry[1])
		if pair.is_empty():
			check(false, "#284: %s loads" % entry[0])
			continue
		var state: ELAdventureSession = pair[0]
		var director: ELAdventureDirector = pair[1]
		var player := state.current_player
		var castle: Dictionary = state.scenario.castles[player]
		castle.health = int(castle.max) - 10
		var expected := ELFirstScenario.regained(state, player, ELGlobalSpells.free_ether(state, player))
		var before := int(castle.health)
		director.end_day()
		for i in 4000:
			if director.encounter != null:
				ELFirstAI.resolve(director, state.object(director.encounter.hero_id), state.object(director.encounter.opponent_id))
				continue
			if director._shopping():
				for shop: Variant in [director.first_shop, director.rune_shop]:
					if shop != null: shop.cancel()
				director.first_shop = null
				director.rune_shop = null
				continue
			if director.strategy.is_empty() and director.movement.is_empty() and director.travel.is_empty() and director.free_queue.is_empty() and state.commands.is_empty() and director.can_move(): break
			director.advance(0.1)
		check(expected >= 1 and int(castle.health) == mini(int(castle.max), before + expected), "#284: %s: the castle regains %d energy at the day's end (%d -> %d)" % [entry[0], expected, before, int(castle.health)])
		state.close()
