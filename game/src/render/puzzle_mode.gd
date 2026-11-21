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
## A generated challenge or an exact retry; never an authored catalog index.
signal generated_requested(entry: Dictionary)
## The player left the puzzles: back to the main menu.
signal left

const SOLVED_INK := Color("9fc98a")
const FAILED_INK := Color("d99a86")
const LEVELS := ["Easy puzzles", "Medium puzzles", "Hard puzzles", "Expert puzzles", "Master puzzles"]
const RANDOM_LEVEL_NAMES := {2: "Medium", 3: "Hard", 4: "Expert", 5: "Master · 2 turns"}
const RANDOM_LEVEL_GUIDANCE := {
	2: "Short tactical combinations. Find the key interaction.",
	3: "Combine several tactics and manage limited resources.",
	4: "Resolve interacting threats and plan for the strongest reply.",
	5: "Plan across two turns: survive the reply and prepare the finish."
}
const GOALS := ["", "win", "clear", "survive", "control"]
const GOAL_NAMES := {"win": "Win", "clear": "Clear army", "survive": "Survive", "control": "Control"}
const HINTLESS_DESCRIPTION := "Completed in an attempt without revealing hints. You can earn this on a replay."
## The result follows the end of the battle by this long.
const RESULT_DELAY := 1.2

var profile: ELProfile
## The installed games by id, for the switch over the list (set by the host).
var games: Dictionary = {}
## The game names on the switch.
const GAME_NAMES := {"el1": "Etherlords", "el2": "Etherlords II"}
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
var _switch: HBoxContainer
var _catalog: VBoxContainer
var _catalog_tab: Button
var _random_tab: Button
var _random_panel: VBoxContainer
var _random_level: OptionButton
var _random_guidance: Label
var _random_seed: LineEdit
var _random_generate: Button
var _random_cancel: Button
var _random_status: Label
var _random_code: LineEdit
var _random_copy: Button
var _random_selected := false
var _random_difficulty := 3
var _random_input := ""
var _last_random_code := ""
var _generator_job: RefCounted
## Generation work per frame; a short menu frame leaves the rest for drawing.
const GENERATOR_SLICE_USEC := 12000
const GENERATOR_NODE_QUOTA := 100000
var _generator_profile: ELProfile
var _generator_seed := 0
## Accepted challenges guide automatic variety. Explicit codes keep using
## the history-independent generator; cancellation and retries add nothing.
var _random_session: RefCounted = ELPuzzleGenerator.Session.new()
var _generated_copy: Button
var _groups: VBoxContainer
var _list_scroll: ScrollContainer
var _goal_choice: OptionButton
var _difficulty_choice: OptionButton
var _progress_choice: OptionButton
var _search: LineEdit
var _continue: Button
## Filters survive opening the list and switching editions.
var _goal_filter := 0
var _difficulty_filter := 0
var _progress_filter := 0
var _search_query := ""
var _continue_index := -1
var _bar: PanelContainer
var _bar_text: Label
var _objective_text: Label
var _rules_text: Label
var _briefing_text: Label
var _supply_scroll: ScrollContainer
var _supply_text: Label
var _briefing_button: Button
var _hint_text: Label
var _hint_button: Button
var _hide_hint: Button
## Hiding a hint does not reveal the next one when it is reopened.
var _hint_index := -1
var _advice_button: Button
var _advice_scroll: ScrollContainer
var _advice_text: Label
var _advice_job: RefCounted
var _advice_result: Dictionary = {}
var _advice_state_key := ""
var _result: PanelContainer
var _result_title: Label
var _result_text: Label
var _result_explanation: Label
var _result_code_row: HBoxContainer
var _result_code: LineEdit
var _next: Button
var _next_index := -1
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
	_cancel_generation()
	_cancel_advice()
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
	_dress_button(button)
	return button

func _dress_button(button: Button) -> void:
	if _kit != null:
		ELUiSounds.bind(button, profile, str(_kit.art.get("button", "")))
		return
	for state: String in ["font_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ELMenuKit.TITLE_INK)
	button.add_theme_color_override("font_hover_color", ELMenuKit.HOVER_INK)
	for state: Array in [["normal", 0.3], ["hover", 0.6], ["pressed", 1.0]]:
		var style := _panel("box", Vector4(12, 5, 12, 5)) as StyleBoxFlat
		style.border_color = Color(ELMenuKit.TITLE_INK, float(state[1]))
		button.add_theme_stylebox_override(String(state[0]), style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _choice(labels: Array, width: float) -> OptionButton:
	var choice := OptionButton.new()
	choice.focus_mode = Control.FOCUS_NONE
	choice.custom_minimum_size = Vector2(width, 32)
	choice.add_theme_font_size_override("font_size", 14)
	for label: String in labels: choice.add_item(ELRemakeText.t(label, profile))
	_dress_button(choice)
	return choice

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
	_list.add_theme_stylebox_override("panel", _panel("frame", Vector4(24, 20, 24, 20)))
	_centred(_list)
	_list.hide()
	_over.add_child(_list)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_list.add_child(column)
	var heading := HBoxContainer.new()
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", 16)
	column.add_child(heading)
	heading.add_child(ELMenuKit.heading("Puzzles", 22))
	_catalog_tab = _button("Collection", 120, 28)
	_catalog_tab.name = "AuthoredPuzzleTab"
	_catalog_tab.toggle_mode = true
	_catalog_tab.add_theme_font_size_override("font_size", 14)
	_catalog_tab.pressed.connect(func(): _select_puzzle_tab(false))
	heading.add_child(_catalog_tab)
	_random_tab = _button("Random challenge", 160, 28)
	_random_tab.name = "RandomPuzzleTab"
	_random_tab.toggle_mode = true
	_random_tab.add_theme_font_size_override("font_size", 14)
	_random_tab.pressed.connect(func(): _select_puzzle_tab(true))
	heading.add_child(_random_tab)
	# Either game's puzzles, whichever game the main menu shows.
	_switch = HBoxContainer.new()
	_switch.name = "GameSwitch"
	_switch.alignment = BoxContainer.ALIGNMENT_CENTER
	_switch.add_theme_constant_override("separation", 8)
	column.add_child(_switch)
	_catalog = VBoxContainer.new()
	_catalog.name = "AuthoredPuzzleCatalog"
	_catalog.add_theme_constant_override("separation", 10)
	column.add_child(_catalog)
	_list_note = _text(15, ELMenuKit.BODY_INK)
	_list_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_note.custom_minimum_size.x = 560
	_catalog.add_child(_list_note)
	_search = LineEdit.new()
	_search.name = "PuzzleSearch"
	_search.custom_minimum_size = Vector2(600, 32)
	_search.add_theme_font_size_override("font_size", 14)
	_search.placeholder_text = ELRemakeText.t("Search titles, heroes and briefings", profile)
	_search.tooltip_text = ELRemakeText.t("Match all words in titles, categories, briefings or hero names and levels, in English or Russian.", profile)
	_search.clear_button_enabled = true
	if _kit == null:
		_search.add_theme_stylebox_override("normal", _panel("box", Vector4(10, 5, 10, 5)))
		_search.add_theme_color_override("font_color", ELMenuKit.BODY_INK)
	_search.text = _search_query
	_search.text_changed.connect(func(value: String):
		_search_query = value
		_fill_list())
	_catalog.add_child(_search)
	var filters := HBoxContainer.new()
	filters.name = "PuzzleFilters"
	filters.alignment = BoxContainer.ALIGNMENT_CENTER
	filters.add_theme_constant_override("separation", 8)
	_catalog.add_child(filters)
	_goal_choice = _choice(["Goal: All", "Goal: Win", "Goal: Clear", "Goal: Survive", "Goal: Control"], 170)
	_goal_choice.name = "ObjectiveFilter"
	_goal_choice.tooltip_text = ELRemakeText.t("Filter by objective", profile)
	_goal_choice.select(_goal_filter)
	_goal_choice.item_selected.connect(func(at: int):
		_goal_filter = at
		_fill_list())
	filters.add_child(_goal_choice)
	_difficulty_choice = _choice(["All difficulties", "Easy", "Medium", "Hard", "Expert", "Master"], 140)
	_difficulty_choice.name = "DifficultyFilter"
	_difficulty_choice.tooltip_text = ELRemakeText.t("Puzzle difficulty is separate from the heroes' levels.", profile)
	_difficulty_choice.select(_difficulty_filter)
	_difficulty_choice.item_selected.connect(func(at: int):
		_difficulty_filter = at
		_fill_list())
	filters.add_child(_difficulty_choice)
	_progress_choice = _choice(["All puzzles", "Unsolved", "Solved puzzles", "Needs practice", "Hintless"], 140)
	_progress_choice.name = "ProgressFilter"
	_progress_choice.tooltip_text = ELRemakeText.t("Filter by completion", profile)
	_progress_choice.select(_progress_filter)
	_progress_choice.item_selected.connect(func(at: int):
		_progress_filter = at
		_fill_list())
	filters.add_child(_progress_choice)
	_continue = _button("Continue", 110, 32)
	_continue.name = "ContinuePuzzle"
	_continue.pressed.connect(func():
		if _continue_index >= 0: _choose_puzzle(_continue_index))
	filters.add_child(_continue)
	_list_scroll = ScrollContainer.new()
	# Fits the game's 800 x 600 minimum window, including both game tabs.
	_list_scroll.custom_minimum_size = Vector2(600, 240)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_catalog.add_child(_list_scroll)
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 14)
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_groups)
	_build_random_panel(column)
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
	_select_puzzle_tab(_random_selected)

## A separate pane keeps the original collection and its filters intact at
## the minimum window size. A seed code includes edition and difficulty.
func _build_random_panel(parent: VBoxContainer) -> void:
	_random_panel = VBoxContainer.new()
	_random_panel.name = "RandomPuzzleSetup"
	_random_panel.custom_minimum_size = Vector2(600, 360)
	_random_panel.add_theme_constant_override("separation", 12)
	parent.add_child(_random_panel)
	var description := _text(15, ELMenuKit.BODY_INK)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 590
	description.text = "Choose a short tactical combination or a two-turn plan. Each position is checked before play."
	_random_panel.add_child(description)
	var difficulty_row := HBoxContainer.new()
	difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	difficulty_row.add_theme_constant_override("separation", 12)
	_random_panel.add_child(difficulty_row)
	var difficulty_label := _text(15, ELMenuKit.BODY_INK)
	difficulty_label.text = "Difficulty"
	difficulty_row.add_child(difficulty_label)
	_random_level = _choice(RANDOM_LEVEL_NAMES.values(), 240)
	_random_level.name = "RandomPuzzleDifficulty"
	for index in _random_level.item_count: _random_level.set_item_id(index, index + 2)
	_random_level.select(_random_difficulty - 2)
	_random_level.item_selected.connect(func(index: int):
		_random_difficulty = _random_level.get_item_id(index)
		_refresh_random_guidance())
	difficulty_row.add_child(_random_level)
	_random_guidance = _text(14, ELMenuKit.NOTE_INK)
	_random_guidance.name = "RandomPuzzleGuidance"
	_random_guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_random_guidance.custom_minimum_size = Vector2(590, 38)
	_random_panel.add_child(_random_guidance)
	_refresh_random_guidance()
	_random_seed = LineEdit.new()
	_random_seed.name = "RandomPuzzleSeed"
	_random_seed.custom_minimum_size = Vector2(590, 34)
	_random_seed.max_length = 80
	_random_seed.add_theme_font_size_override("font_size", 14)
	_random_seed.placeholder_text = ELRemakeText.t("Seed or challenge code (optional)", profile)
	_random_seed.tooltip_text = ELRemakeText.t("Leave blank to vary the challenges in this session. Paste a code to replay its exact edition, difficulty and position.", profile)
	_random_seed.clear_button_enabled = true
	if _kit == null:
		_random_seed.add_theme_stylebox_override("normal", _panel("box", Vector4(10, 5, 10, 5)))
		_random_seed.add_theme_color_override("font_color", ELMenuKit.BODY_INK)
	_random_seed.text = _random_input
	_random_seed.text_changed.connect(func(value: String): _random_input = value)
	_random_seed.text_submitted.connect(func(_value: String): _start_random())
	_random_panel.add_child(_random_seed)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	_random_panel.add_child(actions)
	_random_generate = _button("Generate & play", 190, 36)
	_random_generate.name = "GenerateRandomPuzzle"
	_random_generate.pressed.connect(_start_random)
	actions.add_child(_random_generate)
	_random_cancel = _button("Cancel", 120, 36)
	_random_cancel.name = "CancelRandomPuzzle"
	_random_cancel.pressed.connect(_cancel_generation)
	_random_cancel.hide()
	actions.add_child(_random_cancel)
	_random_status = _text(14, ELMenuKit.BODY_INK)
	_random_status.name = "RandomPuzzleStatus"
	_random_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_random_status.custom_minimum_size = Vector2(590, 76)
	_random_status.text = "A blank seed varies your session. A challenge code replays the same position."
	_random_panel.add_child(_random_status)
	var sharing := HBoxContainer.new()
	sharing.add_theme_constant_override("separation", 8)
	_random_panel.add_child(sharing)
	_random_code = LineEdit.new()
	_random_code.name = "RandomPuzzleCode"
	_random_code.editable = false
	_random_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_random_code.custom_minimum_size.y = 32
	_random_code.add_theme_font_size_override("font_size", 14)
	_random_code.placeholder_text = ELRemakeText.t("Your last challenge code appears here", profile)
	_random_code.text = _last_random_code
	sharing.add_child(_random_code)
	_random_copy = _button("Copy code", 130, 32)
	_random_copy.name = "CopyRandomPuzzleCode"
	_random_copy.disabled = _last_random_code.is_empty()
	_random_copy.pressed.connect(func(): _copy_challenge_code(_last_random_code))
	sharing.add_child(_random_copy)

func _refresh_random_guidance() -> void:
	if not is_instance_valid(_random_guidance): return
	_random_guidance.text = ELRemakeText.t(String(RANDOM_LEVEL_GUIDANCE.get(_random_difficulty, "")), profile)
	_random_level.tooltip_text = _random_guidance.text

func _select_puzzle_tab(random_tab: bool) -> void:
	_random_selected = random_tab
	if not random_tab: _cancel_generation()
	if _catalog == null or _random_panel == null: return
	_catalog.visible = not random_tab
	_random_panel.visible = random_tab
	_catalog_tab.set_pressed_no_signal(not random_tab)
	_random_tab.set_pressed_no_signal(random_tab)
	_list.reset_size()
	_centred(_list)

func _set_random_busy(busy: bool) -> void:
	if not is_instance_valid(_random_generate): return
	_random_generate.disabled = busy
	_random_cancel.visible = busy
	_random_level.disabled = busy
	_random_seed.editable = not busy

func _cancel_generation() -> void:
	var was_running := _generator_job != null
	_generator_job = null
	_generator_profile = null
	_set_random_busy(false)
	if was_running and is_instance_valid(_random_status):
		_random_status.text = ELRemakeText.t("Generation cancelled. Your current challenge is unchanged.", profile)

func _random_error(message: String) -> void:
	_random_status.text = ELRemakeText.t(message, profile)
	_random_status.add_theme_color_override("font_color", FAILED_INK)
	_set_random_busy(false)

## Empty input uses session variety; explicit input is reproduced exactly.
func _start_random() -> void:
	if _generator_job != null or profile == null: return
	var source := profile
	var difficulty := _random_difficulty
	var text := _random_seed.text.strip_edges()
	var seed_value := 0
	if not text.is_empty():
		if text.is_valid_int():
			if text.length() > 10 or int(text) < 1 or int(text) > 2147483647:
				_random_error("Use a seed from 1 to 2147483647 or paste a challenge code.")
				return
			seed_value = int(text)
		else:
			var parsed := ELPuzzleGenerator.parse_code(text)
			if not bool(parsed.get("ok", false)):
				_random_error(String(parsed.get("error", "That challenge code is not valid.")))
				return
			var edition := String(parsed.get("edition", ""))
			if not games.has(edition):
				_random_error("This challenge code needs a game that is not installed.")
				return
			source = games[edition]
			difficulty = int(parsed.difficulty)
			seed_value = int(parsed.seed)
			# Opening the other edition rebuilds its theme and preserves this
			# exact recipe. No generation work has started yet.
			_random_difficulty = difficulty
			if source.id != profile.id: open_list(source)
			_random_level.select(difficulty - 2)
			_refresh_random_guidance()
			_select_puzzle_tab(true)
	_random_difficulty = difficulty
	_generator_profile = source
	_generator_seed = seed_value
	if seed_value == 0:
		_generator_job = _random_session.call("start", source, difficulty)
	else:
		_generator_job = ELPuzzleGenerator.start(source, seed_value, difficulty)
	if _generator_job == null:
		_random_error("Could not start puzzle generation.")
		return
	_random_status.add_theme_color_override("font_color", ELMenuKit.BODY_INK)
	_random_status.text = ELRemakeText.t("Checking a fresh challenge…", profile)
	_set_random_busy(true)

## Each frame has a small simulation budget, keeping Cancel, tabs and Back
## responsive. Switching edition or leaving discards the pending job.
func _process(_delta: float) -> void:
	_step_advice()
	if _generator_job == null: return
	if not _list.visible or not _random_selected or profile != _generator_profile:
		_cancel_generation()
		return
	# Time bounds the slice, not node count: generation is deterministic in
	# its own limits however it is sliced, and Master needs most of a frame.
	_generator_job.call("step", GENERATOR_NODE_QUOTA, GENERATOR_SLICE_USEC)
	_random_status.text = ELRemakeText.t(String(_generator_job.get("progress_text")), profile)
	if not bool(_generator_job.get("done")): return
	var result: Dictionary = _generator_job.get("result")
	_generator_job = null
	_generator_profile = null
	_set_random_busy(false)
	var entry: Dictionary = result.get("entry", {})
	if entry.is_empty():
		_random_error(String(result.get("error", "No suitable challenge was found. Try another seed.")))
		return
	_generator_seed = int(entry.get("generated", {}).get("seed", 0))
	_random_session.call("note", entry)
	_last_random_code = String(result.get("code", entry.get("generated", {}).get("code", "")))
	_random_code.text = _last_random_code
	_random_copy.disabled = _last_random_code.is_empty()
	_random_status.text = ELRemakeText.t("Challenge ready.", profile)
	_list.hide()
	_shade.hide()
	generated_requested.emit(entry)

func _generated_run() -> bool:
	return run != null and run.entry.get("generated") is Dictionary

func _restart_puzzle() -> void:
	if run == null: return
	_cancel_advice()
	if _generated_run(): generated_requested.emit(run.entry.duplicate(true))
	else: play_requested.emit(run.index)

func _next_random() -> void:
	if not _generated_run(): return
	_random_difficulty = int(run.entry.generated.get("difficulty", run.entry.get("level", 3)))
	_random_input = ""
	open_list(run.duel.profile)
	_random_seed.text = ""
	_random_level.select(_random_difficulty - 2)
	_refresh_random_guidance()
	_select_puzzle_tab(true)
	_start_random()

func _challenge_code() -> String:
	return String(run.entry.generated.get("code", "")) if _generated_run() else ""

func _copy_challenge_code(value: String) -> void:
	if not value.is_empty(): DisplayServer.clipboard_set(value)

## Authored text is localised in the pack; legacy entries need no metadata.
func _entry_text(entry: Dictionary, key: String, fallback := "") -> String:
	if ELRemakeText.language(profile) == "ru":
		var translated := String(entry.get(key + "_ru", ""))
		if not translated.is_empty(): return translated
	return String(entry.get(key, fallback))

## Opens the list of `source`'s puzzles.
func open_list(source: ELProfile) -> void:
	_cancel_advice()
	_use(source)
	_fill_switch()
	_fill_list()
	_shade.show()
	_list.show()
	_result.hide()

func _choose_puzzle(index: int) -> void:
	_cancel_generation()
	_list.hide()
	_shade.hide()
	play_requested.emit(index)

func _goal_name(entry: Dictionary) -> String:
	var goal := String(entry.get("objective", {}).get("type", "win"))
	return ELRemakeText.t(String(GOAL_NAMES.get(goal, "Win")), profile)

## A matchup describes the starting heroes, without borrowing puzzle difficulty.
## Card rows put the level first so a long name cannot hide an asymmetric match.
func _matchup_lines(entry: Dictionary, compact := false) -> PackedStringArray:
	var lines := PackedStringArray()
	var heroes := ELPuzzles.combatants(entry, profile)
	for side in mini(heroes.size(), 2):
		var who := ELRemakeText.t("You" if side == 0 else "Opponent", profile)
		var hero: Dictionary = heroes[side]
		if compact:
			lines.append(ELRemakeText.t("%s · Lv. %d · %s", profile) % [who, int(hero.level), String(hero.name)])
		else:
			lines.append(ELRemakeText.t("%s: %s · Hero level %d", profile) % [who, String(hero.name), int(hero.level)])
	return lines

## Search only descriptions visible before play, in either supported language.
func _matches_search(entry: Dictionary) -> bool:
	var words := _search_query.strip_edges().to_lower().split(" ", false)
	if words.is_empty(): return true
	var fields := PackedStringArray()
	for key: String in ["title", "category", "briefing", "title_ru", "category_ru", "briefing_ru"]:
		fields.append(String(entry.get(key, "")))
	for language: String in ["en", "ru"]:
		for hero: Dictionary in ELPuzzles.combatants(entry, profile, language):
			fields.append(String(hero.name))
			fields.append(("Hero level %d · Lv. %d" if language == "en" else "Уровень героя %d · ур. %d") % [int(hero.level), int(hero.level)])
	var searchable := "\n".join(fields).to_lower()
	for word: String in words:
		if not searchable.contains(word): return false
	return true

func _matches_filter(entry: Dictionary, solved: bool, mastered: bool) -> bool:
	if _goal_filter > 0 and entry.get("objective", {}).get("type", "win") != GOALS[_goal_filter]: return false
	if _difficulty_filter > 0 and clampi(int(entry.get("level", 2)), 1, LEVELS.size()) != _difficulty_filter: return false
	if not _matches_search(entry): return false
	match _progress_filter:
		1: return not solved
		2: return solved
		3: return solved and not mastered
		4: return mastered
	return true

## Filtering keeps each puzzle's original index, difficulty group and progress.
func _fill_list() -> void:
	var entries := ELPuzzles.list(profile.id)
	for child: Node in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	_list_scroll.scroll_vertical = 0
	_continue_index = -1
	var shown := 0
	var hintless := 0
	var grids := {}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var taken := ELPuzzles.solved_in(profile.id, String(entry.id))
		var mastered := ELPuzzles.mastered(profile.id, String(entry.id))
		if mastered: hintless += 1
		if not _matches_filter(entry, taken > 0, mastered): continue
		shown += 1
		if (taken == 0 or _progress_filter == 3) and _continue_index < 0: _continue_index = i
		var level := clampi(int(entry.get("level", 2)), 1, LEVELS.size())
		if not grids.has(level):
			var grid := GridContainer.new()
			grid.columns = 2
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			_group(_groups, LEVELS[level - 1]).add_child(grid)
			grids[level] = grid
		var title := _entry_text(entry, "title", "Puzzle %d" % [i + 1])
		var category := _entry_text(entry, "category")
		# The card shows only the name and the topic; the goal and the
		# briefing are in its tooltip.
		var caption := "%d. %s" % [i + 1, title] if entry.has("title") else title
		if mastered: caption = "★ " + caption
		var box: Texture2D = _over.theme.get_icon("checked" if taken > 0 else "unchecked", "CheckBox") if _over.theme != null and _over.theme.has_icon("checked", "CheckBox") else null
		if taken > 0 and box == null: caption += " · " + ELRemakeText.t("Solved", profile)
		var card_text := caption
		if not category.is_empty(): card_text += "
" + category
		var button := _button(card_text, 282, 62)
		button.name = "Puzzle_%d" % (i + 1)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 14)
		button.tooltip_text = title
		if not category.is_empty(): button.tooltip_text += "
" + category
		button.tooltip_text += "
" + _goal_name(entry)
		var briefing := _entry_text(entry, "briefing")
		if not briefing.is_empty(): button.tooltip_text += "\n" + briefing
		# A solved puzzle is ticked, in the Options check box.
		if box != null:
			button.icon = box
			button.add_theme_constant_override("h_separation", 8)
		if taken > 0:
			button.tooltip_text += "\n" + ELRemakeText.t("Solved in turn %d", profile) % taken
			for state: String in ["font_color", "font_focus_color"]: button.add_theme_color_override(state, SOLVED_INK)
		if mastered: button.tooltip_text += "\n★ " + ELRemakeText.t(HINTLESS_DESCRIPTION, profile)
		button.pressed.connect(func(): _choose_puzzle(i))
		(grids[level] as GridContainer).add_child(button)
	if shown == 0:
		var empty := _text(15, ELMenuKit.BODY_INK)
		empty.name = "EmptyPuzzleList"
		empty.text = "No puzzles match these filters."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_groups.add_child(empty)
	_list_note.text = (ELRemakeText.t("Solved: %d of %d · Without hints: %d", profile) % [ELPuzzles.solved_count(profile.id), entries.size(), hintless]) + "\n" + (ELRemakeText.t("Shown: %d of %d", profile) % [shown, entries.size()])
	_list_note.tooltip_text = "★ " + ELRemakeText.t(HINTLESS_DESCRIPTION, profile)
	_continue.disabled = _continue_index < 0
	if _progress_filter == 3:
		_continue.tooltip_text = ELRemakeText.t("Practise the first matching puzzle without a hintless completion." if _continue_index >= 0 else "No puzzles needing practice match these filters.", profile)
	elif _progress_filter in [2, 4]:
		_continue.tooltip_text = ELRemakeText.t("Choose a completed puzzle to replay.", profile)
	else:
		_continue.tooltip_text = ELRemakeText.t("Start the first unsolved puzzle matching these filters." if _continue_index >= 0 else "No unsolved puzzles match these filters.", profile)

## The switch between the games whose puzzles can be played; hidden with
## only one. The shown game's button stays pressed.
func _fill_switch() -> void:
	for child: Node in _switch.get_children():
		_switch.remove_child(child)
		child.queue_free()
	var shown := 0
	for id: String in GAME_NAMES:
		if not games.has(id) or ELPuzzles.list(id).is_empty(): continue
		shown += 1
		var button := _button(GAME_NAMES[id], 180, 34)
		button.name = "Game_" + id
		button.toggle_mode = true
		button.button_pressed = id == profile.id
		# The game shown reads as chosen: gold, the other dimmed.
		if id == profile.id:
			for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: button.add_theme_color_override(state, ELMenuKit.TITLE_INK)
		else:
			button.self_modulate = Color(0.6, 0.6, 0.6)
			button.add_theme_color_override("font_color", Color(ELMenuKit.BODY_INK, 0.7))
		button.pressed.connect(func():
			if id == profile.id:
				button.set_pressed_no_signal(true)
				return
			open_list(games[id]))
		_switch.add_child(button)
	_switch.visible = shown > 1

func _close_list() -> void:
	_cancel_generation()
	_list.hide()
	_shade.hide()
	# Browsing the other edition rebuilt these controls. Back still returns
	# to the running puzzle, with its own language, rules and visible strip.
	if run != null and profile != null and profile.id != run.edition:
		begin(run.duel.profile, run)
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
	_bar_text = _text(16, ELMenuKit.TITLE_INK)
	_bar_text.custom_minimum_size.x = 660
	_bar_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_bar_text)
	_objective_text = _text(14, ELMenuKit.BODY_INK)
	_objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_objective_text)
	_rules_text = _text(12, ELMenuKit.BODY_INK)
	_rules_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_text.hide()
	column.add_child(_rules_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_briefing_button = _button("Briefing", 86, 28)
	_briefing_button.toggle_mode = true
	_briefing_button.pressed.connect(func():
		_briefing_text.visible = _briefing_button.button_pressed
		_refresh_supply())
	row.add_child(_briefing_button)
	var again := _button("Restart", 88, 28)
	again.name = "RestartPuzzle"
	again.pressed.connect(_restart_puzzle)
	row.add_child(again)
	var others := _button("Puzzles", 88, 28)
	others.pressed.connect(func():
		if profile != null: open_list(profile))
	row.add_child(others)
	_generated_copy = _button("Copy code", 96, 28)
	_generated_copy.name = "CopyActivePuzzleCode"
	_generated_copy.pressed.connect(func(): _copy_challenge_code(_challenge_code()))
	_generated_copy.hide()
	row.add_child(_generated_copy)
	var leave := _button("Leave", 78, 28)
	leave.pressed.connect(leave_puzzles)
	row.add_child(leave)
	# Keep guidance controls on their own compact row at the minimum window
	# size. The current-position analysis is always a deliberate extra click.
	var guidance := HBoxContainer.new()
	guidance.add_theme_constant_override("separation", 6)
	guidance.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(guidance)
	_hint_button = _button("Hint", 150, 28)
	_hint_button.pressed.connect(show_hint)
	guidance.add_child(_hint_button)
	_hide_hint = _button("Hide hint", 90, 28)
	_hide_hint.pressed.connect(func():
		_hint_text.hide()
		_update_hint_buttons())
	_hide_hint.hide()
	guidance.add_child(_hide_hint)
	_advice_button = _button("Tactical hint", 180, 28)
	_advice_button.name = "TacticalPuzzleHint"
	_advice_button.pressed.connect(show_tactical_hint)
	_advice_button.hide()
	guidance.add_child(_advice_button)
	_briefing_text = _text(14, ELMenuKit.BODY_INK)
	_briefing_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefing_text.hide()
	column.add_child(_briefing_text)
	_supply_scroll = ScrollContainer.new()
	_supply_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_supply_scroll.hide()
	column.add_child(_supply_scroll)
	_supply_text = _text(14, ELMenuKit.BODY_INK)
	_supply_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_supply_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_supply_scroll.add_child(_supply_text)
	_hint_text = _text(14, ELMenuKit.BODY_INK)
	_hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_text.hide()
	column.add_child(_hint_text)
	_advice_scroll = ScrollContainer.new()
	_advice_scroll.name = "TacticalHintAnalysis"
	_advice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_advice_scroll.custom_minimum_size.y = 90
	_advice_scroll.hide()
	column.add_child(_advice_scroll)
	_advice_text = _text(14, ELMenuKit.BODY_INK)
	_advice_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advice_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_advice_scroll.add_child(_advice_text)

## Reveal one hint per deliberate click, from a nudge to the concrete idea.
## Reopening a hidden hint keeps its level; legacy command hints still work.
func show_hint() -> void:
	if run == null or run.hint_count() <= 0: return
	if _advice_job != null: _cancel_advice()
	else:
		_advice_scroll.hide()
		_update_advice_button()
	var previous := _hint_index
	if _hint_index < 0: _hint_index = 0
	elif _hint_text.visible: _hint_index = mini(_hint_index + 1, run.hint_count() - 1)
	if _hint_index != previous: run.note_hint(_hint_index)
	_hint_text.text = "%s\n%s" % [ELRemakeText.t("Hint %d of %d", profile) % [_hint_index + 1, run.hint_count()], run.hint(_hint_index)]
	_hint_text.show()
	_update_hint_buttons()

func _update_hint_buttons() -> void:
	var count := run.hint_count() if run != null else 0
	_hide_hint.visible = _hint_text.visible
	_hint_button.text = ("Next puzzle hint" if _hint_text.visible else "Puzzle hint") if _generated_run() else ("Next hint" if _hint_text.visible else "Hint")
	_hint_button.disabled = count <= 0 or (_hint_text.visible and _hint_index + 1 >= count)
	_hint_button.tooltip_text = "Reveal one more hint" if _hint_text.visible else ("Hints for the starting position. Tactical hint checks your current position." if _generated_run() else "Hints start with a nudge. Each further hint reveals more.")

## Analyze the position the player can act on now. Neither requesting advice
## nor revealing its result applies any combat command.
func show_tactical_hint() -> void:
	if _advice_job != null:
		_cancel_advice()
		return
	if not _advice_allowed(): return
	var state_key := ELPuzzleAdvice.fingerprint(run)
	if not _advice_result.is_empty() and _advice_state_key == state_key:
		_advice_scroll.visible = not _advice_scroll.visible
		if _advice_scroll.visible: _hint_text.hide()
		_update_hint_buttons()
		_update_advice_button()
		return
	_cancel_advice()
	_advice_state_key = state_key
	_advice_job = ELPuzzleAdvice.start(run)
	_hint_text.hide()
	_advice_text.text = ELRemakeText.t("Analyzing the current position…", profile)
	_advice_scroll.show()
	_update_hint_buttons()
	_update_advice_button()

func _advice_allowed() -> bool:
	return _generated_run() and run.duel != null and run.outcome.is_empty() and run.duel.active_side() == 0 and run.duel.phase != ELDuel.Phase.FINISHED and not (_list != null and _list.visible) and not (_result != null and _result.visible)

func _update_advice_button() -> void:
	if _advice_button == null: return
	_advice_button.visible = _generated_run()
	_advice_button.disabled = not _advice_allowed()
	_advice_button.text = "Tactical hint"
	if _advice_job != null: _advice_button.text = "Cancel analysis"
	elif not _advice_result.is_empty(): _advice_button.text = "Hide analysis" if _advice_scroll.visible else "Show analysis"
	_advice_button.tooltip_text = "Analyze this position and its remaining turns. Useful guidance counts as a hint; no move is played."
	if not _advice_allowed(): _advice_button.tooltip_text = "Tactical hints are available while it is your action."

func _step_advice() -> void:
	if _advice_job == null: return
	if not _advice_allowed() or not bool(_advice_job.call("is_current", run)):
		_cancel_advice()
		return
	_advice_job.call("step", 32, 6000)
	# A state check after the slice protects even a result completed in the
	# same frame as a restart or action; stale answers never count as hints.
	if not _advice_allowed() or not bool(_advice_job.call("is_current", run)):
		_cancel_advice()
		return
	_advice_text.text = String(_advice_job.get("progress_text"))
	if not bool(_advice_job.get("done")): return
	var answer: Dictionary = _advice_job.get("result")
	_advice_job = null
	var status := String(answer.get("status", "error"))
	if status == "cancelled":
		_cancel_advice()
		return
	_advice_result = answer.duplicate(true)
	var guidance := String(answer.get("text", ""))
	if guidance.is_empty(): guidance = ELRemakeText.t("Analysis ended without a conclusion.", profile)
	elif status in ["proven", "refuted"]: run.note_tactical_hint()
	_advice_text.text = guidance
	_advice_scroll.show()
	_update_advice_button()

func _cancel_advice() -> void:
	if _advice_job != null:
		_advice_job.call("cancel")
		_advice_job = null
	_advice_result.clear()
	_advice_state_key = ""
	if _advice_scroll != null: _advice_scroll.hide()
	_update_advice_button()

func _advice_state_changed() -> void:
	_cancel_advice()

func _disconnect_advice() -> void:
	if run != null and run.duel != null and run.duel.changed.is_connected(_advice_state_changed):
		run.duel.changed.disconnect(_advice_state_changed)

## The host has started `attempt`'s duel: the strip shows over it.
func begin(source: ELProfile, attempt: ELPuzzles.Run) -> void:
	_cancel_generation()
	_cancel_advice()
	_disconnect_advice()
	_use(source)
	_disconnect_supply()
	run = attempt
	_generated_copy.visible = _generated_run()
	_generated_copy.tooltip_text = _challenge_code()
	if _generated_run():
		_last_random_code = _challenge_code()
		_random_code.text = _last_random_code
		_random_copy.disabled = _last_random_code.is_empty()
	if bool(run.entry.get("show_supply", false)):
		run.duel.changed.connect(_refresh_supply)
	if _generated_run(): run.duel.changed.connect(_advice_state_changed)
	_result_clock = 0.0
	_result_shown = false
	_shown_turn = -1
	_hint_index = clampi(run.hints_used - run.tactical_hints_used - 1, -1, run.hint_count() - 1)
	_hint_text.hide()
	_update_hint_buttons()
	_briefing_text.text = run.briefing()
	_briefing_text.hide()
	_briefing_button.set_pressed_no_signal(false)
	_briefing_button.visible = not _briefing_text.text.is_empty() or bool(run.entry.get("show_supply", false))
	_refresh_supply()
	_list.hide()
	_shade.hide()
	_result.hide()
	_bar.show()
	_refresh_bar()
	_update_advice_button()

func _refresh_supply() -> void:
	var text := run.supply_text() if run != null and _briefing_button.button_pressed else ""
	_supply_scroll.visible = not text.is_empty()
	if _supply_scroll.visible:
		_supply_scroll.custom_minimum_size.y = minf(180.0, get_viewport().get_visible_rect().size.y * 0.30)
		_supply_text.text = text

func _disconnect_supply() -> void:
	if run != null and run.duel.changed.is_connected(_refresh_supply):
		run.duel.changed.disconnect(_refresh_supply)

func _refresh_bar() -> void:
	if run == null: return
	_shown_turn = run.turn
	_bar_text.text = "%s  ·  %s" % [run.title(), ELRemakeText.t("Turn %d of %d", profile) % [clampi(run.turn, 1, run.allowed), run.allowed]]
	if _generated_run():
		var tier := int(run.entry.generated.get("difficulty", run.entry.get("level", 3)))
		_bar_text.text = "%s  ·  %s  ·  %s" % [run.title(), ELRemakeText.t(String(RANDOM_LEVEL_NAMES.get(tier, "Hard")), profile),
			ELRemakeText.t("Turn %d of %d", profile) % [clampi(run.turn, 1, run.allowed), run.allowed]]
	if ELPuzzles.mastered(run.edition, String(run.entry.id)): _bar_text.text += "  ·  ★"
	elif ELPuzzles.solved_in(run.edition, String(run.entry.id)) > 0: _bar_text.text += "  ·  " + ELRemakeText.t("Solved", profile)
	_bar_text.tooltip_text = run.title() + ("\n" + run.category() if not run.category().is_empty() else "")
	if ELPuzzles.mastered(run.edition, String(run.entry.id)): _bar_text.tooltip_text += "\n★ " + ELRemakeText.t(HINTLESS_DESCRIPTION, profile)
	_objective_text.text = run.objective_text()
	var rules := PackedStringArray()
	var details := PackedStringArray()
	if run.duel != null and bool(run.duel.setup.get("puzzle_fixed_hands", false)):
		rules.append(ELRemakeText.t("Fixed hands", profile))
		details.append(ELRemakeText.t("Neither hero draws from a deck.", profile))
	if run.duel != null and bool(run.duel.setup.get("puzzle_fixed_channels", false)):
		rules.append(ELRemakeText.t("Fixed channels", profile))
		details.append(ELRemakeText.t("Existing channels refill normally; natural channel growth is disabled.", profile))
	if _generated_run():
		rules.append(_challenge_code())
		details.append(ELRemakeText.t("Paste this code in Random challenge to replay the same puzzle.", profile))
	_rules_text.text = " · ".join(rules)
	_rules_text.visible = not rules.is_empty()
	if not details.is_empty(): details.append(ELRemakeText.t("Card effects and abilities still work.", profile))
	_rules_text.tooltip_text = "\n".join(details)

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
	_result_text.custom_minimum_size.x = 540
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_result_text)
	_result_explanation = _text(14, ELMenuKit.BODY_INK)
	_result_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_explanation.hide()
	column.add_child(_result_explanation)
	_result_code_row = HBoxContainer.new()
	_result_code_row.name = "GeneratedPuzzleResultCode"
	_result_code_row.add_theme_constant_override("separation", 8)
	_result_code_row.hide()
	column.add_child(_result_code_row)
	_result_code = LineEdit.new()
	_result_code.name = "CompletedPuzzleCode"
	_result_code.editable = false
	_result_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_code.add_theme_font_size_override("font_size", 14)
	_result_code_row.add_child(_result_code)
	var copy_code := _button("Copy code", 130, 32)
	copy_code.pressed.connect(func(): _copy_challenge_code(_challenge_code()))
	_result_code_row.add_child(copy_code)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_next = _button("Next challenge", 140)
	_next.pressed.connect(func():
		if _generated_run(): _next_random()
		elif run != null and _next_index >= 0: play_requested.emit(_next_index))
	row.add_child(_next)
	_again = _button("Try again", 130)
	_again.pressed.connect(_restart_puzzle)
	row.add_child(_again)
	var others := _button("Puzzles", 120)
	others.pressed.connect(func():
		if profile != null: open_list(profile))
	row.add_child(others)
	# The modal shade covers the strip's Leave button. Results need their
	# own exit, including a failed attempt and the last puzzle in a set.
	var leave := _button("Leave", 90)
	leave.name = "PuzzleLeave"
	leave.pressed.connect(leave_puzzles)
	row.add_child(leave)

## The attempt's result (also on the end-of-phase control once it is over).
func show_result() -> void:
	if run != null and not run.outcome.is_empty() and not _list.visible: _show_result()

## The completed entry may have disappeared from Unsolved or Needs practice.
## Scan original indices, exclude Retry's current entry, and wrap only once.
func _refresh_next() -> void:
	_next_index = -1
	_next.visible = run != null and (run.outcome == "solved" or _generated_run())
	_next.disabled = true
	_next.text = ELRemakeText.t("Next challenge", profile)
	_next.tooltip_text = ELRemakeText.t("No other puzzles match these filters.", profile)
	if not _next.visible: return
	if _generated_run():
		_next.text = ELRemakeText.t("New challenge", profile)
		_next.tooltip_text = ELRemakeText.t("Generate another challenge at the same difficulty.", profile)
		_next.disabled = false
		return
	var entries := ELPuzzles.list(run.edition)
	for step in range(1, entries.size()):
		var index := (run.index + step) % entries.size()
		var entry: Dictionary = entries[index]
		var solved := ELPuzzles.solved_in(run.edition, String(entry.id)) > 0
		var mastered := ELPuzzles.mastered(run.edition, String(entry.id))
		if not _matches_filter(entry, solved, mastered): continue
		_next_index = index
		var wrapped := index < run.index
		_next.text = ELRemakeText.t("First matching" if wrapped else "Next challenge", profile)
		_next.tooltip_text = ELRemakeText.t("Wrap to: %s" if wrapped else "Next: %s", profile) % _entry_text(entry, "title", ELRemakeText.t("Puzzle %d", profile) % (index + 1))
		_next.disabled = false
		return

func _show_result() -> void:
	if run == null: return
	_cancel_advice()
	_result_shown = true
	var solved := run.outcome == "solved"
	_result_title.text = "Puzzle solved" if solved else "Not solved"
	_result_title.add_theme_color_override("font_color", SOLVED_INK if solved else FAILED_INK)
	_result_explanation.hide()
	_result_text.tooltip_text = ""
	_result_code_row.visible = _generated_run()
	_result_code.text = _challenge_code()
	if solved:
		var count := ELPuzzles.list(profile.id).size()
		_result_text.text = "Completed in turn %d of %d." % [clampi(run.turn, 1, run.allowed), run.allowed]
		if not _generated_run(): _result_text.text += "\nSolved: %d of %d" % [ELPuzzles.solved_count(profile.id), count]
		if run.hints_used == 0:
			_result_text.text += "\n★ " + ELRemakeText.t("Solved without hints", profile)
			_result_text.tooltip_text = ELRemakeText.t(HINTLESS_DESCRIPTION, profile)
		else: _result_text.text += "\n" + ELRemakeText.t("Hints revealed: %d", profile) % run.hints_used
		_result_explanation.text = run.explanation()
		_result_explanation.visible = not _result_explanation.text.is_empty()
	else:
		_result_text.text = run.failure_text()
	_refresh_next()
	_again.text = "Play again" if solved else "Try again"
	_shade.show()
	_result.show()

# --- Leaving --------------------------------------------------------------------

## Ends the attempt without a word (another battle starts, the game leaves).
func close() -> void:
	_cancel_generation()
	_cancel_advice()
	_disconnect_advice()
	_disconnect_supply()
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
