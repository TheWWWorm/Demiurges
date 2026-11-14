class_name ELPuzzleMode
extends CanvasLayer
## Battle puzzles on screen (a remake addition; see ELPuzzles): the list to
## choose from, the strip over a puzzle's battle that says what is asked and
## how far the attempt is, and the box that closes an attempt. All three are
## dressed in the game's own interface pieces (ELMenuKit: the Options frame,
## its header strips and column boxes, the lobby's buttons), like the
## remake's settings. The host starts the duel of a chosen puzzle and steps
## this each frame.

## A puzzle was chosen (from the list, Restart or Next): the host starts it.
signal play_requested(index: int)
## The player left the puzzles: back to the main menu.
signal left

const SOLVED_INK := Color("9fc98a")
const FAILED_INK := Color("d99a86")
const LEVELS := ["Easy puzzles", "Medium puzzles", "Hard puzzles"]
## The result follows the end of the battle by this long.
const RESULT_DELAY := 1.2

var profile: ELProfile
## The attempt being played (null outside a puzzle).
var run: ELPuzzles.Run
var _kit: ELMenuKit
## The game the controls were built for.
var _built := ""
var _top: CanvasLayer
var _over: Control
var _under: Control
var _shade: ColorRect
var _list: PanelContainer
var _list_note: Label
var _groups: VBoxContainer
var _bar: PanelContainer
var _bar_text: Label
var _hint_text: Label
var _result: PanelContainer
var _result_title: Label
var _result_text: Label
var _next: Button
var _again: Button
var _result_clock := 0.0
var _result_shown := false
var _shown_turn := -1

func _init() -> void:
	# The strip lies over the battle's own controls and under every menu;
	# the list and the result lie over the main menu too.
	layer = 4
	_top = CanvasLayer.new()
	_top.layer = 7
	add_child(_top)

## Whether a puzzle is being played.
func active() -> bool:
	return run != null

## The duel of the attempt being played.
func duel() -> ELDuel:
	return run.duel if run != null else null

## The battle under it takes no orders: the list or the result is open, or
## the attempt has ended and its result is about to show.
func blocking() -> bool:
	if _list == null: return false
	return _list.visible or _result.visible or (run != null and not run.outcome.is_empty())

# --- Looks ----------------------------------------------------------------------

## Builds the controls in the look of `source`'s game (once per game).
func _use(source: ELProfile) -> void:
	profile = source
	if _built == source.id: return
	_built = source.id
	for old: Control in [_over, _under]:
		if old != null: old.queue_free()
	_kit = ELMenuKit.for_profile(source)
	var look: Theme = _kit.theme() if _kit != null else null
	if look == null: _kit = null
	_over = _layer_root(_top, look)
	_under = _layer_root(self, look)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.55)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()
	_over.add_child(_shade)
	_build_bar()
	_build_list()
	_build_result()

func _layer_root(parent: Node, look: Theme) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if look != null: root.theme = look
	parent.add_child(root)
	return root

## The Options frame ("frame") or one of its column boxes ("box") around a
## panel; a dark plate for a game without those pieces.
func _panel(kind: String, padding: Vector4) -> StyleBox:
	if _kit != null: return _kit.panel_style(kind, padding)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.94 if kind == "frame" else 0.78)
	style.border_color = Color(ELMenuKit.TITLE_INK, 0.6 if kind == "frame" else 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	return style

## A push button: the lobby's plate from the kit's theme, or a dark plate.
func _button(text: String, width := 120.0, height := 34.0) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, height)
	if _kit != null:
		ELUiSounds.bind(button, profile, str(_kit.art.get("button", "")))
		return button
	for state: String in ["font_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ELMenuKit.TITLE_INK)
	button.add_theme_color_override("font_hover_color", ELMenuKit.HOVER_INK)
	for state: Array in [["normal", 0.3], ["hover", 0.6], ["pressed", 1.0]]:
		var style := _panel("box", Vector4(12, 5, 12, 5)) as StyleBoxFlat
		style.border_color = Color(ELMenuKit.TITLE_INK, float(state[1]))
		button.add_theme_stylebox_override(String(state[0]), style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

static func _text(size: int, ink: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

## A titled group of the list: the Options header strip, then its rows.
func _group(parent: VBoxContainer, title: String) -> VBoxContainer:
	if _kit != null: return _kit.section(parent, title)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	var caption := _text(17, ELMenuKit.TITLE_INK)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.text = title
	column.add_child(caption)
	return column

func _centred(panel: PanelContainer) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

# --- The list -------------------------------------------------------------------

func _build_list() -> void:
	_list = PanelContainer.new()
	_list.name = "PuzzleList"
	_list.add_theme_stylebox_override("panel", _panel("frame", Vector4(34, 30, 34, 30)))
	_centred(_list)
	_list.hide()
	_over.add_child(_list)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_list.add_child(column)
	column.add_child(ELMenuKit.heading("Puzzles", 22))
	_list_note = _text(15, ELMenuKit.BODY_INK)
	_list_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_note.custom_minimum_size.x = 560
	column.add_child(_list_note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 14)
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_groups)
	var back := Button.new()
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The lobby's Back, as the remake's other dialogs close.
	if _kit == null or not _kit.icon_button(back, str(_kit.art.get("back", _kit.art.get("close", ""))), "Back"):
		back.queue_free()
		back = _button("Back", 160)
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_list)
	column.add_child(back)

## Opens the list of `source`'s puzzles.
func open_list(source: ELProfile) -> void:
	_use(source)
	var entries := ELPuzzles.list(profile.id)
	_list_note.text = "Each battle can be won within the turns given, whatever the enemy does. Find the way.\nSolved: %d of %d" % [ELPuzzles.solved_count(profile.id), entries.size()]
	for child: Node in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	var grids := {}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var level := clampi(int(entry.get("level", 2)), 1, 3)
		if not grids.has(level):
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			_group(_groups, LEVELS[level - 1]).add_child(grid)
			grids[level] = grid
		var taken := ELPuzzles.solved_in(profile.id, String(entry.id))
		var button := _button("%d  ·  %d turns" % [i + 1, int(entry.turns)], 140, 36)
		# A solved puzzle is ticked, in the Options check box.
		var box: Texture2D = _over.theme.get_icon("checked" if taken > 0 else "unchecked", "CheckBox") if _over.theme != null and _over.theme.has_icon("checked", "CheckBox") else null
		if box != null:
			button.icon = box
			button.add_theme_constant_override("h_separation", 8)
		elif taken > 0: button.text = "%d  ·  %d turns  ·  Solved" % [i + 1, int(entry.turns)]
		if taken > 0:
			button.tooltip_text = "Solved in turn %d" % taken
			for state: String in ["font_color", "font_focus_color"]: button.add_theme_color_override(state, SOLVED_INK)
		button.pressed.connect(func():
			_list.hide()
			_shade.hide()
			play_requested.emit(i))
		(grids[level] as GridContainer).add_child(button)
	_shade.show()
	_list.show()
	_result.hide()

func _close_list() -> void:
	_list.hide()
	_shade.hide()
	# Over a puzzle's battle the list closes back to it; an ended attempt
	# shows its result again.
	if run == null: left.emit()
	elif not run.outcome.is_empty(): _show_result()

# --- The strip over the battle --------------------------------------------------

func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.name = "PuzzleStrip"
	_bar.add_theme_stylebox_override("panel", _panel("box", Vector4(14, 6, 10, 6)))
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.offset_top = 6
	_bar.hide()
	_under.add_child(_bar)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_bar.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_bar_text = _text(16, ELMenuKit.TITLE_INK)
	row.add_child(_bar_text)
	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	row.add_child(gap)
	var hint := _button("Hint", 76, 30)
	hint.pressed.connect(func():
		if _hint_text.visible: _hint_text.hide()
		else: show_hint())
	row.add_child(hint)
	var again := _button("Restart", 96, 30)
	again.pressed.connect(func():
		if run != null: play_requested.emit(run.index))
	row.add_child(again)
	var others := _button("Puzzles", 96, 30)
	others.pressed.connect(func():
		if profile != null: open_list(profile))
	row.add_child(others)
	var leave := _button("Leave", 86, 30)
	leave.pressed.connect(leave_puzzles)
	row.add_child(leave)
	_hint_text = _text(15, ELMenuKit.BODY_INK)
	_hint_text.hide()
	column.add_child(_hint_text)

## The first command of a winning line, under the strip.
func show_hint() -> void:
	if run == null: return
	_hint_text.text = run.hint()
	_hint_text.show()

## The host has started `attempt`'s duel: the strip shows over it.
func begin(source: ELProfile, attempt: ELPuzzles.Run) -> void:
	_use(source)
	run = attempt
	_result_clock = 0.0
	_result_shown = false
	_shown_turn = -1
	_hint_text.hide()
	_list.hide()
	_shade.hide()
	_result.hide()
	_bar.show()
	_refresh_bar()

func _refresh_bar() -> void:
	if run == null: return
	_shown_turn = run.turn
	_bar_text.text = "Puzzle %d  ·  Win in %d turns  ·  Turn %d of %d" % [run.index + 1, run.allowed, clampi(run.turn, 1, run.allowed), run.allowed]
	if ELPuzzles.solved_in(run.edition, String(run.entry.id)) > 0: _bar_text.text += "  ·  Solved"

## Follows the attempt each frame; `idle` once nothing of the battle is
## still being shown (a fight, a spell, the winner's clip).
func step(delta: float, idle: bool) -> void:
	if run == null: return
	run.watch()
	if run.turn != _shown_turn: _refresh_bar()
	if run.outcome.is_empty() or _result_shown or _list.visible: return
	if not idle:
		_result_clock = 0.0
		return
	_result_clock += delta
	if _result_clock >= RESULT_DELAY: _show_result()

# --- The result -----------------------------------------------------------------

func _build_result() -> void:
	_result = PanelContainer.new()
	_result.name = "PuzzleResult"
	_result.add_theme_stylebox_override("panel", _panel("frame", Vector4(36, 30, 36, 30)))
	_centred(_result)
	_result.hide()
	_over.add_child(_result)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_result.add_child(column)
	_result_title = ELMenuKit.heading("", 22)
	column.add_child(_result_title)
	_result_text = _text(15, ELMenuKit.BODY_INK)
	_result_text.custom_minimum_size.x = 380
	column.add_child(_result_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_next = _button("Next puzzle", 140)
	_next.pressed.connect(func():
		if run != null and profile != null: play_requested.emit(mini(run.index + 1, ELPuzzles.list(profile.id).size() - 1)))
	row.add_child(_next)
	_again = _button("Try again", 130)
	_again.pressed.connect(func():
		if run != null: play_requested.emit(run.index))
	row.add_child(_again)
	var others := _button("Puzzles", 120)
	others.pressed.connect(func():
		if profile != null: open_list(profile))
	row.add_child(others)

## The attempt's result (also on the end-of-phase control once it is over).
func show_result() -> void:
	if run != null and not run.outcome.is_empty() and not _list.visible: _show_result()

func _show_result() -> void:
	if run == null: return
	_result_shown = true
	var solved := run.outcome == "solved"
	_result_title.text = "Puzzle solved" if solved else "Not solved"
	_result_title.add_theme_color_override("font_color", SOLVED_INK if solved else FAILED_INK)
	if solved:
		var count := ELPuzzles.list(profile.id).size()
		_result_text.text = "Won in turn %d of %d.\nSolved: %d of %d" % [clampi(run.turn, 1, run.allowed), run.allowed, ELPuzzles.solved_count(profile.id), count]
		_next.visible = run.index + 1 < count
	else:
		_result_text.text = "Your hero has fallen." if run.reason == "lost" else "The turns have run out: the win was there within %d turns." % run.allowed
		_next.hide()
	_again.text = "Play again" if solved else "Try again"
	_shade.show()
	_result.show()

# --- Leaving --------------------------------------------------------------------

## Ends the attempt without a word (another battle starts, the game leaves).
func close() -> void:
	run = null
	if _list == null: return
	_bar.hide()
	_list.hide()
	_result.hide()
	_shade.hide()

## The Leave button: out of the puzzle and back to the main menu.
func leave_puzzles() -> void:
	close()
	left.emit()
