class_name ELMinimapPicture
extends RefCounted
## Authored minimap picture of an adventure map.
##
## First game: the scenario's <minimap> name selects
## Resources/MiniMap/<name>.bmp (160×160). When it is missing, the game builds
## the picture from the map cells instead (the HUD keeps its terrain-colour
## image for that case).
## Second game: the picture is the map file with the .bm1 extension
## (Maps/<id>.bm1 or Tutorial/Adventure/e2tutorial.bm1, 130×130). When it is
## missing or not square, the strategic minimap draws nothing: no picture, no
## fog and no markers, so the panel artwork shows through.

## Installation-relative picture path of a map, or "" when it names none.
static func path(map: ELAdventureMap) -> String:
	if map == null or map.profile == null: return ""
	if map.profile.id == "el1":
		var name := str(ELXml.value(map.document, "minimap")).strip_edges()
		return "" if name.is_empty() else "Resources/MiniMap/" + name + ".bmp"
	if map.id.is_empty(): return ""
	return (map.id if map.id.contains("/") else "Maps/" + map.id) + ".bm1"

## The decoded picture (top row = top of the minimap), or null when the file
## is missing, unreadable or (second game) not square.
static func load_for(map: ELAdventureMap) -> Image:
	var relative := path(map)
	if relative.is_empty(): return null
	var file := map.profile.file(relative)
	if file.is_empty(): return null
	var image := decode(FileAccess.get_file_as_bytes(file))
	if image == null: return null
	if map.profile.id != "el1" and image.get_width() != image.get_height(): return null
	return image

## Uncompressed 24- or 32-bit BMP (BI_RGB, or BI_BITFIELDS with byte masks),
## bottom-up or top-down. Returns null for anything else.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 54 or bytes[0] != 0x42 or bytes[1] != 0x4d: return null
	var offset := bytes.decode_u32(10)
	var header := bytes.decode_u32(14)
	var width := bytes.decode_s32(18)
	var height := bytes.decode_s32(22)
	var bits := bytes.decode_u16(28)
	var compression := bytes.decode_u32(30)
	if width < 1 or width > 4096 or height == 0 or absi(height) > 4096: return null
	if bits != 24 and bits != 32: return null
	var shifts := [16, 8, 0]
	if compression == 3:
		var masks_at := 14 + header if header >= 52 else 54
		if bits != 32 or masks_at + 12 > bytes.size(): return null
		for channel in 3:
			var mask := bytes.decode_u32(masks_at + channel * 4)
			var shift := -1
			for candidate in [0, 8, 16, 24]:
				if mask == 0xff << candidate: shift = candidate
			if shift < 0: return null
			shifts[channel] = shift
	elif compression != 0: return null
	var rows := absi(height)
	var step := bits / 8
	var stride := (width * step + 3) & ~3
	if offset + stride * rows > bytes.size(): return null
	var data := PackedByteArray()
	data.resize(width * rows * 3)
	for row in rows:
		var source := offset + stride * (rows - 1 - row if height > 0 else row)
		var target := row * width * 3
		for x in width:
			var at := source + x * step
			var pixel := bytes.decode_u32(at) if step == 4 else bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16
			for channel in 3: data[target + x * 3 + channel] = (pixel >> shifts[channel]) & 0xff
	return Image.create_from_data(width, rows, false, Image.FORMAT_RGB8, data)
