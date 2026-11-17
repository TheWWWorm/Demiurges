extends SceneTree
## Headless check of second-game battle and encyclopaedia reports (0.15.0):
## - #143 the pale manifestations' variable strength reads X/X in the
##   encyclopaedia's creature list and in a card tooltip (it showed -2/-2);
## - #148 hot seat: the hero panels follow the player at the screen, the
##   acting player's portrait and values on the left, the opponent's on the
##   right (both games);
## - #144 combat tutorial: the text column stands along the right edge and
##   fills most of the screen height, with only the close cross offered; the
##   spell the script awaits blinks in the hand.
##
##   godot --headless --path game --script ../tools/d2_battle_ui_check.gd
##
## Needs the original games' files (user://profiles.json); without them a
## game is skipped.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no el2 files configured (user://profiles.json)")
	else:
		var profile := ELProfile.new()
		if profile.mount("el2", str(paths.el2)): _pale_strength(profile)
		else: print("SKIP: el2 files could not be mounted")
	for edition: String in ["el2", "el1"]: await _hot_seat_panels(edition)
	await _casting_and_retry()
	await _tutorial()
	print("D2 BATTLE UI CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# --- #143 ---------------------------------------------------------------------

func _pale_strength(profile: ELProfile) -> void:
	var found := 0
	for code: String in profile.table("CombatCreatures"):
		var row: Dictionary = profile.table("CombatCreatures")[code]
		if int(row.get("Power", 0)) >= 0: continue
		found += 1
		var shown := ELEncyclopaedia.strength(profile, code)
		check(shown == "X/X", "el2 #143: the encyclopaedia shows %s as X/X (%s)" % [code, shown])
		var tip := ELCombatTooltip.spell_text(profile, code)
		check(tip.contains(" X/X") and not tip.contains("-2"), "el2 #143: %s's card tooltip reads X/X" % code)
	check(found >= 2, "el2 #143: the pale manifestations with variable strength are found (%d)" % found)
	check(ELEncyclopaedia.strength(profile, "ORSH") == "%d/%d" % [int(profile.table("CombatCreatures").ORSH.Power), int(profile.table("CombatCreatures").ORSH.Toughness)], "el2 #143: a printed strength stays as it is")

# --- #148 ---------------------------------------------------------------------

func _hot_seat_panels(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	var profile: ELProfile = view.profiles.get(edition)
	if profile == null:
		print("SKIP: no %s files for the hot-seat check" % edition)
		view.queue_free()
		return
	var pool := ELDuelPresets.shipped(profile)
	var first: Dictionary = pool[0]
	var second := {}
	for row: Dictionary in pool:
		if row.faction != first.faction and int(row.resource_level) == int(first.resource_level):
			second = row
			break
	var hot_match := ELDuelMatch.new()
	hot_match.begin(profile, pool, [first, second], int(first.resource_level), 1, ELDuelMatch.RANDOM, 77)
	hot_match.hot_seat = true
	hot_match.names = ["P1", "P2"]
	view._begin_duel_match(hot_match)
	await frames(5)
	var seen := {}
	for turn in 3:
		for i in 50:
			if view.hot_pending: break
			await process_frame
		var side: int = view.duel.active_side()
		view._confirm_handover()
		await frames(2)
		var own: Control = view.portraits[side]
		var other: Control = view.portraits[1 - side]
		var stats: Array = view.rail.stats
		var expected := [view.shown_health(side), view.shown_ether(side), view.shown_channels(side)]
		var left_ok: bool = own.position.x < other.position.x and view.hero_buttons[side].position.x < view.hero_buttons[1 - side].position.x
		check(left_ok and stats.size() == 2 and stats[0] == expected, "%s #148 hot seat: player %d's portrait and values are on the left on their turn" % [edition, side + 1])
		seen[side] = true
		var guard := 0
		while view.duel.active_side() == side and guard < 8 and view.duel.phase != ELDuel.Phase.FINISHED:
			view._end_phase()
			await frames(3)
			guard += 1
	check(seen.size() == 2, "%s #148 hot seat: both players took the screen" % edition)
	view.duel_match = null
	view.queue_free()
	await frames(2)

func _casting_and_retry() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	if not view.profiles.has("el2"):
		view.queue_free()
		return
	view._hide_front_menu()
	view._start("el2", {"first_side": 0}, null, 212)
	var duel: ELDuel = view.duel
	var opening: Dictionary = duel.snapshot()
	duel.heroes[0].mana = 20
	duel.heroes[0].hand = ["FRWA", "FRWA", "ZAPP", "STRT"]
	duel.heroes[0].hand_slots = [-1, -1, -1, -1]
	duel._summon(1, "STMC")
	duel._summon(1, "BATT")
	view._skip_battle_presentation()
	var target: int = duel.army(1)[0].id
	var played: Array[String] = []
	var discarded: Array[Dictionary] = []
	duel.event.connect(func(data: Dictionary):
		if data.kind == "cast": played.append(data.card)
		if data.kind == "discard": discarded.append(data))
	view._cast_card(0)
	check(played == ["FRWA"] and (view._display_lagging() or not view._hits_waiting.is_empty()), "Fire Wave starts and has a hit still being presented")
	view._cast_card(0)
	check(discarded.size() == 1 and discarded[0].card == "STRT" and discarded[0].get("source_card") == "BATT", "the dying Bat discards the rat and identifies the cause")
	view._cast_card(duel.heroes[0].hand.find("ZAPP"))
	view._target(target)
	view._end_phase()
	check(played == ["FRWA", "FRWA", "ZAPP"] and duel.active_side() == 1, "two Fire Waves and Electroshock resolve before the turn passes")
	view._skip_battle_presentation()
	var log_key := InputEventKey.new()
	log_key.keycode = KEY_L
	log_key.physical_keycode = KEY_L
	log_key.pressed = true
	view.log_text.hide()
	root.push_input(log_key, true)
	view._show_log()
	var report: String = view.log_text.text
	var death: String = view._t("%s dies.") % duel.card_name("BATT")
	var loss: String = view._t("The dying Bat made you discard %s.") % duel.card_name("STRT")
	var damage := -1
	for event: Dictionary in duel.history:
		if event.kind != "damage" or event.get("source_card") != "FRWA" or event.get("target_card") != "BATT": continue
		var hit: String = view._t("%s takes %d damage.") % [duel.card_name("BATT"), event.amount]
		var with_source: String = view._t("%s (during %s)") % [hit, duel.card_name("FRWA")]
		damage = report.find(with_source)
		break
	check(view.log_text.visible and damage >= 0 and report.find(death) > damage and report.find(loss) > report.find(death), "L shows Fire Wave's damage, the Bat's death and the discard in order")
	duel._emit({"kind": "draw", "side": 1, "card": "PWTP"})
	var hidden_draw: String = view._t("%s draws a spell.") % view._hero_name(1)
	check(view.logs.back() == hidden_draw, "the battle log records the opponent's draw without naming the hidden card")
	view._ask_surrender()
	var retry: ELFrontMenu.CutButton = view.options_host.buttons.get("MBRetry") if view.options_host != null else null
	check(retry != null and view.options_host.buttons.has("MBOK") and view.options_host.buttons.has("MBCancel"), "the surrender box has all three choices")
	if retry != null:
		var ok: ELFrontMenu.CutButton = view.options_host.buttons.MBOK
		var cancel: ELFrontMenu.CutButton = view.options_host.buttons.MBCancel
		check(retry.size == ok.size and retry.size == cancel.size, "the three surrender buttons are the original size")
		check(retry.position - cancel.position == cancel.position - ok.position, "the three surrender buttons are evenly spaced")
		retry.pressed.emit()
		check(view.duel != duel and view.duel.turn_serial == opening.turn_serial and view.duel.heroes[0].hand == opening.heroes[0].hand, "Try again restarts the same duel and opening hand")
	view.queue_free()
	await frames(2)

# --- #144 ---------------------------------------------------------------------

func _tutorial() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	await frames(3)
	if not view.profiles.has("el2"):
		print("SKIP: no el2 files for the combat tutorial check")
		view.queue_free()
		return
	view._begin_combat_tutorial()
	await frames(4)
	var tutorial: ELCombatTutorial = view.combat_tutorial
	var panel: ELCombatTutorialPanel = view.tutorial_panel
	if tutorial == null or panel == null:
		check(false, "el2 #144: the combat tutorial starts")
		view.queue_free()
		return
	var screen: Vector2 = panel.size
	var text := Rect2(panel.text_box.position, panel.text_box.size)
	check(text.end.x > screen.x * 0.9 and text.position.x > screen.x * 0.6, "el2 #144: the tutorial text stands along the right edge (%s in %s)" % [text, screen])
	check(text.size.y > screen.y * 0.6, "el2 #144: the tutorial text fills most of the screen height (%d of %d px)" % [text.size.y, screen.y])
	check(panel.buttons.TP_Close.visible and not panel.buttons.TP_Show.visible, "el2 #144: the tutorial panel offers the close cross alone")
	# Play the script up to the first spell the player must cast.
	var guard := 0
	while tutorial.awaited_hand_index() < 0 and not tutorial.done() and tutorial.error.is_empty() and guard < 300:
		tutorial.run_current()
		guard += 1
	var awaited: int = tutorial.awaited_hand_index()
	check(awaited >= 0, "el2 #144: the script reaches a spell the player must cast")
	view._refresh()
	await frames(2)
	var blinking: Array = []
	for button: Node in view.hand.get_children():
		if button.has_meta("hand_index") and button.get_node_or_null("TutorialBlink") != null: blinking.append(int(button.get_meta("hand_index")))
	check(blinking == [awaited], "el2 #144: the awaited spell (hand %d) blinks, no other card does (%s)" % [awaited, blinking])
	view._close_combat_tutorial()
	view.queue_free()
	await frames(2)
