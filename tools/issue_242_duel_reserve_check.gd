extends SceneTree
## #242: the Etherlords II duel deck editor as the game itself shows it (the
## main scene, its front menu and overlays) in a 1600x900 window: a shipped
## preset with a full active deck (16/16), eight reserve copies and a name
## being typed in "Save deck as". Real pointer events (window pixels, through
## Input) drag a reserve copy onto the available spells, which removes it, and
## another onto an occupied deck slot, which swaps the two. Each press comes
## after the pointer rested long enough for a tooltip. The editor is opened,
## cancelled and opened again, and the tabs switched, before the drags.
##
##   godot --headless --path game --script ../tools/issue_242_duel_reserve_check.gd
##
## Needs the second game's files (user://profiles.json); without them it is
## skipped. Nothing is saved.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

var view: Node

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count: await process_frame

func _send(event: InputEventMouse, at: Vector2) -> void:
	event.position = root.get_final_transform() * at
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _move(at: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_send(event, at)

func _button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_send(event, at)

func _drag(from: Vector2, to: Vector2, rest := 0.0) -> void:
	_move(from)
	await frames(2)
	if rest > 0.0: await create_timer(rest).timeout
	_button(from, true)
	await frames(1)
	for step in 6:
		_move(from.lerp(to, (step + 1) / 6.0), true)
		await frames(1)
	_button(to, false)
	await frames(2)

func pt(c: Control, local: Vector2) -> Vector2:
	return c.get_global_transform_with_canvas() * local

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
		quit(0)
		return
	view = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	for i in 100:
		await create_timer(0.1).timeout
		if view.front_menu != null and view.front_menu.is_visible_in_tree(): break
	if view.front_menu == null: view._show_front_menu()
	await create_timer(0.5).timeout
	var menu: ELFrontMenu = view.front_menu
	if menu != null and menu.edition != "el2":
		menu._choice.selected.emit("el2")
		await create_timer(1.0).timeout
		menu = view.front_menu
	check(menu != null and menu.edition == "el2", "the second game's main menu is shown")
	if menu != null and menu.edition == "el2": await _editor(menu)
	view.queue_free()
	await frames(5)
	print("ISSUE 242 DUEL RESERVE CHECK: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _editor(menu: ELFrontMenu) -> void:
	var duel := menu.duel_ui
	duel.refresh_pool()
	var shipped := ELDuelPresets.shipped(menu.profile)
	check(not shipped.is_empty(), "the game ships deck presets")
	if shipped.is_empty(): return
	var preset: Dictionary = shipped[min(2, shipped.size() - 1)]
	duel.open_editor(preset, String(preset.id))
	await frames(3)
	duel.cancel_editor()
	await frames(3)
	duel.open_editor(preset, String(preset.id))
	await frames(3)
	duel.select_tab(1)
	await frames(3)
	duel.select_tab(0)
	await frames(3)
	for i in 8: duel.act("spell_to_reserve", duel.right_items[10 + i].value)
	duel.name_edit.text = String(preset.name) + "2"
	duel.name_edit.grab_focus()
	duel.name_edit.caret_column = duel.name_edit.text.length()
	await frames(3)
	var p := duel.editor_preset()
	var copies := func() -> int: return duel.editor_preset().reserve.values().reduce(func(a, b): return a + b, 0)
	check(p.cards.size() == 16 and copies.call() == 8, "the deck is full and the reserve holds eight copies")
	var reserve: ELDuelScreen.BookView = menu.labels.reserve
	var book: ELDuelScreen.BookView = duel.book_view
	var list: Control = duel.right_list
	var removed: String = reserve.entries()[0].card
	var before := int(p.reserve.get(removed, 0))
	await _drag(pt(reserve, reserve.slot_rect(0).get_center()), pt(list, list.size * 0.5), ELCombatTooltip.DELAY + 0.3)
	p = duel.editor_preset()
	check(copies.call() == 7 and int(p.reserve.get(removed, 0)) == before - 1, "a reserve copy dragged onto the available spells is removed")
	var card: String = reserve.entries()[0].card
	var displaced: String = p.cards[3]
	await _drag(pt(reserve, reserve.slot_rect(0).get_center()), pt(book, book.slot_rect(3).get_center()), ELCombatTooltip.DELAY + 0.3)
	p = duel.editor_preset()
	check(p.cards.size() == 16 and p.cards[3] == card and int(p.reserve.get(displaced, 0)) >= 1 and copies.call() == 7,
		"a reserve copy dragged onto a slot of the full deck swaps with it")
	duel.cancel_editor()
	await frames(2)
