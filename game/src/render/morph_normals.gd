extends RefCounted
## Transport the artist's vertex normals with a morph's deformation, once
## while its cached mesh is built. Reusing the rest-pose normals made bending
## bodies and wings keep the rest pose's shading and metal highlights.
##
## Each triangle supplies a local deformation and its inverse transpose for
## normals. The third basis axis scales with the square root of its area, so
## rigid motion and uniform scaling preserve the authored shading exactly.
## Corner-angle weights join only the same source vertex AND authored normal:
## UV seams stay smooth while deliberately split normals keep their hard edge.

static func prepare(arrays: Array, source_indices: PackedInt32Array) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if vertices.is_empty() or normals.size() != vertices.size(): return {}
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size() - vertices.size() % 3)
		for index in indices.size(): indices[index] = index
	var groups := PackedInt32Array()
	groups.resize(vertices.size())
	var group_normals := PackedVector3Array()
	var by_source := {}
	for index in vertices.size():
		var source := source_indices[index] if index < source_indices.size() else index
		var at_source: Dictionary = by_source.get(source, {})
		if not at_source.has(normals[index]):
			at_source[normals[index]] = group_normals.size()
			group_normals.append(normals[index])
			by_source[source] = at_source
		groups[index] = at_source[normals[index]]
	var faces := PackedInt32Array()
	var weights := PackedFloat32Array()
	var bases: Array[Basis] = []
	for at in range(0, indices.size() - 2, 3):
		var a := indices[at]
		var b := indices[at + 1]
		var c := indices[at + 2]
		if mini(a, mini(b, c)) < 0 or maxi(a, maxi(b, c)) >= vertices.size(): continue
		var ab := vertices[b] - vertices[a]
		var ac := vertices[c] - vertices[a]
		var bc := vertices[c] - vertices[b]
		var cross := ab.cross(ac)
		if _degenerate(ab, ac, cross): continue
		faces.append_array([a, b, c])
		bases.append(Basis(ab, ac, cross / sqrt(cross.length())).transposed())
		var angle_a := acos(clampf(ab.normalized().dot(ac.normalized()), -1.0, 1.0))
		var angle_b := acos(clampf((-ab).normalized().dot(bc.normalized()), -1.0, 1.0))
		weights.append_array([angle_a, angle_b, maxf(0.0, PI - angle_a - angle_b)])
	return {"vertices": vertices, "normals": normals, "groups": groups, "group_normals": group_normals,
		"faces": faces, "bases": bases, "weights": weights}

static func for_pose(rest: Dictionary, vertices: PackedVector3Array) -> PackedVector3Array:
	if rest.is_empty(): return PackedVector3Array()
	var authored: PackedVector3Array = rest.normals
	if vertices.size() != authored.size() or vertices == rest.vertices: return authored
	var group_normals: PackedVector3Array = rest.group_normals
	var groups: PackedInt32Array = rest.groups
	var faces: PackedInt32Array = rest.faces
	var weights: PackedFloat32Array = rest.weights
	var bases: Array[Basis] = rest.bases
	var summed := PackedVector3Array()
	summed.resize(group_normals.size())
	for at in range(0, faces.size(), 3):
		var ab := vertices[faces[at + 1]] - vertices[faces[at]]
		var ac := vertices[faces[at + 2]] - vertices[faces[at]]
		var cross := ab.cross(ac)
		if _degenerate(ab, ac, cross): continue
		var transform := Basis(ab, ac, cross / sqrt(cross.length())).inverse().transposed() * bases[at / 3]
		for corner in 3:
			var group := groups[faces[at + corner]]
			var normal := transform * group_normals[group]
			if normal.is_finite(): summed[group] += normal.normalized() * weights[at + corner]
	for group in summed.size():
		summed[group] = summed[group].normalized() if summed[group].length_squared() > 0.00000001 else group_normals[group]
	var result := authored.duplicate()
	for index in result.size(): result[index] = summed[groups[index]]
	return result

static func _degenerate(ab: Vector3, ac: Vector3, cross: Vector3) -> bool:
	var area_scale := ab.length_squared() * ac.length_squared()
	return not cross.is_finite() or area_scale <= 1e-20 or cross.length_squared() <= area_scale * 1e-12
