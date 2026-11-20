extends "expedition_combat_balance.gd"
## Six field recipes x four factions x both starts x base/item = 96 real
## AI duels. All scenarios/selections are fixed before outcomes. The original
## printed fixture and explicit income proxy are inherited from the base tool.
## No forced winners, scripted guardians, prices or full-run survival model.

const Items := preload("res://src/expedition/artifacts.gd")
const RECIPES := ["mndp", "unsm", "repr", "prfy", "enlh", "aslt"]

func _arg(name: String, fallback := "") -> String:
	var defaults := {"limit": "96", "total-ms": "600000", "game-ms": "30000", "think-ms": "0", "nodes": "12000",
		"player-level": "4", "player-life": "28", "enemy-level": "6", "enemy-life": "30", "enemy-style": "pressure"}
	return super._arg(name, str(defaults.get(name, fallback)))

func _cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	if not ELCombatBrain.available:
		printerr("This controlled field-artifact experiment requires the native combat extension.")
		return cases
	for recipe_index in RECIPES.size():
		var id: String = RECIPES[recipe_index]
		if id not in Items.available(profile):
			printerr("Missing printed recipe: " + id)
			return []
		for faction_index in FACTIONS.size():
			var style := "pressure" if (faction_index + recipe_index) % 2 == 0 else "engine"
			for first_side in 2:
				for equipped: bool in [false, true]:
					cases.append({"type": "combat", "recipe_id": id, "variant": id if equipped else "base",
						"field_id": id if equipped else "", "field_starting_charges": 2 if equipped else 0,
						"faction": FACTIONS[faction_index], "style": style,
						"enemy_faction": FACTIONS[(faction_index + 1 + recipe_index / 2) % 4],
						"enemy_style": "engine" if style == "pressure" else "pressure",
						"first_side": first_side, "seed": 51515 + recipe_index * 1009 + faction_index * 101,
						"repeat": recipe_index, "recipe": Items.find(profile, id)})
	return cases

func _play(spec: Dictionary) -> Dictionary:
	var result := spec.duplicate(true)
	var player := {"faction": spec.faction, "cards": _book(spec.faction, spec.style),
		"health": int(_arg("player-life")), "level": int(_arg("player-level")),
		"skills": {"PRVD": 0}, "specialization": "NONE", "artifacts": []}
	if not str(spec.field_id).is_empty(): player.artifacts.append(Items.battle_entry(profile, spec.field_id, spec.field_starting_charges))
	var enemy := {"id": "authored-proxy-" + str(spec.enemy_faction), "title": "Authored benchmark opponent",
		"faction": spec.enemy_faction, "cards": _book(spec.enemy_faction, spec.enemy_style),
		"health": int(_arg("enemy-life")), "level": int(_arg("enemy-level")),
		"skills": {}, "specialization": "NONE"}
	result.player_level = player.level
	result.player_starting_life = player.health
	result.enemy_level = enemy.level
	result.enemy_starting_life = enemy.health
	result.player_cards = player.cards.duplicate()
	result.enemy_cards = enemy.cards.duplicate()
	result.player_page_count = player.cards.size()
	result.enemy_page_count = enemy.cards.size()
	result.winner = -1
	result.rounds = 0
	result.player_life = player.health
	result.enemy_life = enemy.health
	result.elapsed_ms = 0
	result.refused = 0
	result.empty = 0
	result.status = "invalid"
	result.artifact_events = []
	result.artifact_uses = 0
	result.artifact_remaining = int(spec.field_starting_charges)
	for actor: Dictionary in [player, enemy]:
		for code: String in actor.cards:
			if ELCatalog.rule(profile, code).is_empty() or not ELDuelCosts.spell_allowed(profile, code, actor.faction):
				result.error = "Unavailable/wrong-faction benchmark card: " + code
				failures += 1
				return result
	ELCombatSearch.reset_caches()
	var duel := ELDuel.new()
	if not duel.start(profile, int(spec.seed), {"adventure": true, "players": [player, enemy],
			"first_side": spec.first_side, "arena": "Green.001", "opening_slots": [-1, -1]}):
		result.error = duel.error
		failures += 1
		return result
	duel.smart_sides.assign([0, 1])
	result.player_starting_charges = _charges(duel.heroes[0])
	result.enemy_starting_charges = _charges(duel.heroes[1])
	result.opening_rng = duel.rng_state
	result.player_opening_hand = duel.heroes[0].hand.duplicate()
	result.player_opening_slots = duel.heroes[0].hand_slots.duplicate()
	result.enemy_opening_hand = duel.heroes[1].hand.duplicate()
	result.enemy_opening_slots = duel.heroes[1].hand_slots.duplicate()
	result.initial_artifacts = duel.heroes[0].artifacts.duplicate(true)
	result.artifact_use_limit = duel.artifact_limit(0)
	if Items.remaining_charges(profile, spec.field_id, spec.field_starting_charges, duel.heroes[0].artifacts) != int(spec.field_starting_charges):
		result.error = "Initial field artifact did not match its canonical recipe."
		failures += 1
		return result
	var began := Time.get_ticks_msec()
	var refused_before := ELPracticeAI.refused
	var empty_before := ELPracticeAI.empty
	var commands := 0
	var phase_commands := 0
	var native_searches := 0
	var cursor := duel.history.size()
	var mark: Array = []
	var game_limit := clampi(int(_arg("game-ms")), 1000, 300000)
	result.status = "running"
	while duel.phase != ELDuel.Phase.FINISHED:
		if Time.get_ticks_msec() - began >= game_limit:
			result.status = "timeout"
			break
		if duel.round_number > 45 or commands >= 900:
			result.status = "limit"
			break
		var now := [duel.round_number, duel.attacker, duel.phase]
		if now != mark:
			mark = now
			phase_commands = 0
		phase_commands += 1
		if phase_commands > 80:
			result.status = "stalled"
			break
		var before_round := duel.round_number
		var before_artifact_round := duel.artifact_round()
		ELPracticeAI.step(duel)
		if ELPracticeAI.last_decision.get("engine") in ["native", "proof", "beyond"]: native_searches += 1
		commands += 1
		for index in range(cursor, duel.history.size()):
			var event: Dictionary = duel.history[index]
			if event.get("kind") == "artifact" and int(event.get("side", -1)) == 0 and str(event.get("artifact", "")).begins_with(Items.NAME_PREFIX):
				var seen := event.duplicate(true)
				seen.round_before_command = before_round
				seen.artifact_round_before_command = before_artifact_round
				seen.command = commands
				result.artifact_events.append(seen)
		cursor = duel.history.size()
	if duel.phase == ELDuel.Phase.FINISHED:
		result.status = "finished"
		result.winner = duel.winner
	result.rounds = duel.round_number
	result.player_life = int(duel.heroes[0].health)
	result.enemy_life = int(duel.heroes[1].health)
	result.elapsed_ms = Time.get_ticks_msec() - began
	result.commands = commands
	result.native_searches = native_searches
	result.player_remaining_charges = _charges(duel.heroes[0])
	result.enemy_remaining_charges = _charges(duel.heroes[1])
	result.artifact_uses = int(duel.heroes[0].artifact_uses)
	result.artifact_remaining = Items.remaining_charges(profile, spec.field_id, spec.field_starting_charges, duel.heroes[0].artifacts)
	result.artifact_charges_spent = int(spec.field_starting_charges) - int(result.artifact_remaining)
	result.final_artifacts = duel.heroes[0].artifacts.duplicate(true)
	result.refused = ELPracticeAI.refused - refused_before
	result.empty = ELPracticeAI.empty - empty_before
	if result.status != "finished" or result.refused > 0 or result.empty > 0 or result.artifact_remaining < 0:
		failures += 1
	if result.artifact_uses != result.artifact_events.size() or result.artifact_uses != result.artifact_charges_spent or result.artifact_uses > result.artifact_use_limit:
		result.charge_or_use_mismatch = true
		failures += 1
	return result

func _write(row: Dictionary) -> void:
	var annotated := row.duplicate(true)
	if annotated.get("type") == "settings":
		annotated.experiment = "96 paired real-AI duels: six recipes, four factions, both starts, base versus one two-charge custom artifact."
		annotated.scenarios = "Pressure/engine alternates by faction and recipe; opposing style is complementary; opponent faction shifts by 1/2/3 across recipe pairs."
		annotated.powers_applied = []
		annotated.artificer_skill = false
		annotated.artificer_specialization = false
		annotated.artifact_use_budget = 1
		annotated.prices_simulated = false
		annotated.persistent_charge_economy_simulated = false
		annotated.limitations = Array(annotated.limitations).duplicate()
		annotated.limitations.append("Each duel starts with two item charges, but the normal unskilled hero can use only one. Single-duel outcomes do not value the remaining charge, construction, camp action or 20-gold recharge.")
	super._write(annotated)
