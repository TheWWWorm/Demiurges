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
## Approximations: glyphs keep a fixed screen size (16 px at 768 lines; the
## original projects them with the figure) and floating numbers rise straight
## up at 0.8 units a second; numbers that start together over one figure
## begin a step apart.

const CELL := 16.0
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
## the Colourless Plane and spell silencing.
const ICON_CODES := [15, 32, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 35, 36, 37]
const FLOAT_LIFE := 3.0
const FLOAT_SPEED := 0.8
const FLOAT_START := 0.17
## Simultaneous numbers over one figure start this far apart (remake spacing).
const STACK_STEP := 0.45
const STACK_AGE := 0.5

var sheet: Texture2D
var camera: Camera3D
## Per figure: {"top": Vector3, "numbers": [[code, colour]...], "icons": [codes],
## "order": [marker, digits...] or []}.
var figures: Array = []
## Rising numbers: {"point": Vector3, "glyphs": [codes], "colour": Color, "age": float}.
var floating: Array = []
var _shown := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func build(profile: ELProfile) -> void:
	sheet = profile.texture("Interface/combatsymbols") if profile != null else null
	figures.clear()
	floating.clear()
	queue_redraw()

## Digit codes of a non-negative number: '0' is 1, '1'..'9' are 2..10.
static func digits(value: int) -> Array:
	var result: Array = []
	for character in str(maxi(value, 0)): result.append(int(character) + 1)
	return result

## The number row: "power/toughness" or a hero's health alone.
static func number_row(power: int, toughness: int, damaged: bool, hero: bool) -> Array:
	var row: Array = []
	var tail := RED if damaged else WHITE
	if hero:
		for code: int in digits(toughness): row.append([code, tail])
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
	floating.append({"point": point + Vector3(0, FLOAT_START + STACK_STEP * fresh, 0), "glyphs": digits(mini(absi(amount), 99999)), "colour": RED if amount > 0 else GREEN, "age": 0.0, "key": key})

## Screen points of the rising numbers (for checks).
func number_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	if camera == null or not is_instance_valid(camera): return result
	for entry: Dictionary in floating: result.append(camera.unproject_position(entry.point))
	return result

func _process(delta: float) -> void:
	if floating.is_empty() and figures.is_empty():
		# Clear the last drawn marks once (numbers turned off, a close-up started).
		if _shown: queue_redraw()
		_shown = false
		return
	_shown = true
	for entry: Dictionary in floating:
		entry.age += delta
		entry.point = entry.point + Vector3(0, FLOAT_SPEED * delta, 0)
	floating = floating.filter(func(entry: Dictionary) -> bool: return entry.age < FLOAT_LIFE)
	queue_redraw()

func glyph_size() -> float:
	var viewport := get_viewport()
	if viewport == null: return CELL
	return roundf(CELL * maxf(viewport.get_visible_rect().size.y / 768.0, 1.0))

func _draw() -> void:
	if sheet == null or camera == null or not is_instance_valid(camera) or not camera.is_inside_tree(): return
	var size := glyph_size()
	for figure: Dictionary in figures:
		var top: Vector3 = figure.get("top", Vector3.ZERO)
		if camera.is_position_behind(top): continue
		var anchor := camera.unproject_position(top)
		var icons: Array = figure.get("icons", [])
		var y := anchor.y - size * (2.0 if not icons.is_empty() else 1.5)
		var numbers: Array = figure.get("numbers", [])
		if not numbers.is_empty(): _draw_row(numbers, anchor.x, y, size)
		if not icons.is_empty():
			var cells: Array = []
			for code: int in icons: cells.append([code, WHITE])
			_draw_row(cells, anchor.x, y + size, size)
		var order: Array = figure.get("order", [])
		if not order.is_empty(): _draw_order(order, anchor.x, y - size, size)
	for entry: Dictionary in floating:
		if camera.is_position_behind(entry.point): continue
		var at := camera.unproject_position(entry.point)
		var cells: Array = []
		for code: int in entry.glyphs: cells.append([code, entry.colour])
		_draw_row(cells, at.x, at.y - size, size)

func _cell(code: int) -> Rect2:
	return Rect2((code % 16) * CELL, (code / 16) * CELL, CELL, CELL)

## One centred row of fixed-advance glyphs.
func _draw_row(cells: Array, centre: float, y: float, size: float) -> void:
	var x := centre - cells.size() * size * 0.5
	for cell: Array in cells:
		draw_texture_rect_region(sheet, Rect2(x, y, size, size), _cell(int(cell[0])), cell[1])
		x += size

## The marker (sword three cells wide, or shield two cells tall) with the
## number centred over it.
func _draw_order(order: Array, centre: float, y: float, size: float) -> void:
	var marker := int(order[0])
	if marker == SWORD:
		draw_texture_rect_region(sheet, Rect2(centre - size * 1.5, y, size * 3, size), Rect2(SWORD * CELL, 0, CELL * 3, CELL))
	else:
		draw_texture_rect_region(sheet, Rect2(centre - size * 0.5, y - size * 0.5, size, size * 2), Rect2(CELL, 2 * CELL, CELL, CELL * 2))
	var cells: Array = []
	for code: int in order.slice(1): cells.append([code, WHITE])
	_draw_row(cells, centre, y, size)
