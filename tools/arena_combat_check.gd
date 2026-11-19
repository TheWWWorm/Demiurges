extends SceneTree
## Plays real drafted spellbooks through the ordinary combat rules and AI.
## This is a functional smoke test, not a drafting-strength benchmark.
## The offline fixture has catalog card data and synthetic hero/income rows.
## Use --el2=/installed/game with the game project to test original tables.
##
## godot --headless --path game --script ../tools/arena_combat_check.gd -- \
##   --fixture=<arena-lab>/fixture.json --games=4 --think-ms=200

const DraftCheck := preload("arena_draft_check.gd")
var failures := 0
var checks := 0

func _arg(name: String, fallback := "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="): return value.substr(name.length() + 3)
	return fallback

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: ELProfile
	var installation := _arg("el2")
	if installation.is_empty(): source = DraftCheck.synthetic_profile(_arg("fixture"))
	else:
		source = ELProfile.new()
		if not source.mount("el2", installation):
			check(false, "Mount Etherlords II: " + source.error)
			quit(1)
			return
	if source == null:
		check(false, "The test profile is available")
		quit(1)
		return
	print("INPUT: ", "installed Etherlords II" if not installation.is_empty() else "catalog/synthetic fixture; no original hero/income or rendering validation")
	# Shorter decisions keep this smoke test practical. Production budgets and
	# policies are untouched; a separate benchmark is needed to rank drafters.
	ELCombatSearch.smart_engine_ms = clampi(int(_arg("think-ms", "200")), 50, 5000)
	ELCombatSearch.smart_engine_budget = 200000
	var native_available := ELCombatBrain.available
	print("NATIVE AVAILABLE: ", native_available)
	var rules := ELArenaRules.FACTION_RULES if _arg("pool") == "faction" else ELArenaRules.OPEN_RULES
	for i in clampi(int(_arg("games", "4")), 1, 32):
		_play(source, i, native_available, rules)
	ELPracticeAI.finish()
	print("ARENA COMBAT: %d checks, %d failure(s)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _play(source: ELProfile, index: int, native_available: bool, rules: int) -> void:
	var magic: String = ELArenaRules.FACTIONS[index % ELArenaRules.FACTIONS.size()]
	var run := ELArenaRun.new()
	run.auto_save = false
	var seed := 51971 + index * 101
	var created := run.create(source, seed, rules)
	while created and not run.hero_choices.has(magic):
		seed += 1
		created = run.create(source, seed, rules)
	check(created and run.choose_hero(magic), "%s: a legal hero is selected" % magic)
	if not created or run.phase != "draft": return
	while run.phase == "draft":
		if not run.pick(ELArenaDraftBot.choose(run.draft)):
			check(false, "%s: the player draft completes: %s" % [magic, run.error])
			return
	var duel := run.build_battle()
	check(duel != null, "%s: both drafted decks start a real battle" % magic)
	if duel == null: return
	check(ELCombatSearch.info_policy(duel) == "full", "%s: Arena uses full-information combat search" % magic)
	duel.smart_sides.assign([0, 1])
	var commands := 0
	var in_phase := 0
	var mark := [-1, -1, -1]
	var native_searches := 0
	var refused_before := ELPracticeAI.refused
	var empty_before := ELPracticeAI.empty
	var casts := 0
	var started := Time.get_ticks_msec()
	var restored := false
	var capped := false
	while duel.phase != ELDuel.Phase.FINISHED and duel.round_number <= 50 and Time.get_ticks_msec() - started < 180000:
		var here := [duel.round_number, duel.attacker, duel.phase]
		if here != mark:
			mark = here
			in_phase = 0
		in_phase += 1
		if in_phase > 100:
			capped = true
			break
		ELPracticeAI.step(duel)
		var command: Dictionary = ELPracticeAI.last_decision.get("command", {})
		if ELPracticeAI.last_decision.get("engine") in ["native", "proof", "beyond"]: native_searches += 1
		if command.get("kind") == "cast": casts += 1
		commands += 1
		if not restored and commands >= 12 and duel.phase != ELDuel.Phase.FINISHED:
			var checkpoint := duel.snapshot()
			var saved := run.save_battle(duel)
			var resumed := run.build_battle() if saved else null
			check(resumed != null and resumed.snapshot() == checkpoint, "%s: a played mid-battle checkpoint resumes exactly" % magic)
			if resumed == null: return
			duel = resumed
			duel.smart_sides.assign([0, 1])
			restored = true
	check(not capped and duel.phase == ELDuel.Phase.FINISHED, "%s: drafted decks finish a battle within the smoke-test limits" % magic)
	check(ELPracticeAI.refused == refused_before and ELPracticeAI.empty == empty_before, "%s: AI sends legal nonempty commands" % magic)
	check(not native_available or native_searches > 0, "%s: available native combat search is exercised" % magic)
	if duel.phase == ELDuel.Phase.FINISHED:
		check(run.resolve_battle(duel) and run.matches.size() == 1, "%s: a played result records once" % magic)
	print("COMBAT %s seed=%d rounds=%d commands=%d casts=%d winner=%d native_searches=%d elapsed_ms=%d" % [magic, seed, duel.round_number, commands, casts, duel.winner, native_searches, Time.get_ticks_msec() - started])
