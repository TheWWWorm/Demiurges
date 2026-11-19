extends SceneTree
## Actual naval duel construction and return-to-map integration, using only
## synthetic data. Run with Godot 4.7:
##   godot --headless --path game --script ../tools/first_naval_battle_check.gd
## This does not test original arena models or textures (those require an
## installed game). The fixture deliberately has no EL2 Ship.001 arena.

const Fixture = preload("first_naval_fixture.gd")
var checks := 0
var completed := 0
var failures: Array[String] = []
var label := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_case("open water", Vector2i(27, 16), Vector2i(28, 16), "Ether.001", true)
	_case("landing assault", Fixture.RIGHT_WATER, Fixture.RIGHT_LAND, "Blue.002", true)
	_case("defending the harbor", Fixture.LEFT_LAND, Fixture.LEFT_WATER, "Blue.002", false)
	label = "completion"
	check(completed == 3, "all three actual battle scenarios completed")
	print("FIRST NAVAL BATTLES: %d checks, %d scenarios, %d failure(s)" % [checks, completed, failures.size()])
	for failure: String in failures: printerr("  " + failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: return
	failures.append(label + ": " + what)
	printerr("FAIL: " + failures[-1])

func _case(title: String, first: Vector2i, second: Vector2i, arena: String, survivor_ship: bool) -> void:
	label = title
	var map := Fixture.world()
	# The normal first-game battlefield names, without copyrighted geometry.
	# ELDuel.start verifies this registry before creating either combatant.
	map.profile.tables.CombatSceneDB = {}
	for name: String in ELAdventureEncounter.FIRST_ARENAS: map.profile.tables.CombatSceneDB[name] = {"synthetic": true}
	var income := {}
	for turn in range(1, 25):
		var row := {}
		for level in range(1, 21): row["Level%d" % level] = 1
		income[str(turn)] = row
	map.profile.tables.CombatManaIncome = income
	var state := ELAdventureSession.new()
	check(state.start(map, 1, 711), "synthetic session starts: " + state.error)
	if not state.error.is_empty(): return
	var director := ELAdventureDirector.new()
	check(director.build(state), "actual director builds: " + director.error)
	if not director.error.is_empty():
		state.close()
		return
	var hero := state.object(0)
	var enemy := state.object(1)
	for pair: Array in [[hero, first], [enemy, second]]:
		pair[0].x = pair[1].x
		pair[0].y = pair[1].y
		pair[0].ship = ELFirstNaval.is_water(map, pair[1])
		director.grid.update_actor(pair[0])
	director.interception.rebuild(state, director.grid)
	check(ELStrategy.adjacent(director, hero, enemy), "opponents can actually engage at these cells")
	var before_ap := int(hero.ap)
	director.use_object(int(hero.uid), int(enemy.uid), int(enemy.uid))
	check(director.encounter != null, "real use_object prepares a battle: " + director.notice)
	if director.encounter == null:
		state.close()
		return
	var battle := director.encounter.battle
	check(battle != null and battle.error.is_empty(), "duel constructor accepts the combatants and terrain")
	if battle == null:
		state.close()
		return
	check(battle.profile == map.profile and battle.profile.id == "el1", "battle keeps its first-game rules and content profile")
	check(battle.setup.arena == arena and battle.setup.arena != "Ship.001", "battle uses the expected ordinary EL1 arena: " + str(battle.setup.arena))
	check(battle.heroes[0].template == hero.name and battle.heroes[1].template == enemy.name, "strategic ship form does not replace either combat hero template")
	check(battle.heroes[0].deck == hero.cards and battle.heroes[0].deck.size() == 15 and battle.heroes[0].hand.size() == 5, "first combatant retains its complete spellbook and draws an opening hand")
	check(battle.heroes[1].deck == enemy.cards and battle.heroes[1].deck.size() == 15 and battle.heroes[1].hand.size() == 5, "second combatant retains its complete spellbook and draws an opening hand")
	check(battle.phase == ELDuel.Phase.ATTACK and battle.active_side() in [0, 1], "the naval battle has a valid opening turn")
	check(battle.cast(0), "a normal creature spell can be cast in the naval encounter: " + battle.error)
	check(battle.creatures.size() == 1, "the cast creates a real tactical creature")
	var first_side := battle.active_side()
	check(battle.end_phase() and battle.phase == ELDuel.Phase.ATTACK and battle.active_side() != first_side, "ending an unopposed turn advances through defence to the opponent's turn")
	var restored := ELDuel.new()
	var document := {"format": "etherlords-duel", "version": 1, "state": battle.snapshot()}
	check(restored.restore(map.profile, JSON.parse_string(JSON.stringify(document))), "the active naval duel survives a JSON snapshot: " + restored.error)
	if restored.scripts != null: restored.scripts.close()
	# Supply a controlled tactical result, then execute the real encounter
	# finish path to test strategic death, occupancy, and the survivor's mode.
	battle._declare_victory(0)
	check(director.finish_encounter(), "the finished duel returns through the real director: " + director.error)
	check(hero.alive and not enemy.alive, "the winner survives and the defeated hero is removed")
	check(not director.grid.occupied.has(int(enemy.uid)), "a defeated ship or harbor defender no longer blocks its tile")
	check(Vector2i(hero.x, hero.y) == first and hero.ship == survivor_ship, "combat neither teleports the winner nor grants a free landing")
	check(int(hero.ap) == before_ap, "combat preserves the movement balance for the subsequent landing")
	check(not director.grid.occupies(enemy), "dead heroes at sea cannot occupy or navigate a boat")
	check(ELFirstNaval.step_cost(director.grid, first, second) > 0, "the freed destination can be reached with its ordinary movement cost")
	state.close()
	completed += 1
