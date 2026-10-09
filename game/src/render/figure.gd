class_name ELFigure
extends RefCounted
## FIG1/FIG8 mesh layout; adapted from Cursed Lands' FIG reader.
static func vector(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

static func quaternion(bytes: PackedByteArray, offset: int) -> Quaternion:
	var q := Quaternion(bytes.decode_float(offset + 4), bytes.decode_float(offset + 12),
		-bytes.decode_float(offset + 8), bytes.decode_float(offset))
	return q.normalized() if q.length_squared() > 0.00001 else Quaternion.IDENTITY

static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() < 80 or data.slice(0, 3).get_string_from_ascii() != "FIG":
		return {}
	var variants := data[3] - 48
	var vb := data.decode_u32(4)
	var nb := data.decode_u32(8)
	var nt := data.decode_u32(12)
	var ni := data.decode_u32(16)
	var nc := data.decode_u32(20)
	var vo := 40 + variants * 40
	var no := vo + vb * 12 * variants * 4
	var uo := no + nb * 16 * 4
	var io := uo + nt * 8
	var co := io + ni * 2
	if variants < 1 or variants > 8 or co + nc * 6 > data.size():
		return {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var source_indices := PackedInt32Array()
	for i in nc:
		var v := data.decode_u16(co + i * 6)
		var n := data.decode_u16(co + i * 6 + 2)
		var t := data.decode_u16(co + i * 6 + 4)
		var p := Vector3()
		for axis in 3:
			p[axis] = data.decode_float(vo + (((v >> 2) * 3 + axis) * variants * 4 + (v & 3)) * 4)
		var normal_offset := no + ((n >> 2) * 16 + (n & 3)) * 4
		vertices.append(vector(p))
		normals.append(vector(Vector3(data.decode_float(normal_offset), data.decode_float(normal_offset + 16), data.decode_float(normal_offset + 32))).normalized())
		uvs.append(Vector2(data.decode_float(uo + t * 8), data.decode_float(uo + t * 8 + 4)))
		source_indices.append(v)
	var indices := PackedInt32Array()
	for i in range(0, ni - 2, 3):
		indices.append_array([data.decode_u16(io + i * 2), data.decode_u16(io + (i + 2) * 2), data.decode_u16(io + (i + 1) * 2)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "source_indices": source_indices, "vertices": nc, "triangles": ni / 3,
		"texture_slot": data.decode_u32(36)}

static func mesh(figure: Dictionary, track: Dictionary = {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = figure.arrays
	var shapes := []
	var frames: int = track.get("morph_frames", 0)
	var count: int = track.get("morph_vertices", 0)
	if frames > 0 and count > 0:
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		var source: PackedByteArray = track.data
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for frame in frames:
			var vertices := base.duplicate()
			for i in vertices.size():
				var index: int = figure.source_indices[i]
				if index >= count:
					continue
				var p: int = track.morph_offset + (frame * count + index) * 12
				vertices[i] += vector(Vector3(source.decode_float(p), source.decode_float(p + 4), source.decode_float(p + 8)))
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = vertices
			shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
			shapes.append(shape)
			mesh.add_blend_shape("frame_%d" % frame)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	return mesh

static func hierarchy(bytes: PackedByteArray) -> Array:
	var out := []
	if bytes.size() < 4:
		return out
	var p := 4
	for i in bytes.decode_u32(0):
		var n := bytes.decode_u32(p)
		var name := ELArchive.key(ELText.ansi(bytes.slice(p + 4, p + 4 + n)))
		p += 4 + n
		n = bytes.decode_u32(p)
		var parent := ELArchive.key(ELText.ansi(bytes.slice(p + 4, p + 4 + n)))
		p += 4 + n
		out.append([name, parent])
	return out

static func track(bytes: PackedByteArray) -> Dictionary:
	var result := {"data": bytes, "frames": 1, "morph_frames": 0, "morph_vertices": 0}
	var p := 0
	# Etherlords adds scale keys between translation and vertex deformation.
	for field in ["rotation", "position", "scale"]:
		if p + 4 > bytes.size():
			return {}
		var count := bytes.decode_u32(p)
		p += 4
		result[field + "_offset"] = p
		result[field + "_count"] = count
		result.frames = maxi(result.frames, count)
		p += count * (16 if field == "rotation" else 12)
		if p > bytes.size():
			return {}
	if p + 8 <= bytes.size():
		var frames := bytes.decode_u32(p)
		var count := bytes.decode_u32(p + 4)
		if frames > 0 and count > 0 and p + 8 + frames * count * 12 <= bytes.size():
			result.morph_frames = frames
			result.morph_vertices = count
			result.morph_offset = p + 8
			result.frames = maxi(result.frames, frames)
	return result

static func material(texture: Texture2D, unlit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	if unlit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
