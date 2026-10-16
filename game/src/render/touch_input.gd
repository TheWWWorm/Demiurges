class_name ELTouchInput
extends Node
## Touch controls for phones, tablets and touch browsers (a remake addition).
## Active only on a touch device (or with --touch / a test hook), so mouse and
## keyboard play is unchanged. A touch is held until its intent is known:
## - tap: one left click (two quick taps on the same spot: a double click);
## - hold without moving: the right click of the item under the finger, or its
##   hover tooltip when the item has one; release ends the press;
## - one-finger drag on a panel: a left drag (scroll bars, sliders);
## - one-finger drag on the world: pans the map, turns the battle camera;
## - two fingers: drag or twist turns and tilts, pinch zooms.
## Camera owners join the "touch_camera" group and provide touch_camera_ready,
## touch_pan(from, to), touch_orbit(turn, tilt) and touch_zoom(factor).

const HOLD_SECONDS := 0.5
const DOUBLE_TAP_MS := 330

## Touch mode in use; read by views that change their behaviour on touch
## (for example no edge scrolling under a finger).
static var enabled := false

var fingers: Dictionary = {}
var _primary := -1
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _control: Control
var _elapsed := 0.0
## "", "drag" (left drag on a panel), "world" (camera drag), "hold", "pair", "done".
var _mode := ""
var _right_down := false
var _pair := PackedVector2Array()
var _tap_ms := -100000
var _tap_at := Vector2(-1000, -1000)
var _emitting := false
var bar: CanvasLayer

## True on a phone or tablet, in a touch-first browser, or with --touch.
static func wanted() -> bool:
	if OS.get_cmdline_user_args().has("--touch") or OS.has_feature("mobile"): return true
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches", true))
	return false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_enabled(wanted())

func _exit_tree() -> void:
	if enabled:
		enabled = false
		Input.set_emulate_mouse_from_touch(true)

func set_enabled(on: bool) -> void:
	enabled = on
	# Our own mouse events replace the engine's emulation while touch is on.
	Input.set_emulate_mouse_from_touch(not on)
	if on and bar == null:
		bar = preload("res://src/render/touch_bar.gd").new()
		add_child(bar)
	if bar != null: bar.visible = on

## Minimum finger travel (in viewport units) before a touch counts as a drag.
func slop() -> float:
	return 14.0 / maxf(0.1, get_viewport().get_final_transform().get_scale().x) * _density()

func _density() -> float:
	if OS.has_feature("mobile"): return maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	return 1.0

func _input(event: InputEvent) -> void:
	if _emitting or not enabled: return
	if event is InputEventMagnifyGesture:
		var target := camera_owner()
		if target != null and (event as InputEventMagnifyGesture).factor > 0.0:
			target.call("touch_zoom", (event as InputEventMagnifyGesture).factor)
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if event is InputEventScreenTouch:
		if event.pressed: _press(event.index, event.position)
		else: _release(event.index, event.position, event.canceled)
	else:
		_drag(event.index, event.position)
	# After the events sent above: a nested delivery resets the handled flag.
	get_viewport().set_input_as_handled()

## The visible camera that gestures move, or null (menus, windows, dialogs).
func camera_owner() -> Node:
	var found: Node = null
	for node: Node in get_tree().get_nodes_in_group("touch_camera"):
		if is_instance_valid(node) and node.is_inside_tree() and bool(node.call("touch_camera_ready")): found = node
	return found

func _press(index: int, point: Vector2) -> void:
	fingers[index] = point
	if fingers.size() == 1:
		_primary = index
		_start = point
		_last = point
		_elapsed = 0.0
		_mode = ""
		_hover(point)
		_control = get_viewport().gui_get_hovered_control()
		return
	# A second finger turns a pending touch into a camera gesture.
	if _mode == "drag": button(_last, false)
	if _right_down:
		button(_last, false, MOUSE_BUTTON_RIGHT)
		_right_down = false
	_mode = "pair"
	_tap_ms = -100000
	_pair = PackedVector2Array(fingers.values().slice(0, 2))

func _drag(index: int, point: Vector2) -> void:
	if not fingers.has(index): return
	fingers[index] = point
	if fingers.size() >= 2:
		var now := PackedVector2Array(fingers.values().slice(0, 2))
		if _pair.size() == 2: _pair_gesture(_pair, now)
		_pair = now
		return
	if index != _primary or _mode in ["pair", "done"]: return
	var relative := point - _last
	_last = point
	if _mode == "hold":
		motion(point, relative, MOUSE_BUTTON_MASK_RIGHT if _right_down else 0)
		return
	if _mode == "":
		if point.distance_to(_start) < slop(): return
		if _is_world(_control) and camera_owner() != null:
			_mode = "world"
			relative = point - _start
		else:
			_mode = "drag"
			button(_start, true)
	if _mode == "world":
		var target := camera_owner()
		if target != null: target.call("touch_pan", point - relative, point)
	elif _mode == "drag":
		motion(point, relative, MOUSE_BUTTON_MASK_LEFT)

## Two fingers: the midpoint's travel and the twist turn and tilt; the change
## of spread zooms.
func _pair_gesture(before: PackedVector2Array, now: PackedVector2Array) -> void:
	var target := camera_owner()
	if target == null: return
	var mid_before := (before[0] + before[1]) * 0.5
	var mid_now := (now[0] + now[1]) * 0.5
	var twist := wrapf((now[1] - now[0]).angle() - (before[1] - before[0]).angle(), -PI, PI)
	# The mouse camera's drag rates: 0.006 rad a unit across, 0.004 down.
	var turn := -(mid_now.x - mid_before.x) * 0.006 - twist
	var tilt := (mid_now.y - mid_before.y) * 0.004
	if absf(turn) > 0.0001 or absf(tilt) > 0.0001: target.call("touch_orbit", turn, tilt)
	var spread_before := before[0].distance_to(before[1])
	var spread_now := now[0].distance_to(now[1])
	if spread_before > 4.0 and spread_now > 4.0 and not is_equal_approx(spread_before, spread_now):
		target.call("touch_zoom", spread_now / spread_before)

func _release(index: int, point: Vector2, canceled: bool) -> void:
	if not fingers.has(index): return
	fingers.erase(index)
	if index == _primary:
		match _mode:
			"drag": button(point, false)
			"hold":
				if _right_down: button(point, false, MOUSE_BUTTON_RIGHT)
				_right_down = false
			"":
				if not canceled:
					var now := Time.get_ticks_msec()
					var double := now - _tap_ms < DOUBLE_TAP_MS and point.distance_to(_tap_at) < slop() * 2.0
					_tap_ms = -100000 if double else now
					_tap_at = point
					button(point, true, MOUSE_BUTTON_LEFT, double)
					button(point, false, MOUSE_BUTTON_LEFT, double)
		_primary = -1
		_mode = "done" if not fingers.is_empty() else ""
	if fingers.size() < 2: _pair.clear()
	if fingers.is_empty():
		_mode = ""
		_control = null

func _process(delta: float) -> void:
	if not enabled or _primary < 0 or _mode != "" or fingers.size() != 1: return
	_elapsed += delta
	if _elapsed < HOLD_SECONDS: return
	_mode = "hold"
	_tap_ms = -100000
	# An item with its own tooltip shows it (the hover stays under the
	# finger); anything else gets the right click it has with a mouse.
	if is_instance_valid(_control) and not _control.get_tooltip(_control.get_global_transform_with_canvas().affine_inverse() * _start).is_empty():
		return
	_right_down = true
	button(_start, true, MOUSE_BUTTON_RIGHT)

## True when the touch began on the 3D view rather than on a panel. Panels
## that cover the screen but let the view through join "touch_world".
func _is_world(control: Control) -> bool:
	if not is_instance_valid(control): return true
	return control.is_in_group("touch_world")

## A cursor move to the touched point, delivered at once so the panel under
## the finger is known before deciding what the gesture is.
func _hover(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = point
	event.global_position = point
	_emitting = true
	get_viewport().push_input(event, true)
	_emitting = false

func motion(point: Vector2, relative: Vector2, mask := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = mask
	_emitting = true
	get_viewport().push_input(event, true)
	_emitting = false

func button(point: Vector2, pressed: bool, which := MOUSE_BUTTON_LEFT, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.device = InputEvent.DEVICE_ID_EMULATION
	event.position = point
	event.global_position = point
	event.button_index = which
	event.pressed = pressed
	event.double_click = double
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	_emitting = true
	get_viewport().push_input(event, true)
	_emitting = false

## Presses and releases a key, as the touch bar and Android Back do.
static func tap_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = pressed
		Input.parse_input_event(key)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not fingers.is_empty():
		if _mode == "drag": button(_last, false)
		if _right_down: button(_last, false, MOUSE_BUTTON_RIGHT)
		_right_down = false
		fingers.clear()
		_primary = -1
		_mode = ""
		_pair.clear()
