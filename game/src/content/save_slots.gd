class_name ELSaveSlots
extends RefCounted
## Named saved games of both editions (the original SaveMissionScreen list).
## The original keeps every save as Save\<name>.sav in one folder and lists
## the readable ones in folder order; its load and save screens filter them
## by kind (campaign, single mission or multiplayer). The remake keeps one folder
## per edition, so a game of one edition never lists or replaces the other's:
## user://saves/<edition>/slot-<hash>.json holds the adventure save and
## slot-<hash>.meta.json the legacy list index. The checkpoint itself carries
## the list row so it can still be found if the index is lost.
## Strategic saves keep their list data inside the checkpoint
## under the edition's strategic folder. Old single-slot files are still listed.

const ROOT := "user://saves"
const KIND_CAMPAIGN := "campaign"
const KIND_SINGLE := "single"
const KIND_STRATEGIC := "strategic"
const META_FORMAT := "etherlords-save-slot"
const META_LIMIT := 8192
const META_PREFIX := '{"_slot":"'
const STRATEGY_FORMAT := "etherlords-strategic-save"
## The second game's SaveMissionScreen uses a 256×192 scene capture.
const PREVIEW_SIZE := Vector2i(256, 192)
const PREVIEW_BYTES := 256 * 192 * 3
## Characters the second game refuses in a save name (T_MB_WRONG_SAVE_NAME);
## the remake refuses them in both editions because the file name is derived
## from the save name.
const FORBIDDEN := "\\/:*?\"<>|.[],;="
const MAX_NAME := 60
## RECOVERED rows have no name from a current or legacy index. Their labels
## are for display, so selecting one in Save leaves the name field alone.
const SLOT := "slot"
const RECOVERED := "recovered"
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

static func folder(edition: String, kind := "") -> String:
	var base := ROOT.path_join(edition)
	return base.path_join(KIND_STRATEGIC) if kind == KIND_STRATEGIC else base

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

static func save_path(edition: String, name: String, kind := "") -> String:
	return folder(edition, kind).path_join(_stem(name) + ".json")

static func meta_path(edition: String, name: String) -> String:
	return folder(edition).path_join(_stem(name) + ".meta.json")

## True when a named slot of this edition already uses the name (any kind,
## compared without case, as the file system of the original compares it).
static func exists(edition: String, name: String, kind := "") -> bool:
	if kind == KIND_STRATEGIC: return FileAccess.file_exists(save_path(edition, name, kind))
	return FileAccess.file_exists(save_path(edition, name)) or FileAccess.file_exists(meta_path(edition, name))

## Writes a named slot. Returns "" or the error text.
static func write(name: String, director: ELAdventureDirector, camera: Dictionary = {}, preview: Image = null) -> String:
	var profile := director.state.map.profile
	var cleaned := clean_name(profile.id, name)
	if cleaned.is_empty(): return "Invalid save name."
	return _write(save_path(profile.id, cleaned), meta_path(profile.id, cleaned), cleaned, SLOT, director, camera, preview)

## A strategic slot is one file so the row and world change together. The
## ordered seat IDs survive reconnecting; readiness belongs to the live match.
static func write_strategy(name: String, director: ELAdventureDirector, players: Array[int], camera: Dictionary = {}, turn_seconds := 0, combat_seconds := 0, local_authority := false) -> String:
	var cleaned := clean_name("el1", name)
	if cleaned.is_empty(): return "Invalid save name."
	if turn_seconds < 0 or turn_seconds > ELNetworkStrategy.MAX_TURN_SECONDS: return "Invalid adventure time limit."
	if combat_seconds < 0 or combat_seconds > ELNetworkStrategy.MAX_TURN_SECONDS: return "Invalid combat time limit."
	if not _strategy_planning(director, players, local_authority) or director.strategy_seats() != players or local_authority != (director.strategy_commanders().size() == 1):
		return "Save a strategic match while both players are still planning."
	var codec := ELAdventureSave.new()
	var world := codec.encode(director, camera)
	if world.is_empty(): return codec.error
	var directory := folder("el1", KIND_STRATEGIC)
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return "Could not open the strategic save folder."
	var document := {"format": STRATEGY_FORMAT, "version": 1, "name": cleaned, "created": int(Time.get_unix_time_from_system()), "players": players, "world": world}
	if local_authority:
		document.merge({"version": 4, "turn_seconds": turn_seconds, "combat_seconds": combat_seconds, "local_authority": true}, true)
	elif combat_seconds > 0:
		document.version = 3
		document.turn_seconds = turn_seconds
		document.combat_seconds = combat_seconds
	elif turn_seconds > 0:
		document.version = 2
		document.turn_seconds = turn_seconds
	return "" if codec.write_document(save_path("el1", cleaned, KIND_STRATEGIC), document) else codec.error

## Returns the decoded world with host/guest seat IDs, or an error. The caller
## binds the seats after setting up the new connection.
static func read_strategy(path: String, profile: ELProfile) -> Dictionary:
	var codec := ELAdventureSave.new()
	var document: Variant = codec.read_document(path)
	if not codec.error.is_empty(): return {"error": "No readable strategic save was found."}
	var header := _strategy_header(document, profile)
	if header.is_empty(): return {"error": "Invalid strategic save."}
	var world: Dictionary = document.world
	if not _strategy_document_idle(world): return {"error": "The strategic save contains an action in progress."}
	var restored := codec.decode(world, {"el1": profile})
	if restored.is_empty(): return {"error": codec.error}
	if not _strategy_planning(restored.director, header.players, header.local_authority):
		restored.state.close()
		return {"error": "The strategic save cannot resume from planning."}
	restored.players = header.players
	restored.turn_seconds = header.turn_seconds
	restored.combat_seconds = header.combat_seconds
	restored.local_authority = header.local_authority
	return restored

static func _strategy_header(document: Variant, profile: ELProfile) -> Dictionary:
	if profile == null or profile.id != "el1" or not document is Dictionary: return {}
	if document.get("format") != STRATEGY_FORMAT or not ELLuaSave._integer(document.get("version"), 1, 4): return {}
	var turn_seconds := 0
	var combat_seconds := 0
	var local_authority: bool = document.version == 4
	if document.version == 1:
		if document.size() != 6 or document.has("turn_seconds") or document.has("combat_seconds"): return {}
	elif document.version == 2:
		if document.size() != 7 or document.has("combat_seconds") or not ELLuaSave._integer(document.get("turn_seconds"), 1, ELNetworkStrategy.MAX_TURN_SECONDS): return {}
		turn_seconds = int(document.turn_seconds)
	else:
		if (document.size() != (9 if local_authority else 8) or not ELLuaSave._integer(document.get("turn_seconds"), 0, ELNetworkStrategy.MAX_TURN_SECONDS)
			or not ELLuaSave._integer(document.get("combat_seconds"), 0 if local_authority else 1, ELNetworkStrategy.MAX_TURN_SECONDS)): return {}
		if local_authority and document.get("local_authority") != true: return {}
		turn_seconds = int(document.turn_seconds)
		combat_seconds = int(document.combat_seconds)
	var name: Variant = document.get("name")
	if not name is String or clean_name("el1", name).is_empty() or not ELLuaSave._integer(document.get("created"), 0, 253402300799): return {}
	var seats: Variant = document.get("players")
	if not seats is Array or seats.size() != 2: return {}
	var players: Array[int] = []
	for seat: Variant in seats:
		if not ELLuaSave._integer(seat, 1, 0x7fffffff) or players.has(int(seat)): return {}
		players.append(int(seat))
	var payload: Variant = document.get("world")
	if not payload is Dictionary or payload.get("format") != ELAdventureSave.FORMAT or payload.get("edition") != "el1": return {}
	var map_id: Variant = payload.get("map")
	if not ELNetworkStrategy._valid_map_id(map_id) or payload.get("script_name") != "Maps/" + map_id: return {}
	var world: Variant = payload.get("world")
	if not world is Dictionary or world.get("current_player") != players[0]: return {}
	# The save carries the mutable world LCG state, which uses all 32 bits.
	if not ELLuaSave._integer(world.get("day"), 1, 0x7fffffff) or not ELLuaSave._integer(world.get("seed_value"), 0, 0xffffffff): return {}
	var map_header := ELSingleScenario.read_header(profile, map_id)
	if map_header.is_empty() or map_header.campaign: return {}
	var map := ELAdventureMap.new()
	if not map.load_map(profile, map_id) or not ELNetworkStrategy._valid_players(map, Vector2i(players[0], players[1])): return {}
	return {"map": map_id, "title": ELSingleScenario.title(profile, map_header), "day": int(world.day), "players": players,
		"seat_count": map_header.players.size(), "turn_seconds": turn_seconds, "combat_seconds": combat_seconds, "local_authority": local_authority}

static func _strategy_document_idle(document: Dictionary) -> bool:
	# Check before decode, which may drop a stale movement record.
	var playback: Variant = document.get("director")
	var encounter: Variant = document.get("encounter")
	var commands: Variant = document.get("commands")
	if not playback is Dictionary or not encounter is Dictionary or not encounter.is_empty() or not commands is Array or not commands.is_empty(): return false
	for key: String in ["movement", "travel", "strategy", "dialogue"]:
		var field: Variant = playback.get(key)
		if not field is Dictionary or not field.is_empty(): return false
	var boxes: Variant = playback.get("boxes")
	return boxes is Array and boxes.is_empty() and playback.get("waiting") == false and playback.get("commands_pending") == false and playback.get("action_wait") == 0.0

static func _strategy_planning(director: ELAdventureDirector, players: Array[int], local_authority := false) -> bool:
	if director == null or director.state == null or director.grid == null or players.size() != 2 or players[0] == players[1]: return false
	var state := director.state
	if not ELFirstScenario.applies(state) or bool(state.scenario.get("campaign", false)) or state.tutorial: return false
	if not ELXml.child(state.map.document, "campaign").is_empty() or not ELNetworkStrategy._valid_players(state.map, Vector2i(players[0], players[1])):
		return false
	if not ELNetworkStrategy._valid_map_id(state.map.id) or state.script_name != "Maps/" + state.map.id or state.current_player != players[0]:
		return false
	if state.day < 1 or state.day > 0x7fffffff or state.seed_value < 0 or state.seed_value > 0xffffffff or state.difficulty < 0 or state.difficulty > 4:
		return false
	if state.main_hero >= 0 and state.object(state.main_hero).get("owner") != state.current_player: return false
	if not state.error.is_empty() or not director.can_move() or not director.movement.is_empty() or not director.boxes.is_empty() or director.action_wait != 0.0 or director._waiting or director._commands_pending:
		return false
	for player: int in players:
		if not state.players.has(player) or director.strategy_ready(player): return false
		if not ELFirstScenario.alive(state, player) and (not local_authority or player != players[1]): return false
	return true

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

static func _write(path: String, entry: String, name: String, type: String, director: ELAdventureDirector, camera: Dictionary, preview: Image = null) -> String:
	var state := director.state
	var profile := state.map.profile
	if state.tutorial: return "The tutorial cannot be saved."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder(profile.id)))
	var codec := ELAdventureSave.new()
	var document := codec.encode(director, camera)
	if document.is_empty(): return codec.error
	if profile.id == "el2" and preview != null and preview.get_size() == PREVIEW_SIZE and preview.get_format() == Image.FORMAT_RGB8 and not preview.has_mipmaps():
		# Store the picture in the atomic world save so an overwrite always
		# pairs the preview with the state it depicts.
		document.preview_rgb = Marshalls.raw_to_base64(preview.get_data())
	var meta := {"format": META_FORMAT, "version": 1, "name": name, "type": type, "file": path.get_file(), "edition": profile.id, "kind": kind_of(state), "map": state.map.id,
		"title": map_title(profile, state.map.id), "campaign": campaign_title(state), "day": state.day, "players": player_count(state), "created": int(Time.get_unix_time_from_system())}
	# Sorted checkpoint JSON puts this bounded string first. Listings can
	# read it without loading the world, even when it supersedes a stale index.
	document._slot = Marshalls.utf8_to_base64(JSON.stringify(meta))
	if not codec.write_document(path, document): return codec.error
	# Older builds still read the separate index.
	codec.write_document(entry, meta)
	return ""

## Read only the chosen row's optional picture. Fixed dimensions keep preview
## decoding bounded independently of the rest of the saved game.
static func preview_image(row: Dictionary) -> Image:
	if row.get("edition") != "el2" or row.get("type") not in [SLOT, RECOVERED]: return null
	var raw := _header(str(row.get("path", "")))
	var preview: Variant = raw.get("preview_rgb")
	if raw.get("edition") != "el2" or not preview is String or preview.length() != PREVIEW_BYTES / 3 * 4: return null
	var pixels := Marshalls.base64_to_raw(preview)
	if pixels.size() != PREVIEW_BYTES: return null
	return Image.create_from_data(PREVIEW_SIZE.x, PREVIEW_SIZE.y, false, Image.FORMAT_RGB8, pixels)

static func map_title(profile: ELProfile, map_id: String) -> String:
	var entry := ELSingleScenario.read_binary_header(profile, ELSingleScenario.map_path(map_id)) if profile.id == "el2" else ELSingleScenario.read_header(profile, map_id)
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
	if kind == KIND_STRATEGIC: return _strategy_list(profile)
	var result: Array[Dictionary] = []
	var directory := folder(profile.id)
	var dir := DirAccess.open(directory)
	if dir != null:
		for file: String in dir.get_files():
			var identity := _slot_identity(profile, file)
			if identity.is_empty(): continue
			var path := directory.path_join(file)
			var index := path.get_basename() + ".meta.json"
			var row := _slot_row(profile, path, index, identity)
			if row.get("kind") != kind: continue
			row.path = path
			row.meta_path = index
			row.modified = int(row.get("created", FileAccess.get_modified_time(path)))
			result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.name).to_upper() != str(b.name).to_upper(): return str(a.name).to_upper() < str(b.name).to_upper()
		return a.type == AUTO and b.type != AUTO)
	result.append_array(legacy(profile, kind))
	return result

static func _slot_identity(profile: ELProfile, file: String) -> Dictionary:
	if not file.ends_with(".json"): return {}
	var stem := file.get_basename()
	if stem.begins_with("slot-") and stem.length() == 37:
		var hash_text := stem.substr(5)
		if hash_text.is_valid_hex_number() and hash_text == hash_text.to_lower() and not hash_text.begins_with("-") and not hash_text.begins_with("+"):
			var quick := quick_name(profile)
			return {"type": SLOT, "name": quick if stem == _stem(quick) else "", "kind": "", "suffix": hash_text.left(8)}
	for key: String in AUTOSAVES:
		for kind: String in [KIND_CAMPAIGN, KIND_SINGLE]:
			if file == auto_path(profile.id, kind, key).get_file():
				return {"type": AUTO, "name": profile.text(key).strip_edges(), "kind": kind}
	return {}

static func _row_meta(text: String, profile: ELProfile, file: String, identity: Dictionary) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {}
	var meta: Dictionary = parser.data
	if meta.get("format") != META_FORMAT or meta.get("edition") != profile.id or meta.get("file", file) != file: return {}
	if meta.get("version", 1) != 1 or meta.get("kind") not in [KIND_CAMPAIGN, KIND_SINGLE] or meta.get("type", SLOT) != identity.type: return {}
	if not meta.get("name") is String or not meta.get("map") is String or not String(meta.map).is_valid_identifier(): return {}
	if not ELLuaSave._integer(meta.get("day"), 0, 0x7fffffff) or not ELLuaSave._integer(meta.get("players"), 0, 0x7fffffff): return {}
	if not meta.get("title") is String or not meta.get("campaign", "") is String: return {}
	if not ELLuaSave._integer(meta.get("created", 0), 0, 253402300799): return {}
	if identity.type == SLOT and (clean_name(profile.id, meta.name).is_empty() or _stem(meta.name) + ".json" != file): return {}
	if identity.type == AUTO and meta.kind != identity.kind: return {}
	meta.type = identity.type
	return meta

static func _slot_row(profile: ELProfile, path: String, index: String, identity: Dictionary) -> Dictionary:
	var save := FileAccess.open(path, FileAccess.READ)
	if save == null or save.get_length() > ELAdventureSave.MAX_BYTES: return {}
	var prefix := save.get_buffer(mini(save.get_length(), META_LIMIT)).get_string_from_ascii()
	save.close()
	var embedded := {}
	if prefix.begins_with(META_PREFIX):
		var end := prefix.find('"', META_PREFIX.length())
		if end >= 0:
			embedded = _row_meta(Marshalls.base64_to_utf8(prefix.substr(META_PREFIX.length(), end - META_PREFIX.length())), profile, path.get_file(), identity)
	var index_file := FileAccess.open(index, FileAccess.READ)
	if index_file != null and index_file.get_length() <= META_LIMIT:
		var indexed := _row_meta(index_file.get_as_text(), profile, path.get_file(), identity)
		index_file.close()
		if not indexed.is_empty(): return embedded if not embedded.is_empty() else indexed
	# The list must not present an unreadable payload merely because it has a
	# recognizable filename. Validate orphaned checkpoints through normal Load.
	var codec := ELAdventureSave.new()
	var document: Variant = codec.read_document(path)
	if not document is Dictionary: return {}
	var restored := codec.decode(document, {profile.id: profile})
	if restored.is_empty(): return {}
	var row := current_row(restored.state)
	restored.state.close()
	if identity.type == AUTO and row.kind != identity.kind: return {}
	if embedded.is_empty() and document.get("_slot") is String and document._slot.length() <= META_LIMIT:
		embedded = _row_meta(Marshalls.base64_to_utf8(document._slot), profile, path.get_file(), identity)
	row.edition = profile.id
	row.type = identity.type
	row.name = identity.name
	if not embedded.is_empty() and embedded.kind == row.kind and embedded.map == row.map:
		row.name = embedded.name
		if embedded.has("created"): row.created = embedded.created
	elif row.name.is_empty():
		row.type = RECOVERED
		row.name = "%s · %s" % [row.title, identity.suffix]
	return row

static func _strategy_list(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile.id != "el1": return result
	var directory := folder(profile.id, KIND_STRATEGIC)
	var dir := DirAccess.open(directory)
	if dir == null: return result
	var codec := ELAdventureSave.new()
	for file: String in dir.get_files():
		if not file.begins_with("slot-") or not file.ends_with(".json"): continue
		var path := directory.path_join(file)
		var document: Variant = codec.read_document(path)
		var header := _strategy_header(document, profile)
		if header.is_empty() or file != _stem(document.name) + ".json": continue
		result.append({"type": SLOT, "name": document.name, "path": path, "kind": KIND_STRATEGIC, "edition": profile.id, "map": header.map, "title": header.title,
			"campaign": "", "day": header.day, "players": header.seat_count, "modified": int(document.created)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).nocasecmp_to(b.name) < 0)
	return result

## Old single-slot files of this edition and kind (written by earlier builds'
## F5, hence the quick-save name), and the second game's chapter autosave.
static func legacy(profile: ELProfile, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if kind == KIND_STRATEGIC: return result
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
