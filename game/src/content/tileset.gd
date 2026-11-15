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
## Every stored tile (full, mask, overlay; 96 px EL2, 48 px EL1) repeats its
## outer texels mirrored across this margin; a map cell shows the inner square
## (seams between cells otherwise show mirrored crosses the original lacks).
const BORDER := 4
## Water and bog share the liquid terrain treatment. Lava has its own tile.
const BOG_KIND := 19
const WATER_KINDS := [16, BOG_KIND]
var side := 0
var types: Dictionary = {}
var pixels: Array[PackedByteArray] = []
var error := ""
var _rotations: Dictionary = {}
var _cache_lock := Mutex.new()
var _red_tiles: Dictionary = {}
var _tile_runs: Dictionary = {}
var _pick_cache: Dictionary = {}

func load_file(path: String) -> bool:
	return parse(FileAccess.get_file_as_bytes(path)) if not path.is_empty() else _fail("Missing tileset.")

func parse(bytes: PackedByteArray) -> bool:
	types.clear()
	pixels.clear()
	_rotations.clear()
	_red_tiles.clear()
	_tile_runs.clear()
	_pick_cache.clear()
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
	var layers := [{"source": record.full[variant], "mask": {}, "overlay": {}, "rotation": base_rotation & 3,
		"grey": (kind & GREY) != 0, "water": (kind & ~GREY) in WATER_KINDS, "bog": (kind & ~GREY) == BOG_KIND}]
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
		layers.append({"source": record.full[0], "mask": masks[variant], "overlay": overlay, "rotation": rotation,
			"grey": (kind & GREY) != 0, "water": (kind & ~GREY) in WATER_KINDS, "bog": (kind & ~GREY) == BOG_KIND})
		frames = maxi(frames, maxi(record.full[0].ids.size(), masks[variant].ids.size()))
		for i in 4:
			if remaining[i] == kind and (shape > 0 or i == rotation): remaining[i] = -1
	if variation > 0: return {}
	return {"layers": layers, "frames": frames}

func compose(composition: Dictionary, frame := 0) -> Image:
	if composition.is_empty(): return null
	# Works on red-first copies of the stored blue-first tiles: every step
	# treats the channels alike (the overlay key, magenta, reads the same
	# either way), so the result needs no final swap.
	var output := PackedByteArray()
	for layer: Dictionary in composition.layers:
		var grey: bool = layer.get("grey", false)
		var source_id: int = layer.source.ids[frame % layer.source.ids.size()]
		if layer.mask.is_empty():
			var base := _red_first(source_id, layer.rotation)
			output = _grey(base) if grey else base
			continue
		var source := _red_first(source_id, 0)
		if grey: source = _grey(source)
		var mask_id: int = layer.mask.ids[frame % layer.mask.ids.size()]
		output = _blend(output, source, _red_first(mask_id, layer.rotation), _runs(mask_id, layer.rotation, false))
		if not layer.overlay.is_empty():
			var overlay_id: int = layer.overlay.ids[frame % layer.overlay.ids.size()]
			var overlay := _red_first(overlay_id, layer.rotation)
			# A grey layer's overlay texels take their channel average.
			if grey: overlay = _grey(overlay)
			output = _blend(output, overlay, PackedByteArray(), _runs(overlay_id, layer.rotation, true))
	return Image.create_from_data(side, side, false, Image.FORMAT_RGB8, output)

## Mixes `source` over `below` by `mask` (out = ((255 - m) * below + m *
## source) / 255 per byte), along runs of [kind, start, end]: kind 0 keeps
## `below`, 1 takes `source` (a clear or full mask gives those exactly) and 2
## mixes byte by byte. The division by 255 is done as
## (x + 1 + (x >> 8)) >> 8, equal for every x up to 255 * 255; GDScript's
## integer division does not scale across worker threads.
static func _blend(below: PackedByteArray, source: PackedByteArray, mask: PackedByteArray, runs: PackedInt32Array) -> PackedByteArray:
	if runs.size() == 3 and runs[0] == 0: return below
	var result := below.duplicate()
	for r in range(0, runs.size(), 3):
		match runs[r]:
			0: pass
			1:
				for i in range(runs[r + 1], runs[r + 2]): result[i] = source[i]
			_:
				for i in range(runs[r + 1], runs[r + 2]):
					var weight := mask[i]
					var mixed := (255 - weight) * result[i] + source[i] * weight
					result[i] = (mixed + 1 + (mixed >> 8)) >> 8
	return result

## A stored tile (turned `turns` quarters) with red first. compose() may run
## on worker threads (ELAdventureTerrain), which share these caches.
func _red_first(id: int, turns: int) -> PackedByteArray:
	var key := id * 4 + turns
	_cache_lock.lock()
	var found: Variant = _red_tiles.get(key)
	_cache_lock.unlock()
	if found != null: return found
	var swapped := _rotated(id, turns).duplicate()
	for i in range(0, swapped.size(), 3):
		var blue := swapped[i]
		swapped[i] = swapped[i + 2]
		swapped[i + 2] = blue
	_cache_lock.lock()
	_red_tiles[key] = swapped
	_cache_lock.unlock()
	return swapped

## Runs of a red-first tile for _blend: a mask's bytes by weight (0, 255 or
## between), or an overlay's texels by its magenta key (kept 0, drawn 1).
func _runs(id: int, turns: int, overlay: bool) -> PackedInt32Array:
	var key := (id * 4 + turns) * 2 + int(overlay)
	_cache_lock.lock()
	var found: Variant = _tile_runs.get(key)
	_cache_lock.unlock()
	if found != null: return found
	var bytes := _red_first(id, turns)
	var runs := PackedInt32Array()
	var step := 3 if overlay else 1
	var kind := -1
	for i in range(0, bytes.size(), step):
		var here: int
		if overlay: here = 0 if bytes[i] == 255 and bytes[i + 1] == 0 and bytes[i + 2] == 255 else 1
		else: here = 0 if bytes[i] == 0 else (1 if bytes[i] == 255 else 2)
		if here != kind:
			if kind >= 0: runs.append(i)
			runs.append_array([here, i])
			kind = here
	runs.append(bytes.size())
	_cache_lock.lock()
	_tile_runs[key] = runs
	_cache_lock.unlock()
	return runs

## How grey each texel of a composition is (0..255), at `out_side` square:
## the same layers and masks as compose(), carrying 255 for a grey layer and
## 0 for a coloured one. The renderer blends the coloured tile towards its
## greyscale by this weight, which matches the composed greyscale layers
## wherever one layer covers a texel. Frame 0 of animated masks is used.
func grey_weights(composition: Dictionary, out_side: int) -> PackedByteArray:
	return layer_weights(composition, out_side, "grey")

## Coverage of marked layers in a tile at the given animation frame, using
## its original transition mask and overlay.
func layer_weights(composition: Dictionary, out_side: int, flag: String, frame := 0) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(out_side * out_side)
	if composition.is_empty() or side < 1: return output
	var picks := _picks(out_side)
	for layer: Dictionary in composition.layers:
		var value := 255 if layer.get(flag, false) else 0
		if layer.mask.is_empty():
			output.fill(value)
			continue
		var mask := _rotated(layer.mask.ids[frame % layer.mask.ids.size()], layer.rotation)
		var overlay := _rotated(layer.overlay.ids[frame % layer.overlay.ids.size()], layer.rotation) if not layer.overlay.is_empty() else PackedByteArray()
		for i in picks.size():
			var at := picks[i]
			var m := mask[at]
			var mixed := (255 - m) * output[i] + value * m
			output[i] = (mixed + 1 + (mixed >> 8)) >> 8
			if not overlay.is_empty() and (overlay[at] != 255 or overlay[at + 1] != 0 or overlay[at + 2] != 255): output[i] = value
	return output

## The stored texel each output texel of layer_weights reads (shared by
## every call at that size; worker threads may ask for them).
func _picks(out_side: int) -> PackedInt32Array:
	_cache_lock.lock()
	var found: Variant = _pick_cache.get(out_side)
	_cache_lock.unlock()
	if found != null: return found
	var picks := PackedInt32Array()
	picks.resize(out_side * out_side)
	for y in out_side:
		for x in out_side:
			var inner := side - 2 * BORDER
			picks[y * out_side + x] = ((BORDER + (y * inner) / out_side + inner / (2 * out_side)) * side + BORDER + (x * inner) / out_side + inner / (2 * out_side)) * 3
	_cache_lock.lock()
	_pick_cache[out_side] = picks
	_cache_lock.unlock()
	return picks

static func _grey(source: PackedByteArray) -> PackedByteArray:
	var result := source.duplicate()
	for i in range(0, result.size(), 3):
		var value := (int(result[i]) + int(result[i + 1]) + int(result[i + 2])) / 3
		result[i] = value
		result[i + 1] = value
		result[i + 2] = value
	return result

## compose() and layer_weights() may run on worker threads (ELAdventureTerrain),
## which share the rotated tile cache.
func _rotated(id: int, turns: int) -> PackedByteArray:
	if turns == 0: return pixels[id]
	var key := id * 4 + turns
	_cache_lock.lock()
	var found: Variant = _rotations.get(key)
	if found == null:
		var image := Image.create_from_data(side, side, false, Image.FORMAT_RGB8, pixels[id])
		for i in turns: image.rotate_90(CLOCKWISE)
		found = image.get_data()
		_rotations[key] = found
	_cache_lock.unlock()
	return found

func _lowest(corners: Array[int]) -> int:
	var first := -1
	for kind: int in corners:
		if kind >= 0 and (first == -1 or types[kind & ~GREY].priority < types[first & ~GREY].priority): first = kind
	return first

func _fail(message: String) -> bool:
	error = message
	return false
