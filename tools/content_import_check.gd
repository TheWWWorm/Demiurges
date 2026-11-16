extends SceneTree
## Headless check of the importers that write the player's files: the GOG
## installer reader (ELInnoSetup), the data pack import (ELContentImport)
## and the custom map archive import (ELCustomMaps.import_zip).
##
## - No file name of any format may write outside the import's folder
##   (an installer entry "{app}\resources\..\..\escaped.smp" did), and a
##   bad name stops the import before anything is written.
## - A staged import replaces the previous copy only once its archives open:
##   empty archives of the right names keep the previous copy.
## - A map archive that fails partway (a full disk, simulated with
##   ELSafeFile.test_write_limit) leaves the previous copy of the map whole,
##   and a successful one replaces it whole.
## - Where this computer has the games (user://profiles.json), each
##   installed folder passes the same check an import must.
##
##   godot --headless --path game --script ../tools/content_import_check.gd -- [--installer=<GOG setup exe> ...]
##
## Works in user://content_import_check/ and user://maps/ (one folder of its
## own), removed afterwards.

const FOLDER := "user://content_import_check"
const MAP_NAME := "content_import_check_map"

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var work := ProjectSettings.globalize_path(FOLDER)
	ELContentLibrary.remove_tree(work)
	DirAccess.make_dir_recursive_absolute(work)
	_paths()
	_installer_names(work)
	await _packs(work)
	_map_archives(work)
	_installed_games()
	ELContentLibrary.remove_tree(work)
	print("CONTENT IMPORT: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

# -- names ---------------------------------------------------------------------

func _paths() -> void:
	for good: String in ["resources/textures.res", "maps/custom/ctt/hero.scp", "campaigns/white.cpg", "Name..smp"]:
		check(ELContentLibrary.safe_relative(good) == good, "%s is a safe name" % good)
	for bad: String in ["", "/etc/passwd", "resources/../../escaped.smp", "../x.res", "resources/./x.res", "resources//x.res",
			"c:/windows/x.res", "c:x.res", "resources\\..\\x.res", "resources/x.res" + String.chr(1) + ".txt","resources/...", "resources/.. /x",
			"resources/x. ", "resources/con.res", "resources/nul", "maps/a\tb.smp", "resources/x?.res", "resources/x:stream"]:
		check(ELContentLibrary.safe_relative(bad).is_empty(), "%s is refused" % bad.c_escape())
	var base := ProjectSettings.globalize_path(FOLDER)
	check(ELContentLibrary.inside(base, "resources/x.res") == base.path_join("resources/x.res"), "a safe name lands inside its folder")
	check(ELContentLibrary.inside(base, "resources/../../x.res").is_empty(), "a name leading out of its folder has no place")

# -- installer -----------------------------------------------------------------

## A file entry as the installer's setup header stores one: ten strings
## (the destination second), the version range, then the data entry index
## and the rest of the entry.
static func _entry(destination: String, location: int) -> PackedByteArray:
	var out := PackedByteArray()
	for k in 10:
		var text := destination.to_utf16_buffer() if k == 1 else PackedByteArray()
		var size := PackedByteArray()
		size.resize(4)
		size.encode_u32(0, text.size())
		out.append_array(size)
		out.append_array(text)
	var tail := PackedByteArray()
	tail.resize(20 + 23)
	tail.encode_u32(20, location)
	out.append_array(tail)
	return out

static func _setup_header(destinations: Array) -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(16)
	for i in destinations.size(): header.append_array(_entry(destinations[i], i))
	header.resize(header.size() + 64)
	return header

func _installer_names(work: String) -> void:
	var game := ["{app}\\Resources\\figures.res", "{app}\\Resources\\crfigures.res", "{app}\\Resources\\textures.res",
		"{app}\\Resources\\regs.res", "{app}\\Resources\\text.res", "{app}\\Campaigns\\White.cpg", "{app}\\Etherlords2.exe"]
	var setup := ELInnoSetup.new()
	for i in game.size(): setup.chunks.append({"flags": 0, "size": 1})
	setup._find_files(_setup_header(game))
	var names := {}
	for entry: Dictionary in setup.files: names[entry.name] = true
	check(setup.unsafe.is_empty() and names.has("resources/textures.res") and names.has("campaigns/white.cpg") and not names.has("etherlords2.exe"),
		"an installer's game files are found, its program left out")
	check(ELContentLibrary.detect_names(names) == "el2", "and recognised as the second game")

	var escaping := game.duplicate()
	escaping.insert(3, "{app}\\resources\\..\\..\\escaped.smp")
	setup = ELInnoSetup.new()
	for i in escaping.size(): setup.chunks.append({"flags": 0, "size": 1})
	setup._find_files(_setup_header(escaping))
	check(setup.unsafe == "resources/../../escaped.smp" and setup.files.is_empty(), "an installer entry leading out of the game folder is caught, and no file is kept")
	for bad: String in ["{app}\\maps\\C:\\escaped.smp", "{app}\\maps\\...", "{app}\\maps\\custom\\con.smp"]:
		setup = ELInnoSetup.new()
		var list := game.duplicate()
		list.append(bad)
		for i in list.size(): setup.chunks.append({"flags": 0, "size": 1})
		setup._find_files(_setup_header(list))
		check(not setup.unsafe.is_empty() and setup.files.is_empty(), "an installer entry %s is caught" % bad.c_escape())
	# Even a file list made some other way is checked as it is written.
	setup = ELInnoSetup.new()
	setup._dest = work.path_join("installer")
	check(ELContentLibrary.inside(setup._dest, "resources/../../escaped.smp").is_empty(), "the writer finds no place for such a name")

# -- data packs ----------------------------------------------------------------

## A Nival archive (the second game's layout) holding one file.
static func _archive(content := "data") -> PackedByteArray:
	var payload := content.to_ascii_buffer()
	var out := PackedByteArray()
	out.resize(16)
	out.encode_u32(0, 0x019ce23d)
	out.encode_u32(4, 1)
	out.encode_u32(8, 16 + payload.size())
	out.encode_u32(12, 1)
	out.append_array(payload)
	var entry := PackedByteArray()
	entry.resize(18)
	entry.encode_u32(4, payload.size())
	entry.encode_u16(8, 1)
	entry.encode_u32(10, 16)
	entry.encode_u32(14, 0)
	out.append_array(entry)
	out.append_array("a".to_ascii_buffer())
	return out

static func _pack(files: Dictionary) -> PackedByteArray:
	var index := {}
	var payload := PackedByteArray()
	for name: String in files:
		index[name] = {"offset": payload.size(), "size": files[name].size()}
		payload.append_array(files[name])
	var json := JSON.stringify(index).to_utf8_buffer()
	var out := ELContentLibrary.PACK_MAGIC.to_ascii_buffer()
	var size := PackedByteArray()
	size.resize(4)
	size.encode_u32(0, json.size())
	out.append_array(size)
	out.append_array(json)
	out.append_array(payload)
	return out

static func _game(empty := false) -> Dictionary:
	var files := {}
	for path: String in ELContentLibrary.REQUIRED: files[path] = PackedByteArray() if empty else _archive(path)
	files["campaigns/white.cpg"] = "campaign".to_ascii_buffer()
	return files

## Imports `bytes` as a picked file: [edition or "", error or ""].
func _import(work: String, bytes: PackedByteArray) -> Array:
	var path := work.path_join("picked.elpack")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var importer := ELContentImport.new()
	importer.content_root = work.path_join("content")
	root_node().add_child(importer)
	var result := ["", ""]
	importer.completed.connect(func(edition: String, _folder: String): result[0] = edition)
	importer.failed.connect(func(message: String): result[1] = message)
	await importer.import_file(path)
	importer.queue_free()
	return result

func root_node() -> Node:
	return root

func _packs(work: String) -> void:
	var result: Array = await _import(work, _pack(_game()))
	var target := work.path_join("content/el2")
	check(result[0] == "el2" and FileAccess.file_exists(target.path_join("resources/textures.res")), "a sound data pack is imported")
	var kept := FileAccess.get_file_as_bytes(target.path_join("resources/textures.res"))

	result = await _import(work, _pack(_game(true)))
	check(result[0].is_empty() and not result[1].is_empty(), "a data pack of empty archives is refused (%s)" % result[1])
	check(FileAccess.get_file_as_bytes(target.path_join("resources/textures.res")) == kept, "and the previous copy is kept")

	var damaged := _game()
	damaged["resources/regs.res"] = "not an archive at all".to_ascii_buffer()
	result = await _import(work, _pack(damaged))
	check(result[0].is_empty() and FileAccess.get_file_as_bytes(target.path_join("resources/textures.res")) == kept, "a data pack with a damaged archive is refused, the previous copy kept")

	var escaping := _game()
	escaping["resources/../../escaped.res"] = _archive()
	result = await _import(work, _pack(escaping))
	check(result[0].is_empty() and not FileAccess.file_exists(work.path_join("escaped.res")) and not FileAccess.file_exists(work.get_base_dir().path_join("escaped.res")),
		"a data pack naming a file outside the game folder is refused, and nothing escapes")
	var leftovers := Array(DirAccess.get_directories_at(work.path_join("content"))).filter(func(name: String) -> bool: return name.begins_with("import-"))
	check(leftovers.is_empty(), "refused imports leave no staging folder behind")

# -- custom map archives ---------------------------------------------------------

static func _zip(path: String, files: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(path)
	for name: String in files:
		packer.start_file(name)
		packer.write_file(files[name])
		packer.close_file()
	packer.close()

static func _tree(folder: String, relative := "") -> Dictionary:
	var result := {}
	var here := folder.path_join(relative) if not relative.is_empty() else folder
	if not DirAccess.dir_exists_absolute(here): return result
	for file in DirAccess.get_files_at(here):
		var key := relative.path_join(file) if not relative.is_empty() else file
		result[key] = FileAccess.get_file_as_bytes(here.path_join(file))
	for sub in DirAccess.get_directories_at(here): result.merge(_tree(folder, relative.path_join(sub) if not relative.is_empty() else sub))
	return result

func _map_archives(work: String) -> void:
	var folder := ProjectSettings.globalize_path(ELCustomMaps.USER_FOLDER).path_join(MAP_NAME)
	ELContentLibrary.remove_tree(folder)
	var archive := work.path_join(MAP_NAME + ".zip")
	var first := {"Map.smp": "<map one/>".to_utf8_buffer(), "Map.scp": "-- one".to_utf8_buffer(), "Old.scp": "-- old script".to_utf8_buffer()}
	_zip(archive, first)
	var result := ELCustomMaps.import_zip(archive)
	check(result.error.is_empty() and _tree(folder) == first, "a map archive is imported")

	# The second version, with its script cut short by a full disk.
	var second := {"Map.smp": "<map two, somewhat longer/>".to_utf8_buffer(), "Map.scp": "-- two, a longer script than before".to_utf8_buffer()}
	_zip(archive, second)
	ELSafeFile.test_write_limit = 10
	result = ELCustomMaps.import_zip(archive)
	ELSafeFile.test_write_limit = -1
	check(not result.error.is_empty() and result.maps.is_empty(), "a map archive that cannot be written fails (%s)" % result.error)
	check(_tree(folder) == first, "and the previous copy of the map is whole, its scenario and scripts as they were")

	var traversal := second.duplicate()
	traversal["../escaped.scp"] = "-- out".to_utf8_buffer()
	traversal["sub/../../escaped2.scp"] = "-- out".to_utf8_buffer()
	_zip(archive, traversal)
	result = ELCustomMaps.import_zip(archive)
	var maps := ProjectSettings.globalize_path(ELCustomMaps.USER_FOLDER)
	check(result.error.is_empty() and _tree(folder) == second, "the second version replaces the first whole (its dropped script goes)")
	check(not FileAccess.file_exists(maps.path_join("escaped.scp")) and not FileAccess.file_exists(maps.path_join("escaped2.scp")) and not FileAccess.file_exists(maps.get_base_dir().path_join("escaped.scp")),
		"names leading out of the map's folder are not written")
	_zip(archive, {"Map.smp": PackedByteArray(), "Map.scp": "-- empty map".to_utf8_buffer()})
	result = ELCustomMaps.import_zip(archive)
	check(not result.error.is_empty() and _tree(folder) == second, "an archive whose map file is empty is refused, the previous copy kept")
	var staging := ProjectSettings.globalize_path(ELCustomMaps.STAGING_FOLDER)
	check(not DirAccess.dir_exists_absolute(staging) or DirAccess.get_directories_at(staging).is_empty(), "no staged copy is left behind")
	ELContentLibrary.remove_tree(folder)

# -- the installed games -----------------------------------------------------------

func _installed_games() -> void:
	var folders := ELContentLibrary.linked_folders()
	var checked := 0
	for edition: String in folders:
		var folder: String = folders[edition]
		if ELContentLibrary.detect(folder) != edition: continue
		checked += 1
		var problem := ELContentLibrary.validate(folder, edition)
		check(problem.is_empty(), "the installed %s passes the import check%s" % [ELContentLibrary.title(edition), "" if problem.is_empty() else " (%s)" % problem])
	if checked == 0: print("SKIP: no installed game here; the real folders are not checked")
	# GOG installers given with --installer=<setup_etherlords*.exe>: every
	# file they hold passes the name check.
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--installer="): continue
		var setup := ELInnoSetup.open(arg.get_slice("=", 1))
		check(setup.error.is_empty() and setup.unsafe.is_empty() and setup.files.size() > 100,
			"the installer %s is read: %s, %d files%s" % [arg.get_file(), setup.edition, setup.files.size(), "" if setup.error.is_empty() else " (%s)" % setup.error])
