class_name ELBattleHistory
extends Control
## A remake addition (setting "battle_history", on by default): the plays of
## the whole battle as a column of small tiles at the left edge of the
## screen, the newest on top, as card games with a play history show them.
## It takes the place of the top-left icon list of the current turn's casts
## (ELCombatNotices.icons_hidden). The column stands alone, about two fifths
## of the screen tall, in the battle panel's phase caption frame (the 1024
## layout's caption oval) turned upright and drawn smaller, its straight
## middle stretched to the column's length; without that art, a plain dark
## column. The mouse wheel over it, or dragging it with a finger or the
## left button, scrolls back through older plays (a tile's height of drag
## per play); a tap opens a tile's card where there is no hover.
## Each tile is one play: a spell cast, a creature's or hero's ability, an
## artifact used, or one attack (the attacker's blow and the blow it takes
## back). Its rounded frame tells whose play it was: a pale blue to deep
## blue gradient for the viewer's, a red to dark maroon one for the
## opponent's, as card-game histories colour them; the picture inside has
## rounded corners too. An ability carries a star. An attack is a lower tile, a
## band across the middle of the attacker's picture, with the battle's own
## attack sign at its lower right: the sword of the game's attack cursor
## (the gauntlet's sword, cut out of the cursor's first frame), small and
## turned to point up and to the right, with a thin dark outline. Without
## the cursor, the CombatSymbols sheet's sword state icon stands in. The last tile that only partly fits is cut off at the
## frame's lower end and fades out there.
##
## Pointing at a tile opens its card to the right of the column, in the
## battle tooltips' own frame (Interface/black/ToolTip, as ELCombatTooltip
## draws it) and their bold italic face: the played card or the attacker
## large, its name and text, and after an arrow halfway between them (the
## bronze chevrons of Interface/black/tooltip1's round "next" button, cut
## off the button; a drawn arrow without that sheet) each
## character it touched with what happened to it (health lost or gained,
## killed, summoned, enchanted). Every picture there keeps its own shape
## (a hero's photo is wider than a spell icon) inside the same side-coloured
## gradient frame as the tiles; a tile shows the middle square of a wide
## picture. Nothing here takes a command.
##
## The view feeds it with `begin` (a play as it is shown), `touch` (an
## outcome of the latest play) and `close` (a phase change: later outcomes
## belong to no play). Coordinates are design pixels times `ui_scale`.

const TILE := 22.0
## An attack's tile height (its width is TILE's), and the gap between tiles.
const ATTACK_HEIGHT := 14.0
const GAP := 3.0
## The shortest part of a last tile still shown at the lower end.
const MIN_PART := 6.0
const MARGIN := 4.0
## The column's width, and the frame's ends that tiles keep clear of
## (design pixels).
const DEPTH := 32.0
const END_INSET := 12.0
const LOWER_INSET := 9.0
## The caption oval's straight middle (as ELHudFrame.CAPTION_MIDDLE and
## CAPTION_SLICE): it is stretched along the column.
const FRAME_MIDDLE := 120.0
const FRAME_SLICE := 8.0
## The column's share of the screen height, and the battle panel's height
## (with its gargoyles) it is centred above, in design pixels.
const HEIGHT_SHARE := 0.4
const BOTTOM := 190.0
const KEEP := 80
## The tile frames' gradients, top to bottom, and their dark outer line.
const OWN_FRAME := [Color("b9c8f2"), Color("6f86d6"), Color("34428f")]
const RIVAL_FRAME := [Color("d9614f"), Color("9e2a22"), Color("4d0f0c")]
const FRAME_LINE := Color(0.05, 0.03, 0.03)
## The frame's width and corner radius (design pixels).
const FRAME_WIDTH := 1.5
const CORNER := 4.0
const RIM := Color("6b5236")
const ACCENT := Color("e0af68")
const INK := Color("e5e3da")
const BACK := Color(0.07, 0.06, 0.05, 0.93)
const LOSS := Color("d23a2a")
const GAIN := Color("3fae4a")
const FADE_IN := 0.25
## Seconds a new play takes to open its place at the top, pushing the
## older ones down.
const PUSH_TIME := 0.32
## The open card: the played card's picture, its text width, a touched
## character's picture.
const CARD := 64.0
const TEXT_WIDTH := 160.0
const TARGET := 40.0
const MAX_TARGETS := 6
## Space between touched characters across and down, and between each
## picture and the arrow between them, and the arrow's width (design
## pixels).
const TARGET_GAP := 14.0
const TARGET_ROW_GAP := 22.0
const ARROW_GAP := 8.0
const ARROW_SIZE := 34.0
## The round "next" button in Interface/black/tooltip1 (both games): its
## three embossed chevrons inside the sheet's first 50-pixel cell. Their
## light strokes and dark shadows are kept, the button's grey face between
## them cleared (CHEVRON_LIGHT and CHEVRON_SHADOW, brightness 0 to 1).
const CHEVRONS := Rect2i(15, 21, 20, 13)
const CHEVRON_LIGHT := 0.27
const CHEVRON_SHADOW := 0.09
## The tiles' gradient for a character of neither side.
const NEUTRAL_FRAME := [Color("d8c08e"), Color("8f6f42"), Color("3e2c16")]
## The tooltip ink (ELCombatTooltip.INK).
const TIP_INK := Color("d6bb88")

## Plays, oldest first: {side, kind ("cast", "ability", "artifact",
## "attack"), source (character id or -1), icon, title, text, targets:
## [{id, icon, name, delta, died, summoned, enchanted}], age}.
var entries: Array = []
var viewer_side := 0:
	set(side):
		if viewer_side == side: return
		viewer_side = side
		queue_redraw()
var ui_scale := 1.0:
	set(value):
		if ui_scale == value: return
		ui_scale = value
		queue_redraw()
var _open := -1
var _current := -1
## Plays scrolled past at the top (the wheel), 0 shows the newest.
var _scroll := 0
## A drag along the column: where it started, the drag not yet turned into
## plays scrolled, and whether it moved far enough to be a drag (not a tap).
var _drag_from := Vector2.ZERO
var _drag_left := 0.0
var _dragging := false
var _pressed := false
## A press moves at least this far (design pixels) before it scrolls.
const DRAG_START := 4.0
## The battle panel's caption oval piece ({texture, source, destination}),
## or {}.
var _frame: Dictionary = {}
## Interface/CombatSymbols, for its sword.
var _symbols: Texture2D
## CombatSymbols cell 16: a single diagonal sword in its dark square; the
## sword itself lies in the square's inside (SWORD_INSIDE of the cell).
const SWORD_ICON := Rect2(0, 16, 16, 16)
const SWORD_INSIDE := Rect2i(2, 2, 12, 12)
## The sword alone (its pixels kept, the square's dark ground cleared).
var _sword: Texture2D
## The attack cursor's sword, upright as in the cursor; turned when drawn.
var _cursor_sword: Texture2D
## A pixel of the cursor's blade near its tip, where the cut starts.
const CURSOR_TIP := Vector2i(40, 4)
var _font: Font
var _bold: SystemFont
## The battle tooltips' frame texture and its pieces (as
## ELSecondMapTooltip.pieces), or null for a plain dark panel.
var _tip_frame: Texture2D
var _tip_pieces: Dictionary = {}
## Interface/black/tooltip1, for the arrow's button, or null.
var _arrow: Texture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ELCombatTooltip.face()
	_bold = SystemFont.new()
	_bold.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	_bold.font_weight = 700

## The battle panel's caption oval piece (one of ELHudFrame.pieces), or {}.
func set_frame(piece: Dictionary) -> void:
	_frame = piece
	queue_redraw()

## The battle tooltips' frame for the open card: its texture and pieces
## (corners, edges and fill, as ELSecondMapTooltip.pieces).
func set_tooltip_frame(texture: Texture2D, pieces: Dictionary) -> void:
	_tip_frame = texture
	_tip_pieces = pieces
	queue_redraw()

## Interface/black/tooltip1: its round "next" button is the card's arrow.
func set_arrow_sheet(sheet: Texture2D) -> void:
	_arrow = null
	var image := sheet.get_image() if sheet != null else null
	if image != null:
		if image.is_compressed(): image.decompress()
		var cut := image.get_region(CHEVRONS)
		cut.convert(Image.FORMAT_RGBA8)
		for y in cut.get_height():
			for x in cut.get_width():
				var pixel := cut.get_pixel(x, y)
				var light := (pixel.r + pixel.g + pixel.b) / 3.0
				# Strokes fade in above the face's grey, shadows below it.
				var alpha := 0.0
				if light >= CHEVRON_LIGHT: alpha = clampf((light - CHEVRON_LIGHT) / 0.06 + 0.4, 0.0, 1.0)
				elif light <= CHEVRON_SHADOW: alpha = clampf((CHEVRON_SHADOW - light) / 0.05 + 0.5, 0.0, 0.9)
				cut.set_pixel(x, y, Color(pixel, alpha))
		_arrow = ImageTexture.create_from_image(cut)
	queue_redraw()

## The arrow between the played card and what it touched, centred on
## `centre`: the button's chevrons, ARROW_SIZE wide, or a drawn arrow.
func _draw_arrow(centre: Vector2) -> void:
	var k := _k()
	var radius := ARROW_SIZE * 0.5 * k
	if _arrow != null:
		var picture := Vector2(_arrow.get_size())
		var drawn := Vector2(ARROW_SIZE, ARROW_SIZE * picture.y / picture.x) * k
		# Brightened a little: on the button the chevrons sat on a lighter face.
		draw_texture_rect(_arrow, Rect2(centre - drawn * 0.5, drawn), false, Color(1.3, 1.25, 1.15))
		return
	var tip := centre + Vector2(radius, 0)
	var tail := centre - Vector2(radius, 0)
	draw_line(tail, tip - Vector2(6.0 * k, 0), ACCENT, 5.0 * k)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-13.0, -11.0) * k, tip + Vector2(-13.0, 11.0) * k]), ACCENT)

## The attack cursor's first frame (ELCursors "attack"): its sword, the
## pixels joined to the blade's tip, becomes the attack sign.
func set_cursor(frame: Image) -> void:
	_cursor_sword = null
	if frame == null: return
	var image := frame.duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	var start := CURSOR_TIP
	# The tip pixel may sit a little off: take the nearest solid one in its row.
	for dx in range(-4, 5):
		var probe := CURSOR_TIP + Vector2i(dx, 0)
		if probe.x >= 0 and probe.x < image.get_width() and image.get_pixelv(probe).a > 0.5:
			start = probe
			break
	if image.get_pixelv(start).a <= 0.5: return
	var kept := {}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if kept.has(at) or at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height(): continue
		if image.get_pixelv(at).a <= 0.5: continue
		kept[at] = true
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]: queue.append(at + step)
	# Too large a piece means the blade touches the gauntlet: keep the icon.
	if kept.size() > 260 or kept.size() < 20: return
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for at: Vector2i in kept:
		low = Vector2i(mini(low.x, at.x), mini(low.y, at.y))
		high = Vector2i(maxi(high.x, at.x), maxi(high.y, at.y))
	var cut := Image.create(high.x - low.x + 1, high.y - low.y + 1, false, Image.FORMAT_RGBA8)
	for at: Vector2i in kept: cut.set_pixelv(at - low, image.get_pixelv(at))
	_cursor_sword = ImageTexture.create_from_image(cut)
	queue_redraw()

## The CombatSymbols sheet, for the attack sign.
func set_symbols(sheet: Texture2D) -> void:
	_symbols = sheet
	_sword = null
	if sheet != null:
		var image := sheet.get_image()
		if image != null:
			if image.is_compressed(): image.decompress()
			var at := Vector2i(SWORD_ICON.position) + SWORD_INSIDE.position
			var cut := image.get_region(Rect2i(at, SWORD_INSIDE.size))
			cut.convert(Image.FORMAT_RGBA8)
			# The sword is the reddish pixels; the ground is dark blue.
			for y in cut.get_height():
				for x in cut.get_width():
					var pixel := cut.get_pixel(x, y)
					if pixel.r <= pixel.b + 0.1: cut.set_pixel(x, y, Color(0, 0, 0, 0))
			_sword = ImageTexture.create_from_image(cut)
	queue_redraw()

func clear() -> void:
	entries.clear()
	_scroll = 0
	_open = -1
	_current = -1
	queue_redraw()

## A new play as it is shown. `source` is the character that played or
## attacked (-1 for none); the play's own result goes on it.
func begin(side: int, kind: String, source: int, icon: Texture2D, title: String, text: String) -> void:
	entries.append({"side": side, "kind": kind, "source": source, "icon": icon, "title": title, "text": text, "targets": [], "source_delta": 0, "source_died": false, "age": 0.0})
	while entries.size() > KEEP:
		entries.pop_front()
		if _open >= 0: _open -= 1
	_current = entries.size() - 1
	if _scroll > 0: _scroll += 1
	queue_redraw()

## The open play, for an attack's return blow: the index of the attack
## between `a` and `b` in either direction, or -1.
func current_attack(a: int, b: int) -> int:
	if _current < 0: return -1
	var entry: Dictionary = entries[_current]
	if entry.kind != "attack": return -1
	if entry.source == a and not entry.targets.is_empty() and entry.targets[0].id == b: return _current
	if entry.source == b and not entry.targets.is_empty() and entry.targets[0].id == a: return _current
	return -1

## The open play, or {}.
func current_entry() -> Dictionary:
	return entries[_current] if _current >= 0 and _current < entries.size() else {}

## Drops character `id` from the open play's list.
func forget_target(id: int) -> void:
	var entry := current_entry()
	if entry.is_empty(): return
	entry.targets = entry.targets.filter(func(target: Dictionary) -> bool: return int(target.id) != id)
	queue_redraw()

func has_current() -> bool:
	return _current >= 0

## Records what happened to character `id` (of `side`, -1 for neither)
## during the open play. `change` keys: "delta" (health), "died",
## "summoned", "enchanted".
func touch(id: int, icon: Texture2D, title: String, change: Dictionary, side := -1) -> void:
	if _current < 0 or _current >= entries.size(): return
	var entry: Dictionary = entries[_current]
	if id == int(entry.source) and id >= 0:
		entry.source_delta += int(change.get("delta", 0))
		if change.get("died", false): entry.source_died = true
		queue_redraw()
		return
	var found: Dictionary = {}
	for target: Dictionary in entry.targets:
		if int(target.id) == id: found = target
	if found.is_empty():
		if entry.targets.size() >= MAX_TARGETS * 4: return
		found = {"id": id, "side": side, "icon": icon, "name": title, "delta": 0, "died": false, "summoned": false, "enchanted": false}
		entry.targets.append(found)
	found.delta += int(change.get("delta", 0))
	for flag: String in ["died", "summoned", "enchanted"]:
		if change.get(flag, false): found[flag] = true
	queue_redraw()

## Later outcomes belong to no play.
func close() -> void:
	_current = -1

func _process(delta: float) -> void:
	var moving := false
	for entry: Dictionary in entries:
		if entry.age < maxf(FADE_IN, PUSH_TIME):
			entry.age += delta
			moving = true
	if moving: queue_redraw()

func _k() -> float:
	return maxf(ui_scale, 0.5)

## A play's tile height.
func _tile_height(entry: Dictionary) -> float:
	return ATTACK_HEIGHT if entry.kind == "attack" else TILE

## The column's rectangle, centred above the panel.
func _rail_rect() -> Rect2:
	var k := _k()
	var length := maxf(80.0, size.y / k * HEIGHT_SHARE)
	var middle := (size.y / k - BOTTOM) * 0.5 + 20.0
	var top := maxf(4.0, middle - length * 0.5)
	return Rect2(Vector2(MARGIN, top) * k, Vector2(DEPTH, length) * k)

## How far a play's place has opened, 0 to 1, easing out.
func _opened(entry: Dictionary) -> float:
	var t := clampf(entry.age / PUSH_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

## The shown tiles from the top, [entry index, shown rect, share of the
## tile's height down to the shown lower edge, share hidden above]: the
## newest (or the scrolled-to) play first, down to the frame's lower end,
## the last one cut off there. A new play's place opens from nothing,
## pushing the older tiles down, while the tile slides into it from above.
func _slots() -> Array:
	var k := _k()
	var rail := _rail_rect()
	var result: Array = []
	var y := END_INSET
	var room := rail.size.y / k - LOWER_INSET
	var index := entries.size() - 1 - _scroll
	while index >= 0 and room - y >= MIN_PART:
		var entry: Dictionary = entries[index]
		var height := _tile_height(entry)
		var place := height * _opened(entry)
		var hidden := height - place
		var shown := minf(place, room - y)
		if shown > 2.0:
			result.append([index, Rect2(rail.position + Vector2((DEPTH - TILE) * 0.5, y) * k, Vector2(TILE, shown) * k), (hidden + shown) / height, hidden / height])
		y += place + GAP * _opened(entry)
		index -= 1
	return result

func _slot_at(at: Vector2) -> int:
	for slot: Array in _slots():
		if (slot[1] as Rect2).grow(GAP * 0.5 * _k()).has_point(at): return int(slot[0])
	return -1

func _has_point(point: Vector2) -> bool:
	return visible and not entries.is_empty() and _rail_rect().has_point(point)

func _gui_input(event: InputEvent) -> void:
	var touch_as_mouse: bool = ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)
	if event is InputEventMouseMotion:
		if _pressed and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag(event.position)
			accept_event()
			return
		var index := _slot_at(event.position)
		if index != _open:
			_open = index
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_press(event.pressed, event.position)
		accept_event()
	elif event is InputEventScreenTouch and not touch_as_mouse:
		_press(event.pressed, event.position)
		accept_event()
	elif event is InputEventScreenDrag and not touch_as_mouse and _pressed:
		_drag(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept_event()
		_scroll_by(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)

func _press(down: bool, at: Vector2) -> void:
	if down:
		_pressed = true
		_dragging = false
		_drag_from = at
		_drag_left = 0.0
		return
	# A tap (no drag) opens the tile's card, or closes the one open.
	if _pressed and not _dragging:
		var index := _slot_at(at)
		_open = index if index != _open else -1
		queue_redraw()
	_pressed = false
	_dragging = false

## Dragging up shows older plays, down newer ones: one play per step of a
## tile's height.
func _drag(at: Vector2) -> void:
	var k := _k()
	var moved := at.y - _drag_from.y
	if not _dragging:
		if absf(moved) < DRAG_START * k: return
		_dragging = true
		_open = -1
	_drag_left += moved
	_drag_from = at
	var step := (TILE + GAP) * k
	while _drag_left <= -step:
		_drag_left += step
		_scroll_by(1)
	while _drag_left >= step:
		_drag_left -= step
		_scroll_by(-1)

## The furthest scroll: the oldest play at the column's lower end, never
## an empty column below it. The column then holds the oldest plays that
## fit whole.
func _max_scroll() -> int:
	var room := _rail_rect().size.y / _k() - LOWER_INSET - END_INSET
	var used := 0.0
	var fit := 0
	for index in entries.size():
		var height := _tile_height(entries[index])
		if used + height > room: break
		used += height + GAP
		fit += 1
	return maxi(0, entries.size() - maxi(fit, 1))

func _scroll_by(plays: int) -> void:
	var next := clampi(_scroll + plays, 0, _max_scroll())
	if next == _scroll: return
	_scroll = next
	_open = -1
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _open >= 0:
		_open = -1
		queue_redraw()

func _draw() -> void:
	if entries.is_empty(): return
	var k := _k()
	var slots := _slots()
	_draw_rail(slots)
	for slot: Array in slots:
		var index := int(slot[0])
		var entry: Dictionary = entries[index]
		var rect: Rect2 = slot[1]
		var part := float(slot[2])
		var above := float(slot[3])
		# A new tile fades in as it slides into place.
		var alpha := clampf(entry.age / FADE_IN, 0.0, 1.0)
		# A tile cut off at the lower end fades into the frame.
		if part < 1.0: alpha *= 0.35 + 0.4 * part
		var attack: bool = entry.kind == "attack"
		var frame_colours: Array = OWN_FRAME if int(entry.side) == viewer_side else RIVAL_FRAME
		var radius := minf(CORNER, rect.size.y / (2.0 * k)) * k
		# The dark line around the frame, the frame's gradient, then the picture.
		_draw_round(rect.grow(0.6 * k), radius + 0.6 * k, [FRAME_LINE, FRAME_LINE], alpha * 0.85)
		_draw_round(rect, radius, frame_colours, alpha)
		var inside := rect.grow(-FRAME_WIDTH * k)
		var inner_radius := maxf(1.0, radius - FRAME_WIDTH * k * 0.6)
		if entry.icon is Texture2D and inside.size.y > 1.0:
			# An attack shows a band across the picture's middle; a cut-off tile
			# its upper part.
			var square := _square(entry.icon)
			var band := square.size.y * (ATTACK_HEIGHT / TILE if attack else 1.0)
			var source := Rect2(square.position + Vector2(0, (square.size.y - band) * 0.5 + band * above), Vector2(square.size.x, band * (part - above)))
			_draw_round(inside, inner_radius, [Color.WHITE, Color.WHITE], alpha, entry.icon, source)
		elif inside.size.y > 1.0: _draw_round(inside, inner_radius, [Color(0.2, 0.17, 0.13), Color(0.12, 0.1, 0.08)], alpha)
		# A thin shadow inside the frame, as an inset picture has.
		_outline_round(inside, inner_radius, Color(0, 0, 0, 0.45 * alpha), 0.6 * k)
		if index == _open: _outline_round(rect.grow(1.5 * k), radius + 1.5 * k, Color(ACCENT, alpha), 1.5 * k)
		if part < 1.0: continue
		if attack: _draw_sword(Vector2(rect.end.x - 1.0 * k, rect.end.y + 1.0 * k), 11.0 * k, alpha)
		elif entry.kind in ["ability", "artifact"]: _draw_star(rect.end - Vector2(4.0, 4.0) * k, 3.5 * k, alpha)
	for slot: Array in slots:
		if int(slot[0]) == _open: _draw_card(entries[_open], slot[1])

## The middle square of a picture (a hero's photo is wider than tall).
func _square(texture: Texture2D) -> Rect2:
	var picture := Vector2(texture.get_size())
	var side := minf(picture.x, picture.y)
	return Rect2((picture - Vector2(side, side)) * 0.5, Vector2(side, side))

## A picture's size at `height`, in its own proportions.
func _shaped(texture: Variant, height: float) -> Vector2:
	if not texture is Texture2D: return Vector2(height, height)
	var picture := Vector2((texture as Texture2D).get_size())
	return Vector2(height * picture.x / maxf(picture.y, 1.0), height)

## The gradient of a side's frames.
func _side_frame(side: int) -> Array:
	if side < 0: return NEUTRAL_FRAME
	return OWN_FRAME if side == viewer_side else RIVAL_FRAME

## A picture in a tile's frame: the dark line, the side's gradient, the
## picture with rounded corners inside it and its thin inner shadow.
func _framed_picture(rect: Rect2, texture: Variant, colours: Array) -> void:
	var k := _k()
	var border := 2.5 * k
	var outer := rect.grow(border)
	var radius := CORNER * 1.25 * k
	_draw_round(outer.grow(0.8 * k), radius + 0.8 * k, [FRAME_LINE, FRAME_LINE], 0.9)
	_draw_round(outer, radius, colours, 1.0)
	var inner_radius := maxf(1.0, radius - border * 0.6)
	if texture is Texture2D: _draw_round(rect, inner_radius, [Color.WHITE, Color.WHITE], 1.0, texture, Rect2(Vector2.ZERO, (texture as Texture2D).get_size()))
	else: _draw_round(rect, inner_radius, [Color(0.2, 0.17, 0.13), Color(0.12, 0.1, 0.08)], 1.0)
	_outline_round(rect, inner_radius, Color(0, 0, 0, 0.45), 0.8 * k)

## The battle tooltips' frame around `rect`: corners, edges tiled along
## their length and the fill tiled, in design pixels scaled to the screen.
func _draw_tip_frame(rect: Rect2) -> void:
	if _tip_frame == null or _tip_pieces.is_empty():
		draw_rect(rect, BACK)
		draw_rect(rect, RIM, false, 2.0 * _k())
		return
	var k := _k()
	var border: float = _tip_pieces.border
	var inner := Rect2(Vector2(border, border), rect.size / k - Vector2(border, border) * 2.0)
	if inner.size.x <= 0 or inner.size.y <= 0: return
	draw_set_transform(rect.position, 0.0, Vector2(k, k))
	_tile(inner, _tip_pieces.fill)
	_tile(Rect2(inner.position.x, 0, inner.size.x, border), _tip_pieces.top)
	_tile(Rect2(inner.position.x, inner.end.y, inner.size.x, border), _tip_pieces.bottom)
	_tile(Rect2(0, inner.position.y, border, inner.size.y), _tip_pieces.left)
	_tile(Rect2(inner.end.x, inner.position.y, border, inner.size.y), _tip_pieces.right)
	var corner := Vector2(border, border)
	draw_texture_rect_region(_tip_frame, Rect2(Vector2.ZERO, corner), _tip_pieces.top_left)
	draw_texture_rect_region(_tip_frame, Rect2(Vector2(inner.end.x, 0), corner), _tip_pieces.top_right)
	draw_texture_rect_region(_tip_frame, Rect2(Vector2(0, inner.end.y), corner), _tip_pieces.bottom_left)
	draw_texture_rect_region(_tip_frame, Rect2(inner.end, corner), _tip_pieces.bottom_right)
	draw_set_transform(Vector2.ZERO)

## Repeats a piece of the tooltip texture over `target` from its top left.
func _tile(target: Rect2, piece: Rect2) -> void:
	var y := target.position.y
	while y < target.end.y:
		var h := minf(piece.size.y, target.end.y - y)
		var x := target.position.x
		while x < target.end.x:
			var w := minf(piece.size.x, target.end.x - x)
			draw_texture_rect_region(_tip_frame, Rect2(x, y, w, h), Rect2(piece.position, Vector2(w, h)))
			x += w
		y += h

## `text` shortened with an ellipsis to fit `width` at `font_size`.
func _fitted(font: Font, text: String, width: float, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width: return text
	var shown := text
	while shown.length() > 1 and font.get_string_size(shown + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		shown = shown.left(shown.length() - 1)
	return shown.strip_edges() + "…"

## A rounded rectangle's outline points, clockwise from the top left.
func _round_points(rect: Rect2, radius: float) -> PackedVector2Array:
	# Just under half the short side, so opposite corners never share points.
	var r := maxf(0.0, minf(radius, minf(rect.size.x, rect.size.y) * 0.45))
	var points := PackedVector2Array()
	var corners := [[rect.position + Vector2(r, r), PI], [Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5],
		[rect.end - Vector2(r, r), 0.0], [Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5]]
	for corner: Array in corners:
		for step in 5:
			var angle: float = corner[1] + step * (PI * 0.5) / 4.0
			points.append(corner[0] + Vector2(cos(angle), sin(angle)) * r)
	return points

## A rounded rectangle filled with a top-to-bottom gradient through
## `colours` (two or three), or with `texture`'s `source` region.
func _draw_round(rect: Rect2, radius: float, colours: Array, alpha: float, texture: Texture2D = null, source := Rect2()) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0: return
	var points := _round_points(rect, radius)
	var tints := PackedColorArray()
	var uvs := PackedVector2Array()
	var picture := Vector2(texture.get_size()) if texture != null else Vector2.ONE
	for point: Vector2 in points:
		var t := clampf((point.y - rect.position.y) / maxf(rect.size.y, 0.001), 0.0, 1.0)
		var colour: Color
		if colours.size() >= 3: colour = (colours[0] as Color).lerp(colours[1], t * 2.0) if t < 0.5 else (colours[1] as Color).lerp(colours[2], t * 2.0 - 1.0)
		else: colour = (colours[0] as Color).lerp(colours[1], t)
		colour.a *= alpha
		tints.append(colour)
		if texture != null:
			var along := (point - rect.position) / rect.size
			uvs.append((source.position + along * source.size) / picture)
	if texture != null: draw_polygon(points, tints, uvs, texture)
	else: draw_polygon(points, tints)

func _outline_round(rect: Rect2, radius: float, colour: Color, width: float) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0: return
	var points := _round_points(rect, radius)
	points.append(points[0])
	draw_polyline(points, colour, width, true)

## The upright frame: the caption oval turned a quarter, drawn DEPTH wide,
## its straight middle stretched along the column; and marks for plays
## above or below the shown ones.
func _draw_rail(slots: Array) -> void:
	var k := _k()
	var rail := _rail_rect()
	var texture: Texture2D = _frame.get("texture")
	if texture != null:
		var source: Rect2 = _frame.source
		var destination: Rect2 = _frame.destination
		var scale_x := source.size.x / destination.size.x
		var shrink := DEPTH / destination.size.y
		var length := rail.size.y / k
		var left := FRAME_MIDDLE * shrink
		var right := (destination.size.x - FRAME_MIDDLE) * shrink
		var stretch := maxf(0.0, length - left - right)
		# Turned a quarter clockwise: the oval's length runs down the screen.
		draw_set_transform(Vector2(rail.end.x, rail.position.y), PI / 2, Vector2(k, k))
		draw_texture_rect_region(texture, Rect2(Vector2.ZERO, Vector2(left, DEPTH)), Rect2(source.position, Vector2(FRAME_MIDDLE * scale_x, source.size.y)))
		var slice := Rect2(source.position + Vector2((FRAME_MIDDLE - FRAME_SLICE * 0.5) * scale_x, 0), Vector2(FRAME_SLICE * scale_x, source.size.y))
		draw_texture_rect_region(texture, Rect2(Vector2(left, 0), Vector2(stretch, DEPTH)), slice)
		draw_texture_rect_region(texture, Rect2(Vector2(left + stretch, 0), Vector2(right, DEPTH)), Rect2(source.position + Vector2(FRAME_MIDDLE * scale_x, 0), Vector2(source.size.x - FRAME_MIDDLE * scale_x, source.size.y)))
		draw_set_transform(Vector2.ZERO)
	else:
		draw_rect(rail, Color(0.06, 0.05, 0.04, 0.9))
		draw_rect(rail.grow(1.0 * k), RIM, false, 2.0 * k)
	# More plays past either end of the column.
	var centre := rail.position.x + rail.size.x * 0.5
	if _scroll > 0: _draw_chevron(Vector2(centre, rail.position.y + 6.0 * k), -1)
	if not slots.is_empty() and int(slots[-1][0]) > 0: _draw_chevron(Vector2(centre, rail.end.y - 6.0 * k), 1)

func _draw_chevron(at: Vector2, direction: int) -> void:
	var k := _k()
	var points := PackedVector2Array([at + Vector2(-4, 0) * k, at + Vector2(4, 0) * k, at + Vector2(0, 4 * direction) * k])
	draw_colored_polygon(points, ACCENT)

## The attack sign, `extent` square, its lower right corner at `corner`:
## the CombatSymbols sword with a thin dark outline (or a plain blade).
func _draw_sword(corner: Vector2, extent: float, alpha: float) -> void:
	var k := _k()
	var rect := Rect2(corner - Vector2(extent, extent), Vector2(extent, extent))
	if _cursor_sword != null:
		# The upright sword turned a quarter of a half-turn: point up and right,
		# its length the square's diagonal.
		var picture := Vector2(_cursor_sword.get_size())
		var length := extent * 1.41
		var drawn := Vector2(picture.x * length / picture.y, length)
		var outline := maxf(1.0, 0.7 * k)
		draw_set_transform(rect.get_center(), PI / 4, Vector2.ONE)
		var placed := Rect2(-drawn * 0.5, drawn)
		for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_texture_rect(_cursor_sword, Rect2(placed.position + offset * outline, placed.size), false, Color(0, 0, 0, 0.9 * alpha))
		draw_texture_rect(_cursor_sword, placed, false, Color(1.15, 1.15, 1.15, alpha))
		draw_set_transform(Vector2.ZERO)
		return
	if _sword != null:
		var step := maxf(1.0, 0.75 * k)
		for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1)]:
			draw_texture_rect(_sword, Rect2(rect.position + offset * step, rect.size), false, Color(0, 0, 0, 0.9 * alpha))
		draw_texture_rect(_sword, rect, false, Color(1.35, 1.3, 1.25, alpha))
		return
	draw_line(rect.position + Vector2(extent * 0.85, extent * 0.15), rect.position + Vector2(extent * 0.2, extent * 0.8), Color(0, 0, 0, alpha), 3.0 * k)
	draw_line(rect.position + Vector2(extent * 0.85, extent * 0.15), rect.position + Vector2(extent * 0.2, extent * 0.8), Color("d9744a") * Color(1, 1, 1, alpha), 1.4 * k)

func _draw_star(centre: Vector2, radius: float, alpha: float) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI / 2 + i * PI / 5
		points.append(centre + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, Color(ACCENT, alpha))
	points.append(points[0])
	draw_polyline(points, Color(0, 0, 0, alpha), 1.0)

## A health change or a death on a picture's lower right corner.
func _draw_result(rect: Rect2, delta: int, died: bool) -> void:
	var k := _k()
	if died:
		draw_rect(rect, Color(0.25, 0.0, 0.0, 0.45))
		draw_line(rect.position + rect.size * 0.2, rect.end - rect.size * 0.2, LOSS, 3.0 * k)
		draw_line(Vector2(rect.end.x, rect.position.y) + Vector2(-rect.size.x, rect.size.y) * 0.2, Vector2(rect.position.x, rect.end.y) + Vector2(rect.size.x, -rect.size.y) * 0.2, LOSS, 3.0 * k)
	if delta == 0: return
	var text := ("+%d" if delta > 0 else "%d") % delta
	var font_size := int(round(13.0 * k))
	var centre := rect.end - Vector2(9.0, 9.0) * k
	draw_circle(centre, 9.5 * k, Color(0, 0, 0, 0.85))
	draw_circle(centre, 8.0 * k, GAIN if delta > 0 else LOSS)
	var width := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := centre + Vector2(-width * 0.5, font_size * 0.36)
	draw_string_outline(_bold, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color.BLACK)
	draw_string(_bold, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

## The open card beside `tile`.
func _draw_card(entry: Dictionary, tile: Rect2) -> void:
	var k := _k()
	var pad := 12.0 * k
	var title_size := int(round(13.0 * k))
	var text_size := int(round(11.0 * k))
	var name_size := int(round(10.0 * k))
	var title := String(entry.title)
	var text := String(entry.text)
	var picture_size := _shaped(entry.icon, CARD) * k
	# The text column is as wide as its widest line, up to TEXT_WIDTH.
	var widest := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	for line in text.split("\n"): widest = maxf(widest, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x)
	var card_width := maxf(picture_size.x, minf(TEXT_WIDTH * k, widest + 2.0 * k))
	var text_height := 0.0
	if not text.is_empty(): text_height = _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, card_width, text_size, 9).y
	var targets: Array = entry.targets.slice(0, MAX_TARGETS)
	var columns := mini(targets.size(), 3)
	var rows := ceili(targets.size() / 3.0)
	# Every touched character's cell is as wide as the widest picture.
	var cell_width := TARGET * k
	for target: Dictionary in targets: cell_width = maxf(cell_width, _shaped(target.icon, TARGET).x * k)
	var row_height := TARGET * k + name_size * 1.9
	var target_block := Vector2.ZERO
	if not targets.is_empty():
		target_block = Vector2(columns * cell_width + (columns - 1) * TARGET_GAP * k, rows * row_height + (rows - 1) * (TARGET_ROW_GAP * k - name_size * 1.9))
	var arrow := (ARROW_GAP * 2.0 + ARROW_SIZE) * k if not targets.is_empty() else 0.0
	var card_height := picture_size.y + title_size * 1.6 + text_height + 4.0 * k
	var inner := Vector2(card_width + arrow + target_block.x, maxf(card_height, target_block.y))
	var panel_size := inner + Vector2(pad, pad) * 2.0
	var at := Vector2(_rail_rect().end.x + 8.0 * k, tile.position.y + tile.size.y * 0.5 - panel_size.y * 0.5)
	at.y = clampf(at.y, 4.0 * k, maxf(4.0 * k, size.y - BOTTOM * k * 0.5 - panel_size.y))
	var panel := Rect2(at, panel_size)
	_draw_tip_frame(panel)
	# The played card or the attacker, its name and text.
	var origin := panel.position + Vector2(pad, pad)
	var picture := Rect2(origin + Vector2((card_width - picture_size.x) * 0.5, 0), picture_size)
	_framed_picture(picture, entry.icon, _side_frame(int(entry.side)))
	if entry.kind == "attack": _draw_sword(picture.end + Vector2(3.0, 3.0) * k, 22.0 * k, 1.0)
	_draw_result(picture, int(entry.source_delta), bool(entry.source_died))
	var title_at := Vector2(origin.x, picture.end.y + title_size * 1.4)
	draw_string_outline(_font, title_at, title, HORIZONTAL_ALIGNMENT_CENTER, card_width, title_size, maxi(1, int(round(2.0 * k))), Color(0, 0, 0, 0.7))
	draw_string(_font, title_at, title, HORIZONTAL_ALIGNMENT_CENTER, card_width, title_size, ACCENT)
	if not text.is_empty():
		draw_multiline_string(_font, title_at + Vector2(0, text_size * 1.35), text, HORIZONTAL_ALIGNMENT_LEFT, card_width, text_size, 9, TIP_INK)
	if targets.is_empty(): return
	# One row of touched characters lines up with the played card's picture
	# where the panel allows; more rows are centred in the panel. The arrow
	# runs halfway between the picture and them, and halfway in height.
	var block_y := origin.y + (inner.y - target_block.y) * 0.5
	if rows == 1: block_y = clampf(picture.get_center().y - TARGET * k * 0.5, origin.y, origin.y + inner.y - target_block.y)
	var block_at := Vector2(origin.x + card_width + arrow, block_y)
	var arrow_y := (picture.get_center().y + block_y + TARGET * k * 0.5) * 0.5 if rows == 1 else origin.y + inner.y * 0.5
	_draw_arrow(Vector2((picture.end.x + block_at.x) * 0.5, arrow_y))
	for i in targets.size():
		var target: Dictionary = targets[i]
		var cell := block_at + Vector2((i % 3) * (cell_width + TARGET_GAP * k), (i / 3) * (TARGET + TARGET_ROW_GAP) * k)
		var face_size := _shaped(target.icon, TARGET) * k
		var face := Rect2(cell + Vector2((cell_width - face_size.x) * 0.5, 0), face_size)
		_framed_picture(face, target.icon, _side_frame(int(target.get("side", -1))))
		if target.summoned: _draw_star(face.position + Vector2(7, 7) * k, 6.0 * k, 1.0)
		elif target.enchanted: draw_circle(face.position + Vector2(7, 7) * k, 5.0 * k, Color("8c6cd9"))
		_draw_result(face, int(target.delta), bool(target.died))
		# A name keeps to its cell and a little of the gap on each side.
		var name_width := cell_width + TARGET_GAP * k * 0.7
		var name := _fitted(_font, String(target.name), name_width, name_size)
		draw_string(_font, Vector2(cell.x - TARGET_GAP * k * 0.35, face.end.y + name_size * 1.8), name, HORIZONTAL_ALIGNMENT_CENTER, name_width, name_size, TIP_INK)
	if entry.targets.size() > MAX_TARGETS:
		var more := "+%d" % (entry.targets.size() - MAX_TARGETS)
		draw_string(_bold, panel.end - Vector2(pad + 30.0 * k, pad * 0.5), more, HORIZONTAL_ALIGNMENT_RIGHT, 30.0 * k, title_size, TIP_INK)
