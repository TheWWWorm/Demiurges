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
	ELPuzzles.remember = false
	if _wanted("guard attack"): _guard_attack()
	if _wanted("cached summon"): _cached_summon()
	if _wanted("spell payments"): _spell_payments()
	if _wanted("ability routes"): _ability_routes()
	if _wanted("phase routes"): _phase_routes()
	if _wanted("forecast intuition"): _intuition_draws()
	if _wanted("information book"): _fair_book()
	if not ELCombatBrain.available:
		print("SKIP: checks requiring the compiled engine")
		print("%d failures" % failures.size())
		quit(1 if not failures.is_empty() else 0)
		return
	if _wanted("chance"): _chance()
	if _wanted("request"): _request()
	if _wanted("search workers"): _search_workers()
	if _wanted("forced defence"): _forced_defence()
	if _wanted("pale recovery"): _recovered_manifestation()
	if _wanted("retained wounds"):
		_overload_decay()
		_retained_wounds()
	if _wanted("forecast"): _forecast()
	if _wanted("forecast rune charges"): _forecast_charges()
	if _wanted("protected forecast"): _protected_forecast()
	if _wanted("block coverage"): _block_coverage()
	if _wanted("disturbance forecast"): _disturbance_forecast()
	if _wanted("disturbance onset"): _disturbance_onset()
	if _wanted("attack order"): _attack_order()
	if _wanted("comet payments"): _comet_payments()
	if _wanted("crowded"): _crowded()
	if _wanted("repeated cards"): _repeated_cards()
	if _wanted("curse hand order"): _curse_hand_order()
	if _wanted("next turn cast"): _next_turn_cast()
	if _wanted("pruned"): _pruned()
	if _wanted("comet"): _comet()
	if _wanted("place"): _place()
	if _wanted("reblock"): _reblock()
	if _wanted("information"): _information()
	print("%d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _disturbance_forecast() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var protections := ["none", "REGN"]
		if edition == "el2": protections.append_array(["ENBR", "LFGR"])
		for protection: String in protections:
			var hero := {"health": 3, "maximum": 20, "turns": 13, "level": 4, "mana": 0,
				"spec": "NONE", "skills": {}, "enchantments": []}
			if protection == "REGN": hero.skills = {"REGN": 2}
			elif protection != "none": hero.enchantments.append(protection)
			var foe := {"health": 5, "maximum": 20, "turns": 13, "level": 4, "mana": 0, "spec": "NONE", "skills": {}}
			var duel := Fixtures.build(profile, {"heroes": [hero, foe]})
			var score := ELCombatBrain.reckon(Fixtures.context(profile, 0), duel)
			for turn in 12:
				if duel.winner >= 0 or not duel.end_phase(): break
			var expected := 1 if protection == "none" else 0
			check(duel.winner == expected and not score.is_empty() and (score.worth > 0 if expected == 0 else score.worth < 0),
				"disturbance forecast: %s with %s favours the hero that survives when both pass" % [edition, protection])
		if edition == "el2":
			# Energy Barrier absorbs successive small hits. Lifeguard can stop a single fatal hit.
			for race: Dictionary in [{"turns": 12, "foe_health": 7, "ward": "ENBR"}, {"turns": 20, "foe_health": 12, "ward": "LFGR"}]:
				var duel := Fixtures.build(profile, {"heroes": [
					{"health": 3, "maximum": 22, "mana": 4, "turns": race.turns, "level": 4, "spec": "NONE", "skills": {}, "hand": ["LFGR", "ENBR"]},
					{"health": race.foe_health, "maximum": 22, "mana": 0, "turns": race.turns, "level": 4, "spec": "NONE", "skills": {}}]})
				_play_side(duel, 0)
				var move := ELCombatSearch.think(duel)
				var played := ELCombatSearch.apply(duel, move)
				for turn in 24:
					if duel.winner >= 0 or not duel.end_phase(): break
				check(played and move.get("card") == race.ward and duel.winner == 0,
					"disturbance forecast: chooses %s and wins when both heroes then pass" % race.ward)

func _disturbance_onset() -> void:
	var profile := _profile("el2")
	if profile == null: return
	var hero := {"health": 3, "maximum": 20, "mana": 0, "level": 4, "turns": 9, "spec": "NONE", "skills": {}}
	for recipient in 2:
		var walls := []
		for side in 2:
			walls.append({"card": "WLWD", "owner": side, "caster": 1 - side, "enchantments": ["GIFT"] if side == recipient else []})
		var duel := Fixtures.build(profile, {"heroes": [hero, hero], "creatures": walls})
		var score := ELCombatBrain.reckon(Fixtures.context(profile, 0), duel)
		for turn in 12:
			if duel.winner >= 0 or not duel.end_phase(): break
		check(duel.winner == 1 - recipient and not score.is_empty() and (score.worth < 0 if recipient == 0 else score.worth > 0),
			"disturbance onset: the Gift on side %d's wall brings that hero's loss into view" % recipient)
	# No Gift at the root. Disturbance enters the forecast as the search plays future turns.
	var own := {"health": 2, "maximum": 22, "mana": 4, "turns": 8, "level": 4, "spec": "NONE", "skills": {}, "hand": ["LFGR", "ENBR"]}
	var foe := {"health": 4, "maximum": 22, "mana": 0, "turns": 8, "level": 4, "spec": "NONE", "skills": {}}
	var race := Fixtures.build(profile, {"heroes": [own, foe]})
	_play_side(race, 0)
	var move := ELCombatSearch.think(race)
	var played := ELCombatSearch.apply(race, move)
	for turn in 32:
		if race.winner >= 0 or not race.end_phase(): break
	check(played and move.get("card") == "ENBR" and race.winner == 0,
		"disturbance onset: chooses the lasting barrier before either hero is taking damage")
	own.merge({"mana": 2, "turns": 9, "hand": ["GIFT"]}, true)
	foe.turns = 9
	var gift_race := Fixtures.build(profile, {"heroes": [own, foe], "creatures": [{"card": "WLWD", "owner": 0}]})
	_play_side(gift_race, 0)
	var gift := ELCombatSearch.think(gift_race)
	var gave_wall := ELCombatSearch.apply(gift_race, gift)
	for turn in 32:
		if gift_race.winner >= 0 or not gift_race.end_phase(): break
	check(gave_wall and gift.get("card") == "GIFT" and gift_race.winner == 0,
		"disturbance onset: gives away a wall to win the race against a healthier hero")

func _play_side(duel: ELDuel, side: int) -> void:
	var smart: Array[int] = [side]
	duel.smart_sides = smart

## These defenders have no spells or abilities that can stop the attack.
## Reject the line if any creature can still block before resolving combat.
func _resolve_clear_attack(duel: ELDuel) -> bool:
	_play_side(duel, 0)
	ELCombatSearch.reset_caches()
	var turn := duel.turn_serial
	for step in 10:
		if duel.turn_serial != turn or duel.phase != ELDuel.Phase.ATTACK: break
		if not ELCombatSearch.apply(duel, ELCombatSearch.think(duel)): return false
	if duel.turn_serial != turn or duel.phase != ELDuel.Phase.DEFENCE: return false
	for defender: Dictionary in duel.army(1):
		for attacker: int in duel.attacks:
			if duel.block_problem(defender.id, attacker).is_empty(): return false
	return duel.end_phase()

func _wins_clear_attack(duel: ELDuel) -> bool:
	return _resolve_clear_attack(duel) and duel.winner == 0

func _ability_routes() -> void:
	var saved_engine := ELCombatSearch.smart_engine
	var saved_ms := ELCombatSearch.smart_engine_ms
	var saved_budget := ELCombatSearch.smart_engine_budget
	ELCombatSearch.smart_engine = ELCombatBrain.available
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_budget = 20000
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var spores := Fixtures.build(profile, {"heroes": [{"health": 16, "mana": 0}, {"health": 9, "mana": 0}],
			"creatures": [{"card": "SWMN", "owner": 0}, {"card": "SPFG", "owner": 0}, {"card": "SPFG", "owner": 0},
				{"card": "SPFG", "owner": 0}, {"card": "KBGD", "owner": 1}]})
		if ELCombatBrain.available:
			check(spores != null and _wins_clear_attack(spores), "ability routes: %s combines three nonlethal spore hits to clear the guard" % edition)
		var tap := Fixtures.build(profile, {"heroes": [{"health": 8, "mana": 1}, {"health": 6, "mana": 2}],
			"creatures": [{"card": "MTPT", "owner": 0}, {"card": "RVHL", "owner": 0}, {"card": "GROG", "owner": 0},
				{"card": "KBWR", "owner": 1, "flags": ["NoTarget"]}, {"card": "KBWR", "owner": 1}]})
		check(tap != null, "ability routes: %s tapping fixture restores" % edition)
		if tap == null: continue
		if ELCombatBrain.available:
			check(_wins_clear_attack(tap.search_copy()), "ability routes: %s siphons ether and taps both blockers with one activation" % edition)
		var ctx := Fixtures.context(profile, 0)
		ctx.smart = true
		tap.creatures[6].resting = true
		var line := ELCombatSearch.Line.new()
		ELCombatSearch._ability_moves(ctx, line, tap, 0, 2, ELCatalog.first_ability(profile, "MTPT"))
		var target := 6 if edition == "el2" else 5
		check(line.children.size() == 1 and line.children[0].command.target == target
			and ELCombatSearch.apply(tap, line.children[0].command) and tap.creatures[5].resting and tap.heroes[0].mana == 0,
			"ability routes: %s uses one legal representative for the race and pays only for the ready blocker" % edition)
		line.children.clear()
	ELCombatSearch.smart_engine = saved_engine
	ELCombatSearch.smart_engine_ms = saved_ms
	ELCombatSearch.smart_engine_budget = saved_budget
	ELCombatSearch.reset_caches()

func _spell_payments() -> void:
	var profile := _profile("el2")
	if profile == null: return
	var wards := ["ENBR", "ENBR", "LFGR"]
	var guarded := Fixtures.build(profile, {"heroes": [{"health": 12, "mana": 20, "hand": ["COMT"]},
		{"health": 12, "enchantments": wards}], "creatures": [{"card": "GROG", "owner": 1, "enchantments": wards}]})
	if guarded == null:
		check(false, "spell payments: protected targets restore")
		return
	for target: int in [1, 2]:
		var needed := ELCombatSearch._damage_threshold(guarded, target)
		var lower := guarded.search_copy()
		var exact := guarded.search_copy()
		check(needed == (7 if target == 1 else 1) and lower.cast(0, target, -1, needed - 1) and exact.cast(0, target, -1, needed)
			and lower._enchantment_count(target, "LFGR") == 1 and exact._enchantment_count(target, "LFGR") == 0,
			"spell payments: %d is the least Comet damage that spends Lifeguard on target %d behind two barriers" % [needed, target])
	var wave := Fixtures.build(profile, {"heroes": [{"health": 18, "channels": 4, "hand": ["WNFL", "ZAPP"]}, {"health": 5}],
		"creatures": [{"card": "GBAT", "owner": 0}, {"card": "BEHD", "owner": 1, "enchantments": ["LFGR"]}]})
	var comets := Fixtures.build(profile, {"heroes": [{"health": 12, "hand": ["COMT", "COMT"]}, {"health": 18}],
		"creatures": [{"card": "SWMN", "owner": 0}, {"card": "SWMN", "owner": 0}, {"card": "TIWR", "owner": 1},
			{"card": "GROG", "owner": 1, "enchantments": ["ENBR"]}]})
	check(wave != null and comets != null, "spell payments: both positions restore")
	if wave == null or comets == null: return
	wave.heroes[0].mana = wave.cost("WNFL") + wave.cost("ZAPP") + 17
	comets.heroes[0].mana = 2 * comets.cost("COMT") + 10
	var saved_engine := ELCombatSearch.smart_engine
	var saved_budget := ELCombatSearch.smart_engine_budget
	var saved_ms := ELCombatSearch.smart_engine_ms
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine = false
	check(_wins_clear_attack(comets.search_copy()), "spell payments: rules search divides ten ether between both blockers and wins")
	check(_wins_clear_attack(wave.search_copy()), "spell payments: rules search strips Lifeguard and spares its attacking flyer")
	if ELCombatBrain.available:
		ELCombatSearch.smart_engine = true
		ELCombatSearch.smart_engine_budget = 8000000
		check(_wins_clear_attack(comets), "spell payments: native search can spend the next identical Comet after the first")
		ELCombatSearch.smart_engine_budget = 20000
		check(_wins_clear_attack(wave), "spell payments: native search finds the two-spell flying attack within 20,000 nodes")
	ELCombatSearch.smart_engine = saved_engine
	ELCombatSearch.smart_engine_budget = saved_budget
	ELCombatSearch.smart_engine_ms = saved_ms
	ELCombatSearch.reset_caches()

## Check the attack bonus at the end of a search line against the same fight
## played through the duel. A false lethal bonus can outweigh the whole board.
func _forecast() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var ctx := Fixtures.context(profile, 0)
		var guard := {"card": "GROG", "owner": 0, "flags": ["TeamAttack"], "power": 8, "toughness": 10}
		var spec := {"heroes": [{"health": 20}, {"health": 4}], "creatures": [guard, guard]}
		var duel := Fixtures.build(profile, spec)
		var score := ELCombatBrain.reckon(ctx, duel)
		check(not duel.toggle_attack(2) and not duel.toggle_attack(3) and not score.is_empty() and is_equal_approx(score.leaf, score.worth),
			"forecast: %s two guards without a partner threaten no damage" % edition)
		spec.creatures[1] = {"card": "GROG", "owner": 0, "flags": [], "power": 0, "toughness": 4}
		duel = Fixtures.build(profile, spec)
		score = ELCombatBrain.reckon(ctx, duel)
		check(duel.toggle_attack(3) and duel.toggle_attack(2) and not score.is_empty() and score.leaf - score.worth >= 30.0,
			"forecast: %s a zero-power partner can enable the guard's lethal attack" % edition)
		var blocker := {"card": "GROG", "owner": 1, "flags": [], "power": 1, "toughness": 4}
		spec.creatures = [{"card": "GROG", "owner": 0, "flags": ["Trample"], "power": 8, "toughness": 10}, blocker, blocker]
		duel = Fixtures.build(profile, spec)
		score = ELCombatBrain.reckon(ctx, duel)
		var fought := duel.toggle_attack(2) and duel.end_phase() and duel.assign_block(3, 2) and duel.assign_block(4, 2) and duel.end_phase()
		check(fought and duel.heroes[1].health == 4 and not score.is_empty() and is_equal_approx(score.leaf, score.worth),
			"forecast: %s two four-health blockers absorb all eight trample damage" % edition)
		spec.heroes[1].health = 7
		spec.creatures.pop_back()
		spec.creatures[1].damage = 3
		duel = Fixtures.build(profile, spec)
		score = ELCombatBrain.reckon(ctx, duel)
		fought = duel.toggle_attack(2) and duel.end_phase() and duel.assign_block(3, 2) and duel.end_phase()
		check(fought and duel.winner == 0 and not score.is_empty() and score.leaf - score.worth >= 30.0,
			"forecast: %s a wounded blocker absorbs one damage and the remaining seven are lethal" % edition)
		spec = {"heroes": [{"health": 20, "mana": 1}, {"health": 8, "enchantments": ["LSDS"]}],
			"creatures": [{"card": "GROG", "owner": 0, "flags": [], "power": 8, "toughness": 10}]}
		duel = Fixtures.build(profile, spec)
		var paid := duel.toggle_attack(2) and int(duel.heroes[0].mana) == 0
		score = ELCombatBrain.reckon(ctx, duel)
		check(paid and not score.is_empty() and score.leaf - score.worth >= 30.0,
			"forecast: %s a declared attacker has already paid its ether cost" % edition)

## Compare the search horizon with combat resolved in the same declaration order.
func _protected_forecast() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var ctx := Fixtures.context(profile, 0)
		# Defender starts at five. Each row gives the enchantment, army, IDs
		# actually sent, and both heroes' health after combat.
		var cases := [
			["FDBK", ["GROG"], [2], 6, 5],
			["LNRD", ["GROG"], [2], 6, 5],
			["ETCH", ["GROG"], [2], 0 if edition == "el2" else 6, 0],
			["REDR", ["GROG"], [2], 12, 5],
			["REDR", ["BEHD", "BEHD"], [2, 3], 12, 2],
			["STSK", ["KBWR", "GROG"], [2, 3], 12, 1],
			["LFGR", ["KBWR", "GBAT"], [2, 3], 12, 0],
			["LFGR", ["KBWR", "GBAT"], [3, 2], 12, 4],
			["", ["KBWR", "GROG"], [2], 12, 4],
		]
		for row: Array in cases:
			var charm: String = row[0]
			if not charm.is_empty() and not profile.table("CombatSpells").has(charm): continue
			var army := []
			for card: String in row[1]: army.append({"card": card, "owner": 0})
			if charm == "REDR":
				army.append({"card": "KBWR", "owner": 1, "resting": true, "enchantments": [charm]})
			var worn := [] if charm in ["", "REDR"] else [charm]
			var duel := Fixtures.build(profile, {"heroes": [{"health": 12}, {"health": 5, "enchantments": worn}], "creatures": army})
			var legal := true
			for id: int in row[2]: legal = duel.toggle_attack(id) and legal
			legal = duel.end_phase() and legal
			var score := ELCombatBrain.reckon(ctx, duel)
			if edition == "el2" and charm == "ETCH":
				var pass_step := {"kind": "end_phase"}
				check(ELCombatSearch._holds(ctx, duel, pass_step, [], 1, true) and not ELCombatSearch._holds(ctx, duel, pass_step),
					"protected forecast: a pass that draws does not require an escape from defeat")
			legal = duel.end_phase() and legal
			var bonus := float(score.leaf - score.worth)
			var wins := duel.winner == 0
			var deals_damage := int(duel.heroes[1].health) < 5 and int(duel.heroes[0].health) > 0
			check(legal and duel.heroes[0].health == row[3] and duel.heroes[1].health == row[4]
				and (bonus >= 30.0) == wins and (bonus > 0.001) == deals_damage,
				"protected forecast: %s %s attack %s, health %s/%s, bonus %.2f" % [
					edition, charm if not charm.is_empty() else "committed", row[2], duel.heroes[0].health, duel.heroes[1].health, bonus])

## Compare the horizon estimate with a legal defence in declaration order.
func _block_coverage() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var ctx := Fixtures.context(profile, 0)
		# Attacker cards and powers, defending cards and their targets, ward,
		# starting health and the health remaining after the blocks resolve.
		var cases := [
			[["GROG", "NWLF", "GBAT"], [8, 5, 1], ["WLBR", "GBAT"], [3, 2], [], 3, 2],
			[["GBAT"], [5], ["WLWD"], [2], [], 9, 9],
		]
		if profile.table("CombatSpells").has("LFGR"):
			cases.append([["GROG", "GROG", "GROG"], [8, 1, 5], ["KBWR"], [4], ["LFGR"], 3, 2])
		for row: Array in cases:
			var army := []
			for i in row[0].size():
				army.append({"card": row[0][i], "owner": 0, "power": row[1][i], "toughness": 8})
			for card: String in row[2]:
				army.append({"card": card, "owner": 1, "power": 0, "toughness": 9})
			var duel := Fixtures.build(profile, {"heroes": [{"health": 19}, {"health": row[5], "enchantments": row[4]}], "creatures": army})
			var legal := true
			for i in row[0].size(): legal = duel.toggle_attack(2 + i) and legal
			legal = duel.end_phase() and legal
			var score := ELCombatBrain.reckon(ctx, duel)
			for i in row[2].size():
				legal = duel.assign_block(2 + row[0].size() + i, row[3][i]) and legal
			legal = duel.end_phase() and legal
			var bonus := float(score.leaf - score.worth)
			check(legal and duel.heroes[1].health == row[6] and is_equal_approx(bonus, (row[5] - row[6]) * 0.8),
				"block coverage: %s %s against %s, hero has %s health and threat bonus %.2f" % [edition, row[2], row[0], duel.heroes[1].health, bonus])

## All twelve ether are needed: the three Comets cost one each and
## the three blockers have four, two and three health left.
func _comet_payments() -> void:
	var saved_budget := ELCombatSearch.smart_engine_budget
	var saved_ms := ELCombatSearch.smart_engine_ms
	ELCombatSearch.smart_engine_budget = 20000
	ELCombatSearch.smart_engine_ms = 0
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var army := []
		for i in 4: army.append({"card": "GROG", "owner": 0})
		army.append_array([{"card": "GBAT", "owner": 1}, {"card": "BEHD", "owner": 1, "damage": 1},
			{"card": "CTMN", "owner": 1, "damage": 1}])
		var duel := Fixtures.build(profile, {"heroes": [{"health": 6, "mana": 12, "hand": ["COMT", "COMT", "COMT"]},
			{"health": 24}], "creatures": army})
		check(_wins_clear_attack(duel), "comet payments: %s clears three blockers and wins with twelve ether" % edition)
		var pump := Fixtures.build(profile, {"heroes": [{"health": 12, "hand": ["PSBR"]}, {"health": 12}],
			"creatures": [{"card": "GROG", "owner": 0}]})
		pump.heroes[0].mana = pump.cost("PSBR") + 3
		var payments := []
		for item: Dictionary in ELCombatBrain.weigh(Fixtures.context(profile, 0), pump, 2, 20000, 6):
			var command: Dictionary = item.command
			if command.get("card", "") == "PSBR" and int(command.target) == 2: payments.append(command.power)
		payments.sort()
		check(payments == [0, 1, 2, 3], "comet payments: %s weighs each legal variable payment once (%s)" % [edition, payments])
	ELCombatSearch.smart_engine_budget = saved_budget
	ELCombatSearch.smart_engine_ms = saved_ms

func _attack_order() -> void:
	var saved_budget := ELCombatSearch.smart_engine_budget
	var saved_ms := ELCombatSearch.smart_engine_ms
	ELCombatSearch.smart_engine_budget = 350000
	ELCombatSearch.smart_engine_ms = 0
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		for charm: String in ["LFGR", "REDR"]:
			if not profile.table("CombatSpells").has(charm): continue
			var army := [{"card": "GROG", "owner": 0}, {"card": "KBWR", "owner": 0}]
			if charm == "REDR":
				army.append({"card": "KBWR", "owner": 1, "resting": true, "enchantments": [charm]})
			var duel := Fixtures.build(profile, {"heroes": [{"health": 12}, {"health": 6,
				"enchantments": [charm] if charm == "LFGR" else []}], "creatures": army})
			check(_wins_clear_attack(duel), "attack order: %s sends the one-power attacker into %s and wins this turn" % [edition, charm])
			# Far from lethal, the ordinary search must still choose which hit
			# to spend on the protection. A tougher redirect needs the big hit.
			for protector: String in (["KBWR", "GROG"] if charm == "REDR" else [""]):
				var units := [{"card": "GROG", "owner": 0}, {"card": "KBWR", "owner": 0}]
				if not protector.is_empty():
					units.append({"card": protector, "owner": 1, "resting": true, "enchantments": [charm]})
				var press := Fixtures.build(profile, {"heroes": [
					{"health": 40, "turns": 3, "spec": "NONE", "skills": {}},
					{"health": 80, "turns": 3, "spec": "NONE", "skills": {}, "enchantments": [charm] if protector.is_empty() else []}],
					"creatures": units})
				var expected := 79 if protector == "GROG" else 74
				check(_resolve_clear_attack(press) and press.heroes[1].health == expected,
					"attack order: %s leaves %d health against %s" % [edition, expected,
						charm if protector.is_empty() else "%s on %s" % [charm, protector]])
		if profile.table("CombatSpells").has("LFGR"):
			var layered := Fixtures.build(profile, {"heroes": [
				{"health": 39, "turns": 3, "spec": "NONE", "skills": {}},
				{"health": 79, "turns": 3, "spec": "NONE", "skills": {}, "enchantments": ["LFGR", "LFGR"]}],
				"creatures": [{"card": "GROG", "owner": 0}, {"card": "KBWR", "owner": 0},
					{"card": "GBAT", "owner": 0}, {"card": "KBWR", "owner": 0}]})
			check(_resolve_clear_attack(layered) and layered.heroes[1].health == 68,
				"attack order: both one-power creatures draw Lifeguard before the eleven damage lands")
	ELCombatSearch.smart_engine_budget = saved_budget
	ELCombatSearch.smart_engine_ms = saved_ms

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
	var won := Fixtures.build(el1, {"heroes": [{"health": 20, "mana": 0}, {"health": 6, "mana": 0}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 3, "toughness": 3}, {"card": "GROG", "owner": 0, "power": 3, "toughness": 3}]})
	if won != null:
		var plain := Fixtures.context(el1, 0)
		var weighed := ELCombatBrain.weigh(plain, won, 4, 200000, 16)
		var best := -1e18
		for item: Dictionary in weighed: best = maxf(best, float(item.value))
		check(best >= 1e5, "request: weighing sees the win on the board (best %.1f)" % best)
		var passes := weighed.filter(func(item: Dictionary) -> bool: return item.command.kind == "end_phase")
		check(passes.size() == 1 and passes[0].value < best, "request: passing is scored separately from sending both attackers")
		var combined := weighed.filter(func(item: Dictionary) -> bool: return item.get("line", []).size() == 2)
		check(combined.size() == 1 and combined[0].value == best and combined[0].line == [{"kind": "attack", "id": 2}, {"kind": "attack", "id": 3}],
			"request: weighing preserves the winning pair of attackers")
		var rollouts := ELCombatSearch.smart_engine_rollouts
		ELCombatSearch.smart_engine_rollouts = true
		check(_wins_clear_attack(won), "request: the rollout player sends both attackers and wins through the duel rules")
		ELCombatSearch.smart_engine_rollouts = rollouts

## Two Kobold Guards can win if the Shaman attacks first. Using its Sting
## leaves the enemy Shaman alive to win on the next turn. The large hand
## makes the game use its rules search, including the normal saved plan.
func _guard_attack() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var hand: Array = []
		hand.resize(ELCombatBrain.HAND + 1)
		hand.fill("MGHT")
		var guard := {"card": "KBGD", "owner": 0}
		var shaman := {"card": "KBSH", "owner": 0}
		var spec := {"fixed": false, "heroes": [{"health": 1, "mana": 0, "hand": hand}, {"health": 2, "mana": 0}],
			"creatures": [guard, guard, shaman, {"card": "KBSH", "owner": 1, "resting": true}]}
		var duel := Fixtures.build(profile, spec)
		_play_side(duel, 0)
		ELCombatSearch.reset_caches()
		var stats := {}
		var first := ELCombatSearch.think(duel, stats)
		var played := ELCombatSearch.apply(duel, first)
		check(played and first == {"kind": "attack", "id": 4} and stats.get("engine") == "search",
			"guard attack: %s the rules search sends the zero-power Shaman first" % edition)
		for step in 3:
			if not played or duel.phase != ELDuel.Phase.ATTACK: break
			played = ELCombatSearch.apply(duel, ELCombatSearch.think(duel))
		check(played and duel.phase == ELDuel.Phase.DEFENCE and duel.end_phase() and duel.winner == 0,
			"guard attack: %s the saved sequence sends both guards and wins this turn" % edition)
		duel = Fixtures.build(profile, spec)
		var line := ELCombatSearch.Line.new()
		check(not ELCombatSearch._send_attackers(line, duel, [2, 3], true) and duel.attacks.is_empty(),
			"guard attack: %s a selected set cannot recruit an escort outside it" % edition)
		check(ELCombatSearch._send_attackers(line, duel, [2, 3, 4], true) and duel.attacks == [4, 2, 3],
			"guard attack: %s a selected set declares its escort before its guards" % edition)
		spec.heroes[1].enchantments = ["LSDS"]
		spec.heroes[0].mana = 1
		duel = Fixtures.build(profile, spec)
		line = ELCombatSearch.Line.new()
		check(not ELCombatSearch._send_attackers(line, duel, [2, 3], true, [4]) and duel.heroes[0].mana == 1,
			"guard attack: %s one ether is kept when the escort and guard would cost two" % edition)

## Each Comet can name several targets at several prices. The ability to
## exhaust a race wins immediately but used to fall outside the move list.
func _repeated_cards() -> void:
	var profile := _profile("el2")
	if profile == null: return
	var hand := []
	var uses := []
	for i in 12:
		hand.append("COMT")
		uses.append(1)
	var units := [{"card": "MTPT", "owner": 0}, {"card": "SWMN", "owner": 0}, {"card": "SWMN", "owner": 0}]
	for i in 8: units.append({"card": "GROG", "owner": 1})
	var duel := Fixtures.build(profile, {"heroes": [
		{"health": 9, "mana": 8, "hand": hand, "deck": hand, "pages": range(hand.size()), "spell_uses": uses},
		{"health": 18, "mana": 0}], "creatures": units})
	var saved_budget := ELCombatSearch.smart_engine_budget
	var saved_ms := ELCombatSearch.smart_engine_ms
	ELCombatSearch.smart_engine_budget = 8000000
	ELCombatSearch.smart_engine_ms = 0
	check(duel != null and _wins_clear_attack(duel), "repeated cards: a hand full of Comets still sees the two Sawers' winning attack")
	var shots := Fixtures.build(profile, {"heroes": [{"health": 10, "mana": 4, "hand": ["ZAPP", "ZAPP"],
		"deck": ["ZAPP", "ZAPP"], "pages": [0, 1], "spell_uses": [1, 1]}, {"health": 1}]})
	var lethal_slots := {}
	if shots != null:
		for item: Dictionary in ELCombatBrain.weigh(Fixtures.context(profile, 0), shots, 2, 20000, 8):
			var command: Dictionary = item.command
			if command.get("card") == "ZAPP" and command.target == 1 and item.complete and item.value >= 1e5:
				lethal_slots[command.index] = true
	check(lethal_slots.has(0) and lethal_slots.has(1), "repeated cards: root evaluation still sees a winning Zap from each page")
	ELCombatSearch.smart_engine_budget = saved_budget
	ELCombatSearch.smart_engine_ms = saved_ms
	ELCombatSearch.reset_caches()

## Curse takes creatures from the front of the displayed hand. Newly drawn
## cards can be at the front even when they occupy the last storage slots.
func _curse_hand_order() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var hand := ["CURS"]
		var charges := [1]
		for i in range(1, 16):
			hand.append(["KBWR", "GBAT", "GROG"][i % 3])
			charges.append(1)
		var duel := Fixtures.build(profile, {"heroes": [{"health": 35, "mana": 40,
			"hand": hand, "deck": hand, "pages": range(hand.size()), "spell_uses": charges}, {"health": 60}]})
		var display_keys := range(hand.size())
		display_keys.reverse()
		duel.heroes[0].hand_view = display_keys
		var after := duel.search_copy()
		check(after.cast(0, 0), "curse hand order: %s Curse resolves" % edition)
		var ctx := Fixtures.context(profile, 0)
		for slot in [12, 15]:
			var survivor: int = after.heroes[0].hand_slots.find(slot)
			var legal := survivor >= 0 and after.search_copy().cast(survivor, -1)
			var model := ELCombatBrain.fight(ctx, duel, 4, [[3, 0, -1, 0], [3, slot, -99, 0]])
			check(model.get("played", 0) == (2 if legal else 1),
				"curse hand order: %s follow-up summon from page %d agrees with duel rules" % [edition, slot])

## A second Zap wins with two ether, or with one ether and Ether Drop.
## Keep the defence plan when it still leaves the winning sequence open.
func _next_turn_cast() -> void:
	var profile := _profile("el2")
	if profile == null: return
	for scenario: Array in [["ZAPP", 2, "KBWR"], ["GBAT", 2, "KBWR"],
			["ZAPP", 1, "KBWR"], ["ZAPP", 1, "MNDP"], ["GBAT", 1, "KBWR"]]:
		var draw: String = scenario[0]
		var ether: int = scenario[1]
		var forecast: String = scenario[2]
		var hand := ["KBWR", "ZAPP"]
		if ether == 1: hand.append("MNDP")
		var uses := []
		uses.resize(hand.size() + 1)
		uses.fill(1)
		var duel := Fixtures.build(profile, {"phase": "defence", "heroes": [
			{"health": 2, "mana": 0}, {"health": 15, "channels": ether, "mana": ether,
			"hand": hand, "deck": hand + [draw], "pages": range(hand.size()), "spell_uses": uses}]})
		duel.setup.puzzle_fixed_hands = false
		duel.smart_sides = [1]
		ELCombatSearch.reset_caches()
		var request := ELCombatSearch.request(duel)
		var cast := {"kind": "cast", "index": hand.find(forecast), "card": forecast, "target": -1, "grave": -1, "power": 0}
		ELCombatSearch._remember_next_cast(Fixtures.context(profile, 1), duel, cast, request.policy)
		check(duel.end_phase() and duel.heroes[1].hand.back() == draw, "next turn cast: draw %s" % draw)
		var planned := ELCombatSearch._recall(duel, request.policy)
		if draw == "GBAT":
			check(planned == cast and ELCombatSearch.apply(duel, planned), "next turn cast: an unaffordable draw preserves the legal summon")
		else:
			if forecast == "MNDP":
				check(planned == cast, "next turn cast: the planned Ether Drop still funds both Zaps")
			else:
				check(planned.is_empty(), "next turn cast: reconsider the summon with %d starting ether" % ether)
			for step in hand.size():
				if duel.phase == ELDuel.Phase.FINISHED: break
				ELCombatSearch.apply(duel, ELCombatSearch.think(duel))
			check(duel.winner == 1, "next turn cast: both Zaps deal lethal under the duel rules")
	ELCombatSearch.reset_caches()

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

func _cached_summon() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var duel := Fixtures.build(profile, {"heroes": [
			{"health": 2, "mana": 12, "hand": ["KBWR", "GROG", "GBAT"]}, {"health": 20}],
			"creatures": [{"card": "GBAT", "owner": 1, "power": 4, "toughness": 5}]})
		duel.smart_sides = [0]
		var asked := ELCombatSearch.request(duel)
		asked.budget = 1000000
		asked.deadline_usec = 0
		var first := {"kind": "cast", "card": "KBWR", "index": 0, "target": -1, "grave": -1, "power": 0}
		ELCombatSearch._remember(duel, [first, {"kind": "end_phase"}], asked.policy)
		var legal := ELCombatSearch.apply(duel, first)
		var stats := {}
		var command := ELCombatSearch.think(duel, stats, false, asked)
		check(legal and command.get("card") == "GBAT" and stats.get("engine") == "summon_defence",
			"cached summon: %s chooses a flying blocker when the first affordable creature cannot stop lethal" % edition)
		if command.get("card") == "GBAT":
			legal = ELCombatSearch.apply(duel, command) and duel.end_phase()
			legal = legal and duel.toggle_attack(2) and duel.end_phase()
			legal = legal and duel.assign_block(duel.army(0).back().id, 2) and duel.end_phase()
			check(legal and duel.heroes[0].health > 0, "cached summon: %s the new flyer blocks under the duel rules" % edition)

func _phase_routes() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var spec := {"heroes": [{"health": 4}, {"health": 2}], "creatures": [
			{"card": "GROG", "owner": 0, "power": 2, "toughness": 4, "flags": []},
			{"card": "GROG", "owner": 1, "power": 4, "toughness": 5, "flags": []}]}
		var duel := Fixtures.build(profile, spec)
		if duel == null: continue
		var ctx := Fixtures.context(profile, 0)
		ctx.smart = true
		ctx.orderly = true
		ctx.width = 6
		ctx.limit = 3
		var root := ELCombatSearch.Line.new()
		var attack := ELCombatSearch._add(root, {"kind": "attack", "id": 2}, 1.0, ELCombatSearch.MOVE_ATTACK)
		attack.budget = 1500
		var read := ELCombatSearch._search(ctx, attack, duel)
		root.children.clear()
		var played := duel.toggle_attack(2) and duel.end_phase() and duel.assign_block(3, 2) and duel.end_phase()
		played = played and duel.toggle_attack(3) and duel.end_phase() and duel.end_phase()
		check(played and duel.winner == 1 and read and attack.value < -9000,
			"phase routes: %s the rules search sees the defender kill the attacker and win on the counterattack" % edition)

		# The same assignments in a different order can kill different blockers.
		spec.creatures.append({"card": "GROG", "owner": 1, "power": 1, "toughness": 1, "flags": []})
		duel = Fixtures.build(profile, spec)
		if duel == null or not duel.toggle_attack(2) or not duel.end_phase(): continue
		ctx.limit = 0
		root = ELCombatSearch.Line.new()
		var searched := []
		var small_blocker_survives := []
		for pairs: Array in [[3, 2, 4, 2], [3, 2, 4, 2], [4, 2, 3, 2]]:
			var blocks := ELCombatSearch._add(root, {"kind": "block_set", "pairs": pairs}, 1.0, ELCombatSearch.MOVE_BRAIN_BLOCKS)
			blocks.budget = 100
			searched.append(ELCombatSearch._search(ctx, blocks, duel))
			var fight := duel.search_copy()
			small_blocker_survives.append(fight.assign_block(pairs[0], 2) and fight.assign_block(pairs[2], 2) and fight.end_phase() and fight.creatures.has(4))
		root.children.clear()
		check(searched == [true, false, true] and small_blocker_survives == [true, true, false],
			"phase routes: %s identical blocks share a search and the order that loses the 1/1 gets a separate reading" % edition)

func _intuition_draws() -> void:
	for edition: String in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var duel := Fixtures.build(profile, {"fixed": false, "heroes": [{}, {"spec": "QIHN", "spec_level": 20}]})
		if duel == null: continue
		for hero: Dictionary in duel.heroes:
			hero.deck = ["STRT", "GROG", "KBWR", "MGHT"]
			hero.spell_uses = [4, 4, 4, 4]
			if edition == "el1":
				for slot in hero.deck.size():
					if ELRunes.unlimited(profile, hero, hero.deck[slot]): hero.spell_uses[slot] = -1
			hero.drawn = []
		var matching := true
		var bonuses := 0
		for seed in range(1, 17):
			var played := duel.search_copy()
			played.rng_state = seed
			var forecast := ELCombatBrain.foreseen(played)
			for phase in 8:
				if played.heroes[0].hand.size() >= 2 or not played.end_phase(): break
			if played.heroes[1].hand.size() > 2: bonuses += 1
			for side in 2:
				var hand: Array = played.heroes[side].hand
				matching = matching and hand.size() >= 2 and forecast[side].slice(0, hand.size()) == hand
		check(matching and bonuses > 0 and bonuses < 16, "forecast: %s both books follow the actual deal through Intuition hits and misses" % edition)

func _forecast_charges() -> void:
	var profile := _profile("el2")
	if profile == null: return
	for uses in [1, 2]:
		var hero := {"health": 40, "mana": 10, "channels": 10, "deck": ["ZAPP"], "spell_uses": [uses],
			"hand": ["ZAPP", "WTLK", "WTLK", "WTLK", "WTLK", "WTLK"], "pages": [0, -1, -1, -1, -1, -1]}
		var duel := Fixtures.build(profile, {"fixed": false, "heroes": [hero, {"health": 2, "deck": ["GEYS"], "spell_uses": [0]}]})
		# Passing discards Zap from the back of the rail. Its charge is then
		# free to draw again. Casting Zap instead spends that charge.
		duel.heroes[0].hand_view = [5, 4, 3, 2, 1, 0]
		var ctx := Fixtures.context(profile, 0)
		for cast in [false, true]:
			var copy := duel.search_copy()
			var commands := []
			var legal := true
			if cast:
				legal = ELCombatSearch.apply(copy, {"kind": "cast", "index": 0, "card": "ZAPP", "target": 1, "grave": -1, "power": 0})
				commands.append([3, 0, -2, 0])
			while legal and copy.turn_serial < duel.turn_serial + 2:
				legal = copy.end_phase()
				commands.append([0, 0, 0, 0])
			var model := ELCombatBrain.fight(ctx, duel, 4, commands)
			check(legal and model.get("played", -1) == commands.size() and model.counts.hands[0] == copy.heroes[0].hand.size(),
				"forecast: real and simulated hands agree after %s with %d Zap charge(s)" % ["casting" if cast else "passing", uses])
			if copy.scripts != null and copy.scripts.search_only: copy.scripts.close()
		var proof := ELCombatBrain.prove(ctx, duel, 2, 100000)
		check(proof.get("status") == ("proven" if uses == 2 else "no_forced_win"),
			"forecast: a two-Zap win requires two charges (book has %d)" % uses)
		if uses == 1:
			# The packed hand can name fewer pages than this custom book has.
			# The Zap in hand and the next Zap still have separate charges.
			var large := duel.heroes[0] as Dictionary
			large.deck.resize(65)
			large.deck.fill("ZAPP")
			large.spell_uses.resize(65)
			large.spell_uses.fill(0)
			large.spell_uses[63] = 1
			large.spell_uses[64] = 1
			large.hand_slots[0] = 63
			large.drawn = [63]
			check(ELCombatBrain.prove(ctx, duel, 2, 100000).get("status") == "proven", "forecast: independent late pages can each pay for one Zap")

func _fair_book() -> void:
	var profile := _profile("el2")
	if profile == null: return
	var book := ["STRT", "GROG", "KBWR", "MGHT"]
	var duel := Fixtures.build(profile, {"fixed": false, "heroes": [
		{"deck": book, "spell_uses": [1, 1, 1, 1], "drawn": [0, 1, 2]},
		{"deck": book, "spell_uses": [1, 1, 1, 1], "hand": ["STRT", "MGHT", "GROG", "KBWR", "MGHT"], "pages": [0, -1, 1, 2, 3]}]})
	if duel == null: return
	var valid := true
	var forecasts := true
	for seed in 16:
		duel.turn_serial = seed
		var view := ELCombatSearch.fair_view(duel, 0)
		var other: Dictionary = view.heroes[1]
		valid = valid and ELSpellCharges.valid(profile, other) and other.hand[1] == "MGHT" and other.hand_slots[1] == -1
		var coming := ELCombatBrain.foreseen(view)
		forecasts = forecasts and coming[1][0] == "" and coming[0][0] == "MGHT"
	check(valid, "information: a sampled EL2 hand reserves each charge once and keeps a public return")
	check(forecasts, "information: the opponent's fully reserved book has no draw and the viewer knows its last unvisited page")
	var saved := ELCombatSearch.smart_engine_info
	ELCombatSearch.smart_engine_info = "fair"
	var views := []
	var packs := []
	for variant in 2:
		duel.heroes[1].drawn = [[0, 1, 2, 3], [3, 2, 1, 0]][variant]
		if variant == 1:
			duel.heroes[1].hand = ["MGHT", "MGHT", "GROG", "KBWR", "STRT"]
			duel.heroes[1].hand_slots = [3, -1, 1, 2, 0]
		var before := duel.snapshot()
		var view := ELCombatSearch.fair_view(duel, 0)
		views.append(view.heroes)
		if ELCombatBrain.available:
			ELCombatBrain.last_packed = PackedByteArray()
			ELCombatBrain.ask(Fixtures.context(profile, 0), duel, 1, 1000, true, 5, [], 4, 8)
			packs.append(ELCombatBrain.last_packed)
		check(before == duel.snapshot(), "information: sampling leaves the live EL2 duel intact (deal %d)" % variant)
	check(views[0] == views[1], "information: concealed EL2 cards and draw history produce the same search view")
	if ELCombatBrain.available:
		check(not packs[0].is_empty() and packs[0] == packs[1], "information: the native engine receives the same EL2 hand and forecast in both deals")
	ELCombatSearch.smart_engine_info = saved

func _search_workers() -> void:
	var pacing := ELPracticeAI.FrameBudget.new()
	check(pacing.limit == pacing.capacity, "search workers: a displayed duel starts with every assigned processor")
	pacing.capacity = 8
	pacing.limit = 7
	var stamp := 1000000
	for frame in 130:
		pacing.observe(stamp, true, 16667)
		stamp += 16667
	check(pacing.limit == 8, "search workers: smooth frames release all eight workers")
	pacing.observe(stamp + 70000, true, 16667)
	check(pacing.limit == 6, "search workers: a missed frame reduces the live allowance")
	pacing.observe(stamp + 90000, false, 16667)
	pacing.observe(stamp + 4000000, true, 16667)
	check(pacing.limit == 6, "search workers: idle time between decisions does not count as a frame stall")
	var sustained := ELPracticeAI.FrameBudget.new()
	sustained.limit = 8
	for frame in 15: sustained.observe(1000000 + frame * 22000, true, 16667)
	check(sustained.limit == 6, "search workers: sustained 22 ms frames reduce the allowance at a 60 FPS target")
	var slower_scene := ELPracticeAI.FrameBudget.new()
	slower_scene.limit = 8
	for frame in 36: slower_scene.observe(1000000 + frame * 22000, frame >= 18, 16667)
	check(slower_scene.limit == 8, "search workers: an unchanged 22 ms idle cadence keeps its allowance")
	var cold_scene := ELPracticeAI.FrameBudget.new()
	cold_scene.capacity = 8
	cold_scene.limit = 8
	var helped := ELPracticeAI.FrameBudget.new()
	helped.capacity = 8
	helped.limit = 8
	var helped_stamp := 1000000
	for frame in 90:
		cold_scene.observe(1000000 + frame * 31000, true, 16667)
		helped_stamp += 22000 if helped.limit == 1 else 36000
		helped.observe(helped_stamp, true, 16667)
	check(cold_scene.limit == 8, "search workers: a stable 31 ms scene regains its cores when one worker draws at the same pace")
	check(helped.limit == 1, "search workers: keep the reduction when it improves a cold scene from 36 to 22 ms")
	var profile := _profile("el1")
	if profile == null: return
	var duel := ELDuel.new()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tools/duel_ai_positions/el1_survive_cutters.json"))
	if not duel.restore(profile, doc):
		check(false, "search workers: crowded defence restores")
		return
	var saved_workers := ELCombatSearch.smart_engine_workers
	var saved_ms := ELCombatSearch.smart_engine_ms
	var limit := mini(6, ELCombatSearch.available_processors())
	var fixed: Array = []
	for ms in [0, 750]:
		for workers: int in [1, limit]:
			ELCombatSearch.smart_engine_workers = workers
			ELCombatSearch.smart_engine_ms = ms
			var ctx := Fixtures.context(profile, duel.active_side())
			var choice := ELCombatBrain.choose(ctx, duel, 4, 2000000, 16, 16)
			var copy := ELDuel.new()
			check(copy.restore(profile, doc) and ELCombatSearch.apply(copy, choice.get("command", {})),
				"search workers: legal command at %d ms with limit %d" % [ms, workers])
			var used := int(choice.get("workers", 0))
			check(used >= 1 and used <= workers, "search workers: %d started with limit %d" % [used, workers])
			if ms == 0: fixed.append(choice.get("raw", PackedInt32Array()))
			elif workers >= 3: check(used >= 3, "search workers: multiple alternatives ran concurrently on the crowded defence")
	check(fixed.size() == 2 and fixed[0] == fixed[1], "search workers: fixed-node replay reproduces the full serial result")
	# Exercise the parallel search at a horizon both sides can finish. A
	# repeated position met on another worker must carry the same score.
	var packet := ELCombatBrain.last_packed.to_int32_array()
	if ELCombatBrain.supports_frame_limit:
		var displayed := packet.duplicate()
		var available := mini(24, ELCombatSearch.available_processors())
		# Include a deeper reply search in the requested allocation, so the
		# live one-worker limit covers both groups on a wide machine.
		displayed[26] = (available << 8) | 6 | (displayed[26] & 1)
		displayed[28] = 600
		ClassDB.class_call_static(&"ELNativeDuelBrain", &"set_frame_worker_limit", 1)
		var capped := (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", displayed.to_byte_array()) as PackedByteArray).to_int32_array()
		ClassDB.class_call_static(&"ELNativeDuelBrain", &"set_frame_worker_limit", 255)
		check(capped.size() > 10 and capped[10 + 4 * capped[8]] == 1, "search workers: displayed native search honors the live one-worker allowance")
		if available >= 12:
			var resumed := (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", displayed.to_byte_array()) as PackedByteArray).to_int32_array()
			check(resumed.size() > 10 and resumed[10 + 4 * resumed[8]] > 1 and resumed[10 + 4 * resumed[8]] <= available, "search workers: concurrent searches stay within the restored allowance")
	packet[16] = 3
	packet[22] &= 0xffff
	packet[31] = 0
	packet[28] = 1500
	var answers := []
	for workers: int in [1, limit, limit]:
		packet[26] = (packet[26] & 1) | (workers << 8)
		var raw := (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", packet.to_byte_array()) as PackedByteArray).to_int32_array()
		check(raw.size() >= 11 and raw[6] == 0 and (raw[7] & 255) == 3, "search workers: finished the same three-command horizon")
		answers.append(raw.slice(0, 5))
	check(answers[0] == answers[1] and answers[0] == answers[2], "search workers: repeated parallel reads agree with the serial score and move")
	ELCombatSearch.smart_engine_workers = saved_workers
	ELCombatSearch.smart_engine_ms = saved_ms

## Concealed opponent cards must produce the same fair search view.
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
	# Equality includes the node count. Use an exact work allowance so CPU
	# scheduling cannot affect the comparison between the two hidden hands.
	var saved_ms := ELCombatSearch.smart_engine_ms
	ELCombatSearch.smart_engine_ms = 0
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
	ELCombatSearch.smart_engine_ms = saved_ms
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

func _forced_defence() -> void:
	var profile := _profile("el2")
	if profile == null: return
	var board := {"phase": "defence", "attacks": [2], "heroes": [{"health": 20}, {"health": 20, "mana": 4}],
		"creatures": [{"card": "GROG", "owner": 0, "power": 2, "toughness": 2}]}
	var duel := Fixtures.build(profile, board)
	duel.smart_sides = [1]
	duel.setup.puzzle_fixed_hands = false
	ELCombatSearch.reset_caches()
	var stats := {}
	var action := ELCombatSearch.think(duel, stats)
	check(action.get("kind") == "end_phase" and stats.get("engine") == "forced_pass" and stats.get("positions") == 0,
			"forced defence: a hero with no legal response passes immediately")
	board.heroes[1].hand = ["FOGG"]
	duel = Fixtures.build(profile, board)
	check(not ELCombatSearch._must_end_defence(duel, 1), "forced defence: consider a defensive spell")
	board.heroes[1].hand = []
	board.creatures.append({"card": "GROG", "owner": 1, "power": 2, "toughness": 2})
	duel = Fixtures.build(profile, board)
	check(duel.block_problem(3, 2).is_empty() and not ELCombatSearch._must_end_defence(duel, 1),
			"forced defence: consider a legal block")
	check(duel.assign_block(3, 2) and not ELCombatSearch._must_end_defence(duel, 1),
			"forced defence: preserve the choice to revise an assigned block")

	board.attacks = []
	board.creatures[1] = {"card": "CTMN", "owner": 1, "resting": true}
	board.creatures.append({"card": "GROG", "owner": 1})
	duel = Fixtures.build(profile, board)
	var legal := ELPuzzleProof.legal_moves(duel)
	check(legal.any(func(move: Dictionary) -> bool: return move.kind == "ability") and not ELCombatSearch._must_end_defence(duel, 1),
			"forced defence: consider an ability when no spell or block is available")

func _overload_decay() -> void:
	for edition in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		for card: String in ["OVRL", "BLSS"]:
			for ticks in [0, 1, 2]:
				var duel := Fixtures.build(profile, {"heroes": [{"hand": ["CLNP"], "mana": 20}, {}],
						"creatures": [{"card": "MNHP", "owner": 1, "enchantments": [card]}]})
				var unit: Dictionary = duel.creatures[2]
				var buff: Dictionary = unit.enchantments[0]
				# Both enchantments hold the creature above zero. Removing the
				# last Overload also leaves its earlier turns of decay behind.
				var rule := ELCatalog.rule(profile, card)
				buff.power = int(rule.power)
				buff.toughness = int(rule.toughness)
				unit.decay = ticks
				duel._refresh_stats(unit)
				var what := ELCombatBrain.enchantment_name(duel, 2, buff)
				var model := ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 4, [[3, 0, 0, what]], 200000)
				var applied := duel.cast(0, 2, int(buff.id))
				var survived := duel.creatures.has(2)
				check(applied and survived == (ticks == 0) and model.get("played") == 1 and
						model.get("units", {}).get(2) == (0 if survived else -1),
						"%s Overload: removing %s after %d decay ticks agrees with the duel" % [edition, card, ticks])

func _retained_wounds() -> void:
	for edition in ["el1", "el2"]:
		var profile := _profile(edition)
		if profile == null: continue
		var duel := Fixtures.build(profile, {"heroes": [{"hand": ["CLNP", "CLNP"], "mana": 20}, {}],
				"creatures": [{"card": "MNHP", "owner": 1, "enchantments": ["BLSS", "DWND"]}]})
		var unit: Dictionary = duel.creatures[2]
		var buff: Dictionary = unit.enchantments[0]
		var wound: Dictionary = unit.enchantments[1]
		buff.power = 4
		buff.toughness = 4
		wound.toughness = -4
		wound.lethal = ELCatalog.rule(profile, "DWND").get("lethal", false)
		duel._refresh_stats(unit)
		for first: Dictionary in [buff, wound]:
			var copy := duel.search_copy()
			var first_name := ELCombatBrain.enchantment_name(duel, 2, first)
			var sequence := [[3, 0, 0, first_name]]
			var played := copy.cast(0, 2, int(first.id))
			var model := ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 4, sequence, 200000)
			var alive := copy.creatures.has(2)
			check(played and alive == (first.card == "DWND" or not wound.lethal) and model.get("played") == 1
					and model.get("units", {}).get(2) == (0 if alive else -1),
					"%s wounds: removing %s while Dwindle and Bless are in play agrees with the duel" % [edition, first.card])
			if first.card != "DWND": continue
			sequence.append([3, 1, 0, ELCombatBrain.enchantment_name(duel, 2, buff)])
			model = ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 4, sequence, 200000)
			played = copy.cast(0, 2, int(buff.id))
			check(played and copy.creatures.has(2) and model.get("played") == 2
					and model.get("stats", {}).get(2, {}).get("toughness") == copy.creatures[2].toughness,
					"%s wounds: dispelling the wound before Bless removes its toughness penalty" % edition)

func _recovered_manifestation() -> void:
	var profile := _profile("el2")
	if profile == null: return
	for wait in [false, true]:
		var duel := Fixtures.build(profile, {"heroes": [{"hand": ["ANHL"], "mana": 30, "channels": 3}, {}],
				"creatures": [{"card": "OUD1", "owner": 0}]})
		var copy := duel.search_copy()
		var played := copy.cast(0)
		var route := [[3, 0, -99, 0]]
		if wait:
			for i in 2:
				played = copy.end_phase() and played
				route.append([0, 0, 0, 0])
		var manifested := copy.use_ability(2, "fiendish")
		played = manifested and played
		route.append([11, 0, -99, ELCombatBrain.PALE_KEYS.find("fiendish") << 16])
		var model := ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 4, route, 200000)
		check(played and not copy.in_plane(2) and copy.creatures[2].resting == (not wait)
				and model.get("played") == route.size() and model.get("resting", {}).get(2) == copy.creatures[2].resting,
				"el2: a manifested Devourer %s after lethal damage" % ("is ready on its next turn" if wait else "stays resting"))
	for rested in [false, true]:
		var duel := Fixtures.build(profile, {"heroes": [{"hand": ["CLNP"], "mana": 30, "channels": 3}, {}],
				"creatures": [{"card": "OUD1", "owner": 0, "resting": rested, "enchantments": ["BLSS"]}]})
		var unit: Dictionary = duel.creatures[2]
		var buff: Dictionary = unit.enchantments[0]
		var rule := ELCatalog.rule(profile, "BLSS")
		buff.power = int(rule.power)
		buff.toughness = int(rule.toughness)
		duel._refresh_stats(unit)
		unit.damage = 5
		var copy := duel.search_copy()
		var dispelled := copy.cast(0, 2, int(buff.id))
		var dissipated := copy.in_plane(2)
		var manifested := copy.use_ability(2, "fiendish")
		var route := [[3, 0, 0, ELCombatBrain.enchantment_name(duel, 2, buff)],
				[11, 0, -99, ELCombatBrain.PALE_KEYS.find("fiendish") << 16]]
		var model := ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 4, route, 200000)
		check(dispelled and dissipated and manifested and copy.creatures[2].resting == rested
				and model.get("played") == 2 and model.get("resting", {}).get(2) == rested,
				"el2: losing a toughness bonus preserves the Devourer's prior rest (%s) when it manifests" % rested)
