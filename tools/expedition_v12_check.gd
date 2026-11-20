extends "expedition_v11_check.gd"
## Real route/choice/duel/save APIs with synthetic content. Journey setup
## forces victories; this is not a combat or campaign win-rate benchmark.
## Never reads or writes the player's save.
## godot --headless --path game --script ../tools/expedition_v12_check.gd -- \
##   --baseline=/path/to/frozen-v11/run.gd --seeds=16 --output=/tmp/v12.json

const V12 := 12
const V12_ROOT := "user://expedition_v12_check"
var legacy_rooms := 0
var legacy_stages := 0

func _argument(name: String, fallback := "") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.trim_prefix("--" + name + "=")
	return fallback

func _run() -> void:
	var source := Fixture.profile_at(V12_ROOT)
	check(source != null, "Version 12 synthetic content is available")
	if source != null:
		_version_boundary(source)
		_camp_arrangement(source)
		_haven_arrangement(source)
		_library_placements(source)
		_cartographer_bargain(source)
		_reward_identity(source)
		_story_receipts(source)
		_zero_resource_story(source)
		_reject_v12_saves(source)
		_exact_battle_resume(source)
		_frozen_v11(source)
	check(checks >= 300, "The complete version 12 boundary suite executed")
	var output := _argument("output")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		check(file != null, "Version 12 audit result can be saved")
		if file != null:
			file.store_string(JSON.stringify({"rules": V12, "checks": checks, "failures": failures,
				"legacy_rooms": legacy_rooms, "legacy_stages": legacy_stages,
				"baseline": _argument("baseline"), "seeds": clampi(int(_argument("seeds", "16")), 1, 64),
				"assumptions": ["Synthetic content with real route, choice and checkpoint APIs.",
					"Lifecycle setup forces victories; no combat or campaign win rate is estimated.",
					"Frozen core is loaded read only with current shared content and localization.",
					"Frozen room sweep uses controlled states; lifecycle checks use reachable journeys."]}, "\t", true, true))
	Fixture.clean(V12_ROOT)
	print("EXPEDITION VERSION 12: %d checks, %d failure(s); %d frozen-v11 rooms, %d pending/completed stages" % [checks, failures.size(), legacy_rooms, legacy_stages])
	quit(0 if failures.is_empty() else 1)

func _fresh(source: ELProfile, faction := "Red", seed_value := 12345) -> ELExpeditionRun:
	return _new(source, seed_value, V12, faction)

func _settle(run: ELExpeditionRun) -> bool:
	# Full-life Rest is unavailable in v12. Setup uses the useful alternative.
	if run.rebalanced() and run.phase == "rest" and run.health == run.max_health:
		return run.choose("forage")
	return super._settle(run)

func _library_for(source: ELProfile, faction := "Red", chapter := 1) -> ELExpeditionRun:
	for seed_value in 128:
		var run := _enter(source, "event", seed_value, chapter, V12, ELExpeditionRun.LIBRARY_EVENT, faction)
		if run != null: return run
	return null

func _reserve_pair(run: ELExpeditionRun) -> void:
	for code: String in run._eligible_spells():
		if code not in run.deck and code not in run.reserve: run.reserve.append(code)
		if run.reserve.size() == ELExpeditionRun.RESERVE_LIMIT: return

func _fill_book(run: ELExpeditionRun, count: int, excluded := "") -> bool:
	while run.deck.size() < count:
		var added := false
		for code: String in run._eligible_spells():
			if code == excluded: continue
			run.deck.append(code)
			added = true
			break
		if not added: return false
	return true

func _copy_state(run: ELExpeditionRun, code: String, active: int, stored: int) -> void:
	for index in run.deck.size():
		if run.deck[index] == code:
			for other: String in run._eligible_spells():
				if other != code:
					run.deck[index] = other
					break
	for index in active: run.deck[index] = code
	run.reserve.clear()
	for index in stored: run.reserve.append(code)

func _reject(run: ELExpeditionRun, raw: Dictionary, label: String) -> void:
	var before := run.snapshot()
	check(not run.restore_snapshot(run.profile, _json(raw)) and run.snapshot() == before, label)

func _readonly(run: ELExpeditionRun, label: String) -> void:
	var before := run.snapshot()
	var offers := run.choices()
	var summary := run.room_summary()
	var outcome := run.outcome_details()
	var ownership := run.owned_spells()
	if not offers.is_empty(): offers[0].title = "test-only changed copy"
	summary.clear()
	outcome.clear()
	ownership.clear()
	check(run.snapshot() == before and (offers.is_empty() or run.choices() != offers), label)

func _version_boundary(source: ELProfile) -> void:
	var latest := ELExpeditionRun.new()
	check(latest.create(source, "ExpeditionFixtureRed", 12345, V12) and latest.rebalanced() and int(latest.snapshot().version) == V12, "Explicit rules 12 retain their original identity")
	for version in [8, 9, 10, 11]:
		var old := _new(source, 12345, version)
		check(old != null and not old.rebalanced() and int(old.snapshot().version) == version, "Explicit rules %d retain their original identity" % version)
		_restore_equal(old, "Rules %d retain their checkpoint identity" % version)

func _camp_arrangement(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var run := _enter(source, "rest", 12345, 1, V12, -1, faction)
		check(run != null, faction + ": reach a camp through a valid journey")
		if run == null: continue
		run.deck.resize(12)
		run.relics.append("duelists_crest")
		_reserve_pair(run)
		check(run.reserve.size() == 2, faction + ": two distinct reserve pages are available")
		if run.reserve.size() != 2: continue
		run.gold = 0
		var level := int(run.battle_preview().level)
		var charges := run.deck.size() * run.charges_per_page()
		var owned := run.owned_spells()
		var life := run.health
		var before := run.snapshot()
		check(bool(_option(run, "heal", false).get("disabled", false)) and not _option(run, "forage").is_empty(), faction + ": full-life Rest is disabled but supplies remain available")
		check(not run.choose("heal") and run.snapshot() == before, faction + ": unavailable Rest preserves the camp")
		for step in 3:
			before = run.snapshot()
			var slot := step % 2
			check(run.choose("swap_select:%d" % slot) and run.pending_reserve == slot, faction + ": select free reserve swap %d" % step)
			check(run.choices().all(func(row: Dictionary) -> bool: return str(row.id).begins_with("swap_with:") or row.id == "back"), faction + ": a pending swap isolates its placement stage")
			_restore_equal(run, faction + ": pending free camp swap restores exactly")
			var swap := _option(run, "swap_with:")
			check(not swap.is_empty() and int(swap.get("cost", 0)) == 0, faction + ": camp swap has no hidden payment")
			check(run.choose("back") and run.snapshot() == before, faction + ": canceling the swap changes nothing")
			check(not run.choose(str(swap.get("id", "swap_with:0"))) and run.snapshot() == before, faction + ": stale canceled swap cannot commit")
			check(run.choose("swap_select:%d" % slot) and run.choose(str(swap.id)), faction + ": confirm free reserve swap %d" % step)
			check(run.phase == "rest" and run.pending_reserve == -1 and run.gold == 0 and run.health == life and "reserve_swap" not in run._shop_bought, faction + ": swap preserves the camp action and spends no resources")
			check(run.deck.size() == 12 and run.reserve.size() == 2 and _same_owned(owned, run.owned_spells()), faction + ": repeated preparation conserves every owned page")
			check(run.deck.size() * run.charges_per_page() == charges and int(run.battle_preview().level) == level, faction + ": preparation does not change charges or Crest level")
			check(run._last_outcome.book_added.size() == 1 and run._last_outcome.book_removed.size() == 1 and run._last_outcome.reserve_added.size() == 1 and run._last_outcome.reserve_removed.size() == 1 and int(run._last_outcome.gold) == 0, faction + ": swap receipt records one conserved exchange")
			_restore_equal(run, faction + ": completed free camp swap restores exactly")
			before = run.snapshot()
			check(not run.choose(str(swap.id)) and run.snapshot() == before, faction + ": stale confirmed swap cannot replay")
		_readonly(run, faction + ": preparation summaries and choices do not mutate the run")
		check(run.choose("forage") and run.phase == "map" and run.gold == 18, faction + ": the main camp action remains available after every swap")
		before = run.snapshot()
		check(not run.choose("forage") and not run.choose("heal") and not run.choose("swap_select:0") and run.snapshot() == before, faction + ": completing the main action closes the camp exactly once")
		_restore_equal(run, faction + ": completed camp and receipt round-trip")
	var hurt := _enter(source, "rest", 12345, 1, V12)
	hurt.health = hurt.max_health - 10
	_reserve_pair(hurt)
	check(hurt.choose("swap_select:0") and hurt.choose(str(_option(hurt, "swap_with:").id)), "An injured hero can prepare before resting")
	var healing := hurt._heal_amount(hurt._camp_healing())
	var health_before := hurt.health
	check(hurt.choose("heal") and hurt.phase == "map" and hurt.health == health_before + healing, "Preparation preserves the advertised camp healing")
	var trained := _enter(source, "rest", 12345, 2, V12)
	_reserve_pair(trained)
	trained.choose("swap_select:0")
	trained.choose(str(_option(trained, "swap_with:").id))
	var train := _option(trained, "train:")
	check(not train.is_empty() and trained.choose(str(train.id)) and trained.phase == "map" and trained._training_sessions() == 1, "Preparation preserves the one main training action")

func _haven_arrangement(source: ELProfile) -> void:
	var run := _enter(source, "boss", 12345, 3, V12)
	check(run != null and run.phase == "haven", "Reach the real final Haven")
	if run == null: return
	_reserve_pair(run)
	check(run.reserve.size() == 2, "Haven has two carried reserve pages")
	run.gold = 0
	var stock := run._shop_stock.duplicate()
	var owned := run.owned_spells()
	var pages := run.deck.size()
	var charges := run.charges_per_page() * pages
	for step in 4:
		var before := run.snapshot()
		check(run.choose("swap_select:%d" % (step % 2)), "Haven can begin free swap %d with no gold" % step)
		_restore_equal(run, "Pending Haven swap %d survives reload" % step)
		var option := _option(run, "swap_with:")
		check(not option.is_empty() and int(option.get("cost", 0)) == 0, "Haven outgoing selection has no charge")
		check(run.choose("back") and run.snapshot() == before, "Haven cancel does not consume a service")
		check(run.choose("swap_select:%d" % (step % 2)) and run.choose(str(option.id)), "Haven confirms free swap %d" % step)
		check(run.phase == "haven" and run.gold == 0 and run._shop_bought.is_empty() and run._shop_stock == stock, "Haven rearrangement does not consume gold or merchant stock")
		check(run.deck.size() == pages and run.charges_per_page() * pages == charges and _same_owned(owned, run.owned_spells()), "Haven rearrangement conserves size, charges and ownership")
		_restore_equal(run, "Completed Haven swap %d survives reload" % step)
	var forged := run.snapshot()
	forged.shop.bought.append("reserve_swap")
	_reject(run, forged, "Rules 12 reject the obsolete paid-Haven service marker atomically")
	run.gold = 200
	var offer := _option(run, "buy_card:")
	check(not offer.is_empty() and run.choose(str(offer.id)) and _option(run, "reserve_add").is_empty(), "Haven purchases still go directly into the active book")
	check(run.choose("back"), "Cancel a Haven purchase after rearrangement")
	check(run.choose("enter_guardian") and run.build_battle() != null, "Free preparation still reaches the actual final guardian")
	var before := run.snapshot()
	check(not run.choose("swap_select:0") and not run.choose("reserve_add") and run.snapshot() == before, "No reserve changes are permitted during the final duel")

func _library_placements(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var original := _library_for(source, faction)
		check(original != null, faction + ": reach a generated Library room")
		if original == null: continue
		var offer := _option(original, "library_card:")
		check(not offer.is_empty(), faction + ": the Library offers an affordable legal page")
		if offer.is_empty(): continue
		var code: String = offer.card
		for destination: String in ["add", "replace", "reserve_add", "reserve_replace"]:
			var run := _roundtrip(original)
			if run == null: continue
			if destination == "reserve_replace": _reserve_pair(run)
			var before := run.snapshot()
			var book := run.deck.duplicate()
			var stored := run.reserve.duplicate()
			var gold_before := run.gold
			check(run.choose("library_card:" + code), faction + ": inspect Library placement " + destination)
			check(not _option(run, "add").is_empty() and not _option(run, "replace:").is_empty(), faction + ": Library can immediately add or replace an active page")
			check(run.choices().filter(func(row: Dictionary) -> bool: return str(row.id).begins_with("replace:") and row.card == code).is_empty(), faction + ": Library omits identical active replacements")
			_restore_equal(run, faction + ": pending Library " + destination + " restores exactly")
			check(run.choose("back") and run.snapshot() == before, faction + ": backing out preserves the Library reward")
			check(not run.choose("add") and run.snapshot() == before, faction + ": a stale Library placement cannot be applied")
			check(run.choose("library_card:" + code), faction + ": reopen the same Library offer")
			var action := destination
			if destination in ["replace", "reserve_replace"]: action = str(_option(run, destination + ":").get("id", ""))
			check(not action.is_empty() and run.choose(action) and run.phase == "map", faction + ": claim one Library page via " + destination)
			check(run.gold == gold_before and run.pending_card.is_empty(), faction + ": the Library page costs no gold and clears its pending stage")
			if destination == "add":
				check(run.deck.size() == book.size() + 1 and run.deck.count(code) == book.count(code) + 1 and run.reserve == stored, faction + ": Library add supplies exactly one active page")
			elif destination == "replace":
				check(run.deck.size() == book.size() and run.deck.count(code) == book.count(code) + 1 and run.reserve == stored, faction + ": Library replacement preserves active size")
			elif destination == "reserve_add":
				check(run.deck == book and run.reserve == [code], faction + ": optional Library storage adds no active page")
			else:
				check(run.deck == book and run.reserve.size() == 2 and code in run.reserve, faction + ": Library replaces one full-reserve slot")
			check(run.owned_copies(code) <= 4 and str(run._last_outcome.get("story", "")) == "16:" + action.get_slice(":", 0), faction + ": Library receipt records its actual completion path")
			_restore_equal(run, faction + ": completed Library " + destination + " restores exactly")
			before = run.snapshot()
			check(not run.choose(action) and not run.choose("library_notes") and not run.choose("library_card:" + code) and run.snapshot() == before, faction + ": Library cannot pay a second reward")
		var full := _roundtrip(original)
		check(_fill_book(full, ELExpeditionRun.MAX_DECK, code), faction + ": construct a legal maximum-size book")
		var full_code: String = full._library_offers()[0]
		check(full.choose("library_card:" + full_code) and _option(full, "add").is_empty() and not _option(full, "replace:").is_empty(), faction + ": a 24-page book can replace a Library page")
		_restore_equal(full, faction + ": maximum-book Library placement survives reload")
		var replacement := _option(full, "replace:")
		check(full.choose(str(replacement.id)) and full.deck.size() == ELExpeditionRun.MAX_DECK and full._last_outcome.book_added == [full_code] and full._last_outcome.book_removed == [replacement.card], faction + ": maximum-book Library replacement exchanges exactly one page")
		var identical := _roundtrip(original)
		_copy_state(identical, code, 0, 2)
		check(not identical._can_pack_spell(code) and not _option(identical, "library_card:" + code).is_empty(), faction + ": identical full reserve does not block active Library placement")
		check(identical.choose("library_card:" + code) and _option(identical, "reserve_").is_empty() and not _option(identical, "add").is_empty(), faction + ": only impossible reserve destinations are omitted")
		_restore_equal(identical, faction + ": active Library placement with an identical full reserve restores")
		check(identical.choose("add") and identical.reserve == [code, code] and identical.deck.count(code) == 1, faction + ": Library preserves both existing reserved copies")
		var capped := _roundtrip(original)
		_copy_state(capped, code, 3, 1)
		check(capped.owned_copies(code) == 4 and code not in capped._library_offers() and _option(capped, "library_card:" + code, false).is_empty(), faction + ": four combined copies exclude the Library offer")
		_restore_equal(capped, faction + ": four combined copies remain a valid Library state")
		var bad := capped.snapshot()
		bad.pending_card = code
		_reject(capped, bad, faction + ": a forged fifth-copy Library selection is rejected")
		bad = capped.snapshot()
		bad.reserve.append(code)
		_reject(capped, bad, faction + ": a fifth owned page cannot be restored")
	var notes := _library_for(source)
	var gold_before := notes.gold
	var book := notes.deck.duplicate()
	check(notes.choose("library_notes") and notes.gold == gold_before + 12 and notes.deck == book and notes.reserve.is_empty(), "Library catalogue pays twelve gold instead of a card")
	_restore_equal(notes, "Library catalogue payment and story survive reload")

func _cartographer_bargain(source: ELProfile) -> void:
	for chapter in range(1, 4):
		var run := _event(source, 8, chapter, V12)
		check(run != null, "Act %d Cartographer is reachable" % chapter)
		if run == null: continue
		var cost := chapter + 3
		var payment := chapter * 4 + 20
		check(run._cartographer_trade() == {"life": cost, "gold": payment}, "Act %d Cartographer uses the scaled bargain" % chapter)
		run.health = cost
		var before := run.snapshot()
		check(bool(_option(run, "cartographer_help", false).get("disabled", false)) and not run.choose("cartographer_help") and run.snapshot() == before, "Act %d bargain cannot consume the last life" % chapter)
		_restore_equal(run, "Act %d exact-life boundary restores" % chapter)
		run.health = cost + 1
		var offer := _option(run, "cartographer_help")
		check(not offer.is_empty() and str(offer.description).contains(str(cost)) and str(offer.description).contains(str(payment)), "Act %d offer discloses its exact price and payment" % chapter)
		var gold_before := run.gold
		check(run.choose("cartographer_help") and run.health == 1 and run.gold == gold_before + payment and run.phase == "map", "Act %d bargain applies exactly once and leaves one life" % chapter)
		check(int(run._last_outcome.life) == -cost and int(run._last_outcome.gold) == payment and run._last_outcome.story == "8:cartographer_help", "Act %d receipt reports the actual bargain" % chapter)
		_restore_equal(run, "Act %d bargain and story round-trip" % chapter)
		before = run.snapshot()
		check(not run.choose("cartographer_help") and run.snapshot() == before, "Act %d bargain cannot pay twice" % chapter)
		var medicine := _event(source, 8, chapter, V12)
		medicine.health = 1
		medicine.gold = 22
		var heal := medicine._heal_amount(0.4)
		check(int(_option(medicine, "cartographer_heal").cost) == 22 and medicine.choose("cartographer_heal") and medicine.gold == 0 and medicine.health == 1 + heal, "Act %d medicine retains 22-gold 40-percent recovery" % chapter)
		var old := _event(source, 8, chapter, V11)
		check(old._cartographer_trade() == {"life": 4, "gold": 38}, "Rules 11 retain the old Cartographer bargain in act %d" % chapter)

func _reward_identity(source: ELProfile) -> void:
	var run := _reward(source)
	var code: String = run._offered_cards()[0]
	if code not in run.deck: run.deck[0] = code
	check(run.choose("card:" + code), "Inspect a version 12 battle reward")
	check(run.choices().filter(func(row: Dictionary) -> bool: return str(row.id).begins_with("replace:") and row.card == code).is_empty(), "Battle rewards cannot replace an identical copy")
	_restore_equal(run, "Pending reward with useful replacements restores")
	var before := run.snapshot()
	var index := run.deck.find(code)
	check(index >= 0 and not run.choose("replace:%d" % index) and run.snapshot() == before, "A stale same-card reward replacement is rejected")
	check(run.choose("back"), "The reward can still be reconsidered")
	var old := _new(source, 12345, V11)
	old.choose_node(old.available()[0])
	_win_current(old)
	code = old._offered_cards()[0]
	if code not in old.deck: old.deck[0] = code
	old.choose("card:" + code)
	index = old.deck.find(code)
	check(index >= 0 and not _option(old, "replace:%d" % index).is_empty(), "Rules 11 retain their original identical reward replacement")

func _story_receipts(source: ELProfile) -> void:
	var prior_language := OS.get_environment("DEMIURGES_LANGUAGE")
	OS.set_environment("DEMIURGES_LANGUAGE", "en")
	var run := _event(source, 8, 1, V12)
	run.choose("cartographer_help")
	var english := run.outcome_details()
	check(not str(english.get("title", "")).is_empty() and str(english.get("description", "")).contains(ELExpeditionContent.outcome(source, "8:cartographer_help")) and str(english.description).contains("Gold: +24"), "English receipt combines event consequence and exact resource changes")
	var before := run.snapshot()
	OS.set_environment("DEMIURGES_LANGUAGE", "ru")
	var russian := run.outcome_details()
	check(russian != english and str(russian.description).contains("Золото: +24") and str(russian.description).contains(ELExpeditionContent.outcome(source, "8:cartographer_help")), "The same receipt localizes story and deltas into Russian")
	check(run.snapshot() == before and run._last_outcome.story == "8:cartographer_help", "Receipt language leaves the saved story identity unchanged")
	_restore_equal(run, "Localized event receipt survives JSON")
	OS.set_environment("DEMIURGES_LANGUAGE", "en")
	var departed := _library_for(source)
	var owned := departed.owned_spells()
	var gold_before := departed.gold
	var departure_receipt := departed._last_outcome.duplicate(true)
	check(departed.choose("leave") and departed.phase == "map" and departed.gold == gold_before and departed.owned_spells() == owned, "Leaving a Library costs no resources")
	check(departed._last_outcome == departure_receipt, "An unannotated departure does not invent a story or resource receipt")
	_restore_equal(departed, "No-cost departure round-trips")
	var pending := _library_for(source)
	var saved_receipt := pending._last_outcome.duplicate(true)
	pending.choose(str(_option(pending, "library_card:").id))
	check(pending._last_outcome == saved_receipt, "Inspecting a Library page does not claim its story")
	pending.choose("back")
	check(pending._last_outcome == saved_receipt, "Canceling a Library page does not overwrite the previous outcome")
	_readonly(run, "Localized receipt and summary helpers return detached data")
	OS.set_environment("DEMIURGES_LANGUAGE", prior_language)

func _zero_resource_story(source: ELProfile) -> void:
	var run := _event(source, 0, 1, V12)
	check(run != null, "Reach a Spring with a real artifact-loan choice")
	if run == null: return
	var offer := _option(run, "borrow:")
	check(not offer.is_empty(), "The synthetic artifact fixture offers a legal loan")
	if offer.is_empty(): return
	var before := run._outcome_state()
	var artifact := str(offer.artifact.name)
	check(run.choose(str(offer.id)) and run.phase == "map" and run.borrowed_artifact == artifact, "Borrowing an artifact completes the Spring visit")
	var after := run._outcome_state()
	var unchanged := true
	for key: String in ["gold", "life", "maximum", "book", "reserve", "relics", "training", "prepared"]:
		if before[key] != after[key]: unchanged = false
	check(unchanged, "An artifact loan changes no resource tracked by the outcome deltas")
	var receipt := run._last_outcome
	var zero_deltas := receipt.size() == 12 and str(receipt.get("story", "")) == "0:borrow"
	for key: String in ["gold", "life", "maximum", "training"]:
		if int(receipt.get(key, -1)) != 0: zero_deltas = false
	for key: String in ["book_added", "book_removed", "reserve_added", "reserve_removed", "relics_added", "relics_removed"]:
		if not receipt.get(key, ["missing"]).is_empty(): zero_deltas = false
	if bool(receipt.get("prepared", true)): zero_deltas = false
	check(zero_deltas and str(run.outcome_details().get("description", "")).contains(ELExpeditionContent.outcome(source, "0:borrow")), "A zero-delta decision still saves and renders the explicit 0:borrow story")
	var restored := _restore_equal(run, "The zero-resource Spring story and borrowed artifact restore exactly")
	if restored == null: return
	var next := restored.available()
	check(not next.is_empty() and restored.choose_node(next[0]) and restored._last_outcome.is_empty() and restored.outcome_details().is_empty(), "Entering the next room clears the previous zero-resource story")
	check(restored.borrowed_artifact == artifact, "Clearing the story does not discard the borrowed artifact")

func _reject_v12_saves(source: ELProfile) -> void:
	var run := _event(source, 8, 1, V12)
	run.choose("cartographer_help")
	for forged: Variant in [null, 8, [], {}, "8:invented", "999:leave", "8:cartographer_help:extra", ""]:
		var raw := run.snapshot()
		raw.last_outcome.story = forged
		_reject(run, raw, "Forged event story %s is rejected atomically" % str(forged))
	var raw := run.snapshot()
	raw.last_outcome.extra = "not a receipt field"
	_reject(run, raw, "Unexpected outcome keys cannot reach the renderer")
	raw = run.snapshot()
	raw.version = V11
	_reject(run, raw, "A rules 11 checkpoint cannot acquire the rules 12 story field")
	var library := _library_for(source)
	var offer := _option(library, "library_card:")
	library.choose(str(offer.id))
	raw = library.snapshot()
	raw.pending_craft = library.deck[0]
	_reject(library, raw, "Library placement cannot coexist with a recipe")
	raw = library.snapshot()
	raw.pending_reserve = 0
	raw.reserve = [library.deck[0]]
	_reject(library, raw, "Library placement cannot coexist with a reserve swap")
	var camp := _enter(source, "rest", 12345, 1, V12)
	_reserve_pair(camp)
	camp.choose("swap_select:0")
	raw = camp.snapshot()
	raw.pending_reserve = 2
	_reject(camp, raw, "An out-of-range reserve slot is rejected atomically")
	raw = camp.snapshot()
	raw.phase = "map"
	_reject(camp, raw, "Free reserve preparation cannot restore outside camp or Haven")

func _legacy_at(run: Variant, room: Dictionary, chapter: int) -> void:
	run._clear_room_state()
	run.current = room.id
	run.visited.assign([String(room.id)])
	run.phase = String(room.kind)
	run.pending_card = ""
	if room.kind == "boss" and chapter == 3: run.phase = "haven"
	if run.phase in ["shop", "haven"]: run._prepare_shop()

func _legacy_equal(left: Variant, right: Variant, label: String) -> void:
	check(left.snapshot() == right.snapshot() and left.choices() == right.choices() and left.room_summary() == right.room_summary() and left.outcome_details() == right.outcome_details(), label)
	legacy_stages += 1

func _frozen_v11(source: ELProfile) -> void:
	var path := _argument("baseline")
	if path.is_empty():
		print("Frozen v11 comparison omitted: pass --baseline=/path/to/v11/run.gd.")
		return
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path).replace("class_name ELExpeditionRun\n", "")
	check(script.reload() == OK and script.can_instantiate(), "Frozen v11 core loads read only as an anonymous model")
	if not script.can_instantiate(): return
	var seeds := clampi(int(_argument("seeds", "16")), 1, 64)
	for seed_value in seeds:
		for chapter in range(1, 4):
			var left := _new(source, seed_value, V11)
			var right: Variant = script.new()
			check(right.create(source, "ExpeditionFixtureRed", seed_value, V11) and right.choose("relic:amber_seed") and right.choose("study:none"), "Frozen v11 creates its original opening")
			for run: Variant in [left, right]:
				run._reset(source, run.preset, seed_value, chapter)
				run.health = run.max_health
				run.gold = 999
			check(left.route() == right.route(), "Rules 11 preserve frozen routes, event assignments and seeds")
			for room: Dictionary in left._nodes.values():
				_legacy_at(left, room, chapter)
				_legacy_at(right, room, chapter)
				check(left.choices() == right.choices() and left.room_summary() == right.room_summary() and left._offered_cards() == right._offered_cards() and left._relic_offers(3) == right._relic_offers(3) and left._shop_stock == right._shop_stock and left._shop_relic == right._shop_relic, "Rules 11 room %s seed %d matches frozen choices and offers" % [room.id, seed_value])
				legacy_rooms += 1
	for kind: String in ["rest", "haven", "library", "mirror", "forge", "anvil", "cartographer", "reward"]:
		var left: ELExpeditionRun
		match kind:
			"rest": left = _enter(source, "rest", 12345, 1, V11)
			"haven": left = _enter(source, "boss", 12345, 3, V11)
			"library": left = _event(source, ELExpeditionRun.LIBRARY_EVENT, 1, V11)
			"mirror": left = _event(source, 1, 1, V11)
			"forge": left = _event(source, 7, 1, V11)
			"anvil": left = _event(source, ELExpeditionRun.ANVIL_EVENT, 1, V11)
			"cartographer": left = _event(source, 8, 1, V11)
			"reward":
				left = _new(source, 12345, V11)
				left.choose_node(left.available()[0])
				_win_current(left)
		if left == null:
			check(false, "Reach rules 11 " + kind + " comparison checkpoint")
			continue
		left.gold = 200
		if kind in ["rest", "haven"]: _reserve_pair(left)
		var right: Variant = script.new()
		check(right.restore_snapshot(source, _json(left.snapshot())), "Frozen v11 restores current rules 11 " + kind)
		_legacy_equal(left, right, "Rules 11 " + kind + " initial state matches frozen behavior")
		var select := ""
		match kind:
			"rest", "haven": select = "swap_select:0"
			"library": select = str(_option(left, "library_card:").id)
			"mirror", "forge", "anvil": select = str(_option(left, "craft_select:").id)
			"cartographer": select = "cartographer_help"
			"reward": select = str(_option(left, "card:").id)
		check(left.choose(select) and right.choose(select), "Both rules 11 models accept " + kind + " selection")
		_legacy_equal(left, right, "Rules 11 " + kind + " selection matches frozen behavior")
		if kind == "cartographer": continue
		var restored: Variant = script.new()
		check(restored.restore_snapshot(source, _json(left.snapshot())) and restored.snapshot() == right.snapshot() and restored.choices() == right.choices(), "Frozen v11 resumes the exact current pending " + kind)
		var action := ""
		match kind:
			"rest", "haven": action = str(_option(left, "swap_with:").id)
			"library": action = "reserve_add"
			"mirror", "forge", "anvil": action = str(_option(left, "craft:").id)
			"reward": action = "add"
		check(left.choose(action) and right.choose(action), "Both rules 11 models commit " + kind + " once")
		_legacy_equal(left, right, "Rules 11 " + kind + " completion and receipt match the frozen release")
	check(legacy_rooms == seeds * 3 * 22 and legacy_stages == 23, "All frozen v11 rooms and selection/completion stages executed")
