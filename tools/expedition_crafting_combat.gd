extends "expedition_combat_balance.gd"
## Bounded actual-AI recipe comparison. Reuses the established fixture,
## native search, duel loop, timeout/stall guards, and outcome reporting.
## Exactly eight paired starter matchups per treatment; forty games maximum.
## Forge and Anvil gold prices are recorded, not priced as single-duel life.
## These are Forge exchanges, NOT Mirror exchanges: no 3-life cost is claimed.
## godot --headless --path game --script ../tools/expedition_crafting_combat.gd -- \
##   --fixture=/path/to/expedition_balance/fixture.json \
##   --output=/tmp/expedition-crafting-combat.jsonl --think-ms=0 --nodes=25000

const Crafting := preload("res://src/expedition/crafting.gd")
const STUDIES := {"Red": "red_raiders", "Green": "green_grove", "Blue": "blue_sky", "Black": "black_toxin"}
const TREATMENTS := ["base", "forge_a", "forge_b", "anvil_a", "anvil_b"]
var plans := {}
var active_case := {}

func _arg(name: String, fallback := "") -> String:
	var defaults := {"limit": "40", "total-ms": "240000", "game-ms": "30000", "think-ms": "0", "nodes": "25000",
		"player-level": "1", "player-life": "24", "enemy-level": "2", "enemy-life": "15", "enemy-style": "starter"}
	return super._arg(name, str(defaults.get(name, fallback)))

func _cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not ELCombatBrain.available:
		printerr("This controlled crafting experiment requires the native combat search extension.")
		return result
	for index in FACTIONS.size():
		var faction: String = FACTIONS[index]
		var original := super._book(faction, "starter")
		var room_seed := 81011 + index * 257
		var two := Crafting.recipes(profile, faction, original, original, 1, room_seed, STUDIES[faction], 2)
		var usable: Array[Dictionary] = []
		for row: Dictionary in two:
			if row.incoming.size() == 2: usable.append(row)
		# Prefer a cheap duplicate creature; lowest cost and printed code break
		# ties deterministically. Never select a recipe after seeing outcomes.
		usable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_creature: bool = profile.table("CombatSpells")[a.source].get("Class") == "Creature"
			var b_creature: bool = profile.table("CombatSpells")[b.source].get("Class") == "Creature"
			var a_cost := ELEncyclopaedia.cost(profile, a.source)
			var b_cost := ELEncyclopaedia.cost(profile, b.source)
			var a_priority := 0 if a_creature and a_cost <= 3 else (1 if a_creature else 2)
			var b_priority := 0 if b_creature and b_cost <= 3 else (1 if b_creature else 2)
			if a_priority != b_priority: return a_priority < b_priority
			if a_cost != b_cost: return a_cost < b_cost
			return str(a.source) < str(b.source))
		if usable.is_empty():
			printerr("No two-choice printed Anvil recipe for " + faction)
			return []
		var chosen: Dictionary = usable[0]
		var one := Crafting.recipes(profile, faction, original, original, 1, room_seed, STUDIES[faction], 1)
		var same_source := one.filter(func(row: Dictionary) -> bool: return row.source == chosen.source)
		if same_source.size() != 1 or same_source[0].incoming != chosen.incoming:
			printerr("Forge and Anvil must offer the same two cards to isolate page consumption: " + faction)
			return []
		plans[faction] = {"act": 1, "room_seed": room_seed, "study": STUDIES[faction], "source": chosen.source,
			"source_name": _title(chosen.source), "source_cost": ELEncyclopaedia.cost(profile, chosen.source),
			"alternatives": chosen.incoming.duplicate(), "original_cards": original.duplicate()}
		_write({"type": "recipe_plan", "faction": faction, "plan": plans[faction]})
	for treatment: String in TREATMENTS:
		for index in FACTIONS.size():
			var faction: String = FACTIONS[index]
			var plan: Dictionary = plans[faction]
			var consume := 2 if treatment.begins_with("anvil_") else (1 if treatment.begins_with("forge_") else 0)
			var incoming := "" if consume == 0 else str(plan.alternatives[1 if treatment.ends_with("_b") else 0])
			for first_side in 2:
				result.append({"type": "combat", "variant": treatment, "style": "starter", "faction": faction,
					"enemy_faction": FACTIONS[(index + 1) % FACTIONS.size()], "first_side": first_side,
					"seed": 41213 + index * 101, "repeat": 0, "recipe_act": 1, "recipe_room_seed": plan.room_seed,
					"study_path": plan.study, "recipe_source": plan.source, "recipe_source_name": plan.source_name,
					"recipe_source_cost": plan.source_cost, "recipe_consume": consume,
					"recipe_incoming": incoming, "recipe_incoming_name": _title(incoming) if consume > 0 else "",
					"recipe_incoming_cost": ELEncyclopaedia.cost(profile, incoming) if consume > 0 else 0,
					"recipe_gold_price": 12 if consume == 2 else (32 if consume == 1 else 0),
					"recipe_life_price": 0, "gold_opportunity_cost_simulated": false})
	return result

func _book(faction: String, style: String) -> Array[String]:
	var cards := super._book(faction, style)
	if active_case.is_empty() or faction != active_case.faction or style != "starter": return cards
	for index in int(active_case.recipe_consume): cards.erase(active_case.recipe_source)
	if int(active_case.recipe_consume) > 0: cards.append(active_case.recipe_incoming)
	return cards

func _play(spec: Dictionary) -> Dictionary:
	active_case = spec.duplicate(true)
	var result := super._play(spec)
	active_case = {}
	var original: Array = plans[spec.faction].original_cards
	result.original_player_cards = original.duplicate()
	result.active_pages_before = original.size()
	result.active_pages_after = result.player_cards.size()
	result.source_copies_before = original.count(spec.recipe_source)
	result.source_copies_after = result.player_cards.count(spec.recipe_source)
	result.incoming_copies_before = original.count(spec.recipe_incoming) if not str(spec.recipe_incoming).is_empty() else 0
	result.incoming_copies_after = result.player_cards.count(spec.recipe_incoming) if not str(spec.recipe_incoming).is_empty() else 0
	result.original_charge_capacity = original.size() * ELSpellCharges.providence({"PRVD": 0})
	result.expected_charge_capacity = result.player_cards.size() * ELSpellCharges.providence({"PRVD": 0})
	if result.status != "invalid" and int(result.get("player_starting_charges", -1)) != int(result.expected_charge_capacity):
		result.charge_mismatch = true
		failures += 1
	return result

func _title(code: String) -> String:
	return profile.text(str(profile.table("CombatSpells").get(code, {}).get("Name", code)))

func _write(row: Dictionary) -> void:
	var annotated := row.duplicate(true)
	if annotated.get("type") == "settings":
		annotated.experiment = "Paired affordable Forge/Anvil preparation, four recorded starters, five treatments, both starting sides; forty duels maximum."
		annotated.recipe_selection = "Deterministic cheapest duplicated creature with two legal affordable recipe choices, before any outcomes."
		annotated.gold_opportunity_cost_simulated = false
		annotated.mirror_life_cost_applied = false
		annotated.transaction = "One-page treatment is gold-only Forge (32 gold), not Mirror; two-page treatment is Anvil (12 gold). Prices are recorded but not valued by this single-duel comparison."
	super._write(annotated)
