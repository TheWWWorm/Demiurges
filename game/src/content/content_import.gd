class_name ELContentImport
extends Node
## Copies the player's GOG installer or data pack (made with
## tools/prepare_game_data.py) into app-private storage. The installer is read,
## never run. A new import is staged in its own folder and replaces the
## edition's previous files only once it is complete and recognised, so a
## cancelled or failed import keeps the old files.
##
## Adapted from the Cursed Lands engine (TheWWWorm, PrivateDataImport, Apache-2.0).
signal progress(text: String)
signal completed(edition: String, folder: String)
signal failed(message: String)
var cancelled := false
var busy := false
var _installer: ELInnoSetup

func _exit_tree() -> void:
	cancelled = true
	if _installer:
		_installer.cancel()
		_installer.wait_to_finish()
		_installer = null


func import_file(path: String) -> void:
	if busy: return
	busy = true
	cancelled = false
	var base := OS.get_user_data_dir().path_join("content")
	var stage := base.path_join("import-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(stage)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_finish(stage, "The selected file could not be opened.")
		return
	var signature := file.get_buffer(8).get_string_from_ascii()
	file.seek(0)
	var error := ""
	if signature == ELContentLibrary.PACK_MAGIC:
		error = await _pack(file, stage)
	elif signature.begins_with("MZ"):
		error = await _setup(file, stage)
	else:
		error = "Choose the GOG installer (.exe) or a data pack (.elpack)."
	file.close()
	if cancelled: error = "Import cancelled."
	_finish(stage, error)


func _setup(file: FileAccess, stage: String) -> String:
	# The picked document may not be a seekable local file, so it is copied
	# first and removed after unpacking.
	var installer := stage.path_join("installer.exe")
	var output := FileAccess.open(installer, FileAccess.WRITE)
	if output == null: return "Could not create the import folder."
	var error := ""
	var total := maxi(file.get_length(), 1)
	while file.get_position() < file.get_length() and not cancelled:
		var bytes := file.get_buffer(mini(4194304, file.get_length() - file.get_position()))
		if bytes.is_empty():
			error = "Could not read the selected installer."
			break
		output.store_buffer(bytes)
		if output.get_error() != OK:
			error = "Not enough space to copy the installer."
			break
		progress.emit("Copying the installer: %d%%" % (file.get_position() * 100 / total))
		await get_tree().process_frame
	output.close()
	if cancelled or not error.is_empty():
		DirAccess.remove_absolute(installer)
		return error
	var setup := ELInnoSetup.open(installer)
	error = setup.error
	if error.is_empty():
		_installer = setup
		setup.extract(stage)
		while not setup.finished():
			if cancelled: setup.cancel()
			progress.emit("Unpacking the installer: %d%%" % int(setup.progress() * 100.0))
			await get_tree().process_frame
		error = setup.failure()
		_installer = null
	DirAccess.remove_absolute(installer)
	return error


func _pack(file: FileAccess, stage: String) -> String:
	file.seek(8)
	var header_size := file.get_32()
	if header_size < 2 or header_size > 4194304 or header_size + 12 > file.get_length():
		return "Invalid data pack header."
	var index: Variant = JSON.parse_string(file.get_buffer(header_size).get_string_from_utf8())
	if not index is Dictionary or index.is_empty() or index.size() > 20000:
		return "Invalid data pack index."
	var payload := header_size + 12
	# Validate every path and range before creating any file.
	for key: Variant in index:
		if not key is String or not index[key] is Dictionary:
			return "Invalid data pack entry."
		var name: String = key
		var parts := name.split("/")
		var entry: Dictionary = index[key]
		var offset := int(entry.get("offset", -1))
		var length := int(entry.get("size", -1))
		if name.is_empty() or name.is_absolute_path() or name.contains("\\") or name.contains(":") or name != name.to_lower() \
				or ".." in parts or "" in parts or "." in parts or not ELContentLibrary.wanted(name):
			return "Invalid data pack path."
		if offset < 0 or length < 0 or length > 2147483648 or payload + offset + length > file.get_length():
			return "Invalid data pack range."
	for key: String in index:
		if cancelled: return "Import cancelled."
		progress.emit("Importing %s" % key)
		var dest := stage.path_join(key)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var output := FileAccess.open(dest, FileAccess.WRITE)
		if output == null: return "Could not write the imported files."
		file.seek(payload + int(index[key].offset))
		var left := int(index[key].size)
		while left > 0:
			if cancelled:
				output.close()
				return "Import cancelled."
			var bytes := file.get_buffer(mini(left, 4194304))
			if bytes.is_empty(): return "The data pack is incomplete."
			output.store_buffer(bytes)
			if output.get_error() != OK: return "Not enough space to import the game files."
			left -= bytes.size()
			await get_tree().process_frame
		output.close()
	return ""


func _finish(stage: String, error: String) -> void:
	var edition := ""
	if error.is_empty():
		edition = ELContentLibrary.detect(stage)
		if edition.is_empty(): error = "These files are not a complete copy of Etherlords or Etherlords II."
	if error.is_empty():
		var target := ELContentLibrary.managed_root(edition)
		var previous := target + "-previous"
		ELContentLibrary.remove_tree(previous)
		if DirAccess.dir_exists_absolute(target) and DirAccess.rename_absolute(target, previous) != OK:
			error = "Could not replace the previous game files."
		elif DirAccess.rename_absolute(stage, target) != OK:
			if DirAccess.dir_exists_absolute(previous): DirAccess.rename_absolute(previous, target)
			error = "Could not store the imported game files."
		else:
			ELContentLibrary.remove_tree(previous)
			busy = false
			completed.emit(edition, target)
			return
	busy = false
	ELContentLibrary.remove_tree(stage)
	failed.emit(error)
