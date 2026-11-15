class_name ELPuzzleLabChecks
extends RefCounted
## Behavioral checks of the real Run observer and puzzle-only rule switches.
## Uses the same card fixture as puzzle_lab.gd; no game content is mocked here.

static var results: Array = []

static func _check(condition: bool, label: String) -> void:
	results.append({"ok": condition, "check": label})
	print(("OK " if condition else "FAILED ") + label)

static func _entry(profile: ELProfile, seed: Dictionary) -> Dictionary:
	var heroes: Array = []
	for side in 2:
		heroes.append({"id": side, "health": 10, "maximum": 10, "mana": 2, "channels": 2,
			"level": 4, "turns": 1, "template": seed.state.heroes[side].template,
			"faction": "Red", "kind": "hero", "skills": {}, "spec": "NONE", "spec_level": 4,
			"luck": 0, "suppression": 0, "deck": ["ZAPP"], "hand": ["ZAPP"], "hand_slots": [-1],
			"spell_uses": [-1 if profile.id == "el1" else 1], "drawn": [], "grave": [], "enchantments": [],
			"artifacts": [], "artifact_uses": 0})
	return {"id": "lab-regression", "turns": 1, "state": {"profile": profile.id, "charge_version": 2, "payment_version": 1,
		"phase": 0, "attacker": 0, "round": 2, "turn_serial": 3, "rng": 212, "winner": -1,
		"next_id": 2, "next_enchantment": 1, "attacks": [], "blocks": {}, "creatures": {}, "heroes": heroes,
		"setup": {"puzzle_fixed_hands": true, "puzzle_fixed_channels": true}}}

static func _creature(profile: ELProfile, card: String, side: int) -> Dictionary:
	var row: Dictionary = profile.table("CombatCreatures")[card]
	var flags := ELCatalog.flags(row)
	return {"id": 2, "card": card, "owner": side, "power": int(row.Power), "toughness": int(row.Toughness),
		"damage": int(row.Toughness) - 1, "flags": flags, "flying": "Fly" in flags, "enchantments": [],
		"resting": false, "sick": false, "regenerated": false}

static func _begin(profile: ELProfile, entry: Dictionary) -> ELPuzzles.Run:
	ELPuzzles._lists[profile.id] = [entry]
	var run := ELPuzzles.Run.new()
	_check(run.begin(profile, 0), "restore " + String(entry.get("test_name", "case")))
	return run

static func _hero_checks(profile: ELProfile, seed: Dictionary) -> void:
	_check(ELHeroSkills.valid_ranks(profile, {"REGN": 2, "CNLG": 0}), "real skill validator accepts registered deterministic ranks")
	_check(not ELHeroSkills.valid_ranks(profile, {"REGN": 3}) and not ELHeroSkills.valid_ranks(profile, {"CNLG": -1}), "real skill validator rejects out-of-range ranks")
	_check(not ELHeroSkills.valid_ranks(profile, {"REGN": 0.5}) and not ELHeroSkills.valid_ranks(profile, {"FAKE": 0}), "real skill validator rejects fractional and unregistered skills")
	var hero := {"level": 4, "turns": 19, "skills": {}}
	var opponent := {"level": 4, "turns": 18, "skills": {}}
	_check(ELHeroEffects.disturbance(profile.id, hero, opponent) == (4 if profile.id == "el1" else 5), "disturbance uses the edition's linear or exponential damage")
	hero.level = 8
	_check(ELHeroEffects.disturbance(profile.id, hero, opponent) == 0, "higher hero level postpones disturbance at the same turn")
	hero.level = 4
	hero.skills = {"CNLG": 2}
	_check(ELHeroEffects.disturbance(profile.id, hero, opponent) == 1, "Channeling rank three delays own disturbance by three turns")
	hero.skills = {}
	opponent.skills = {"CNLG": 1}
	_check(ELHeroEffects.disturbance(profile.id, hero, opponent) == (6 if profile.id == "el1" else 11), "enemy Channeling rank two advances disturbance by two turns")
	hero.skills = {"CNLG": 2}
	_check(ELHeroEffects.disturbance(profile.id, hero, opponent) == 3, "both heroes' Channeling ranks combine with opposite signs")
	hero.skills = {}
	opponent.skills = {}
	hero.turns = 15
	_check(ELHeroEffects.disturbance(profile.id, hero, opponent, 4) == (4 if profile.id == "el1" else 5), "explicit disturbance acceleration is added after level and Channeling")
	var expected := [[2, 5, 8], [2, 4, 6, 8], [1, 2, 3, 4, 5, 6, 7, 8]]
	for rank in 3:
		hero.skills = {"REGN": rank}
		var turns: Array = []
		for turn in range(1, 9):
			hero.turns = turn
			if ELHeroEffects.regenerates(hero): turns.append(turn)
		_check(turns == expected[rank], "Regeneration rank %d follows its actual own-turn cadence" % (rank + 1))
	var entry := _entry(profile, seed)
	entry.test_name = "lethal disturbance before regeneration"
	entry.objective = {"type": "survive", "enemy_turns": 1}
	entry.state.round = 12
	entry.state.turn_serial = 24
	entry.state.heroes[0].turns = 12
	entry.state.heroes[0].level = 1
	entry.state.heroes[0].health = 1
	entry.state.heroes[0].skills = {"REGN": 2}
	entry.state.heroes[1].turns = 12
	entry.state.heroes[1].level = 20
	var attempt := _begin(profile, entry)
	attempt.duel.end_phase()
	attempt.duel.end_phase()
	_check(attempt.outcome == "failed" and attempt.duel.heroes[0].health <= 0, "lethal disturbance is resolved before Regeneration can heal")
	entry.test_name = "surviving disturbance before regeneration"
	entry.state.heroes[0].health = 2
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	attempt.duel.end_phase()
	_check(attempt.outcome == "solved" and attempt.duel.heroes[0].health == 2, "a surviving hero regenerates after disturbance with fixed puzzle supplies")
	entry.test_name = "hero level avoids the same disturbance"
	entry.state.heroes[0].level = 2
	entry.state.heroes[0].health = 1
	entry.state.heroes[0].skills = {}
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	attempt.duel.end_phase()
	_check(attempt.outcome == "solved" and attempt.duel.heroes[0].health == 1, "changing the actual hero level changes survival in the restored battle")
	entry.test_name = "regeneration maximum cap"
	entry.state.heroes[0].health = 10
	entry.state.heroes[0].skills = {"REGN": 2}
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	attempt.duel.end_phase()
	_check(attempt.outcome == "solved" and attempt.duel.heroes[0].health == 10, "Regeneration cannot raise health above the stored maximum")
	entry.hero_names = ["Novice", "Veteran"]
	entry.hero_names_ru = ["Ученик", "Ветеран"]
	entry.level = 4
	_check(ELPuzzles.valid_entry(entry, profile.id), "schema accepts bilingual combatant names")
	_check(ELPuzzles.combatants(entry, profile, "en") == [{"name": "Novice", "level": 2}, {"name": "Veteran", "level": 20}], "combatant display uses actual asymmetric levels, independent of Expert difficulty")
	_check(ELPuzzles.combatants(entry, profile, "ru")[0].name == "Ученик", "combatant names follow the requested language")
	entry.hero_names = ["Missing opponent"]
	_check(not ELPuzzles.valid_entry(entry, profile.id), "schema rejects incomplete combatant-name metadata")

static func run(profile: ELProfile, seed: Dictionary) -> Dictionary:
	results = []
	ELPuzzles.remember = false
	var entry := _entry(profile, seed)
	entry.test_name = "lethal spell"
	entry.state.heroes[1].health = 1
	var attempt := _begin(profile, entry)
	_check(attempt.duel.cast(0, 1) and attempt.outcome == "solved", "victory is detected by the real changed observer")
	entry = _entry(profile, seed)
	entry.test_name = "health floor"
	entry.objective = {"type": "win", "min_health": 10}
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 0) and attempt.outcome == "failed" and attempt.reason == "health", "health floor fails immediately after a legal self-targeted spell")
	entry = _entry(profile, seed)
	entry.test_name = "protect a creature"
	entry.state.next_id = 3
	entry.state.creatures = {"2": _creature(profile, "WTEL", 0)}
	entry.objective = {"type": "win", "protect": [2]}
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 2) and attempt.outcome == "failed" and attempt.reason == "protected", "destroying a protected creature fails even before the battle ends")
	attempt.duel.creatures[2] = _creature(profile, "WTEL", 0)
	attempt.duel.changed.emit()
	_check(attempt.outcome == "failed", "bringing a protected creature back cannot erase the failure")
	entry = _entry(profile, seed)
	entry.test_name = "clear the board"
	entry.state.next_id = 3
	entry.state.creatures = {"2": _creature(profile, "WTEL", 1)}
	entry.objective = {"type": "clear"}
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 2) and attempt.outcome == "solved" and attempt.duel.heroes[1].health == 10, "clear-board succeeds with the enemy hero alive")
	entry.state.heroes[1].health = 1
	entry.test_name = "clear-board hero shortcut"
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 1) and attempt.outcome == "failed" and attempt.reason == "objective", "hero lethal alone cannot bypass a clear-board objective")
	entry = _entry(profile, seed)
	entry.test_name = "survival boundary"
	entry.objective = {"type": "survive", "enemy_turns": 1}
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	_check(attempt.outcome.is_empty(), "survival waits for the enemy turn to finish")
	attempt.duel.end_phase()
	_check(attempt.outcome == "solved" and attempt.turn == 1, "survival succeeds at the next-turn boundary before timeout")
	entry = _entry(profile, seed)
	entry.test_name = "survival early victory"
	entry.state.heroes[1].health = 1
	entry.objective = {"type": "survive", "enemy_turns": 2}
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 1) and attempt.outcome == "solved", "early victory satisfies survival")
	entry = _entry(profile, seed)
	entry.test_name = "ordinary win timeout"
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	attempt.duel.end_phase()
	_check(attempt.outcome == "failed" and attempt.reason == "turns", "win objectives still time out at the same next-turn boundary")
	# Real turn progression uses an unmistakable +3 fixture row. This detects
	# accidental changes to ordinary duels as well as a missing puzzle guard.
	var old_income: Dictionary = profile.tables.CombatManaIncome
	var row := {}
	for level in range(1, 21): row["Level%d" % level] = 3
	profile.tables.CombatManaIncome = {"1": row, "2": row, "3": row, "4": row}
	entry = _entry(profile, seed)
	entry.test_name = "fixed puzzle supplies"
	for hero: Dictionary in entry.state.heroes:
		hero.hand = []
		hero.hand_slots = []
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	_check(attempt.duel.heroes[1].hand.is_empty(), "fixed-hands puzzles do not draw at turn start")
	_check(attempt.duel.heroes[1].channels == 2 and attempt.duel.heroes[1].mana == 2, "fixed-channel puzzles refill ether without natural channel growth")
	entry.state.setup.erase("puzzle_fixed_hands")
	entry.state.setup.erase("puzzle_fixed_channels")
	entry.test_name = "ordinary duel supplies"
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	_check(attempt.duel.heroes[1].hand == ["ZAPP"], "ordinary duels still draw normally")
	_check(attempt.duel.heroes[1].channels == 5 and attempt.duel.heroes[1].mana == 5, "ordinary duels still gain and refill natural channels")
	profile.tables.CombatManaIncome = old_income
	# Capture is about these live identities, not a kill, bounce, or replacement.
	entry = _entry(profile, seed)
	entry.test_name = "capture two live creatures"
	entry.state.next_id = 4
	var first := _creature(profile, "STRT", 1)
	first.damage = 0
	var second := first.duplicate(true)
	second.id = 3
	entry.state.creatures = {"2": first, "3": second}
	entry.state.heroes[0].hand = ["CHCM", "CHCM"]
	entry.state.heroes[0].hand_slots = [-1, -1]
	entry.state.heroes[0].mana = 10
	entry.objective = {"type": "control", "targets": [2, 3]}
	_check(ELPuzzles.valid_entry(entry, profile.id), "capture schema accepts two distinct enemy targets")
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 2) and attempt.outcome.is_empty(), "capturing only one required target does not finish")
	_check(attempt.duel.cast(0, 3) and attempt.outcome == "solved", "capturing every live target completes without killing the hero")
	var invalid := entry.duplicate(true)
	invalid.objective.targets = []
	_check(not ELPuzzles.valid_entry(invalid, profile.id), "capture rejects empty targets")
	invalid.objective.targets = [2, 2]
	_check(not ELPuzzles.valid_entry(invalid, profile.id), "capture rejects duplicate targets")
	invalid.objective.targets = [999]
	_check(not ELPuzzles.valid_entry(invalid, profile.id), "capture rejects missing targets")
	invalid.objective.targets = [2]
	invalid.state.creatures["2"].owner = 0
	_check(not ELPuzzles.valid_entry(invalid, profile.id), "capture targets must initially belong to the opponent")
	entry.state.heroes[0].hand = ["ZAPP"]
	entry.state.heroes[0].hand_slots = [-1]
	entry.test_name = "capture target killed"
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 2) and attempt.outcome == "failed" and attempt.reason == "capture", "killing a capture target fails immediately")
	entry.test_name = "capture hero lethal shortcut"
	entry.state.heroes[1].health = 1
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 1) and attempt.outcome == "failed" and attempt.reason == "objective", "hero lethal cannot substitute for capturing the targets")
	# Completion requirements allow recovery and rebuilding; they do not have
	# the sticky semantics of protect/min_health. Exercise real spells and the
	# real observer, including an already-cleared board that is not yet enough.
	entry = _entry(profile, seed)
	entry.test_name = "recover and rebuild after clearing"
	entry.state.next_id = 4
	entry.state.next_enchantment = 2
	var ally := _creature(profile, "STRT", 0)
	ally.damage = 0
	var foe := _creature(profile, "STRT", 1)
	foe.id = 3
	foe.damage = 0
	entry.state.creatures = {"2": ally, "3": foe}
	entry.state.heroes[0].mana = 5
	entry.state.heroes[0].hand = ["ZAPP", "ZAPP", "STRT"]
	entry.state.heroes[0].hand_slots = [-1, -1, -1]
	entry.state.heroes[0].enchantments = [{"id": 1, "card": "LSHE", "owner": 0, "power": 0, "toughness": 0, "born": 3, "used": false}]
	entry.objective = {"type": "clear", "finish_health": 10, "finish_mana": 1, "min_allies": 2}
	_check(ELPuzzles.valid_entry(entry, profile.id), "schema accepts combined completion requirements")
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 0) and attempt.outcome.is_empty(), "temporary health below the finishing requirement remains playable")
	_check(attempt.duel.cast(0, 3) and attempt.duel.army(1).is_empty() and attempt.outcome.is_empty(), "clearing the board waits for the remaining completion requirements")
	_check(attempt.duel.use_ability(0, "heal:1") and attempt.duel.heroes[0].health == 11 and attempt.outcome.is_empty(), "recovering health still waits for the required army")
	_check(attempt.duel.cast(0) and attempt.outcome == "solved" and attempt.duel.heroes[0].mana == 1 and attempt.duel.army(0).size() == 2, "rebuilding the army completes all three requirements together")
	for requirement: String in ["finish_health", "finish_mana", "min_allies"]:
		entry = _entry(profile, seed)
		entry.test_name = "lethal with unmet " + requirement
		entry.state.heroes[0].health = 9
		entry.state.heroes[1].health = 1
		entry.objective = {"type": "win", requirement: 10 if requirement == "finish_health" else (2 if requirement == "finish_mana" else 1)}
		attempt = _begin(profile, entry)
		_check(attempt.duel.cast(0, 1) and attempt.outcome == "failed" and attempt.reason == requirement, "hero victory cannot bypass " + requirement)
	entry = _entry(profile, seed)
	entry.test_name = "survival with insufficient final reserve"
	entry.objective = {"type": "survive", "enemy_turns": 1, "finish_mana": 3}
	attempt = _begin(profile, entry)
	attempt.duel.end_phase()
	attempt.duel.end_phase()
	_check(attempt.outcome == "failed" and attempt.reason == "finish_mana", "survival boundary checks final reserve before awarding success")
	entry = _entry(profile, seed)
	entry.test_name = "capture through an enemy response"
	entry.state.next_id = 3
	entry.state.creatures = {"2": first.duplicate(true)}
	entry.state.heroes[0].mana = 6
	entry.state.heroes[0].hand = ["CHCM", "ZAPP"]
	entry.state.heroes[0].hand_slots = [-1, -1]
	entry.objective = {"type": "control", "targets": [2], "enemy_turns": 1, "min_allies": 1}
	attempt = _begin(profile, entry)
	_check(attempt.duel.cast(0, 2) and attempt.outcome.is_empty(), "delayed capture does not solve before the enemy response")
	attempt.duel.end_phase()
	_check(attempt.outcome.is_empty(), "starting the enemy turn does not satisfy delayed capture")
	attempt.duel.end_phase()
	_check(attempt.outcome == "solved" and attempt.turn == 1, "delayed capture succeeds at the enemy-end boundary before timeout")
	entry.test_name = "early lethal during delayed capture"
	entry.state.heroes[1].health = 1
	attempt = _begin(profile, entry)
	attempt.duel.cast(0, 2)
	_check(attempt.duel.cast(0, 1) and attempt.outcome == "failed" and attempt.reason == "objective", "early hero lethal does not skip the delayed-capture response window")
	# Validate bounds without depending on authoring metadata or UI labels.
	entry = _entry(profile, seed)
	entry.level = 4
	entry.objective = {"type": "win", "finish_mana": 0}
	_check(ELPuzzles.valid_entry(entry, profile.id), "Expert level and zero final ether are valid")
	entry.level = 5
	_check(not ELPuzzles.valid_entry(entry, profile.id), "unknown difficulty levels are rejected")
	entry.level = 4
	for requirement: String in ["finish_health", "finish_mana", "min_allies"]:
		entry.objective = {"type": "win", requirement: -1}
		_check(not ELPuzzles.valid_entry(entry, profile.id), "negative " + requirement + " is rejected")
		entry.objective[requirement] = 1.5
		_check(not ELPuzzles.valid_entry(entry, profile.id), "fractional " + requirement + " is rejected")
	entry.objective = {"type": "control", "targets": [2], "enemy_turns": 0}
	entry.state.creatures = {"2": first.duplicate(true)}
	_check(not ELPuzzles.valid_entry(entry, profile.id), "delayed capture requires a positive enemy-turn count")
	# Hint badges are separate from fastest turns and do not retroactively award
	# old completions whose hint usage was never recorded.
	ELPuzzles._mastery_read = true
	ELPuzzles._mastery = {}
	ELPuzzles.mark(profile.id, "legacy-no-hint-record", 1)
	_check(not ELPuzzles.mastered(profile.id, "legacy-no-hint-record"), "legacy completion does not invent a hintless badge")
	ELPuzzles.mark(profile.id, "independent-mastery", 1, 3)
	ELPuzzles.mark(profile.id, "independent-mastery", 2, 0)
	_check(ELPuzzles.solved_in(profile.id, "independent-mastery") == 1 and ELPuzzles.mastered(profile.id, "independent-mastery"), "slower hintless replay improves mastery without losing the fastest record")
	ELPuzzles.mark(profile.id, "independent-mastery", 1, 2)
	_check(ELPuzzles.mastered(profile.id, "independent-mastery"), "later hinted completion cannot erase a hintless badge")
	entry = _entry(profile, seed)
	entry.test_name = "hint stage accounting"
	entry.id = "hint-stage-accounting"
	entry.hints = ["first", "second", "third"]
	entry.state.heroes[1].health = 1
	attempt = _begin(profile, entry)
	attempt.note_hint(0)
	attempt.note_hint(0)
	_check(attempt.hints_used == 1, "reopening a hint does not inflate the disclosed stage count")
	attempt.note_hint(2)
	attempt.note_hint(1)
	_check(attempt.hints_used == 3, "disclosed hints retain the deepest stage")
	_check(attempt.duel.cast(0, 1) and not ELPuzzles.mastered(profile.id, entry.id), "hinted success records completion without a hintless badge")
	attempt = _begin(profile, entry)
	_check(attempt.hints_used == 0, "new practice attempt resets current hint count")
	_check(attempt.duel.cast(0, 1) and ELPuzzles.mastered(profile.id, entry.id), "unassisted practice success earns the badge")
	_hero_checks(profile, seed)
	var failures := results.filter(func(result: Dictionary) -> bool: return not result.ok).size()
	print("TOTAL runtime_checks=%d failures=%d" % [results.size(), failures])
	return {"edition": profile.id, "checks": results.size(), "failures": failures, "results": results}
