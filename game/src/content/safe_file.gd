class_name ELSafeFile
extends RefCounted
## Replaces a save or settings file only once its new contents are on disk.
## The data goes to a temporary file next to it, which is flushed, checked
## for write errors and read back; only a complete copy is renamed over the
## old file. A full disk, a quota or a failed write therefore leaves the
## previous file as it was, and the caller is told the write failed.

## Tests set this to cut every write short after this many bytes, as a full
## disk would. Negative: writes are not cut.
static var test_write_limit := -1

static func write_text(path: String, text: String) -> bool:
	return write_bytes(path, text.to_utf8_buffer())

static func write_bytes(path: String, data: PackedByteArray) -> bool:
	var target := ProjectSettings.globalize_path(path)
	var temporary := "%s.%d-%d.tmp" % [target, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	var stored := data if test_write_limit < 0 or data.size() <= test_write_limit else data.slice(0, test_write_limit)
	var ok := file.store_buffer(stored)
	file.flush()
	ok = ok and file.get_error() == OK
	file.close()
	# Some failures (a quota, a full disk) only show as a short file.
	ok = ok and FileAccess.get_file_as_bytes(temporary) == data
	if not ok or DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true
