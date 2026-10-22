class_name ELCombatTooltip
extends Control
## The battle screen's tooltips, drawn as the originals draw them: the
## Interface/black/ToolTip frame with bold italic text in the panel ink.
## The second game shows them when the pointer rests on a control; the first
## game only while the right button is held over it. Godot's own tooltip is
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
## The control under the pointer and the seconds it has been there.
var subject: Control
var rest := 0.0
## Builds the content for a control: returns {} to fall back to its text.
var describe: Callable
var _shown_key := ""

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
	return {"labels": labels, "picture": {}}

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
	rest = 0.0
	_shown_key = ""
	if panel != null: panel.hide()

func _process(delta: float) -> void:
	if panel == null or not is_visible_in_tree(): return
	var hovered := get_viewport().gui_get_hovered_control()
	var first := profile != null and profile.id == "el1"
	if hovered == null or not _owns(hovered) or (first and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		hide_tip()
		return
	if hovered != subject:
		hide_tip()
		subject = hovered
	rest += delta
	if not first and rest < DELAY: return
	var cursor := get_local_mouse_position()
	var content: Dictionary = describe.call(hovered, hovered.get_local_mouse_position()) if describe.is_valid() else {}
	if content.is_empty():
		var text := hovered.get_tooltip(hovered.get_local_mouse_position()).strip_edges()
		if text.is_empty():
			if panel.visible: panel.hide()
			_shown_key = ""
			return
		content = text_content(text)
	var key := str(content.hash())
	if key != _shown_key:
		_shown_key = key
		panel.set_content(hovered.get_instance_id(), content)
		_centre_titles(content)
	panel.position = place(profile.id if profile != null else "el2", panel.size, cursor, size)
	if not panel.visible:
		panel.show()
	move_to_front()

func _owns(control: Control) -> bool:
	var owner_node := get_parent()
	return owner_node != null and owner_node.is_ancestor_of(control) and control != self and not is_ancestor_of(control)

## First-game hero titles are centred over the whole frame.
func _centre_titles(content: Dictionary) -> void:
	var labels: Array = content.get("labels", [])
	for i in mini(labels.size(), panel._labels.size()):
		if not labels[i].get("centre", false): continue
		var label: Label = panel._labels[i]
		label.position.x = (panel.size.x - label.size.x) * 0.5
