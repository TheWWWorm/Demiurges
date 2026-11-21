extends Control
## The start-up screen (the project's main scene): the boot splash again, with
## a moving bar, while the game's scripts load in a thread; then the game
## scene (scenes/duel.tscn) replaces it.
##
## Compiling the game's GDScript takes several seconds (longer on a first
## start). Loaded as the main scene's script, that ran before the first frame,
## with no window messages answered, and Windows offered to close the game as
## not responding. This script names none of the game's classes (only the
## standalone ELRendererChoice), so it starts at once; the scene and every script it uses load in ResourceLoader's
## thread and the window keeps drawing.
##
## Without a window (headless checks) or threads (web), the scene loads at
## once, as before.

const GAME_SCENE := "res://scenes/duel.tscn"
const BAR_HEIGHT := 4.0
const BAR_WIDTH := 0.3
const BAR_COLOR := Color(0.88, 0.69, 0.41, 0.8)

var _loading := false
var _bar: ColorRect
var _shown_at := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_window().title = "Demiurges"
	# A saved choice of the other renderer starts the game again before
	# anything is compiled (ELRendererChoice names no other game class).
	if ELRendererChoice.restart_early(get_tree()): return
	var threaded := DisplayServer.get_name() != "headless" and not OS.has_feature("web")
	if threaded and ResourceLoader.load_threaded_request(GAME_SCENE, "PackedScene") == OK:
		_loading = true
		_build()
		return
	_open.call_deferred(load(GAME_SCENE))

func _build() -> void:
	var back := ColorRect.new()
	back.color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var path := String(ProjectSettings.get_setting("application/boot_splash/image", ""))
	if bool(ProjectSettings.get_setting("application/boot_splash/show_image", true)) and ResourceLoader.exists(path):
		var splash := TextureRect.new()
		splash.texture = load(path) as Texture2D
		splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(splash)
	_bar = ColorRect.new()
	_bar.color = BAR_COLOR
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_shown_at = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if not _loading: return
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_move_bar()
		return
	_loading = false
	var scene: PackedScene = ResourceLoader.load_threaded_get(GAME_SCENE) if status == ResourceLoader.THREAD_LOAD_LOADED else null
	# A failed thread load reports its errors; the plain load gives the game
	# its usual error handling.
	_open(scene if scene != null else load(GAME_SCENE))

## A short bar sweeping along the bottom edge: the game is loading.
func _move_bar() -> void:
	var width := size.x * BAR_WIDTH
	var phase := fmod((Time.get_ticks_msec() - _shown_at) / 1600.0, 1.0)
	_bar.position = Vector2(lerpf(-width, size.x, phase), size.y - BAR_HEIGHT)
	_bar.size = Vector2(width, BAR_HEIGHT)

func _open(scene: PackedScene) -> void:
	if scene == null:
		push_error("Could not load " + GAME_SCENE)
		get_tree().quit(1)
		return
	get_tree().change_scene_to_packed(scene)

## Quitting while the thread still loads: wait for it, so nothing it loads is
## left behind at exit.
func _exit_tree() -> void:
	if _loading:
		_loading = false
		ResourceLoader.load_threaded_get(GAME_SCENE)
