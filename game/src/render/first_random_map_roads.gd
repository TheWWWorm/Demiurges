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
	var recipe := ELFirstRandomMap.configuration(map)
	var wilderness := int(recipe.get("version", 0)) >= ELFirstRandomMapV2.WILDERNESS_VERSION
	var phase := (ELFirstRandomMap.seed_for_config(recipe) % 630) * 0.01 if wilderness else 0.0
	var trails := _trail_network(map) if wilderness else {}
	for y in map.height:
		for x in map.width:
			var point := Vector2i(x, y)
			if not _road(map, point): continue
			road_cells += 1
			if wilderness:
				_draw_trail(map, point, phase, trails)
				continue
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

func _draw_trail(map: ELAdventureMap, point: Vector2i, phase: float, network: Dictionary) -> void:
	var primary := map.roads[point.y * map.width + point.x] == 6
	var width := _trail_width(point, phase, primary)
	var start := _trail_point(point, phase)
	var shade := Color(0.40, 0.31, 0.205, 0.78) if primary else Color(0.38, 0.285, 0.18, 0.58)
	var neighbors: Array = network.get(point, [])
	for target: Vector2i in neighbors:
		var delta := target - point
		if delta.y < 0 or (delta.y == 0 and delta.x < 0): continue
		var next_width := _trail_width(target, phase, map.roads[target.y * map.width + target.x] == 6)
		var end := _trail_point(target, phase)
		var reach := start.distance_to(end) * 0.37
		var leaving := _trail_tangent(neighbors, target, start, phase)
		var arriving := _trail_tangent(network[target], point, end, phase)
		_trail_curve(start, end, start + leaving * reach, end + arriving * reach, shade, Vector2(width, next_width))
	if neighbors.size() != 2: _cap(start, shade, width)

static func _trail_network(map: ELAdventureMap) -> Dictionary:
	var links := {}
	var primary: Array[Vector4i] = []
	var secondary: Array[Vector4i] = []
	for y in map.height:
		for x in map.width:
			var point := Vector2i(x, y)
			if not _road(map, point): continue
			for index in 4:
				var delta: Vector2i = DIRECTIONS[index]
				var target := point + delta
				if not _road(map, target): continue
				if delta.x != 0 and delta.y != 0 and (_road(map, point + Vector2i(delta.x, 0)) or _road(map, point + Vector2i(0, delta.y))): continue
				var trunk := map.roads[y * map.width + x] == 6 and map.roads[target.y * map.width + target.x] == 6
				var band := primary if trunk else secondary
				band.append(Vector4i(x, y, target.x, target.y))
	# Reuse nearby junctions where two routes would otherwise draw a little
	# ring of dirt. Longer loops, such as roads around a lake, still show.
	for edges in [primary, secondary]:
		for edge: Vector4i in edges:
			var a := Vector2i(edge.x, edge.y)
			var b := Vector2i(edge.z, edge.w)
			if _short_trail_connection(links, a, b): continue
			links.get_or_add(a, []).append(b)
			links.get_or_add(b, []).append(a)
	return links

static func _short_trail_connection(links: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if not links.has(from) or not links.has(to): return false
	var visited := {from: true}
	var frontier: Array[Vector2i] = [from]
	for step in 5:
		var next: Array[Vector2i] = []
		for point: Vector2i in frontier:
			for adjacent: Vector2i in links[point]:
				if adjacent == to: return true
				if not visited.has(adjacent):
					visited[adjacent] = true
					next.append(adjacent)
		if next.is_empty(): break
		frontier = next
	return false

static func _trail_tangent(neighbors: Array, toward: Vector2i, center: Vector3, phase: float) -> Vector3:
	if neighbors.size() == 2:
		var anchor: Vector2i = neighbors[0] if neighbors[0] != toward else neighbors[1]
		center = _trail_point(anchor, phase)
	return (_trail_point(toward, phase) - center).normalized()

func _trail_curve(a: Vector3, b: Vector3, control_a: Vector3, control_b: Vector3, shade: Color, widths: Vector2) -> void:
	var previous := a
	var across := _trail_normal(control_a - a)
	for step in range(1, 4):
		var blend := float(step) / 3.0
		var at := a.bezier_interpolate(control_a, control_b, b, blend)
		var next_across := _trail_normal(a.bezier_derivative(control_a, control_b, b, blend))
		_strip(previous, at, across, next_across, shade, lerpf(widths.x, widths.y, blend - 1.0 / 3.0), lerpf(widths.x, widths.y, blend))
		previous = at
		across = next_across

static func _trail_normal(direction: Vector3) -> Vector3:
	return Vector3(-direction.z, 0, direction.x).normalized()

static func _trail_width(point: Vector2i, phase: float, primary: bool) -> float:
	return (1.06 if primary else 0.65) + 0.17 * sin(point.x * 0.222 + point.y * 0.195 + phase)

static func _trail_point(point: Vector2i, phase: float) -> Vector3:
	var x := sin(0.49 * point.y + 0.18 * point.x + phase) * 0.30
	var z := sin(0.51 * point.x - 0.20 * point.y - phase) * 0.30
	return _world(point) + Vector3(x, 0, z)

func _ribbon(a: Vector3, b: Vector3, color: Color) -> void:
	var across := _trail_normal(b - a)
	_strip(a, b, across, across, color, 1.0, 1.0)

func _strip(a: Vector3, b: Vector3, across_a: Vector3, across_b: Vector3, color: Color, start_width: float, end_width: float) -> void:
	var inner_a := across_a * (INNER * ELAdventureTerrain.CELL * start_width)
	var outer_a := across_a * (OUTER * ELAdventureTerrain.CELL * start_width)
	var inner_b := across_b * (INNER * ELAdventureTerrain.CELL * end_width)
	var outer_b := across_b * (OUTER * ELAdventureTerrain.CELL * end_width)
	var clear := Color(color, 0.0)
	_quad(a - inner_a, b - inner_b, b + inner_b, a + inner_a, color, color, color, color)
	_quad(a - outer_a, b - outer_b, b - inner_b, a - inner_a, clear, clear, color, color)
	_quad(a + inner_a, b + inner_b, b + outer_b, a + outer_a, color, color, clear, clear)

func _cap(at: Vector3, color: Color, width := 1.0) -> void:
	var clear := Color(color, 0.0)
	for index in 8:
		var a := Vector3(cos(TAU * index / 8.0), 0, sin(TAU * index / 8.0))
		var b := Vector3(cos(TAU * (index + 1) / 8.0), 0, sin(TAU * (index + 1) / 8.0))
		var ai := at + a * (INNER * ELAdventureTerrain.CELL * width)
		var bi := at + b * (INNER * ELAdventureTerrain.CELL * width)
		_triangle(at, ai, bi, color, color, color)
		_quad(ai, at + a * (OUTER * ELAdventureTerrain.CELL * width), at + b * (OUTER * ELAdventureTerrain.CELL * width), bi, color, clear, clear, color)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_triangle(a, b, c, ca, cb, cc)
	_triangle(a, c, d, ca, cc, cd)

func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_vertices.append_array([a, b, c])
	_colors.append_array([ca, cb, cc])
	for point: Vector3 in [a, b, c]:
		var cell := Vector2(point.x, -point.z) / ELAdventureTerrain.CELL
		_uvs.append((cell + Vector2(0.5, 0.5)) / Vector2(_map_size + Vector2i.ONE))
