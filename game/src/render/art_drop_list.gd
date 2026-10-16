class_name ELArtDropList
extends Control
## Second-game drop-down list on the original art (the inventory's
## specialisation list SpecPopUpDialog and the duel editor's EPDropDown1):
## one 26 px row per entry, drawn from the nine pieces of the list's
## "...TexturesCtrl": pieces 0..2 are the left, tiled middle and right strip of
## the row under the mouse, 3..5 those of the other rows, 6..8 the top, middle
## and bottom of the scroll column. At most eight rows are shown; a longer list
## gets the scroll column, the list's up/down arrows and the mouse wheel. Names
## start 10,5 inside a row, ink, the current entry.
## Rows are flat Buttons under the first child, so clicks and tooltips use the
## ordinary GUI path.
## The scroll column carries the original scroller (class, built in
## ): an 11x12 thumb from MULTIPLAYER_PANEL_8 (224,24)-(235,36)
## (static rect) placed at top + (track - thumb) * first / last
## (centred when nothing scrolls); dragging it snaps to the nearest
## position; a click on the track moves at most five rows
## towards the click.

signal chosen(index: int)

const ROW := 26.0
const VISIBLE := 8
const INK := Color8(0x99, 0x8c, 0x68)
const CURRENT_INK := Color8(0xd6, 0xbb, 0x88)
const TEXT_MARGIN := Vector2(10, 5)
const THUMB_SOURCE := Rect2(224, 24, 11, 12)
const PAGE := 5

var hover := -1
var first := 0
var current := -1
var rows_box: Control
var up: BaseButton
var down: BaseButton
var font: Font
## Row text: format word in both fills is
## face 0 bold at a 17 px cell, which outside the Japanese build is Arial
## Bold; a 17 px Arial cell is about a 15 px em.
var font_size := 15
var _strips: Array[Dictionary] = []
var _count := 0
## MULTIPLAYER_PANEL_8; without it no thumb is drawn.
var thumb_texture: Texture2D
var _drag := -1.0

## The thumb's sheet from the edition's InterfaceTextures table.
static func thumb_art(profile: ELProfile) -> Texture2D:
	for row: Dictionary in profile.table("InterfaceTextures").values():
		if row.get("Name", "") == "MULTIPLAYER_PANEL_8":
			return profile.texture("Interface/" + str(row.get("Path", "")).replace("\\", "/"))
	return null

## The original row face, Arial Bold, or the closest metric match installed.
static func row_font() -> SystemFont:
	var result := SystemFont.new()
	result.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	result.font_weight = 700
	return result

## `pieces` are cut parts ({texture, source}); they are ordered here as the
## row strips by x, then the scroll column by y.
func setup(pieces: Array, text_font: Font, up_button: BaseButton = null, down_button: BaseButton = null) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = text_font
	rows_box = Control.new()
	rows_box.name = "Rows"
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows_box)
	var ordered := pieces.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _order(a) < _order(b))
	for piece: Dictionary in ordered:
		if piece.get("texture") != null: _strips.append(piece)
	up = up_button
	down = down_button
	for button: BaseButton in [up, down]:
		if button == null: continue
		if button.get_parent() != null: button.get_parent().remove_child(button)
		add_child(button)
		button.hide()
	if up != null: up.pressed.connect(scroll.bind(-1))
	if down != null: down.pressed.connect(scroll.bind(1))
	mouse_exited.connect(func():
		hover = current
		queue_redraw())

static func _order(piece: Dictionary) -> Array:
	var source: Rect2 = piece.get("source", Rect2())
	return [1 if source.size.x > 10.0 else 0, source.position.y, source.position.x]

## Top-left and width from the list's Controls entry (its height follows the rows).
func place(design: Rect2) -> void:
	position = design.position
	size.x = design.size.x
	_arrange()

func fill(labels: Array, tooltips: Array = [], selected := -1) -> void:
	for child: Node in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	_count = labels.size()
	current = selected
	for index in _count:
		var option := Button.new()
		option.name = "Row%d" % index
		option.text = str(labels[index])
		option.flat = true
		option.clip_text = true
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.focus_mode = Control.FOCUS_NONE
		option.mouse_filter = Control.MOUSE_FILTER_PASS
		if index < tooltips.size(): option.tooltip_text = str(tooltips[index])
		for state_name: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var style := StyleBoxEmpty.new()
			style.content_margin_left = TEXT_MARGIN.x
			style.content_margin_top = TEXT_MARGIN.y
			option.add_theme_stylebox_override(state_name, style)
		if font != null: option.add_theme_font_override("font", font)
		option.add_theme_font_size_override("font_size", font_size)
		var ink := CURRENT_INK if index == current else INK
		for colour: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			option.add_theme_color_override(colour, ink)
		option.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		option.add_theme_constant_override("shadow_offset_x", 1)
		option.add_theme_constant_override("shadow_offset_y", 1)
		option.pressed.connect(func(): chosen.emit(index))
		option.mouse_entered.connect(func():
			hover = index
			queue_redraw())
		rows_box.add_child(option)
	# The current entry starts highlighted and scrolled into view.
	hover = current
	first = clampi(current - VISIBLE + 1, 0, _last_first()) if current >= 0 else 0
	_arrange()

func scrolling() -> bool:
	return _count > VISIBLE

func scroll(delta: int) -> void:
	first = clampi(first + delta, 0, _last_first())
	_arrange()

func row_button(index: int) -> Button:
	return rows_box.get_child(index) as Button if index >= 0 and index < rows_box.get_child_count() else null

func _gui_input(event: InputEvent) -> void:
	if not scrolling(): return
	if event is InputEventMouseMotion and _drag >= 0.0:
		var y := clampf(event.position.y - _drag, _track().position.y, _track().end.y - THUMB_SOURCE.size.y)
		var nearest := _nearest(y)
		if nearest != first: scroll(nearest - first)
		accept_event()
		return
	if not event is InputEventMouseButton: return
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag = -1.0
		return
	if not event.pressed: return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
	elif event.button_index == MOUSE_BUTTON_LEFT and thumb_texture != null and _track().has_point(event.position):
		var thumb := thumb_rect()
		if thumb.has_point(event.position): _drag = event.position.y - thumb.position.y
		else:
			# A track click pages towards the pointer, never past it.
			var aim := _nearest(event.position.y - THUMB_SOURCE.size.y * 0.5)
			if event.position.y >= thumb.end.y: scroll(mini(first + PAGE, maxi(aim, first)) - first)
			elif event.position.y < thumb.position.y: scroll(maxi(first - PAGE, mini(aim, first)) - first)
	else: return
	accept_event()

## The scroller's own rect, set by the list layout from the list's
## rect when it scrolls: (right - 15, top + 14) to (right - 5, bottom - 15).
func _track() -> Rect2:
	if _column() <= 0.0: return Rect2(size.x, 0, 0, 0)
	return Rect2(size.x - 15, 14, 10, maxf(0.0, size.y - 29))

## Thumb position for a first row.
func thumb_rect(at := -1) -> Rect2:
	var track := _track()
	var travel := track.size.y - THUMB_SOURCE.size.y
	var index := first if at < 0 else at
	var y := travel * 0.5 if _last_first() == 0 else travel * index / _last_first()
	# x is the scroller rect's left edge, so the 11 px thumb
	# overhangs its 10 px rect by one pixel on the right.
	return Rect2(track.position.x, track.position.y + floorf(y), THUMB_SOURCE.size.x, THUMB_SOURCE.size.y)

func _nearest(y: float) -> int:
	var best := 0
	for index in _last_first() + 1:
		if absf(thumb_rect(index).position.y - y) < absf(thumb_rect(best).position.y - y): best = index
	return best

func _last_first() -> int:
	return maxi(0, _count - VISIBLE)

func _column() -> float:
	return _strips[6].source.size.x if scrolling() and _strips.size() >= 9 else 0.0

func _arrange() -> void:
	size.y = ROW * mini(_count, VISIBLE)
	var width := size.x - _column()
	for index in rows_box.get_child_count():
		var option := rows_box.get_child(index) as Control
		if option == null: continue
		option.visible = index >= first and index < first + VISIBLE
		option.position = Vector2(0, (index - first) * ROW)
		option.size = Vector2(width, ROW)
	for button: BaseButton in [up, down]:
		if button != null: button.visible = scrolling()
	if scrolling():
		# The arrows sit at the right edge, 2 px inside the top and bottom.
		if up != null: up.position = Vector2(size.x - 17, 2)
		if down != null: down.position = Vector2(size.x - 17, size.y - down.size.y - 2)
	queue_redraw()

func _draw() -> void:
	var shown := mini(_count, VISIBLE)
	var column := _column()
	var width := size.x - column
	for slot in shown:
		var top := slot * ROW
		if _strips.size() < 6:
			draw_rect(Rect2(0, top, width, ROW), Color(0.05, 0.05, 0.04, 0.97))
		else:
			var base := 0 if first + slot == hover else 3
			var left: Dictionary = _strips[base]
			var middle: Dictionary = _strips[base + 1]
			var right: Dictionary = _strips[base + 2]
			var step: float = left.source.size.x
			draw_texture_rect_region(left.texture, Rect2(0, top, step, ROW), left.source)
			var x := step
			while x < width - step:
				var part := minf(step, width - step - x)
				draw_texture_rect_region(middle.texture, Rect2(x, top, part, ROW), Rect2(middle.source.position, Vector2(part, middle.source.size.y)))
				x += part
			draw_texture_rect_region(right.texture, Rect2(width - step, top, step, ROW), right.source)
		if column > 0.0:
			var piece: Dictionary = _strips[6 if slot == 0 else (8 if slot == shown - 1 else 7)]
			draw_texture_rect_region(piece.texture, Rect2(width, top, column, ROW), piece.source)
	if column > 0.0 and thumb_texture != null:
		draw_texture_rect_region(thumb_texture, thumb_rect(), THUMB_SOURCE)
