extends SceneTree
## Computer exploration over water with ordinary per-player fog. Unlike the
## known-objective integration fixture, this never fills explored cells or
## invokes the console reveal switch. Run with Godot 4.7:
##   godot --headless --path game --script ../tools/first_naval_exploration_check.gd

const Fixture = preload("first_naval_fixture.gd")
var checks := 0
var completed := 0
var failures: Array[String] = []
var label := ""
var trace: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_case(false)
	_case(true)
	label = "completion"
	check(completed == 2, "both computer personalities completed the fog test")
	print("FIRST NAVAL EXPLORATION: %d checks, %d scenarios, %d failure(s)" % [checks, completed, failures.size()])
	for failure: String in failures: printerr("  " + failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: return
	failures.append(label + ": " + what)
	printerr("FAIL: " + failures[-1])

func _case(smart: bool) -> void:
	label = "Smarter AI" if smart else "Original AI"
	var map := Fixture.world()
	# Move authored placements before the first fog computation. The human
	# stays away from the neutral mine; the computer starts on its own shore.
	_place(map.objects[0], Vector2i(9, 28))
	_place(map.objects[1], Vector2i(36, 16))
	Fixture.place(map, "heroes", ELCatalog.HEROES.Blue, Vector2i(55, 17), 2, "Blue")
	var state := ELAdventureSession.new()
	check(state.start(map, 1, 219), "synthetic session starts: " + state.error)
	if not state.error.is_empty(): return
	var champion := state.object(5)
	champion.experience = 150
	var director := ELAdventureDirector.new()
	check(director.build(state), "normal director builds: " + director.error)
	if not director.error.is_empty():
		state.close()
		return
	director.smart_ai = smart
	director.free_movement = false
	director.fast_mode = true
	trace.clear()
	director.grid.actor_moved.connect(_moved.bind(director))
	var worker := state.object(1)
	var target := state.object(4)
	var target_tile := Vector2i(target.x, target.y)
	check(ELFog.active(state, 2), "normal fog is active for the computer")
	check(not ELFog.explored(state, 2, target_tile) and ELFog.object_state(state, 2, target) == ELFog.UNEXPLORED, "the foreign objective starts completely unknown")
	check(not ELFog.explored(state, 2, Fixture.LEFT_LAND), "the destination island's harbor starts unknown")
	check(ELFog.visible(state, 2, Fixture.RIGHT_LAND), "the home harbor is visible from the starting shore")
	check(not worker.ship and not champion.ship and int(target.owner) != 2, "no computer hero starts sailing or already owns the objective")
	var known_before := _known(state, 2)
	ELFirstAI.plan_player(director, 2, false)
	var assigned: Array = ELFirstAI.data(state, 2).assigned
	check(assigned.any(func(pair: Array) -> bool: return pair[1].get("kind") == "explore"), "the real planner selects exploration while the island is unknown")
	check(not assigned.any(func(pair: Array) -> bool: return int(pair[1].get("target", -1)) == int(target.uid)), "the unseen mine is not assigned through unexplored water")
	var days := 0
	var discovered := -1
	var finished_turns := true
	for turn in 30:
		if int(target.owner) == 2: break
		var before := int(state.day)
		if not director.end_day() or not _drive(director):
			finished_turns = false
			break
		days += 1
		if int(state.day) != before + 1:
			finished_turns = false
			break
		if discovered < 0 and ELFog.explored(state, 2, target_tile): discovered = days
	var status := "days=%d, discovered=%d, mine_owner=%d, worker=%s, champion=%s, assignments=%s, error=%s/%s" % [days, discovered, target.owner, Vector2i(worker.x, worker.y), Vector2i(champion.x, champion.y), ELFirstAI.data(state, 2).assigned, state.error, director.error]
	check(finished_turns and days > 0, "ordinary end_day turns finish without encounters or runtime errors: " + status)
	check(discovered > 0 and discovered <= days and _known(state, 2) > known_before, "normal sight discovers the previously unknown objective: " + status)
	check(trace.any(func(row: Dictionary) -> bool: return row.ship), "the computer actually boards and sails during exploration")
	check(trace.any(func(row: Dictionary) -> bool: return row.x < Fixture.LEFT_WATER.x and not row.ship), "the computer actually lands on the opposite island")
	check(int(target.owner) == 2 and days <= 30, "the discovered mine is captured within thirty real turns: " + status)
	check(state.error.is_empty() and director.error.is_empty() and trace.all(func(row: Dictionary) -> bool: return row.ap >= 0), "exploration preserves valid movement budgets and runtime state")
	print("  %s: %s" % [label, status])
	state.close()
	completed += 1

func _place(record: Dictionary, at: Vector2i) -> void:
	record.x = at.x
	record.y = at.y
	for child: Dictionary in record.node.children:
		if child.tag == "place":
			child.attrs.x = str(at.x)
			child.attrs.y = str(at.y)

func _moved(hero: Dictionary, director: ELAdventureDirector) -> void:
	if int(hero.get("owner", -1)) != 2: return
	trace.append({"id": int(hero.uid), "x": int(hero.x), "y": int(hero.y), "ship": bool(hero.get("ship", false)), "ap": int(hero.get("ap", 0)), "day": int(director.state.day)})

func _known(state: ELAdventureSession, player: int) -> int:
	var result := 0
	for cell: int in state.explored:
		if cell & ELFog.bit(player): result += 1
	return result

func _drive(director: ELAdventureDirector) -> bool:
	for frame in 10000:
		if not director.error.is_empty() or not director.state.error.is_empty() or director.encounter != null or not director.state.outcome.is_empty(): return false
		if director.strategy.is_empty() and director.movement.is_empty() and director.free_queue.is_empty(): return true
		director.advance(0.05)
	return false
