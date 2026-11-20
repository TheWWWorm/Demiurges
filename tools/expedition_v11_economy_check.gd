extends SceneTree
## Economic opportunity ceilings and v11 no-benefit purchase guards. Uses
## synthetic tables and the production route/choice APIs; no battles are played.
## godot --headless --path game --script ../tools/expedition_v11_economy_check.gd -- \
##   --seeds=64 --output=/tmp/expedition-economy-v11.json
## Optional --baseline=/path/to/frozen-v10/game/src/expedition/run.gd compares
## v10 offers against that original script without changing either source tree.

const Fixture := preload("expedition_fixture.gd")
const FOLDER := "user://expedition_v11_economy_check"
const ECONOMIC := ["silver_scale", "ember_purse", "hunters_badge", "purifier_stone"]
const KINDS := ["wins", "elites", "merchants", "training"]
var checks := 0
var failures: Array[String] = []
var report := {}

func _initialize() -> void:
	_run.call_deferred()

func _argument(name: String, fallback := "") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.trim_prefix("--" + name + "=")
	return fallback

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: " + label)

func _run() -> void:
	var seeds := clampi(int(_argument("seeds", "64")), 1, 256)
	var source := Fixture.profile_at(FOLDER)
	check(source != null, "Synthetic economic fixture is available")
	if source == null:
		quit(1)
		return
	report = {"rules": [10, 11], "seeds": seeds, "bound_states": 0, "optional_event_duels": 0,
		"late_merchants": {}, "training_states": 0, "feast_states": 0, "legacy_comparisons": 0,
		"assumptions": [
			"Synthetic tables support production route, prices, offers and choice APIs. No combat result, win rate or expected run value is measured.",
			"Controlled room states are constructed directly; this is an economic boundary audit, not completed playable journeys.",
			"Production bounds optimistically choose the best room on every future floor, even across disconnected lanes. Independent graph calculations include ordinary paths and one Compass detour per eligible act.",
			"Gold ceilings assume every relevant fight is won; Ember Purse additionally assumes every victory is swift. Optional event duels count. The final guardian cannot repay purchases because the Last Haven precedes it.",
			"Stone's ceiling assumes every remaining merchant removal is useful and bought. Training ceilings assume each available camp or Forge is spent on training. These assumptions deliberately overstate realizable returns.",
			"Late-stock comparisons use the same seeds with the ordinary starting relic, no training, full life, and the Open Road. Version 11's added events can change event assignments; this is not a combat difficulty comparison."
		]}
	_bound_checks(source, seeds)
	_merchant_checks(source, seeds)
	_training_checks(source, seeds)
	_feast_checks(source)
	_level_caps(source)
	_legacy_comparison(source, seeds)
	check(int(report.bound_states) == seeds * 3 * 22 * KINDS.size() * 2, "Every sampled node, act, kind and inclusion mode received a graph-bound check")
	check(int(report.training_states) == seeds * 3, "Every late-training boundary scenario completed")
	check(int(report.feast_states) == 8, "All free-versus-paid Feast boundaries completed")
	check(checks >= seeds * 640 + 50, "Minimum assertion gate prevents incomplete subtests silently passing")
	report.checks = checks
	report.failures = failures.duplicate()
	var output := _argument("output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			check(false, "Economic report can be written")
		else: file.store_string(JSON.stringify(report, "\t", true, true))
	Fixture.clean(FOLDER)
	print("EXPEDITION VERSION 11 ECONOMY: %d checks, %d failure(s); %d seeds; no combat outcomes measured" % [checks, failures.size(), seeds])
	quit(0 if failures.is_empty() else 1)

func _new(source: ELProfile, seed_value: int, version := 11, chapter := 3) -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(source, "ExpeditionFixtureRed", seed_value, version):
		check(false, "Create economic probe: " + run.error)
		return null
	run.choose("relic:amber_seed")
	run.choose("study:none")
	run._reset(source, run.preset, seed_value, chapter)
	run.health = run.max_health
	run.gold = 999
	return run

func _at(run: ELExpeditionRun, room: Dictionary, phase := "") -> void:
	run._clear_room_state()
	run.current = room.id
	run.visited.assign([String(room.id)])
	run.phase = phase if not phase.is_empty() else String(room.kind)

func _value(room: Dictionary, chapter: int, kind: String) -> int:
	var event := int(room.get("event", -1))
	var optional: bool = room.kind == "event" and event in [4, 9]
	match kind:
		"wins": return int((room.kind in ["fight", "elite", "boss"] or optional) and not (chapter == 3 and room.kind == "boss"))
		"elites": return int((room.kind in ["elite", "boss"] or optional) and not (chapter == 3 and room.kind == "boss"))
		"merchants": return int(room.kind == "shop" or (room.kind == "event" and event == 5) or (chapter == 3 and room.kind == "boss"))
		"training": return int(chapter >= 2 and (room.kind == "rest" or (room.kind == "event" and event == 7)))
	return 0

## Independent DAG dynamic program: exact path maximum, with separate states
## for an unused and spent detour. A new act renews the Compass allowance.
func _legal_maxima(runs: Array[ELExpeditionRun], kind: String) -> Dictionary:
	var result := {}
	var future_plain := 0
	var future_compass := 0
	for chapter_index in range(2, -1, -1):
		var run := runs[chapter_index]
		var plain := {}
		var spent := {}
		var unused := {}
		for row_index in range(run._route.size() - 1, -1, -1):
			for room: Dictionary in run._route[row_index]:
				var p := future_plain if room.kind == "boss" else 0
				var s := future_compass if room.kind == "boss" else 0
				var u := future_compass if room.kind == "boss" else 0
				for next: String in room.next:
					p = maxi(p, int(plain[next]))
					s = maxi(s, int(spent[next]))
					u = maxi(u, int(unused[next]))
				if run.act >= 2 and row_index + 1 < run._route.size():
					for next: Dictionary in run._route[row_index + 1]:
						u = maxi(u, int(spent[next.id]))
				var own := _value(room, run.act, kind)
				plain[room.id] = own + p
				spent[room.id] = own + s
				unused[room.id] = own + u
		for room: Dictionary in run._nodes.values():
			result[room.id] = {"plain": int(plain[room.id]), "spent": int(spent[room.id]), "unused": int(unused[room.id])}
		future_plain = 0
		future_compass = 0
		for room: Dictionary in run._route[0]:
			future_plain = maxi(future_plain, int(plain[room.id]))
			future_compass = maxi(future_compass, int(unused[room.id]))
	return result

func _bound_checks(source: ELProfile, seeds: int) -> void:
	for seed_value in seeds:
		var runs: Array[ELExpeditionRun] = []
		for chapter in range(1, 4): runs.append(_new(source, seed_value, 11, chapter))
		for kind: String in KINDS:
			var expected := _legal_maxima(runs, kind)
			for run: ELExpeditionRun in runs:
				for room: Dictionary in run._nodes.values():
					_at(run, room)
					if kind == "wins" and room.kind == "event" and int(room.get("event", -1)) in [4, 9]: report.optional_event_duels += 1
					for include_current: bool in [false, true]:
						var bound := run._remaining_opportunity_bound(kind, include_current)
						var own := 0 if include_current else _value(room, run.act, kind)
						var legal := maxi(int(expected[room.id].plain), maxi(int(expected[room.id].spent), int(expected[room.id].unused))) - own
						check(bound >= legal, "Seed %d %s %s bound covers every natural/Compass route" % [seed_value, room.id, kind])
						report.bound_states += 1
		var final := runs[2]
		_at(final, final._route.back()[0], "haven")
		check(final._remaining_opportunity_bound("wins", true) == 0 and final._remaining_opportunity_bound("elites", true) == 0, "Final guardian cannot repay a pre-Haven purchase")
		check(final._remaining_opportunity_bound("merchants", true) == 1 and final._remaining_opportunity_bound("merchants") == 0, "Haven is counted exactly once when the current merchant is included")
	check(int(report.optional_event_duels) > 0, "The graph audit includes actual generated optional event duels")

func _ceiling(run: ELExpeditionRun, id: String) -> int:
	match id:
		"silver_scale": return 6 * run._remaining_opportunity_bound("wins")
		"ember_purse": return 12 * run._remaining_opportunity_bound("wins")
		"hunters_badge": return 20 * run._remaining_opportunity_bound("elites")
		"purifier_stone": return run._merchant_price(25) * run._remaining_opportunity_bound("merchants", true)
	return -1

func _merchant_checks(source: ELProfile, seeds: int) -> void:
	for version in [10, 11]:
		var data := {"visits": 0, "offers": {}, "cannot_repay_offers": 0, "no_extra_training_offers": 0}
		for seed_value in seeds:
			var run := _new(source, seed_value, version)
			for room: Dictionary in run._nodes.values():
				if room.kind != "shop": continue
				_at(run, room)
				for seal: bool in [false, true]:
					for heart: bool in [false, true]:
						run.relics.assign(["amber_seed", "merchant_seal"] if seal else ["amber_seed"])
						run.keystones.assign(["living_heart"] if heart else [])
						for id: String in ECONOMIC:
							var expected: bool = version < 11 or _ceiling(run, id) > run._shop_relic_price(id)
							check(run._merchant_relic_viable(id) == expected, "Version %d seed %d floor %d applies optimistic repayment with Seal=%s Heart=%s" % [version, seed_value, room.floor, seal, heart])
						check(version < 11 or not run._merchant_relic_viable("silver_scale"), "Final-act merchants cannot sell a Scale that has too few remaining wins to repay")
						if int(room.floor) == 6:
							check(run._remaining_opportunity_bound("wins") <= 1, "Only one pre-Haven victory can follow the second merchant")
							check(version < 11 or (not run._merchant_relic_viable("ember_purse") and not run._merchant_relic_viable("hunters_badge")), "The late merchant excludes purses and badges with no possible repayment")
				run.relics.assign(["amber_seed"])
				run.keystones.clear()
				run._prepare_shop()
				data.visits += 1
				var id := run._shop_relic
				data.offers[id] = int(data.offers.get(id, 0)) + 1
				if id in ECONOMIC and _ceiling(run, id) <= run._shop_relic_price(id): data.cannot_repay_offers += 1
				if id == "twin_seal" and run._training_sessions() + run._remaining_opportunity_bound("training", true) < 3: data.no_extra_training_offers += 1
				check(version < 11 or id.is_empty() or (run._merchant_relic_viable(id) and run._useful_relic(id)), "Actual v11 merchant stock obeys both usefulness filters")
		check(int(data.visits) == seeds * 2, "Version %d samples both final-act merchants for every seed" % version)
		if version == 11:
			check(int(data.cannot_repay_offers) == 0 and int(data.no_extra_training_offers) == 0, "New stock contains no mathematically unrecoverable economic purchase")
		report.late_merchants[str(version)] = data
	var early := _new(source, 17, 11, 1)
	for room: Dictionary in early._nodes.values():
		if room.kind != "shop": continue
		_at(early, room)
		check(early._merchant_relic_viable("silver_scale") and early._merchant_relic_viable("hunters_badge") and early._merchant_relic_viable("purifier_stone"), "Early merchants retain economic relics with enough potential remaining value")
		break
	var late := _new(source, 17)
	for room: Dictionary in late._route[5]:
		if room.kind != "shop": continue
		_at(late, room)
		check("silver_scale" in late._relic_offers(12) and "silver_scale" not in late._relic_offers(12, 0, true), "The repayment filter changes paid merchant stock without globally banning free economy relics")
		break
	report.price_examples = {"floor_6_maximum_pre_haven_wins": 1, "scale_maximum_return": 6, "scale_base_price": 45,
		"purse_maximum_return": 12, "purse_base_price": 45, "badge_maximum_return": 20, "badge_base_price": 60}

func _training_checks(source: ELProfile, seeds: int) -> void:
	for seed_value in seeds:
		var run := _new(source, seed_value)
		for room: Dictionary in run._route[5]:
			if room.kind != "shop": continue
			_at(run, room)
			for sessions in range(3):
				run._training = {} if sessions == 0 else {"PRVD": sessions}
				check(run._remaining_opportunity_bound("training", true) == 1, "Late merchant has at most the final-floor camp for training")
				check(run._can_use_extra_training() == (sessions == 2), "Master's Seal requires the third training session to remain reachable")
				check(run._useful_relic("twin_seal") == (sessions == 2), "The unreachable-third-training guard also applies to free relic pools")
				report.training_states += 1
			# A custom supported starter can already have both skills advanced.
			# Two legal training sessions then exhaust both skills' available ranks.
			run.preset = run.preset.duplicate(true)
			run.preset.skills = {"PRVD": 1, "SUPR": 1}
			run._training = {"PRVD": 1, "SUPR": 1}
			check(not run._can_use_extra_training(), "A remaining camp cannot make Master's Seal useful when every trainable rank is capped")
			break

func _event(source: ELProfile, index: int, version: int) -> ELExpeditionRun:
	for seed_value in range(256):
		var run := _new(source, seed_value, version)
		for room: Dictionary in run._nodes.values():
			if room.kind == "event" and int(room.get("event", -1)) == index:
				_at(run, room)
				return run
	return null

func _option(run: ELExpeditionRun, id: String) -> Dictionary:
	for option: Dictionary in run.choices():
		if option.id == id: return option
	return {}

func _feast_checks(source: ELProfile) -> void:
	for version in [10, 11]:
		for maximum in [24, 32, 40, 52]:
			var run := _event(source, 11, version)
			check(run != null, "Version %d has a generated Feast for the recovery boundary" % version)
			if run == null: continue
			run.max_health = maximum
			run.health = maximum - 1
			var option := _option(run, "feast_heal")
			check(not option.is_empty() and bool(option.get("disabled", false)) == (version == 11), "Only v11 refuses to charge when the free meal heals the same missing life")
			if version == 11:
				var before := run.snapshot()
				check(not str(option.get("reason", "")).is_empty() and not run.choose("feast_heal") and run.snapshot() == before, "The no-benefit Feast has an explanation and cannot spend gold")
			var free := ceili(maximum * 0.15)
			run.health = maximum - free
			check(bool(_option(run, "feast_heal").get("disabled", false)) == (version == 11), "The exact free-meal recovery boundary is protected")
			run.health -= 1
			check(not bool(_option(run, "feast_heal").get("disabled", false)), "The paid Feast remains available as soon as it restores additional life")
			var gold := run.gold
			check(run.choose("feast_heal") and run.gold == gold - 25 and run.health == maximum, "A useful Feast charges its unchanged price and applies the advertised healing")
			report.feast_states += 1

func _level_caps(source: ELProfile) -> void:
	for version in [10, 11]:
		var run := _event(source, 11, version)
		if run == null: continue
		run.preset = run.preset.duplicate(true)
		run.preset.level = 16
		check(int(run.battle_preview().level) == 20, "Controlled maximum-level fixture reaches the actual combat cap")
		check(bool(_option(run, "feast_prepare").get("disabled", false)) == (version == 11), "Only v11 disables no-benefit Feast provisions at level 20")
		for room: Dictionary in run._route[5]:
			if room.kind != "shop": continue
			_at(run, room)
			run._prepare_shop()
			var option := _option(run, "shop_prepare")
			check(bool(option.get("disabled", false)) == (version == 11), "Merchant provisions have the same versioned maximum-level guard")
			if version == 11:
				var before := run.snapshot()
				check(not run.choose("shop_prepare") and run.snapshot() == before, "Rejected capped provisions spend neither gold nor merchant service")
			run.preset.level = 15
			check(not bool(_option(run, "shop_prepare").get("disabled", false)), "Level-19 heroes can still buy the useful final provision level")
			break

func _legacy_comparison(source: ELProfile, seeds: int) -> void:
	var path := _argument("baseline")
	if path.is_empty():
		report.legacy_baseline = "Not supplied; versioned predicates were checked, but no external-source comparison was requested."
		return
	var script := GDScript.new()
	# The anonymous copy keeps the original methods without registering a
	# second global ELExpeditionRun class. No baseline file is modified.
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name ELExpeditionRun\n", "")
	check(script.reload() == OK, "Frozen v10 source compiles as a read-only anonymous comparison model")
	if not script.can_instantiate(): return
	for seed_value in seeds:
		for chapter in range(1, 4):
			var run := _new(source, seed_value, 10, chapter)
			var legacy = script.new()
			check(legacy.create(source, "ExpeditionFixtureRed", seed_value, 10), "Frozen baseline creates its original v10 state")
			legacy.choose("relic:amber_seed")
			legacy.choose("study:none")
			legacy._reset(source, legacy.preset, seed_value, chapter)
			legacy.health = legacy.max_health
			legacy.gold = 999
			check(JSON.stringify(run.route()) == JSON.stringify(legacy.route()), "Version 10 preserves the frozen route and event bag for seed %d act %d" % [seed_value, chapter])
			for room: Dictionary in run._nodes.values():
				_at(run, room)
				legacy._clear_room_state()
				legacy.current = room.id
				legacy.visited.assign([String(room.id)])
				legacy.phase = String(room.kind)
				if room.kind == "shop" or (room.kind == "boss" and chapter == 3):
					if room.kind == "boss":
						run.phase = "haven"
						legacy.phase = "haven"
					run._prepare_shop()
					legacy._prepare_shop()
					check(run._shop_stock == legacy._shop_stock and run._shop_relic == legacy._shop_relic, "Version 10 preserves frozen merchant spells and relics")
				else:
					check(run._offered_cards() == legacy._offered_cards() and run._relic_offers(3) == legacy._relic_offers(3), "Version 10 preserves frozen seeded spell and relic offers")
				report.legacy_comparisons += 1
	check(int(report.legacy_comparisons) == seeds * 3 * 22, "Every sampled v10 room matched its frozen offer source")
	report.legacy_baseline = path
