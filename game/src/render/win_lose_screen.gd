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
## The widescreen extensions use the installed edition's picture and caption.
## The blurred backdrop remains available for tall windows and missing overlays.
signal closed

const DESIGN := Vector2(1024, 768)
const HOLD := 15.0
const FADE := 1.0
const WAIT_TEXT := "WL_WaitText"
const WAIT_INK := Color8(0xd6, 0xbb, 0x88)
const GOOD_COLOURS := ["green", "blue"]
const WIDE_ART := "res://assets/widescreen/"
const EL2_DEFEAT_OVERLAY := WIDE_ART + "etherlords-ii-defeat-overlay.png"
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
var _wide_picture: Texture2D
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
	var picture := compose_picture(pieces)
	_wide_picture = wide_picture(picture, _overlay_path())
	_blurred = _blur(picture)
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

func _overlay_path() -> String:
	if first:
		return WIDE_ART + ("etherlords-good-result-overlay.png" if mask.has("Type1") else "etherlords-evil-result-overlay.png")
	return WIDE_ART + "etherlords-ii-victory-overlay.png" if won else EL2_DEFEAT_OVERLAY

static func compose_picture(tiles: Array[Dictionary]) -> Image:
	if tiles.is_empty(): return null
	var whole := Image.create_empty(int(DESIGN.x), int(DESIGN.y), false, Image.FORMAT_RGBA8)
	whole.fill(Color.BLACK)
	for piece: Dictionary in tiles:
		var image := ELTexture.readable(ELIconUpscale.image_of(piece.texture))
		if image == null: continue
		var source: Rect2 = piece.source
		var rect: Rect2 = piece.rect
		whole.blend_rect(image, Rect2i(source), Vector2i(rect.position))
	return whole

## Composite once so the extended scene and the original fade as one image.
static func wide_picture(picture: Image, path: String) -> Texture2D:
	if picture == null or not ResourceLoader.exists(path): return null
	var texture := load(path) as Texture2D
	if texture == null: return null
	var overlay := ELTexture.readable(texture.get_image())
	if overlay == null or overlay.get_width() <= picture.get_width() or overlay.get_height() < picture.get_height(): return null
	var margin := (overlay.get_size() - picture.get_size()) / 2
	var whole := Image.create_empty(overlay.get_width(), overlay.get_height(), false, Image.FORMAT_RGBA8)
	whole.blit_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), margin)
	whole.blend_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(whole)

## A soft copy for the bars when the widescreen art cannot be drawn.
func _blur(whole: Image) -> Texture2D:
	if whole == null: return null
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
	_art.queue_redraw()
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
	if _wide_picture != null and gap.x >= ELFrontMenu.WIDE_MINIMUM: return
	if maxf(gap.x, gap.y) < ELFrontMenu.WIDE_MINIMUM: return
	var cover := maxf(size.x / DESIGN.x, size.y / DESIGN.y)
	var extent := DESIGN * cover
	_backdrop.draw_texture_rect(_blurred, Rect2((size - extent) * 0.5, extent), false, Color(BLUR_SHADE, BLUR_SHADE, BLUR_SHADE, alpha))
	# A soft shadow outside each edge of the picture that has a bar beside it.
	var picture := Rect2(_art.position, DESIGN * factor)
	var reach := EDGE_SHADOW * factor
	var dark := Color(0, 0, 0, 0.75 * alpha)
	var clear := Color(0, 0, 0, 0)
	if gap.x >= ELFrontMenu.WIDE_MINIMUM:
		_edge(Rect2(picture.position.x - reach, picture.position.y, reach, picture.size.y), clear, dark, true)
		_edge(Rect2(picture.end.x, picture.position.y, reach, picture.size.y), dark, clear, true)
	if gap.y >= ELFrontMenu.WIDE_MINIMUM:
		_edge(Rect2(picture.position.x, picture.position.y - reach, picture.size.x, reach), clear, dark, false)
		_edge(Rect2(picture.position.x, picture.end.y, picture.size.x, reach), dark, clear, false)

## A rectangle shaded from `from` to `to` across (left to right) or down.
func _edge(rect: Rect2, from: Color, to: Color, across: bool) -> void:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var colours := PackedColorArray([from, to, to, from] if across else [from, from, to, to])
	_backdrop.draw_polygon(points, colours)

func _draw_art() -> void:
	var tint := Color(1, 1, 1, alpha)
	var side := (size.x / _art.scale.x - DESIGN.x) * 0.5
	if _wide_picture != null and side >= ELFrontMenu.WIDE_MINIMUM:
		draw_wide_picture(_art, _wide_picture, side, tint)
		return
	for piece: Dictionary in pieces:
		_art.draw_texture_rect_region(piece.texture, piece.rect, piece.source, tint)

## At widescreen sizes, draw in one rectangle so filtering crosses the joins.
## Narrower windows compress the extensions to keep the outer frame visible.
static func draw_wide_picture(target: CanvasItem, picture: Texture2D, side: float, tint := Color.WHITE) -> void:
	if side < DESIGN.y * (16.0 / 9.0) * 0.5 - DESIGN.x * 0.5 - 0.01:
		ELFrontMenu.draw_wide_texture(target, picture, side, tint)
		return
	var margin := (Vector2(picture.get_size()) - DESIGN) * 0.5
	var outer := minf(side, margin.x)
	var extent := DESIGN + Vector2(outer * 2.0, 0)
	target.draw_texture_rect_region(picture, Rect2(Vector2(-outer, 0), extent),
		Rect2(Vector2(margin.x - outer, margin.y), extent), tint)

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
