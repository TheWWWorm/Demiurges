extends SceneTree
## Headless check of dragging cards out of the battle hand:
## - a targeted spell (Zap) dragged onto an enemy creature is cast on it;
## - dragged onto empty ground, onto the panel or back onto the rail it is
##   not cast and nothing stays selected;
## - a summon dragged onto the battlefield is cast, one dropped back on the
##   rail is not, and a plain click on it still casts it;
## - click the spell, then click the target still casts;
## - on touch, a drag along the rail does not pick the card up (the rail
##   scrolls), one leaving the rail upward does;
## - plain item lists (ELListDrag: the quick battle spellbook editor, the
##   network deck change): an entry dragged onto the other list is dropped
##   there, one dropped on its own list is not;
## - the Expedition board (second game): an offer dragged onto a spellbook
##   card is taken in its place, one dropped outside the spellbook is not
##   and the choice goes back to what it was;
## - autochess (second game): a shop offer dragged onto the reserves is
##   bought, a reserve creature dragged onto another reserve slot moves
##   there, one dropped on the shop moves nowhere.
## Runs for each game whose files are configured; pointer events go through
## the viewport as the mouse (and the touch layer) send them.
##
##   godot --headless --path game --script ../tools/hand_drag_check.gd
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _edition(edition)
	print("HAND DRAG: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _edition(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return
	view.settings.values.hide_cast = true
	view._start(edition)
	await _idle(view)
	view.demo = false
	# A desktop-sized window with the panel at one to one.
	root.size = Vector2i(1440, 900)
	view.settings.values.battle_interface = 1
	await process_frame
	view._layout_hud()
	var duel: ELDuel = view.duel
	# The player's own attack phase.
	for i in 600:
		if view._human_turn() and duel.phase == ELDuel.Phase.ATTACK: break
		view.ai_clock = -1000.0
		await process_frame
	if not view._human_turn():
		check(false, "%s: the player gets a turn" % edition)
		view.queue_free()
		await process_frame
		return
	var side := duel.active_side()
	var summon := ""
	for row: String in view.profile.table("CombatCreatures"):
		if duel.is_summon(row):
			summon = row
			break
	var victim := await _summoned(view, 1 - side, summon)
	check(victim >= 2, "%s: a creature stands on the opposing side" % edition)
	if victim < 2:
		view.queue_free()
		await process_frame
		return
	duel.creatures[victim].damage = 0
	var rail_top: float = (view.card_scroll.get_global_transform_with_canvas() * Vector2.ZERO).y
	var ground := Vector2(view.get_viewport().get_visible_rect().size.x * 0.5, 6.0)
	var panel: Vector2 = (view.hero_buttons[0].get_global_transform_with_canvas() * Vector2(view.hero_buttons[0].size.x + 60.0, 20.0))

	# A targeted spell dropped on empty ground, on the panel, back on the rail.
	for place: String in ["ground", "panel", "rail"]:
		var button := await _given(view, side, "ZAPP")
		var start := _centre(button)
		var drop: Vector2 = {"ground": ground, "panel": panel, "rail": start + Vector2(0, -2)}[place]
		var count := _count(duel, side, "ZAPP")
		await _drag(view, start, drop, place != "rail")
		check(_count(duel, side, "ZAPP") == count and view.selection == -1 and not view._hand_drag_icon.visible, "%s: Zap dropped on the %s is not cast and not left selected" % [edition, place])

	# A targeted spell dragged onto the creature.
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	var zap := await _given(view, side, "ZAPP")
	var count := _count(duel, side, "ZAPP")
	var at := _figure_point(view, victim)
	check(view._character_at(at) == victim, "%s: the creature is found under its screen point" % edition)
	await _drag(view, _centre(zap), at, true, func() -> void:
		check(view._hand_drag_icon.visible and view.selection >= 0 and view.combat_hover == victim and view.cursor_name == "spell", "%s: while dragged, the card follows the pointer with the targeting cursor over the creature (%s)" % [edition, view.cursor_name]))
	check(_count(duel, side, "ZAPP") == count - 1 and _zapped(duel, victim), "%s: Zap dropped on the creature is cast on it" % edition)
	await _idle(view)

	# Click the spell, then click the target.
	victim = await _summoned(view, 1 - side, summon)
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	zap = await _given(view, side, "ZAPP")
	count = _count(duel, side, "ZAPP")
	await _click(view, _centre(zap))
	check(view.selection >= 0 and duel.heroes[side].hand[view.selection] == "ZAPP", "%s: a click selects the spell" % edition)
	await _click(view, _figure_point(view, victim))
	check(_count(duel, side, "ZAPP") == count - 1 and view.selection == -1, "%s: then a click on the creature casts it" % edition)
	await _idle(view)

	# A summon: back on the rail (nothing), onto the battlefield (cast), clicked (cast).
	if not summon.is_empty():
		var creatures: int = duel.creatures.size()
		duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 60)
		var card := await _given(view, side, summon)
		count = _count(duel, side, summon)
		await _drag(view, _centre(card), _centre(card) + Vector2(0, -2), false)
		check(_count(duel, side, summon) == count and duel.creatures.size() == creatures, "%s: a summon dropped back on the rail is not cast" % edition)
		card = _button(view, summon)
		await _drag(view, _centre(card), ground, true)
		check(_count(duel, side, summon) == count - 1 and duel.creatures.size() == creatures + 1, "%s: a summon dropped on the battlefield is cast" % edition)
		await _idle(view)
		duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 60)
		card = await _given(view, side, summon)
		count = _count(duel, side, summon)
		await _click(view, _centre(card))
		check(_count(duel, side, summon) == count - 1, "%s: a click on a summon still casts it" % edition)
		await _idle(view)

	# Touch: along the rail the card stays; leaving the rail upward picks it up.
	ELTouchInput.enabled = true
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	zap = await _given(view, side, "ZAPP")
	var from := _centre(zap)
	_button_event(view, from, true)
	for step in 6: _motion(view, from + Vector2(-8.0 * (step + 1), 0))
	check(not view._hand_drag.is_empty() and not view._hand_drag.started, "%s: on touch a drag along the rail does not pick the card up" % edition)
	_motion(view, Vector2(from.x - 48.0, rail_top - 30.0))
	check(not view._hand_drag.is_empty() and view._hand_drag.started, "%s: on touch a drag leaving the rail upward picks the card up" % edition)
	_motion(view, ground)
	_button_event(view, ground, false)
	await process_frame
	check(view.selection == -1 and _count(duel, side, "ZAPP") >= 1, "%s: on touch the card dropped on empty ground is not cast" % edition)
	ELTouchInput.enabled = false
	var profile: ELProfile = view.profile
	view.queue_free()
	await process_frame
	await process_frame
	await _lists(profile)
	if edition == "el2":
		await _expedition_board(profile)
		await _autochess(profile)

func _autochess(profile: ELProfile) -> void:
	var screen := ELAutochessScreen.new()
	root.add_child(screen)
	screen.build(profile, ELSettings.new().values)
	var game := ELAutochessMatch.new()
	game.auto_save = false
	var seats: Array[String] = ["human"]
	for player in ELAutochessRules.PLAYER_COUNT - 1: seats.append("computer")
	game.begin(profile, 777, ELAutochessCharacters.choices(profile)[0], seats)
	screen.show_match(game, 0, null)
	for i in 5: await process_frame
	var own := screen.company()
	own.ether = 99
	screen._refresh()
	await process_frame
	var offer := -1
	for index in own.shop.size():
		if not screen._offers[index].disabled:
			offer = index
			break
	if offer < 0:
		check(false, "autochess: an offer can be bought")
		screen.queue_free()
		return
	var army := own.army.size()
	var offer_at: Vector2 = screen._offers[offer].get_global_transform_with_canvas() * (screen._offers[offer].size * 0.5)
	await _drag(screen, offer_at, _centre(screen._reserves[0]), true)
	check(own.army.size() == army + 1, "autochess: an offer dragged onto the reserves is bought")
	await process_frame
	# A bought creature may step onto the board: one goes to the first slot.
	if own.bench_count() == 0 and not own.army.is_empty():
		screen._act("bench", [int(own.army[-1].uid), 0])
		screen._refresh()
		await process_frame
	var slots := own.reserve_slots()
	var from := -1
	for slot in slots.size():
		if not slots[slot].is_empty():
			from = slot
			break
	var to := slots.size() - 1
	if from < 0 or from == to:
		check(false, "autochess: a reserve creature stands apart from the last slot")
	else:
		var uid := int(slots[from].uid)
		await _drag(screen, _centre(screen._reserves[from]), _centre(screen._reserves[to]), true)
		check(int(own.reserve_slots()[to].get("uid", -1)) == uid and not own.unit(uid).deployed, "autochess: a reserve creature dragged onto another slot moves there")
		await _drag(screen, _centre(screen._reserves[to]), offer_at, true)
		check(int(own.reserve_slots()[to].get("uid", -1)) == uid and not own.unit(uid).deployed and own.army.size() == army + 1, "autochess: a reserve creature dropped on the shop moves nowhere")
	screen.queue_free()
	await process_frame

## Two item lists joined as the deck editors join theirs.
func _lists(profile: ELProfile) -> void:
	var host := HBoxContainer.new()
	host.size = Vector2(600, 300)
	root.add_child(host)
	var left := ItemList.new()
	var right := ItemList.new()
	for list: ItemList in [left, right]:
		list.custom_minimum_size = Vector2(280, 280)
		list.fixed_icon_size = Vector2i(36, 36)
		host.add_child(list)
	for card: String in ["ZAPP", "ZAPP", "ZAPP"]: left.add_item(card, profile.card_icon(card))
	right.add_item("ZAPP", profile.card_icon("ZAPP"))
	var drops: Array = []
	ELListDrag.enable(left, "left", ["right"], func(from: String, index: int, to: int): drops.append([from, index, to]))
	ELListDrag.enable(right, "right", ["left"], func(from: String, index: int, to: int): drops.append([from, index, to]))
	await process_frame
	await process_frame
	await _viewport_drag(left, left.get_item_rect(1).get_center(), right, right.get_item_rect(0).get_center())
	# Headless, the viewport reports the drop at the window's mouse position
	# (the origin), so only the source of the drop is checked here.
	check(drops.size() == 1 and drops[0][0] == "left" and drops[0][1] == 1, "lists: an entry dragged onto the other list is dropped there (%s)" % [drops])
	drops.clear()
	await _viewport_drag(left, left.get_item_rect(0).get_center(), left, left.get_item_rect(2).get_center())
	check(drops.is_empty(), "lists: an entry dropped on its own list is not")
	host.queue_free()
	await process_frame

## An Expedition reward board with two offers and a full spellbook.
func _expedition_board(profile: ELProfile) -> void:
	var kit := ELMenuKit.for_profile(profile)
	if kit == null or kit.theme() == null or not kit.has_control(ELExpeditionBoard.PANEL):
		print("SKIP: no spell shop art for the Expedition board")
		return
	var board := ELExpeditionBoard.new()
	board.kit = kit
	board.profile = profile
	board.phase = "reward"
	board.max_deck = 3
	board.deck.assign(["ZAPP", "ZAPP", "ZAPP"])
	for id: String in ["reward:a", "reward:b"]:
		board.offers.append({"id": id, "icon": profile.card_icon("ZAPP"), "name": id, "stats": "", "text": "", "needs": "room"})
	board._build()
	root.add_child(board)
	await process_frame
	var taken: Array = []
	board.chosen.connect(func(ids: Array): taken.append(ids))
	var surface: Control = board._surface
	var from := board.cell_rect("shop", 1).get_center()
	await _surface_drag(surface, from, Vector2(5, 5))
	check(taken.is_empty() and board.picked == -1 and board.marked == -1 and not board._dragging, "Expedition: an offer dropped outside the spellbook is not taken and nothing stays chosen")
	await _surface_drag(surface, from, board.cell_rect("bag", 2).get_center())
	check(taken == [["reward:b", "replace:2"]], "Expedition: an offer dragged onto a spellbook card is taken in its place (%s)" % [taken])
	board.queue_free()
	await process_frame

## Press, motion and release sent to a control in its own coordinates.
func _surface_drag(target: Control, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	target._gui_input(press)
	for step in 6:
		var move := InputEventMouseMotion.new()
		move.position = from.lerp(to, (step + 1) / 6.0)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		target._gui_input(move)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	target._gui_input(release)
	await process_frame

## A drag through the viewport from a point of one control to a point of another.
func _viewport_drag(from: Control, from_at: Vector2, to: Control, to_at: Vector2) -> void:
	var start := from.get_global_transform_with_canvas() * from_at
	var end := to.get_global_transform_with_canvas() * to_at
	_motion_at(start, false)
	_button_at(start, true)
	await process_frame
	var last := start
	for step in 6:
		var event := InputEventMouseMotion.new()
		event.position = start.lerp(end, (step + 1) / 6.0)
		event.global_position = event.position
		event.relative = event.position - last
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = event.position
		root.push_input(event, true)
		await process_frame
	_button_at(end, false)
	await process_frame
	await process_frame

func _motion_at(at: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)

func _button_at(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 600:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return

func _summoned(view: Node, side: int, card: String) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if not before.has(id): return id
	return -1

func _count(duel: ELDuel, side: int, card: String) -> int:
	return duel.heroes[side].hand.count(card)

func _zapped(duel: ELDuel, id: int) -> bool:
	return not duel.creatures.has(id) or int(duel.creatures[id].damage) > 0

## Puts `card` into the side's hand and returns its rail button.
func _given(view: Node, side: int, card: String) -> TextureButton:
	view.duel._give_card(side, card, -1, true)
	view._refresh()
	# The card drops into the rail first.
	await create_timer(1.0).timeout
	return _button(view, card)

func _button(view: Node, card: String) -> TextureButton:
	view.card_scroll.scroll_horizontal = 0
	for child: Node in view.hand.get_children():
		if child is TextureButton and child.get_meta("card", "") == card and not child.disabled: return child
	return null

func _centre(button: Control) -> Vector2:
	if button == null: return Vector2(-1000, -1000)
	return button.get_global_transform_with_canvas() * (button.size * 0.5)

## The screen point of a figure's middle.
func _figure_point(view: Node, id: int) -> Vector2:
	var model: ELModel = view.models[id]
	for lift: float in [0.6, 0.4, 0.9, 0.2, 1.2]:
		var at: Vector2 = view.camera.unproject_position(model.global_position + Vector3(0, lift, 0))
		if view._character_at(at) == id: return at
	return view.camera.unproject_position(model.global_position + Vector3(0, 0.6, 0))

func _button_event(view: Node, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	view.get_viewport().push_input(event, true)

func _motion(view: Node, at: Vector2, held := true) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	view.get_viewport().push_input(event, true)

func _click(view: Node, at: Vector2) -> void:
	_motion(view, at, false)
	_button_event(view, at, true)
	_button_event(view, at, false)
	await process_frame

## A left drag from `from` to `to` in steps; `during` runs before the release.
func _drag(view: Node, from: Vector2, to: Vector2, far: bool, during := Callable()) -> void:
	_motion(view, from, false)
	_button_event(view, from, true)
	await process_frame
	var path: Array[Vector2] = []
	if far:
		for step in 8: path.append(from.lerp(to, (step + 1) / 8.0))
	else:
		# Out of the slop and back onto the card.
		path = [from + Vector2(0, -12), from + Vector2(0, -20), to]
	for point: Vector2 in path:
		_motion(view, point)
		await process_frame
	view._update_cursor()
	if during.is_valid(): during.call()
	_button_event(view, to, false)
	await process_frame
	await process_frame
