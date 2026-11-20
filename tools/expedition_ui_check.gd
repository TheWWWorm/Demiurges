extends SceneTree
## Expedition presentation checks against real run choices and synthetic
## game tables. No original assets and no real checkpoint are read or written.
## godot --headless --path game --script ../tools/expedition_ui_check.gd
## Optional rendered capture: -- --screenshots=/absolute/output/folder

const Fixture := preload("expedition_fixture.gd")
const FOLDER := "user://expedition_ui_check"
var checks := 0
var failures: Array[String] = []
var captured: Array[String] = []
var languages_completed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _frames(count := 6) -> void:
	for index in count: await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	var profile := Fixture.profile_at(FOLDER)
	check(profile != null, "Synthetic Expedition profile is available")
	if profile == null:
		_finish()
		return
	_board_empty_cell_checks(profile)
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		ELRemakeText.use(profile)
		var screen := ELExpeditionScreen.new()
		root.add_child(screen)
		screen.build(profile)
		screen.choice_made.connect(func(id: String): captured.append(id))
		await _start_options(screen, language)
		var run := _new(profile)
		if run == null: break
		screen.show_run(run)
		await _frames()
		check(run.phase == "boon" and screen._choice_pending() and screen._dialogue.visible, language + ": starting boon has a modal choice panel")
		_check_dialogue(screen, language + ": boon")
		await _capture("expedition-boon-" + language)
		var boon := _first_enabled(run)
		var boon_button := _choice_button(screen, boon)
		check(boon_button != null, language + ": starting boon is a visible text action")
		if boon_button != null:
			captured.clear()
			boon_button.pressed.emit()
			check(captured == [boon.id], language + ": boon action emits its exact choice once")
		check(run.choose(boon.id), language + ": starting boon can be taken")
		screen.show_run(run)
		await _frames()
		check(screen._route.size() == 8 and not screen._dialogue.visible, language + ": all eight route floors are visible after the boon")
		_check_map(screen, language + ": map at 720p")
		await _capture("expedition-map-" + language)
		run._prepared = true
		run._contract_remaining = 2
		screen.show_run(run)
		await _frames()
		for effect: String in run.journey_effects():
			check(_has_text(screen._journal, effect), language + ": active journey effect is visible on the route")
		screen._show_deck(true)
		await _frames()
		for relic: Dictionary in run.relic_details():
			check(_has_text(screen._journal, relic.title) and _has_text(screen._journal, relic.description), language + ": collected relic has a readable name and effect")
		for effect: String in run.journey_effects():
			check(_has_text(screen._journal, effect), language + ": active journey effect is visible in Deck")
		screen._show_deck(false)
		await _frames()
		var shop := _new(profile)
		check(_enter_kind(shop, "shop"), language + ": a real merchant room is reachable")
		if shop.phase == "shop": await _shop_checks(screen, shop, language)
		for kind: String in ["treasure", "elite", "event"]:
			var room := _new(profile)
			check(_enter_kind(room, kind), language + ": " + kind + " room is reachable")
			if kind == "elite": _win(room)
			screen.show_run(room)
			await _frames()
			check(screen._dialogue.visible and screen._board == null, language + ": " + kind + " choices use the readable journal")
			_check_dialogue(screen, language + ": " + kind)
			check(not screen._journal.get_children().is_empty(), language + ": " + kind + " panel is populated")
		await _v9_checks(screen, profile, language)
		await _v10_checks(screen, profile, language)
		await _v11_checks(screen, profile, language)
		await _v12_checks(screen, profile, language)
		var legacy := ELExpeditionRun.new()
		check(legacy.create(profile, "ExpeditionFixtureRed", 81, 7), language + ": legacy run creates")
		screen.show_run(legacy)
		await _frames()
		check(screen._route.size() == 6 and not screen._choice_pending(), language + ": legacy route retains its six-floor map")
		screen.queue_free()
		await _frames()
		languages_completed += 1
	OS.unset_environment("DEMIURGES_LANGUAGE")
	ELRemakeText.release()
	Fixture.clean(FOLDER)
	_finish()

func _board_empty_cell_checks(profile: ELProfile) -> void:
	var board := ELExpeditionBoard.new()
	board.profile = profile
	board.phase = "rest"
	board.room_title = "Empty stock camp"
	board.room_text = "Rest or remove a spell."
	for area: String in ["shop", "bag", "deal"]:
		board._hover = [area, -1]
		check(str(board._subject().get("name", "")) == board.room_title, "Native board: an empty " + area + " cell safely keeps the room description")
	board.offers.append({"id": "offer", "name": "Last offer", "text": "Offer description"})
	board._hover = ["shop", -1]
	check(str(board._subject().get("name", "")) == board.room_title, "Native board: empty stock space does not preview the last offer")
	board.picked = 0
	check(str(board._subject().get("name", "")) == "Last offer", "Native board: an empty cell preserves an intentionally selected offer")
	board.free()

func _start_options(screen: ELExpeditionScreen, language: String) -> void:
	screen.show_run(null)
	await _frames()
	var difficulty := screen._journal.get_node_or_null("ExpeditionDifficulty") as OptionButton
	var starter := screen._journal.get_node_or_null("ExpeditionStarter") as OptionButton
	var seed := screen._journal.get_node_or_null("ExpeditionSeed") as LineEdit
	var start := screen._journal.get_node_or_null("BeginExpedition") as Button
	check(difficulty != null and str(difficulty.get_selected_metadata()) == "standard", language + ": Standard is the default difficulty")
	if difficulty == null or starter == null or seed == null or start == null: return
	difficulty.select(1)
	difficulty.item_selected.emit(1)
	seed.text = "31415"
	await _frames()
	check(_has_text(screen._journal.get_node("ExpeditionDifficultyDescription"), "15%"), language + ": Veteran explains its combat and reward changes")
	# Exercise cancellation without creating or replacing the real checkpoint.
	var prompt := screen._journal.get_node("ReplaceCheckpoint") as Control
	prompt.show()
	start.hide()
	starter.disabled = true
	difficulty.disabled = true
	seed.editable = false
	screen._journal.get_node("ReplaceCheckpoint/CancelReplacement").pressed.emit()
	check(not difficulty.disabled and str(difficulty.get_selected_metadata()) == "veteran" and seed.text == "31415", language + ": cancelling replacement preserves difficulty and seed")
	var starts: Array = []
	var collect := func(preset: String, run_seed: int, challenge: String): starts.append([preset, run_seed, challenge])
	screen.started.connect(collect)
	start.pressed.emit()
	if prompt.visible: screen._journal.get_node("ReplaceCheckpoint/ConfirmReplacement").pressed.emit()
	check(starts.size() == 1 and starts[0][1] == 31415 and starts[0][2] == "veteran", language + ": start emits the chosen difficulty with its exact seed")
	screen.started.disconnect(collect)

func _v9_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var veteran := _new(profile, 9020, 9, "veteran")
	veteran.choose(_first_enabled(veteran).id)
	veteran.relics.append_array(["aether_prism", "duelists_crest"])
	veteran._prepared = true
	screen.show_run(veteran)
	await _frames()
	check(screen._subtitle.text.contains(screen._difficulty_name("veteran")), language + ": the running expedition identifies Veteran difficulty")
	var level_line := screen._text("Next duel · Hero level %d", "Следующий бой · Уровень героя %d") % int(veteran.battle_preview().level)
	check(_has_text(screen._journal, level_line), language + ": route readiness shows actual relic and provision level")
	screen._show_deck(true)
	await _frames()
	check(_has_text(screen._journal, veteran.relic_status("duelists_crest")), language + ": Deck explains the inactive Crest requirement")
	for bonus: String in veteran.battle_preview().bonus_lines:
		check(_has_text(screen._journal, bonus), language + ": Deck explains each active combat-level bonus")
	veteran.deck.resize(12)
	screen.show_run(veteran)
	screen._show_deck(true)
	await _frames()
	check(_has_text(screen._journal, veteran.relic_status("duelists_crest")), language + ": the Crest status updates after the deck reaches its condition")
	screen._show_deck(false)
	screen._show_scout(ELExpeditionRun.ACTS)
	await _frames()
	var final_guardian := veteran.guardian_at(ELExpeditionRun.ACTS)
	var enemy_line := screen._text("%d life · Level %d", "%d здоровья · Уровень %d") % [final_guardian.health, final_guardian.level]
	check(_has_text(screen._journal, enemy_line), language + ": future guardian scouting uses the actual Veteran opponent")
	var reward := _new(profile)
	check(_enter_kind(reward, "fight") and _win(reward), language + ": a real battle reaches the new reward screen")
	reward.gold = 100
	screen.show_run(reward)
	await _frames()
	check(screen._board == null and screen._journal.get_node_or_null("RewardReceipt") != null, language + ": reward receipt is visible separately from spell inspection")
	check(_has_text(screen._journal, reward.room_summary().receipt), language + ": receipt shows the actual settled gold and recovery")
	var redraw := _option(reward, "reroll_reward")
	var redraw_button := _choice_button(screen, redraw)
	check(redraw_button != null and not redraw_button.disabled, language + ": redraw is an explicit priced action")
	if redraw_button != null:
		captured.clear()
		redraw_button.pressed.emit()
		check(captured == ["reroll_reward"], language + ": redraw sends the intended action")
		check(reward.choose("reroll_reward"), language + ": actual reward redraw succeeds")
		screen.show_run(reward)
		await _frames()
		redraw_button = _choice_button(screen, _option(reward, "reroll_reward"))
		check(redraw_button != null and redraw_button.disabled and screen._board == null, language + ": spent redraw remains visible and keeps the same reward layout")
	await _haven_checks(screen, profile, language)
	await _broker_checks(screen, profile, language)
	var legacy := _new(profile, 81, 8)
	check(_enter_kind(legacy, "shop"), language + ": v8 merchant is still reachable")
	legacy.relics.append("purifier_stone")
	legacy.gold = 0
	screen.show_run(legacy)
	await _frames()
	var old_service := screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	check(old_service != null and not old_service.disabled and old_service.text.contains("0"), language + ": v8 retains free Purifier removal")
	check(screen._journal.get_node_or_null("BattleReadiness") == null, language + ": v8 retains its prior presentation")

func _haven_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile)
	run.choose(_first_enabled(run).id)
	run._reset(profile, run.preset, run.seed_value, ELExpeditionRun.ACTS)
	run.health = run.max_health
	check(_enter_kind(run, "boss") and run.phase == "haven", language + ": the final route room opens preparations")
	if run.phase != "haven": return
	run.gold = 999
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": final preparations")
	check(screen._merchant_footer.visible and screen._merchant_leave.text == screen._text("Face White Lord", "Бросить вызов Белому Лорду"), language + ": final preparations have an explicit final-battle action")
	var inspect := screen._journal.get_node_or_null("InspectWarden") as Button
	check(inspect != null, language + ": the final guardian can be inspected before spending")
	if inspect != null:
		inspect.pressed.emit()
		await _frames()
		screen._journal.get_node("RoomDetailBack").pressed.emit()
		await _frames()
		check(screen._merchant_footer.visible and run.phase == "haven", language + ": inspecting returns to preparations without starting combat")
	var prepare := _option(run, "shop_prepare")
	check(not prepare.is_empty() and not bool(prepare.get("disabled", false)) and run.choose("shop_prepare"), language + ": the final merchant sells one-duel provisions")
	screen.show_run(run)
	await _frames()
	var prepare_button := _choice_button(screen, _option(run, "shop_prepare"))
	check(prepare_button != null and prepare_button.disabled, language + ": bought provisions visibly cannot stack")
	var expected := screen._text("Next duel · Hero level %d", "Следующий бой · Уровень героя %d") % int(run.battle_preview().level)
	check(_has_text(screen._journal, expected), language + ": final-battle readiness immediately includes bought provisions")
	var service := screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	if service != null and not service.disabled:
		service.pressed.emit()
		await _frames()
		check(screen._merchant_back.visible and screen._merchant_leave.visible, language + ": final-battle footer stays available while refining the deck")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(screen._merchant_leave.get_global_rect()), language + ": long final-battle text fits its fixed footer")
		screen._merchant_back.pressed.emit()
		await _frames()
	captured.clear()
	screen._merchant_leave.pressed.emit()
	check(captured == ["enter_guardian"], language + ": the haven footer sends the final-battle action rather than leaving a shop")
	check(run.choose("enter_guardian") and run.phase == "battle", language + ": the footer's action starts the actual guardian encounter")

func _broker_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run: ELExpeditionRun
	for seed in 64:
		var candidate := _new(profile, seed)
		if not _path_to_kind(candidate, "event", 12).is_empty():
			run = candidate
			break
	check(run != null and _enter_kind(run, "event", 12), language + ": a real Relic Broker event is reachable")
	if run == null or run.phase != "event": return
	run.gold = 999
	var selected := {}
	for option: Dictionary in run.choices():
		if str(option.id).begins_with("broker_select:") and not bool(option.get("disabled", false)):
			selected = option
			break
	check(not selected.is_empty() and run.choose(selected.id), language + ": the broker can prepare a relic exchange")
	if selected.is_empty(): return
	var old_gold := run.gold
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": relic exchange")
	var incoming := ELExpeditionContent.relic(profile, run.pending_relic, true)
	check(screen._journal.get_node_or_null("IncomingRelic") != null and _has_text(screen._journal, incoming.description), language + ": pending broker exchange shows the incoming effect before commitment")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	captured.clear()
	screen._unhandled_key_input(escape)
	check(captured == ["back"], language + ": Escape cancels a pending relic exchange")
	check(run.choose("back") and run.pending_relic.is_empty() and run.gold == old_gold, language + ": broker cancellation keeps gold and clears the pending relic")

func _option(run: ELExpeditionRun, id: String) -> Dictionary:
	for option: Dictionary in run.choices():
		if option.id == id: return option
	return {}

func _v10_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1020, 10)
	run.choose(_first_enabled(run).id)
	screen.show_run(run)
	await _frames()
	await _capture("expedition-v10-study-" + language)
	check(run.phase == "discipline" and screen._dialogue.visible, language + ": v10 opens the spell-study choice after the starting relic")
	_check_dialogue(screen, language + ": study path")
	for option: Dictionary in run.choices():
		var button := _choice_button(screen, option)
		check(button != null and _has_text(screen._journal, str(option.description)), language + ": study option explains its effect before choosing")
	var study := _first_enabled(run)
	check(run.choose(study.id) and run.phase == "map", language + ": choosing a study reaches the route")
	screen.show_run(run)
	await _frames()
	await _capture("expedition-v10-map-" + language)
	check(screen._journal.get_node_or_null("StudyIdentity") != null and _has_text(screen._journal, run.study_details().title), language + ": the selected study is visible on the route")
	_check_map(screen, language + ": v10 route")
	var key := screen._journal.get_node_or_null("MapKey") as Button
	var entries := screen._journal.get_node_or_null("MapKeyEntries") as Control
	check(key != null and entries != null and not entries.visible, language + ": the repeated map legend starts collapsed")
	if key != null:
		key.pressed.emit()
		check(entries.visible, language + ": the map legend can be expanded")
		key.pressed.emit()
		check(not entries.visible, language + ": the map legend can be collapsed without changing the run")
	for id: String in run.available():
		var foe := run.opponent_at(id)
		if not foe.is_empty():
			check(_has_text(screen._journal, str(foe.title)), language + ": reachable combat identity is available without opening Scout")
			check(screen._journal.find_child("RouteInspect_" + id, true, false) != null, language + ": reachable combat has a direct inspection action")
	check(_enter_kind(run, "fight"), language + ": v10 reaches a normal battle")
	run.health = maxi(1, run.max_health - 5)
	check(_win(run), language + ": v10 victory reaches spell rewards")
	screen.show_run(run)
	await _frames()
	await _capture("expedition-v10-reward-" + language)
	check(screen._choice_footer.visible, language + ": reward utility actions have a fixed footer")
	for id: String in ["recover_reward", "reroll_reward", "skip"]:
		var offer := _option(run, id)
		if offer.is_empty(): continue
		var button := _choice_button(screen, offer)
		check(button != null and screen._choice_footer.is_ancestor_of(button), language + ": " + id + " stays outside the spell list")
	screen._scroll.scroll_vertical = 10000
	await _frames()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(screen._choice_footer.get_global_rect()), language + ": reward utilities stay visible while scrolling")
	var incoming := {}
	for option: Dictionary in run.choices():
		if str(option.id).begins_with("card:"):
			incoming = option
			break
	check(not incoming.is_empty() and _has_text(screen._journal, screen._text("%d in spellbook", "В книге: %d") % run.deck.count(incoming.card)), language + ": reward cards show the current copy count")
	if not incoming.is_empty():
		run.choose(incoming.id)
		screen.show_run(run)
		await _frames()
		var back := _choice_button(screen, _option(run, "back"))
		check(back != null and screen._choice_footer.is_ancestor_of(back), language + ": pending spell cancellation is fixed outside the replacement list")
		var replacement := {}
		for option: Dictionary in run.choices():
			if str(option.id).begins_with("replace:"):
				replacement = option
				break
		var compare := _choice_button(screen, replacement)
		if compare != null:
			compare.pressed.emit()
			await _frames()
			await _capture("expedition-v10-replacement-" + language)
			var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
			var comparison_back := screen._choice_footer.find_child("ReplacementBack", true, false) as Button
			check(confirm != null and comparison_back != null, language + ": replacement confirmation and Back remain visible")
			if comparison_back != null: comparison_back.pressed.emit()
			await _frames()
			check(screen._replacement.is_empty() and not run.pending_card.is_empty(), language + ": comparison Back preserves the selected reward")
		check(run.choose("back"), language + ": pending reward can still be cancelled")
	run.keystones.append("prismatic_quill")
	run.gold = 0
	screen.show_run(run)
	await _frames()
	var redraw := _choice_button(screen, _option(run, "reroll_reward"))
	check(redraw != null and not redraw.disabled and redraw.text.contains("0"), language + ": Prismatic Quill visibly makes the fixed redraw free")
	run.keystones.append("blood_crown")
	screen.show_run(run)
	await _frames()
	check(_option(run, "recover_reward").is_empty() and screen._choice_footer.find_child("Choice_recover_reward", true, false) == null, language + ": Blood Crown removes spell-reward recovery without leaving a stale button")
	await _elite_gate_checks(screen, profile, language)
	await _keystone_route_checks(screen, profile, language)

func _elite_gate_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var early := _new(profile, 1021, 10)
	check(_enter_kind(early, "elite") and early.phase == "elite_gate", language + ": an Act I elite opens its challenge gate")
	if early.phase != "elite_gate": return
	screen.show_run(early)
	await _frames()
	await _capture("expedition-v10-elite-gate-act1-" + language)
	var locked := _option(early, "elite:fortified")
	var locked_button := _choice_button(screen, locked)
	var locked_reason := str(locked.get("disabled_reason", locked.get("reason", "")))
	check(locked_button != null and locked_button.disabled, language + ": Fortified is visibly locked in Act I")
	check(not locked_reason.is_empty() and _has_text(screen._journal, locked_reason), language + ": the locked challenge explains when it unlocks")
	check(screen._journal.get_node_or_null("InspectElite_fortified") == null, language + ": a locked challenge does not open an empty inspection")
	if locked_button != null:
		captured.clear()
		locked_button.pressed.emit()
		check(captured.is_empty(), language + ": a locked challenge cannot be accepted")
	var run := _new(profile, 1021, 10)
	check(_enter_kind(run, "boss") and _win(run) and _settle_room(run) and run.act == 2, language + ": the first guardian leads to Act II before testing all challenge profiles")
	check(_enter_kind(run, "elite") and run.phase == "elite_gate", language + ": an Act II elite opens all challenge profiles")
	if run.phase != "elite_gate": return
	var before := run.snapshot()
	for option: Dictionary in run.choices():
		var description := str(option.get("description", ""))
		check(not description.is_empty() and not description.contains("%d") and not description.contains("%%"), language + ": elite risk and reward copy is fully formatted")
	for variant: String in ["standard", "overcharged", "fortified"]:
		screen.show_run(run)
		await _frames()
		if variant == "standard": await _capture("expedition-v10-elite-gate-" + language)
		var inspect := screen._journal.get_node_or_null("InspectElite_" + variant) as Button
		check(inspect != null, language + ": " + variant + " can be inspected before committing")
		if inspect == null: continue
		inspect.pressed.emit()
		await _frames()
		var expected := run.elite_preview(run.current, variant)
		var line := screen._text("%d life · Level %d", "%d здоровья · Уровень %d") % [expected.health, expected.level]
		check(_has_text(screen._journal, line), language + ": " + variant + " preview shows the exact opponent stats")
		check(run.snapshot() == before, language + ": inspecting " + variant + " does not commit the challenge")
		screen._journal.get_node("RoomDetailBack").pressed.emit()
		await _frames()
		check(screen._scout_variant.is_empty() and run.phase == "elite_gate", language + ": challenge inspection returns to the gate")
	var chosen := run.elite_preview(run.current, "overcharged")
	check(run.choose("elite:overcharged"), language + ": the inspected overcharged challenge can be accepted")
	var duel := run.build_battle()
	check(duel != null and duel.heroes[1].health == chosen.health and duel.heroes[1].level == chosen.level, language + ": accepted elite stats match the inspection")

func _keystone_route_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1022, 10)
	check(_enter_kind(run, "boss") and _win(run) and run.phase == "keystone_reward", language + ": the first guardian opens its distinct keystone reward")
	if run.phase != "keystone_reward": return
	screen.show_run(run)
	await _frames()
	await _capture("expedition-v10-keystone-" + language)
	_check_dialogue(screen, language + ": guardian legacy")
	var choice := _first_enabled(run)
	check(_choice_button(screen, choice) != null and _has_text(screen._journal, str(choice.description)), language + ": guardian rewards expose their full effect before commitment")
	check(run.choose(choice.id) and run.phase == "reward", language + ": a guardian legacy leads into the spell reward")
	screen.show_run(run)
	screen._show_deck(true)
	await _frames()
	for item: Dictionary in run.keystone_details():
		check(_has_text(screen._journal, item.title) and _has_text(screen._journal, item.description), language + ": claimed guardian legacy is explained in Deck")
	run.choose("skip")
	if not run.keystones.has("wayfarer_compass"): run.keystones.append("wayfarer_compass")
	check(run.choose_node(run.available()[0]) and _settle_room(run), language + ": Compass route reaches a real next-floor fork")
	var detour := ""
	for id: String in run.available():
		if run.is_detour(id):
			detour = id
			break
	check(not detour.is_empty(), language + ": Compass exposes a disconnected next-floor choice")
	if detour.is_empty(): return
	screen.show_run(run)
	await _frames()
	await _capture("expedition-v10-compass-" + language)
	var node: Button = screen._nodes[detour]
	check(node.text.begins_with("↗") and node.tooltip_text.contains(screen._detour_hint()), language + ": Compass detour is marked on the map with its cost")
	check(screen._journal.find_child("RouteEnter_" + detour, true, false) != null, language + ": Compass detour is included in reachable route choices")
	check(run.choose_node(detour) and _settle_room(run), language + ": selecting the marked detour uses the real route action")
	screen.show_run(run)
	await _frames()
	for effect: String in run.journey_effects():
		check(_has_text(screen._journal, effect), language + ": route effects include the settled Compass state")

func _v11_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1101, 11)
	while run.phase in ["boon", "discipline"]: run.choose(_first_enabled(run).id)
	run.deck.assign(["STRT", "STRT", "KBWR", "KBSH", "ORWR", "ZAPP", "FRWA", "FRST"])
	run.reserve.assign(["ZAPP", "KBSH"])
	screen.show_run(run)
	await _frames()
	var before := run.snapshot()
	var metrics := screen._book_metrics(run.deck)
	check(metrics.pages == 8 and metrics.creatures == 5 and metrics.sorceries == 3 and metrics.enchantments == 0, language + ": book guidance counts active copies by printed class")
	check(metrics.cheap_creatures == 3 and metrics.curve == [3, 2, 2, 1] and is_equal_approx(float(metrics.average), 2.625), language + ": base-cost curve and low-cost creature count match the fixture pages")
	check(metrics.charges == 16 and metrics.copies.STRT == 2 and run.snapshot() == before, language + ": reserve pages add no charges and inspecting composition is read-only")
	check(screen._owned_context("ZAPP").contains("2 / 4") and not screen._study_context("STRT").is_empty(), language + ": card context distinguishes ownership and study membership")
	run._training.PRVD = 1
	check(screen._book_metrics(run.deck).charges == 32, language + ": displayed capacity follows the actual trained Providence charges")
	run._training.clear()
	var old_tooltip: Variant = profile.tables.CombatSpells.STRT.get("ToolTip")
	profile.tables.CombatSpells.STRT.ToolTip = "Fixture spell description for keyboard inspection."
	screen._show_deck(true)
	await _frames()
	check(screen._journal.get_node_or_null("BookSummary") != null and screen._journal.find_child("BookCostCurve", true, false) != null, language + ": Deck includes factual cost and composition guidance")
	check(screen._journal.get_node_or_null("ReservePanel") != null and _has_text(screen._journal, screen._text("Reserve · %d / 2 pages", "Резерв · Страниц: %d / 2") % 2), language + ": reserved pages have a separate visible panel")
	var inspect := screen._journal.find_child("ActiveSpell_STRT", true, false) as Button
	check(inspect != null and inspect.focus_mode != Control.FOCUS_NONE, language + ": spell descriptions can be opened without hover")
	if inspect != null:
		inspect.focus_entered.emit()
		check(_has_text(screen._journal.get_node("ActiveBook"), "Fixture spell description for keyboard inspection."), language + ": the explicit spell description expands")
	await _capture("expedition-v11-book-" + language)
	screen._show_deck(false)
	await _frames()
	if old_tooltip == null: profile.tables.CombatSpells.STRT.erase("ToolTip")
	else: profile.tables.CombatSpells.STRT.ToolTip = old_tooltip
	_check_map(screen, language + ": v11 route and reserve readout")
	await _v11_reward_checks(screen, profile, language)
	await _v11_reserve_checks(screen, profile, language)
	await _v11_crafting_checks(screen, profile, language)
	await _v11_library_checks(screen, profile, language)

func _v11_reward_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1102, 11)
	check(_enter_kind(run, "fight") and _win(run), language + ": v11 reaches an actual spell reward")
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": v11 reward guidance")
	var incoming := _v11_option_prefix(run, "card:")
	var button := _choice_button(screen, incoming)
	check(button != null and screen._journal.get_node_or_null("BookSummary") != null, language + ": reward offers appear with the active-book summary")
	if button == null: return
	check(screen._scroll.get_global_rect().intersects(button.get_global_rect()), language + ": the first reward action is visible without scrolling past guidance")
	button.grab_focus()
	await _frames()
	screen._scroll.scroll_vertical = 160
	await _frames()
	var old_scroll := screen._scroll.scroll_vertical
	var old_focus := str(button.name)
	var unchanged := run.snapshot()
	screen._show_deck(true)
	await _frames()
	screen._show_deck(false)
	await _frames(10)
	var restored_focus := root.gui_get_focus_owner()
	check(screen._scroll.scroll_vertical == old_scroll and restored_focus != null and str(restored_focus.name) == old_focus, language + ": inspecting Deck restores the exact offer scroll and keyboard focus")
	check(run.snapshot() == unchanged, language + ": inspecting Deck does not change the pending reward")
	check(run.choose(incoming.id), language + ": a reward spell can be selected for active or reserve placement")
	screen.show_run(run)
	await _frames()
	var add := _option(run, "add")
	var hold := _option(run, "reserve_add")
	var added := screen._change_preview(add)
	var stored := screen._change_preview(hold)
	check(not added.is_empty() and added.active.size() == run.deck.size() + 1 and added.reserve == run.reserve, language + ": add preview increases only the active book")
	check(not stored.is_empty() and stored.active == run.deck and stored.reserve == [run.pending_card], language + ": reserve placement preview leaves active capacity unchanged")
	check(_has_text(screen._journal, screen._change_text(added, true)) and _has_text(screen._journal, screen._change_text(stored, true)), language + ": placement effects are visible before either action")
	await _capture("expedition-v11-placement-" + language)
	check(run.choose("reserve_add") and run.deck == stored.active and run.reserve == stored.reserve and run.phase == "map", language + ": actual reward storage matches the preview")
	screen.show_run(run)
	await _frames()
	check(screen._journal.get_node_or_null("EncounterOutcome") != null and _has_text(screen._journal, run.outcome_details().description), language + ": the settled decision receipt shows the core's actual result")

func _v11_reserve_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	for haven: bool in [false, true]:
		var run := _new(profile, 1103 + int(haven), 11)
		if haven:
			while run.phase in ["boon", "discipline"]: run.choose(_first_enabled(run).id)
			run._reset(profile, run.preset, run.seed_value, 3)
			run.health = run.max_health
		check(_enter_kind(run, "boss" if haven else "rest"), language + ": reserve exchange room is reachable")
		var spare := ""
		for code: String in run._eligible_spells():
			if code not in run.deck:
				spare = code
				break
		if spare.is_empty(): spare = run._eligible_spells()[0]
		run.reserve.assign([spare])
		run.gold = 999
		screen.show_run(run)
		await _frames()
		var prepare := _v11_option_prefix(run, "swap_select:")
		check(not prepare.is_empty() and _choice_button(screen, prepare) != null, language + ": a stored page can be selected for exchange")
		if prepare.is_empty(): continue
		var gold := run.gold
		check(run.choose(prepare.id) and run.gold == gold, language + ": choosing a reserved page does not charge for the exchange")
		screen.show_run(run)
		await _frames()
		check(_choice_button(screen, _option(run, "back")) != null and screen._choice_footer.visible and not screen._merchant_footer.visible, language + ": a pending exchange has fixed Back without a premature merchant exit")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		captured.clear()
		screen._unhandled_key_input(escape)
		check(captured == ["back"], language + ": Escape cancels a pending reserve selection")
		var exchange := _v11_option_prefix(run, "swap_with:")
		var preview := screen._change_preview(exchange)
		var comparison := _choice_button(screen, exchange)
		check(comparison != null and preview.active.size() == run.deck.size() and preview.reserve.size() == 1, language + ": exchange preview keeps both inventory sizes")
		if comparison == null: continue
		comparison.pressed.emit()
		await _frames()
		check(screen._journal.get_node_or_null("BookChangePreview") != null and _has_text(screen._journal, screen._change_text(preview, false)), language + ": exchange comparison shows both active and reserve changes")
		var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
		captured.clear()
		if confirm != null: confirm.pressed.emit()
		check(confirm != null and captured == [exchange.id], language + ": exchange confirmation emits its exact core operation")
		check(run.choose(exchange.id) and run.deck == preview.active and run.reserve == preview.reserve and run.gold == gold - int(exchange.get("cost", 0)), language + ": actual exchange matches both books and the displayed price")
		screen.show_run(run)
		await _frames()
		if haven:
			var used := _option(run, "swap_select:0")
			var used_button := _choice_button(screen, used)
			check(run.phase == "haven" and used_button != null and used_button.disabled and screen._merchant_footer.visible, language + ": the paid Haven exchange stays visible as spent and restores the exit")
			var purchase := _v11_option_prefix(run, "buy_card:")
			var available_gold := run.gold
			check(not purchase.is_empty() and run.choose(purchase.id), language + ": Haven stock can still be bought after the reserve exchange")
			screen.show_run(run)
			await _frames()
			check(not _option(run, "add").is_empty() and not _v11_option_prefix(run, "replace:").is_empty() and _option(run, "reserve_add").is_empty() and _v11_option_prefix(run, "reserve_replace:").is_empty(), language + ": a Haven purchase offers active placement without unusable reserve storage")
			check(_has_text(screen._journal, screen._text("Haven purchases go directly into your active book.", "Покупки на Последнем привале поступают прямо в активную книгу.")) and run.choose("back") and run.gold == available_gold, language + ": Haven placement explains its destination and can be cancelled without payment")
		else:
			check(run.phase == "map" and screen._journal.get_node_or_null("EncounterOutcome") != null, language + ": exchanging at camp consumes that visit and shows its result")
	var removal := _new(profile, 1105, 11)
	check(_enter_kind(removal, "rest"), language + ": a camp removal can be reviewed")
	screen.show_run(removal)
	await _frames()
	var offer := _v11_option_prefix(removal, "remove:")
	check(not offer.is_empty(), language + ": a camp has an available active-page removal")
	if offer.is_empty(): return
	var remove_button := screen._journal_panel.find_child("Compare_" + str(offer.id).replace(":", "_"), true, false) as Button
	var has_remove := remove_button != null
	var before := removal.snapshot()
	if remove_button != null: remove_button.pressed.emit()
	await _frames()
	check(has_remove and removal.snapshot() == before and screen._journal.get_node_or_null("BookChangePreview") != null, language + ": removal first shows lost active capacity without committing")
	var expected := screen._change_preview(offer)
	check(expected.active.size() == removal.deck.size() - 1 and screen._book_metrics(expected.active).charges == screen._book_metrics(removal.deck).charges - removal.charges_per_page(), language + ": removing one page previews the exact lost duel charges")

func _v11_crafting_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	for event_index: int in [1, 7, ELExpeditionRun.ANVIL_EVENT]:
		var run := _v11_event(profile, event_index)
		check(run != null, language + ": a crafting event has a real seeded route")
		if run == null: continue
		run.gold = 999
		run.health = run.max_health
		screen.show_run(run)
		await _frames()
		var source := _v11_option_prefix(run, "craft_select:")
		check(not source.is_empty() and _choice_button(screen, source) != null, language + ": crafting lets the player choose its source page")
		if source.is_empty(): continue
		var gold := run.gold
		var life := run.health
		var book := run.deck.duplicate()
		check(run.choose(source.id) and run.deck == book and run.gold == gold and run.health == life, language + ": choosing a crafting source spends no page, gold, or life")
		screen.show_run(run)
		await _frames()
		var recipe := _v11_option_prefix(run, "craft:")
		var compare := _choice_button(screen, recipe)
		check(compare != null and _choice_button(screen, _option(run, "back")) != null, language + ": visible crafting recipes have a fixed cancellation action")
		if compare == null: continue
		var preview := screen._change_preview(recipe)
		compare.pressed.emit()
		await _frames()
		_check_dialogue(screen, language + ": crafting comparison")
		check(screen._journal.get_node_or_null("BookChangePreview") != null and run.deck == book, language + ": the recipe comparison remains read-only")
		var consume := 2 if event_index == ELExpeditionRun.ANVIL_EVENT else 1
		check(preview.active.size() == book.size() - consume + 1 and preview.reserve == run.reserve, language + ": the recipe preview consumes the specified number of active pages")
		if event_index == 1:
			check(_has_text(screen._journal, screen._text("Life after confirming: %d → %d", "Здоровье после подтверждения: %d → %d") % [life, life - 3]), language + ": Mirror comparison shows its actual life payment")
		if event_index == ELExpeditionRun.ANVIL_EVENT: await _capture("expedition-v11-anvil-" + language)
		var back := screen._choice_footer.find_child("ReplacementBack", true, false) as Button
		var has_back := back != null
		if back != null: back.pressed.emit()
		await _frames()
		check(has_back and not run.pending_craft.is_empty() and screen._replacement.is_empty(), language + ": comparison Back returns to recipes without losing the selected source")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		captured.clear()
		screen._unhandled_key_input(escape)
		check(captured == ["back"], language + ": Escape can cancel the pending crafting source")
		check(run.choose(recipe.id) and run.deck == preview.active and run.reserve == preview.reserve and run.gold == gold - int(recipe.get("cost", 0)) and run.health == life - int(recipe.get("life_cost", 0)), language + ": committed recipe matches the preview and its exact payment")
		screen.show_run(run)
		await _frames()
		check(screen._journal.get_node_or_null("EncounterOutcome") != null and _has_text(screen._journal, run.outcome_details().description), language + ": completed crafting displays the settled outcome")

func _v11_library_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _v11_event(profile, ELExpeditionRun.LIBRARY_EVENT)
	check(run != null, language + ": the Abandoned Library is reachable")
	if run == null: return
	var offered := _v11_option_prefix(run, "library_card:")
	check(not offered.is_empty(), language + ": the Library offers a real page")
	if offered.is_empty(): return
	var alternatives: Array[String] = []
	for code: String in run._eligible_spells():
		if code != offered.card: alternatives.append(code)
		if alternatives.size() == 2: break
	run.reserve.assign(alternatives)
	check(run.choose(offered.id), language + ": a Library page opens reserve-only placement")
	screen.show_run(run)
	await _frames()
	check(_option(run, "add").is_empty() and _option(run, "reserve_add").is_empty(), language + ": a full Library reserve cannot silently add an active or third stored page")
	var replace := _v11_option_prefix(run, "reserve_replace:")
	var comparison := _choice_button(screen, replace)
	var preview := screen._change_preview(replace)
	check(comparison != null and preview.active == run.deck and preview.reserve.size() == 2, language + ": reserve replacement previews the unchanged active book")
	if comparison == null: return
	comparison.pressed.emit()
	await _frames()
	check(_has_text(screen._journal, screen._text("Active book and combat charges stay unchanged.", "Активная книга и боевые заряды не меняются.")), language + ": reserve comparison explicitly excludes active-book and charge changes")
	check(run.choose(replace.id) and run.deck == preview.active and run.reserve == preview.reserve, language + ": the Library's actual reserve replacement matches its preview")

func _v11_option_prefix(run: ELExpeditionRun, prefix: String) -> Dictionary:
	for option: Dictionary in run.choices():
		if str(option.id).begins_with(prefix) and not bool(option.get("disabled", false)): return option
	return {}

func _v11_event(profile: ELProfile, event_index: int) -> ELExpeditionRun:
	for seed in 96:
		var run := _new(profile, 1110 + seed, 11)
		if not _path_to_kind(run, "event", event_index).is_empty() and _enter_kind(run, "event", event_index): return run
	return null

func _v12_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var meal := _v12_event(profile, 11)
	check(meal != null, language + ": v12 reaches a narrative encounter")
	if meal != null:
		screen.show_run(meal)
		await _frames()
		check(screen._journal.get_node_or_null("BookSummary") == null and screen._journal.get_node_or_null("EncounterDeck") != null, language + ": narrative choices omit card statistics while keeping book inspection")
	var reward := _new(profile, 1201, 12)
	check(_enter_kind(reward, "fight") and _win(reward), language + ": v12 reaches a real reward")
	screen.show_run(reward)
	await _frames()
	var strip := screen._journal.get_node_or_null("BookSummary") as Control
	check(strip != null and strip.get_child(0).get_child_count() == 1 and strip.size.y < 90, language + ": card choices use a short single-row book strip")
	check(screen._journal.get_node_or_null("EncounterDeck") == null, language + ": the compact strip avoids a duplicate book button")
	var offer := _v11_option_prefix(reward, "card:")
	check(not offer.is_empty() and reward.choose(offer.id), language + ": v12 selects a reward spell")
	screen.show_run(reward)
	await _frames()
	var add := _choice_button(screen, _option(reward, "add"))
	var reserve := _choice_button(screen, _option(reward, "reserve_add"))
	var replacement := _choice_button(screen, _v11_option_prefix(reward, "replace:"))
	check(add != null and reserve != null and replacement != null and _journal_index(screen, add) < _journal_index(screen, reserve) and _journal_index(screen, reserve) < _journal_index(screen, replacement), language + ": add and reserve placement appear before the replacement list")
	check(reserve != null and screen._scroll.get_global_rect().intersects(reserve.get_global_rect()), language + ": reserve placement is reachable without scrolling past the spellbook")
	check(replacement != null and not replacement.text.contains("×"), language + ": a replacement action does not imply that every owned copy will change")
	screen._show_deck(true)
	await _frames()
	check(screen._journal.find_child("BookCostCurve", true, false) != null and _has_text(screen._journal, screen._text("Spells in your book", "Заклинания в боевой книге")), language + ": full Deck retains cost and class information")
	check(_has_text(screen._journal.get_node("ReservePanel"), screen._text("for free", "бесплатно")) and _has_text(screen._journal.get_node("ReservePanel"), screen._text("as often as you like", "сколько угодно")), language + ": reserve rules explain free repeatable rearrangement")
	screen._show_deck(false)
	await _frames()
	await _v12_camp_checks(screen, profile, language)
	await _v12_merchant_checks(screen, profile, language)
	await _v12_recipe_checks(screen, profile, language)
	await _v12_library_checks(screen, profile, language)
	await _v11_merchant_confirmation_regression(screen, profile, language)

func _v12_camp_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1202, 12)
	check(_enter_kind(run, "rest"), language + ": v12 camp is reachable")
	var spare := ""
	for code: String in run._eligible_spells():
		if code not in run.deck:
			spare = code
			break
	if spare.is_empty(): spare = "ZAPP"
	run.reserve.assign([spare])
	screen.show_run(run)
	await _frames()
	var group := screen._journal.get_node_or_null("CampRemoveChoice") as Button
	var removal := _v11_option_prefix(run, "remove:")
	check(group != null and screen._journal.find_child("Compare_" + str(removal.id).replace(":", "_"), true, false) == null, language + ": camp has one removal entry instead of its entire book")
	var unchanged := run.snapshot()
	if group != null: group.pressed.emit()
	await _frames()
	check(screen._camp_removal_open and screen._choice_footer.find_child("CampRemovalBack", true, false) != null, language + ": camp removal has a fixed Back action")
	_check_dialogue(screen, language + ": v12 grouped camp removal")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	captured.clear()
	screen._unhandled_key_input(escape)
	await _frames()
	check(not screen._camp_removal_open and captured.is_empty() and run.snapshot() == unchanged, language + ": Escape leaves the camp subview without spending the visit")
	for pass_index in 2:
		var prepare := _v11_option_prefix(run, "swap_select:")
		var gold := run.gold
		check(not prepare.is_empty() and run.choose(prepare.id), language + ": free camp swap can be selected repeatedly")
		screen.show_run(run)
		await _frames()
		var swap := _v11_option_prefix(run, "swap_with:")
		var preview := screen._change_preview(swap)
		var compare := _choice_button(screen, swap)
		check(compare != null and not swap.has("cost"), language + ": v12 camp swap has no gold fee")
		if compare == null: return
		compare.pressed.emit()
		await _frames()
		var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
		check(confirm != null and confirm.text == screen._text("Swap spells", "Обменять заклинания"), language + ": swap confirmation names the action")
		check(run.choose(swap.id) and run.deck == preview.active and run.reserve == preview.reserve and run.gold == gold and run.phase == "rest", language + ": the free swap matches its preview and leaves the camp open")
		screen.show_run(run)
		await _frames()
		check(screen._journal.get_node_or_null("EncounterOutcome") != null and _has_text(screen._journal, run.outcome_details().description), language + ": the unspent camp shows the completed swap result")
		check(not _option(run, "forage").is_empty() and screen._journal.get_node_or_null("CampRemoveChoice") != null, language + ": a main camp service remains available after rearranging")
	group = screen._journal.get_node_or_null("CampRemoveChoice") as Button
	if group != null: group.pressed.emit()
	await _frames()
	removal = _v11_option_prefix(run, "remove:")
	var remove_button := screen._journal.find_child("Compare_" + str(removal.id).replace(":", "_"), true, false) as Button
	var had_remove := remove_button != null
	var preview := screen._change_preview(removal)
	if remove_button != null: remove_button.pressed.emit()
	await _frames()
	var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
	check(had_remove and confirm != null and confirm.text == screen._text("Remove spell", "Удалить заклинание"), language + ": grouped removal retains a specific fixed confirmation")
	var change_text := screen._change_text(preview, false)
	check(change_text.contains("%d → %d" % [run.deck.size() * run.charges_per_page(), preview.active.size() * run.charges_per_page()]) and not change_text.contains("0 → 0"), language + ": removal shows lost charges without unchanged zero metrics")
	check(run.choose(removal.id) and run.deck == preview.active and run.phase == "map", language + ": confirmed removal still consumes the main camp service")

func _v12_merchant_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _new(profile, 1203, 12)
	check(_enter_kind(run, "shop"), language + ": v12 merchant is reachable")
	run.gold = 999
	run.health = maxi(1, run.max_health - 5)
	screen.show_run(run)
	await _frames()
	var heal := _choice_button(screen, _option(run, "shop_heal"))
	check(heal != null and not heal.disabled, language + ": merchant healing can be bought")
	if heal == null: return
	heal.grab_focus()
	await _frames()
	screen._scroll.scroll_vertical = 10000
	await _frames()
	var old_anchor := heal.get_global_rect().position.y - screen._scroll.get_global_rect().position.y
	check(screen._scroll.scroll_vertical > 0 and run.choose("shop_heal"), language + ": a purchase is made from the scrolled stock")
	screen.show_run(run)
	await _frames(10)
	heal = _choice_button(screen, _option(run, "shop_heal"))
	check(heal != null and heal.disabled and absf(heal.get_global_rect().position.y - screen._scroll.get_global_rect().position.y - old_anchor) < 3.0, language + ": bought stock retains its position despite the inserted result receipt")
	var next_focus := root.gui_get_focus_owner() as Button
	check(next_focus != null and not next_focus.disabled and screen._scroll.get_global_rect().intersects(next_focus.get_global_rect()), language + ": buying an offer keeps keyboard focus on a nearby usable action")
	var purchase := _v11_option_prefix(run, "buy_card:")
	var buy := _choice_button(screen, purchase)
	if buy == null: return
	buy.grab_focus()
	await _frames()
	screen._scroll.scroll_vertical = 140
	await _frames()
	var old_scroll := screen._scroll.scroll_vertical
	var old_name := str(buy.name)
	var gold := run.gold
	check(run.choose(purchase.id), language + ": merchant card opens its placement choice")
	screen.show_run(run)
	await _frames()
	check(run.choose("back") and run.gold == gold, language + ": cancelling placement leaves gold unchanged")
	screen.show_run(run)
	await _frames(10)
	var focused := root.gui_get_focus_owner()
	check(screen._scroll.scroll_vertical == old_scroll and focused != null and str(focused.name) == old_name, language + ": merchant Back restores stock scroll and keyboard focus")
	var service := screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	if service != null: service.pressed.emit()
	await _frames()
	var removal := _v11_option_prefix(run, "shop_remove:")
	var remove_button := screen._journal.find_child("Compare_" + str(removal.id).replace(":", "_"), true, false) as Button
	if remove_button != null: remove_button.pressed.emit()
	await _frames()
	var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
	check(confirm != null and confirm.text.contains(screen._text("Remove spell", "Удалить заклинание")) and confirm.text.contains(str(removal.cost)), language + ": merchant removal comparison keeps its fixed priced confirmation")
	var haven := _new(profile, 1204, 12)
	while haven.phase in ["boon", "discipline"]: haven.choose(_first_enabled(haven).id)
	haven._reset(profile, haven.preset, haven.seed_value, 3)
	haven.health = haven.max_health
	check(_enter_kind(haven, "boss"), language + ": v12 Last Haven is reachable")
	haven.reserve.assign(["STRT", "ZAPP"])
	haven.gold = 0
	for pass_index in 2:
		var prepare := _v11_option_prefix(haven, "swap_select:")
		check(not prepare.is_empty() and haven.choose(prepare.id), language + ": even an empty purse allows another Haven reserve swap")
		screen.show_run(haven)
		await _frames()
		var swap := _v11_option_prefix(haven, "swap_with:")
		check(not swap.is_empty() and not swap.has("cost") and haven.choose(swap.id) and haven.gold == 0 and haven.phase == "haven", language + ": repeated Haven swaps are free and preserve final preparations")
		screen.show_run(haven)
		await _frames()
		check(screen._merchant_footer.visible and screen._journal.get_node_or_null("EncounterOutcome") != null, language + ": Haven restores its exit and swap result")

func _v12_recipe_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	for event_index: int in [1, ELExpeditionRun.ANVIL_EVENT]:
		var run := _v12_event(profile, event_index)
		check(run != null, language + ": v12 crafting event is reachable")
		if run == null: continue
		run.gold = 999
		run.health = run.max_health
		var source := _v11_option_prefix(run, "craft_select:")
		check(not source.is_empty() and run.choose(source.id), language + ": the recipe source remains explicit")
		screen.show_run(run)
		await _frames()
		var recipe := _v11_option_prefix(run, "craft:")
		var comparison := _choice_button(screen, recipe)
		var expected := screen._change_preview(recipe)
		if comparison == null: continue
		comparison.pressed.emit()
		await _frames()
		var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
		var verb := screen._text("Combine two copies", "Объединить две копии") if event_index == ELExpeditionRun.ANVIL_EVENT else screen._text("Rewrite spell", "Переписать заклинание")
		check(confirm != null and confirm.text.begins_with(verb), language + ": the recipe confirmation specifies rewrite or two-copy combination")
		if event_index == 1: check(confirm != null and confirm.text.contains(screen._text("3 life", "3 здоровья")), language + ": Mirror life cost is on its final action")
		check(not _has_text(screen._journal, "page(s)") and not _has_text(screen._journal, screen._text("Review the change", "Проверьте изменение")), language + ": recipe comparison uses concrete language")
		check(run.choose(recipe.id) and run.deck == expected.active and run.reserve == expected.reserve, language + ": the shorter recipe preview still matches the actual change")

func _v12_library_checks(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var run := _v12_event(profile, ELExpeditionRun.LIBRARY_EVENT)
	check(run != null, language + ": v12 Library is reachable")
	if run == null: return
	var offer := _v11_option_prefix(run, "library_card:")
	check(not offer.is_empty() and run.choose(offer.id), language + ": v12 Library page opens normal placement")
	screen.show_run(run)
	await _frames()
	var add := _choice_button(screen, _option(run, "add"))
	var reserve := _choice_button(screen, _option(run, "reserve_add"))
	var replace := _choice_button(screen, _v11_option_prefix(run, "replace:"))
	check(add != null and reserve != null and replace != null and _journal_index(screen, reserve) < _journal_index(screen, replace), language + ": Library offers direct use and clearly placed reserve storage")
	var preview := screen._change_preview(_option(run, "add"))
	check(run.choose("add") and run.deck == preview.active and run.phase == "map", language + ": a Library spell can be used immediately without a later swap")

func _v12_event(profile: ELProfile, event_index: int) -> ELExpeditionRun:
	for seed in 96:
		var run := _new(profile, 1210 + seed, 12)
		if not _path_to_kind(run, "event", event_index).is_empty() and _enter_kind(run, "event", event_index): return run
	return null

func _v11_merchant_confirmation_regression(screen: ELExpeditionScreen, profile: ELProfile, language: String) -> void:
	var source := _new(profile, 1205, 11)
	check(_enter_kind(source, "shop"), language + ": legacy v11 merchant removal regression reaches a real shop")
	source.gold = 999
	var run := ELExpeditionRun.new()
	check(run.restore_snapshot(profile, source.snapshot()), language + ": the v11 merchant snapshot resumes under current rules")
	screen.show_run(run)
	await _frames()
	var service := screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	if service != null: service.pressed.emit()
	await _frames()
	var removal := _v11_option_prefix(run, "shop_remove:")
	var remove_button := screen._journal.find_child("Compare_" + str(removal.id).replace(":", "_"), true, false) as Button
	check(remove_button != null and screen._shop_removal_open, language + ": resumed v11 merchant has its selectable removal subview")
	if remove_button == null: return
	var unchanged := run.snapshot()
	remove_button.pressed.emit()
	await _frames()
	var confirm := screen._choice_footer.find_child("ConfirmReplacementChoice", true, false) as Button
	check(confirm != null and confirm.text.contains(screen._text("Confirm change", "Подтвердить изменение")) and confirm.text.contains(str(removal.cost)) and run.snapshot() == unchanged, language + ": resumed v11 removal comparison has an unchanged, priced confirmation")
	check(screen._choice_footer.find_child("ReplacementBack", true, false) != null and not screen._merchant_footer.visible, language + ": v11 removal comparison has Back without a premature merchant exit")
	captured.clear()
	if confirm != null: confirm.pressed.emit()
	var gold := run.gold
	var pages := run.deck.size()
	check(captured == [removal.id] and run.choose(removal.id) and run.deck.size() == pages - 1 and run.gold == gold - int(removal.cost), language + ": the recovered v11 confirmation performs its exact original transaction")
	screen.show_run(run)
	await _frames()
	service = screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	check(run.phase == "shop" and service != null and service.disabled and screen._merchant_footer.visible, language + ": v11 merchant returns with its removal spent once")

func _new(profile: ELProfile, seed := 20261120, version := 9, challenge := "standard") -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(profile, "ExpeditionFixtureRed", seed, version, challenge):
		check(false, "Create current Expedition: " + run.error)
		return null
	return run

func _first_enabled(run: ELExpeditionRun) -> Dictionary:
	for option: Dictionary in run.choices():
		if not bool(option.get("disabled", false)): return option
	return {}

func _path_to_kind(run: ELExpeditionRun, kind: String, event_index := -1) -> Array[String]:
	var paths := {}
	for row: Array in run.route():
		for node: Dictionary in row:
			if node.floor == 1: paths[node.id] = [node.id]
			if not paths.has(node.id): continue
			if node.kind == kind and (event_index < 0 or int(node.get("event", -1)) == event_index):
				var result: Array[String] = []
				result.assign(paths[node.id])
				return result
			for next: String in node.next:
				if not paths.has(next): paths[next] = paths[node.id] + [next]
	return []

func _enter_kind(run: ELExpeditionRun, kind: String, event_index := -1) -> bool:
	if run == null: return false
	while run.phase in ["boon", "discipline"]:
		if not run.choose(_first_enabled(run).id): return false
	var path := _path_to_kind(run, kind, event_index)
	if path.is_empty(): return false
	for id: String in path:
		if not run.choose_node(id): return false
		if id == path.back(): return true
		if not _settle_room(run): return false
	return false

func _win(run: ELExpeditionRun) -> bool:
	if run.phase != "battle": return false
	var duel := run.build_battle()
	if duel == null: return false
	duel.phase = ELDuel.Phase.FINISHED
	duel.winner = 0
	duel.heroes[0].health = mini(run.max_health, maxi(1, run.health))
	duel.heroes[1].health = 0
	return run.resolve_battle(duel)

func _settle_room(run: ELExpeditionRun) -> bool:
	for attempt in 8:
		if run.phase == "map": return true
		if run.phase == "battle":
			if not _win(run): return false
			continue
		var selected := _first_enabled(run)
		for option: Dictionary in run.choices():
			if option.id in ["leave", "skip", "skip_relic", "heal"] and not bool(option.get("disabled", false)):
				selected = option
				break
		if selected.is_empty() or not run.choose(selected.id): return false
	return run.phase == "map"

func _shop_checks(screen: ELExpeditionScreen, run: ELExpeditionRun, language: String) -> void:
	run.gold = 0
	screen.show_run(run)
	await _frames()
	_check_dialogue(screen, language + ": merchant")
	var disabled_count := 0
	for option: Dictionary in run.choices():
		if not option.has("cost") or int(option.cost) <= 0: continue
		var button := _choice_button(screen, option)
		if button == null: continue # Equivalent copies of a removable spell share one action.
		disabled_count += 1
		check(button.disabled and _caption(button).contains(str(option.cost)), language + ": unaffordable merchant offer retains its price and disabled button")
		captured.clear()
		button.pressed.emit()
		check(captured.is_empty(), language + ": a disabled offer cannot emit a purchase")
	check(disabled_count > 0, language + ": merchant shows unaffordable stock instead of hiding it")
	var service := screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	check(service != null and service.disabled, language + ": unaffordable removal is one clearly disabled service")
	check(screen._merchant_footer.visible and screen._merchant_leave.visible, language + ": Leave remains outside the scrolling merchant stock")
	screen._scroll.scroll_vertical = 10000
	await _frames()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(screen._merchant_leave.get_global_rect()), language + ": Leave stays on screen at the bottom of the stock list")
	await _capture("expedition-merchant-" + language)
	# The service must show the actual relic-adjusted price, including the
	# retained zero price for old runs and the v9 discount.
	run.relics.append("purifier_stone")
	var removal_price := 0
	for option: Dictionary in run.choices():
		if str(option.id).begins_with("shop_remove:"):
			removal_price = int(option.cost)
			break
	run.gold = removal_price
	screen.show_run(run)
	await _frames()
	service = screen._journal.get_node_or_null("ShopRemoveChoice") as Button
	check(service != null and not service.disabled and service.text.contains(str(removal_price)), language + ": Purifier removal shows its actual price and accepts exact funds")
	if service != null:
		service.pressed.emit()
		await _frames()
		check(screen._shop_removal_open and screen._merchant_back.visible and screen._merchant_leave.visible, language + ": removal has Back and persistent Leave")
		_check_dialogue(screen, language + ": removal service")
		screen._merchant_back.pressed.emit()
		await _frames()
		check(not screen._shop_removal_open and screen._journal.get_node_or_null("ShopRemoveChoice") != null, language + ": Back returns to merchant stock without spending")
		service = screen._journal.get_node_or_null("ShopRemoveChoice") as Button
		service.pressed.emit()
		await _frames()
		var removal := {}
		for option: Dictionary in run.choices():
			if str(option.id).begins_with("shop_remove:") and not bool(option.get("disabled", false)):
				removal = option
				break
		var remove_button := _choice_button(screen, removal)
		check(remove_button != null, language + ": removal subview lists actual selectable cards")
		if remove_button != null:
			captured.clear()
			remove_button.pressed.emit()
			check(captured == [removal.id], language + ": removal sends the exact selected card action")
			var old_size := run.deck.size()
			check(run.choose(removal.id) and run.deck.size() == old_size - 1 and run.gold == 0, language + ": discounted removal pays the shown price through the actual run")
			screen.show_run(run)
			await _frames()
			service = screen._journal.get_node_or_null("ShopRemoveChoice") as Button
			check(service != null and service.disabled, language + ": an already-used removal remains visible and unavailable")
			captured.clear()
			service.pressed.emit()
			check(captured.is_empty() and not screen._shop_removal_open, language + ": a used service cannot reopen the removal subview")
	run.gold = 999
	var bought := {}
	for option: Dictionary in run.choices():
		if str(option.id).begins_with("buy_card:") and not bool(option.get("disabled", false)):
			bought = option
			break
	check(not bought.is_empty(), language + ": merchant offers a purchasable spell")
	if bought.is_empty(): return
	check(run.choose(bought.id), language + ": merchant spell opens a placement choice")
	screen.show_run(run)
	await _frames()
	var replacement := {}
	for option: Dictionary in run.choices():
		if str(option.id).begins_with("replace:"):
			replacement = option
			break
	check(not replacement.is_empty() and replacement.has("cost"), language + ": placement choices retain the price")
	if replacement.is_empty(): return
	var compare := _choice_button(screen, replacement)
	check(compare != null, language + ": spell replacement has a visible comparison action")
	if compare == null: return
	compare.pressed.emit()
	await _frames()
	var confirm := screen._journal_panel.find_child("ConfirmReplacementChoice", true, false) as Button
	check(confirm != null and not confirm.disabled, language + ": replacement comparison has an enabled confirmation")
	check(_has_text(screen._journal, str(replacement.cost)), language + ": replacement comparison displays payment information")
	if confirm != null:
		captured.clear()
		confirm.pressed.emit()
		check(captured == [replacement.id], language + ": replacement confirmation emits one exact transaction")
	await _capture("expedition-replacement-" + language)
	var old_gold := run.gold
	check(run.choose(replacement.id) and run.gold == old_gold - int(replacement.cost), language + ": confirmed replacement pays the shown price")
	screen.show_run(run)
	await _frames()
	var bought_button := _choice_button(screen, bought)
	check(bought_button != null and bought_button.disabled, language + ": purchased stock stays visible and cannot be bought again")

func _choice_button(screen: ELExpeditionScreen, option: Dictionary) -> Button:
	if option.is_empty(): return null
	var id := str(option.id)
	var prefix := "Compare_" if id.begins_with("replace:") or option.has("incoming") else "Choice_"
	return screen._journal_panel.find_child(prefix + id.replace(":", "_"), true, false) as Button

func _check_dialogue(screen: ELExpeditionScreen, label: String) -> void:
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	check(viewport.encloses(screen._journal_panel.get_global_rect()), label + ": the modal panel fits the viewport")
	check(screen._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, label + ": choices wrap without horizontal scrolling")
	check(screen._scroll.size.y > 100.0, label + ": a useful vertical choice area remains")

func _check_map(screen: ELExpeditionScreen, label: String) -> void:
	var buttons: Array = screen._nodes.values()
	var bounds := Rect2(Vector2.ZERO, screen._map.size)
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	check(viewport.encloses(screen._map.get_global_rect()), label + ": the route itself fits the viewport")
	check(viewport.encloses(screen._vitals.get_global_rect()) and viewport.encloses(screen._return.get_global_rect()), label + ": gold, life and navigation fit the header")
	var all_inside := true
	var overlap := false
	for i in buttons.size():
		var rect: Rect2 = buttons[i].get_rect()
		all_inside = all_inside and bounds.encloses(rect)
		for j in range(i + 1, buttons.size()):
			if rect.intersects(buttons[j].get_rect()): overlap = true
	check(all_inside, label + ": every room button fits the map")
	check(not overlap, label + ": room buttons do not overlap")

## Everything a choice shows: its own text, its tile's lines and the cost
## under a spellbook square.
func _caption(button: Button) -> String:
	var parts: PackedStringArray = [button.text]
	var holders: Array[Node] = [button]
	var square := button.get_parent()
	if square != null and str(square.name).begins_with("Square_"): holders = [square]
	for holder: Node in holders:
		for label: Node in holder.find_children("*", "Label", true, false): parts.append(str(label.text))
	return " ".join(parts)

## Points at a spellbook square, so its lines show in the detail under it.
func _reveal(button: Control) -> void:
	if button != null: button.mouse_entered.emit()

## The journal position of the entry that holds `node` (-1 outside it).
func _journal_index(screen: ELExpeditionScreen, node: Node) -> int:
	while node != null and node.get_parent() != screen._journal: node = node.get_parent()
	return node.get_index() if node != null else -1

func _has_text(node: Node, fragment: String) -> bool:
	if (node is Label or node is Button) and str(node.text).contains(fragment): return true
	for child: Node in node.get_children():
		if _has_text(child, fragment): return true
	return false

func _capture(name: String) -> void:
	var folder := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="): folder = arg.trim_prefix("--screenshots=")
	if folder.is_empty(): return
	await _frames()
	var image := root.get_texture().get_image()
	if image == null or image.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder)
	image.save_png(folder.path_join(name + ".png"))

func _finish() -> void:
	check(checks >= 50, "The complete UI suite executed in both languages")
	check(languages_completed == 2, "Both language passes reached completion")
	print("EXPEDITION UI: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
