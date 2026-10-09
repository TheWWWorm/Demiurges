class_name ELMoviePlayer
extends ColorRect
## The original Bink movies (Resources/Movies/*.bik) of either edition. A
## movie is converted once on a background thread into the edition's movie
## cache (ELMovieCache); the first showing streams the frames already
## converted and starts as soon as the rest will be ready in time. Frames are
## turned into RGB by a shader.
##
## Full-screen use (start-up logos and intro, campaign endings) follows the
## originals: black around the picture, the game waits underneath, and a key
## press of Esc or Space or a left or right click ends the current movie (the
## next one of a sequence still plays). `Video` mode 2 fits the picture to the
## screen keeping its aspect, mode 1 shows it at its own size on the 1024x768
## layout, mode 0 plays no movie at all. A missing or unreadable file is logged
## and skipped.
##
## Embedded use (`embedded`): a picture inside a menu (the first game's chapter
## map on the campaign screen): no input, no sound, played once and held on its
## last frame.
##
## Adapted from the Cursed Lands engine's movie player (TheWWWorm, Apache-2.0).

const SHADER := """
shader_type canvas_item;
uniform sampler2D u_tex : filter_linear;
uniform sampler2D v_tex : filter_linear;
void fragment() {
	float y = (texture(TEXTURE, UV).r - 16.0 / 255.0) * 1.164383;
	float u = texture(u_tex, UV).r - 128.0 / 255.0;
	float v = texture(v_tex, UV).r - 128.0 / 255.0;
	COLOR = vec4(y + 1.596027 * v, y - 0.391762 * u - 0.812968 * v, y + 2.017232 * u, 1.0);
}
"""
const SAFETY := 0.85  # stream when the conversion needs < 85 % of the playing time
const DESIGN := Vector2(1024, 768)

enum { IDLE, PREPARING, PLAYING, HELD }

## Emitted when a sequence ends: every movie played, skipped or missing.
signal finished
## Emitted when one movie ends (name, true when it was skipped).
signal movie_ended(name: String, skipped: bool)

## Movies are shown. Off for headless runs, scripted checks (--script) and
## the --no-movies launch option: a sequence then ends at once. Checks that
## look at a movie turn it back on.
static var enabled := _default_enabled()
## Remake setting mirroring the originals' `Video` key: 0 none, 1 own size,
## 2 fitted to the screen (the shipped value).
static var mode := 2
## Every movie requested, in order (also when disabled or missing): the
## trigger points of the start-up sequence and the endings are checked on it.
static var history: PackedStringArray = []
static var _converters := {}  # cache path -> ELMovieCache (running or finished)

var embedded := false
var silent := false
var _view: TextureRect
var _label: Label
var _audio: AudioStreamPlayer
var _mat: ShaderMaterial
var _tex: Array[ImageTexture] = [null, null, null]
var _queue: Array[Dictionary] = []
var _item: Dictionary = {}
var _state := IDLE
var _conv: ELMovieCache
var _file: FileAccess
var _offsets := PackedInt64Array()
var _frames := 0
var _fps := 25.0
var _width := 0
var _height := 0
var _clock := 0.0
var _shown := -1
var _stalled := false
var _hist: Array[Vector2] = []  # (seconds, frames converted) of the last few seconds


static func _default_enabled() -> bool:
	if DisplayServer.get_name() == "headless": return false
	if OS.get_cmdline_args().has("--script"): return false
	# The browser keeps converted movies in memory-backed storage; skip them there.
	if OS.has_feature("web"): return false
	return not OS.get_cmdline_user_args().has("--no-movies")


## A movie of the mounted edition: {name, source (absolute path, "" when the
## file is not installed), cache}. `relative` is the original's own name, e.g.
## "Movies\\intro.bik" or a campaign's "Green01.bik".
static func item(profile: ELProfile, relative: String) -> Dictionary:
	var rel := relative.replace("\\", "/")
	if not rel.to_lower().begins_with("movies/"): rel = "Movies/" + rel
	var source := profile.file("Resources/" + rel)
	if source.is_empty(): source = profile.file(rel)
	var name := rel.get_file().get_basename().to_lower()
	# While a movie is converted the screen shows the edition's own T_WAIT text.
	var wait := profile.text("T_WAIT")
	return {"name": name, "source": source, "cache": "user://movies/%s/%s.elv" % [profile.id, name],
		"wait": wait if wait != "T_WAIT" else "..."}


## The edition's start-up sequence. The first game plays its fixed logo list
## then the intro (a missing logo is skipped); the second plays the lines of
## its settings.ini [Intro Settings] section, nothing when it has none.
static func startup_items(profile: ELProfile) -> Array[Dictionary]:
	var names: PackedStringArray = []
	if profile.id == "el1":
		names = ["Movies\\firstlogo.bik", "Movies\\fishtank.bik", "Movies\\nival.bik", "Movies\\intro.bik"]
	else:
		names = ini_section(profile.file("settings.ini"), "Intro Settings")
	var items: Array[Dictionary] = []
	for name in names: items.append(item(profile, name))
	return items


## The bare lines of one section of an original ini file.
static func ini_section(path: String, section: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if path.is_empty() or not FileAccess.file_exists(path): return out
	var current := ""
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"): current = line.substr(1, line.length() - 2).strip_edges()
		elif current.to_lower() == section.to_lower() and not line.is_empty() and not line.begins_with(";") and not line.contains("="):
			out.append(line)
	return out


## The first game's campaign ending: `outtro<colour index + 1>.bik` from the
## colour of the final chapter's human player (Red, Green, Blue, Black).
static func first_ending(profile: ELProfile, colour: String) -> Dictionary:
	var index := ["red", "green", "blue", "black"].find(colour.to_lower())
	return item(profile, "Movies\\outtro%d.bik" % (maxi(index, 0) + 1))


## Joins the background conversions (call once when the game quits).
static func shutdown() -> void:
	for c: ELMovieCache in _converters.values():
		c.cancel = true
		c.finish()
	_converters.clear()


func _ready() -> void:
	visible = false
	color = Color.BLACK
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not embedded: set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if embedded else Control.MOUSE_FILTER_STOP
	if embedded: color = Color(0, 0, 0, 0)
	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SHADER
	_view.material = _mat
	add_child(_view)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	_label.visible = not embedded
	add_child(_label)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	resized.connect(_layout)


func playing() -> bool:
	return _state != IDLE


## Current movie name ("" when idle).
func current() -> String:
	return str(_item.get("name", ""))


## Plays `items` one after another, then emits `finished`.
func play_list(items: Array[Dictionary]) -> void:
	_queue = items.duplicate()
	_next()


func play(entry: Dictionary) -> void:
	play_list([entry])


func _next() -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		history.append(str(entry.get("name", "")))
		if not enabled or mode == 0: continue
		if str(entry.get("source", "")).is_empty():
			print("movie %s: not installed; skipped" % entry.get("name", ""))
			continue
		if _open(entry): return
	_item = {}
	_state = IDLE
	visible = false
	finished.emit.call_deferred()


func _open(entry: Dictionary) -> bool:
	_item = entry
	_hist.clear()
	var cached := ProjectSettings.globalize_path(str(entry.cache))
	var size := FileAccess.get_size(entry.source)
	for n in _converters.keys():  # drop finished conversions
		var old: ELMovieCache = _converters[n]
		if not old.is_running():
			old.finish()
			_converters.erase(n)
	var conv: ELMovieCache = _converters.get(cached)
	if conv == null:
		var c := ELMovieCache.open_cache(cached, size)
		if not c.is_empty():
			_start_cache(c)
			return true
		conv = ELMovieCache.new()
		conv.start(entry.source, cached)
		_converters[cached] = conv
	_conv = conv
	_state = PREPARING
	_label.text = _wait_text()
	visible = true
	_layout()
	return true


## Ends the current movie (a skip); a sequence continues with its next movie.
func skip() -> void:
	if _state == IDLE: return
	var name := current()
	_close()
	movie_ended.emit(name, true)
	_next()


## Ends the whole sequence at once.
func stop() -> void:
	_queue.clear()
	if _state == IDLE: return
	skip()


func _close() -> void:
	_audio.stop()
	_audio.stream = null
	_state = IDLE
	_shown = -1
	_frames = 0
	_conv = null
	_file = null
	_view.texture = null
	_tex = [null, null, null]
	_label.text = ""


func _exit_tree() -> void:
	_queue.clear()
	if _state != IDLE: _close()


func _process(delta: float) -> void:
	if _state == PREPARING: _prepare()
	elif _state == PLAYING: _advance(delta)


func _prepare() -> void:
	var c := _conv
	if c.failed:
		print("movie %s: cannot be decoded; skipped" % current())
		_end()
		return
	if c.ok:  # finished while we waited
		c.finish()
		_converters.erase(c.path)
		var cache := ELMovieCache.open_cache(c.path)
		if cache.is_empty(): _end()
		else: _start_cache(cache)
		return
	var total := c.frame_count
	if total <= 0: return
	_fps = float(c.fps_num) / maxf(c.fps_den, 1)
	_frames = total
	var done := _sample()
	if _can_play_from(0) and (silent or embedded or c.audio_ready()):
		var f := FileAccess.open(c.path, FileAccess.READ)
		if f == null: return
		_file = f
		_offsets = PackedInt64Array()
		_begin(total, _fps, c.width, c.height, PackedByteArray() if silent or embedded else c.audio_pcm(), c.audio_rate, c.audio_channels)
		return
	_label.text = "%s %d%%" % [_wait_text(), clampi(done * 100 / total, 0, 99)]


func _wait_text() -> String:
	return String(_item.get("wait", "..."))


func _end() -> void:
	var name := current()
	_close()
	movie_ended.emit(name, false)
	_next()


## Frames converted so far; also records the recent conversion speed.
func _sample() -> int:
	var done := _conv.frames_done()
	var now := Time.get_ticks_msec() / 1000.0
	_hist.append(Vector2(now, done))
	while _hist.size() > 2 and now - _hist[0].x > 6.0:
		_hist.pop_front()
	return done


## Seconds of conversion per unit of ELMovieCache.cum_cost: the slower of the
## recent and the overall speed (0 until measurable).
func _sec_per_cost() -> float:
	var cum := _conv.cum_cost
	var done := int(_hist[-1].y)
	var r := 0.0
	if done > 0 and _conv.elapsed() > 0.5:
		r = _conv.elapsed() / cum[done]
	if _hist.size() >= 2 and _hist[-1].x - _hist[0].x >= 2.0 and _hist[-1].y > _hist[0].y:
		r = maxf(r, (_hist[-1].x - _hist[0].x) / (cum[int(_hist[-1].y)] - cum[int(_hist[0].y)]))
	return r


## True when playing on from frame `f` will not overtake the conversion: every
## later frame (predicted from its size) is converted before it is due.
func _can_play_from(f: int) -> bool:
	var done := int(_hist[-1].y)
	if done >= _frames: return true
	var spc := _sec_per_cost()
	if spc <= 0.0 or done - f < mini(_frames - f, ceili(_fps)): return false
	var cum := _conv.cum_cost
	var step := maxi(1, (_frames - done) / 256)
	var k := done
	while true:
		if (cum[k + 1] - cum[done]) * spc > (k - f) / _fps * SAFETY: return false
		if k == _frames - 1: return true
		k = mini(k + step, _frames - 1)
	return true


func _start_cache(c: Dictionary) -> void:
	_conv = null
	_file = c.file
	_offsets = c.offsets
	var pcm: PackedByteArray = PackedByteArray() if silent or embedded else c.pcm
	_begin(c.frames, float(c.fps_num) / maxf(c.fps_den, 1), c.width, c.height, pcm, c.audio_rate, c.audio_channels)


func _begin(frames: int, fps: float, w: int, h: int, pcm: PackedByteArray, rate: int, channels: int) -> void:
	_frames = frames
	_fps = fps
	_width = w
	_height = h
	_clock = 0.0
	_shown = -1
	_stalled = false
	_hist.clear()
	_state = PLAYING
	_label.text = ""
	visible = true
	_layout()
	if pcm.size() > 0 and rate > 0:
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.stereo = channels == 2
		s.mix_rate = rate
		s.data = pcm
		_audio.stream = s
		_audio.play()
	_advance(0.0)


func _advance(delta: float) -> void:
	var avail := _sample() if _conv else _frames
	if _stalled:
		# the conversion fell behind: hold picture and sound until enough is
		# buffered to play on without stalling again
		if not _can_play_from(int(_clock * _fps)):
			_label.text = "..."
			return
		_stalled = false
		_label.text = ""
		_audio.stream_paused = false
	_clock += delta
	var f := int(_clock * _fps)
	if f >= _frames:
		if embedded:  # held on its last frame
			if _shown < _frames - 1 and _frames - 1 < avail: _show(_frames - 1)
			if _shown == _frames - 1: _state = HELD
			return
		_end()
		return
	if f == _shown: return
	if f >= avail:
		_stalled = true
		_audio.stream_paused = true
		_clock = float(f) / _fps
		return
	_show(f)


## Frame shown last (-1 before the first).
func shown_frame() -> int:
	return _shown


func frame_count() -> int:
	return _frames


func frame_size() -> Vector2i:
	return Vector2i(_width, _height)


func has_sound() -> bool:
	return _audio.stream != null


func _show(i: int) -> void:
	var span := _conv.frame_span(i) if _conv else Vector2i(_offsets[i], _offsets[i + 1])
	_file.seek(span.x)
	var img := Image.new()
	if img.load_jpg_from_buffer(_file.get_buffer(span.y - span.x)) != OK: return
	_shown = i
	var cw := (_width + 1) >> 1
	var ch := (_height + 1) >> 1
	var parts := [img.get_region(Rect2i(0, 0, _width, _height)), img.get_region(Rect2i(0, _height, cw, ch)),
		img.get_region(Rect2i(cw, _height, cw, ch))]
	for k in 3:
		if _tex[k] == null: _tex[k] = ImageTexture.create_from_image(parts[k])
		else: _tex[k].update(parts[k])
	_view.texture = _tex[0]
	_mat.set_shader_parameter("u_tex", _tex[1])
	_mat.set_shader_parameter("v_tex", _tex[2])


## Picture rectangle: the whole control when embedded or fitted (mode 2);
## the movie's own size on the 1024x768 layout, centred, in mode 1.
func _layout() -> void:
	if _view == null: return
	if embedded or mode != 1 or _width <= 0:
		_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var ui := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	var picture := Vector2(_width, _height) * ui
	if picture.x > size.x or picture.y > size.y: picture *= minf(size.x / picture.x, size.y / picture.y)
	_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_view.position = ((size - picture) * 0.5).floor()
	_view.size = picture


func _input(e: InputEvent) -> void:
	if embedded or _state == IDLE or not is_visible_in_tree(): return
	var key: bool = e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ESCAPE, KEY_SPACE]
	var click: bool = e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	if key or click:
		get_viewport().set_input_as_handled()
		skip()
	elif e is InputEventKey or e is InputEventMouseButton:
		get_viewport().set_input_as_handled()
