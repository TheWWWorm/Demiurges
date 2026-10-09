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
## - second game: the opponent's cast spells as icons, top left. There are 5
##   per row at a 53 px step, and new ones blink. The list is cleared when the
##   opponent's next turn starts.
## Approximations: list and icon origins, the line font, and the blink rate.

const BAND := 85.0
const GROW := 0.25
const HOLD := 1.0
const SHRINK := 0.25
const OUTLINE := Color8(0x0f, 0x1f, 0x37)
const FILL := Color8(0xdf, 0xf4, 0xf9)
const HOLD_LINE := 3.0
const FADE_LINE := 0.5
const LINE_HEIGHT := 18.0
const ICON := 50.0
const ICON_STEP := 53.0
const ICON_ROW := 5
const BLINK_TICKS := 5
const BLINK_TICK := 0.15
const ORIGIN := Vector2(12, 8)

var profile: ELProfile
var halves: Array[Texture2D] = []
## Banner: band index (0 attack, 1 defence, 2 enemy turn) and its age, -1 when idle.
var banner := -1
var banner_age := 0.0
var _sounded := false
## First game message lines: {"text", "colour", "age"}.
var lines: Array = []
## Second game enemy cast icons: {"texture", "age"}.
var icons: Array = []
var _font: SystemFont
## The combat panel's scale (the HUD's 800x600 layout factor); lines and icons follow it.
var ui_scale := 1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Arimo", "DejaVu Sans"])
	_font.font_weight = 700

func build(source: ELProfile) -> void:
	profile = source
	halves.clear()
	if profile != null:
		for index in [1, 2]:
			var texture := profile.texture("Interface/combat_text_%d" % index)
			if texture != null: halves.append(texture)
	clear()

func clear() -> void:
	banner = -1
	banner_age = 0.0
	lines.clear()
	icons.clear()
	queue_redraw()

func show_banner(band: int) -> void:
	if halves.size() < 2: return
	banner = clampi(band, 0, 2)
	banner_age = 0.0
	_sounded = false
	queue_redraw()

func add_line(text: String, colour: Color) -> void:
	if text.strip_edges().is_empty(): return
	lines.append({"text": text.strip_edges(), "colour": colour, "age": 0.0})
	queue_redraw()

func add_icon(texture: Texture2D) -> void:
	if texture == null: return
	icons.append({"texture": texture, "age": 0.0})
	queue_redraw()

func clear_icons() -> void:
	icons.clear()
	queue_redraw()

func busy() -> bool:
	return banner >= 0 or not lines.is_empty() or not icons.is_empty()

func _process(delta: float) -> void:
	if not busy(): return
	if banner >= 0:
		banner_age += delta
		if not _sounded and banner_age >= GROW:
			_sounded = true
			if profile != null: ELUiSounds.play(profile, "Buttons/Begin_Combat.wav")
		if banner_age >= GROW + HOLD + SHRINK: banner = -1
	for line: Dictionary in lines: line.age = float(line.age) + delta
	lines = lines.filter(func(line: Dictionary) -> bool: return float(line.age) < HOLD_LINE + FADE_LINE)
	for icon: Dictionary in icons: icon.age = float(icon.age) + delta
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
	for index in icons.size():
		var icon: Dictionary = icons[index]
		var tick := int(float(icon.age) / BLINK_TICK)
		if tick < BLINK_TICKS and tick % 2 == 1: continue
		var cell := (ORIGIN + Vector2((index % ICON_ROW) * ICON_STEP, (index / ICON_ROW) * ICON_STEP)) * k
		draw_texture_rect(icon.texture, Rect2(cell, Vector2(ICON, ICON) * k), false)

func _draw_banner() -> void:
	var rect := banner_rect()
	var source_y := banner * BAND
	var half := Rect2(rect.position, Vector2(rect.size.x * 0.5, rect.size.y))
	var first := profile != null and profile.id == "el1"
	var alpha := banner_frame(banner_age).y if first else 1.0
	for index in 2:
		var target := Rect2(half.position + Vector2(half.size.x * index, 0), half.size)
		var source := Rect2(0, source_y, 256, BAND)
		if first:
			var outline := Color(OUTLINE, alpha)
			for offset: Vector2 in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
				draw_texture_rect_region(halves[index], Rect2(target.position + offset, target.size), source, outline)
			draw_texture_rect_region(halves[index], target, source, Color(FILL, alpha))
		else:
			draw_texture_rect_region(halves[index], target, source)
