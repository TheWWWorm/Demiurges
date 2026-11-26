extends SceneTree
## Headless check of #328: adventure outcomes are random per game.
## - second game: each new start of a chapter draws its own map and script
##   random state, so the first level-up offers, the scripted spell loot and
##   the specialisation rolls differ between new campaigns (they were fixed
##   by the mission: the map state started at 212 for every start, the
##   adventure library seeded its script generator from it, and skill offers
##   came from the hero's map id);
## - second game: a specialisation that worked against the main hero is
##   learned after a won battle with the adventure library's 50% chance
##   (random(100) <= 50), counted over many rolls;
## - second game: a loaded save rolls afresh (the original draws these rolls
##   from the C library's generator, which its save does not keep); offers
##   already shown are kept;
## - first game: new campaign starts give different offers and creature loot;
##   a save keeps the map's random state, as before (#259).
##
##   godot --headless --path game --script ../tools/issues_328_check.gd
##
## Needs both games' files (user://profiles.json). Saves written by a mission
## start are put back afterwards.

const STARTS := 4
const SPEC_TRIALS := 4000

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var profiles := {}
	for edition: String in ["el1", "el2"]:
		var profile := ELProfile.new()
		if paths is Dictionary and paths.has(edition) and profile.mount(edition, str(paths[edition])): profiles[edition] = profile
	if profiles.is_empty():
		print("SKIP: no game files configured (user://profiles.json)")
		quit(0)
		return
	if profiles.has("el2"):
		var saves := _backup(ELSaveSlots.folder("el2"))
		await _second_starts(profiles.el2)
		_second_specialisations(profiles.el2)
		await _second_load(profiles.el2)
		_restore(ELSaveSlots.folder("el2"), saves)
	else: print("SKIP: no second-game files")
	if profiles.has("el1"):
		var saves := _backup(ELSaveSlots.folder("el1"))
		await _first_starts(profiles.el1)
		_restore(ELSaveSlots.folder("el1"), saves)
	else: print("SKIP: no first-game files")
	print("ISSUES 328 CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# --- second game ------------------------------------------------------------

func _second_scenario(profile: ELProfile) -> Dictionary:
	for found: Dictionary in ELSingleScenario.maps(profile):
		if str(found.id).to_lower().ends_with("e2mission21"): return ELSingleScenario.scenario(found)
	return {}

func _second_settings() -> ELSettings:
	var settings := ELSettings.new()
	settings.use_edition("el2")
	return settings

func _main_hero(state: ELAdventureSession) -> Dictionary:
	var hero := state.object(state.main_hero)
	if not hero.is_empty(): return hero
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player: return item
	return {}

## The offers of the hero's next level-up.
func _level_up(state: ELAdventureSession, hero: Dictionary) -> Array:
	var profile := state.map.profile
	state.add_experience(int(hero.uid), maxi(1, ELHeroProgression.threshold(profile, int(hero.level) + 1) - int(hero.experience)))
	var offers: Array = hero.get("skill_offers", []).duplicate()
	offers.sort()
	return offers

## The adventure library's loot payout: six spells shared by two corpses, the
## first corpse's three drawn by the script generator.
func _scripted_loot(state: ELAdventureSession, hero: Dictionary) -> Array:
	var vm := state.vm
	vm.globals["g_LootSpell"] = vm.table()
	vm.globals["g_LootSpellCount"] = 0.0
	vm.globals["g_LootCorpse"] = vm.table()
	vm.globals["g_LootCorpseCount"] = 0.0
	vm.globals["g_LootSpellCorpse"] = vm.table()
	vm.globals["g_LootSpellCorpseCount"] = 0.0
	var cards: Array = state.map.profile.table("CombatSpells").keys()
	cards.sort()
	for i in 6: vm.invoke("AddLootSpell", [str(cards[i * 7])])
	vm.invoke("AddLootCorpse", [-901.0])
	vm.invoke("AddLootCorpse", [-902.0])
	var before := state.messages.size()
	vm.invoke("PayLoot", [float(hero.uid), -901.0])
	if not vm.error.is_empty(): return ["error: " + vm.error]
	var result: Array = []
	for message: Dictionary in state.messages.slice(before):
		if message.get("kind") == "loot":
			for item: Dictionary in message.get("items", []): result.append(str(item.get("card", "")))
	return result

func _second_starts(profile: ELProfile) -> void:
	var scenario := _second_scenario(profile)
	if scenario.is_empty():
		check(false, "el2 #328: chapter 21 is found")
		return
	var seeds: Array = []
	var script_states: Array = []
	var offers: Array = []
	var loot: Array = []
	for start in STARTS:
		var view := ELAdventureView.new()
		root.add_child(view)
		var built := view.build(profile, scenario.duplicate(true), _second_settings(), 1)
		check(built, "el2 #328: new start %d of chapter 21 builds %s" % [start + 1, view.error])
		if not built:
			view.queue_free()
			return
		await frames(2)
		var state := view.state
		seeds.append(state.seed_value)
		script_states.append(state.vm.rng_state)
		var hero := _main_hero(state)
		if start == 0: print("el2 #328: main hero %s, level %d" % [hero.get("title", hero.get("name")), int(hero.get("level", 0))])
		offers.append(_level_up(state, hero))
		loot.append(_scripted_loot(state, hero))
		view.queue_free()
		await frames(2)
	print("el2 #328: map states %s, script states %s" % [seeds, script_states])
	print("el2 #328: first level-up offers %s" % [offers])
	print("el2 #328: scripted loot %s" % [loot])
	check(not seeds.has(212) and _distinct(seeds) == STARTS, "el2 #328: each new start draws its own map random state")
	check(_distinct(script_states) == STARTS, "el2 #328: each new start seeds the scripts' generator afresh")
	check(offers.all(func(o: Array) -> bool: return o.size() == 3 and o.has("PRVD")), "el2 #328: a level-up still offers three skills with Resources first")
	check(_distinct(offers) > 1, "el2 #328: the first level-up offers differ between new campaigns")
	check(loot.all(func(l: Array) -> bool: return l.size() == 3), "el2 #328: the loot payout hands out three of six spells")
	check(_distinct(loot) > 1, "el2 #328: the scripted spell loot differs between new campaigns")

## The adventure library's CheckNewSpecialization after a won battle, on a map
## started like a new campaign: the rate is the script's 50%.
func _second_specialisations(profile: ELProfile) -> void:
	var scenario := _second_scenario(profile)
	var map := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	if not (map.load_map(profile, str(scenario.file_name)) and state.start(map, 1, randi() & 0x7fffffff, str(scenario.get("script", "")), int(str(scenario.get("player", "1"))), true, true)):
		check(false, "el2 #328: chapter 21 starts for the specialisation rolls %s" % state.error)
		return
	var hero := _main_hero(state)
	var code := ""
	var codes: Array = profile.table("HeroesSpecs").keys()
	codes.sort()
	for candidate: String in codes:
		if candidate != "NONE" and state.specialization_available(hero, candidate): code = candidate
	if code.is_empty():
		check(false, "el2 #328: the main hero can learn a specialisation")
		state.close()
		return
	state.vm.globals["g_MainHeroId"] = float(hero.uid)
	var shown := str(hero.get("specialization", "NONE"))
	# One stream, as a chapter rolls battle after battle, and the first roll
	# after many fresh seeds, as many new campaigns roll their first battle.
	var counts := [0, 0]
	for mode in 2:
		for trial in SPEC_TRIALS:
			if mode == 1: state.vm.rng_state = randi() & 0xffffffff
			hero.specializations = []
			hero.specialization = shown
			state.set_variable("IsNewSpecialization", 1.0)
			state.set_variable("NewSpecializationType", code)
			state.vm.invoke("CheckNewSpecialization")
			if not state.vm.error.is_empty():
				check(false, "el2 #328: CheckNewSpecialization runs: " + state.vm.error)
				state.close()
				return
			if state.specializations(hero).has(code): counts[mode] += 1
	for mode in 2:
		var rate := float(counts[mode]) / SPEC_TRIALS
		var label := "one chapter's stream" if mode == 0 else "first rolls of fresh seeds"
		print("el2 #328: %s learned %d of %d times (%.1f%%), %s" % [code, counts[mode], SPEC_TRIALS, rate * 100.0, label])
		# Three standard deviations of 4000 fair coin flips are about 2.4%.
		check(absf(rate - 0.5) < 0.03, "el2 #328: a worked specialisation is learned with the original 50%% chance (%s)" % label)
	state.close()

func _second_load(profile: ELProfile) -> void:
	var scenario := _second_scenario(profile)
	var view := ELAdventureView.new()
	root.add_child(view)
	if not view.build(profile, scenario.duplicate(true), _second_settings(), 1):
		check(false, "el2 #328: chapter 21 builds for the save check " + view.error)
		view.queue_free()
		return
	await frames(2)
	var hero := _main_hero(view.state)
	var saved_seed := view.state.seed_value
	var saved_script := view.state.vm.rng_state
	var codec := ELAdventureSave.new()
	var checkpoint := codec.encode(view.director, {})
	# A hero with a choice already shown keeps it through a load.
	var pending_view := _level_up(view.state, hero)
	var pending := ELAdventureSave.new().encode(view.director, {})
	view.queue_free()
	await frames(2)
	var decoded := codec.decode(checkpoint, {"el2": profile})
	check(not decoded.is_empty() and decoded.state.seed_value == saved_seed and decoded.state.vm.rng_state == saved_script,
		"el2 #328: the save itself records the map and script random states")
	if not decoded.is_empty(): decoded.state.close()
	var offers: Array = []
	var seeds: Array = []
	for load in STARTS:
		var restored := codec.decode(checkpoint, {"el2": profile})
		if restored.is_empty():
			check(false, "el2 #328: the save decodes: " + codec.error)
			return
		var loaded := ELAdventureView.new()
		root.add_child(loaded)
		var built := loaded.build(profile, scenario.duplicate(true), _second_settings(), 1, restored)
		check(built, "el2 #328: load %d of the save opens the map %s" % [load + 1, loaded.error])
		if not built:
			loaded.queue_free()
			return
		await frames(2)
		seeds.append([loaded.state.seed_value, loaded.state.vm.rng_state])
		offers.append(_level_up(loaded.state, _main_hero(loaded.state)))
		loaded.queue_free()
		await frames(2)
	print("el2 #328: level-up offers after %d loads of one save %s" % [STARTS, offers])
	check(not seeds.has([saved_seed, saved_script]) and _distinct(seeds) == STARTS, "el2 #328: each load of a solo save rolls from a fresh random state")
	check(_distinct(offers) > 1, "el2 #328: levelling up after a load can offer other skills")
	var again := codec.decode(pending, {"el2": profile})
	if again.is_empty():
		check(false, "el2 #328: the save with a pending choice decodes")
		return
	var reopened := ELAdventureView.new()
	root.add_child(reopened)
	if reopened.build(profile, scenario.duplicate(true), _second_settings(), 1, again):
		var kept: Array = _main_hero(reopened.state).get("skill_offers", []).duplicate()
		kept.sort()
		check(kept == pending_view, "el2 #328: offers already shown stay through a load (%s)" % [kept])
	else: check(false, "el2 #328: the save with a pending choice opens " + reopened.error)
	reopened.queue_free()
	await frames(2)

# --- first game -------------------------------------------------------------

func _first_starts(profile: ELProfile) -> void:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	var offers: Array = []
	var loot: Array = []
	for start in STARTS:
		var view := ELAdventureView.new()
		root.add_child(view)
		var built := view.build(profile, row.duplicate(true), settings, 1)
		check(built, "el1 #328: new start %d of the first chapter builds %s" % [start + 1, view.error])
		if not built:
			view.queue_free()
			return
		await frames(2)
		var state := view.state
		var hero := _main_hero(state)
		if hero.is_empty(): hero = state.object(ELGlobalSpells.summon(state, state.current_player, 1))
		if start == 0:
			var codec := ELAdventureSave.new()
			var restored := codec.decode(codec.encode(view.director, {}), {"el1": profile})
			check(not restored.is_empty() and restored.state.seed_value == state.seed_value, "el1 #328: a first-game save keeps the map's random state (#259)")
			if not restored.is_empty(): restored.state.close()
		offers.append(_level_up(state, hero))
		var drawn: Array = []
		for item: Dictionary in state.objects.values():
			if item.get("type") == "monster" and item.get("alive", false): drawn.append(ELAdventureEncounter.loot(state, hero, item))
		loot.append(drawn)
		view.queue_free()
		await frames(2)
	print("el1 #328: first level-up offers %s" % [offers])
	check(_distinct(offers) > 1, "el1 #328: the first level-up offers differ between new campaigns")
	check(_distinct(loot) > 1, "el1 #328: the creatures' loot differs between new campaigns")

# --- helpers ----------------------------------------------------------------

static func _distinct(values: Array) -> int:
	var seen := {}
	for value: Variant in values: seen[var_to_str(value)] = true
	return seen.size()

func _backup(folder: String) -> Dictionary:
	var files := {}
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder): files[file] = FileAccess.get_file_as_bytes(folder.path_join(file))
	return files

func _restore(folder: String, files: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(folder): return
	for file: String in DirAccess.get_files_at(folder):
		if not files.has(file): DirAccess.remove_absolute(folder.path_join(file))
	for file: String in files:
		var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		if out != null: out.store_buffer(files[file])
