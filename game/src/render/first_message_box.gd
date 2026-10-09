class_name ELFirstMessageBox
extends Control
## First-game MessageBox (Controls "MessageBox": MBText, MBOK, MBCancel) over
## the adventure. The text (font 17) wraps at 512 px; the box is the text plus
## 10 px each side and the button row, centred on the screen. Mode 0 shows OK
## alone, mode 1 OK and Cancel 15 px either side of the centre, mode 2 Cancel
## alone. Enter answers OK (modes 0 and 1); Escape answers OK in mode 0 and
## Cancel otherwise. The frame is drawn from the TOOLTIP sheet: 50 px
## background tiles over the box grown by 36/24 px and rounded down to whole
## tiles, 8 px edges and corners, and a SYMBOLS shade offset by 5 px.
##
## Map notices add pictures to the box (section 15): an object, artifact or
## global spell picture centred above the text, resource rows (a framed
## resource icon and its amount, 28 px apart) under it, and a framed resource
## icon in place of each "@1", "@2"... marker in the text. Building messages
## add a row of item pictures (a Master's skill icon) centred under the text,
## 10 px apart, above the button row.
signal answered(accepted: bool)
const OK_ONLY := 0
const OK_CANCEL := 1
const CANCEL_ONLY := 2
const MAX_TEXT := 512.0
const MARGIN := 10.0
const TILE := 50.0
const EDGE := 8.0
const TEXT := Color("f2eee4")
const FONT_SIZE := 15
## Resource icons: BUILDING_SCREEN_1 cells of 23 px from (0, 233), framed by
## the TOOLTIP cell (9, 20, 26, 27); index 7 is ether.
const RESOURCE_CELL := 23.0
const RESOURCE_FRAME := Rect2(9, 20, 26, 27)
const ROW_STEP := 28.0
const INLINE := "@1"

var hud: ELAdventureHud
var mode := OK_ONLY
var body: Label
var buttons: Dictionary = {}
## Box rectangle in 1024x768 design units.
var box := Rect2()
var canvas: Control
var _frame_texture: Texture2D
var _shade: Texture2D
var _resources: Texture2D
## Drawn extras in design units: [{texture, rect, source?}].
var pieces: Array[Dictionary] = []
var picture_rect := Rect2()
var amount_labels: Array[Label] = []
var _placeholder := 0
## Item row pictures in design units.
var item_rects: Array[Rect2] = []
const ITEM_GAP := 10.0

## The resource icon cell of BUILDING_SCREEN_1 for a resource index (7 ether).
static func resource_index(kind: String) -> int:
	return 7 if kind == "Ether" else ELResources.ORIGINAL.find(kind)

## extras: "picture" (Texture2D, drawn at its own size above the text),
## "rows" ([[resource kind, amount], ...]) and "inline" (resource kind drawn
## in place of the text's "@1"; an Array names the kinds for "@1", "@2"...)
## and "items" (Texture2D pictures in a row under the text).
func setup(panel: ELAdventureHud, text: String, box_mode := OK_ONLY, extras: Dictionary = {}) -> void:
	hud = panel
	mode = box_mode
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var profile := hud.profile
	_frame_texture = profile.texture(str(hud._paths.get("TOOLTIP", "")))
	_shade = profile.texture(str(hud._paths.get("SYMBOLS", "")))
	_resources = profile.texture(str(hud._paths.get("BUILDING_SCREEN_1", "")))
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_frame)
	add_child(canvas)
	var font: Font = hud._bold
	# Inline icons take the place of their markers: spaces as wide as the frame.
	var inline_value: Variant = extras.get("inline", "")
	var inline_kinds: Array = inline_value if inline_value is Array else ([inline_value] if not str(inline_value).is_empty() else [])
	var markers: Array = []
	if not inline_kinds.is_empty():
		var space := maxf(1.0, font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
		_placeholder = int(ceilf((RESOURCE_FRAME.size.x + 6) / space))
		for index in inline_kinds.size():
			var at := text.find("@%d" % (index + 1))
			if at < 0 or str(inline_kinds[index]).is_empty(): continue
			text = text.substr(0, at) + " ".repeat(_placeholder) + text.substr(at + 2)
			markers.append([at, str(inline_kinds[index])])
	var width := minf(MAX_TEXT, ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) + 2)
	var extent := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, FONT_SIZE)
	var text_size := Vector2(width, minf(MAX_TEXT, ceilf(extent.y)))
	body = Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_theme_font_override("font", font)
	body.add_theme_font_size_override("font_size", FONT_SIZE)
	body.add_theme_color_override("font_color", TEXT)
	body.add_theme_constant_override("line_spacing", 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sized before it enters the tree: a wrapping label first laid out at
	# zero width would keep the height of one character per line.
	body.size = text_size
	var names: Array = [["MBOK"], ["MBOK", "MBCancel"], ["MBCancel"]][mode]
	var button_size := Vector2.ZERO
	for control: String in names:
		var button := ELAdventureHud.CutButton.from_rows(hud, control, Vector2.ZERO)
		button.place(Vector2.ZERO)
		button.focus_mode = Control.FOCUS_NONE
		# The first game's captions CtrlMBOK/CtrlMBCancel are empty; the art
		# carries the tick and cross (as in the front-end MessageBox).
		button.tooltip_text = "OK" if control == "MBOK" else "Отмена"
		button.pressed.connect(_answer.bind(control == "MBOK"))
		canvas.add_child(button)
		buttons[control] = button
		button_size = button_size.max(button.size)
	var picture: Texture2D = extras.get("picture")
	var rows: Array = extras.get("rows", [])
	var items: Array[Texture2D] = []
	for item: Variant in extras.get("items", []):
		if item is Texture2D: items.append(item)
	var items_size := Vector2.ZERO
	for item: Texture2D in items:
		items_size = Vector2(items_size.x + item.get_size().x + (ITEM_GAP if items_size.x > 0 else 0.0), maxf(items_size.y, item.get_size().y))
	# The picture sits directly above the text and the box grows up to it.
	var top := picture.get_size().y - MARGIN if picture != null else 0.0
	# Rows: the last amount label ends 21 px below its row, and OK sits 10 px under it.
	var below := (5 + ROW_STEP * (rows.size() - 1) + 16) if not rows.is_empty() else 0.0
	# Items: 5 px under the text, the buttons 10 px under them.
	if not items.is_empty(): below += 5 + items_size.y
	var size_box := Vector2(maxf(maxf(text_size.x, items_size.x), picture.get_size().x if picture != null else 0.0) + 2 * MARGIN, top + text_size.y + below + button_size.y + 30)
	var screen := Vector2(1024 + hud.right_shift, 768)
	box = Rect2(((screen - size_box) * 0.5).floor(), size_box)
	body.position = box.position + Vector2(MARGIN + floorf((size_box.x - 2 * MARGIN - text_size.x) * 0.5), MARGIN + top)
	canvas.add_child(body)
	body.size = text_size
	if picture != null:
		picture_rect = Rect2(body.position + Vector2(floorf((text_size.x - picture.get_size().x) * 0.5), -picture.get_size().y), picture.get_size())
		pieces.append({"texture": picture, "rect": picture_rect})
	for index in rows.size():
		var at := body.position + Vector2(20, text_size.y + 5 + ROW_STEP * index)
		_resource_icon(at, str(rows[index][0]))
		var amount := Label.new()
		amount.text = str(int(rows[index][1]))
		amount.add_theme_font_override("font", font)
		amount.add_theme_font_size_override("font_size", FONT_SIZE)
		amount.add_theme_color_override("font_color", TEXT)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount.position = at + Vector2(30, 6 - 4)
		canvas.add_child(amount)
		amount_labels.append(amount)
	for marker: Array in markers: _place_inline(font, str(marker[1]), text_size, int(marker[0]))
	if not items.is_empty():
		var x := box.position.x + floorf((size_box.x - items_size.x) * 0.5)
		var y := body.position.y + text_size.y + 5
		for item: Texture2D in items:
			var rect := Rect2(Vector2(x, y), item.get_size())
			item_rects.append(rect)
			pieces.append({"texture": item, "rect": rect})
			x += item.get_size().x + ITEM_GAP
	var row := body.position.y + text_size.y + 10 + below
	var middle := box.position.x + MARGIN + floorf(text_size.x * 0.5)
	match mode:
		OK_ONLY: buttons.MBOK.position = Vector2(box.position.x + MARGIN + floorf((text_size.x - buttons.MBOK.size.x) * 0.5), row)
		OK_CANCEL:
			buttons.MBOK.position = Vector2(middle - 15 - buttons.MBOK.size.x, row)
			buttons.MBCancel.position = Vector2(middle + 15, row)
		CANCEL_ONLY: buttons.MBCancel.position = Vector2(box.position.x + MARGIN + floorf((text_size.x - buttons.MBCancel.size.x) * 0.5), row)
	if size_box.x > text_size.x + 2 * MARGIN:
		for button: Control in buttons.values(): button.position.x += floorf((size_box.x - 2 * MARGIN - text_size.x) * 0.5)
	resized.connect(_layout)
	_layout()

## A framed resource icon with its top-left corner at `at`.
func _resource_icon(at: Vector2, kind: String) -> void:
	var index := resource_index(kind)
	if _frame_texture != null: pieces.append({"texture": _frame_texture, "rect": Rect2(at, RESOURCE_FRAME.size), "source": RESOURCE_FRAME})
	if _resources != null and index >= 0: pieces.append({"texture": _resources, "rect": Rect2(at + Vector2(2, 2), Vector2(RESOURCE_CELL, RESOURCE_CELL)), "source": Rect2(index * RESOURCE_CELL, 233, RESOURCE_CELL, RESOURCE_CELL)})

## The inline icon over the spaces that replaced "@1" (the first line that
## holds them; centred lines as the label draws them).
func _place_inline(font: Font, kind: String, text_size: Vector2, marker: int) -> void:
	var paragraph := TextParagraph.new()
	paragraph.add_string(body.text, font, FONT_SIZE)
	paragraph.width = text_size.x
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var y := 0.0
	for line in paragraph.get_line_count():
		var span := paragraph.get_line_range(line)
		var height := paragraph.get_line_size(line).y
		if marker >= span.x and marker < span.y:
			var line_text := body.text.substr(span.x, span.y - span.x)
			var line_width := font.get_string_size(line_text.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var x := floorf((text_size.x - line_width) * 0.5) + font.get_string_size(body.text.substr(span.x, marker - span.x), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var offset := floorf((text_size.y - paragraph.get_size().y) * 0.5)
			# Centred in the spaces that replaced the marker.
			var gap := font.get_string_size(" ".repeat(_placeholder), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			_resource_icon(body.position + Vector2(x + floorf((gap - RESOURCE_FRAME.size.x) * 0.5), offset + y + floorf((height - RESOURCE_FRAME.size.y) * 0.5)), kind)
			return
		y += height

func _layout() -> void:
	if hud == null: return
	canvas.scale = Vector2(hud.scale_factor, hud.scale_factor)
	canvas.size = Vector2(1024 + hud.right_shift, 768)
	canvas.queue_redraw()

## Interior of the frame: the box grown by 36/24 px, rounded down to whole
## tiles and centred on it.
func interior() -> Rect2:
	return frame_interior(box)

static func frame_interior(area: Rect2) -> Rect2:
	var grown := area.size + Vector2(72, 48)
	var tiles := (grown / TILE).floor() * TILE
	var rest := grown - tiles
	return Rect2(area.position - Vector2(36, 24) + (rest * 0.5).floor(), tiles)

func _draw_frame() -> void:
	draw_frame(canvas, _frame_texture, _shade, box)
	for piece: Dictionary in pieces:
		if piece.has("source"): canvas.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
		else: canvas.draw_texture_rect(piece.texture, piece.rect, false)

## The first game's window frame around `area` from the TOOLTIP sheet: 50 px
## background tiles, 8 px edges and corners and the SYMBOLS shade at +5 px.
static func draw_frame(item: CanvasItem, frame_texture: Texture2D, shade: Texture2D, area: Rect2) -> void:
	if frame_texture == null: return
	var inner := frame_interior(area)
	var outer := inner.grow(EDGE)
	# The shade is the SYMBOLS swatch tinted.
	if shade != null: item.draw_texture_rect_region(shade, Rect2(outer.position + Vector2(5, 5), outer.size), Rect2(225, 45, 10, 10), Color(0, 0, 0, 0xbf / 255.0))
	var columns := int(inner.size.x / TILE)
	var lines := int(inner.size.y / TILE)
	for column in columns:
		for line in lines: item.draw_texture_rect_region(frame_texture, Rect2(inner.position + Vector2(column, line) * TILE, Vector2(TILE, TILE)), Rect2(150, 50, 50, 50))
	var corners := {Vector2(0, 0): outer.position, Vector2(10, 0): Vector2(inner.end.x, outer.position.y), Vector2(0, 10): Vector2(outer.position.x, inner.end.y), Vector2(10, 10): inner.end}
	for source: Vector2 in corners: item.draw_texture_rect_region(frame_texture, Rect2(corners[source], Vector2(EDGE, EDGE)), Rect2(source, Vector2(EDGE, EDGE)))
	for column in columns:
		var x := inner.position.x + column * TILE
		item.draw_texture_rect_region(frame_texture, Rect2(x, outer.position.y, TILE, EDGE), Rect2(20, 0, 50, 8))
		item.draw_texture_rect_region(frame_texture, Rect2(x, inner.end.y, TILE, EDGE), Rect2(20, 9, 50, 8))
	for line in lines:
		var y := inner.position.y + line * TILE
		item.draw_texture_rect_region(frame_texture, Rect2(outer.position.x, y, EDGE, TILE), Rect2(71, 0, 8, 50))
		item.draw_texture_rect_region(frame_texture, Rect2(inner.end.x, y, EDGE, TILE), Rect2(80, 0, 8, 50))

## A horizontal rule across the frame of `area` at height `y`: 50 px pieces
## (TOOLTIP 0,58) over the frame's tiled width, 8 px caps (0,67 / 9,67) on the
## frame edges, 8 px high from y - 4.
static func draw_rule(item: CanvasItem, frame_texture: Texture2D, area: Rect2, y: float) -> void:
	if frame_texture == null: return
	var inner := frame_interior(area)
	var top := y - 4.0
	for column in int(inner.size.x / TILE): item.draw_texture_rect_region(frame_texture, Rect2(inner.position.x + column * TILE, top, TILE, EDGE), Rect2(0, 58, 50, 8))
	item.draw_texture_rect_region(frame_texture, Rect2(inner.position.x - EDGE, top, EDGE, EDGE), Rect2(0, 67, 8, 8))
	item.draw_texture_rect_region(frame_texture, Rect2(inner.end.x, top, EDGE, EDGE), Rect2(9, 67, 8, 8))

func _answer(accepted: bool) -> void:
	answered.emit(accepted)

## Enter answers OK where shown; Escape answers OK alone, else Cancel.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo: return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and mode != CANCEL_ONLY:
		get_viewport().set_input_as_handled()
		_answer(true)
	elif event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_answer(mode == OK_ONLY)
