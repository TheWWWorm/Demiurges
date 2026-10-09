extends Control
## Second game: ExBlinkElement frames on the InventoryScreen.
## In the lit half of each 500 ms period a frame is drawn around the element's
## fixed rectangle (initialised, relative to the screen origin, i.e.
## the InventoryScreen panel shift). The frame is a ring of 5-pixel cells from
## WORLD_SYMBOLS_MAP: width/5 by height/5 cells (at least 3 each), corner
## pieces at the corners and edge pieces repeated along the sides, the inside
## left open.
const RECTS := {
	"E_INV_HERO_INFO": Rect2(25, 28, 278, 113),
	"E_INV_SPEC": Rect2(25, 163, 282, 46),
	"E_INV_SKILLS": Rect2(25, 233, 282, 146),
	"E_INV_ARTIFACTS": Rect2(25, 404, 282, 116),
	"E_INV_DECK": Rect2(342, 404, 439, 113),
	"E_INV_BAG": Rect2(337, 60, 448, 318),
}
const PERIOD := 0.5
const CELL := 5
## WORLD_SYMBOLS_MAP source cells: [column, row] of the 3x3 frame -> origin.
const PIECES := {
	Vector2i(0, 0): Vector2(10, 200), Vector2i(1, 0): Vector2(16, 200), Vector2i(2, 0): Vector2(22, 200),
	Vector2i(0, 1): Vector2(10, 206), Vector2i(2, 1): Vector2(22, 206),
	Vector2i(0, 2): Vector2(10, 212), Vector2i(1, 2): Vector2(16, 212), Vector2i(2, 2): Vector2(22, 212),
}
## Without the texture: gold corner brackets of the same size.
const COLOR := Color8(0xf2, 0xc9, 0x4c)
const WIDTH := 3.0
var texture: Texture2D

var state: ELAdventureSession
## Design-space origin of the screen (ELSecondInventoryView._offset).
var origin: Callable
var lit := true
var _clock := 0.0
var _shown := ""

func _ready() -> void:
	name = "BlinkFrames"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture == null and state != null:
		var profile := state.map.profile
		for row: Dictionary in profile.table("InterfaceTextures").values():
			if row.get("Name", "") == "WORLD_SYMBOLS_MAP":
				texture = profile.texture("Interface/" + str(row.get("Path", "")).replace("\\", "/"))

## Cells across and down: a fifth of each side, at least three.
static func cells(rect: Rect2) -> Vector2i:
	return Vector2i(maxi(int(rect.size.x) / CELL, 3), maxi(int(rect.size.y) / CELL, 3))

## Source origin of the piece at cell (x, y) of a frame `count` cells big;
## (-1, -1) inside the frame.
static func piece(x: int, y: int, count: Vector2i) -> Vector2:
	var column := 0 if x == 0 else (2 if x == count.x - 1 else 1)
	var row := 0 if y == 0 else (2 if y == count.y - 1 else 1)
	return PIECES.get(Vector2i(column, row), Vector2(-1, -1))

func active() -> Array[String]:
	var result: Array[String] = []
	if state == null: return result
	for element: String in RECTS:
		if state.blinks.has(element): result.append(element)
	return result

## The frame rectangle of `element` in the parent's design coordinates.
func frame(element: String) -> Rect2:
	var at: Vector2 = origin.call() if origin.is_valid() else Vector2.ZERO
	var rect: Rect2 = RECTS[element]
	return Rect2(rect.position + at, rect.size)

func _process(delta: float) -> void:
	if get_parent() is Control: size = (get_parent() as Control).size
	var shown := ",".join(active())
	if shown != _shown:
		# Setting a flag restarts the period in the lit phase.
		_shown = shown
		lit = true
		_clock = 0.0
		queue_redraw()
	if shown.is_empty(): return
	_clock += delta
	if _clock >= PERIOD:
		_clock = fmod(_clock, PERIOD)
		lit = not lit
		queue_redraw()

func _draw() -> void:
	if not lit: return
	for element: String in active():
		var rect := frame(element)
		if texture != null:
			var count := cells(rect)
			for y in count.y:
				for x in count.x:
					var source := piece(x, y, count)
					if source.x < 0: continue
					draw_texture_rect_region(texture, Rect2(rect.position + Vector2(x, y) * CELL, Vector2(CELL, CELL)), Rect2(source, Vector2(CELL, CELL)))
			continue
		var arm := Vector2(maxf(rect.size.x / 5.0, 3.0), maxf(rect.size.y / 5.0, 3.0))
		var a := rect.position
		var b := rect.end
		for corner: Array in [[a, Vector2(1, 1)], [Vector2(b.x, a.y), Vector2(-1, 1)], [b, Vector2(-1, -1)], [Vector2(a.x, b.y), Vector2(1, -1)]]:
			var point: Vector2 = corner[0]
			var sign: Vector2 = corner[1]
			draw_line(point, point + Vector2(arm.x * sign.x, 0), Color(0, 0, 0, 0.7), WIDTH + 2)
			draw_line(point, point + Vector2(0, arm.y * sign.y), Color(0, 0, 0, 0.7), WIDTH + 2)
			draw_line(point, point + Vector2(arm.x * sign.x, 0), COLOR, WIDTH)
			draw_line(point, point + Vector2(0, arm.y * sign.y), COLOR, WIDTH)
