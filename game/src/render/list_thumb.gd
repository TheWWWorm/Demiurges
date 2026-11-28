class_name ELListThumb
extends Control
## The position thumb in a drawn list's scroll track, between the original's
## up and down arrows. With the original art (`texture`, the 11x12 scroller
## thumb ELArtDropList uses, as the encyclopedia shows it) the thumb keeps its
## size and travels the track, centred while nothing scrolls (issue #302);
## without it a plain grip shows how much of the list is in view. A drag
## moves it. A click on the track moves the original thumb at most five
## steps towards the pointer, never past it, as the original scroller does
## (issue #331); the plain grip pages.
##
## The list is read through callables: `offset` (the first shown step),
## `last` (the last offset), `scroll_to` (sets the offset) and `page` (steps
## per page). `attach` fills them from a list Control with `offset` and
## `visible_rows()`.

var offset: Callable
var last: Callable
var scroll_to: Callable
var page: Callable
var texture: Texture2D
var _drag_from := -1.0
var _drag_offset := 0
var _hover := false

## Fills the track between `up` and `down` (either may be missing: then the
## list's own height on its right edge).
static func attach(parent: Node, target: Control, rows: Callable, up: Control, down: Control, art: Texture2D = null) -> ELListThumb:
	var thumb := ELListThumb.new()
	thumb.offset = func() -> int: return int(target.offset) if is_instance_valid(target) else 0
	thumb.page = func() -> int: return maxi(1, int(target.visible_rows())) if is_instance_valid(target) else 1
	thumb.last = func() -> int: return maxi(0, int(rows.call()) - int(thumb.page.call())) if rows.is_valid() else 0
	thumb.scroll_to = func(value: int) -> void:
		if not is_instance_valid(target) or value == int(target.offset): return
		target.offset = value
		target.queue_redraw()
	var x := up.position.x if up != null else target.position.x + target.size.x
	var width := up.size.x if up != null else 14.0
	var top := up.position.y + up.size.y if up != null else target.position.y
	var bottom := down.position.y if down != null else target.position.y + target.size.y
	thumb.place(parent, Rect2(x, top, width, maxf(0.0, bottom - top)), art)
	target.draw.connect(thumb.queue_redraw)
	return thumb

## Puts the thumb's track at `track` under `parent`.
func place(parent: Node, track: Rect2, art: Texture2D) -> void:
	name = "ListThumb"
	texture = art
	position = track.position
	size = track.size
	parent.add_child(self)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_MOUSE_ENTER:
		_hover = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()

func _last() -> int:
	return maxi(0, int(last.call())) if last.is_valid() else 0

func _offset() -> int:
	return int(offset.call()) if offset.is_valid() else 0

func _page() -> int:
	return maxi(1, int(page.call())) if page.is_valid() else 1

## The thumb's rectangle: the original art's size travelling the track
## (centred while nothing scrolls); the plain grip, empty while every row
## is in view, without the art.
func thumb_rect(at := -1) -> Rect2:
	if size.y < 8.0: return Rect2()
	var span := _last()
	var index := _offset() if at < 0 else at
	if texture != null:
		var art := ELArtDropList.THUMB_SOURCE.size
		var travel := size.y - art.y
		var y := travel * 0.5 if span == 0 else travel * clampf(float(index) / span, 0.0, 1.0)
		return Rect2(floorf((size.x - art.x) * 0.5), floorf(y), art.x, art.y)
	if span == 0: return Rect2()
	var inset := 2.0
	var track := size.y - inset * 2.0
	var shown := float(_page())
	var length := clampf(track * shown / (shown + span), minf(18.0, track), track)
	var where := clampf(float(index) / float(span), 0.0, 1.0) * (track - length)
	return Rect2(inset, inset + where, size.x - inset * 2.0, length)

## The offset whose thumb top is nearest `y`.
func _nearest(y: float) -> int:
	var best := 0
	for index in _last() + 1:
		if absf(thumb_rect(index).position.y - y) < absf(thumb_rect(best).position.y - y): best = index
	return best

func _set_offset(value: int) -> void:
	var clamped := clampi(value, 0, _last())
	if clamped == _offset() or not scroll_to.is_valid(): return
	scroll_to.call(clamped)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var grip := thumb_rect()
	if grip.size.y <= 0.0 or _last() == 0:
		if event is InputEventMouseButton: accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_set_offset(_offset() + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: _drag_from = -1.0
			elif grip.has_point(event.position):
				_drag_from = event.position.y
				_drag_offset = _offset()
			elif texture != null:
				var aim := _nearest(event.position.y - ELArtDropList.THUMB_SOURCE.size.y * 0.5)
				if event.position.y >= grip.end.y: _set_offset(mini(_offset() + ELArtDropList.PAGE, maxi(aim, _offset())))
				elif event.position.y < grip.position.y: _set_offset(maxi(_offset() - ELArtDropList.PAGE, mini(aim, _offset())))
			else:
				_set_offset(_offset() + (_page() if event.position.y > grip.end.y else -_page()))
		accept_event()
	elif event is InputEventMouseMotion and _drag_from >= 0.0:
		var free := size.y - grip.size.y - (0.0 if texture != null else 4.0)
		if free > 0.0: _set_offset(_drag_offset + roundi((event.position.y - _drag_from) / free * _last()))
		accept_event()

func _process(_delta: float) -> void:
	# Lists scrolled by their arrows, wheel or keys move the thumb too.
	var key := Vector2i(_offset(), _last())
	if key != _seen:
		_seen = key
		queue_redraw()

var _seen := Vector2i(-1, -1)

func _draw() -> void:
	var grip := thumb_rect()
	if grip.size.y <= 0.0: return
	if texture != null:
		draw_texture_rect_region(texture, grip, ELArtDropList.THUMB_SOURCE)
		return
	# The menu kit's scroll bar grip (ELMenuKit), lit under the pointer.
	draw_rect(grip, Color("66553c") if _hover or _drag_from >= 0.0 else Color("4b3f2e"))
	draw_rect(grip, Color("8a7350"), false, 1.0)
