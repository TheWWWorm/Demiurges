class_name ELCursorDriver
extends Node
## Shows the original cursors (ELCursors) as the hardware mouse cursor and
## steps their frames every 125 ms. Without the edition's cursor textures, or
## with no profile, the system cursor is used.

static var _instance: ELCursorDriver

var profile: ELProfile
var current := ""
## Frame position of each cursor; a cursor resumes where it stopped.
var positions: Dictionary = {}
var clock := 0.0
## The last request sent to the display: {"edition", "name", "frame",
## "hotspot", "image"}; empty while the system cursor is shown.
var shown: Dictionary = {}
## Number of cursor images sent to the display (frame steps included).
var uploads := 0

## The shared driver, created under the scene root on first use.
static func instance() -> ELCursorDriver:
	if is_instance_valid(_instance) and _instance.is_inside_tree(): return _instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return null
	_instance = ELCursorDriver.new()
	_instance.name = "ELCursorDriver"
	tree.root.add_child.call_deferred(_instance)
	return _instance

## Requests a cursor of the profile's edition by table name ("default",
## "attack", ...). An unknown or missing cursor falls back to the system one.
static func request(owner_profile: ELProfile, cursor_name: String) -> void:
	var driver := instance()
	if driver != null: driver.select(owner_profile, cursor_name)

static func current_name() -> String:
	return _instance.current if is_instance_valid(_instance) else ""

func select(owner_profile: ELProfile, cursor_name: String) -> void:
	if owner_profile == profile and cursor_name == current: return
	if owner_profile != profile: positions.clear()
	profile = owner_profile
	current = cursor_name
	_apply()

func _process(delta: float) -> void:
	if current.is_empty() or profile == null: return
	clock += delta
	if clock < ELCursors.FRAME_TIME: return
	var steps := int(clock / ELCursors.FRAME_TIME)
	clock -= steps * ELCursors.FRAME_TIME
	var entry := ELCursors.cursor(profile, current)
	if entry.is_empty() or entry.frames.size() < 2: return
	positions[current] = (int(positions.get(current, 0)) + steps) % entry.frames.size()
	_apply()

func _apply() -> void:
	var entry := ELCursors.cursor(profile, current) if profile != null else {}
	if entry.is_empty() or entry.frames.is_empty():
		if not shown.is_empty(): Input.set_custom_mouse_cursor(null)
		shown = {}
		return
	var frame: int = int(positions.get(current, 0)) % int(entry.frames.size())
	var image: ImageTexture = entry.frames[frame]
	if shown.get("image") == image: return
	# A hotspot on the far edge (the right/down scroll cursors) is kept on
	# the last pixel, which display servers require.
	var size := image.get_size()
	var point := Vector2(minf(entry.hotspot.x, size.x - 1), minf(entry.hotspot.y, size.y - 1))
	Input.set_custom_mouse_cursor(image, Input.CURSOR_ARROW, point)
	uploads += 1
	shown = {"edition": profile.id, "name": current, "frame": frame, "hotspot": entry.hotspot, "point": point, "image": image}

func _exit_tree() -> void:
	if not shown.is_empty(): Input.set_custom_mouse_cursor(null)
	shown = {}
