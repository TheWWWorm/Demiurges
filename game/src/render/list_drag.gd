class_name ELListDrag
extends Node
## Dragging entries between plain item lists (a remake addition), as the
## spellbook lists do: a press on an entry and a move with the button held
## lift it with its icon under the pointer, and a drop on a list that takes
## it runs `dropped` there as a click or double-click would; a drop anywhere
## else does nothing. Touch drags arrive as the same mouse drag.

var _list: ItemList
var _release := Vector2.INF

static func track_release(list: ItemList) -> ELListDrag:
	var tracker := ELListDrag.new()
	tracker._list = list
	list.add_child(tracker)
	return tracker

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_release = Vector2.INF if event.pressed else _list.get_global_transform_with_canvas().affine_inverse() * event.position

## Godot forwards the hardware cursor position to drop callbacks. The release
## event also covers touch-generated and other viewport-injected drags.
func release_position(cursor: Vector2) -> Vector2:
	return _release if _release != Vector2.INF else cursor

## Lets `list` lift its entries as `tag` and take drops of the tags in
## `accepts`: dropped(from_tag, from_index, to_index) runs on a drop, with
## to_index -1 away from the entries.
static func enable(list: ItemList, tag: String, accepts: Array, dropped: Callable) -> void:
	var tracker := track_release(list)
	list.set_drag_forwarding(
		func(at: Vector2) -> Variant: return _lift(list, tag, at),
		func(_at: Vector2, data: Variant) -> bool: return data is Dictionary and accepts.has(data.get("list_drag", "")),
		func(at: Vector2, data: Variant) -> void:
			dropped.call(String(data.list_drag), int(data.index), list.get_item_at_position(tracker.release_position(at), true)))

static func _lift(list: ItemList, tag: String, at: Vector2) -> Variant:
	var index := list.get_item_at_position(at, true)
	if index < 0 or list.is_item_disabled(index): return null
	var size := Vector2(list.fixed_icon_size) if list.fixed_icon_size != Vector2i.ZERO else Vector2(36, 36)
	list.set_drag_preview(drag_preview(list.get_item_icon(index), size))
	return {"list_drag": tag, "index": index}

## An icon centred under the pointer while it is dragged.
static func drag_preview(icon: Texture2D, size: Vector2) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture := TextureRect.new()
	picture.texture = icon
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size = size
	picture.position = -size * 0.5
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	return holder
