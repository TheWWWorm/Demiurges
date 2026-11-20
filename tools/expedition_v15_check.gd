extends "expedition_v14_check.gd"
## Real run/duel/save APIs with synthetic route maps and hero metadata.
## Six recipe spell rows come from the printed wiki fixture. Forced wins
## only reach checkpoints; no campaign or combat win-rate claim is made.
## Never calls persist/save_battle or reads the player's checkpoint.
## --fixture=/path/to/fixture.json --baseline=/path/to/v14/run.gd --output=/tmp/v15.json

const V15 := 15
const V15_ROOT := "user://expedition_v15_check"
const RECIPE_IDS := ["mndp", "unsm", "repr", "prfy", "enlh", "aslt"]
var sections: Array[String] = []
var project_cases := 0
var elite_cases := 0
var live_uses := 0
var saved_duels := 0
var corruptions := 0
var bound_cases := 0
var optional_bound_cases := 0
var useful_detours := 0
var camp_detours := 0
var prices: Array[Dictionary] = []

func _run() -> void:
	var began := Time.get_ticks_msec()
	var source := Fixture.profile_at(V15_ROOT)
	check(source != null, "Rules 15 synthetic route fixture is available")
	if source != null and _recipe_rows(source):
		_fields_boundary(source)
		_constructor_projects(source)
		_camp_completion(source)
		_paid_services(source)
		_elite_devices(source)
		_reliquary_recharge(source)
		_carried_charge_lifecycle(source)
		_slots_and_shared_uses(source)
		_reject_field_saves(source)
		_remaining_opportunities(source)
		_frozen_legacy(source)
	check(sections.size() == 11, "All eleven rules 15 sections completed without an aborted subtest")
	check(project_cases >= 4 and elite_cases == 3 and live_uses >= 4 and saved_duels >= 2, "Project, elite and actual charge lifecycle coverage gates completed")
	check(corruptions >= 35 and bound_cases >= 1000 and optional_bound_cases > 0 and useful_detours > 0 and camp_detours > 0, "Corruption and reachable-opportunity coverage gates completed")
	var legacy_seeds := clampi(int(_argument("seeds", "4")), 1, 16)
	check(legacy_rooms == 777 + legacy_seeds * 264 and legacy_stages >= 18, "All frozen v1–14 room and pending-stage comparisons completed")
	check(checks >= 1200, "The integration suite met its minimum assertion count")
	var output := _argument("output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		check(file != null, "Rules 15 result file opens")
		if file != null:
			file.store_string(JSON.stringify({"rules": V15, "checks": checks, "failures": failures,
				"sections": sections, "project_cases": project_cases, "elite_cases": elite_cases,
				"actual_artifact_uses": live_uses, "resumed_duels": saved_duels, "corruptions": corruptions,
				"bound_cases": bound_cases, "optional_bound_cases": optional_bound_cases,
				"useful_detours": useful_detours, "camp_detours": camp_detours,
				"legacy_rooms": legacy_rooms, "legacy_stages": legacy_stages, "prices": prices,
				"baseline": _argument("baseline"), "elapsed_ms": Time.get_ticks_msec() - began,
				"assumptions": ["Real run choices, artifact activations and exact JSON checkpoints; synthetic route maps and hero metadata.",
					"Six artifact spell rows come from the printed wiki fixture; deterministic ARTF metadata tests conservation, not original specialization probabilities.",
					"Forced combat outcomes reach lifecycle checkpoints; these are not AI-duel or whole-run expected-value estimates.",
					"Capacity, corruption and recharge matrices explicitly arrange legal inventory/health/gold states on reachable routes.",
					"Opportunity checks independently enumerate generated connections, optional duels and Compass detours.",
					"Frozen v14 core uses current shared helper modules; earlier rule branches must retain their original behavior."]}, "\t", true, true))
	Fixture.clean(V15_ROOT)
	print("EXPEDITION VERSION 15: %d checks, %d failure(s); %d legacy rooms, %d live artifact uses, %d resumed duels, %d opportunity cases" % [checks, failures.size(), legacy_rooms, live_uses, saved_duels, bound_cases])
	quit(0 if failures.is_empty() else 1)

func _fresh(source: ELProfile, faction := "Red", seed_value := 12345) -> ELExpeditionRun:
	return _new(source, seed_value, V15, faction)

func _recipe_rows(source: ELProfile) -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_argument("fixture")))
	check(raw is Dictionary and raw.get("el2") is Dictionary, "Printed recipe fixture loads")
	if raw is not Dictionary or raw.get("el2") is not Dictionary: return false
	for detail: Dictionary in ELExpeditionArtifacts.catalog(source):
		var code := str(detail.card)
		check(raw.el2.CombatSpells.has(code), "Printed fixture includes recipe " + code)
		if not raw.el2.CombatSpells.has(code): return false
		source.tables.CombatSpells[code] = raw.el2.CombatSpells[code].duplicate(true)
	for rank in 3:
		source.tables.HeroesSkills["ARTF" + str(rank + 1)] = {"Code": "ARTF", "Level": rank + 1, "Name": "Artificer", "Duel": "True"}
	check(ELExpeditionArtifacts.available(source).size() == 6, "All six printed recipes are usable")
	return ELExpeditionArtifacts.available(source).size() == 6

func _exact(run: ELExpeditionRun, id: String) -> Dictionary:
	for option: Dictionary in run.choices():
		if str(option.id) == id: return option
	return {}

func _enabled(run: ELExpeditionRun, id: String) -> bool:
	var option := _exact(run, id)
	return not option.is_empty() and not bool(option.get("disabled", false))

func _rejected_action(run: ELExpeditionRun, id: String, label: String) -> void:
	var before := run.snapshot()
	check(not run.choose(id) and run.snapshot() == before, label)

func _equip(run: ELExpeditionRun, recipe := "mndp", charges := 1, project := "") -> void:
	run.field_artifact = recipe
	run.field_charges = charges
	run.artifact_project = project

func _bad_field_save(run: ELExpeditionRun, raw: Dictionary, label: String) -> void:
	corruptions += 1
	_reject(run, raw, label)

func _fields_boundary(source: ELProfile) -> void:
	var run := ELExpeditionRun.new()
	check(run.create(source, "ExpeditionFixtureRed", 431) and run.implements_enabled() and int(run.snapshot().version) == V15, "Default creation selects rules 15")
	check(run.field_artifact.is_empty() and run.field_charges == 0 and run.artifact_project.is_empty() and run.field_artifact_details().is_empty() and run.artifact_project_details().is_empty(), "No free starting project or charged device")
	for key: String in ["field_artifact", "field_charges", "artifact_project"]:
		var raw := run.snapshot()
		raw.erase(key)
		_bad_field_save(run, raw, "Rules 15 require saved field " + key)
	var raw := run.snapshot()
	raw.field_artifact = "mndp"
	raw.field_charges = 2
	_bad_field_save(run, raw, "Starting gift cannot contain a forged finished device")
	raw = run.snapshot()
	raw.artifact_project = "mndp"
	_bad_field_save(run, raw, "Starting gift cannot contain a forged project")
	for version in range(1, V15):
		var old := _new(source, 431, version)
		check(old != null and not old.implements_enabled(), "Rules %d keep implements disabled" % version)
		if old == null: continue
		check(not old.snapshot().has("field_artifact") and not old.snapshot().has("field_charges") and not old.snapshot().has("artifact_project"), "Rules %d retain their save shape" % version)
		check(old._nodes.values().all(func(room: Dictionary) -> bool: return int(room.get("event", -1)) != 18), "Rules %d cannot acquire Constructor event 18" % version)
		check(old.field_artifact_details().is_empty() and old.artifact_project_details().is_empty(), "Rules %d expose no new equipment inspection" % version)
	sections.append("version boundary")

func _constructor_projects(source: ELProfile) -> void:
	var run := _event(source, 18, 1, V15)
	check(run != null, "Reach an Act I Constructor through real route choices")
	if run == null: return
	var options: Array[Dictionary] = []
	for offer: Dictionary in run.choices():
		if str(offer.id).begins_with("project:"): options.append(offer)
	check(options.size() == 3, "Constructor offers three distinct recipes")
	if options.is_empty(): return
	var seen: Array[String] = []
	for offer: Dictionary in options:
		check(offer.get("field_recipe") in RECIPE_IDS and str(offer.field_recipe) not in seen and str(offer.get("artifact_action")) == "project" and str(offer.get("card", "")).is_empty(), "Project metadata is distinct and not a fake card reward")
		seen.append(str(offer.field_recipe))
	_restore_equal(run, "Unclaimed Constructor offers survive JSON reload")
	var before := run.snapshot()
	var initial := str(options[0].field_recipe)
	check(run.choose(str(options[0].id)) and run.phase == "map" and run.artifact_project == initial and run.field_artifact.is_empty() and run.field_charges == 0, "Taking a project grants only unfinished work and ends the encounter")
	check(run.gold == int(before.gold) and run.health == int(before.health) and run.deck == before.deck, "Project selection creates no gold, pages or life")
	check(not run.artifact_project_details().is_empty() and run.hero_details().get("artifacts", []).is_empty(), "Unfinished work is described but absent from combat")
	_restore_equal(run, "Carried unfinished project restores exactly")
	_rejected_action(run, str(options[0].id), "Constructor cannot be claimed twice")
	project_cases += 1
	var salvage := _event(source, 18, 1, V15)
	if salvage == null:
		check(false, "Reach Constructor salvage branch")
		return
	_equip(salvage, "mndp", 1, "unsm")
	before = salvage.snapshot()
	check(salvage.choose("constructor_salvage") and salvage.gold == int(before.gold) + 12 and salvage.phase == "map" and salvage.field_artifact == "mndp" and salvage.field_charges == 1 and salvage.artifact_project == "unsm", "Salvage pays twelve once and preserves existing work and equipment")
	_restore_equal(salvage, "Salvage receipt with carried work restores")
	_rejected_action(salvage, "constructor_salvage", "Salvage cannot be replayed")
	var replacement := _event(source, 18, 1, V15)
	if replacement == null:
		check(false, "Reach Constructor replacement state")
		return
	_equip(replacement, "mndp", 1, "unsm")
	var pick := _option(replacement, "project:")
	check(not pick.is_empty() and pick.field_recipe not in ["mndp", "unsm"], "Identical equipment and project are excluded from new plans")
	if pick.is_empty(): return
	check(replacement.choose(str(pick.id)) and replacement.artifact_project == pick.field_recipe and replacement.field_artifact == "mndp" and replacement.field_charges == 1, "Replacing a project retains the usable old implement")
	_restore_equal(replacement, "Replacement project and old implement restore together")
	project_cases += 1
	sections.append("constructor")

func _camp_completion(source: ELProfile) -> void:
	var run: ELExpeditionRun
	for seed_value in 128:
		var candidate := _enter(source, "event", seed_value, 1, V15, 18)
		if candidate == null: continue
		var pick := _option(candidate, "project:")
		if pick.is_empty() or not candidate.choose(str(pick.id)) or _path(candidate, "rest").is_empty(): continue
		run = candidate
		break
	check(run != null, "Find a generated Constructor with a later reachable camp")
	if run == null: return
	var recipe := run.artifact_project
	var old := "unsm" if recipe == "mndp" else "mndp"
	_equip(run, old, 1, recipe)
	check(_travel(run, "rest"), "Carry an acquired project to camp through actual route transitions")
	if run.phase != "rest": return
	var before := run.snapshot()
	var offer := _exact(run, "complete_project")
	check(not offer.is_empty() and offer.get("field_recipe") == recipe and offer.get("artifact_action") == "complete" and not offer.has("cost"), "Camp completion identifies the recipe and costs no gold")
	check(run.choose("complete_project") and run.phase == "map" and run.field_artifact == recipe and run.field_charges == 2 and run.artifact_project.is_empty(), "Camp completion replaces equipment at commit and consumes the main action")
	check(run.gold == int(before.gold) and run.health == int(before.health) and run.deck == before.deck, "Camp assembly gives no healing, forage gold or pages")
	check(run._last_outcome.get("field_artifact_before") == old and run._last_outcome.get("field_artifact_after") == recipe and int(run._last_outcome.get("field_charges_after", -1)) == 2 and run._last_outcome.get("artifact_project_after") == "", "Assembly receipt names replacement, charges and consumed project")
	_restore_equal(run, "Completed camp artifact and receipt restore")
	_rejected_action(run, "complete_project", "Camp completion cannot be replayed")
	_rejected_action(run, "forage", "Assembly consumes the camp's main action")
	project_cases += 1
	var recharge := _enter(source, "rest", 12345, 1, V15)
	check(recharge != null, "Reach an early recharge camp")
	if recharge == null: return
	_equip(recharge, "mndp", 0, "unsm")
	_reserve_pair(recharge)
	before = recharge.snapshot()
	check(recharge.choose("opening_select"), "Inspect another camp activity before equipment work")
	_rejected_action(recharge, "complete_project", "Pending rehearsal isolates artifact completion")
	_rejected_action(recharge, "recharge_artifact", "Pending rehearsal isolates recharging")
	check(recharge.choose("back") and recharge.snapshot() == before, "Cancel restores the exact equipment state")
	check(recharge.choose("swap_select:0"), "Begin a reserve arrangement alongside equipment")
	_rejected_action(recharge, "complete_project", "Pending reserve placement isolates completion")
	check(recharge.choose("back"), "Cancel reserve placement before recharging")
	before = recharge.snapshot()
	check(recharge.choose("recharge_artifact") and recharge.phase == "map" and recharge.field_charges == 1 and recharge.artifact_project == "unsm", "Camp recharge restores one charge and preserves unfinished work")
	check(recharge.health == int(before.health) and recharge.gold == int(before.gold) and recharge.deck == before.deck and recharge.reserve == before.reserve, "Recharge consumes the main action without unrelated rewards")
	_restore_equal(recharge, "Camp recharge receipt restores")
	_rejected_action(recharge, "recharge_artifact", "Camp cannot charge repeatedly")
	sections.append("camp services")

func _modifiers(run: ELExpeditionRun, modifier: String) -> void:
	if modifier in ["seal", "both"]: run.relics.append("merchant_seal")
	if modifier in ["heart", "both"]:
		run.keystones.assign(["living_heart"])
		run.max_health += 8
		run.health = mini(run.health, run.max_health)
	# This matrix constructs ownership before the visit's fixed stock.
	# Adding Seal after stocking it would create an impossible shop save.
	run._prepare_shop()

func _paid_services(source: ELProfile) -> void:
	for pair: Array in [["none", 28, 20], ["seal", 23, 16], ["heart", 34, 24], ["both", 27, 20]]:
		var modifier := str(pair[0])
		var haven := _enter(source, "boss", 12345, 3, V15)
		check(haven != null and haven.phase == "haven", modifier + ": reach final Haven")
		if haven == null: continue
		_modifiers(haven, modifier)
		_equip(haven, "unsm", 1, "mndp")
		haven.gold = int(pair[1]) - 1
		check(int(_exact(haven, "complete_project").get("cost", -1)) == int(pair[1]) and not _enabled(haven, "complete_project"), modifier + ": exact combined assembly price")
		_rejected_action(haven, "complete_project", modifier + ": unaffordable completion is atomic")
		haven.gold = int(pair[1])
		var before := haven.snapshot()
		check(haven.choose("complete_project") and haven.phase == "haven" and haven.gold == 0 and haven.field_artifact == "mndp" and haven.field_charges == 2 and haven.artifact_project.is_empty(), modifier + ": exact payment completes once and leaves Haven open")
		check(haven.health == int(before.health) and haven.deck == before.deck and haven.reserve == before.reserve, modifier + ": assembly changes only equipment, project and gold")
		_restore_equal(haven, modifier + ": paid assembly and receipt restore")
		_rejected_action(haven, "complete_project", modifier + ": consumed project cannot be completed twice")
		project_cases += 1
		check(not _enabled(haven, "recharge_artifact"), modifier + ": a full device cannot recharge")
		haven.field_charges = 0
		haven.gold = int(pair[2]) - 1
		check(int(_exact(haven, "recharge_artifact").get("cost", -1)) == int(pair[2]), modifier + ": independently calculated recharge price")
		_rejected_action(haven, "recharge_artifact", modifier + ": insufficient recharge payment is atomic")
		haven.gold += 1
		check(haven.choose("recharge_artifact") and haven.field_charges == 1 and haven.gold == 0 and "field_charge" in haven._shop_bought, modifier + ": merchant restores one charge and records used stock")
		_restore_equal(haven, modifier + ": charge and used merchant stock restore")
		haven.gold = 999
		_rejected_action(haven, "recharge_artifact", modifier + ": wealth cannot replay a used recharge")
		prices.append({"modifier": modifier, "completion": int(pair[1]), "recharge": int(pair[2])})
	var caravan := _event(source, 5, 1, V15)
	check(caravan != null and caravan.choose("caravan_shop"), "Open a real Caravan merchant")
	if caravan == null or caravan.phase != "shop": return
	_equip(caravan, "mndp", 0)
	caravan.gold = 100
	var card := _option(caravan, "buy_card:")
	check(not card.is_empty() and caravan.choose(str(card.id)), "A merchant card can be inspected before committing a recharge")
	_rejected_action(caravan, "recharge_artifact", "Pending merchant placement isolates equipment services")
	check(caravan.choose("back"), "Cancel card placement before charging")
	check(_enabled(caravan, "caravan_back") and caravan.choose("recharge_artifact"), "Caravan recharge commits a browsing visit")
	check(not _enabled(caravan, "caravan_back") and caravan.field_charges == 1 and caravan.gold == 80, "Recharging cannot also collect the guiding payment")
	_rejected_action(caravan, "caravan_back", "Artifact service cannot reopen the guiding branch")
	_restore_equal(caravan, "Caravan recharge remains committed after reload")
	sections.append("paid services")

func _elite_devices(source: ELProfile) -> void:
	for event_index in [-1, 4, 9]:
		var run := _enter(source, "elite", 12345, 2, V15) if event_index < 0 else _event(source, event_index, 2, V15)
		check(run != null, "Reach elite reward source %d" % event_index)
		if run == null: continue
		if event_index >= 0: check(run.choose("challenge"), "Optional event %d begins its elite duel" % event_index)
		check(_win_current(run) != null and run.phase == "relic_reward", "Elite source %d reaches its relic reward" % event_index)
		if run.phase != "relic_reward": continue
		_equip(run, "mndp", 1, "unsm")
		var offers := run.choices()
		var pick := _option(run, "claim_artifact:")
		check(not pick.is_empty() and str(pick.get("field_recipe", "")) not in ["mndp", "unsm"] and str(pick.get("artifact_action")) == "claim", "Elite source %d offers a useful completed device" % event_index)
		if pick.is_empty(): continue
		_restore_equal(run, "Unclaimed elite device remains fixed after reload")
		check(run.choices() == offers, "Inspection and reload cannot reroll an elite device")
		var before := run.snapshot()
		check(run.choose(str(pick.id)) and run.phase == "reward" and run.field_artifact == pick.field_recipe and run.field_charges == 2 and run.artifact_project == "unsm", "Elite device replaces the implement and retains a different project")
		check(run.gold == int(before.gold) and run.health == int(before.health) and run.relics == before.relics, "Device gives neither another relic nor supplies gold/healing")
		_rejected_action(run, "skip_relic", "Device consumes the relic-or-supplies reward budget")
		_rejected_action(run, str(pick.id), "Elite device cannot be claimed twice")
		check(not _option(run, "card:").is_empty(), "Ordinary spell reward remains after device acquisition")
		_restore_equal(run, "Claimed device survives the pending spell reward")
		elite_cases += 1
	var guardian := _enter(source, "boss", 12345, 1, V15)
	check(guardian != null and _win_current(guardian) != null and guardian.phase == "keystone_reward" and _option(guardian, "claim_artifact:", false).is_empty(), "Guardian major rewards never become device rewards")
	sections.append("elite alternatives")

func _reliquary_recharge(source: ELProfile) -> void:
	var source_run := _event(source, 3, 2, V15)
	check(source_run != null, "Reach the original Reliquary recharger")
	if source_run == null: return
	for amount in [1, 2]:
		var run := _roundtrip(source_run)
		if run == null: return
		_equip(run, "mndp", 0, "unsm")
		run.health = amount * 3
		var id := "recharge_artifact:%d" % amount
		check(not _enabled(run, id), "Reliquary cannot take a lethal %d-life payment" % (amount * 3))
		_rejected_action(run, id, "Lethal recharge preserves the complete snapshot")
		run.health += 1
		check(_enabled(run, id), "One life beyond the cost enables %d-charge refill" % amount)
		var before := run.snapshot()
		check(run.choose(id) and run.phase == "map" and run.field_charges == amount and run.health == 1 and run.gold == int(before.gold) and run.artifact_project == "unsm", "Reliquary spends three life per charge and ends the encounter")
		_restore_equal(run, "Reliquary charge and life receipt restore")
		_rejected_action(run, id, "Reliquary recharge cannot be replayed")
	var partial := _roundtrip(source_run)
	if partial == null: return
	_equip(partial, "mndp", 0)
	partial.health = 4
	check(_enabled(partial, "recharge_artifact:1") and not _enabled(partial, "recharge_artifact:2"), "Safe partial recharge remains available when a full refill is lethal")
	_equip(partial, "mndp", 1)
	partial.health = partial.max_health
	check(_enabled(partial, "recharge_artifact:1") and not _enabled(partial, "recharge_artifact:2"), "Reliquary cannot exceed missing storage capacity")
	_equip(partial, "mndp", 2)
	_rejected_action(partial, "recharge_artifact:1", "A full implement cannot spend life on an unused charge")
	sections.append("reliquary")

func _field_index(duel: ELDuel) -> int:
	for index in duel.heroes[0].artifacts.size():
		if str(duel.heroes[0].artifacts[index].name).begins_with(ELExpeditionArtifacts.NAME_PREFIX): return index
	return -1

func _attack_turn(duel: ELDuel, earliest := 1) -> bool:
	for step in 24:
		if duel.phase == ELDuel.Phase.ATTACK and duel.attacker == 0 and duel.artifact_round() >= earliest: return true
		if duel.phase == ELDuel.Phase.FINISHED or not duel.end_phase(): return false
	return false

func _json_duel_equal(left: ELDuel, right: ELDuel) -> bool:
	return _json(left.snapshot()) == _json(right.snapshot())

func _carried_charge_lifecycle(source: ELProfile) -> void:
	for faction: String in ["Red", "Blue"]:
		var run := _fresh(source, faction)
		_equip(run, "mndp", 2, "unsm")
		check(run.choose_node(run.available()[0]), faction + ": enter a real generated fight carrying two charges")
		var duel := run.build_battle()
		check(duel != null and _attack_turn(duel), faction + ": reach a real player attack turn")
		if duel == null: continue
		var index := _field_index(duel)
		check(index >= 0 and int(duel.heroes[0].artifacts[index].charges) == 2 and duel.artifact_limit(0) == 1, faction + ": canonical device enters with carried count and ordinary shared budget")
		if index < 0: continue
		var mana := int(duel.heroes[0].mana)
		var pages: Array = duel.heroes[0].spell_uses.duplicate()
		check(duel.use_artifact(0, index) and int(duel.heroes[0].artifacts[index].charges) == 1 and int(duel.heroes[0].mana) == mana + 2, faction + ": real activation spends one persistent charge and grants printed ether")
		live_uses += 1
		check(duel.heroes[0].spell_uses == pages and run.field_charges == 2 and run.artifact_project == "unsm", faction + ": book charges and immutable entry equipment remain unchanged during combat")
		var state := duel.snapshot()
		check(not duel.use_artifact(0, index) and duel.snapshot() == state, faction + ": shared one-use limit blocks a second activation")
		run._battle_checkpoint = duel.snapshot()
		var restored := _restore_equal(run, faction + ": checkpoint after spending a charge restores")
		if restored == null: continue
		var resumed := restored.build_battle()
		check(resumed != null and _json_duel_equal(duel, resumed) and restored.field_charges == 2, faction + ": resume preserves actual charge and frozen entry identity")
		if resumed == null: continue
		saved_duels += 1
		for step in 4:
			check(duel.end_phase() == resumed.end_phase() and _json_duel_equal(duel, resumed), faction + ": identical resumed continuation %d" % step)
		_end(resumed)
		check(restored.resolve_battle(resumed) and restored.field_charges == 1 and restored.artifact_project == "unsm", faction + ": accepted result writes remaining charge back exactly once")
		_rejected_resolution(restored, resumed, faction + ": the same finished duel cannot resolve twice")
		_restore_equal(restored, faction + ": postcombat charge count restores")
		check(_settle(restored) and _travel(restored, "fight"), faction + ": travel to another fight")
		var next := restored.build_battle()
		check(next != null, faction + ": next fight builds with the partially spent implement")
		if next == null: continue
		index = _field_index(next)
		check(index >= 0 and int(next.heroes[0].artifacts[index].charges) == 1 and int(next.heroes[0].artifacts[index].ready_round) == 1 and int(next.heroes[0].artifact_uses) == 0, faction + ": new duel preserves charges and resets cadence and shared uses")
		check(_attack_turn(next) and next.use_artifact(0, index), faction + ": spend the last stored charge through the engine")
		live_uses += 1
		_end(next)
		check(restored.resolve_battle(next) and restored.field_charges == 0 and restored.field_artifact == "mndp", faction + ": an exhausted implement remains owned without refill")
		check(_settle(restored) and _travel(restored, "boss") and _settle(restored) and restored.act == 2 and restored.field_charges == 0 and restored.artifact_project == "unsm", faction + ": act transition preserves empty equipment and unfinished work")
		_restore_equal(restored, faction + ": exhausted equipment restores across acts")
	sections.append("live charge lifecycle")

func _rejected_resolution(run: ELExpeditionRun, duel: ELDuel, label: String) -> void:
	var before := run.snapshot()
	check(not run.resolve_battle(duel) and run.snapshot() == before, label)

func _slots_and_shared_uses(source: ELProfile) -> void:
	var original: Dictionary = source.tables.DuelPresets.ExpeditionFixtureRed.duplicate(true)
	for count in [3, 4, 5]:
		source.tables.DuelPresets.ExpeditionFixtureRed.Artefacts = []
		for index in count: source.tables.DuelPresets.ExpeditionFixtureRed.Artefacts.append("RingOfHealing")
		var run := _enter(source, "rest", 12345, 1, V15)
		check(run != null, "Reach camp with %d preset artifact slots" % count)
		if run == null: continue
		run.artifact_project = "mndp"
		if count == 3: run.borrowed_artifact = "RodOfLightning"
		check(_enabled(run, "complete_project") == (count < 5), "Completion includes all carried items in the five-slot cap")
		if count < 5:
			check(run.choose("complete_project") and run.hero_details().artifacts.size() == 5, "Completing a fifth artifact retains every existing item")
			_restore_equal(run, "A full five-artifact loadout restores")
		else:
			_rejected_action(run, "complete_project", "Five permanent items block completion without discarding the project")
		source.tables.DuelPresets.ExpeditionFixtureRed = original.duplicate(true)
	source.tables.DuelPresets.ExpeditionFixtureRed.Artefacts = ["RingOfHealing", "RingOfHealing", "RingOfHealing", "RingOfHealing"]
	var reserved := _event(source, 3, 2, V15)
	check(reserved != null, "Reach Reliquary with four permanent artifact slots")
	if reserved != null:
		reserved.artifact_project = "mndp"
		check(not _enabled(reserved, "keep:RodOfLightning"), "A fifth permanent keepsake cannot strand an unfinished project")
		_rejected_action(reserved, "keep:RodOfLightning", "Unfinishable permanent-slot acquisition is rejected atomically")
	source.tables.DuelPresets.ExpeditionFixtureRed = original.duplicate(true)
	source.tables.DuelPresets.ExpeditionFixtureRed.Artefacts = ["RodOfLightning"]
	var shared := _fresh(source)
	_equip(shared, "mndp", 2)
	check(shared.choose_node(shared.available()[0]), "Enter combat carrying a preset rod and field implement")
	var shared_duel := shared.build_battle()
	check(shared_duel != null and _attack_turn(shared_duel), "Shared-budget duel reaches the player's attack")
	if shared_duel != null:
		check(shared_duel.use_artifact(0, 0, 1), "Use the preset rod through the actual artifact action")
		var field_index := _field_index(shared_duel)
		var before := shared_duel.snapshot()
		check(field_index >= 0 and not shared_duel.use_artifact(0, field_index) and shared_duel.snapshot() == before, "Using another artifact consumes the same budget and leaves both field charges intact")
		_end(shared_duel)
		check(shared.resolve_battle(shared_duel) and shared.field_charges == 2, "Other carried artifact usage does not consume the field device's charges")
	source.tables.DuelPresets.ExpeditionFixtureRed = original.duplicate(true)
	for rank in range(-1, 3):
		source.tables.DuelPresets.ExpeditionFixtureRed.Skills = ["PRVD(1)"] if rank < 0 else ["PRVD(1)", "ARTF(%d)" % (rank + 1)]
		var run := _enter(source, "boss", 12345, 3, V15)
		check(run != null, "Reach Haven with Artificer skill rank %d" % rank)
		if run == null: continue
		_equip(run, "mndp", 1)
		run.gold = 100
		var limit: int = 1 if rank < 0 else [2, 4, 8][rank]
		check(run.artifact_use_limit() == limit and _enabled(run, "recharge_artifact") == (rank >= 0), "Final-charge usefulness follows the shared Artificer use budget")
		check(run.choose("enter_guardian"), "Enter guardian after inspecting artifact allowance")
		var duel := run.build_battle()
		check(duel != null and duel.artifact_limit(0) == limit and int(duel.heroes[0].artifacts[_field_index(duel)].charges) == 1, "Run and original engine agree on activation limit without free charges")
		source.tables.DuelPresets.ExpeditionFixtureRed = original.duplicate(true)
	var old_specs: Dictionary = source.tables.get("HeroesSpecs", {}).duplicate(true)
	var old_stats: Dictionary = source.tables.HeroesStats.duplicate(true)
	source.tables.HeroesSpecs = old_specs.duplicate(true)
	source.tables.HeroesSpecs["ARTF"] = {"Chance": "High"}
	for conserved in [false, true]:
		source.tables.HeroesStats.SpecChanceHigh = {}
		for level in range(1, 21): source.tables.HeroesStats.SpecChanceHigh["Level%d" % level] = 1.0 if conserved else 0.0
		source.tables.DuelPresets.ExpeditionFixtureRed.Specialization = "ARTF"
		var run := _fresh(source)
		_equip(run, "mndp", 1)
		check(run.choose_node(run.available()[0]), "Start deterministic ARTF conservation branch")
		var duel := run.build_battle()
		check(duel != null and _attack_turn(duel), "Conservation branch reaches legal activation")
		if duel == null: continue
		var index := _field_index(duel)
		check(duel.use_artifact(0, index) and int(duel.heroes[0].artifact_uses) == 1 and int(duel.heroes[0].artifacts[index].charges) == int(conserved), "ARTF preserves or consumes charge while spending the same shared use")
		live_uses += 1
		_end(duel)
		check(run.resolve_battle(duel) and run.field_charges == int(conserved), "Write-back uses actual remaining charges, not artifact_uses")
		_restore_equal(run, "Specialization-adjusted charge restores")
		source.tables.DuelPresets.ExpeditionFixtureRed = original.duplicate(true)
	source.tables.HeroesSpecs = old_specs
	source.tables.HeroesStats = old_stats
	source.tables.DuelPresets.ExpeditionFixtureRed = original
	sections.append("slots and shared use budget")

func _reject_field_saves(source: ELProfile) -> void:
	var run := _enter(source, "rest", 12345, 1, V15)
	check(run != null, "Reach corruption-matrix checkpoint")
	if run == null: return
	_equip(run, "mndp", 1, "unsm")
	_restore_equal(run, "Legal held/project state restores before corruption")
	for key: String in ["field_artifact", "artifact_project"]:
		for value: Variant in [null, {}, [], 1, true, "unknown_recipe"]:
			var raw := run.snapshot()
			raw[key] = value
			_bad_field_save(run, raw, "Malformed " + key + " rejects atomically: " + str(value))
	for value: Variant in [null, false, "1", -1, 3, 0.5, [], {}]:
		var raw := run.snapshot()
		raw.field_charges = value
		_bad_field_save(run, raw, "Malformed field charge rejects atomically: " + str(value))
	var raw := run.snapshot()
	raw.field_artifact = ""
	_bad_field_save(run, raw, "Charges cannot exist without a held implement")
	raw = run.snapshot()
	raw.artifact_project = "mndp"
	_bad_field_save(run, raw, "Project cannot duplicate the held implement")
	check(run.choose("forage") and _travel(run, "fight"), "Enter a battle for canonical item and identity rejection")
	var duel := run.build_battle()
	check(duel != null, "Corruption test duel builds")
	if duel == null: return
	run._battle_checkpoint = duel.snapshot()
	var index := _field_index(duel)
	check(index >= 0, "Locate the reserved field item")
	if index < 0: return
	for kind: String in ["missing", "duplicate", "alien", "spell", "charge_increase", "charge_fraction", "capacity", "first", "gap", "title", "extra_custom", "project", "entry_charge"]:
		raw = run.snapshot()
		var item: Dictionary = raw.battle.heroes[0].artifacts[index]
		match kind:
			"missing": raw.battle.heroes[0].artifacts.remove_at(index)
			"duplicate": raw.battle.heroes[0].artifacts.append(item.duplicate(true))
			"alien": item.name = ELExpeditionArtifacts.NAME_PREFIX + "unsm"
			"spell": item.spell = "UNSM"
			"charge_increase": item.charges = 2
			"charge_fraction": item.charges = 0.5
			"capacity": item.custom.max = 3
			"first": item.custom.first = 0
			"gap": item.custom.gap = 0
			"title": item.custom.elk_name = "forged title"
			"extra_custom": item.custom.extra = true
			"project": raw.artifact_project = "repr"
			"entry_charge": raw.field_charges = 2
		_bad_field_save(run, raw, "Saved duel rejects field corruption: " + kind)
	var before := run.snapshot()
	var live := run.build_battle()
	check(live != null, "Original live state still builds after rejected saves")
	if live != null:
		live.heroes[0].artifacts[index].charges = 2
		_end(live)
		check(not run.resolve_battle(live) and run.snapshot() == before, "A live forged charge increase cannot commit a victory")
	var empty := _fresh(source)
	check(empty.choose_node(empty.available()[0]), "Enter ordinary battle without a field item")
	var ordinary := empty.build_battle()
	if ordinary == null:
		check(false, "Ordinary battle builds for alien item rejection")
		return
	empty._battle_checkpoint = ordinary.snapshot()
	raw = empty.snapshot()
	raw.battle.heroes[0].artifacts.append(ELExpeditionArtifacts.battle_entry(source, "mndp", 2))
	_bad_field_save(empty, raw, "Unequipped run cannot import a hidden reserved field item")
	sections.append("save atomicity")

func _exact_future(run: ELExpeditionRun, id: String, detour_used: bool, memo: Dictionary) -> Dictionary:
	var key := id + ":" + str(detour_used)
	if memo.has(key): return memo[key]
	var room: Dictionary = run._nodes[id]
	if room.kind == "boss": return {"duels": 0, "camp": false}
	var successors: Array = room.next.duplicate()
	if run._has_keystone("wayfarer_compass") and not detour_used:
		for next: Dictionary in run._route[int(room.floor)]:
			if next.id not in successors: successors.append(next.id)
	var best := 0
	var camp := false
	for next_id: String in successors:
		var next: Dictionary = run._nodes[next_id]
		var after := _exact_future(run, next_id, detour_used or next_id not in room.next, memo)
		var combat: bool = next.kind in ["fight", "elite", "boss"] or (next.kind == "event" and int(next.get("event", -1)) in [4, 9])
		best = maxi(best, int(combat) + int(after.duels))
		camp = camp or next.kind == "rest" or bool(after.camp)
	var answer := {"duels": best, "camp": camp}
	memo[key] = answer
	return answer

func _remaining_opportunities(source: ELProfile) -> void:
	for seed_value in 32:
		var run := _fresh(source, "Red", seed_value)
		run._reset(source, run.preset, seed_value, 3)
		_equip(run, "mndp", 1)
		for room: Dictionary in run._nodes.values():
			if room.kind == "boss": continue
			run.current = room.id
			run.phase = str(room.kind)
			var original_duels := 0
			var original_camp := false
			for mode: String in ["none", "available", "spent"]:
				run.keystones.clear()
				run._detours_used.clear()
				if mode != "none": run.keystones.append("wayfarer_compass")
				if mode == "spent": run._detours_used.append(3)
				var exact := _exact_future(run, str(room.id), mode == "spent", {})
				check(run._remaining_artifact_duels() == mini(2, int(exact.duels)) and run._later_camp_reachable() == bool(exact.camp), "Generated opportunities match independent path enumeration: seed %d %s %s" % [seed_value, room.id, mode])
				check(run._useful_field_charges() == mini(2, int(exact.duels)), "Ordinary stored charges cannot exceed reachable activations")
				bound_cases += 1
				if mode == "none":
					original_duels = mini(2, int(exact.duels))
					original_camp = bool(exact.camp)
				elif mode == "available":
					if mini(2, int(exact.duels)) > original_duels: useful_detours += 1
					if bool(exact.camp) and not original_camp: camp_detours += 1
				if room.kind == "event" and int(room.get("event", -1)) in [4, 9]: optional_bound_cases += 1
	for chapter in [1, 2]:
		var early := _enter(source, "boss", 12345, chapter, V15)
		check(early != null and early._remaining_artifact_duels() == 2 and early._later_camp_reachable(), "Act %d guardian leaves later battles and camp opportunities" % chapter)
	var last: ELExpeditionRun
	for seed_value in 128:
		var candidate := _enter(source, "rest", seed_value, 3, V15)
		if candidate == null: continue
		while int(candidate._nodes[candidate.current].floor) < 7:
			if not _settle(candidate) or not _travel(candidate, "rest"): break
		if candidate.phase == "rest" and int(candidate._nodes[candidate.current].floor) == 7:
			last = candidate
			break
	check(last != null, "Reach a real camp immediately before White Lord")
	if last == null: return
	_equip(last, "mndp", 1)
	check(last._useful_field_charges() == 1 and not _enabled(last, "recharge_artifact"), "Last camp cannot add an unusable second charge")
	_rejected_action(last, "recharge_artifact", "Useless final-camp recharge preserves camp action and equipment")
	last.field_charges = 0
	check(_enabled(last, "recharge_artifact"), "A missing final-duel charge remains useful")
	sections.append("remaining opportunities")

func _compare_legacy_rooms(source: ELProfile, frozen: Script, version: int, faction: String, seed_value: int) -> void:
	for chapter in range(1, 4):
		var left := _new(source, seed_value, version, faction)
		var right: Variant = frozen.new()
		if left == null: return
		check(right.create(source, "ExpeditionFixture" + faction, seed_value, version), "Frozen core creates rules %d %s" % [version, faction])
		if right.phase == "boon": right.choose("relic:amber_seed")
		if right.phase == "discipline": right.choose("study:none")
		for run: Variant in [left, right]:
			run._reset(source, run.preset, seed_value, chapter)
			run.health = run.max_health
			run.gold = 999 if run.expanded() else 0
		check(left.route() == right.route(), "Rules %d %s act %d preserve routes, event assignment and seeds" % [version, faction, chapter])
		for room: Dictionary in left._nodes.values():
			_legacy_at(left, room, chapter)
			_legacy_at(right, room, chapter)
			check(left.snapshot() == right.snapshot() and left.choices() == right.choices() and left.room_summary() == right.room_summary() and left.hero_details() == right.hero_details() and left._offered_cards() == right._offered_cards() and left._relic_offers(3) == right._relic_offers(3) and left._shop_stock == right._shop_stock and left._shop_relic == right._shop_relic, "Frozen rules %d %s seed %d room %s retain state, choices and offers" % [version, faction, seed_value, room.id])
			legacy_rooms += 1

func _frozen_legacy(source: ELProfile) -> void:
	var path := _argument("baseline")
	check(not path.is_empty() and FileAccess.file_exists(path), "A frozen final v14 core is required")
	if path.is_empty() or not FileAccess.file_exists(path): return
	var frozen := GDScript.new()
	frozen.source_code = FileAccess.get_file_as_string(path).replace("class_name ELExpeditionRun\n", "")
	check(frozen.reload() == OK and frozen.can_instantiate(), "Final v14 core loads read-only as an anonymous model")
	if not frozen.can_instantiate(): return
	for version in range(1, V15): _compare_legacy_rooms(source, frozen, version, ELDuelPresets.RACES[version % 4], 431)
	for seed_value in clampi(int(_argument("seeds", "4")), 1, 16):
		for faction: String in ELDuelPresets.RACES: _compare_legacy_rooms(source, frozen, V14, faction, seed_value)
	for kind: String in ["rest", "haven", "shrine", "caravan", "reward", "elite"]:
		var left: ELExpeditionRun
		match kind:
			"rest": left = _enter(source, "rest", 12345, 1, V14)
			"haven": left = _enter(source, "boss", 12345, 3, V14)
			"shrine": left = _event(source, 17, 1, V14)
			"caravan": left = _event(source, 5, 1, V14)
			"reward", "elite":
				left = _enter(source, "fight" if kind == "reward" else "elite", 12345, 1, V14)
				if left != null: _win_current(left)
		check(left != null, "Reach legitimate frozen v14 " + kind + " stage")
		if left == null: continue
		left.gold = 200
		var right: Variant = frozen.new()
		check(right.restore_snapshot(source, _json(left.snapshot())), "Frozen v14 restores current v14 " + kind)
		_legacy_equal(left, right, "Frozen v14 " + kind + " entry agrees")
		var first := "opening_select"
		if kind == "caravan": first = "caravan_shop"
		elif kind == "reward": first = str(_option(left, "card:").id)
		elif kind == "elite": first = str(_option(left, "relic:").id)
		check(left.choose(first) and right.choose(first), "Both v14 models take " + kind + " selection")
		_legacy_equal(left, right, "Frozen v14 " + kind + " pending selection agrees")
		var second := ""
		if kind in ["rest", "haven", "shrine"]: second = str(_option(left, "opening_spell:").id)
		elif kind == "caravan": second = "caravan_back"
		elif kind == "reward": second = "reserve_add"
		else: second = "skip"
		check(left.choose(second) and right.choose(second), "Both v14 models commit " + kind + " once")
		_legacy_equal(left, right, "Frozen v14 " + kind + " completion and receipt agree")
	sections.append("frozen v1–14")
