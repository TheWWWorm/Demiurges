extends "expedition_power_ui_check.gd"
## Focused v14 UI checks. Uses synthetic tables and real Expedition choices;
## does not run either inherited suite or touch a player's checkpoint.
## godot --headless --path game --script ../tools/expedition_opening_ui_check.gd

const OPENING_FOLDER := "user://expedition_opening_ui_check"

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	var profile := Fixture.profile_at(OPENING_FOLDER)
	check(profile != null, "Synthetic opening-spell UI profile is available")
	if profile == null:
		_finish()
		return
	_add_power_metadata(profile)
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		ELRemakeText.use(profile)
		var screen := ELExpeditionScreen.new()
		root.add_child(screen)
		screen.build(profile)
		screen.choice_made.connect(func(id: String): captured.append(id))
		await _opening_camp_checks(screen, profile, language)
		await _opening_camp_toggle_checks(screen, profile, language)
		await _opening_haven_checks(screen, profile, language)
		await _opening_shrine_checks(screen, profile, language)
		await _opening_change_checks(screen, profile, language)
		await _opening_route_checks(screen, profile, language)
		await _opening_legacy_checks(screen, profile, language)
		screen.queue_free()
		await _frames()
		languages_completed += 1
	OS.unset_environment("DEMIURGES_LANGUAGE")
	ELRemakeText.release()
	Fixture.clean(OPENING_FOLDER)
	_finish()

func _opening_button(screen: ELExpeditionScreen, option: Dictionary) -> Button:
	if option.is_empty(): return null
	if bool(option.get("opening_toggle", false)):
		return screen._journal.get_node_or_null("OpeningToggle") as Button
	if str(option.id).begins_with("opening_spell:") or str(option.id).get_slice(":", 0) in ["remove", "shop_remove", "purge"]:
		return screen._journal.find_child("Compare_" + str(option.id).replace(":", "_"), true, false) as Button
	return _choice_button(screen, option)

func _opening_confirm(screen: ELExpeditionScreen) -> Button:
	return screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button

func _opening_escape(screen: ELExpeditionScreen) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	screen._unhandled_key_input(event)

func _opening_camp_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1401, 14)
	check(_enter_kind(run, "rest"), language + ": opening-spell practice reaches a real camp")
	if run.phase != "rest": return
	run.reserve.assign([run.deck.back()])
	run.keystones.assign(["power_energy_barrier"])
	screen.show_run(run)
	await _frames()
	var free := screen._journal.get_node_or_null("CampFreePreparation")
	var main := screen._journal.get_node_or_null("CampMainService")
	var swap := _opening_button(screen, _v11_option_prefix(run, "swap_select:"))
	var toggle := screen._journal.get_node_or_null("PowerToggle_power_energy_barrier")
	var service := _opening_button(screen, _option(run, "opening_select"))
	check(free != null and main != null and free.get_index() < main.get_index() and swap != null and swap.get_index() < main.get_index() and toggle != null and toggle.get_index() < main.get_index(), language + ": free swaps and power preparation precede services that end camp")
	check(service != null and service.get_index() > main.get_index(), language + ": rehearsal is clearly a main camp service")
	if service == null: return
	var before := run.snapshot()
	service.grab_focus()
	captured.clear()
	service.pressed.emit()
	check(captured == ["opening_select"] and run.choose("opening_select"), language + ": the camp entry opens its exact selection action")
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": opening spell selector at 720p")
	var unique := {}
	var sorted := true
	var previous_cost := -100
	for option: Dictionary in run.choices():
		if not str(option.id).begins_with("opening_spell:"): continue
		unique[str(option.card)] = true
		var cost := ELEncyclopaedia.cost(profile, str(option.card))
		sorted = sorted and cost >= previous_cost
		previous_cost = cost
		check(_opening_button(screen, option) != null, language + ": each opening candidate is visible")
	var active_unique := {}
	for card: String in run.deck: active_unique[card] = true
	check(unique == active_unique and sorted, language + ": selector lists each active spell once in printed-cost order")
	var selected := _v11_option_prefix(run, "opening_spell:")
	var selecting := run.snapshot()
	_opening_button(screen, selected).pressed.emit()
	await _frames()
	var confirm := _opening_confirm(screen)
	check(confirm != null and not confirm.disabled and confirm.text == screen._text("Prepare opening spell", "Подготовить стартовое заклинание") and run.snapshot() == selecting, language + ": selecting a candidate opens a specific confirmation without spending camp")
	check(_has_text(screen._journal, str(selected.description)) and _has_text(screen._journal, str(selected.context)) and screen._journal.get_node_or_null("OpeningSpellReview") != null, language + ": confirmation shows the spell and exact service cost")
	_check_dialogue(screen, language + ": opening spell confirmation at 720p")
	var back := screen._choice_footer.find_child("ReplacementBack", true, false) as Button
	if back != null: back.pressed.emit()
	await _frames()
	check(screen._replacement.is_empty() and run.snapshot() == selecting and run.opening_selecting, language + ": comparison Back returns to candidates without committing")
	captured.clear()
	_opening_escape(screen)
	check(captured == ["back"] and run.choose("back"), language + ": Escape cancels the selector through the core Back action")
	screen.show_run(run)
	await _frames(10)
	check(run.snapshot() == before and screen._journal.get_node_or_null("CampMainService") != null, language + ": cancellation preserves the original camp and its main action")
	check(root.gui_get_focus_owner() == _opening_button(screen, _option(run, "opening_select")), language + ": cancellation restores focus to the camp rehearsal entry")
	check(run.choose("opening_select"), language + ": cancelled rehearsal remains available")
	screen.show_run(run)
	await _frames()
	selected = _v11_option_prefix(run, "opening_spell:")
	_opening_button(screen, selected).pressed.emit()
	await _frames()
	captured.clear()
	confirm = _opening_confirm(screen)
	if confirm != null: confirm.pressed.emit()
	check(captured == [selected.id] and run.choose(selected.id) and run.phase == "map" and run.opening_spell == selected.card and run.gold == int(before.gold), language + ": confirmation prepares the chosen spell and consumes exactly the camp action")
	screen.show_run(run)
	await _frames()
	var readiness := screen._journal.get_node_or_null("BattleReadiness")
	check(readiness != null and _has_text(readiness, str(run.battle_preview().opening_line)), language + ": route readiness names the prepared opening spell")
	screen._show_deck(true)
	await _frames()
	var active := screen._journal.find_child("ActiveSpell_" + run.opening_spell, true, false) as Control
	var reserve := screen._journal.get_node_or_null("ReservePanel")
	var hero := screen._journal.get_node_or_null("HeroDetails")
	var power := screen._journal.get_node_or_null("PowerDetail_power_energy_barrier")
	_reveal(active)
	check(active != null and _has_text(screen._journal.get_node("ActiveBook"), screen._text("Opening hand", "Стартовая рука")), language + ": the active spell is marked as the opening spell")
	check(reserve != null and hero != null and power != null and active != null and _journal_index(screen, active) < reserve.get_index() and reserve.get_index() < hero.get_index() and reserve.get_index() < power.get_index(), language + ": active book and reserve precede detailed skills and powers")
	var opening := screen._journal.get_node_or_null("OpeningSpellDetails")
	check(opening != null and _has_text(opening, run.opening_details().description), language + ": Deck explains normal opening slots, cost and charges")
	screen._show_deck(false)
	await _frames()

func _opening_haven(profile: ELProfile) -> ELExpeditionRun:
	var run := _new(profile, 1402, 14)
	for chapter in 2:
		if not _enter_kind(run, "boss") or not _win(run) or not _settle_room(run): return null
	if not _enter_kind(run, "boss") or run.phase != "haven": return null
	return run

func _opening_haven_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _opening_haven(profile)
	check(run != null, language + ": rehearsal reaches the final Haven through three acts")
	if run == null: return
	run.opening_spell = run.deck[0]
	run.gold = 0
	screen.show_run(run)
	await _frames()
	var entry := _option(run, "opening_select")
	var service := _opening_button(screen, entry)
	check(service != null and service.disabled and _caption(service).contains(str(entry.cost)) and _has_text(screen._journal, str(entry.get("reason", entry.get("disabled_reason", "")))), language + ": unaffordable Haven rehearsal remains visible with its price and reason")
	captured.clear()
	if service != null: service.pressed.emit()
	check(captured.is_empty() and not run.opening_selecting, language + ": an unaffordable rehearsal cannot open or charge")
	run.gold = 999
	check(run.choose("opening_select"), language + ": affordable Haven rehearsal opens")
	screen.show_run(run)
	await _frames()
	check(not screen._merchant_footer.visible and screen._choice_footer.find_child("Choice_back", true, false) != null, language + ": the selector has a fixed Back without a premature final-battle exit")
	var current := _option(run, "opening_spell:" + run.opening_spell)
	var current_button := _opening_button(screen, current)
	_reveal(current_button)
	check(current_button != null and current_button.disabled and _has_text(screen._journal, str(current.get("reason", current.get("disabled_reason", "")))), language + ": already-prepared spell stays visible and explains why no purchase is needed")
	captured.clear()
	if current_button != null: current_button.pressed.emit()
	check(captured.is_empty() and screen._replacement.is_empty(), language + ": the current opening spell cannot spend gold again")
	var selected := _v11_option_prefix(run, "opening_spell:")
	var before := run.snapshot()
	_opening_button(screen, selected).pressed.emit()
	await _frames()
	var confirm := _opening_confirm(screen)
	check(confirm != null and confirm.text.contains(str(selected.cost)) and run.snapshot() == before and _has_text(screen._journal, screen._text("Gold %d → %d", "Золото: %d → %d") % [run.gold, run.gold - int(selected.cost)]), language + ": Haven comparison shows the actual charge but has not paid it")
	captured.clear()
	_opening_escape(screen)
	await _frames()
	check(screen._replacement.is_empty() and captured.is_empty() and run.snapshot() == before, language + ": Escape first leaves the comparison without cancelling or charging the selector")
	_opening_button(screen, selected).pressed.emit()
	await _frames()
	captured.clear()
	_opening_confirm(screen).pressed.emit()
	check(captured == [selected.id] and run.choose(selected.id) and run.gold == int(before.gold) - int(selected.cost) and run.phase == "haven" and run.opening_spell == selected.card, language + ": Haven charges once on the confirmed spell and stays open")
	screen.show_run(run)
	await _frames()
	check(screen._merchant_footer.visible and _has_text(screen._journal.get_node("BattleReadiness"), str(run.battle_preview().opening_line)), language + ": Haven restores its final-battle action and updated opening readiness")
	await _opening_toggle_checks(screen, run, language)

func _opening_camp_toggle_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1406, 14)
	check(_enter_kind(run, "rest"), language + ": free opening-preparation toggle reaches a camp")
	if run.phase != "rest": return
	# Controlled learned-page state; acquisition is exercised separately above.
	run.opening_spell = run.deck[0]
	await _opening_toggle_checks(screen, run, language)

func _opening_toggle_checks(screen: ELExpeditionScreen, run: ELExpeditionRun, language: String) -> void:
	var haven := run.phase == "haven"
	var place := "Haven" if haven else "camp"
	screen.show_run(run)
	await _frames()
	var option := _option(run, "suppress_opening")
	var toggle := _opening_button(screen, option)
	check(toggle != null and not toggle.disabled and not option.has("cost") and not option.has("card"), language + ": " + place + " offers a free opening toggle without another spell purchase")
	if toggle == null: return
	if not haven:
		check(toggle.get_index() < screen._journal.get_node("CampMainService").get_index(), language + ": opening preparation is grouped before consuming camp services")
	var before := run.snapshot()
	var stock := run._shop_bought.duplicate()
	toggle.grab_focus()
	await _frames()
	screen._scroll.scroll_vertical = maxi(0, screen._scroll.scroll_vertical - 24)
	await _frames()
	var anchor := toggle.get_global_rect().position.y - screen._scroll.get_global_rect().position.y
	captured.clear()
	toggle.pressed.emit()
	check(captured == ["suppress_opening"] and run.choose("suppress_opening"), language + ": " + place + " emits and applies the exact suppression action")
	screen.show_run(run)
	await _frames(10)
	toggle = screen._journal.get_node_or_null("OpeningToggle") as Button
	check(toggle != null and root.gui_get_focus_owner() == toggle and absf(toggle.get_global_rect().position.y - screen._scroll.get_global_rect().position.y - anchor) < 3.0, language + ": " + place + " preserves the toggle's position and keyboard focus")
	var detail := run.opening_details()
	check(run.opening_suppressed and not bool(detail.prepared) and not bool(detail.active) and run.opening_spell == str(before.opening_spell), language + ": setting aside preparation keeps the learned spell but removes its opening guarantee")
	check(run.phase == str(before.phase) and run.gold == int(before.gold) and run.health == int(before.health) and run.deck == before.deck and run.reserve == before.reserve and run._shop_bought == stock, language + ": " + place + " suppression preserves life, gold, book, reserve, stock and visit")
	if haven:
		check(_has_text(screen._journal.get_node("BattleReadiness"), str(run.battle_preview().opening_line)) and screen._merchant_footer.visible, language + ": Haven readiness reports suppression and keeps the final-duel action")
	screen._show_deck(true)
	await _frames()
	var opening := screen._journal.get_node_or_null("OpeningSpellDetails")
	var active := screen._journal.find_child("ActiveSpell_" + run.opening_spell, true, false) as Control
	_reveal(active)
	check(opening != null and active != null and _has_text(opening, str(detail.status)) and _has_text(opening, str(detail.reason)) and _has_text(screen._journal.get_node("ActiveBook"), str(detail.status)), language + ": Deck and its active page show the exact set-aside status and reason")
	screen._show_deck(false)
	await _frames(10)
	check(root.gui_get_focus_owner() == screen._journal.get_node_or_null("OpeningToggle"), language + ": returning from Deck keeps focus on free preparation")
	var resumed := ELExpeditionRun.new()
	check(resumed.restore_snapshot(run.profile, run.snapshot()) and resumed.snapshot() == run.snapshot(), language + ": " + place + " restores the exact suppressed preparation checkpoint")
	if resumed.phase != run.phase: return
	run = resumed
	screen.show_run(run)
	await _frames()
	check(run.choose("opening_select"), language + ": the resumed lesson can still inspect a different spell")
	screen.show_run(run)
	await _frames()
	var current := _option(run, "opening_spell:" + run.opening_spell)
	var current_button := _opening_button(screen, current)
	_reveal(current_button)
	check(current_button != null and current_button.disabled and _has_text(screen._journal, str(current.reason)), language + ": relearning a suppressed spell is disabled with its free-preparation explanation")
	check(run.choose("back"), language + ": cancelling another lesson preserves the suppressed choice")
	screen.show_run(run)
	await _frames()
	toggle = screen._journal.get_node_or_null("OpeningToggle") as Button
	captured.clear()
	if toggle != null: toggle.pressed.emit()
	check(captured == ["prepare_opening"] and run.choose("prepare_opening") and not run.opening_suppressed and bool(run.opening_details().active), language + ": " + place + " prepares the learned spell again without buying another lesson")
	screen.show_run(run)
	await _frames()
	check(run.phase == str(before.phase) and run.gold == int(before.gold) and run.health == int(before.health) and run.deck == before.deck and run.reserve == before.reserve and run._shop_bought == stock and (haven or not _option(run, "forage").is_empty()), language + ": free preparation leaves all resources and the main service available")

func _opening_event(profile: ELProfile) -> ELExpeditionRun:
	for seed in 128:
		var run := _new(profile, 1410 + seed, 14)
		if not _path_to_kind(run, "event", 17).is_empty() and _enter_kind(run, "event", 17): return run
	return null

func _opening_shrine_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _opening_event(profile)
	check(run != null, language + ": the scholar encounter is reachable on a real route")
	if run == null: return
	screen.show_run(run)
	await _frames()
	var service := _opening_button(screen, _option(run, "opening_select"))
	check(service != null and not service.disabled and not _option(run, "opening_select").has("cost"), language + ": the scholar's lesson is offered without a gold fee")
	var gold := run.gold
	check(run.choose("opening_select"), language + ": the scholar opens the same safe selector")
	screen.show_run(run)
	await _frames()
	var selected := _v11_option_prefix(run, "opening_spell:")
	_opening_button(screen, selected).pressed.emit()
	await _frames()
	check(_has_text(screen._journal, str(selected.context)) and str(selected.context).contains("12"), language + ": confirmation states the forgone 12-gold alternative")
	captured.clear()
	_opening_confirm(screen).pressed.emit()
	check(captured == [selected.id] and run.choose(selected.id) and run.phase == "map" and run.gold == gold and run.opening_spell == selected.card, language + ": the free lesson prepares its spell instead of collecting the alternative gold")

func _opening_change_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1403, 14)
	check(_enter_kind(run, "rest"), language + ": opening-book changes reach a camp")
	if run.phase != "rest": return
	var card := run.deck[0]
	while run.deck.count(card) > 1: run.deck.erase(card)
	run.opening_spell = card
	var spare: String = run.deck.back()
	if spare == card: spare = run.deck[1]
	run.reserve.assign([spare])
	check(run.choose("swap_select:0"), language + ": reserve swap can select a real stored spell")
	screen.show_run(run)
	await _frames()
	var swap := _option(run, "swap_with:%d" % run.deck.find(card))
	var preview := screen._change_preview(swap)
	var after := run.opening_details_for(preview.active, preview.reserve)
	_opening_button(screen, swap).pressed.emit()
	await _frames()
	check(not bool(after.active) and bool(after.owned) and _has_text(screen._journal.get_node("BookChangePreview"), str(after.reason)), language + ": swapping out the last active copy warns that preparation moves to reserve")
	check(run.choose(swap.id) and run.opening_spell == card and not bool(run.opening_details().active) and run.phase == "rest", language + ": reserve storage retains the selection without pretending it is battle-ready")
	screen.show_run(run)
	screen._show_deck(true)
	await _frames()
	check(_has_text(screen._journal.get_node("OpeningSpellDetails"), str(run.opening_details().reason)) and _has_text(screen._journal.get_node("ReservePanel"), str(run.opening_details().status)), language + ": Deck identifies the reserved opening spell and how to restore it")
	screen._show_deck(false)
	await _frames()
	check(run.choose("swap_select:%d" % run.reserve.find(card)), language + ": the retained spell can be selected from reserve again")
	screen.show_run(run)
	await _frames()
	swap = _v11_option_prefix(run, "swap_with:")
	preview = screen._change_preview(swap)
	_opening_button(screen, swap).pressed.emit()
	await _frames()
	check(_has_text(screen._journal.get_node("BookChangePreview"), screen._text("%s returns to your opening hand.", "%s снова будет в стартовой руке.") % ELEncyclopaedia.name(profile, card)), language + ": returning the page previews restoration of its opening guarantee")
	check(run.choose(swap.id) and bool(run.opening_details().active), language + ": returning the retained spell restores readiness for free")
	screen.show_run(run)
	await _frames()
	screen._show_camp_removals(true)
	await _frames()
	var removal := _option(run, "remove:%d" % run.deck.find(card))
	preview = screen._change_preview(removal)
	after = run.opening_details_for(preview.active, preview.reserve)
	var remove_button := _opening_button(screen, removal)
	check(remove_button != null, language + ": the prepared spell has a real selectable removal comparison")
	if remove_button == null: return
	remove_button.pressed.emit()
	await _frames()
	check(not bool(after.owned) and _has_text(screen._journal.get_node("BookChangePreview"), str(after.reason)), language + ": removing the final owned copy previews the permanent loss of preparation")
	check(run.choose(removal.id) and run.opening_spell.is_empty(), language + ": final-copy removal clears the preparation exactly as warned")

func _opening_route_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1404, 14)
	check(_settle_room(run), language + ": v14 route navigation fixture starts")
	run.keystones.assign(["power_transfer_aspects", "power_energy_barrier"])
	run.opening_spell = run.deck[0]
	screen.show_run(run)
	await _frames()
	var rooms := screen._journal.get_node_or_null("ReachableRooms")
	var readiness := screen._journal.get_node_or_null("BattleReadiness")
	check(rooms != null and readiness != null and rooms.get_index() < readiness.get_index(), language + ": reachable rooms precede long power and opening readiness")
	var id := str(run.available()[0])
	var inspect := screen._journal.find_child("RouteInspect_" + id, true, false) as Button
	check(inspect != null and inspect.get_parent() != screen._journal, language + ": route inspection uses the real nested action")
	if inspect == null: return
	inspect.grab_focus()
	await _frames()
	screen._scroll.scroll_vertical = mini(60, int(screen._scroll.get_v_scroll_bar().max_value - screen._scroll.get_v_scroll_bar().page))
	await _frames()
	var old_scroll := screen._scroll.scroll_vertical
	var before := run.snapshot()
	inspect.pressed.emit()
	await _frames()
	var back := screen._journal.get_node("RoomDetailBack") as Button
	back.pressed.emit()
	await _frames(10)
	inspect = screen._journal.find_child("RouteInspect_" + id, true, false) as Button
	check(old_scroll > 0 and screen._scroll.scroll_vertical == old_scroll and root.gui_get_focus_owner() == inspect and run.snapshot() == before, language + ": leaving room inspection restores nonzero route scroll and its nested Inspect button")

func _opening_legacy_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1405, 13)
	check(_enter_kind(run, "rest"), language + ": v13 compatibility fixture reaches camp")
	screen.show_run(run)
	await _frames()
	check(_option(run, "opening_select").is_empty() and screen._journal.get_node_or_null("CampMainService") == null, language + ": v13 keeps its previous services and ordering")
	screen._show_deck(true)
	await _frames()
	var hero := screen._journal.get_node("HeroDetails")
	var reserve := screen._journal.get_node("ReservePanel")
	var book := screen._journal.get_node("ActiveBookHeading")
	check(hero.get_index() < book.get_index() and reserve.get_index() < book.get_index() and screen._journal.get_node_or_null("OpeningSpellDetails") == null, language + ": v13 keeps its previous Deck ordering without opening controls")

func _finish() -> void:
	check(languages_completed == 2, "Both opening-spell UI language passes reached completion")
	print("EXPEDITION OPENING UI: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
