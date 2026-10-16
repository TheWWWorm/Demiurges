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
## original uses the Windows short date), and the saved picture is not shown.

## Rows follow the 26 px grid of the SaveMissionScreen list art.
const ROW := 26.0
## Panel-local rectangles of controls the first game takes from CutParts only
## (its art is the second game's: the same pieces at the same places).
const FALLBACK := {"SMGamesBarBounds": Rect2(449, 72, 14, 415), "SMScrollD": Rect2(447, 487, 15, 12), "SMInfoBounds": Rect2(480, 278, 242, 219)}

var menu: ELFrontMenu
var entries: Array[Dictionary] = []
var selected := -1
var list: SaveList
## "load" or "save".
var mode := "load"
## ELSaveSlots.KIND_CAMPAIGN or KIND_SINGLE.
var kind := ELSaveSlots.KIND_SINGLE
## Shown over a running game: Load asks first, Save is possible.
var in_game := false
## Save mode: called with the cleaned name; returns "" or an error text.
var saver := Callable()
## Save mode: the running game's row (information box before a row is chosen).
var current: Dictionary = {}
var name_edit: LineEdit

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
	for index in 3:
		var control := "SMCaption%d" % (index + 1)
		menu._label("column%d" % index, menu._caption(control), _rect(control), 17)
	list = SaveList.new()
	list.screen = self
	# The grid under the column captions: it starts 33 px left of the name
	# caption (the art's narrow first column) and ends at the scroll bar and
	# its down arrow.
	var name_column := _rect("SMCaption1")
	var bar := _rect("SMGamesBarBounds")
	var down := _rect("SMScrollD")
	list.position = Vector2(name_column.position.x - 33, name_column.end.y + 1)
	list.size = Vector2(bar.position.x - list.position.x - 2, floorf((down.end.y - list.position.y) / ROW) * ROW)
	for index in 3:
		var column := _rect("SMCaption%d" % (index + 1))
		list.columns.append(Vector2(column.position.x - list.position.x, column.size.x))
	menu.canvas.add_child(list)
	menu.labels["list"] = list
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
	if name_edit != null:
		var edit := name_edit
		(func(): if is_instance_valid(edit) and edit.is_inside_tree(): edit.grab_focus()).call_deferred()

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
	if menu.text_box != null:
		var row: Dictionary = entries[selected] if chosen else current
		menu.text_box.text = ELSaveSlots.info(profile(), row) if not row.is_empty() else ""
		menu.text_box.get_v_scroll_bar().value = 0
	if list != null: list.queue_redraw()

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
	if ELSaveSlots.exists(menu.edition, cleaned):
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
			var baseline := y + (ELMissionLoadScreen.ROW - font.get_height(15)) * 0.5 + font.get_ascent(15)
			var ink := ELFrontMenu.INK_HOVER if index == screen.selected else ELFrontMenu.BODY_INK
			var when := ELMissionLoadScreen.stamp(int(entry.modified))
			var cells: Array[String] = [str(entry.name), when[0], when[1]]
			for column in mini(columns.size(), cells.size()):
				draw_string(font, Vector2(columns[column].x + 2, baseline), cells[column], HORIZONTAL_ALIGNMENT_LEFT, columns[column].y - 4, 15, ink)
