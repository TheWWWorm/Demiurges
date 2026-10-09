class_name ELTileSet
extends RefCounted
## Both editions use 32 fixed terrain records followed by square BGR tiles.
## Corner masks and chroma-key overlays compose transitions between terrain
## types. Completed tiles can be packed once and shared by terrain chunks.
const HEADER := 0x12910
const RECORD := 2376
## A corner kind with this bit is the greyscale copy of its terrain
## (Etherlords II colourless zones). It shares its record and priority but
## forms its own layer, so grey and coloured corners meet along the terrain's
## own transition masks.
const GREY := 0x40
var side := 0
var types: Dictionary = {}
var pixels: Array[PackedByteArray] = []
var error := ""
var _rotations: Dictionary = {}

func load_file(path: String) -> bool:
	return parse(FileAccess.get_file_as_bytes(path)) if not path.is_empty() else _fail("Missing tileset.")

func parse(bytes: PackedByteArray) -> bool:
	types.clear()
	pixels.clear()
	_rotations.clear()
	error = ""
	if bytes.size() < HEADER or bytes.decode_u32(0) != 0x5fe634b1: return _fail("Invalid tileset header.")
	var count := bytes.decode_u32(4)
	var texture_count := bytes.decode_u32(HEADER - 8)
	side = bytes.decode_u32(HEADER - 4)
	if count > 32 or count < 1 or side < 1 or side > 512 or texture_count < 1 or texture_count > 4096: return _fail("Invalid tileset dimensions.")
	var stride := side * side * 3
	if HEADER + stride * texture_count != bytes.size(): return _fail("Truncated tileset pixels.")
	for i in texture_count: pixels.append(bytes.slice(HEADER + i * stride, HEADER + (i + 1) * stride))
	for i in count:
		var base := 8 + i * RECORD
		var kind := bytes.decode_u32(base + 2336)
		if kind >= 32 or types.has(kind): return _fail("Invalid terrain type.")
		var record := {"priority": bytes.decode_u32(base + 2332), "movement": bytes.decode_s32(base + 2340), "full": [], "masks": [], "overlays": []}
		record.full = _groups(bytes, base + 4, bytes.decode_u32(base), 8)
		for shape in 3:
			record.masks.append(_groups(bytes, base + 592 + shape * 288, bytes.decode_u32(base + 580 + shape * 4), 4))
			record.overlays.append(_groups(bytes, base + 1468 + shape * 288, bytes.decode_u32(base + 1456 + shape * 4), 4))
		if not error.is_empty() or record.full.is_empty(): return _fail("Invalid terrain image group.")
		types[kind] = record
	return true

func _groups(bytes: PackedByteArray, offset: int, count: int, maximum: int) -> Array:
	var groups := []
	if count > maximum:
		_fail("Too many tileset variants.")
		return groups
	for i in count:
		var at := offset + i * 72
		var frames := bytes.decode_u32(at)
		if frames < 1 or frames > 32:
			_fail("Invalid terrain animation.")
			return []
		var ids: Array[int] = []
		for j in frames:
			var id := bytes.decode_u16(at + 4 + j * 2)
			if id >= pixels.size():
				_fail("Missing terrain texture.")
				return []
			ids.append(id)
		groups.append({"ids": ids, "period": bytes.decode_u32(at + 68)})
	return groups

func plan(corners: Array[int], variation := 0, base_rotation := 0) -> Dictionary:
	if corners.size() != 4 or variation < 0: return {}
	for kind in corners:
		if kind < 0 or not types.has(kind & ~GREY): return {}
	var remaining := corners.duplicate()
	var kind := _lowest(remaining)
	var record: Dictionary = types[kind & ~GREY]
	var variant := 0
	if corners.count(kind) == 4:
		variant = variation % record.full.size()
		variation /= record.full.size()
	var layers := [{"source": record.full[variant], "mask": {}, "overlay": {}, "rotation": base_rotation & 3, "grey": (kind & GREY) != 0}]
	var frames: int = record.full[variant].ids.size()
	for i in 4:
		if remaining[i] == kind: remaining[i] = -1
	while remaining != [-1, -1, -1, -1]:
		kind = _lowest(remaining)
		record = types[kind & ~GREY]
		var rotation := 0
		var shape := 0
		var found := false
		for candidate in [2, 1, 0]:
			for turn in 4:
				var positions: Array = [[0], [0, 1], [0, 1, 3]][candidate]
				var matches := true
				for pos: int in positions:
					if remaining[(pos + turn) % 4] != kind: matches = false
				if matches:
					shape = candidate
					rotation = turn
					found = true
					break
			if found: break
		var masks: Array = record.masks[shape]
		if masks.is_empty(): return {}
		variant = variation % masks.size()
		variation /= masks.size()
		var overlay: Dictionary = record.overlays[shape][variant] if variant < record.overlays[shape].size() else {}
		layers.append({"source": record.full[0], "mask": masks[variant], "overlay": overlay, "rotation": rotation, "grey": (kind & GREY) != 0})
		frames = maxi(frames, maxi(record.full[0].ids.size(), masks[variant].ids.size()))
		for i in 4:
			if remaining[i] == kind and (shape > 0 or i == rotation): remaining[i] = -1
	if variation > 0: return {}
	return {"layers": layers, "frames": frames}

func compose(composition: Dictionary, frame := 0) -> Image:
	if composition.is_empty(): return null
	var output := PackedByteArray()
	for layer: Dictionary in composition.layers:
		var grey: bool = layer.get("grey", false)
		var source: PackedByteArray = pixels[layer.source.ids[frame % layer.source.ids.size()]]
		if grey: source = _grey(source)
		if layer.mask.is_empty():
			var base := _rotated(layer.source.ids[frame % layer.source.ids.size()], layer.rotation)
			output = _grey(base) if grey else base.duplicate()
			continue
		var mask := _rotated(layer.mask.ids[frame % layer.mask.ids.size()], layer.rotation)
		for i in output.size(): output[i] = ((255 - int(mask[i])) * int(output[i]) + int(source[i]) * int(mask[i])) / 255
		if not layer.overlay.is_empty():
			var overlay := _rotated(layer.overlay.ids[frame % layer.overlay.ids.size()], layer.rotation)
			for i in range(0, output.size(), 3):
				if overlay[i] != 255 or overlay[i + 1] != 0 or overlay[i + 2] != 255:
					var value := (int(overlay[i]) + int(overlay[i + 1]) + int(overlay[i + 2])) / 3 if grey else -1
					output[i] = overlay[i] if value < 0 else value
					output[i + 1] = overlay[i + 1] if value < 0 else value
					output[i + 2] = overlay[i + 2] if value < 0 else value
	for i in range(0, output.size(), 3):
		var blue := output[i]
		output[i] = output[i + 2]
		output[i + 2] = blue
	return Image.create_from_data(side, side, false, Image.FORMAT_RGB8, output)

## How grey each texel of a composition is (0..255), at `out_side` square:
## the same layers and masks as compose(), carrying 255 for a grey layer and
## 0 for a coloured one. The renderer blends the coloured tile towards its
## greyscale by this weight, which matches the composed greyscale layers
## wherever one layer covers a texel. Frame 0 of animated masks is used.
func grey_weights(composition: Dictionary, out_side: int) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(out_side * out_side)
	if composition.is_empty() or side < 1: return output
	var picks := PackedInt32Array()
	picks.resize(out_side * out_side)
	for y in out_side:
		for x in out_side:
			picks[y * out_side + x] = (((y * side) / out_side + side / (2 * out_side)) * side + (x * side) / out_side + side / (2 * out_side)) * 3
	for layer: Dictionary in composition.layers:
		var value := 255 if layer.get("grey", false) else 0
		if layer.mask.is_empty():
			output.fill(value)
			continue
		var mask := _rotated(layer.mask.ids[0], layer.rotation)
		var overlay := _rotated(layer.overlay.ids[0], layer.rotation) if not layer.overlay.is_empty() else PackedByteArray()
		for i in picks.size():
			var at := picks[i]
			var m := int(mask[at])
			output[i] = ((255 - m) * int(output[i]) + value * m) / 255
			if not overlay.is_empty() and (overlay[at] != 255 or overlay[at + 1] != 0 or overlay[at + 2] != 255): output[i] = value
	return output

static func _grey(source: PackedByteArray) -> PackedByteArray:
	var result := source.duplicate()
	for i in range(0, result.size(), 3):
		var value := (int(result[i]) + int(result[i + 1]) + int(result[i + 2])) / 3
		result[i] = value
		result[i + 1] = value
		result[i + 2] = value
	return result

func _rotated(id: int, turns: int) -> PackedByteArray:
	if turns == 0: return pixels[id]
	var key := id * 4 + turns
	if _rotations.has(key): return _rotations[key]
	var image := Image.create_from_data(side, side, false, Image.FORMAT_RGB8, pixels[id])
	for i in turns: image.rotate_90(CLOCKWISE)
	_rotations[key] = image.get_data()
	return _rotations[key]

func _lowest(corners: Array[int]) -> int:
	var first := -1
	for kind: int in corners:
		if kind >= 0 and (first == -1 or types[kind & ~GREY].priority < types[first & ~GREY].priority): first = kind
	return first

func _fail(message: String) -> bool:
	error = message
	return false
