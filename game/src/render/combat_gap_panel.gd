class_name ELCombatGapPanel
extends Control
## A remake addition: on a wide screen the battle panel's extra width (what
## the original layout leaves between the card rail and the phase caption,
## see ELHudFrame.rail_trim) holds one of several readouts, switched with the
## arrows at its ends. The choice is the "battle_gap" setting and is kept
## between battles. Nothing here takes a command: every item only explains
## itself in a tooltip.
##
## It is drawn as a second rail, from the card rail's own art
## (COMBAT_PANEL_1): the left arrow housing with the knot before it, the
## rail's dark strip with its top line and lower band (a bay's inside, so
## without the bay dividers) and the right arrow housing, which meets the
## caption's knot as the card rail's does in the original. The arrows are the
## rail's SpellScrollLeft/Right buttons with their hover and pressed art and
## sound. Items follow the combat lists' look (ELListLook): the hover border,
## the red veil on an item that is spent, the rail's digit glyphs for counts.
## A width too narrow for the arrows and a readout (under MIN_WIDTH) shows
## the plain strip.
##
## Slides (SLIDES):
## - "book": the shown hero's spellbook, one icon per book slot with the
##   charges still to be drawn from it; a slot with none is veiled.
## - "advice": the battle adviser (ELCombatAdvisor): both heroes' portraits
##   with the position estimate for each (out of 100, to the nearest
##   ESTIMATE_STEP: an uncalibrated reading, not a measured chance to win)
##   and a gauge between them, and
##   (it flashes green when the chance rises and red when it falls, whoever
##   moved, see FLASH_TIME); under them, in a caption box, the verdict on the player's last move
##   with the points of the estimate it gave away ("Your move: mistake, −14
##   of the estimate").
## - "graves" and "auras": both heroes side by side in two rows, each led by
##   its hero's portrait, showing their graveyards or the enchantments on
##   them, the newest first. The two are one stop of the arrows: which list
##   is shown is chosen with the original's Graveyard / Enchantments radio
##   pair, drawn at the left from the rail's own pressed art (the unchosen
##   one darkened), and the arrows come back to the list last shown.
## - "watch": the battle camera (ELCombatWatch), a live picture of one
##   figure after another filling the readout, with nothing written on it
##   and no tooltip.
## The view supplies each slide's contents with `set_content`.
##
## Coordinates are original pixels, like the rest of the panel; the view
## places the control over ELHudFrame.gap_rect.
signal slide_changed(index: int)

const SLIDES := ["book", "advice", "graves", "auras", "watch"]
## The adviser's estimate is shown rounded to this many points.
const ESTIMATE_STEP := 5
const TITLES := ["Spellbook", "Battle adviser", "Graveyards", "Hero enchantments", "Battle camera"]
const MIN_WIDTH := 150.0
const INK := ELCombatRail.COUNT_COLOR
const DIM := Color(0.84, 0.73, 0.53, 0.6)
## COMBAT_PANEL_1: the knot and the left arrow housing up to the first bay's
## line, a bay's inside, and the last bay's line with the right arrow housing.
const LEFT_END := Rect2(0, 0, 33, 61)
const STRIP := Rect2(36, 0, 44, 61)
const RIGHT_END := Rect2(92, 61, 22, 61)
## A bay's dividing line, and the strip's inside between its top line and
## its lower band (panel coordinates).
const DIVIDER := Rect2(83, 0, 3, 61)
const BAY := Rect2(0, 2, 0, 51)
## The panel's bronze, for thin rims.
const RIM := Color("6b5236")
## The arrow buttons' original rectangles and their places in the end pieces.
const LEFT_ARROW := Rect2(131, 542, 17, 48)
const RIGHT_ARROW := Rect2(469, 542, 17, 48)
const LEFT_ARROW_AT := Vector2(13, 3)
const RIGHT_ARROW_AT := Vector2(3, 3)
## The contents' top and height: a rail item's, as the hand's cards stand.
const TOP := 3.0
const HEIGHT := float(ELListLook.ITEM_SIZE)
const MARGIN := 2.0
## The right end piece opens with the last bay's line and a dark edge of its own.
const MARGIN_RIGHT := 0.0
## Small icons: two rows of them fill the contents' height.
const SMALL := 24.0
const GAP := 2.0
## A hero portrait at a small icon's height, in the portrait's own shape.
const FACE := Vector2(34, 24)
## The adviser's gauge shows a change of the chance as a hit: the part won
## lights up green, the part lost stays behind in red, the whole gauge
## glowing in that colour, and both fade over this long. A change under
## FLASH_LEAST of the whole gauge passes unmarked.
const FLASH_TIME := 1.1
const FLASH_LEAST := 0.01
const GAIN := Color("63b33c")
const HARM := Color("d0362a")
## The verdict as the caption says it (GRADE_NAMES name it in the tooltip).
const VERDICTS := ["Your move: best", "Your move: excellent", "Your move: good", "Your move: inaccuracy", "Your move: mistake", "Your move: blunder"]
const GRADE_NAMES := ["Best move", "Excellent move", "Good move", "Inaccuracy", "Mistake", "Blunder"]
## Verdicts in the panel's own colours: the counts' gold, brighter for the
## best move and paler for a slip, and the lists' red for a mistake.
const GRADE_COLOURS := [Color("f3deaa"), Color("d6bb88"), Color("d6bb88"), Color("b89a68"), Color("d0653c"), Color("c8362a")]

var slide := 0
var profile: ELProfile
var content := {}
var look: ELListLook
var _art: Texture2D
## The rail's pressed Graveyard and Enchantments radio art, by slide name:
## {"texture", "source"}.
var _emblems := {}
var _font: SystemFont
var _left: ELCutPartButton
var _right: ELCutPartButton
## The chance the gauge showed before its last change, and that change's age.
var _flash_from := 0.5
var _flash_age := FLASH_TIME
## Items of the slide as last drawn: [{rect, tooltip}], and the one under the
## pointer (-1 for none).
var _spots: Array = []
var _hovered := -1
## The heroes' list last shown: the slide the arrows stop at for the pair.
var _heroes := 2
## The readout is drawn on two layers over the panel art: icons, which are
## shown smaller than they are and so smoothed, and everything else in the
## panel's own sharp filter. The slide is laid out once for each (`_pass` 0
## draws the icons on `_canvas`, 1 the rest).
var _icons: Control
var _marks: Control
var _canvas: Control
var _pass := 0

func build(data: ELProfile) -> void:
	profile = data
	content.clear()
	_flash_age = FLASH_TIME
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
		_font.font_weight = 700
		mouse_filter = Control.MOUSE_FILTER_STOP
		_icons = _layer(0)
		_icons.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_marks = _layer(1)
		_left = _arrow(-1)
		_right = _arrow(1)
		mouse_exited.connect(func():
			_hovered = -1
			queue_redraw())
	look = ELListLook.load(profile)
	_art = profile.texture("Interface/black/combat_panel_1")
	_emblems.clear()
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("CutParts").values():
		var key: String = {"Graveyard": "graves", "Enchantments": "auras"}.get(str(row.get("Ctrl", "")), "")
		var masks: Variant = row.get("Msk", [])
		if key.is_empty() or (masks if masks is Array else [masks]) != ["Push"]: continue
		var texture := profile.texture(paths.get(row.get("Txt", ""), ""))
		if texture != null: _emblems[key] = {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH)}
	_left.build(profile, "SpellScrollLeft", LEFT_ARROW)
	_right.build(profile, "SpellScrollRight", RIGHT_ARROW)
	_name_arrows()
	layout()

func _layer(pass_index: int) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(_draw_slide.bind(layer, pass_index))
	add_child(layer)
	return layer

func _arrow(direction: int) -> ELCutPartButton:
	var arrow := ELCutPartButton.new()
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.dim_disabled = false
	arrow.set_meta("gap_arrow", direction)
	arrow.pressed.connect(step.bind(direction))
	arrow.mouse_entered.connect(arrow.queue_redraw)
	arrow.mouse_exited.connect(arrow.queue_redraw)
	add_child(arrow)
	return arrow

## Off (setting "battle_readouts") the panel is only the plain strip.
var readouts := true

## Whether the readouts are on and the width holds the arrows and a readout
## between them.
func roomy() -> bool:
	return readouts and size.x >= MIN_WIDTH

func layout() -> void:
	if _left == null: return
	_left.visible = roomy()
	_right.visible = roomy()
	_left.position = LEFT_ARROW_AT
	_right.position = Vector2(size.x - RIGHT_END.size.x, 0) + RIGHT_ARROW_AT
	queue_redraw()

## The arrows' stops: the spellbook, the adviser, the heroes' lists (one
## stop for the pair) and the battle camera.
func _stops() -> Array[int]:
	return [0, 1, _heroes, 4]

## Shows the next stop (`direction` 1) or the one before, round and round.
func step(direction: int) -> void:
	var stops := _stops()
	choose(stops[posmod(stops.find(slide) + direction, stops.size())])

## Shows a slide as the player's choice (it is remembered).
func choose(index: int) -> void:
	show_slide(index)
	slide_changed.emit(slide)

func show_slide(index: int) -> void:
	slide = clampi(index, 0, SLIDES.size() - 1)
	if slide in [2, 3]: _heroes = slide
	_hovered = -1
	_name_arrows()
	queue_redraw()

func _name_arrows() -> void:
	if _left == null: return
	var stops := _stops()
	var at := stops.find(slide)
	_left.tooltip_text = _t(TITLES[stops[posmod(at - 1, stops.size())]])
	_right.tooltip_text = _t(TITLES[stops[posmod(at + 1, stops.size())]])

## A slide's contents, by its name in SLIDES:
## "book": [cell]; "graves", "auras": one {"face": Texture2D, "name", "cells":
## [cell]} per hero, the local side first; "advice": {"available", "reason",
## "chance" (0..1), "faces" and "names" (the local side first), "grade" (-1
## none), "loss", "pending", "tooltip"}; "watch": {"texture"}.
## A cell is {"icon": Texture2D, "tooltip", "count" (-1 for none), "dim"}.
func set_content(key: String, value: Variant) -> void:
	if content.has(key) and content[key] == value: return
	if key == "advice" and content.has(key) and content[key].get("available", false) and value.get("available", false):
		var before := float(content[key].get("chance", 0.5))
		if absf(float(value.get("chance", 0.5)) - before) >= FLASH_LEAST:
			# A change during a flash starts from what the gauge showed first.
			if _flash_age >= FLASH_TIME: _flash_from = before
			_flash_age = 0.0
			set_process(true)
	content[key] = value
	if key == SLIDES[slide]: queue_redraw()

func _process(delta: float) -> void:
	_flash_age += delta
	queue_redraw()
	if _flash_age >= FLASH_TIME: set_process(false)

func _t(text: String) -> String:
	return ELRemakeText.t(text, profile)

func _spot_at(at: Vector2) -> int:
	for i in _spots.size():
		if _spots[i].rect.has_point(at): return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var spot := _spot_at(event.position)
		if spot >= 0 and _spots[spot].has("slide") and int(_spots[spot].slide) != slide:
			ELUiSounds.play(profile, ELUiSounds.sound_of(profile, String(_spots[spot].sound)))
			choose(int(_spots[spot].slide))
		return
	if event is not InputEventMouseMotion: return
	var now := _spot_at(event.position)
	if now == _hovered: return
	_hovered = now
	queue_redraw()

func _get_tooltip(at: Vector2) -> String:
	if not roomy(): return ""
	var spot := _spot_at(at)
	if spot >= 0: return String(_spots[spot].tooltip)
	# The battle camera shows its picture and nothing else.
	return "" if SLIDES[slide] == "watch" else _t(TITLES[slide])

## The contents' place between the end pieces.
func area() -> Rect2:
	var from := LEFT_END.size.x + MARGIN
	return Rect2(from, TOP, maxf(0.0, size.x - RIGHT_END.size.x - MARGIN_RIGHT - from), HEIGHT)

func _draw() -> void:
	_icons.queue_redraw()
	_marks.queue_redraw()
	if _art == null: return
	var ends := roomy()
	var from := LEFT_END.size.x if ends else 0.0
	var to := size.x - (RIGHT_END.size.x if ends else 0.0)
	ELHudFrame.draw_rail_backing(self, _art, Vector2(from, 0), to - from, STRIP)
	if not ends: return
	draw_texture_rect_region(_art, Rect2(Vector2.ZERO, LEFT_END.size), LEFT_END)
	draw_texture_rect_region(_art, Rect2(Vector2(to, 0), RIGHT_END.size), RIGHT_END)

func _draw_slide(canvas: Control, pass_index: int) -> void:
	_spots.clear()
	if not roomy(): return
	_canvas = canvas
	_pass = pass_index
	var room := area()
	match SLIDES[slide]:
		"book": _draw_cells(content.get("book", []), room, 2)
		"advice": _draw_advice(content.get("advice", {}), room)
		"watch": _draw_watch(content.get("watch", {}), room)
		_: _draw_rows(content.get(SLIDES[slide], []), room)

## The battle camera's picture in the readout (panel coordinates): all of it.
func watch_rect() -> Rect2:
	return area()

## The battle camera: its picture alone, in a rim.
func _draw_watch(watch: Dictionary, _room: Rect2) -> void:
	var picture := watch_rect()
	var texture: Texture2D = watch.get("texture")
	if _pass == 0 and texture != null: _canvas.draw_texture_rect(texture, picture, false)
	if _pass == 1: _canvas.draw_rect(picture.grow(-0.5), RIM, false, 1.0)

## How `count` icons are laid in `room`, in one row or up to `rows`: the
## largest size that fits, never more than a rail item's, with the columns
## GAP apart or, where that would cost size, a pixel apart.
## Returns (size, rows, column gap).
static func cell_size(count: int, room: Vector2, rows: int) -> Vector3i:
	var best := Vector3i(0, 1, int(GAP))
	for lines in range(1, rows + 1):
		var across := maxi(1, ceili(count / float(lines)))
		var most := minf(floorf((room.y + GAP) / lines - GAP), ELListLook.ITEM_SIZE)
		for between: int in [int(GAP), 1]:
			var size_here := int(minf(most, floorf((room.x + between) / across - between)))
			if size_here > best.x: best = Vector3i(size_here, lines, between)
	return best

func _draw_cells(cells: Array, room: Rect2, rows: int) -> void:
	if cells.is_empty():
		_text("—", room.get_center(), 14, DIM, 0)
		return
	var fit := cell_size(cells.size(), room.size, rows)
	var side := float(maxi(fit.x, 12))
	var step := Vector2(side + fit.z, side + GAP)
	var across := ceili(cells.size() / float(fit.y))
	var block := Vector2(across * step.x - fit.z, fit.y * step.y - GAP)
	var origin := room.position + ((room.size - block) * 0.5).max(Vector2.ZERO).floor()
	for i in cells.size():
		var at := origin + Vector2(i % across, i / across) * step
		if at.x + side > room.end.x + 0.5: continue
		_cell(cells[i], Rect2(at, Vector2(side, side)))

## An item in the combat lists' look: its icon, the veil when spent, the
## hover border under the pointer and its count in the rail's glyphs.
func _cell(cell: Dictionary, rect: Rect2) -> void:
	var icon: Texture2D = cell.get("icon")
	# Icons are drawn smaller than they are: smoothed, whatever the panel's filter.
	if icon != null and _pass == 0: _canvas.draw_texture_rect(icon, rect, false)
	if _pass == 1:
		if cell.get("dim", false) and look != null and look.veil != null: _canvas.draw_texture_rect(look.veil, rect, false, ELListLook.VEIL_TINT)
		elif _hovered == _spots.size() and look != null and look.hover != null: _canvas.draw_texture_rect(look.hover, rect, false)
	var count := int(cell.get("count", -1))
	if count >= 0: _glyphs(str(count), rect.end - Vector2(1, 1))
	_spots.append({"rect": rect, "tooltip": cell.get("tooltip", "")})

## A number in the rail's digit glyphs (ELListLook.GlyphNumber's sheet), its
## last digit's cell ending at `corner`.
func _glyphs(text: String, corner: Vector2) -> void:
	if _pass != 1: return
	var sheet: Texture2D = look.hover.atlas if look != null and look.hover != null else null
	if sheet == null:
		_text(text, corner - Vector2(1, 0), 10, Color.WHITE, 1, true)
		return
	for k in text.length():
		var code := text.unicode_at(text.length() - 1 - k) - 0x2d
		if code < 0 or code > 12: continue
		var source := Rect2(code * 10, 246, 10, 10)
		var at := corner - Vector2(10 + k * 8, 10)
		_canvas.draw_texture_rect_region(sheet, Rect2(at + Vector2.ONE, Vector2(10, 10)), source, Color.BLACK)
		_canvas.draw_texture_rect_region(sheet, Rect2(at, Vector2(10, 10)), source)

## The radio pair, then two rows, one per hero: the portrait and the newest
## items that fit; the last place counts the rest.
func _draw_rows(rows: Array, room: Rect2) -> void:
	var start := room.position.x
	var widest := 0.0
	var tallest := 0.0
	for i in 2:
		var emblem: Dictionary = _emblems.get(SLIDES[2 + i], {})
		if emblem.is_empty(): continue
		widest = maxf(widest, emblem.source.size.x)
		tallest = maxf(tallest, emblem.source.size.y)
	if widest > 0.0:
		# The pair stands in a black housing closed by a bay line, as the
		# original's radios do beside the portrait.
		var housing := Rect2(LEFT_END.size.x, BAY.position.y, room.position.x - LEFT_END.size.x + widest + GAP, BAY.size.y)
		if _pass == 1:
			_canvas.draw_rect(housing, Color("090807"))
			_canvas.draw_texture_rect_region(_art, Rect2(housing.end.x, 0, DIVIDER.size.x, DIVIDER.size.y), DIVIDER)
		var top := BAY.position.y + floorf((BAY.size.y - tallest * 2.0 - GAP) * 0.5)
		for i in 2:
			var emblem: Dictionary = _emblems.get(SLIDES[2 + i], {})
			if emblem.is_empty(): continue
			var extent: Vector2 = emblem.source.size
			var place := Rect2(Vector2(start + floorf((widest - extent.x) * 0.5), top + i * (tallest + GAP)), extent)
			var lit: bool = slide == 2 + i or _hovered == _spots.size()
			if _pass == 1: _canvas.draw_texture_rect_region(emblem.texture, place, emblem.source, Color.WHITE if lit else Color(0.55, 0.55, 0.55))
			_spots.append({"rect": Rect2(housing.position.x, housing.position.y + i * housing.size.y * 0.5, housing.size.x, housing.size.y * 0.5), "tooltip": _t(TITLES[2 + i]), "slide": 2 + i, "sound": "Graveyard" if i == 0 else "Enchantments"})
		start = housing.end.x + DIVIDER.size.x + GAP
	for r in mini(rows.size(), 2):
		var row: Dictionary = rows[r]
		var y := room.position.y + r * (SMALL + GAP)
		var face := Rect2(Vector2(start, y), FACE)
		if row.get("face") != null and _pass == 0: _canvas.draw_texture_rect(row.face, face, false)
		if _pass == 1: _canvas.draw_rect(face.grow(-0.5), RIM, false, 1.0)
		_spots.append({"rect": face, "tooltip": row.get("name", "")})
		var cells: Array = row.get("cells", [])
		var x := face.end.x + GAP + 1.0
		var places := int((room.end.x - x + GAP) / (SMALL + GAP))
		# The places share what width is left over, so the row ends at the
		# right arrow.
		var pitch := SMALL + GAP
		if places > 1: pitch += floorf((room.end.x - x - (places * pitch - GAP)) / (places - 1))
		var shown := cells.size() if cells.size() <= places else maxi(0, places - 1)
		for i in places:
			var place := Rect2(Vector2(x + i * pitch, y), Vector2(SMALL, SMALL))
			if i < shown:
				_cell(cells[i], place)
				if _pass == 1: _canvas.draw_rect(place.grow(-0.5), Color(0, 0, 0, 0.7), false, 1.0)
			elif _pass == 1:
				# An empty place: a plain sunken slot (the list look's knotted
				# tile is too busy at this size).
				_canvas.draw_rect(place, Color(0, 0, 0, 0.32))
				_canvas.draw_rect(place.grow(-0.5), Color(RIM, 0.35), false, 1.0)
		if shown < cells.size() and places > 0:
			var more := Rect2(Vector2(x + shown * pitch, y), Vector2(SMALL, SMALL))
			var names := PackedStringArray()
			for i in range(shown, cells.size()): names.append(String(cells[i].get("tooltip", "")).get_slice("\n", 0))
			_text("+%d" % (cells.size() - shown), more.get_center(), 11, INK, 0)
			_spots.append({"rect": more, "tooltip": "\n".join(names)})

func _draw_advice(advice: Dictionary, room: Rect2) -> void:
	_spots.append({"rect": room, "tooltip": advice.get("tooltip", "")})
	# Below: the verdict in a sunken caption box, as the phase caption is.
	var caption := Rect2(room.position + Vector2(0, SMALL + GAP), Vector2(room.size.x, SMALL))
	if _pass == 1:
		_canvas.draw_rect(caption, Color("090807"))
		_canvas.draw_rect(caption.grow(-0.5), Color(RIM, 0.8), false, 1.0)
	if not advice.get("available", false):
		_text(String(advice.get("reason", "")), caption.get_center(), 11, DIM, 0)
		return
	# Above: both heroes, each with its chance in the counts' gold, and the
	# gauge between them.
	var chance := clampf(float(advice.get("chance", 0.5)), 0.0, 1.0)
	var faces: Array = advice.get("faces", [])
	var names: Array = advice.get("names", [])
	var own := Rect2(room.position, FACE)
	var foe := Rect2(Vector2(room.end.x - FACE.x, room.position.y), FACE)
	for i in 2:
		var face := own if i == 0 else foe
		if i < faces.size() and faces[i] != null and _pass == 0: _canvas.draw_texture_rect(faces[i], face, false)
		if _pass == 1: _canvas.draw_rect(face.grow(-0.5), RIM, false, 1.0)
		if i < names.size(): _spots.append({"rect": face, "tooltip": names[i]})
	var middle := room.position.y + SMALL * 0.5
	# An estimate, not a measured chance: shown to the nearest ESTIMATE_STEP.
	var share := ESTIMATE_STEP * roundi(chance * 100.0 / ESTIMATE_STEP)
	_text("≈%d" % share, Vector2(own.end.x + 18, middle), 13, INK, 0)
	_text("≈%d" % (100 - share), Vector2(foe.position.x - 18, middle), 13, INK, 0)
	if _pass == 1: _gauge(Rect2(own.end.x + 36, middle - 5, foe.position.x - own.end.x - 72, 10), chance, _flash_from, clampf(1.0 - _flash_age / FLASH_TIME, 0.0, 1.0))
	var grade := int(advice.get("grade", -1))
	if grade < 0:
		_text(_t("Reading your move…") if advice.get("pending", false) else _t("Your moves are judged here"), caption.get_center(), 11, DIM, 0)
		return
	# What the move was, and the winning chance it gave away against the best.
	var words := _t(VERDICTS[grade])
	var loss := roundi(float(advice.get("loss", 0.0)))
	if grade > 0 and loss > 0: words += ", −%d %s" % [loss, _t("of the estimate")]
	_text(words, caption.get_center(), 11, GRADE_COLOURS[grade], 0)
	if advice.get("pending", false): _text("…", Vector2(caption.end.x - 4, caption.get_center().y), 13, DIM, 1)

## A gauge in the panel's metal: a bronze frame around a dark slot, filled
## from the left with the counts' gold, a notch at the half. `glow` (1 fading
## to 0) marks a change from `from`: the part gained in green, the part lost
## in red, and the same colour over the frame and the fill.
func _gauge(rect: Rect2, share: float, from := 0.0, glow := 0.0) -> void:
	var gained := share >= from
	var tint := GAIN if gained else HARM
	_canvas.draw_rect(rect, Color("6b5236").lerp(tint, glow * 0.8))
	_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Color("2a2118").lerp(tint, glow * 0.5))
	_canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 1), Vector2(rect.size.x, 1)), Color("9a7a4e").lerp(tint, glow * 0.8))
	var slot := rect.grow(-1)
	_canvas.draw_rect(slot, Color("0b0a08"))
	var filled := Rect2(slot.position, Vector2(roundf(slot.size.x * share), slot.size.y))
	if filled.size.x > 0.0:
		_canvas.draw_rect(filled, Color("a98a55").lerp(tint, glow * 0.35))
		_canvas.draw_rect(Rect2(filled.position, Vector2(filled.size.x, 2)), INK.lerp(tint, glow * 0.35))
		_canvas.draw_rect(Rect2(filled.position + Vector2(0, filled.size.y - 2), Vector2(filled.size.x, 2)), Color("6f5632").lerp(tint, glow * 0.35))
	if glow > 0.0:
		var edge := slot.position.x + roundf(slot.size.x * from)
		var changed := Rect2(minf(edge, filled.end.x), slot.position.y, absf(filled.end.x - edge), slot.size.y)
		if changed.size.x > 0.0: _canvas.draw_rect(changed, Color(tint, glow))
	var half := slot.position.x + floorf(slot.size.x * 0.5)
	_canvas.draw_rect(Rect2(half, rect.position.y, 1, 3), Color("d6bb88"))
	_canvas.draw_rect(Rect2(half, rect.end.y - 3, 1, 3), Color("d6bb88"))

## Text with its middle line at `at.y`: `align` -1 starts at `at.x`, 0 centres
## on it, 1 ends there. `corner` puts the text's lower edge at `at.y` instead.
func _text(text: String, at: Vector2, points: int, colour: Color, align: int, corner := false, shadow := true) -> void:
	if _font == null or text.is_empty() or _pass != 1: return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x
	var x := at.x - (0.0 if align < 0 else (width * 0.5 if align == 0 else width))
	var baseline := at.y - points * 0.12 if corner else at.y + points * 0.36
	if shadow: _canvas.draw_string(_font, Vector2(x + 1, baseline + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, points, Color(0, 0, 0, colour.a * 0.9))
	_canvas.draw_string(_font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, points, colour)
