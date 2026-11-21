extends SceneTree
## Headless check of new-start and retry randomness:
## - #259: every new local start of a first-game mission seeds the map's
##   random state afresh, so castle recruits differ between starts; a save
##   keeps the state, so a loaded game recruits the hero it would have;
## - #263: Try again in a map battle deals the same battle anew, with new
##   opening hands, in the first game too (the second game's retry runs in
##   issue_reports_check); who moves first is decided afresh, by the home
##   terrain or the new seed's coin flip, counted over 200 retries.
##
##   godot --headless --path game --script ../tools/issue_seeds_check.gd
##
## Needs the first game's files (user://profiles.json). A mission start writes
## the first game's mission-start autosave.

const VIEW_SCRIPT := preload("res://src/duel/view.gd")

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
	var profile := ELProfile.new()
	if paths is not Dictionary or not paths.has("el1") or not profile.mount("el1", str(paths.el1)):
		print("SKIP: no first-game files configured (user://profiles.json)")
		quit(0)
		return
	await _new_starts(profile)
	_retry_hands(profile)
	print("ISSUE SEEDS CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _summoned(state: ELAdventureSession) -> Array:
	var id := ELGlobalSpells.summon(state, state.current_player, 1)
	var hero := state.object(id)
	return [hero.get("name"), hero.get("title"), hero.get("specialization")] if id >= 0 else []

# --- #259 ---------------------------------------------------------------------

func _new_starts(profile: ELProfile) -> void:
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	var seeds: Array[int] = []
	var recruits: Array = []
	for start in 3:
		var view := ELAdventureView.new()
		root.add_child(view)
		var built := view.build(profile, {"file_name": "pmission05"}, settings, 1)
		check(built, "el1 #259: start %d of a single mission builds %s" % [start + 1, view.error])
		if not built:
			view.queue_free()
			return
		await frames(2)
		var state := view.state
		seeds.append(state.seed_value)
		if start == 0:
			# A save keeps the random state: the loaded game recruits the same hero.
			var codec := ELAdventureSave.new()
			var restored := codec.decode(codec.encode(view.director, {}), {"el1": profile})
			check(not restored.is_empty() and restored.state.seed_value == state.seed_value, "el1 #259: a save keeps the map's random state")
			if not restored.is_empty():
				var loaded := _summoned(restored.state)
				recruits.append(_summoned(state))
				check(not loaded.is_empty() and loaded == recruits[0], "el1 #259: the loaded game recruits the hero the saved one would (%s)" % [loaded])
				restored.state.close()
		else: recruits.append(_summoned(state))
		view.queue_free()
		await frames(2)
	check(not seeds.has(212) and seeds[0] != seeds[1] and seeds[1] != seeds[2], "el1 #259: each new start draws its own random state (%s)" % [seeds])
	check(not (recruits[0] == recruits[1] and recruits[1] == recruits[2]), "el1 #259: the castle's first recruit differs between new starts (%s)" % [recruits])

# --- #263 ---------------------------------------------------------------------

func _retry_hands(profile: ELProfile) -> void:
	var map := ELAdventureMap.new()
	var state := ELAdventureSession.new()
	var director := ELAdventureDirector.new()
	if not (map.load_map(profile, "pmission05") and state.start(map, 1, 212, "", 1, false) and director.build(state)):
		check(false, "el1 #263: the battle map loads")
		state.close()
		return
	var hero := {}
	var monster := {}
	for item: Dictionary in state.objects.values():
		if not item.get("alive", false): continue
		if hero.is_empty() and item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player: hero = item
		if monster.is_empty() and item.get("type") == "monster": monster = item
	# A single mission opens without heroes: the castle recruits one.
	if hero.is_empty(): hero = state.object(ELGlobalSpells.summon(state, state.current_player, 1))
	var encounter := ELAdventureEncounter.new()
	var ready := not hero.is_empty() and not monster.is_empty() and encounter.prepare(state, int(hero.uid), int(monster.uid))
	check(ready, "el1 #263: a hero meets a creature in battle %s" % encounter.error)
	if not ready:
		state.close()
		return
	director.encounter = encounter
	var opening: ELDuel = encounter.battle
	var hands := opening.heroes.map(func(h: Dictionary) -> Array: return h.hand.duplicate())
	var codec := ELAdventureSave.new()
	var checkpoint := codec.encode(director, {})
	var restored := codec.decode(checkpoint, {"el1": profile})
	check(not restored.is_empty() and restored.director.encounter != null, "el1 #263: the encounter checkpoint restores")
	if restored.is_empty():
		state.close()
		return
	var again: ELAdventureEncounter = restored.director.encounter
	check(again.battle.heroes.map(func(h: Dictionary) -> Array: return h.hand) == hands, "el1 #263: the checkpoint alone deals the old hands")
	VIEW_SCRIPT._redeal_encounter(again)
	var retried: ELDuel = again.battle
	check(_without_first(retried.setup) == _without_first(opening.setup) and retried.phase == opening.phase and retried.attacker == retried.first_side()
		and retried.heroes.map(func(h: Dictionary) -> int: return h.health) == opening.heroes.map(func(h: Dictionary) -> int: return h.health),
		"el1 #263: Try again restarts the same battle")
	check(retried.heroes.map(func(h: Dictionary) -> Array: return h.hand) != hands, "el1 #263: Try again deals new opening hands")
	check(retried.adventure_session() == restored.state, "el1 #263: the new battle belongs to the restored map")
	_retry_first_sides(again, opening)
	restored.state.close()
	state.close()

static func _without_first(setup: Dictionary) -> Dictionary:
	var copy := setup.duplicate(true)
	copy.erase("first_side")
	return copy

## Who moves first after Try again is decided as for a new battle: the home
## terrain when it favours one side (then always that side), otherwise the
## new seed's coin flip (then both sides turn up over many retries).
func _retry_first_sides(encounter: ELAdventureEncounter, opening: ELDuel) -> void:
	var decided: int = encounter.first_side_for(opening.setup, 0)
	var terrain := decided == encounter.first_side_for(opening.setup, 1)
	var counts := [0, 0]
	var consistent := true
	for retry in 200:
		VIEW_SCRIPT._redeal_encounter(encounter)
		var battle: ELDuel = encounter.battle
		counts[battle.first_side()] += 1
		if battle.attacker != battle.first_side() or _without_first(battle.setup) != _without_first(opening.setup): consistent = false
	print("el1 #263: first side over 200 retries: side 0 %d, side 1 %d (%s)" % [counts[0], counts[1], "home terrain decides" if terrain else "coin flip"])
	if terrain: check(counts[decided] == 200 and consistent, "el1 #263: when the home terrain decides, every retry keeps that side first")
	else: check(counts[0] >= 60 and counts[1] >= 60 and consistent, "el1 #263: Try again flips a new coin for who moves first (%s)" % [counts])
	# The same map battle with the coin flip forced: no side's colour matches
	# the battle tile, so only the seed's parity decides.
	var setup := opening.setup.duplicate(true)
	var coin := false
	for faction: String in ["Red", "Green", "Blue", "Black"]:
		setup.players[0].faction = faction
		setup.players[1].faction = faction
		if encounter.first_side_for(setup, 0) == 0 and encounter.first_side_for(setup, 1) == 1: coin = true
	check(coin, "el1 #263: sides of one colour (the home terrain favours neither) take the new seed's coin flip")
