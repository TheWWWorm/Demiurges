class_name ELBlazonScreen
extends RefCounted
## First game: the player's name and blazon on the front end.
## Campaign screen (SelectCampaign): after a side is clicked, a name frame with
## the SCName edit and a blazon box appear under that side's portrait; the
## blazon box opens the blazon choice. Blazon choice (CISelectBlazon): 72
## logos (15 × 5) and 16 colours (8 × 2) with a preview; clicks and arrow keys
## choose, Tab switches grids, OK keeps the choice and Cancel drops it.

## Panel shift of the 1024 layout.
const PANEL := Vector2(112, 84)
const BLAZON := 41.0
## Name frame (CAMPAIGN_SCREEN_1 0,0 206×93) and blazon box, Good side; the
## Evil side is 271 px to the right.
const FRAME_AT := Vector2(161, 459)
const BOX_AT := Vector2(243, 467)
const SIDE_STEP := 271.0
const BOX_HOVER := Rect2(206, 192, 41, 39)
## Logo grid: 15 columns × 5 rows from (57,40), 46 px pitch.
const LOGO_AT := Vector2(57, 40)
const LOGO_PITCH := 46.0
const LOGO_COLUMNS := 15
## Colour grid: 8 columns × 2 rows from (270,515), 35 × 21 pitch, 30 × 16 swatches.
const COLOUR_AT := Vector2(270, 515)
const COLOUR_PITCH := Vector2(35, 21)
const COLOUR_SIZE := Vector2(30, 16)
const COLOUR_COLUMNS := 8
const PREVIEW_AT := Vector2(120, 509)
## Hover frames (MISSION_SCREEN_1) and the chosen-cell tint (SYMBOLS).
const LOGO_HOVER := Rect2(0, 124, 43, 43)
const COLOUR_HOVER := Rect2(75, 51, 34, 20)
const CHOSEN := Rect2(0, 60, 4, 4)

var menu: ELFrontMenu
## Blazon being chosen in the dialog, the grid with the keyboard focus
## (0 logos, 1 colours) and the screen the dialog returns to.
var working := Vector2i.ZERO
var focus := 0
var return_to := "campaigns"
var name_edit: LineEdit
var frame: FrameView
var box: Canvas
var grid: Canvas
var _hover := Vector2i(-1, -1)
var _box_hover := false

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func profile() -> ELProfile:
	return menu.profile

func texture(name: String) -> Texture2D:
	return menu.texture_named(name)

## Draws a blazon (logo over its colour) at a point, 41 px square. A colour of
## -1 draws the logo alone.
func draw_blazon(canvas: CanvasItem, picture: Vector2i, at: Vector2) -> void:
	var back := texture("BLAZON_BACK")
	if picture.y >= 0 and back != null:
		canvas.draw_texture_rect_region(back, Rect2(at, Vector2(BLAZON, BLAZON)), Rect2(BLAZON * (picture.y % 6), BLAZON * (picture.y / 6), BLAZON, BLAZON))
	if picture.x < 0: return
	var fore := texture("BLAZON_FORE_%02d" % (picture.x / 36))
	var cell := picture.x % 36
	if fore != null: canvas.draw_texture_rect_region(fore, Rect2(at, Vector2(BLAZON, BLAZON)), Rect2(BLAZON * (cell % 6), BLAZON * (cell / 6), BLAZON, BLAZON))

# --- Campaign screen --------------------------------------------------------------

## Side offset of the name frame and blazon box (Good 0, Evil 271).
func side_offset() -> Vector2:
	return Vector2(SIDE_STEP if menu.selected_campaign == "Evil" else 0.0, 0)

func build_campaign() -> void:
	name_edit = LineEdit.new()
	var rect := menu.control_rect("SCName")
	name_edit.position = rect.position
	name_edit.size = Vector2(rect.size.x, rect.size.y + 6)
	name_edit.max_length = ELPlayerProfile.NAME_LIMIT
	name_edit.text = ELPlayerProfile.current_name(profile())
	name_edit.flat = true
	name_edit.context_menu_enabled = false
	name_edit.add_theme_font_override("font", menu.serif)
	name_edit.add_theme_font_size_override("font_size", 15)
	name_edit.add_theme_color_override("font_color", ELFrontMenu.INK)
	name_edit.add_theme_constant_override("minimum_character_width", 0)
	name_edit.text_changed.connect(func(value: String) -> void: ELPlayerProfile.choose_name(value))
	name_edit.visible = false
	menu.canvas.add_child(name_edit)
	box = Canvas.new()
	box.size = Vector2(BLAZON, BLAZON)
	box.draw_call = _draw_box
	box.press_call = func(_point: Vector2) -> void: open_dialog("campaigns")
	box.hover_call = func(inside: bool) -> void:
		_box_hover = inside
		box.queue_redraw()
	box.tooltip_text = profile().text("T_PL_SELECT_BLAZON")
	box.visible = false
	menu.canvas.add_child(box)
	frame = FrameView.new()
	frame.owner_screen = self
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	menu.canvas.add_child(frame)
	menu.canvas.move_child(frame, name_edit.get_index())

## A side was chosen (or cleared): the name frame, edit and blazon box follow
## it; the side's default blazon replaces one still at the other default.
func side_chosen(previous: String, side: String) -> void:
	if side != previous and ELPlayerProfile.SIDE_BLAZON.has(side):
		if previous.is_empty() or ELPlayerProfile.blazon == ELPlayerProfile.SIDE_BLAZON.get(previous, Vector2i(-1, -1)):
			ELPlayerProfile.blazon = ELPlayerProfile.SIDE_BLAZON[side]
	if name_edit == null or not is_instance_valid(name_edit): return
	var shown := not side.is_empty()
	var offset := side_offset()
	var rect := menu.control_rect("SCName")
	name_edit.position = rect.position + offset
	name_edit.visible = shown
	box.position = PANEL + BOX_AT + offset
	box.visible = shown
	frame.position = PANEL + FRAME_AT + offset
	frame.size = Vector2(206, 93)
	frame.visible = shown
	box.queue_redraw()
	frame.queue_redraw()
	if shown and name_edit.is_inside_tree():
		name_edit.grab_focus()
		# The first key typed replaces the whole name.
		name_edit.select_all()
		name_edit.caret_column = name_edit.text.length()

func _draw_box(canvas: Canvas) -> void:
	draw_blazon(canvas, ELPlayerProfile.blazon, Vector2.ZERO)
	var hover := texture("CAMPAIGN_SCREEN_1")
	if _box_hover and hover != null: canvas.draw_texture_rect_region(hover, Rect2(Vector2.ZERO, BOX_HOVER.size), BOX_HOVER)

func open_dialog(back: String) -> void:
	ELUiSounds.play(profile(), "Buttons/Select1.wav")
	return_to = back
	working = ELPlayerProfile.blazon
	focus = 0
	menu.show_screen("blazon" if back == "campaigns" else "blazon_single")

# --- Blazon choice ----------------------------------------------------------------

func build_dialog() -> void:
	menu._label("caption", menu._caption("SBCaption"), menu.control_rect("SBCaption"), 17)
	grid = Canvas.new()
	grid.position = PANEL
	grid.size = Vector2(800, 600)
	grid.draw_call = _draw_grid
	grid.press_call = _press
	grid.motion_call = func(point: Vector2) -> void:
		var hit := _hit(point)
		if hit != _hover:
			_hover = hit
			grid.queue_redraw()
	grid.focus_mode = Control.FOCUS_ALL
	grid.key_call = _key
	menu.canvas.add_child(grid)
	var ok := menu._square("SBOK")
	if ok != null: ok.pressed.connect(func() -> void: close(true))
	var cancel := menu._square("SBCancel")
	if cancel != null: cancel.pressed.connect(func() -> void: close(false))
	grid.grab_focus.call_deferred()

static func logo_rect(index: int) -> Rect2:
	return Rect2(LOGO_AT + Vector2(index % LOGO_COLUMNS, index / LOGO_COLUMNS) * LOGO_PITCH, Vector2(BLAZON, BLAZON))

static func colour_rect(index: int) -> Rect2:
	return Rect2(COLOUR_AT + Vector2(index % COLOUR_COLUMNS, index / COLOUR_COLUMNS) * COLOUR_PITCH, COLOUR_SIZE)

## Grid cell under a panel point: (0, logo) or (1, colour), else (-1, -1).
static func hit(point: Vector2) -> Vector2i:
	for index in ELPlayerProfile.LOGOS:
		if logo_rect(index).has_point(point): return Vector2i(0, index)
	for index in ELPlayerProfile.COLOURS:
		if colour_rect(index).has_point(point): return Vector2i(1, index)
	return Vector2i(-1, -1)

func _hit(point: Vector2) -> Vector2i:
	return hit(point)

func _draw_grid(canvas: Canvas) -> void:
	var symbols := texture("SYMBOLS")
	var hover := texture("MISSION_SCREEN_1")
	var back := texture("BLAZON_BACK")
	for index in ELPlayerProfile.LOGOS:
		var rect := logo_rect(index)
		if index == working.x and symbols != null: canvas.draw_texture_rect_region(symbols, rect, CHOSEN)
		draw_blazon(canvas, Vector2i(index, -1), rect.position)
		if _hover == Vector2i(0, index) and hover != null: canvas.draw_texture_rect_region(hover, Rect2(rect.position - Vector2.ONE, LOGO_HOVER.size), LOGO_HOVER)
	for index in ELPlayerProfile.COLOURS:
		var rect := colour_rect(index)
		if index == working.y and symbols != null: canvas.draw_texture_rect_region(symbols, rect.grow(2), CHOSEN)
		if back != null: canvas.draw_texture_rect_region(back, rect, Rect2((index % 8) * 30, 224 + (index / 8) * 16, 30, 16))
		if _hover == Vector2i(1, index) and hover != null: canvas.draw_texture_rect_region(hover, Rect2(rect.position - Vector2(2, 2), COLOUR_HOVER.size), COLOUR_HOVER)
	draw_blazon(canvas, working, PREVIEW_AT)

func _press(point: Vector2) -> void:
	var cell := hit(point)
	if cell.x < 0: return
	ELUiSounds.play(profile(), "Buttons/Select2.wav")
	choose(cell.x, cell.y)

## Picks a logo (grid 0) or colour (grid 1); that grid takes the keyboard.
func choose(which: int, index: int) -> void:
	focus = which
	if which == 0: working.x = clampi(index, 0, ELPlayerProfile.LOGOS - 1)
	else: working.y = clampi(index, 0, ELPlayerProfile.COLOURS - 1)
	if grid != null and is_instance_valid(grid): grid.queue_redraw()

## Tab switches grids; arrows step 1 sideways and a row (15 logos, 8 colours)
## up or down; a step past either end is ignored.
func key(code: Key) -> bool:
	if code == KEY_TAB:
		focus = 1 - focus
		return true
	var step := 0
	var row := LOGO_COLUMNS if focus == 0 else COLOUR_COLUMNS
	match code:
		KEY_LEFT: step = -1
		KEY_RIGHT: step = 1
		KEY_UP: step = -row
		KEY_DOWN: step = row
		_: return false
	var current := working.x if focus == 0 else working.y
	var limit := ELPlayerProfile.LOGOS if focus == 0 else ELPlayerProfile.COLOURS
	if current + step >= 0 and current + step < limit: choose(focus, current + step)
	return true

func _key(code: Key) -> bool:
	return key(code)

## OK keeps the chosen blazon; Cancel (or Esc) keeps the previous one.
func close(keep: bool) -> void:
	if keep: ELPlayerProfile.blazon = working
	menu.show_screen(return_to)

## Draws through callbacks and forwards clicks, motion and keys.
class Canvas extends Control:
	var draw_call: Callable
	var press_call: Callable
	var motion_call: Callable
	var hover_call: Callable
	var key_call: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: if hover_call.is_valid(): hover_call.call(true))
		mouse_exited.connect(func() -> void: if hover_call.is_valid(): hover_call.call(false))

	func _draw() -> void:
		if draw_call.is_valid(): draw_call.call(self)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and press_call.is_valid():
			press_call.call(event.position)
			accept_event()
		elif event is InputEventMouseMotion and motion_call.is_valid(): motion_call.call(event.position)
		elif event is InputEventKey and event.pressed and key_call.is_valid() and key_call.call(event.keycode): accept_event()

## The name frame under the chosen side's portrait.
class FrameView extends Control:
	var owner_screen: ELBlazonScreen

	func _draw() -> void:
		var art := owner_screen.texture("CAMPAIGN_SCREEN_1")
		if art != null: draw_texture_rect_region(art, Rect2(Vector2.ZERO, Vector2(206, 93)), Rect2(0, 0, 206, 93))
