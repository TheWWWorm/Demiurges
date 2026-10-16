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
## Second game: a carried card's icon replaces the cursor picture (inventory
## spell shop through). The 48x48
## top-left of the 50x50 icon cell is copied over the cursor frame
## so the arrow is hidden and the point stays the cursor's own
## hotspot. Null when nothing is carried.
var carry_image: Texture2D
var _carry_source: Texture2D
const CARRY_SIZE := 48

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

## Shows `icon` (a spell icon cell) as the cursor picture; null restores the
## animated cursor. Returns whether the hardware cursor carries it.
static func carry(owner_profile: ELProfile, icon: Texture2D) -> bool:
	var driver := instance()
	if driver == null: return false
	return driver.set_carry(owner_profile, icon)

static func current_name() -> String:
	return _instance.current if is_instance_valid(_instance) else ""

func select(owner_profile: ELProfile, cursor_name: String) -> void:
	if owner_profile == profile and cursor_name == current: return
	if owner_profile != profile: positions.clear()
	profile = owner_profile
	current = cursor_name
	_apply()

func set_carry(owner_profile: ELProfile, icon: Texture2D) -> bool:
	if icon == _carry_source and (icon == null or carry_image != null): return carry_image != null
	_carry_source = icon
	carry_image = carry_picture(icon)
	if owner_profile != null and profile == null: profile = owner_profile
	shown = {} if carry_image == null else shown
	_apply()
	return carry_image != null

## The 48x48 top-left of an icon cell as a stand-alone texture.
static func carry_picture(icon: Texture2D) -> Texture2D:
	if icon == null: return null
	var image: Image
	var origin := Vector2i.ZERO
	if icon is AtlasTexture:
		var atlas := icon as AtlasTexture
		if atlas.atlas == null: return null
		image = atlas.atlas.get_image()
		origin = Vector2i(atlas.region.position)
	else:
		image = icon.get_image()
	if image == null: return null
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	var region := Rect2i(origin, Vector2i(CARRY_SIZE, CARRY_SIZE)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if region.size.x <= 0 or region.size.y <= 0: return null
	return ImageTexture.create_from_image(image.get_region(region))

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
	if carry_image != null:
		if shown.get("image") == carry_image: return
		var hotspot := Vector2(entry.get("hotspot", Vector2i.ZERO))
		Input.set_custom_mouse_cursor(carry_image, Input.CURSOR_ARROW, hotspot)
		uploads += 1
		shown = {"edition": profile.id if profile != null else "", "name": current, "frame": -1, "hotspot": hotspot, "point": hotspot, "image": carry_image, "carry": true}
		return
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
