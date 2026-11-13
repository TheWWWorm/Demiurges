class_name ELWinLoseScreen
extends Control
## The mission-end picture (CutParts group WinLose), both games.
##
## The 1024x768 rows are drawn whose Type masks all belong to the screen's
## mask, over black. First game: the picture of the winning side and the
## victory or defeat caption, chosen by the local player's side (Green and
## Blue are good): good win Type1+Type3, evil win Type2+Type3, good defeat
## Type2+Type4, evil defeat Type1+Type4, with Buttons/<Good|Evil><Victory|
## Defeat>.wav. It holds 15 s, fades to black in 1 s and closes; a click or a
## key closes it at once. Second game: Type1 victory / Type2 defeat with
## Buttons/GoodVictory.wav or GoodDefeat.wav; it fades in over 1 s (input is
## ignored meanwhile), holds 15 s, and a click or key during the hold starts
## the 1 s fade-out; "Wait..." (WL_WaitText) shows on black before it closes.
## Closing stops its sound and emits `closed` once.
##
## Remake: in a window wider (or taller) than 4:3 the bars beside the picture
## show the same picture blurred, darkened and stretched to fill the window,
## with a soft shadow along the picture's edges; at 4:3 nothing changes.
signal closed

const DESIGN := Vector2(1024, 768)
const HOLD := 15.0
const FADE := 1.0
const WAIT_TEXT := "WL_WaitText"
const WAIT_INK := Color8(0xd6, 0xbb, 0x88)
const GOOD_COLOURS := ["green", "blue"]
## Bars narrower than this (design pixels) stay black, as the front end's
## widescreen frame does (ELFrontMenu.WIDE_MINIMUM).
const WIDE_MINIMUM := 48.0
## The blurred copy: its size before it is smoothed back up, and its brightness.
const BLUR_SIZE := Vector2i(32, 24)
const BLUR_SHADE := 0.42
## Width of the shadow along the picture's edges (design pixels).
const EDGE_SHADOW := 40.0

## The sound requested by the last screen shown (checks read it).
static var last_sound := ""

var profile: ELProfile
var won := false
var first := true
var mask: Array[String] = []
## {texture, source, rect} in the 1024 layout.
var pieces: Array[Dictionary] = []
## 0 fade-in (second game), 1 hold, 2 fade-out, 3 closed.
var stage := 1
var clock := 0.0
var alpha := 1.0
var wait_label: Label
var _art: Control
var _backdrop: Control
var _blurred: Texture2D
var _player: AudioStreamPlayer

## The screen's mask for one outcome; `colour` is the local player's colour.
static func masks(first_game: bool, victory: bool, colour: String) -> Array[String]:
	var result: Array[String] = []
	if not first_game:
		result.append("Type1" if victory else "Type2")
		return result
	var good := colour.to_lower() in GOOD_COLOURS
	# The winning side's picture, then the victory or defeat caption.
	result.append("Type1" if good == victory else "Type2")
	result.append("Type3" if victory else "Type4")
	return result

static func sound_path(first_game: bool, victory: bool, colour: String) -> String:
	if not first_game: return "Buttons/GoodVictory.wav" if victory else "Buttons/GoodDefeat.wav"
	var side := "Good" if colour.to_lower() in GOOD_COLOURS else "Evil"
	return "Buttons/%s%s.wav" % [side, "Victory" if victory else "Defeat"]

## Builds the screen; returns false when the edition has no WinLose art.
func setup(source: ELProfile, victory: bool, colour: String) -> bool:
	profile = source
	won = victory
	first = source == null or source.id != "el2"
	mask = masks(first, victory, colour)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	if source != null: _collect()
	_blurred = _blur()
	_backdrop = Control.new()
	_backdrop.name = "WideBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop)
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.size = DESIGN
	_art.draw.connect(_draw_art)
	add_child(_art)
	wait_label = Label.new()
	wait_label.name = "WaitText"
	wait_label.hide()
	_art.add_child(wait_label)
	if not first and source != null: _place_wait()
	resized.connect(_layout)
	stage = 1 if first else 0
	clock = 0.0
	alpha = 1.0 if first else 0.0
	last_sound = sound_path(first, victory, colour)
	_play(last_sound)
	_layout()
	return not pieces.is_empty()

func _collect() -> void:
	var paths := {}
	for definition: Dictionary in profile.table("InterfaceTextures").values():
		paths[str(definition.get("Name", ""))] = "Interface/" + str(definition.get("Path", "")).replace("\\", "/")
	for row: Dictionary in profile.table("CutParts").values():
		if str(row.get("Ctrl", "")) != "WinLose": continue
		var raw: Variant = row.get("Msk", [])
		var row_masks: Array = raw if raw is Array else [raw]
		if row_masks.has("Res1"): continue
		var fits := true
		for entry: Variant in row_masks:
			var name := str(entry)
			if name.begins_with("Type") and not mask.has(name): fits = false
		if not fits: continue
		var key := str(row.get("Txt", ""))
		var texture: Texture2D = profile.texture(paths[key]) if paths.has(key) else null
		if texture == null: continue
		var source := Rect2(float(row.get("TxtL", 0)), float(row.get("TxtT", 0)), float(row.get("TxtW", 0)), float(row.get("TxtH", 0)))
		pieces.append({"texture": texture, "source": source, "rect": Rect2(Vector2(float(row.get("ScrL", 0)), float(row.get("ScrT", 0))), source.size)})

## The picture shrunk to a few pixels and smoothed back up: a soft copy for
## the bars of wider windows (no new art, only the shown picture).
func _blur() -> Texture2D:
	if pieces.is_empty(): return null
	var whole := Image.create(int(DESIGN.x), int(DESIGN.y), false, Image.FORMAT_RGBA8)
	whole.fill(Color.BLACK)
	for piece: Dictionary in pieces:
		var image: Image = piece.texture.get_image()
		if image == null: continue
		if image.is_compressed() and image.decompress() != OK: continue
		image.convert(Image.FORMAT_RGBA8)
		var source: Rect2 = piece.source
		var rect: Rect2 = piece.rect
		whole.blend_rect(image, Rect2i(source), Vector2i(rect.position))
	# Halving steps average neighbouring pixels; one large step would alias.
	while whole.get_width() > BLUR_SIZE.x * 2:
		whole.resize(maxi(BLUR_SIZE.x, whole.get_width() / 2), maxi(BLUR_SIZE.y, whole.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	whole.resize(BLUR_SIZE.x, BLUR_SIZE.y, Image.INTERPOLATE_BILINEAR)
	whole.resize(BLUR_SIZE.x * 8, BLUR_SIZE.y * 8, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(whole)

## WL_WaitText: Controls rectangle plus its shift, bold 24, left-aligned.
func _place_wait() -> void:
	for row: Dictionary in profile.table("Controls").values():
		if str(row.get("Name", "")) != WAIT_TEXT: continue
		var at := Vector2(float(row.get("Left", 0)) + float(row.get("ShiftX", 0)), float(row.get("Top", 0)) + float(row.get("ShiftY", 0)))
		wait_label.position = at
		wait_label.size = Vector2(float(row.get("Width", 0)), float(row.get("Height", 0)))
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"])
		font.font_weight = 700
		wait_label.add_theme_font_override("font", font)
		wait_label.add_theme_font_size_override("font_size", int(row.get("FontSize", 24)))
		wait_label.add_theme_color_override("font_color", WAIT_INK)
		var key := str(row.get("Text", ""))
		var value := profile.text(key)
		wait_label.text = "" if value == key else value
		return

func _layout() -> void:
	if _art == null or size.x <= 0.0 or size.y <= 0.0: return
	var factor := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_art.scale = Vector2(factor, factor)
	_art.position = ((size - DESIGN * factor) * 0.5).round()
	queue_redraw()
	if _backdrop != null: _backdrop.queue_redraw()

## Black under the art: always in the first game; in the second only from the
## fade-out (its fade-in shows the map behind the picture).
func _draw() -> void:
	if first or stage >= 2: draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)

## The blurred copy filling the window around the picture (only when the bars
## are wide enough), fading with the picture.
func _draw_backdrop() -> void:
	if _blurred == null or _art == null or alpha <= 0.0: return
	var factor := _art.scale.x
	if factor <= 0.0: return
	var gap := (size / factor - DESIGN) * 0.5
	if maxf(gap.x, gap.y) < WIDE_MINIMUM: return
	var cover := maxf(size.x / DESIGN.x, size.y / DESIGN.y)
	var extent := DESIGN * cover
	_backdrop.draw_texture_rect(_blurred, Rect2((size - extent) * 0.5, extent), false, Color(BLUR_SHADE, BLUR_SHADE, BLUR_SHADE, alpha))
	# A soft shadow outside each edge of the picture that has a bar beside it.
	var picture := Rect2(_art.position, DESIGN * factor)
	var reach := EDGE_SHADOW * factor
	var dark := Color(0, 0, 0, 0.75 * alpha)
	var clear := Color(0, 0, 0, 0)
	if gap.x >= WIDE_MINIMUM:
		_edge(Rect2(picture.position.x - reach, picture.position.y, reach, picture.size.y), clear, dark, true)
		_edge(Rect2(picture.end.x, picture.position.y, reach, picture.size.y), dark, clear, true)
	if gap.y >= WIDE_MINIMUM:
		_edge(Rect2(picture.position.x, picture.position.y - reach, picture.size.x, reach), clear, dark, false)
		_edge(Rect2(picture.position.x, picture.end.y, picture.size.x, reach), dark, clear, false)

## A rectangle shaded from `from` to `to` across (left to right) or down.
func _edge(rect: Rect2, from: Color, to: Color, across: bool) -> void:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var colours := PackedColorArray([from, to, to, from] if across else [from, from, to, to])
	_backdrop.draw_polygon(points, colours)

func _draw_art() -> void:
	var tint := Color(1, 1, 1, alpha)
	for piece: Dictionary in pieces:
		_art.draw_texture_rect_region(piece.texture, piece.rect, piece.source, tint)

func _process(delta: float) -> void:
	if stage >= 3: return
	clock += delta
	match stage:
		0:
			alpha = clampf(clock / FADE, 0.0, 1.0)
			if clock >= FADE: _enter(1)
		1:
			alpha = 1.0
			if clock >= HOLD: _enter(2)
		2:
			alpha = clampf(1.0 - clock / FADE, 0.0, 1.0)
			if clock >= FADE: finish()
	if _art != null: _art.queue_redraw()
	if _backdrop != null: _backdrop.queue_redraw()

func _enter(next: int) -> void:
	stage = next
	clock = 0.0
	queue_redraw()

## A click or a key: the first game closes at once; the second fades out, and
## only from the hold.
func dismiss() -> void:
	if stage == 1:
		if first: finish()
		else: _enter(2)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		dismiss()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or stage >= 3: return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo: dismiss()

## Ends the screen: stops its sound and emits `closed` once.
func finish() -> void:
	if stage >= 3: return
	stage = 3
	alpha = 0.0
	queue_redraw()
	if not first and wait_label != null and not wait_label.text.is_empty(): wait_label.show()
	if _art != null: _art.queue_redraw()
	if _backdrop != null: _backdrop.queue_redraw()
	if _player != null: _player.stop()
	closed.emit()

func _play(path: String) -> void:
	if profile == null or ELUiSounds.volume <= 0.0: return
	var stream := ELAudio.sound(profile, path)
	if stream == null: return
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.stream = stream
	_player.volume_db = linear_to_db(ELUiSounds.volume)
	_player.play()
