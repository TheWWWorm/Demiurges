class_name ELTooltipWidth
extends Node
## Every tooltip has a greatest width. Godot's own tooltip (a Label of the
## TooltipLabel type, made for any control's tooltip_text) never wraps, so a
## long spell or option description ran across most of the window. Running
## as an autoload, this catches that label as the tooltip opens, before its
## popup is sized, and wraps it at MAX_WIDTH; the remake's own tooltip panels
## call fit() on their text labels.

## The widest a tooltip's text runs before it wraps, in the window's design
## units (ELSecondMapTooltip.MAX_LABEL_WIDTH, the map tooltips' width).
const MAX_WIDTH := ELSecondMapTooltip.MAX_LABEL_WIDTH

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is Label and (node as Label).theme_type_variation == &"TooltipLabel" and node.get_parent() is PopupPanel:
		fit(node)

## Wraps `label` at `width` when its longest line is wider; shorter text keeps
## its own width. Call it again after the text changes.
static func fit(label: Label, width := MAX_WIDTH) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 0.0
	if label.get_minimum_size().x <= width: return
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
