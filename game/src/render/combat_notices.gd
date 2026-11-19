class_name ELCombatNotices
extends Control
## The combat screen's original notices, drawn over the battle:
## - the phase banner (option CombatPhases): «АТАКА», «ЗАЩИТА» or
##   «ХОД ПРОТИВНИКА» from Interface/combat_text_1 (left half) and _2 (right
##   half), three 85 px bands. It grows in from 300% over 250 ms, holds for
##   1 s (Buttons/Begin_Combat.wav plays as it settles) and shrinks to 90% over
##   250 ms. The banner is half the screen wide, centred 50 px above the middle.
##   The first game tints its white art (a dark outline, then a pale fill) and
##   fades it in and out. The second game's art is coloured and has no fade.
## - first game: the cast message list (option CastMessages, also ShowChat),
##   top left. Each line holds 3 s, then fades over 0.5 s while the list
##   slides up.
## - first game: cast spells from both heroes as icons, marked by caster.
##   The second game clears the list when a new side acts or a turn starts,
##   and adds ability, ether disturbance and specialisation icons.
##   There are 5 per row at a 53 px step. The first game's "cast_icons"
##   setting enables this list with its own list border (ELListLook.HOVER).
## Approximations: list and icon origins, and the line font.

const BAND := 85.0
const GROW := 0.25
const HOLD := 1.0
const SHRINK := 0.25
const OUTLINE := Color8(0x0f, 0x1f, 0x37)
const FILL := Color8(0xdf, 0xf4, 0xf9)
const HOLD_LINE := 3.0
const FADE_LINE := 0.5
const MAX_CHAT_LINES := 5
const LINE_HEIGHT := 18.0
const ICON := 50.0
const ICON_STEP := 53.0
const ICON_ROW := 5
const ORIGIN := Vector2(12, 8)
const OWN_CAST := Color("65e0e0")
const RIVAL_CAST := Color("ff9973")
## Etherlords II SPELLS_37, column 3. The original's icon builders
## (0x568469 and 0x568818) use separate cells for each side.
const OWN_DISTURBANCE_ICON := 915
const RIVAL_DISTURBANCE_ICON := 916
const OWN_SPECIALISATION_ICON := 918
const RIVAL_SPECIALISATION_ICON := 917

var profile: ELProfile
var halves: Array[Texture2D] = []
## Banner: band index (0 attack, 1 defence, 2 enemy turn) and its age, -1 when idle.
var banner := -1
var banner_age := 0.0
var _sounded := false
## First game message lines: {"text", "colour", "age"}.
var lines: Array = []
## Battle icons: texture, side and either a card or an explicit tooltip.
var icons: Array = []
var _turn_side := -1
var _turn_serial := -1
var viewer_side := 0:
	set(side):
		if viewer_side == side: return
		viewer_side = side
		queue_redraw()
## The icons' frame drawn over each icon: WORLD_SYMBOLS_MAP (140,0)-(190,50),
## or, in the first game, its list border (already cut to 50x50).
var frame: Texture2D
var _frame_region := Rect2(140, 0, 50, 50)
## Tooltip text for a cast card (the hand's card tooltip).
var describe_card: Callable
var _font: SystemFont
## The combat panel's scale (the HUD's 800x600 layout factor); lines and icons follow it.
var ui_scale := 1.0:
	set(value):
		if ui_scale == value: return
		ui_scale = value
		queue_redraw()

func _init() -> void:
	set_process(false)
	# Only the icons take the mouse (see _has_point), for their spell tooltips.
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	_font.font_weight = 700

func _ready() -> void:
	set_process(banner >= 0 or not lines.is_empty())

func build(source: ELProfile) -> void:
	profile = source
	halves.clear()
	if profile != null:
		for index in [1, 2]:
			var texture := profile.texture("Interface/combat_text_%d" % index)
			if texture != null: halves.append(texture)
		frame = null
		for row: Dictionary in profile.table("InterfaceTextures").values():
			if row.get("Name", "") == "WORLD_SYMBOLS_MAP":
				frame = profile.texture("Interface/" + str(row.get("Path", "")).replace("\\", "/"))
		_frame_region = Rect2(140, 0, 50, 50)
		if frame == null:
			var border := ELListLook.load(profile).hover
			if border != null:
				frame = border.atlas
				_frame_region = border.region
	clear()

func clear() -> void:
	banner = -1
	banner_age = 0.0
	lines.clear()
	icons.clear()
	_turn_side = -1
	_turn_serial = -1
	set_process(false)
	queue_redraw()

func show_banner(band: int) -> void:
	if halves.size() < 2: return
	banner = clampi(band, 0, 2)
	banner_age = 0.0
	_sounded = false
	set_process(true)
	queue_redraw()

func add_line(text: String, colour: Color, chat := false) -> void:
	if text.strip_edges().is_empty(): return
	if chat and lines.filter(func(line: Dictionary) -> bool: return line.chat).size() >= MAX_CHAT_LINES:
		lines.remove_at(lines.find_custom(func(line: Dictionary) -> bool: return line.chat))
	lines.append({"text": text.strip_edges(), "colour": colour, "age": 0.0, "chat": chat})
	set_process(true)
	queue_redraw()

func add_icon(texture: Texture2D, card: String, side: int, tooltip := "") -> void:
	_add_icon({"texture": texture, "card": card, "side": side, "tooltip": tooltip})

func add_disturbance(side: int) -> void:
	_add_sided_icon(OWN_DISTURBANCE_ICON, RIVAL_DISTURBANCE_ICON, side, profile.text("ETHER_DISTURBANCE_SELF_Tt"), profile.text("ETHER_DISTURBANCE_ENEMY_Tt"))

func add_specialisation(side: int, tooltip: String) -> void:
	_add_sided_icon(OWN_SPECIALISATION_ICON, RIVAL_SPECIALISATION_ICON, side, tooltip, tooltip)

func _add_sided_icon(own: int, rival: int, side: int, tooltip: String, rival_tooltip: String) -> void:
	_add_icon({"texture": profile.icon_at(own), "rival_texture": profile.icon_at(rival), "card": "", "side": side,
		"tooltip": tooltip, "rival_tooltip": rival_tooltip})

func _add_icon(icon: Dictionary) -> void:
	var texture: Texture2D = icon.texture
	if texture == null or (texture is AtlasTexture and texture.atlas == null): return
	icons.append(icon)
	queue_redraw()

func clear_icons() -> void:
	icons.clear()
	queue_redraw()

func show_turn(side: int, serial: int) -> void:
	if side < 0 or (side == _turn_side and serial == _turn_serial): return
	_turn_side = side
	_turn_serial = serial
	clear_icons()

func _process(delta: float) -> void:
	var changed := false
	if banner >= 0:
		var previous := banner_age
		banner_age += delta
		changed = previous < GROW or banner_age >= GROW + HOLD
		if not _sounded and banner_age >= GROW:
			_sounded = true
			if profile != null: ELUiSounds.play(profile, "Buttons/Begin_Combat.wav")
		if banner_age >= GROW + HOLD + SHRINK: banner = -1
	# Retain the array and compact survivors in place. Most frames are in
	# the unchanged hold period; only a fade or banner transition redraws.
	var count := 0
	for line: Dictionary in lines:
		line.age = float(line.age) + delta
		if float(line.age) >= HOLD_LINE: changed = true
		if float(line.age) < HOLD_LINE + FADE_LINE:
			lines[count] = line
			count += 1
	if count != lines.size(): lines.resize(count)
	if changed and is_visible_in_tree(): queue_redraw()
	if banner < 0 and lines.is_empty(): set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or (what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree()):
		queue_redraw()

## The banner's scale in percent and its alpha (0..1) at `age` seconds.
static func banner_frame(age: float) -> Vector2:
	var ms := age * 1000.0
	if ms < GROW * 1000.0: return Vector2(37500.0 / (ms + 125.0), ms / (GROW * 1000.0))
	if ms < (GROW + HOLD) * 1000.0: return Vector2(100.0, 1.0)
	var t := minf(ms - (GROW + HOLD) * 1000.0, SHRINK * 1000.0)
	return Vector2(225000.0 / (t + 2250.0), 1.0 - t / (SHRINK * 1000.0))

func banner_rect() -> Rect2:
	var view := get_viewport_rect().size
	var frame := banner_frame(banner_age)
	var width := view.x * 0.5 * frame.x / 100.0
	var height := width * BAND / 512.0
	return Rect2(view.x * 0.5 - width * 0.5, view.y * 0.5 - height * 0.5 - 50.0, width, height)

func _draw() -> void:
	if banner >= 0 and halves.size() >= 2: _draw_banner()
	var k := maxf(ui_scale, 0.5)
	var y := ORIGIN.y * k
	if not icons.is_empty(): y = icon_rect(icons.size() - 1).end.y + (ICON_STEP - ICON) * k
	for line: Dictionary in lines:
		var age := float(line.age)
		var fade := clampf((age - HOLD_LINE) / FADE_LINE, 0.0, 1.0)
		var colour: Color = line.colour
		colour.a = 1.0 - fade
		var at := Vector2(ORIGIN.x * k, y + (14.0 - fade * LINE_HEIGHT) * k)
		var font_size := int(round(14.0 * k))
		draw_string_outline(_font, at, String(line.text), HORIZONTAL_ALIGNMENT_LEFT, 768.0 * k, font_size, 3, Color(0, 0, 0, colour.a))
		draw_string(_font, at, String(line.text), HORIZONTAL_ALIGNMENT_LEFT, 768.0 * k, font_size, colour)
		y += LINE_HEIGHT * k * (1.0 - fade)
	# Older rows scroll above the view. Keep their history for tooltips and
	# ordering, but submit only the rows which can touch the viewport.
	var visible_icons := visible_icon_range()
	for index in range(visible_icons.x, visible_icons.y):
		var icon: Dictionary = icons[index]
		var cell := icon_rect(index)
		draw_texture_rect(icon_texture(index), cell, false)
		if frame != null: draw_texture_rect_region(frame, cell, _frame_region)
		if profile == null or profile.id != "el1": continue
		# The bars differ in position as well as colour. Keep the art legible.
		var own: bool = icon.side == viewer_side
		var edge := Vector2(cell.position.x, cell.end.y - 3.0 * k if own else cell.position.y)
		draw_rect(Rect2(edge, Vector2(cell.size.x, 3.0 * k)), OWN_CAST if own else RIVAL_CAST)

func icon_texture(index: int) -> Texture2D:
	var icon: Dictionary = icons[index]
	return icon.texture if icon.side == viewer_side else icon.get("rival_texture", icon.texture)

func icon_column_right() -> float:
	return (ORIGIN.x + (ICON_ROW - 1) * ICON_STEP + ICON) * maxf(ui_scale, 0.5)

## Icon `index`'s place: rows of five; past five rows the list moves up a row
## per extra row, as in the original.
func icon_rect(index: int) -> Rect2:
	var k := maxf(ui_scale, 0.5)
	var over := maxi(0, (icons.size() + ICON_ROW - 1) / ICON_ROW - 5)
	var cell := ORIGIN + Vector2((index % ICON_ROW) * ICON_STEP, (index / ICON_ROW - over) * ICON_STEP)
	return Rect2(cell * k, Vector2(ICON, ICON) * k)

func _icon_at(at: Vector2) -> int:
	var k := maxf(ui_scale, 0.5)
	var cell := (at / k - ORIGIN) / ICON_STEP
	var column := floori(cell.x)
	if column < 0 or column >= ICON_ROW: return -1
	var over := maxi(0, (icons.size() + ICON_ROW - 1) / ICON_ROW - 5)
	var index := (floori(cell.y) + over) * ICON_ROW + column
	if index < 0 or index >= icons.size(): return -1
	return index if icon_rect(index).has_point(at) else -1

## [first, end) of rows which can intersect the viewport. Include the
## preceding row: its final five design pixels remain visible at the top.
func visible_icon_range() -> Vector2i:
	var over := maxi(0, (icons.size() + ICON_ROW - 1) / ICON_ROW - 5)
	var rows := ceili(maxf(get_viewport_rect().size.y / maxf(ui_scale, 0.5) - ORIGIN.y, 0.0) / ICON_STEP)
	return Vector2i(maxi(0, over - 1) * ICON_ROW, mini(icons.size(), (over + rows) * ICON_ROW))

func _has_point(point: Vector2) -> bool:
	return _icon_at(point) >= 0

func _get_tooltip(at: Vector2) -> String:
	var index := _icon_at(at)
	if index < 0: return ""
	var icon: Dictionary = icons[index]
	var tooltip: String = icon.tooltip if icon.side == viewer_side else icon.get("rival_tooltip", icon.tooltip)
	if not tooltip.is_empty(): return tooltip
	return String(describe_card.call(String(icon.card))) if describe_card.is_valid() and not String(icon.card).is_empty() else ""

func _draw_banner() -> void:
	var rect := banner_rect()
	var source_y := banner * BAND
	var half := Rect2(rect.position, Vector2(rect.size.x * 0.5, rect.size.y))
	var first := profile != null and profile.id == "el1"
	var alpha := banner_frame(banner_age).y if first else 1.0
	var source := Rect2(0, source_y, 256, BAND)
	# Both halves' outlines go down before either fill: the right half's outline
	# shifted one pixel left would otherwise draw a dark line over the left
	# half's fill where the halves meet.
	if first:
		var outline := Color(OUTLINE, alpha)
		for index in 2:
			var target := Rect2(half.position + Vector2(half.size.x * index, 0), half.size)
			for offset: Vector2 in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
				draw_texture_rect_region(halves[index], Rect2(target.position + offset, target.size), source, outline)
	for index in 2:
		var target := Rect2(half.position + Vector2(half.size.x * index, 0), half.size)
		draw_texture_rect_region(halves[index], target, source, Color(FILL, alpha) if first else Color.WHITE)
