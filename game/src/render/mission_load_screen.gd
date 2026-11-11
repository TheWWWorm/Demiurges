class_name ELMissionLoadScreen
extends RefCounted
## The original SaveMissionScreen of both games in its two modes:
## load (Load game -> Campaign / Single in the first game; Campaign -> Load and
## Mission -> Load in the second; Load inside a running game) and save (Save
## inside a running game). The list shows the named saves of one edition and
## one kind (campaign games or single missions) under ИМЯ / ДАТА / ВРЕМЯ.
## Load mode selects the first row when the list opens; Load and Delete need a
## row. Save mode opens with an empty name field; clicking a row copies its
## name; Save asks T_MB_OVERWRITE when the name is taken and then closes the
## screen. Delete asks T_MB_DELETE_SAVE; Load inside a running game asks
## T_MB_LOAD_GAME. A double click is Enter (Load or Save); Back and Esc close
## the screen. The second game cleans the typed name and refuses forbidden
## characters with T_MB_WRONG_SAVE_NAME; the first keeps Save disabled while
## the name is blank. Approximations: rows follow name order (the original
## lists its folder order), the date is dd.mm.yyyy and the time hh:mm (the
## original uses the Windows short date).

## Rows follow the 26 px grid of the SaveMissionScreen list art.
const ROW := 26.0
## The grid painted by SaveMissionScreen, in panel-local coordinates.
## The registry calls its column controls SMCaption or SMSort depending on the install.
const GRID := Rect2(60, 83, 387, 416)
const COLUMNS := [Rect2(93, 58, 200, 24), Rect2(296, 58, 79, 24), Rect2(378, 58, 64, 24)]
const SORT_HEADERS := ["CtrlSMSortName", "CtrlSMSortDate", "CtrlSMSortTime"]
const EN_HEADERS := ["Name", "Date", "Time"]
const RU_HEADERS := ["Имя", "Дата", "Время"]
## EL2's scene capture rectangle, relative to SaveMissionScreen.
const PREVIEW := Rect2(481, 60, 256, 192)
## Panel-local rectangles of controls the first game takes from CutParts only
## (its art is the second game's: the same pieces at the same places).
const FALLBACK := {"SMInfoBounds": Rect2(480, 278, 242, 219)}

var menu: ELFrontMenu
var entries: Array[Dictionary] = []
var selected := -1
var list: SaveList
## "load" or "save".
var mode := "load"
## The save category of this screen.
var kind := ELSaveSlots.KIND_SINGLE
## Shown over a running game: Load asks first, Save is possible.
var in_game := false
## Save mode: called with the cleaned name; returns "" or an error text.
var saver := Callable()
## Save mode: the running game's row (information box before a row is chosen).
var current: Dictionary = {}
var name_edit: LineEdit
var _preview: TextureRect
var _previews := {}

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func profile() -> ELProfile:
	return menu.profile

## Mode and kind for the next build_screen.
func prepare(next_mode: String, next_kind: String, running := false) -> void:
	mode = next_mode
	kind = next_kind
	in_game = running
	if not running:
		saver = Callable()
		current = {}

## Single-mission saves of this edition whose map the catalogue still knows.
static func saves(source: ELProfile, of_kind := ELSaveSlots.KIND_SINGLE) -> Array[Dictionary]:
	return ELSaveSlots.list(source, of_kind)

## "dd.mm.yyyy" and "hh:mm" of a file time in the local time zone.
static func stamp(unix: int) -> Array[String]:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var at := Time.get_datetime_dict_from_unix_time(unix + bias)
	return ["%02d.%02d.%04d" % [at.day, at.month, at.year], "%02d:%02d" % [at.hour, at.minute]]

func _rect(control: String) -> Rect2:
	var found := menu.control_rect(control)
	if found.size.x > 0 or not FALLBACK.has(control): return found
	var local: Rect2 = FALLBACK[control]
	return Rect2(local.position + menu.shift("SaveMissionScreen"), local.size)

func _button(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var button := menu._square(control)
	if button != null: button.pressed.connect(action)
	return button

func build_screen() -> void:
	var caption := "SaveMissionText" if mode == "save" else "LoadMissionText"
	menu._label("caption", menu._caption(caption), _rect(caption), 18)
	var origin := menu.shift("SaveMissionScreen")
	list = SaveList.new()
	list.screen = self
	list.position = origin + GRID.position
	list.size = GRID.size
	for index in COLUMNS.size():
		var column: Rect2 = COLUMNS[index]
		menu._label("column%d" % index, _column_caption(index), Rect2(origin + column.position, column.size), 17)
		list.columns.append(Vector2(column.position.x - GRID.position.x, column.size.x))
	menu.canvas.add_child(list)
	menu.labels["list"] = list
	_preview = null
	_previews.clear()
	if menu.edition == "el2":
		_preview = TextureRect.new()
		_preview.name = "SavePreview"
		_preview.position = menu.shift("SaveMissionScreen") + PREVIEW.position
		_preview.size = PREVIEW.size
		_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.canvas.add_child(_preview)
	var info := menu.control_rect("SMInfoBounds") if menu.control_rect("SMInfoBounds").size.x > 0 else menu.control_rect("SMInfo")
	if info.size.x <= 0: info = _rect("SMInfoBounds")
	menu._text_box(info.grow_individual(-6, -4, -4, -4), "", 16)
	_button("SMScrollU", func(): list.scroll(-3))
	_button("SMScrollD", func(): list.scroll(3))
	_button("SMInfoU", func(): menu.scroll_text(-3))
	_button("SMInfoD", func(): menu.scroll_text(3))
	if mode == "save":
		_build_name_field()
		_button("SaveButton", save_chosen)
	else: _button("LoadButton", load_chosen)
	_button("SMDelete", ask_delete)
	_button("SaveMissionBack", close)
	entries = saves(profile(), kind)
	selected = 0 if mode == "load" and not entries.is_empty() else -1
	refresh()
	if mode == "save" and name_edit != null:
		_focus_name.call_deferred(name_edit.get_instance_id())

func _column_caption(index: int) -> String:
	var plain := "CtrlSMCaption%d" % (index + 1)
	var sort: String = SORT_HEADERS[index]
	for key: String in ([sort, plain] if menu.edition == "el2" else [plain, sort]):
		var caption := menu.text(key)
		if not caption.is_empty() and caption != key: return caption
	return RU_HEADERS[index] if ELRemakeText.language(profile()) == "ru" else EN_HEADERS[index]

func _focus_name(id: int) -> void:
	var edit := instance_from_id(id) as LineEdit
	if is_instance_valid(edit) and edit.is_inside_tree(): edit.grab_focus()

## The name field: the second game's caption control left of it; the first
## game's caption ("Имя файла:", the edit control's own text) at the start of
## the edit rectangle, which begins right of the Delete button.
func _build_name_field() -> void:
	var rect := menu.control_rect("SaveMissionEdit")
	if menu.edition == "el2":
		menu._label("name_caption", menu._caption("SaveMissionNameStatic"), _rect("SaveMissionNameStatic"), 16, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var caption := menu._caption("SaveMissionEdit")
		var width := ceilf(menu.arial.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) + 8.0
		menu._label("name_caption", caption, Rect2(rect.position, Vector2(width, rect.size.y)), 16, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
		rect = Rect2(rect.position.x + width, rect.position.y, maxf(80.0, rect.size.x - width), rect.size.y)
	name_edit = LineEdit.new()
	name_edit.position = rect.position
	name_edit.size = rect.size
	name_edit.max_length = ELSaveSlots.MAX_NAME
	name_edit.add_theme_font_override("font", menu.arial)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.add_theme_color_override("font_color", ELFrontMenu.INK_HOVER)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0, 0, 0, 0.25)
	field.content_margin_left = 4
	for style in ["normal", "focus", "read_only"]: name_edit.add_theme_stylebox_override(style, field)
	name_edit.text_changed.connect(func(_text: String): _sync_save())
	name_edit.text_submitted.connect(func(_text: String): save_chosen())
	menu.canvas.add_child(name_edit)
	menu.labels["name"] = name_edit

func refresh() -> void:
	if not menu.screen in ELFrontMenu.SAVE_SCREENS: return
	if selected >= entries.size(): selected = -1
	var chosen := selected >= 0
	if menu.buttons.has("LoadButton"): menu.buttons.LoadButton.disabled = not chosen
	if menu.buttons.has("SMDelete"): menu.buttons.SMDelete.disabled = not chosen
	_sync_save()
	var row: Dictionary = entries[selected] if chosen else current
	if menu.text_box != null:
		menu.text_box.text = ELSaveSlots.info(profile(), row) if not row.is_empty() else ""
		menu.text_box.get_v_scroll_bar().value = 0
	if is_instance_valid(_preview):
		_preview.texture = row.get("preview") if not chosen else _saved_preview(row)
	if list != null: list.queue_redraw()

func _saved_preview(row: Dictionary) -> Texture2D:
	var path := str(row.get("path", ""))
	if not _previews.has(path):
		var image := ELSaveSlots.preview_image(row)
		_previews[path] = ImageTexture.create_from_image(image) if image != null else null
	return _previews[path]

## First game: Save only while the name has a non-space character.
func _sync_save() -> void:
	if not menu.buttons.has("SaveButton") or name_edit == null: return
	menu.buttons.SaveButton.disabled = menu.edition == "el1" and ELSaveSlots.clean_name("el1", name_edit.text).is_empty()

func choose_row(index: int) -> void:
	if index < 0 or index >= entries.size(): return
	selected = index
	if mode == "save" and name_edit != null and entries[index].type == ELSaveSlots.SLOT:
		name_edit.text = str(entries[index].name)
	refresh()

## Enter / double click: the default button of the mode.
func confirm() -> void:
	if mode == "save": save_chosen()
	else: load_chosen()

## Load: the chosen save resumes through the host. Inside a running game the
## original asks T_MB_LOAD_GAME first.
func load_chosen() -> void:
	if selected < 0 or selected >= entries.size(): return
	var row := entries[selected]
	if in_game:
		menu.duel_ui.show_message(menu.text("T_MB_LOAD_GAME").strip_edges(), func(): _load(row), true)
		return
	_load(row)

func _load(row: Dictionary) -> void:
	if in_game:
		menu.leave_screen()
		menu.slot_chosen.emit(row)
		return
	if kind == ELSaveSlots.KIND_SINGLE and row.type != ELSaveSlots.PROGRESS:
		ELSingleScenario.SAVE = str(row.path)
		menu.single_load_requested.emit()
		return
	menu.slot_load_requested.emit(row)

## Save: second-game name rules, the overwrite question, then the host writes
## the slot and the screen closes.
func save_chosen() -> void:
	if mode != "save" or name_edit == null: return
	var cleaned := ELSaveSlots.clean_name(menu.edition, name_edit.text)
	if cleaned.is_empty():
		if menu.edition == "el2": menu.duel_ui.show_message(menu.text("T_MB_WRONG_SAVE_NAME").strip_edges(), Callable(), false, 320.0)
		return
	name_edit.text = cleaned
	if ELSaveSlots.exists(menu.edition, cleaned, kind):
		menu.duel_ui.show_message(menu.text("T_MB_OVERWRITE").strip_edges(), func(): _save(cleaned), true)
		return
	_save(cleaned)

func _save(cleaned: String) -> void:
	var error: String = saver.call(cleaned) if saver.is_valid() else "Saving is not available here."
	if not error.is_empty():
		menu.refuse(error, 300.0)
		entries = saves(profile(), kind)
		refresh()
		return
	menu.leave_screen()

func ask_delete() -> void:
	if selected < 0 or selected >= entries.size(): return
	var row := entries[selected]
	menu.duel_ui.show_message(menu.text("T_MB_DELETE_SAVE").strip_edges(), func():
		ELSaveSlots.remove(row)
		entries = saves(profile(), kind)
		selected = 0 if mode == "load" and not entries.is_empty() else -1
		refresh(), true)

func close() -> void:
	menu.go_back()

## Esc closes an open message box before it leaves the screen.
func escape() -> bool:
	if menu.duel_ui.message != null and is_instance_valid(menu.duel_ui.message):
		menu.duel_ui.close_message()
		return true
	return false

## Saved games: name, date and time under the SMCaption1..3 columns.
class SaveList extends Control:
	var screen: ELMissionLoadScreen
	var offset := 0
	## Per column: x from the list's left edge and width.
	var columns: Array[Vector2] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func visible_rows() -> int:
		return int(size.y / ELMissionLoadScreen.ROW)

	func scroll(step: int) -> void:
		offset = clampi(offset + step, 0, maxi(0, screen.entries.size() - visible_rows()))
		queue_redraw()

	func row_rect(index: int) -> Rect2:
		var at := index - offset
		if at < 0 or at >= visible_rows(): return Rect2()
		return Rect2(Vector2(0, at * ELMissionLoadScreen.ROW), Vector2(size.x, ELMissionLoadScreen.ROW))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var index := offset + int(event.position.y / ELMissionLoadScreen.ROW)
				if index < screen.entries.size():
					screen.choose_row(index)
					if event.double_click: screen.confirm()
			accept_event()

	func _draw() -> void:
		var font := screen.menu.arial
		for at in visible_rows():
			var index := offset + at
			if index >= screen.entries.size(): break
			var entry: Dictionary = screen.entries[index]
			var y := at * ELMissionLoadScreen.ROW
			if index == screen.selected: draw_rect(Rect2(0, y, size.x, ELMissionLoadScreen.ROW), Color(0.85, 0.7, 0.4, 0.22))
			var ink := ELFrontMenu.INK_HOVER if index == screen.selected else ELFrontMenu.BODY_INK
			var when := ELMissionLoadScreen.stamp(int(entry.modified))
			var cells: Array[String] = [str(entry.name), when[0], when[1]]
			for column in mini(columns.size(), cells.size()):
				var width := columns[column].y - 4
				var font_size := 15
				# The complete date and time must fit even with a wider system font.
				while column > 0 and font_size > 1 and font.get_string_size(cells[column], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
					font_size -= 1
				var baseline := y + (ELMissionLoadScreen.ROW - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
				draw_string(font, Vector2(columns[column].x + 2, baseline), cells[column], HORIZONTAL_ALIGNMENT_LEFT, width, font_size, ink)
