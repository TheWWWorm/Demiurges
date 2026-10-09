class_name ELSingleScreen
extends RefCounted
## Single mission choice (CSelectMission) on the ELFrontMenu canvas: the
## non-campaign map list with the original size filter (MapSize1..5) and
## column sorts, the chosen map's name and description, the difficulty radios,
## and Back / Start. Layout comes from the Controls and CutParts registries in
## the 1024 design; the list rows are drawn by the remake.
## First game (screen "single"): sorts Sort1/2/31..34/4/5 and Mission, five
## difficulties, the first row chosen on every rebuild, original rows (size
## icon, "players/players", race marks, win and lose marks, name; white text,
## the chosen row bold gold, no bar), the description box holding the
## description and the objective / win / lose captions with their texts, and
## the player-slot panel (ELSingleSlots).
## Second game (screen "select_mission", from Single game -> Mission -> New):
## only the size (Sort1) and name (Mission) sorts, which never clear; three
## difficulties; name and description only; no row is chosen when the screen
## opens, so Start stays disabled until one is clicked (rows: size icon, name).

## First game: rows of the original list, 26 px apart from (57,125) of the
## 800 layout, 317 px wide.
const ROW := 26.0
const FIRST_LIST := Rect2(169, 209, 317, 0)
## Row pieces: MISSION_PANEL_9 size icons per size class; MISSION_PANEL_7 race
## marks (2x2 at x 69/85, y 1/13: Green, Blue / Black, Red) and the win and
## lose marks, which are the same for every map.
const SIZE_ICONS := [Rect2(225, 69, 31, 23), Rect2(225, 92, 31, 23), Rect2(225, 115, 31, 23), Rect2(225, 46, 31, 23)]
const RACE_MARKS := {2: [Vector2(69, 1), Rect2(225, 0, 15, 11)], 3: [Vector2(85, 1), Rect2(241, 0, 15, 11)], 4: [Vector2(69, 13), Rect2(225, 12, 15, 11)], 1: [Vector2(85, 13), Rect2(241, 12, 15, 11)]}
const WIN_MARK := [Vector2(252, 1), Rect2(225, 161, 31, 23)]
const LOSE_MARK := [Vector2(286, 1), Rect2(225, 184, 31, 23)]
const ROW_TEXT := 16
const ROW_INK := Color.WHITE
const ROW_CHOSEN_INK := Color("d6bb88")
## Second game: rows follow the 26 px grid of the SelectMission list art.
const SECOND_ROW := 26.0
## Captions and map texts that follow the description in its box.
const DETAIL_ROWS := [["MissObj1", "objective"], ["MissWin1", "win_condition"], ["MissLose1", "lose_condition"]]

var menu: ELFrontMenu
## Size filter (0..3, ALL_SIZES) and sort key are kept while the game runs, as
## in the original; the chosen map returns to the first row on every rebuild.
var size_filter := ELSingleScenario.ALL_SIZES
var sort_key := 0
var selected := ""
var list: MissionList
var slots: ELSingleSlots
## The human's slot while the blazon choice is open.
var kept_slot := 0

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func profile() -> ELProfile:
	return menu.profile

func second() -> bool:
	return menu.edition == "el2"

## The front-menu screen this choice is drawn on.
func screen_name() -> String:
	return "select_mission" if second() else "single"

func row_height() -> float:
	return SECOND_ROW if second() else ROW

## A new edition starts a new game: filter and sort return to their defaults.
func reset() -> void:
	size_filter = ELSingleScenario.ALL_SIZES
	sort_key = 0
	selected = ""

func rows() -> Array[Dictionary]:
	return ELSingleScenario.rows(profile(), size_filter, sort_key)

func chosen() -> Dictionary:
	for entry: Dictionary in rows():
		if entry.id == selected: return entry
	return {}

func _rect(control: String) -> Rect2:
	return menu.control_rect(control)

func _button(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var button := menu._square(control)
	if button != null: button.pressed.connect(action)
	return button

func build_screen() -> void:
	menu._label("caption", menu._caption("SMCaption"), _rect("SMCaption"), 17)
	menu._label("choose", menu._caption("SelectMissionTxt"), _rect("SelectMissionTxt"), 17)
	for index in 5:
		var size_radio := _button("MapSize%d" % (index + 1), set_size_filter.bind(index))
		if size_radio != null: size_radio.active = index == size_filter
		var difficulty_radio := _button("Diff%d" % (index + 1), set_difficulty.bind(index))
		if difficulty_radio != null: difficulty_radio.active = index == (mini(menu.difficulty, 2) if second() else menu.difficulty)
	for control: String in ELSingleScenario.SORT_CONTROLS:
		if control == "Mission": continue
		var sort := _button(control, set_sort.bind(ELSingleScenario.SORT_CONTROLS[control]))
		if sort != null: sort.active = sort_key == ELSingleScenario.SORT_CONTROLS[control]
	var by_name := ELDuelScreen.FlatText.new()
	by_name.menu = menu
	by_name.caption = menu._caption("Mission")
	by_name.font_size = 18
	var name_rect := _rect("Mission")
	by_name.position = name_rect.position
	by_name.size = name_rect.size
	by_name.active = sort_key == ELSingleScenario.SORT_NAME
	menu.canvas.add_child(by_name)
	menu.buttons["Mission"] = by_name
	by_name.pressed.connect(set_sort.bind(ELSingleScenario.SORT_NAME))
	var up := _button("SMScrollLU", func(): list.scroll(-3))
	var down := _button("SMScrollLD", func(): list.scroll(3))
	list = MissionList.new()
	list.screen = self
	var sort_size: Control = menu.buttons.get("Sort1")
	var left := sort_size.position.x if sort_size != null else name_rect.position.x - 100
	var top := name_rect.end.y + 6
	var right := up.position.x - 4 if up != null else name_rect.end.x + 60
	var bottom := down.position.y + down.size.y if down != null else top + 420
	list.position = Vector2(left, top)
	list.size = Vector2(right - left, bottom - top)
	# Second game: the list control's own bounds (SMLeftBounds).
	var bounds := _rect("SMLeftBounds")
	if second() and bounds.size.x > 0:
		list.position = bounds.position
		list.size = Vector2(bounds.size.x, floorf(bounds.size.y / SECOND_ROW) * SECOND_ROW)
	elif not second():
		list.position = FIRST_LIST.position
		list.size = Vector2(FIRST_LIST.size.x, floorf((bottom - FIRST_LIST.position.y) / ROW) * ROW)
	left = list.position.x
	for control: String in ["Sort1", "Sort2", "Sort31", "Sort32"]:
		var button: Control = menu.buttons.get(control)
		list.columns[control] = (button.position.x + button.size.x * 0.5 - left) if button != null else 0.0
	list.columns["Mission"] = name_rect.position.x - left + 4
	list.columns["Sort4"] = menu.buttons.Sort4.position.x - left if menu.buttons.has("Sort4") else list.size.x
	list.icons = _size_icons()
	menu.canvas.add_child(list)
	menu.labels["list"] = list
	menu._label("mission_name", "", _rect("MissName"), 18)
	menu._text_box(_rect("MissDesc"), "")
	slots = null
	if not second():
		slots = ELSingleSlots.new()
		slots.setup(menu)
		menu.canvas.add_child(slots)
		menu.labels["slots"] = slots
	_button("SMScrollRU", func(): menu.scroll_text(-3))
	_button("SMScrollRD", func(): menu.scroll_text(3))
	_button("SMBack", func(): menu.go_back())
	_button("SMStart", start)
	# Showing the screen rebuilds the list. The first game chooses its first row
	# the second game chooses none (selects -1). Back from the
	# blazon choice keeps the chosen map and the human's slot.
	var keep := menu.previous_screen == "blazon_single"
	if not keep: selected = ""
	if slots != null and keep: slots.human = kept_slot
	if slots != null and keep: slots.entry = chosen()
	refresh()
	if slots != null and keep: slots.show_entry(chosen(), true)

## MapSize1..4 normal-state pictures, used as the list's size icons.
func _size_icons() -> Array:
	var icons: Array = []
	for index in 4:
		var found := menu.rows("MapSize%d" % (index + 1), ["Free"], ["Light"])
		icons.append(menu.cut(found[0]) if not found.is_empty() else {})
	return icons

## First game: the objective / win / lose caption and map text pairs that
## follow the description in its box, [caption, text] each; empty texts are
## left out.
func detail_pairs(entry: Dictionary) -> Array:
	var pairs: Array = []
	for row: Array in DETAIL_ROWS:
		var key := str(entry.get(row[1], ""))
		var value := menu.text(key).strip_edges() if not key.is_empty() else ""
		if not value.is_empty(): pairs.append([menu._caption(row[0]).strip_edges(), value])
	return pairs

## The objective and condition texts shown for the chosen map.
func details_text() -> String:
	return "\n".join(detail_pairs(chosen()).map(func(pair: Array): return pair[1]))

## The description box: the description, then each caption (title ink, after
## a gap) over its text.
func _fill_description(entry: Dictionary) -> void:
	var box := menu.text_box
	box.clear()
	var description := menu.text(str(entry.description)).strip_edges() if not entry.is_empty() and not str(entry.get("description", "")).is_empty() else ""
	box.add_text(description)
	if second() or entry.is_empty(): return
	for pair: Array in detail_pairs(entry):
		box.push_font_size(15)
		box.add_text("\n")
		box.pop()
		box.push_color(ELFrontMenu.TITLE_INK)
		box.add_text("\n" + str(pair[0]))
		box.pop()
		box.add_text("\n" + str(pair[1]))

## Re-applies the filter and sort; with no current choice the first row is
## chosen (the original selects the first row after every rebuild).
func refresh() -> void:
	if menu.screen != screen_name(): return
	var shown := rows()
	if not shown.any(func(entry: Dictionary): return entry.id == selected):
		selected = shown[0].id if not shown.is_empty() and not second() else ""
	for index in 5:
		var size_radio: ELFrontMenu.CutButton = menu.buttons.get("MapSize%d" % (index + 1))
		if size_radio != null: size_radio.active = index == size_filter
	for control: String in ELSingleScenario.SORT_CONTROLS:
		var button: Variant = menu.buttons.get(control)
		if button != null: button.active = sort_key == ELSingleScenario.SORT_CONTROLS[control]
	var entry := chosen()
	menu.labels.mission_name.text = ELSingleScenario.title(profile(), entry) if not entry.is_empty() else ""
	if menu.text_box != null:
		_fill_description(entry)
		menu.text_box.get_v_scroll_bar().value = 0
	if slots != null and slots.entry.get("id", "") != entry.get("id", ""): slots.show_entry(entry)
	if menu.buttons.has("SMStart"): menu.buttons.SMStart.disabled = entry.is_empty()
	if list != null:
		list.reveal(shown.find(entry))
		list.queue_redraw()

func set_size_filter(index: int) -> void:
	size_filter = clampi(index, 0, ELSingleScenario.ALL_SIZES)
	if list != null: list.offset = 0
	selected = ""
	refresh()

## First game: clicking the active sort column again returns to the scan
## order. Second game: a sort button always sets its key.
func set_sort(key: int) -> void:
	sort_key = key if second() or sort_key != key else 0
	if list != null: list.offset = 0
	selected = ""
	refresh()

func set_difficulty(index: int) -> void:
	menu.set_difficulty(index)
	for i in 5:
		var radio: ELFrontMenu.CutButton = menu.buttons.get("Diff%d" % (i + 1))
		if radio != null: radio.active = i == index

func choose_row(index: int) -> void:
	var shown := rows()
	if index < 0 or index >= shown.size(): return
	selected = shown[index].id
	refresh()

func start() -> void:
	var entry := chosen()
	if entry.is_empty(): return
	if second():
		# The second game has three difficulties (Diff1..3).
		menu.campaign_requested.emit(menu.edition, ELSingleScenario.scenario(entry), mini(menu.difficulty, 2))
		return
	# First game: the human plays the chosen slot with the typed name and blazon.
	var row := ELSingleScenario.scenario(entry, slots.human_player() if slots != null else 1)
	row.player_name = slots.human_name() if slots != null else ELPlayerProfile.current_name(profile())
	row.logo = ELPlayerProfile.blazon.x
	row.colour = ELPlayerProfile.blazon.y
	menu.campaign_requested.emit(menu.edition, row, menu.difficulty)

## Mission list: size icon, number of sides, race marks and the mission name.
class MissionList extends Control:
	var screen: ELSingleScreen
	var offset := 0
	var columns := {}
	var icons: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func visible_rows() -> int:
		return int(size.y / screen.row_height())

	func scroll(step: int) -> void:
		offset = clampi(offset + step, 0, maxi(0, screen.rows().size() - visible_rows()))
		queue_redraw()

	func reveal(index: int) -> void:
		if index < 0: return
		if index < offset: offset = index
		elif index >= offset + visible_rows(): offset = index - visible_rows() + 1

	func row_rect(index: int) -> Rect2:
		var at := index - offset
		if at < 0 or at >= visible_rows(): return Rect2()
		return Rect2(Vector2(0, at * screen.row_height()), Vector2(size.x, screen.row_height()))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				screen.choose_row(offset + int(event.position.y / screen.row_height()))
				# A double click is the list's Enter: Start.
				if event.double_click: screen.start()
			accept_event()

	func _draw() -> void:
		var shown := screen.rows()
		offset = clampi(offset, 0, maxi(0, shown.size() - visible_rows()))
		if not screen.second():
			_draw_first(shown)
			return
		var font := screen.menu.serif
		var profile := screen.profile()
		var row := screen.row_height()
		for at in visible_rows():
			var index := offset + at
			if index >= shown.size(): break
			var entry: Dictionary = shown[index]
			var y := at * row
			if entry.id == screen.selected: draw_rect(Rect2(0, y, size.x, row), Color(0.85, 0.7, 0.4, 0.22))
			var baseline := y + (row - font.get_height(15)) * 0.5 + font.get_ascent(15)
			var icon: Dictionary = icons[int(entry.size_class)] if int(entry.size_class) < icons.size() else {}
			if not icon.is_empty():
				var box: Vector2 = Vector2(icon.source.size) * ((row - 2) / icon.source.size.y)
				draw_texture_rect_region(icon.texture, Rect2(Vector2(float(columns.get("Sort1", 15)) - box.x * 0.5, y + 1), box), icon.source)
			var name_x := float(columns.get("Mission", 100))
			var ink := ELFrontMenu.INK_HOVER if entry.id == screen.selected else ELFrontMenu.BODY_INK
			draw_string(font, Vector2(name_x, baseline), ELSingleScenario.title(profile, entry), HORIZONTAL_ALIGNMENT_LEFT, float(columns.get("Sort4", size.x)) - name_x - 4, 15, ink)

	## First game rows: size icon, "players/players" at (42,5), race marks,
	## win and lose marks and the name at (105,5); white text, the chosen row
	## bold gold, no selection bar.
	func _draw_first(shown: Array[Dictionary]) -> void:
		var menu := screen.menu
		var panel_9 := menu.texture_named("MISSION_PANEL_9")
		var panel_7 := menu.texture_named("MISSION_PANEL_7")
		var bold := FontVariation.new()
		bold.base_font = menu.serif
		bold.variation_embolden = 0.8
		for at in visible_rows():
			var index := offset + at
			if index >= shown.size(): break
			var entry: Dictionary = shown[index]
			var origin := Vector2(0, at * ELSingleScreen.ROW)
			var chosen: bool = entry.id == screen.selected
			var font: Font = bold if chosen else menu.serif
			var ink := ELSingleScreen.ROW_CHOSEN_INK if chosen else ELSingleScreen.ROW_INK
			var size_class := clampi(int(entry.size_class), 0, ELSingleScreen.SIZE_ICONS.size() - 1)
			var icon: Rect2 = ELSingleScreen.SIZE_ICONS[size_class]
			if panel_9 != null: draw_texture_rect_region(panel_9, Rect2(origin, icon.size), icon)
			if panel_7 != null:
				for race: int in ELSingleScreen.RACE_MARKS:
					if not entry.races.has(race): continue
					var mark: Array = ELSingleScreen.RACE_MARKS[race]
					draw_texture_rect_region(panel_7, Rect2(origin + mark[0], mark[1].size), mark[1])
				for mark: Array in [ELSingleScreen.WIN_MARK, ELSingleScreen.LOSE_MARK]:
					draw_texture_rect_region(panel_7, Rect2(origin + mark[0], mark[1].size), mark[1])
			var baseline := font.get_ascent(ELSingleScreen.ROW_TEXT)
			var players: int = entry.players.size()
			draw_string(font, origin + Vector2(42, 5 + baseline), "%d/%d" % [players, players], HORIZONTAL_ALIGNMENT_LEFT, -1, ELSingleScreen.ROW_TEXT, ink)
			draw_string(font, origin + Vector2(105, 5 + baseline), ELSingleScenario.title(screen.profile(), entry), HORIZONTAL_ALIGNMENT_LEFT, 147, ELSingleScreen.ROW_TEXT, ink)
