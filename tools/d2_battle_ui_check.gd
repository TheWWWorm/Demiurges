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
