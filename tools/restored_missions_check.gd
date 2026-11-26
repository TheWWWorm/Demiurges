extends SceneTree
## Checks the restored cut missions of Etherlords I (ELRestoredMissions) on
## the installed game: the single-mission entry, the generated map and its
## goal rules.
##   godot --headless --path game --script ../tools/restored_missions_check.gd -- --el1=/path/to/Etherlords
## Without --el1 the profile from user://profiles.json is used. Saves and
## settings are not touched.

var failures: Array[String] = []
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _folder() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--el1="): return argument.trim_prefix("--el1=")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	return str(saved.get("el1", "")) if saved is Dictionary else ""

func _run() -> void:
	await process_frame
	var folder := _folder()
	var profile := ELProfile.new()
	if folder.is_empty() or not profile.mount("el1", folder):
		print("SKIP: restored missions need an Etherlords I installation (--el1=...)")
		quit(0)
		return
	_recipe()
	var entry := _entry(profile)
	if not entry.is_empty(): _savage_desert(profile, entry)
	_evil_dale(profile)
	_snowflake_maze(profile)
	_revisions(profile)
	await _story_box_grace()
	print("RESTORED MISSIONS: %d checks, %d failure(s)" % [checks, failures.size()])
	for failure: String in failures: printerr("  " + failure)
	quit(0 if failures.is_empty() else 1)

func _recipe() -> void:
	var recipe := ELRestoredMissions.recipe(ELRestoredMissions.SAVAGE_DESERT)
	var normalized := ELFirstRandomMap.normalize(recipe)
	check(not normalized.is_empty() and normalized.get("scenario") == ELRestoredMissions.SAVAGE_DESERT, "the recipe normalizes and keeps its scenario")
	check(ELFirstRandomMap.normalize(normalized) == normalized, "a normalized recipe normalizes to itself (saves re-read it)")
	var plain := recipe.duplicate()
	plain.erase("scenario")
	check(not ELFirstRandomMap.normalize(plain).has("scenario"), "plain random maps carry no scenario key")
	check(ELFirstRandomMap.id_for_config(plain) != ELRestoredMissions.map_id(ELRestoredMissions.SAVAGE_DESERT), "the mission's map id differs from the same random map's")
	check(ELFirstRandomMap.normalize(recipe.merged({"scenario": "unknown"}, true)).is_empty(), "an unknown scenario is refused")
	check(ELFirstRandomMap.normalize(recipe.merged({"version": 13}, true)).is_empty(), "a scenario needs version 14 or later")
	check(ELRestoredMissions.scenario_of_id(ELRestoredMissions.map_id(ELRestoredMissions.SAVAGE_DESERT)) == ELRestoredMissions.SAVAGE_DESERT, "the map id leads back to the mission")

func _entry(profile: ELProfile) -> Dictionary:
	var found := {}
	for entry: Dictionary in ELSingleScenario.catalog(profile):
		if entry.get("restored", "") == ELRestoredMissions.SAVAGE_DESERT: found = entry
	check(not found.is_empty(), "Savage Desert is in the single-mission list")
	if found.is_empty(): return {}
	check(not ELSingleScenario.title(profile, found).is_empty(), "the entry has a title")
	check(not str(found.description).is_empty() and not str(found.objective).is_empty(), "the entry has a briefing and an objective")
	check(found.players.size() == 1 and found.races == [1], "the entry lists the Chaots alone")
	var row := ELSingleScenario.scenario(found)
	check(row.get("random_map") == found.random_map and row.file_name == found.id, "starting the entry generates its recipe")
	check(ELSaveSlots.map_title(profile, found.id) == ELSingleScenario.title(profile, found), "saves name the mission, not a random map")
	check(ELHallOfFame.title(profile, "scenario", found.id) == ELSingleScenario.title(profile, found), "the Hall of Fame names the mission")
	return found

## The message boxes the director shows, closed one by one: [speaker, text].
func _spoken(director: ELAdventureDirector) -> Array:
	var said: Array = []
	for guard in 16:
		if director.dialogue.is_empty(): break
		said.append([int(director.dialogue.actor), str(director.dialogue.text)])
		director.acknowledge("OK")
	return said

func _savage_desert(profile: ELProfile, entry: Dictionary) -> void:
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(profile, entry.random_map)
	check(map != null, "the map generates: " + generator.error)
	if map == null: return
	check(map.id == entry.id, "the generated map has the entry's id")
	var again := ELFirstRandomMap.new().generate(profile, entry.random_map)
	check(again != null and ELFirstRandomMap.content_hash(again) == ELFirstRandomMap.content_hash(map), "the map is the same every time (saves regenerate it)")
	var colors := map.players.map(func(player: Dictionary) -> String: return ELXml.value(player, "color"))
	check(colors == ["Red"], "the Chaots play alone: the Synthets are beaten")
	check(map.objects.filter(func(item: Dictionary) -> bool: return item.group == "buildings" and item.name == "MainTower").size() == 1, "only the Chaots' castle stands")
	check(map.objects.all(func(item: Dictionary) -> bool: return int(item.owner) <= 1), "nothing belongs to a second player")
	var spoils := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "mines" and int(item.x) > map.width / 2 and int(item.y) < map.height / 2)
	check(not spoils.is_empty(), "the Synthets' old mines stay in the south-east")
	var cyclops := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "np_heroes" and item.name == "Cyclope")
	check(cyclops.size() == 1, "one Cyclops stands on the map")
	if cyclops.size() != 1: return
	var lair := Vector2i(cyclops[0].x, cyclops[0].y)
	check(lair.x > map.width / 2 and lair.y > map.height / 2, "he stands in the north-east (high rows are north)")
	check(ELAdventureArt.terrain_color(map.tile(lair.x, lair.y)) == "Red", "on the dark rock of the mountains")
	var guards := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "np_heroes" and item.name in ELRestoredMissions.LAIR_GUARDS and Vector2i(item.x, item.y).distance_to(lair) < 14.0)
	check(guards.size() >= ELRestoredMissions.LAIR_GUARDS.size(), "strong guards stand on the way to him")
	var castle := Vector2i(int(generator.report.starts[0].x), int(generator.report.starts[0].y))
	check(ELAdventureArt.terrain_color(map.tile(castle.x, castle.y)) == "Black", "the Chaots start on the desert sand")
	# The hand-made finish (ELRestoredMissions.EDITS): every piece stands.
	for edit: Dictionary in ELRestoredMissions.EDITS[ELRestoredMissions.SAVAGE_DESERT]:
		for piece: Array in edit.get("props", []):
			var size := Vector2i(ELAdventureGrid.footprint(profile.table("TerrObj")[piece[0]], int(piece[2])).size)
			var at := Vector2i(piece[1]) - size / 2
			check(map.objects.any(func(item: Dictionary) -> bool: return item.name == piece[0] and Vector2i(item.x, item.y) == at), "the hand-placed %s stands at %s" % [piece[0], piece[1]])

	var state := ELAdventureSession.new()
	check(state.start(map, 2, ELFirstRandomMap.seed_for_config(entry.random_map), "", 1, false, true), "the mission starts: " + state.error)
	var director := ELAdventureDirector.new()
	check(director.build(state), "the director builds the mission")
	var goal := {}
	var hero := {}
	var other := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "monster" and item.name == "Cyclope": goal = item
		elif item.get("type") == "monster" and other.is_empty(): other = item
		elif item.get("type") == "hero" and int(item.owner) == 1: hero = item
	check(ELRestoredMissions.goal_monster(state) == "Cyclope", "the session knows the mission's goal")
	# The story: the hero's first words, then each beat once, where it belongs.
	var russian := ELRemakeText.language(profile) == "ru"
	ELFirstScenario.opening(director)
	var said := _spoken(director)
	check(said.size() == 1 and said[0][0] == int(hero.uid) and said[0][1] == ELRestoredStory.STORY[ELRestoredMissions.SAVAGE_DESERT][0].lines[0][2 if russian else 1], "the mission opens with the hero's words, in the edition's language")
	var home := Vector2i((ELRestoredMissions.SYNTHET_HOME * Vector2(map.width, map.height)).round())
	var start_at := Vector2i(hero.x, hero.y)
	# Walked through on the way, the move ending well beyond it: the beat is
	# not missed for want of stopping on its spot.
	hero.x = home.x
	hero.y = home.y
	ELRestoredStory.stepped(state, hero)
	hero.x = start_at.x
	hero.y = start_at.y
	ELFirstScenario.evaluate(director)
	check(_spoken(director).size() == 1 and state.scenario.told.has("fallen"), "the hero speaks at the Synthets' fallen castle, passed on the way")
	check(not state.scenario.has("due"), "the beats passed on the way are cleared once told")
	ELFirstScenario.evaluate(director)
	check(_spoken(director).is_empty(), "a beat is told only once")
	hero.x = int(goal.x) - 4
	hero.y = int(goal.y)
	ELFirstScenario.evaluate(director)
	said = _spoken(director)
	check(said.size() == 3 and said[1][0] == int(goal.uid) and said[2][0] == int(hero.uid), "in the mountains the hero speaks, then the Cyclops and the hero have words")
	check(ELFirstScenario.restore(state, state.scenario.duplicate(true)) == "" and state.scenario.told.size() == 4, "a save keeps the beats told")
	var forged := state.scenario.duplicate(true)
	forged.told = ["nothing"]
	check(ELFirstScenario.restore(state, forged) != "", "a save with an unknown beat is refused")
	hero.x = start_at.x
	hero.y = start_at.y
	check(state.scenario.castles.keys() == [1], "the session has one castle")
	check(ELFirstScenario.evaluate(director) == "", "a map without rivals is not won on its first day")
	check(ELFirstScenario.evaluate(director, {"hero": hero.uid, "opponent": other.uid, "winner": hero.uid}) == "", "beating another creature does not end the mission")
	check(ELFirstScenario.evaluate(director, {"hero": hero.uid, "opponent": goal.uid, "winner": goal.uid}) == "", "losing to the Cyclops does not end the mission")
	goal.alive = false
	check(ELFirstScenario.evaluate(director, {"hero": hero.uid, "opponent": goal.uid, "winner": hero.uid}) == "win", "a human hero's victory over the Cyclops wins")
	state.close()

	# Should he ever leave the map another way, the mission does not stall.
	var second := ELAdventureSession.new()
	second.start(ELFirstRandomMap.new().generate(profile, entry.random_map), 2, 1, "", 1, false, true)
	var second_director := ELAdventureDirector.new()
	second_director.build(second)
	for item: Dictionary in second.objects.values():
		if item.get("type") == "monster" and item.name == "Cyclope": item.alive = false
	check(ELFirstScenario.evaluate(second_director) == "win", "without the Cyclops and with no rival, the mission is won")
	second.close()

func _evil_dale(profile: ELProfile) -> void:
	var entry := {}
	for found: Dictionary in ELSingleScenario.catalog(profile):
		if found.get("restored", "") == ELRestoredMissions.EVIL_DALE: entry = found
	check(not entry.is_empty(), "Evil Dale is in the single-mission list")
	if entry.is_empty(): return
	check(entry.players.size() == 1 and entry.races == [2] and int(entry.size_class) == 3, "the entry lists one Vital on a huge map")
	check(not str(entry.description).is_empty(), "the entry has a briefing")
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(profile, entry.random_map)
	check(map != null, "the dale generates: " + generator.error)
	if map == null: return
	check(map.width == 160 and map.height == 160, "the dale is a 160-tile map, as its points need")
	var again := ELFirstRandomMap.new().generate(profile, entry.random_map)
	check(again != null and ELFirstRandomMap.content_hash(again) == ELFirstRandomMap.content_hash(map), "the dale is the same every time")
	check(map.players.size() == 1 and ELXml.value(map.players[0], "color") == "Green", "the Chosen One's Vitals play alone")
	check(not map.objects.any(func(item: Dictionary) -> bool: return ELFirstScenario.is_castle(item)), "no castle stands in the dale")
	check(not map.objects.any(func(item: Dictionary) -> bool: return item.group == "global_spells"), "no global-spell scroll lies in the dale (the Chosen One has no castle to cast them)")
	var outpost := map.objects.filter(func(item: Dictionary) -> bool: return item.group in ["laboratories", "factories"] and Vector2i(item.x, item.y).distance_to(ELRestoredMissions.OUTPOST) <= 20.0)
	check(outpost.size() == 3, "the Synthets' outpost has a portal and two shops where the sand begins (%d)" % outpost.size())
	var chosen := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "heroes" and item.name == ELRestoredMissions.CHOSEN and int(item.owner) == 1)
	check(chosen.size() == 1 and map.objects.filter(func(item: Dictionary) -> bool: return item.group == "heroes").size() == 1, "the Chosen One is the only hero of the player")
	for name: String in ELRestoredMissions.RIVALS:
		var rival := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "np_heroes" and item.name == name and ELXml.child(item.node, "monster").is_empty())
		check(rival.size() == 1 and Vector2i(rival[0].x, rival[0].y).distance_to(ELRestoredMissions.RIVALS[name]) <= 8.0, "%s stands near his place" % name)
	# The exit is reachable on foot, creatures and rivals aside.
	var objects := {}
	for item: Dictionary in map.objects:
		if item.group in ["heroes", "np_heroes"]: continue
		var copy := item.duplicate()
		copy.uid = int(item.permanent_id) - 1
		copy.alive = true
		copy.visible = true
		copy.placed = true
		copy.type = "object"
		objects[copy.uid] = copy
	var grid := ELAdventureGrid.new()
	grid.build(map, objects)
	var start := Vector2i(chosen[0].x, chosen[0].y) if not chosen.is_empty() else Vector2i.ZERO
	var path := grid.path(start, ELRestoredMissions.EXIT)
	check(not path.is_empty(), "the way out can be walked from the Chosen One's glade")
	check(path.size() > 300, "the way out is long (%d steps)" % path.size())
	# Revision 2: met in order along the walk, no kind of creature comes
	# back before DALE_FRESH others.
	var met: Array = []
	for item: Dictionary in map.objects:
		if item.group != "np_heroes" or ELXml.child(item.node, "monster").is_empty(): continue
		var walk := grid.path(start, Vector2i(item.x, item.y))
		if not walk.is_empty(): met.append([walk.size(), str(item.name).trim_suffix(" D")])
	met.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var soon := 0
	for index in met.size():
		for back in range(1, ELRestoredMissions.DALE_FRESH + 1):
			if index - back >= 0 and met[index - back][1] == met[index][1] and met[index][0] - met[index - back][0] > 2: soon += 1
	# Revision 3 keeps the creatures near the rivals' levels, where each
	# ground has fewer kinds: a few more meet again early.
	check(soon <= 3, "the dale's creatures do not repeat along the walk (%d early repeats among %d)" % [soon, met.size()])
	for point: Vector2i in ELRestoredMissions.PATROL:
		check(not grid.path(start, point).is_empty(), "Glazzz's loop point %s is in the dale" % point)

	var state := ELAdventureSession.new()
	check(state.start(map, 2, ELFirstRandomMap.seed_for_config(entry.random_map), "", 1, false, true), "the dale starts: " + state.error)
	var director := ELAdventureDirector.new()
	check(director.build(state), "the director builds the dale")
	var hero := ELRestoredMissions.chosen_one(state)
	check(not hero.is_empty(), "the session finds the Chosen One")
	check(ELFirstScenario.evaluate(director) == "", "the dale is not decided at the start")
	ELFirstScenario.opening(director)
	check(_spoken(director).size() == 1, "the Chosen One speaks as the dale begins")
	var patroller := {}
	var warden := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.name == ELRestoredMissions.PATROLLER: patroller = item
		if item.get("type") == "hero" and item.name == ELRestoredMissions.WARDEN: warden = item
	var walked_from := Vector2i(hero.x, hero.y)
	hero.x = int(patroller.x)
	hero.y = int(patroller.y) - 4
	ELFirstScenario.evaluate(director)
	var words := _spoken(director)
	check(words.size() == 2 and words[0][0] == int(patroller.uid) and words[1][0] == int(hero.uid), "Glazzz and the Chosen One have words when they meet")
	warden.alive = false
	ELFirstScenario.evaluate(director, {"hero": hero.uid, "opponent": warden.uid, "winner": hero.uid})
	words = _spoken(director)
	check(words.size() == 1 and words[0][0] == int(hero.uid), "the Chosen One speaks when Warp is beaten")
	warden.alive = true
	hero.x = walked_from.x
	hero.y = walked_from.y
	var glazzz := {}
	var warp := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") == "hero" and item.name == ELRestoredMissions.PATROLLER: glazzz = item
		if item.get("type") == "hero" and item.name == ELRestoredMissions.WARDEN: warp = item
	check(int(glazzz.get("owner", 1)) <= 0 and int(warp.get("owner", 1)) <= 0, "the rivals are neutral heroes")
	ELFirstAI.scripts(director)
	check(glazzz.get("strategy_order", {}).get("destination", []) == [55, 110], "Glazzz sets off from the top of his loop to (55, 110)")
	check(warp.get("strategy_order", {}).is_empty(), "Warp holds his place while the Chosen One is far")
	glazzz.x = 64
	glazzz.y = 85
	ELFirstAI.scripts(director)
	check(glazzz.get("strategy_order", {}).get("destination", []) == [55, 104] and int(state.scenario.get("patrol", -1)) == 2, "at (64, 84) Glazzz turns for (55, 104)")
	# The Chosen One comes into Warp's sight.
	hero.x = int(warp.x) + 3
	hero.y = int(warp.y)
	director.grid.update_actor(hero)
	ELFirstAI.scripts(director)
	check(int(warp.get("strategy_order", {}).get("use", -1)) == int(hero.uid), "Warp attacks the Chosen One in sight")
	# Saves keep the patrol leg.
	var saved := state.scenario.duplicate(true)
	check(ELFirstScenario.restore(state, saved) == "" and int(state.scenario.get("patrol", -1)) == 2, "a save keeps Glazzz's leg")
	# The way out.
	hero.x = ELRestoredMissions.EXIT.x + 2
	hero.y = ELRestoredMissions.EXIT.y - 2
	check(ELFirstScenario.evaluate(director) == "win", "reaching the way out wins")
	var corner := ELRestoredMissions.EXIT_REVEAL.position + Vector2i(1, ELRestoredMissions.EXIT_REVEAL.size.y - 2)
	check((state.explored[corner.y * map.width + corner.x] & ELFog.bit(1)) != 0, "the ruins beyond are revealed")
	state.close()

	var second := ELAdventureSession.new()
	second.start(ELFirstRandomMap.new().generate(profile, entry.random_map), 2, 1, "", 1, false, true)
	var second_director := ELAdventureDirector.new()
	second_director.build(second)
	var one := ELRestoredMissions.chosen_one(second)
	one.x = ELRestoredMissions.EXIT.x + 3
	one.y = ELRestoredMissions.EXIT.y
	check(ELFirstScenario.evaluate(second_director) == "", "three tiles from the way out is not yet out")
	one.alive = false
	check(ELFirstScenario.evaluate(second_director) == "lose", "the Chosen One's death loses")
	second.close()

## Steps from `from` to a tile beside `to` over open ground, the game's
## corner rule kept; -1 when there is no way. `skip` leaves out the terrain
## objects it accepts (to measure the walk without them).
func _steps(map: ELAdventureMap, from: Vector2i, to: Vector2i, skip := Callable()) -> int:
	var objects := {}
	for item: Dictionary in map.objects:
		if item.group in ["heroes", "np_heroes"] or (skip.is_valid() and skip.call(item)): continue
		var copy := item.duplicate()
		copy.uid = int(item.permanent_id) - 1
		copy.alive = true
		copy.visible = true
		copy.placed = true
		copy.type = "object"
		objects[copy.uid] = copy
	var grid := ELAdventureGrid.new()
	if not grid.build(map, objects): return -1
	var steps := {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		if maxi(absi(at.x - to.x), absi(at.y - to.y)) == 1: return int(steps[at])
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := at + Vector2i(dx, dy)
				if steps.has(next) or not grid.contains(next) or grid.land.is_point_solid(next): continue
				if dx != 0 and dy != 0 and grid.land.is_point_solid(at + Vector2i(dx, 0)) and grid.land.is_point_solid(at + Vector2i(0, dy)): continue
				steps[next] = int(steps[at]) + 1
				queue.append(next)
	return -1

## A line just shown ignores the clicks and keys that arrive in its first
## moments (those pressed while a long map build held the window), then
## answers as usual.
func _story_box_grace() -> void:
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var box := ELFirstStoryBox.new()
	holder.add_child(box)
	var answers: Array[String] = []
	box.answered.connect(func(answer: String) -> void: answers.append(answer))
	box.present({"title": "Hero", "text": "A line."}, null)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space)
	await process_frame
	root.push_input(space)
	await process_frame
	check(answers.is_empty() and box.visible, "keys pressed while the line appears do not close it")
	await create_timer(float(ELFirstStoryBox.GRACE_MS) / 1000.0 + 0.2).timeout
	root.push_input(space)
	await process_frame
	check(answers == ["OK"], "a key closes the line once it has been seen (%s)" % [answers])
	holder.queue_free()

## Revisions: saves keep the revision they began with, so the first
## revision's recipe still builds and still names its mission.
func _revisions(profile: ELProfile) -> void:
	for scenario: String in ELRestoredMissions.SCENARIOS:
		var first := ELRestoredMissions.recipe(scenario)
		check(int(first.get("revision", 1)) == ELRestoredMissions.REVISION, "%s starts at the current revision" % scenario)
		first.erase("revision")
		check(ELFirstRandomMap.id_for_config(first) != ELRestoredMissions.map_id(scenario), "%s's revisions have their own map ids" % scenario)
		check(ELRestoredMissions.scenario_of_id(ELFirstRandomMap.id_for_config(first)) == scenario, "a first-revision save of %s still names its mission" % scenario)
		first["revision"] = 2
		check(ELRestoredMissions.scenario_of_id(ELFirstRandomMap.id_for_config(first)) == scenario, "a second-revision save of %s still names its mission" % scenario)
	check(ELFirstRandomMap.normalize(ELRestoredMissions.recipe(ELRestoredMissions.EVIL_DALE).merged({"revision": ELRestoredMissions.REVISION + 1}, true)).is_empty(), "an unknown revision is refused")
	var plain := ELFirstRandomMap.defaults()
	plain["revision"] = 2
	check(ELFirstRandomMap.normalize(plain).is_empty(), "plain random maps carry no revision")
	var first := ELRestoredMissions.recipe(ELRestoredMissions.SAVAGE_DESERT)
	first.erase("revision")
	var generator := ELFirstRandomMap.new()
	var old := generator.generate(profile, first)
	check(old != null, "the first revision of Savage Desert still generates: " + generator.error)
	if old != null: check(not old.objects.any(func(item: Dictionary) -> bool: return item.name == "Tower02"), "the first revision keeps its own fallen castle")

func _snowflake_maze(profile: ELProfile) -> void:
	var entry := {}
	for found: Dictionary in ELSingleScenario.catalog(profile):
		if found.get("restored", "") == ELRestoredMissions.SNOWFLAKE_MAZE: entry = found
	check(not entry.is_empty(), "the Snowflake Maze is in the single-mission list")
	if entry.is_empty(): return
	check(entry.players.size() == 3 and entry.players.all(func(side: Dictionary) -> bool: return side.color == "Blue"), "the entry lists three Kinet lords")
	var generator := ELFirstRandomMap.new()
	var map := generator.generate(profile, entry.random_map)
	check(map != null, "the maze map generates: " + generator.error)
	if map == null: return
	var again := ELFirstRandomMap.new().generate(profile, entry.random_map)
	check(again != null and ELFirstRandomMap.content_hash(again) == ELFirstRandomMap.content_hash(map), "the maze map is the same every time")
	var colors := map.players.map(func(player: Dictionary) -> String: return ELXml.value(player, "color"))
	check(colors == ["Blue", "Blue", "Blue"], "all three players are Kinets")
	check(map.objects.filter(func(item: Dictionary) -> bool: return item.group == "buildings" and item.name == "MainTower").size() == 3, "three castles stand")
	var heroes := {}
	for item: Dictionary in map.objects:
		if item.group == "heroes": heroes[int(item.owner)] = item
	check(heroes.has(2) and heroes[2].name == ELRestoredMissions.TOURNEY_HEROES[0], "the first rival lord brings Santa Claus")
	check(heroes.has(3) and heroes[3].name == ELRestoredMissions.TOURNEY_HEROES[1], "the second rival lord brings Father Frost")
	var middle := ELRestoredMissions.maze_middle(map.width)
	var heart := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "additional_buildings" and item.name == ELRestoredMissions.MAZE_HEART and Vector2i(item.x, item.y) == middle)
	check(heart.size() == 1, "the Teacher stands at the heart of the maze")
	var ice := func(item: Dictionary) -> bool: return item.group == "terrain_objects" and str(item.name) in ELRestoredMissions.MAZE_ICE and Vector2(item.x, item.y).distance_to(Vector2(middle)) <= ELRestoredMissions.MAZE_SPIKE + 1.0
	check(map.objects.filter(ice).size() > 150, "the maze's ice walls stand")
	var guards := map.objects.filter(func(item: Dictionary) -> bool: return item.group == "np_heroes" and Vector2(item.x, item.y).distance_to(Vector2(middle)) <= 6.0)
	check(guards.size() == ELRestoredMissions.MAZE_GAPS[0].size(), "a guard holds each way into the heart")
	check(guards.all(func(item: Dictionary) -> bool: return item.name == ELRestoredMissions.MAZE_GUARD), "the same creature guards every way in")
	var walks: Array[int] = []
	for player: int in [1, 2, 3]:
		if not heroes.has(player): continue
		var from := Vector2i(heroes[player].x, heroes[player].y)
		var through := _steps(map, from, middle)
		var straight := _steps(map, from, middle, ice)
		check(through > 0, "player %d's hero can walk to the Teacher" % player)
		check(through >= straight + 12, "the maze winds for player %d (%d steps through it, %d without it)" % [player, through, straight])
		walks.append(through)
	if walks.size() == 3: check(walks.max() - walks.min() <= 8, "the walk to the heart is about as long for every lord: %s" % [walks])

	var state := ELAdventureSession.new()
	check(state.start(map, 2, ELFirstRandomMap.seed_for_config(entry.random_map), "", 1, false, true), "the tournament starts: " + state.error)
	var director := ELAdventureDirector.new()
	check(director.build(state), "the director builds the tournament")
	var own := {}
	var santa := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero": continue
		if int(item.owner) == 1: own = item
		elif item.name == ELRestoredMissions.TOURNEY_HEROES[0]: santa = item
	check(state.hostile({"owner": 1}, {"owner": 2}) and state.hostile({"owner": 2}, {"owner": 3}), "the Kinet lords are rivals of one another")
	check(int(own.level) == ELRestoredMissions.TOURNEY_LEVEL and int(own.skill_points) == ELRestoredMissions.TOURNEY_LEVEL - 1, "the player's hero starts at the rivals' level, with its skill points to spend")
	check(int(santa.level) == ELRestoredMissions.TOURNEY_LEVEL and int(santa.experience) == ELHeroProgression.threshold(profile, ELRestoredMissions.TOURNEY_LEVEL), "the rivals' heroes keep their own level")
	var russian := ELRemakeText.language(profile) == "ru"
	ELFirstScenario.opening(director)
	var said := _spoken(director)
	check(said.size() == 1 and said[0][0] == int(own.uid) and said[0][1] == ELRestoredStory.STORY[ELRestoredMissions.SNOWFLAKE_MAZE][0].lines[0][2 if russian else 1], "the tournament opens with the hero's words")
	check(ELFirstScenario.evaluate(director) == "", "the tournament is not won while rival castles stand")
	own.x = int(santa.x) + 3
	own.y = int(santa.y)
	ELFirstScenario.evaluate(director)
	said = _spoken(director)
	check(said.size() == 2 and said[0][0] == int(santa.uid) and said[1][0] == int(own.uid), "Santa Claus and the hero have words when they meet")
	ELFirstScenario.evaluate(director, {"hero": own.uid, "opponent": santa.uid, "winner": own.uid})
	check(state.scenario.told.has("santa_beaten"), "the hero speaks after beating Santa Claus")
	_spoken(director)
	own.x = middle.x + 1
	own.y = middle.y + 1
	ELFirstScenario.evaluate(director)
	check(state.scenario.told.has("maze") and state.scenario.told.has("heart"), "the hero speaks at the maze and at its heart")
	state.close()
