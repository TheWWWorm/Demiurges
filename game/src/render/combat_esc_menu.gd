class_name ELCombatEscMenu
extends Control
## Second-game Esc menu in battle (CEscMenu shown with the combat flag): the
## original "OPTIONS MENU" panel (A6-Int-Esc art) with Surrender in place of
## Save, Load, Encyclopaedia, Options (combat page first), Exit to main menu,
## Exit to Windows and the cancel button. Surrender, both exits ask their
## original question (T_MB_SURRENDER, T_MB_QUIT_TO_MM, T_MB_QUIT_TO_WIN) in the
## host. Surrender is disabled while a duel replay plays. The remake's own
## battle menu stays reachable from a small button under the panel. The 1024
## design is scaled uniformly to the window and centred, like the front menu.

signal surrender_requested
signal load_requested
signal encyclopaedia_requested
signal options_requested
signal exit_requested
signal quit_requested
signal remake_menu_requested
signal closed

const DESIGN := Vector2(1024, 768)
const PANEL := "EscMenu"
const BUTTONS := ["EscSurrender", "EscLoad", "EscEncyclopaedia", "EscOptions", "EscExitMM", "EscExitWin"]
const INK := Color("e6dcc0")
const INK_HOVER := Color("fff4d6")
const INK_DISABLED := Color("8a8478")
const CAPTION_SIZE := 22

var profile: ELProfile
var canvas: Control
var art: Control
var header: Label
var remake_button: Button
var buttons: Dictionary = {}
var serif: Font
var serif_bold: Font
var _paths: Dictionary = {}
var _controls: Dictionary = {}
var _rows: Dictionary = {}
var _pieces: Array[Dictionary] = []

func build(source: ELProfile) -> bool:
	profile = source
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		_paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("Controls").values(): _controls[str(row.get("Name", ""))] = row
	for value: Variant in profile.table("CutParts").values():
		var row: Dictionary = value
		var masks: Variant = row.get("Msk", [])
		var copy := row.duplicate()
		copy.masks = masks if masks is Array else [masks]
		if not _rows.has(row.get("Ctrl", "")): _rows[row.get("Ctrl", "")] = []
		_rows[row.get("Ctrl", "")].append(copy)
	if not _rows.has(PANEL) or not _controls.has(PANEL): return false
	name = "CombatEscMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Times New Roman", "Liberation Serif", "DejaVu Serif", "Noto Serif", "serif"])
	serif = system
	var bold := SystemFont.new()
	bold.font_names = system.font_names
	bold.font_weight = 700
	serif_bold = bold
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = DESIGN
	add_child(canvas)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = DESIGN
	art.draw.connect(func():
		for piece: Dictionary in _pieces: art.draw_texture_rect_region(piece.texture, piece.rect, piece.source))
	canvas.add_child(art)
	var offset := shift(PANEL)
	for row: Dictionary in rows(PANEL):
		var piece := cut(row, offset)
		if not piece.is_empty(): _pieces.append(piece)
	header = Label.new()
	header.name = "EscHdr"
	header.text = profile.text("CtrlEscHdr").strip_edges()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", serif_bold)
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", INK)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hdr := control_rect("EscHdr")
	header.position = hdr.position
	header.size = hdr.size
	canvas.add_child(header)
	var widest := 0.0
	for control: String in BUTTONS: widest = maxf(widest, serif.get_string_size(caption(control), HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x)
	var width := clampf(ceilf(widest + 64.0), 140.0, 400.0)
	for control: String in BUTTONS:
		var button := MenuButton3.make(self, control, width)
		if button == null: continue
		canvas.add_child(button)
		buttons[control] = button
	var cancel := CancelButton.make(self, "EscCancel")
	if cancel != null:
		canvas.add_child(cancel)
		buttons.EscCancel = cancel
		cancel.pressed.connect(func(): closed.emit())
	_connect("EscSurrender", surrender_requested)
	_connect("EscLoad", load_requested)
	_connect("EscEncyclopaedia", encyclopaedia_requested)
	_connect("EscOptions", options_requested)
	_connect("EscExitMM", exit_requested)
	_connect("EscExitWin", quit_requested)
	# Remake-only: the remake battle menu (editions, practice setup, saves...).
	remake_button = Button.new()
	remake_button.text = "Remake menu…"
	remake_button.focus_mode = Control.FOCUS_NONE
	remake_button.add_theme_font_size_override("font_size", 15)
	remake_button.tooltip_text = "The remake's own battle menu."
	var panel := control_rect(PANEL)
	remake_button.position = Vector2(panel.position.x + panel.size.x * 0.5 - 70, panel.end.y + 10)
	remake_button.size = Vector2(140, 30)
	remake_button.pressed.connect(func(): remake_menu_requested.emit())
	canvas.add_child(remake_button)
	resized.connect(_layout)
	_layout()
	hide()
	return true

func _connect(control: String, target: Signal) -> void:
	if buttons.has(control): buttons[control].pressed.connect(func(): target.emit())

## Shows the menu; Surrender is offered unless a replay is playing.
func open(surrender_enabled := true) -> void:
	if buttons.has("EscSurrender"): buttons.EscSurrender.disabled = not surrender_enabled
	show()
	move_to_front()
	_layout()

func _layout() -> void:
	if canvas == null or size.x <= 0 or size.y <= 0: return
	var scale_factor := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	canvas.scale = Vector2(scale_factor, scale_factor)
	canvas.position = ((size - DESIGN * scale_factor) * 0.5).floor()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))

# --- Registry helpers ----------------------------------------------------------------

func cut(row: Dictionary, offset := Vector2.ZERO) -> Dictionary:
	var texture := profile.texture(_paths.get(row.get("Txt", ""), ""))
	if texture == null: return {}
	return {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH), "rect": Rect2(Vector2(row.ScrL, row.ScrT) + offset, Vector2(row.TxtW, row.TxtH))}

func rows(control: String, required: Array = [], excluded: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in _rows.get(control, []):
		if required.all(func(mask: String): return row.masks.has(mask)) and not excluded.any(func(mask: String): return row.masks.has(mask)): result.append(row)
	return result

## The panel's registry shift (the Esc menu is a Desktop child).
func shift(control: String) -> Vector2:
	var result := Vector2.ZERO
	var current := control
	for depth in 6:
		var row: Dictionary = _controls.get(current, {})
		if row.is_empty(): break
		result += Vector2(float(row.get("ShiftX", 0)), float(row.get("ShiftY", 0)))
		current = str(row.get("Parent", ""))
	return result

func control_rect(control: String) -> Rect2:
	var row: Dictionary = _controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + shift(control), Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

func caption(control: String) -> String:
	return profile.text(str(_controls.get(control, {}).get("Text", "Ctrl" + control))).replace("  ", " ").strip_edges()

## A three-part (Type5 left, Type6 middle, Type7 right) text button; the
## middle stretches for wider captions and the column stays centred on the
## original 140-unit button.
class MenuButton3 extends BaseButton:
	var menu: ELCombatEscMenu
	var caption := ""
	var states: Dictionary = {}
	var design := Rect2()

	static func make(owner: ELCombatEscMenu, control: String, width: float) -> MenuButton3:
		if owner.rows(control, ["Free", "Type5"], ["Light"]).is_empty(): return null
		var button := MenuButton3.new()
		button.menu = owner
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		button.caption = owner.caption(control)
		var rect := owner.control_rect(control)
		button.design = Rect2(rect.position, Vector2(width, 57))
		var offset := owner.shift(control)
		for state: String in ["normal", "pressed", "hover", "hover_pressed"]:
			var required: Array = {"normal": ["Free"], "pressed": ["Push"], "hover": ["Free", "Light"], "hover_pressed": ["Push", "Light"]}[state]
			var excluded: Array = [] if state.begins_with("hover") else ["Light"]
			var parts: Array[Dictionary] = []
			for type: String in ["Type5", "Type6", "Type7"]:
				var found := owner.rows(control, required + [type], excluded)
				if found.is_empty(): continue
				var piece := owner.cut(found[0], offset)
				if piece.is_empty(): continue
				piece.type = type
				parts.append(piece)
			button.states[state] = parts
		button.size = Vector2(width, 57)
		button.position = Vector2(button.design.position.x + 70.0 - width * 0.5, button.design.position.y)
		return button

	func _ready() -> void:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var lit := not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED)
		var tint := Color(0.6, 0.6, 0.6) if disabled else Color.WHITE
		_parts(states.get("pressed" if pushed else "normal", []), tint)
		if lit: _parts(states.get("hover_pressed" if pushed else "hover", []), Color.WHITE)
		var color := INK_DISABLED if disabled else (INK_HOVER if lit else INK)
		var font := menu.serif
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE)
		var at := Vector2((size.x - text_size.x) * 0.5, (size.y - text_size.y) * 0.5 + font.get_ascent(CAPTION_SIZE) + (1.0 if pushed else 0.0))
		draw_string(font, at + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, Color(0, 0, 0, 0.85))
		draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, color)

	func _parts(parts: Array, tint: Color) -> void:
		var left := design.position.x
		for part: Dictionary in parts:
			var rect: Rect2 = part.rect
			var x: float = rect.position.x - left
			var width: float = rect.size.x
			if part.type == "Type6": width += size.x - 140.0
			elif part.type == "Type7": x = size.x - (left + 140.0 - rect.position.x)
			draw_texture_rect_region(part.texture, Rect2(Vector2(x, rect.position.y - design.position.y), Vector2(width, rect.size.y)), part.source, tint)

## The round cancel button (Free/Push pieces with a Light overlay).
class CancelButton extends BaseButton:
	var parts: Dictionary = {}

	static func make(owner: ELCombatEscMenu, control: String) -> CancelButton:
		var offset := owner.shift(control)
		var pick := func(required: Array, excluded: Array) -> Dictionary:
			var found := owner.rows(control, required, excluded)
			return owner.cut(found[0], offset) if not found.is_empty() else {}
		var button := CancelButton.new()
		button.name = control
		button.focus_mode = Control.FOCUS_NONE
		ELUiSounds.bind(button, owner.profile, control)
		button.parts = {"normal": pick.call(["Free"], ["Light"]), "pressed": pick.call(["Push"], ["Light"]),
			"hover": pick.call(["Free", "Light"], []), "hover_pressed": pick.call(["Push", "Light"], [])}
		if button.parts.normal.is_empty(): return null
		var bounds: Rect2 = button.parts.normal.rect
		for part: Dictionary in button.parts.values():
			if not part.is_empty(): bounds = bounds.merge(part.rect)
		button.position = bounds.position
		button.size = bounds.size
		var tip := owner.profile.text(str(owner._controls.get(control, {}).get("ToolTip", "")))
		button.tooltip_text = tip if not tip.begins_with("Ctrl") else ""
		return button

	func _ready() -> void:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var mode := get_draw_mode()
		var pushed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		_piece(parts.pressed if pushed and not parts.pressed.is_empty() else parts.normal)
		if mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED: _piece(parts.hover_pressed if pushed else parts.hover)

	func _piece(part: Dictionary) -> void:
		if part.is_empty(): return
		draw_texture_rect_region(part.texture, Rect2(part.rect.position - position, part.rect.size), part.source)
