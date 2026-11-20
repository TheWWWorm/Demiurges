extends SceneTree
## Headless Expedition lifecycle and seeded-content checks. This uses explicit
## synthetic maps/tables and never reads or writes the player's checkpoint.
## Run after a headless editor import with the project's supported Godot:
##   godot --headless --path game --script ../tools/expedition_expansion_check.gd

const Fixture := preload("expedition_fixture.gd")
const BASE_RULES := 8
# Each gate is evaluated before it increments the check counter itself.
const MIN_CHECKS := 286
const MIN_BALANCE_CHECKS := 88
# Captured from base commit 878d6280 before expanding the run rules. Each
# digest covers four boundary seeds and all three acts, including room seeds.
const LEGACY_ROUTES := {
	1: "e8d319da28039596bccfa41a56d08b602417d6b49cff915835181a5f9a944153",
	2: "e8d319da28039596bccfa41a56d08b602417d6b49cff915835181a5f9a944153",
	3: "751cba558c02fb6def50fb8c3d29ae3fa1b897fa1e7c2c96ccb43cad50652352",
	4: "751cba558c02fb6def50fb8c3d29ae3fa1b897fa1e7c2c96ccb43cad50652352",
	5: "751cba558c02fb6def50fb8c3d29ae3fa1b897fa1e7c2c96ccb43cad50652352",
	6: "751cba558c02fb6def50fb8c3d29ae3fa1b897fa1e7c2c96ccb43cad50652352",
	7: "751cba558c02fb6def50fb8c3d29ae3fa1b897fa1e7c2c96ccb43cad50652352",
	8: "4e43b2b819fb93aa312c0580cd1a7a9891fb3344ba5bfa0af3958405ca9e1d22",
}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures.append(label)

func _run() -> void:
	var source := Fixture.profile_at()
	check(source != null, "Synthetic campaign maps and spell tables are available")
	if source != null:
		_basics(source)
		_legacy(source)
		_routes(source)
		_journeys(source)
		if ELExpeditionRun.SAVE_VERSION >= 8:
			_boons(source)
			_shops(source)
			_deck_limits(source)
			_relic_rewards(source)
			_relic_effects(source)
			_events(source)
			_malformed(source)
		if ELExpeditionRun.SAVE_VERSION >= 9:
			var v9_start := checks
			_balanced_prices(source)
			_haven(source)
			_redraw(source)
			_difficulty(source)
			_broker_and_bounties(source)
			_swift_boundaries(source)
			_balanced_save_guards(source)
			check(checks - v9_start >= MIN_BALANCE_CHECKS, "The complete version 9 balance and lifecycle checks executed")
	check(checks >= MIN_CHECKS, "The complete integration suite executed at least %d checks" % MIN_CHECKS)
	Fixture.clean()
	print("EXPEDITION EXPANSION: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new(source: ELProfile, seed := 12345, version := BASE_RULES) -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(source, "ExpeditionFixtureRed", seed, version):
		check(false, "Create run: " + run.error)
		return null
	if run.phase == "boon" and not run.choose(str(run.choices()[0].id)):
		check(false, "Choose the starting boon: " + run.error)
		return null
	return run

func _json(raw: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(raw, "", true, true))

func _roundtrip(run: ELExpeditionRun) -> ELExpeditionRun:
	var restored := ELExpeditionRun.new()
	if not restored.restore_snapshot(run.profile, _json(run.snapshot())):
		check(false, "Restore " + run.phase + ": " + restored.error)
		return null
	return restored

func _basics(source: ELProfile) -> void:
	check(ELExpeditionRun.starters(source).size() == 4, "All four faction starters use normal shipped-preset validation")
	var run := _new(source)
	if run == null: return
	var twin := _new(source)
	check(twin != null and run.route() == twin.route(), "A seed reproduces room kinds, links and content seeds")
	var restored := _roundtrip(run)
	check(restored != null and restored.snapshot() == run.snapshot(), "The initial run survives a JSON round trip exactly")
	var before := run.snapshot()
	check(not run.choose_node("bad-node") and run.snapshot() == before, "Unavailable rooms cannot mutate the run")
	check(not run.choose("bad-choice") and run.snapshot() == before, "Unavailable actions cannot mutate the run")
	check(run.choose_node(run.available()[0]), "Enter an opening battle through the real route")
	var battle := run.build_battle()
	check(battle != null, "Synthetic campaign encounter starts a real duel: " + run.error)
	if battle == null: return
	check(battle.heroes[0].maximum == run.max_health and battle.heroes[0].health == run.health, "Persistent life and its maximum reach the duel")
	var saved := run.snapshot()
	saved.battle = battle.snapshot()
	var resumed := ELExpeditionRun.new()
	check(resumed.restore_snapshot(source, _json(saved)), "An unfinished duel checkpoint restores: " + resumed.error)
	var resumed_battle := resumed.build_battle() if resumed.phase == "battle" else null
	check(resumed_battle != null and resumed_battle.heroes == battle.heroes and resumed_battle.phase == battle.phase, "Resume retains hands, life, spell charges, and combat phase")
	_end(battle)
	check(run.resolve_battle(battle) and run.phase == "reward", "Winning a real duel produces the reward phase")
	before = run.snapshot()
	check(not run.resolve_battle(battle) and run.snapshot() == before, "The same battle cannot pay its reward twice")
	restored = _roundtrip(run)
	check(restored != null and restored.choices() == run.choices(), "Reward choices remain identical after a JSON checkpoint")

func _legacy(source: ELProfile) -> void:
	for version in range(1, BASE_RULES + 1):
		var run := _new(source, 34567, version)
		if run == null: continue
		var route := run.route()
		var floors := 8 if version == 8 else 6
		check(route.size() == floors and route.back()[0].kind == "boss", "Version %d retains its %d-floor act" % [version, floors])
		var restored := _roundtrip(run)
		check(restored != null and restored.route() == route and restored.snapshot() == run.snapshot(), "Version %d retains its route and checkpoint" % version)
		var body := ""
		for seed_value: int in [0, 1, 34567, 0xffffffff]:
			for chapter in range(1, 4):
				run._reset(source, run.preset, seed_value, chapter)
				body += JSON.stringify(run.route(), "", true, true)
		check(body.sha256_text() == LEGACY_ROUTES[version], "Version %d exactly matches the pre-expansion routes for all reference seeds and acts" % version)

func _routes(source: ELProfile) -> void:
	var all_reachable := true
	var has_exits := true
	var fewest_combats := 99
	var kinds := {}
	var distinct := {}
	for seed_value in 128:
		var run := _new(source, seed_value)
		if run == null: return
		var route := run.route()
		var reached := {}
		for id: String in run.available(): reached[id] = true
		for floor_index in route.size():
			for room: Dictionary in route[floor_index]:
				all_reachable = all_reachable and reached.has(room.id)
				kinds[room.kind] = true
				has_exits = has_exits and (not room.next.is_empty() or floor_index == route.size() - 1)
				for next: String in room.next:
					has_exits = has_exits and floor_index + 1 < route.size() and int(next.get_slice("-", 1)) == int(room.floor) + 1
					reached[next] = true
		var fingerprint := JSON.stringify(route)
		distinct[fingerprint] = true
		for chapter in range(1, ELExpeditionRun.ACTS + 1):
			run._reset(source, run.preset, seed_value, chapter)
			fewest_combats = mini(fewest_combats, _minimum_combats(run.route()))
	check(all_reachable and has_exits, "128 seeded routes have no unreachable rooms, dead ends, skips, or backward links")
	check(distinct.size() == 128, "Different test seeds produce different route/content layouts")
	if ELExpeditionRun.SAVE_VERSION >= 8:
		check(kinds.has("shop") and kinds.has("treasure") and kinds.has("elite") and kinds.has("rest"), "Expanded routes contain merchants, treasures, elites, and recovery choices")
		check(fewest_combats >= 3, "Every path across 128 seeds and all three acts requires at least three combats, excluding optional event duels")

func _minimum_combats(route: Array[Array]) -> int:
	var distance := {}
	for room: Dictionary in route.front(): distance[room.id] = 0
	var result := 99
	for row: Array in route:
		for room: Dictionary in row:
			if not distance.has(room.id): continue
			var after := int(distance[room.id]) + int(room.kind in ELExpeditionRun.COMBAT_ROOMS)
			if room.kind == "boss": result = mini(result, after)
			for next: String in room.next:
				distance[next] = mini(int(distance.get(next, 99)), after)
	return result if result < 99 else 0

func _journeys(source: ELProfile) -> void:
	var versions: Array[int] = [1, 7, BASE_RULES]
	# This is the frozen v8/v9 compatibility suite. New rules have their own
	# lifecycle checks, and must never silently replace the v9 full journey.
	if ELExpeditionRun.SAVE_VERSION >= 9: versions.append(9)
	for version: int in versions:
		var run := _new(source, 71391, version)
		if run == null: continue
		var steps := 0
		var roundtrips := true
		while not run.finished() and steps < 40:
			if run.phase != "map" or run.available().is_empty(): break
			if not run.choose_node(run.available()[0]) or not _settle(run): break
			var restored := _roundtrip(run)
			if restored == null:
				roundtrips = false
				break
			run = restored
			steps += 1
		check(run.phase == "won" and roundtrips, "Version %d completes all three acts with checkpoint reload after every room" % version)
		if run.phase == "won":
			check(run.journey().size() == 3 and run.journey().all(func(chapter: Dictionary) -> bool: return chapter.recorded), "Version %d records a complete three-act journey" % version)
			var retried := run.retry()
			check(retried != null and retried.seed_value == run.seed_value and retried._version == version, "Version %d retry preserves seed, starter, and original rules" % version)

func _settle(run: ELExpeditionRun) -> bool:
	for step in 12:
		match run.phase:
			"map", "won", "lost": return true
			"battle":
				var battle := run.build_battle()
				if battle == null:
					check(false, "Build battle during traversal: " + run.error)
					return false
				_end(battle)
				if not run.resolve_battle(battle): return false
			"reward", "relic_reward", "treasure":
				if not run.choose("skip" if run.phase == "reward" else "skip_relic"):
					check(false, "Skip optional room reward: " + run.error)
					return false
			"rest":
				if not run.choose("heal"): return false
			"event", "shop":
				if not run.choose("leave"): return false
			"haven":
				if not run.choose("enter_guardian"): return false
			"boon":
				if not run.choose(str(run.choices()[0].id)): return false
			_:
				check(false, "Unknown phase during traversal: " + run.phase)
				return false
	check(false, "A room settles within its finite choice flow")
	return false

func _path_to_kind(run: ELExpeditionRun, kind: String, event_index := -1) -> Array[String]:
	var nodes := {}
	for row: Array in run.route():
		for room: Dictionary in row: nodes[room.id] = room
	var queue: Array[Array] = []
	for id: String in run.available(): queue.append([id])
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var room: Dictionary = nodes[path.back()]
		if room.kind == kind and (event_index < 0 or int(room.get("event", -1)) == event_index):
			var result: Array[String] = []
			result.assign(path)
			return result
		for id: String in room.next:
			var next := path.duplicate()
			next.append(id)
			queue.append(next)
	return []

func _enter_kind(source: ELProfile, kind: String, seed_value := 12345, chapter := 1, version := BASE_RULES) -> ELExpeditionRun:
	var run := _new(source, seed_value, version)
	if run == null: return null
	if chapter != 1:
		run._reset(source, run.preset, seed_value, chapter)
		run.health = run.max_health
	var path := _path_to_kind(run, kind)
	if path.is_empty(): return null
	for index in path.size():
		if not run.choose_node(path[index]): return null
		if index + 1 < path.size() and not _settle(run): return null
	return run

func _end(battle: ELDuel, winner := 0) -> void:
	battle.heroes[1 - winner].health = 0
	battle.winner = winner
	battle.phase = ELDuel.Phase.FINISHED

func _option(run: ELExpeditionRun, prefix: String, enabled_only := true) -> Dictionary:
	for option: Dictionary in run.choices():
		if str(option.id).begins_with(prefix) and (not enabled_only or not bool(option.get("disabled", false))): return option
	return {}

func _boons(source: ELProfile) -> void:
	for relic: String in ["amber_seed", "silver_scale", "glass_compass"]:
		var run := ELExpeditionRun.new()
		check(run.create(source, "ExpeditionFixtureRed", 97531, BASE_RULES), "Create an expedition for starting relic " + relic)
		check(run.phase == "boon" and run.available().is_empty() and run.choices().size() == 3, "The starting relic is a real mandatory choice before the route")
		var restored := _roundtrip(run)
		check(restored != null and restored.phase == "boon" and restored.choices() == run.choices(), "An undecided starting boon resumes without losing its options")
		check(run.choose("relic:" + relic) and run.phase == "map" and run.relics == [relic] and run.gold == 40, "The selected starting relic enters the run with 40 gold")
		var before := run.snapshot()
		check(not run.choose("relic:" + relic) and run.snapshot() == before, "The starting relic cannot be taken twice")

func _shops(source: ELProfile) -> void:
	var run := _enter_kind(source, "shop")
	check(run != null and run.phase == "shop", "A merchant is reachable through a genuine seeded path")
	if run == null: return
	run.gold = 999
	var stock := run._shop_stock.duplicate()
	var restored := _roundtrip(run)
	check(restored != null and restored.choices() == run.choices() and restored._shop_stock == stock, "Merchant stock, prices and services survive a checkpoint")
	var card := _option(run, "buy_card:")
	check(not card.is_empty(), "The merchant offers a legal spell purchase")
	if card.is_empty(): return
	# A merchant may sell a spell the hero already knows. Replacing one of
	# its existing copies with the purchase must never consume gold or stock.
	var overlap := {}
	if restored != null:
		for candidate: Dictionary in restored.choices():
			if str(candidate.id).begins_with("buy_card:") and restored.deck.has(candidate.card) and not candidate.get("disabled", false):
				overlap = candidate
				break
	check(not overlap.is_empty(), "The merchant regression fixture has stock overlapping the owned spellbook")
	if not overlap.is_empty():
		check(restored.choose(overlap.id), "Stage a merchant spell already present in the owned book")
		var pending_before := restored.snapshot()
		var protected := true
		for index in restored.deck.size():
			if restored.deck[index] != restored.pending_card: continue
			var id := "replace:%d" % index
			protected = protected and not restored.choices().any(func(option: Dictionary) -> bool: return option.id == id)
			protected = protected and not restored.choose(id) and restored.snapshot() == pending_before
		check(protected, "Identical merchant replacements are absent and forced attempts preserve the deck, gold, pending purchase, and stock")
	var discounted := _roundtrip(run)
	if discounted != null:
		discounted.relics.append("merchant_seal")
		var cheaper := _option(discounted, str(card.id))
		check(not cheaper.is_empty() and int(cheaper.cost) == ceili(int(card.cost) * 0.8), "Merchant's Seal discounts a real stock item by twenty percent")
		var cash := discounted.gold
		check(discounted.choose(cheaper.id) and discounted.choose("add") and discounted.gold == cash - int(cheaper.cost), "The discounted price is the amount actually charged on confirmation")
	var before := run.snapshot()
	var money := run.gold
	check(run.choose(card.id) and run.gold == money and not run.pending_card.is_empty(), "Selecting a merchant spell defers payment until its place is confirmed")
	check(run.choose("back") and run.snapshot() == before, "Cancelling a merchant spell restores the exact prior shop without charging or consuming stock")
	check(run.choose(card.id), "Stage the same spell again after cancellation")
	restored = _roundtrip(run)
	check(restored != null and restored.pending_card == run.pending_card and restored.choices() == run.choices(), "A pending merchant replacement restores its card, price and choices")
	var outgoing := run.deck[0]
	var incoming := run.pending_card
	var size_before := run.deck.size()
	check(run.choose("replace:0") and run.phase == "shop" and run.pending_card.is_empty(), "Confirming a purchase returns to the same merchant for further shopping")
	check(run.gold < money and run.deck.size() == size_before and run.deck[0] == incoming and run._shop_stock == stock, "One payment replaces exactly one card without rerolling the merchant's stock")
	check(outgoing != incoming or run.deck.count(incoming) <= ELDuelCosts.EL2_COPIES, "A replacement respects the ordinary four-copy ceiling")
	check(_option(run, str(card.id)).is_empty(), "The purchased stock item cannot be bought a second time")
	before = run.snapshot()
	check(not run.choose("replace:0") and run.snapshot() == before, "A repeated confirmation cannot charge again")
	var remove := _option(run, "shop_remove:")
	check(not remove.is_empty() and run.choose(remove.id) and run.deck.size() == size_before - 1, "The merchant's removal service removes one spell")
	check(_option(run, "shop_remove:").is_empty(), "A merchant offers at most one removal during this visit")
	run.health = maxi(1, run.max_health - 10)
	var heal := _option(run, "shop_heal")
	check(not heal.is_empty() and run.choose(heal.id), "The merchant's restorative service can be purchased")
	check(_option(run, "shop_heal").is_empty(), "Restoration stock is consumed once at this merchant")
	restored = _roundtrip(run)
	check(restored != null and restored.snapshot() == run.snapshot(), "A merchant with several purchases resumes with the same sold stock and services")
	run.gold = 0
	var refused := 0
	for option: Dictionary in run.choices():
		if not bool(option.get("disabled", false)): continue
		before = run.snapshot()
		if not run.choose(option.id) and run.snapshot() == before: refused += 1
		else: check(false, "An unaffordable merchant action cannot mutate its visit: " + str(option.id))
	check(refused > 0, "Unaffordable merchant offers stay visible and cannot be forced through the action API")
	check(run.choose("leave") and run.phase == "map", "A penniless player can leave the merchant and continue the run")

func _relic_rewards(source: ELProfile) -> void:
	var run := _enter_kind(source, "elite")
	check(run != null and run.phase == "battle", "An elite is reachable through a real route")
	if run == null: return
	var battle := run.build_battle()
	check(battle != null, "The expanded elite starts using the real duel model")
	if battle == null: return
	var hunter := _roundtrip(run)
	if hunter != null:
		hunter.relics.append("hunters_badge")
		var hunt := hunter.build_battle()
		if hunt != null:
			_end(hunt)
			check(hunter.resolve_battle(hunt), "Hunter's Badge elite fixture completes a real duel")
	var money := run.gold
	_end(battle)
	check(run.resolve_battle(battle) and run.phase == "relic_reward" and run.gold > money, "Elite victory settles gold once and offers a relic before its spell reward")
	check(hunter != null and hunter.gold == run.gold + 20, "Hunter's Badge adds exactly twenty gold to an elite's actual reward")
	var before := run.snapshot()
	check(not run.resolve_battle(battle) and run.snapshot() == before, "Reopening the finished elite cannot duplicate gold or rewards")
	var restored := _roundtrip(run)
	check(restored != null and restored.choices() == run.choices(), "Relic reward offers remain fixed across saving")
	var offered := _option(run, "relic:")
	var count := run.relics.size()
	check(not offered.is_empty() and run.choose(offered.id) and run.phase == "reward" and run.relics.size() == count + 1, "Taking an elite relic preserves the separate spell reward")
	check(run.choose("skip") and run.phase == "map", "Finishing the spell reward returns to the route")
	var treasure := _enter_kind(source, "treasure")
	check(treasure != null, "A treasure room is reachable")
	if treasure == null: return
	money = treasure.gold
	check(treasure.choose("skip_relic") and treasure.phase == "map" and treasure.gold == money + 25, "Declining a treasure relic gives the advertised 25 gold exactly once")
	before = treasure.snapshot()
	check(not treasure.choose("skip_relic") and treasure.snapshot() == before, "A treasure cannot be collected twice")

func _malformed(source: ELProfile) -> void:
	var run := _new(source, 29101)
	if run == null: return
	var healthy := run.snapshot()
	for change: Array in [["gold", -1], ["gold", 1.5], ["gold", 10000], ["gold", "40"], ["relics", ["missing_relic"]], ["relics", ["amber_seed", "amber_seed"]], ["relics", 5], ["prepared", 1], ["contract_remaining", 3], ["contract_remaining", 0.5], ["removals", -1], ["shop", {"stock": []}], ["last_reward", {"gold": 2, "healed": 0, "contract": 0}]]:
		var damaged := healthy.duplicate(true)
		damaged[change[0]] = change[1]
		check(not run.restore_snapshot(source, _json(damaged)) and run.snapshot() == healthy, "Invalid %s=%s cannot overwrite a healthy run" % [str(change[0]), str(change[1])])
	var merchant := _enter_kind(source, "shop")
	if merchant == null: return
	merchant.gold = 999
	healthy = merchant.snapshot()
	for corruption: String in ["duplicate_stock", "unknown_card", "unknown_relic", "duplicate_purchase", "unknown_purchase", "wrong_room"]:
		var damaged := healthy.duplicate(true)
		match corruption:
			"duplicate_stock": damaged.shop.stock[1] = damaged.shop.stock[0]
			"unknown_card": damaged.shop.stock[0] = "FAKE"
			"unknown_relic": damaged.shop.relic = "fake_relic"
			"duplicate_purchase": damaged.shop.bought = ["heal", "heal"]
			"unknown_purchase": damaged.shop.bought = ["card:FAKE"]
			"wrong_room": damaged.phase = "map"
		check(not merchant.restore_snapshot(source, _json(damaged)) and merchant.snapshot() == healthy, "Malformed merchant %s cannot replace the loaded visit" % corruption)
	var offer := _option(merchant, "buy_card:")
	if not offer.is_empty() and merchant.choose(offer.id):
		healthy = merchant.snapshot()
		var damaged := healthy.duplicate(true)
		damaged.gold = 0
		check(not merchant.restore_snapshot(source, _json(damaged)) and merchant.snapshot() == healthy, "An unfunded pending merchant purchase cannot restore as confirmable")

func _deck_limits(source: ELProfile) -> void:
	var run := _enter_kind(source, "shop", 2468)
	if run == null: return
	run.gold = 999
	var offer := _option(run, "buy_card:")
	if offer.is_empty(): return
	var target := str(offer.card)
	for code: String in run._eligible_spells():
		if code == target: continue
		while run.deck.size() < ELExpeditionRun.MAX_DECK and run.deck.count(code) < ELDuelCosts.EL2_COPIES:
			run.deck.append(code)
	var before := run.snapshot()
	check(run.deck.size() == ELExpeditionRun.MAX_DECK and run.choose(offer.id) and _option(run, "add").is_empty(), "A full twenty-four-card book can buy a replacement but cannot add a twenty-fifth card")
	var pending := run.snapshot()
	check(not run.choose("add") and run.snapshot() == pending, "Forcing Add on a full book cannot spend gold or consume stock")
	check(run.choose("replace:0") and run.deck.size() == ELExpeditionRun.MAX_DECK and run.gold == int(before.gold) - int(offer.cost), "The full book can complete a paid replacement without changing size")
	var minimum := _enter_kind(source, "shop", 8642)
	if minimum == null: return
	minimum.gold = 999
	minimum.deck.resize(ELExpeditionRun.MIN_DECK)
	before = minimum.snapshot()
	check(_option(minimum, "shop_remove:").is_empty() and not minimum.choose("shop_remove:0") and minimum.snapshot() == before, "Merchant removal cannot reduce a book below eight cards")

func _victory_case(source: ELProfile, held: Array[String], round_number := 6, book_size := 16, version := BASE_RULES) -> Dictionary:
	var run := _new(source, 1267, version)
	if run == null: return {}
	run.relics.assign(held)
	while run.deck.size() > book_size: run.deck.pop_back()
	run.health = run.max_health - 7
	if not run.choose_node(run.available()[0]): return {}
	var battle := run.build_battle()
	if battle == null:
		check(false, "Relic scenario starts a real duel: " + run.error)
		return {}
	var level := int(battle.heroes[0].level)
	var health_before := int(battle.heroes[0].health)
	var gold_before := run.gold
	battle.round_number = round_number
	_end(battle)
	if not run.resolve_battle(battle): return {}
	var cards := 0
	for option: Dictionary in run.choices():
		if str(option.id).begins_with("card:"): cards += 1
	return {"run": run, "gold": run.gold - gold_before, "healed": run.health - health_before, "level": level, "cards": cards}

func _relic_effects(source: ELProfile) -> void:
	var plain := _victory_case(source, ["glass_compass"])
	var amber := _victory_case(source, ["amber_seed"])
	var silver := _victory_case(source, ["silver_scale"])
	if plain.is_empty() or amber.is_empty() or silver.is_empty():
		check(false, "Starting-relic effect fixtures finish")
		return
	check(amber.healed == 2 and plain.healed == 0, "Amber Seed heals exactly two life after a victory")
	check(silver.gold == plain.gold + 6, "Silver Scale pays six additional gold after a victory")
	check(plain.cards == amber.cards + 1, "Glass Compass increases reward variety without adding another pick")
	var restored := _roundtrip(amber.run)
	check(restored != null and restored.snapshot() == amber.run.snapshot(), "Reloading a rewarded run cannot repeat its healing or gold payout")
	var quick := _victory_case(source, ["glass_compass", "ember_purse"], 6)
	var slow := _victory_case(source, ["glass_compass", "ember_purse"], 7)
	check(not quick.is_empty() and not slow.is_empty() and quick.gold == slow.gold + 12, "Ember Purse rewards round six but not round seven")
	var prism := _victory_case(source, ["glass_compass", "aether_prism"])
	var small := _victory_case(source, ["glass_compass", "duelists_crest"], 6, 12)
	var large := _victory_case(source, ["glass_compass", "duelists_crest"], 6, 13)
	check(not prism.is_empty() and prism.level == plain.level + 1, "Ether Prism's hero level reaches the actual battle")
	check(not small.is_empty() and not large.is_empty() and small.level == plain.level + 2 and large.level == plain.level, "Duelist's Crest rewards a twelve-card book and stops at thirteen")
	var camp := _enter_kind(source, "rest")
	if camp != null:
		camp.relics.append("pilgrims_flask")
		camp.health = 1
		var expected := mini(camp.max_health, 1 + ceili(camp.max_health * 0.45))
		check(camp.choose("heal") and camp.health == expected, "Pilgrim's Flask changes the camp's actual recovery to 45 percent")
	var road := _new(source)
	if road != null:
		road.relics.append("travel_rations")
		var path := _path_to_kind(road, "event")
		for index in path.size():
			if index == path.size() - 1: road.health = road.max_health - 8
			if not road.choose_node(path[index]): break
			if index < path.size() - 1 and not _settle(road): break
		check(road.phase == "event" and road.health == road.max_health - 6, "Wayfarer's Rations heal two on entering an encounter")
		restored = _roundtrip(road)
		check(restored != null and restored.health == road.health, "Reloading the encounter does not trigger travel healing again")
	var purge := _enter_kind(source, "shop")
	if purge != null:
		purge.relics.append("purifier_stone")
		purge.gold = 0
		var remove := _option(purge, "shop_remove:")
		var old_size := purge.deck.size()
		check(not remove.is_empty() and purge.choose(remove.id) and purge.gold == 0 and purge.deck.size() == old_size - 1, "Purifier's Stone makes one real merchant removal free at zero gold")
		check(_option(purge, "shop_remove:").is_empty(), "The free removal cannot be farmed within one merchant")
	var trained := _enter_kind(source, "rest", 12345, 2)
	if trained != null:
		trained._training = {"PRVD": 2}
		check(_option(trained, "train:").is_empty(), "Two camp training sessions normally exhaust the run's allowance")
		trained.relics.append("twin_seal")
		var training := _option(trained, "train:")
		check(not training.is_empty() and trained.choose(training.id), "Master's Seal unlocks a third real camp training session")
		restored = _roundtrip(trained)
		check(restored != null and restored.trained_skills() == trained.trained_skills(), "The extra training session remains valid after checkpoint restoration")

func _enter_event(source: ELProfile, event_index: int, version := BASE_RULES, chapter := 2, minimum_floor := 0) -> ELExpeditionRun:
	for seed_value in 64:
		var run := _new(source, seed_value, version)
		if run == null: return null
		run._reset(source, run.preset, seed_value, chapter)
		run.health = run.max_health
		var path := _path_to_kind(run, "event", event_index)
		if path.is_empty(): continue
		if int(run._nodes[path.back()].floor) < minimum_floor: continue
		for index in path.size():
			if not run.choose_node(path[index]): return null
			if index + 1 < path.size() and not _settle(run): return null
		return run
	return null

func _next_battle(run: ELExpeditionRun) -> ELDuel:
	if run.phase != "map" and not _settle(run): return null
	var selected: Array[String] = []
	for kind: String in ["fight", "elite", "boss"]:
		var path := _path_to_kind(run, kind)
		if not path.is_empty() and (selected.is_empty() or path.size() < selected.size()): selected = path
	for index in selected.size():
		if not run.choose_node(selected[index]): return null
		if index + 1 < selected.size() and not _settle(run): return null
	return run.build_battle() if run.phase == "battle" else null

func _events(source: ELProfile) -> void:
	var samples := {}
	for event_index in 12:
		var run := _enter_event(source, event_index)
		check(run != null and run._event_index() == event_index, "Event %d is reachable in the expanded route bag" % event_index)
		if run == null: continue
		run.gold = 999
		run.health = run.max_health - 10
		var restored := _roundtrip(run)
		check(restored != null and restored.choices() == run.choices(), "Event %d keeps its offers and outcomes on reload" % event_index)
		samples[event_index] = run
		if restored != null:
			restored.gold = 0
			restored.health = 1
			var guarded := true
			for option: Dictionary in restored.choices():
				if not bool(option.get("disabled", false)): continue
				var before := restored.snapshot()
				guarded = guarded and not restored.choose(option.id) and restored.snapshot() == before
			check(guarded and restored.choose("leave") and restored.health > 0, "Event %d cannot force an unaffordable or fatal bargain and always permits leaving" % event_index)
	if samples.has(5):
		var caravan: ELExpeditionRun = samples[5]
		check(caravan.choose("caravan_shop") and caravan.phase == "shop", "The lost caravan opens a real merchant inside its event room")
		var restored := _roundtrip(caravan)
		check(restored != null and restored._shop_stock == caravan._shop_stock and restored.choices() == caravan.choices(), "The caravan merchant resumes with its event origin and fixed stock")
	if samples.has(6):
		var courier: ELExpeditionRun = samples[6]
		var money := courier.gold
		check(courier.choose("courier_contract") and courier.gold == money - 20 and courier._contract_remaining == 2, "Funding the courier charges 20 gold and records two victories owed")
		courier._reset(source, courier.preset, courier.seed_value, 3)
		check(courier._contract_remaining == 2, "The courier contract survives the same reset used at an act transition")
		for win_index in 2:
			var battle := _next_battle(courier)
			if battle == null:
				check(false, "A contracted victory has a usable duel")
				break
			_end(battle)
			check(courier.resolve_battle(battle) and courier._contract_remaining == 1 - win_index and int(courier._last_reward.contract) == (55 if win_index == 1 else 0), "Courier victory %d advances once and pays only on the second victory" % [win_index + 1])
		var restored := _roundtrip(courier)
		check(restored != null and restored.gold == courier.gold and restored._contract_remaining == 0, "A paid contract cannot pay again when its reward checkpoint reloads")
	if samples.has(7):
		var forge: ELExpeditionRun = samples[7]
		var offer := _option(forge, "forge_exchange")
		check(not offer.is_empty(), "The forge has a legal rarity exchange for the synthetic book")
		if not offer.is_empty():
			var size_before := forge.deck.size()
			var old_count := forge.deck.count(offer.card)
			var new_count := forge.deck.count(offer.incoming)
			var life := forge.health
			check(forge.choose(offer.id) and forge.deck.size() == size_before and forge.deck.count(offer.card) == old_count - 1 and forge.deck.count(offer.incoming) == new_count + 1 and forge.gold == 967 and forge.health == life, "The forge exchanges exactly one copy for 32 gold without charging mirror-event life")
	if samples.has(8):
		var cartographer: ELExpeditionRun = samples[8]
		var life := cartographer.health
		check(cartographer.choose("cartographer_help") and cartographer.health == life - 4 and cartographer.gold == 1037, "Helping the cartographer trades four life for 38 gold")
	if samples.has(9):
		var trial: ELExpeditionRun = samples[9]
		var slow := _roundtrip(trial)
		var earned: Array[int] = []
		for run: ELExpeditionRun in [trial, slow]:
			if run == null or not run.choose("challenge"): continue
			var battle := run.build_battle()
			if battle == null: continue
			battle.round_number = 6 + earned.size()
			_end(battle)
			if run.resolve_battle(battle): earned.append(run.gold)
		check(earned.size() == 2 and earned[0] == earned[1] + 30 and trial.phase == "relic_reward", "The veteran's trial grants elite rewards and its 30-gold bonus only through round six")
	if samples.has(10):
		var vault: ELExpeditionRun = samples[10]
		var blood := _roundtrip(vault)
		var buy := _option(vault, "vault_buy:")
		var sacrifice := _option(blood, "vault_blood:") if blood != null else {}
		check(not buy.is_empty() and not sacrifice.is_empty() and buy.relic == sacrifice.relic, "Both vault bargains visibly offer the same deterministic relic")
		if not buy.is_empty() and not sacrifice.is_empty():
			var life := blood.health
			check(vault.choose(buy.id) and blood.choose(sacrifice.id) and vault.gold == 944 and blood.gold == 999 and blood.health == life - 8 and vault.relics == blood.relics, "The vault charges exactly the selected gold or life cost for one matching relic")
	if samples.has(11):
		var feast: ELExpeditionRun = samples[11]
		check(feast.choose("feast_prepare") and feast._prepared and feast.gold == 983, "Feast provisions cost 16 gold and remain pending until a duel is resolved")
		var battle := _next_battle(feast)
		check(battle != null and int(battle.heroes[0].level) == int(feast.preset.level) + 2 * (feast.act - 1) + 1, "Provisions grant exactly one hero level in the next actual duel")
		if battle != null:
			var raw := feast.snapshot()
			raw.battle = battle.snapshot()
			var restored := ELExpeditionRun.new()
			check(restored.restore_snapshot(source, _json(raw)) and restored._prepared, "Mid-battle saving retains the provisions that produced this duel")
			var continued := restored.build_battle()
			if continued != null:
				_end(continued)
				check(restored.resolve_battle(continued) and not restored._prepared, "Resolving the provisioned duel consumes the effect exactly once")

func _balanced_prices(source: ELProfile) -> void:
	var prices := {"amber_seed": 65, "silver_scale": 45, "glass_compass": 65, "hunters_badge": 60,
		"merchant_seal": 35, "travel_rations": 65, "pilgrims_flask": 45, "aether_prism": 85,
		"duelists_crest": 80, "ember_purse": 45, "purifier_stone": 70, "twin_seal": 55}
	for chapter in range(1, 4):
		var run := _enter_kind(source, "shop", 12345, chapter, 9)
		check(run != null, "Version 9 merchant is reachable in act %d" % chapter)
		if run == null: continue
		run.gold = 999
		var correct := true
		for id: String in prices:
			run._shop_relic = id
			var quote := _option(run, "buy_relic:" + id, false)
			correct = correct and not quote.is_empty() and int(quote.get("cost", -1)) == int(prices[id])
		check(correct, "Act %d uses all twelve differentiated relic prices without an act markup" % chapter)
		var plain := _option(run, "shop_remove:")
		check(not plain.is_empty() and int(plain.cost) == 40, "Paid removal still starts at forty gold")
		run.relics.append("purifier_stone")
		var discounts := true
		for count in 4:
			run._removals = count
			var quote := _option(run, "shop_remove:")
			discounts = discounts and not quote.is_empty() and int(quote.cost) == 15 + 15 * count
		check(discounts, "Version 9 Purifier's Stone discounts twenty-five gold instead of erasing escalating prices")
		run.relics.append("merchant_seal")
		discounts = true
		for count in 4:
			run._removals = count
			var quote := _option(run, "shop_remove:")
			discounts = discounts and not quote.is_empty() and int(quote.cost) == ceili((15 + 15 * count) * 0.8)
		check(discounts, "Merchant's Seal applies after the stone's flat reduction and never produces a negative removal price")
	var vault := _enter_event(source, 10, 9)
	check(vault != null, "Version 9 vault is reachable")
	if vault != null:
		vault.gold = 999
		var twin := _roundtrip(vault)
		var bought := _option(vault, "vault_buy:")
		var blood := _option(twin, "vault_blood:") if twin != null else {}
		var life := twin.health if twin != null else 0
		check(not bought.is_empty() and int(bought.cost) == 50 and vault.choose(bought.id) and vault.gold == 949, "Version 9 vault charges its reduced fifty-gold price")
		check(not blood.is_empty() and twin.choose(blood.id) and twin.health == life - 12 and twin.relics == vault.relics, "Version 9 blood bargain charges twelve life for the same relic")
	var treasure := _enter_kind(source, "treasure", 12345, 1, 9)
	if treasure != null:
		treasure.health = 1
		var money := treasure.gold
		var expected := mini(treasure.max_health, 1 + ceili(treasure.max_health * 0.2))
		check(treasure.choose("skip_relic") and treasure.gold == money + 25 and treasure.health == expected, "Declining a version 9 relic offers useful recovery as well as gold")

func _haven(source: ELProfile) -> void:
	var run := _enter_kind(source, "boss", 24681, 3, 9)
	check(run != null and run.phase == "haven", "Choosing the final guardian first opens the final preparation merchant")
	if run == null: return
	check(run.build_battle() == null, "The final duel cannot bypass preparation before the player enters the guardian")
	run.gold = 999
	run.health = maxi(1, run.max_health - 15)
	var saved := run.snapshot()
	var restored := _roundtrip(run)
	check(restored != null and restored.phase == "haven" and restored.choices() == run.choices(), "Final-haven stock and entry actions restore from a checkpoint")
	var bought := _option(run, "buy_card:")
	check(not bought.is_empty() and run.choose(bought.id), "The haven can stage a real final spell purchase")
	if not run.pending_card.is_empty():
		var pending := _roundtrip(run)
		check(pending != null and pending.pending_card == run.pending_card and pending.phase == "haven", "A pending haven card purchase is resumable")
		check(run.choose("back") and run.snapshot() == saved, "Cancelling a haven card returns the exact pre-purchase state")
	var heal := _option(run, "shop_heal")
	check(not heal.is_empty() and run.choose(heal.id), "Late-run gold can buy healing before the last guardian")
	var prepare := _option(run, "shop_prepare")
	check(not prepare.is_empty() and run.choose(prepare.id) and run._prepared, "Late-run gold can provision the final duel")
	var before := run.snapshot()
	check(not run.choose("leave") and run.snapshot() == before, "The final haven cannot return the run to an unavailable map state")
	check(run.choose("enter_guardian") and run.phase == "battle", "The player can leave preparation by entering the final duel")
	var battle := run.build_battle()
	check(battle != null and int(battle.heroes[0].level) == int(run.battle_preview().level), "The guardian duel uses the prepared hero level shown in its preview")
	if battle != null:
		_end(battle)
		check(run.resolve_battle(battle) and run.phase == "won", "The final guardian still ends the run after the new haven")
	var poor := _enter_kind(source, "boss", 24681, 3, 9)
	if poor != null:
		poor.gold = 0
		check(poor.choose("enter_guardian") and poor.phase == "battle", "A penniless player can always enter the final guardian")
	var counter := _new(source, 14681, 9)
	if counter != null:
		var answer := str(ELExpeditionRun.CAMP_STUDY[counter.preset.faction])
		counter.deck.assign(counter.deck.filter(func(card: String) -> bool: return card != answer))
		counter._reset(source, counter.preset, counter.seed_value, 3)
		var path := _path_to_kind(counter, "boss")
		for index in path.size():
			if index == path.size() - 1:
				counter._contract_remaining = 1
				counter._bounty = {"kind": "swift", "remaining": 1}
			if not counter.choose_node(path[index]): break
			if index < path.size() - 1 and not _settle(counter): break
		check(counter.phase == "haven" and answer in counter._shop_stock, "The final haven stocks a missing faction answer to enemy enchantments")
		check(counter._contract_remaining == 0 and counter._bounty.is_empty(), "Entering the final haven expires unfinished courier and bounty contracts")
		counter.gold = 999
		var quote := _option(counter, "buy_card:" + answer)
		check(not quote.is_empty() and counter.choose(quote.id) and counter.choose("add") and answer in counter.deck and counter.phase == "haven", "The guaranteed enchantment counter can actually be bought and added before White Lord")

func _redraw(source: ELProfile) -> void:
	var run := _new(source, 71631, 9)
	if run == null: return
	var battle := _next_battle(run)
	if battle == null:
		check(false, "The redraw fixture can start its opening duel")
		return
	_end(battle)
	check(run.resolve_battle(battle) and run.phase == "reward", "A version 9 victory offers its spell reward")
	var first := run._offered_cards()
	run.gold = 0
	var before := run.snapshot()
	check(not run.choose("reroll_reward") and run.snapshot() == before, "An unfunded reward redraw cannot consume the once-per-act allowance")
	run.gold = 99
	check(run.choose("reroll_reward") and run.gold == 87 and run._reward_roll == 1 and run._reroll_used_acts.has(run.act), "A reward redraw costs twelve gold and records its act allowance")
	var second := run._offered_cards()
	check(second.size() == first.size() and second.all(func(card: String) -> bool: return card not in first), "A sufficiently large card pool redraws genuinely different legal spell offers")
	var restored := _roundtrip(run)
	check(restored != null and restored._offered_cards() == second and restored._reroll_used_acts == run._reroll_used_acts, "Redrawn offers and their spent allowance survive reloading")
	before = run.snapshot()
	check(not run.choose("reroll_reward") and run.snapshot() == before, "A reward cannot redraw twice in the same act")
	var card := _option(run, "card:")
	check(not card.is_empty() and run.choose(card.id), "A redrawn spell remains selectable")
	restored = _roundtrip(run)
	check(restored != null and restored.pending_card == run.pending_card, "A selected redrawn spell retains a valid pending replacement on reload")
	run.choose("back")
	run.choose("skip")
	run._reset(source, run.preset, run.seed_value, 2)
	battle = _next_battle(run)
	if battle != null:
		_end(battle)
		run.resolve_battle(battle)
		check(not _option(run, "reroll_reward").is_empty(), "A new act makes its separate reward redraw available")
	_no_alternative_redraw(source)

func _no_alternative_redraw(source: ELProfile) -> void:
	# A legal, tiny custom catalog: four capped spells fill the starter book,
	# leaving exactly three spells to offer. Reordering those is not a redraw.
	var tiny := ELProfile.new()
	tiny.id = source.id
	tiny.title = "Expedition tiny reward catalog"
	tiny.tables = source.tables.duplicate(true)
	tiny.texts = source.texts.duplicate()
	var codes: Array[String] = ["STRT", "KBWR", "KBGD", "KBSH", "ZAPP", "COMT", "FRWA"]
	var spells := {}
	var book: Array[String] = []
	for code: String in codes: spells[code] = tiny.tables.CombatSpells[code]
	for code: String in codes.slice(0, 4):
		for copy in ELDuelCosts.EL2_COPIES: book.append(code)
	tiny.tables.CombatSpells = spells
	tiny.tables.DuelPresets = {"ExpeditionFixtureRed": tiny.tables.DuelPresets.ExpeditionFixtureRed}
	tiny.tables.CombatDecks.ExpeditionFixtureRed.Spells = book
	var run := _new(tiny, 71631, 9)
	if run == null: return
	run.choose_node(run.available()[0])
	# This test isolates reward choices, not battle resolution; the full-duel
	# reward transition is already covered by the preceding redraw checks.
	run.phase = "reward"
	run.gold = 99
	var initial := run._offered_cards(0)
	var shuffled := run._offered_cards(1)
	initial.sort()
	shuffled.sort()
	check(initial.size() == 3 and initial == shuffled, "The tiny catalog fixture exhausts its three legal spell offers")
	var before := run.snapshot()
	var offer := _option(run, "reroll_reward", false)
	check(not offer.is_empty() and bool(offer.get("disabled", false)) and not run.choose("reroll_reward") and run.snapshot() == before, "A redraw with no different spell set is disabled and cannot spend gold or its allowance")
	var restored := _roundtrip(run)
	check(restored != null and restored.choices() == run.choices(), "The exhausted catalog's disabled redraw remains stable after reloading")
	for code: String in codes.slice(4): tiny.tables.CombatSpells.erase(code)
	before = run.snapshot()
	check(run._offered_cards().is_empty() and _option(run, "reroll_reward").is_empty() and not run.choose("reroll_reward") and run.snapshot() == before, "An entirely exhausted catalog cannot charge for an empty redraw")

func _difficulty(source: ELProfile) -> void:
	var standard := ELExpeditionRun.new()
	var veteran := ELExpeditionRun.new()
	check(standard.create(source, "ExpeditionFixtureRed", 19876, 9, "standard") and veteran.create(source, "ExpeditionFixtureRed", 19876, 9, "veteran"), "Standard and Veteran create explicit version 9 runs")
	standard.choose("relic:glass_compass")
	veteran.choose("relic:glass_compass")
	var room := standard.available()[0]
	var basic_foe := standard.opponent_at(room)
	var tough_foe := veteran.opponent_at(room)
	check(not basic_foe.is_empty() and not tough_foe.is_empty() and int(tough_foe.health) == ceili(int(basic_foe.health) * 1.15) and int(tough_foe.level) == int(basic_foe.level) + 1, "Veteran scales opening foe life by fifteen percent and its unscripted non-boss level by one")
	check(standard.route() == veteran.route(), "Difficulty changes encounter pressure without rerolling the seed's route")
	var restored := _roundtrip(veteran)
	check(restored != null and restored.difficulty == "veteran" and restored.opponent_at(room) == tough_foe, "Veteran choice and exact encounter scaling survive reloading")
	standard.choose_node(room)
	veteran.choose_node(room)
	var earned: Array[int] = []
	for run: ELExpeditionRun in [standard, veteran]:
		var duel := run.build_battle()
		if duel == null: continue
		var money := run.gold
		_end(duel)
		if run.resolve_battle(duel): earned.append(run.gold - money)
	check(earned.size() == 2 and earned[1] == ceili(earned[0] * 1.15), "Veteran pays fifteen percent extra base gold for the same seeded victory")
	var invalid := ELExpeditionRun.new()
	check(not invalid.create(source, "ExpeditionFixtureRed", 1, 9, "unknown") and not invalid.create(source, "ExpeditionFixtureRed", 1, 8, "veteran"), "Unknown difficulties and retroactive Veteran on legacy rules are rejected")

func _broker_and_bounties(source: ELProfile) -> void:
	var broker := _enter_event(source, 12, 9)
	check(broker != null, "The new relic broker is reachable in version 9")
	if broker != null:
		broker.gold = 99
		var before := broker.snapshot()
		var pick := _option(broker, "broker_select:")
		check(not pick.is_empty() and broker.choose(pick.id) and broker.gold == 99 and not broker.pending_relic.is_empty(), "Selecting a broker offer previews the incoming relic without charging")
		var restored := _roundtrip(broker)
		check(restored != null and restored.pending_relic == broker.pending_relic and restored.choices() == broker.choices(), "A pending relic exchange preserves both sides of the decision after reload")
		check(broker.choose("back") and broker.snapshot() == before, "Cancelling a broker preview preserves gold and every owned relic")
		broker.choose(pick.id)
		var give := _option(broker, "broker_exchange:")
		var owned := broker.relics.size()
		var surrendered := str(give.id).trim_prefix("broker_exchange:") if not give.is_empty() else ""
		var received := broker.pending_relic
		check(not give.is_empty() and broker.choose(give.id) and broker.gold == 87 and broker.relics.size() == owned and received in broker.relics and surrendered not in broker.relics and broker.pending_relic.is_empty(), "A confirmed broker trade charges twelve gold and exchanges exactly one relic")
		before = broker.snapshot()
		check(not broker.choose(str(give.get("id", "broker_exchange:missing"))) and broker.snapshot() == before, "A completed broker exchange cannot be replayed")
	var trained := _enter_event(source, 12, 9)
	if trained != null:
		trained.gold = 99
		trained.relics.append("twin_seal")
		trained._training = {"PRVD": 2, "SUPR": 1}
		var pick := _option(trained, "broker_select:")
		if not pick.is_empty() and trained.choose(pick.id):
			var before := trained.snapshot()
			check(_option(trained, "broker_exchange:twin_seal").is_empty() and not trained.choose("broker_exchange:twin_seal") and trained.snapshot() == before, "The broker cannot remove a Master's Seal supporting the third training session")
			var restored := _roundtrip(trained)
			check(restored != null and restored._training == trained._training, "The protected three-session broker state remains resumable")
	var complete := _enter_event(source, 12, 9)
	if complete != null:
		complete.relics.assign(ELExpeditionContent.RELICS.keys())
		check(_option(complete, "broker_select:").is_empty() and complete.choose("leave"), "Owning every relic leaves a safe exit from an exhausted broker")
	var board := _enter_event(source, 13, 9)
	check(board != null, "The new bounty board is reachable in version 9")
	if board != null:
		board.gold = 99
		var expired := _roundtrip(board)
		check(board.choose("bounty:swift") and board.gold == 89 and board._bounty == {"kind": "swift", "remaining": 2}, "A swift bounty records its ten-gold bond and two-victory deadline")
		var restored := _roundtrip(board)
		check(restored != null and restored._bounty == board._bounty, "An active bounty survives checkpoint restoration")
		var battle := _next_battle(board)
		if battle != null:
			battle.round_number = 8
			_end(battle)
			check(board.resolve_battle(battle) and board._bounty.is_empty() and int(board._last_reward.get("bounty", -1)) == 30, "An eighth-round victory fulfils the swift bounty and pays thirty gold once")
			var before := board.snapshot()
			check(not board.resolve_battle(battle) and board.snapshot() == before, "A settled bounty cannot pay twice from the same duel")
		if expired != null and expired.choose("bounty:swift"):
			for step in 2:
				battle = _next_battle(expired)
				if battle == null: break
				battle.round_number = 9
				_end(battle)
				var settled := expired.resolve_battle(battle)
				check(settled and int(expired._last_reward.get("bounty", -1)) == 0 and (expired._bounty.is_empty() if step == 1 else int(expired._bounty.get("remaining", -1)) == 1), "Slow victory %d advances the bounty deadline without paying" % (step + 1))
	var elite := _enter_kind(source, "elite", 3456, 2, 9)
	if elite != null:
		elite._bounty = {"kind": "elite", "remaining": 1}
		var battle := elite.build_battle()
		if battle != null:
			_end(battle)
			check(elite.resolve_battle(battle) and elite._bounty.is_empty() and int(elite._last_reward.get("bounty", -1)) == 40, "The elite bounty pays forty gold when the final allowed victory is an elite")
	var guardian := _enter_kind(source, "boss", 3456, 2, 9)
	if guardian != null:
		guardian._bounty = {"kind": "elite", "remaining": 1}
		var battle := guardian.build_battle()
		if battle != null:
			_end(battle)
			check(guardian.resolve_battle(battle) and guardian._bounty.is_empty() and int(guardian._last_reward.get("bounty", -1)) == 0, "Guardians do not silently count as elites for the elite bounty")
	var late := _enter_event(source, 6, 9, 3, 6)
	check(late != null, "The late courier forecast fixture is reachable")
	if late != null:
		late.gold = 99
		var before := late.snapshot()
		check(_option(late, "courier_contract").is_empty() and not late.choose("courier_contract") and late.snapshot() == before, "A courier investment is blocked when two scheduled wins cannot occur before the final haven")
		check(late.choose("courier_wages") and late.gold == 109, "The late courier still offers useful immediate wages")

func _swift_boundaries(source: ELProfile) -> void:
	var old_plain := _victory_case(source, ["glass_compass"], 7, 16, 8)
	var old_purse := _victory_case(source, ["glass_compass", "ember_purse"], 7, 16, 8)
	check(not old_plain.is_empty() and not old_purse.is_empty() and old_plain.gold == old_purse.gold, "Version 8 Ember Purse still pays nothing on round seven")
	var plain := _victory_case(source, ["glass_compass"], 8, 16, 9)
	var fast := _victory_case(source, ["glass_compass", "ember_purse"], 8, 16, 9)
	var slow := _victory_case(source, ["glass_compass", "ember_purse"], 9, 16, 9)
	check(not plain.is_empty() and not fast.is_empty() and fast.gold == plain.gold + 12, "Version 9 Ember Purse pays its twelve-gold bonus through round eight")
	check(not plain.is_empty() and not slow.is_empty() and slow.gold == plain.gold, "Version 9 Ember Purse stops paying at round nine")
	var trial := _enter_event(source, 9, 9)
	if trial != null:
		var later := _roundtrip(trial)
		var earned: Array[int] = []
		for run: ELExpeditionRun in [trial, later]:
			if run == null or not run.choose("challenge"): continue
			var battle := run.build_battle()
			if battle == null: continue
			var before := run.gold
			battle.round_number = 6 + earned.size()
			_end(battle)
			if run.resolve_battle(battle): earned.append(run.gold - before)
		check(earned.size() == 2 and earned[0] == earned[1] + 30, "The Veteran's Trial keeps its separate round-six deadline in version 9")

func _balanced_save_guards(source: ELProfile) -> void:
	var run := _new(source, 2957, 9)
	if run == null: return
	var healthy := run.snapshot()
	for change: Array in [["difficulty", "impossible"], ["reward_roll", 2], ["reward_roll", 0.5], ["reroll_used_acts", [1, 1]], ["reroll_used_acts", [4]], ["bounty", {"kind": "unknown", "remaining": 1}], ["bounty", {"kind": "swift", "remaining": 0}], ["bounty", {"kind": "elite", "remaining": 3}], ["pending_relic", "missing_relic"]]:
		var damaged := healthy.duplicate(true)
		damaged[change[0]] = change[1]
		check(not run.restore_snapshot(source, _json(damaged)) and run.snapshot() == healthy, "Malformed version 9 field %s=%s cannot replace the live run" % [str(change[0]), str(change[1])])
