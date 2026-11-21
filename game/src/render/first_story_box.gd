class_name ELFirstStoryBox
extends Control
## The restored missions' speaker lines in the first game, drawn as the second
## game's TextDialog (ELSecondDialogueBox): a 512-wide box of translucent
## black with no frame, the 100x70 portrait at (30,30), the name with a colon
## at (145,30) and the text at (145,58) in tan Arial Bold, a 30-pixel right
## and bottom margin, and the close cross 4 pixels from the top-right corner.
## The box is centred, its top 50 pixels under the screen centre, raised so
## it ends 55 pixels above the bottom edge. The cross is drawn here: the
## second game's art is not part of the first game.
##
## A click on the box, Enter, Esc or Space closes it (`answered` "OK").
## Coordinates are the 1024x768 design scaled by the window height.
signal answered(answer: String)

const DESIGN_HEIGHT := 768.0
const WIDTH := ELSecondDialogueBox.WIDTH
const MARGIN := ELSecondDialogueBox.MARGIN
const PORTRAIT := ELSecondDialogueBox.PORTRAIT
const SPEAKER_TEXT := ELSecondDialogueBox.SPEAKER_TEXT
const SPEAKER_NAME := ELSecondDialogueBox.SPEAKER_NAME
const MIN_SPEAKER_HEIGHT := ELSecondDialogueBox.MIN_SPEAKER_HEIGHT
const BOTTOM_MARGIN := ELSecondDialogueBox.BOTTOM_MARGIN
const BELOW_CENTRE := ELSecondDialogueBox.BELOW_CENTRE
const BOTTOM_CLEAR := ELSecondDialogueBox.BOTTOM_CLEAR
const CLOSE_INSET := ELSecondDialogueBox.CLOSE_INSET
const TAN := ELSecondDialogueBox.TAN
const SHADE := ELSecondDialogueBox.SHADE
const TEXT_SIZE := ELSecondDialogueBox.TEXT_SIZE
const NAME_SIZE := ELSecondDialogueBox.NAME_SIZE
## The drawn close cross: its square and stroke.
const CLOSE_SIZE := 18.0
const CLOSE_STROKE := 2.0

var canvas: Control
var surface: Control
var portrait: TextureRect
var title: Label
var body: RichTextLabel
var close: Button
var box := Rect2()
var _factor := 1.0
var _font: Font

func _init() -> void:
	name = "FirstStoryBox"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ELArtDropList.row_font()
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	surface = Control.new()
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.draw.connect(_draw_surface)
	canvas.add_child(surface)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(portrait)
	title = Label.new()
	title.name = "Name"
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", NAME_SIZE)
	_shade(title, "font_color")
	canvas.add_child(title)
	body = RichTextLabel.new()
	body.name = "Text"
	body.bbcode_enabled = false
	body.scroll_active = false
	body.fit_content = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_override("normal_font", _font)
	body.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	_shade(body, "default_color")
	canvas.add_child(body)
	close = Button.new()
	close.name = "Close"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "focus"]: close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	close.draw.connect(_draw_close)
	close.mouse_entered.connect(close.queue_redraw)
	close.mouse_exited.connect(close.queue_redraw)
	close.pressed.connect(func(): answered.emit("OK"))
	canvas.add_child(close)
	hide()

func _shade(control: Control, color_name: String) -> void:
	control.add_theme_color_override(color_name, TAN)
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	control.add_theme_constant_override("shadow_offset_x", 1)
	control.add_theme_constant_override("shadow_offset_y", 1)

## Shows a speaker line: {title, text}, with the speaker's portrait (null
## for none).
func present(speech: Dictionary, face: Texture2D) -> void:
	title.text = str(speech.get("title", ""))
	if not title.text.is_empty() and not title.text.ends_with(":"): title.text += ":"
	body.text = str(speech.get("text", ""))
	portrait.texture = face
	show()
	layout()

## Enter, Esc and Space answer the line.
func key_answer(keycode: int) -> String:
	return "OK" if keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE] else ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		answered.emit("OK")

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if not key_answer(event.keycode).is_empty():
		get_viewport().set_input_as_handled()
		answered.emit("OK")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible: layout()

## Places the box in the parent's area (call after a resize as well).
func layout() -> void:
	if not visible or get_parent() == null: return
	var area: Vector2 = get_parent().size if get_parent() is Control else get_viewport_rect().size
	if area.y <= 0: return
	_factor = area.y / DESIGN_HEIGHT
	var design := area / _factor
	var text_width := WIDTH - MARGIN - SPEAKER_TEXT.x
	# Measured here: the label would size itself before it knows its width.
	var lines := _font.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, TEXT_SIZE, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var text_height := lines.y + 4.0
	body.position = SPEAKER_TEXT
	body.size = Vector2(text_width, text_height)
	var height := maxf(text_height + SPEAKER_TEXT.y, MIN_SPEAKER_HEIGHT) + BOTTOM_MARGIN
	portrait.position = PORTRAIT.position
	portrait.size = PORTRAIT.size
	portrait.visible = portrait.texture != null
	title.position = SPEAKER_NAME
	title.size = Vector2(WIDTH - MARGIN - SPEAKER_NAME.x, 26)
	close.position = Vector2(WIDTH - CLOSE_INSET.x - CLOSE_SIZE, CLOSE_INSET.y)
	var top := minf(design.y * 0.5 + BELOW_CENTRE, design.y - BOTTOM_CLEAR - height)
	box = Rect2(Vector2((design.x - WIDTH) * 0.5, top), Vector2(WIDTH, height))
	canvas.scale = Vector2(_factor, _factor)
	position = box.position * _factor
	size = box.size * _factor
	canvas.size = box.size
	surface.size = box.size
	surface.queue_redraw()

func _draw_surface() -> void:
	surface.draw_rect(Rect2(Vector2.ZERO, box.size), SHADE)

func _draw_close() -> void:
	var ink := TAN.lightened(0.25) if close.is_hovered() else TAN
	var inset := 4.0
	var square := Rect2(Vector2.ZERO, close.size)
	close.draw_rect(square, Color(0, 0, 0, 0.35))
	close.draw_rect(square, ink, false, 1.0)
	close.draw_line(Vector2(inset, inset), close.size - Vector2(inset, inset), ink, CLOSE_STROKE, true)
	close.draw_line(Vector2(close.size.x - inset, inset), Vector2(inset, close.size.y - inset), ink, CLOSE_STROKE, true)
