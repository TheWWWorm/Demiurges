class_name ELCombatTooltip
extends Control
## The battle screen's tooltips, drawn as the originals draw them: the
## Interface/black/ToolTip frame with bold italic text in the panel ink.
## The second game shows them on hover or right click; the first game shows
## them while the right button is held. Godot's own tooltip is
## kept invisible for the battle panel (`hidden_theme`) and its text is read
## from the hovered control, so every control keeps its tooltip_text.
##
## Placement (1024 panel units, pointer tip at `cursor`): below and right of
## the pointer when the frame fits, otherwise above it, pulled in from the
## right edge.

const INK := Color("d6bb88")
const FONT_SIZE := 16
const SLANT := 0.21
## The pointer's height: a frame goes above the pointer unless it fits below
## with the whole pointer clear of the bottom edge.
const POINTER := 32.0
const LINE := 17.0
## Seconds the pointer rests before the second game shows a tooltip.
const DELAY := 0.5
## Frame placement per edition: offset of the frame's top-left below the
## pointer, offset of its bottom-left when it goes above, inner margins
## (across, down) and the right and left screen limits.
const PLACEMENT := {
	"el2": {"below": Vector2(45, -8), "above": Vector2(-13, -13), "margin": Vector2(10, 10), "right": 33.0, "left": 0.0},
	"el1": {"below": Vector2(45, -8), "above": Vector2(-35, -25), "margin": Vector2(38, 28.5), "right": 24.0, "left": 12.0},
}
const PORTRAIT := Vector2(100, 70)
## The first game's frame: strips of the same texture rather than one square.
const FIRST_FRAME := {"border": 5.0, "fill": Rect2(150, 50, 50, 50),
	"top": Rect2(0, 50, 50, 5), "bottom": Rect2(200, 45, 50, 5), "left": Rect2(50, 50, 5, 50), "right": Rect2(145, 50, 5, 50),
	"top_left": Rect2(100, 0, 5, 5), "top_right": Rect2(145, 0, 5, 5), "bottom_left": Rect2(0, 45, 5, 5), "bottom_right": Rect2(95, 45, 5, 5)}

var profile: ELProfile
var panel: ELSecondMapTooltip
## The control or figure under the pointer and the seconds it has been there.
var subject: Control
var figure_subject := -1
var rest := 0.0
## Builds the content for a control: returns {} to fall back to its text.
var describe: Callable
var describe_figure: Callable
var blocked: Callable
var touch: ELTouchInput
## The deck editor can show the first game's frame on hover as well.
var hover_in_first_game := false
var _shown_key := ""
var _right_clicked := false

## Bold Arial slanted, with the upright bold advances: the originals' tooltip
## lines are as wide as plain bold text of the same size.
static func face() -> FontVariation:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	font.font_weight = 700
	var slanted := FontVariation.new()
	slanted.base_font = font
	slanted.variation_transform = Transform2D(Vector2(1.0, SLANT), Vector2(0.0, 1.0), Vector2.ZERO)
	return slanted

## A theme whose tooltip panel and text are invisible, for the controls whose
## tooltips this overlay draws instead.
static func hidden_theme() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("panel", "TooltipPanel", StyleBoxEmpty.new())
	theme.set_color("font_color", "TooltipLabel", Color.TRANSPARENT)
	theme.set_color("font_shadow_color", "TooltipLabel", Color.TRANSPARENT)
	theme.set_color("font_outline_color", "TooltipLabel", Color.TRANSPARENT)
	return theme

func setup(source: ELProfile) -> void:
	profile = source
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if panel != null: panel.queue_free()
	panel = ELSecondMapTooltip.new()
	panel.setup(profile, face())
	panel.ink = INK
	panel.font_size = FONT_SIZE
	panel.margin = _rule().margin
	if profile != null and profile.id == "el1": panel.pieces = FIRST_FRAME
	add_child(panel)
	set_process(true)

func _rule() -> Dictionary:
	return PLACEMENT.get(profile.id if profile != null else "el2", PLACEMENT.el2)

## Content of plain text: one label per line.
static func text_content(text: String) -> Dictionary:
	var labels: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		labels.append({"text": lines[i], "at": Vector2(0, i * LINE)})
	return {"labels": labels, "picture": {}, "flow": true}

static func spell_text(source: ELProfile, card: String, ether_cost := -1, card_title := "") -> String:
	var row: Dictionary = source.table("CombatSpells").get(card, {})
	var spell_class := str(row.get("Class", ""))
	var key: String = {"Creature": "T_SPELL_TYPE", "Sorcery": "T_SPELL_TYPE2", "Enchantment": "T_SPELL_TYPE3"}.get(spell_class, "")
	var title := card_title if not card_title.is_empty() else source.text(str(row.get("Name", card)))
	var creature: Dictionary = source.table("CombatCreatures").get(card, {})
	if spell_class == "Creature" and creature.has("Power"):
		title += " %d/%d" % [int(creature.Power), int(creature.get("Toughness", 0))]
	var kind := source.text(key)
	if not key.is_empty(): title = "%s: %s" % [spell_class if kind == key else kind, title]
	var cost := source.text("T_COST")
	var mana := source.text("T_MANA")
	var lines := [title, "%s %d %s" % ["Cost:" if cost == "T_COST" else cost, int(row.get("Cost", 0)) if ether_cost < 0 else ether_cost, "ether" if mana == "T_MANA" else mana]]
	var description := source.card_description(card)
	if not description.is_empty() and description != str(row.get("ToolTip", card)): lines.append(description)
	return "\n".join(lines)

## A hero card: the portrait and lines beside it (second game), or a centred
## title over the portrait and lines (first game).
static func hero_content(edition: String, picture: Texture2D, title: String, lines: Array) -> Dictionary:
	var labels: Array = []
	if edition == "el1":
		labels.append({"text": title, "at": Vector2(PORTRAIT.x * 0.5 + 20, 0), "centre": true})
		for i in lines.size(): labels.append({"text": str(lines[i]), "at": Vector2(PORTRAIT.x + 16, 20 + i * LINE)})
		# The card sits closer to its frame than text lines do.
		return {"labels": labels, "picture": {"texture": picture, "at": Vector2(0, 20), "size": PORTRAIT}, "margin": Vector2(20, 9)}
	labels.append({"text": title, "at": Vector2(PORTRAIT.x + 16, 9)})
	for i in lines.size(): labels.append({"text": str(lines[i]), "at": Vector2(PORTRAIT.x + 16, 9 + (i + 1) * LINE)})
	return {"labels": labels, "picture": {"texture": picture, "at": Vector2.ZERO, "size": PORTRAIT}}

## Top-left of a frame of `frame` size for the pointer at `cursor` on a panel
## of `screen` size.
static func place(edition: String, frame: Vector2, cursor: Vector2, screen: Vector2) -> Vector2:
	var rule: Dictionary = PLACEMENT.get(edition, PLACEMENT.el2)
	var at: Vector2 = cursor + rule.below
	if cursor.y + POINTER + frame.y > screen.y:
		at = cursor + Vector2(rule.above.x, rule.above.y - frame.y)
	at.x = minf(at.x, screen.x - float(rule.right) - frame.x)
	at.x = maxf(at.x, float(rule.left))
	at.y = maxf(at.y, 0.0)
	return at

func hide_tip() -> void:
	subject = null
	figure_subject = -1
	rest = 0.0
	_shown_key = ""
	if panel != null: panel.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not event.shift_pressed:
		_right_clicked = true

func _process(delta: float) -> void:
	var right_clicked := _right_clicked
	_right_clicked = false
	if panel == null or not is_visible_in_tree(): return
	if blocked.is_valid() and blocked.call():
		hide_tip()
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var first := profile != null and profile.id == "el1"
	var touch_hold := touch != null and touch.holding()
	var inspecting := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or touch_hold
	if first and not hover_in_first_game and not inspecting:
		hide_tip()
		return
	if hovered != null and not _owns(hovered):
		hide_tip()
		return
	var point := touch.hold_position() if touch_hold else get_viewport().get_mouse_position()
	var figure := hovered == null
	var content: Dictionary = describe_figure.call(point) if figure and describe_figure.is_valid() else {}
	var id := int(content.get("figure_id", -1))
	if figure and id < 0:
		hide_tip()
		return
	if hovered != subject or id != figure_subject:
		hide_tip()
		subject = hovered
		figure_subject = id
	rest += delta
	if inspecting or right_clicked: rest = maxf(rest, DELAY)
	if rest < DELAY: return
	var cursor := get_global_transform_with_canvas().affine_inverse() * point
	var at := Vector2.ZERO
	if not figure: at = hovered.get_global_transform_with_canvas().affine_inverse() * point
	if not figure and describe.is_valid():
		content = describe.call(hovered, at)
	if content.is_empty():
		var text := hovered.atr(hovered.get_tooltip(at)).strip_edges()
		if text.is_empty():
			if panel.visible: panel.hide()
			_shown_key = ""
			return
		content = text_content(text)
	var key := str(content.hash())
	if key != _shown_key:
		_shown_key = key
		panel.set_content(-1 - id if figure else hovered.get_instance_id(), content)
		_centre_titles(content)
	var screen := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var fit := minf(1.0, minf(screen.size.x / maxf(1.0, panel.size.x), screen.size.y / maxf(1.0, panel.size.y)))
	panel.scale = Vector2.ONE * fit
	var frame := panel.size * fit
	var position_on_screen := place(profile.id if profile != null else "el2", frame, cursor - screen.position, screen.size)
	panel.position = screen.position + position_on_screen.clamp(Vector2.ZERO, (screen.size - frame).max(Vector2.ZERO))
	if not panel.visible:
		panel.show()
	move_to_front()

func _owns(control: Control) -> bool:
	var owner_node := get_parent()
	# The opponent's cast icons are drawn over the battle, outside the HUD.
	if control is ELCombatNotices: return true
	return owner_node != null and owner_node.is_ancestor_of(control) and control != self and not is_ancestor_of(control)

## First-game hero titles are centred over the whole frame.
func _centre_titles(content: Dictionary) -> void:
	var labels: Array = content.get("labels", [])
	for i in mini(labels.size(), panel._labels.size()):
		if not labels[i].get("centre", false): continue
		var label: Label = panel._labels[i]
		label.position.x = (panel.size.x - label.size.x) * 0.5
