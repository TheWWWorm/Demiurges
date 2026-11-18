class_name ELFirstRandomMapRoads
extends Node3D
## A single batched, softly edged earth surface for generated-map roads.
## The original road bytes still own movement cost and minimap markings.
## StandardMaterial3D works in Compatibility, Mobile and Forward+; no
## proprietary texture or custom lighting shader is needed.

const HEIGHT := 0.025
const INNER := 0.17
const OUTER := 0.30
const EARTH := Color(0.34, 0.26, 0.17, 0.84)
const DIRECTIONS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
var surface: MeshInstance3D
var vertex_count := 0
var road_cells := 0
var visibility_texture: ImageTexture
## CPU copy of the exact current mask sent to the renderer. This also makes
## fog diagnostics possible with Godot's headless dummy texture backend.
var visibility_image: Image
var _map_size := Vector2i.ZERO
var _material: StandardMaterial3D
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()

func build(map: ELAdventureMap) -> bool:
	if surface != null:
		surface.free()
		surface = null
	_vertices.clear()
	_colors.clear()
	_uvs.clear()
	visibility_texture = null
	visibility_image = null
	_material = null
	vertex_count = 0
	road_cells = 0
	if map == null or not ELFirstRandomMap.is_random_id(map.id) or map.roads.size() != map.width * map.height: return false
	_map_size = Vector2i(map.width, map.height)
	for y in map.height:
		for x in map.width:
			var point := Vector2i(x, y)
			if not _road(map, point): continue
			road_cells += 1
			var shade := EARTH
			var grain := 0.94 + float((x * 37 + y * 71) % 17) / 136.0
			shade.r *= grain
			shade.g *= grain
			shade.b *= grain
			var neighbours: Array[Vector2i] = []
			for direction: Vector2i in DIRECTIONS:
				if _road(map, point + direction): neighbours.append(direction)
			# Each undirected connection is drawn once. Straight segments need
			# no cap; bends, crossings and endpoints have a small feathered disc.
			for direction: Vector2i in DIRECTIONS.slice(0, 4):
				if _road(map, point + direction): _ribbon(_world(point), _world(point + direction), shade)
			if neighbours.size() != 2 or neighbours[0] + neighbours[1] != Vector2i.ZERO: _cap(_world(point), shade)
	if _vertices.is_empty(): return true
	var normals := PackedVector3Array()
	normals.resize(_vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.texture_repeat = false
	_material = material
	surface = MeshInstance3D.new()
	surface.name = "GeneratedRoadSurface"
	surface.mesh = mesh
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The scene applies its fog immediately after build. A frame between
	# those calls must not reveal the hidden road network.
	surface.visible = false
	add_child(surface)
	vertex_count = _vertices.size()
	_vertices.clear()
	_colors.clear()
	_uvs.clear()
	return true

## Scene fog bytes: visible 0, remembered 133, unknown 255. Empty means
## fog is disabled. Corner maxima and UVs match the terrain's fog sampler,
## keeping unknown roads invisible even at a linearly filtered boundary.
func set_fog(tiles: PackedByteArray) -> void:
	if surface == null or _material == null: return
	if not tiles.is_empty() and tiles.size() != _map_size.x * _map_size.y:
		surface.visible = false
		return
	var image := Image.create(_map_size.x + 1, _map_size.y + 1, false, Image.FORMAT_RGBA8)
	if tiles.is_empty(): image.fill(Color.WHITE)
	else:
		for y in range(_map_size.y + 1):
			for x in range(_map_size.x + 1):
				var fog := 255
				if x > 0 and y > 0 and x < _map_size.x and y < _map_size.y:
					var at := y * _map_size.x + x
					fog = maxi(maxi(tiles[at], tiles[at - 1]), maxi(tiles[at - _map_size.x], tiles[at - _map_size.x - 1]))
				image.set_pixel(x, y, Color(0, 0, 0, 0) if fog >= 255 else (Color(0.3, 0.3, 0.3, 1) if fog > 0 else Color.WHITE))
	visibility_image = image
	if visibility_texture == null:
		visibility_texture = ImageTexture.create_from_image(image)
		_material.albedo_texture = visibility_texture
	else: visibility_texture.update(image)
	surface.visible = true

static func _road(map: ELAdventureMap, point: Vector2i) -> bool:
	if point.x < 0 or point.y < 0 or point.x >= map.width or point.y >= map.height: return false
	var value := int(map.roads[point.y * map.width + point.x])
	return value > 4 and value < 9

static func _world(point: Vector2i) -> Vector3:
	return Vector3((point.x + 0.5) * ELAdventureTerrain.CELL, HEIGHT, -(point.y + 0.5) * ELAdventureTerrain.CELL)

func _ribbon(a: Vector3, b: Vector3, color: Color) -> void:
	var along := (b - a).normalized()
	var across := Vector3(-along.z, 0, along.x)
	var inner := across * INNER * ELAdventureTerrain.CELL
	var outer := across * OUTER * ELAdventureTerrain.CELL
	var clear := Color(color, 0.0)
	_quad(a - inner, b - inner, b + inner, a + inner, color, color, color, color)
	_quad(a - outer, b - outer, b - inner, a - inner, clear, clear, color, color)
	_quad(a + inner, b + inner, b + outer, a + outer, color, color, clear, clear)

func _cap(at: Vector3, color: Color) -> void:
	var clear := Color(color, 0.0)
	for index in 8:
		var a := Vector3(cos(TAU * index / 8.0), 0, sin(TAU * index / 8.0))
		var b := Vector3(cos(TAU * (index + 1) / 8.0), 0, sin(TAU * (index + 1) / 8.0))
		var ai := at + a * INNER * ELAdventureTerrain.CELL
		var bi := at + b * INNER * ELAdventureTerrain.CELL
		_triangle(at, ai, bi, color, color, color)
		_quad(ai, at + a * OUTER * ELAdventureTerrain.CELL, at + b * OUTER * ELAdventureTerrain.CELL, bi, color, clear, clear, color)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_triangle(a, b, c, ca, cb, cc)
	_triangle(a, c, d, ca, cc, cd)

func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_vertices.append_array([a, b, c])
	_colors.append_array([ca, cb, cc])
	for point: Vector3 in [a, b, c]:
		var cell := Vector2(point.x, -point.z) / ELAdventureTerrain.CELL
		_uvs.append((cell + Vector2(0.5, 0.5)) / Vector2(_map_size + Vector2i.ONE))
