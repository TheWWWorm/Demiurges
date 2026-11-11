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


static func decode(data: PackedByteArray) -> Image:
	if data.size() < DATA_OFFSET or data.decode_u32(0) != MAGIC:
		return null
	var w := data.decode_u32(4)
	var h := data.decode_u32(8)
	var size_field := data.decode_u32(12)
	var tag := data.slice(16, 20)
	var img: Image
	if tag == "DXT1".to_ascii_buffer():
		img = Image.create_from_data(w, h, false, Image.FORMAT_DXT1,
				data.slice(DATA_OFFSET, DATA_OFFSET + w * h / 2))
		img.decompress()
	elif tag == "DXT3".to_ascii_buffer():
		img = Image.create_from_data(w, h, false, Image.FORMAT_DXT3,
				data.slice(DATA_OFFSET, DATA_OFFSET + w * h))
		img.decompress()
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

static func _decode_raw(data: PackedByteArray, w: int, h: int, src := DATA_OFFSET) -> Image:
	if native:
		var decoded: PackedByteArray = ClassDB.class_call_static(&"ELNativeAssets", &"decode_raw", data, w, h, src)
		if decoded.size() == w * h * 4: return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, decoded)
	var bpp := data.decode_u32(20) / 8
	var masks: Array[PackedInt64Array] = []
	for c in 4:  # a, r, g, b: (mask, shift, bit count)
		var p := 24 + c * 12
		masks.append(PackedInt64Array([data.decode_u32(p), data.decode_u32(p + 4), data.decode_u32(p + 8)]))
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
		var end := mini(w * h, (data.size() - src) / 2)
		for i in end:
			out.encode_u32(i * 4, table[data.decode_u16(src + i * 2)])
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
	for i in w * h:
		var px: int = data.decode_u32(src)
		src += bpp
		out.encode_u32(i * 4, _channel(px, masks[1], false) | (_channel(px, masks[2], false) << 8) | (_channel(px, masks[3], false) << 16) | (_channel(px, masks[0], true) << 24))
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
