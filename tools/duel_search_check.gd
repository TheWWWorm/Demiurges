extends SceneTree
## Headless check of how the computer opponent's decision is driven: what the
## compiled engine is asked and told back (ELCombatBrain), and what is done
## with its answer before a command is given (ELCombatSearch):
##
## - every reading of the engine's own is told its own settings and the
##   decision's deadline (the request is checked as it is serialized);
## - a choice that drops part of the hero's own hand from the model is not
##   played: the search over the duel's own rules decides instead;
## - a win the engine's usual reading foresees is held to a reading of every
##   reply, and a defence it ranked low is not cut from that reading;
## - the original's reckoning of spells only orders commands: it never puts
##   a losing command in place of the engine's;
## - results say what they are (proven, no forced win, judged, unknown, past
##   the model), and the chance to win of the two heroes comes to one;
## - what is remembered between thinks is kept by the whole duel;
## - the search over the duel's own rules can move a block already set.
##
##   godot --headless --path game --script ../tools/duel_search_check.gd [-- --only=<text>]
##
## Needs the original games' files (user://profiles.json or --el1=/--el2=).

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures: Array[String] = []
var profiles := {}
var only := ""

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _wanted(name: String) -> bool:
	return only.is_empty() or name.contains(only)

func _profile(game: String) -> ELProfile:
	if profiles.has(game): return profiles[game]
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(game, ""))
	var profile := ELProfile.new()
	profiles[game] = profile if not folder.is_empty() and profile.mount(game, folder) else null
	if profiles[game] == null: print("SKIP: no files of %s" % game)
	return profiles[game]

func _initialize() -> void:
	only = _arg("only", "")
	if not ELCombatBrain.available:
		print("SKIP: the compiled engine is not built for this platform")
		quit(0)
		return
	ELPuzzles.remember = false
	if _wanted("chance"): _chance()
	if _wanted("request"): _request()
	if _wanted("crowded"): _crowded()
	if _wanted("pruned"): _pruned()
	if _wanted("comet"): _comet()
	if _wanted("place"): _place()
	if _wanted("reblock"): _reblock()
	if _wanted("information"): _information()
	print("%d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _play_side(duel: ELDuel, side: int) -> void:
	var smart: Array[int] = [side]
	duel.smart_sides = smart

## The chances of the two heroes in one position come to one.
func _chance() -> void:
	for edition: String in ["el1", "el2"]:
		var even := ELCombatSearch.worth_chance(edition, 0.0)
		check(absf(even - 0.5) < 1e-9, "chance: %s level heroes each have an even chance (%.4f)" % [edition, even])
		var worst := 0.0
		for worth: float in [-40.0, -12.5, -1.0, 3.0, 26.0, 60.0]:
			worst = maxf(worst, absf(ELCombatSearch.worth_chance(edition, worth) + ELCombatSearch.worth_chance(edition, -worth) - 1.0))
		check(worst < 1e-9, "chance: %s the chances of the two sides come to one (off by %.6f)" % [edition, worst])
		check(ELCombatSearch.worth_chance(edition, 26.0) > ELCombatSearch.worth_chance(edition, 10.0), "chance: %s more ahead is more likely to win" % edition)

## The serialized request of the readings other than the choice.
func _request() -> void:
	var el1 := _profile("el1")
	if el1 == null: return
	var duel := Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 3}, {"health": 20, "mana": 3}],
		"creatures": [{"card": "GROG", "owner": 0}, {"card": "KBWR", "owner": 1}]})
	check(duel != null, "request: fixture restores")
	if duel == null: return
	var ctx := Fixtures.context(el1, 0)
	ctx.deadline_usec = Time.get_ticks_usec() + 5000000
	var items := ELCombatBrain.weigh(ctx, duel, 4, 20000, 7, 9)
	var told := ELCombatBrain.last_packed.to_int32_array()
	check(told[3] == 7 and told[4] == 4, "request: every first command weighed (mode 7) with the phases asked (%d)" % told[4])
	check(told[16] == 7, "request: weighing is told its commands a line (%d, asked 7)" % told[16])
	check(told[10] == 9, "request: weighing is told its width (%d, asked 9)" % told[10])
	check(told[28] > 0 and told[28] <= 5000, "request: weighing keeps to the decision's deadline (%d ms)" % told[28])
	check(told[20] == ELCombatSearch.smart_engine_leaf, "request: weighing scores a line's end as the choice does")
	check(not items.is_empty() and items.all(func(item: Dictionary) -> bool: return item.has("complete")), "request: every weighed command says whether its reading was whole (%d)" % items.size())
	ELCombatBrain.gamble(ctx, duel, 5, 2000)
	told = ELCombatBrain.last_packed.to_int32_array()
	check(told[3] == 8 and told[16] == 5, "request: played-out duels (mode 8) are told their rounds (%d, asked 5)" % told[16])
	check(told[10] == ELCombatSearch.smart_engine_width, "request: played-out duels are told the width (%d)" % told[10])
	check(told[28] > 0, "request: played-out duels keep to the deadline (%d ms)" % told[28])
	ELCombatBrain.prove(ctx, duel, 1, 2000)
	told = ELCombatBrain.last_packed.to_int32_array()
	check(told[3] == 9 and told[28] > 0 and told[28] <= 5000, "request: a proof within a decision keeps to its deadline (%d ms)" % told[28])
	# The weighing of the chosen command agrees with the choice's own worth
	# when both read the same: a decided line.
	var won := Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 0}, {"health": 3, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 3, "toughness": 3}, {"card": "GROG", "owner": 0, "power": 3, "toughness": 3}]})
	if won != null:
		var plain := Fixtures.context(el1, 0)
		var weighed := ELCombatBrain.weigh(plain, won, 4, 200000, 16)
		var best := -1e18
		for item: Dictionary in weighed: best = maxf(best, float(item.value))
		check(best >= 1e5, "request: weighing sees the win on the board (best %.1f)" % best)

## A hand of one card more than the model holds: that last card wins.
func _crowded() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		if not profile.table("CombatSpells").has("COMT"): continue
		var hand: Array = []
		for i in ELCombatBrain.HAND: hand.append("MGHT")
		hand.append("COMT")
		var duel := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 9, "hand": hand}, {"health": 5, "mana": 0}],
			"creatures": [{"card": "GROG", "owner": 1, "resting": true}]})
		check(duel != null, "crowded: %s fixture restores" % edition)
		if duel == null: continue
		ELCombatSearch.reset_caches()
		var choice := ELCombatBrain.choose(Fixtures.context(profile, 0), duel, 4, 200000, 16, 16)
		check(String(choice.get("status", "")) == "unsupported" and Array(choice.get("crowding", [])).has("hand0"),
			"crowded: %s a choice on a model short of the hand says so (%s %s)" % [edition, choice.get("status", "-"), str(choice.get("crowding", []))])
		var proof := ELCombatBrain.prove(Fixtures.context(profile, 0), duel, 1, 200000)
		check(String(proof.get("status", "")) == "unsupported" and int(proof.get("turns", 0)) == 0, "crowded: %s no proof stands on it (%s)" % [edition, proof.get("status", "-")])
		_play_side(duel, 0)
		var stats := {}
		var command := ELCombatSearch.think(duel, stats)
		check(String(command.get("kind", "")) == "cast" and String(command.get("card", "")) == "COMT" and int(command.get("target", 0)) == 1,
			"crowded: %s the last card's Comet is cast at the hero (%s, by %s)" % [edition, str(command), stats.get("engine", "-")])
		check(String(stats.get("unsupported", "")) == "hand0", "crowded: %s the decision tells what the model left out" % edition)
		break

## Ten unblockable attackers deal 14 to a hero at 14 with a heal for 2, and
## twenty shots that change nothing rank above the heal.
func _pruned() -> void:
	var el1 := _profile("el1")
	if el1 == null: return
	var creatures: Array = []
	for i in 10: creatures.append({"card": "KBWR", "owner": 0, "power": 2 if i < 4 else 1, "toughness": 9, "flags": ["UB"]})
	for i in 2: creatures.append({"card": "AVMK", "owner": 1})
	var duel := Fixtures.build(el1, {"heroes": [{"health": 30, "mana": 0}, {"health": 14, "mana": 2, "enchantments": ["LSHE"]}], "creatures": creatures})
	check(duel != null, "pruned: fixture restores")
	if duel == null: return
	var saved := ELCombatSearch.smart_engine_prove
	ELCombatSearch.smart_engine_prove = 0
	var choice := ELCombatBrain.choose(Fixtures.context(el1, 0), duel, 2, 400000, 16, 16)
	ELCombatSearch.smart_engine_prove = saved
	var said := "value=%.1f status=%s proven=%d selective=%s" % [float(choice.get("value", 0.0)), choice.get("status", "-"), int(choice.get("proven", 0)), choice.get("selective_win", "-")]
	check(not choice.is_empty() and not (bool(choice.get("terminal", false)) and String(choice.get("status", "")) != "proven"),
		"pruned: the heal ranked below twenty shots is still read; no unproved win is claimed (%s)" % said)
	check(float(choice.get("value", 0.0)) < 1e5, "pruned: the attack is no win this turn (%s)" % said)
	# A win that is there is proved when the usual reading foresees it, even
	# with no proof asked first.
	var won := Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 0}, {"health": 3, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 3, "toughness": 3}, {"card": "GROG", "owner": 0, "power": 3, "toughness": 3},
			{"card": "KBWR", "owner": 1, "power": 1, "toughness": 1}]})
	if won != null:
		ELCombatSearch.smart_engine_prove = 0
		choice = ELCombatBrain.choose(Fixtures.context(el1, 0), won, 4, 400000, 16, 16)
		ELCombatSearch.smart_engine_prove = saved
		check(String(choice.get("status", "")) == "proven" and bool(choice.get("exact", false)) and int(choice.get("proven", 0)) == 1,
			"pruned: a foreseen win read again with every reply is a proof (%s proven=%d)" % [choice.get("status", "-"), int(choice.get("proven", 0))])
	# What every choice says of itself is one of the five.
	var plain := Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 3}, {"health": 20, "mana": 3}],
		"creatures": [{"card": "GROG", "owner": 0}, {"card": "KBWR", "owner": 1}]})
	if plain != null:
		choice = ELCombatBrain.choose(Fixtures.context(el1, 0), plain, 4, 400000, 16, 16)
		check(String(choice.get("status", "")) in ["no_forced_win", "heuristic", "unknown"], "pruned: an even position's choice is judged, not proven (%s)" % choice.get("status", "-"))

## The engine's Comet at the creature that would kill the hero: Comet X8
## through an Energy Barrier (-3) kills a ready 5/5; X8 at a hero at 30 does not.
func _comet() -> void:
	var el2 := _profile("el2")
	if el2 == null: return
	if not el2.table("CombatSpells").has("COMT"):
		print("SKIP: no Comet in el2")
		return
	var probe := Fixtures.build(el2, {"heroes": [{"health": 5, "mana": 0}, {"health": 30, "mana": 0}], "creatures": []})
	if probe == null: return
	var duel := Fixtures.build(el2, {"heroes": [{"health": 5, "mana": probe.cost("COMT") + 8, "hand": ["COMT"]}, {"health": 30, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 1, "power": 5, "toughness": 5, "enchantments": ["ENBR"]}]})
	check(duel != null, "comet: fixture restores")
	if duel == null: return
	ELCombatSearch.reset_caches()
	_play_side(duel, 0)
	var at_creature := {"kind": "cast", "index": 0, "card": "COMT", "target": 2, "grave": -1, "power": 8}
	var at_face := {"kind": "cast", "index": 0, "card": "COMT", "target": 1, "grave": -1, "power": 8}
	var ctx := Fixtures.context(el2, 0)
	ctx.budget = ELCombatSearch.engine_budget()
	check(ELCombatSearch._unlikely(ctx, duel, at_creature), "comet: the original's reckoning rules the creature out (prior 0)")
	check(not ELCombatSearch._holds(ctx, duel, at_face), "comet: Comet X8 at the hero fails the guard: the 5/5 kills the hero next turn")
	check(ELCombatSearch._holds(ctx, duel, at_creature), "comet: Comet X8 at the 5/5 passes the guard")
	var stats := {}
	var command := ELCombatSearch.think(duel, stats)
	check(String(command.get("kind", "")) == "cast" and int(command.get("target", -1)) == 2 and int(command.get("power", 0)) >= 8,
		"comet: Comet goes at the barriered 5/5 (%s by %s, unlikely %d, likely %d refused %d)" % [str(command), stats.get("engine", "-"),
			int(stats.get("unlikely", 0)), int(stats.get("likely", 0)), int(stats.get("likely_refused", 0))])
	# Played on: the hero lives through the other hero's turn.
	var copy := duel.search_copy()
	for step in 40:
		if copy.phase == ELDuel.Phase.FINISHED or (copy.attacker == 0 and copy.turn_serial > duel.turn_serial + 1): break
		_play_side(copy, copy.active_side())
		var next := ELCombatSearch.think(copy)
		if next.is_empty() or not ELCombatSearch.apply(copy, next): copy.end_phase()
	check(not (copy.phase == ELDuel.Phase.FINISHED and copy.winner == 1), "comet: the hero survives the 5/5's turn")

## What is remembered between thinks is kept by the whole duel.
func _place() -> void:
	var el1 := _profile("el1")
	if el1 == null: return
	var duel := Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 3}, {"health": 20, "mana": 3}], "creatures": [{"card": "GROG", "owner": 0}]})
	if duel == null: return
	var before := ELCombatSearch._place(duel)
	var other := duel.search_copy()
	other.setup = duel.setup.duplicate(true)
	other.setup["puzzle_goal"] = {"type": "survive", "side": 0}
	check(ELCombatSearch._place(other) != before, "place: another objective is another position")
	other = duel.search_copy()
	other.next_id += 1
	check(ELCombatSearch._place(other) != before, "place: another next creature number is another position")
	# A plan remembered for one opponent is not followed by another.
	ELCombatSearch.reset_caches()
	var after := duel.search_copy()
	var sent := {"kind": "attack", "id": int(duel.creatures.keys()[0])}
	ELCombatSearch._remember(duel, [sent, {"kind": "end_phase"}], 11)
	ELCombatSearch.apply(after, sent)
	check(not ELCombatSearch._recall(after, 11).is_empty() and ELCombatSearch._recall(after, 12).is_empty(), "place: a plan belongs to the opponent that chose it")
	# And to the hero that chose it: the steps of a line past the end of
	# that hero's phase are the other hero's, and no plan for it.
	ELCombatSearch.reset_caches()
	after = duel.search_copy()
	ELCombatSearch._remember(duel, [{"kind": "end_phase"}, {"kind": "end_phase"}], 11)
	ELCombatSearch.apply(after, {"kind": "end_phase"})
	check(after.active_side() == duel.active_side() or ELCombatSearch._recall(after, 11).is_empty(), "place: a plan is not carried into the other hero's commands")
	var ctx := Fixtures.context(el1, 0)
	var goal := duel.search_copy()
	goal.setup = duel.setup.duplicate(true)
	goal.setup["puzzle_goal"] = {"type": "clear", "side": 0}
	check(ELCombatSearch._proof_key(ctx, duel, {}) != ELCombatSearch._proof_key(ctx, goal, {}), "place: what a proof settled is kept by the objective too")
	ELCombatSearch.reset_caches()

## A blocker already set on a harmless attacker while a lethal one is open:
## the search over the duel's own rules moves it.
func _reblock() -> void:
	var el1 := _profile("el1")
	if el1 == null: return
	var duel := Fixtures.build(el1, {"attacker": 1, "phase": "defence", "attacks": [3, 4],
		"heroes": [{"health": 6, "mana": 0}, {"health": 20, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 2, "toughness": 9},
			{"card": "KBWR", "owner": 1, "power": 1, "toughness": 1}, {"card": "GROG", "owner": 1, "power": 7, "toughness": 3}]})
	check(duel != null, "reblock: fixture restores")
	if duel == null: return
	check(duel.assign_block(2, 3), "reblock: the bad block is set")
	var saved := ELCombatSearch.smart_engine
	ELCombatSearch.smart_engine = false
	ELCombatSearch.reset_caches()
	var copy := duel.search_copy()
	var said: Array = []
	for step in 10:
		if copy.phase != ELDuel.Phase.DEFENCE: break
		_play_side(copy, 0)
		var command := ELCombatSearch.think(copy)
		said.append(command)
		if command.is_empty() or not ELCombatSearch.apply(copy, command): copy.end_phase()
	ELCombatSearch.smart_engine = saved
	check(not (copy.phase == ELDuel.Phase.FINISHED and copy.winner == 1), "reblock: the blocker is moved onto the 7/3 and the hero lives (%s)" % str(said))

## Under the "fair" information policy no reading of the engine's own hangs
## on the other hand.
func _information() -> void:
	var el1 := _profile("el1")
	if el1 == null: return
	# "full" is the default; the fair policy is set here by name, and the
	# default put back at the end.
	var info_default := ELCombatSearch.smart_engine_info
	check(info_default == "full", "information: the smarter player's policy is \"full\" by default")
	(ELCombatSearch as Script).set("smart_engine_info", "fair")
	# Two duels alike in all a hero could know: the other hero drew other
	# cards, and the run of chance (the cards to come) is another.
	for mode: int in [-1, 5, 7, 8, 9]:
		var told: Array = []
		for variant in 2:
			var duel := Fixtures.drawn_hands(el1, [["MGHT", "MGHT"], ["DELS", "ENFL"]][variant], variant)
			if duel == null: continue
			var ctx := Fixtures.context(el1, 0)
			ctx.brain_cards = mode < 0
			ELCombatBrain.ask(ctx, duel, 1, 1000, true, mode, [], 4, 8)
			told.append(ELCombatBrain.last_packed)
		check(told.size() == 2 and told[0] == told[1], "information: under \"fair\" mode %d is told nothing of the cards the other hero drew or of those to come" % mode)
	# A reading made for the other hero on this hero's behalf (the guard
	# against a forced loss) is still held to what this hero knows.
	var guard: Array = []
	for variant in 2:
		var duel := Fixtures.drawn_hands(el1, [["MGHT", "MGHT"], ["DELS", "ENFL"]][variant], variant)
		if duel == null: continue
		var foe := Fixtures.context(el1, 1)
		foe.viewer = 0
		ELCombatBrain.ask(foe, duel, 1, 1000, true, 9, [], 4, 8)
		guard.append(ELCombatBrain.last_packed)
	check(guard.size() == 2 and guard[0] == guard[1], "information: under \"fair\" a reading for the other hero is told nothing this hero does not know")
	# The search written in the game's language reads a copy of the duel as
	# its hero could know it: the same copy for both duels, with this hero's
	# own hand as it is, and the same decision either way from the engine
	# and from that search.
	var views: Array = []
	var decisions := {true: [], false: []}
	var saved_engine := ELCombatSearch.smart_engine
	for variant in 2:
		var duel := Fixtures.drawn_hands(el1, [["MGHT", "MGHT"], ["DELS", "ENFL"]][variant], variant)
		if duel == null: continue
		var view := ELCombatSearch.fair_view(duel, 0)
		views.append([view.heroes, view.rng_state, view.creatures])
		check(view.heroes[0].hand == duel.heroes[0].hand and view.heroes[1].hand.size() == duel.heroes[1].hand.size(),
			"information: a fair view keeps the hero's own hand and the number of cards the other holds")
		var smart: Array[int] = [0]
		duel.smart_sides = smart
		for engine: bool in [true, false]:
			ELCombatSearch.smart_engine = engine
			ELCombatSearch.reset_caches()
			var stats := {}
			var command := ELCombatSearch.think(duel, stats)
			decisions[engine].append([command, stats.get("engine", ""), stats.get("positions", 0), stats.get("value", 0.0)])
	ELCombatSearch.smart_engine = saved_engine
	check(views.size() == 2 and views[0] == views[1], "information: a fair view is the same whatever the other hero drew and whatever is to come")
	for engine: bool in [true, false]:
		var made: Array = decisions[engine]
		check(made.size() == 2 and made[0] == made[1], "information: under \"fair\" the %s decides the same whatever the other hero drew and whatever is to come (%s)" % ["engine" if engine else "search", str(made[0]) if not made.is_empty() else "-"])
	# With everything known the two duels are not the same to it.
	(ELCombatSearch as Script).set("smart_engine_info", "full")
	var full: Array = []
	for variant in 2:
		var duel := Fixtures.drawn_hands(el1, [["MGHT", "MGHT"], ["DELS", "ENFL"]][variant], variant)
		if duel == null: continue
		ELCombatBrain.ask(Fixtures.context(el1, 0), duel, 1, 1000, true, 5, [], 4, 8)
		full.append(ELCombatBrain.last_packed)
	check(full.size() == 2 and full[0] != full[1], "information: under \"full\" the engine is told the other hand and the cards to come")
	(ELCombatSearch as Script).set("smart_engine_info", info_default)
