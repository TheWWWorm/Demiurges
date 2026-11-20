extends SceneTree
## Real encounter transformations and seeded roster checks with deliberately
## synthetic card stats. This validates rules and safety, not mounted-game AI
## balance. No player checkpoints are read or written.
## godot --headless --path game --script ../tools/expedition_tactics_check.gd

const Fixture := preload("expedition_fixture.gd")
const ROOT := "user://expedition_tactics_check"
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := Fixture.profile_at(ROOT)
	if profile == null:
		check(false, "Synthetic profile mounts")
		quit(1)
		return
	_complete_tactic_tables(profile)
	for plan: Dictionary in ELExpeditionEncounters.TACTICS:
		_check_plan(profile, plan)
	_check_boundaries(profile)
	_check_roster(profile)
	Fixture.clean(ROOT)
	print("Expedition tactics: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _complete_tactic_tables(profile: ELProfile) -> void:
	# All synthetic costs are two. Real numeric card data remains owned by
	# the mounted game; production code filters its actual cost and legality.
	for plan: Dictionary in ELExpeditionEncounters.TACTICS:
		var codes: Array = plan.cards.duplicate()
		codes.append_array(plan.anchors)
		for code: String in codes:
			var creature: bool = code in ELCatalog.SUMMONS or code in ELCatalog.FIRST_SUMMONS
			profile.tables.CombatSpells[code] = {"Class": "Creature" if creature else "Sorcery", "Cost": 2,
				"Color": plan.faction, "Use": "+", "Rarity": "Common", "Name": code}
			if creature:
				profile.tables.CombatCreatures[code] = {"Power": 2, "Toughness": 2, "Race": "Fixture", "Flags": []}

func _source(profile: ELProfile, plan: Dictionary) -> Dictionary:
	var cards: Array[String] = []
	var first := str(plan.anchors[0])
	var second := str(plan.anchors[1])
	var support: String = {"Green": "BLSS", "Red": "FRWA", "Blue": "LSPC", "Black": "NOIS"}[plan.faction]
	profile.tables.CombatSpells[support] = {"Class": "Sorcery", "Cost": 2,
		"Color": plan.faction, "Use": "+", "Rarity": "Common", "Name": support}
	# Two signature creatures with duplicates and support copies leave room
	# to reinforce a theme, just as the campaign's authored books do.
	for i in 4:
		cards.append(first)
		cards.append(second)
		cards.append(support)
	return {"id": "tactic-fixture", "title": "Tactic fixture", "faction": plan.faction,
		"cards": cards, "skills": {"PRVD": 0}, "health": 19, "level": 3,
		"specialization": "NONE", "arena": str(plan.faction) + ".001"}

func _check_plan(profile: ELProfile, plan: Dictionary) -> void:
	var source := _source(profile, plan)
	var before := source.duplicate(true)
	var result := ELExpeditionEncounters.apply_tactics(profile, source, "elite", 3, 4, 222)
	var repeated := ELExpeditionEncounters.apply_tactics(profile, source, "elite", 3, 4, 222)
	var prefix := str(plan.id) + ": "
	check(result.get("strategy_id") == plan.id, prefix + "matching source theme selects the intended tactic")
	check(source == before and result == repeated, prefix + "deterministic and does not mutate campaign source")
	check(result.cards.size() == source.cards.size(), prefix + "preserves spellbook size")
	var preserved := 0
	var valid := true
	for index in source.cards.size():
		if source.cards[index] == result.cards[index]: preserved += 1
	for code: String in result.cards:
		valid = valid and result.cards.count(code) <= 4 and ELDuelCosts.spell_allowed(profile, code, source.faction) and not ELCatalog.rule(profile, code).is_empty()
	check(valid and preserved >= source.cards.size() / 2, prefix + "retains half the source and obeys card legality/copy limits")
	check(result.cards.has(plan.anchors[0]) and result.cards.has(plan.anchors[1]), prefix + "retains original signature creatures")
	check(result.health == source.health and result.level == source.level and result.skills == source.skills, prefix + "does not add hidden stat or skill advantages")
	for required: String in plan.requires:
		check(result.cards.has(required), prefix + "scouted interaction is present: " + required)

func _check_boundaries(profile: ELProfile) -> void:
	var plan: Dictionary = ELExpeditionEncounters.TACTICS[0]
	var source := _source(profile, plan)
	check(ELExpeditionEncounters.apply_tactics(profile, source, "boss", 3, 5, 222) == source, "Boss mechanics are untouched")
	var scripted := source.duplicate(true)
	scripted.scripts = [{"name": "fixture-boss-script", "side": 1}]
	check(ELExpeditionEncounters.apply_tactics(profile, scripted, "elite", 3, 5, 222) == scripted, "Scripted campaign encounters are untouched")
	check(ELExpeditionEncounters.apply_tactics(profile, source, "fight", 1, 0, 222) == source, "First ordinary duel keeps the original campaign spellbook")
	var small := source.duplicate(true)
	small.cards = [source.cards[0], source.cards[1], source.cards[2]]
	check(ELExpeditionEncounters.apply_tactics(profile, small, "elite", 3, 3, 222) == small, "Tiny campaign spellbooks are not rewritten")
	var unique := source.duplicate(true)
	unique.cards = ["BEWK", "BEWR", "BEQN", "MOBE"]
	check(ELExpeditionEncounters.apply_tactics(profile, unique, "elite", 3, 3, 222) == unique, "A fully protected original book returns safely without a tactic")
	for late: Dictionary in ELExpeditionEncounters.TACTICS:
		if int(late.act) <= 1: continue
		var early := ELExpeditionEncounters.apply_tactics(profile, _source(profile, late), "elite", 1, 3, 222)
		check(early.get("strategy_id", "") != late.id, str(late.id) + ": advanced attrition plan cannot appear in Act I")
	var required := str(plan.requires[0])
	var original: Dictionary = profile.tables.CombatSpells[required].duplicate(true)
	profile.tables.CombatSpells[required].IsArtifact = "True"
	var missing := _source(profile, plan)
	# Remove the required effect from the source as well, so an invalid
	# addition cannot still be described by a misleading scouting label.
	for i in missing.cards.size():
		if missing.cards[i] == required: missing.cards[i] = "TNSA"
	var result := ELExpeditionEncounters.apply_tactics(profile, missing, "elite", 3, 3, 222)
	check(required not in result.cards, "Artifact-only effects cannot be inserted into encounter decks")
	profile.tables.CombatSpells[required] = original
	var narrow := _source(profile, plan)
	profile.tables.CombatSpells["UPGD"].Cost = 8
	result = ELExpeditionEncounters.apply_tactics(profile, narrow, "elite", 1, 3, 222)
	check("UPGD" not in result.cards, "Act I tactics skip unaffordable added cards")
	profile.tables.CombatSpells["UPGD"].Cost = 2

func _check_roster(profile: ELProfile) -> void:
	var same := true
	var normalized := true
	for act in range(1, 4):
		for floor in range(1, 7):
			for kind: String in ["fight", "elite", "boss"]:
				var legacy_floor := (act - 1) * 6 + floor
				var legacy := ELExpeditionEncounters.build(profile, kind, legacy_floor, 222, true)
				var explicit := ELExpeditionEncounters.build(profile, kind, legacy_floor, 222, true, [], false, 6)
				same = same and legacy == explicit
		for kind: String in ["fight", "elite", "boss"]:
			var six := ELExpeditionEncounters.build(profile, kind, act * 6, 222, false)
			var eight := ELExpeditionEncounters.build(profile, kind, act * 8, 222, false, [], true, 8)
			normalized = normalized and not six.is_empty() and not eight.is_empty() and six.level == eight.level and six.health == eight.health
	check(same, "Default and explicit legacy encounter rules remain identical")
	check(normalized, "Eight-floor acts preserve end-of-act enemy strength and boss selection")
