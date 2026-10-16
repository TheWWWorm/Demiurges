class_name ELSecondDialogueBox
extends Control
## Second-game script boxes on the original interface.
##
## TextDialog (CTextDialogA6): a 512-wide box filled with the translucent
## SOLID_BLACK_A texture, no frame. A speaker box shows the 100x70 portrait at
## (30,30), the name at (145,30) and the text at (145,58); a box without a
## speaker starts its text at (30,30). The text area keeps a 30-pixel right
## margin. A one-answer box has the Close cross (TextDialogCloseBtn) 4 pixels
## from the top-right corner and a 30-pixel bottom margin; a question has
## Yes/No (TextDialogOkBtn/CancelBtn) or Move/Explore (TextDialogMoveBtn/
## ExploreBtn) 15 pixels under the text, 10 pixels either side of the centre,
## 20 pixels above the bottom. The box is centred horizontally, its top 50
## pixels under the screen centre, raised so its body ends 55 pixels above the
## bottom edge. Text and name are tan.
##
## MessageBox: the text wrapped at 512 pixels, the MBOK (and MBCancel) art
## buttons 10 pixels under it; the panel is that content grown by 15 pixels on
## every side and drawn with the frame of WORLD_SYMBOLS_MAP (7-pixel border,
## 30-pixel corners, opaque fill). It is centred on the screen and
## moved by the script's (dx, dy).
##
## Loot (the Messages panel, CMessage, filled): the title
## (15,15), then one 65-pixel row per item from y 63: the 50x50 picture at
## x 20 inside a 60x60 slot frame (A6-Int-Message 192,123) and the name at
## (85, y+17). The panel is that content plus a 15-pixel right margin, the OK
## (MessagesOK) centred 20 pixels under it and 15 below; the same frame as the
## MessageBox, centred on the screen. Esc and Space answer OK.
##
## Coordinates are the 1024x768 design scaled by the window height, as the
## second-game panels are.
signal answered(answer: String)

const DESIGN_HEIGHT := 768.0
const WIDTH := 512.0
const MARGIN := 30.0
## Speaker portrait (100x70 cell of HEROES_n) and the name/text column.
const PORTRAIT := Rect2(30, 30, 100, 70)
const SPEAKER_TEXT := Vector2(145, 58)
const SPEAKER_NAME := Vector2(145, 30)
const MIN_SPEAKER_HEIGHT := 100.0
const BOTTOM_MARGIN := 30.0
const BUTTON_GAP := 15.0
const BUTTON_BOTTOM := 20.0
const BUTTON_SPREAD := 10.0
const CLOSE_INSET := Vector2(4, 5)
## Lower-middle placement: top at centre + 50, body clear of the bottom 55.
const BELOW_CENTRE := 50.0
const BOTTOM_CLEAR := 55.0
## The portrait the original draws for a speaker that is not a hero.
const UNKNOWN_FACE := 205
const TAN := Color8(0xd6, 0xbb, 0x88)
const SHADE := Color(0, 0, 0, 136.0 / 255.0)
## MessageBox: text wrap width, gap above the buttons, frame growth.
const MESSAGE_WIDTH := 512.0
const MESSAGE_GAP := 10.0
const MESSAGE_GROW := 15.0
const MESSAGE_SPREAD := 8.0
## WORLD_SYMBOLS_MAP frame pieces.
const FRAME_BORDER := 7.0
const FRAME_CORNER := 30.0
const FRAME_FILL := Color8(0x22, 0x22, 0x22)
const TEXT_SIZE := 16
const NAME_SIZE := 18
const MESSAGE_SIZE := 17
const CAPTION_SIZE := 14
## Loot rows.
const LOOT_TITLE := Vector2(15, 15)
const LOOT_FIRST_ROW := 63.0
const LOOT_ROW := 65.0
## The artifact-created panel puts its single row higher.
const CREATED_FIRST_ROW := 47.0
const LOOT_ICON_X := 20.0
const LOOT_ICON := 50.0
const LOOT_SLOT_SOURCE := Rect2(192, 123, 60, 60)
const LOOT_NAME := Vector2(85, 17)
const LOOT_MARGIN := 15.0
const LOOT_BUTTON_GAP := 20.0

var hud: ELSecondAdventureHud
var canvas: Control
var surface: Control
var portrait: TextureRect
var title: Label
var body: RichTextLabel
var buttons: Dictionary = {}
var captions: Dictionary = {}
## "text" (TextDialog), "message" (MessageBox) or "loot" (Messages panel).
var style := "text"
## Loot rows: {icon: Texture2D, name: String}; the name labels go with them.
var loot: Array = []
var loot_names: Array[Label] = []
var loot_top := LOOT_FIRST_ROW
var _slot: Texture2D
var speaker_box := false
## Active answer buttons: the first answers OK, the second Cancel.
var accept: BaseButton
var decline: BaseButton
var question := false
var box := Rect2()
var offset := Vector2.ZERO
var _frame: Texture2D
var _factor := 1.0

func setup(source: ELSecondAdventureHud) -> void:
	hud = source
	name = "SecondDialogueBox"
	mouse_filter = Control.MOUSE_FILTER_STOP
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	surface = Control.new()
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.draw.connect(_draw_surface)
	canvas.add_child(surface)
	_frame = _texture("WORLD_SYMBOLS_MAP")
	_slot = _texture("A6-Int-Message")
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
	_ink(title, hud.face_bold, NAME_SIZE)
	canvas.add_child(title)
	body = RichTextLabel.new()
	body.name = "Text"
	body.bbcode_enabled = false
	body.scroll_active = false
	body.fit_content = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_override("normal_font", hud.face)
	body.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	body.add_theme_color_override("default_color", TAN)
	body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	body.add_theme_constant_override("shadow_offset_x", 1)
	body.add_theme_constant_override("shadow_offset_y", 1)
	canvas.add_child(body)
	for control: String in ["TextDialogCloseBtn", "TextDialogOkBtn", "TextDialogCancelBtn", "TextDialogMoveBtn", "TextDialogExploreBtn", "MBOK", "MBCancel", "MessagesOK"]:
		var button := ELSecondNotebookView.ArtButton.make(hud, control)
		var tip := hud.tooltip_of(control)
		# The message box buttons carry only tooltips; the first game's captions
		# do not apply here.
		button.tooltip_text = tip
		button.accessibility_name = tip
		button.hide()
		canvas.add_child(button)
		buttons[control] = button
		var answer := "CANCEL" if control in ["TextDialogCancelBtn", "TextDialogExploreBtn", "MBCancel"] else "OK"
		button.pressed.connect(func(): answered.emit(answer))
		var key := str(hud._controls.get(control, {}).get("Text", ""))
		if not key.is_empty():
			var label := Label.new()
			label.name = "Caption"
			label.text = hud.text(key)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.clip_text = true
			_ink(label, hud.face_bold, CAPTION_SIZE)
			label.size = button.size
			button.add_child(label)
			captions[control] = label
	hide()

func _texture(texture_name: String) -> Texture2D:
	var path: String = hud._paths.get(texture_name, "")
	return hud.profile.texture(path) if not path.is_empty() else null

func _ink(label: Label, font: Font, font_size: int) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TAN)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

## Shows a director dialogue: {box, speaker_box, question, move, title, text,
## actor, offset}. `state` resolves the speaker's portrait.
func present(speech: Dictionary, state: ELAdventureSession) -> void:
	style = str(speech.get("box", "text"))
	if style not in ["message", "loot"]: style = "text"
	for label: Label in loot_names: label.queue_free()
	loot_names.clear()
	loot = Array(speech.get("items", [])).filter(func(row: Variant) -> bool: return row is Dictionary).duplicate(true) if style == "loot" else []
	loot_top = CREATED_FIRST_ROW if speech.get("created", false) else LOOT_FIRST_ROW
	for item: Dictionary in loot:
		# Queued boxes carry a card code (or a generated artifact's own icon
		# index); the picture is resolved here.
		if not item.get("icon") is Texture2D:
			var index := int(item.get("icon_index", -1))
			if index >= 0: item.icon = state.map.profile.icon_at(index)
			elif item.has("card"): item.icon = state.map.profile.card_icon(str(item.card))
		var label := Label.new()
		label.name = "LootName"
		label.text = str(item.get("name", ""))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ink(label, hud.face, MESSAGE_SIZE)
		canvas.add_child(label)
		loot_names.append(label)
	question = bool(speech.get("question", false))
	# Older saves carry no style: a queued line (with a text id) is a speaker box.
	speaker_box = style == "text" and bool(speech.get("speaker_box", not str(speech.get("text_id", "")).is_empty()))
	var shift: Array = speech.get("offset", [0.0, 0.0])
	offset = Vector2(float(shift[0]), float(shift[1])) if shift.size() > 1 else Vector2.ZERO
	body.text = str(speech.get("text", ""))
	var actor := state.object(int(speech.get("actor", -1))) if speech.has("actor") else {}
	var hero := actor if not actor.is_empty() and actor.get("type") == "hero" else {}
	title.text = str(speech.get("title", "")) if not hero.is_empty() else hud.text("T_UNKNOWN_HERO_NAME")
	if title.text.is_empty() and not hero.is_empty(): title.text = str(hero.get("name", ""))
	var face := UNKNOWN_FACE
	if not hero.is_empty(): face = int(hud._art.resolve(hero).get("row", {}).get("Face", UNKNOWN_FACE))
	portrait.texture = state.map.profile.portrait(face) if speaker_box else null
	for button: BaseButton in buttons.values(): button.hide()
	if style == "loot":
		accept = buttons.MessagesOK
		decline = null
		question = false
	elif style == "message":
		accept = buttons.MBOK
		decline = buttons.MBCancel if question else null
	elif not question:
		accept = buttons.TextDialogCloseBtn
		decline = null
	elif bool(speech.get("move", false)):
		accept = buttons.TextDialogMoveBtn
		decline = buttons.TextDialogExploreBtn
	else:
		accept = buttons.TextDialogOkBtn
		decline = buttons.TextDialogCancelBtn
	accept.show()
	if decline != null: decline.show()
	show()
	layout()

## The answer a key gives, or "" (TextDialog, MessageBox
## ): one-answer boxes take Enter, Esc and Space; a question takes
## Enter for the first button and Esc for the second.
func key_answer(keycode: int) -> String:
	# The loot panel binds only Esc and Space to its OK.
	if style == "loot": return "OK" if keycode in [KEY_ESCAPE, KEY_SPACE] else ""
	if not question:
		return "OK" if keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE] else ""
	if keycode in [KEY_ENTER, KEY_KP_ENTER]: return "OK"
	if keycode == KEY_ESCAPE: return "CANCEL"
	return ""

## Places the box in the parent's area (call after a resize as well).
func layout() -> void:
	if not visible or get_parent() == null: return
	var area: Vector2 = get_parent().size if get_parent() is Control else get_viewport_rect().size
	if area.y <= 0: return
	_factor = area.y / DESIGN_HEIGHT
	var design_width := area.x / _factor
	if style == "message": _layout_message(design_width)
	elif style == "loot": _layout_loot(design_width)
	else: _layout_text(design_width)
	canvas.scale = Vector2(_factor, _factor)
	canvas.position = Vector2.ZERO
	position = box.position * _factor
	size = box.size * _factor
	# Children are laid out relative to the box.
	canvas.size = box.size
	surface.size = box.size
	surface.queue_redraw()

func _layout_text(design_width: float) -> void:
	var origin := SPEAKER_TEXT if speaker_box else Vector2(MARGIN, MARGIN)
	var text_width := WIDTH - MARGIN - origin.x
	body.position = origin
	body.size = Vector2(text_width, 0)
	body.custom_minimum_size = Vector2(text_width, 0)
	var text_height := _text_height(text_width, TEXT_SIZE)
	body.size = Vector2(text_width, text_height)
	var content := text_height + origin.y
	if speaker_box: content = maxf(content, MIN_SPEAKER_HEIGHT)
	portrait.visible = speaker_box
	title.visible = speaker_box
	portrait.position = PORTRAIT.position
	portrait.size = PORTRAIT.size
	title.position = SPEAKER_NAME
	title.size = Vector2(WIDTH - MARGIN - SPEAKER_NAME.x, 26)
	var height := content
	if not question:
		height += BOTTOM_MARGIN
		accept.position = Vector2(WIDTH - accept.size.x - CLOSE_INSET.x, CLOSE_INSET.y)
	var top := DESIGN_HEIGHT * 0.5 + BELOW_CENTRE
	if top + height > DESIGN_HEIGHT - BOTTOM_CLEAR: top = DESIGN_HEIGHT - BOTTOM_CLEAR - height
	if question:
		var row := content + BUTTON_GAP
		accept.position = Vector2(WIDTH * 0.5 - accept.size.x - BUTTON_SPREAD, row)
		decline.position = Vector2(WIDTH * 0.5 + BUTTON_SPREAD, row)
		height = row + accept.size.y + BUTTON_BOTTOM
	box = Rect2(Vector2(roundf((design_width - WIDTH) * 0.5), roundf(top)), Vector2(WIDTH, height))

func _layout_message(design_width: float) -> void:
	portrait.visible = false
	title.visible = false
	var font: Font = hud.face
	var natural := font.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_CENTER, MESSAGE_WIDTH, MESSAGE_SIZE)
	var text_width := clampf(ceilf(natural.x) + 2.0, 60.0, MESSAGE_WIDTH)
	body.add_theme_font_size_override("normal_font_size", MESSAGE_SIZE)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.size = Vector2(text_width, 0)
	var text_height := _text_height(text_width, MESSAGE_SIZE)
	var button_height := accept.size.y
	var content := Vector2(maxf(text_width, (accept.size.x + MESSAGE_SPREAD) * 2.0), text_height + MESSAGE_GAP + button_height)
	var grow := Vector2(MESSAGE_GROW, MESSAGE_GROW)
	body.position = grow + Vector2((content.x - text_width) * 0.5, 0)
	body.size = Vector2(text_width, text_height)
	var row := grow.y + text_height + MESSAGE_GAP
	if decline == null: accept.position = Vector2(grow.x + (content.x - accept.size.x) * 0.5, row)
	else:
		accept.position = Vector2(grow.x + content.x * 0.5 - accept.size.x - MESSAGE_SPREAD, row)
		decline.position = Vector2(grow.x + content.x * 0.5 + MESSAGE_SPREAD, row)
	var centre := Vector2(design_width * 0.5, DESIGN_HEIGHT * 0.5) + offset
	var outer := content + grow * 2.0
	box = Rect2((centre - outer * 0.5).round(), outer)

func _layout_loot(design_width: float) -> void:
	portrait.visible = false
	title.visible = false
	var font: Font = hud.face
	body.add_theme_font_size_override("normal_font_size", MESSAGE_SIZE)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# The original title has its own line break; nothing else wraps.
	var title_size := font.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, -1, MESSAGE_SIZE)
	body.position = LOOT_TITLE
	body.size = Vector2(ceilf(title_size.x) + 2.0, 0)
	body.size = Vector2(body.size.x, _text_height(body.size.x, MESSAGE_SIZE))
	var content := Rect2(0, 0, 1, 1).merge(Rect2(body.position, body.size))
	for index in loot.size():
		var y := loot_top + LOOT_ROW * index
		content = content.merge(Rect2(LOOT_ICON_X - 5.0, y - 5.0, LOOT_ICON + 10.0, LOOT_ICON + 10.0))
		var label := loot_names[index]
		label.position = Vector2(LOOT_NAME.x, y + LOOT_NAME.y)
		label.size = Vector2(ceilf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, MESSAGE_SIZE).x) + 2.0, 0)
		label.reset_size()
		content = content.merge(Rect2(label.position, label.size))
	content.size.x += LOOT_MARGIN
	accept.position = Vector2(roundf(content.size.x * 0.5 - accept.size.x * 0.5), content.end.y + LOOT_BUTTON_GAP)
	content = content.merge(Rect2(accept.position, accept.size))
	content.size.y += LOOT_MARGIN
	var centre := Vector2(design_width * 0.5, DESIGN_HEIGHT * 0.5) + offset
	box = Rect2((centre - content.size * 0.5).round(), content.size)

func _text_height(width: float, font_size: int) -> float:
	body.add_theme_font_size_override("normal_font_size", font_size)
	if style == "text": body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.size = Vector2(width, 0)
	var measured := float(body.get_content_height())
	var estimate := hud.face.get_multiline_string_size(body.text, body.horizontal_alignment, width, font_size).y
	return ceilf(maxf(measured, estimate))

func _draw_surface() -> void:
	var rect := Rect2(Vector2.ZERO, box.size)
	if style == "text":
		surface.draw_rect(rect, SHADE)
		return
	_draw_frame(rect)
	for index in loot.size():
		var y := loot_top + LOOT_ROW * index
		if _slot != null: surface.draw_texture_rect_region(_slot, Rect2(LOOT_ICON_X - 5.0, y - 5.0, LOOT_ICON + 10.0, LOOT_ICON + 10.0), LOOT_SLOT_SOURCE)
		var icon: Variant = loot[index].get("icon")
		if icon is Texture2D: surface.draw_texture_rect(icon, Rect2(LOOT_ICON_X, y, LOOT_ICON, LOOT_ICON), false)

## WORLD_SYMBOLS_MAP (134..256): corners 30x30, 7-pixel border strips cut from
## the 60-pixel edge tiles, and the opaque fill inside the border.
func _draw_frame(rect: Rect2) -> void:
	draw_world_frame(surface, _frame, rect)

static func draw_world_frame(surface: CanvasItem, _frame: Texture2D, rect: Rect2) -> void:
	var inner := rect.grow(-FRAME_BORDER)
	surface.draw_rect(inner, FRAME_FILL)
	if _frame == null:
		surface.draw_rect(rect, Color("8a6d45"), false, 2.0)
		return
	var corner := FRAME_CORNER
	var span := 60.0
	# Edges, tiled between the corners.
	var x := rect.position.x + corner
	while x < rect.end.x - corner:
		var w := minf(span, rect.end.x - corner - x)
		surface.draw_texture_rect_region(_frame, Rect2(x, rect.position.y, w, FRAME_BORDER), Rect2(165, 134, w, FRAME_BORDER))
		surface.draw_texture_rect_region(_frame, Rect2(x, rect.end.y - FRAME_BORDER, w, FRAME_BORDER), Rect2(165, 256 - FRAME_BORDER, w, FRAME_BORDER))
		x += span
	var y := rect.position.y + corner
	while y < rect.end.y - corner:
		var h := minf(span, rect.end.y - corner - y)
		surface.draw_texture_rect_region(_frame, Rect2(rect.position.x, y, FRAME_BORDER, h), Rect2(134, 165, FRAME_BORDER, h))
		surface.draw_texture_rect_region(_frame, Rect2(rect.end.x - FRAME_BORDER, y, FRAME_BORDER, h), Rect2(256 - FRAME_BORDER, 165, FRAME_BORDER, h))
		y += span
	surface.draw_texture_rect_region(_frame, Rect2(rect.position, Vector2(corner, corner)), Rect2(134, 134, corner, corner))
	surface.draw_texture_rect_region(_frame, Rect2(Vector2(rect.end.x - corner, rect.position.y), Vector2(corner, corner)), Rect2(256 - corner, 134, corner, corner))
	surface.draw_texture_rect_region(_frame, Rect2(Vector2(rect.position.x, rect.end.y - corner), Vector2(corner, corner)), Rect2(134, 256 - corner, corner, corner))
	surface.draw_texture_rect_region(_frame, Rect2(rect.end - Vector2(corner, corner), Vector2(corner, corner)), Rect2(256 - corner, 256 - corner, corner, corner))
