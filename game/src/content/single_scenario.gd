class_name ELSingleScenario
extends RefCounted
## Single missions of both games: the maps the original SelectMission screen
## offers, their header summary, the map-size filter and the column sorts.
## First game (New game -> Single, Load game -> Single): the original scans
## Maps/*.map and keeps every map whose document has no <campaign> node; a
## chosen map starts outside the campaign (ELFirstScenario's generic win/lose)
## with the human as player 1 and every other player under ELFirstAI.
## Second game (Single game -> Mission -> New / Load): the catalogue scans the
## binary maps Maps/*.ebm (and the tutorial map) and lists every map whose
## header campaign flag is clear; every shipped map is a campaign chapter, so
## the list is empty unless the player adds a single map. Single saves are
## kept apart from the campaign save, one file per edition.

const SAVE_FIRST := "user://single-save.json"
const SAVE_SECOND := "user://single-save-el2.json"
## The single-mission save the front menu's Load opens: the file of the
## edition the menu shows (ELFrontMenu.use_edition sets it).
static var SAVE := SAVE_FIRST
## Campaign saves, one file per edition, so a campaign of one game never
## replaces the other's. CAMPAIGN_SAVE is the shared file older builds wrote
## for both editions; campaign_file() moves it to its own edition's file.
const CAMPAIGN_SAVE := "user://campaign-save.json"
const CAMPAIGN_SAVES := {"el1": "user://campaign-save-el1.json", "el2": "user://campaign-save-el2.json"}
## What the last migration attempt did (for tests and the log).
static var legacy_note := ""
static var _legacy_seen := -1
## map/size@x -> size class (small, medium, large, giant); other widths count as small.
const SIZE_CLASSES := {20: 0, 40: 0, 80: 1, 120: 2, 160: 3}
## MapSize5: every size class.
const ALL_SIZES := 4
## Original race codes by castle colour (the race-sort keys 1..4).
const RACES := {"Red": 1, "Green": 2, "Blue": 3, "Black": 4}
## Sort keys of the original (0 keeps the scan order). First game: clicking the
## active column again returns to the scan order. The second game has only
## the size (Sort1) and name (Mission) columns and never clears its sort.
const SORT_CONTROLS := {"Sort1": 0x10, "Sort2": 0x20, "Sort34": 1, "Sort31": 2, "Sort32": 3, "Sort33": 4, "Sort4": 0x40, "Sort5": 0x80, "Mission": 0x100}
const SORT_SIZE := 0x10
const SORT_SIDES := 0x20
const SORT_NAME := 0x100
## Second game: the tutorial map joins the catalogue after Maps/*.ebm.
const SECOND_TUTORIAL := "Tutorial/Adventure/e2tutorial"
## Second-game binary map header fields (tag order of the header block).
const BINARY_FIELDS := {1: "guid", 2: "title", 3: "description", 4: "objective", 5: "win_condition", 6: "lose_condition", 7: "minimap", 8: "width", 9: "campaign"}

static var _cache: Dictionary = {}

## Non-campaign maps in scan (file-name) order; cached per mounted profile.
static func catalog(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in maps(profile):
		if not entry.campaign: result.append(entry)
	return result

## Every map the catalogue knows, campaign chapters included, in scan order.
## Second game: Maps/*.ebm, then the tutorial map.
static func maps(profile: ELProfile) -> Array[Dictionary]:
	var key := profile.id + "|" + profile.root
	if not _cache.has(key):
		var found: Array[Dictionary] = []
		var second := profile.id == "el2"
		for path: String in profile.files_under("Maps/"):
			if not path.ends_with(".ebm" if second else ".map") or path.count("/") != 1: continue
			var id := path.get_file().get_basename()
			var entry := read_binary_header(profile, "Maps/" + id) if second else read_header(profile, id)
			if not entry.is_empty(): found.append(entry)
		if second:
			var tutorial := read_binary_header(profile, SECOND_TUTORIAL)
			if not tutorial.is_empty(): found.append(tutorial)
		_cache[key] = found
	var result: Array[Dictionary] = []
	result.assign(_cache[key])
	return result

static func clear_cache() -> void:
	_cache.clear()

## Header summary of one map document: text keys, players, size class.
static func read_header(profile: ELProfile, id: String) -> Dictionary:
	var path := profile.file("Maps/" + id + ".map")
	if path.is_empty(): return {}
	var document := FileAccess.get_file_as_bytes(path).get_string_from_ascii()
	var players_at := document.find("<players>")
	if not document.contains("<scenario>") or players_at < 0: return {}
	var head := document.substr(0, players_at)
	var entry := {"id": id, "campaign": head.contains("<campaign/>") or head.contains("<campaign>"), "players": [], "races": []}
	for field: String in ["title", "objective", "win_condition", "lose_condition", "description"]:
		entry[field] = _tag(head, field)
	var players_end := document.find("</players>", players_at)
	var block := document.substr(players_at, players_end - players_at) if players_end > players_at else ""
	# Each player: id, colour, name key, map blazon and diplomacy (opponent id ->
	# relations; nonzero is an ally, 255 the player itself).
	var pattern := RegEx.create_from_string("(?s)<player id=\"(\\d+)\"([^>]*)>\\s*<color>(\\w+)</color>(.*?)</player>")
	var number := RegEx.create_from_string("(\\w+)=\"(-?\\d+)\"")
	var opponent := RegEx.create_from_string("<opponent id=\"(\\d+)\" relations=\"(\\d+)\"")
	for found: RegExMatch in pattern.search_all(block):
		var attrs := {}
		for pair: RegExMatch in number.search_all(found.get_string(2)): attrs[pair.get_string(1)] = int(pair.get_string(2))
		var body := found.get_string(4)
		var relations := {}
		for row: RegExMatch in opponent.search_all(body): relations[int(row.get_string(1))] = int(row.get_string(2))
		entry.players.append({"id": int(found.get_string(1)), "color": found.get_string(3), "name": _tag(body.substr(0, body.find("<start_resources")) if body.contains("<start_resources") else body, "name"),
			"blazon": Vector2i(int(attrs.get("blazon", -1)), int(attrs.get("blazon_color", -1))), "relations": relations})
		var race: int = RACES.get(found.get_string(3), 0)
		if race > 0 and not entry.races.has(race): entry.races.append(race)
	var map_at := document.find("<map>")
	var width := 0
	if map_at >= 0:
		var size := RegEx.create_from_string("<size x=\"(\\d+)\"").search(document, map_at)
		if size != null: width = int(size.get_string(1))
	entry.width = width
	entry.size_class = int(SIZE_CLASSES.get(width, 0))
	return entry

static func _tag(text: String, field: String) -> String:
	var start := text.find("<" + field + ">")
	var stop := text.find("</" + field + ">")
	return text.substr(start + field.length() + 2, stop - start - field.length() - 2).strip_edges() if start >= 0 and stop > start else ""

## Second-game binary map header (<path>.ebm). The file is one tagged
## object; each field is a tag byte, a length and the bytes. A length byte with
## bit 0 clear holds the length in its upper seven bits; with bit 0 set, the
## length is the little-endian dword starting there, shifted right by one.
## The object holds one map object of fifteen sections (tags 1..15); the
## 0x0f section is the header: GUID, title, description,
## objective, win and lose texts, minimap, map width and the campaign flag.
## Returns {} when the file is missing or has no such block.
static func read_binary_header(profile: ELProfile, path: String) -> Dictionary:
	var file := profile.file(path + ".ebm")
	if file.is_empty(): return {}
	var fields := binary_header(FileAccess.get_file_as_bytes(file))
	if fields.is_empty(): return {}
	var entry := {"id": path.get_file(), "path": path, "players": [], "races": []}
	for tag: int in BINARY_FIELDS:
		var value: PackedByteArray = fields.get(tag, PackedByteArray())
		match tag:
			8: entry.width = value.decode_s32(0) if value.size() >= 4 else 0
			9: entry.campaign = value.size() > 0 and value[0] != 0
			_: entry[BINARY_FIELDS[tag]] = ELText.ansi(value).strip_edges()
	entry.size_class = int(SIZE_CLASSES.get(int(entry.width), 0))
	return entry

## Tag -> bytes of the header block, or {}.
static func binary_header(bytes: PackedByteArray) -> Dictionary:
	var top := binary_children(bytes, 0, bytes.size())
	if top.size() != 1: return {}
	var map := binary_children(bytes, top[0][1], top[0][2])
	if map.size() != 1: return {}
	var children := binary_children(bytes, map[0][1], map[0][2])
	for index in range(children.size() - 1, -1, -1):
		if children[index][0] != 0x0f: continue
		var fields := {}
		for field: Array in binary_children(bytes, children[index][1], children[index][2]): fields[field[0]] = bytes.slice(field[1], field[2])
		if fields.has(1) and fields.has(9): return fields
	return {}

## [tag, data start, data end] of each field in bytes[from, to), or [] unless
## the fields fill the range exactly.
static func binary_children(bytes: PackedByteArray, from: int, to: int) -> Array:
	var result: Array = []
	var at := from
	while at < to:
		if at + 1 >= to: return []
		var length := 0
		var data := at + 2
		if bytes[at + 1] & 1 == 0: length = bytes[at + 1] >> 1
		else:
			if at + 5 > to: return []
			length = bytes.decode_u32(at + 1) >> 1
			data = at + 5
		if data + length > to: return []
		result.append([bytes[at], data, data + length])
		at = data + length
	return result

## Rows shown for a size filter and sort key (stable within equal keys).
static func rows(profile: ELProfile, size_filter: int, sort_key: int) -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for entry: Dictionary in catalog(profile):
		if size_filter == ALL_SIZES or int(entry.size_class) == size_filter: shown.append(entry)
	if sort_key == 0: return shown
	var order := {}
	for index in shown.size(): order[shown[index].id] = index
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: Variant = _key(profile, a, sort_key)
		var second: Variant = _key(profile, b, sort_key)
		if first != second: return first < second
		return int(order[a.id]) < int(order[b.id]))
	return shown

static func _key(profile: ELProfile, entry: Dictionary, sort_key: int) -> Variant:
	match sort_key:
		SORT_SIZE: return int(entry.size_class)
		SORT_SIDES: return entry.players.size()
		1, 2, 3, 4: return 0 if entry.races.has(sort_key) else 1
	# Name, and the win / lose columns, which the original also orders by name.
	return title(profile, entry)

static func title(profile: ELProfile, entry: Dictionary) -> String:
	return profile.text(str(entry.get("title", ""))).strip_edges() if not str(entry.get("title", "")).is_empty() else str(entry.get("id", ""))

## Scenario row for the adventure view: no chapter number, so the session runs
## the non-campaign rules; the human takes player 1.
static func scenario(entry: Dictionary, player := 1) -> Dictionary:
	return {"file_name": str(entry.id), "player": str(player), "header": str(entry.get("title", "")), "single": true}

## A mission started from the single-mission choice. Second game: any map
## whose own header has no campaign node (only Select Mission starts one; the
## tutorial is never saved).
static func is_single(state: ELAdventureSession) -> bool:
	if state == null or state.map == null: return false
	match state.map.profile.id:
		"el1": return not state.scenario.is_empty() and not bool(state.scenario.get("campaign", true))
		"el2": return not state.tutorial and not state.scenario.has(ELSecondCampaign.KEY) and ELXml.child(state.map.document, "campaign").is_empty()
	return false

static func save_file(edition: String) -> String:
	return SAVE_SECOND if edition == "el2" else SAVE_FIRST

## Where F5 writes and F9 / Load reads for this session.
static func save_path(state: ELAdventureSession) -> String:
	return save_file(state.map.profile.id) if is_single(state) else campaign_file(state.map.profile.id)

## The campaign save of one edition. A shared save left by an older build is
## moved to its own edition first.
static func campaign_file(edition: String) -> String:
	migrate_campaign_save()
	return CAMPAIGN_SAVES.get(edition, CAMPAIGN_SAVES.el1)

## Moves the old shared campaign save to the file of the edition it names.
## Nothing is deleted: a save without a readable edition, or one whose
## edition already has its own file, stays where it is (legacy_note says why).
## Returns the edition the save was moved to, or "".
static func migrate_campaign_save() -> String:
	if not FileAccess.file_exists(CAMPAIGN_SAVE):
		_legacy_seen = -1
		return ""
	var stamp := FileAccess.get_modified_time(CAMPAIGN_SAVE)
	if stamp == _legacy_seen: return ""
	_legacy_seen = stamp
	var edition := legacy_edition(CAMPAIGN_SAVE)
	if edition.is_empty():
		legacy_note = "The old shared campaign save names no installed edition; it was kept unchanged."
		return ""
	var target: String = CAMPAIGN_SAVES[edition]
	if FileAccess.file_exists(target):
		_legacy_seen = -1
		legacy_note = "The old shared campaign save was kept: %s already has its own campaign save." % edition
		return ""
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(CAMPAIGN_SAVE), ProjectSettings.globalize_path(target)) != OK:
		legacy_note = "The old shared campaign save could not be moved; it was kept unchanged."
		return ""
	_legacy_seen = -1
	legacy_note = "The old shared campaign save now belongs to %s." % edition
	return edition

## The edition a campaign save says it belongs to ("el1"/"el2"), or "".
static func legacy_edition(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > ELAdventureSave.MAX_BYTES: return ""
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("format") != ELAdventureSave.FORMAT: return ""
	var edition: Variant = raw.get("edition")
	return str(edition) if edition is String and CAMPAIGN_SAVES.has(edition) else ""
