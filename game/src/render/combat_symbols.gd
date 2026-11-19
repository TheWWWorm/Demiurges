class_name ELCombatSymbols
extends Control
## The combat screen's figure readouts in the original Interface/CombatSymbols
## glyph sheet (16 x 16 cells of 16 px), drawn over the 3D view:
## - over every figure up to three rows, from the top: the order mark (a sword
##   with the attack number, or a shield with the number of the blocked
##   attacker), "power/toughness" (heroes: health), and the state and ability
##   icons. Toughness is red while the creature is damaged.
## - floating damage (red) and healing (green) numbers without a sign, which
##   rise from the top of the figure for 3 seconds.
## Options: ShowCreatureNumbers hides all three rows; ShowIcons the icon row;
## ShowOrder the order row. Floating numbers have no option.
## Size and placement follow the original (EL1, EL2
## ): each glyph is as wide as a camera-facing square 0.24 world units
## across at the figure's mark (rising numbers 0.2), so nearer figures carry
## larger glyphs; the number row hangs just under the mark, or is centred on it
## when an icon row follows; the order row sits one row above, rising numbers
## are centred on their point.
## Approximations: floating numbers rise straight up at 0.8 units a second;
## numbers that start together over one figure begin a step apart; glyphs never
## shrink below MIN_SIZE window pixels (remake readability floor for small
## windows and the remake's zoomed-out orbit; the original has none). Numeric
## readouts are drawn bare over the scene, as in the original (no backing).

const CELL := 16.0
## Half the glyph's world width: figure readouts, rising numbers (original
## 0.12 / 0.1, passed with the anchor to the camera's sprite projection).
const FIGURE_HALF := 0.12
const FLOAT_HALF := 0.1
const MIN_SIZE := 7.0
const SWORD := 11
const SHIELD := 33
## Glyph colours: white, red (damage), green (healing).
const WHITE := Color(1, 1, 1)
const RED := Color(1, 0, 0)
const GREEN := Color(0, 1, 0)
## Icon codes by state bit: resting, summoning rest, cannot attack, flying,
## first strike, bloodthirsty, tireless, vampire, regeneration, robber,
## breaks enchantments, poisonous, cannot rise, unblockable, ready,
## aggressive, guard, evasive; the second game adds the colourless group,
## the Colourless Plane and spell silencing (sheet and text only: no released
## creature has that ability, so the duel never sets it).
const ICON_CODES := [15, 32, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 35, 36, 37]
const FLOAT_LIFE := 3.0
const FLOAT_SPEED := 0.8
const FLOAT_START := 0.17
## Simultaneous numbers over one figure stack this many glyph heights apart on
## screen, so they stay readable from any view (remake spacing).
const STACK_STEP := 1.25
const STACK_AGE := 0.5

var sheet: Texture2D:
	set(value):
		if sheet == value: return
		sheet = value
		_invalidate()
var camera: Camera3D:
	set(value):
		if camera == value: return
		camera = value
		_view_valid = false
		_invalidate()
## Per figure: {"top": Vector3, "numbers": [[code, colour]...], "icons": [codes],
## "order": [marker, digits...] or []}.
var figures: Array = []:
	set(value):
		if figures == value: return
		figures = value
		_invalidate()
		_refresh_processing()
## Rising numbers: {"point": Vector3, "glyphs": [codes], "colour": Color, "age": float}.
var floating: Array = []
var _dirty := true
var _view_valid := false
var _view_camera := Transform3D.IDENTITY
var _view_projection := Projection()
var _view_canvas := Transform2D.IDENTITY
var _view_rect := Rect2()

func _init() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The 16 px sheet is drawn smaller than its cells; mipmaps keep it legible.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	_refresh_processing()

func build(profile: ELProfile) -> void:
	sheet = profile.texture("Interface/combatsymbols") if profile != null else null
	figures.clear()
	floating.clear()
	_invalidate()
	_refresh_processing()

## Digit codes of a non-negative number: '0' is 1, '1'..'9' are 2..10.
static func digits(value: int) -> Array:
	var result: Array = []
	for character in str(maxi(value, 0)): result.append(int(character) + 1)
	return result

## The number row: "power/toughness" or a hero's health alone.
static func number_row(power: int, toughness: int, damaged: bool, hero: bool) -> Array:
	var row: Array = []
	var tail := RED if damaged else WHITE
	# A hero's health is always white, wounded or not, as in the originals.
	if hero:
		for code: int in digits(toughness): row.append([code, WHITE])
		return row
	for code: int in digits(power): row.append([code, WHITE])
	row.append([0, WHITE])
	for code: int in digits(toughness): row.append([code, tail])
	return row

## The order row: the sword (attack number) or shield (blocked attacker).
static func order_row(attack_number: int, blocked_number: int) -> Array:
	if attack_number > 0: return [SWORD] + digits(attack_number)
	if blocked_number > 0: return [SHIELD] + digits(blocked_number)
	return []

## Damage is red, healing green; values stop at 99999.
## Numbers that start together over one figure (`key`) begin one step apart.
func add_number(point: Vector3, amount: int, key := -1) -> void:
	if amount == 0: return
	var fresh := 0
	for entry: Dictionary in floating:
		if key >= 0 and int(entry.get("key", -1)) == key and float(entry.age) < STACK_AGE: fresh += 1
	floating.append({"point": point + Vector3(0, FLOAT_START, 0), "stack": fresh, "glyphs": digits(mini(absi(amount), 99999)), "colour": RED if amount > 0 else GREEN, "age": 0.0, "key": key})
	_invalidate()
	_refresh_processing()

## Screen points of the rising numbers (for checks).
func number_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	if camera == null or not is_instance_valid(camera): return result
	for entry: Dictionary in floating: result.append(_number_at(entry))
	return result

func _number_at(entry: Dictionary, size := -1.0) -> Vector2:
	if size < 0.0: size = glyph_size(entry.point, FLOAT_HALF)
	return camera.unproject_position(entry.point) - Vector2(0, size * STACK_STEP * int(entry.get("stack", 0)))

func _process(delta: float) -> void:
	var moving := not floating.is_empty()
	var count := 0
	for entry: Dictionary in floating:
		entry.age += delta
		entry.point = entry.point + Vector3(0, FLOAT_SPEED * delta, 0)
		if float(entry.age) < FLOAT_LIFE:
			floating[count] = entry
			count += 1
	if count != floating.size(): floating.resize(count)
	# Hidden readouts still age correctly, but do not project or rebuild draw
	# commands. Static anchors need a redraw only after camera/canvas changes.
	if is_visible_in_tree():
		if _view_changed() or moving or _dirty: queue_redraw()
	elif moving:
		_dirty = true
	_refresh_processing()

func _invalidate() -> void:
	_dirty = true
	if is_visible_in_tree(): queue_redraw()

func _refresh_processing() -> void:
	set_process(not floating.is_empty() or (not figures.is_empty() and is_visible_in_tree()))

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_refresh_processing()
		if is_visible_in_tree(): _invalidate()
	elif what == NOTIFICATION_RESIZED:
		_invalidate()

func _view_changed() -> bool:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		var changed := _view_valid
		_view_valid = false
		return changed
	var pose := camera.get_camera_transform()
	var projection := camera.get_camera_projection()
	var canvas := get_viewport().get_final_transform()
	var rect := get_viewport_rect()
	if _view_valid and pose == _view_camera and projection == _view_projection and canvas == _view_canvas and rect == _view_rect:
		return false
	_view_valid = true
	_view_camera = pose
	_view_projection = projection
	_view_canvas = canvas
	_view_rect = rect
	return true

## Glyph size in px at a world point: the screen width of a camera-facing
## square `half` x 2 units across there (fixed 16 px without a camera).
func glyph_size(point: Vector3, half := FIGURE_HALF) -> float:
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree(): return CELL
	var right := camera.global_transform.basis.x.normalized() * half
	var width := camera.unproject_position(point + right).distance_to(camera.unproject_position(point - right))
	return maxf(width, MIN_SIZE / _window_scale())

## Window pixels per canvas unit (the stretched canvas is larger than small windows).
func _window_scale() -> float:
	var viewport := get_viewport()
	if viewport == null: return 1.0
	var scale := viewport.get_final_transform().get_scale().y
	return scale if scale > 0.0 else 1.0

## The screen rows of one figure's readout: glyph size, anchor and the tops of
## the number, icon and order rows (from the original's layout).
func figure_rows(figure: Dictionary) -> Dictionary:
	var top: Vector3 = figure.get("top", Vector3.ZERO)
	var size := glyph_size(top)
	var anchor := camera.unproject_position(top)
	var numbers := anchor.y - size * 0.5 if not (figure.get("icons", []) as Array).is_empty() else anchor.y
	return {"size": size, "anchor": anchor, "numbers": numbers, "icons": numbers + size, "order": numbers - size}

## The area one figure's readout covers on screen (for checks).
func figure_rect(figure: Dictionary) -> Rect2:
	var rows := figure_rows(figure)
	return _figure_bounds(figure, rows)

func _figure_bounds(figure: Dictionary, rows: Dictionary) -> Rect2:
	var size: float = rows.size
	var width := maxf(float((figure.get("numbers", []) as Array).size()), float((figure.get("icons", []) as Array).size())) * size
	var top: float = rows.numbers
	if not (figure.get("order", []) as Array).is_empty():
		width = maxf(width, 3.0 * size)
		top = rows.order - (size * 0.5 if int(figure.order[0]) == SHIELD else 0.0)
	var bottom: float = rows.icons + size if not (figure.get("icons", []) as Array).is_empty() else rows.numbers + size
	return Rect2(rows.anchor.x - width * 0.5, top, width, bottom - top)

## The screen squares of one figure's icon row, left to right:
## {"id": figure id, "bit": icon bit (T_CREATURE_ICON_<bit+1>), "rect": Rect2}.
## Empty while the figure is behind the camera or has no icons.
func icon_rects(figure: Dictionary) -> Array:
	var result: Array = []
	var icons: Array = figure.get("icons", [])
	if icons.is_empty() or camera == null or not is_instance_valid(camera) or not camera.is_inside_tree(): return result
	if camera.is_position_behind(figure.get("top", Vector3.ZERO)): return result
	var rows := figure_rows(figure)
	var size: float = rows.size
	var x: float = rows.anchor.x - icons.size() * size * 0.5
	for i in icons.size():
		result.append({"id": int(figure.get("id", -1)), "bit": ICON_CODES.find(int(icons[i])),
			"rect": Rect2(x + i * size, rows.icons, size, size)})
	return result

## The icon under a screen point, as icon_rects gives it, else {}. Like the
## original, which keeps each icon's screen
## rect as it draws the row: where rows overlap, the nearest figure's icon.
func icon_at(point: Vector2) -> Dictionary:
	var found := {}
	if not is_visible_in_tree() or camera == null or not is_instance_valid(camera) or not camera.is_inside_tree(): return found
	var depth := INF
	for figure: Dictionary in figures:
		var icons: Array = figure.get("icons", [])
		var top: Vector3 = figure.get("top", Vector3.ZERO)
		if icons.is_empty() or camera.is_position_behind(top): continue
		var rows := figure_rows(figure)
		var size: float = rows.size
		var x: float = rows.anchor.x - icons.size() * size * 0.5
		var row := Rect2(x, rows.icons, 0.0, size)
		if point.y < row.position.y or point.y >= row.end.y: continue
		var index := floori((point.x - x) / size)
		var distance := camera.global_position.distance_squared_to(top)
		if distance >= depth: continue
		# Rect2 stores float32 coordinates. At an exact cell boundary its
		# rounded edge can differ from the division by one ULP; checking the
		# adjacent cells keeps picking identical to the drawn rectangles.
		for candidate in range(maxi(0, index - 1), mini(icons.size(), index + 2)):
			var rect := Rect2(x + candidate * size, rows.icons, size, size)
			if not rect.has_point(point): continue
			var bit := ICON_CODES.find(int(icons[candidate]))
			if bit < 0: continue
			depth = distance
			found = {"id": int(figure.get("id", -1)), "bit": bit, "rect": rect}
			break
	return found

func _draw() -> void:
	_dirty = false
	if sheet == null or camera == null or not is_instance_valid(camera) or not camera.is_inside_tree(): return
	var view := get_viewport_rect()
	var pixel := 1.0 / _window_scale()
	var margin := maxf(2.0, 3.0 * pixel)
	for figure: Dictionary in figures:
		var top: Vector3 = figure.get("top", Vector3.ZERO)
		if camera.is_position_behind(top): continue
		var rows := figure_rows(figure)
		if not view.intersects(_figure_bounds(figure, rows).grow(margin)): continue
		var size: float = rows.size
		var x: float = rows.anchor.x
		var icons: Array = figure.get("icons", [])
		var numbers: Array = figure.get("numbers", [])
		if not numbers.is_empty(): _draw_row(numbers, x, rows.numbers, size)
		if not icons.is_empty():
			_draw_codes(icons, WHITE, x, rows.icons, size)
		var order: Array = figure.get("order", [])
		if not order.is_empty(): _draw_order(order, x, rows.order, size)
	for entry: Dictionary in floating:
		if camera.is_position_behind(entry.point): continue
		var size := glyph_size(entry.point, FLOAT_HALF)
		var at := _number_at(entry, size)
		var glyphs: Array = entry.glyphs
		var width := glyphs.size() * size
		if not view.intersects(Rect2(at - Vector2(width, size) * 0.5, Vector2(width, size)).grow(margin)): continue
		var x := at.x - width * 0.5
		for code: int in glyphs:
			_draw_glyph(code, entry.colour, Rect2(x, at.y - size * 0.5, size, size))
			x += size

static func cell_rect(code: int) -> Rect2:
	return Rect2((code % 16) * CELL, (code / 16) * CELL, CELL, CELL)

## One centred row of fixed-advance glyphs.
func _draw_row(cells: Array, centre: float, y: float, size: float) -> void:
	var x := centre - cells.size() * size * 0.5
	for cell: Array in cells:
		_draw_glyph(int(cell[0]), cell[1], Rect2(x, y, size, size))
		x += size

## Single-colour rows already store codes, so avoid building [code, colour]
## arrays for every icon, order and floating number on every drawn frame.
func _draw_codes(codes: Array, colour: Color, centre: float, y: float, size: float, first := 0) -> void:
	var x := centre - (codes.size() - first) * size * 0.5
	for index in range(first, codes.size()):
		_draw_glyph(int(codes[index]), colour, Rect2(x, y, size, size))
		x += size

func _draw_glyph(code: int, colour: Color, rect: Rect2) -> void:
	draw_texture_rect_region(sheet, rect, cell_rect(code), colour)

## The marker (sword three cells wide, or shield two cells tall) with the
## number centred over it.
func _draw_order(order: Array, centre: float, y: float, size: float) -> void:
	var marker := int(order[0])
	if marker == SWORD:
		draw_texture_rect_region(sheet, Rect2(centre - size * 1.5, y, size * 3, size), Rect2(SWORD * CELL, 0, CELL * 3, CELL))
	else:
		draw_texture_rect_region(sheet, Rect2(centre - size * 0.5, y - size * 0.5, size, size * 2), Rect2(CELL, 2 * CELL, CELL, CELL * 2))
	_draw_codes(order, WHITE, centre, y, size, 1)
