extends SceneTree
## Headless check of the original games' map difficulty in battles:
## - first game: the temporary battle levels of all 200 campaign-mode rows
##   recorded from the original game (five difficulties, the local player on
##   either side, levels 1-20, fort tiers), the local side found by its owner;
## - second game: difficulty moves the battle level itself (ether income,
##   disturbance, specialisation chance, the scripts' ExGetPlayerLevel) by
##   +2/-1 on Easy and +2 for the opponent on Hard; the hero's own level stays
##   on the map, in ExGetPlayerOriginalLevel and in the battle tooltip, and
##   survives a battle save;
## - the second game keeps three difficulties (a fourth or fifth would pick
##   the easiest map variants), and the campaign chooser opens on Normal.
##
##   godot --headless --path game --script ../tools/difficulty_check.gd
##
## The second-game part needs its files (user://profiles.json); without them
## it is skipped.

## [difficulty, local side, level 0, level 1, fort tier 0, fort tier 1 (-1 none), result 0, result 1]
const FIRST_ROWS := "[[0,0,1,1,-1,-1,3,1],[0,0,1,1,2,-1,4,1],[0,0,1,1,-1,2,3,1],[0,0,1,1,1,0,3,1],[0,0,1,1,2,2,4,1],[0,0,10,10,-1,-1,12,9],[0,0,10,10,2,-1,13,9],[0,0,10,10,-1,2,12,10],[0,0,10,10,1,0,12,9],[0,0,10,10,2,2,13,10],[0,0,19,20,-1,-1,20,19],[0,0,19,20,2,-1,20,19],[0,0,19,20,-1,2,20,20],[0,0,19,20,1,0,20,19],[0,0,19,20,2,2,20,20],[0,0,20,1,-1,-1,20,1],[0,0,20,1,2,-1,20,1],[0,0,20,1,-1,2,20,1],[0,0,20,1,1,0,20,1],[0,0,20,1,2,2,20,1],[0,1,1,1,-1,-1,1,3],[0,1,1,1,2,-1,1,3],[0,1,1,1,-1,2,1,4],[0,1,1,1,1,0,1,3],[0,1,1,1,2,2,1,4],[0,1,10,10,-1,-1,9,12],[0,1,10,10,2,-1,10,12],[0,1,10,10,-1,2,9,13],[0,1,10,10,1,0,9,12],[0,1,10,10,2,2,10,13],[0,1,19,20,-1,-1,18,20],[0,1,19,20,2,-1,19,20],[0,1,19,20,-1,2,18,20],[0,1,19,20,1,0,18,20],[0,1,19,20,2,2,19,20],[0,1,20,1,-1,-1,19,3],[0,1,20,1,2,-1,20,3],[0,1,20,1,-1,2,19,4],[0,1,20,1,1,0,19,3],[0,1,20,1,2,2,20,4],[1,0,1,1,-1,-1,2,1],[1,0,1,1,2,-1,3,1],[1,0,1,1,-1,2,2,2],[1,0,1,1,1,0,2,1],[1,0,1,1,2,2,3,2],[1,0,10,10,-1,-1,11,10],[1,0,10,10,2,-1,12,10],[1,0,10,10,-1,2,11,11],[1,0,10,10,1,0,11,10],[1,0,10,10,2,2,12,11],[1,0,19,20,-1,-1,20,20],[1,0,19,20,2,-1,20,20],[1,0,19,20,-1,2,20,20],[1,0,19,20,1,0,20,20],[1,0,19,20,2,2,20,20],[1,0,20,1,-1,-1,20,1],[1,0,20,1,2,-1,20,1],[1,0,20,1,-1,2,20,2],[1,0,20,1,1,0,20,1],[1,0,20,1,2,2,20,2],[1,1,1,1,-1,-1,1,2],[1,1,1,1,2,-1,2,2],[1,1,1,1,-1,2,1,3],[1,1,1,1,1,0,1,2],[1,1,1,1,2,2,2,3],[1,1,10,10,-1,-1,10,11],[1,1,10,10,2,-1,11,11],[1,1,10,10,-1,2,10,12],[1,1,10,10,1,0,10,11],[1,1,10,10,2,2,11,12],[1,1,19,20,-1,-1,19,20],[1,1,19,20,2,-1,20,20],[1,1,19,20,-1,2,19,20],[1,1,19,20,1,0,19,20],[1,1,19,20,2,2,20,20],[1,1,20,1,-1,-1,20,2],[1,1,20,1,2,-1,20,2],[1,1,20,1,-1,2,20,3],[1,1,20,1,1,0,20,2],[1,1,20,1,2,2,20,3],[2,0,1,1,-1,-1,1,1],[2,0,1,1,2,-1,2,1],[2,0,1,1,-1,2,1,2],[2,0,1,1,1,0,1,1],[2,0,1,1,2,2,2,2],[2,0,10,10,-1,-1,10,10],[2,0,10,10,2,-1,11,10],[2,0,10,10,-1,2,10,11],[2,0,10,10,1,0,10,10],[2,0,10,10,2,2,11,11],[2,0,19,20,-1,-1,19,20],[2,0,19,20,2,-1,20,20],[2,0,19,20,-1,2,19,20],[2,0,19,20,1,0,19,20],[2,0,19,20,2,2,20,20],[2,0,20,1,-1,-1,20,1],[2,0,20,1,2,-1,20,1],[2,0,20,1,-1,2,20,2],[2,0,20,1,1,0,20,1],[2,0,20,1,2,2,20,2],[2,1,1,1,-1,-1,1,1],[2,1,1,1,2,-1,2,1],[2,1,1,1,-1,2,1,2],[2,1,1,1,1,0,1,1],[2,1,1,1,2,2,2,2],[2,1,10,10,-1,-1,10,10],[2,1,10,10,2,-1,11,10],[2,1,10,10,-1,2,10,11],[2,1,10,10,1,0,10,10],[2,1,10,10,2,2,11,11],[2,1,19,20,-1,-1,19,20],[2,1,19,20,2,-1,20,20],[2,1,19,20,-1,2,19,20],[2,1,19,20,1,0,19,20],[2,1,19,20,2,2,20,20],[2,1,20,1,-1,-1,20,1],[2,1,20,1,2,-1,20,1],[2,1,20,1,-1,2,20,2],[2,1,20,1,1,0,20,1],[2,1,20,1,2,2,20,2],[3,0,1,1,-1,-1,1,2],[3,0,1,1,2,-1,2,2],[3,0,1,1,-1,2,1,3],[3,0,1,1,1,0,1,2],[3,0,1,1,2,2,2,3],[3,0,10,10,-1,-1,10,11],[3,0,10,10,2,-1,11,11],[3,0,10,10,-1,2,10,12],[3,0,10,10,1,0,10,11],[3,0,10,10,2,2,11,12],[3,0,19,20,-1,-1,19,20],[3,0,19,20,2,-1,20,20],[3,0,19,20,-1,2,19,20],[3,0,19,20,1,0,19,20],[3,0,19,20,2,2,20,20],[3,0,20,1,-1,-1,20,2],[3,0,20,1,2,-1,20,2],[3,0,20,1,-1,2,20,3],[3,0,20,1,1,0,20,2],[3,0,20,1,2,2,20,3],[3,1,1,1,-1,-1,2,1],[3,1,1,1,2,-1,3,1],[3,1,1,1,-1,2,2,2],[3,1,1,1,1,0,2,1],[3,1,1,1,2,2,3,2],[3,1,10,10,-1,-1,11,10],[3,1,10,10,2,-1,12,10],[3,1,10,10,-1,2,11,11],[3,1,10,10,1,0,11,10],[3,1,10,10,2,2,12,11],[3,1,19,20,-1,-1,20,20],[3,1,19,20,2,-1,20,20],[3,1,19,20,-1,2,20,20],[3,1,19,20,1,0,20,20],[3,1,19,20,2,2,20,20],[3,1,20,1,-1,-1,20,1],[3,1,20,1,2,-1,20,1],[3,1,20,1,-1,2,20,2],[3,1,20,1,1,0,20,1],[3,1,20,1,2,2,20,2],[4,0,1,1,-1,-1,1,3],[4,0,1,1,2,-1,2,3],[4,0,1,1,-1,2,1,4],[4,0,1,1,1,0,1,3],[4,0,1,1,2,2,2,4],[4,0,10,10,-1,-1,10,12],[4,0,10,10,2,-1,11,12],[4,0,10,10,-1,2,10,13],[4,0,10,10,1,0,10,12],[4,0,10,10,2,2,11,13],[4,0,19,20,-1,-1,19,20],[4,0,19,20,2,-1,20,20],[4,0,19,20,-1,2,19,20],[4,0,19,20,1,0,19,20],[4,0,19,20,2,2,20,20],[4,0,20,1,-1,-1,20,3],[4,0,20,1,2,-1,20,3],[4,0,20,1,-1,2,20,4],[4,0,20,1,1,0,20,3],[4,0,20,1,2,2,20,4],[4,1,1,1,-1,-1,3,1],[4,1,1,1,2,-1,4,1],[4,1,1,1,-1,2,3,2],[4,1,1,1,1,0,3,1],[4,1,1,1,2,2,4,2],[4,1,10,10,-1,-1,12,10],[4,1,10,10,2,-1,13,10],[4,1,10,10,-1,2,12,11],[4,1,10,10,1,0,12,10],[4,1,10,10,2,2,13,11],[4,1,19,20,-1,-1,20,20],[4,1,19,20,2,-1,20,20],[4,1,19,20,-1,2,20,20],[4,1,19,20,1,0,20,20],[4,1,19,20,2,2,20,20],[4,1,20,1,-1,-1,20,1],[4,1,20,1,2,-1,20,1],[4,1,20,1,-1,2,20,2],[4,1,20,1,1,0,20,1],[4,1,20,1,2,2,20,2]]"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_first_rows()
	_second_rule()
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is Dictionary and paths.has("el2"):
		var profile := ELProfile.new()
		if profile.mount("el2", str(paths.el2)): _second_battle(profile)
		else: print("SKIP: the second game's files could not be mounted")
	else: print("SKIP: no second-game files configured (user://profiles.json)")
	_chooser()
	print("DIFFICULTY: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _fixture() -> ELAdventureSession:
	var state := ELAdventureSession.new()
	state.current_player = 1
	for id: int in [1, 2]:
		state.objects[id] = {"uid": id, "type": "hero", "owner": id, "level": 1, "alive": true, "fortified": false, "fort": -1}
		state.objects[10 + id] = {"uid": 10 + id, "type": "fort", "garrison": -1, "fort_level": 0, "alive": true}
	return state

func _garrison(state: ELAdventureSession, id: int, tier: int) -> void:
	var actor := state.object(id)
	var fort := state.object(10 + id)
	actor.fortified = tier >= 0
	actor.fort = fort.uid if tier >= 0 else -1
	fort.garrison = id if tier >= 0 else -1
	fort.fort_level = maxi(tier, 0)

func _first_rows() -> void:
	var rows: Array = JSON.parse_string(FIRST_ROWS)
	var state := _fixture()
	var matched := 0
	var wrong: Array = []
	for row: Array in rows:
		state.difficulty = int(row[0])
		var local := int(row[1])
		for side in 2:
			var actor := state.object(side + 1)
			actor.level = int(row[2 + side])
			# The local player's hero sits on the recorded local side.
			actor.owner = 1 if side == local else 2
			_garrison(state, side + 1, int(row[4 + side]))
		var actual := ELAdventureEncounter.first_levels(state, 1, 2)
		if actual == [int(row[6]), int(row[7])]: matched += 1
		elif wrong.size() < 5: wrong.append([row, actual])
	check(rows.size() == 200 and matched == rows.size(), "first game: battle levels match %d/%d original rows %s" % [matched, rows.size(), wrong])
	# The local player's hero may be on the second side: a computer hero
	# there is not helped by the player's difficulty.
	state = _fixture()
	state.difficulty = 0
	state.object(1).owner = 2
	state.object(2).owner = 1
	state.object(1).level = 5
	state.object(2).level = 5
	check(ELAdventureEncounter.first_levels(state, 1, 2) == [4, 7], "first game, Easy: the local player's hero gains two on the second side, the computer's loses one")
	state.difficulty = 4
	check(ELAdventureEncounter.first_levels(state, 1, 2) == [7, 5], "first game, Master: the computer's hero gains two on the first side")
	# A guest's battle prepared by the host: neither side is the host's.
	state.object(2).owner = 3
	check(ELAdventureEncounter.first_levels(state, 1, 2) == [5, 7], "first game: with no local hero the first side counts as the player's")

func _second_rule() -> void:
	var levels: Array[int] = [5, 5]
	check(ELSpecs.second_levels(levels, 0, 0) == [7, 4] and ELSpecs.second_levels(levels, 1, 0) == [5, 5] and ELSpecs.second_levels(levels, 2, 0) == [5, 7], "second game: Easy +2/-1, Normal none, Hard opponent +2")
	var high: Array[int] = [20, 1]
	var low: Array[int] = [1, 20]
	check(ELSpecs.second_levels(high, 0, 0) == [20, 1] and ELSpecs.second_levels(low, 2, 0) == [1, 20], "second game: battle levels stay within 1-20")

func _second_map(profile: ELProfile) -> String:
	for id: String in ELCampaign.available(profile):
		var data := ELCampaign.new()
		if data.load_campaign(profile, id) and not data.scenarios.is_empty(): return str(data.scenarios[0].file_name)
	return ""

func _sides(state: ELAdventureSession) -> Array[Dictionary]:
	var hero := {}
	var opponent := {}
	for item: Dictionary in state.objects.values():
		if item.get("type") != "hero" or not item.get("alive", false) or item.get("fortified", false): continue
		if int(item.get("owner", -1)) == 1:
			hero = item
			break
	if hero.is_empty(): return []
	for item: Dictionary in state.objects.values():
		if item.get("type") not in ["hero", "monster"] or not item.get("alive", false) or item.get("fortified", false): continue
		if int(item.get("owner", -1)) != 1 and state.hostile(hero, item):
			opponent = item
			break
	if opponent.is_empty(): return []
	return [hero, opponent]

func _second_battle(profile: ELProfile) -> void:
	var map_id := _second_map(profile)
	var map := ELAdventureMap.new()
	if map_id.is_empty() or not map.load_map(profile, map_id):
		check(false, "second game: a chapter map loads (%s)" % map_id)
		return
	var state := ELAdventureSession.new()
	check(state.start(map, 4) and state.difficulty == 2, "second game: a fifth difficulty is played as the hardest of three")
	state.close()
	for difficulty in 3:
		state = ELAdventureSession.new()
		if not state.start(map, difficulty):
			check(false, "second game: %s starts at difficulty %d: %s" % [map_id, difficulty, state.error])
			return
		var sides := _sides(state)
		if sides.is_empty():
			check(false, "second game: %s has a player hero and a hostile side" % map_id)
			state.close()
			return
		var hero: Dictionary = sides[0]
		var opponent: Dictionary = sides[1]
		hero.level = 5
		opponent.level = 5
		var label := "second game, %s" % ["Easy", "Normal", "Hard"][difficulty]
		var expected: Array = [[7, 4], [5, 5], [5, 7]][difficulty]
		for attacking: bool in [true, false]:
			var encounter := ELAdventureEncounter.new()
			var ok := encounter.prepare(state, int(hero.uid) if attacking else int(opponent.uid), int(opponent.uid) if attacking else int(hero.uid))
			if not ok or encounter.battle == null:
				check(false, "%s: the battle starts: %s" % [label, encounter.error])
				continue
			var battle := encounter.battle
			var own := encounter.player_side()
			var heroes: Array = [battle.heroes[own], battle.heroes[1 - own]]
			var role := "attacking" if attacking else "attacked"
			check(int(heroes[0].level) == expected[0] and int(heroes[1].level) == expected[1], "%s, the player %s: battle levels %s (got %d, %d)" % [label, role, expected, heroes[0].level, heroes[1].level])
			check(int(heroes[0].spec_level) == expected[0] and int(heroes[1].spec_level) == expected[1], "%s, the player %s: specialisation levels follow" % [label, role])
			check(int(heroes[0].get("map_level", -1)) == 5 and int(heroes[1].get("map_level", -1)) == 5 and int(hero.level) == 5 and int(opponent.level) == 5, "%s, the player %s: the heroes keep their own level" % [label, role])
			var scripts := ELBattleScripts.new(battle)
			scripts.in_combat = true
			check(scripts._native([float(own)], "ExGetPlayerLevel") == [float(expected[0])] and scripts._native([float(own)], "ExGetPlayerOriginalLevel") == [5.0], "%s, the player %s: ExGetPlayerLevel is the battle level, ExGetPlayerOriginalLevel the hero's own" % [label, role])
			var restored := ELDuel.new()
			var snapshot := {"format": "etherlords-duel", "version": 1, "state": JSON.parse_string(JSON.stringify(battle.snapshot()))}
			check(restored.restore(profile, snapshot) and int(restored.heroes[own].level) == expected[0] and int(restored.heroes[own].get("map_level", -1)) == 5, "%s, the player %s: a battle save keeps both levels" % [label, role])
		state.close()

func _chooser() -> void:
	var setup := ELCampaignSetup.new()
	setup.difficulty = OptionButton.new()
	setup._difficulties("el1")
	check(setup.difficulty.selected == 1, "the campaign chooser opens on Normal")
	setup.difficulty.select(4)
	setup._difficulties("el2")
	check(setup.difficulty.item_count == 3 and setup.difficulty.selected == 2, "the second game's chooser offers three difficulties")
	setup.difficulty.free()
	setup.free()
