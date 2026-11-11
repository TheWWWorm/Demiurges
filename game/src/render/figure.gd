class_name ELFigure
extends RefCounted
## FIG1/FIG8 mesh layout; adapted from Cursed Lands' FIG reader.
## Both original material loaders give Magic full emission (RGB 1).
const MATERIAL_MAGIC := 23
const AUTHORED_FULLBRIGHT := &"authored_fullbright"
## The compiled readers (native/el_assets.c), where the platform has them.
static var native := ClassDB.class_exists(&"ELNativeAssets")

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
	if native:
		var arrays := _native_arrays(ClassDB.class_call_static(&"ELNativeAssets", &"figure", data), nc)
		if not arrays.is_empty():
			var source_indices: PackedInt32Array = arrays.pop_back()
			return {"arrays": arrays, "source_indices": source_indices, "vertices": nc, "triangles": ni / 3,
				"material_id": data.decode_u32(32), "texture_slot": data.decode_u32(36)}
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
		"material_id": data.decode_u32(32), "texture_slot": data.decode_u32(36)}

## The mesh arrays from the native reader's block, with the source vertex
## indices appended last; empty when the block does not match.
static func _native_arrays(block: PackedByteArray, corners: int) -> Array:
	if block.size() < 8 or block.decode_u32(0) != corners: return []
	var count := block.decode_u32(4)
	var at := 8
	if block.size() != at + corners * 36 + count * 4: return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = block.slice(at, at + corners * 12).to_vector3_array()
	at += corners * 12
	arrays[Mesh.ARRAY_NORMAL] = block.slice(at, at + corners * 12).to_vector3_array()
	at += corners * 12
	arrays[Mesh.ARRAY_TEX_UV] = block.slice(at, at + corners * 8).to_vector2_array()
	at += corners * 8
	var source_indices := block.slice(at, at + corners * 4).to_int32_array()
	at += corners * 4
	arrays[Mesh.ARRAY_INDEX] = block.slice(at, at + count * 4).to_int32_array()
	arrays.append(source_indices)
	return arrays

static func mesh(figure: Dictionary, track: Dictionary = {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = figure.arrays
	var shapes := []
	var positions: Array[PackedVector3Array] = []
	var morph_bounds: Array[AABB] = []
	var frames: int = track.get("morph_frames", 0)
	var count: int = track.get("morph_vertices", 0)
	if frames > 0 and count > 0:
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		var source: PackedByteArray = track.data
		var base: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = figure.source_indices
		var block := PackedByteArray()
		if native:
			block = ClassDB.class_call_static(&"ELNativeAssets", &"morph", base.to_byte_array(), source_indices.to_byte_array(), source, int(track.morph_offset), frames, count)
			if block.size() != frames * (base.size() * 12 + 24): block = PackedByteArray()
		if not block.is_empty():
			var bounds := block.slice(frames * base.size() * 12).to_vector3_array()
			for frame in frames:
				var vertices := block.slice(frame * base.size() * 12, (frame + 1) * base.size() * 12).to_vector3_array()
				morph_bounds.append(AABB(bounds[frame * 2], bounds[frame * 2 + 1] - bounds[frame * 2]))
				var shape := []
				shape.resize(Mesh.ARRAY_MAX)
				shape[Mesh.ARRAY_VERTEX] = vertices
				positions.append(vertices)
				shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
				shapes.append(shape)
				mesh.add_blend_shape("frame_%d" % frame)
			frames = 0
		# Every frame's offsets as floats at once (a native conversion).
		var offsets := source.slice(int(track.morph_offset), int(track.morph_offset) + frames * count * 12).to_float32_array()
		var vertex_count := base.size()
		for frame in frames:
			var vertices := base.duplicate()
			var first := frame * count * 3
			var low := Vector3.INF
			var high := -Vector3.INF
			for i in vertex_count:
				var index := source_indices[i]
				var vertex := vertices[i]
				if index < count:
					var q := first + index * 3
					vertex += Vector3(offsets[q], offsets[q + 2], -offsets[q + 1])
					vertices[i] = vertex
				low = low.min(vertex)
				high = high.max(vertex)
			morph_bounds.append(AABB(low, high - low) if vertex_count > 0 else AABB())
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = vertices
			positions.append(vertices)
			shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
			shapes.append(shape)
			mesh.add_blend_shape("frame_%d" % frame)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	# Each frame's whole vertex positions, for traced lighting.
	if not positions.is_empty():
		mesh.set_meta("morph_positions", positions)
		mesh.set_meta("morph_bounds", morph_bounds)
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
	if not _plain_track(bytes):
		var unpacked := unpack_track(bytes)
		if not unpacked.is_empty(): bytes = unpacked
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

## True when the track fills the plain layout exactly: 32-bit counts with
## float rotation, position and scale keys, then an 8-byte vertex animation
## header and its float offsets.
static func _plain_track(bytes: PackedByteArray) -> bool:
	var p := 0
	for size: int in [16, 12, 12]:
		if p + 4 > bytes.size(): return false
		p += 4 + bytes.decode_u32(p) * size
		if p > bytes.size(): return false
	var rest := bytes.size() - p
	if rest == 0: return true
	return rest >= 8 and rest == 8 + bytes.decode_u32(p) * bytes.decode_u32(p + 4) * 12

## Converts a packed track (the Etherlords II release sold on Steam) to the
## plain layout, or returns an empty array when the bytes are not one. Packed
## tracks use 16-bit counts, store positions and vertex offsets as
## thousandths in 16-bit integers, omit all-zero positions and all-one scales,
## and keep only the key frames of each vertex coordinate, with straight
## lines between them.
static func unpack_track(bytes: PackedByteArray) -> PackedByteArray:
	if native: return ClassDB.class_call_static(&"ELNativeAssets", &"unpack_track", bytes)
	var out := PackedByteArray()
	var size := bytes.size()
	var p := 0
	if p + 2 > size: return PackedByteArray()
	var count := bytes.decode_u16(p)
	p += 2
	if p + count * 16 > size: return PackedByteArray()
	_put_u32(out, count)
	out.append_array(bytes.slice(p, p + count * 16))
	p += count * 16
	if p + 2 > size: return PackedByteArray()
	count = bytes.decode_u16(p)
	p += 2
	if p + count * 6 > size: return PackedByteArray()
	_put_u32(out, count)
	for i in count * 3:
		_put_float(out, bytes.decode_s16(p + i * 2) / 1000.0)
	p += count * 6
	if p + 2 > size: return PackedByteArray()
	count = bytes.decode_u16(p)
	p += 2
	if p + count * 12 > size: return PackedByteArray()
	_put_u32(out, count)
	out.append_array(bytes.slice(p, p + count * 12))
	p += count * 12
	if p == size:
		out.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
		return out
	if p + 4 > size: return PackedByteArray()
	var frames := bytes.decode_u16(p)
	var vertices := bytes.decode_u16(p + 2)
	p += 4
	_put_u32(out, frames)
	_put_u32(out, vertices)
	if frames == 0 or vertices == 0:
		return out if p == size else PackedByteArray()
	# Offsets in the plain layout run frame by frame; packed ones vertex by vertex.
	var values := PackedFloat32Array()
	values.resize(frames * vertices * 3)
	var mask_bytes := frames / 8 + 1
	var keys := PackedInt32Array()
	for vertex in vertices:
		if p + 1 > size: return PackedByteArray()
		var keyed := bytes[p]
		p += 1
		if keyed == 0:
			if p + frames * 6 > size: return PackedByteArray()
			for frame in frames:
				for axis in 3:
					values[(frame * vertices + vertex) * 3 + axis] = bytes.decode_s16(p + (frame * 3 + axis) * 2) / 1000.0
			p += frames * 6
			continue
		for axis in 3:
			if p + mask_bytes + 2 > size: return PackedByteArray()
			keys.clear()
			for frame in frames:
				if bytes[p + frame / 8] & (1 << (frame % 8)): keys.append(frame)
			p += mask_bytes
			count = bytes.decode_u16(p)
			p += 2
			if count != keys.size() or count == 0 or p + count * 2 > size: return PackedByteArray()
			var key := 0
			for frame in frames:
				while key + 1 < count and keys[key + 1] <= frame: key += 1
				var value := bytes.decode_s16(p + key * 2) / 1000.0
				if frame > keys[key] and key + 1 < count:
					var next := bytes.decode_s16(p + (key + 1) * 2) / 1000.0
					value += (next - value) * float(frame - keys[key]) / float(keys[key + 1] - keys[key])
				values[(frame * vertices + vertex) * 3 + axis] = value
			p += count * 2
	if p != size: return PackedByteArray()
	out.append_array(values.to_byte_array())
	return out

static func _put_u32(out: PackedByteArray, value: int) -> void:
	var at := out.size()
	out.resize(at + 4)
	out.encode_u32(at, value)

static func _put_float(out: PackedByteArray, value: float) -> void:
	var at := out.size()
	out.resize(at + 4)
	out.encode_float(at, value)

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
