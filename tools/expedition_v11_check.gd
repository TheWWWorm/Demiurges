extends "expedition_v10_check.gd"
## Real run/duel/save APIs with synthetic content. Lifecycle victories are
## forced; this is not a combat difficulty or campaign win-rate benchmark.
## Never reads or writes the player's Expedition save.

const V11 := 11
const V11_ROOT := "user://expedition_v11_check"

func _run() -> void:
	var source := Fixture.profile_at(V11_ROOT)
	check(source != null, "Version 11 synthetic content is available")
	if source != null:
		_legacy_isolation(source)
		_reserve_rewards(source)
		_reserve_merchants(source)
		_reserve_camps(source)
		_reserve_haven(source)
		_total_copy_limits(source)
		_recipes_lifecycle(source)
		_library_lifecycle(source)
		_exact_battle_resume(source)
		_invalid_refinements(source)
	check(checks >= 262, "The complete version 11 lifecycle suite executed")
	Fixture.clean(V11_ROOT)
	print("EXPEDITION VERSION 11: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _fresh(source: ELProfile, faction := "Red", seed_value := 12345) -> ELExpeditionRun:
	return _new(source, seed_value, V11, faction)

func _reward(source: ELProfile, faction := "Red") -> ELExpeditionRun:
	var run := _fresh(source, faction)
	if run == null or not run.choose_node(run.available()[0]) or _win_current(run) == null: return null
	return run

func _unused(run: ELExpeditionRun) -> String:
	for code: String in run._eligible_spells():
		if code not in run.deck and code not in run.reserve: return code
	return ""

func _same_owned(left: Array[String], right: Array[String]) -> bool:
	var a := left.duplicate()
	var b := right.duplicate()
	a.sort()
	b.sort()
	return a == b

func _restore_equal(run: ELExpeditionRun, label: String) -> ELExpeditionRun:
	var restored := _roundtrip(run)
	check(restored != null and restored.snapshot() == run.snapshot() and restored.choices() == run.choices(), label)
	return restored

func _legacy_isolation(source: ELProfile) -> void:
	for version in [8, 9, 10]:
		var run := _new(source, 12345, version)
		check(run != null and not run.refined() and not run.snapshot().has("reserve"), "Rules %d retain their reserve-free save format" % version)
		var highest := -1
		for row: Array in run.route():
			for room: Dictionary in row: highest = maxi(highest, int(room.get("event", -1)))
		check(highest <= (14 if version == 10 else (13 if version == 9 else 11)), "Rules %d cannot acquire new event indices" % version)
		check(run.choose_node(run.available()[0]) and _win_current(run) != null, "Rules %d still reach their original reward" % version)
		var card := str(_option(run, "card:").id)
		check(run.choose(card) and _option(run, "reserve_").is_empty(), "Rules %d do not gain reserve placement" % version)
		_restore_equal(run, "Rules %d pending reward restores with its old choices" % version)
	var mirror := _event(source, 1, 1, 10)
	check(mirror != null and _option(mirror, "craft_select:").is_empty() and not mirror._mirror_exchange().is_empty(), "Version 10 keeps its old single Mirror exchange")

func _reserve_rewards(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var run := _reward(source, faction)
		check(run != null and run.phase == "reward", faction + ": reach a real reward")
		if run == null: continue
		var code: String = run._offered_cards()[0]
		var before := run.snapshot()
		check(run.choose("card:" + code) and not _option(run, "reserve_add").is_empty(), faction + ": a reward offers a reserve slot")
		_restore_equal(run, faction + ": pending reserve placement survives JSON")
		check(run.choose("back") and run.snapshot() == before, faction + ": Back spends nothing and keeps the reward")
		var book := run.deck.duplicate()
		var life := run.health
		check(run.choose("card:" + code) and run.choose("reserve_add"), faction + ": place a normally acquired reward into reserve")
		check(run.reserve == [code] and run.deck == book and run.health == life and run.phase == "map", faction + ": storage consumes the reward without changing the active book or healing")
		check(not run.outcome_details().is_empty() and run._last_outcome.reserve_added == [code], faction + ": the outcome records the actual reserved page")
		_restore_equal(run, faction + ": stored page and outcome survive JSON")
		before = run.snapshot()
		check(not run.choose("reserve_add") and run.snapshot() == before, faction + ": the reward cannot be claimed twice")
	var full := _reward(source)
	var offers := full._offered_cards()
	full.reserve.assign([offers[1], offers[2]])
	var incoming: String = full._offered_cards()[0]
	check(full.choose("card:" + incoming), "A full reserve can still inspect another reward")
	check(_option(full, "reserve_add").is_empty() and not _option(full, "reserve_replace:").is_empty(), "A full reserve offers replacement, never a third slot")
	var replace := _option(full, "reserve_replace:")
	var old: String = replace.card
	var book := full.deck.duplicate()
	check(full.choose(str(replace.id)) and full.reserve.size() == 2 and full.deck == book and incoming in full.reserve, "Reserve replacement discards only the chosen stored page")
	check(full._last_outcome.reserve_removed == [old] and full._last_outcome.reserve_added == [incoming], "Reserve replacement reports the exact exchange")
	_restore_equal(full, "Full reserve replacement round-trips")

func _reserve_merchants(source: ELProfile) -> void:
	var run := _enter(source, "shop", 12345, 1, V11)
	check(run != null, "Reach a version 11 merchant")
	if run == null: return
	run.gold = 200
	var offer := _option(run, "buy_card:")
	var before := run.snapshot()
	check(run.choose(str(offer.id)), "Inspect a merchant spell for storage")
	check(int(_option(run, "reserve_add").cost) == int(offer.cost), "Reserve placement has the same price as active placement")
	_restore_equal(run, "Merchant reserve placement restores before payment")
	check(run.choose("back") and run.snapshot() == before, "Cancelling merchant storage neither spends gold nor consumes stock")
	var book := run.deck.duplicate()
	var gold_before := run.gold
	check(run.choose(str(offer.id)) and run.choose("reserve_add"), "Buy a spell into reserve")
	check(run.deck == book and run.reserve == [offer.card] and run.gold == gold_before - int(offer.cost) and run.phase == "shop", "Merchant storage pays exactly once and keeps shopping open")
	check(bool(_option(run, str(offer.id), false).get("disabled", false)), "A stored merchant spell is still sold stock")
	_restore_equal(run, "Stored merchant purchase and receipt restore")
	before = run.snapshot()
	check(not run.choose(str(offer.id)) and run.snapshot() == before, "Sold stock cannot be duplicated into reserve")

func _reserve_camps(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var run := _enter(source, "rest", 12345, 1, V11, -1, faction)
		check(run != null, faction + ": reach a camp for preparation")
		if run == null: continue
		var stored := _unused(run)
		check(not stored.is_empty(), faction + ": a distinct legal reserve page exists")
		if stored.is_empty(): continue
		run.reserve.append(stored)
		var before := run.snapshot()
		var level := int(run.battle_preview().level)
		var pages := run.deck.size()
		var charges := pages * run.charges_per_page()
		var owned := run.owned_spells()
		check(run.choose("swap_select:0") and run.pending_reserve == 0, faction + ": camp selects a reserved spell without payment")
		check(run.choices().all(func(row: Dictionary) -> bool: return str(row.id).begins_with("swap_with:") or row.id == "back"), faction + ": a pending swap cannot also rest or train")
		_restore_equal(run, faction + ": pending camp swap restores exactly")
		check(run.choose("back") and run.snapshot() == before, faction + ": cancelling preparation preserves the camp action")
		check(run.choose("swap_select:0"), faction + ": reopen preparation")
		var swap := _option(run, "swap_with:")
		var outgoing: String = swap.card
		check(run.choose(str(swap.id)) and run.phase == "map", faction + ": confirming the swap spends the camp visit")
		check(run.deck.size() == pages and run.deck.count(stored) == 1 and run.reserve == [outgoing] and _same_owned(owned, run.owned_spells()), faction + ": swap conserves every page and active-book size")
		check(run.charges_per_page() * run.deck.size() == charges and int(run.battle_preview().level) == level, faction + ": swapping gives no extra charges or level bonus")
		before = run.snapshot()
		check(not run.choose("heal") and not run.choose(str(swap.id)) and run.snapshot() == before, faction + ": the camp cannot be used a second time")
		_restore_equal(run, faction + ": completed preparation round-trips")

func _reserve_haven(source: ELProfile) -> void:
	var run := _enter(source, "boss", 12345, 3, V11)
	check(run != null and run.phase == "haven", "Reach the real final Haven")
	if run == null: return
	var stored := _unused(run)
	run.reserve.append(stored)
	run.gold = 200
	var before := run.snapshot()
	check(run.choose("swap_select:0"), "The Haven offers one paid reserve exchange")
	check(int(_option(run, "swap_with:").cost) == ELExpeditionRun.RESERVE_SWAP_COST, "The base Haven exchange costs 18 gold")
	_restore_equal(run, "Pending Haven preparation restores")
	check(run.choose("back") and run.snapshot() == before, "Cancelling Haven preparation does not pay")
	check(run.choose("swap_select:0"), "Reopen Haven preparation")
	var swap := _option(run, "swap_with:")
	var gold_before := run.gold
	var owned := run.owned_spells()
	check(run.choose(str(swap.id)) and run.phase == "haven" and run.gold == gold_before - 18, "Haven exchange pays once and remains in the shop")
	check(_same_owned(owned, run.owned_spells()) and bool(_option(run, "swap_select:", false).get("disabled", false)), "Haven conserves pages and disables its spent exchange")
	_restore_equal(run, "Spent Haven service restores")
	before = run.snapshot()
	check(not run.choose("swap_select:0") and run.snapshot() == before, "Haven service cannot be replayed")
	check(run.choose("enter_guardian") and run.build_battle() != null, "Preparation still leads to the actual guardian")
	before = run.snapshot()
	check(not run.choose("swap_select:0") and not run.choose("reserve_add") and run.snapshot() == before, "Reserve cannot be edited during a duel")

func _total_copy_limits(source: ELProfile) -> void:
	var run := _reward(source)
	var code := _unused(run)
	check(not code.is_empty(), "A legal absent card is available for cap checks")
	if code.is_empty(): return
	for index in 3: run.deck[index] = code
	run.reserve.append(code)
	check(run.owned_copies(code) == 4 and code not in run._eligible_spells() and code not in run._offered_cards(), "Four active-plus-reserve copies exclude further rewards")
	_restore_equal(run, "Exactly four combined copies are a valid checkpoint")
	var raw := run.snapshot()
	raw.reserve.append(code)
	var before := run.snapshot()
	check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == before, "Five combined copies are rejected atomically")
	var shop := _enter(source, "shop", 12345, 1, V11)
	shop.deck = run.deck.duplicate()
	shop.reserve = run.reserve.duplicate()
	shop._prepare_shop()
	check(code not in shop._shop_stock, "Shop generation counts reserved copies")
	var mirror := _event(source, 1, 1, V11)
	mirror.deck = run.deck.duplicate()
	mirror.reserve = run.reserve.duplicate()
	check(mirror.choices().filter(func(row: Dictionary) -> bool: return str(row.id).begins_with("echo:") and row.card == code).is_empty(), "Mirror cannot copy a fifth combined page")
	check(run.charges_per_page() == ELSpellCharges.providence(run._starting_skills()), "Charge guidance uses the same Providence rule as the duel")

func _recipes_lifecycle(source: ELProfile) -> void:
	for event_index in [1, 7, ELExpeditionRun.ANVIL_EVENT]:
		var run := _event(source, event_index, 1, V11)
		check(run != null, "Crafting event %d is reachable on generated routes" % event_index)
		if run == null: continue
		run.gold = 200
		var source_offer := _option(run, "craft_select:")
		check(not source_offer.is_empty(), "Crafting event %d has a usable source" % event_index)
		if source_offer.is_empty(): continue
		var before := run.snapshot()
		check(run.choose(str(source_offer.id)) and run.pending_craft == source_offer.card, "Crafting event %d selects the outgoing page first" % event_index)
		var options := run.choices()
		check(options.size() >= 2 and options.size() <= 3 and options.back().id == "back", "Crafting event %d offers up to two recipes and Back" % event_index)
		_restore_equal(run, "Crafting event %d preserves pending recipes through JSON" % event_index)
		check(run.choose("back") and run.snapshot() == before, "Crafting event %d cancels without payment or page loss" % event_index)
		check(run.choose(str(source_offer.id)) and run.choices() == options, "Crafting event %d cannot reroll by reselecting its source" % event_index)
		var recipe := _option(run, "craft:")
		var old_count := run.deck.count(str(recipe.card))
		var new_count := run.deck.count(str(recipe.incoming))
		var pages := run.deck.size()
		var life := run.health
		var gold_before := run.gold
		var consume := int(recipe.consume)
		check(run.choose(str(recipe.id)) and run.phase == "map", "Crafting event %d commits one service" % event_index)
		check(run.deck.size() == pages - consume + 1 and run.deck.count(str(recipe.card)) == old_count - consume and run.deck.count(str(recipe.incoming)) == new_count + 1, "Crafting event %d exchanges the exact page multiplicity" % event_index)
		check(run.health == life - (3 if event_index == 1 else 0) and run.gold == gold_before - (0 if event_index == 1 else (12 if event_index == ELExpeditionRun.ANVIL_EVENT else 32)), "Crafting event %d pays the disclosed cost exactly once" % event_index)
		check(run._last_outcome.book_added == [recipe.incoming] and run._last_outcome.book_removed.size() == consume, "Crafting event %d records actual card changes" % event_index)
		_restore_equal(run, "Crafting event %d completed outcome round-trips" % event_index)
		before = run.snapshot()
		check(not run.choose(str(recipe.id)) and run.snapshot() == before, "Crafting event %d cannot be replayed" % event_index)
	var anvil := _event(source, ELExpeditionRun.ANVIL_EVENT, 1, V11)
	anvil.deck.resize(ELExpeditionRun.MIN_DECK)
	check(_option(anvil, "craft_select:", false).is_empty(), "Anvil cannot reduce an eight-page book below minimum")
	var gold_before := anvil.gold
	check(anvil.choose("anvil_salvage") and anvil.gold == gold_before + 10, "An unusable Anvil still offers its ten-gold alternative")
	var mirror := _event(source, 1, 1, V11)
	mirror.health = 3
	var unavailable := _option(mirror, "craft_select:", false)
	check(not unavailable.is_empty() and bool(unavailable.get("disabled", false)) and not mirror.choose(str(unavailable.id)), "Mirror cannot consume the last three life")
	var forge := _event(source, 7, 1, V11)
	forge.gold = 31
	unavailable = _option(forge, "craft_select:", false)
	check(not unavailable.is_empty() and bool(unavailable.get("disabled", false)) and not forge.choose(str(unavailable.id)), "Forge cannot begin an unaffordable binding")

func _library_lifecycle(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var run: ELExpeditionRun = null
		for seed_value in 64:
			run = _enter(source, "event", seed_value, 1, V11, ELExpeditionRun.LIBRARY_EVENT, faction)
			if run != null: break
		check(run != null, faction + ": the Library is reachable")
		if run == null: continue
		var offer := _option(run, "library_card:")
		check(not offer.is_empty(), faction + ": the Library has an affordable page")
		if offer.is_empty(): continue
		var before := run.snapshot()
		check(run.choose(str(offer.id)), faction + ": inspect Library storage")
		check(_option(run, "add").is_empty() and _option(run, "replace:").is_empty() and not _option(run, "reserve_add").is_empty(), faction + ": Library pages cannot go straight into the active book")
		_restore_equal(run, faction + ": pending Library placement restores")
		check(run.choose("back") and run.snapshot() == before, faction + ": cancelling keeps the original Library offers")
		var book := run.deck.duplicate()
		check(run.choose(str(offer.id)) and run.choose("reserve_add") and run.phase == "map" and run.deck == book and run.reserve == [offer.card], faction + ": Library gives one stored page and consumes the visit")
		_restore_equal(run, faction + ": packed Library page restores")
	var notes := _event(source, ELExpeditionRun.LIBRARY_EVENT, 1, V11)
	var gold_before := notes.gold
	check(notes.choose("library_notes") and notes.gold == gold_before + 12 and notes.reserve.is_empty(), "Library notes are a twelve-gold alternative, not an additional reward")
	_restore_equal(notes, "Library notes and receipt round-trip")

func _exact_battle_resume(source: ELProfile) -> void:
	var run := _fresh(source)
	var stored := _unused(run)
	run.reserve.append(stored)
	check(run.choose_node(run.available()[0]), "Enter a duel with a reserve page")
	var duel := run.build_battle()
	check(duel != null and duel.heroes[0].deck == run.deck and stored not in duel.heroes[0].deck, "Only the active book enters combat")
	if duel == null: return
	check(duel.heroes[0].spell_uses.size() == run.deck.size() and duel.heroes[0].spell_uses.all(func(value: int) -> bool: return value == run.charges_per_page()), "Reserved pages add neither slots nor duel charges")
	run._battle_checkpoint = duel.snapshot()
	var rng := duel.rng_state
	var restored := _roundtrip(run)
	check(restored != null and int(restored._battle_checkpoint.rng) == rng, "Run restoration preserves the exact saved random state")
	if restored == null: return
	var resumed := restored.build_battle()
	check(resumed != null and resumed.rng_state == rng and resumed.snapshot() == duel.snapshot(), "Resuming retains the exact battle checkpoint")
	if resumed == null: return
	for step in 6:
		var left := duel.end_phase()
		var right := resumed.end_phase()
		check(left == right and duel.snapshot() == resumed.snapshot(), "Identical continuation command %d produces identical draws, random effects, and state" % (step + 1))
	var before := run.snapshot()
	var mismatch := run.snapshot()
	var alternate := _unused(run)
	mismatch.reserve = [alternate]
	check(not run.restore_snapshot(source, _json(mismatch)) and run.snapshot() == before, "A battle checkpoint cannot be rebound to a different reserve")
	check(run.build_battle(true) == null and run.snapshot() == before, "Version 11 keeps the in-fight restart restriction")

func _invalid_refinements(source: ELProfile) -> void:
	var run := _reward(source)
	var saved := run.snapshot()
	var bad_fields := {
		"reserve": [null, 7, {}, ["missing"], [run.deck[0], run.deck[1], run.deck[2]]],
		"pending_reserve": [null, "0", 0.5, -2, 2, 0],
		"pending_craft": [null, 7, [], "missing", run.deck[0]],
		"last_outcome": [null, 7, [], {"gold": 1}],
	}
	for field: String in bad_fields:
		for value: Variant in bad_fields[field]:
			var raw := saved.duplicate(true)
			raw[field] = value
			check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == saved, "Malformed %s=%s cannot replace the live run" % [field, str(value)])
	for field: String in bad_fields:
		var raw := saved.duplicate(true)
		raw.erase(field)
		check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == saved, "A version 11 save must carry %s" % field)
	var library := _event(source, ELExpeditionRun.LIBRARY_EVENT, 1, V11)
	var card := _option(library, "library_card:")
	library.choose(str(card.id))
	var raw := library.snapshot()
	raw.pending_craft = library.deck[0]
	check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == saved, "Two simultaneous pending placement stages are rejected")
	var mirror := _event(source, 1, 1, V11)
	mirror.choose(str(_option(mirror, "craft_select:").id))
	raw = mirror.snapshot()
	raw.health = 3
	check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == saved, "Pending Mirror payment is validated against saved life, not fresh-run life")
	library = _event(source, ELExpeditionRun.LIBRARY_EVENT, 1, V11)
	var blocked := ""
	for code: String in library._library_offers():
		if library.deck.count(code) <= 1:
			blocked = code
			break
	check(not blocked.is_empty(), "A Library page can exercise a full identical reserve")
	if not blocked.is_empty():
		library.reserve.assign([blocked, blocked])
		var blocked_offer := _option(library, "library_card:" + blocked, false)
		check(not blocked_offer.is_empty() and bool(blocked_offer.get("disabled", false)) and not library.choose(str(blocked_offer.id)), "The Library disables a page with no meaningful reserve destination")
		raw = library.snapshot()
		raw.pending_card = blocked
		check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == saved, "An unplaceable pending Library page is rejected during restore")
	var receipt := _reward(source)
	receipt.choose("card:" + receipt._offered_cards()[0])
	receipt.choose("reserve_add")
	for field: String in ["gold", "life", "maximum", "training", "prepared", "book_added", "reserve_added", "relics_added"]:
		raw = receipt.snapshot()
		raw.last_outcome[field] = null
		check(not run.restore_snapshot(source, _json(raw)) and run.snapshot() == saved, "Malformed outcome field %s is rejected before rendering" % field)
