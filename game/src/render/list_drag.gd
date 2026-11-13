class_name ELListDrag
## Dragging entries between plain item lists (a remake addition), as the
## spellbook lists do: a press on an entry and a move with the button held
## lift it with its icon under the pointer, and a drop on a list that takes
## it runs `dropped` there as a click or double-click would; a drop anywhere
## else does nothing. Touch drags arrive as the same mouse drag.

## Lets `list` lift its entries as `tag` and take drops of the tags in
## `accepts`: dropped(from_tag, from_index, to_index) runs on a drop, with
## to_index -1 away from the entries.
static func enable(list: ItemList, tag: String, accepts: Array, dropped: Callable) -> void:
	list.set_drag_forwarding(
		func(at: Vector2) -> Variant: return _lift(list, tag, at),
		func(_at: Vector2, data: Variant) -> bool: return data is Dictionary and accepts.has(data.get("list_drag", "")),
		func(at: Vector2, data: Variant) -> void: dropped.call(String(data.list_drag), int(data.index), list.get_item_at_position(at, true)))

static func _lift(list: ItemList, tag: String, at: Vector2) -> Variant:
	var index := list.get_item_at_position(at, true)
	if index < 0 or list.is_item_disabled(index): return null
	var size := Vector2(list.fixed_icon_size) if list.fixed_icon_size != Vector2i.ZERO else Vector2(36, 36)
	list.set_drag_preview(ELSpellbookView.drag_preview(list.get_item_icon(index), size))
	return {"list_drag": tag, "index": index}
