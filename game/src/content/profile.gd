class_name ELProfile
extends RefCounted
## Each edition owns its archives and caches. Identical card/asset names never
## resolve through another edition's mounted content.
var id := ""
var title := ""
var root := ""
var error := ""
var archives: Dictionary = {}
var tables: Dictionary = {}
var texts: Dictionary = {}
var _textures: Dictionary = {}
var _files: Dictionary = {}
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
## Interface button sounds by control name (ELUiSounds).
var button_sounds: Dictionary = {}

func mount(edition: String, folder: String) -> bool:
	error = ""
	archives.clear()
	tables.clear()
	texts.clear()
	_textures.clear()
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
	for required in ["resources/figures.res", "resources/crfigures.res", "resources/textures.res", "resources/regs.res", "resources/text.res"]:
		if not _files.has(required):
			error = "Missing original content: " + required
			return false
	# Distinguish editions from their campaign structure, not an arbitrary filename.
	var marker := "campaigns/good.cpg" if id == "el1" else "campaigns/white.cpg"
	if not _files.has(marker):
		error = "This folder does not contain the selected game: " + title
		return false
	for name: String in ["figures", "crfigures", "textures", "regs", "text", "animdb", "sfx", "camera", "pfx", "fx", "scripts"]:
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
	var bytes := read("textures", key if key.ends_with(".mmp") else key + ".mmp")
	var img := ELTexture.decode(bytes)
	if img == null:
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex

func text(key: String) -> String:
	return String(texts.get(key, key)).strip_edges()

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

func _index(folder: String, relative: String) -> void:
	for path in DirAccess.get_files_at(folder):
		_files[ELArchive.key(relative + path)] = folder.path_join(path)
	for path in DirAccess.get_directories_at(folder):
		_index(folder.path_join(path), relative + path + "/")
