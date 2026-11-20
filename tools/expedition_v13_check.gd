extends "expedition_v12_check.gd"
## Version 13 acquisition, preparation, and exact checkpoint continuation.
## Synthetic maps exercise the real run API; forced victories set up states
## only. Printed spell rows come from the independently exported wiki fixture.
## This script never reads or writes the player's Expedition checkpoint.

const V13 := 13
const V13_ROOT := "user://expedition_v13_check"
var powers_acquired := 0
var resumed_duels := 0

func _run() -> void:
	var source := Fixture.profile_at(V13_ROOT)
	check(source != null, "Version 13 synthetic route fixture is available")
	if source != null:
		_frozen_v12(source)
		if _power_rows(source):
			_boundaries(source)
			_acquisition_and_preparation(source)
			_two_guardian_powers(source)
			_reject_power_saves(source)
			_effective_hero(source)
			_exact_battle_resume(source)
	var output := _argument("output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		check(file != null, "Version 13 result file opens")
		if file != null: file.store_string(JSON.stringify({"rules": V13, "checks": checks, "failures": failures,
			"legacy_rooms": legacy_rooms, "legacy_stages": legacy_stages, "powers_acquired": powers_acquired,
			"resumed_duels": resumed_duels, "baseline": _argument("baseline"),
			"assumptions": ["Real run and duel APIs with synthetic route maps and wiki-exported power rows.",
				"Forced victories are lifecycle setup, not combat balance evidence.",
				"Concentration metadata is explicitly added from wiki skill-conc; effects run through the real engine."]}, "\t", true, true))
	Fixture.clean(V13_ROOT)
	print("EXPEDITION VERSION 13: %d checks, %d failure(s); %d frozen-v12 rooms, %d acquired powers, %d resumed duels" % [checks, failures.size(), legacy_rooms, powers_acquired, resumed_duels])
	quit(0 if failures.is_empty() else 1)

func _fresh(source: ELProfile, faction := "Red", seed_value := 12345) -> ELExpeditionRun:
	return _new(source, seed_value, V13, faction)

func _power_rows(source: ELProfile) -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_argument("fixture")))
	check(data is Dictionary and data.get("el2") is Dictionary, "Printed power fixture loads")
	if data is not Dictionary or data.get("el2") is not Dictionary: return false
	for row: Dictionary in ELExpeditionAttunements.catalog(source):
		if str(row.card).is_empty(): continue
		check(data.el2.CombatSpells.has(row.card), "Printed spell data includes " + str(row.card))
		if not data.el2.CombatSpells.has(row.card): return false
		source.tables.CombatSpells[row.card] = data.el2.CombatSpells[row.card].duplicate(true)
	for rank in 3:
		source.tables.HeroesSkills["CONC" + str(rank + 1)] = {"Code": "CONC", "Level": rank + 1, "Name": "Concentration", "Duel": "True"}
	return true

func _boundaries(source: ELProfile) -> void:
	var latest := ELExpeditionRun.new()
	check(latest.create(source, "ExpeditionFixtureRed", 431, V13) and latest.attuned() and int(latest.snapshot().version) == V13, "Explicit rules 13 retain their original identity")
	for version in range(1, 13):
		var run := ELExpeditionRun.new()
		check(run.create(source, "ExpeditionFixtureRed", 431, version), "Create preserved rules %d" % version)
		check(not run.attuned() and run.active_powers().is_empty() and run.ability_details().is_empty() and not run.snapshot().has("inactive_powers"), "Rules %d do not gain power state" % version)
	var run := _fresh(source)
	check(run.attuned() and run.snapshot().get("inactive_powers") == [] and run.active_powers().is_empty(), "New rules begin with no free power")
	check(run._keystone_offers().size() == 3, "New major reward still has three offers")
	var before := run.snapshot()
	var hero := run.hero_details()
	hero.cards.clear()
	hero.skills.clear()
	check(run.snapshot() == before and not run.hero_details().cards.is_empty() and not run.hero_details().skills.is_empty(), "Hero inspection cannot mutate run or preset")
	# Rendering this learned power must explain the missing active-book pair,
	# without discarding ownership or pretending the enchantment is disabled.
	run.keystones.assign(["power_transfer_aspects"])
	check(run.ability_details()[0].prepared and run.ability_details()[0].has("readiness") and run.battle_preview().ability_lines.size() == 2, "Transfer Aspects warns when the active book cannot supply both planes")
	run.inactive_powers.assign(["power_transfer_aspects"])
	check(not run.ability_details()[0].has("readiness") and run.battle_preview().ability_lines.size() == 1, "A dormant aspect power does not request targets for the next duel")

func _acquisition_and_preparation(source: ELProfile) -> void:
	for faction: String in ["Red", "Green", "Blue", "Black"]:
		for seed_value in 4:
			var run := _enter(source, "boss", seed_value, 1, V13, -1, faction)
			check(run != null and _win_current(run) != null and run.phase == "keystone_reward", faction + ": guardian reaches its major reward")
			if run == null or run.phase != "keystone_reward": continue
			var offers := run.choices()
			var powers: Array[Dictionary] = []
			for offer: Dictionary in offers:
				if offer.has("ability"): powers.append(offer)
			check(powers.size() == 2 and offers.size() == 4 and _distinct(run._keystone_offers()), faction + ": two distinct combat plans compete with one keystone and supplies")
			if powers.size() != 2: continue
			var restored := _restore_equal(run, faction + ": unclaimed guardian powers survive reload")
			check(restored != null and restored.choices() == offers, faction + ": reward cannot reroll on reload")
			var selected: Dictionary = powers[seed_value % 2]
			var id := str(selected.ability)
			var detail := ELExpeditionAttunements.find(source, id)
			check(detail.faction in [faction, "Colorless"] and not str(detail.description).is_empty() and not str(detail.source).is_empty(), faction + ": chosen power matches race and explains its source")
			check(run.choose(str(selected.id)) and run.phase == "reward" and run.keystones == [id] and run.active_powers() == [id] and run._keystone_claimed == [1], faction + ": a power consumes one guardian reward exactly once")
			powers_acquired += 1
			var once := run.snapshot()
			check(not run.choose(str(selected.id)) and run.snapshot() == once, faction + ": repeated reward click is rejected")
			check(run.choose("skip") and run.act == 2 and run.phase == "map" and run.active_powers() == [id], faction + ": learned power crosses the act boundary")
			var camp_path := _path(run, "rest")
			check(not camp_path.is_empty() and run.choose_node(camp_path[0]), faction + ": enter an actual powered battle on a route to camp")
			var duel := run.build_battle()
			check(duel != null, faction + ": opening power builds with the original enemy setup: " + id + " " + run.error)
			if duel == null: continue
			check(duel.setup.get(ELExpeditionAttunements.OPENING_MARKER) == [id] and duel.heroes[0].skills == run.hero_details().skills, faction + ": checkpoint records the exact prepared plan")
			check(duel.heroes[0].deck == run.deck and duel.heroes[0].spell_uses.all(func(value: int) -> bool: return value == run.charges_per_page()), faction + ": power does not create pages or extra charges")
			if not str(detail.card).is_empty():
				check(duel.heroes[0].enchantments.any(func(e: Dictionary) -> bool: return e.card == detail.card), faction + ": ordinary opening enchantment is present")
				# A saved position after dispelling must not recreate the ward.
				duel.heroes[0].enchantments.clear()
			run._battle_checkpoint = duel.snapshot()
			restored = _restore_equal(run, faction + ": exact powered battle restores after a ward is removed")
			if restored == null: continue
			var resumed := restored.build_battle()
			check(resumed != null and resumed.snapshot() == duel.snapshot(), faction + ": resume never reapplies an opening effect")
			if resumed == null: continue
			resumed_duels += 1
			for step in 4:
				check(duel.end_phase() == resumed.end_phase() and duel.snapshot() == resumed.snapshot(), faction + ": continuation keeps RNG and draws identical %d" % step)
			check(_settle(run) and _travel(run, "rest"), faction + ": reach camp through normal route transitions")
			if run.phase != "rest": continue
			var camp := run.snapshot()
			check(run.choose("suppress_power:" + id) and run.phase == "rest" and run.inactive_powers == [id] and run.active_powers().is_empty(), faction + ": set aside a learned power at camp")
			check(run.gold == int(camp.gold) and run.health == int(camp.health) and run._last_outcome == camp.last_outcome and run._prepared == bool(camp.prepared), faction + ": power preparation is free and does not spend the camp action")
			_restore_equal(run, faction + ": dormant power persists")
			once = run.snapshot()
			check(not run.choose("suppress_power:" + id) and run.snapshot() == once, faction + ": a stale toggle cannot change ownership")
			check(run.choose("prepare_power:" + id) and run.phase == "rest" and run.active_powers() == [id], faction + ": prepare the same power again without consuming camp")
			_reserve_pair(run)
			check(run.choose("swap_select:0"), faction + ": start a reserve swap alongside prepared power")
			once = run.snapshot()
			check(not run.choose("suppress_power:" + id) and run.snapshot() == once, faction + ": a pending page selection isolates its choices")
			check(run.choose("back") and run.choose("forage") and run.phase == "map", faction + ": the main camp action remains usable after toggling")
			once = run.snapshot()
			check(not run.choose("suppress_power:" + id) and run.snapshot() == once, faction + ": powers cannot be changed on the route")
			check(_travel(run, "boss") and _settle(run) and run.act == 3 and _travel(run, "boss") and run.phase == "haven", faction + ": reach the final preparation room with the learned power")
			if run.phase != "haven": continue
			var stock := run._shop_stock.duplicate()
			check(run.choose("suppress_power:" + id) and run.phase == "haven" and run._shop_stock == stock and "reserve_swap" not in run._shop_bought, faction + ": Haven power preparation preserves its merchant stock")
			_restore_equal(run, faction + ": final preparation restores with a dormant power")
			check(run.choose("enter_guardian"), faction + ": dormant power does not block the final duel")
			duel = run.build_battle()
			check(duel != null and duel.setup.get(ELExpeditionAttunements.OPENING_MARKER) == [], faction + ": a set-aside power is not attached to the final duel")

func _owned_power(source: ELProfile, faction := "Black", desired := "power_data_attraction") -> ELExpeditionRun:
	for seed_value in 32:
		var run := _enter(source, "boss", seed_value, 1, V13, -1, faction)
		if run == null or _win_current(run) == null: continue
		if _option(run, "keystone:" + desired).is_empty(): continue
		if run.choose("keystone:" + desired) and run.choose("skip"): return run
	return null

func _two_guardian_powers(source: ELProfile) -> void:
	for entry: Array in [["Red", "power_burnout"], ["Green", "power_ether_feeding"], ["Blue", "power_concentration"], ["Black", "power_data_attraction"]]:
		var run := _owned_power(source, str(entry[0]), str(entry[1]))
		check(run != null, "Acquire the first power for a two-guardian build: " + str(entry[0]))
		if run == null: continue
		check(_travel(run, "boss") and _win_current(run) != null and run.phase == "keystone_reward", "A powered run reaches its second guardian reward")
		if run.phase != "keystone_reward": continue
		var second := ""
		for option: Dictionary in run.choices():
			if option.has("ability"):
				check(str(option.ability) not in run.keystones, "The second guardian never repeats an owned power")
				second = str(option.id)
		check(not second.is_empty() and run.choose(second) and run.choose("skip") and run.act == 3 and run.keystones.size() == 2 and run._keystone_claimed == [1, 2], "Two powers consume exactly the two available guardian rewards")
		_restore_equal(run, "Both guardian powers survive the next-act checkpoint")
		check(run.choose_node(run.available()[0]), "Enter the final act with two prepared powers")
		var duel := run.build_battle()
		check(duel != null and duel.setup.get(ELExpeditionAttunements.OPENING_MARKER) == run.active_powers() and run.active_powers().size() == 2, "Both acquired effects initialize together")
		if duel == null: continue
		run._battle_checkpoint = duel.snapshot()
		var restored := _roundtrip(run)
		check(restored != null and restored.build_battle().snapshot() == duel.snapshot(), "Two-effect battle resumes without duplication")
		var raw := run.snapshot()
		raw.keystones.append("blood_crown")
		_reject(run, raw, "A checkpoint cannot add a third major reward")

func _reject_power_saves(source: ELProfile) -> void:
	var run := _owned_power(source)
	check(run != null, "Reach a legitimate Data Attraction ownership checkpoint")
	if run == null: return
	for value: Variant in [null, 2, {}, ["missing"], ["power_burnout"], ["blood_crown"], ["power_data_attraction", "power_data_attraction"]]:
		var raw := run.snapshot()
		raw.inactive_powers = value
		_reject(run, raw, "Malformed dormant-power state is rejected atomically: " + str(value))
	var raw := run.snapshot()
	raw.erase("inactive_powers")
	_reject(run, raw, "Version 13 requires explicit preparation state")
	raw = run.snapshot()
	raw.version = V12
	_reject(run, raw, "Older rules cannot acquire new power IDs")
	raw = run.snapshot()
	raw.keystones = ["power_burnout"]
	_reject(run, raw, "Wrong-faction ownership is rejected")
	raw = run.snapshot()
	raw.keystones = ["power_data_attraction", "power_data_attraction"]
	_reject(run, raw, "Duplicate learned powers are rejected")
	check(run.choose_node(run.available()[0]), "Enter a battle for power identity checks")
	var duel := run.build_battle()
	check(duel != null, "Build identity-check battle")
	if duel == null: return
	run._battle_checkpoint = duel.snapshot()
	for marker: Variant in [null, [], ["power_second_birth"], "power_data_attraction"]:
		raw = run.snapshot()
		raw.battle.setup[ELExpeditionAttunements.OPENING_MARKER] = marker
		_reject(run, raw, "A forged opening marker cannot replace the battle checkpoint")
	raw = run.snapshot()
	raw.inactive_powers = ["power_data_attraction"]
	_reject(run, raw, "A battle checkpoint cannot be rebound to a different power loadout")
	raw = run.snapshot()
	raw.battle.heroes[0].skills.CONC = 1
	_reject(run, raw, "A saved duel cannot add an unearned skill")

func _effective_hero(source: ELProfile) -> void:
	var run := _owned_power(source, "Blue", "power_concentration")
	check(run != null, "Reach a legitimate Concentration checkpoint")
	if run == null: return
	check(int(run.hero_details().skills.get("CONC", -1)) == 1 and not run._starting_skills().has("CONC"), "Concentration is a prepared skill without mutating the starter")
	check(_travel(run, "rest") and run.choose("suppress_power:power_concentration"), "Concentration can be set aside at camp: " + run.error)
	check(not run.hero_details().skills.has("CONC"), "Dormant Concentration restores the original skill plan")
	check(run.choose("prepare_power:power_concentration"), "Concentration can be prepared again")
	var before := run.snapshot()
	for detail: Dictionary in run.ability_details():
		detail.description = "changed inspection copy"
	check(run.snapshot() == before and str(run.ability_details()[0].description) != "changed inspection copy", "Power inspection cannot alter owned effects")
	var starting: Dictionary = run.preset.skills.duplicate()
	run.preset.skills["CONC"] = 2
	check(int(run.hero_details().skills.CONC) == 2 and "power_concentration" not in run._keystone_offers(), "A stronger existing skill is neither downgraded nor offered again")
	run.preset.skills = starting

func _frozen_v12(source: ELProfile) -> void:
	var path := _argument("baseline")
	if path.is_empty():
		print("Frozen v12 comparison omitted: pass --baseline=/path/to/v12/run.gd.")
		return
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name ELExpeditionRun\n", "")
	check(script.reload() == OK and script.can_instantiate(), "Frozen v12 core loads read only as an anonymous model")
	if not script.can_instantiate(): return
	var seeds := clampi(int(_argument("seeds", "16")), 1, 64)
	for seed_value in seeds:
		for chapter in range(1, 4):
			var left := _new(source, seed_value, V12)
			var right: Variant = script.new()
			check(right.create(source, "ExpeditionFixtureRed", seed_value, V12) and right.choose("relic:amber_seed") and right.choose("study:none"), "Frozen v12 creates its original opening")
			for run: Variant in [left, right]:
				run._reset(source, run.preset, seed_value, chapter)
				run.health = run.max_health
				run.gold = 999
			check(left.route() == right.route(), "Rules 12 preserve frozen routes, event assignments and seeds")
			for room: Dictionary in left._nodes.values():
				_legacy_at(left, room, chapter)
				_legacy_at(right, room, chapter)
				check(left.choices() == right.choices() and left.room_summary() == right.room_summary() and left._offered_cards() == right._offered_cards() and left._relic_offers(3) == right._relic_offers(3) and left._shop_stock == right._shop_stock and left._shop_relic == right._shop_relic, "Rules 12 room %s seed %d matches frozen choices and offers" % [room.id, seed_value])
				legacy_rooms += 1
	for kind: String in ["rest", "haven", "library", "mirror", "forge", "anvil", "cartographer", "reward"]:
		var left: ELExpeditionRun
		match kind:
			"rest": left = _enter(source, "rest", 12345, 1, V12)
			"haven": left = _enter(source, "boss", 12345, 3, V12)
			"library": left = _event(source, ELExpeditionRun.LIBRARY_EVENT, 1, V12)
			"mirror": left = _event(source, 1, 1, V12)
			"forge": left = _event(source, 7, 1, V12)
			"anvil": left = _event(source, ELExpeditionRun.ANVIL_EVENT, 1, V12)
			"cartographer": left = _event(source, 8, 1, V12)
			"reward":
				left = _new(source, 12345, V12)
				left.choose_node(left.available()[0])
				_win_current(left)
		if left == null:
			check(false, "Reach rules 12 " + kind + " comparison checkpoint")
			continue
		left.gold = 200
		if kind in ["rest", "haven"]: _reserve_pair(left)
		var right: Variant = script.new()
		check(right.restore_snapshot(source, _json(left.snapshot())), "Frozen v12 restores current rules 12 " + kind)
		_legacy_equal(left, right, "Rules 12 " + kind + " initial state matches frozen behavior")
		var select := ""
		match kind:
			"rest", "haven": select = "swap_select:0"
			"library": select = str(_option(left, "library_card:").id)
			"mirror", "forge", "anvil": select = str(_option(left, "craft_select:").id)
			"cartographer": select = "cartographer_help"
			"reward": select = str(_option(left, "card:").id)
		check(left.choose(select) and right.choose(select), "Both rules 12 models accept " + kind + " selection")
		_legacy_equal(left, right, "Rules 12 " + kind + " selection matches frozen behavior")
		if kind == "cartographer": continue
		var restored: Variant = script.new()
		check(restored.restore_snapshot(source, _json(left.snapshot())) and restored.snapshot() == right.snapshot() and restored.choices() == right.choices(), "Frozen v12 resumes the exact current pending " + kind)
		var action := ""
		match kind:
			"rest", "haven": action = str(_option(left, "swap_with:").id)
			"library": action = "reserve_add"
			"mirror", "forge", "anvil": action = str(_option(left, "craft:").id)
			"reward": action = "add"
		check(left.choose(action) and right.choose(action), "Both rules 12 models commit " + kind + " once")
		_legacy_equal(left, right, "Rules 12 " + kind + " completion and receipt match the frozen release")
	check(legacy_rooms == seeds * 3 * 22 and legacy_stages == 23, "All frozen v12 rooms and selection/completion stages executed")
