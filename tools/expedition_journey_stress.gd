extends SceneTree
## Randomized complete-run checkpoint stress test. Uses synthetic maps and
## card tables, starts real duel objects, then FORCES victory with simulated
## damage and round counts. This is state-machine/persistence verification,
## not an AI win-rate, difficulty, or installed-game balance measurement.
## Never reads, writes, or deletes the player's Expedition checkpoint.
##
## godot --headless --path game --script ../tools/expedition_journey_stress.gd
## Optional: -- --runs=48 --route-seeds=256

const Fixture := preload("expedition_fixture.gd")
const ROOT := "user://expedition_journey_stress"
const STEP_LIMIT := 200
const CHOICE_SEED := 20261120
var failures := 0
var transitions := 0
var completed := 0

func _initialize() -> void:
	_run.call_deferred()

func _count_arg(name: String, fallback: int, maximum: int) -> int:
	var prefix := "--" + name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			var value := argument.trim_prefix(prefix)
			if value.is_valid_int(): return clampi(int(value), 1, maximum)
	return fallback

func _fail(message: String) -> void:
	failures += 1
	printerr("FAIL: " + message)

func _run() -> void:
	var runs := _count_arg("runs", 48, 4096)
	var route_seeds := _count_arg("route-seeds", 256, 65536)
	var source := Fixture.profile_at(ROOT)
	print("INPUT: synthetic fixtures; forced combat victories, simulated damage and round counts")
	if source == null:
		_fail("Synthetic profile is unavailable")
		quit(1)
		return
	_check_pacing(source, route_seeds)
	var random := RandomNumberGenerator.new()
	random.seed = CHOICE_SEED
	for seed_value in runs:
		_exercise_journey(source, seed_value, random)
	if completed != runs: _fail("Not every requested journey reached a terminal state")
	Fixture.clean(ROOT)
	print("EXPEDITION JOURNEY STRESS: %d/%d complete runs, %d checked transitions, %d failure(s)" % [completed, runs, transitions, failures])
	quit(1 if failures > 0 else 0)

func _check_pacing(source: ELProfile, route_seeds: int) -> void:
	var minimum_histogram := {}
	var treasure_histogram := {}
	for seed_value in route_seeds:
		var run := ELExpeditionRun.new()
		if not run.create(source, "ExpeditionFixtureRed", seed_value):
			_fail("Pacing probe could not create seed %d: %s" % [seed_value, run.error])
			return
		var minimum := {}
		var with_treasure := {}
		for row: Array in run.route():
			for room: Dictionary in row:
				if room.floor == 1: minimum[room.id] = 0
				var combat := int(room.kind in ["fight", "elite", "boss"])
				var cost := int(minimum.get(room.id, 999)) + combat
				var treasure_cost := int(with_treasure.get(room.id, 999)) + combat
				if room.kind == "treasure": treasure_cost = cost
				if room.kind == "boss":
					minimum_histogram[cost] = int(minimum_histogram.get(cost, 0)) + 1
					if treasure_cost < 999: treasure_histogram[treasure_cost] = int(treasure_histogram.get(treasure_cost, 0)) + 1
					if cost < 3: _fail("Seed %d can avoid the mid-act combat" % seed_value)
				for next: String in room.next:
					minimum[next] = mini(int(minimum.get(next, 999)), cost)
					with_treasure[next] = mini(int(with_treasure.get(next, 999)), treasure_cost)
	print("MINIMUM ACT I COMBATS INCLUDING GUARDIAN: ", minimum_histogram)
	print("MINIMUM ACT I COMBATS WITH TREASURE: ", treasure_histogram)

func _exercise_journey(source: ELProfile, seed_value: int, random: RandomNumberGenerator) -> void:
	var run := ELExpeditionRun.new()
	var faction: String = ELDuelPresets.RACES[seed_value % ELDuelPresets.RACES.size()]
	if not run.create(source, "ExpeditionFixture" + faction, seed_value):
		_fail("Could not create run %d: %s" % [seed_value, run.error])
		return
	var steps := 0
	while not run.finished() and steps < STEP_LIMIT:
		steps += 1
		if run.phase == "map":
			var available := run.available()
			if available.is_empty() or not run.choose_node(available[random.randi_range(0, available.size() - 1)]):
				_fail("No available room for seed %d: %s" % [seed_value, run.error])
				return
		elif run.phase == "battle":
			var duel := run.build_battle()
			if duel == null:
				_fail("Build battle for seed %d: %s" % [seed_value, run.error])
				return
			# Deliberately skip AI combat. Exercise postcombat contracts, gold,
			# healing, preparation consumption, and reward-state transitions.
			duel.heroes[0].health = maxi(1, int(duel.heroes[0].health) - random.randi_range(0, 7))
			duel.heroes[1].health = 0
			duel.winner = 0
			duel.round_number = random.randi_range(2, 10)
			duel.phase = ELDuel.Phase.FINISHED
			if not run.resolve_battle(duel):
				_fail("Resolve battle for seed %d: %s" % [seed_value, run.error])
				return
		else:
			var options := run.choices().filter(func(option: Dictionary) -> bool: return not bool(option.get("disabled", false)))
			if options.is_empty() or not run.choose(options[random.randi_range(0, options.size() - 1)].id):
				_fail("Choose action for seed %d in %s: %s" % [seed_value, run.phase, run.error])
				return
		var raw := run.snapshot()
		var restored := ELExpeditionRun.new()
		if not restored.restore_snapshot(source, JSON.parse_string(JSON.stringify(raw))):
			_fail("Restore seed %d in %s: %s" % [seed_value, run.phase, restored.error])
			return
		if raw != restored.snapshot():
			_fail("Checkpoint differs after restoring seed %d in %s" % [seed_value, run.phase])
			return
		run = restored
		transitions += 1
	if not run.finished():
		_fail("Seed %d did not finish within %d actions; phase %s" % [seed_value, STEP_LIMIT, run.phase])
		return
	completed += 1
