class_name ELSecondPrecombatView
extends Control
## Second-game pre-battle panel (PrecombatScreen, CCombatInfoScreen) on the
## original A6-Int-Precombat art. Every battle with a side of the local player
## opens it once both actors face each other: the question "Принять сражение?"
## (BattleNumText), the local side on the left and its opponent on the right,
## each with a 94x50 portrait cut from the 100x70 cell at (3, 9), the level and
## life values in the 41-pixel boxes and their captions beside them.
##
## PreCombatBegin (Enter, Space) starts the battle; PreCombatCancel (Escape)
## declines it. BeginCombat is drawn and shows its tooltip, but the original
## handler gives its click no action, so it has none here either. The side
## panels (AdvPanelLB/RB) are hidden while the panel is up.

signal accepted
signal declined

const PANEL := "PrecombatScreen"
## CHeroStatsView text origins and portrait rectangles (800x600 layout).
const STATS := [Vector2(264, 283), Vector2(520, 283)]
const PORTRAITS := [Rect2(161, 282, 94, 50), Rect2(416, 282, 94, 50)]
const PORTRAIT_CUT := Vector2(3, 9)
const VALUE_WIDTH := 41
const CAPTION_WIDTH := 90
const ROW := 25
const TAN := Color("d6bb88")
const WHITE := Color("f2ead8")

var hud: ELSecondAdventureHud
var canvas: Control
var surface: Control
var labels: Dictionary = {}
var begin_button: BaseButton
var cancel_button: BaseButton
var decoration: Control
## [local id, opponent id]
var pair: Array = []
var _faces: Array = [-1, -1]
var _values: Array = [["", ""], ["", ""]]
var _pieces: Array[Dictionary] = []
var _offset := Vector2.ZERO

func build(owner: ELSecondAdventureHud) -> void:
	hud = owner
	name = "PrecombatScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	surface = Control.new()
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.draw.connect(_draw_surface)
	canvas.add_child(surface)
	labels.BattleNumText = _label(hud.text(str(hud._controls.get("BattleNumText", {}).get("Text", ""))), 20, HORIZONTAL_ALIGNMENT_CENTER, TAN)
	labels.PrecombatHeroName = _label("", 20, HORIZONTAL_ALIGNMENT_CENTER, TAN)
	labels.OpponentName = _label("", 20, HORIZONTAL_ALIGNMENT_CENTER, TAN)
	for control: String in labels: labels[control].name = control
	for side in 2:
		for row in 2:
			labels["value_%d_%d" % [side, row]] = _label("", 17, HORIZONTAL_ALIGNMENT_CENTER, WHITE)
			labels["caption_%d_%d" % [side, row]] = _label(hud.text(["T_LEVEL", "T_LIFE"][row]), 17, HORIZONTAL_ALIGNMENT_LEFT, TAN)
	begin_button = ELSecondNotebookView.ArtButton.make(hud, "PreCombatBegin")
	begin_button.pressed.connect(func(): accepted.emit())
	canvas.add_child(begin_button)
	cancel_button = ELSecondNotebookView.ArtButton.make(hud, "PreCombatCancel")
	cancel_button.pressed.connect(func(): declined.emit())
	canvas.add_child(cancel_button)
	decoration = Decoration.new()
	decoration.name = "BeginCombat"
	decoration.view = self
	decoration.tooltip_text = hud.tooltip_of("BeginCombat")
	canvas.add_child(decoration)
	resized.connect(_layout)
	_layout()
	hide()

func _label(value: String, font_size: int, align: HorizontalAlignment, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", hud.face_bold)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(label)
	return label

## `faces` are the portrait indices of [local, opponent] (-1: none).
func open(state: ELAdventureSession, local_id: int, opponent_id: int, faces: Array) -> void:
	pair = [local_id, opponent_id]
	_faces = faces.duplicate()
	for side in 2:
		var actor := state.object(pair[side])
		labels["PrecombatHeroName" if side == 0 else "OpponentName"].text = str(actor.get("title", actor.get("name", "")))
		_values[side] = [str(int(actor.get("level", 1))), str(int(actor.get("health", 0)))]
		for row in 2: labels["value_%d_%d" % [side, row]].text = _values[side][row]
	show()
	_layout()

func close() -> void:
	pair = []
	hide()

func design(control: String) -> Rect2:
	var row: Dictionary = hud._controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + _offset, Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func _layout() -> void:
	var area := size
	if area.y <= 0: return
	var factor := area.y / ELSecondAdventureHud.DESIGN_HEIGHT
	var width := maxf(1024.0, area.x / factor)
	canvas.scale = Vector2(factor, factor)
	canvas.size = Vector2(width, ELSecondAdventureHud.DESIGN_HEIGHT)
	var row: Dictionary = hud._controls.get(PANEL, {})
	_offset = Vector2(float(row.get("ShiftX", 112)) + (width - 1024.0) * 0.5, float(row.get("ShiftY", 284)))
	_pieces.clear()
	for piece_row: Dictionary in hud.rows(PANEL):
		var piece := hud.cut(piece_row, _offset)
		if not piece.is_empty(): _pieces.append(piece)
	var panel := design(PANEL)
	surface.position = panel.position
	surface.size = panel.size
	for control: String in ["BattleNumText", "PrecombatHeroName", "OpponentName"]:
		var box := design(control)
		labels[control].position = box.position
		labels[control].size = box.size
	for side in 2:
		for line in 2:
			var origin: Vector2 = STATS[side] + _offset + Vector2(0, line * ROW)
			labels["value_%d_%d" % [side, line]].position = origin
			labels["value_%d_%d" % [side, line]].size = Vector2(VALUE_WIDTH, ROW)
			labels["caption_%d_%d" % [side, line]].position = origin + Vector2(VALUE_WIDTH, 0)
			labels["caption_%d_%d" % [side, line]].size = Vector2(CAPTION_WIDTH, ROW)
	(begin_button as ELSecondNotebookView.ArtButton).place(_offset)
	(cancel_button as ELSecondNotebookView.ArtButton).place(_offset)
	var bar := design("BeginCombat")
	decoration.position = bar.position
	decoration.size = bar.size
	surface.queue_redraw()
	decoration.queue_redraw()

func _draw_surface() -> void:
	var origin := surface.position
	for piece: Dictionary in _pieces: surface.draw_texture_rect_region(piece.texture, Rect2(piece.rect.position - origin, piece.rect.size), piece.source)
	for side in 2:
		if int(_faces[side]) < 0: continue
		var atlas := hud.profile.portrait(int(_faces[side])) as AtlasTexture
		if atlas == null or atlas.atlas == null: continue
		var box: Rect2 = PORTRAITS[side]
		surface.draw_texture_rect_region(atlas.atlas, Rect2(box.position + _offset - origin, box.size), Rect2(atlas.region.position + PORTRAIT_CUT, box.size))

## The BeginCombat strip: the Type1 Free art, its Light art under the cursor.
class Decoration extends Control:
	var view: ELSecondPrecombatView
	var _hover := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())

	func _draw() -> void:
		var rows := view.hud.rows("BeginCombat", ["Free", "Type1"], ["Light"])
		if _hover: rows.append_array(view.hud.rows("BeginCombat", ["Free", "Type1", "Light"]))
		for row: Dictionary in rows:
			var piece := view.hud.cut(row, view._offset)
			if not piece.is_empty(): draw_texture_rect_region(piece.texture, Rect2(piece.rect.position - position, piece.rect.size), piece.source)
