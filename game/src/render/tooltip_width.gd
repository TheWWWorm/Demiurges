class_name ELTooltipWidth
extends Node
## Every tooltip has a greatest width. Godot's own tooltip (a Label of the
## TooltipLabel type, made for any control's tooltip_text) never wraps, so a
## long spell or option description ran across most of the window. Running
## as an autoload, this catches that label as the tooltip opens, before its
## popup is sized, and wraps it at MAX_WIDTH; the remake's own tooltip panels
## call fit() on their text labels.
##
## It also keeps blank tooltips from opening: Godot strips only plain
## whitespace from a tooltip's text, and a control with its own tooltip maker
## opens one even for no text at all, so a space-only or empty text (some of
## the originals' tooltip strings are one space or a no-break space) showed
## an empty frame. `blank()` is the test the remake's own tooltips use too.

## The widest a tooltip's text runs before it wraps, in the window's design
## units (ELSecondMapTooltip.MAX_LABEL_WIDTH, the map tooltips' width). A
## number here: naming that class compiled most of the game's scripts with
## this autoload, before the first frame (scenes/boot.tscn loads them in a
## thread).
const MAX_WIDTH := 480.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is Label and (node as Label).theme_type_variation == &"TooltipLabel" and node.get_parent() is PopupPanel:
		fit(node)
	elif node is PopupPanel and (node as PopupPanel).theme_type_variation == &"TooltipPanel":
		# The viewport shows the panel right after adding it; hidden at the
		# frame's end, before it is drawn. The viewport keeps it as its open
		# tooltip until the pointer moves on, so it is not opened again.
		if _empty(node): node.hide.call_deferred()

## True when `text` shows nothing: empty, or only spaces, line breaks,
## no-break and other Unicode spaces or zero-width characters.
static func blank(text: String) -> bool:
	if text.strip_edges().is_empty(): return true
	if _spaces == null:
		_spaces = RegEx.new()
		_spaces.compile(r"[\s\x{00A0}\x{1680}\x{2000}-\x{200D}\x{2028}\x{2029}\x{202F}\x{205F}\x{2060}\x{3000}\x{FEFF}]")
	return _spaces.sub(text, "", true).is_empty()

static var _spaces: RegEx

## A tooltip's content with nothing to show: only blank text, containers
## and panels. A picture or a control drawn by a script counts as something.
static func _empty(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible: continue
		if child is Label:
			if not blank((child as Label).text): return false
		elif child is RichTextLabel:
			if not blank((child as RichTextLabel).get_parsed_text()): return false
		elif child is Container or child is Panel or (child is Control and child.get_script() == null and child.get_class() == "Control"):
			if not _empty(child): return false
		else:
			return false
	return true

## Wraps `label` at `width` when its longest line is wider; shorter text keeps
## its own width. Call it again after the text changes.
static func fit(label: Label, width := MAX_WIDTH) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 0.0
	if label.get_minimum_size().x <= width: return
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
