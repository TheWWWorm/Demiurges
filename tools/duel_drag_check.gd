extends SceneTree
## Headless check of dragging items on the Duel preset editor (ELDuelScreen):
## - first game (EditHero): a spell dragged from the list onto the spellbook is
##   added, a book spell dragged onto the list is returned; an artifact dragged
##   onto the hero's strip is bought and dragged back is returned; a skill or a
##   specialisation dragged onto the specialisation and skills block is taken,
##   an owned skill dragged onto the list is lowered; a rune row dragged onto a
##   book spell adds a rune there; a drop on the item's own panel or outside
##   every panel changes nothing, a press without travel only picks;
##   the right panel's cells and rows sit on the art's grid;
## - second game (EditPresetA6): a listed spell dragged onto the deck or the
##   reserve goes there, deck and reserve spells move between them, a reserve
##   spell dragged onto the list is removed; a listed skill dragged onto the
##   hero's skills is learned and dragged back is lowered; a listed artifact
##   dragged onto the hero's cells is bought and dragged back is returned.
##
##   godot --headless --path game --script ../tools/duel_drag_check.gd
##
## Pointer input goes through the viewport (press, motions, release), as a
## mouse or a touch drag does. Needs the original games' files
## (user://profiles.json); a game without them is skipped. Nothing is saved.

var failures: Array[String] = []
var host: Control

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func frames(count: int) -> void:
	for i in count: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 960)
	host = Control.new()
	host.size = Vector2(1280, 960)
	root.add_child(host)
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary:
		print("SKIP: no original game files configured (user://profiles.json)")
		paths = {}
	var mounted := {}
	for edition: String in ["el1", "el2"]:
		if not paths.has(edition):
			print("SKIP: %s files are not configured" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		mounted[edition] = profile
	for edition: String in mounted:
		var menu := ELFrontMenu.new()
		host.add_child(menu)
		menu.size = host.size
		if not menu.build(mounted, edition):
			print("SKIP: %s has no front-end art" % edition)
			menu.queue_free()
			continue
		await frames(2)
		if edition == "el1": await _first(menu)
		else: await _second(menu)
		menu.queue_free()
		await frames(2)
	print("DUEL DRAG CHECK: %d failure(s)" % failures.size())
	host.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

func _editor(menu: ELFrontMenu) -> ELDuelScreen:
	var duel := menu.duel_ui
	duel.refresh_pool()
	var preset := ELDuelPresets.blank("Green", 1)
	preset.level = 10
	preset.resource_level = 5 if menu.edition == "el1" else 3
	duel.open_editor(preset, "")
	return duel

func _tab(duel: ELDuelScreen, tab: int) -> void:
	duel.select_tab(tab)
	await frames(2)

func preset(duel: ELDuelScreen) -> Dictionary:
	return duel.editor_preset()

# --- First game ------------------------------------------------------------

func _first(menu: ELFrontMenu) -> void:
	var duel := _editor(menu)
	await _tab(duel, 0)
	var choices: ELDuelScreen.ChoiceView = duel.choice_view
	check(choices != null and choices.grid, "first game: the Spells tab shows the cell grid")
	if choices == null: return
	var origin := choices.position - menu.shift("EditHero")
	check(origin == ELDuelScreen.EL1_GRID_ORIGIN and choices.size == Vector2(212, 371), "first game: the grid covers the art's 4x7 cells of 53 px")
	var card: String = duel.right_items[0].value
	await drag(choices, choices.item_rect(0).get_center(), duel.book_view, Vector2(10, 10))
	check(preset(duel).cards == [card], "first game: a listed spell dragged onto the book is added")
	await drag(choices, choices.item_rect(1).get_center(), choices, choices.item_rect(5).get_center())
	check(preset(duel).cards.size() == 1, "first game: a spell dropped on its own list changes nothing")
	await drag(choices, choices.item_rect(1).get_center(), menu.canvas, Vector2(4, 4))
	check(preset(duel).cards.size() == 1 and duel.carry.is_empty(), "first game: a spell dropped outside the panels goes back")
	await click(choices, choices.item_rect(2).get_center())
	check(preset(duel).cards.size() == 1 and int(duel.edit.item) == 2, "first game: a press without travel only picks")
	await drag(duel.book_view, duel.book_view.slot_rect(0).get_center(), choices, Vector2(20, 20))
	check(preset(duel).cards.is_empty(), "first game: a book spell dragged onto the list is returned")
	# Runes: a rune row dropped on a book spell adds a rune to it.
	duel.act("add_spell", card)
	duel.act("add_spell", card)
	await _tab(duel, 2)
	choices = duel.choice_view
	check(choices != null and not choices.grid, "first game: the Runes tab shows rows")
	if duel.apply(preset(duel), "add_rune", 1) != null:
		await drag(choices, choices.item_rect(0).get_center(), duel.book_view, duel.book_view.slot_rect(1).get_center())
		check(int(preset(duel).runes[1]) == 1 and int(preset(duel).runes[0]) == 0, "first game: a rune row dropped on a book spell adds its rune there")
	else:
		print("NOTE: no rune can be bought for the test preset")
	# Artifacts.
	await _tab(duel, 3)
	choices = duel.choice_view
	var strip: Control = menu.labels.get("artifacts")
	if duel.right_items.is_empty() or strip == null:
		print("NOTE: no artifacts to drag")
	else:
		var artifact: String = duel.right_items[0].value
		await drag(choices, choices.item_rect(0).get_center(), strip, strip.size * 0.5)
		check(preset(duel).artifacts == [artifact], "first game: a listed artifact dragged onto the strip is bought")
		await drag(strip, Vector2(strip.size.x * 0.1, strip.size.y * 0.5), choices, Vector2(20, 20))
		check(preset(duel).artifacts.is_empty(), "first game: a strip artifact dragged onto the list is returned")
	# Skills and specialisation onto the specialisation and skills block.
	var block := _zone(duel, "skills")
	await _tab(duel, 1)
	choices = duel.choice_view
	block = _zone(duel, "skills")
	check(block != null, "first game: the specialisation and skills block takes drops")
	if block == null or duel.right_items.is_empty(): return
	var skill: String = duel.right_items[0].value
	await drag(choices, choices.item_rect(0).get_center(), block, block.size * 0.5)
	check(preset(duel).skills.has(skill), "first game: a listed skill dragged onto the skills is learned")
	var row := duel._rect("EHSkill1")
	await drag(block, row.get_center() - block.position, choices, Vector2(20, 20))
	check(not preset(duel).skills.has(skill), "first game: an owned skill dragged onto the list is lowered")
	await _tab(duel, 4)
	choices = duel.choice_view
	block = _zone(duel, "skills")
	if duel.right_items.size() > 1:
		var spec: String = duel.right_items[1].value
		await drag(choices, choices.item_rect(1).get_center(), block, block.size * 0.5)
		check(String(preset(duel).specialization) == spec, "first game: a specialisation dragged onto the block is taken")

func _zone(duel: ELDuelScreen, zone: String) -> Control:
	for entry: Dictionary in duel.drop_zones:
		if entry.zone == zone and is_instance_valid(entry.control): return entry.control
	return null

# --- Second game -----------------------------------------------------------

func _second(menu: ELFrontMenu) -> void:
	var duel := _editor(menu)
	await _tab(duel, 0)
	var list := duel.right_list
	var reserve: Control = menu.labels.get("reserve")
	check(list != null and reserve != null, "second game: the spell lists are shown")
	if list == null or reserve == null: return
	var card: String = duel.right_items[0].value
	await drag(list, list.get_item_rect(0).get_center(), duel.book_view, Vector2(10, 10))
	check(preset(duel).cards == [card], "second game: a listed spell dragged onto the deck is added")
	await drag(list, list.get_item_rect(0).get_center(), reserve, Vector2(10, 10))
	check(int(preset(duel).reserve.get(card, 0)) == 1, "second game: a listed spell dragged onto the reserve is stored")
	await drag(duel.book_view, duel.book_view.slot_rect(0).get_center(), reserve, Vector2(10, 10))
	check(preset(duel).cards.is_empty() and int(preset(duel).reserve.get(card, 0)) == 2, "second game: a deck spell dragged onto the reserve moves there")
	await drag(reserve, reserve.slot_rect(0).get_center(), duel.book_view, Vector2(10, 10))
	check(preset(duel).cards == [card] and int(preset(duel).reserve.get(card, 0)) == 1, "second game: a reserve spell dragged onto the deck moves there")
	await drag(reserve, reserve.slot_rect(0).get_center(), list, Vector2(10, 10))
	check(not preset(duel).reserve.has(card), "second game: a reserve spell dragged onto the list is removed")
	await drag(list, list.get_item_rect(1).get_center(), menu.canvas, Vector2(4, 4))
	check(preset(duel).cards == [card] and preset(duel).reserve.is_empty(), "second game: a spell dropped outside the panels goes back")
	await _tab(duel, 1)
	list = duel.right_list
	var skills := _zone(duel, "skills")
	var artifacts: ItemList = menu.labels.get("all_artifacts")
	var strip: Control = menu.labels.get("artifacts")
	if list == null or skills == null or duel.right_items.is_empty(): return
	var skill: String = duel.right_items[0].value
	await drag(list, list.get_item_rect(0).get_center(), skills, Vector2(20, 10))
	check(preset(duel).skills.has(skill), "second game: a listed skill dragged onto the hero's skills is learned")
	await drag(skills, Vector2(20, 10), list, Vector2(10, 10))
	check(not preset(duel).skills.has(skill), "second game: a hero skill dragged onto the list is lowered")
	if artifacts == null or strip == null or artifacts.item_count == 0: return
	var artifact: String = duel.artifact_choices()[0]
	await drag(artifacts, artifacts.get_item_rect(0).get_center(), strip, Vector2(10, strip.size.y * 0.5))
	check(preset(duel).artifacts == [artifact], "second game: a listed artifact dragged onto the hero's cells is bought")
	await drag(strip, Vector2(10, strip.size.y * 0.5), artifacts, Vector2(10, 10))
	check(preset(duel).artifacts.is_empty(), "second game: a hero artifact dragged onto the list is returned")

# --- Pointer --------------------------------------------------------------

func button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	return event

func motion(at: Vector2, held := true) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.position = at
	event.global_position = at
	return event

## A press, six motions and a release through the viewport, from a point of
## one control to a point of another (local coordinates).
func drag(from: Control, from_at: Vector2, to: Control, to_at: Vector2) -> void:
	var start := from.get_global_transform_with_canvas() * from_at
	var end := to.get_global_transform_with_canvas() * to_at
	root.push_input(motion(start, false), true)
	await frames(1)
	root.push_input(button(start, true), true)
	await frames(1)
	var last := start
	for step in 6:
		var event := motion(start.lerp(end, (step + 1) / 6.0))
		event.relative = event.position - last
		last = event.position
		root.push_input(event, true)
		await frames(1)
	root.push_input(button(end, false), true)
	await frames(2)

func click(control: Control, at: Vector2) -> void:
	var point := control.get_global_transform_with_canvas() * at
	root.push_input(motion(point, false), true)
	await frames(1)
	root.push_input(button(point, true), true)
	await frames(1)
	root.push_input(button(point, false), true)
	# Past the double-click interval, so the next press is a single click.
	await create_timer(0.6).timeout
