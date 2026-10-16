extends CanvasLayer
## A small row of touch buttons for actions that otherwise need a keyboard:
## Back (Esc) everywhere, plus the camera owner's own keys (quick save/load on
## the map, camera reset in battle). Shown only in touch mode.

var row: HBoxContainer
var _keys: Array = []

func _init() -> void:
	layer = 120
	row = HBoxContainer.new()
	row.name = "TouchBar"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

func _process(_delta: float) -> void:
	if not visible: return
	var keys: Array = [["Back", KEY_ESCAPE]]
	var cam: Node = get_parent().call("camera_owner") if get_parent() != null and get_parent().has_method("camera_owner") else null
	if cam != null and cam.has_method("touch_bar_keys"): keys.append_array(cam.call("touch_bar_keys"))
	if keys != _keys:
		_keys = keys
		_rebuild()
	var screen := row.get_viewport_rect().size if row.is_inside_tree() else Vector2.ZERO
	row.size = row.get_combined_minimum_size()
	# Top centre: the corners hold the original menu, minimap and day buttons.
	row.position = Vector2(roundf((screen.x - row.size.x) * 0.5), 6.0)

func _rebuild() -> void:
	for child: Node in row.get_children(): child.queue_free()
	for entry: Array in _keys:
		var button := Button.new()
		button.text = str(entry[0])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(74, 44)
		button.add_theme_font_size_override("font_size", 16)
		button.set_meta("touch_key", entry[1])
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.05, 0.05, 0.06, 0.62 if state != "pressed" else 0.85)
			box.border_color = Color(0.75, 0.66, 0.42, 0.55)
			box.set_border_width_all(1)
			box.set_corner_radius_all(6)
			button.add_theme_stylebox_override(state, box)
		button.add_theme_color_override("font_color", Color(0.93, 0.88, 0.74, 0.92))
		var keycode: Key = entry[1]
		button.pressed.connect(func(): ELTouchInput.tap_key(keycode))
		row.add_child(button)
