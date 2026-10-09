class_name ELSelectionRing
extends Node3D
## Animated ground ring of the adventure map under the hovered object and the
## selected hero (both games). The art is Interface\Selection00/01: 8×8 frames
## of 64 px, each texture holding two colours of 32 frames. The colour follows
## the local player's race colour; one frame per 64 ms map tick.

const TICK := 0.064
const FRAMES := 32
## Ring half-extent per unit of object radius (4.5 / 2).
const SPREAD := 2.25
## Object radius: 0.7 × the larger footprint side (cells), 1 cell = 2 units.
const RADIUS_PER_CELL := 0.7
const HOVER_SIZE := 0.85
const HOVER_LIGHT := 0.5
## Colour index (Red, Green, Blue, Black) -> texture and half (0 top, 1 bottom).
const ATLAS := [[0, 1], [1, 1], [1, 0], [0, 0]]

var textures: Array[Texture2D] = []
var colour := 0
var hover_uid := -1
var selected_uid := -1
var _clock := 0.0
var _selected_age := 0.0
var _hover: MeshInstance3D
var _selected: MeshInstance3D

func setup(profile: ELProfile) -> bool:
	textures.clear()
	for name: String in ["Interface/Selection00", "Interface/Selection01"]:
		var texture := profile.texture(name)
		if texture == null: return false
		textures.append(texture)
	_hover = _quad()
	_selected = _quad()
	return true

func _quad() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2, 2)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.uv1_scale = Vector3(0.125, 0.125, 1)
	material.render_priority = 1
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node

## Colour index of a race colour name; other colours use the first entry.
static func colour_index(name: String) -> int:
	return maxi(0, ["Red", "Green", "Blue", "Black"].find(name))

## Ring scale while selected: 0.85 → 1.2 over 0.2 s, back to 1.0 by 0.6 s.
static func selected_size(age: float) -> float:
	if age >= 0.6: return 1.0
	if age <= 0.2: return HOVER_SIZE + (1.2 - HOVER_SIZE) * age / 0.2
	return 1.0 + (1.2 - 1.0) * (0.4 - (age - 0.2)) / 0.4

## Ring light while selected: 0.5 → 1.1 over 0.2 s, back to 1.0 by 0.6 s.
static func selected_light(age: float) -> float:
	if age >= 0.6: return 1.0
	if age <= 0.2: return HOVER_LIGHT + (1.1 - HOVER_LIGHT) * age / 0.2
	return 1.0 + (1.1 - 1.0) * (0.4 - (age - 0.2)) / 0.4

## Animation frame (0..31) after the given time on the map.
static func frame_at(seconds: float) -> int:
	return int(floor(seconds / TICK)) % FRAMES

## Atlas offset of a frame in a colour.
static func frame_offset(index: int, frame: int) -> Vector2:
	var half: int = ATLAS[clampi(index, 0, 3)][1]
	return Vector2((frame % 8) * 0.125, (frame / 8) * 0.125 + half * 0.5)

## Half-extent in world units of a ring around a footprint of the given size.
static func half_extent(size: Vector2i, scale: float) -> float:
	return SPREAD * scale * RADIUS_PER_CELL * float(maxi(size.x, size.y)) * ELAdventureTerrain.CELL * 0.5

## Shows the rings: hover at `hover_at` (ignored when hover is -1) and the
## selected one at `selected_at`; positions are ground points.
func show_rings(delta: float, hover: int, hover_at: Vector3, hover_size: Vector2i, selected: int, selected_at: Vector3, selected_size_cells: Vector2i) -> void:
	if textures.is_empty(): return
	_clock += delta
	if selected != selected_uid: _selected_age = 0.0
	else: _selected_age += delta
	selected_uid = selected
	hover_uid = hover if hover != selected else -1
	var frame := frame_at(_clock)
	_place(_hover, hover_uid >= 0, hover_at, hover_size, HOVER_SIZE, HOVER_LIGHT, frame)
	_place(_selected, selected_uid >= 0, selected_at, selected_size_cells, selected_size(_selected_age), selected_light(_selected_age), frame)

func hide_rings() -> void:
	if _hover != null: _hover.visible = false
	if _selected != null: _selected.visible = false

func _place(node: MeshInstance3D, shown: bool, at: Vector3, size: Vector2i, scale: float, light: float, frame: int) -> void:
	node.visible = shown
	if not shown: return
	var half := half_extent(size, scale)
	node.position = at + Vector3(0, 0.03, 0)
	node.scale = Vector3(half, 1, half)
	var material: StandardMaterial3D = node.material_override
	material.albedo_texture = textures[ATLAS[clampi(colour, 0, 3)][0]]
	material.uv1_offset = Vector3(frame_offset(colour, frame).x, frame_offset(colour, frame).y, 0)
	material.albedo_color = Color(minf(light, 1.0), minf(light, 1.0), minf(light, 1.0))
	# Light above 1 brightens towards white (the brief flash on selection).
	material.emission_enabled = light > 1.0
	if light > 1.0: material.emission = Color.WHITE * (light - 1.0)
