class_name ELListThumb
extends Control
## The position thumb in a drawn list's scroll track, between the original's
## up and down arrows (which the art gives no thumb of its own). It shows how
## much of the list is in view and where; a drag moves it, a click on the
## track pages. `list` keeps `offset` and `visible_rows()`; `count` gives the
## number of rows.

var list: Control
var count: Callable
var _drag_from := -1.0
var _drag_offset := 0
var _hover := false

## Fills the track between `up` and `down` (either may be missing: then the
## list's own height on its right edge).
static func attach(parent: Node, target: Control, rows: Callable, up: Control, down: Control) -> ELListThumb:
	var thumb := ELListThumb.new()
	thumb.name = "ListThumb"
	thumb.list = target
	thumb.count = rows
	var x := up.position.x if up != null else target.position.x + target.size.x
	var width := up.size.x if up != null else 14.0
	var top := up.position.y + up.size.y if up != null else target.position.y
	var bottom := down.position.y if down != null else target.position.y + target.size.y
	thumb.position = Vector2(x, top)
	thumb.size = Vector2(width, maxf(0.0, bottom - top))
	parent.add_child(thumb)
	target.draw.connect(thumb.queue_redraw)
	return thumb

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_MOUSE_ENTER:
		_hover = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()

func _total() -> int:
	return int(count.call()) if count.is_valid() else 0

func _shown() -> int:
	return maxi(1, int(list.visible_rows())) if is_instance_valid(list) else 1

func _span() -> int:
	return maxi(0, _total() - _shown())

## The thumb's rectangle, empty while every row is in view.
func thumb_rect() -> Rect2:
	var total := _total()
	if not is_instance_valid(list) or total <= _shown() or size.y < 8.0: return Rect2()
	var inset := 2.0
	var track := size.y - inset * 2.0
	var length := clampf(track * float(_shown()) / float(total), minf(18.0, track), track)
	var at := clampf(float(int(list.offset)) / float(_span()), 0.0, 1.0) * (track - length)
	return Rect2(inset, inset + at, size.x - inset * 2.0, length)

func _set_offset(value: int) -> void:
	var clamped := clampi(value, 0, _span())
	if clamped == int(list.offset): return
	list.offset = clamped
	list.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var grip := thumb_rect()
	if grip.size.y <= 0.0: return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_set_offset(int(list.offset) + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: _drag_from = -1.0
			elif grip.has_point(event.position):
				_drag_from = event.position.y
				_drag_offset = int(list.offset)
			else:
				_set_offset(int(list.offset) + (_shown() if event.position.y > grip.end.y else -_shown()))
		accept_event()
	elif event is InputEventMouseMotion and _drag_from >= 0.0:
		var free := size.y - 4.0 - grip.size.y
		if free > 0.0: _set_offset(_drag_offset + roundi((event.position.y - _drag_from) / free * _span()))
		accept_event()

func _draw() -> void:
	var grip := thumb_rect()
	if grip.size.y <= 0.0: return
	# The menu kit's scroll bar grip (ELMenuKit), lit under the pointer.
	draw_rect(grip, Color("66553c") if _hover or _drag_from >= 0.0 else Color("4b3f2e"))
	draw_rect(grip, Color("8a7350"), false, 1.0)
