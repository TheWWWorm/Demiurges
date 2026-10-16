class_name ELSpellShopView
extends PanelContainer
## Second-game spell shop (SpellShopScreen) on the original art: the hero's
## reserve ("bag", 8x5 cells) and the 16-slot active deck on the left, the
## shop stock (5x5 cells) on the right, the deal table (selected spell, total
## bill, available resources; bill figures turn red when they exceed the
## stock) and OK / Cancel. Cards are picked with a click, follow the cursor and
## are placed with a second click (into the bag, a deck slot or the shop); the
## right button puts a carried card back. Enter = OK, Esc = Cancel. Rules in
## ELSecondSpellShop over the ELSpellShop trade; layout from Controls and
## CutParts (panel "SpellShopScreen", shift 112,14 at 1024x768).
signal closed
const PANEL := "SpellShopScreen"
const CELL := Vector2(53, 52)
const ICON := Vector2(50, 50)
## Icon inset inside a cell, as on the inventory screen (same list views).
const INSET := Vector2(2, 1)
const BAG_COLUMNS := 8
const BAG_ROWS := 5
const SHOP_COLUMNS := 5
const SHOP_ROWS := 5
const DECK_COLUMNS := 8
const TAN := Color8(0xd6, 0xbb, 0x88)
const RED := Color8(0xff, 0x00, 0x00)
## SOLID_WHITE (white, alpha 136) tinted over the picked card and
##  over a card that crossed the counter.
const PICK_TINT := Color(0xf0 / 255.0, 0xf0 / 255.0, 0xf0 / 255.0, 136 / 255.0)
const MARK_TINT := Color(0x80 / 255.0, 0x80 / 255.0, 1.0, 136 / 255.0)
const HEADERS := ["SpellShopHdrBag", "SpellShopHdrBagSpells", "SpellShopHdrDeck", "SpellShopHdrShop", "SpellShopShopHdrSpells", "SpellShopHdrDeal", "SpellShopHdrSelSpell", "SpellShopHdrTotalBill", "SpellShopHdrAvailRes"]

var hud: ELSecondAdventureHud
var trade: ELSpellShop
var model := ELSecondSpellShop.new()
var profile: ELProfile
var root_control: Control
var canvas: Control
var surface: Surface
var cursor: Control
var labels: Dictionary = {}
var buttons: Dictionary = {}
var accept: BaseButton
var message_box: ELSecondDialogueBox
var sound: AudioStreamPlayer
var bag_row := 0
var shop_row := 0
var _pieces: Array[Dictionary] = []
var _offset := Vector2.ZERO
var _mouse := Vector2(-1000, -1000)

func build(exchange: ELSpellShop) -> void:
	trade = exchange
	profile = trade.state.map.profile
	model.open(trade)
	name = "SpellShopScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_STOP
	root_control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root_control)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(canvas)
	surface = Surface.new()
	surface.view = self
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.tooltip_text = " "
	canvas.add_child(surface)
	for control: String in HEADERS:
		var row: Dictionary = hud._controls.get(control, {})
		var align := HORIZONTAL_ALIGNMENT_RIGHT if "Right" in str(row.get("FontType", "")) else HORIZONTAL_ALIGNMENT_CENTER
		labels[control] = _label(hud.text(str(row.get("Text", ""))), int(row.get("FontSize", 18)), align)
	for line in 3:
		for column in 3:
			var control := "SpellShopRes%d%d" % [line + 1, column + 1]
			labels[control] = _label("", int(hud._controls.get(control, {}).get("FontSize", 17)), HORIZONTAL_ALIGNMENT_CENTER)
	for control: String in labels: labels[control].name = control
	for control: String in ["SpellShopOkBtn", "SpellShopCancelBtn", "SpellShopScrollUp1", "SpellShopScrollDown1", "SpellShopScrollUp2", "SpellShopScrollDown2"]:
		var button := ELSecondNotebookView.ArtButton.make(hud, control)
		button.tooltip_text = hud.tooltip_of(control)
		canvas.add_child(button)
		buttons[control] = button
	accept = buttons.SpellShopOkBtn
	buttons.SpellShopOkBtn.pressed.connect(_commit)
	buttons.SpellShopCancelBtn.pressed.connect(cancel_trade)
	buttons.SpellShopScrollUp1.pressed.connect(scroll.bind("bag", -1))
	buttons.SpellShopScrollDown1.pressed.connect(scroll.bind("bag", 1))
	buttons.SpellShopScrollUp2.pressed.connect(scroll.bind("shop", -1))
	buttons.SpellShopScrollDown2.pressed.connect(scroll.bind("shop", 1))
	message_box = ELSecondDialogueBox.new()
	root_control.add_child(message_box)
	message_box.setup(hud)
	message_box.name = "SpellShopMessage"
	message_box.answered.connect(func(_answer: String): message_box.hide())
	cursor = Control.new()
	cursor.name = "CarriedCard"
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(cursor)
	cursor.draw.connect(_draw_cursor)
	# Leaving or hiding the screen gives the cursor back.
	tree_exiting.connect(func(): ELCursorDriver.carry(profile, null))
	visibility_changed.connect(func(): if not is_visible_in_tree(): ELCursorDriver.carry(profile, null))
	sound = AudioStreamPlayer.new()
	add_child(sound)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.resized.connect(_layout)
	refresh()

func _label(value: String, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", hud.face_bold)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TAN)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

# --- Layout -------------------------------------------------------------------

func design(control: String) -> Rect2:
	var row: Dictionary = hud._controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + _offset, Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func _layout() -> void:
	var area := root_control.size
	if area.y <= 0: return
	var factor := area.y / ELSecondAdventureHud.DESIGN_HEIGHT
	var width := maxf(1024.0, area.x / factor)
	canvas.scale = Vector2(factor, factor)
	canvas.size = Vector2(width, ELSecondAdventureHud.DESIGN_HEIGHT)
	surface.size = canvas.size
	cursor.size = canvas.size
	var row: Dictionary = hud._controls.get(PANEL, {})
	_offset = Vector2(float(row.get("ShiftX", 112)) + (width - 1024.0) * 0.5, float(row.get("ShiftY", 14)))
	_pieces.clear()
	for piece_row: Dictionary in hud._rows.get(PANEL, []):
		var piece := hud.cut(piece_row, _offset)
		if not piece.is_empty(): _pieces.append(piece)
	for control: String in labels:
		labels[control].position = design(control).position
		labels[control].size = design(control).size
	for control: String in buttons: buttons[control].place(_offset)
	message_box.layout()
	surface.queue_redraw()
	cursor.queue_redraw()

# --- State --------------------------------------------------------------------

func refresh() -> void:
	if surface == null: return
	var price := model.selected_price()
	var total := model.bill()
	var money := model.wallet()
	for column in 3:
		var kind: String = ELResources.SEQUEL[column]
		var picked: Label = labels["SpellShopRes1%d" % (column + 1)]
		var bill: Label = labels["SpellShopRes2%d" % (column + 1)]
		var stock: Label = labels["SpellShopRes3%d" % (column + 1)]
		# "-" until the first click, then figures (0 with nothing carried).
		picked.text = str(int(price[kind])) if model.touched else "-"
		bill.text = str(int(total[kind])) if model.touched else "-"
		stock.text = str(int(money.get(kind, 0)))
		bill.add_theme_color_override("font_color", RED if int(total[kind]) > int(money.get(kind, 0)) else TAN)
	_refresh_scroll()
	_layout()

func scroll(which: String, delta: int) -> void:
	if which == "bag": bag_row = clampi(bag_row + delta, 0, _last_row("bag"))
	else: shop_row = clampi(shop_row + delta, 0, _last_row("shop"))
	_refresh_scroll()
	surface.queue_redraw()

func _last_row(which: String) -> int:
	if which == "bag": return maxi(0, ceili(model.bag.size() / float(BAG_COLUMNS)) - BAG_ROWS)
	return maxi(0, ceili(model.shop.size() / float(SHOP_COLUMNS)) - SHOP_ROWS)

func _refresh_scroll() -> void:
	bag_row = clampi(bag_row, 0, _last_row("bag"))
	shop_row = clampi(shop_row, 0, _last_row("shop"))
	buttons.SpellShopScrollUp1.disabled = bag_row <= 0
	buttons.SpellShopScrollDown1.disabled = bag_row >= _last_row("bag")
	buttons.SpellShopScrollUp2.disabled = shop_row <= 0
	buttons.SpellShopScrollDown2.disabled = shop_row >= _last_row("shop")

# --- Hit testing ----------------------------------------------------------------

## Zone and index under a canvas point: ["bag", i], ["shop", i] (-1 = empty
## space), ["deck", slot] or ["", -1].
func hit(at: Vector2) -> Array:
	for which: String in ["bag", "shop"]:
		var bounds := design("SpellShopBagBounds" if which == "bag" else "SpellShopShopBounds")
		if bounds.has_point(at):
			var columns := BAG_COLUMNS if which == "bag" else SHOP_COLUMNS
			var rows := BAG_ROWS if which == "bag" else SHOP_ROWS
			var cell := Vector2i((at - bounds.position) / CELL)
			if cell.x >= columns or cell.y >= rows: return [which, -1]
			var index := ((bag_row if which == "bag" else shop_row) + cell.y) * columns + cell.x
			return [which, index if index < model.zone(which).size() else -1]
	var deck := design("SpellShopASpellsBounds1")
	if deck.has_point(at):
		var cell := Vector2i((at - deck.position) / CELL)
		if cell.x >= DECK_COLUMNS or cell.y >= 2: return ["deck", -1]
		return ["deck", cell.y * DECK_COLUMNS + cell.x]
	return ["", -1]

## Canvas rectangle of a card (empty when scrolled out of view).
func cell_rect(which: String, index: int) -> Rect2:
	match which:
		"bag", "shop":
			var columns := BAG_COLUMNS if which == "bag" else SHOP_COLUMNS
			var row := index / columns - (bag_row if which == "bag" else shop_row)
			if row < 0 or row >= (BAG_ROWS if which == "bag" else SHOP_ROWS): return Rect2()
			return Rect2(design("SpellShopBagBounds" if which == "bag" else "SpellShopShopBounds").position + INSET + Vector2(index % columns, row) * CELL, ICON)
		"deck": return Rect2(design("SpellShopASpellsBounds1").position + INSET + Vector2(index % DECK_COLUMNS, index / DECK_COLUMNS) * CELL, ICON)
	return Rect2()

func surface_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if not model.carried().is_empty(): cursor.queue_redraw()
		return
	if not event is InputEventMouseButton or not event.pressed: return
	_mouse = event.position
	if message_box.visible: return
	var target := hit(event.position)
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: if target[0] in ["bag", "shop"]: scroll(target[0], -1)
		MOUSE_BUTTON_WHEEL_DOWN: if target[0] in ["bag", "shop"]: scroll(target[0], 1)
		MOUSE_BUTTON_RIGHT:
			if model.right_click():
				_play(model.last_sound)
				_changed()
		MOUSE_BUTTON_LEFT:
			var result := ""
			var sizes := [model.bag.size(), model.shop.size()]
			match target[0]:
				"bag": result = model.click_bag(target[1])
				"deck": result = model.click_deck(target[1])
				"shop": result = model.click_shop(target[1])
				_: return
			# A card appended to a list is scrolled into view.
			if model.bag.size() > sizes[0]: bag_row = maxi(bag_row, (model.bag.size() - 1) / BAG_COLUMNS - BAG_ROWS + 1)
			if model.shop.size() > sizes[1]: shop_row = maxi(shop_row, (model.shop.size() - 1) / SHOP_COLUMNS - SHOP_ROWS + 1)
			_play(result)
			_changed()

func _changed() -> void:
	refresh()
	cursor.queue_redraw()

func _play(path: String) -> void:
	if path.is_empty(): return
	var stream := ELAudio.sound(profile, path)
	if stream == null: return
	sound.stream = stream
	sound.play()

# --- Commands -------------------------------------------------------------------

func _commit() -> void:
	if message_box.visible: return
	var result := model.accept()
	_changed()
	if result.is_empty():
		closed.emit()
		return
	if result != "forbidden": show_message(profile.text(result))

func cancel_trade() -> void:
	if message_box.visible:
		message_box.hide()
		return
	_changed()
	if model.cancel(): closed.emit()

func show_message(value: String) -> void:
	message_box.present({"box": "message", "text": value, "question": false}, trade.state)
	message_box.move_to_front()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if message_box.visible: message_box.hide()
			else: _commit()
		_: return
	get_viewport().set_input_as_handled()

# --- Drawing --------------------------------------------------------------------

func draw_surface(target: Control) -> void:
	target.draw_rect(Rect2(Vector2.ZERO, target.size), Color(0, 0, 0, 0.35))
	for piece: Dictionary in _pieces: target.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	for which: String in ["bag", "shop", "deck"]:
		var entries := model.zone(which)
		for index in entries.size():
			if entries[index].is_empty(): continue
			var rect := cell_rect(which, index)
			if rect.size == Vector2.ZERO: continue
			var icon := profile.card_icon(str(entries[index].card))
			if icon != null: target.draw_texture_rect(icon, rect, false)
			if model.picked_zone == which and model.picked == index: target.draw_rect(rect, PICK_TINT)
			if ELSecondSpellShop.marked(which, entries[index]): target.draw_rect(rect, MARK_TINT)

func _draw_cursor() -> void:
	var entry := model.carried()
	var icon: Texture2D = profile.card_icon(str(entry.card)) if not entry.is_empty() else null
	# The original's cursor becomes the icon; drawn here only without one.
	if ELCursorDriver.carry(profile, icon) or icon == null or _mouse.x < -500: return
	cursor.draw_texture_rect(icon, Rect2(_mouse - ICON * 0.5, ICON), false)

# --- Tooltips -------------------------------------------------------------------

func tooltip_at(at: Vector2) -> String:
	var target := hit(at)
	if target[0].is_empty() or target[1] < 0: return ""
	var entry: Dictionary = model.zone(target[0])[target[1]]
	if entry.is_empty(): return ""
	var row: Dictionary = profile.table("CombatSpells").get(entry.card, {})
	return profile.text(str(row.get("Name", entry.card))) + "\n" + profile.card_description(str(entry.card)) + "\n" + ELResources.describe("el2", model.value(entry), false)

class Surface extends Control:
	var view

	func _draw() -> void:
		view.draw_surface(self)

	func _gui_input(event: InputEvent) -> void:
		view.surface_input(event)

	func _get_tooltip(at_position: Vector2) -> String:
		return view.tooltip_at(at_position)
