class_name ELFirstTutorialPanel
extends Control
## First game's tutorial panel (Controls "Tutorial"): the event's caption and
## text, Back / Forward through the shown events of this screen, Close and
## Clear, and scroll arrows for a text taller than the panel. Buttons use the
## original CutParts art at their registry places; the frames are painted (the
## original paints them procedurally). Layout measured on original captures at
## 1024x768 (mission 1 opening and the first battle hint): a fixed outer frame
## around the registry panel, and an inner text box centred on it that fits
## the wrapped text (caption in bold Arial 18, body Arial 15, both with
## a dark shadow). While it is open it takes every click and key of the screen
## below. Keys: Esc closes, Left / Right browse. Design units are the 1024x768
## layout.
##
## Adventure use also watches the map: watch_adventure() connects the session
## events and the opened windows to their tutorial events.

signal closed

const DESIGN := Vector2(1024, 768)
## Registry panel rectangle (800 layout 100,40 600x530) and its children,
## relative to the panel's top-left corner.
const PANEL := Vector2(600, 530)
## Registry panel position in the 1024x768 layout (800 layout + ShiftX/Y).
const PANEL_AT := Vector2(212, 124)
## TuCaption width and TuText wrap width / scroll limit. The original wraps at
## TuText's 560 px with hinted GDI Arial, whose advances run about 2% wider
## than the outline metrics used here; 546 reproduces its line breaks on the
## captured hints (breaks fall between 540 and 552 outline units).
const CAPTION_WIDTH := 400.0
const TEXT_WIDTH := 546.0
const TEXT_MAX_HEIGHT := 384.0
## Measured on the original (relative to the panel): outer frame, the inner
## box's centre, the text block's horizontal centre, box padding and the gap
## between the caption and the body.
const FRAME := Rect2(-31, -16, 662, 562)
const BOX_CENTRE_Y := 240.0
const TEXT_CENTRE_X := 297.0
const BOX_PAD_LEFT := 24.0
const BOX_PAD_RIGHT := 30.0
const BOX_PAD_TOP := 18.0
const BOX_PAD_BOTTOM := 35.0
const CAPTION_GAP := 15.0
const CAPTION_SIZE := 18
const TEXT_SIZE := 15
const LINE_PITCH := 17.0
const BUTTONS := {"TuClose": Vector2(-5, 477), "TuClear": Vector2(105, 477), "TuBack": Vector2(485, 477), "TuForward": Vector2(555, 477)}
const ARROWS := {"TuScrollU": Vector2(589, 7), "TuScrollD": Vector2(589, 461)}
const CAPTION_INK := Color8(214, 187, 136)
const TEXT_INK := Color8(214, 187, 136)
const SHADOW := Color(0, 0, 0, 0.85)
const FRAME_FILL := Color8(49, 57, 57)
const FRAME_EDGE := Color8(145, 128, 108)
const FRAME_LIGHT := Color8(214, 198, 156)
const FRAME_DARK := Color8(33, 24, 16)
const BOX_FILL := Color8(24, 33, 33)
const BOX_EDGE := Color8(123, 107, 90)
const BOX_OUTLINE := Color8(41, 41, 41)

var tutorial: ELFirstTutorial
var profile: ELProfile
var category := ELFirstTutorial.ADVENTURE
var caption: Label
var body: RichTextLabel
var buttons: Dictionary = {}
var sound: AudioStreamPlayer
var font: Font
var caption_font: Font
## Panel rectangle in design units (registry place), the inner text box
## relative to it (fitted to the text) and whether the text scrolls.
var panel := Rect2(PANEL_AT, PANEL)
var box := Rect2()
var scrolling := false
var _art: Dictionary = {}
var _volume := 1.0
var _text_height := 0.0
## Adventure watching: the view and the windows already reported.
var _view: Node
var _windows: Dictionary = {}

func build(source: ELProfile, shared: ELFirstTutorial, screen: int) -> void:
	profile = source
	tutorial = shared
	category = screen
	name = "FirstTutorial"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sans := SystemFont.new()
	sans.font_names = PackedStringArray(["Arial", "Liberation Sans", "DejaVu Sans", "Noto Sans", "sans-serif"])
	font = sans
	var bold := SystemFont.new()
	bold.font_names = sans.font_names
	bold.font_weight = 700
	caption_font = bold
	_load_art()
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", caption_font)
	caption.add_theme_color_override("font_color", CAPTION_INK)
	caption.add_theme_color_override("font_shadow_color", SHADOW)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	body = RichTextLabel.new()
	body.bbcode_enabled = false
	body.scroll_active = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_theme_font_override("normal_font", font)
	body.add_theme_color_override("default_color", TEXT_INK)
	body.add_theme_color_override("font_shadow_color", SHADOW)
	body.add_theme_constant_override("shadow_offset_x", 1)
	body.add_theme_constant_override("shadow_offset_y", 1)
	body.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	body.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)
	for control: String in ["TuClose", "TuClear", "TuBack", "TuForward", "TuScrollU", "TuScrollD"]:
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		for style in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		var tip := ""
		for row: Dictionary in profile.table("Controls").values():
			if row.get("Name") == control and row.has("ToolTip"): tip = profile.text(str(row.ToolTip))
		button.tooltip_text = "" if tip.begins_with("Ctrl") else tip
		button.name = control
		for each: Signal in [button.mouse_entered, button.mouse_exited, button.button_down, button.button_up]: each.connect(queue_redraw)
		add_child(button)
		buttons[control] = button
	buttons.TuClose.pressed.connect(close)
	# Clear shows the intro screens again through the tutorial's signal.
	buttons.TuClear.pressed.connect(func(): tutorial.clear(category))
	buttons.TuBack.pressed.connect(func(): if tutorial.back(): _fill())
	buttons.TuForward.pressed.connect(func(): if tutorial.forward(): _fill())
	buttons.TuScrollU.pressed.connect(scroll.bind(-1))
	buttons.TuScrollD.pressed.connect(scroll.bind(1))
	sound = AudioStreamPlayer.new()
	add_child(sound)
	tutorial.shown.connect(func(shown_category: int): if shown_category == category: present())
	resized.connect(_layout)
	hide()

## Effects volume (0..1) for the opening sound.
func set_volume(value: float) -> void:
	_volume = value

## Fires an event of this screen; the panel opens when the tutorial shows it.
func fire(event_name: String) -> bool:
	return tutorial != null and tutorial.fire(event_name, category)

## H: this screen's shown events, or both intro screens when there are none.
func open_history() -> bool:
	return tutorial != null and tutorial.open_history(category)

## Shows the tutorial's current entry, with the original opening sound.
func present() -> void:
	if tutorial == null or tutorial.current_id() < 0: return
	show()
	move_to_front()
	_fill()
	var stream := ELAudio.sound(profile, ELFirstTutorial.SOUND)
	if stream != null:
		sound.stream = stream
		sound.volume_db = linear_to_db(maxf(_volume, 0.0001))
		sound.play()

func close() -> void:
	if not visible: return
	hide()
	closed.emit()

## Keys while the panel is open (all of them stop here). Returns true when
## the event was taken.
func handle_input(event: InputEvent) -> bool:
	if not visible: return false
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE: close()
			KEY_LEFT: if tutorial.back(): _fill()
			KEY_RIGHT: if tutorial.forward(): _fill()
			KEY_UP: scroll(-1)
			KEY_DOWN: scroll(1)
		get_viewport().set_input_as_handled()
		return true
	return event is InputEventKey or event is InputEventMouse

func scroll(step: int) -> void:
	var bar := body.get_v_scroll_bar()
	bar.value = clampf(bar.value + step * body.get_theme_font_size("normal_font_size") * 3, 0, bar.max_value)

func shown_caption() -> String:
	return caption.text if caption != null else ""

func shown_text() -> String:
	return body.text.replace(WORD_JOINER, "") if body != null else ""

## The original breaks lines only at spaces ("(<Esc>-меню)" stays whole); a
## word joiner after an inner hyphen keeps the label from breaking there.
const WORD_JOINER := "\u2060"

static func no_hyphen_breaks(value: String) -> String:
	var regex := RegEx.create_from_string("-(?=\\S)")
	return regex.sub(value, "-" + WORD_JOINER, true)

func design_scale() -> float:
	return maxf(1.0, minf(size.x / DESIGN.x, size.y / DESIGN.y)) if size.x > 0 and size.y > 0 else 1.0

## Screen rectangle of a design rectangle given relative to the panel (the
## 1024x768 layout is centred in larger windows).
func screen_rect(local: Rect2) -> Rect2:
	var s := design_scale()
	var origin := (size - DESIGN * s) * 0.5 + panel.position * s
	return Rect2(origin + local.position * s, local.size * s)

## The painted outer frame on screen.
func frame_rect() -> Rect2:
	return screen_rect(FRAME)

func _fill() -> void:
	var entry := ELFirstTutorial.texts(profile, tutorial.current_id())
	caption.text = entry.caption
	body.text = no_hyphen_breaks(entry.body)
	body.scroll_to_line(0)
	_layout()

func _layout() -> void:
	if body == null: return
	var s := design_scale()
	caption.add_theme_font_size_override("font_size", roundi(CAPTION_SIZE * s))
	body.add_theme_font_size_override("normal_font_size", roundi(TEXT_SIZE * s))
	# The body wraps at TuText's width; the box fits the widest line and the
	# text height up to the scroll limit, centred on the panel.
	# Measured at the drawn size so the label wraps the same way.
	var drawn_size := roundi(TEXT_SIZE * s)
	var measured := font.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, TEXT_WIDTH * s, drawn_size) / s
	# The original's line pitch is 17 px (the outline font's height is ~17.3).
	var line_height := font.get_height(drawn_size) / s
	var lines := maxi(1, roundi(measured.y / line_height))
	var separation := roundi((LINE_PITCH - line_height) * s)
	body.add_theme_constant_override("line_separation", separation)
	_text_height = lines * (line_height + separation / s) + 2.0
	scrolling = _text_height > TEXT_MAX_HEIGHT
	var text_height := minf(_text_height, TEXT_MAX_HEIGHT)
	var text_width := minf(maxf(measured.x, 120.0), TEXT_WIDTH)
	var caption_height := caption_font.get_height(CAPTION_SIZE)
	var box_height := BOX_PAD_TOP + caption_height + CAPTION_GAP + text_height + BOX_PAD_BOTTOM
	var text_left := TEXT_CENTRE_X - text_width * 0.5
	box = Rect2(text_left - BOX_PAD_LEFT, BOX_CENTRE_Y - box_height * 0.5, text_width + BOX_PAD_LEFT + BOX_PAD_RIGHT, box_height)
	var caption_rect := screen_rect(Rect2(text_left, box.position.y + BOX_PAD_TOP, CAPTION_WIDTH, caption_height))
	caption.position = caption_rect.position
	caption.size = caption_rect.size
	# A little slack keeps the label's wrapping identical to the measurement.
	var text_rect := screen_rect(Rect2(text_left, box.position.y + BOX_PAD_TOP + caption_height + CAPTION_GAP, text_width + 6.0, text_height))
	body.position = text_rect.position
	body.size = text_rect.size
	for control: String in BUTTONS:
		var button: Button = buttons[control]
		var rect := screen_rect(Rect2(BUTTONS[control], Vector2(50, 50)))
		button.position = rect.position
		button.size = rect.size
	# Back and Forward: hidden with a single entry, disabled at the ends.
	var several := tutorial != null and tutorial.shown_list.size() > 1
	buttons.TuBack.visible = several
	buttons.TuForward.visible = several
	buttons.TuBack.disabled = tutorial == null or not tutorial.can_back()
	buttons.TuForward.disabled = tutorial == null or not tutorial.can_forward()
	for control: String in ARROWS:
		var arrow: Button = buttons[control]
		var rect := screen_rect(Rect2(ARROWS[control], Vector2(13, 12)))
		arrow.position = rect.position
		arrow.size = rect.size
		arrow.visible = scrolling
	queue_redraw()

func _load_art() -> void:
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[definition.get("Name", "")] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("CutParts").values():
		var control := str(row.get("Ctrl", ""))
		if not control.begins_with("Tu"): continue
		var masks: Variant = row.get("Msk", [])
		var list: Array = masks if masks is Array else [masks]
		var state := "free"
		if list.has("Light"): state = "light_push" if list.has("Push") else "light"
		elif list.has("Push"): state = "push"
		elif list.has("Disabled"): state = "disabled"
		var texture := profile.texture(paths.get(row.get("Txt", ""), ""))
		if texture == null: continue
		var home: Vector2 = BUTTONS.get(control, ARROWS.get(control, Vector2.ZERO))
		# CutParts positions are 800-layout screen points; keep the offset of
		# each piece from its control's home (the glow sits 8-9 px inside).
		var origin := Vector2(float(row.ScrL), float(row.ScrT)) - Vector2(100, 40)
		_art[control + ":" + state] = {"texture": texture, "source": Rect2(row.TxtL, row.TxtT, row.TxtW, row.TxtH), "offset": origin - home, "size": Vector2(row.TxtW, row.TxtH)}

func _draw() -> void:
	if body == null: return
	var s := design_scale()
	_draw_frames(s)
	for control: String in buttons:
		var button: Button = buttons[control]
		if not button.visible: continue
		var mode := button.get_draw_mode()
		var base := "free"
		if button.disabled: base = "disabled"
		elif mode in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]: base = "push"
		var piece: Dictionary = _art.get(control + ":" + base, _art.get(control + ":free", {}))
		_draw_piece(piece, button.position, s)
		if not button.disabled and mode in [BaseButton.DRAW_HOVER, BaseButton.DRAW_HOVER_PRESSED, BaseButton.DRAW_PRESSED]:
			_draw_piece(_art.get(control + (":light_push" if base == "push" else ":light"), {}), button.position, s)

## Outer frame: opaque slate with a bevelled tan edge (light outer line, dark
## inner line); inner box: darker fill with a thin tan edge.
func _draw_frames(s: float) -> void:
	var frame := frame_rect()
	var edge := maxi(1, roundi(4 * s))
	draw_style_box(_flat(FRAME_FILL, FRAME_EDGE, edge), frame)
	draw_style_box(_flat(Color(0, 0, 0, 0), FRAME_LIGHT, 1), frame)
	draw_style_box(_flat(Color(0, 0, 0, 0), FRAME_DARK, 1), frame.grow(-edge))
	var inner := screen_rect(box)
	draw_style_box(_flat(Color(0, 0, 0, 0), BOX_OUTLINE, 1), inner.grow(1))
	draw_style_box(_flat(BOX_FILL, BOX_EDGE, 1), inner)

static func _flat(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = fill.a > 0.0
	style.border_color = border
	style.set_border_width_all(width)
	return style

func _draw_piece(piece: Dictionary, at: Vector2, s: float) -> void:
	if piece.is_empty(): return
	draw_texture_rect_region(piece.texture, Rect2(at + piece.offset * s, piece.size * s), piece.source)

# --- Adventure events ------------------------------------------------------------

## Connects a first-game map: session events (day start, building use,
## captures, heroes lost, levels) and the windows it opens.
func watch_adventure(view: Node) -> void:
	_view = view
	var state: ELAdventureSession = view.state
	state.event.connect(_session_event)
	set_process(true)

func _session_event(data: Dictionary) -> void:
	if _view == null: return
	var state: ELAdventureSession = _view.state
	var local := state.current_player
	match str(data.get("kind", "")):
		"day_changed": fire("ADVENTURE_SCREEN")
		"building_used": if int(data.get("player", -1)) == local: fire("USE_ADDITIONAL_BUILDING")
		"site_captured": if int(data.get("player", -1)) == local and int(data.get("previous", -1)) != local: fire("TAKE_MINE")
		"object_killed":
			var item := state.object(int(data.get("id", -1)))
			if item.get("type") == "hero" and int(item.get("owner", -1)) == local: fire("HERO_DEATH")
		"experience_gained":
			if int(data.get("levels", 0)) > 0 and int(state.object(int(data.get("id", -1))).get("owner", -1)) == local: fire("LEVEL_UP")

## The map click of a hero order: own hero (selected), own castle, and the
## monster, enemy hero or fort an order was given against.
func map_click(site: Dictionary, ordered: bool) -> void:
	if _view == null or site.is_empty(): return
	var local: int = _view.state.current_player
	var owner := int(site.get("owner", -1))
	if site.get("type") == "hero" and owner == local: fire("HERO_CLICK")
	elif ELFirstScenario.is_castle(site) and owner == local: fire("CASTLE_CLICK")
	elif not ordered: return
	elif site.get("type") == "monster": fire("MONSTER_CLICK")
	elif site.get("type") == "hero": fire("ENEMY_HERO_CLICK")
	elif site.get("type") == "fort": fire("FORT_ATTACK_OR_USE")

func _process(_delta: float) -> void:
	if _view == null: return
	# Windows the original reports when they open.
	var hero_screen: Variant = _view.get("hero_screen")
	var open := {"first_shop": "OPEN_SPELL_SHOP", "rune_shop": "OPEN_COMPONENT_SHOP", "global_spells": "OPEN_GLOBAL_SPELLS_SCREEN",
		"hero_screen": "OPEN_EXCHANGE_SCREEN" if hero_screen is Object and is_instance_valid(hero_screen) and hero_screen.get("exchange") == true else "OPEN_HERO_SCREEN"}
	for key: String in open:
		var window: Variant = _view.get(key)
		var id: int = window.get_instance_id() if window is Object and is_instance_valid(window) else 0
		if id != 0 and _windows.get(key, 0) != id: fire(open[key])
		_windows[key] = id
