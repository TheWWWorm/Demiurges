class_name ELSecondLevelUpView
extends ELHeroSkillsView
## Second-game level-up dialog (LevelUpDialog) drawn with the original
## A6-Int-Upgrade artwork: the 256x380 panel centred on the screen, the
## "UPGRADE" header, three offered skills as 50x50 icons (LUBounds, one cell
## every 69 pixels; the chosen one is covered by the translucent white swatch of
## the SYMBOLS sheet), the hero's five skill rows (LUSkill1..5, a 20x20 icon
## and the name, rows 26 pixels apart) and the LUOk button.
##
## Choosing an offer previews it in the skill rows (a new skill appended, a
## known one raised). LUOk learns the chosen offer and closes the dialog once no
## choice is left. The remake keeps LUOk disabled while offers wait without a
## selection, so a pending choice is never lost; Escape closes the dialog and
## keeps it. The active specialisation is chosen on the inventory screen, as in
## the original, so this dialog carries no selector.

const PANEL := "LevelUpDialog"
const CELL := 69
const ICON := 50
const ROW := 26
const TAN := Color("d6bb88")
const WHITE := Color("f2ead8")
const MARK := Rect2(0, 60, 4, 4)

var hud: ELSecondAdventureHud
var root_control: Control
var canvas: Control
var surface: Control
var labels: Dictionary = {}
var _pieces: Array[Dictionary] = []
var _offset := Vector2.ZERO
var _skills_sheet: Texture2D
var _mark_sheet: Texture2D
## Hero skill rows shown, with the chosen offer applied: [code, rank, new].
var _rows: Array = []

func build(session: ELAdventureSession, id: int) -> void:
	state = session
	hero_id = id
	name = "LevelUpDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skills_sheet = state.map.profile.texture("Interface/Skills/icon_1")
	_mark_sheet = state.map.profile.texture(str(hud._paths.get("SYMBOLS", "Interface/Symbols")))
	root_control = Control.new()
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(canvas)
	surface = Control.new()
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.draw.connect(_draw_surface)
	canvas.add_child(surface)
	for control: String in ["LUHeader1", "LUHeader2", "LUHeader3"]:
		labels[control] = _text_label(hud.text(str(hud._controls.get(control, {}).get("Text", ""))), int(hud._controls.get(control, {}).get("FontSize", 18)), HORIZONTAL_ALIGNMENT_CENTER, TAN)
		labels[control].clip_text = false
	for index in 5: labels["LUSkill%d" % (index + 1)] = _text_label("", 17, HORIZONTAL_ALIGNMENT_LEFT, WHITE)
	for control: String in labels: labels[control].name = control
	heading = labels.LUHeader1
	offers = OfferStrip.new()
	offers.name = "LUBounds"
	offers.view = self
	offers.item_selected.connect(func(_index: int): _select())
	canvas.add_child(offers)
	learned = SkillRows.new()
	learned.name = "LUSkillsBounds"
	learned.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(learned)
	var ok := ELSecondNotebookView.ArtButton.make(hud, "LUOk")
	ok.tooltip_text = hud.tooltip_of("LUOk")
	ok.pressed.connect(_choose)
	canvas.add_child(ok)
	accept = ok
	# Kept for the shared interface: the description sits in the offer tooltip,
	# messages and the specialisation choice belong to other screens.
	details = RichTextLabel.new()
	details.visible = false
	add_child(details)
	message = Label.new()
	message.visible = false
	add_child(message)
	spec_row = HBoxContainer.new()
	spec_row.visible = false
	add_child(spec_row)
	spec_pick = OptionButton.new()
	spec_row.add_child(spec_pick)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.resized.connect(_layout)
	refresh()
	_layout()

func _text_label(value: String, font_size: int, align: HorizontalAlignment, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", hud.serif_bold)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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
	var row: Dictionary = hud._controls.get(PANEL, {})
	_offset = Vector2(float(row.get("ShiftX", 112)) + (width - 1024.0) * 0.5, float(row.get("ShiftY", 84)))
	_pieces.clear()
	for piece_row: Dictionary in hud._rows.get(PANEL, []):
		var piece := hud.cut(piece_row, _offset)
		if not piece.is_empty(): _pieces.append(piece)
	var panel := design(PANEL)
	surface.position = panel.position
	surface.size = panel.size
	for control: String in labels:
		var box := design(control)
		var label: Label = labels[control]
		# A header longer than its box (the 123-pixel title plate) spreads
		# evenly to both sides instead of being cut.
		var wide := label.get_minimum_size().x if control.begins_with("LUHeader") else 0.0
		if wide > box.size.x: box = box.grow_individual((wide - box.size.x) * 0.5, 0, (wide - box.size.x) * 0.5, 0)
		label.position = box.position
		label.size = box.size
	offers.position = design("LUBounds").position
	offers.size = design("LUBounds").size
	learned.position = design("LUSkillsBounds").position
	learned.size = design("LUSkillsBounds").size
	(accept as ELSecondNotebookView.ArtButton).place(_offset)
	surface.queue_redraw()

func _draw_surface() -> void:
	var origin := surface.position
	for piece: Dictionary in _pieces: surface.draw_texture_rect_region(piece.texture, Rect2(piece.rect.position - origin, piece.rect.size), piece.source)
	if _skills_sheet == null: return
	var skill_origin := design("LUSkill1").position - origin
	var left := design("LUSkillsBounds").position.x - origin.x + 4
	for index in mini(5, _rows.size()):
		var icon := _icon_index(str(_rows[index][0]), int(_rows[index][1]))
		if icon < 0: continue
		surface.draw_texture_rect_region(_skills_sheet, Rect2(Vector2(left, skill_origin.y + 3 + index * ROW), Vector2(20, 20)), _cell(icon))

func _icon_index(code: String, rank: int) -> int:
	return int(ELHeroSkills.definition(state.map.profile, code, rank).get("Icon", -1))

static func _cell(icon: int) -> Rect2:
	return Rect2((icon / 5) * 50, (icon % 5) * 50, 50, 50)

# --- State --------------------------------------------------------------------

func refresh() -> void:
	var hero := state.object(hero_id)
	offers.clear()
	for code: String in hero.get("skill_offers", []):
		var rank := int(hero.skills.get(code, -1)) + 1
		offers.add_item(code, rank)
	learned.clear()
	for code: String in hero.skills: learned.add_item(code, int(hero.skills[code]))
	_select()

func _select() -> void:
	var hero := state.object(hero_id)
	var chosen: Array = offers.get_selected_items()
	_rows.clear()
	for code: String in hero.skills: _rows.append([code, int(hero.skills[code]), false])
	var code := ""
	var rank := 0
	if not chosen.is_empty():
		code = str(hero.skill_offers[chosen[0]])
		rank = int(hero.skills.get(code, -1)) + 1
		var found := false
		for row: Array in _rows:
			if row[0] == code:
				row[1] = rank
				row[2] = true
				found = true
		if not found: _rows.append([code, rank, true])
	for index in 5:
		var label: Label = labels["LUSkill%d" % (index + 1)]
		label.text = ""
		if index < _rows.size():
			label.text = state.map.profile.text(str(ELHeroSkills.definition(state.map.profile, str(_rows[index][0]), int(_rows[index][1])).get("Name", _rows[index][0])))
			label.add_theme_color_override("font_color", TAN if _rows[index][2] else WHITE)
		label.tooltip_text = ""
	# LUOk learns a chosen offer; with no offer waiting it simply closes.
	accept.disabled = chosen.is_empty() and offers.item_count > 0
	details.text = "" if code.is_empty() else describe(code, rank)
	surface.queue_redraw()

func describe(code: String, rank: int) -> String:
	var row := ELHeroSkills.definition(state.map.profile, code, rank)
	var text := str(row.get("Desc", row.get("Description", "")))
	return state.map.profile.text(str(row.get("Name", code))) + ("" if text.is_empty() else "\n" + state.map.profile.text(text))

func _choose() -> void:
	if accept.disabled: return
	var chosen: Array = offers.get_selected_items()
	if chosen.is_empty():
		closed.emit()
		return
	var code := str(state.object(hero_id).skill_offers[chosen[0]])
	if not state.choose_skill(hero_id, code):
		message.text = state.error
		push_warning(state.error)
		return
	var hero := state.object(hero_id)
	if int(hero.get("skill_points", 0)) > 0:
		ELHeroSkills.prepare(state.map.profile, hero)
		refresh()
		return
	closed.emit()

## Enter presses LUOk when it is available.
func press_ok() -> void:
	if not accept.disabled: _choose()

func _choose_spec(_index: int) -> void:
	pass

## The three offered skills, one 50x50 icon per 69-pixel cell.
class OfferStrip extends Control:
	signal item_selected(index: int)
	var view: ELSecondLevelUpView
	var item_count: int:
		get: return _items.size()
	var _items: Array = []
	var _selected := -1

	func clear() -> void:
		_items.clear()
		_selected = -1
		queue_redraw()

	func add_item(code: String, rank: int) -> void:
		_items.append([code, rank])
		queue_redraw()

	func get_item_rect(index: int) -> Rect2:
		return Rect2(index * CELL, 0, ICON, ICON)

	func get_selected_items() -> PackedInt32Array:
		return PackedInt32Array() if _selected < 0 else PackedInt32Array([_selected])

	func select(index: int) -> void:
		_selected = index if index >= 0 and index < _items.size() else -1
		queue_redraw()

	func deselect_all() -> void:
		select(-1)

	func item_at(at: Vector2) -> int:
		if at.y < 0 or at.y >= ICON or at.x < 0: return -1
		var index := int(at.x) / CELL
		return index if index < _items.size() and int(at.x) % CELL < ICON else -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var index := item_at(event.position)
			if index >= 0:
				select(index)
				item_selected.emit(index)
				accept_event()

	func _get_tooltip(at: Vector2) -> String:
		var index := item_at(at)
		return "" if index < 0 else view.describe(str(_items[index][0]), int(_items[index][1]))

	func _ready() -> void:
		tooltip_text = " "

	func _draw() -> void:
		if view._skills_sheet == null: return
		for index in _items.size():
			var icon := view._icon_index(str(_items[index][0]), int(_items[index][1]))
			var box := get_item_rect(index)
			if icon >= 0: draw_texture_rect_region(view._skills_sheet, box, ELSecondLevelUpView._cell(icon))
			if index == _selected and view._mark_sheet != null: draw_texture_rect_region(view._mark_sheet, box, MARK)

## The hero's skill rows (drawn by the dialog surface); a list interface only.
class SkillRows extends Control:
	signal item_selected(index: int)
	var item_count: int:
		get: return _items.size()
	var _items: Array = []

	func clear() -> void: _items.clear()
	func add_item(code: String, rank: int) -> void: _items.append([code, rank])
	func get_selected_items() -> PackedInt32Array: return PackedInt32Array()
	func select(_index: int) -> void: pass
	func deselect_all() -> void: pass
