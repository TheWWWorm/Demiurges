extends "expedition_attunements_check.gd"
## Reuses the printed-data profile, assertions and summon helpers only.
## Isolated specialization endpoints exercise concrete effect branches, not
## claimed original chance tables. No forced winners or balance claims.
## godot --headless --path game --script ../tools/expedition_artifacts_check.gd -- \
##   --fixture=/path/to/fixture.json --output=/tmp/field-artifacts.json

const Items := preload("res://src/expedition/artifacts.gd")
var actual_uses := 0

func _run() -> void:
	var fixture_path := _arg("fixture")
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if loaded is not Dictionary or loaded.get("expedition_balance", {}).get("books") is not Dictionary:
		printerr("Supply --fixture with printed cards and recorded starter books.")
		quit(1)
		return
	fixture = loaded
	profile = DraftCheck.synthetic_profile(fixture_path)
	if profile == null:
		quit(1)
		return
	profile.tables.HeroesSpecs = {}
	for rank in 3:
		profile.tables.HeroesSkills["ARTF%d" % (rank + 1)] = {"Code": "ARTF", "Level": rank + 1, "Name": "Artificer", "Duel": "True"}
	var original := profile.tables.duplicate(true)
	var began := Time.get_ticks_msec()
	_catalog()
	_charge_validation()
	_effects()
	_rejections()
	_cooldown_and_budget()
	_attraction()
	_artificer()
	_spell_specializations()
	_native()
	_check(profile.tables == original, "Checks leave shared printed definitions unchanged")
	var report := {"complete": true, "checks": checks, "failures": failures.size(), "failure_labels": failures,
		"duel_setups": started, "save_roundtrips": roundtrips, "actual_artifact_uses": actual_uses,
		"native_available": ELCombatBrain.available, "native_decisions": native_decisions, "native": native_rows,
		"elapsed_ms": Time.get_ticks_msec() - began, "fixture": fixture_path,
		"forced_winners": 0, "complete_ai_battles": 0,
		"scope": "Printed effects, target/phase/timing/charge/save checks and bounded native decisions. Synthetic positions and income; isolated ARTF 0%/100%, BPRC 100% and CEXC 100% endpoints are mechanical branch tests, not original probabilities."}
	var output := FileAccess.open(_arg("output", "user://expedition-artifacts-check.json"), FileAccess.WRITE)
	_check(output != null, "Report file opens")
	if output != null:
		report.checks = checks
		output.store_string(JSON.stringify(report, "\t", true, true))
		output.close()
	print("FIELD ARTIFACTS: %d checks, %d failures; %d starts, %d exact saves, %d uses, %d native decisions" % [checks, failures.size(), started, roundtrips, actual_uses, native_decisions])
	ELPracticeAI.finish()
	quit(0 if failures.is_empty() else 1)

func _catalog() -> void:
	var ids := Items.available(profile)
	_check(ids == ["mndp", "unsm", "repr", "prfy", "enlh", "aslt"], "Six fixed supported recipe identities")
	_check(Items.catalog(profile).size() == 6, "Six catalog rows")
	for id: String in ids:
		var row := Items.find(profile, id)
		_check(row.title == profile.text(profile.table("CombatSpells")[row.card].Name), id + ": original printed title")
		_check(row.capacity == 2 and row.gap == 1 and not row.description.is_empty() and not row.context.is_empty(), id + ": capacity, cadence and limitations")
		_check(row.first == (3 if id == "aslt" else (2 if id in ["prfy", "enlh"] else 1)), id + ": agreed availability round")
		for charge in 3:
			var entry := Items.battle_entry(profile, id, charge)
			_check(ELDuel.artifact_entry(profile, entry) == entry, id + ": canonical entry survives ordinary normalization")
			_check(Items.battle_entry(profile, id, float(charge)) == entry, id + ": integral JSON charges normalize")
			_check(Items.remaining_charges(profile, id, charge, [entry]) == charge, id + ": initial charge validates")
		var before := Items.battle_entry(profile, id, 2)
		var changed := Items.battle_entry(profile, id, 2)
		changed.custom.first = 77
		changed.charges = 0
		_check(Items.battle_entry(profile, id, 2) == before, id + ": entry dictionaries do not alias")
	for bad: Variant in [-1, 3, 0.5, "1", true, false, null, INF, NAN]:
		_check(Items.battle_entry(profile, "mndp", bad).is_empty(), "Malformed charge rejected: " + str(bad))
	_check(Items.battle_entry(profile, "unknown", 2).is_empty() and Items.find(profile, "unknown").is_empty(), "Unknown recipe rejected")
	_check(Items.catalog(null).is_empty() and Items.available(null).is_empty(), "Missing profile has no offers")
	var absent := ELProfile.new()
	absent.id = "el2"
	_check(Items.available(absent).is_empty() and Items.battle_entry(absent, "mndp", 2).is_empty(), "Missing printed tables cannot produce an artifact")
	absent.id = "el1"
	_check(Items.catalog(absent).is_empty() and Items.battle_entry(absent, "mndp", 2).is_empty(), "Recipes cannot change EL1 modes")
	for key: String in ["Use", "IsArtifact", "Support", "UseIn", "Class", "Name"]:
		var changed := _copy_profile()
		changed.tables.CombatSpells.MNDP[key] = {"Use": "-", "IsArtifact": "True", "Support": "True", "UseIn": "Defence", "Class": "Enchantment", "Name": ""}[key]
		_check("mndp" not in Items.available(changed) and Items.battle_entry(changed, "mndp", 2).is_empty(), "Unsupported printed field excluded: " + key)
	var language_before := OS.get_environment("DEMIURGES_LANGUAGE")
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		var source := _copy_profile()
		var wiki_path := ProjectSettings.globalize_path("res://").path_join("../wiki/catalog/" + language + ".json")
		var wiki: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(wiki_path))
		var titles := {}
		for page: Dictionary in wiki.pages: titles[page.key] = page.title
		for id: String in ids:
			var row := Items.find(profile, id)
			source.texts[source.table("CombatSpells")[row.card].Name] = titles[row.source]
		for row: Dictionary in Items.catalog(source):
			_check(row.title == titles[row.source], language + ": exact localized printed title for " + row.id)
			_check(Items.battle_entry(source, row.id, 2).custom.elk_name == Items.battle_entry(profile, row.id, 2).custom.elk_name, language + ": title language cannot change saved identity")
	OS.set_environment("DEMIURGES_LANGUAGE", language_before)
	var rows := Items.catalog(profile)
	rows[0].title = "caller edit"
	_check(Items.catalog(profile)[0].title != "caller edit", "Catalog rows do not alias future calls")

func _charge_validation() -> void:
	var ordinary := {"name": "Unrelated artifact", "charges": 99}
	_check(Items.remaining_charges(profile, "", 0, []) == 0 and Items.remaining_charges(profile, "", 0.0, [ordinary]) == 0, "Empty field slot ignores unrelated carried items")
	_check(Items.remaining_charges(profile, "", 1, []) == -1, "An empty slot cannot own charges")
	for id: String in Items.available(profile):
		var entry := Items.battle_entry(profile, id, 2)
		var entries := [ordinary.duplicate(), entry.duplicate(true)]
		var before := entries.duplicate(true)
		_check(Items.remaining_charges(profile, id, 2.0, _json(entries)) == 2, id + ": normalized JSON validates")
		_check(entries == before, id + ": validation is read-only")
		_check(Items.remaining_charges(profile, id, 2, [ordinary]) == -1, id + ": missing reserved item rejected")
		_check(Items.remaining_charges(profile, id, 2, [entry, entry.duplicate(true)]) == -1, id + ": duplicate reserved item rejected")
		_check(Items.remaining_charges(profile, "", 0, [entry]) == -1, id + ": unowned reserved item rejected")
		for left in 3:
			var changed := entry.duplicate(true)
			changed.charges = float(left)
			changed.ready_round = float(entry.ready_round + 4)
			_check(Items.remaining_charges(profile, id, 2, [changed]) == left, id + ": later cooldown and remaining charges survive JSON")
			if left == 2: _check(Items.remaining_charges(profile, id, 1, [changed]) == -1, id + ": combat cannot increase the starting charge")
		for key: String in ["name", "spell", "charges", "ready_round", "custom"]:
			var changed := entry.duplicate(true)
			changed.erase(key)
			_check(Items.remaining_charges(profile, id, 2, [changed]) == -1, id + ": missing field rejected: " + key)
		for change: Dictionary in [{"name": Items.NAME_PREFIX + "alien"}, {"spell": "ZAPP"}, {"charges": 3}, {"charges": -1}, {"charges": 1.2}, {"charges": "1"}, {"charges": true}, {"ready_round": 0}, {"ready_round": 1.5}, {"ready_round": "3"}, {"custom": []}]:
			var changed := entry.duplicate(true)
			changed.merge(change, true)
			_check(Items.remaining_charges(profile, id, 2, [changed]) == -1, id + ": forged entry rejected: " + str(change))
		for key: String in entry.custom:
			var changed := entry.duplicate(true)
			changed.custom[key] = "forged" if changed.custom[key] is String else int(changed.custom[key]) + 1
			_check(Items.remaining_charges(profile, id, 2, [changed]) == -1, id + ": forged definition rejected: " + key)
		var extra := entry.duplicate(true)
		extra.custom["extra"] = 1
		_check(Items.remaining_charges(profile, id, 2, [extra]) == -1, id + ": extra definition field rejected")
		var alien := Items.battle_entry(profile, "unsm" if id == "mndp" else "mndp", 2)
		_check(Items.remaining_charges(profile, id, 2, [entry, alien]) == -1, id + ": alien reserved item cannot hide beside the correct item")
	for malformed: Variant in [null, 5, "artifact", {}, {"name": 2}]:
		_check(Items.remaining_charges(profile, "mndp", 2, [malformed]) == -1, "Malformed entry rejected safely")

func _item_duel(id: String, faction := "Red", first := 0, skills: Dictionary = {}, source: ELProfile = null, specialization := "NONE") -> ELDuel:
	if source == null: source = profile
	var ranks := {"PRVD": 0}
	ranks.merge(skills, true)
	var player := {"faction": faction, "hero": ELDuelPresets.DEFAULT_HEROES[faction], "cards": _book(faction),
		"level": 5, "health": 80, "skills": ranks, "specialization": specialization, "artifacts": [Items.battle_entry(source, id, 2)]}
	var enemy := {"faction": "Red", "hero": ELDuelPresets.DEFAULT_HEROES.Red, "cards": _book("Red"),
		"level": 5, "health": 80, "skills": {"PRVD": 0}, "specialization": "NONE"}
	var duel := ELDuel.new()
	started += 1
	_check(duel.start(source, 91415, {"adventure": true, "players": [player, enemy], "arena": "Green.001", "first_side": first}), id + ": real custom-artifact duel starts: " + duel.error)
	return duel

func _advance(duel: ELDuel, target_round: int) -> void:
	for step in 30:
		if duel.phase == ELDuel.Phase.ATTACK and duel.attacker == 0 and duel.artifact_round() >= target_round: return
		if not duel.end_phase(): break
	_check(false, "Synthetic position advances to the requested attack phase")

func _item_target(duel: ELDuel, id: String, faction := "Red") -> Dictionary:
	var target := {"target": -1, "choice": -1}
	match id:
		"unsm": target.target = _summon(duel, 1, "STRT")
		"repr":
			duel.heroes[0].grave.append(BODY[faction])
			target.target = 0
			target.choice = duel.heroes[0].grave.size() - 1
		"prfy":
			target.target = _summon(duel, 1, "STRT")
			target.choice = duel.next_enchantment
			duel._enchant("STRG", 1, int(target.target), ELCatalog.rule(profile, "STRG"))
		"aslt": target.body = _summon(duel, 0, BODY[faction])
	return target

func _use_item(duel: ELDuel, target: Dictionary) -> bool:
	var ok := duel.use_artifact(0, 0, int(target.target), int(target.choice))
	if ok: actual_uses += 1
	return ok

func _roundtrip(duel: ELDuel, label: String) -> ELDuel:
	var before := duel.snapshot()
	var resumed := ELDuel.new()
	var ok := resumed.restore(duel.profile, {"format": "etherlords-duel", "version": 1, "state": _json(before)})
	roundtrips += 1
	_check(ok, label + ": JSON save restores: " + resumed.error)
	if ok: _check(resumed.snapshot() == before, label + ": complete saved state remains exact")
	return resumed

func _effects() -> void:
	for id: String in Items.available(profile):
		for faction: String in STARTERS:
			for first in 2:
				var duel := _item_duel(id, faction, first)
				_advance(duel, int(Items.find(profile, id).first))
				var target := _item_target(duel, id, faction)
				duel.heroes[0].mana = 0
				var before := duel.snapshot()
				var history_before := duel.history.size()
				var ok := _use_item(duel, target)
				_check(ok, "%s/%s/first%d: real activation succeeds: %s" % [id, faction, first, duel.error])
				if not ok: continue
				_check(duel.heroes[0].artifacts[0].charges == 1 and duel.heroes[0].artifact_uses == 1, id + ": one stored charge and one shared activation spent")
				_check(duel.heroes[0].artifacts[0].ready_round == duel.artifact_round() + 1, id + ": one-round cooldown begins")
				_check(duel.heroes[0].spell_uses == before.heroes[0].spell_uses and duel.heroes[0].deck == before.heroes[0].deck, id + ": no book charges or pages consumed/created")
				_check(duel.heroes[0].mana == (2 if id == "mndp" else 0), id + ": no printed ether cost paid")
				match id:
					"unsm": _check(not duel.creatures.has(target.target) and duel.heroes[1].hand.size() == before.heroes[1].hand.size() + 1 and duel.heroes[1].hand.back() == "STRT", "Unsummon returns the selected creature")
					"repr": _check(duel.heroes[0].grave.size() == before.heroes[0].grave.size() - 1 and duel.heroes[0].hand.back() == BODY[faction] and duel.heroes[1].health == before.heroes[1].health - int(profile.table("CombatCreatures")[BODY[faction]].Power), "Repair returns the grave creature and deals printed power")
					"prfy": _check(duel.find_enchantment(int(target.choice)) == -1, "Purify removes the chosen enchantment")
					"enlh":
						var events := duel.history.slice(history_before)
						var discards := events.filter(func(event: Dictionary) -> bool: return event.get("kind") == "discard" and event.get("side") == 0)
						var draws := events.filter(func(event: Dictionary) -> bool: return event.get("kind") == "draw" and event.get("side") == 0)
						_check(discards.size() == before.heroes[0].hand.size() and draws.size() == discards.size() and duel.heroes[0].hand.size() == before.heroes[0].hand.size(), "Enlightenment exchanges the actual hand without adding cards")
					"aslt": _check(duel.creatures[target.body].power == before.creatures[target.body].power + 2 and duel.creatures[target.body].toughness == before.creatures[target.body].toughness + 2 and duel.has_flag(target.body, "Trample") and duel.has_flag(target.body, "Berserk"), "Assault grants its original army bonuses and keywords")
				var resumed := _roundtrip(duel, id + "/" + faction)
				_check(Items.remaining_charges(profile, id, 2, resumed.heroes[0].artifacts) == 1, id + ": used charge survives save for run write-back")
				var saved := resumed.snapshot()
				_check(not _use_item(resumed, target) and resumed.snapshot() == saved, id + ": save does not reset the shared activation or cooldown")

func _rejections() -> void:
	for id: String in Items.available(profile):
		var duel := _item_duel(id)
		var target := _item_target(duel, id)
		if int(Items.find(profile, id).first) > 1:
			var before := duel.snapshot()
			_check(not _use_item(duel, target) and duel.snapshot() == before, id + ": premature activation is atomic")
		_advance(duel, int(Items.find(profile, id).first))
		duel.attacker = 1
		duel.phase = ELDuel.Phase.DEFENCE
		var before := duel.snapshot()
		_check(not _use_item(duel, target) and duel.snapshot() == before, id + ": custom artifact refuses defence-phase use")
		duel.attacker = 0
		duel.phase = ELDuel.Phase.ATTACK
		duel.heroes[0].artifacts[0].charges = 0
		before = duel.snapshot()
		_check(not _use_item(duel, target) and duel.snapshot() == before, id + ": exhausted item refuses atomically")
	for id: String in ["unsm", "repr", "prfy"]:
		var duel := _item_duel(id)
		_advance(duel, int(Items.find(profile, id).first))
		var before := duel.snapshot()
		_check(not _use_item(duel, {"target": -1, "choice": -1}) and duel.snapshot() == before, id + ": missing target cannot waste a charge")
		if id == "unsm":
			var immune := _summon(duel, 1, "BRMZ")
			before = duel.snapshot()
			_check(not _use_item(duel, {"target": immune, "choice": -1}) and duel.snapshot() == before, "Artifact does not bypass untargetability")
	var empty_hand := _item_duel("enlh")
	_advance(empty_hand, 2)
	while not empty_hand.heroes[0].hand.is_empty(): empty_hand._take_card(0, 0)
	_check(_use_item(empty_hand, {"target": -1, "choice": -1}) and empty_hand.heroes[0].hand.is_empty() and empty_hand.heroes[0].artifacts[0].charges == 1, "Ordinary Enlightenment can waste a charge on an empty hand; catalog discloses this")

func _cooldown_and_budget() -> void:
	var duel := _item_duel("mndp", "Red", 0, {"ARTF": 1})
	var target := {"target": -1, "choice": -1}
	_check(_use_item(duel, target), "Artificer can make the first use")
	var before := duel.snapshot()
	_check(not _use_item(duel, target) and duel.snapshot() == before, "Cooldown blocks a same-round use despite spare shared activations")
	var resumed := _roundtrip(duel, "Cooldown with Artificer")
	_advance(resumed, resumed.artifact_round() + 1)
	_check(_use_item(resumed, target) and resumed.heroes[0].artifacts[0].charges == 0 and resumed.heroes[0].artifact_uses == 2, "Next round permits the second use and exhausts the item")
	_check(Items.remaining_charges(profile, "mndp", 2, resumed.heroes[0].artifacts) == 0, "Two uses write back zero charges")
	duel = _item_duel("mndp")
	var other := Items.battle_entry(profile, "mndp", 2)
	other.name = "OtherCustomArtifact"
	duel.heroes[0].artifacts.append(other)
	_check(_use_item(duel, target), "Field item uses the default hero's artifact activation")
	before = duel.snapshot()
	_check(not duel.use_artifact(0, 1) and duel.snapshot() == before, "Other carried items share the same per-battle activation budget")
	_advance(duel, 2)
	before = duel.snapshot()
	_check(not _use_item(duel, target) and duel.snapshot() == before, "Default artifact activation budget does not reset next round")

func _attraction() -> void:
	var duel := _item_duel("mndp", "Black")
	duel._enchant("TRLB", 0, 0, ELCatalog.rule(profile, "TRLB"))
	var hand_size: int = duel.heroes[0].hand.size()
	var health := int(duel.heroes[0].health)
	var uses: Array = duel.heroes[0].spell_uses.duplicate()
	_check(_use_item(duel, {"target": -1, "choice": -1}), "Artifact spell uses the ordinary cast-reaction path")
	_check(duel.heroes[0].hand.size() == hand_size + 1 and duel.heroes[0].health == health - 2, "Data Attraction draws and deals its unavoidable self-damage")
	_check(duel.heroes[0].spell_uses == uses, "Artifact-triggered draw creates no charges")
	_roundtrip(duel, "Artifact-triggered Data Attraction")

func _artificer() -> void:
	for probability: float in [0.0, 1.0]:
		var source := _copy_profile()
		source.tables.HeroesSpecs = {"ARTF": {"Chance": "high"}}
		var chances := {}
		for level in range(1, 21): chances["Level%d" % level] = probability
		source.tables.HeroesStats["SpecChanceHigh"] = chances
		var duel := _item_duel("mndp", "Red", 0, {}, source, "ARTF")
		_check(_use_item(duel, {"target": -1, "choice": -1}), "Isolated ARTF endpoint exercises the actual use")
		var expected := 2 if probability == 1.0 else 1
		_check(duel.heroes[0].artifacts[0].charges == expected and duel.heroes[0].artifact_uses == 1, "ARTF can conserve charges while spending the activation")
		_check(Items.remaining_charges(source, "mndp", 2, duel.heroes[0].artifacts) == expected, "Write-back preserves the actual ARTF charge result")
		_roundtrip(duel, "ARTF endpoint " + str(probability))

func _spell_specializations() -> void:
	var source := _copy_profile()
	source.tables.HeroesSpecs = {"BPRC": {"Chance": "high"}, "CEXC": {"Chance": "ulow"}}
	var chances := {}
	for level in range(1, 21): chances["Level%d" % level] = 1.0
	source.tables.HeroesStats["SpecChanceHigh"] = chances.duplicate()
	source.tables.HeroesStats["SpecChanceULow"] = chances.duplicate()
	var purify := _item_duel("prfy", "Black", 0, {}, source, "BPRC")
	_advance(purify, 2)
	var target := _item_target(purify, "prfy")
	var other := purify.next_enchantment
	purify._enchant("SHSK", 1, int(target.target), ELCatalog.rule(source, "SHSK"))
	_check(purify.find_enchantment(int(target.choice)) >= 0 and purify.find_enchantment(other) >= 0, "BPRC control has two removable enchantments")
	_check(_use_item(purify, target), "Purify artifact casts with isolated BPRC endpoint")
	_check(purify.find_enchantment(int(target.choice)) == -1 and purify.find_enchantment(other) == -1, "Selective Purification still removes the holder's other enchantment for an artifact")
	_check(purify.heroes[0].artifacts[0].charges == 1 and purify.heroes[0].artifact_uses == 1, "BPRC keeps the ordinary artifact charge and activation cost")
	var translocation := _item_duel("mndp", "Black", 0, {}, source, "CEXC")
	var hand: Array = translocation.heroes[0].hand.duplicate()
	var rng := translocation.rng_state
	_check(_use_item(translocation, {"target": -1, "choice": -1}), "Ether Drop artifact casts with isolated CEXC endpoint")
	_check(translocation.heroes[0].hand == hand and translocation.rng_state == rng, "Artifact skips Spell Translocation's extra draw and generic specialization roll")
	translocation._give_card(0, "MNDP")
	translocation.heroes[0].mana = 99
	var normal_hand: int = translocation.heroes[0].hand.size()
	_check(translocation.cast(normal_hand - 1, 0), "Same CEXC endpoint accepts an ordinary printed spell")
	_check(translocation.heroes[0].hand.size() == normal_hand, "Ordinary spell consumes one card and Spell Translocation draws one, proving the test specialization is active")

func _native() -> void:
	_check(ELCombatBrain.available, "Native extension is available")
	if not ELCombatBrain.available: return
	ELCombatSearch.smart_engine = true
	ELCombatSearch.smart_engine_info = "full"
	ELCombatSearch.smart_engine_budget = 2000
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_prove = 0
	ELCombatSearch.smart_engine_beyond = 0
	for id: String in Items.available(profile):
		for first in 2:
			var duel := _item_duel(id, "Black", first)
			_advance(duel, int(Items.find(profile, id).first))
			_item_target(duel, id, "Black")
			_summon(duel, 0, "MCWO")
			_summon(duel, 1, "STRT")
			duel.smart_sides.assign([0, 1])
			var context := ELCombatSearch.plain_context(duel, 0)
			var record := ELCombatBrain.artifact_card(context, duel, duel.heroes[0].artifacts[0])
			_check(not record.is_empty(), id + ": native representation contains the custom spell")
			var packed := ELCombatBrain.ask(context, duel, 1, 256, true, 6)
			_check(not packed.get("raw", PackedInt32Array()).is_empty() and ELCombatBrain.last_crowding.is_empty(), id + ": position packs without unsupported/crowded state")
			var stats := {}
			var command := ELCombatSearch.think(duel, stats)
			var accepted := not command.is_empty() and ELCombatSearch.apply(duel, command)
			_check(accepted, id + ": native decision is accepted by the real duel: " + duel.error)
			if accepted: native_decisions += 1
			native_rows.append({"id": id, "first_side": first, "engine": stats.get("engine", ""), "command": command, "accepted": accepted, "crowding": ELCombatBrain.last_crowding})
