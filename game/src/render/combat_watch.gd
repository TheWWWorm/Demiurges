class_name ELCombatWatch
extends Node
## A remake addition: a second camera on the battlefield for the battle
## panel's "watch" readout (ELCombatGapPanel). It renders the battle's own
## 3D scene into a small viewport and stays on one figure at a time, a hero
## or a creature, moving to the next every DWELL seconds, in the manner of
## the automatic camera's close-ups but all the time.
##
## What of a figure is framed is decided when the camera comes to it:
## - a figure with a head part (the first game's heroes, "head") is framed
##   on the head, from over it down to about the waist;
## - one with shoulder parts and no head part (the second game's heroes,
##   whose head belongs to the body mesh: "l_plecho", "r_plecho") is framed
##   a little above the middle of the shoulders, the same way;
## - a hero with neither by its posed meshes' bounds: head and chest when it
##   stands clearly taller than it is wide (UPRIGHT_FROM), else whole;
## - a creature whole, by its posed meshes' bounds (WHOLE_AIR).
## The aim follows the figure as its animation moves it (a hero bending to
## cast, a creature running to its fight), smoothly, so that the picture
## does not shake with every step of the animation. Bounds are those of the
## pose shown (ELModel.posed_part_bounds; a mesh's own box spans its whole
## clip). They are not used for the heroes because a raised staff or an axe
## held aside would pull the picture off the face.
##
## The camera stands in front of the figure, towards the opposing hero, to
## one side and a little above, and drifts slowly round it while it stays.
## The side is the first of SIDES from which no other figure stands between
## the camera and its aim (a hero's creatures stand right in front of it);
## with none clear it looks down from higher up. The line of sight is looked
## at again every RECHECK seconds, and the camera changes side when a figure
## has come to stand in it. A figure that leaves the battle is left at once.
##
## The viewport shares the battle's world, so it shows the arena, the spell
## effects and the light as the main view does. Marks drawn in the world for
## the main view alone (figure labels, the selection ring) are put on render
## layer HIDDEN_LAYER by the battle view and left out here. Nothing is
## rendered while no panel shows the readout (`active`).

const DWELL := 4.5
## Wide enough that the camera stands close to its figure: at 26 degrees it
## stood so far out that on a sloping arena it was often inside the ground.
const FOV := 38.0
## How far above the ground the camera keeps, and above the ground between
## it and its aim (world units), checked every RECHECK seconds.
const CLEARANCE := 0.45
const SIGHT_CLEARANCE := 0.15
const SIGHT_SAMPLES := [0.25, 0.5, 0.75]
const HIDDEN_LAYER := 2
## Aiming at a part: the names looked for (lower case, as a part of the
## node's name), how far above the part the aim is and how much is framed,
## both as shares of the part's height above the figure's feet.
const HEAD := {"names": ["head"], "lift": 0.0, "span": 0.85}
const SHOULDERS := {"names": ["plecho"], "lift": 0.1, "span": 0.62}
## Framing by bounds: the share of an upright figure's height that is shown.
const UPRIGHT_SHARE := 0.62
## A figure counts as upright when it stands this many times as tall as it
## is wide or long (a rat rearing to bite does not).
const UPRIGHT_FROM := 1.3
## Degrees off the figure's front the camera may stand, tried in order (the
## sign is turned over from one stay to the next), and the degrees it drifts
## during a stay.
const SIDES := [22.0, -22.0, 48.0, -48.0, 75.0, -75.0, 105.0, -105.0]
const DRIFT := 12.0
## How far above its aim the camera stands (a share of the distance), and
## when no side is clear.
const RAISE := 0.32
const RAISE_OVER := 0.7
## A creature is framed whole, this much taller than its posed bounds.
const WHOLE_AIR := 1.2
const WHOLE_DEPTH := 0.8
## How fast the aim follows a moving part (per second).
const FOLLOW := 5.0
const RECHECK := 0.4

var viewport: SubViewport
var camera: Camera3D
## The figures to visit, in order: {"id", "node": Node3D, "facing": Vector3}
## (`facing` is the way the figure looks, on the ground).
var subjects: Array = []
## The figure shown (its id), -1 for none.
var subject := -1
var active := false:
	set(value):
		active = value
		if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
var _age := 0.0
var _visits := 0
## The stay's framing: the parts aimed at (empty: the fixed `_offset` from
## the figure's place), the aim's lift, the framed height, the side the
## camera stands on (degrees) and its raise.
var _parts: Array = []
var _lift := 0.0
## Framing by bounds: whether head and chest are framed (else the whole).
var _upright := false
var _span := 1.0
var _checked := 0.0
var _side := 22.0
var _raise := RAISE
var _aim := Vector3.INF
## The arena's ground height at (x, z), or none; and the lowest the camera
## may stand now (eased so that a change does not jump).
var ground := Callable()
var _floor := -INF
var _floor_wanted := -INF

func _init() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(220, 100)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.cull_mask = 0xfffff & ~(1 << (HIDDEN_LAYER - 1))
	viewport.add_child(camera)
	camera.current = true

## Shows `world` (the battle's) with the main camera's environment.
func attach(world: World3D, main: Camera3D, ground_height := Callable()) -> void:
	viewport.world_3d = world
	camera.environment = main.environment if main != null else null
	camera.attributes = main.attributes if main != null else null
	ground = ground_height
	subject = -1
	subjects = []

func set_pixels(pixels: Vector2) -> void:
	var wanted := Vector2i(clampi(roundi(pixels.x), 16, 1024), clampi(roundi(pixels.y), 16, 512))
	if viewport.size != wanted: viewport.size = wanted

## The figures of the battle as they stand now. The one shown stays.
func set_subjects(list: Array) -> void:
	subjects = list
	if _entry(subject).is_empty(): _next()

func _entry(id: int) -> Dictionary:
	for entry: Dictionary in subjects:
		if int(entry.id) == id and _alive(entry): return entry
	return {}

static func _alive(entry: Dictionary) -> bool:
	return is_instance_valid(entry.node) and entry.node.is_inside_tree()

## Moves on when the stay is over and keeps the camera on the figure.
## True when another figure is shown.
func step(delta: float) -> bool:
	if not active: return false
	var before := subject
	_age += delta
	if _age >= DWELL or _entry(subject).is_empty(): _next()
	var entry := _entry(subject)
	if not entry.is_empty(): _place(entry, delta)
	return subject != before

func _next() -> void:
	var at := -1
	for i in subjects.size():
		if int(subjects[i].id) == subject: at = i
	subject = -1
	for step_index in subjects.size():
		var entry: Dictionary = subjects[(at + 1 + step_index) % subjects.size()]
		if not _alive(entry): continue
		subject = int(entry.id)
		_age = 0.0
		_visits += 1
		_frame(entry)
		break

## The bounds of a figure's posed, visible meshes; a man's size where it has none.
static func bounds(node: Node3D) -> AABB:
	var box := AABB()
	var found := false
	var pending: Array = [node]
	while not pending.is_empty():
		var part: Node = pending.pop_back()
		pending.append_array(part.get_children())
		if part is not MeshInstance3D or part.mesh == null or not part.is_visible_in_tree(): continue
		var local: AABB = part.mesh.get_aabb()
		if node is ELModel and node.parts.get(String(part.name)) == part: local = node.posed_part_bounds(String(part.name))
		var here: AABB = part.global_transform * local
		box = here if not found else box.merge(here)
		found = true
	if not found or box.size.y < 0.05: return AABB(node.global_position - Vector3(0.4, 0, 0.4), Vector3(0.8, 1.7, 0.8))
	return box

## What part of a figure with these bounds is framed in a picture `aspect`
## times as wide as high: {"middle": Vector3, "span": its height in the world}.
static func framing(box: AABB, aspect: float) -> Dictionary:
	var across := maxf(box.size.x, box.size.z)
	var middle := box.get_center()
	if box.size.y >= across * UPRIGHT_FROM:
		# Upright: the head and chest, with a little air over the head.
		var span := maxf(box.size.y * UPRIGHT_SHARE, 0.4)
		middle.y = box.end.y - span * 0.44
		return {"middle": middle, "span": span}
	return {"middle": middle, "span": maxf(box.size.y, across / maxf(aspect, 0.1)) * 1.12}

## The height to frame for the whole of a figure with these bounds, with a
## little air round it. Its length counts as well as its width: a long
## creature turned towards the camera (a rat) stood so close that its
## snout filled the picture.
static func whole_span(box: AABB, aspect: float) -> float:
	var across := maxf(box.size.x, box.size.z)
	return maxf(box.size.y, maxf(across / maxf(aspect, 0.1), across * WHOLE_DEPTH)) * WHOLE_AIR

## The figure's parts of one kind (HEAD, SHOULDERS) that stand off the ground.
static func parts_named(node: Node3D, kind: Dictionary) -> Array:
	var found: Array = []
	var pending: Array = node.get_children()
	while not pending.is_empty():
		var part: Node = pending.pop_back()
		pending.append_array(part.get_children())
		if part is not Node3D: continue
		var name := String(part.name).to_lower()
		for wanted: String in kind.names:
			if name.contains(wanted) and part.global_position.y - node.global_position.y > 0.3: found.append(part)
	return found

static func _middle(parts: Array) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for part: Variant in parts:
		if is_instance_valid(part):
			sum += part.global_position
			count += 1
	return sum / count if count > 0 else Vector3.INF

func _frame(entry: Dictionary) -> void:
	var node: Node3D = entry.node
	_parts = []
	_aim = Vector3.INF
	# Heroes (ids 0 and 1) only: a creature framed on its head part or by the
	# top of its bounds showed little but a raised sword, or an ogre's chin.
	for kind: Dictionary in ([HEAD, SHOULDERS] if int(entry.id) < 2 else []):
		var found := parts_named(node, kind)
		if found.is_empty(): continue
		var height := _middle(found).y - node.global_position.y
		_parts = found
		_lift = height * float(kind.lift)
		_span = height * float(kind.span)
		break
	if _parts.is_empty():
		var box := bounds(node)
		_upright = int(entry.id) < 2 and box.size.y >= maxf(box.size.x, box.size.z) * UPRIGHT_FROM
		var aspect := float(viewport.size.x) / float(viewport.size.y)
		_span = framing(box, aspect).span if _upright else whole_span(box, aspect)
	_checked = 0.0
	_floor = -INF
	_floor_wanted = -INF
	_choose_side(entry, _target(node))

## The other figures as [centre, radius] each, for the line of sight.
func _others() -> Array:
	var others: Array = []
	for other: Dictionary in subjects:
		if int(other.id) == subject or not _alive(other): continue
		var box := bounds(other.node)
		others.append([box.get_center(), maxf(box.size.x, box.size.z) * 0.45])
	return others

## Takes the first side with nothing between the camera and its aim.
func _choose_side(entry: Dictionary, target: Vector3) -> void:
	var others := _others()
	var turn := 1.0 if _visits % 2 == 0 else -1.0
	_side = float(SIDES[0]) * turn
	_raise = RAISE_OVER
	for side: float in SIDES:
		if _blocked(_stand(entry, target, side * turn, RAISE), target, others): continue
		_side = side * turn
		_raise = RAISE
		break

func _target(node: Node3D) -> Vector3:
	var middle := _middle(_parts) if not _parts.is_empty() else Vector3.INF
	if middle != Vector3.INF: return middle + Vector3(0, _lift, 0)
	var box := bounds(node)
	middle = box.get_center()
	if _upright: middle.y = box.end.y - _span * 0.44
	return middle

## Where the camera stands to see `target` from `side` degrees off the front.
func _stand(entry: Dictionary, target: Vector3, side: float, raise: float) -> Vector3:
	var front: Vector3 = entry.get("facing", Vector3.FORWARD)
	front.y = 0.0
	front = front.normalized() if front.length() > 0.001 else Vector3.FORWARD
	var distance := (_span * 0.5) / tan(deg_to_rad(FOV) * 0.5)
	return target + (front.rotated(Vector3.UP, deg_to_rad(side)) + Vector3(0, raise, 0)).normalized() * distance

## Whether one of `others` ([centre, radius] each) stands on the line of sight.
static func _blocked(from: Vector3, target: Vector3, others: Array) -> bool:
	var line := target - from
	var length := line.length()
	if length < 0.001: return false
	for other: Array in others:
		var centre: Vector3 = other[0]
		var along := clampf((centre - from).dot(line) / (length * length), 0.0, 1.0)
		if (from + line * along).distance_to(centre) < float(other[1]): return true
	return false

func _place(entry: Dictionary, delta: float) -> void:
	var target := _target(entry.node)
	_aim = target if _aim == Vector3.INF else _aim.lerp(target, 1.0 - exp(-FOLLOW * delta))
	var drift := DRIFT * (clampf(_age / DWELL, 0.0, 1.0) - 0.5) * signf(_side)
	_checked += delta
	if _checked >= RECHECK:
		_checked = 0.0
		if _blocked(_stand(entry, _aim, _side + drift, _raise), _aim, _others()): _choose_side(entry, _aim)
	var from := _stand(entry, _aim, _side + drift, _raise)
	if _floor_wanted == -INF or _checked == 0.0: _floor_wanted = lowest_stand(from, _aim, ground)
	_floor = _floor_wanted if _floor == -INF else lerpf(_floor, _floor_wanted, 1.0 - exp(-FOLLOW * delta))
	from.y = maxf(from.y, _floor)
	camera.global_position = from
	if not from.is_equal_approx(_aim): camera.look_at(_aim, Vector3.UP)

## The lowest the camera at `from` may stand to keep CLEARANCE over the
## ground under it and SIGHT_CLEARANCE over the ground between it and `aim`
## (-INF when the arena's ground is not known).
static func lowest_stand(from: Vector3, aim: Vector3, ground_at: Callable) -> float:
	if not ground_at.is_valid(): return -INF
	var lowest := float(ground_at.call(from.x, from.z)) + CLEARANCE
	for t: float in SIGHT_SAMPLES:
		var point := from.lerp(aim, t)
		var needed := float(ground_at.call(point.x, point.z)) + SIGHT_CLEARANCE
		# The sight line at t is from.y + (aim.y - from.y) * t; solve for from.y.
		lowest = maxf(lowest, (needed - aim.y * t) / (1.0 - t))
	return lowest
