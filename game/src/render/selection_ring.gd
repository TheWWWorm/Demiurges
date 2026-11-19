class_name ELSelectionRing
extends Node3D
## Animated ground ring of the adventure map under the hovered object and the
## selected hero (both games). The art is Interface\Selection00/01: 8×8 frames
## of 64 px, each texture holding two colours of 32 frames. The colour follows
## the local player's race colour; one authored frame per 64 ms map tick.
## The GPU blends consecutive frames to keep the original animation fluid at
## display refresh rates. Frame samples never cross into another race's row.

const TICK := 0.064
const FRAMES := 32
const RING_SHADER := preload("res://src/render/selection_ring.gdshader")
const EDGE_TEXTURE := &"selection_edge_texture"
## Ring half-extent per unit of object radius (4.5 / 2).
const SPREAD := 2.25
## Object radius (the view object's): 0.7 × the larger footprint side
## for objects given a size (: buildings, terrain objects, shops,
## forts, mines), 1 cell = 2 units; otherwise the constructor's 1.0 world
## unit, which the second game's heroes keep (no size call on that path).
## The first game's non-building view objects return 1.0 outright;
## its buildings use 0.7 × the larger side.
const RADIUS_PER_CELL := 0.7
## Size passed for an object with no footprint size: radius 1.0.
const NO_SIZE := Vector2i.ZERO
const HOVER_SIZE := 0.85
const HOVER_LIGHT := 0.5
## Colour index (Red, Green, Blue, Black) -> texture and half (0 top, 1 bottom).
const ATLAS := [[0, 1], [1, 1], [1, 0], [0, 0]]
## Second game danger pulse: a triangle wave over 32 ticks takes
## the ring to 70 % size and 40 % opacity at its peak and back.
const PULSE_SIZE := 0.3
const PULSE_FADE := 0.6

var textures: Array[Texture2D] = []
var colour := 0
var hover_uid := -1
var selected_uid := -1
var _clock := 0.0
var _selected_age := 0.0
## Seconds the selected ring has been pulsing; -1 when it is not.
var _pulse_age := -1.0
var _hover: MeshInstance3D
var _selected: MeshInstance3D

func setup(profile: ELProfile) -> bool:
	textures.clear()
	for name: String in ["Interface/Selection00", "Interface/Selection01"]:
		var texture := profile.texture(name)
		if texture == null: return false
		textures.append(_edge_texture(texture))
	_hover = _quad()
	_selected = _quad()
	return true

## Prepare only the two selection atlases, once per source texture. Bilinear
## filtering happens before the shader sees a texel: invisible black/magenta
## RGB would otherwise fringe the artwork even with correct frame blending.
## Preserve visible pixels and alpha; other users retain the original texture.
static func _edge_texture(source: Texture2D) -> Texture2D:
	if source.has_meta(EDGE_TEXTURE): return source.get_meta(EDGE_TEXTURE) as Texture2D
	# Repair must stay inside each authored frame, just like the shader's
	# samples. A neighbouring frame or race can have a different edge colour.
	if source.get_width() < 16 or source.get_height() < 16 or source.get_width() % 8 != 0 or source.get_height() % 8 != 0: return source
	var image := source.get_image()
	if image == null or image.is_empty(): return source
	image = image.duplicate()
	if image.is_compressed() and image.decompress() != OK: return source
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	if image.has_mipmaps(): image.clear_mipmaps()
	var cell := Vector2i(image.get_width() / 8, image.get_height() / 8)
	for row in 8:
		for column in 8:
			var at := Vector2i(column, row) * cell
			var frame := image.get_region(Rect2i(at, cell))
			frame.fix_alpha_edges()
			image.blit_rect(frame, Rect2i(Vector2i.ZERO, cell), at)
	var prepared := ImageTexture.create_from_image(image)
	source.set_meta(EDGE_TEXTURE, prepared)
	return prepared

func _quad() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2, 2)
	node.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	material.render_priority = 1
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.set_meta("raster_only", true)
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

## Pulse phase 0..1..0 over 32 ticks (folded at 16).
static func pulse_phase(seconds: float) -> float:
	var tick := fposmod(seconds / TICK, float(FRAMES))
	if tick > FRAMES / 2: tick = FRAMES - tick
	return float(tick) / float(FRAMES / 2)

## Animation frame (0..31) after the given time on the map.
static func frame_at(seconds: float) -> int:
	return int(floor(seconds / TICK)) % FRAMES

## Atlas offset of a frame in a colour.
static func frame_offset(index: int, frame: int) -> Vector2:
	var half: int = ATLAS[clampi(index, 0, 3)][1]
	return Vector2((frame % 8) * 0.125, (frame / 8) * 0.125 + half * 0.5)

## Half-extent in world units of a ring around a footprint of the given size.
static func half_extent(size: Vector2i, scale: float) -> float:
	if size == NO_SIZE: return SPREAD * scale
	return SPREAD * scale * RADIUS_PER_CELL * float(maxi(size.x, size.y)) * ELAdventureTerrain.CELL * 0.5

## Shows the rings: hover at `hover_at` (ignored when hover is -1) and the
## selected one at `selected_at`; positions are ground points.
func show_rings(delta: float, hover: int, hover_at: Vector3, hover_size: Vector2i, selected: int, selected_at: Vector3, selected_size_cells: Vector2i, selected_pulse := false) -> void:
	if textures.is_empty(): return
	_clock = fposmod(_clock + maxf(delta, 0.0), TICK * FRAMES)
	if selected != selected_uid: _selected_age = 0.0
	else: _selected_age += delta
	selected_uid = selected
	hover_uid = hover if hover != selected else -1
	if not selected_pulse or selected_uid < 0: _pulse_age = -1.0
	elif _pulse_age < 0.0: _pulse_age = 0.0
	else: _pulse_age += delta
	var frame := frame_at(_clock)
	_place(_hover, hover_uid >= 0, hover_at, hover_size, HOVER_SIZE, HOVER_LIGHT, frame)
	var t := pulse_phase(_pulse_age) if _pulse_age >= 0.0 else 0.0
	_place(_selected, selected_uid >= 0, selected_at, selected_size_cells, selected_size(_selected_age) * (1.0 - PULSE_SIZE * t), selected_light(_selected_age), frame, 1.0 - PULSE_FADE * t)

func hide_rings() -> void:
	if _hover != null: _hover.visible = false
	if _selected != null: _selected.visible = false

func _place(node: MeshInstance3D, shown: bool, at: Vector3, size: Vector2i, scale: float, light: float, frame: int, alpha := 1.0) -> void:
	node.visible = shown
	if not shown: return
	var half := half_extent(size, scale)
	node.position = at + Vector3(0, 0.03, 0)
	node.scale = Vector3(half, 1, half)
	var material: ShaderMaterial = node.material_override
	var texture := textures[ATLAS[clampi(colour, 0, 3)][0]]
	material.set_shader_parameter("ring_atlas", texture)
	material.set_shader_parameter("frame_from", frame_offset(colour, frame))
	material.set_shader_parameter("frame_to", frame_offset(colour, (frame + 1) % FRAMES))
	material.set_shader_parameter("frame_mix", fposmod(_clock / TICK, 1.0))
	material.set_shader_parameter("ring_modulate", Color(minf(light, 1.0), minf(light, 1.0), minf(light, 1.0), alpha))
	# An undersized or irregular replacement atlas still draws, but gets no
	# extra contour. Normal and upscaled 8 x 8 atlases both use their real texels.
	var grid := texture.get_width() >= 16 and texture.get_height() >= 16 and texture.get_width() % 8 == 0 and texture.get_height() % 8 == 0
	material.set_shader_parameter("outline_strength", 0.44 if grid else 0.0)
	# Light above 1 brightens towards white (the brief flash on selection).
	material.set_shader_parameter("ring_flash", Color.WHITE * maxf(0.0, light - 1.0))
