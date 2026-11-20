extends "expedition_combat_balance.gd"
## Paired live-AI probes for rules 13. No assigned winner or injected lethal.
## Inherits the disclosed wiki-card / interpolated-income benchmark. Players
## gain only the supplied guardian powers; base and power games share books,
## seeds, income, side order and AI budgets. No campaign scripts are claimed.

const POWER_PAIRS := {
	"Red": ["power_burnout", "power_crystal_ball"],
	"Green": ["power_ether_feeding", "power_martyrdom"],
	"Blue": ["power_hostile_ambience", "power_concentration"],
	"Black": ["power_second_birth", "power_data_attraction"],
}

func _profile(installation: String) -> ELProfile:
	var source := super._profile(installation)
	if source != null and installation.is_empty():
		# Metadata absent from the earlier printed fixture. Exact code/ranks
		# are documented by wiki/catalog/en.json skill-conc; the real engine
		# supplies its every-fourth/third/second-own-turn draw behavior.
		for rank in 3:
			source.tables.HeroesSkills["CONC" + str(rank + 1)] = {"Code": "CONC", "Level": rank + 1, "Name": "Concentration", "Duel": "True"}
	return source

func _book(faction: String, style: String) -> Array[String]:
	if style != "pale": return super._book(faction, style)
	var book := super._book(faction, "engine")
	# Explicit authored Pale variant: retain the faction engine, replace
	# four pages with two copies each of existing summonable Pale creatures.
	for pair: Array in [[0, "SMFX"], [1, "SMFX"], [2, "OUS1"], [3, "OUS1"]]:
		book[pair[0]] = pair[1]
	return book

func _cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for style: String in _arg("styles", "pressure,engine,thin,pale").split(",", false):
		if style not in ["pressure", "engine", "thin", "pale"]: return []
		for index in FACTIONS.size():
			var faction: String = FACTIONS[index]
			if faction not in _arg("factions", ",".join(FACTIONS)).split(",", false): continue
			var plans: Array[Array] = [[]]
			if style == "pale": plans.append(["power_transfer_aspects"])
			else:
				for id: String in POWER_PAIRS[faction]: plans.append([id])
				plans.append(["power_energy_barrier"])
				plans.append(POWER_PAIRS[faction].duplicate())
			for repeat_index in clampi(int(_arg("repeats", "1")), 1, 8):
				for plan: Array in plans:
					for first_side in 2:
						var powers: Array[String] = []
						powers.assign(plan)
						result.append({"type": "combat", "variant": "+".join(powers) if not powers.is_empty() else "base",
							"powers": powers, "style": style, "faction": faction, "enemy_faction": FACTIONS[(index + clampi(int(_arg("enemy-shift", "1")), 1, 3) + repeat_index % 3) % 4],
							"first_side": first_side, "seed": 43113 + repeat_index * 1009 + index * 101, "repeat": repeat_index})
	return result

func _play(spec: Dictionary) -> Dictionary:
	var result := spec.duplicate(true)
	var starter: bool = spec.style in ["starter", "starter12"]
	var level := int(_arg("player-level", "1" if starter else "3"))
	var health := int(_arg("player-life", "24" if starter else "28"))
	if spec.variant == "living_heart": health += 8
	var maximum := health
	if spec.variant == "wounded": health -= 6
	if spec.variant in ["prism", "prism_crest"]: level += int(_arg("prism-bonus", "1"))
	if spec.variant in ["crest", "prism_crest"]: level += int(_arg("crest-bonus", "2"))
	if spec.variant == "level2": level += 2
	if spec.variant == "level3": level += 3
	if spec.variant == "blood_crown": level += 1
	level = clampi(level, 1, 20)
	var player := {"faction": spec.faction, "cards": _book(spec.faction, spec.style),
		"health": health, "level": level, "skills": {"PRVD": 0}, "specialization": "NONE"}
	player = ELExpeditionAttunements.prepare_hero(player, spec.powers)
	var enemy := {"id": "authored-proxy-" + str(spec.enemy_faction), "title": "Authored benchmark opponent",
		"faction": spec.enemy_faction, "cards": _book(spec.enemy_faction, _arg("enemy-style", "starter" if starter else "pressure")),
		"health": int(_arg("enemy-life", "10" if starter else "25")), "level": int(_arg("enemy-level", "1" if starter else "5")),
		"skills": {}, "specialization": "NONE"}
	if spec.variant in ["veteran_hp", "veteran", "veteran_overcharged", "veteran_fortified"]:
		enemy.health = ceili(float(enemy.health) * 1.15)
	if spec.variant in ["veteran_level", "veteran", "veteran_overcharged", "veteran_fortified"]:
		enemy.level = mini(20, int(enemy.level) + 1)
	result.enemy_base_level = enemy.level
	result.enemy_base_life = enemy.health
	var variant_error := ""
	if spec.variant in ["overcharged", "veteran_overcharged"]:
		if int(enemy.level) >= 20: variant_error = "Overcharged requires an enemy below level 20."
		else:
			enemy.level = int(enemy.level) + 1
			enemy.health = maxi(1, ceili(float(enemy.health) * 0.85))
	elif spec.variant in ["fortified", "veteran_fortified"]:
		if int(enemy.level) <= 1: variant_error = "Fortified requires an enemy above level 1."
		else:
			enemy.level = int(enemy.level) - 1
			enemy.health = ceili(float(enemy.health) * 1.25)
	if spec.variant == "tactics":
		enemy = ELExpeditionEncounters.apply_tactics(profile, enemy, "elite", int(_arg("act", "1" if starter else "2")), 3, int(spec.seed))
	result.player_level = level
	result.player_starting_life = health
	result.enemy_level = enemy.level
	result.enemy_starting_life = enemy.health
	result.player_cards = player.cards
	result.enemy_cards = enemy.cards
	result.strategy = enemy.get("strategy_id", "")
	result.winner = -1
	result.rounds = 0
	result.player_life = health
	result.enemy_life = enemy.health
	result.elapsed_ms = 0
	result.status = "invalid"
	if not variant_error.is_empty():
		result.error = variant_error
		failures += 1
		return result
	for side: Dictionary in [player, enemy]:
		for card: String in side.cards:
			if ELCatalog.rule(profile, card).is_empty() or not ELDuelCosts.spell_allowed(profile, card, side.faction):
				result.error = "Unavailable/wrong-faction benchmark card: " + card
				failures += 1
				return result
	ELCombatSearch.reset_caches()
	var duel := ELDuel.new()
	if not duel.start(profile, int(spec.seed), {"adventure": true, "players": [player, enemy], "first_side": spec.first_side, "arena": "Green.001"}):
		result.error = duel.error
		failures += 1
		return result
	if not ELExpeditionAttunements.apply_opening(duel, spec.powers):
		result.error = "Opening powers failed."
		failures += 1
		return result
	duel.smart_sides.assign([0, 1])
	duel.heroes[0].maximum = maximum
	result.player_starting_charges = _charges(duel.heroes[0])
	result.enemy_starting_charges = _charges(duel.heroes[1])
	var began := Time.get_ticks_msec()
	var refused_before := ELPracticeAI.refused
	var empty_before := ELPracticeAI.empty
	var commands := 0
	var phase_commands := 0
	var native_searches := 0
	var mark: Array = []
	var game_limit := clampi(int(_arg("game-ms", "30000")), 1000, 300000)
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
		ELPracticeAI.step(duel)
		if ELPracticeAI.last_decision.get("engine") in ["native", "proof", "beyond"]: native_searches += 1
		commands += 1
	if duel.phase == ELDuel.Phase.FINISHED:
		result.status = "finished"
		result.winner = duel.winner
	result.player_draws = 0
	result.power_activations = {}
	for event: Dictionary in duel.history:
		if event.get("kind") == "draw" and int(event.get("side", -1)) == 0: result.player_draws += 1
		if event.get("kind") == "ability" and int(event.get("side", -1)) == 0:
			var key := str(event.get("ability", ""))
			result.power_activations[key] = int(result.power_activations.get(key, 0)) + 1
	result.rounds = duel.round_number
	result.player_life = int(duel.heroes[0].health)
	result.enemy_life = int(duel.heroes[1].health)
	result.elapsed_ms = Time.get_ticks_msec() - began
	result.commands = commands
	result.native_searches = native_searches
	result.player_remaining_charges = _charges(duel.heroes[0])
	result.enemy_remaining_charges = _charges(duel.heroes[1])
	result.refused = ELPracticeAI.refused - refused_before
	result.empty = ELPracticeAI.empty - empty_before
	if result.status != "finished" or result.refused > 0 or result.empty > 0: failures += 1
	return result
