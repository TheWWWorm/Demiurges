class_name ELProfile
extends RefCounted
## Each edition owns its archives and caches. Identical card/asset names never
## resolve through another edition's mounted content.
## Original FIG material table. Magic has its own full-bright override.
const FIGURE_MATERIALS := {17: "leather.mat", 18: "wood.mat", 19: "metal.mat", 20: "cloth.mat", 21: "skin.mat", 22: "stone.mat", 25: "metal.mat"}
var id := ""
var title := ""
var root := ""
var error := ""
var archives: Dictionary = {}
var tables: Dictionary = {}
var texts: Dictionary = {}
var _textures: Dictionary = {}
var _figure_diffuse: Dictionary = {}
var _files: Dictionary = {}
## Index keys ELCustomMaps added (imported maps and the .smp/.sbm aliases).
var _custom_keys: Array[String] = []
var asset_reads := 0
var model_resources: Dictionary = {}
var mounted_layers: Dictionary = {}
var _icons: Dictionary = {}
var sound_cache: Dictionary = {}
var sound_bytes := 0
var terrain_tiles: ELTileSet
var adventure_terrain_cache: Dictionary = {}
## Original cursor frames (ELCursors.load_set), decoded once per edition.
var cursor_cache: Dictionary = {}
var _prefetch: Array = []
var _prefetch_task := -1
## Interface button sounds by control name (ELUiSounds).
var button_sounds: Dictionary = {}

func mount(edition: String, folder: String) -> bool:
	error = ""
	archives.clear()
	tables.clear()
	texts.clear()
	_textures.clear()
	_figure_diffuse.clear()
	_icons.clear()
	sound_cache.clear()
	sound_bytes = 0
	terrain_tiles = null
	adventure_terrain_cache.clear()
	cursor_cache.clear()
	button_sounds.clear()
	_files.clear()
	model_resources.clear()
	mounted_layers.clear()
	asset_reads = 0
	if edition not in ["el1", "el2"]:
		error = "Unknown game edition: " + edition
		return false
	id = edition
	title = "Etherlords I" if edition == "el1" else "Etherlords II"
	root = folder.simplify_path()
	if not DirAccess.dir_exists_absolute(root):
		error = "Game folder does not exist: " + root
		return false
	_index(root, "")
	_custom_keys.clear()
	if edition == "el2": _custom_keys = ELCustomMaps.index(_files, root)
	for required in ["resources/figures.res", "resources/crfigures.res", "resources/textures.res", "resources/regs.res", "resources/text.res"]:
		if not _files.has(required):
			error = "Missing original content: " + required
			return false
	# Distinguish editions from their campaign structure, not an arbitrary filename.
	var marker := "campaigns/good.cpg" if id == "el1" else "campaigns/white.cpg"
	if not _files.has(marker):
		error = "This folder does not contain the selected game: " + title
		return false
	for name: String in ["figures", "crfigures", "textures", "regs", "text", "animdb", "sfx", "camera", "pfx", "fx", "scripts", "materials", "gp1tex"]:
		var paths: Array[String] = []
		# Numbered patch packs override the base; installation-root packs override
		# Resources. Resolution is per entry, so patches may contain only a few files.
		for directory: String in ["resources/", ""]:
			var patches: Array[String] = []
			var base := directory + name
			if _files.has(base + ".res"):
				paths.append(base + ".res")
			for candidate: String in _files:
				if candidate.begins_with(base) and candidate.ends_with(".res"):
					var suffix := candidate.trim_prefix(base).trim_suffix(".res")
					if not suffix.is_empty() and suffix.is_valid_int():
						patches.append(candidate)
			patches.sort_custom(func(a: String, b: String): return int(a.trim_prefix(base).trim_suffix(".res")) < int(b.trim_prefix(base).trim_suffix(".res")))
			paths.append_array(patches)
		var layers: Array[ELArchive] = []
		for path: String in paths:
			var arc := ELArchive.open(_files[path])
			if not arc.error.is_empty():
				if name in ["materials", "gp1tex"]: continue
				error = path + ": " + arc.error
				return false
			layers.append(arc)
		if not layers.is_empty():
			archives[name] = ELArchive.overlay(layers)
			mounted_layers[name] = paths
	var ta: ELArchive = archives.text
	for name: String in ta.entries:
		texts.merge(ELText.parse(ta.read(name)), true)
	return true

func table(name: String) -> Dictionary:
	if not tables.has(name):
		tables[name] = ELRegistry.parse(read("regs", name + ".reg"))
	return tables[name]

func read(archive: String, entry: String) -> PackedByteArray:
	var a: ELArchive = archives.get(archive)
	if a == null:
		return PackedByteArray()
	asset_reads += 1
	return a.read(entry)

## MAT begins with a length-prefixed name followed by four RGBA values
## (diffuse, ambient, specular, emissive) and the specular exponent.
func figure_diffuse(material_id: int) -> Color:
	if not archives.has("materials") or not FIGURE_MATERIALS.has(material_id): return Color.WHITE
	if not _figure_diffuse.has(material_id):
		var bytes := read("materials", FIGURE_MATERIALS[material_id])
		var color := Color.WHITE
		if bytes.size() >= 2:
			var offset := 2 + bytes.decode_u16(0)
			if offset + 68 <= bytes.size():
				var rgba := Color(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8), bytes.decode_float(offset + 12))
				if rgba.r >= 0.0 and rgba.r <= 1.0 and rgba.g >= 0.0 and rgba.g <= 1.0 and rgba.b >= 0.0 and rgba.b <= 1.0 and rgba.a >= 0.0 and rgba.a <= 1.0:
					color = rgba
		_figure_diffuse[material_id] = color
	return _figure_diffuse[material_id]

func figure(name: String) -> PackedByteArray:
	for archive in ["crfigures", "figures"]:
		var a: ELArchive = archives[archive]
		if a.has(name):
			return read(archive, name)
	return PackedByteArray()

func texture(name: String) -> Texture2D:
	var key := ELArchive.key(name)
	if _textures.has(key):
		return _textures[key]
	var source := _texture_source(key)
	var decoded := _texture_decode(source)
	if decoded.is_empty(): return null
	return _texture_store(key, decoded)

## Where a texture is stored: {file, bytes, soft}. Reads the archive, so it
## stays on the main thread.
func _texture_source(key: String) -> Dictionary:
	var file := key if key.ends_with(".mmp") else key + ".mmp"
	var bytes := read("textures", file)
	if bytes.is_empty() and file.begins_with("interface/black/progress_panel_"):
		bytes = read("gp1tex", file)
	# Tables name some textures without the Alpha or Alpha32 folder they are
	# stored in (the second game's map leaders, such as SmBlackFemale00 in
	# Heroes/Alpha): look there too, as the originals do.
	# Failing that, the closest stored variant: the full-size skin of a small
	# ("Sm") one, the first colour of a set ("_00") or a lord's main sheet.
	var soft := false
	if bytes.is_empty() and "/" in file:
		var folder := file.get_base_dir()
		var base := file.get_file().get_basename()
		var names := [base]
		if base.begins_with("sm"): names.append(base.substr(2))
		for stem: String in names.duplicate(): names.append_array([stem + "_00", stem + "main"])
		for stem: String in names:
			for sub in ["", "alpha", "alpha32"]:
				bytes = read("textures", folder.path_join(sub).path_join(stem + ".mmp"))
				soft = sub == "alpha32"
				if not bytes.is_empty(): break
			if not bytes.is_empty(): break
	return {"file": file, "bytes": bytes, "soft": soft}

## Decodes a texture's bytes into its image and mipmaps: {image, one_bit,
## authored, soft} or empty. Touches nothing shared, so worker threads may
## run it.
static func _texture_decode(source: Dictionary) -> Dictionary:
	var bytes: PackedByteArray = source.get("bytes", PackedByteArray())
	var img := ELTexture.decode(bytes)
	if img == null: return {}
	var one_bit_alpha := bytes.decode_u32(32) == 1
	var authored: Image
	if one_bit_alpha and String(source.file).begins_with("combatscenes/"):
		authored = ELTexture.authored_mask_mipmaps(bytes, img)
	if authored != null: img = authored
	else: img.generate_mipmaps()
	return {"image": img, "one_bit": one_bit_alpha, "authored": authored != null, "levels": bytes.decode_u32(12), "soft": bool(source.soft)}

func _texture_store(key: String, decoded: Dictionary) -> Texture2D:
	var tex := ImageTexture.create_from_image(decoded.image)
	if decoded.one_bit: tex.set_meta(ELTexture.ONE_BIT_ALPHA, true)
	if decoded.authored: tex.set_meta(ELTexture.AUTHORED_MASK_MIPS, int(decoded.levels))
	# Found in Alpha32: a soft-alpha skin (see ELModel.build).
	if decoded.soft: tex.set_meta("alpha32", true)
	_textures[key] = tex
	return tex

## Starts decoding `names` on worker threads (a loading screen's batch);
## poll finish_textures() each frame until it returns true.
func prefetch_textures(names: Array) -> void:
	_prefetch = []
	for name: Variant in names:
		var key := ELArchive.key(String(name))
		if key.is_empty() or _textures.has(key): continue
		var source := _texture_source(key)
		if PackedByteArray(source.bytes).is_empty(): continue
		source.key = key
		_prefetch.append(source)
	var jobs := _prefetch
	_prefetch_task = WorkerThreadPool.add_group_task(func(index: int): jobs[index].decoded = _texture_decode(jobs[index]), jobs.size()) if not jobs.is_empty() else -1

func finish_textures() -> bool:
	if _prefetch_task >= 0:
		if not WorkerThreadPool.is_group_task_completed(_prefetch_task): return false
		WorkerThreadPool.wait_for_group_task_completion(_prefetch_task)
		_prefetch_task = -1
	for job: Dictionary in _prefetch:
		if not _textures.has(job.key) and not Dictionary(job.get("decoded", {})).is_empty(): _texture_store(job.key, job.decoded)
	_prefetch = []
	return true

func text(key: String) -> String:
	return ELTextFixes.apply(id, key, String(texts.get(key, key))).strip_edges()

func card_icon(card: String) -> Texture2D:
	if _icons.has(card):
		return _icons[card]
	_icons[card] = icon_at(int(table("CombatSpells").get(card, {}).get("Icon", 0)))
	return _icons[card]

## A cell of the original spell icon sheets by its global icon index.
func icon_at(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture("Interface/Spells/icon_%02d" % (index / 25 + 1))
	# Original sheets store their 5 x 5 cells in column-major order.
	atlas.region = Rect2(((index % 25) / 5) * 50, (index % 5) * 50, 50, 50)
	atlas.filter_clip = true
	return atlas

func card_description(card: String) -> String:
	var row: Dictionary = table("CombatSpells").get(card, {})
	return text(String(row.get("ToolTip", card)))

func portrait(index: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture("Interface/heroes/photo_%02d" % (index / 6 + 1))
	atlas.region = Rect2(((index % 6) / 3) * 100, (index % 3) * 70, 100, 70)
	atlas.filter_clip = true
	return atlas

func file(relative: String) -> String:
	return _files.get(ELArchive.key(relative), "")

## Loose-file keys (lowercase, "/"-separated) under one folder of the original
## installation, sorted; e.g. files_under("Maps/").
func files_under(folder: String) -> PackedStringArray:
	var prefix := ELArchive.key(folder)
	var result := PackedStringArray()
	for key: String in _files:
		if key.begins_with(prefix): result.append(key)
	result.sort()
	return result

## Re-reads the custom maps (after an import or a copy into the maps folder).
func refresh_custom_maps() -> void:
	for key: String in _custom_keys: _files.erase(key)
	_custom_keys.clear()
	if id == "el2": _custom_keys = ELCustomMaps.index(_files, root)
	ELSingleScenario.clear_cache()

## The bytes of a script: the compiled chunk `name` + ".sobj" in the scripts
## archive, or else the loose text file `name` (custom maps). `name` may use
## backslashes, as script references in maps do.
func script_bytes(name: String) -> PackedByteArray:
	var key := ELArchive.key(name.strip_edges())
	if key.is_empty(): return PackedByteArray()
	var bytes := read("scripts", key + ".sobj") if archives.has("scripts") else PackedByteArray()
	if bytes.is_empty():
		var path := file(key)
		if not path.is_empty() and FileAccess.get_size(path) <= 16777216: bytes = FileAccess.get_file_as_bytes(path)
	return bytes

func _index(folder: String, relative: String) -> void:
	for path in DirAccess.get_files_at(folder):
		_files[ELArchive.key(relative + path)] = folder.path_join(path)
	for path in DirAccess.get_directories_at(folder):
		_index(folder.path_join(path), relative + path + "/")
