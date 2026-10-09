class_name ELHallOfFame
extends RefCounted
## Hall of Fame of both games: two tables (campaign, scenario) of at most ten
## records {name, id, points}, sorted by points descending with ties kept in
## arrival order. A won single mission adds a scenario record (map GUID, map
## player name, chapter score); a won campaign final adds a campaign record
## (campaign GUID, campaign player name, campaign score). The remake keeps the
## tables in its own per-edition user file; when that file does not exist yet,
## the records of the player's original HallOfFame.hl are read once.
## The second game keeps the same screen and file but reads only the scenario
## table, keeping records whose id is the GUID of one of its maps; nothing in
## it adds a record or opens the Hall of Fame after a win, so its campaign
## table always starts empty.

const LIMIT := 10
const KINDS := ["campaign", "scenario"]

static func path(edition: String) -> String:
	return "user://hall-of-fame-%s.json" % edition

## Stored tables and the last shown mode ("campaign" or "scenario").
static func load_tables(profile: ELProfile) -> Dictionary:
	var result := {"campaign": [], "scenario": [], "mode": "campaign"}
	var file := path(profile.id)
	if FileAccess.file_exists(file):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if raw is Dictionary:
			for kind: String in KINDS:
				result[kind] = _valid_records(raw.get(kind))
			if raw.get("mode") in KINDS: result.mode = raw.mode
		return result
	for kind: String in KINDS: result[kind] = original_records(profile, kind) if kind in original_kinds(profile.id) else []
	return result

## Tables the edition's game reads back from HallOfFame.hl at start-up.
static func original_kinds(edition: String) -> Array:
	return KINDS if edition == "el1" else ["scenario"]

static func save_tables(edition: String, tables: Dictionary) -> bool:
	var file := FileAccess.open(path(edition), FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"campaign": tables.campaign, "scenario": tables.scenario, "mode": tables.mode}))
	return true

static func _valid_records(raw: Variant) -> Array:
	var records: Array = []
	if not raw is Array: return records
	for row: Variant in raw:
		if not row is Dictionary or not row.get("name") is String or not row.get("id") is String: continue
		var points: Variant = row.get("points")
		if not (points is int or points is float) or float(points) < 0 or float(points) > 4294967295.0: continue
		records.append({"name": row.name, "id": row.id, "points": int(points)})
		if records.size() >= LIMIT: break
	return records

## Records of the original game's HallOfFame.hl (hall/<kind>/record name, id, points).
static func original_records(profile: ELProfile, kind: String) -> Array:
	var file := profile.file("HallOfFame.hl")
	if file.is_empty(): return []
	return document_records(profile, ELXml.parse(FileAccess.get_file_as_bytes(file)), kind)

## One table of a parsed HallOfFame.hl document, sorted. The second game keeps
## only records whose id is the GUID of one of its maps.
static func document_records(profile: ELProfile, document: Dictionary, kind: String) -> Array:
	if document.get("tag") != "hall": return []
	var records: Array = []
	var known := known_maps(profile) if profile.id != "el1" else {}
	for record: Dictionary in ELXml.children(ELXml.child(document, kind), "record"):
		var points := str(record.attrs.get("points", ""))
		if not points.is_valid_int(): continue
		if profile.id != "el1" and not known.has(str(record.attrs.get("id", "")).to_upper()): continue
		records.append({"name": str(record.attrs.get("name", "")), "id": str(record.attrs.get("id", "")), "points": clampi(int(points), 0, 4294967295)})
	return _sorted(records)

## Stable insertion by points descending; the table keeps its first ten rows.
static func insert(records: Array, record: Dictionary) -> int:
	var at := records.size()
	for index in records.size():
		if int(records[index].points) < int(record.points):
			at = index
			break
	records.insert(at, record)
	while records.size() > LIMIT: records.pop_back()
	return at if at < LIMIT else -1

static func _sorted(records: Array) -> Array:
	var result: Array = []
	for record: Dictionary in records: insert(result, record)
	return result

## Adds one record and makes its table the mode shown next; returns the row
## (0-based) or -1 when the points do not reach the table.
static func add(profile: ELProfile, kind: String, name: String, id: String, points: int) -> int:
	var tables := load_tables(profile)
	var row := insert(tables[kind], {"name": name, "id": id, "points": maxi(0, points)})
	tables.mode = kind
	save_tables(profile.id, tables)
	return row

static func set_mode(profile: ELProfile, kind: String) -> void:
	var tables := load_tables(profile)
	tables.mode = kind if kind in KINDS else "campaign"
	save_tables(profile.id, tables)

## GUID in a map document header (<id>{...}</id>).
static func map_guid(profile: ELProfile, map_id: String) -> String:
	return _header_tag(profile.file("Maps/" + map_id + ".map"), "<id>\\s*(\\{[^<]*\\})\\s*</id>").to_upper()

static func _header_tag(file: String, pattern: String) -> String:
	var handle := FileAccess.open(file, FileAccess.READ) if not file.is_empty() else null
	if handle == null: return ""
	var head := handle.get_buffer(8192).get_string_from_ascii()
	var found := RegEx.create_from_string(pattern).search(head)
	return found.get_string(1) if found != null else ""

## Second-game map catalogue by GUID: every map of Maps/ and the adventure
## tutorial map, campaign maps included -> {"path", "title"}.
static func known_maps(profile: ELProfile) -> Dictionary:
	var result := {}
	var keys: Array = []
	for key: String in profile.files_under("Maps/"):
		if key.ends_with(".map") and key.count("/") == 1: keys.append(key)
	keys.append("Tutorial/Adventure/e2tutorial.map")
	for key: String in keys:
		var file := profile.file(key)
		var guid := _header_tag(file, "<id>\\s*(\\{[^<]*\\})\\s*</id>").to_upper()
		if guid.is_empty() or result.has(guid): continue
		var title := _header_tag(file, "<title>([^<]*)</title>").strip_edges()
		result[guid] = {"path": key, "title": profile.text(title).strip_edges() if not title.is_empty() else key.get_file().get_basename()}
	return result

## Campaign document id attribute and default player name.
static func campaign_info(profile: ELProfile, campaign_id: String) -> Dictionary:
	var file := profile.file("Campaigns/" + campaign_id + ".cpg")
	if file.is_empty(): return {}
	var document := ELXml.parse(FileAccess.get_file_as_bytes(file))
	if document.get("tag") != "campaign": return {}
	return {"id": str(document.attrs.get("id", "")).to_upper(), "name": profile.text(str(document.attrs.get("name", campaign_id))), "player": str(document.attrs.get("default_player_name", ""))}

## Title shown in the last column: the campaign name or the map title whose GUID matches.
static func title(profile: ELProfile, kind: String, guid: String) -> String:
	var wanted := guid.to_upper()
	if wanted.is_empty(): return ""
	# The second game shows no title for campaign rows and the catalogue
	# title of the map for scenario rows.
	if profile.id != "el1":
		return "" if kind == "campaign" else str(known_maps(profile).get(wanted, {}).get("title", ""))
	if kind == "campaign":
		for campaign_id: String in ELCampaign.available(profile):
			var info := campaign_info(profile, campaign_id)
			if info.get("id", "") == wanted: return info.name
		return ""
	for key: String in profile.files_under("Maps/"):
		if not key.ends_with(".map") or key.count("/") != 1: continue
		var map_id := key.get_file().get_basename()
		if map_guid(profile, map_id) != wanted: continue
		var entry := ELSingleScenario.read_header(profile, map_id)
		return ELSingleScenario.title(profile, entry) if not entry.is_empty() else map_id
	return ""

## Name for a campaign started before names were chosen: the default
## player name the campaign screen's edit starts with.
static func campaign_player(profile: ELProfile, _campaign_id: String) -> String:
	return ELPlayerProfile.default_name(profile)

## Mission won: single missions add a scenario record; the campaign
## final adds the campaign record. Returns the kind recorded, or "".
static func record_mission(state: ELAdventureSession) -> String:
	if state == null or state.map == null or state.outcome != "win": return ""
	var profile: ELProfile = state.map.profile
	if profile.id != "el1" or state.scenario.is_empty(): return ""
	if ELSingleScenario.is_single(state):
		var points := ELCampaign.first_score(state.map.width, state.day, state.difficulty)
		# The name typed on the Single player panel (the human's slot).
		add(profile, "scenario", ELFirstScenario.player_name(state, state.current_player), map_guid(profile, state.map.id), points)
		return "scenario"
	var result := ELFirstScenario.chapter_result(state)
	var progress: Dictionary = state.scenario.get("progress", {})
	if result.is_empty() or not result.get("final", false) or progress.is_empty(): return ""
	# The name typed on the campaign screen; older campaigns fall back.
	var named: String = str(progress.player_name) if progress.get("player_name") is String else campaign_player(profile, progress.campaign)
	add(profile, "campaign", named, str(campaign_info(profile, progress.campaign).get("id", "")), int(result.score))
	return "campaign"
