class_name ELExpeditionCardCell
extends Button
## One square of a spellbook, as in the duel deck editor's book (ELDuelScreen
## BookView): the spell's icon in a dark slot with a bronze line, lit under
## the pointer and outlined while it has focus or is chosen. A real Button, so
## a click, Enter and keyboard focus work like any other choice. Without a
## card it is an empty book place.

const SLOT := Color("060606e8")
const LINE := Color("5c4c36")
const LINE_LIT := Color("8a7350")
const CHOSEN := Color("d6bb88")
const FOCUS := Color("fff4d6")
## The deck editor's copy count ink.
const COUNT_INK := Color("9de2d8")

var card := ""
var _count: Label
var _mark: Label

## A cell `side` pixels square for `code` ("" for an empty place).
static func make(profile: ELProfile, code: String, side := 52.0) -> ELExpeditionCardCell:
	var cell := ELExpeditionCardCell.new()
	cell.card = code
	cell.custom_minimum_size = Vector2(side, side)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cell.expand_icon = true
	cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_theme_constant_override("icon_max_width", int(side) - 4)
	cell.add_theme_constant_override("h_separation", 0)
	if not code.is_empty() and profile != null: cell.icon = profile.card_icon(code)
	cell.add_theme_stylebox_override("normal", _style(LINE, 1))
	cell.add_theme_stylebox_override("hover", _style(LINE_LIT, 1, Color("1a1610f0")))
	cell.add_theme_stylebox_override("pressed", _style(CHOSEN, 2))
	cell.add_theme_stylebox_override("hover_pressed", _style(CHOSEN, 2, Color("1a1610f0")))
	cell.add_theme_stylebox_override("disabled", _style(Color("3a3226"), 1, Color("0a0a0a90")))
	cell.add_theme_stylebox_override("focus", _style(FOCUS, 2, Color.TRANSPARENT))
	if code.is_empty():
		cell.disabled = true
		cell.focus_mode = Control.FOCUS_NONE
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cell

static func _style(line: Color, width: int, fill := SLOT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.set_border_width_all(width)
	style.set_content_margin_all(2)
	return style

## A copy count in the corner, as the deck editor shows it ("" hides it).
func set_count(value: String) -> void:
	if _count == null:
		_count = _corner(Control.PRESET_BOTTOM_LEFT, COUNT_INK)
		_count.name = "Count"
	_count.text = value
	_count.visible = not value.is_empty()

## A small marker in the top corner (the opening spell, a school's spell).
func set_mark(value: String, ink: Color) -> void:
	if _mark == null:
		_mark = _corner(Control.PRESET_TOP_RIGHT, ink)
		_mark.name = "Mark"
	_mark.text = value
	_mark.add_theme_color_override("font_color", ink)
	_mark.visible = not value.is_empty()

func _corner(corner: int, ink: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	label.set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE, 3)
	return label

func _draw() -> void:
	# Dim the icon of a choice that cannot be taken, as the shop dims stock
	# the hero cannot afford.
	if disabled and not card.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
