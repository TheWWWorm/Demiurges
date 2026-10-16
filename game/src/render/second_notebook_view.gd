class_name ELSecondNotebookView
extends Control
## Second-game Notebook screen (CNotebookScreen) on the original art: the
## event list with its filter and current-mission checkbox on the left; the
## selected entry's day, kind, portrait, minimap and phrase text or battle
## record on the right. Layout from the Controls/CutParts registries (panel
## "Notebook", shift 112,14 at 1024x768) and the positions read
## (phrase) and (battle).
signal closed
const PANEL := "Notebook"
const ROWS := 16
const ROW_HEIGHT := 26.0
const TAN := Color8(0xd6, 0xbb, 0x88)
const WHITE := Color(1, 1, 1)
const FILTERS := [ELSecondNotebook.FILTER_ALL, ELSecondNotebook.FILTER_PHRASE, ELSecondNotebook.FILTER_BATTLE]
## Right-hand areas (800x600 units): top (day, kind, portrait, minimap),
## speech box and battle record.
const TOP := Vector2(482, 23)
const SPEECH := Rect2(499, 197, 262, 322)
const BATTLE := Vector2(482, 192)

var hud: ELSecondAdventureHud
var state: ELAdventureSession
var profile: ELProfile
var canvas: Control
var art: Control
var list: Control
var details: Control
var speech: Control
var speech_text: Label
var speech_name: Label
var minimap: Control
var minimap_fog: TextureRect
var filter_popup: PanelContainer
var filter := ELSecondNotebook.FILTER_ALL
var current_only := false
var entries: Array = []
var selected := -1
var top := 0
var speech_offset := 0.0
var buttons: Dictionary = {}
var labels: Dictionary = {}
var checkbox: ArtButton
var _pieces: Array[Dictionary] = []
var _offset := Vector2.ZERO

func build(source_hud: ELSecondAdventureHud) -> bool:
	hud = source_hud
	state = hud.state
	profile = hud.profile
	if not hud._rows.has(PANEL) or not hud._controls.has("NotebookLeftBounds"): return false
	name = "Notebook"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	art.draw.connect(_draw_art)
	for control: String in ["NotebookHdrLeft", "NotebookHdrRight", "NotebookHdrEvent", "NotebookHdrDay"]:
		var label := _label(canvas, hud.text(str(hud._controls[control].get("Text", ""))), hud.face_bold, 15, TAN, HORIZONTAL_ALIGNMENT_CENTER)
		label.name = control
		labels[control] = label
	labels.NotebookHdrEvent.tooltip_text = profile.text("T_NOTEBOOK_TT_EVENT")
	labels.NotebookHdrDay.tooltip_text = profile.text("T_NOTEBOOK_TT_DAY")
	for control: String in ["NotebookHdrEvent", "NotebookHdrDay"]: labels[control].mouse_filter = Control.MOUSE_FILTER_PASS
	labels.NotebookCurFilter = _label(canvas, "", hud.face_bold, 14, TAN, HORIZONTAL_ALIGNMENT_LEFT)
	labels.NotebookCurMis = _label(canvas, hud.text("CtrlNotebookCurMis"), hud.face_bold, 14, TAN, HORIZONTAL_ALIGNMENT_LEFT)
	list = Control.new()
	list.name = "NotebookLeftBounds"
	list.mouse_filter = Control.MOUSE_FILTER_STOP
	list.clip_contents = true
	canvas.add_child(list)
	list.draw.connect(_draw_list)
	list.gui_input.connect(_list_input)
	details = Control.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(details)
	details.draw.connect(_draw_details)
	_build_minimap()
	speech = Control.new()
	speech.name = "NotebookSpeechScrollBounds"
	speech.clip_contents = true
	speech.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(speech)
	speech.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scroll_speech(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
	speech_text = Label.new()
	speech_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_text.add_theme_font_override("font", hud.face)
	speech_text.add_theme_font_size_override("font_size", 15)
	speech_text.add_theme_color_override("font_color", TAN)
	speech_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	speech_text.add_theme_constant_override("shadow_offset_x", 1)
	speech_text.add_theme_constant_override("shadow_offset_y", 1)
	speech_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech.add_child(speech_text)
	speech_name = _label(speech, "", hud.face_bold, 15, WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	speech_name.name = "Speaker"
	for control: String in ["NotebookOkBtn", "NotebookDropBtn", "NotebookU2", "NotebookD2", "NotebookScrollUp1", "NotebookScrollDown1", "NotebookU1", "NotebookD1"]:
		var button := ArtButton.make(hud, control)
		canvas.add_child(button)
		buttons[control] = button
	buttons.NotebookOkBtn.tooltip_text = hud.tooltip_of("NotebookOkBtn")
	buttons.NotebookOkBtn.pressed.connect(close)
	buttons.NotebookDropBtn.pressed.connect(func(): show_filters(not filter_popup.visible))
	buttons.NotebookU2.pressed.connect(scroll_list.bind(-1))
	buttons.NotebookD2.pressed.connect(scroll_list.bind(1))
	buttons.NotebookScrollUp1.pressed.connect(scroll_list.bind(-ROWS))
	buttons.NotebookScrollDown1.pressed.connect(scroll_list.bind(ROWS))
	buttons.NotebookU1.pressed.connect(scroll_speech.bind(-1))
	buttons.NotebookD1.pressed.connect(scroll_speech.bind(1))
	checkbox = ArtButton.make(hud, "NotebookCurMis", true)
	checkbox.toggle_mode = true
	checkbox.button_pressed = current_only
	checkbox.toggled.connect(func(on: bool):
		current_only = on
		refresh_entries(true))
	canvas.add_child(checkbox)
	buttons.NotebookCurMis = checkbox
	_build_filter_popup()
	resized.connect(_layout)
	refresh_entries(true)
	_layout()
	return true

func _label(parent: Control, value: String, font: Font, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_minimap() -> void:
	minimap = Control.new()
	minimap.name = "NotebookMinimap"
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(minimap)
	minimap.draw.connect(_draw_minimap)
	if hud.minimap_fog != null:
		# CMiniMapNotebook uses the same two-state fog as the strategic minimap.
		minimap_fog = TextureRect.new()
		minimap_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap_fog.stretch_mode = TextureRect.STRETCH_SCALE
		minimap_fog.flip_v = true
		minimap_fog.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		minimap_fog.material = hud.minimap_fog.material
		minimap.add_child(minimap_fog)
	var marks := Control.new()
	marks.name = "Marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	minimap.add_child(marks)
	marks.draw.connect(_draw_minimap_marks.bind(marks))

func _build_filter_popup() -> void:
	filter_popup = PanelContainer.new()
	filter_popup.name = "NotebookFilter"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.04, 0.96)
	style.border_color = Color("6a5a3a")
	style.set_border_width_all(1)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	filter_popup.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	filter_popup.add_child(column)
	for value: int in FILTERS:
		var option := Button.new()
		option.name = "Filter%d" % value
		option.text = profile.text(ELSecondNotebook.FILTER_TEXT[value])
		option.flat = true
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.focus_mode = Control.FOCUS_NONE
		option.add_theme_font_override("font", hud.face_bold)
		option.add_theme_font_size_override("font_size", 14)
		option.add_theme_color_override("font_color", TAN)
		option.add_theme_color_override("font_hover_color", WHITE)
		option.pressed.connect(set_filter.bind(value))
		column.add_child(option)
	canvas.add_child(filter_popup)
	filter_popup.hide()

# --- Layout -------------------------------------------------------------------

func design(control: String) -> Rect2:
	var row: Dictionary = hud._controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + _offset, Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func _layout() -> void:
	if size.y <= 0: return
	var factor := size.y / ELSecondAdventureHud.DESIGN_HEIGHT
	var width := maxf(1024.0, size.x / factor)
	canvas.scale = Vector2(factor, factor)
	canvas.size = Vector2(width, ELSecondAdventureHud.DESIGN_HEIGHT)
	art.size = canvas.size
	var row: Dictionary = hud._controls.get(PANEL, {})
	# The panel keeps its registry shift and is centred in a wider window.
	_offset = Vector2(float(row.get("ShiftX", 112)) + (width - 1024.0) * 0.5, float(row.get("ShiftY", 14)))
	_pieces.clear()
	var variant := "Type1" if _entry().get("kind") == ELSecondNotebook.BATTLE else "Type2"
	for piece_row: Dictionary in hud._rows.get(PANEL, []):
		if not piece_row.masks.is_empty() and not piece_row.masks.has(variant): continue
		var piece := hud.cut(piece_row, _offset)
		if not piece.is_empty(): _pieces.append(piece)
	for control: String in labels:
		if control == "NotebookCurMis":
			var box := design("NotebookCurMis")
			labels[control].position = Vector2(box.end.x + 6, box.position.y)
			labels[control].size = Vector2(200, box.size.y)
		elif control == "NotebookCurFilter":
			var rect := design(control)
			labels[control].position = rect.position
			labels[control].size = Vector2(rect.size.x, 22)
		else:
			labels[control].position = design(control).position
			labels[control].size = design(control).size
	var bounds := design("NotebookLeftBounds")
	list.position = bounds.position
	list.size = Vector2(bounds.size.x, ROWS * ROW_HEIGHT)
	details.position = Vector2.ZERO
	details.size = canvas.size
	minimap.position = TOP + _offset + Vector2(160, 20)
	minimap.size = Vector2(130, 130)
	if minimap_fog != null:
		var area := minimap_area()
		minimap_fog.position = area.position
		minimap_fog.size = area.size
	speech.position = SPEECH.position + _offset + Vector2(10, 10)
	speech.size = SPEECH.size - Vector2(20, 20)
	speech_text.position = Vector2(0, 31 - speech_offset)
	speech_text.size = Vector2(speech.size.x, 0)
	speech_name.position = Vector2(0, -speech_offset)
	speech_name.size = Vector2(speech.size.x, 22)
	for control: String in buttons: buttons[control].place(_offset)
	var popup := design("NotebookFilter") if hud._controls.has("NotebookFilter") else Rect2(Vector2(22, 65) + _offset, Vector2(200, 10))
	filter_popup.position = popup.position
	filter_popup.size = Vector2(popup.size.x, 0)
	_refresh_kind()
	art.queue_redraw()
	details.queue_redraw()
	list.queue_redraw()
	minimap.queue_redraw()
	minimap.get_node("Marks").queue_redraw()

## The current filter's icon in NotebookFilterIcon, cut from TOOLTIP: the
## phrase or battle mark, the "all" mark for the other filters.
const FILTER_ICONS := {ELSecondNotebook.FILTER_PHRASE: Rect2(212, 20, 20, 14), ELSecondNotebook.FILTER_BATTLE: Rect2(189, 20, 20, 14)}
const FILTER_ICON_ALL := Rect2(235, 20, 20, 14)

func filter_icon() -> Rect2:
	return FILTER_ICONS.get(filter, FILTER_ICON_ALL)

func _draw_art() -> void:
	art.draw_rect(Rect2(Vector2.ZERO, art.size), Color(0, 0, 0, 0.6))
	for piece: Dictionary in _pieces: art.draw_texture_rect_region(piece.texture, piece.rect, piece.source)
	var icons: Texture2D = hud.profile.texture(hud._paths["TOOLTIP"]) if hud._paths.has("TOOLTIP") else null
	if icons != null and hud._controls.has("NotebookFilterIcon"):
		var source := filter_icon()
		art.draw_texture_rect_region(icons, Rect2(design("NotebookFilterIcon").position, source.size), source)

# --- Entries ------------------------------------------------------------------

## Rebuilds the filtered list; keeps the selected entry when it is
## still listed, else selects the newest one.
func refresh_entries(select_newest := false) -> void:
	var previous := int(_entry().get("id", -1))
	entries = ELSecondNotebook.filtered(state.notebook, filter, current_only)
	selected = -1
	if not select_newest:
		for index in entries.size():
			if int(entries[index].id) == previous: selected = index
	if selected < 0: selected = entries.size() - 1
	top = clampi(top, 0, maxi(0, entries.size() - ROWS))
	if selected >= 0 and (selected < top or selected >= top + ROWS): top = clampi(selected - ROWS + 1, 0, maxi(0, entries.size() - ROWS))
	labels.NotebookCurFilter.text = profile.text(ELSecondNotebook.FILTER_TEXT[filter])
	speech_offset = 0.0
	_layout()

func _entry() -> Dictionary:
	return entries[selected] if selected >= 0 and selected < entries.size() else {}

func select(index: int) -> void:
	if index < 0 or index >= entries.size(): return
	selected = index
	speech_offset = 0.0
	_layout()

func set_filter(value: int) -> void:
	filter = value
	show_filters(false)
	refresh_entries(true)

func show_filters(value: bool) -> void:
	filter_popup.visible = value
	if value: filter_popup.move_to_front()

func scroll_list(delta: int) -> void:
	top = clampi(top + delta, 0, maxi(0, entries.size() - ROWS))
	_refresh_kind()
	list.queue_redraw()

func scroll_speech(delta: int) -> void:
	var limit := maxf(0.0, speech_text.get_combined_minimum_size().y + 31 - speech.size.y)
	speech_offset = clampf(speech_offset + delta * 20.0, 0.0, limit)
	speech_text.position.y = 31 - speech_offset
	speech_name.position.y = -speech_offset

func close() -> void:
	show_filters(false)
	# the tutorial learns that the notebook was closed (result ignored).
	if state.vm != null: state.hook("Hook_ForbidDialogClose", ["Notebook"])
	closed.emit()

func _list_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP: scroll_list(-1)
		MOUSE_BUTTON_WHEEL_DOWN: scroll_list(1)
		MOUSE_BUTTON_LEFT:
			show_filters(false)
			select(top + int(event.position.y / ROW_HEIGHT))

## Row index at a point in the list's local units, or -1.
func row_rect(index: int) -> Rect2:
	return Rect2(Vector2(0, (index - top) * ROW_HEIGHT), Vector2(list.size.x, ROW_HEIGHT))

func _refresh_kind() -> void:
	var entry := _entry()
	var phrase: bool = entry.get("kind") == ELSecondNotebook.PHRASE
	speech.visible = phrase
	for control: String in ["NotebookU1", "NotebookD1"]:
		if buttons.has(control): buttons[control].visible = phrase
	speech_text.text = profile.text(str(entry.get("text", ""))) if phrase else ""
	# The speaker's name heads the text when the phrase has a face.
	speech_name.text = str(entry.speaker) + ":" if phrase and int(entry.get("face", -1)) >= 0 and not str(entry.get("speaker", "")).is_empty() else ""
	buttons.NotebookU2.disabled = top <= 0
	buttons.NotebookScrollUp1.disabled = top <= 0
	var last := maxi(0, entries.size() - ROWS)
	buttons.NotebookD2.disabled = top >= last
	buttons.NotebookScrollDown1.disabled = top >= last
	minimap.visible = not entry.is_empty()

# --- Drawing ------------------------------------------------------------------

func _text(target: CanvasItem, at: Vector2, value: String, color := TAN, bold := false, font_size := 15, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font: Font = hud.face_bold if bold else hud.face
	var baseline := at + Vector2(0, font.get_ascent(font_size))
	target.draw_string(font, baseline + Vector2(1, 1), value, align, width, font_size, Color(0, 0, 0, 0.85))
	target.draw_string(font, baseline, value, align, width, font_size, color)

func _draw_list() -> void:
	var day_rect := design("NotebookHdrDay")
	var bounds := design("NotebookLeftBounds")
	var day_x := day_rect.position.x - bounds.position.x
	for row in ROWS:
		var index := top + row
		if index >= entries.size(): break
		var entry: Dictionary = entries[index]
		var color := WHITE if index == selected else TAN
		var y := row * ROW_HEIGHT + 4
		var title := str(entry.get("speaker", "")) if entry.kind == ELSecondNotebook.PHRASE else str(entry.get("opponent", ""))
		_text(list, Vector2(8, y), title, color, false, 15, day_x - 12)
		_text(list, Vector2(day_x, y), str(int(entry.day) + 1), color, false, 15, day_rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_details() -> void:
	var entry := _entry()
	if entry.is_empty(): return
	var at := TOP + _offset
	var battle: bool = entry.kind == ELSecondNotebook.BATTLE
	_text(details, at + Vector2(22, 15), profile.text("T_NOTEBOOK_DAY"), TAN, true)
	_text(details, at + Vector2(70, 15), str(int(entry.day) + 1), WHITE, true)
	_text(details, at + Vector2(22, 40), profile.text("T_NOTEBOOK_BATTLE" if battle else "T_NOTEBOOK_PHRASE"), TAN, true)
	var face := int(entry.get("opponent_face" if battle else "face", -1))
	if face >= 0:
		var portrait := profile.portrait(face)
		if portrait != null: details.draw_texture_rect(portrait, Rect2(at + Vector2(18, 80), Vector2(100, 70)), false)
	if not battle: return
	var b := BATTLE + _offset
	_text(details, b + Vector2(22, 9), str(entry.opponent), WHITE, true)
	_text(details, b + Vector2(45, 41), profile.text("T_NOTEBOOK_LIFE"))
	_text(details, b + Vector2(145, 41), str(entry.opponent_life), WHITE)
	_text(details, b + Vector2(45, 71), profile.text("T_NOTEBOOK_LEVEL"))
	_text(details, b + Vector2(145, 71), str(entry.opponent_level), WHITE)
	_text(details, b + Vector2(22, 106), str(entry.hero), WHITE, true)
	_text(details, b + Vector2(130, 131), profile.text("T_NOTEBOOK_BB"))
	_text(details, b + Vector2(225, 131), profile.text("T_NOTEBOOK_AB"))
	_text(details, b + Vector2(45, 161), profile.text("T_NOTEBOOK_LIFE"))
	_text(details, b + Vector2(145, 161), str(entry.life_before), WHITE)
	_text(details, b + Vector2(250, 161), str(entry.life_after), WHITE)
	_text(details, b + Vector2(45, 196), profile.text("T_NOTEBOOK_LEVEL"))
	_text(details, b + Vector2(145, 196), str(entry.level_before), WHITE)
	_text(details, b + Vector2(250, 196), str(entry.level_after), WHITE)
	_text(details, b + Vector2(45, 231), profile.text("T_NOTEBOOK_EXP"))
	_text(details, b + Vector2(250, 231), str(entry.experience), WHITE)
	if not entry.loot.is_empty(): _text(details, b + Vector2(45, 261), profile.text("T_NOTEBOOK_LOOT"))

## Whole map fitted into the 130x130 box, as the strategic minimap.
func minimap_area() -> Rect2:
	var map := state.map
	var bounds := Vector2(130, 130)
	var fit := minf(bounds.x, bounds.y) / maxf(1, maxf(map.width, map.height))
	var area := Vector2(map.width, map.height) * fit
	return Rect2((bounds - area) * 0.5, area)

func _draw_minimap() -> void:
	minimap.draw_rect(Rect2(Vector2.ZERO, minimap.size), Color.BLACK)
	if hud.minimap_texture != null: minimap.draw_texture_rect(hud.minimap_texture, minimap_area(), false)
	if minimap_fog != null and minimap_fog.texture != hud._fog_texture: minimap_fog.texture = hud._fog_texture

func _draw_minimap_marks(marks: Control) -> void:
	var entry := _entry()
	if entry.is_empty(): return
	var point: Array = entry.point
	if float(point[0]) < 0: return
	var area := minimap_area()
	var map := state.map
	var at := area.position + Vector2(float(point[0]), map.height - float(point[1])) * area.size / Vector2(maxf(1, map.width), maxf(1, map.height))
	marks.draw_arc(at, 5, 0, TAU, 20, Color("d8b058"), 1.5)
	marks.draw_rect(Rect2(at - Vector2(1.5, 1.5), Vector2(3, 3)), WHITE)

## Point of an entry on the notebook minimap, in canvas units (tests).
func minimap_point(entry: Dictionary) -> Vector2:
	var area := minimap_area()
	var map := state.map
	return minimap.position + area.position + Vector2(float(entry.point[0]), map.height - float(entry.point[1])) * area.size / Vector2(maxf(1, map.width), maxf(1, map.height))

## Registry art button drawn from every piece of its state (the page bars
## have two pieces); a missing normal piece leaves the background visible.
class ArtButton extends BaseButton:
	var parts: Dictionary = {}
	var check := false
	var _origin := Vector2.ZERO

	static func make(owner: ELSecondAdventureHud, control: String, checkbox := false) -> ArtButton:
		var button := ArtButton.new()
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		button.check = checkbox
		var pick := func(required: Array, excluded: Array) -> Array:
			var result: Array = []
			for row: Dictionary in owner.rows(control, required, excluded):
				var piece := owner.cut(row)
				if not piece.is_empty(): result.append(piece)
			return result
		if checkbox:
			# NotebookCurMis: frame (no mask), check mark (Push), hover (Light).
			var frames: Array = []
			for row: Dictionary in owner.rows(control):
				if row.masks.is_empty():
					var piece := owner.cut(row)
					if not piece.is_empty(): frames.append(piece)
			button.parts = {"normal": frames, "pressed": pick.call(["Push"], []), "hover": pick.call(["Light"], [])}
		else:
			button.parts = {"normal": pick.call(["Free"], ["Light"]), "pressed": pick.call(["Push"], ["Light"]), "hover": pick.call(["Free", "Light"], []),
				"hover_pressed": pick.call(["Push", "Light"], []), "disabled": pick.call(["Disabled"], [])}
		var bounds := Rect2()
		var first := true
		for list: Array in button.parts.values():
			for part: Dictionary in list:
				bounds = part.rect if first else bounds.merge(part.rect)
				first = false
		if first:
			var row: Dictionary = owner._controls.get(control, {})
			bounds = Rect2(float(row.get("Left", 0)), float(row.get("Top", 0)), float(row.get("Width", 1)), float(row.get("Height", 1)))
		button._origin = bounds.position
		button.size = bounds.size
		return button

	func place(offset: Vector2) -> void:
		position = _origin + offset
		queue_redraw()

	func _draw() -> void:
		var mode := get_draw_mode()
		var hover := mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED
		if check:
			_pieces(parts.normal)
			if button_pressed: _pieces(parts.pressed)
			if hover: _pieces(parts.hover)
			return
		if disabled:
			_pieces(parts.disabled)
			return
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		if pushed: _pieces(parts.hover_pressed if hover and not parts.hover_pressed.is_empty() else parts.pressed)
		elif hover and not parts.hover.is_empty(): _pieces(parts.hover)
		else: _pieces(parts.normal)

	func _pieces(list: Array) -> void:
		for part: Dictionary in list: draw_texture_rect_region(part.texture, Rect2(part.rect.position - _origin, part.rect.size), part.source)
