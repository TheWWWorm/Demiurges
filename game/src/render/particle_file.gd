class_name ELParticleFile
extends RefCounted
## Second-game baked particle animation (.pfx in pfx.res), 30 frames a second.
##
##   u32, u32 frames
##   per frame: u32 n; n x u32 particle id; n x (x, y, z) f32; n x f32 size;
##              n x u16 atlas cell; n x (r, g, b) u8; n x u8 alpha
##   u16 length + texture name; u32 atlas columns; u32 atlas rows;
##   u16 blend (1 additive, 0 alpha); u32 loop start; u32 loop end
## Coordinates are relative to the effect origin, z up, two units per map cell.
## A non-zero loop end makes the effect cyclic: the emission repeats every
## (loop end) frames while earlier cycles play their tail to the last frame.
const MAGIC := 0x1468fcca
const FPS := 30.0
const MAX_FRAMES := 4096
## Largest frame in the shipped files: Ublockable.pfx (combat), 18,645.
const MAX_PARTICLES := 32768

## Camera-facing particle quads in every renderer (combat effects, figure
## clips, adventure script effects and weather, combat blood drops) share this
## size rule. A particle's size is a screen measure in the originals: each
## corner moves by size / w in normalized device units on both axes, which as a
## view-space half-extent is size / P[0][0]. A 4:3 view is assumed so sprites
## keep their size in wider windows. The remake's adventure map uses an
## orthographic camera, which has no w to scale by; there the size stays the
## half-extent (the original map camera's projection is not reproduced).
## Shaders name SPRITE_SIZE_FUNCTION on its own line; `sprite_shader` inserts
## the function there.
const SPRITE_SIZE_FUNCTION := """float sprite_half_extent(float size, mat4 projection) {
	if (projection[3][3] == 1.0) return size;
	return size * 4.0 / (3.0 * projection[1][1]);
}"""

static func sprite_shader(code: String) -> String:
	return code.replace("SPRITE_SIZE_FUNCTION", SPRITE_SIZE_FUNCTION)

var frames := 0
## First particle of each frame (frames + 1 entries).
var starts := PackedInt32Array()
var positions := PackedFloat32Array()
var sizes := PackedFloat32Array()
## Atlas cell per particle (u16 little-endian pairs).
var cells := PackedByteArray()
## RGB bytes per particle, and alpha bytes.
var rgb := PackedByteArray()
var alpha := PackedByteArray()
var texture := ""
var columns := 1
var rows := 1
var additive := false
var loop_start := 0
var loop_end := 0
var max_count := 0
var error := ""
## MultiMesh instance data of each frame (16 floats per particle), built the
## first time the frame is drawn and shared by every effect using this file.
var _instances: Dictionary = {}

static func decode(bytes: PackedByteArray) -> ELParticleFile:
	var file := ELParticleFile.new()
	file._parse(bytes)
	return file

func _parse(bytes: PackedByteArray) -> void:
	if bytes.size() < 8 or bytes.decode_u32(0) != MAGIC:
		error = "Not a particle file"
		return
	frames = bytes.decode_u32(4)
	if frames < 1 or frames > MAX_FRAMES:
		error = "Invalid particle frame count"
		return
	var at := 8
	starts.resize(frames + 1)
	var total := 0
	for frame in frames:
		starts[frame] = total
		if at + 4 > bytes.size(): return _bad()
		var count := bytes.decode_u32(at)
		at += 4
		if count > MAX_PARTICLES or at + count * 26 > bytes.size(): return _bad()
		max_count = maxi(max_count, count)
		at += count * 4
		positions.append_array(bytes.slice(at, at + count * 12).to_float32_array())
		at += count * 12
		sizes.append_array(bytes.slice(at, at + count * 4).to_float32_array())
		at += count * 4
		cells.append_array(bytes.slice(at, at + count * 2))
		at += count * 2
		rgb.append_array(bytes.slice(at, at + count * 3))
		alpha.append_array(bytes.slice(at + count * 3, at + count * 4))
		at += count * 4
		total += count
	starts[frames] = total
	if at + 2 > bytes.size(): return _bad()
	var length := bytes.decode_u16(at)
	at += 2
	if at + length + 18 > bytes.size(): return _bad()
	texture = bytes.slice(at, at + length).get_string_from_ascii()
	at += length
	columns = clampi(bytes.decode_u32(at), 1, 64)
	rows = clampi(bytes.decode_u32(at + 4), 1, 64)
	additive = bytes.decode_u16(at + 8) == 1
	loop_start = bytes.decode_u32(at + 10)
	loop_end = bytes.decode_u32(at + 14)
	if loop_end >= frames or loop_start > loop_end: loop_end = 0

func _bad() -> void:
	error = "Truncated particle file"
	frames = 0

## The frames drawn together `frame` frames after the start: one per cycle
## still playing. `loops` is the script's loop count (-1 unlimited).
func visible_frames(frame: int, loops := -1) -> PackedInt32Array:
	var result := PackedInt32Array()
	if frames < 1 or frame < 0: return result
	if loop_end <= 0:
		if frame < frames: result.append(frame)
		return result
	var period := loop_end
	var cycle := frame / period
	var phase := frame % period
	var newest := cycle if loops < 0 else mini(cycle, loops)
	for back in range(0, cycle + 1):
		var at := phase + back * period
		if at >= frames: break
		# Cycles past the loop count are not started again.
		if cycle - back > newest: continue
		result.append(at)
	return result

## Whether the effect has played out (non-cyclic, or cyclic with its loops used).
func finished(frame: int, loops := -1) -> bool:
	if loop_end <= 0: return frame >= frames
	return loops >= 0 and frame >= frames + loops * loop_end

## The frame's particles as MultiMesh instance data: the transform carries the
## size (basis x and z), the atlas cell + 1 (basis y) and the position in
## map-scene axes (x east, y up, z south); the custom data is RGBA.
func instances(frame: int) -> PackedFloat32Array:
	var cached: Variant = _instances.get(frame)
	if cached != null: return cached
	var first := starts[frame]
	var count := starts[frame + 1] - first
	var buffer := PackedFloat32Array()
	buffer.resize(count * 16)
	buffer.fill(0.0)
	for n in count:
		var i := first + n
		var o := n * 16
		var size: float = sizes[i]
		buffer[o] = size
		buffer[o + 3] = positions[i * 3]
		buffer[o + 5] = float(cells.decode_u16(i * 2) + 1)
		buffer[o + 7] = positions[i * 3 + 2]
		buffer[o + 10] = size
		buffer[o + 11] = -positions[i * 3 + 1]
		buffer[o + 12] = rgb[i * 3] / 255.0
		buffer[o + 13] = rgb[i * 3 + 1] / 255.0
		buffer[o + 14] = rgb[i * 3 + 2] / 255.0
		buffer[o + 15] = alpha[i] / 255.0
	_instances[frame] = buffer
	return buffer
