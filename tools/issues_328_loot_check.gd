extends SceneTree
## Headless check of #328 (0.30.3 report): a first-game neutral's loot is
## rolled at each victory, not fixed by the save.
## - a save is made on the first chapter's map; each try loads it, as the
##   player does, and wins a battle against the same neutral;
## - the save itself records the map's random state, so a victory on the
##   decoded state alone pays the same every time (the reported behaviour);
## - loaded like a game, it rolls afresh: the loot differs between loads
##   (several distinct payouts over many tries), and a second victory in the
##   same loaded game rolls on as well;
## - every payout stays in the original's range: Loot100 always, Loot66 and
##   Loot33 each on their own percentile roll, each entry its constant plus
##   N rolls of 1..M, times the winner's Search factor, truncated.
##
##   godot --headless --path game --script ../tools/issues_328_loot_check.gd
##
## Needs the first game's files (user://profiles.json). Saves written by a
## mission start are put back afterwards.

const TRIES := 16

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
	var saves := _backup(ELSaveSlots.folder("el1"))
	await _loads(profile)
	_restore(ELSaveSlots.folder("el1"), saves)
	print("ISSUES 328 LOOT CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _settings() -> ELSettings:
	var settings := ELSettings.new()
	settings.use_edition("el1")
	settings.values.show_tutorial = false
	ELFirstTutorial.for_settings(settings).persist = false
	return settings

func _row(profile: ELProfile) -> Dictionary:
	var campaign := ELCampaign.new()
	campaign.load_campaign(profile, "Good")
	var row: Dictionary = campaign.scenarios[0].duplicate()
	row.campaign = "Good"
	return row

func _main_hero(state: ELAdventureSession) -> Dictionary:
	var hero := state.object(state.main_hero)
	if not hero.is_empty() and hero.get("alive", false): return hero
	for item: Dictionary in state.objects.values():
		if item.get("alive", false) and item.get("type") == "hero" and int(item.get("owner", -1)) == state.current_player: return item
	return {}

## The living neutrals with loot, widest range first.
func _neutrals(state: ELAdventureSession) -> Array:
	var found: Array = []
	for item: Dictionary in state.objects.values():
		if item.get("type") != "monster" or not item.get("alive", false): continue
		var row := ELFirstMonsters.definition(state.map.profile, str(item.get("name", "")), int(item.get("monster_difficulty", state.difficulty)))
		var spread := 0
		for tier: String in ["Loot100", "Loot66", "Loot33"]:
			for entry: Array in ELFirstMonsters.loot_entries(row.get(tier, [])): spread += int(entry[1]) * maxi(0, int(entry[2]) - 1) + (1 if tier != "Loot100" else 0)
		if spread > 0: found.append([spread, int(item.uid)])
	found.sort()
	found.reverse()
	return found.map(func(pair: Array) -> int: return pair[1])

## The original's bounds per resource: Loot100 alone at its lowest rolls, all
## three tiers at their highest, times the Search factor (truncated).
func _bounds(state: ELAdventureSession, hero: Dictionary, monster: Dictionary) -> Dictionary:
	var row := ELFirstMonsters.definition(state.map.profile, str(monster.get("name", "")), int(monster.get("monster_difficulty", state.difficulty)))
	var low := {}
	var high := {}
	for kind: String in ELResources.ORIGINAL:
		low[kind] = 0
		high[kind] = 0
	for tier: String in ["Loot100", "Loot66", "Loot33"]:
		for entry: Array in ELFirstMonsters.loot_entries(row.get(tier, [])):
			if tier == "Loot100": low[entry[0]] += int(entry[3]) + int(entry[1])
			high[entry[0]] += int(entry[3]) + int(entry[1]) * maxi(1, int(entry[2]))
	var factor := ELFirstMonsters.loot_multiplier(hero)
	var result := {}
	for kind: String in ELResources.ORIGINAL: result[kind] = [maxi(0, int(float(low[kind]) * factor)), maxi(0, int(float(high[kind]) * factor))]
	return result

func _in_range(draws: Array, bounds: Dictionary) -> bool:
	var paid := {}
	for entry: Array in draws: paid[entry[0]] = int(entry[1])
	for kind: String in ELResources.ORIGINAL:
		var amount := int(paid.get(kind, 0))
		# A kind left out paid nothing, which a low roll of a negative entry allows.
		if paid.has(kind) and (amount < int(bounds[kind][0]) or amount > int(bounds[kind][1])): return false
		if not paid.has(kind) and int(bounds[kind][0]) > 0: return false
	return true

## The hero beats the neutral through the encounter's own finish (the duel
## decided for the hero), and the victory report's resources come back.
func _win(state: ELAdventureSession, hero_id: int, monster_id: int) -> Variant:
	var encounter := ELAdventureEncounter.new()
	if not encounter.prepare(state, hero_id, monster_id): return "prepare: " + encounter.error
	encounter.battle = null
	encounter.auto = true
	encounter.scripted_winner = hero_id
	if not encounter.finish(): return "finish: " + encounter.error
	if state.object(monster_id).get("alive", false): return "the neutral survived"
	return encounter.report.get("resources", [])

func _loads(profile: ELProfile) -> void:
	var view := ELAdventureView.new()
	root.add_child(view)
	if not view.build(profile, _row(profile), _settings(), 1):
		check(false, "el1 #328 loot: the first chapter builds " + view.error)
		view.queue_free()
		return
	await frames(2)
	var state := view.state
	var hero := _main_hero(state)
	if hero.is_empty(): hero = state.object(ELGlobalSpells.summon(state, state.current_player, 1))
	var neutrals := _neutrals(state)
	check(not hero.is_empty() and neutrals.size() >= 2, "el1 #328 loot: the chapter has a hero and neutrals with loot (%d)" % neutrals.size())
	if hero.is_empty() or neutrals.size() < 2:
		view.queue_free()
		return
	var hero_id := int(hero.uid)
	var first: int = neutrals[0]
	var second: int = neutrals[1]
	var monster := state.object(first)
	var bounds := _bounds(state, hero, monster)
	var other_bounds := _bounds(state, hero, state.object(second))
	print("el1 #328 loot: hero %s vs %s (difficulty %d), range %s" % [hero.get("title", hero.get("name")), monster.get("name"), int(monster.get("monster_difficulty", state.difficulty)), bounds])
	var codec := ELAdventureSave.new()
	var checkpoint := codec.encode(view.director, {})
	var saved_seed := state.seed_value
	view.queue_free()
	await frames(2)
	check(not checkpoint.is_empty(), "el1 #328 loot: the map saves " + codec.error)
	if checkpoint.is_empty(): return

	# The decoded save alone: its recorded random state pays the same each time.
	var decoded_rolls: Array = []
	for attempt in 4:
		var restored := codec.decode(checkpoint, {"el1": profile})
		if restored.is_empty():
			check(false, "el1 #328 loot: the save decodes " + codec.error)
			return
		check(restored.state.seed_value == saved_seed, "el1 #328 loot: the save records the map's random state")
		decoded_rolls.append(_win(restored.state, hero_id, first))
		restored.state.close()
	print("el1 #328 loot: victories on the decoded save alone %s" % [decoded_rolls])
	check(decoded_rolls.all(func(roll: Variant) -> bool: return roll is Array) and _distinct(decoded_rolls) == 1, "el1 #328 loot: the decoded save alone pays the same each time (what a load did before)")

	# Loaded as the game loads a save: each victory rolls afresh.
	var rolls: Array = []
	var seconds: Array = []
	var seeds: Array = []
	var ranged := true
	for attempt in TRIES:
		var restored := codec.decode(checkpoint, {"el1": profile})
		if restored.is_empty():
			check(false, "el1 #328 loot: load %d decodes %s" % [attempt + 1, codec.error])
			return
		var loaded := ELAdventureView.new()
		root.add_child(loaded)
		var built := loaded.build(profile, _row(profile), _settings(), 1, restored)
		if not built:
			check(false, "el1 #328 loot: load %d opens the map %s" % [attempt + 1, loaded.error])
			loaded.queue_free()
			return
		await frames(1)
		seeds.append(loaded.state.seed_value)
		var roll: Variant = _win(loaded.state, hero_id, first)
		var again: Variant = _win(loaded.state, hero_id, second)
		if roll is not Array or again is not Array:
			check(false, "el1 #328 loot: load %d wins both battles (%s, %s)" % [attempt + 1, roll, again])
			loaded.queue_free()
			return
		rolls.append(roll)
		seconds.append(again)
		ranged = ranged and _in_range(roll, bounds) and _in_range(again, other_bounds)
		loaded.queue_free()
		await frames(1)
	print("el1 #328 loot: first victory after each of %d loads %s" % [TRIES, rolls])
	print("el1 #328 loot: second victory after each load %s" % [seconds])
	check(not seeds.has(saved_seed) and _distinct(seeds) == TRIES, "el1 #328 loot: each load of a solo save rolls from a fresh random state")
	check(_distinct(rolls) >= 3, "el1 #328 loot: the same neutral pays differently between loads (%d distinct of %d)" % [_distinct(rolls), TRIES])
	check(_distinct(seconds) >= 3, "el1 #328 loot: a later victory in a loaded game rolls on (%d distinct of %d)" % [_distinct(seconds), TRIES])
	check(ranged, "el1 #328 loot: every payout stays within the original's Loot100/66/33 range")

	_rates(profile, codec, checkpoint, hero_id, first)

## Many victories from fresh random states, decoded directly: the payouts
## spread over the original range and reach both its ends.
func _rates(profile: ELProfile, codec: ELAdventureSave, checkpoint: Dictionary, hero_id: int, monster_id: int) -> void:
	var restored := codec.decode(checkpoint, {"el1": profile})
	if restored.is_empty(): return
	var state: ELAdventureSession = restored.state
	var hero := state.object(hero_id)
	var monster := state.object(monster_id)
	var row := ELFirstMonsters.definition(profile, str(monster.get("name", "")), int(monster.get("monster_difficulty", state.difficulty)))
	var bounds := _bounds(state, hero, monster)
	var totals: Array = []
	var ranged := true
	for trial in 2000:
		state.fresh_random_state()
		var draws := ELFirstMonsters.scale_loot(ELFirstMonsters.roll_loot(row, func() -> int: return ELAdditionalBuildings._random(state)), hero)
		ranged = ranged and _in_range(draws, bounds)
		var sum := 0
		for entry: Array in draws: sum += int(entry[1])
		totals.append(sum)
	var low := 0
	var high := 0
	for kind: String in ELResources.ORIGINAL:
		low += int(bounds[kind][0])
		high += int(bounds[kind][1])
	print("el1 #328 loot: 2000 rolls total %d..%d (range %d..%d), %d distinct totals" % [totals.min(), totals.max(), low, high, _distinct(totals)])
	check(ranged and int(totals.min()) >= low and int(totals.max()) <= high, "el1 #328 loot: 2000 fresh rolls stay in the original's range")
	check(_distinct(totals) >= mini(5, high - low + 1), "el1 #328 loot: fresh rolls spread over the range")
	state.close()

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
		var handle := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
		if handle != null: handle.store_buffer(files[file])
