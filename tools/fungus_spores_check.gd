extends SceneTree
## Headless checks of a fingus's spores, in each game whose files are set up:
## - #260: the Fingus Immortality specialisation (GFNR) rolls three times
##   after the spit; only three successes out of three save the fingus, and
##   only then does the specialisation announce that it worked. One or two
##   successes leave the fingus to die without a word;
## - #261: a fingus that spits falls at its action's impact frame, as the
##   spit leaves it (not once the whole action clip has played), the spit
##   starts at that frame, and its target is hit at the spit's own hit cue.
##
##   godot --headless --path game --script ../tools/fungus_spores_check.gd
##
## Needs the original games' files (user://profiles.json); without them a
## game is skipped. Settings are never written.

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, String(paths[edition])):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		_immortality(profile)
		await _spit_timing(edition)
	print("FUNGUS SPORES: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## Successes of `trials` specialisation trials from `seed` at `chance`, by
## the duel's own sequence (no luck or suppression).
func _successes(seed: int, chance: float, trials: int) -> int:
	var state := seed
	var hits := 0
	for i in trials:
		state = (state * 0x343fd + 0x269ec3) & 0xffffffff
		if float((state >> 16) & 0x7fff) / 32767.0 < chance: hits += 1
	return hits

func _immortality(profile: ELProfile) -> void:
	var game := profile.id
	if not profile.table("HeroesSpecs").has("GFNR"):
		check(false, "%s: the Fingus Immortality specialisation is in the game" % game)
		return
	# A level whose odds leave every count of successes likely enough.
	var level := 20
	for l in range(1, 21):
		var p := ELSpecs.chance(profile, "GFNR", l)
		if p >= 0.4 and p <= 0.8:
			level = l
			break
	var chance := ELSpecs.chance(profile, "GFNR", level)
	var seen := {}
	for seed in range(1, 20000):
		var hits := _successes(seed, chance, 3)
		if seen.has(hits): continue
		seen[hits] = true
		var duel := Fixtures.build(profile, {"rng": seed,
			"heroes": [{"health": 20, "mana": 0, "spec": "GFNR", "spec_level": level, "luck": 0, "suppression": 0},
				{"health": 20, "mana": 0, "spec": "NONE", "luck": 0, "suppression": 0}],
			"creatures": [{"card": "SPFG", "owner": 0}, {"card": "STRT", "owner": 1, "toughness": 5}]})
		if duel == null:
			check(false, "%s: the spores position restores" % game)
			return
		duel.rng_state = seed
		var start := duel.history.size()
		var used := duel.use_ability(2, "spores", 3)
		var told := 0
		var regenerated := false
		for entry: Dictionary in duel.history.slice(start):
			if entry.kind == "spec" and String(entry.spec) == "GFNR": told += 1
			if entry.kind == "regenerate" and int(entry.target) == 2: regenerated = true
		var what := "%s: Fingus Immortality with %d success(es) of 3" % [game, hits]
		check(used and int(duel.creatures.get(3, {}).get("damage", 0)) == 1, what + ": the spit still hurts its target")
		if hits == 3:
			check(duel.creatures.has(2) and regenerated and told == 1, what + ": the fingus lives and the specialisation is announced once")
		else:
			check(not duel.creatures.has(2) and not regenerated and told == 0, what + ": the fingus dies and nothing says the specialisation worked")
		if seen.size() == 4: break
	check(seen.size() == 4, "%s: every count of successes was tried (%s)" % [game, str(seen.keys())])

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 600:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return

func _summon(view: Node, side: int, card: String) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if not before.has(id): return id
	return -1

func _spit_timing(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return
	view.settings.values.hide_cast = false
	view._start(edition)
	await _idle(view)
	var duel: ELDuel = view.duel
	var side := duel.active_side()
	duel.heroes[side].spec = "NONE"
	var fingus := await _summon(view, side, "SPFG")
	var target := await _summon(view, 1 - side, "STRT")
	if fingus < 2 or target < 2 or not view.models.has(fingus) or not view.models.has(target):
		check(false, "%s: a fingus and its target stand" % edition)
		view.queue_free()
		await process_frame
		return
	duel.creatures[target].toughness = 9
	await _idle(view)
	var model: ELModel = view.models[fingus]
	var timing: Dictionary = model.timing.get("uinstant", {})
	var impact := int(timing.get("impact", -1))
	var frames := int(timing.get("frames", 0))
	check(impact > 0 and impact < frames, "%s: the fingus's action marks an impact frame (%d of %d)" % [edition, impact, frames])
	var key := float(impact) / 30.0
	var spit_hit := ELCombatEffects.ability_hit_delay(view.profile, "SPFG")
	check(spit_hit > 0.0, "%s: the spit has its own hit cue (%.2f s)" % [edition, spit_hit])
	var wound := int(view.shown_damage(target))
	view.effects.requested.clear()
	var begin := Time.get_ticks_usec()
	if not duel.use_ability(fingus, "spores", target):
		check(false, "%s: the fingus spits (%s)" % [edition, duel.error])
		view.queue_free()
		await process_frame
		return
	check(not duel.creatures.has(fingus), "%s: the rules let the fingus die at once" % edition)
	var died_at := -1.0
	var spat_at := -1.0
	var hit_at := -1.0
	for i in 3000:
		view.ai_clock = -1000.0
		await process_frame
		var seconds := (Time.get_ticks_usec() - begin) / 1000000.0
		if spat_at < 0.0 and view.effects.requested.has("FingusSpit"): spat_at = seconds
		if died_at < 0.0 and (not is_instance_valid(model) or bool(model.get_meta("dying", false)) or model.clip == "udeath"): died_at = seconds
		if hit_at < 0.0 and int(view.shown_damage(target)) != wound: hit_at = seconds
		if seconds > key + spit_hit + 1.0 or (died_at >= 0.0 and spat_at >= 0.0 and hit_at >= 0.0 and seconds > float(frames) / 30.0 + 0.2): break
	# One frame's slack either way: the cue timers fire between frames.
	check(died_at >= key - 0.05 and died_at <= key + 0.2,
		"%s: the fingus falls at its action's impact (%.2f s), not after the whole action (%.2f s): fell at %.3f s" % [edition, key, float(frames) / 30.0, died_at])
	check(spat_at >= key - 0.05 and spat_at <= key + 0.2, "%s: the spit leaves at the action's impact (%.2f s): left at %.3f s" % [edition, key, spat_at])
	check(hit_at >= key + spit_hit - 0.05 and hit_at <= key + spit_hit + 0.3,
		"%s: the target is hit at the spit's cue (%.2f s): hit at %.3f s" % [edition, key + spit_hit, hit_at])
	view.queue_free()
	await process_frame
	await process_frame
