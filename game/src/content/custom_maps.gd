class_name ELCustomMaps
extends RefCounted
## Etherlords II custom maps made with the map editor. A map is a set of files
## sharing one name:
##   .sbm  the map as the game plays it (binary, the layout of a shipped .ebm)
##   .smp  the editor's scenario (XML, the layout of a shipped .map), which
##         the remake reads for the map itself
##   .scp  plain-text Lua scripts: the main one (<name>.scp) and the battle
##         scripts creatures name in their Script= attribute, compiled when
##         loaded
##   .bm1  the 130×130 minimap; .bm2/.bmp/.png pictures; .mp3 music
## The game keeps every custom map in one folder, Maps/Custom, and scripts
## name their files from it (Script="Maps\Custom\CtT\Hero.scp"). The remake
## looks in the installation's Maps/Custom and in its own maps folder
## (user://maps), where each folder is a Maps/Custom of its own (a folder
## holding Maps/Custom, as a map's repository does, counts from there). Files
## keep their sub-folders. All appear to the game under Maps/Custom/.
## A map whose .smp and .sbm names differ (an editor copy beside the release)
## pairs them when its folder has one of each; a map with only the .sbm plays
## from the scenario ELBinaryMap reads out of it.

const FOLDER := "Maps/Custom/"
const KEY_PREFIX := "maps/custom/"
const USER_FOLDER := "user://maps"
## Scenarios read from map files that came without one.
const CACHE_FOLDER := "user://maps-cache"
## The files a custom map may bring. An import copies nothing else.
const EXTENSIONS := ["smp", "sbm", "scp", "bm1", "bm2", "bmp", "png", "jpg", "mp3", "ogg", "txt"]
## Custom files that stand in for the shipped extensions the loaders read.
const ALIASES := {"smp": "map", "sbm": "ebm"}
## Picture shown in the mission list, best first: the author's art, the
## editor's preview, then the large overview.
const PICTURES := ["png", "jpg", "bmp", "bm2"]
## The files whose contents make the map (its saves check them).
const CONTENT := ["smp", "sbm", "scp"]
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_IMPORT_BYTES := 256 * 1024 * 1024
const MAX_FILES := 1024
const MAX_DEPTH := 4

## Folders the next index() also reads as Maps/Custom roots (checks).
static var extra_roots: Array[String] = []

## Adds custom map files to a profile's loose-file index ({lowercase key:
## absolute path}): the installation's Maps/Custom (again, for maps saved
## after the game started), the remake's own maps, and the alias keys.
## Earlier roots win over later files of the same name. Returns the keys it
## added.
static func index(files: Dictionary, root: String) -> Array[String]:
	var added: Array[String] = []
	var roots: Array[String] = []
	var installed := _child(_child(root, "maps"), "custom")
	if not installed.is_empty(): roots.append(installed)
	var folder := ProjectSettings.globalize_path(USER_FOLDER)
	var candidates: Array[String] = []
	if DirAccess.dir_exists_absolute(folder):
		var folders := Array(DirAccess.get_directories_at(folder))
		folders.sort()
		for sub: String in folders: candidates.append(folder.path_join(sub))
	candidates.append_array(extra_roots)
	for candidate: String in candidates: roots.append(map_root(candidate))
	# Map files copied straight into the maps folder (not in a folder of their own).
	if DirAccess.dir_exists_absolute(folder): roots.append(folder)
	for map_folder: String in roots:
		var found: Array[String] = []
		_collect(map_folder, "", 0, found, map_folder == folder)
		for relative: String in found:
			var key := ELArchive.key(FOLDER + relative)
			if files.has(key): continue
			files[key] = map_folder.path_join(relative)
			added.append(key)
		_pair(files, map_folder, added)
	_read_binary_maps(files, added)
	for key: String in files.keys():
		if not key.begins_with(KEY_PREFIX): continue
		var extension := key.get_extension()
		if not ALIASES.has(extension): continue
		var alias: String = key.get_basename() + "." + ALIASES[extension]
		if files.has(alias): continue
		files[alias] = files[key]
		added.append(alias)
	return added

## The folder to read as Maps/Custom: the folder itself, or its Maps/Custom.
static func map_root(folder: String) -> String:
	var nested := _child(_child(folder, "maps"), "custom")
	return nested if not nested.is_empty() else folder

static func _child(folder: String, name: String) -> String:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): return ""
	for sub: String in DirAccess.get_directories_at(folder):
		if sub.to_lower() == name: return folder.path_join(sub)
	return ""

static func _collect(folder: String, relative: String, depth: int, found: Array[String], top_only := false) -> void:
	if depth > MAX_DEPTH or found.size() >= MAX_FILES: return
	var here := folder.path_join(relative) if not relative.is_empty() else folder
	for file: String in DirAccess.get_files_at(here):
		if file.get_extension().to_lower() in EXTENSIONS: found.append(relative.path_join(file) if not relative.is_empty() else file)
	if top_only: return
	for sub: String in DirAccess.get_directories_at(here):
		if sub.begins_with("."): continue
		_collect(folder, relative.path_join(sub) if not relative.is_empty() else sub, depth + 1, found)

## A folder with one scenario and one map file of different names: the map
## file's name is the map's (its main script carries it too), the scenario
## is read for it.
static func _pair(files: Dictionary, map_folder: String, added: Array[String]) -> void:
	var scenarios: Array[String] = []
	var maps: Array[String] = []
	for file: String in DirAccess.get_files_at(map_folder):
		match file.get_extension().to_lower():
			"smp": scenarios.append(file.get_basename())
			"sbm": maps.append(file.get_basename())
	var lone_scenarios := scenarios.filter(func(name: String): return not maps.any(func(other: String): return other.to_lower() == name.to_lower()))
	var lone_maps := maps.filter(func(name: String): return not scenarios.any(func(other: String): return other.to_lower() == name.to_lower()))
	if lone_scenarios.size() != 1 or lone_maps.size() != 1: return
	var key := ELArchive.key(FOLDER + str(lone_maps[0]) + ".smp")
	if files.has(key): return
	files[key] = map_folder.path_join(str(lone_scenarios[0]) + ".smp")
	added.append(key)
	# The editor copy is not a map of its own.
	var own := ELArchive.key(FOLDER + str(lone_scenarios[0]) + ".smp")
	if files.get(own, "") == files[key] and added.has(own):
		files.erase(own)
		added.erase(own)

## A map with only its map file (.sbm) plays from the scenario read out of
## it (ELBinaryMap), kept in CACHE_FOLDER under the file's SHA-256 so it is
## rebuilt only when the map changes. A map file that cannot be read stays
## listed but unplayable.
static func _read_binary_maps(files: Dictionary, added: Array[String]) -> void:
	for key: String in files.keys():
		if not key.begins_with(KEY_PREFIX) or key.count("/") != 2 or key.get_extension() != "sbm": continue
		var scenario := key.get_basename() + ".smp"
		if files.has(scenario): continue
		var path := scenario_from_binary(String(files[key]))
		if path.is_empty(): continue
		files[scenario] = path
		added.append(scenario)

## The cached scenario file built from a binary map, or "" when it is unreadable.
static func scenario_from_binary(source: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES: return ""
	var folder := ProjectSettings.globalize_path(CACHE_FOLDER)
	var hash := FileAccess.get_sha256(source)
	var path := folder.path_join("%s-%d.smp" % [hash, ELBinaryMap.VERSION])
	if FileAccess.file_exists(path): return path
	var result := ELBinaryMap.scenario(bytes)
	if String(result.text).is_empty():
		push_warning("Custom map %s: %s" % [source.get_file(), result.error])
		return ""
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(result.text)
	file.close()
	return path

## Whether a map id names a custom map ("Maps/Custom/<name>").
static func is_custom(id: String) -> bool:
	return id.begins_with(FOLDER)

## A saved or requested map id of a custom map: one file name under
## Maps/Custom/, no folders or control characters.
static func valid_id(value: Variant) -> bool:
	if not value is String or not is_custom(value): return false
	var name := String(value).trim_prefix(FOLDER)
	return not name.is_empty() and name.length() <= 160 and clean_name(name) == name

## A file name made safe to store: path separators, reserved and control
## characters removed. (Names may end in a dot before the extension, as
## "Name..smp" does.)
static func clean_name(name: String) -> String:
	var out := ""
	for i in name.length():
		var c := name.unicode_at(i)
		if c < 32 or "/\\:*?\"<>|".contains(String.chr(c)): continue
		out += String.chr(c)
	out = out.strip_edges()
	if out in [".", ".."]: return ""
	return out.substr(0, 160)

## The custom maps a profile has, as Maps/Custom/<name> ids with the real
## file-name case, sorted: every .sbm or .smp at the top of Maps/Custom.
static func ids(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	for key: String in profile.files_under(FOLDER):
		if key.count("/") != 2 or not key.get_extension() in ["sbm", "smp"]: continue
		var base := key.get_basename()
		if seen.has(base): continue
		seen[base] = true
		# The map file names the map (a paired scenario has another name).
		var named := profile.file(base + ".sbm")
		if named.is_empty(): named = profile.file(key)
		result.append(FOLDER + named.get_file().get_basename())
	result.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
	return result

## Whether the remake can play the map: it reads the scenario (.smp).
static func playable(profile: ELProfile, id: String) -> bool:
	return not profile.file(id + ".smp").is_empty()

## SHA-256 over the map's scenario, map file and every script under
## Maps/Custom (names and contents), so a save notices any change. "" when
## the map is missing.
static func content_hash(profile: ELProfile, id: String) -> String:
	if profile.file(id + ".smp").is_empty(): return ""
	var keys: Array[String] = []
	var base := ELArchive.key(id)
	for key: String in profile.files_under(FOLDER):
		var extension := key.get_extension()
		if not extension in CONTENT: continue
		# Scripts may sit in sub-folders and serve several maps; the scenario
		# and map file are the map's own.
		if extension == "scp" or key.get_basename() == base: keys.append(key)
	keys.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for key: String in keys:
		context.update(key.to_utf8_buffer())
		context.update(FileAccess.get_file_as_bytes(profile.file(key)))
	return context.finish().hex_encode()

## The map's picture for the mission list, or null.
static func picture(profile: ELProfile, id: String) -> Texture2D:
	for extension: String in PICTURES:
		var path := profile.file(id + "." + extension)
		if path.is_empty(): continue
		var bytes := FileAccess.get_file_as_bytes(path)
		var image: Image
		if extension in ["bmp", "bm2"]:
			image = ELMinimapPicture.decode(bytes)
		else:
			image = Image.new()
			var loaded := image.load_png_from_buffer(bytes) if extension == "png" else image.load_jpg_from_buffer(bytes)
			if loaded != OK: image = null
		if image == null or image.is_empty(): continue
		if image.get_width() > 1024 or image.get_height() > 1024:
			var scale := 1024.0 / maxf(image.get_width(), image.get_height())
			image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		return ImageTexture.create_from_image(image)
	return null

## The file of the map's own music (<name>.mp3 or .ogg), or "".
static func music_path(profile: ELProfile, id: String) -> String:
	var path := profile.file(id + ".mp3")
	return path if not path.is_empty() else profile.file(id + ".ogg")

## The map's own music, looping, or null.
static func music(profile: ELProfile, id: String) -> AudioStream:
	var path := profile.file(id + ".mp3")
	if not path.is_empty():
		var stream := AudioStreamMP3.load_from_file(path)
		if stream != null:
			stream.loop = true
			return stream
	path = profile.file(id + ".ogg")
	if not path.is_empty():
		var ogg := AudioStreamOggVorbis.load_from_file(path)
		if ogg != null:
			ogg.loop = true
			return ogg
	return null

## Copies a custom map archive (.zip) into user://maps/<archive name>/. The
## archive's map folder is the shallowest folder holding a scenario or map
## file; only the custom-map file types under it are copied, keeping
## sub-folders, each name cleaned. Returns {maps: [ids], error: ""}; nothing
## is written when the archive holds no map.
static func import_zip(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK: return {"maps": [], "error": "The archive could not be opened."}
	var entries := reader.get_files()
	if entries.size() > MAX_FILES * 4:
		reader.close()
		return {"maps": [], "error": "The archive holds too many files."}
	var root := ""
	var root_depth := 1 << 30
	for entry: String in entries:
		var normal := entry.replace("\\", "/")
		if not normal.get_extension().to_lower() in ["smp", "sbm"]: continue
		var directory := normal.get_base_dir()
		var depth := 0 if directory.is_empty() else directory.count("/") + 1
		if depth < root_depth:
			root_depth = depth
			root = directory
	if root_depth == 1 << 30:
		reader.close()
		return {"maps": [], "error": "The archive has no custom map: it needs a scenario (.smp) or map file (.sbm)."}
	var chosen: Dictionary = {}
	var names: Array[String] = []
	for entry: String in entries:
		var normal := entry.replace("\\", "/")
		if normal.ends_with("/") or not normal.get_extension().to_lower() in EXTENSIONS: continue
		if not root.is_empty() and not normal.begins_with(root + "/"): continue
		var parts: Array[String] = []
		for part: String in normal.trim_prefix(root + "/" if not root.is_empty() else "").split("/", false):
			var cleaned := clean_name(part)
			if cleaned.is_empty():
				parts.clear()
				break
			parts.append(cleaned)
		if parts.is_empty() or parts.size() > MAX_DEPTH + 1: continue
		var relative := "/".join(parts)
		if chosen.has(relative.to_lower()): continue
		chosen[relative.to_lower()] = [entry, relative]
		if parts.size() == 1 and relative.get_extension().to_lower() in ["smp", "sbm"]: names.append(relative)
	if chosen.size() > MAX_FILES:
		reader.close()
		return {"maps": [], "error": "The archive holds too many files."}
	var name := clean_name(path.get_file().get_basename()).trim_suffix(".").strip_edges()
	if name.is_empty(): name = names[0].get_basename().trim_suffix(".")
	var folder := ProjectSettings.globalize_path(USER_FOLDER).path_join(name)
	var total := 0
	for key: String in chosen:
		var data := reader.read_file(chosen[key][0])
		if data.size() > MAX_FILE_BYTES: continue
		total += data.size()
		if total > MAX_IMPORT_BYTES: break
		var target := folder.path_join(chosen[key][1])
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			reader.close()
			return {"maps": [], "error": "The maps folder could not be created."}
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return {"maps": [], "error": "A map file could not be written."}
		file.store_buffer(data)
		file.close()
	reader.close()
	# The ids the index gives these files (pairs share the map file's name).
	var found: Dictionary = {}
	for file: String in names:
		var base := file.get_basename()
		var sbm := names.filter(func(other: String): return other.get_extension().to_lower() == "sbm")
		var smp := names.filter(func(other: String): return other.get_extension().to_lower() == "smp")
		if file.get_extension().to_lower() == "smp" and not names.any(func(other: String): return other.to_lower() == (base + ".sbm").to_lower()) and sbm.size() == 1 and smp.size() == 1:
			base = str(sbm[0]).get_basename()
		found[FOLDER + base] = true
	var result: Array[String] = []
	result.assign(found.keys())
	result.sort()
	return {"maps": result, "error": ""}

## The folder players can copy map files into, created when missing.
static func user_folder() -> String:
	var folder := ProjectSettings.globalize_path(USER_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	return folder
