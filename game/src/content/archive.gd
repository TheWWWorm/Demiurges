class_name ELArchive
extends RefCounted
## Nival RES containers. EI/EL1: 22-byte directory; EL2: 18-byte directory.
## File-backed archives seek to individual payloads; never load a whole resource pack.

var entries: Dictionary = {}
var error := ""
var _file: FileAccess
var _data: PackedByteArray
var _sources: Dictionary = {}

static func overlay(layers: Array[ELArchive]) -> ELArchive:
	var merged := ELArchive.new()
	for layer in layers:
		for entry: String in layer.entries:
			merged.entries[entry] = layer.entries[entry]
			merged._sources[entry] = layer
	return merged

static func open(path: String) -> ELArchive:
	var a := ELArchive.new()
	a._file = FileAccess.open(path, FileAccess.READ)
	if a._file == null:
		a.error = "Cannot read " + path
	else:
		a._parse()
	return a

static func from_bytes(bytes: PackedByteArray) -> ELArchive:
	var a := ELArchive.new()
	a._data = bytes
	a._parse()
	return a

static func is_archive(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 16 and bytes.decode_u32(0) in [0x019ce23c, 0x019ce23d]

func read(entry: String) -> PackedByteArray:
	if _sources.has(key(entry)):
		return _sources[key(entry)].read(entry)
	var bounds: Variant = entries.get(key(entry))
	return _range(bounds.x, bounds.y) if bounds != null else PackedByteArray()

func has(entry: String) -> bool:
	return entries.has(key(entry))

static func key(name: String) -> String:
	return name.replace("\\", "/").to_lower()

func _range(offset: int, size: int) -> PackedByteArray:
	if _file:
		_file.seek(offset)
		return _file.get_buffer(size)
	return _data.slice(offset, offset + size)

func _parse() -> void:
	var total := _file.get_length() if _file else _data.size()
	var header := _range(0, 16)
	if not is_archive(header):
		error = "Unsupported Nival archive header"
		return
	var count := header.decode_u32(4)
	var table_offset := header.decode_u32(8)
	var names_len := header.decode_u32(12)
	var stride := 22 if header.decode_u32(0) == 0x019ce23c else 18
	var names_base := count * stride
	if count > 1000000 or names_len > 16777216 or table_offset + names_base + names_len > total:
		error = "Invalid archive directory range"
		return
	var table := _range(table_offset, names_base + names_len)
	for i in count:
		var at := i * stride
		var size := table.decode_u32(at + 4)
		var offset := table.decode_u32(at + (8 if stride == 22 else 10))
		var length := table.decode_u16(at + (16 if stride == 22 else 8))
		var name_at := names_base + table.decode_u32(at + (18 if stride == 22 else 14))
		if offset + size > total or name_at + length > table.size():
			error = "Invalid archive entry range"
			entries.clear()
			return
		var name := key(ELText.ansi(table.slice(name_at, name_at + length)))
		if entries.has(name):
			error = "Duplicate archive entry: " + name
			entries.clear()
			return
		entries[name] = Vector2i(offset, size)
