extends SceneTree
## #242: the Etherlords II duel deck editor as the game itself shows it (the
## main scene, its front menu and overlays) in a 1600x900 window: a shipped
## preset with a full active deck (16/16), eight reserve copies and a name
## being typed in "Save deck as". Real pointer events (window pixels, through
## Input) drag a reserve copy onto the available spells, which removes it, and
## another onto an occupied deck slot, which swaps the two. Each press comes
## after the pointer rested long enough for a tooltip. The editor is opened,
## cancelled and opened again, and the tabs switched, before the drags.
## The original's click to pick up and click to place: a reserve copy clicked
## and then a card of the full deck swap; a reserve copy clicked and then the
## available spells is removed; a deck card clicked and then the reserve is
## stored; an available spell clicked twice goes back; a right click puts a
## carried card back and deletes nothing. Every pick and place plays Select3,
## a click on an empty cell with nothing carried Error, and the carried card
## is on the pointer, its cell left empty.
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

func _click(at: Vector2, index := MOUSE_BUTTON_LEFT) -> void:
	_move(at)
	await frames(1)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = index
		event.pressed = pressed
		event.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		_send(event, at)
		await frames(1)
	# Past the double-click interval, so the next press is a single click.
	await create_timer(0.6).timeout

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
	await _clicks(duel, reserve, book, list, copies)
	duel.cancel_editor()
	await frames(2)
	check(duel.held.is_empty() and ELCursorDriver.instance().carry_image == null, "closing the editor lets go of the carried card")

func _clicks(duel: ELDuelScreen, reserve: ELDuelScreen.BookView, book: ELDuelScreen.BookView, list: ItemList, copies: Callable) -> void:
	var sounds := func(from: int) -> Array: return ELUiSounds.history.slice(from)
	var p := duel.editor_preset()
	# A reserve copy into the full deck: pick, then place on a deck card.
	var mark := ELUiSounds.history.size()
	var card: String = reserve.entries()[0].card
	await _click(pt(reserve, reserve.slot_rect(0).get_center()))
	check(duel.held.get("zone") == "reserve" and duel.held.get("card") == card and ELCursorDriver.instance().carry_image != null and sounds.call(mark) == [ELDuelScreen.SELECT_SOUND],
		"a click picks up a reserve copy: it rides on the pointer with Select3")
	var displaced: String = p.cards[5]
	var before: int = copies.call()
	await _click(pt(book, book.slot_rect(5).get_center()))
	p = duel.editor_preset()
	check(duel.held.is_empty() and p.cards.size() == 16 and p.cards[5] == card and int(p.reserve.get(displaced, 0)) >= 1 and copies.call() == before
		and sounds.call(mark) == [ELDuelScreen.SELECT_SOUND, ELDuelScreen.SELECT_SOUND] and ELCursorDriver.instance().carry_image == null,
		"click-click: a reserve copy placed on a card of the full deck swaps with it")
	# A reserve copy removed by a click on the available spells.
	card = reserve.entries()[0].card
	var count := int(p.reserve.get(card, 0))
	before = copies.call()
	await _click(pt(reserve, reserve.slot_rect(0).get_center()))
	await _click(pt(list, list.get_item_rect(7).get_center()))
	p = duel.editor_preset()
	check(copies.call() == before - 1 and int(p.reserve.get(card, 0)) == count - 1 and int(duel.edit.item) == -1 and list.get_selected_items().is_empty(),
		"click-click: a reserve copy put on the available spells is removed, nothing is picked there")
	# A right click puts the carried copy back and deletes nothing.
	before = copies.call()
	mark = ELUiSounds.history.size()
	await _click(pt(reserve, reserve.slot_rect(0).get_center()))
	await _click(pt(reserve, reserve.slot_rect(0).get_center()), MOUSE_BUTTON_RIGHT)
	check(duel.held.is_empty() and copies.call() == before and sounds.call(mark) == [ELDuelScreen.SELECT_SOUND, ELDuelScreen.SELECT_SOUND],
		"a right click puts the carried copy back")
	await _click(pt(reserve, reserve.slot_rect(0).get_center()), MOUSE_BUTTON_RIGHT)
	check(copies.call() == before, "a right click with nothing carried deletes nothing")
	# The same copy clicked twice goes back.
	await _click(pt(reserve, reserve.slot_rect(0).get_center()))
	await _click(pt(reserve, reserve.slot_rect(0).get_center()))
	check(duel.held.is_empty() and copies.call() == before, "a copy clicked again goes back")
	# An empty reserve cell with nothing carried plays Error.
	mark = ELUiSounds.history.size()
	await _click(pt(reserve, reserve.slot_rect(15).get_center()))
	check(sounds.call(mark) == [ELDuelScreen.ERROR_SOUND] and duel.held.is_empty(), "an empty reserve cell with nothing carried plays Error")
	# A deck card stored in the reserve.
	p = duel.editor_preset()
	card = p.cards[0]
	count = int(p.reserve.get(card, 0))
	await _click(pt(book, book.slot_rect(0).get_center()))
	check(duel.is_held("book", 0), "a click picks up a deck card")
	await _click(pt(reserve, reserve.slot_rect(15).get_center()))
	p = duel.editor_preset()
	check(p.cards.size() == 15 and int(p.reserve.get(card, 0)) == count + 1, "click-click: a deck card put on the reserve is stored there")
	# An available spell: clicked twice goes back, then placed on the deck's gap.
	await _click(pt(list, list.get_item_rect(2).get_center()))
	check(int(duel.edit.item) == 2 and ELCursorDriver.instance().carry_image != null, "a click picks up an available spell")
	await _click(pt(list, list.get_item_rect(2).get_center()))
	check(int(duel.edit.item) == -1 and ELCursorDriver.instance().carry_image == null, "the same available spell clicked again goes back")
	var spell: String = duel.right_items[2].value
	await _click(pt(list, list.get_item_rect(2).get_center()))
	await _click(pt(book, book.size - Vector2(8, 8)))
	p = duel.editor_preset()
	check(p.cards.size() == 16 and p.cards[-1] == spell, "click-click: an available spell placed on the deck's gap fills it")
