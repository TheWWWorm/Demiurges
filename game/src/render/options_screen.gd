class_name ELOptionsScreen
extends RefCounted
## Original Options screen (both games) on the ELFrontMenu canvas: the general
## and combat pages (CutParts group Options, Type2 general / Type1 combat),
## their checkboxes and sliders, the page tabs and OK / Cancel. The first game
## adds the general page's Save / Load / Main menu / Quit / Objectives buttons
## and the combat page's Surrender.
## Values are edited on a copy of the active edition's ELSettings; OK stores
## them, Cancel (or Esc) drops them. Volume sliders are heard while dragged.
## Options without a remake system are kept and saved but have no effect; their
## tooltip says so.
## Approximations: slider travel 140 px; caption placement beside each box.

const NO_EFFECT := "No effect in the remake yet."
const THUMB := Rect2(241, 123, 6, 24)
const TRAVEL := 140.0
const ACTIVE_TAB := Color("fff0c8")
const IDLE_TAB := Color("a89c80")
const HEADING := Color("c9b07a")
const CAPTION := Color("e2d8bf")

## Per edition: page panels / masks, checkbox control -> setting key, sliders
## (800x600 origin or Fake control, setting key, kind) and the keys that have
## no remake system.
const SPEC := {
	"el1": {
		"tabs": {"general": "ShowGeneralOptions", "combat": "ShowCombatOptions"},
		"ok": "OptionsOK", "cancel": "OptionsCancel",
		"panels": {"general": "GeneralOptions", "combat": "CombatOptions"},
		"checks": {"Autosave": "autosave", "AdvAccelerated": "adventure_fast", "AudioReverse": "audio_reverse",
			"AnimatedObjects": "animated_objects", "FogAnimations": "fog_animations", "AmbientSounds": "ambient_sounds",
			"ShowBlazons": "show_blazons", "ShowTutorial": "show_tutorial", "ShowChat": "show_chat",
			"UseSpells": "use_spells", "AutoCamera": "auto_camera", "HideMotion": "hide_motion", "HideAnimations": "hide_cast",
			"CombatPhases": "combat_phases", "HeroesCasting": "heroes_casting", "HeroesVoices": "heroes_voices",
			"ShowCreatureNumbers": "creature_numbers", "ShowIcons": "ability_icons", "NumbersOnCamera": "numbers_on_camera",
			"Order": "attack_order", "DrawBlood": "blood", "VisualLog": "visual_log"},
		"sliders": {
			"general": [[Vector2(200, 152), "mouse_scroll", "multiplier"], [Vector2(200, 208), "mouse_rotation", "multiplier"],
				[Vector2(200, 264), "keyboard_scroll", "multiplier"], [Vector2(200, 320), "keyboard_rotation", "multiplier"],
				[Vector2(463, 152), "music", "volume"], [Vector2(463, 208), "effects", "volume"], [Vector2(200, 418), "gamma", "gamma"]],
			"combat": [[Vector2(200, 453), "auto_camera_dynamics", "percent"]]},
		"commands": {"general": ["GOQuit", "GOMenu", "GOSave", "GOLoad", "GOInfo"], "combat": ["Surrender"]},
		# Multiplayer only: shown with its Disabled art.
		"disabled": ["ShowChat"],
	},
	"el2": {
		"tabs": {"general": "OP_ShowGen", "combat": "OP_ShowCom"},
		"ok": "OP_OK", "cancel": "OP_Cancel",
		"masks": {"general": "Type2", "combat": "Type1"},
		"checks": {"OPG_InvertRotation": "invert_rotation", "OPG_AmbientSounds": "ambient_sounds", "OPG_AudioReverse": "audio_reverse",
			"OPG_Autosave": "autosave", "OPG_AcceleratedMode": "adventure_fast", "OPG_AnimatedObjects": "animated_objects",
			"OPG_MouseOverTooltips": "map_tooltips", "OPC_CombatPhases": "combat_phases", "OPC_HeroesCasting": "heroes_casting",
			"OPC_HeroesVoices": "heroes_voices", "OPC_PowerToughness": "creature_numbers", "OPC_AbilitiesIcons": "ability_icons",
			"OPC_AttackersBlockers": "attack_order", "OPC_NumbersClose": "numbers_on_camera", "OPC_BloodStains": "blood",
			"OPC_HideMovement": "hide_motion", "OPC_HideCastMotions": "hide_cast", "OPC_AutomaticCamera": "auto_camera",
			"OPC_Autosave": "visual_log"},
		"sliders": {
			"general": [["OPG_MRotSpdSlider", "mouse_rotation", "multiplier"], ["OPG_KRotSpdSlider", "keyboard_rotation", "multiplier"],
				["OPG_MVolSlider", "music", "volume"], ["OPG_SVolSlider", "effects", "volume"], ["OPG_GammaSlider", "gamma", "gamma"]],
			"combat": [["OPC_AutoCamDynSlider", "auto_camera_dynamics", "percent"]]},
		"commands": {"general": [], "combat": []},
		"disabled": [],
	},
}
## Settings with no remake system (stored only). The second game's Autosave
## has no effect in the original either (its only reader arms a field nothing
## reads; the after-chapter autosave is unconditional), so it is not marked;
## the first game's is the end-of-turn autosave. Mouse scroll is the first
## game's edge-pan speed; the second game's edges only turn the view.
## VisualLog writes a plain-text duel log file. The second game's CastMessages has no reader
## besides this screen. FogAnimations animates the first game's ether-mist
## texture, which the remake's plain fog dimming does not draw; HideMotion
## speeds up creatures walking to their attack places, which the remake's
## short strike lunge does not have. ShowChat is multiplayer only.
const INERT := ["fog_animations",
	"show_chat", "hide_motion", "visual_log"]

var menu: ELFrontMenu
var page := "general"
## Where the screen is shown: "menu" (main menu), "adventure" or "combat".
var context := "menu"
var pending: Dictionary = {}
var checks: Dictionary = {}
var sliders: Dictionary = {}
var commands: Dictionary = {}
var tabs: Dictionary = {}
var remake_button: Button
## The way the last session ended: OK (true) or Cancel, and the command
## button pressed ("" for OK / Cancel).
var last_applied := false
var last_command := ""

func _init(owner: ELFrontMenu) -> void:
	menu = owner

func spec() -> Dictionary:
	return SPEC.get(menu.edition, SPEC.el1)

func art_exclude(target: String) -> Array:
	if target != "options": return []
	return ["Type2"] if page == "combat" else ["Type1"]

## Starts editing: a copy of the active edition's values, on `first_page`.
func open(where := "menu", first_page := "general") -> void:
	context = where
	page = first_page
	pending = menu.option_settings().values.duplicate()
	menu.show_screen("options")

static func inert(key: String, edition: String) -> bool:
	return key in INERT or (key == "mouse_scroll" and edition == "el2") or (key == "heroes_casting" and edition == "el2")

## Screen offset of a control: its own shift plus every parent panel's.
func shift(control: String) -> Vector2:
	var result := Vector2.ZERO
	var name := control
	for depth in 8:
		var row: Dictionary = menu._controls.get(name, {})
		if row.is_empty(): break
		result += Vector2(float(row.get("ShiftX", 0)), float(row.get("ShiftY", 0)))
		name = str(row.get("Parent", ""))
	return result

func rect(control: String) -> Rect2:
	var row: Dictionary = menu._controls.get(control, {})
	return Rect2(Vector2(float(row.get("Left", 0)), float(row.get("Top", 0))) + shift(control), Vector2(float(row.get("Width", 0)), float(row.get("Height", 0))))

## Controls of the shown page with the given registry type.
func page_controls(type: String) -> Array[String]:
	var result: Array[String] = []
	var panel: String = spec().get("panels", {}).get(page, "")
	var mask: String = spec().get("masks", {}).get(page, "")
	for row: Dictionary in menu.profile.table("Controls").values():
		if str(row.get("Type", "")) != type: continue
		var masks: Variant = row.get("Msk", [])
		if not panel.is_empty() and str(row.get("Parent", "")) == panel: result.append(str(row.Name))
		elif not mask.is_empty() and str(row.get("Parent", "")) == "Options" and (masks == mask or (masks is Array and masks.has(mask))): result.append(str(row.Name))
	return result

func build_screen() -> void:
	checks.clear()
	sliders.clear()
	commands.clear()
	tabs.clear()
	if pending.is_empty(): pending = menu.option_settings().values.duplicate()
	# The first game's slider tracks are pieces of the page panels.
	if spec().has("panels"):
		menu._add_group(spec().panels[page], [])
		menu.art.queue_redraw()
	for control: String in page_controls("Text"):
		var row: Dictionary = menu._controls[control]
		var heading := str(row.get("FontType", "")) == "Dark"
		var label := menu._label(control, menu._caption(control), rect(control), int(row.get("FontSize", 17)), HEADING if heading else CAPTION)
		label.clip_text = true
	for page_id: String in ["general", "combat"]: _tab(page_id)
	for control: String in page_controls("CheckButton"): _check(control)
	for item: Array in spec().sliders[page]: _slider(item)
	for control: String in spec().commands[page]: _command(control)
	var ok := ELFrontMenu.CutButton.make(menu, spec().ok, shift(spec().ok))
	if ok != null:
		menu.canvas.add_child(ok)
		menu.buttons[spec().ok] = ok
		ok.tooltip_text = _tip(spec().ok)
		ok.pressed.connect(accept)
	var cancel := ELFrontMenu.CutButton.make(menu, spec().cancel, shift(spec().cancel))
	if cancel != null:
		menu.canvas.add_child(cancel)
		menu.buttons[spec().cancel] = cancel
		cancel.tooltip_text = _tip(spec().cancel)
		cancel.pressed.connect(close)
	_remake_section()

func _tip(control: String) -> String:
	var key := str(menu._controls.get(control, {}).get("ToolTip", ""))
	return "" if key.is_empty() or menu.text(key) == key else menu.text(key).strip_edges()

func _tab(page_id: String) -> void:
	var control: String = spec().tabs[page_id]
	var button := Button.new()
	button.name = control
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.text = menu._caption(control)
	var area := rect(control)
	button.position = area.position
	button.size = area.size
	button.add_theme_font_override("font", menu.serif)
	button.add_theme_font_size_override("font_size", int(menu._controls.get(control, {}).get("FontSize", 20)))
	var colour := ACTIVE_TAB if page_id == page else IDLE_TAB
	for state: String in ["font_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(state, colour)
	button.add_theme_color_override("font_hover_color", ACTIVE_TAB)
	button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	button.add_theme_constant_override("shadow_offset_x", 1)
	button.add_theme_constant_override("shadow_offset_y", 1)
	for style: String in ["normal", "hover", "pressed", "focus"]: button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	button.pressed.connect(show_page.bind(page_id))
	menu.canvas.add_child(button)
	menu.buttons[control] = button
	tabs[page_id] = button

func show_page(page_id: String) -> void:
	if page_id == page: return
	page = page_id
	menu.show_screen("options")

func _check(control: String) -> void:
	var key: String = spec().checks.get(control, "")
	var box := Check.make(menu, control, shift(control))
	if box == null: return
	box.button_pressed = bool(pending.get(key, false)) if not key.is_empty() else false
	box.disabled = key.is_empty() or control in spec().disabled
	box.set_meta("setting", key)
	menu.canvas.add_child(box)
	menu.buttons[control] = box
	checks[control] = box
	var tip := _tip(control)
	if key.is_empty() or control in spec().disabled: tip = (tip + "\n" if not tip.is_empty() else "") + ELFrontMenu.UNAVAILABLE
	elif inert(key, menu.edition): tip = (tip + "\n" if not tip.is_empty() else "") + NO_EFFECT
	box.tooltip_text = tip
	box.toggled.connect(func(on: bool):
		if not key.is_empty(): pending[key] = on)
	# The caption sits right of the box, to the end of its column.
	var area := Rect2(box.position, box.size)
	var column_end := _column_end(area)
	var left := area.end.x + 7.0
	# The first game's Tutorial shares its row with Chat.
	if control == "ShowTutorial" and not menu.rows("ShowChat").is_empty(): column_end = minf(column_end, float(menu.rows("ShowChat")[0].ScrL) + shift(control).x - 6.0)
	var row: Dictionary = menu._controls.get(control, {})
	var caption := menu._label("caption_" + control, menu._caption(control), Rect2(left, area.get_center().y - 21, maxf(40.0, column_end - left), 42), int(row.get("FontSize", 17)), CAPTION, HORIZONTAL_ALIGNMENT_LEFT)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The label grew to its one-line text before wrapping was on; its minimum
	# size is refreshed before it is narrowed to the column.
	caption.update_minimum_size()
	caption.get_minimum_size()
	caption.size = Vector2(maxf(40.0, column_end - left), 42)
	caption.add_theme_constant_override("line_spacing", -4)
	if box.disabled: caption.add_theme_color_override("font_color", ELFrontMenu.INK_DISABLED)
	_fit_caption(caption)

## Right edge of the page column holding `area`: the column's section heading
## (the Dark headings span their columns).
func _column_end(area: Rect2) -> float:
	var best := area.end.x + 200.0
	var best_top := -INF
	for control: String in page_controls("Text"):
		if str(menu._controls[control].get("FontType", "")) != "Dark": continue
		var heading := rect(control)
		if area.position.x < heading.position.x - 4.0 or area.position.x >= heading.end.x: continue
		if heading.position.y > area.position.y or heading.position.y < best_top: continue
		best_top = heading.position.y
		best = heading.end.x - 6.0
	return best

## Long captions shrink until they fit two lines of their column.
func _fit_caption(label: Label) -> void:
	var font_size := label.get_theme_font_size("font_size")
	while font_size > 12:
		var lines := menu.serif.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, label.size.x, font_size).y
		if lines <= label.size.y: break
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)

func _slider(item: Array) -> void:
	var origin: Vector2
	if item[0] is Vector2: origin = item[0] + shift(spec().panels[page])
	else: origin = rect(item[0]).position
	var slider := ThumbSlider.new()
	slider.name = "slider_" + str(item[1])
	slider.menu = menu
	slider.position = origin
	slider.size = Vector2(TRAVEL + THUMB.size.x, THUMB.size.y)
	slider.value = to_slider(str(item[2]), pending.get(item[1], 0.0))
	slider.set_meta("setting", item[1])
	if inert(str(item[1]), menu.edition): slider.tooltip_text = NO_EFFECT
	slider.changed.connect(func(value: int):
		pending[item[1]] = from_slider(str(item[2]), value)
		if item[2] == "volume": menu.preview_volumes(pending))
	menu.canvas.add_child(slider)
	sliders[item[1]] = slider

## Slider position 0..100 for a stored value, and back.
static func to_slider(kind: String, value: Variant) -> int:
	match kind:
		"volume": return roundi(float(value) * 100.0)
		"multiplier": return roundi(float(value) * 50.0)
		"gamma": return roundi((float(value) + 1.0) * 50.0)
	return roundi(float(value))

static func from_slider(kind: String, value: int) -> Variant:
	match kind:
		"volume": return value / 100.0
		"multiplier": return value / 50.0
		"gamma": return value / 50.0 - 1.0
	return value

## First game: commands of the general page and Surrender on the combat page.
func _command(control: String) -> void:
	var button := ELFrontMenu.CutButton.make(menu, control, shift(control))
	if button == null: return
	menu.canvas.add_child(button)
	menu.buttons[control] = button
	commands[control] = button
	button.tooltip_text = _tip(control)
	# Main menu: as the original, only Quit is available; on the map Save,
	# Load, Main menu and the mission objectives work; in a battle only
	# Surrender.
	var enabled := false
	match control:
		"GOQuit": enabled = true
		"GOMenu", "GOSave", "GOLoad": enabled = context == "adventure"
		"GOInfo": enabled = context == "adventure" and not menu.mission_texts.is_empty()
		"Surrender": enabled = context == "combat"
	button.disabled = not enabled
	if not enabled and context != "menu":
		button.tooltip_text += ("\n" if not button.tooltip_text.is_empty() else "") + ELFrontMenu.UNAVAILABLE
	button.pressed.connect(func(): finish(true, control))

## Remake-only settings stay in the remake's dialog, below the original frame.
func _remake_section() -> void:
	remake_button = null
	if menu.settings_requested.get_connections().is_empty() or context != "menu": return
	remake_button = Button.new()
	remake_button.name = "RemakeSettings"
	remake_button.flat = true
	remake_button.focus_mode = Control.FOCUS_NONE
	remake_button.text = "Remake settings…"
	remake_button.tooltip_text = "Settings of the remake only: ambience volume, creature shadows, adventure weather, movies."
	remake_button.add_theme_font_size_override("font_size", 14)
	remake_button.add_theme_color_override("font_color", Color(ELFrontMenu.INK, 0.7))
	remake_button.position = Vector2(DESIGN_CENTRE - 80, 700)
	remake_button.size = Vector2(160, 28)
	remake_button.pressed.connect(func():
		finish(true, "")
		menu.settings_requested.emit())
	menu.canvas.add_child(remake_button)

const DESIGN_CENTRE := 512.0

## OK: the edited values become the settings (saved), then the screen closes.
func accept() -> void:
	finish(true, "")

## Cancel or Esc: the edits are dropped (previewed volumes are restored).
func close() -> void:
	finish(false, "")

func finish(apply: bool, command: String) -> void:
	var settings := menu.option_settings()
	if apply:
		for key: String in pending: settings.values[key] = pending[key]
		settings.save_file(menu.settings_path)
	else: menu.preview_volumes(settings.values)
	pending = {}
	last_command = command
	last_applied = apply
	menu.options_closed.emit(apply, command)
	# GOInfo shows the mission objectives in place of the Options screen.
	if command == "GOInfo" and menu.hosted:
		menu.show_screen("objectives")
		return
	# Over a game the host runs the command once the screen has closed.
	if command == "GOQuit" and not menu.hosted:
		menu.quit_requested.emit()
		return
	menu.leave_screen()

## Checkbox drawn from the CutParts pieces: the box, the tick when checked,
## the glow under the cursor and the dimmed box when disabled.
class Check extends BaseButton:
	var box: Dictionary = {}
	var tick: Dictionary = {}
	var glow: Dictionary = {}
	var glow_checked: Dictionary = {}
	var _origin := Vector2.ZERO

	static func make(owner: ELFrontMenu, control: String, offset: Vector2) -> Check:
		var all := owner.rows(control)
		if all.is_empty(): return null
		var button := Check.new()
		button.name = control
		ELUiSounds.bind(button, owner.profile, control)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		var first := func(required: Array, excluded: Array) -> Dictionary:
			var found := owner.rows(control, required, excluded)
			return owner.cut(found[0], offset) if not found.is_empty() else {}
		button.box = first.call(["Free"], ["Light", "Disabled"])
		if button.box.is_empty():
			for row: Dictionary in all:
				if row.masks.is_empty():
					button.box = owner.cut(row, offset)
					break
		button.tick = first.call(["Push"], ["Light", "Disabled"])
		button.glow = first.call(["Light"], ["Push"])
		button.glow_checked = first.call(["Light", "Push"], [])
		if button.glow_checked.is_empty(): button.glow_checked = button.glow
		var bounds := Rect2()
		var started := false
		for part: Dictionary in [button.box, button.tick, button.glow]:
			if part.is_empty(): continue
			bounds = part.rect if not started else bounds.merge(part.rect)
			started = true
		button._origin = bounds.position
		button.position = bounds.position
		button.size = bounds.size
		return button

	func _ready() -> void:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		toggled.connect(func(_on: bool): queue_redraw())

	func _draw() -> void:
		var tint := Color(0.55, 0.55, 0.55) if disabled else Color.WHITE
		_piece(box, tint)
		if button_pressed: _piece(tick, tint)
		var mode := get_draw_mode()
		if not disabled and (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED): _piece(glow_checked if button_pressed else glow, Color.WHITE)

	func _piece(part: Dictionary, tint: Color) -> void:
		if part.is_empty(): return
		draw_texture_rect_region(part.texture, Rect2(part.rect.position - _origin, part.rect.size), part.source, tint)

## Slider: the original thumb (OPTIONS_PANEL_12) moved over the track; a click
## or drag sets the value 0..100.
class ThumbSlider extends Control:
	signal changed(value: int)
	var menu: ELFrontMenu
	var value := 50:
		set(next):
			value = clampi(next, 0, 100)
			queue_redraw()
	var _texture: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_texture = menu.texture_named("OPTIONS_PANEL_12")

	func _gui_input(event: InputEvent) -> void:
		var pressed: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		var dragged: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if not pressed and not dragged: return
		var next := clampi(roundi((event.position.x - THUMB.size.x * 0.5) / TRAVEL * 100.0), 0, 100)
		accept_event()
		if next == value: return
		value = next
		changed.emit(value)

	func _draw() -> void:
		if _texture == null: return
		var x := roundf(value / 100.0 * TRAVEL)
		draw_texture_rect_region(_texture, Rect2(Vector2(x, 0), THUMB.size), THUMB)
