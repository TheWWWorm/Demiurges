class_name ELCheckEnter
extends Node
## Enter (and keypad Enter) presses the check (OK) button that is shown, as a
## click on it would, in both games (player report #264). Runs as an autoload;
## each dialog window gets one of its own for the keys sent to that window.
##
## The check buttons are the push buttons drawn with one of the games' check
## plates (CHECK_ART); ELUiSounds.bind marks them as every original button is
## made. Enter presses the one on the topmost screen or dialog: shown, enabled,
## not covered where a click would land, on the highest canvas layer and then
## the latest in tree order. Two check buttons side by side on that panel are
## left alone rather than guessed between.
##
## Everything that already answers Enter keeps it: screens that take the key
## themselves, a focused button, the battle and the map. This only sees an
## Enter nothing else took. A focused one-line text field takes Enter, so the
## field's submit presses the check button instead, unless the field has a
## submit action of its own; multi-line text keeps Enter for new lines.

const GROUP := &"el_check_button"
## The check plates' pieces (texture file, then its source rectangles) in the
## first and second games' interface art.
const CHECK_ART := {
	"adv_panel_1": [Rect2i(202, 109, 40, 40), Rect2i(202, 188, 50, 27)],
	"tooltip": [Rect2i(206, 115, 50, 27), Rect2i(0, 180, 50, 50)],
	"compain_screen_1": [Rect2i(206, 40, 40, 40), Rect2i(0, 93, 50, 27), Rect2i(138, 93, 38, 32)],
	"diplomacy_panel_17": [Rect2i(181, 101, 38, 32)],
	"inetduel_panel_6": [Rect2i(95, 128, 40, 40)],
	"multiduel_panel_6": [Rect2i(95, 128, 40, 40)],
	"mission_screen_1": [Rect2i(206, 27, 50, 27)],
	"options_panel_12": [Rect2i(167, 154, 40, 40)],
	"preset_panel_9": [Rect2i(154, 150, 40, 40)],
	"saveload_panel_6": [Rect2i(0, 80, 40, 40)],
	"a6-int-invent-08": [Rect2i(0, 89, 61, 41)],
	"a6-int-message": [Rect2i(123, 0, 50, 27)],
	"a6-int-shop-08": [Rect2i(0, 89, 61, 41)],
	"a6-int-upgrade-02": [Rect2i(0, 123, 61, 41)],
}
const _ENTER_FRAME := &"check_enter_frame"
const _LISTENER := &"check_enter_listener"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Only the autoload watches the tree; the copies in dialogs just listen.
	if get_parent() != get_tree().root: return
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is LineEdit:
		var edit := node as LineEdit
		# Once per field, however often it enters the tree.
		if not edit.has_meta(_LISTENER):
			edit.set_meta(_LISTENER, true)
			edit.gui_input.connect(_note_enter.bind(edit))
			edit.text_submitted.connect(_on_text_submitted.bind(edit))
	elif node is Window and not node is Popup and not node.has_meta(_LISTENER):
		node.set_meta(_LISTENER, true)
		var listener := ELCheckEnter.new()
		listener.name = "CheckEnter"
		node.add_child.call_deferred(listener, false, Node.INTERNAL_MODE_BACK)

# --- Marking ---------------------------------------------------------------------

## Marks `button` as a check button when its control is drawn with a check
## plate (called for every original button, see ELUiSounds.bind).
static func mark(button: BaseButton, profile: ELProfile, control: String) -> void:
	if button == null or profile == null or button.toggle_mode: return
	if is_check(profile, control): button.add_to_group(GROUP)

## True for an original push button drawn with a check plate.
static func is_check(profile: ELProfile, control: String) -> bool:
	if profile.check_buttons.is_empty():
		var push := {}
		for row: Dictionary in profile.table("Controls").values():
			if str(row.get("Type", "")) == "PushButton": push[str(row.get("Name", ""))] = true
		var files := {}
		for row: Dictionary in profile.table("InterfaceTextures").values():
			files[str(row.get("Name", ""))] = str(row.get("Path", "")).replace("\\", "/").get_file().get_basename().to_lower()
		for row: Dictionary in profile.table("CutParts").values():
			var name := str(row.get("Ctrl", ""))
			if not push.has(name): continue
			var raw: Variant = row.get("Msk", [])
			var masks: Array = raw if raw is Array else [raw]
			if not "Free" in masks or "Light" in masks: continue
			var source := Rect2i(int(row.get("TxtL", 0)), int(row.get("TxtT", 0)), int(row.get("TxtW", 0)), int(row.get("TxtH", 0)))
			if source in CHECK_ART.get(files.get(row.get("Txt", ""), ""), []): profile.check_buttons[name] = true
		profile.check_buttons["_loaded"] = false
	return bool(profile.check_buttons.get(control, false))

# --- Choosing and pressing -------------------------------------------------------

static func is_enter(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER] \
		and not (key.alt_pressed or key.ctrl_pressed or key.meta_pressed)

## The check button Enter presses in `viewport` (only those under `scope` when
## given, only on canvas layer `min_layer` or above): the topmost one a click
## would reach. Null when none is shown, or when two share the topmost panel.
## It may be disabled (Enter then does nothing).
static func target(viewport: Viewport, scope: Node = null, min_layer := -(1 << 30)) -> BaseButton:
	if viewport == null: return null
	var shown: Array[Control] = []
	_collect(viewport, true, shown)
	var order := {}
	for index in shown.size(): order[shown[index]] = index
	var reachable: Array[BaseButton] = []
	for node: Node in viewport.get_tree().get_nodes_in_group(GROUP):
		var button := node as BaseButton
		if button == null or not order.has(button) or button.get_viewport() != viewport: continue
		if scope != null and scope != button and not scope.is_ancestor_of(button): continue
		if _layer(button) < min_layer or _covered(button, shown, order): continue
		reachable.append(button)
	if reachable.is_empty(): return null
	var top := reachable[0]
	for button: BaseButton in reachable:
		if _above(button, top, order): top = button
	for button: BaseButton in reachable:
		if button != top and button.get_parent() == top.get_parent() and _layer(button) == _layer(top): return null
	return top

## Presses `button` as a click does (its pressed signal, with its sound);
## nothing for a disabled one.
static func press(button: BaseButton) -> bool:
	if button == null or not is_instance_valid(button) or button.disabled: return false
	button.pressed.emit()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not is_enter(event): return
	var button := target(get_viewport())
	if button == null: return
	get_viewport().set_input_as_handled()
	press(button)

## A focused one-line field took Enter: its submit presses the check button
## when the field has no submit action of its own.
func _on_text_submitted(_text: String, edit: LineEdit) -> void:
	if not is_instance_valid(edit) or not edit.is_visible_in_tree(): return
	if edit.get_meta(_ENTER_FRAME, -1) != Engine.get_process_frames(): return
	edit.remove_meta(_ENTER_FRAME)
	for connection: Dictionary in edit.text_submitted.get_connections():
		if (connection.callable as Callable).get_object() != self: return
	var button := target(edit.get_viewport(), null, _layer(edit))
	if button == null: return
	# The press may close the field's screen before the field marks the key
	# as taken: mark it here so that nothing else answers the same Enter.
	edit.get_viewport().set_input_as_handled()
	press(button)

func _note_enter(event: InputEvent, edit: LineEdit) -> void:
	if is_enter(event): edit.set_meta(_ENTER_FRAME, Engine.get_process_frames())

# --- Where a click lands ---------------------------------------------------------

## The shown controls under `node` in drawing order (one viewport: other
## windows and sub-viewports are left out).
static func _collect(node: Node, root: bool, into: Array[Control]) -> void:
	if not root and (node is Window or node is SubViewport): return
	if node is CanvasItem and not (node as CanvasItem).visible: return
	if node is CanvasLayer and not (node as CanvasLayer).visible: return
	if node is Control: into.append(node)
	for child: Node in node.get_children(true): _collect(child, false, into)

static func _layer(item: CanvasItem) -> int:
	var layer := item.get_canvas_layer_node()
	return layer.layer if layer != null else 0

## True when `a` is drawn (and picked) over `b`.
static func _above(a: Control, b: Control, order: Dictionary) -> bool:
	var la := _layer(a)
	var lb := _layer(b)
	return la > lb or (la == lb and int(order[a]) > int(order[b]))

## True when a click on the middle of `button` would land on another control.
static func _covered(button: BaseButton, shown: Array[Control], order: Dictionary) -> bool:
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	for control: Control in shown:
		if control == button or control.mouse_filter == Control.MOUSE_FILTER_IGNORE or button.is_ancestor_of(control): continue
		if not _above(control, button, order) or not _contains(control, point): continue
		var clipped := false
		var parent := control.get_parent_control()
		while parent != null and not clipped:
			if parent.clip_contents and not _contains(parent, point): clipped = true
			parent = parent.get_parent_control()
		if not clipped: return true
	return false

static func _contains(control: Control, point: Vector2) -> bool:
	var local := control.get_global_transform_with_canvas().affine_inverse() * point
	return Rect2(Vector2.ZERO, control.size).has_point(local)
