extends "expedition_combat_balance.gd"
## Paired real-AI opening-spell experiment. No forced winner or injected lethal.
## 4 factions x 2 authored books x 2 opponents/seeds x 3 preparations x
## both first sides = 96 duels. All selections below precede the outcomes.
## Inherits wiki card data and the disclosed interpolated-income proxy.
## Camp action value, previous damage, guardians and run economy are not priced.
## godot --headless --path game --script ../tools/expedition_v14_combat_balance.gd -- \
##   --fixture=/path/to/expedition_balance/fixture.json --output=/tmp/opening.jsonl

const OPENING_CHOICES := {
	"Red": {"pressure": ["STRT", "STRG"], "engine": ["ORSH", "FRBL"]},
	"Green": {"pressure": ["BEWK", "BEQN"], "engine": ["TNSA", "GRTN"]},
	"Blue": {"pressure": ["RVHL", "SPWR"], "engine": ["GBBR", "GBGN"]},
	"Black": {"pressure": ["BRAB", "PRFY"], "engine": ["MCWO", "WETX"]},
}

func _arg(name: String, fallback := "") -> String:
	var defaults := {"limit": "96", "total-ms": "600000", "game-ms": "30000", "think-ms": "0", "nodes": "12000",
		"player-level": "4", "player-life": "28", "enemy-level": "6", "enemy-life": "30", "enemy-style": "pressure"}
	return super._arg(name, str(defaults.get(name, fallback)))

func _cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	if not ELCombatBrain.available:
		printerr("The opening-spell experiment requires the native combat search extension.")
		return cases
	for style_index in 2:
		var style: String = ["pressure", "engine"][style_index]
		for faction_index in FACTIONS.size():
			var faction: String = FACTIONS[faction_index]
			var book := _book(faction, style)
			for repeat_index in 2:
				for variant: String in ["base", "cheap_page", "key_page"]:
					var code := "" if variant == "base" else str(OPENING_CHOICES[faction][style][0 if variant == "cheap_page" else 1])
					var slot := -1 if code.is_empty() else book.find(code)
					if not code.is_empty() and slot < 0:
						printerr("The declared opening spell must be in its unchanged active book: " + code)
						return []
					for first_side in 2:
						cases.append({"type": "combat", "variant": variant, "style": style, "faction": faction,
							"enemy_faction": FACTIONS[(faction_index + 1 + repeat_index) % 4],
							"enemy_style": "pressure" if repeat_index == 0 else "engine", "first_side": first_side,
							"seed": 47114 + faction_index * 101 + style_index * 503 + repeat_index * 1009,
							"repeat": repeat_index, "selected_code": code, "selected_slot": slot,
							"selected_name": _title(code), "selected_printed_cost": ELEncyclopaedia.cost(profile, code) if not code.is_empty() else 0,
							"selected_copies": book.count(code) if not code.is_empty() else 0,
							"opening_slots": [slot, -1], "watched_codes": OPENING_CHOICES[faction][style].duplicate()})
	return cases

func _play(spec: Dictionary) -> Dictionary:
	var result := spec.duplicate(true)
	var player := {"faction": spec.faction, "cards": _book(spec.faction, spec.style),
		"health": int(_arg("player-life")), "level": int(_arg("player-level")),
		"skills": {"PRVD": 0}, "specialization": "NONE"}
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
	for actor: Dictionary in [player, enemy]:
		for card: String in actor.cards:
			if ELCatalog.rule(profile, card).is_empty() or not ELDuelCosts.spell_allowed(profile, card, actor.faction):
				result.error = "Unavailable/wrong-faction benchmark card: " + card
				failures += 1
				return result
	ELCombatSearch.reset_caches()
	var duel := ELDuel.new()
	if not duel.start(profile, int(spec.seed), {"adventure": true, "players": [player, enemy],
			"first_side": spec.first_side, "arena": "Green.001", "opening_slots": spec.opening_slots.duplicate()}):
		result.error = duel.error
		failures += 1
		return result
	duel.smart_sides.assign([0, 1])
	result.player_starting_charges = _charges(duel.heroes[0])
	result.enemy_starting_charges = _charges(duel.heroes[1])
	result.opening_rng = duel.rng_state
	result.player_opening_hand = duel.heroes[0].hand.duplicate()
	result.player_opening_slots = duel.heroes[0].hand_slots.duplicate()
	result.player_opening_view = duel.heroes[0].hand_view.duplicate()
	result.player_opening_drawn = duel.heroes[0].drawn.duplicate()
	result.player_opening_uses = duel.heroes[0].spell_uses.duplicate()
	result.enemy_opening_hand = duel.heroes[1].hand.duplicate()
	result.enemy_opening_slots = duel.heroes[1].hand_slots.duplicate()
	result.enemy_opening_uses = duel.heroes[1].spell_uses.duplicate()
	result.opening_forced_fallback = not str(spec.selected_code).is_empty() and not duel.heroes[0].hand.slice(0, 4).has(spec.selected_code)
	result.selected_in_opening = not str(spec.selected_code).is_empty() and duel.heroes[0].hand.has(spec.selected_code)
	result.watched_events = []
	if duel.heroes[0].hand.size() != 5 or duel.heroes[1].hand.size() != 5 \
			or result.player_starting_charges != result.player_page_count * 2 \
			or result.enemy_starting_charges != result.enemy_page_count \
			or (spec.variant != "base" and not result.selected_in_opening):
		result.error = "Opening hand/card/charge invariant failed."
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
		ELPracticeAI.step(duel)
		if ELPracticeAI.last_decision.get("engine") in ["native", "proof", "beyond"]: native_searches += 1
		commands += 1
		for index in range(cursor, duel.history.size()):
			var event: Dictionary = duel.history[index]
			if int(event.get("side", -1)) == 0 and event.get("card", "") in spec.watched_codes \
					and event.get("kind", "") in ["cast", "discard", "draw", "return_card"]:
				var seen := event.duplicate(true)
				seen.round_before_command = before_round
				seen.command = commands
				result.watched_events.append(seen)
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
	result.player_final_hand = duel.heroes[0].hand.duplicate()
	result.player_final_slots = duel.heroes[0].hand_slots.duplicate()
	result.refused = ELPracticeAI.refused - refused_before
	result.empty = ELPracticeAI.empty - empty_before
	if result.status != "finished" or result.refused > 0 or result.empty > 0: failures += 1
	return result

func _title(code: String) -> String:
	if code.is_empty(): return ""
	return profile.text(str(profile.table("CombatSpells").get(code, {}).get("Name", code)))

func _write(row: Dictionary) -> void:
	var annotated := row.duplicate(true)
	if annotated.get("type") == "settings":
		annotated.experiment = "96 paired real-AI duels: four factions, two authored styles, two enemy contexts, base/cheap/key opening page, both first sides."
		annotated.selection = OPENING_CHOICES.duplicate(true)
		annotated.preparation = "One ordinary active page guaranteed by fifth-draw fallback; no additional card, charge, free cast or level."
		annotated.camp_opportunity_cost_simulated = false
		annotated.powers_applied = []
		annotated.opponents = "Repeat 0 faces next faction pressure; repeat 1 faces faction +2 engine. Both are authored proxies."
	super._write(annotated)
