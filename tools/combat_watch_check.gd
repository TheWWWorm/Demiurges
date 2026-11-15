extends SceneTree
## The battle camera readout (ELCombatWatch): it keeps above the ground and
## over any rise between it and its figure, and frames a creature whole.
##
##   godot --headless --path game --script ../tools/combat_watch_check.gd

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var aim := Vector3(0, 0.5, 0)
	var from := Vector3(0, 0.6, 3)
	check(ELCombatWatch.lowest_stand(from, aim, flat) >= ELCombatWatch.CLEARANCE - 0.001, "on flat ground the camera keeps its clearance")
	check(ELCombatWatch.lowest_stand(from, aim, Callable()) == -INF, "without the arena's ground nothing is changed")
	# A slope rising towards the camera: the ground under it is 1.5 high.
	var slope := func(_x: float, z: float) -> float: return z * 0.5
	var lowest := ELCombatWatch.lowest_stand(from, aim, slope)
	check(lowest >= 1.5 + ELCombatWatch.CLEARANCE - 0.001, "on a slope the camera stands above the ground under it (%.2f)" % lowest)
	# A ridge halfway between the camera and its aim.
	var ridge := func(_x: float, z: float) -> float: return 1.2 if absf(z - 1.5) < 0.5 else 0.0
	lowest = ELCombatWatch.lowest_stand(from, aim, ridge)
	var line_at := lowest + (aim.y - lowest) * 0.5
	check(line_at >= 1.2 + ELCombatWatch.SIGHT_CLEARANCE - 0.001, "the line of sight clears a rise between the camera and its figure (%.2f)" % line_at)
	# A long, low creature turned towards the camera is framed by its length.
	var rat := AABB(Vector3(-0.2, 0, -0.8), Vector3(0.4, 0.5, 1.6))
	check(ELCombatWatch.whole_span(rat, 2.2) >= 1.6 * ELCombatWatch.WHOLE_DEPTH, "a long creature is framed by its length, not its height")
	var tall := AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 2.0, 0.6))
	check(ELCombatWatch.whole_span(tall, 2.2) >= 2.0, "a tall creature is framed whole")
	print("COMBAT WATCH: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
