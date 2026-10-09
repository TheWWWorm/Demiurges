class_name ELSaveSlots
extends RefCounted
## Named saved games of both editions (the original SaveMissionScreen list).
## The original keeps every save as Save\<name>.sav in one folder and lists
## the readable ones in folder order; its load and save screens filter them
## by kind (campaign games, or single missions). The remake keeps one folder
## per edition, so a game of one edition never lists or replaces the other's:
## user://saves/<edition>/slot-<hash>.json holds the adventure save and
## slot-<hash>.meta.json the list row (name, kind, map, day, players,
## creation time). The old single-slot files of earlier remake builds are
## listed as read-only rows so they stay loadable.

const ROOT := "user://saves"
const KIND_CAMPAIGN := "campaign"
const KIND_SINGLE := "single"
const META_FORMAT := "etherlords-save-slot"
## Characters the second game refuses in a save name (T_MB_WRONG_SAVE_NAME);
## the remake refuses them in both editions because the file name is derived
## from the save name.
const FORBIDDEN := "\\/:*?\"<>|.[],;="
const MAX_NAME := 60
## Row types: a named slot, an old single-slot file, the second game's
## between-chapter campaign autosave (campaign progress, not a map save).
const SLOT := "slot"
const LEGACY := "legacy"
const PROGRESS := "progress"
const AUTO := "auto"
## The first game's automatic saves: one slot each, overwritten every time.
## T_AUTOSAVE_EOT when the player ends a turn (Autosave option on),
## T_AUTOSAVE_START_MISSION when a mission starts. The original writes them as
## ordinary saves under these names; the remake keeps them in their own files
## (one per edition and kind) so they never replace a save the player named.
const AUTOSAVES := ["T_AUTOSAVE_EOT", "T_AUTOSAVE_START_MISSION"]

## The quick-save slot (F5): T_QUICK_SAVE_NAME of the edition.
static func quick_name(profile: ELProfile) -> String:
	return profile.text("T_QUICK_SAVE_NAME").strip_edges()

## Where F8 / F9 resume: the quick-save slot, or the old single-slot file an
## earlier build's F5 wrote for this kind of game.
static func quick_load_path(state: ELAdventureSession) -> String:
	var quick := save_path(state.map.profile.id, quick_name(state.map.profile))
	return quick if FileAccess.file_exists(quick) else ELSingleScenario.save_path(state)

static func folder(edition: String) -> String:
	return ROOT.path_join(edition)

static func kind_of(state: ELAdventureSession) -> String:
	return KIND_SINGLE if ELSingleScenario.is_single(state) else KIND_CAMPAIGN

## The save name after the edition's rules, or "" when it is refused. The
## second game strips spaces and tabs at both ends; the first keeps the name
## as typed and only needs one non-space character.
static func clean_name(edition: String, name: String) -> String:
	var cleaned := name.strip_edges() if edition == "el2" else name
	if cleaned.strip_edges().is_empty() or cleaned.length() > MAX_NAME: return ""
	for character in FORBIDDEN:
		if cleaned.contains(character): return ""
	return cleaned

## File stem of a name: a hash of the lower-case name, so any name the rules
## allow (Cyrillic included) maps to one short, portable file name; the
## display name lives in the list entry.
static func _stem(name: String) -> String:
	return "slot-" + name.to_lower().md5_text()

static func save_path(edition: String, name: String) -> String:
	return folder(edition).path_join(_stem(name) + ".json")

static func meta_path(edition: String, name: String) -> String:
	return folder(edition).path_join(_stem(name) + ".meta.json")

## True when a named slot of this edition already uses the name (any kind,
## compared without case, as the file system of the original compares it).
static func exists(edition: String, name: String) -> bool:
	return FileAccess.file_exists(save_path(edition, name)) or FileAccess.file_exists(meta_path(edition, name))

## Writes a named slot. Returns "" or the error text.
static func write(name: String, director: ELAdventureDirector, camera: Dictionary = {}) -> String:
	var profile := director.state.map.profile
	var cleaned := clean_name(profile.id, name)
	if cleaned.is_empty(): return "Invalid save name."
	return _write(save_path(profile.id, cleaned), meta_path(profile.id, cleaned), cleaned, SLOT, director, camera)

## File of an automatic save: per edition, kind and autosave key.
static func auto_path(edition: String, kind: String, key: String) -> String:
	return folder(edition).path_join("auto-%s-%s.json" % [key.to_lower(), kind])

## Writes the automatic save `key` (one of AUTOSAVES) of the running game's
## kind, replacing the previous one. Returns "" or the error text.
static func write_auto(key: String, director: ELAdventureDirector, camera: Dictionary = {}) -> String:
	var state := director.state
	var profile := state.map.profile
	if state.tutorial: return "The tutorial is not saved."
	var path := auto_path(profile.id, kind_of(state), key)
	return _write(path, path.get_basename() + ".meta.json", profile.text(key).strip_edges(), AUTO, director, camera)

static func _write(path: String, entry: String, name: String, type: String, director: ELAdventureDirector, camera: Dictionary) -> String:
	var state := director.state
	var profile := state.map.profile
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder(profile.id)))
	var codec := ELAdventureSave.new()
	if not codec.write(path, director, camera): return codec.error
	var meta := {"format": META_FORMAT, "version": 1, "name": name, "type": type, "file": path.get_file(), "edition": profile.id, "kind": kind_of(state), "map": state.map.id,
		"title": map_title(profile, state.map.id), "campaign": campaign_title(state), "day": state.day, "players": player_count(state), "created": int(Time.get_unix_time_from_system())}
	var file := FileAccess.open(entry, FileAccess.WRITE)
	if file == null: return "The save list entry could not be written."
	file.store_string(JSON.stringify(meta))
	file.close()
	return ""

static func map_title(profile: ELProfile, map_id: String) -> String:
	var entry := ELSingleScenario.read_binary_header(profile, "Maps/" + map_id) if profile.id == "el2" else ELSingleScenario.read_header(profile, map_id)
	if entry.is_empty(): return map_id
	return ELSingleScenario.title(profile, entry)

## Title of the campaign a chapter belongs to ("" outside a campaign).
static func campaign_title(state: ELAdventureSession) -> String:
	if ELSingleScenario.is_single(state) or state.tutorial: return ""
	var profile := state.map.profile
	for id: String in ELCampaign.available(profile):
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, id): continue
		for row: Dictionary in campaign.scenarios:
			if str(row.get("file_name", "")) == state.map.id: return campaign.title
	return ""

## Players of the map, the neutral player excluded.
static func player_count(state: ELAdventureSession) -> int:
	var count := 0
	for id: int in state.players:
		if id > 0: count += 1
	return count

## Rows of one edition and kind in list order: named slots and automatic
## saves by name (standing in for the original's folder order), then the old
## single-slot files.
static func list(profile: ELProfile, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(folder(profile.id))
	if dir != null:
		for file: String in dir.get_files():
			if not file.ends_with(".meta.json"): continue
			var path := folder(profile.id).path_join(file)
			var parser := JSON.new()
			if parser.parse(FileAccess.get_file_as_string(path)) != OK: continue
			var meta: Variant = parser.data
			if not meta is Dictionary or meta.get("format") != META_FORMAT or meta.get("edition") != profile.id or meta.get("kind") != kind or not meta.get("name") is String: continue
			var type := str(meta.get("type", SLOT))
			if not type in [SLOT, AUTO]: continue
			var save := save_path(profile.id, str(meta.name)) if type == SLOT else folder(profile.id).path_join(str(meta.get("file", "")).get_file())
			if type == AUTO and not str(meta.get("file", "")).begins_with("auto-"): continue
			if not FileAccess.file_exists(save): continue
			var row: Dictionary = meta.duplicate()
			row.type = type
			row.path = save
			row.meta_path = path
			row.modified = int(meta.get("created", FileAccess.get_modified_time(save)))
			result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.name).to_upper() != str(b.name).to_upper(): return str(a.name).to_upper() < str(b.name).to_upper()
		return a.type == AUTO and b.type != AUTO)
	result.append_array(legacy(profile, kind))
	return result

## Old single-slot files of this edition and kind (written by earlier builds'
## F5, hence the quick-save name), and the second game's chapter autosave.
static func legacy(profile: ELProfile, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quick := profile.text("T_QUICK_SAVE_NAME").strip_edges()
	var paths: Array[String] = []
	if kind == KIND_SINGLE: paths.append(ELSingleScenario.save_file(profile.id))
	else:
		paths.append(ELSingleScenario.campaign_file(profile.id))
		if ELSingleScenario.legacy_edition(ELSingleScenario.CAMPAIGN_SAVE) == profile.id: paths.append(ELSingleScenario.CAMPAIGN_SAVE)
	for path: String in paths:
		var header := _header(path)
		if header.is_empty() or header.get("edition") != profile.id: continue
		var title := map_title(profile, str(header.get("map", "")))
		if kind == KIND_SINGLE and not _single_map(profile, str(header.get("map", ""))): continue
		var world: Variant = header.get("world", {})
		result.append({"type": LEGACY, "name": quick, "path": path, "kind": kind, "edition": profile.id, "map": str(header.get("map", "")), "title": title,
			"campaign": "", "day": int(world.get("day", 0)) if world is Dictionary else 0, "players": -1, "modified": FileAccess.get_modified_time(path)})
	if kind == KIND_CAMPAIGN and profile.id == "el2" and FileAccess.file_exists(ELSecondCampaign.AUTOSAVE) and not ELSecondCampaign.read(ELSecondCampaign.AUTOSAVE).is_empty():
		result.append({"type": PROGRESS, "name": profile.text("T_AUTO_SAVE_AFTER_MISSION").strip_edges(), "path": ELSecondCampaign.AUTOSAVE, "kind": kind, "edition": "el2",
			"map": "", "title": "", "campaign": "", "day": 0, "players": -1, "modified": FileAccess.get_modified_time(ELSecondCampaign.AUTOSAVE)})
	return result

## A single-mission save is listed only while its map is still a known
## non-tutorial map (the original drops records whose map left the catalogue).
static func _single_map(profile: ELProfile, map_id: String) -> bool:
	for entry: Dictionary in ELSingleScenario.maps(profile):
		if entry.id == map_id and not str(entry.get("path", "")).begins_with("Tutorial"): return true
	return false

static func _header(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > ELAdventureSave.MAX_BYTES: return {}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("format") != ELAdventureSave.FORMAT or not raw.get("map") is String: return {}
	return raw

## Deletes a row's files. Old files are removed only after the question the
## screen asks; nothing else is touched.
static func remove(row: Dictionary) -> void:
	for key: String in ["path", "meta_path"]:
		if row.has(key) and FileAccess.file_exists(str(row[key])): DirAccess.remove_absolute(ProjectSettings.globalize_path(str(row[key])))

## The named slot (not an old file) with this name, or {}.
static func find(profile: ELProfile, name: String) -> Dictionary:
	for kind: String in [KIND_CAMPAIGN, KIND_SINGLE]:
		for row: Dictionary in list(profile, kind):
			if row.type == SLOT and str(row.name).to_lower() == name.to_lower(): return row
	return {}

## The running game as a row (the save mode's information box).
static func current_row(state: ELAdventureSession) -> Dictionary:
	return {"name": "", "kind": kind_of(state), "map": state.map.id, "title": map_title(state.map.profile, state.map.id), "campaign": campaign_title(state), "day": state.day, "players": player_count(state)}

## Information-box text of a row. First game: campaign title, name, map
## title, day and player count; second game: "Кампания" for a campaign game,
## otherwise name, map title and day.
static func info(profile: ELProfile, row: Dictionary) -> String:
	var day := profile.text("T_SI_DAY").strip_edges()
	if profile.id == "el2":
		if row.get("kind") == KIND_CAMPAIGN: return profile.text("T_SI_CAMPAIGN").strip_edges()
	var lines: Array[String] = []
	if profile.id == "el1" and not str(row.get("campaign", "")).is_empty(): lines.append(str(row.campaign))
	if not str(row.get("name", "")).is_empty(): lines.append(str(row.name))
	if not str(row.get("title", "")).is_empty(): lines.append(str(row.title))
	if int(row.get("day", 0)) > 0: lines.append("%s %d" % [day, int(row.day)])
	if profile.id == "el1" and int(row.get("players", -1)) >= 0: lines.append("%d %s" % [int(row.players), profile.text("T_SI_PLAYERS").strip_edges()])
	return "\n".join(lines)
