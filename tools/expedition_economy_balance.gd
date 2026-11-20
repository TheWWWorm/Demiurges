extends SceneTree
## Reproducible route/economy audit, NOT a combat win-rate simulation.
## Every full route is enumerated. Gold uses the production settlement code
## for hypothetical victories; no battle is played and no win probability or
## incoming damage is inferred. Healing figures are uncapped opportunities,
## so actual recovery will be lower when the hero is already healthy.
##
## godot --headless --path game --script ../tools/expedition_economy_balance.gd -- --seeds=256 --rules=8
## Optional --output=/absolute/report.json writes the machine-readable report.

const Fixture := preload("expedition_fixture.gd")
const ROOT := "user://expedition_economy_balance"
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _argument(name: String, fallback := "") -> String:
	var prefix := "--" + name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func _run() -> void:
	var count := clampi(int(_argument("seeds", "256")), 1, 4096)
	var rules := clampi(int(_argument("rules", "8")), 8, ELExpeditionRun.SAVE_VERSION)
	var profile := Fixture.profile_at(ROOT)
	if profile == null:
		printerr("Synthetic fixture could not be prepared")
		quit(1)
		return
	var report := {"rules_version": rules, "seeds": count, "acts": [], "prices": [],
		"assumptions": [
			"Synthetic hero/card tables support the real seeded route and economic choice APIs; original combat balance is not measured.",
			"All complete routes are enumerated and weighted equally, not interpreted as player-selection probabilities.",
			"Gold assumes victory at every scheduled combat, round 7, no optional event duels, no owned relics, and no active contract.",
			"Spendable combat gold excludes the final guardian's payout. Event income, skipped relic income, and purchases are not included in base gold.",
			"Relic healing is an opportunity ceiling before missing-health caps, not realized recovery.",
			"Courier usefulness is evaluated only in Act III: payment must occur before a later spending opportunity, including the final haven in rules 9.",
			"An enabled courier offer promises a possible route, not guaranteed payment if the player subsequently chooses fewer combats.",
		]}
	if rules >= 10:
		report.assumptions.append("Crown foregone recovery models ownership immediately after guardian I, without weighting whether that seed offers Crown. It counts that guardian's following spell reward and later nonfinal scheduled victories. It excludes relic supplies, camp, event, merchant, and act-transition recovery.")
		report.assumptions.append("Heart pricing is a separate controlled ownership scenario; its surcharge and Seal discount multiply before one upward rounding, after Stone's flat removal reduction. Act I prices are arithmetic probes only because the first keystone is acquired after that act's guardian. No full-run expected value or combat benefit is inferred.")
	for chapter in range(1, ELExpeditionRun.ACTS + 1):
		var summary := _summary(chapter)
		for seed_value in count:
			var run := ELExpeditionRun.new()
			if not run.create(profile, "ExpeditionFixtureRed", seed_value, rules):
				failures += 1
				continue
			run._reset(profile, run.preset, seed_value, chapter)
			run.health = run.max_health
			var nodes := {}
			var payouts := {}
			var courier_available := {}
			for row: Array in run.route():
				for room: Dictionary in row:
					nodes[room.id] = room
					if room.kind in ELExpeditionRun.COMBAT_ROOMS:
						payouts[room.id] = _hypothetical_gold(run, room)
					elif room.kind == "event" and int(room.get("event", -1)) == 6:
						run.current = room.id
						run.phase = "event"
						run.gold = 9999
						for offer: Dictionary in run.choices():
							if offer.id == "courier_contract": courier_available[room.id] = not bool(offer.get("disabled", false))
			var paths: Array[Array] = []
			for room: Dictionary in run.route().front(): _paths(nodes, room.id, [], paths)
			for path: Array in paths: _measure(summary, nodes, payouts, courier_available, path, run.max_health, rules)
			if seed_value == 0: report.prices.append(_prices(run))
		_summarize(summary)
		report.acts.append(summary)
		print("ACT ECONOMY ", JSON.stringify(summary, "", true))
	print("PRICE PROBES ", JSON.stringify(report.prices, "", true))
	var output := _argument("output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			printerr("Could not write requested economy report: ", output)
			failures += 1
		else:
			file.store_string(JSON.stringify(report, "\t", true) + "\n")
			file.close()
	Fixture.clean(ROOT)
	print("EXPEDITION ECONOMY: %d seeds x 3 acts, %d error(s); no combat outcomes measured" % [count, failures])
	quit(0 if failures == 0 else 1)

func _hypothetical_gold(run: ELExpeditionRun, room: Dictionary) -> int:
	# This deliberately calls only the economy settlement routine. A duel
	# object supplies its round number; it is never started or played.
	run.current = room.id
	run.gold = 0
	run.relics.clear()
	run._contract_remaining = 0
	var duel := ELDuel.new()
	duel.round_number = 7
	run._settle_victory(duel)
	return run.gold

func _paths(nodes: Dictionary, id: String, earlier: Array, result: Array[Array]) -> void:
	var path := earlier.duplicate()
	path.append(id)
	var room: Dictionary = nodes[id]
	if room.next.is_empty():
		result.append(path)
		return
	for next: String in room.next: _paths(nodes, next, path, result)

func _summary(chapter: int) -> Dictionary:
	return {"act": chapter, "routes": 0, "min_combats": 99, "max_combats": 0,
		"min_spendable_combat_gold": 999999, "max_spendable_combat_gold": 0,
		"combats": 0.0, "elites": 0.0, "shops": 0.0, "final_havens": 0.0, "camps": 0.0, "events": 0.0, "treasures": 0.0,
		"spendable_combat_gold": 0.0, "silver_scale_gold": 0.0, "hunters_badge_gold": 0.0,
		"amber_seed_healing_ceiling": 0.0, "travel_rations_healing_ceiling": 0.0, "pilgrims_flask_extra_healing_ceiling": 0.0,
		"normal_spell_reward_recovery_ceiling": 0.0, "crown_foregone_recovery_ceiling_from_guardian_I": 0.0,
		"courier_routes": 0, "courier_insufficient_future_victories": 0, "courier_no_useful_payment": 0,
		"courier_enabled_routes": 0, "courier_enabled_unfulfilled_routes": 0,
		"last_floor_elite_routes": 0, "no_merchant_routes": 0}

func _measure(summary: Dictionary, nodes: Dictionary, payouts: Dictionary, courier_available: Dictionary, path: Array, maximum: int, rules: int) -> void:
	var fights := 0
	var gold := 0
	var shops := 0
	var has_haven: bool = rules >= 9 and int(summary.act) == ELExpeditionRun.ACTS
	if has_haven:
		summary.final_havens += 1
		summary.travel_rations_healing_ceiling += 2
		shops += 1
	for index in path.size():
		var room: Dictionary = nodes[path[index]]
		var final_guardian: bool = summary.act == ELExpeditionRun.ACTS and room.kind == "boss"
		if room.kind in ELExpeditionRun.COMBAT_ROOMS:
			fights += 1
			if not final_guardian:
				gold += int(payouts[room.id])
				summary.silver_scale_gold += 6
				summary.amber_seed_healing_ceiling += 2
				summary.normal_spell_reward_recovery_ceiling += ceili(maximum * 0.2)
				if rules >= 10 and (int(summary.act) > 1 or room.kind == "boss"):
					summary.crown_foregone_recovery_ceiling_from_guardian_I += ceili(maximum * 0.2)
				if room.kind in ["elite", "boss"]: summary.hunters_badge_gold += 20
		else:
			summary.travel_rations_healing_ceiling += 2
		match room.kind:
			"elite":
				summary.elites += 1
				if int(room.floor) == path.size() - 1: summary.last_floor_elite_routes += 1
			"shop":
				summary.shops += 1
				shops += 1
			"rest":
				summary.camps += 1
				summary.pilgrims_flask_extra_healing_ceiling += ceili(maximum * 0.45) - ceili(maximum * 0.3)
			"event": summary.events += 1
			"treasure": summary.treasures += 1
		if int(summary.act) == ELExpeditionRun.ACTS and room.kind == "event" and int(room.get("event", -1)) == 6:
			summary.courier_routes += 1
			var offered: bool = courier_available.get(room.id, false)
			if offered: summary.courier_enabled_routes += 1
			var future: Array[int] = []
			for later in range(index + 1, path.size()):
				var kind: String = nodes[path[later]].kind
				if kind in ELExpeditionRun.COMBAT_ROOMS and (not has_haven or kind != "boss"): future.append(later)
			if future.size() < 2:
				summary.courier_insufficient_future_victories += 1
				summary.courier_no_useful_payment += 1
				if offered: summary.courier_enabled_unfulfilled_routes += 1
			else:
				var spend_after := has_haven
				for later in range(future[1] + 1, path.size()):
					var next: Dictionary = nodes[path[later]]
					if next.kind == "shop" or (next.kind == "event" and int(next.get("event", -1)) in [5, 7, 8, 10, 11, 12]): spend_after = true
				if not spend_after:
					summary.courier_no_useful_payment += 1
					if offered: summary.courier_enabled_unfulfilled_routes += 1
	summary.routes += 1
	summary.combats += fights
	summary.spendable_combat_gold += gold
	summary.min_combats = mini(int(summary.min_combats), fights)
	summary.max_combats = maxi(int(summary.max_combats), fights)
	summary.min_spendable_combat_gold = mini(int(summary.min_spendable_combat_gold), gold)
	summary.max_spendable_combat_gold = maxi(int(summary.max_spendable_combat_gold), gold)
	if shops == 0: summary.no_merchant_routes += 1

func _summarize(summary: Dictionary) -> void:
	var count := maxf(1.0, float(summary.routes))
	for key: String in summary.keys():
		if summary[key] is float: summary[key] = snappedf(float(summary[key]) / count, 0.001)
	summary.no_merchant_fraction = snappedf(float(summary.no_merchant_routes) / count, 0.0001)
	summary.last_floor_elite_fraction = snappedf(float(summary.last_floor_elite_routes) / count, 0.0001)
	if int(summary.courier_routes) > 0:
		summary.courier_no_useful_payment_fraction = snappedf(float(summary.courier_no_useful_payment) / float(summary.courier_routes), 0.0001)
	if int(summary.courier_enabled_routes) > 0:
		summary.courier_enabled_unfulfilled_fraction = snappedf(float(summary.courier_enabled_unfulfilled_routes) / float(summary.courier_enabled_routes), 0.0001)

func _prices(run: ELExpeditionRun) -> Dictionary:
	for row: Array in run.route():
		for room: Dictionary in row:
			if room.kind == "shop":
				run.current = room.id
				run.phase = "shop"
				break
	run._prepare_shop()
	run.gold = 9999
	run.health = 1
	var result := {"act": run.act, "maximum_life_assumed": run.max_health, "shop_healing_amount": run._heal_amount(0.35),
		"camp_healing_amount": run._heal_amount(0.3), "flask_camp_healing_amount": run._heal_amount(0.45),
		"paid_removal_prices": [], "stone_removal_prices": [], "merchant_seal_removal_prices": [], "stone_and_seal_removal_prices": [], "relic_prices": {}}
	for id: String in ELExpeditionContent.RELICS: result.relic_prices[id] = run._shop_relic_price(id)
	for mode: String in ["paid", "stone", "merchant_seal", "stone_and_seal"]:
		run.relics.clear()
		if mode in ["stone", "stone_and_seal"]: run.relics.append("purifier_stone")
		if mode in ["merchant_seal", "stone_and_seal"]: run.relics.append("merchant_seal")
		for removals in 4:
			run._removals = removals
			for choice: Dictionary in run._shop_choices():
				if str(choice.id).begins_with("shop_remove:"):
					result[mode + "_removal_prices"].append(choice.cost)
					break
		if mode == "paid":
			for choice: Dictionary in run._shop_choices():
				if choice.id == "shop_heal": result.shop_healing_price = choice.cost
				elif str(choice.id).begins_with("buy_relic:"):
					result.sample_relic = choice.relic
					result.sample_relic_price = choice.cost
	if run.evolved():
		run.relics.clear()
		run.keystones.assign(["living_heart"])
		run._removals = 0
		result.heart_only_prices = {"heal": run._merchant_price(24), "provisions": run._merchant_price(16),
			"common_spell": run._merchant_price(30 + 3 * (run.act - 1)), "first_removal": run._removal_price()}
		run.relics.assign(["merchant_seal", "purifier_stone"])
		result.heart_seal_stone_prices = {"heal": run._merchant_price(24), "provisions": run._merchant_price(16),
			"common_spell": run._merchant_price(30 + 3 * (run.act - 1)), "removals": []}
		for count in 4:
			run._removals = count
			result.heart_seal_stone_prices.removals.append(run._removal_price())
		if result.heart_only_prices.heal != 29 or result.heart_only_prices.provisions != 20 or result.heart_only_prices.first_removal != 48 or result.heart_seal_stone_prices.heal != 24 or result.heart_seal_stone_prices.provisions != 16 or result.heart_seal_stone_prices.removals != [15, 29, 44, 58]:
			failures += 1
			printerr("Heart/Seal/Stone pricing does not match the single-rounding contract in Act ", run.act)
	return result
