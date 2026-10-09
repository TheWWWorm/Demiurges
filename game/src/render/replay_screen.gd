class_name ELReplayScreen
extends RefCounted
## Second-game ReplayScreen in its two modes. Load (Duel -> Replay, panel
## Type3 art, "LOAD DUEL REPLAY"): the saved replays of the edition by name;
## the chosen one shows "Duel selected:" with my hero and the enemy hero
## (portrait and name); Load plays it back, Delete asks T_MB_DELETE_REPLAY,
## Back returns to the Duel menu. Save (the final round result's "Save duel
## replay", Type4 art, "SAVE DUEL REPLAY"): a name field; OK refuses an empty
## name or a forbidden character (T_MB_WRONG_REPLAY_NAME), asks
## T_MB_OVERWRITE_REPLAY for a taken name, writes the match's rounds and
## returns to the round result. A double click is Load or OK; Esc closes an
## open question first, then the screen. "Sort by replay name" turns the
## order around (approximation: the original's sort details were not read).

const ROW := 22.0

var menu: ELFrontMenu
var mode := "load"
var entries: Array[Dictionary] = []
var selected := -1
var descending := false
var list: ReplayList
var name_edit: LineEdit
## Save mode: the finished match's recording.
var recording: ELDuelRecording

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func profile() -> ELProfile:
	return menu.profile

func refresh_entries() -> void:
	entries = ELDuelRecording.list(menu.edition)
	if descending: entries.reverse()

func build_screen() -> void:
	mode = "save" if menu.screen == "replay_save" else "load"
	var caption := "ReplayScrText" if mode == "save" else "ReplayScrLoadText"
	menu._label("caption", menu._caption(caption), menu.control_rect(caption), 18)
	for control: String in ["ReplayScrDuSel", "ReplayScrMyHero", "ReplayScrEnemyHero"]:
		menu._label(control, menu._caption(control), menu.control_rect(control), 18, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_LEFT)
	for side in 2:
		var control := "ReplayScrName%d" % (side + 1)
		menu._label(control, "", menu.control_rect(control), 16, ELFrontMenu.INK_HOVER)
		var picture := TextureRect.new()
		var rect := menu.control_rect("ReplayScrFace%d" % (side + 1))
		picture.position = rect.position
		picture.size = rect.size
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.canvas.add_child(picture)
		menu.labels["ReplayScrFace%d" % (side + 1)] = picture
	var sort := SortText.new()
	sort.menu = menu
	sort.caption = menu._caption("ReplayScrSort")
	var sort_rect := menu.control_rect("ReplayScrSort")
	sort.position = sort_rect.position
	sort.size = sort_rect.size
	sort.pressed.connect(toggle_sort)
	menu.canvas.add_child(sort)
	menu.buttons["ReplayScrSort"] = sort
	list = ReplayList.new()
	list.screen = self
	var bounds := menu.control_rect("ReplayScrListBounds")
	list.position = bounds.position
	list.size = Vector2(bounds.size.x, floorf(bounds.size.y / ROW) * ROW)
	menu.canvas.add_child(list)
	menu.labels["list"] = list
	_button("ReplayScrScrollU", func(): list.scroll(-3))
	_button("ReplayScrScrollD", func(): list.scroll(3))
	_button("ReplayScrDelete", ask_delete)
	_button("ReplayScrBack", close)
	if mode == "save":
		_button("ReplayScrOk", save_chosen)
		menu._label("ReplayScrFileName", menu._caption("ReplayScrFileName"), menu.control_rect("ReplayScrFileName"), 16, ELFrontMenu.TITLE_INK, HORIZONTAL_ALIGNMENT_RIGHT)
		_build_name_field()
	else: _button("ReplayScrLoad", load_chosen)
	refresh_entries()
	selected = 0 if mode == "load" and not entries.is_empty() else -1
	refresh()
	if name_edit != null:
		var edit := name_edit
		(func(): if is_instance_valid(edit) and edit.is_inside_tree(): edit.grab_focus()).call_deferred()

func _button(control: String, action: Callable) -> ELFrontMenu.CutButton:
	var button := menu._square(control)
	if button != null: button.pressed.connect(action)
	return button

func _build_name_field() -> void:
	var rect := menu.control_rect("ReplayScrEdit")
	name_edit = LineEdit.new()
	name_edit.position = rect.position
	name_edit.size = rect.size
	name_edit.max_length = ELDuelRecording.MAX_NAME
	name_edit.add_theme_font_override("font", menu.serif)
	name_edit.add_theme_font_size_override("font_size", 16)
	name_edit.add_theme_color_override("font_color", ELFrontMenu.INK_HOVER)
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0, 0, 0, 0.25)
	field.content_margin_left = 8
	for style in ["normal", "focus", "read_only"]: name_edit.add_theme_stylebox_override(style, field)
	name_edit.text_submitted.connect(func(_text: String): save_chosen())
	menu.canvas.add_child(name_edit)
	menu.labels["name"] = name_edit

func refresh() -> void:
	if not menu.screen in ["replay_load", "replay_save"]: return
	if selected >= entries.size(): selected = -1
	var chosen := selected >= 0
	if menu.buttons.has("ReplayScrLoad"): menu.buttons.ReplayScrLoad.disabled = not chosen
	if menu.buttons.has("ReplayScrDelete"): menu.buttons.ReplayScrDelete.disabled = not chosen
	if menu.buttons.has("ReplayScrOk"): menu.buttons.ReplayScrOk.disabled = recording == null or not recording.complete()
	var row: Dictionary = entries[selected] if chosen else {}
	if not chosen and mode == "save" and recording != null: row = {"labels": recording.labels, "faces": recording.faces}
	for side in 2:
		var name: Label = menu.labels.get("ReplayScrName%d" % (side + 1))
		var face: TextureRect = menu.labels.get("ReplayScrFace%d" % (side + 1))
		var labels: Array = row.get("labels", [])
		var faces: Array = row.get("faces", [])
		if name != null: name.text = String(labels[side]) if labels.size() > side else ""
		if face != null: face.texture = profile().portrait(int(faces[side])) if faces.size() > side and int(faces[side]) >= 0 else null
	if list != null: list.queue_redraw()

func choose_row(index: int) -> void:
	if index < 0 or index >= entries.size(): return
	selected = index
	if mode == "save" and name_edit != null: name_edit.text = String(entries[index].name)
	refresh()

func confirm() -> void:
	if mode == "save": save_chosen()
	else: load_chosen()

func toggle_sort() -> void:
	var chosen := String(entries[selected].name) if selected >= 0 and selected < entries.size() else ""
	descending = not descending
	refresh_entries()
	selected = -1
	for index in entries.size():
		if String(entries[index].name) == chosen: selected = index
	refresh()

func load_chosen() -> void:
	if mode != "load" or selected < 0 or selected >= entries.size(): return
	var row := entries[selected]
	if ELDuelRecording.read(String(row.path), menu.edition).is_empty():
		# The original's own (untranslated) message.
		menu.duel_ui.show_message("Error loading replay", Callable(), false, 240.0)
		return
	menu.replay_requested.emit(String(row.path))

func save_chosen() -> void:
	if mode != "save" or name_edit == null or recording == null or not recording.complete(): return
	var cleaned := ELDuelRecording.clean_name(name_edit.text)
	if cleaned.is_empty():
		menu.duel_ui.show_message(menu.text("T_MB_WRONG_REPLAY_NAME").strip_edges(), Callable(), false, 340.0)
		return
	name_edit.text = cleaned
	if recording.exists(cleaned):
		menu.duel_ui.show_message(menu.text("T_MB_OVERWRITE_REPLAY").strip_edges(), func(): _save(cleaned), true, 240.0)
		return
	_save(cleaned)

func _save(cleaned: String) -> void:
	var error := recording.save(cleaned)
	if not error.is_empty():
		menu.refuse(error, 260.0)
		return
	close()

func ask_delete() -> void:
	if selected < 0 or selected >= entries.size(): return
	var row := entries[selected]
	menu.duel_ui.show_message(menu.text("T_MB_DELETE_REPLAY").strip_edges(), func():
		ELDuelRecording.remove(String(row.path))
		refresh_entries()
		selected = mini(selected, entries.size() - 1) if mode == "load" else -1
		refresh(), true, 240.0)

func close() -> void:
	menu.go_back()

func escape() -> bool:
	if menu.duel_ui.message != null and is_instance_valid(menu.duel_ui.message):
		menu.duel_ui.close_message()
		return true
	return false

## Saved replays by name.
class ReplayList extends Control:
	var screen: ELReplayScreen
	var offset := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func visible_rows() -> int:
		return int(size.y / ELReplayScreen.ROW)

	func scroll(step: int) -> void:
		offset = clampi(offset + step, 0, maxi(0, screen.entries.size() - visible_rows()))
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: scroll(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: scroll(1)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				var index := offset + int(event.position.y / ELReplayScreen.ROW)
				if index < screen.entries.size():
					screen.choose_row(index)
					if event.double_click: screen.confirm()
			accept_event()

	func _draw() -> void:
		var font := screen.menu.serif
		for at in visible_rows():
			var index := offset + at
			if index >= screen.entries.size(): break
			var y := at * ELReplayScreen.ROW
			if index == screen.selected: draw_rect(Rect2(0, y, size.x, ELReplayScreen.ROW), Color(0.85, 0.7, 0.4, 0.22))
			var baseline := y + (ELReplayScreen.ROW - font.get_height(16)) * 0.5 + font.get_ascent(16)
			var ink := ELFrontMenu.INK_HOVER if index == screen.selected else ELFrontMenu.BODY_INK
			draw_string(font, Vector2(6, baseline), String(screen.entries[index].name), HORIZONTAL_ALIGNMENT_LEFT, size.x - 10, 16, ink)

## "Sort by replay name": a text button over the list's header strip.
class SortText extends BaseButton:
	var menu: ELFrontMenu
	var caption := ""

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := get_draw_mode() in [DRAW_HOVER, DRAW_HOVER_PRESSED]
		var font := menu.serif
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var at := Vector2((size.x - width) * 0.5, (size.y - font.get_height(17)) * 0.5 + font.get_ascent(17))
		draw_string(font, at + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0, 0, 0, 0.8))
		draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ELFrontMenu.INK_HOVER if hover else ELFrontMenu.TITLE_INK)
