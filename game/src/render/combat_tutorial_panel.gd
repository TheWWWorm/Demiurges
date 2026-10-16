class_name ELCombatTutorialPanel
extends Control
## Second-game combat tutorial text panel (CTutPlayerPanel, Controls "TutPlayer"):
## the tutorial text in TP_TextBounds with its scroll arrows, and the Show and
## Close buttons drawn from the original CutParts art. Design coordinates are
## the 1024x768 Controls rows; the panel keeps its distance from the right edge
## on wider windows. In tutorial mode only Show (text on/off) and Close are
## offered. In replay player mode (Duel -> Replay) the panel carries the
## original player controls: Rewind, Play/Pause, Pause at comment, editor mode
## (Show) and Close; editor mode adds Next command / Next phase / Next turn and
## Player mode (HideE). Until the first recorded command plays, Inventory
## takes Rewind's place (544404: shown when a replay opens or
## rewinds, swapped back): it shows each hero's deck and bag. In
## editor mode the comment of the next command is editable, Save changes
## (TP_SaveE) opens the replay save screen, and Add pointer
## (TP_PointerE) is shown but does nothing, as its command has no handler in
## the original.

signal close_requested
signal play_toggled(on: bool)
signal rewind_requested
signal inventory_requested
signal save_requested
## The editor's comment text was changed by the player.
signal comment_edited(text: String)
signal comment_pause_toggled(on: bool)
## 1 next command, 2 next phase, 3 next turn.
signal step_requested(mode: int)

const DESIGN := Vector2(1024, 768)
const BUTTONS := ["TP_Show", "TP_Close", "TP_ScrollUp", "TP_ScrollDown", "TP_Back", "TP_Inventory", "TP_Play", "TP_TextPause",
	"TP_Pause1E", "TP_Pause2E", "TP_Pause3E", "TP_HideE", "TP_CloseE", "TP_SaveE", "TP_PointerE"]
const TUTORIAL_BUTTONS := ["TP_Show", "TP_Close"]
const PLAYER_BUTTONS := ["TP_Back", "TP_Play", "TP_TextPause", "TP_Show", "TP_Close"]
const EDITOR_BUTTONS := ["TP_Back", "TP_Play", "TP_Pause1E", "TP_Pause2E", "TP_Pause3E", "TP_TextPause", "TP_HideE", "TP_CloseE", "TP_SaveE", "TP_PointerE"]
## Buttons with a caption drawn over their art (Controls Text, FontSize 14).
const CAPTIONED := ["TP_SaveE", "TP_PointerE"]
const TEXT_INK := Color("e6dcc0")

var text_box: RichTextLabel
## Editor mode: the next command's comment, editable.
var edit_box: TextEdit
## Comments can be edited (a command is waiting).
var editable := true
var captions: Dictionary = {}
var _font: Font
var _setting := false
var buttons: Dictionary = {}
var text_shown := true
## Replay player (true) or combat tutorial (false); editor mode of the player.
var player := false
var editor := false
## Before the first recorded command: Inventory is offered in Rewind's place.
var at_start := false
## Check buttons drawn pushed: TP_Play, TP_TextPause, TP_Pause1E..3E.
var checked: Dictionary = {}
var _art: Dictionary = {}
var _bounds := Rect2(472, 46, 301, 177)
var _left := 472.0
var _font_size := 15

func build(profile: ELProfile, player_mode := false) -> void:
	player = player_mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	var controls := {}
	for row: Dictionary in profile.table("Controls").values():
		if str(row.get("Parent", "")) == "TutPlayer": controls[str(row.get("Name", ""))] = row
	var bounds: Dictionary = controls.get("TP_TextBounds", {})
	if not bounds.is_empty():
		_bounds = Rect2(float(bounds.Left), float(bounds.Top), float(bounds.Width), float(bounds.Height))
		_font_size = int(bounds.get("FontSize", 15))
	_left = _bounds.position.x
	for row: Dictionary in profile.table("CutParts").values():
		var control := str(row.get("Ctrl", ""))
		if control not in BUTTONS: continue
		var masks: Variant = row.get("Msk", [])
		var list: Array = masks if masks is Array else [masks]
		var state := "free" if list == ["Free"] else ("push" if list == ["Push"] else ("hover" if list.has("Light") and not list.has("Push") else "hover_push"))
		var texture := profile.texture(paths.get(row.get("Txt", ""), ""))
		if texture == null: continue
		var piece := {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH),
			"rect": Rect2(row.ScrL, row.ScrT, row.get("ScrW", row.TxtW), row.get("ScrH", row.TxtH))}
		# The scroll arrows carry a Light highlight only; Free/Push come from another sheet.
		if not _art.has(control + ":" + state): _art[control + ":" + state] = piece
		_left = minf(_left, piece.rect.position.x)
	text_box = RichTextLabel.new()
	text_box.bbcode_enabled = false
	text_box.scroll_active = true
	text_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_theme_font_size_override("normal_font_size", _font_size)
	text_box.add_theme_color_override("default_color", TEXT_INK)
	text_box.add_theme_color_override("font_shadow_color", Color.BLACK)
	text_box.add_theme_constant_override("shadow_offset_x", 1)
	text_box.add_theme_constant_override("shadow_offset_y", 1)
	text_box.mouse_filter = Control.MOUSE_FILTER_PASS
	text_box.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	text_box.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_box)
	edit_box = TextEdit.new()
	edit_box.name = "CommentEdit"
	edit_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit_box.add_theme_color_override("font_color", TEXT_INK)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.03, 0.04, 0.03, 0.85)
	back.border_color = Color(0.55, 0.45, 0.3, 0.8)
	back.set_border_width_all(1)
	back.set_content_margin_all(4)
	edit_box.add_theme_stylebox_override("normal", back)
	edit_box.add_theme_stylebox_override("focus", back)
	edit_box.add_theme_stylebox_override("read_only", back)
	edit_box.text_changed.connect(func():
		if not _setting: comment_edited.emit(edit_box.text))
	add_child(edit_box)
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
	system.font_weight = 700
	_font = system
	for control: String in CAPTIONED:
		var key := str(controls.get(control, {}).get("Text", "Ctrl" + control))
		captions[control] = profile.text(key).strip_edges() if not profile.text(key).strip_edges().is_empty() else key
	for control: String in BUTTONS:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		for style in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.tooltip_text = profile.text(str(controls.get(control, {}).get("ToolTip", "")))
		if button.tooltip_text.begins_with("Ctrl"): button.tooltip_text = ""
		button.set_meta("control", control)
		button.mouse_entered.connect(queue_redraw)
		button.mouse_exited.connect(queue_redraw)
		button.button_down.connect(queue_redraw)
		button.button_up.connect(queue_redraw)
		add_child(button)
		buttons[control] = button
	buttons.TP_Show.pressed.connect(func():
		if player: editor = true
		else: text_shown = not text_shown
		_layout())
	buttons.TP_HideE.pressed.connect(func():
		editor = false
		_layout())
	buttons.TP_Close.pressed.connect(func(): close_requested.emit())
	buttons.TP_CloseE.pressed.connect(func(): close_requested.emit())
	buttons.TP_Back.pressed.connect(func(): rewind_requested.emit())
	buttons.TP_Inventory.pressed.connect(func(): inventory_requested.emit())
	buttons.TP_SaveE.pressed.connect(func(): save_requested.emit())
	buttons.TP_Play.pressed.connect(func(): play_toggled.emit(not checked.get("TP_Play", false)))
	buttons.TP_TextPause.pressed.connect(func():
		set_checked("TP_TextPause", not checked.get("TP_TextPause", false))
		comment_pause_toggled.emit(checked.TP_TextPause))
	for mode in 3: buttons["TP_Pause%dE" % (mode + 1)].pressed.connect(func(): step_requested.emit(mode + 1))
	buttons.TP_ScrollUp.pressed.connect(_scroll.bind(-1))
	buttons.TP_ScrollDown.pressed.connect(_scroll.bind(1))
	resized.connect(_layout)
	_layout()

func set_checked(control: String, on: bool) -> void:
	checked[control] = on
	queue_redraw()

func set_at_start(value: bool) -> void:
	if at_start == value: return
	at_start = value
	_layout()

func set_text(value: String) -> void:
	if text_box == null: return
	text_box.text = value
	text_box.scroll_to_line(0)
	# The edit box follows the shown comment unless the player is typing in it.
	if edit_box.text != value and not edit_box.has_focus():
		_setting = true
		edit_box.text = value
		_setting = false
	_layout()

## Editor comments can be typed only while a command is waiting.
func set_editable(value: bool) -> void:
	editable = value
	if edit_box != null: edit_box.editable = value

func shown_text() -> String:
	return text_box.text if text_box != null else ""

func design_scale() -> float:
	return maxf(1.0, minf(size.x / DESIGN.x, size.y / DESIGN.y))

## Screen position of a design point (right-anchored panel).
func to_screen(point: Vector2) -> Vector2:
	var s := design_scale()
	return Vector2(size.x - (DESIGN.x - point.x) * s, point.y * s)

func _rect(control: String) -> Rect2:
	var piece: Dictionary = _art.get(control + ":free", _art.get(control + ":hover", {}))
	if piece.is_empty(): return Rect2()
	return piece.rect

func _layout() -> void:
	if text_box == null: return
	var s := design_scale()
	text_box.position = to_screen(_bounds.position)
	text_box.size = _bounds.size * s
	text_box.add_theme_font_size_override("normal_font_size", roundi(_font_size * s))
	text_box.visible = text_shown and not (player and editor)
	edit_box.visible = player and editor
	edit_box.position = text_box.position
	edit_box.size = text_box.size
	edit_box.add_theme_font_size_override("font_size", roundi(_font_size * s))
	if not edit_box.visible and edit_box.has_focus(): edit_box.release_focus()
	for control: String in buttons:
		var rect := _rect(control)
		var button: Button = buttons[control]
		button.position = to_screen(rect.position)
		button.size = rect.size * s
		var shown: Array = (EDITOR_BUTTONS if editor else PLAYER_BUTTONS) if player else TUTORIAL_BUTTONS
		if control == "TP_Inventory": button.visible = player and at_start
		elif control == "TP_Back" and at_start: button.visible = false
		else: button.visible = control in shown or (control.begins_with("TP_Scroll") and text_shown and not text_box.text.strip_edges().is_empty())
	queue_redraw()

func _scroll(step: int) -> void:
	var bar := text_box.get_v_scroll_bar()
	bar.value = clampf(bar.value + step * _font_size * 3, 0, bar.max_value)

func _draw() -> void:
	if text_box == null: return
	var s := design_scale()
	if text_shown and not text_box.text.strip_edges().is_empty():
		# Backing behind the text so it stays readable over the arena (remake);
		# blank notes leave the area clear as in the original.
		var back := Rect2(to_screen(_bounds.position - Vector2(6, 4)), (_bounds.size + Vector2(30, 8)) * s)
		draw_rect(back, Color(0.03, 0.04, 0.03, 0.8))
		draw_rect(back, Color(0.55, 0.45, 0.3, 0.6), false, 1.0)
	for control: String in buttons:
		var button: Button = buttons[control]
		if not button.visible: continue
		var state := "push" if checked.get(control, false) else "free"
		match button.get_draw_mode():
			BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED: state = "push"
			BaseButton.DRAW_HOVER: state = "hover"
		var piece: Dictionary = _art.get(control + ":" + state, _art.get(control + ":free", {}))
		if piece.is_empty(): continue
		var area := Rect2(to_screen(piece.rect.position), piece.rect.size * s)
		draw_texture_rect_region(piece.texture, area, piece.source)
		if captions.has(control):
			# FontSize 14 in the registry; a longer caption is set smaller to fit.
			var size := roundi(14 * s)
			var width := _font.get_string_size(captions[control], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			while width > area.size.x - 8 and size > 8:
				size -= 1
				width = _font.get_string_size(captions[control], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var baseline := area.position.y + (area.size.y - _font.get_height(size)) * 0.5 + _font.get_ascent(size)
			draw_string(_font, Vector2(area.position.x + maxf(2, (area.size.x - width) * 0.5), baseline), captions[control], HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 4, size, TEXT_INK)
