class_name ELTexture
extends RefCounted
## Decoder for Evil Islands ".mmp" textures.
## Images are returned in D3D memory order (row 0 = V 0), which matches
## Godot's UV convention, so model UVs from .fig files can be used as-is.

const MAGIC := 0x00504D4D  # "MMP\0"
const DATA_OFFSET := 76
const ONE_BIT_ALPHA := &"one_bit_alpha"
const AUTHORED_MASK_MIPS := &"authored_mask_mips"
## The compiled decoders (native/el_assets.c), where the platform has them.
static var native := ClassDB.class_exists(&"ELNativeAssets")


## A texture's image ready to read in `format`. An ImageTexture hands out
## the very image it was made from, so decompressing or converting what
## get_image() returns changes the texture everything else draws with: the
## particle sheets lost their transparency that way and drew as white
## squares. This copies first, and only when something has to change, so a
## texture already in the wanted format is shared as before.
static func readable(image: Image, format := Image.FORMAT_RGBA8) -> Image:
	if image == null: return null
	var copied := false
	if image.is_compressed():
		image = image.duplicate()
		copied = true
		if image.decompress() != OK: return null
	if image.get_format() != format:
		if not copied: image = image.duplicate()
		image.convert(format)
	return image

## The same, in whatever format the image already has: for a reader that
## only needs the pixels, and keeps them.
static func uncompressed(image: Image) -> Image:
	if image == null or not image.is_compressed(): return image
	image = image.duplicate()
	return null if image.decompress() != OK else image

## Largest side and pixel count of a texture level (the games' largest are
## 1024 a side); larger headers are taken as damaged.
const MAX_SIDE := 16384
const MAX_PIXELS := 1 << 26

static func decode(data: PackedByteArray) -> Image:
	if data.size() < DATA_OFFSET or data.decode_u32(0) != MAGIC:
		return null
	var w := data.decode_u32(4)
	var h := data.decode_u32(8)
	if not _dimensions_ok(w, h): return null
	var size_field := data.decode_u32(12)
	var tag := data.slice(16, 20)
	var img: Image
	if tag == "DXT1".to_ascii_buffer() or tag == "DXT3".to_ascii_buffer():
		# Whole 4×4 blocks: 8 bytes each in DXT1, 16 in DXT3.
		var dxt1 := tag == "DXT1".to_ascii_buffer()
		var length := w * h / 2 if dxt1 else w * h
		if w % 4 or h % 4 or data.size() < DATA_OFFSET + length: return null
		img = Image.create_from_data(w, h, false, Image.FORMAT_DXT1 if dxt1 else Image.FORMAT_DXT3,
				data.slice(DATA_OFFSET, DATA_OFFSET + length))
		if img.decompress() != OK: return null
	elif tag == "PNT3".to_ascii_buffer():
		img = _decode_pnt3(data, size_field, w, h)
	else:
		# Every Etherlords format, 8888 included, stores its rows top-down
		# (unlike Evil Islands, whose 8888 files are bottom-up).
		img = _decode_raw(data, w, h)
	if img and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Arena QU cutouts store a separate one-bit mask and colour at every level.
static func authored_mask_mipmaps(data: PackedByteArray, base: Image) -> Image:
	var levels := data.decode_u32(12)
	if levels < 2 or data.decode_u32(16) != 0x5551 or data.decode_u32(20) != 16: return null
	var width := base.get_width()
	var height := base.get_height()
	var offset := DATA_OFFSET + width * height * 2
	var pixels := base.get_data()
	var last: Image
	for level in range(1, levels):
		if width == 1 and height == 1: return null
		width = maxi(1, width / 2)
		height = maxi(1, height / 2)
		if offset + width * height * 2 > data.size(): return null
		last = _decode_raw(data, width, height, offset)
		if last == null: return null
		pixels.append_array(last.get_data())
		offset += width * height * 2
	# Godot uploads a complete chain. Generate its tail from the last stored level.
	last.generate_mipmaps()
	pixels.append_array(last.get_data().slice(width * height * 4))
	return Image.create_from_data(base.get_width(), base.get_height(), true, Image.FORMAT_RGBA8, pixels)


static func _decode_pnt3(data: PackedByteArray, size: int, w: int, h: int) -> Image:
	# Simple RLE: a dword with non-zero alpha is a BGRA pixel, otherwise it
	# is a count of zero bytes to emit.
	if native:
		var decoded: PackedByteArray = ClassDB.class_call_static(&"ELNativeAssets", &"decode_pnt3", data, size, w, h)
		if decoded.size() == w * h * 4: return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, decoded)
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var dst := 0
	var src := DATA_OFFSET
	var end := mini(DATA_OFFSET + size, data.size())
	while src + 4 <= end and dst < out.size():
		if data[src + 3] != 0:
			if dst + 4 <= out.size():
				out[dst] = data[src + 2]
				out[dst + 1] = data[src + 1]
				out[dst + 2] = data[src]
				out[dst + 3] = data[src + 3]
			dst += 4
		else:
			var v := data.decode_u32(src)
			dst += v if v != 0 else 4  # buffer is already zero-filled
		src += 4
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## Every 16-bit pixel value of a format, already as RGBA8 (one per mask set,
## shared by the worker threads that decode textures).
static var _tables := {}
static var _tables_lock := Mutex.new()

static func _channel(px: int, m: PackedInt64Array, alpha: bool) -> int:
	if alpha and m[2] == 0: return 255
	var full := m[0] >> m[1]
	return int(0.5 + 255.0 * ((px & m[0]) >> m[1]) / full) if full else 0

static func _dimensions_ok(w: int, h: int) -> bool:
	return w > 0 and h > 0 and w <= MAX_SIDE and h <= MAX_SIDE and w * h <= MAX_PIXELS

## The channels of a masked (16- or 32-bit) level at `src`: a, r, g, b, each
## (mask, shift, bit count); empty when the header is damaged. The same rules
## as the compiled decoder: each shift below the pixel's width, each mask
## exactly its bit count of ones from its shift up (a channel the format
## lacks has neither mask nor bits), and the whole level inside the data.
static func raw_format(data: PackedByteArray, w: int, h: int, src := DATA_OFFSET) -> Array[PackedInt64Array]:
	var masks: Array[PackedInt64Array] = []
	if not _dimensions_ok(w, h) or data.size() < DATA_OFFSET or src < DATA_OFFSET or src > data.size(): return masks
	var depth := data.decode_u32(20)
	if depth != 16 and depth != 32: return masks
	for c in 4:
		var p := 24 + c * 12
		var mask := data.decode_u32(p)
		var shift := data.decode_u32(p + 4)
		var bits := data.decode_u32(p + 8)
		var ok := shift < depth and bits <= depth
		if ok and mask == 0: ok = bits == 0
		elif ok: ok = bits > 0 and shift + bits <= depth and mask == ((1 << bits) - 1) << shift
		if not ok:
			masks.clear()
			return masks
		masks.append(PackedInt64Array([mask, shift, bits]))
	if w * h * (depth / 8) > data.size() - src: masks.clear()
	return masks

static func _decode_raw(data: PackedByteArray, w: int, h: int, src := DATA_OFFSET) -> Image:
	var masks := raw_format(data, w, h, src)
	if masks.is_empty(): return null
	if native:
		var decoded: PackedByteArray = ClassDB.class_call_static(&"ELNativeAssets", &"decode_raw", data, w, h, src)
		if decoded.size() == w * h * 4: return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, decoded)
	var bpp := data.decode_u32(20) / 8
	var out := PackedByteArray()
	out.resize(w * h * 4)
	if bpp == 2:
		# a,r,g,b -> r,g,b,a, through the format's table.
		var signature := str(masks)
		_tables_lock.lock()
		var table: PackedInt32Array = _tables.get(signature, PackedInt32Array())
		if table.is_empty():
			table.resize(65536)
			for px in 65536:
				table[px] = _channel(px, masks[1], false) | (_channel(px, masks[2], false) << 8) | (_channel(px, masks[3], false) << 16) | (_channel(px, masks[0], true) << 24)
			_tables[signature] = table
		_tables_lock.unlock()
		for i in w * h:
			out.encode_u32(i * 4, table[data.decode_u16(src + i * 2)])
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
	for i in w * h:
		var px: int = data.decode_u32(src)
		src += bpp
		out.encode_u32(i * 4, _channel(px, masks[1], false) | (_channel(px, masks[2], false) << 8) | (_channel(px, masks[3], false) << 16) | (_channel(px, masks[0], true) << 24))
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
