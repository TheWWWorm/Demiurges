class_name ELGroundHeightIndex
extends RefCounted
## Read-only spatial index of an arena's authored ground triangles. Queries
## keep the original first-hit order and barycentric tolerance, including
## overlapping decks and points just outside a triangle's drawn edge.

const EDGE_EPSILON := 0.001
const MIN_DETERMINANT := 0.00001
const GRID_SIDE := 32.0
const MIN_CELL_SIZE := 1.0

var _vertices := PackedVector3Array()
var _buckets: Dictionary = {}
var _cell_size := MIN_CELL_SIZE
## Useful for diagnostics without adding work to each query.
var triangle_count := 0
var bucket_references := 0

func build(figures: Dictionary) -> void:
	_vertices.clear()
	_buckets.clear()
	triangle_count = 0
	bucket_references = 0
	var bounds := Rect2()
	var first := true
	for figure: Dictionary in figures.values():
		var vertices: PackedVector3Array = figure.arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = figure.arrays[Mesh.ARRAY_INDEX]
		for at in range(0, indices.size(), 3):
			var a := vertices[indices[at]]
			var b := vertices[indices[at + 1]]
			var c := vertices[indices[at + 2]]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ac := Vector2(c.x - a.x, c.z - a.z)
			if absf(ab.cross(ac)) < MIN_DETERMINANT: continue
			_vertices.append(a)
			_vertices.append(b)
			_vertices.append(c)
			var box := _triangle_bounds(a, b, c)
			bounds = box if first else bounds.merge(box)
			first = false
	triangle_count = _vertices.size() / 3
	if first: return
	# A bounded grid also handles unusually large scenery without allocating
	# a dictionary entry for every square world unit of a giant triangle.
	_cell_size = maxf(MIN_CELL_SIZE, maxf(bounds.size.x, bounds.size.y) / GRID_SIDE)
	for at in range(0, _vertices.size(), 3):
		var box := _triangle_bounds(_vertices[at], _vertices[at + 1], _vertices[at + 2])
		var low := _cell(box.position)
		var high := _cell(box.end)
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var key := Vector2i(x, y)
				# Array has reference semantics: appending does not copy every
				# previously inserted index, as a packed array in a dictionary can.
				var bucket: Array = _buckets.get_or_add(key, [])
				bucket.append(at)
				bucket_references += 1

static func _triangle_bounds(a: Vector3, b: Vector3, c: Vector3) -> Rect2:
	var origin := Vector2(a.x, a.z)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	# u >= -e, v >= -e, u + v <= 1 + e defines a slightly larger triangle.
	# Index that exact region; a plain vertex AABB would lose tolerated hits
	# on cell boundaries. Tiny padding covers single-precision vector rounding.
	var p := origin - EDGE_EPSILON * (ab + ac)
	var q := origin + ab + EDGE_EPSILON * (2.0 * ab - ac)
	var r := origin + ac + EDGE_EPSILON * (2.0 * ac - ab)
	return Rect2(p, Vector2.ZERO).expand(q).expand(r).grow(0.00001)

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / _cell_size), floori(point.y / _cell_size))

func height(x: float, z: float) -> float:
	var point := Vector2(x, z)
	for at: int in _buckets.get(_cell(point), []):
		var a := _vertices[at]
		var b := _vertices[at + 1]
		var c := _vertices[at + 2]
		var va := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - va
		var ac := Vector2(c.x, c.z) - va
		var determinant := ab.cross(ac)
		var u := (point - va).cross(ac) / determinant
		var v := ab.cross(point - va) / determinant
		if u >= -EDGE_EPSILON and v >= -EDGE_EPSILON and u + v <= 1.0 + EDGE_EPSILON:
			return a.y + (b.y - a.y) * u + (c.y - a.y) * v
	return 0.0

func candidates_at(x: float, z: float) -> int:
	return (_buckets.get(_cell(Vector2(x, z)), []) as Array).size()
