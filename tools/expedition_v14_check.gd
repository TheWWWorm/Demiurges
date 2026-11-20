extends "expedition_v13_check.gd"
## Real run/duel/save lifecycle checks using synthetic routes and spell rows.
## Victories used to reach later rooms are forced setup, never balance data.
## Controlled book arrangements exercise ownership boundaries explicitly.
## The player's checkpoint is neither read nor written.

const V14 := 14
const V14_ROOT := "user://expedition_v14_check"
var prepared_duels := 0
var caravan_purchases := 0

func _run() -> void:
	var source := Fixture.profile_at(V14_ROOT)
	check(source != null, "Version 14 synthetic route fixture is available")
	if source != null:
		_frozen_v13(source)
		_opening_boundaries(source)
		_camp_openings(source)
		_haven_openings(source)
		_scholar_openings(source)
		_opening_ownership(source)
		_opening_suppression(source)
		_caravan_inspection(source)
		_reject_opening_saves(source)
	var output := _argument("output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		check(file != null, "Version 14 result file opens")
		if file != null: file.store_string(JSON.stringify({"rules": V14, "checks": checks, "failures": failures,
			"legacy_rooms": legacy_rooms, "legacy_stages": legacy_stages,
			"prepared_duels": prepared_duels, "caravan_purchase_types": caravan_purchases,
			"baseline": _argument("baseline"), "assumptions": [
				"Real run, choice, duel and exact checkpoint APIs; synthetic maps and card tables.",
				"Forced victories only reach lifecycle checkpoints; no campaign win-rate claim.",
				"Ownership edge cases explicitly arrange legal books on otherwise reachable routes.",
				"Frozen v13 core uses current shared content; historical rules must retain their offers and choices."]}, "\t", true, true))
	Fixture.clean(V14_ROOT)
	print("EXPEDITION VERSION 14: %d checks, %d failure(s); %d frozen-v13 rooms, %d prepared duels, %d caravan purchase types" % [checks, failures.size(), legacy_rooms, prepared_duels, caravan_purchases])
	quit(0 if failures.is_empty() else 1)

func _fresh(source: ELProfile, faction := "Red", seed_value := 12345) -> ELExpeditionRun:
	return _new(source, seed_value, V14, faction)

func _opening_boundaries(source: ELProfile) -> void:
	var latest := ELExpeditionRun.new()
	check(latest.create(source, "ExpeditionFixtureRed", 431, V14) and latest.practiced() and latest.snapshot().version == V14, "Explicit rules 14 retain their original identity")
	check(latest.opening_spell.is_empty() and not latest.opening_selecting and not latest.opening_suppressed and latest.opening_details().is_empty() and latest._opening_slots() == [-1, -1], "A new run has no free prepared spell")
	for version in range(1, V14):
		var old := _new(source, 431, version)
		check(old != null and not old.practiced() and not old.snapshot().has("opening_spell") and not old.snapshot().has("opening_selecting") and not old.snapshot().has("opening_suppressed"), "Rules %d keep their original save shape" % version)
		check(old._nodes.values().all(func(room: Dictionary) -> bool: return int(room.get("event", -1)) != ELExpeditionRun.SCHOLAR_EVENT), "Rules %d do not acquire a new event" % version)
		check(old.choose_node(old.available()[0]), "Rules %d enter a normal battle" % version)
		var duel := old.build_battle()
		check(duel != null and not duel.setup.has("opening_slots"), "Rules %d use the original draw path" % version)
	var raw := latest.snapshot()
	raw.opening_spell = latest.deck[0]
	_reject(latest, raw, "A new run cannot begin with a forged prepared spell")
	raw = latest.snapshot()
	raw.opening_selecting = true
	_reject(latest, raw, "The starting gift cannot restore an opening selection")
	check(latest.choose("relic:amber_seed"), "Starting relic still leads to study selection")
	raw = latest.snapshot()
	raw.opening_spell = latest.deck[0]
	_reject(latest, raw, "Study selection cannot begin with a forged prepared spell")
	for version in [12, 13]:
		var old := _enter(source, "rest", 12345, 1, version)
		check(old != null and old.choose("forage"), "Create a legitimate rules %d receipt" % version)
		for story: String in ["17:opening_spell", "17:scholar_notes"]:
			raw = old.snapshot()
			raw.last_outcome.story = story
			_reject(old, raw, "Rules %d reject a future Shrine receipt: %s" % [version, story])

func _camp_openings(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var run := _enter(source, "rest", 12345, 1, V14, -1, faction)
		check(run != null, faction + ": reach a generated camp")
		if run == null: continue
		_reserve_pair(run)
		var before := run.snapshot()
		check(run.choose("opening_select") and run.phase == "rest" and run.opening_selecting, faction + ": inspect rehearsal without consuming camp")
		var cards: Array[String] = []
		for offer: Dictionary in run.choices():
			if offer.id == "back": continue
			check(str(offer.id) == "opening_spell:" + str(offer.card) and offer.card in run.deck and offer.card not in cards and not offer.get("disabled", false), faction + ": opening candidates are distinct active spells")
			cards.append(str(offer.card))
		check(cards.size() > 1 and cards.size() < run.deck.size(), faction + ": duplicate pages do not duplicate rehearsal choices")
		_restore_equal(run, faction + ": pending camp rehearsal restores exactly")
		var pending := run.snapshot()
		check(not run.choose("forage") and not run.choose("swap_select:0") and run.snapshot() == pending, faction + ": rehearsal isolates its own choices")
		check(run.choose("back") and run.snapshot() == before, faction + ": cancel spends neither resources nor camp action")
		check(not run.choose("opening_spell:" + cards[0]) and run.snapshot() == before, faction + ": canceled choice cannot commit later")
		check(run.choose("opening_select") and run.choose("opening_spell:" + cards[0]), faction + ": commit the chosen opening spell")
		check(run.phase == "map" and not run.opening_selecting and run.opening_spell == cards[0] and run.deck == before.deck and run.reserve == before.reserve and run.health == int(before.health) and run.gold == int(before.gold), faction + ": rehearsal consumes one camp action without free cards, healing or gold")
		check(run._last_outcome.opening_before == "" and run._last_outcome.opening_after == cards[0] and run._last_outcome.book_added.is_empty() and not run.outcome_details().is_empty(), faction + ": receipt records the learned preparation without fictional pages")
		_restore_equal(run, faction + ": committed opening and receipt restore exactly")
		var prepared := run.snapshot()
		check(not run.choose("forage") and not run.choose("opening_select") and run.snapshot() == prepared, faction + ": completing rehearsal closes camp once")
		check(_travel(run, "boss"), faction + ": carry preparation to the act guardian")
		var duel := run.build_battle()
		check(duel != null, faction + ": prepared duel builds: " + run.error)
		if duel == null: continue
		check(duel.setup.opening_slots == [run.deck.find(cards[0]), -1] and cards[0] in duel.heroes[0].hand and duel.heroes[0].hand.size() == 5, faction + ": selected real page is in the normal opening hand")
		check(duel.heroes[0].deck == run.deck and duel.heroes[0].spell_uses.all(func(value: int) -> bool: return value == run.charges_per_page()), faction + ": opening preparation preserves book and finite charges")
		prepared_duels += 1
		run._battle_checkpoint = duel.snapshot()
		var restored := _restore_equal(run, faction + ": prepared battle checkpoint restores")
		if restored == null: continue
		var resumed := restored.build_battle()
		check(resumed != null and resumed.snapshot() == duel.snapshot(), faction + ": resume does not redeal the opening")
		if resumed != null:
			for step in 4: check(duel.end_phase() == resumed.end_phase() and duel.snapshot() == resumed.snapshot(), faction + ": exact prepared continuation %d" % step)
		for value: Variant in [[-1, -1], [run.deck.find(cards[0]), 0], {}, "wrong", null]:
			var forged := run.snapshot()
			forged.battle.setup.opening_slots = value
			_reject(run, forged, faction + ": mismatched opening identity is rejected atomically")
		var forged := run.snapshot()
		forged.opening_spell = cards[1]
		_reject(run, forged, faction + ": changing the selected code cannot reuse an old duel")
		forged = run.snapshot()
		forged.opening_suppressed = true
		_reject(run, forged, faction + ": a saved duel cannot change opening preparation mid-battle")
		check(_settle(run) and run.act == 2 and run.opening_spell == cards[0], faction + ": preparation persists across the act boundary")
		_restore_equal(run, faction + ": the next act retains opening preparation")

func _haven_openings(source: ELProfile) -> void:
	for modifier: String in ["none", "merchant_seal", "living_heart", "both"]:
		var run := _enter(source, "boss", 12345, 3, V14)
		check(run != null and run.phase == "haven", "Reach the Haven for " + modifier)
		if run == null: continue
		if modifier in ["merchant_seal", "both"]: run.relics.append("merchant_seal")
		if modifier in ["living_heart", "both"]:
			run.keystones.append("living_heart")
			run.max_health += 8
		# The modifier is arranged before this shop's stock is generated.
		# Otherwise a synthetic newly-owned Seal can contradict its sale slot.
		run._prepare_shop()
		run.gold = 200
		var cost := run._merchant_price(ELExpeditionRun.OPENING_COST)
		var before := run.snapshot()
		check(int(_option(run, "opening_select").cost) == cost and run.choose("opening_select"), modifier + ": Haven quotes the actual modified price")
		var first := _option(run, "opening_spell:")
		check(not first.is_empty() and int(first.cost) == cost and run.gold == 200, modifier + ": inspecting a card does not charge")
		_restore_equal(run, modifier + ": pending paid rehearsal restores")
		check(run.choose("back") and run.snapshot() == before, modifier + ": cancel leaves the Haven unchanged")
		check(run.choose("opening_select") and run.choose(str(first.id)), modifier + ": paid preparation commits")
		check(run.phase == "haven" and run.gold == 200 - cost and run.opening_spell == first.card and run._shop_bought == before.shop.bought and run._shop_stock == before.shop.stock, modifier + ": only the quoted gold is spent; other services remain")
		_restore_equal(run, modifier + ": paid preparation receipt restores")
		check(run.choose("opening_select"), modifier + ": another spell can be inspected")
		var current := _option(run, str(first.id), false)
		var pending := run.snapshot()
		check(current.get("disabled", false) and not run.choose(str(first.id)) and run.snapshot() == pending, modifier + ": the same spell cannot be bought again")
		var second := _option(run, "opening_spell:")
		check(not second.is_empty() and run.choose(str(second.id)) and run.gold == 200 - 2 * cost and run.opening_spell == second.card, modifier + ": a deliberate retune pays its displayed cost again")
		run.gold = cost - 1
		before = run.snapshot()
		check(_option(run, "opening_select", false).get("disabled", false) and not run.choose("opening_select") and run.snapshot() == before, modifier + ": unaffordable rehearsal cannot open")
		check(run.choose("enter_guardian") and run.build_battle() != null, modifier + ": final duel uses the chosen opening spell")

func _scholar_openings(source: ELProfile) -> void:
	var run := _event(source, ELExpeditionRun.SCHOLAR_EVENT, 1, V14)
	check(run != null, "The new Shrine encounter is reachable in Act I")
	if run == null: return
	var original := run.snapshot()
	check(not run.room_summary().get("description", "").is_empty() and run.choose("opening_select"), "The scholar offers a concrete preparation lesson")
	_restore_equal(run, "Pending scholar lesson restores")
	check(run.choose("back") and run.snapshot() == original, "Canceling the lesson keeps the copying job")
	var paid := _roundtrip(run)
	check(paid != null and paid.choose("scholar_notes") and paid.phase == "map" and paid.gold == int(original.gold) + 12 and paid.opening_spell.is_empty(), "Copying notes pays 12 gold instead of learning an opening")
	if paid != null:
		check(paid._last_outcome.story == "17:scholar_notes", "The copying job has its own outcome")
		_restore_equal(paid, "Scholar copying receipt restores")
	check(run.choose("opening_select"), "Inspect the alternative scholar lesson")
	var choice := _option(run, "opening_spell:")
	check(not choice.is_empty() and run.choose(str(choice.id)) and run.phase == "map" and run.gold == int(original.gold) and run.opening_spell == choice.card, "The lesson prepares one spell and spends the encounter")
	check(run._last_outcome.story == "17:opening_spell" and not run.outcome_details().description.is_empty(), "The lesson reports the chosen preparation")
	_restore_equal(run, "Scholar lesson and narrative receipt restore")

func _single_copy(run: ELExpeditionRun, code: String) -> void:
	while run.deck.count(code) > 1: run.deck.remove_at(run.deck.rfind(code))

func _opening_ownership(source: ELProfile) -> void:
	var run := _enter(source, "rest", 12345, 2, V14)
	check(run != null, "Reach camp for controlled ownership boundaries")
	if run == null: return
	var code := run.deck[0]
	_single_copy(run, code)
	run.opening_spell = code
	_reserve_pair(run)
	var incoming := run.reserve[0]
	var before := run.snapshot()
	check(run.choose("swap_select:0") and run.choose("swap_with:%d" % run.deck.find(code)), "Move the last active copy into reserve through the real swap")
	check(run.opening_spell == code and not run.opening_details().active and run.opening_details().owned and run._opening_slots() == [-1, -1], "The prepared spell stays learned but dormant in reserve")
	check(run.gold == int(before.gold) and run.health == int(before.health) and run.phase == "rest", "Dormancy does not spend resources or the camp action")
	_restore_equal(run, "Dormant preparation restores")
	check(run.choose("swap_select:0") and run.choose("swap_with:%d" % run.deck.find(incoming)) and run.opening_details().active and run._opening_slots()[0] == run.deck.find(code), "Returning the real page reactivates preparation without another lesson")
	check(run.choose("remove:%d" % run.deck.find(code)) and run.opening_spell.is_empty() and run.opening_details().is_empty(), "Removing the last owned copy clears preparation")
	check(run._last_outcome.opening_before == code and run._last_outcome.opening_after == "" and run._last_outcome.book_removed == [code], "Last-copy removal reports the preparation lost")
	_restore_equal(run, "Removed preparation cannot return on reload")
	var multiple := _enter(source, "rest", 12345, 2, V14)
	code = multiple.deck[0]
	multiple.opening_spell = code
	check(multiple.deck.count(code) > 1 and multiple.choose("remove:%d" % multiple.deck.find(code)) and multiple.opening_spell == code and multiple.opening_details().active, "Removing one duplicate keeps the remaining prepared copy")
	_restore_equal(multiple, "Duplicate-copy removal preserves exact preparation")
	var crafting := _event(source, ELExpeditionRun.ANVIL_EVENT, 2, V14)
	check(crafting != null, "Reach the anvil for consumed-page preparation")
	if crafting == null: return
	crafting.gold = 200
	var selected := _option(crafting, "craft_select:")
	check(not selected.is_empty() and crafting.choose(str(selected.id)), "Inspect a legal anvil recipe")
	if selected.is_empty(): return
	var recipe := _option(crafting, "craft:")
	check(not recipe.is_empty(), "The selected page has a legal replacement")
	if recipe.is_empty(): return
	code = str(selected.card)
	while crafting.deck.count(code) > int(recipe.consume): crafting.deck.remove_at(crafting.deck.rfind(code))
	crafting.opening_spell = code
	check(crafting.choose(str(recipe.id)) and crafting.owned_copies(code) == 0 and crafting.opening_spell.is_empty(), "Crafting the last prepared copies clears the old preparation")
	check(str(recipe.incoming) in crafting.deck and crafting._last_outcome.opening_after == "", "The new spell does not inherit unearned opening preparation")
	_restore_equal(crafting, "Crafted book and lost preparation restore together")

func _opening_suppression(source: ELProfile) -> void:
	for destination: String in ["rest", "haven"]:
		var run := _enter(source, "rest", 12345, 1, V14)
		check(run != null and run.choose("opening_select"), destination + ": learn preparation through an actual camp action")
		if run == null: continue
		var choice := _option(run, "opening_spell:")
		check(not choice.is_empty() and run.choose(str(choice.id)) and _travel(run, "boss") and _settle(run), destination + ": carry a learned opening into Act II")
		if destination == "haven":
			check(_travel(run, "boss") and _settle(run) and _travel(run, "boss"), "Carry learned preparation to the Last Haven")
		else: check(_travel(run, "rest"), "Reach another camp with learned preparation")
		check(run.phase == destination and not _option(run, "suppress_opening").is_empty(), destination + ": a learned opening can be freely set aside")
		var before := run.snapshot()
		var code := run.opening_spell
		check(run.choose("suppress_opening") and run.opening_suppressed and run.opening_spell == code and run._opening_slots() == [-1, -1], destination + ": ordinary openings preserve the learned spell")
		check(run.phase == destination and run.gold == int(before.gold) and run.health == int(before.health) and run.deck == before.deck and run.reserve == before.reserve and run._last_outcome == before.last_outcome, destination + ": setting aside is free and preserves the main action and receipt")
		check(not run.opening_details().active and not run.opening_details().prepared and run.opening_details().owned and not run.opening_details().reason.is_empty(), destination + ": readiness explains a deliberately random opening")
		_restore_equal(run, destination + ": set-aside preparation restores exactly")
		var held := run.snapshot()
		check(not run.choose("suppress_opening") and run.snapshot() == held, destination + ": a stale suppression click cannot replay")
		check(run.choose("opening_select"), destination + ": inspect retuning while set aside")
		var pending := run.snapshot()
		check(not run.choose("prepare_opening") and run.snapshot() == pending, destination + ": paid selection isolates free toggles")
		check(_option(run, "opening_spell:" + code, false).get("disabled", false), destination + ": the already learned spell cannot charge again")
		check(run.choose("back") and run.snapshot() == held, destination + ": cancel retains the set-aside state")
		check(run.choose("prepare_opening") and run.snapshot() == before, destination + ": preparing again exactly restores the earlier state without payment")
		check(run.choose("suppress_opening"), destination + ": choose ordinary draws for the upcoming duel")
		if destination == "rest": check(run.choose("forage") and _travel(run, "boss"), "Setting aside still permits the one main camp action")
		else: check(run.choose("enter_guardian"), "A set-aside opening does not block the final fight")
		var duel := run.build_battle()
		check(duel != null and duel.setup.opening_slots == [-1, -1] and run.opening_spell == code and run.opening_suppressed, destination + ": actual battle receives ordinary opening slots")
		if duel != null:
			run._battle_checkpoint = duel.snapshot()
			var restored := _roundtrip(run)
			# The Act II guardian's Adv_TickCount starts as 2.0; the existing
			# save decoder restores integral Lua numbers as int. Compare the
			# complete serialized values and continuation, not that host type.
			check(restored != null and _json(restored.snapshot()) == _json(run.snapshot()), destination + ": battle with a set-aside opening restores all serialized state")
			if restored != null:
				var resumed := restored.build_battle()
				check(resumed != null and _json(resumed.snapshot()) == _json(duel.snapshot()), destination + ": random-opening resume neither redraws nor forgets the lesson")
				if resumed != null:
					for step in 4: check(duel.end_phase() == resumed.end_phase() and _json(duel.snapshot()) == _json(resumed.snapshot()), destination + ": ordinary-opening continuation remains identical %d" % step)
			var forged := run.snapshot()
			forged.opening_suppressed = false
			_reject(run, forged, destination + ": saved ordinary duel cannot silently prepare a spell")
	var lost := _enter(source, "rest", 12345, 2, V14)
	var code := lost.deck[0]
	_single_copy(lost, code)
	lost.opening_spell = code
	check(lost.choose("suppress_opening") and lost.choose("remove:%d" % lost.deck.find(code)) and lost.opening_spell.is_empty() and not lost.opening_suppressed, "Losing the last copy also clears its set-aside flag")
	_restore_equal(lost, "A forgotten lesson has no stale suppression state")
	var retune := _enter(source, "rest", 12345, 2, V14)
	retune.opening_spell = retune.deck[0]
	check(retune.choose("suppress_opening") and retune.choose("opening_select"), "A set-aside lesson can be replaced at camp")
	var replacement := _option(retune, "opening_spell:")
	check(not replacement.is_empty() and retune.choose(str(replacement.id)) and not retune.opening_suppressed and retune.opening_details().active, "Learning a different spell prepares the newly chosen opening")
	_restore_equal(retune, "Retuning a set-aside lesson restores the new active spell")

func _caravan_inspection(source: ELProfile) -> void:
	var run := _event(source, 5, 1, V14)
	check(run != null, "A generated caravan encounter is reachable")
	if run == null: return
	run.gold = 250
	run.health = run.max_health - 5
	var before := run.snapshot()
	check(run.choose("caravan_shop"), "Browse the caravan before choosing work")
	var stock := run._shop_stock.duplicate()
	var relic := run._shop_relic
	check(not _option(run, "caravan_back").is_empty(), "An unspent caravan offers a return to its event")
	_restore_equal(run, "Caravan inspection and fixed stock restore")
	var card := _option(run, "buy_card:")
	check(not card.is_empty() and run.choose(str(card.id)), "Inspect a caravan spell placement")
	var pending := run.snapshot()
	check(_option(run, "caravan_back").is_empty() and not run.choose("caravan_back") and run.snapshot() == pending, "Pending placement must be canceled before leaving the wares")
	check(run.choose("back") and run.choose("caravan_back") and run.snapshot() == before, "Canceling the inspected spell returns without losing the job")
	check(run.choose("caravan_shop") and run._shop_stock == stock and run._shop_relic == relic, "Reopening does not reroll caravan stock")
	check(run.choose("caravan_back") and run.choose("caravan_guide") and run.gold == 262 and run.phase == "map", "The guiding job still pays exactly 12 after inspecting stock")
	_restore_equal(run, "Guiding receipt restores after free inspection")
	var saved := run.snapshot()
	check(not run.choose("caravan_guide") and run.snapshot() == saved, "The job cannot be claimed twice")
	for prefix: String in ["buy_card:", "buy_relic:", "shop_heal", "shop_prepare", "shop_remove:"]:
		var purchase := ELExpeditionRun.new()
		check(purchase.restore_snapshot(source, _json(before)) and purchase.choose("caravan_shop"), "Restore caravan before purchase " + prefix)
		var choice := _option(purchase, prefix)
		check(not choice.is_empty() and purchase.choose(str(choice.id)), "Complete available caravan service " + prefix)
		if choice.is_empty(): continue
		if prefix == "buy_card:": check(purchase.choose("add"), "Pay for the inspected caravan page")
		check(not purchase._shop_bought.is_empty() and _option(purchase, "caravan_back").is_empty(), "A completed purchase commits the trade branch: " + prefix)
		saved = purchase.snapshot()
		check(not purchase.choose("caravan_back") and not purchase.choose("caravan_guide") and purchase.snapshot() == saved, "A purchase cannot also claim guiding wages: " + prefix)
		_restore_equal(purchase, "Committed caravan stock restores: " + prefix)
		check(purchase.choose("leave") and purchase.phase == "map", "The purchased caravan still has a normal exit: " + prefix)
		caravan_purchases += 1

func _reject_opening_saves(source: ELProfile) -> void:
	var run := _enter(source, "rest", 12345, 1, V14)
	_reserve_pair(run)
	for value: Variant in [null, 1, [], {}, "unknown"]:
		var raw := run.snapshot()
		raw.opening_spell = value
		_reject(run, raw, "Malformed selected spell is rejected atomically: " + str(value))
	for value: Variant in [null, 1, [], {}, "true"]:
		var raw := run.snapshot()
		raw.opening_selecting = value
		_reject(run, raw, "Malformed rehearsal flag is rejected atomically: " + str(value))
		var suppressed := run.snapshot()
		suppressed.opening_suppressed = value
		_reject(run, suppressed, "Malformed set-aside flag is rejected atomically: " + str(value))
	for key: String in ["opening_spell", "opening_selecting", "opening_suppressed"]:
		var raw := run.snapshot()
		raw.erase(key)
		_reject(run, raw, "Rules 14 require explicit " + key)
	var unlearned := run.snapshot()
	unlearned.opening_suppressed = true
	_reject(run, unlearned, "A save cannot set aside a lesson that was never learned")
	for code: String in run._eligible_spells():
		if code in run.owned_spells(): continue
		var raw := run.snapshot()
		raw.opening_spell = code
		_reject(run, raw, "A legal spell not owned cannot be prepared by editing the save")
		break
	check(run.choose("swap_select:0"), "Select a reserve page for pending-state validation")
	var raw := run.snapshot()
	raw.opening_selecting = true
	_reject(run, raw, "Reserve exchange and rehearsal cannot be pending together")
	check(run.choose("back") and run.choose("opening_select"), "Select rehearsal for context validation")
	raw = run.snapshot()
	raw.phase = "map"
	_reject(run, raw, "The route cannot restore a camp-only selection")
	check(run.choose("back") and run.choose("forage"), "Create a rules 14 receipt through the real action")
	for key: String in ["opening_before", "opening_after"]:
		raw = run.snapshot()
		raw.last_outcome.erase(key)
		_reject(run, raw, "A receipt cannot omit " + key)
		raw = run.snapshot()
		raw.last_outcome[key] = []
		_reject(run, raw, "A receipt cannot forge the type of " + key)
	var haven := _enter(source, "boss", 12345, 3, V14)
	haven.gold = haven._merchant_price(ELExpeditionRun.OPENING_COST) - 1
	raw = haven.snapshot()
	raw.opening_selecting = true
	_reject(haven, raw, "An unaffordable Haven rehearsal cannot be restored")
	var caravan := _event(source, 5, 1, V14)
	caravan.choose("caravan_shop")
	raw = caravan.snapshot()
	raw.opening_selecting = true
	_reject(caravan, raw, "Ordinary merchants cannot restore the Haven-only service")

func _frozen_v13(source: ELProfile) -> void:
	var path := _argument("baseline")
	if path.is_empty():
		print("Frozen v13 comparison omitted: pass --baseline=/path/to/v13/run.gd.")
		return
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name ELExpeditionRun\n", "")
	check(script.reload() == OK and script.can_instantiate(), "Frozen v13 core loads read only as an anonymous model")
	if not script.can_instantiate(): return
	var seeds := clampi(int(_argument("seeds", "16")), 1, 64)
	for seed_value in seeds:
		for chapter in range(1, 4):
			var left := _new(source, seed_value, V13)
			var right: Variant = script.new()
			check(right.create(source, "ExpeditionFixtureRed", seed_value, V13) and right.choose("relic:amber_seed") and right.choose("study:none"), "Frozen v13 creates its original opening")
			for run: Variant in [left, right]:
				run._reset(source, run.preset, seed_value, chapter)
				run.health = run.max_health
				run.gold = 999
			check(left.route() == right.route(), "Rules 13 preserve frozen routes, event assignments and seeds")
			for room: Dictionary in left._nodes.values():
				_legacy_at(left, room, chapter)
				_legacy_at(right, room, chapter)
				check(left.choices() == right.choices() and left.room_summary() == right.room_summary() and left._offered_cards() == right._offered_cards() and left._relic_offers(3) == right._relic_offers(3) and left._shop_stock == right._shop_stock and left._shop_relic == right._shop_relic, "Rules 13 room %s seed %d matches frozen choices and offers" % [room.id, seed_value])
				legacy_rooms += 1
	for kind: String in ["rest", "haven", "library", "mirror", "forge", "anvil", "cartographer", "reward"]:
		var left: ELExpeditionRun
		match kind:
			"rest": left = _enter(source, "rest", 12345, 1, V13)
			"haven": left = _enter(source, "boss", 12345, 3, V13)
			"library": left = _event(source, ELExpeditionRun.LIBRARY_EVENT, 1, V13)
			"mirror": left = _event(source, 1, 1, V13)
			"forge": left = _event(source, 7, 1, V13)
			"anvil": left = _event(source, ELExpeditionRun.ANVIL_EVENT, 1, V13)
			"cartographer": left = _event(source, 8, 1, V13)
			"reward":
				left = _new(source, 12345, V13)
				left.choose_node(left.available()[0])
				_win_current(left)
		if left == null:
			check(false, "Reach rules 13 " + kind + " comparison checkpoint")
			continue
		left.gold = 200
		if kind in ["rest", "haven"]: _reserve_pair(left)
		var right: Variant = script.new()
		check(right.restore_snapshot(source, _json(left.snapshot())), "Frozen v13 restores current rules 13 " + kind)
		_legacy_equal(left, right, "Rules 13 " + kind + " initial state matches frozen behavior")
		var select := ""
		match kind:
			"rest", "haven": select = "swap_select:0"
			"library": select = str(_option(left, "library_card:").id)
			"mirror", "forge", "anvil": select = str(_option(left, "craft_select:").id)
			"cartographer": select = "cartographer_help"
			"reward": select = str(_option(left, "card:").id)
		check(left.choose(select) and right.choose(select), "Both rules 13 models accept " + kind + " selection")
		_legacy_equal(left, right, "Rules 13 " + kind + " selection matches frozen behavior")
		if kind == "cartographer": continue
		var restored: Variant = script.new()
		check(restored.restore_snapshot(source, _json(left.snapshot())) and restored.snapshot() == right.snapshot() and restored.choices() == right.choices(), "Frozen v13 resumes the exact current pending " + kind)
		var action := ""
		match kind:
			"rest", "haven": action = str(_option(left, "swap_with:").id)
			"library": action = "reserve_add"
			"mirror", "forge", "anvil": action = str(_option(left, "craft:").id)
			"reward": action = "add"
		check(left.choose(action) and right.choose(action), "Both rules 13 models commit " + kind + " once")
		_legacy_equal(left, right, "Rules 13 " + kind + " completion and receipt match the frozen release")
	check(legacy_rooms == seeds * 3 * 22 and legacy_stages == 23, "All frozen v13 rooms and selection/completion stages executed")
