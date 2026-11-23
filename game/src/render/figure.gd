class_name ELFigure
extends RefCounted
## FIG1/FIG8 mesh layout; adapted from Cursed Lands' FIG reader.
## Both original material loaders give Magic full emission (RGB 1).
const MATERIAL_MAGIC := 23
const AUTHORED_FULLBRIGHT := &"authored_fullbright"
## The second game's Red and Green main heroes are made mostly (the Green
## ones wholly) of Magic: their armour, helmets, chains, crowns and staffs.
## Drawn at full brightness they stood flat and could not shine; the remake
## shades their Magic parts like the colourless creatures' and dresses them
## in metal (shaded, their shapes stay smooth).
const SHADED_MAGIC_HEROES := ["he701", "he702", "he703", "he704", "he705", "he706"]
const MorphNormals := preload("res://src/render/morph_normals.gd")
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
			var native_twins := separate_twins(arrays, source_indices)
			return {"arrays": arrays, "source_indices": native_twins.source_indices, "twinned": native_twins.twinned, "vertices": nc, "triangles": ni / 3,
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
	var twins := separate_twins(arrays, source_indices)
	return {"arrays": arrays, "source_indices": twins.source_indices, "twinned": twins.twinned, "vertices": nc, "triangles": ni / 3,
		"material_id": data.decode_u32(32), "texture_slot": data.decode_u32(36)}

## How far apart back-to-back twin triangles are moved (TWIN_GAP).
const TWIN_GAP := 0.004

## Double-sided sheets (wings, robes, banners, hood linings) are stored as
## twin triangles on the same corners, one facing each way. The originals
## draw each one-sided, so either side shows its own face lit by its own
## normals. Drawn two-sided here, the twins tied in depth and the one facing
## away, lit from behind, often won: dark wings and black linings (issue
## #223). Each twin moves a hair towards the side it faces, so the face
## towards the camera is the nearer one. Returns {source_indices (with the
## moved corners' own appended), twinned (1 per twin triangle)}.
static func separate_twins(arrays: Array, source_indices: PackedInt32Array) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() / 3
	var corner_keys: Array[Vector3i] = []
	var faces: Array[Vector3] = []
	var facing := {}
	for t in count:
		var corners: Array[Vector3i] = []
		for k in 3: corners.append(Vector3i((vertices[indices[t * 3 + k]] * 4096.0).round()))
		corner_keys.append_array(corners)
		var sorted := corners.duplicate()
		sorted.sort()
		# Godot's front faces wind clockwise.
		var face := (vertices[indices[t * 3 + 2]] - vertices[indices[t * 3]]).cross(vertices[indices[t * 3 + 1]] - vertices[indices[t * 3]])
		faces.append(face.normalized() if face.length_squared() > 1e-14 else Vector3.ZERO)
		facing.get_or_add(sorted, []).append(t)
	var twinned := PackedByteArray()
	twinned.resize(count)
	for t in count:
		if faces[t] == Vector3.ZERO: continue
		var sorted := [corner_keys[t * 3], corner_keys[t * 3 + 1], corner_keys[t * 3 + 2]]
		sorted.sort()
		for other: int in facing[sorted]:
			if faces[other].dot(faces[t]) < 0.0:
				twinned[t] = 1
				break
	# Each corner of a twin moves along the summed faces of the twins on its
	# side, so neighbouring twins stay joined; corners shared with a
	# single-sided triangle stay put, so no crack opens beside it.
	var pinned := {}
	var around := {}
	for t in count:
		for k in 3:
			var key := corner_keys[t * 3 + k]
			if twinned[t] == 0: pinned[key] = true
			else: around.get_or_add(key, []).append(t)
	var moved := false
	for t in count:
		if twinned[t] == 0: continue
		for k in 3:
			var key := corner_keys[t * 3 + k]
			if pinned.has(key): continue
			var sum := Vector3.ZERO
			for other: int in around[key]:
				if faces[other].dot(faces[t]) > 0.0: sum += faces[other]
			if sum.length_squared() < 1e-12: continue
			var corner := indices[t * 3 + k]
			indices[t * 3 + k] = vertices.size()
			vertices.append(vertices[corner] + sum.normalized() * TWIN_GAP)
			normals.append(normals[corner])
			uvs.append(uvs[corner])
			source_indices.append(source_indices[corner])
			moved = true
	if moved:
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
	return {"source_indices": source_indices, "twinned": twinned}

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
	# Morph frames bend the surface as well as moving its vertices. Transport
	# the authored shading once when its cached mesh is built, keeping
	# UV seams and deliberate hard edges. Playback only blends cached normals.
	if not positions.is_empty():
		var normal_rest := MorphNormals.prepare(arrays, figure.source_indices)
		if not normal_rest.is_empty():
			for index in shapes.size():
				shapes[index][Mesh.ARRAY_NORMAL] = MorphNormals.for_pose(normal_rest, positions[index])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	# The surface as built (shared by every clip's mesh of the part), so the
	# path tracer never reads it back from the GPU (a stall in the frame a
	# figure first shows a clip: stepping out to block, an attack).
	mesh.set_meta("source_arrays", arrays)
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
	# Tracks are shared by every instance of the model. Prepare the small
	# transform keys here (including worker-thread warm-up), instead of
	# decoding floats and normalising the same quaternions every drawn frame.
	# Keep the original counts and bytes: they define clip timing and morphs.
	var rotations: Array[Quaternion] = []
	rotations.resize(int(result.rotation_count))
	var same_rotation := true
	for index in rotations.size():
		rotations[index] = quaternion(bytes, int(result.rotation_offset) + index * 16)
		if index > 0 and rotations[index] != rotations[0]: same_rotation = false
	if same_rotation and rotations.size() > 1: rotations.resize(1)
	result.rotation_keys = rotations
	result.position_keys = _vector_keys(bytes, int(result.position_offset), int(result.position_count), false)
	result.scale_keys = _vector_keys(bytes, int(result.scale_offset), int(result.scale_count), true)
	# A part whose every channel holds one value and has no morphs keeps the
	# same pose for the whole clip (ELModel poses it when the clip starts).
	result.still = rotations.size() <= 1 and result.position_keys.size() <= 1 and result.scale_keys.size() <= 1 and int(result.get("morph_frames", 0)) == 0
	return result

## Constant channels need only one prepared value, even when the file repeats
## it for the entire clip. The original channel counts remain in the track.
static func _vector_keys(bytes: PackedByteArray, offset: int, count: int, scaling: bool) -> PackedVector3Array:
	var keys := PackedVector3Array()
	keys.resize(count)
	var same := true
	for index in count:
		var at := offset + index * 12
		var value := Vector3(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8))
		keys[index] = Vector3(value.x, value.z, value.y) if scaling else vector(value)
		if index > 0 and keys[index] != keys[0]: same = false
	if same and count > 1: keys.resize(1)
	return keys

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

## Part names (transliterated Russian in places) of armour and weapons. The
## FIG files give every part the same material, so the remake names its metal.
## The Synthets' machine parts too: shoulder shells, arm plates, heels, spine
## plates, needles, the box on their backs, the jet pack and (named exactly,
## as insects' claws share the word) their claws.
const METAL_PARTS := ["sword", "blade", "axe", "knife", "pike", "shield", "helm", "kirasa",
	"naplechnik", "noplechnik", "naruch", "plate", "chain", "kreplenie", "armshell",
	"shouldershell", "legshell", "footshell", "kolenka", "l_shell", "r_shell", "armplane",
	"kabluk", "spinepart", "igles", "box25", "jetpak"]
const METAL_NAMES := ["kogot1", "kogot2", "kogot3", "r_kogot"]
## Weapons named in neither game's armour words: the grey ogre's mace, the
## kobold warrior's katana and the kobold shaman's spear (only the painted
## steel of a spear shines, never its wooden shaft).
const METAL_WEAPONS := ["mace", "katana", "spear"]
## Figures whose parts carry plain names (body, legs, hands, polySurface...)
## though they are plated: the parts named here show the classifier what
## their metal looks like, and it finds the matching paint elsewhere on the
## figure (flesh, bone and fur stay matte). A trailing "*" names every part
## that begins so. The map figure of the same number (adNNN for crNNN) wears
## the same list.
## - The Synthets' machines: the Mechanical Worms, Mechoses, Rippers, Sawers
##   and Cutters, Mechozauri, Abominations and Velos (their claws, saws,
##   wheels, legs and arm plates; the worm's segmented body).
## - The Huntress: the knives on her bandolier, her spiked glove, her crossbow.
## - The Spirit Priest: the spiked head of his flail.
## - Second-game heroes: the Chaots' ogre heroes (pauldrons, helmet and
##   spiked staff, the ogress's steel breastplate on her body) and the
##   Synthet lord's machine arm and gun-staff; the Chaot warriors' spear and
##   mace heads.
## - The Aviak Warlock's hammer and gun.
## - The second game's colourless creatures, whose parts kept Maya's names:
##   the Samurai's gold helmets and pauldrons and their swords, the Hindu
##   warriors' blades and the gold of one's greaves, the Egyptians' blades,
##   shields and gold caps, and the Tribesmen's spear points.
##   Their pale skin is painted in steel's grey, so their heads and bodies,
##   crowns and all, are left to the classifier, which keeps skin matte.
## - The Green main heroes' gold belts, jewellery and staffs, and the Red
##   ones' helmets, pauldrons, rings and chains (SHADED_MAGIC_HEROES).
const METAL_FIGURE_PARTS := {
	"cr101": ["body", "l_back_claw", "r_back_claw"],
	"cr102": ["head", "l_leg*", "r_leg*", "polysurface*", "l_finger*", "r_finger*"],
	"cr103": ["l_circular", "r_circular", "l_leg*", "r_leg*", "l_hand*", "r_hand*", "l_fingers", "r_fingers"],
	"cr104": ["l_arm*", "r_arm*", "l_leg*", "r_leg*"],
	"cr105": ["l_claw", "r_claw", "l_finger*", "r_finger*", "l_leg2", "r_leg2"],
	"cr109": ["wheel", "l_claws", "r_claws", "l_leg*", "r_leg*", "l_hand*", "r_hand*"],
	"cr502": ["poas", "glove", "arbalet*"],
	"cr422": ["star"],
	"he201": ["l_hand1", "r_hand1", "head", "stick", "body"],
	"he203": ["staff"], "he207": ["staff"],
	"cr404": ["gun", "hammer"],
	"he205": ["l_hand1", "r_hand1", "head", "stick"],
	"he722": ["*hand*", "*arm*", "stuff*", "staff*"], "he723": ["*hand*", "*arm*", "stuff*", "staff*"], "he724": ["*hand*", "*arm*", "stuff*", "staff*"],
	"cr701": ["muzzle", "polysurface1"],
	"cr702": ["polysurface20", "polysurface21", "polysurface29251", "polysurface29252", "polysurface29253"],
	"cr703": ["muzzle", "staff", "shoulder_strap*"],
	"cr707": ["polysurface1", "qw_polysurface29251"],
	"cr708": ["polysurface21", "qw1_polysurface3"],
	"cr709": ["polysurface1", "polysurface21", "qw_polysurface29251", "qw1_polysurface3", "polysurface29318"],
	"cr710": ["polysurface21", "polysurface29360"],
	"cr712": ["cap", "baton"],
	"cr705": ["polysurface1"],
	"cr704": ["polysurface29292"],
	"he701": ["belt", "acsessories", "stuff1"], "he702": ["belt", "acsessories", "stuff1"], "he703": ["belt", "acsessories", "stuff1"],
	"he704": ["head", "sh_r*", "ring", "chain*"], "he705": ["head", "sh_r*", "ring", "chain*"], "he706": ["head", "sh_r*", "ring", "chain*"],
}
## Parts that are feathers, hair, fur, tails or cloth: never metal, whatever
## colour they are painted.
const SOFT_PARTS := ["wing", "l_w_", "r_w_", "feather", "pero", "hair", "fur", "xvost", "tail",
	"cloth", "coat", "cape", "balahon", "robe", "flag", "ponit", "ponyt", "skin", "face", "hvost"]
## Parts whose paint is too close to the figure's armour for the metal mask.
## The Vital sorceress's body includes skin and cloth. The White Lord's silver
## robe and hat are painted in the very steel of his sword and shield. The
## orc shaman's hood is named "helm" and his wraps are the slate blue of
## steel, but both are cloth (issue #223: the hood turned black).
## The grey ogre's skin is the grey of his mace, and the Huntress's coat
## the pale steel of her knives: only their weapons shine.
## The Abominations' upper arms and thighs are flesh, which the Bronze and
## Iron ones paint in their metal's own brown.
## The kobold shaman is old and grey, the grey of his knife and spear.
## The first Tribesman's feather headdress is named "head" and painted in
## his spear's grey, and the second one's hide shield in its pale steel.
## The Hindu warriors' pale bodies and arms and the first Egyptian's
## grey-violet hide are painted in their blades' steel.
## The elementals are fire, air, earth and water painted in steel's grey and
## gold's orange: only their swords are metal.
const CLOTH_PARTS := {"he401": ["body"], "he500": ["body", "hat"], "he501": ["body", "hat"],
	"cr214": ["body", "helm"], "ad214": ["body", "helm"], "cr205": ["body", "legs", "l_hand", "r_hand", "bag"], "ad205": ["body", "legs", "l_hand", "r_hand", "bag"],
	"cr502": ["body"], "ad502": ["body"],
	"cr105": ["l_hand1", "r_hand1", "l_leg1", "r_leg1"], "ad105": ["l_hand1", "r_hand1", "l_leg1", "r_leg1"],
	"cr206": ["hip", "body", "head", "l_hand1", "r_hand1", "l_hand3", "r_hand3", "l_leg1", "r_leg1", "l_leg2", "r_leg2"], "ad206": ["hip", "body", "head", "l_hand1", "r_hand1", "l_hand3", "r_hand3", "l_leg1", "r_leg1", "l_leg2", "r_leg2"],
	"cr705": ["head"], "ad705": ["head"], "cr704": ["pcylinder7"], "ad704": ["pcylinder7"],
	"cr707": ["polysurface29344"], "ad707": ["polysurface29344"],
	"cr708": ["polysurface29344", "polysurface29333", "polysurface29341"], "ad708": ["polysurface29344", "polysurface29333", "polysurface29341"],
	"cr709": ["polysurface29261", "polysurface29319", "polysurface29333"], "ad709": ["polysurface29261", "polysurface29319", "polysurface29333"],
	"cr710": ["polysurface29367"], "ad710": ["polysurface29367"], 
	"cr417": ["body", "horns", "head"], "ad417": ["body", "horns", "head"], "cr418": ["body", "horns", "head"], "ad418": ["body", "horns", "head"], "cr419": ["body", "horns", "head"], "ad419": ["body", "horns", "head"], "cr420": ["body", "horns", "head"], "ad420": ["body", "horns", "head"]}
## Parts built as closed shells or back-to-back layers, which the originals
## draw one-sided. Drawn two-sided here, the inside of the shell showed through
## lit from the wrong side or painted black: the orc shaman's hood lining
## (issue #223), the backs of coats, helmet interiors, shoulder plates, insect
## wings. Found by rendering every battle and map figure of both games both
## ways from six angles: each part listed loses that dark inside one-sided and
## opens no hole (in either game).
## Single-sheet parts (capes, flat wings), which one-sided would cut away,
## stay two-sided.
const BACK_CULLED := {"ad103": ["l_circular", "r_circular"], "ad104": ["body"], "ad109": ["body"],
	"ad110": ["head"], "ad111": ["wing"], "ad112": ["blade6"],
	"ad113": ["blade1", "blade2", "blade3"], "ad202": ["body", "l_naplechnik", "r_naplechnik"],
	"ad203": ["body", "r_naplechnik"], "ad206": ["hip", "l_hand1", "r_hand1"], "ad207": ["hip"],
	"ad208": ["hip", "l_hand1", "r_hand1"], "ad209": ["hip"], "ad214": ["chain", "helm"],
	"ad307": ["staf1"], "ad308": ["staf1"], "ad311": ["object04"], "ad313": ["object26"],
	"ad404": ["robe"], "ad409": ["body", "flag", "l_shoulder", "r_shoulder"],
	"ad410": ["bell", "body"], "ad411": ["backshield", "l_shell", "r_shell"], "ad412": ["body"],
	"ad414": ["body"], "ad417": ["sword01"], "ad421": ["helmet", "l_shell", "r_shell"],
	"ad701": ["body", "muzzle", "polysurface1"], "ad702": ["polysurface29253", "sdf"],
	"ad703": ["body", "shoulder_strap"], "ad706": ["polysurface29274"], "ad707": ["cloth"],
	"cr104": ["body"], "cr108": ["body"], "cr109": ["body"], "cr111": ["wing"],
	"cr113": ["blade1", "blade3"], "cr202": ["body", "l_naplechnik", "r_naplechnik"],
	"cr203": ["body", "r_naplechnik"], "cr206": ["hip", "l_hand1", "r_hand1"],
	"cr207": ["head", "hip"], "cr208": ["head", "hip", "l_hand1", "r_hand1"], "cr209": ["hip"],
	"cr214": ["helm"], "cr301": ["l_wing", "r_wing"], "cr307": ["staf1"], "cr308": ["staf1"],
	"cr311": ["object04"], "cr312": ["object02"], "cr313": ["object26", "object27"],
	"cr404": ["robe"], "cr409": ["body", "l_shoulder", "r_shoulder"], "cr410": ["bell"],
	"cr411": ["backshield", "l_shell", "r_shell"], "cr413": ["body"], "cr415": ["body"],
	"cr417": ["sword01"], "cr421": ["helmet", "l_shell", "r_shell"], "cr502": ["arbalet"],
	"cr701": ["body", "polysurface1"], "cr702": ["polysurface29253", "sdf"],
	"cr703": ["body", "shoulder_strap"], "cr706": ["polysurface29274"], "cr707": ["cloth"],
	"he101": ["igles"], "he103": ["r_wing5"], "he105": ["body", "cloth", "l_wing", "r_wing"],
	"he301": ["l_w_11", "l_w_25"], "he303": ["l_w_12", "l_w_25"], "he305": ["body", "head"],
	"he307": ["l_legshell"], "he504": ["head"], "he505": ["coat", "head"], "he704": ["head"],
	"he705": ["coat", "head"], "he706": ["coat", "head"]}

## Parts that are partly lining and partly single sheets: two-sided they
## showed the lining's back from outside, one-sided their sheets would open
## holes. Such a part is drawn one-sided and every single (untwinned)
## triangle gets a reversed copy, except the lining ones listed here, whose
## backs then never show. Found from per-triangle renders of every figure
## from 36 angles over its idle clip: a listed triangle's back showed in
## front of other parts of the figure far more often than against nothing.
## Triangle numbers in the part's own order: template/part -> {edition: [...]}.
const ONE_SIDED_FACES := {
	"ad102/l_leg2": {"el2": [8]},
	"ad102/polysurface1": {"el2": [36]},
	"ad102/r_leg1": {"el2": [115]},
	"ad104/l_arm4": {"el2": [10]},
	"ad104/l_leg4": {"el2": [10,19,43]},
	"ad104/r_arm4": {"el2": [9,12,35]},
	"ad104/r_leg4": {"el2": [9,10,19,43]},
	"ad105/l_finger2": {"el1": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]},
	"ad105/r_finger2": {"el1": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]},
	"ad105/r_hand2": {"el1": [82], "el2": [82]},
	"ad108/body": {"el2": [76,78,81,87,110,111,113,119,124,125,144,145,154]},
	"ad108/hip": {"el2": [11,34]},
	"ad108/l_hand3": {"el2": [36,37,41,44,51,53,54,57,59,64,75]},
	"ad108/l_leg3": {"el2": [9]},
	"ad108/l_nosok": {"el2": [9]},
	"ad108/r_hand3": {"el2": [37,39,40,41,44,50,52,53,54,55,57,75,76,77,78,81]},
	"ad108/r_leg1": {"el2": [29]},
	"ad108/r_leg3": {"el2": [9]},
	"ad108/r_nosok": {"el2": [9]},
	"ad110/body": {"el2": [8,9,12,13,16,17,19,94,95,96,97,99,100,101,102,103,104,105,106,107,108,109,110,114,129,138,139,142,143,146,147,149,224,225,226,227,229,230,231,232,233,234,235,236,237,238,239,240,244,250,259]},
	"ad110/l_hand2": {"el2": [48,60]},
	"ad110/r_hand2": {"el2": [68]},
	"ad111/body": {"el2": [3,4,25,26,28,70,71,92,93,95]},
	"ad201/body": {"el2": [749,750,751,752,753,756,757,758,759,760,761,766,767,768,769,772,774,775,776,777,791,792,795,797,798,799,800,802,803,805,806,811,812,817]},
	"ad201/l_naplechnik": {"el2": [16,37]},
	"ad201/r_naplechnik": {"el2": [16]},
	"ad201/ring": {"el2": [2,3]},
	"ad203/l_naplechnik": {"el2": [0,1,2,3,4,6,7,8,9,15,16,17,18,23,24,28]},
	"ad203/shield": {"el2": [37,41,47]},
	"ad204/body": {"el1": [71,72,73,211,213,219,224,225,226,227,229,231,233,239,240,241,242,243,245]},
	"ad204/helm": {"el1": [5,7,21,22,28,29,30,43,44,45]},
	"ad204/r_hand": {"el1": [50]},
	"ad206/body": {"el1": [52,62,127,183,239,241,242,261,262,281,282], "el2": [52,62,127,203,239,241,242,261,262,281,282]},
	"ad206/head": {"el1": [112,115,116,117,119,120,121,122,125,130,133,135,137,138,139,143], "el2": [112,115,117,119,120,121,122,125,130,133,135,137,138,139,143]},
	"ad206/knife": {"el2": [13,17,18]},
	"ad206/l_hand2": {"el2": [8,10]},
	"ad206/r_hand2": {"el2": [0,1,8,9,10,15]},
	"ad206/spear": {"el1": [78,79,86,87], "el2": [79,87]},
	"ad207/body": {"el1": [3,4,52,62,109,127,128,145,163,164,183,184,203,205,206,225,226,245,246,264,281,282], "el2": [2,3,4,52,62,127,128,145,163,164,183,203,205,206,225,226,245,264,281,282]},
	"ad207/head": {"el1": [112,115,117,119,121,122,130,133,135,137,139,140], "el2": [112,115,116,117,119,121,122,130,133,135,137,138,139,140]},
	"ad207/r_hand2": {"el2": [1,9,10,15,16,17]},
	"ad207/shield": {"el1": [16,17,18,19,20,21,22,23,24,25,26,27,28,29,33,36,37,40,41,45,49], "el2": [9,16,17,18,19,20,21,22,23,24,25,26,27,28,29,32,33,36,37,40,41,45]},
	"ad208/body": {"el1": [52,62], "el2": [52,62]},
	"ad208/head": {"el1": [100,103,105,107,108,109,110,118,121,122,123,125,126,127,128], "el2": [100,103,105,107,108,109,110,118,121,122,123,125,126,127,128,131]},
	"ad208/katana": {"el2": [1,2]},
	"ad208/r_hand2": {"el1": [1,9,10,15,16,17], "el2": [1,9,10,15,16,17]},
	"ad208/shield": {"el1": [22], "el2": [11,12,22]},
	"ad209/body": {"el1": [52,62,187,205,207,208,227,228,247,248,267,287,323,324], "el2": [52,62,81,85,87,88,89,93,94,105,109,111,112,114,115,116,117,118,205,207,208,227,228,247,248,267,323,324]},
	"ad209/head": {"el1": [90,93,95,97,99,100,108,111,113,115,117,118,150,151,152,153,154,156,162,163,164,165,166,168], "el2": [90,93,95,97,99,100,108,111,113,115,117,118,121,150,151,152,153,154,156,160,162,163,164,165,166,168]},
	"ad209/l_hand2": {"el1": [38,39,40,41,50,51,52,53,62,63,64,65,74,75,76,77], "el2": [32,34,38,39,40,41,49,50,51,52,53,62,63,64,65,72,73,74,75,76,77]},
	"ad209/r_hand2": {"el1": [38,39,40,41,50,51,52,53,62,63,64,65,74,75,76,77], "el2": [38,39,40,41,50,51,52,53,62,63,64,65,68,74,75,76,77]},
	"ad209/small_knife": {"el1": [30,31,32,35,36,37,38,39], "el2": [30,31,32,36,37,38,39]},
	"ad209/staff": {"el1": [44,45,47,48,49,51,76,77,97,98,109,115,117,124,125], "el2": [76,77,97,98,115,116,117]},
	"ad215/body": {"el1": [206,213,529], "el2": [204,206,213,321,322,529,642,643,644,645]},
	"ad215/toophs1": {"el1": [15,31], "el2": [8,9,24,25]},
	"ad215/toophs2": {"el1": [6,12], "el2": [4,5,6,7,12,13,14,15]},
	"ad216/chelust": {"el1": [0,2,3,8,9,11], "el2": [0,3,6,7,8,9,10,11]},
	"ad216/head": {"el1": [222,223,224,225,226,227,228,229,230,231,232,233,234,235], "el2": [222,223,224,225,226,227,228,229,230,231,232,233,234,235]},
	"ad301/l_arm1": {"el2": [6]},
	"ad301/l_leg1": {"el2": [2,4]},
	"ad301/l_wingflap": {"el2": [27]},
	"ad301/r_wingflap": {"el2": [27]},
	"ad309/bag": {"el2": [29,36,37,38,42,43,44,45]},
	"ad309/body": {"el2": [101,109,111,140,141,250,253,282,283]},
	"ad314/jaw2": {"el2": [7,16]},
	"ad314/l_leg4": {"el2": [42,43,50,51,52,53]},
	"ad314/r_leg4": {"el2": [52]},
	"ad401/coat": {"el2": [74,174,182,199,216,227,228,229,237,249]},
	"ad402/acoat": {"el2": [174,199,220,222,225,228,237,248]},
	"ad402/coat": {"el2": [51,174,182,199,220,227,228,229,237]},
	"ad403/l_h_fur": {"el1": [0,1,2,3,4,5,6,7,8,9,10,11,12,14,15,18]},
	"ad403/r_h_fur": {"el1": [6,9,10,16,17,18,19,20,21,22,23,25,26,28,30,31]},
	"ad403/wings": {"el1": [37,38,45,53,54,55,56,57,59,66,80,81,82,83]},
	"ad404/body": {"el2": [44]},
	"ad404/gun": {"el1": [40]},
	"ad404/l_h_fur": {"el1": [0,1,2,3,4,5,6,7,8,10,13,14,15,16,17,18,22,24,26], "el2": [0,1,2,3,4,5,6,7,8,10,17,21,22,23,24]},
	"ad404/l_h_h": {"el1": [3,4,5,6,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [3,4,5,6,7,12,13,14,15,16,17,18,19,20,21,22,23]},
	"ad404/r_h_fur": {"el1": [2,3,4,6,10,16,17,18,19,20,21,22,23,24,25,28,31], "el2": [1,2,3,6,16,17,18,19,20,21,22,23,24,31]},
	"ad404/r_h_h": {"el1": [3,4,6,7,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [2,6,7,8,12,13,14,16,18,19,20,21,22,23]},
	"ad404/wings": {"el1": [0,8,9,10,11,12,14,21,35,36,37,38,53,54,57,66,80,81,82,83], "el2": [0,4,8,9,10,11,12,14,21,22,27,35,36,37,38,53,54,57,66,80,82,83]},
	"ad405/l_h_fur": {"el1": [0,1,2,3,4,5,6,7,8,9,14,15,16,17,24,25,26,30,31]},
	"ad405/l_h_h": {"el1": [8,12,13,14,15,16,17,18,19,20,21,22,23]},
	"ad405/r_h_fur": {"el1": [2,3,9,10,14,16,17,18,19,20,21,22,23,24,30,31]},
	"ad405/r_h_h": {"el1": [4,5,12,13,14,16,17,18,19,20,21,22,23]},
	"ad405/wings": {"el1": [0,8,9,10,11,12,14,21,35,36,37,38,45,53,54,55,56,57,59,66,80,81,82,83]},
	"ad406/body": {"el1": [277]},
	"ad406/chest": {"el1": [2,3]},
	"ad406/l_h_fur": {"el1": [0,1,2,4,6,7,8,16,17,25]},
	"ad406/l_h_h": {"el1": [8,10,11,12,14,16,17,18,19,20,21,22,23]},
	"ad406/r_h_fur": {"el1": [0,9,15,16,18,20,21,22,23,24]},
	"ad406/r_h_h": {"el1": [1,8,10,11,12,14,16,17,18,20,21,22,23]},
	"ad406/wings": {"el1": [0,8,9,10,11,12,14,21,35,36,37,38,45,53,54,55,56,57,59,66,80,81,82,83]},
	"ad406/x_chain": {"el1": [1,2,3,5,6,7,8,9,10,11,12,13,14,15,24,29,30,31]},
	"ad705/body": {"el2": [0,2,3,22,33,44,45,46,47,62,63,65,67,68,69,73,76,77,88,89,90,91,92,93,95,98,99]},
	"ad705/hands": {"el2": [76]},
	"ad705/head": {"el2": [6,10,27,28,30,54,60,62,66,87,92,94,118,120,122,123,126,134,136,137,138,140]},
	"ad705/polysurface29301": {"el2": [0,1,2,3,5,6,10,11,13]},
	"ad705/polysurface29302": {"el2": [6,7,12,13,14,15]},
	"ad709/cloth": {"el2": [0,5,12,14,16,20,21,22,23,24,25,26,32,36,48,49,51,53,55,66,68,69,70,71,73]},
	"ad709/polysurface29308": {"el2": [5,7,13,15,21,22,23,24,29,30,31,32,33,34]},
	"ad709/polysurface29333": {"el2": [12,13,14,15,16,57,58,62,695,855,856]},
	"cr102/l_leg2": {"el2": [8]},
	"cr102/polysurface1": {"el2": [36]},
	"cr102/r_leg1": {"el2": [115]},
	"cr103/body": {"el1": [152,153,154,157,158]},
	"cr103/head": {"el1": [9,10,41,42,71,72,104,105,108,109,110,111,112,113]},
	"cr103/l_hand1": {"el1": [7]},
	"cr103/l_hand2": {"el1": [119]},
	"cr103/r_hand1": {"el1": [6,7]},
	"cr104/l_arm4": {"el1": [10,35], "el2": [10,15]},
	"cr104/l_leg4": {"el1": [10,43], "el2": [10,43]},
	"cr104/r_arm4": {"el1": [9,10], "el2": [9,12,35]},
	"cr104/r_leg4": {"el1": [9,10,43], "el2": [9,10,43]},
	"cr105/l_finger2": {"el1": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]},
	"cr105/r_finger2": {"el1": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]},
	"cr105/r_hand2": {"el1": [82], "el2": [82]},
	"cr108/hip": {"el1": [0,11,33], "el2": [0,11,33]},
	"cr108/l_hand3": {"el1": [40,41,44,51,53], "el2": [40,41,44,51,53]},
	"cr108/l_leg3": {"el1": [9], "el2": [9]},
	"cr108/l_nosok": {"el1": [9]},
	"cr108/r_hand3": {"el1": [29,30,37,40,41,44,45,52,54,57,59], "el2": [29,30,37,40,44,45,52,54,57,59]},
	"cr108/r_leg1": {"el1": [29], "el2": [29]},
	"cr108/r_leg3": {"el1": [9], "el2": [9]},
	"cr108/r_nosok": {"el2": [9]},
	"cr110/body": {"el1": [8,9,12,13,16,17,19,94,95,96,97,99,100,101,102,103,104,105,106,107,108,109,110,114,129,138,139,142,143,146,147,149,224,225,226,227,229,230,231,232,233,234,235,236,237,238,239,240,244,259], "el2": [8,9,12,13,16,17,19,94,95,96,97,99,100,101,102,103,104,105,106,107,108,109,110,114,129,138,139,142,143,146,147,149,224,225,226,227,229,230,231,232,233,234,235,236,237,238,239,240,244,250,259]},
	"cr110/head": {"el1": [98,99,100], "el2": [98,99,100]},
	"cr110/l_hand2": {"el1": [48,60,67], "el2": [48,60]},
	"cr110/r_hand2": {"el1": [68], "el2": [68]},
	"cr111/body": {"el2": [3,4,25,26,28,70,71,92,93,95]},
	"cr201/body": {"el2": [750,751,752,753,756,757,758,759,760,761,766,767,768,769,772,774,775,776,777,791,792,795,797,798,799,800,802,803,805,806,811,812,817]},
	"cr201/l_naplechnik": {"el2": [16,37]},
	"cr201/r_axe": {"el2": [101]},
	"cr201/r_naplechnik": {"el2": [16]},
	"cr201/ring": {"el2": [2,3]},
	"cr203/l_naplechnik": {"el1": [0,1,2,3,4,6,7,8,9,15,16,17,18], "el2": [0,1,2,3,4,6,7,8,9,15,16,17,18]},
	"cr203/shield": {"el1": [37,41,47], "el2": [37,41,47]},
	"cr204/body": {"el1": [68,71,72,73,211,213,215,219,221,223,225,226,227,229,231,233,235,237,239,241,242,243,245]},
	"cr204/helm": {"el1": [5,7,21,22,28,29,30,43,44,45]},
	"cr204/r_hand": {"el1": [50]},
	"cr207/body": {"el1": [3,4,52,62,127,128,145,163,164,183,203,205,206,225,226,245,264,281,282], "el2": [2,3,4,52,62,127,128,145,163,183,203,205,206,225,226,245,264,281,282]},
	"cr207/r_hand2": {"el1": [1,9,10,15,16,17], "el2": [1,9,10,15,16,17]},
	"cr207/shield": {"el1": [16,17,18,19,20,21,22,23,24,25,26,27,28,29,32,33,36,37,40,41,45,49], "el2": [16,17,18,19,20,21,22,23,24,25,26,27,28,29,32,33,36,37,40,41,45]},
	"cr208/body": {"el1": [52,62], "el2": [52,62]},
	"cr208/katana": {"el1": [1,2,4,8], "el2": [1,2,4,8]},
	"cr208/r_hand2": {"el1": [1,9,10,15,16,17], "el2": [1,9,10,15,16,17]},
	"cr208/shield": {"el1": [11,12,22], "el2": [11,12,22]},
	"cr209/body": {"el1": [52,62,81,85,87,88,93,104,105,109,111,112,114,115,116,117,118,187,205,207,208,227,247,248,323], "el2": [52,62,81,85,87,88,89,93,104,105,109,111,112,114,115,116,117,118,205,207,208,227,228,247,248,267,323]},
	"cr209/head": {"el1": [90,93,95,97,99,100,108,111,113,115,117,118,150,151,152,153,154,156,162,163,164,165,166,168], "el2": [90,93,95,97,99,100,108,111,113,115,117,118,121,150,151,152,153,154,156,162,163,164,165,166,168]},
	"cr209/l_hand2": {"el1": [37,38,39,40,41,44,49,50,51,52,53,62,63,64,65,72,73,74,75,76,77], "el2": [38,39,40,41,48,49,50,51,52,53,62,63,64,65,73,74,75,76,77]},
	"cr209/r_hand2": {"el1": [37,38,39,40,41,49,50,51,52,53,62,63,64,65,74,75,76,77], "el2": [38,39,40,41,50,51,52,53,62,63,64,65,74,75,76,77]},
	"cr209/small_knife": {"el1": [30,31,32,36,37,38,39], "el2": [30,31,32,36,37,38,39]},
	"cr209/staff": {"el1": [76,77,97,98,115,116,117], "el2": [76,77,97,98,115,116,117]},
	"cr210/head": {"el1": [102,112,114,115,116,118,119,120,132,133,134,135,136,137,138,139,140,141]},
	"cr210/wings": {"el1": [21,63,98]},
	"cr215/body": {"el1": [204,206,213,320,321,322,529,644,645], "el2": [204,206,213,319,320,321,322,529,643,644,645]},
	"cr215/toophs1": {"el1": [8,9,24,25], "el2": [8,9,24,25,28]},
	"cr215/toophs2": {"el1": [4,5,6,7,12,13,14,15], "el2": [4,5,6,7,12,13,14,15]},
	"cr216/chelust": {"el1": [0,2,3,4,6,7,8,9,10,11], "el2": [0,2,3,4,5,6,7,8,9,10,11]},
	"cr216/head": {"el1": [43,222,223,224,225,226,227,228,229,230,231,232,233,234,235], "el2": [222,223,224,225,226,227,228,229,230,231,232,233,234,235]},
	"cr301/l_arm1": {"el1": [6], "el2": [6]},
	"cr301/l_leg1": {"el1": [2,4], "el2": [2,4]},
	"cr301/l_wingflap": {"el1": [27], "el2": [27]},
	"cr301/r_wingflap": {"el1": [27], "el2": [27]},
	"cr307/body": {"el1": [101,107,108,111,140,141,250,251,253,282,283]},
	"cr309/bag": {"el1": [36,37,38,42,43,44,45], "el2": [29,36,37,38,42,43,44,45]},
	"cr309/body": {"el1": [108,109,111,140,141,249,253,282,283], "el2": [107,108,109,111,140,141,251,253,282,283]},
	"cr314/jaw2": {"el1": [7,16], "el2": [7,16]},
	"cr314/l_leg4": {"el1": [48], "el2": [42,43,48,50,51,53]},
	"cr314/r_leg4": {"el1": [48,50,55], "el2": [52]},
	"cr401/coat": {"el1": [174,182,199,220,227,228,237,249], "el2": [74,174,182,199,216,227,228,229,237,249]},
	"cr402/acoat": {"el1": [26,174,199,220,228,237], "el2": [174,199,220,222,225,228,237,248]},
	"cr402/coat": {"el1": [124,174,182,199,220,227,228,229,237], "el2": [51,174,182,199,220,227,228,229,237]},
	"cr404/body": {"el1": [44], "el2": [44]},
	"cr404/l_h_fur": {"el1": [0,1,2,3,4,5,6,7,8,10,17,18,22,23], "el2": [0,1,2,3,4,5,6,7,8,10,17,18,21,22,23,24]},
	"cr404/l_h_h": {"el1": [3,4,5,6,7,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [3,4,5,6,7,12,13,14,15,16,17,18,19,20,21,22,23]},
	"cr404/r_h_fur": {"el1": [1,2,3,6,8,9,10,16,17,18,19,20,21,22,23,24,31], "el2": [1,2,3,6,10,16,17,18,19,20,21,22,23,24,31]},
	"cr404/r_h_h": {"el1": [2,6,7,12,13,14,16,18,19,20,21,22,23], "el2": [2,6,7,12,13,14,16,18,19,20,21,22,23]},
	"cr404/wings": {"el1": [0,4,8,9,10,11,12,14,21,22,27,35,36,37,38,53,54,57,58,66,72,80,82,83], "el2": [0,4,8,9,10,11,12,14,21,22,27,35,36,37,38,53,54,57,58,66,72,80,82,83]},
	"cr406/body": {"el1": [277]},
	"cr406/chest": {"el1": [2,3]},
	"cr406/l_h_fur": {"el1": [1,2,3,4,5,6,7,8,16,17,25]},
	"cr406/l_h_h": {"el1": [8,10,12,14,16,17,18,19,20,21,22,23]},
	"cr406/r_h_fur": {"el1": [0,1,9,15,16,17,18,19,20,21,22,23,24]},
	"cr406/r_h_h": {"el1": [10,12,14,16,17,18,20,21,22,23]},
	"cr406/wings": {"el1": [0,4,8,9,10,11,12,14,18,21,25,26,35,36,37,38,45,49,53,54,55,56,57,59,63,66,67,70,71,80,81,82,83]},
	"cr406/x_chain": {"el1": [1,2,3,5,6,7,8,9,10,11,12,13,14,15,24,29,30,31]},
	"cr709/cloth": {"el2": [0,5,12,14,16,20,21,22,23,24,25,26,32,36,48,49,51,53,55,66,68,69,70,71,73]},
	"cr709/polysurface29308": {"el2": [5,7,13,15,21,23,24,29,30,31,32,33,34]},
	"cr709/polysurface29333": {"el2": [12,13,14,15,16,57,58,62,695,855,856]},
	"he101/body": {"el1": [284,285,286,287,289,290,291,296,298,299,353,375,376,377,378], "el2": [284,285,286,287,289,290,291,296,298,299,353,375,376,377,378]},
	"he101/box25": {"el1": [11,14,15], "el2": [11,14,15]},
	"he101/head": {"el1": [68], "el2": [68]},
	"he101/l_leg2": {"el1": [1,2,3,5,6,7,48,53,54,59,60,67,78,79,80,81], "el2": [1,2,3,5,6,7,48,53,54,59,60,79,80,81]},
	"he101/l_leg3": {"el1": [62], "el2": [62]},
	"he101/r_hand1": {"el1": [1,55], "el2": [1,55]},
	"he101/r_hand3": {"el1": [42], "el2": [42]},
	"he101/r_hand6": {"el1": [29,32,36,41,57], "el2": [29,32,36,41,57]},
	"he101/thing": {"el1": [0], "el2": [0]},
	"he103/body": {"el1": [221,226,229,230,234,474,476,479,480,484], "el2": [221,224,226,229,230,234,474,476,479,480,482,484]},
	"he103/l_armplane1": {"el1": [2,3], "el2": [2,3]},
	"he103/l_armplane3": {"el1": [0,1], "el2": [0,1]},
	"he103/l_armplane4": {"el1": [0], "el2": [0]},
	"he103/l_legpart": {"el1": [8,9,10,11,12,13,14,15], "el2": [8,9,10,11,12,13,14,15]},
	"he103/r_armplane1": {"el1": [2,3], "el2": [2,3]},
	"he103/r_legpart": {"el1": [8,9,10,11,12,13,14,15], "el2": [8,9,10,11,12,13,14,15]},
	"he103/r_shell": {"el1": [12], "el2": [12]},
	"he103/r_wing3": {"el2": [1]},
	"he103/spinepart": {"el1": [0,1,3,5,8,10,11,13,15,18,20,21,22,23,28,30,32,33,38], "el2": [0,1,3,5,8,10,11,12,13,14,15,18,20,22,23,28,30,32,33,38]},
	"he103/stuff": {"el1": [40,56,57], "el2": [40,56,57]},
	"he301/body": {"el1": [816,817,818,819,823,844,845,846,847,848,849], "el2": [816,817,818,819,823,844,845,846,847,848,849]},
	"he301/head": {"el1": [120,121,122,123,152,153,154,155], "el2": [120,121,122,123,152,153,154,155]},
	"he301/l_kolenka": {"el1": [19,22,26,27], "el2": [19,22,26,27]},
	"he301/l_w_05": {"el1": [0], "el2": [0]},
	"he301/l_w_21": {"el1": [0], "el2": [0]},
	"he301/l_w_22": {"el1": [1]},
	"he301/l_w_23": {"el1": [1], "el2": [1]},
	"he301/l_w_28": {"el1": [0,1], "el2": [0,1]},
	"he301/l_w_29": {"el1": [1], "el2": [1]},
	"he301/l_w_31": {"el1": [1], "el2": [1]},
	"he301/l_wing_root": {"el1": [0,1,3], "el2": [0,1,3]},
	"he301/l_wing_root1": {"el1": [0,1], "el2": [0]},
	"he501/body": {"el1": [261,269]},
	"he501/body_static": {"el1": [123,127]},
	"he501/grob": {"el1": [9,19,29,39,51,80,87,88,154,155,156,168,178,268,271,272,273]},
	"he502/bags": {"el1": [43,44,58,64,68,69,70,71,91]},
	"he502/chest": {"el1": [101,197,267,268,276]},
	"he502/coat": {"el1": [0,1,2,3,6,7,23,24,33,35,36,40,42,43,44,45,47,48,49,50,58,59,60,61,62,63,64,65,66,129,130,131,132,135,136,153,162,165,169,173,174,176,177,178,179,187,188,189,190,191,193,195]},
	"he502/head": {"el1": [58,156]},
	"he502/shtanga1": {"el1": [9]},
	"he502/staff": {"el1": [219,220,221,227]},
	"he512/body": {"el1": [30,39,85,128,160,169,242,263,268,281,283,284,286,292,293,298,299,300,306,309,313,354,403,412,422,423,444,447,498,531,615,619,625,632,643,645,646,671,672,673,686,703,704,710,715,726,727,729,730,731,816,817,818,819,846,848,850]},
	"he512/head": {"el1": [1,2,3,4,5,29,30,40,41,42,43,44,45,65,66,120,121,122,123,152,153,154,155]},
	"he512/l_kolenka": {"el1": [19,22,26,27,30]},
	"he512/r_kolenka": {"el1": [26,27]},
	"he715/body": {"el2": [32,33,371]},
	"he715/head": {"el2": [53,54,55,72,73,77,80,85,87,90,91,92,127,179,180,181,183,185,186,200,208,213,215,216,218,219,220,255,283,308,314,315]},
	"he715/head1": {"el2": [26,27,59,60]},
	"he715/wings": {"el2": [36,40,44,49,50,73,96,120,126,128,135,146,150,155,156]},
	"he716/wings": {"el2": [9,15,22,39,45,58,59,60,67,99,106,129,144,151,154,155,165]},
	"he717/wings": {"el2": [8,58,65,74,134,148,152,158]},
	"he722/bags": {"el2": [43,44,57,58,64,68,69,70,71,91]},
	"he722/coat": {"el2": [0,1,2,3,6,7,8,9,21,23,24,32,33,34,35,36,40,42,43,44,45,47,48,49,50,51,52,57,58,59,60,61,62,63,64,65,66,129,130,131,132,135,137,138,150,153,161,163,165,169,173,176,177,178,179,180,181,186,187,188,189,190,191,193,194,195]},
	"he722/staff3": {"el2": [2,3]},
	"he724/bags": {"el2": [41,43,44,64,68,69,70,71,91]},
	"he724/chest": {"el2": [101,197,211,267,268,276,282]},
	"he724/coat": {"el2": [0,1,2,3,6,7,8,9,10,11,12,17,18,19,20,21,22,23,24,29,30,31,32,33,34,35,36,40,42,43,44,45,47,48,49,50,51,52,55,56,57,58,59,60,61,62,63,64,65,66,125,129,130,131,135,137,138,139,140,141,146,147,148,149,150,151,153,158,159,160,161,162,163,165,169,173,174,176,177,178,179,180,181,184,186,187,188,189,190,191,192,193,194,195,224]},
	"he724/head": {"el2": [57,58,156]},
	"he724/shtanga1": {"el2": [4,9]},
	"he724/shtanga2": {"el2": [13]},
	"he724/staff": {"el2": [83]},
	"he731/wings": {"el2": [44,91]}
}

## Parts of translucent figures (ghosts, spirits, the crystal sorceress),
## where every back face showed through the front ones, not only those in
## front of other parts: drawn one-sided, with reversed copies only for the
## triangles listed here, single sheets whose back was seen against nothing
## (from the same renders as ONE_SIDED_FACES). template/part -> {edition: [...]}.
const SHEET_FACES := {
	"ad407/body": {"el1": [126,127,128,129,131,132,133,153,154,156,157,158,160,325,326,486,487,488,489,490,491,507,509,510,511,512,516,659,660,758,759,760,761,762,763,766,767,768,769,770,771,772,774,775,778,780,781,784,786,787,788,792,793,794,795,796,797,798,799,800,801,803,804,807,810,812,813,822,840,841,842,843,847,850,851,852,853,854,855,856,926,927,928,929,930,931,934,935,936,937,938,939,940,943,946,948,949,950,951,952,954,955,958,961,964,970,971,972,973,974,977,980,981,982,983,984,985,986,989], "el2": [109,138,139,140,141,142,143,144,473,496,497,498,499,500,624,758,759,760,761,762,763,766,767,768,769,770,771,772,773,774,775,777,778,780,781,784,786,787,788,789,792,793,794,795,796,797,798,799,800,801,802,803,804,806,807,809,810,812,813,822,840,841,842,843,844,847,849,850,851,852,853,854,855,856,926,927,928,929,930,931,934,935,936,937,938,939,940,942,943,946,947,948,949,950,951,952,954,955,957,958,961,964,970,971,972,973,974,977,979,980,981,982,983,984,985,986]},
	"ad421/body1": {"el1": [], "el2": [1,11,19,35,43,64,68,70,108,109,114,115,116,117,118,119,120,121,122,123,124,125,126,129,130,194,196,206,207,208,209,225,226,229,230,233,255,256,257,258,259,267,268,269,270,281,283,284,292,293,294,295,296,297,298,300,325,326,331,332,333,334,335,336,337,338,339,340,341,342,343,346,347,394,395,396,404,405,408,409,410,411,418,419]},
	"ad421/kirasa": {"el1": [16,19,20,26,28,59,62,68,70], "el2": [16,19,20,26,28,39,59,62,68,70]},
	"ad421/shield": {"el1": [], "el2": []},
	"ad421/sword": {"el1": [], "el2": []},
	"ad422/balahon": {"el1": [2,5,7,11,12,13,15,16,17,18,19,21,22,24,25,26,27,28,29,30,32,34,35,36,38,39,40,43,44,45,47,49,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,76,77,79,80,82,83,86,87,88,90,91,92,93,96,98,100,102,103,104,105,107,108,109,112,113,114,116,117,120,121,123,124,125,126,127,128,129,130,131,132,133,134,135,167,208,223,225,269,270], "el2": [0,1,2,4,5,6,7,10,11,12,13,15,16,17,18,19,20,21,22,24,25,26,27,28,29,30,31,32,34,35,36,38,39,40,41,42,43,44,45,47,49,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,79,80,81,82,83,85,86,87,88,90,91,92,93,94,96,97,98,100,101,102,103,105,107,108,109,112,113,114,116,117,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,167,192,208,214,218,220,221,222,223,224,225,226,245,263,268,269,270,271]},
	"ad422/body": {"el1": [], "el2": [1,2,3,4,5,8,9,11,17,19,21,23,27,28,29,31,32,33,35,41,42,44,45,46,54,57,58,59,64,65,66,68,69,70,71,72,73,74,75,76,122,193,194,202,203,206,208,225,226,228,229,233,235,241,243,245,247,251,252,253,256,257,259,260,265,266,267,268,269,270,278,281,282,283,284,285,286,287,288,289,293,295,296,297,298,299,339,395,396,404,405,408,410,416,417]},
	"ad422/star": {"el1": [45,48,50,60,64,66,67], "el2": [45,48,50,56,60,64,66,67,71]},
	"ad423/body": {"el1": [], "el2": [102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,124,127,128,129,130,206,207,208,209,213,220,320,321,322,323,324,325,326,327,328,329,330,331,332,333,334,335,336,337,338,339,341,344,345,346,347,408,409,410,411,412]},
	"ad423/mask": {"el1": [43,44,45,46,47,48,51,52,78,79,80,81,82,83], "el2": [43,44,45,46,47,48,49,50,51,52,78,79,80,81,82,83,93,98]},
	"ad423/meshochek": {"el1": [], "el2": []},
	"ad423/stuff": {"el1": [], "el2": []},
	"ad424/balahon": {"el1": [0,3,4,5,8,9,10,11,14,16,17,18,19,21,23,24,25,27,29,30,31,32,35,36,37,38,39,40,41,42,43,44,45,48,49,51,52,54,56,57,58,59,60,61,62,63,64,66,67,68,69,70,71,72,73,74,75,78,79,81,82,83,84,85,86,87,88,89,90,91,94,95,96,97,100,101,102,103,104,105,107,108,110,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,136,137,138,139,140,141,142,143,144,145,146,147,148,151,152,213,243,245,247,248,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,269], "el2": [0,3,4,5,6,7,8,9,10,11,12,14,16,17,18,19,21,22,23,24,25,26,27,28,29,30,31,32,35,36,37,38,39,40,41,42,43,44,45,48,49,50,51,52,54,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,78,79,80,81,82,83,84,85,86,87,88,89,90,91,94,95,96,97,98,100,101,102,103,104,105,107,108,110,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,155,193,209,213,214,215,234,237,238,239,241,243,244,245,247,248,249,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,267,269,270]},
	"ad424/blade": {"el1": [116,117,118,119], "el2": [0,13,14,17,25,26,83,84,100,101,116,117,118,119]},
	"ad424/body": {"el1": [], "el2": [1,2,3,4,5,6,7,8,9,11,18,20,32,33,34,35,36,43,44,45,46,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,121,122,193,194,199,202,203,206,208,225,226,228,229,230,232,233,253,255,256,257,258,259,260,265,267,269,270,281,282,283,284,285,286,287,289,293,295,296,297,298,299,300,338,339,394,395,396,402,404,405,408,410,416,417,418,419]},
	"ad424/hat": {"el1": [18,22,47,51], "el2": [16,17,18,19,22,26,31,32,33,34,45,46,47,48,50,53,54,55]},
	"cr407/body": {"el1": [109,138,139,140,141,142,143,144,473,496,497,498,499,500,624,758,759,760,761,762,763,766,767,768,769,770,771,772,774,775,777,778,780,781,784,785,786,787,788,789,792,793,794,795,796,797,798,799,800,801,802,803,804,806,807,809,810,812,813,822,840,841,842,843,844,847,849,850,851,852,853,854,855,856,926,927,928,929,930,931,934,935,936,937,938,939,940,943,946,947,948,949,950,951,952,954,955,957,958,961,964,970,971,972,973,974,977,979,980,981,982,983,984,985,986], "el2": [109,138,139,140,141,142,143,144,473,496,497,498,499,500,624,758,759,760,761,762,763,766,767,768,769,770,771,772,773,774,775,777,778,780,781,784,786,787,788,789,792,793,794,795,796,797,798,799,800,801,802,803,804,806,807,809,810,812,813,822,840,841,842,843,844,847,849,850,851,852,853,854,855,856,926,927,928,929,930,931,934,935,936,937,938,939,940,942,943,946,947,948,949,950,951,952,954,955,957,958,961,964,970,971,972,973,974,977,979,980,981,982,983,984,985,986]},
	"cr421/body1": {"el1": [1,11,35,43,64,68,70,108,109,114,115,116,117,118,119,120,121,122,123,124,125,126,129,130,194,196,206,207,208,209,225,226,229,230,233,255,256,257,258,259,267,268,269,270,281,283,284,292,293,294,295,296,297,298,300,325,326,331,332,333,334,335,336,337,338,339,340,341,342,343,346,347,395,396,404,405,408,409,410,411,418,419], "el2": [1,11,19,35,43,64,68,70,108,109,114,115,116,117,118,119,120,121,122,123,124,125,126,129,130,194,196,206,207,208,209,225,226,229,230,233,255,256,257,258,259,267,268,269,270,281,283,284,292,293,294,295,296,297,298,300,325,326,331,332,333,334,335,336,337,338,339,340,341,342,343,346,347,395,396,404,405,408,409,410,411,418,419]},
	"cr421/kirasa": {"el1": [16,19,20,26,28,59,62,68,70], "el2": [16,19,20,26,28,39,59,62,68,70]},
	"cr421/shield": {"el1": [], "el2": []},
	"cr421/sword": {"el1": [], "el2": []},
	"cr422/balahon": {"el1": [0,2,4,5,6,7,10,11,12,13,15,16,17,18,19,20,21,22,24,25,26,27,28,29,30,31,32,34,35,36,38,39,40,41,42,43,44,45,47,49,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,79,80,81,82,83,85,86,87,88,90,91,92,93,96,97,98,100,101,102,103,104,105,107,108,109,112,113,114,116,117,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,167,192,208,214,218,220,221,222,223,224,225,226,245,263,268,269,270,271], "el2": [0,1,2,4,5,6,7,10,11,12,13,15,16,17,18,19,20,21,22,24,25,26,27,28,29,30,31,32,34,35,36,38,39,40,41,42,43,44,45,47,49,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,79,80,81,82,83,85,86,87,88,90,91,92,93,94,96,97,98,100,101,102,103,105,107,108,109,112,113,114,116,117,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,167,192,208,214,218,220,221,222,223,224,225,226,245,263,268,269,270,271]},
	"cr422/body": {"el1": [1,2,3,4,5,8,9,11,17,19,21,23,27,28,29,31,32,33,35,41,42,44,45,46,54,57,58,59,64,65,66,68,69,70,71,72,73,74,75,76,122,193,194,202,203,206,208,225,226,228,229,233,235,241,243,245,247,251,252,253,256,257,259,260,265,266,267,268,269,270,278,281,282,283,284,285,286,288,289,293,295,296,297,298,299,339,395,396,404,405,408,410,416,417], "el2": [1,2,3,4,5,8,9,11,17,19,21,23,27,28,29,31,32,33,35,41,42,44,45,46,54,57,58,59,64,65,66,68,69,70,71,72,73,74,75,76,122,193,194,202,203,206,208,225,226,228,229,233,235,241,243,245,247,251,252,253,256,257,259,260,265,266,267,268,269,270,278,281,282,283,284,285,286,287,288,289,293,295,296,297,298,299,339,395,396,404,405,408,410,416,417]},
	"cr422/star": {"el1": [45,48,50,60,64,66,67], "el2": [45,48,50,56,60,64,66,67,71]},
	"cr423/body": {"el1": [102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,128,129,130,206,207,208,209,213,220,320,321,322,323,324,325,326,327,328,329,330,331,332,333,334,335,336,337,338,339,344,345,346,347,408,409,410,411,412], "el2": [102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,128,129,130,206,207,208,209,213,220,320,321,322,323,324,325,326,327,328,329,330,331,332,333,334,335,336,337,338,339,344,345,346,347,408,409,410,411,412]},
	"cr423/mask": {"el1": [43,44,45,46,47,48,49,50,51,52,78,79,80,81,82,83,93,98], "el2": [43,44,45,46,47,48,49,50,51,52,78,79,80,81,82,83,93,98]},
	"cr423/meshochek": {"el1": [], "el2": []},
	"cr423/stuff": {"el1": [], "el2": []},
	"cr424/balahon": {"el1": [0,1,3,4,5,6,7,8,9,10,11,12,14,16,17,18,19,21,22,23,24,25,26,27,28,29,30,31,32,35,36,37,38,39,40,41,42,43,44,45,48,49,50,51,52,54,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,78,79,80,81,82,83,84,85,86,87,88,89,90,91,94,95,96,97,98,100,101,102,103,104,105,107,108,110,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,193,209,212,213,214,215,238,239,241,243,244,245,247,248,249,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,269,270], "el2": [0,3,4,5,6,7,8,9,10,11,12,14,16,17,18,19,21,22,23,24,25,26,27,28,29,30,31,32,35,36,37,38,39,40,41,42,43,44,45,48,49,50,51,52,54,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,78,79,80,81,82,83,84,85,86,87,88,89,90,91,94,95,96,97,98,99,100,101,102,103,104,107,108,110,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,193,209,212,213,214,215,234,238,239,241,243,244,245,247,248,249,250,251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,269,270]},
	"cr424/blade": {"el1": [0,13,14,17,25,26,83,84,100,101,116,117,118,119], "el2": [0,13,14,17,25,26,83,84,100,101,116,117,118,119]},
	"cr424/body": {"el1": [1,2,3,4,5,6,7,8,9,11,18,20,32,33,34,35,36,43,44,45,46,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,121,122,193,194,198,199,202,203,206,208,225,226,228,229,230,232,233,253,255,256,257,258,259,260,265,267,269,270,281,282,283,284,285,286,287,289,292,293,295,296,297,298,299,300,338,339,394,395,396,402,404,405,408,410,416,417,418,419], "el2": [1,2,3,4,5,6,7,8,9,11,18,20,32,33,34,35,36,43,44,45,46,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,121,122,193,194,199,202,203,206,208,225,226,228,229,230,232,233,253,255,256,257,258,259,260,265,267,269,270,281,282,283,284,285,286,287,289,292,293,295,296,297,298,299,300,338,339,394,395,396,402,404,405,408,410,416,417,418,419]},
	"cr424/hat": {"el1": [16,17,18,19,22,26,29,32,33,34,45,46,47,48,53,54,55], "el2": [16,17,18,19,22,26,32,33,34,45,46,47,48,53,54,55]},
	"he513/body": {"el1": [0,1,2,3,5,12,14,15,16,17,18,19,20,21,22,23,24,25,26,27,31,32,33,34,35,36,37,38,39,40,44,46,47,48,49,50,53,54,55,56,58,59,60,61,62,63,64,65,66,67,68,69,73,74,75,76,77,79,80,81,82,84,85,86,87,88,89,90,91,92,93,94,95,96,99,100,101,102,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,136,137,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,158,159,160,161,162,163,164,165,166,167,168,169,171,172,173,174,175,176,177,178,179,180,181,182,183,184,186,188,190,192,196,197,199,200,201,202,203,204,205,206,208,209,210,211,212,213,214,215,216,217,218,220,221,222,223,224,225,226,227,228,229,230,231,232,234,241,243,244,245,246,247,248,249,250,251,252,253,254,255,256,260,261,262,263,264,265,266,267,268,269,273,275,276,277,278,279,282,283,284,285,287,288,289,290,291,292,293,294,295,296,297,298,300,302,303,304,305,306,308,309,311,313,314,315,316,317,318,319,320,321,322,323,324,325,328,329,330,331,333,334,335,336,337,338,339,340,341,342,343,344,345,346,347,348,350,351,352,353,354,355,356,357,358,359,360,361,362,363,365,366,368,369,370,371,372,373,374,375,376,377,378,379,380,381,382,383,384,385,386,387,388,389,390,391,392,393,394,395,396,397,398,399,400,401,402,403,404,405,406,407,408,409,410,411,412,413,414,417,419,420,426,427,429,430,431,432,433,434,436,437,438,439,440,441,442,443,444,445,447,448,449,451,452,453,454,455,456,457], "el2": [0,1,2,3,5,12,14,15,16,17,18,19,20,21,22,23,24,25,26,27,31,32,33,34,35,36,37,38,39,40,44,46,47,48,49,50,53,54,55,56,58,59,60,61,62,63,64,65,66,67,68,69,73,74,75,76,77,79,80,81,82,84,85,86,87,88,89,90,91,92,93,94,95,96,99,100,101,102,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,121,122,123,124,125,126,127,128,129,130,131,132,133,134,136,137,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,159,160,161,162,163,164,165,166,167,168,169,171,172,173,174,175,176,177,178,179,180,181,182,183,184,186,188,190,192,196,197,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,214,215,216,217,218,220,221,222,223,224,225,226,227,228,229,230,231,232,234,241,243,244,245,246,247,248,249,250,251,252,253,254,255,256,260,261,262,263,264,265,266,267,268,269,273,275,276,277,278,279,282,283,284,285,287,288,289,290,291,292,293,294,295,296,297,298,302,303,304,305,306,308,309,311,313,314,315,316,317,318,319,320,321,322,323,324,325,328,329,330,331,333,334,335,336,337,338,339,340,341,342,343,344,345,346,347,348,350,351,352,353,354,355,356,357,358,359,360,361,362,363,365,366,368,369,370,371,372,373,374,375,376,377,378,379,380,381,382,383,384,385,387,388,389,390,391,392,393,394,395,396,397,398,399,400,401,402,403,404,405,406,407,408,409,410,411,412,413,414,417,419,420,426,427,429,430,431,432,433,434,436,437,438,439,440,441,442,443,444,445,446,447,448,449,451,452,453,454,455,456,457]},
	"he513/head": {"el1": [0,1,2,3,4,5,6,7,8,9,10,11,13,14,15,17,18,19,20,22,23,24,25,26,27,28,29,30,31,33,34,35,36,37,38,39,40,41,42,43,44,45,46,48,49,52,53,54,55,56,57,58,60,61,62,63,64,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,89,90,91,93,94,95,96,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,124,125,128,129,130,131,132,133,134,136,137,138,139,140,143,144,145,146,147,148,149,150,151], "el2": [0,1,2,3,4,5,6,7,8,9,10,11,13,14,15,17,18,19,20,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,48,49,52,53,54,55,56,57,58,60,61,62,63,64,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,89,90,91,93,94,95,96,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,124,125,128,129,130,131,132,133,134,136,137,138,139,140,143,144,145,146,147,148,149,150,151]},
	"he513/l_hand": {"el1": [0,2,4,5,6,7,8,10,11,12,13,15,16,17,18,23,30,31,33,37,38,39,41,42,43,44,45,47,49,50,51,52,53,54,55,56,57,59,60,62,63,64,65,66,67,68,69,70,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,110,111,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,129,130,131,132,133,134,135,136,137,138,139,140,141,143,144,145,146,147,148,149], "el2": [0,2,4,5,6,7,8,10,11,12,13,15,16,17,18,23,30,31,33,37,38,39,41,42,43,44,45,47,48,49,50,51,52,53,54,55,56,57,59,60,62,63,64,65,66,67,68,69,70,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,109,110,111,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,129,130,131,132,133,134,135,136,137,138,139,140,141,143,144,145,146,147,148,149]},
	"he513/l_hand4": {"el1": [0,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,23,30,31,33,36,37,38,39,41,42,43,44,45,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,104,105,106,107,109,110,111,113,114,116,117,118,119,120,121,122,123,124,125,126,127,129,130,131,133,134,135,136,137,138,139,140,141,143,144,145,146,147,148,149], "el2": [0,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,23,30,31,33,36,37,38,39,41,42,43,44,45,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,104,105,106,107,110,111,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,129,130,131,133,134,135,136,137,138,139,140,141,143,144,145,146,147,148,149]},
	"he513/l_leaf": {"el1": [1,2,4,5,6,7,8,9,11,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [1,2,4,5,6,7,8,9,11,12,13,14,15,16,17,18,19,20,21,22,23]},
	"he513/l_leaf1": {"el1": [1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23], "el2": [1,2,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]},
	"he513/staff": {"el1": [1,2,5,6,8,9,10,11,12,13,14,15,16,17,18,19,21,22,23,24,25,26,27,28,29,32,33,35,36,37,38,39,40,41,42,43,44,46,47,48,52,53,54,55,56,57,59,60,61,62,63,64,65,66,67,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,86,87,88,90,91,92,93,96,98,99,100,102,103,104,105,106,107,108,109], "el2": [1,2,5,6,8,9,10,11,12,13,14,15,16,17,18,19,21,22,23,24,25,26,27,28,29,32,33,35,36,37,38,39,40,41,42,43,44,46,47,48,52,53,54,55,56,57,59,60,61,62,63,64,65,66,67,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,86,87,88,90,91,92,93,96,98,99,100,102,103,104,105,106,107,108,109]}
}

## Makes a part with twins (separate_twins) or listed lining
## (ONE_SIDED_FACES) one-sided (parsed.one_sided, which ELModel draws with
## back faces culled) and gives its single triangles reversed copies, all but
## the lining ones, so it still shows both sides there. Twins then each show
## only from the side they face, as in the originals, also where the part is
## translucent and the far twin showed through the near one.
static func one_sided_faces(parsed: Dictionary, template: String, part: String, edition: String) -> void:
	var key := template.to_lower() + "/" + part.to_lower()
	var lining_list: Variant = ONE_SIDED_FACES.get(key, {}).get(edition)
	var sheet_list: Variant = SHEET_FACES.get(key, {}).get(edition)
	var twinned: PackedByteArray = parsed.get("twinned", PackedByteArray())
	if lining_list == null and sheet_list == null and not twinned.has(1): return
	# Wholly one-sided parts (BACK_CULLED) keep no back faces at all.
	if is_back_culled(template, part):
		parsed.one_sided = true
		return
	var lining := {}
	for t: int in (lining_list if lining_list != null else []): lining[t] = true
	var sheets := {}
	for t: int in (sheet_list if sheet_list != null else []): sheets[t] = true
	var arrays: Array = parsed.arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var source_indices: PackedInt32Array = parsed.source_indices
	var count := indices.size() / 3
	for t in count:
		if lining.has(t) or (t < twinned.size() and twinned[t] == 1): continue
		if sheet_list != null and not sheets.has(t): continue
		var first := vertices.size()
		for k in [0, 2, 1]:
			var corner := indices[t * 3 + k]
			vertices.append(vertices[corner])
			normals.append(-normals[corner])
			uvs.append(uvs[corner])
			source_indices.append(source_indices[corner])
		indices.append_array([first, first + 1, first + 2])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	parsed.source_indices = source_indices
	parsed.one_sided = true

static func is_back_culled(template: String, part: String) -> bool:
	return part.to_lower() in BACK_CULLED.get(template.to_lower(), [])

## Metal's look: how metallic its grey and gold texels become, its
## reflectance and its roughness (a broad, soft sheen). The reflectance is
## the non-metallic share's: none, so texels the mask leaves out (plumes,
## hair, straps and skin on an armoured part) stay as matte as before and
## only the metallic texels shine.
const METAL_METALLIC := 0.6
const METAL_SPECULAR := 0.0
const METAL_ROUGHNESS := 0.28

static func is_metal_part(part: String, template := "") -> bool:
	var name := part.to_lower()
	if _named(name, METAL_PARTS) or name in METAL_NAMES or _named(name, METAL_WEAPONS): return true
	var key := template.to_lower()
	if key.begins_with("ad"): key = "cr" + key.substr(2)
	for pattern: String in METAL_FIGURE_PARTS.get(key, []):
		if name.match(pattern): return true
	return false

## Parts never metal: soft ones and the figure's named cloth.
## Figures whose wings are machines, not feathers or skin: blade wings of
## riveted plate (the Synthets' warriors and their winged machine, and the
## plated hero he512). Their wings are metal all over, whatever the paint.
const MACHINE_WINGS := ["he103", "he104", "he105", "he106", "he913", "he915", "he512", "cr111", "ad111"]
## Hues (from, to, the least saturation, the most value) a figure's metal is
## painted in where its paint is too dark
## a bronze for the classifier's gold: Diamanda's bronze armour (the second
## game's main heroine in her third and fourth skins) is metal wherever it is
## painted so, rather than in scattered patches that showed as dark spots.
## Her skin is a redder hue. The third Egyptian's gold collar and anklets,
## beside a hide painted in his blades' steel grey (his loincloth is a paler,
## less saturated gold).
const METAL_HUE_BANDS := {"he716": [0.078, 0.105, 0.32, 1.0], "he717": [0.078, 0.105, 0.32, 1.0],
	"cr711": [0.075, 0.13, 0.62, 1.0], "ad711": [0.075, 0.13, 0.62, 1.0]}
## Areas of a figure's skin (UV rectangles, each with the least saturation
## that counts there, and optionally the most) that are metal all over: the Ogre
## King's bronze scale mail above and below his belt, painted in the brown of
## the belt and his skin; the third Egyptian's studded gold collar, shaded
## down to near black (not the grey hide beside it).
## The Kinets' heroes wear their breastplates on their bodies, beside bare
## arms and bellies, in steel, gold, bronze or blackened iron by skin: the
## classifier found the steel ones but left bronze and gold plates (and blue
## tinted steel) in matte patches. Their plates are the same texels in every
## skin of a figure: the winged heroine's cups, the winged hero's breast and
## back plate, the lamia heroine's cuirass and cups (the most saturation
## leaves out the leather strap two of her skins draw across a cup; the
## sides under her arms, bare in her first skin, are left to the classifier)
## and the lamia hero's breastplate.
const METAL_UV_RECTS := {"cr204": [[Rect2(0.01, 0.01, 0.68, 0.08), 0.0], [Rect2(0.01, 0.19, 0.68, 0.1), 0.0]],
	"ad204": [[Rect2(0.01, 0.01, 0.68, 0.08), 0.0], [Rect2(0.01, 0.19, 0.68, 0.1), 0.0]],
	"cr711": [[Rect2(0.0, 0.79, 0.115, 0.19), 0.45], [Rect2(0.215, 0.84, 0.098, 0.14), 0.45]],
	"ad711": [[Rect2(0.0, 0.79, 0.115, 0.19), 0.45], [Rect2(0.215, 0.84, 0.098, 0.14), 0.45]],
	"he301": [[Rect2(0.6796875, 0.5234375, 0.1875, 0.09375), 0.0], [Rect2(0.6953125, 0.8515625, 0.03125, 0.0703125), 0.0]],
	"he303": [[Rect2(0.671875, 0.28125, 0.15625, 0.125), 0.0], [Rect2(0.828125, 0.28125, 0.15625, 0.1640625), 0.0],
		[Rect2(0.6953125, 0.40625, 0.125, 0.0390625), 0.0]],
	"he305": [[Rect2(0.6875, 0.34375, 0.28125, 0.1875), 0.0], [Rect2(0.6875, 0.53125, 0.28125, 0.015625), 0.0, 0.5],
		[Rect2(0.6875, 0.546875, 0.0859375, 0.078125), 0.0, 0.5],
		[Rect2(0.9140625, 0.546875, 0.0546875, 0.078125), 0.0, 0.5]],
	"he307": [[Rect2(0.671875, 0.3125, 0.3125, 0.09375), 0.0], [Rect2(0.6953125, 0.40625, 0.2890625, 0.0390625), 0.0],
		[Rect2(0.875, 0.4453125, 0.109375, 0.0078125), 0.0], [Rect2(0.7109375, 0.4453125, 0.1015625, 0.0703125), 0.0],
		[Rect2(0.9140625, 0.453125, 0.0625, 0.0625), 0.0]]}
## Areas of a figure's skin (UV rectangles) that are never metal, where one
## part is both armour and cloth: the first Red main hero's body is his
## gauntlets and his sackcloth robe, which is woven in his helmet's grey.
const MATTE_UV_RECTS := {"he704": [Rect2(0.0, 0.0, 0.74, 0.345)]}
## Parts that are plate all over, painted in the very brown of their wearer's
## skin or dulled to olive, so no colour tells their metal apart: the Chaots'
## ogre hero's helmet, pauldrons, brass greaves and knee plates, and the
## Chaot warriors' breastplates, pauldrons, vambraces and greaves, and the
## kobold guard's and warrior's bronze shields. The third Egyptian's blades
## are whole steel parts too, so his grey-violet hide learns nothing from
## them, and his gold collar and anklets are found by their hue
## (METAL_HUE_BANDS).
const SOLID_METAL_PARTS := {"he205": ["head", "l_hand1", "r_hand1", "l_leg1", "r_leg1", "l_leg2", "r_leg2"],
	"he203": ["breast", "l_koleno", "r_koleno", "l_naplechnik1", "r_naplechnik1", "l_noplechnik2", "r_naplechnik2"],
	"he207": ["breast", "l_koleno", "r_koleno", "l_naplechnik1", "r_naplechnik1", "l_noplechnik2", "r_naplechnik2"],
	"cr207": ["shield"], "ad207": ["shield"], "cr208": ["shield"], "ad208": ["shield"],
	"cr711": ["baton", "polysurface29386"], "ad711": ["baton", "polysurface29386"]}

## A part metal all over: a machine wing, or one in SOLID_METAL_PARTS.
static func is_solid_metal(template: String, part: String) -> bool:
	return is_machine_wing(template, part) or part.to_lower() in SOLID_METAL_PARTS.get(template.to_lower(), [])

static func is_cloth(template: String, part: String) -> bool:
	if is_machine_wing(template, part): return false
	return is_soft_part(part) or part.to_lower() in CLOTH_PARTS.get(template.to_lower(), [])

## A wing of a figure in MACHINE_WINGS.
static func is_machine_wing(template: String, part: String) -> bool:
	if template.to_lower() not in MACHINE_WINGS: return false
	var name := part.to_lower()
	return "wing" in name or name.begins_with("l_w_") or name.begins_with("r_w_")

## Maya's unnamed "polySurface" parts are not faces: matched as one, the
## armour, shields and jewellery of the figures whose parts kept Maya's names
## (the colourless creatures, many heroes) never turned to metal.
static func is_soft_part(part: String) -> bool:
	return _named(part.to_lower().replace("surface", "surf"), SOFT_PARTS)

static func _named(part: String, words: Array) -> bool:
	var name := part.to_lower()
	for word: String in words:
		if word in name: return true
	return false

## A part's material as metal, metallic where `mask` says (ELMetalMasks).
static func metal_material(base: StandardMaterial3D, mask: Texture2D) -> StandardMaterial3D:
	var metal := base.duplicate() as StandardMaterial3D
	metal.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	metal.metallic = METAL_METALLIC
	metal.metallic_specular = METAL_SPECULAR
	metal.roughness = METAL_ROUGHNESS
	if mask != null:
		metal.metallic_texture = mask
		metal.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return metal

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
