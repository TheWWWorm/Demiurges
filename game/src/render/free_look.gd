class_name ELFreeLook
extends Node
## First-person view of a battle (the "first_person" hotkey, F by
## default): the battle camera is handed to a walker on the arena's ground,
## to run around the field and look at the figures up close. The battle
## itself goes on; its camera, panels and clicks wait until the view is left.
##
##   mouse         look around (the pointer is captured)
##   W A S D       walk (arrows too), Shift runs
##   Space / Ctrl  raise / lower the eye (also the wheel)
##   Esc or the hotkey again   back to the battle view

signal left

## The eye without a hero to measure; with one, at this share of its height.
const EYE := 1.6
const EYE_OF_HEIGHT := 0.93
const EYE_LIMITS := Vector2(0.25, 12.0)
const WALK := 4.0
const RUN := 11.0
const LOOK := 0.0025
const FOV := 70.0
## How far from the arena's middle the walker may go.
const REACH := 60.0

var active := false
var camera: Camera3D
## (x, z) -> the ground's height there.
var ground: Callable
var eye := EYE
var _yaw := 0.0
var _pitch := 0.0
var _saved_transform := Transform3D()
var _saved_fov := 0.0
var _saved_mouse := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	set_process(false)

## Takes the camera, standing on the ground under the point the camera
## looks at, a little way back toward it, facing the same way.
func enter(view_camera: Camera3D, ground_height: Callable, eye_height := EYE) -> void:
	if active or view_camera == null: return
	camera = view_camera
	ground = ground_height
	_saved_transform = camera.global_transform
	_saved_fov = camera.fov
	_saved_mouse = Input.mouse_mode
	var forward := -camera.global_transform.basis.z
	var flat := Vector3(forward.x, 0, forward.z)
	if flat.length() < 0.01: flat = Vector3(0, 0, -1)
	flat = flat.normalized()
	# Where the view's line of sight meets the ground, then 8 units back.
	var start := camera.global_position
	if forward.y < -0.05: start += forward * ((start.y - _height(start.x, start.z)) / -forward.y)
	start -= flat * 8.0
	_yaw = atan2(-flat.x, -flat.z)
	_pitch = -0.1
	eye = clampf(eye_height, EYE_LIMITS.x, EYE_LIMITS.y)
	camera.global_position = Vector3(start.x, _height(start.x, start.z) + eye, start.z)
	camera.fov = FOV
	_orient()
	active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_process(true)

func leave() -> void:
	if not active: return
	active = false
	set_process(false)
	Input.mouse_mode = _saved_mouse
	if is_instance_valid(camera):
		camera.global_transform = _saved_transform
		camera.fov = _saved_fov
	left.emit()

## Mouse looks and the wheel lifts the eye; true when the event was taken.
func handle(event: InputEvent) -> bool:
	if not active: return false
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * LOOK
		_pitch = clampf(_pitch - event.relative.y * LOOK, -1.5, 1.5)
		_orient()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		eye = clampf(eye + (0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25), EYE_LIMITS.x, EYE_LIMITS.y)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		leave()
	return true

func _process(delta: float) -> void:
	if not active or not is_instance_valid(camera):
		if active: leave()
		return
	# A window that lost the pointer (Alt+Tab) takes it again on return.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and get_window().has_focus(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var ahead := _pressed(KEY_W) or _pressed(KEY_UP)
	var back := _pressed(KEY_S) or _pressed(KEY_DOWN)
	var right := _pressed(KEY_D) or _pressed(KEY_RIGHT)
	var left_key := _pressed(KEY_A) or _pressed(KEY_LEFT)
	var move := Vector2(float(right) - float(left_key), float(back) - float(ahead))
	var lift := float(_pressed(KEY_SPACE)) - float(_pressed(KEY_CTRL))
	if lift != 0.0: eye = clampf(eye + lift * 2.5 * delta, EYE_LIMITS.x, EYE_LIMITS.y)
	var at := camera.global_position
	if move != Vector2.ZERO:
		var speed := RUN if _pressed(KEY_SHIFT) else WALK
		var step := move.normalized().rotated(-_yaw) * speed * delta
		at.x += step.x
		at.z += step.y
		var flat := Vector2(at.x, at.z)
		if flat.length() > REACH:
			flat = flat.normalized() * REACH
			at.x = flat.x
			at.z = flat.y
	# The eye keeps its height over the ground as the field rises and falls.
	at.y = lerpf(at.y, _height(at.x, at.z) + eye, minf(1.0, delta * 12.0))
	camera.global_position = at

func _orient() -> void:
	camera.global_transform.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0), EULER_ORDER_YXZ)

func _height(x: float, z: float) -> float:
	return float(ground.call(x, z)) if ground.is_valid() else 0.0

static func _pressed(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)
