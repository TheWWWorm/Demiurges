extends SceneTree
## Headless check of the battle adviser (ELCombatAdvisor) and of what it
## reads, in both games:
## - choosing blockers is judged as one decision with the end of the phase,
##   from the position before the first choice: a hero on 5 health with one
##   1/1 blocker, attacked by a 5/5 and a 1/1, that blocks the 1/1 and ends
##   the phase is told it blundered (it used to be read from the position
##   after the choice, where only the end of the phase was left: BEST, no
##   loss); blocking the 5/5 is the best move; a spell cast with a blocker
##   already chosen is judged as that cast, from the position before the
##   choice;
## - the duel keeps each command the rules took whole (ELDuel.accepted:
##   every argument and the position it came from), and the adviser looks a
##   move up by all of its arguments: a reanimation of the weaker of two
##   graveyard creatures is not taken for the stronger one; entries that
##   disagree are no match;
## - specialisations in the adviser's lookahead (ELDuel.fair_specs) keep each
##   trial's probability, luck and suppression counted; the second game's own
##   expectation (the computer opponent's think) and the real rolls are as
##   they were;
## - auto combat taken up halfway takes the side's choices back
##   (ELPracticeAI.release_assignments), leaving attackers that had to attack
##   or paid a tax.
##
##   godot --headless --path game --script ../tools/advisor_check.gd -- [--game=el1|el2]
##
## Needs the original games' files (user://profiles.json); without them a
## game is skipped. Exits 1 on any failure.

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _run() -> void:
	await process_frame
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var wanted := _arg("game", "both")
	var ran := 0
	for edition: String in ["el1", "el2"]:
		if wanted != "both" and wanted != edition: continue
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])):
			print("SKIP: %s files do not mount" % edition)
			continue
		ran += 1
		_specs(profile)
		_release(profile)
		_record(profile)
		_assignment(profile)
		_grave_choice(profile)
	if ran == 0: failures.append("no game was checked")
	print("%d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)

# --- helpers -----------------------------------------------------------------

func _plain(power: int, toughness: int, owner: int) -> Dictionary:
	return {"card": "GROG", "owner": owner, "power": power, "toughness": toughness, "flags": []}

## Waits for the adviser's verdict on the last move.
func _verdict(advisor: ELCombatAdvisor) -> Dictionary:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 180000:
		advisor.tick()
		if not advisor.pending and not advisor.last.is_empty(): return advisor.last
		OS.delay_msec(20)
	return {}

func _grade(last: Dictionary) -> String:
	if last.is_empty(): return "none"
	return "%s, loss %.1f" % [ELCombatAdvisor.Grade.keys()[int(last.grade)], float(last.loss)]

# --- 1: assignments are one decision -----------------------------------------

func _block_fixture(profile: ELProfile, mana := 0, hand: Array = []) -> ELDuel:
	return Fixtures.build(profile, {"attacker": 1, "phase": "defence", "attacks": [3, 4],
		"heroes": [{"health": 5, "maximum": 20, "mana": mana, "hand": hand}, {"health": 20, "mana": 0}],
		"creatures": [_plain(1, 1, 0), _plain(5, 5, 1), _plain(1, 1, 1)]})

func _assignment(profile: ELProfile) -> void:
	var game := profile.id
	for blocked: int in [4, 3]:
		var duel := _block_fixture(profile)
		if duel == null:
			check(false, "%s: the blocking position restores" % game)
			return
		var advisor := ELCombatAdvisor.new()
		advisor.observe(duel, true, 0)
		var assigned := duel.assign_block(2, blocked)
		advisor.observe(duel, true, 0)
		var ended := duel.end_phase()
		advisor.observe(duel, duel.phase != ELDuel.Phase.FINISHED and duel.active_side() == 0, 0)
		var last := _verdict(advisor)
		advisor.finish()
		if not assigned or not ended:
			check(false, "%s: the blocks are taken (%s)" % [game, duel.error])
			continue
		if blocked == 4:
			check(not last.is_empty() and int(last.grade) == ELCombatAdvisor.Grade.BLUNDER and float(last.loss) > 14.0,
				"%s: blocking the 1/1 and dying to the 5/5 is a blunder from the position before the choice (%s)" % [game, _grade(last)])
			check(not last.is_empty() and String(last.move.get("kind", "")) == "block" and String(last.best.get("kind", "")) == "block",
				"%s: the verdict names the block and prefers a block (%s / %s)" % [game, str(last.get("move", {})), str(last.get("best", {}))])
		else:
			check(not last.is_empty() and float(last.loss) <= ELCombatAdvisor.LOSS[0] and int(last.grade) == ELCombatAdvisor.Grade.BEST,
				"%s: blocking the 5/5 is the best move (%s)" % [game, _grade(last)])
	# A spell with a blocker already chosen: the cast, judged from before the choice.
	var spell := ""
	for card: String in ELDuel.DEFENCE_SPELLS.get(game, []):
		if profile.table("CombatSpells").has(card) and not ELCatalog.rule(profile, card).is_empty() and ELCatalog.rule(profile, card).get("target", "") == "none":
			spell = card
			break
	if spell.is_empty():
		check(false, "%s: a defence spell without a target to cast" % game)
		return
	var duel := _block_fixture(profile, 30, [spell])
	var advisor := ELCombatAdvisor.new()
	advisor.observe(duel, true, 0)
	duel.assign_block(2, 4)
	advisor.observe(duel, true, 0)
	var cast := duel.cast(0)
	advisor.observe(duel, duel.phase != ELDuel.Phase.FINISHED and duel.active_side() == 0, 0)
	var last := _verdict(advisor)
	advisor.finish()
	check(cast and not last.is_empty() and String(last.move.get("kind", "")) == "cast" and String(last.move.get("card", "")) == spell,
		"%s: %s cast with a blocker chosen is judged as the cast (%s, %s)" % [game, spell, _grade(last), str(last.get("move", {}))])

# --- 2: the command's whole identity ------------------------------------------

func _record(profile: ELProfile) -> void:
	var game := profile.id
	var duel := _block_fixture(profile)
	var before := ELCombatSearch._position(duel)
	duel.assign_block(2, 3)
	var entry: Dictionary = duel.accepted.back() if not duel.accepted.is_empty() else {}
	check(entry.get("kind") == "block" and int(entry.get("id", -1)) == 2 and int(entry.get("target", -1)) == 3 and int(entry.get("side", -1)) == 0 and int(entry.get("before", 0)) == before,
		"%s: a block is kept whole with the position it came from (%s)" % [game, str(entry)])
	var copy := duel.search_copy()
	copy.assign_block(2, 4)
	check(duel.accepted.size() == 1 and copy.accepted.is_empty(), "%s: lookahead copies keep no commands" % game)
	check(not duel.assign_block(2, 2) and duel.accepted.size() == 1, "%s: a refused command is not kept" % game)
	# Entries the lookahead gave for a command are matched on every argument.
	var position := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 30, "hand": ["GROG", "GROG"]}, {"health": 20, "mana": 0}]})
	var result := {"moves": [
		{"command": {"kind": "cast", "index": 0, "card": "GROG", "target": 1, "grave": 0, "power": 0}, "value": 20.0},
		{"command": {"kind": "cast", "index": 0, "card": "GROG", "target": 1, "grave": 1, "power": 0}, "value": -20.0},
		{"command": {"kind": "ability", "id": 2, "key": "x", "target": 1, "choice": 5, "amount": 3}, "value": 4.0},
		{"command": {"kind": "ability", "id": 2, "key": "x", "target": 1, "choice": 5, "amount": 2}, "value": 1.0},
		{"command": {"kind": "end_phase"}, "value": 0.0}, {"command": {"kind": "end_phase"}, "value": 2.0}]}
	var weak := ELCombatAdvisor._exact(position, 0, result, {"kind": "cast", "index": 0, "card": "GROG", "target": 1, "grave": 1, "power": 0})
	check(float(weak.get("value", 99.0)) == -20.0, "%s: a graveyard choice is matched exactly, not by the best variant (%s)" % [game, str(weak)])
	var paid := ELCombatAdvisor._exact(position, 0, result, {"kind": "ability", "id": 2, "key": "x", "target": 1, "choice": 5, "amount": 2})
	check(float(paid.get("value", 99.0)) == 1.0, "%s: an ability's amount is matched exactly (%s)" % [game, str(paid)])
	check(ELCombatAdvisor._exact(position, 0, result, {"kind": "cast", "index": 1, "card": "GROG", "target": 1, "grave": 0, "power": 0}).is_empty(), "%s: another hand place is no match" % game)
	check(ELCombatAdvisor._exact(position, 0, result, {"kind": "end_phase"}).is_empty(), "%s: entries that disagree are no match" % game)

## A reanimation of the weaker of two graveyard creatures, judged against the
## stronger one.
func _grave_choice(profile: ELProfile) -> void:
	var game := profile.id
	var spell := ""
	for card: String in profile.table("CombatSpells"):
		var rule := ELCatalog.rule(profile, card)
		if rule.get("effect", "") == "reanimate" and rule.get("target", "") == "grave" and not rule.get("enchantment", false) and profile.table("CombatSpells")[card].get("UseIn", "Both") != "Defence":
			spell = card
			break
	if spell.is_empty():
		print("SKIP: %s has no plain reanimation" % game)
		return
	var strong := ""
	var weak := ""
	var creatures: Dictionary = profile.table("CombatCreatures")
	for card: String in creatures:
		if ELCatalog.rule(profile, card).get("effect", "") != "summon": continue
		var size := int(creatures[card].Power) + int(creatures[card].Toughness)
		if strong.is_empty() or size > int(creatures[strong].Power) + int(creatures[strong].Toughness): strong = card
		if size > 0 and (weak.is_empty() or size < int(creatures[weak].Power) + int(creatures[weak].Toughness)): weak = card
	var duel := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 60, "channels": 20, "hand": [spell], "grave": [strong, weak]}, {"health": 20, "mana": 0}]})
	if duel == null or duel.heroes[0].grave.size() != 2:
		print("SKIP: %s: the graveyard position does not restore" % game)
		return
	# The command that brings the weak creature back.
	var chosen := {}
	for target: int in duel.valid_targets(spell):
		for grave: int in duel.valid_grave_targets(spell, target):
			var trial := duel.search_copy()
			if not trial.cast(0, target, grave): continue
			for c: Dictionary in trial.creatures.values():
				if c.card == weak: chosen = {"target": target, "grave": grave}
	if chosen.is_empty():
		print("SKIP: %s: %s cannot bring back %s here" % [game, spell, weak])
		return
	var advisor := ELCombatAdvisor.new()
	advisor.observe(duel, true, 0)
	var cast := duel.cast(0, int(chosen.target), int(chosen.grave))
	var entry: Dictionary = duel.accepted.back() if not duel.accepted.is_empty() else {}
	check(cast and int(entry.get("grave", -9)) == int(chosen.grave) and int(entry.get("target", -9)) == int(chosen.target) and String(entry.get("card", "")) == spell,
		"%s: the cast is kept with its graveyard choice (%s)" % [game, str(entry)])
	advisor.observe(duel, duel.phase != ELDuel.Phase.FINISHED and duel.active_side() == 0, 0)
	var last := _verdict(advisor)
	advisor.finish()
	check(not last.is_empty() and int(last.grade) != ELCombatAdvisor.Grade.BEST and float(last.loss) > 0.0,
		"%s: bringing back %s instead of %s is not the best move (%s)" % [game, weak, strong, _grade(last)])

# --- 3: specialisations in expected mode --------------------------------------

func _specs(profile: ELProfile) -> void:
	var game := profile.id
	var d := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}]})
	for p: float in [0.3, 0.6, 0.8, 0.89, 0.9]:
		d.spec_credit = {}
		var hits := 0
		for i in 1000: hits += ELSpecs._fair(d, 0, "TEST", 1, p)
		check(absi(hits - roundi(p * 1000.0)) <= 1, "%s: a %d%% trial succeeds %d times in 1000 in the adviser's lookahead" % [game, roundi(p * 100.0), hits])
		d.spec_credit = {}
		var many := 0
		for i in 100: many += ELSpecs._fair(d, 0, "TEST", 3, p)
		check(absi(many - roundi(p * 300.0)) <= 1, "%s: %d%% over three trials a time counts %d in 300" % [game, roundi(p * 100.0), many])
	check(is_equal_approx(ELSpecs.trial_chance(0.3, 2), 1.0 - pow(0.7, 3)) and is_equal_approx(ELSpecs.trial_chance(0.3, -2), pow(0.3, 3)) and is_equal_approx(ELSpecs.trial_chance(0.3, 0), 0.3),
		"%s: luck takes the best of 1 + k draws, suppression the worst" % game)
	# A real specialisation on a hero: the adviser's lookahead, the computer
	# opponent's think and the real roll.
	var code := ""
	var level := 1
	for candidate: String in profile.table("HeroesSpecs"):
		for l in range(1, 21):
			var c := ELSpecs.chance(profile, candidate, l)
			if c > 0.25 and c < 0.85:
				code = candidate
				level = l
				break
		if not code.is_empty(): break
	if code.is_empty():
		check(false, "%s: a specialisation of middling chance" % game)
		return
	var p := ELSpecs.chance(profile, code, level)
	var hero := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 0, "spec": code, "spec_level": level, "luck": 1}, {"health": 20, "mana": 0, "suppression": 0}]})
	var fair := hero.search_copy(true)
	fair.fair_specs = true
	var fair_hits := 0
	for i in 200: fair_hits += ELSpecs.roll(fair, 0, code)
	var want := ELSpecs.trial_chance(p, 1)
	check(absi(fair_hits - roundi(want * 200.0)) <= 1 and fair.rng_state == hero.rng_state,
		"%s: %s at %d%% with luck counts %d of 200 in the adviser's lookahead (%.0f expected), drawing nothing" % [game, code, roundi(p * 100.0), fair_hits, want * 200.0])
	check(is_equal_approx(ELSpecs.expected(hero, 0, code), want), "%s: ELSpecs.expected counts luck" % game)
	var nested := fair.search_copy()
	check(nested.fair_specs and nested.spec_credit == fair.spec_credit, "%s: a copy of a fair copy stays fair" % game)
	var think := hero.search_copy(true)
	var percent := int(p * 100.0)
	check(ELSpecs.roll(think, 0, code) == (percent + 10) / 100 and ELSpecs.roll(think, 0, code, 5) == (percent * 5 + 10) / 100,
		"%s: the computer opponent's own expectation is as it was" % game)
	var real := hero.search_copy()
	var reference := hero.search_copy()
	var same := true
	for i in 50:
		var hits := ELSpecs.roll(real, 0, code, 2)
		var expected := 0
		for trial in 2:
			var r := _draw(reference)
			r = minf(r, _draw(reference))
			if r < p: expected += 1
		if hits != expected: same = false
	check(same and real.rng_state == reference.rng_state, "%s: the real roll draws as it did" % game)

func _draw(d: ELDuel) -> float:
	d.rng_state = (d.rng_state * 0x343fd + 0x269ec3) & 0xffffffff
	return float((d.rng_state >> 16) & 0x7fff) / 32767.0

# --- 5: auto combat taken up halfway -------------------------------------------

func _release(profile: ELProfile) -> void:
	var game := profile.id
	var duel := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [_plain(2, 2, 0), _plain(3, 3, 0), {"card": "GROG", "owner": 0, "power": 2, "toughness": 2, "flags": ["Berserk"]}]})
	for id: int in [2, 3, 4]: duel.toggle_attack(id)
	var sent := duel.attacks.size()
	var released := ELPracticeAI.release_assignments(duel)
	check(sent == 3 and released == 2 and Array(duel.attacks) == [4], "%s: auto combat takes back the attackers that may be recalled (%d sent, %d back, %s left)" % [game, sent, released, str(duel.attacks)])
	var blocking := _block_fixture(profile)
	blocking.assign_block(2, 3)
	var freed := ELPracticeAI.release_assignments(blocking)
	check(freed == 1 and blocking.blocks.is_empty(), "%s: auto combat takes back the blockers chosen" % game)
	# The adviser stops judging once the computer has the phase.
	var advisor := ELCombatAdvisor.new()
	var again := _block_fixture(profile)
	advisor.observe(again, true, 0)
	again.assign_block(2, 4)
	advisor.observe(again, true, 0)
	ELPracticeAI.release_assignments(again)
	advisor.observe(again, false, 0)
	again.assign_block(2, 3)
	again.end_phase()
	advisor.observe(again, false, 0)
	var start := Time.get_ticks_msec()
	while advisor.pending and Time.get_ticks_msec() - start < 60000:
		advisor.tick()
		OS.delay_msec(20)
	advisor.tick()
	advisor.finish()
	check(advisor.last.is_empty(), "%s: a phase finished by auto combat is not judged as the player's" % game)
