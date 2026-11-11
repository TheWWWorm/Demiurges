class_name ELBinaryMap
extends RefCounted
## Etherlords II binary maps (a shipped .ebm, a custom map's .sbm) read into
## the XML scenario the remake plays. The game itself plays only the binary
## file, and many custom maps ship without the editor's scenario (.smp); the
## remake reads such a map through the scenario this builds.
##
## The file is one tagged object (see ELSingleScenario.binary_children). The
## map object has fifteen sections:
##   1 terrain objects   2 terrain grids     3 creatures (mdm_mobs)
##   4 resource cuts     5 players           6 heroes without a player
##   7 mana nodes        8 mines             9 laboratories
##   10 factories        11 forts            12 additional buildings
##   13 artefacts        14 global spells    15 header
## Records store permanent ids one lower than the scenario does, positions as
## x, y and rotation dwords, and text in Windows-1251. Grids are packed in
## runs: a big-endian 24-bit header (bit 20 set: that many literal bytes
## follow; clear: one byte repeated that many times). Roads and creeks pack
## dwords the same way with a little-endian dword header; the colourless zone
## packs four 2-bit cells a byte before the runs.
## Checked against the 14 shipped .ebm/.map pairs: every element the scenario
## holds is rebuilt, except the editor's race names of players after the first.

const COLORS := ["Red", "Green", "Blue", "Black", "White"]
const RESOURCES := ["Herbs", "Gems", "Flames", "Ether"]
## Bumped when the output changes, so cached scenarios are rebuilt.
const VERSION := 1
const LITERAL := 0x100000
const MAX_CELLS := 513 * 513

var _bytes := PackedByteArray()
var _out := PackedStringArray()
var _last_id := 0
var error := ""

## The scenario document (UTF-8 XML text) of a binary map, or "" with the
## reason in `error`.
static func scenario(bytes: PackedByteArray) -> Dictionary:
	var reader := ELBinaryMap.new()
	var text := reader._convert(bytes)
	return {"text": text, "error": reader.error}

func _convert(bytes: PackedByteArray) -> String:
	_bytes = bytes
	var top := _kids([0, 0, bytes.size()])
	if top.size() != 1: return _fail("Not a binary map.")
	var outer := _kids(top[0])
	if outer.size() != 1: return _fail("Not a binary map.")
	var map: Array = outer[0]
	var header := _field(map, 15)
	var grids := _field(map, 2)
	if header.is_empty() or grids.is_empty(): return _fail("The binary map has no header or terrain.")
	_out.append("<?xml version=\"1.0\"?>\n<new_scenario>")
	for field: Array in [["id", 1], ["title", 2], ["objective", 4], ["win_condition", 5], ["lose_condition", 6], ["description", 3]]:
		_out.append("<%s>%s</%s>" % [field[0], _text(_field(header, field[1])), field[0]])
	var campaign := _field(header, 9)
	if not campaign.is_empty() and campaign[2] > campaign[1] and _bytes[campaign[1]] != 0: _out.append("<campaign/>")
	_out.append("<minimap>%s</minimap>" % _text(_field(header, 7)))
	_players(map, header)
	var start := _out.size()
	_out.append("<mana_nodes/>")
	_mines(_field(map, 8))
	_cuts(_field(map, 4))
	_laboratories(_field(map, 9))
	_out.append("<factories/>")
	_artefacts(_field(map, 13))
	_out.append("<global_spells/>")
	_forts(_field(map, 11))
	_terrain_objects(_field(map, 1))
	_mobs(_field(map, 3))
	_out.append("<np_heroes>")
	var index := 0
	for hero: Array in _all(_field(map, 6), 1):
		_hero(hero, index)
		index += 1
	_out.append("</np_heroes>")
	_buildings(_field(map, 12))
	if not error.is_empty(): return ""
	# The scenario keeps the highest permanent id ahead of the objects.
	_out.insert(start, "<support last_permanent_id=\"%d\"/>" % _last_id)
	if not _grids(grids): return ""
	_out.append("</new_scenario>")
	return "".join(_out)

func _fail(message: String) -> String:
	if error.is_empty(): error = message
	return ""

# --- Players -----------------------------------------------------------------

func _players(map: Array, header: Array) -> void:
	_out.append("<players>")
	# The header names the first player only (the editor's race label).
	var named := _all(_field(header, 10), 1)
	for player: Array in _all(_field(map, 5), 1):
		var buildings := _field(player, 3)
		# Eight slots are stored; unused ones have no buildings.
		if _count(buildings) == 0: continue
		var id := _int(_field(player, 1))
		var color := _color(_int(_field(player, 2)))
		var info: Array = named[0] if id == 1 and not named.is_empty() else []
		_out.append("<player id=\"%d\" health=\"%d\" blazon=\"%d\" blazon_color=\"%d\"><color>%s</color><name>%s</name><start_resources/><global_spells/><buildings>" % [
			id, _int(_field(player, 4)), _int(_field(info, 3)), _int(_field(info, 4)), color, _text(_field(info, 2))])
		var records := _field(buildings, 2)
		for i in _count(buildings):
			var at := _record(records, i, 28)
			if at < 0: break
			_out.append("<building permanent_id=\"%d\" mana_income=\"%d\"><type>MainTower</type>%s<color>%s</color>%s</building>" % [
				_id(at), _dword(at + 20), "<hidden/>" if _bytes[at + 24] != 0 else "", color, _place(at + 4)])
		_out.append("</buildings><heroes>")
		var index := 0
		for hero: Array in _all(_field(player, 7), 1):
			_hero(hero, index)
			index += 1
		_out.append("</heroes><diplomacy>")
		var diplomacy := _field(player, 5)
		var rows := _field(diplomacy, 2)
		for i in _count(diplomacy):
			var at := _record(rows, i, 8)
			if at < 0: break
			_out.append("<opponent id=\"%d\" relations=\"%d\"/>" % [_dword(at), _bytes[at + 4]])
		_out.append("</diplomacy></player>")
	_out.append("</players>")

## A hero record: permanent id, x, y, rotation, the monster flag; then its name.
func _hero(hero: Array, index: int) -> void:
	var record := _field(hero, 1)
	if record.is_empty() or record[2] - record[1] < 17:
		_fail("Malformed hero record.")
		return
	var at: int = record[1]
	_out.append("<hero id=\"%d\" permanent_id=\"%d\"><name>%s</name>%s%s</hero>" % [
		index, _id(at), _text(_field(hero, 2)), _place(at + 4), "<monster/>" if _bytes[at + 16] != 0 else ""])

# --- Map objects ------------------------------------------------------------

## Mines: permanent id, level, x, y, rotation, shadow flag; name; resources.
func _mines(section: Array) -> void:
	_out.append("<mines>")
	var index := 0
	for mine: Array in _all(section, 1):
		var at := _fixed(_field(mine, 1), 21)
		if at < 0: return
		_out.append("<mine id=\"%d\" permanent_id=\"%d\">%s<name>%s</name><level>%d</level><resources>" % [
			index, _id(at), _place(at + 8), _text(_field(mine, 2)), _dword(at + 4)])
		var resources := _field(mine, 3)
		var rows := _field(resources, 2)
		for i in _count(resources):
			var row := _record(rows, i, 8)
			if row < 0: break
			_out.append("<resource type=\"%s\" amount=\"%d\"/>" % [_resource(_dword(row)), _dword(row + 4)])
		_out.append("</resources>%s</mine>" % ("<noshadow/>" if _bytes[at + 20] == 0 else ""))
		index += 1
	_out.append("</mines>")

func _cuts(section: Array) -> void:
	_out.append("<resource_cuts>")
	var index := 0
	for cut: Array in _all(section, 1):
		var at := _fixed(_field(cut, 1), 16)
		if at < 0: return
		_out.append("<cut id=\"%d\" permanent_id=\"%d\">%s<name>%s</name><resources>" % [index, _id(at), _place(at + 4), _text(_field(cut, 2))])
		for resource: Array in _all(_field(cut, 3), 1):
			_out.append("<resource type=\"%s\" amount=\"%d\"/>" % [_text(_field(resource, 1)), _int(_field(resource, 2))])
		_out.append("</resources></cut>")
		index += 1
	_out.append("</resource_cuts>")

## Laboratories: permanent id, level, x, y, rotation; name; one spell list
## per level.
func _laboratories(section: Array) -> void:
	_out.append("<laboratories>")
	var index := 0
	for lab: Array in _all(section, 1):
		var at := _fixed(_field(lab, 1), 20)
		if at < 0: return
		_out.append("<laboratory id=\"%d\" permanent_id=\"%d\">%s<name>%s</name><level>%d</level>" % [
			index, _id(at), _place(at + 8), _text(_field(lab, 2)), _dword(at + 4)])
		var level := 1
		for list: Array in _all(_field(lab, 3), 1):
			var spells := _all(list, 1)
			if not spells.is_empty():
				_out.append("<spells level=\"%d\">" % level)
				for spell: Array in spells: _out.append("<spell>%s</spell>" % _text(spell))
				_out.append("</spells>")
			level += 1
		_out.append("</laboratory>")
		index += 1
	_out.append("</laboratories>")

func _artefacts(section: Array) -> void:
	_out.append("<artefacts>")
	var index := 0
	for item: Array in _all(section, 1):
		var at := _fixed(_field(item, 1), 16)
		if at < 0: return
		_out.append("<artefact id=\"%d\" permanent_id=\"%d\">%s<name>%s</name></artefact>" % [index, _id(at), _place(at + 4), _text(_field(item, 2))])
		index += 1
	_out.append("</artefacts>")

## Forts: permanent id, colour, index, upgrade level, x, y, rotation.
func _forts(section: Array) -> void:
	_out.append("<forts>")
	var rows := _field(section, 2)
	for i in _count(section):
		var at := _record(rows, i, 28)
		if at < 0: break
		_out.append("<fort id=\"%d\" permanent_id=\"%d\">%s<color>%s</color><upgrade level=\"%d\"/></fort>" % [
			i, _id(at), _place(at + 16), _color(_dword(at + 4)), _dword(at + 12)])
	_out.append("</forts>")

## Terrain objects: a template name table, each object's index into it, and
## records of permanent id, x, y, rotation (20 bytes).
func _terrain_objects(section: Array) -> void:
	_out.append("<terrain_objects>")
	var names: Array[String] = []
	for name: Array in _all(_field(section, 1), 1): names.append(_text(name))
	var indexes := _field(_field(section, 2), 2)
	var records := _field(section, 3)
	var rows := _field(records, 2)
	for i in _count(records):
		var at := _record(rows, i, 20)
		var slot := _record(indexes, i, 4)
		if at < 0 or slot < 0: break
		var template := _dword(slot)
		_out.append("<object permanent_id=\"%d\">%s<template>%s</template></object>" % [
			_id(at), _place(at + 4), names[template] if template >= 0 and template < names.size() else ""])
	_out.append("</terrain_objects>")

## Creatures by difficulty: a spell-code table, then one record each: name,
## shape, specialization, difficulty, level, health, skills, deck (code index
## and components), hero flag, loot, battle script, AP, name text key.
func _mobs(section: Array) -> void:
	_out.append("<mdm_mobs>")
	var codes: Array[String] = []
	for code: Array in _all(_field(section, 1), 1): codes.append(_text(code))
	for mob: Array in _all(_field(section, 2), 1):
		var hero := _field(mob, 9)
		_out.append("<mdm_mob Name=\"%s\" ElkName=\"%s\" DifLvl=\"%d\" Lvl=\"%d\" IsHero=\"%d\" AP=\"%d\" Hp=\"%d\" Spec=\"%s\" Script=\"%s\" shape=\"%s\"><skills>" % [
			_text(_field(mob, 1)), _text(_field(mob, 13)), _int(_field(mob, 4)), _int(_field(mob, 5)),
			1 if not hero.is_empty() and hero[2] > hero[1] and _bytes[hero[1]] != 0 else 0,
			_int(_field(mob, 12)), _int(_field(mob, 6)), _text(_field(mob, 3)), _text(_field(mob, 11)), _text(_field(mob, 2))])
		for skill: Array in _all(_field(mob, 7), 1):
			_out.append("<skill type=\"%s\" level=\"%d\"/>" % [_text(_field(skill, 1)), _int(_field(skill, 2))])
		_out.append("</skills><deck>")
		for card: Array in _all(_field(_field(mob, 8), 1), 1):
			var at := _fixed(_field(card, 1), 8)
			if at < 0: return
			var code := _dword(at)
			_out.append("<spell code=\"%s\" components=\"%d\"/>" % [codes[code] if code >= 0 and code < codes.size() else "", _dword(at + 4)])
		_out.append("</deck><loot/></mdm_mob>")
	_out.append("</mdm_mobs>")

## Additional buildings: permanent id, x, y, rotation; type; parameters.
func _buildings(section: Array) -> void:
	_out.append("<additional_buildings>")
	var index := 0
	for building: Array in _all(section, 1):
		var at := _fixed(_field(building, 1), 16)
		if at < 0: return
		var params := _text(_field(building, 3))
		_out.append("<building id=\"%d\" permanent_id=\"%d\"><type>%s</type>%s%s</building>" % [
			index, _id(at), _text(_field(building, 2)), ("<params>%s</params>" % params) if not params.is_empty() else "", _place(at + 4)])
		index += 1
	_out.append("</additional_buildings>")

# --- Grids --------------------------------------------------------------------

func _grids(section: Array) -> bool:
	var width := _int(_field(section, 1))
	var height := _int(_field(section, 2))
	if width < 1 or height < 1 or width > 512 or height > 512:
		_fail("Invalid map dimensions.")
		return false
	var tiles := _runs(_field(_field(section, 3), 3), (width + 1) * (height + 1))
	var roads := _dword_runs(_field(_field(section, 4), 3), width * height)
	var creeks := _dword_runs(_field(_field(section, 5), 3), width * height)
	var packed := _runs(_field(_field(_field(section, 6), 2), 3), (width * height + 3) / 4)
	if not error.is_empty(): return false
	var zone := PackedByteArray()
	zone.resize(width * height)
	for i in zone.size(): zone[i] = (packed[i >> 2] >> ((i & 3) * 2)) & 3
	_out.append("<map><size x=\"%d\" y=\"%d\"/>" % [width, height])
	_rows("tiles", tiles, width + 1, height + 1)
	_rows("roads", roads, width, height)
	_rows("creeks", creeks, width, height)
	_rows("clrless", zone, width, height)
	_out.append("</map>")
	return true

## Each <row> holds one X column of `rows` values, as the scenario stores them.
func _rows(name: String, values: PackedByteArray, columns: int, rows: int) -> void:
	_out.append("<%s>" % name)
	for x in columns: _out.append("<row>" + values.slice(x * rows, (x + 1) * rows).hex_encode().to_upper() + "</row>")
	_out.append("</%s>" % name)

## Byte runs, exactly `size` bytes (missing data is an error).
func _runs(node: Array, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	if node.is_empty() or size > MAX_CELLS:
		_fail("Missing terrain grid.")
		return out
	out.resize(size)
	var at: int = node[1]
	var end: int = node[2]
	var written := 0
	while at + 3 <= end and written < size:
		var head := (_bytes[at] << 16) | (_bytes[at + 1] << 8) | _bytes[at + 2]
		at += 3
		var count := mini(head & (LITERAL - 1), size - written)
		if head & LITERAL:
			if at + count > end: break
			for i in count: out[written + i] = _bytes[at + i]
			at += head & (LITERAL - 1)
		else:
			if at >= end: break
			_fill(out, written, count, _bytes[at])
			at += 1
		written += count
	if written != size: _fail("Damaged terrain grid.")
	return out

## Dword runs (little-endian header and values), the low byte of each kept.
func _dword_runs(node: Array, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	if node.is_empty() or size > MAX_CELLS:
		_fail("Missing terrain grid.")
		return out
	out.resize(size)
	var at: int = node[1]
	var end: int = node[2]
	var written := 0
	while at + 4 <= end and written < size:
		var head := _bytes.decode_u32(at)
		at += 4
		var count := mini(head & (LITERAL - 1), size - written)
		if head & LITERAL:
			if at + count * 4 > end: break
			for i in count: out[written + i] = _bytes[at + i * 4]
			at += (head & (LITERAL - 1)) * 4
		else:
			if at + 4 > end: break
			_fill(out, written, count, _bytes[at])
			at += 4
		written += count
	if written != size: _fail("Damaged terrain grid.")
	return out

static func _fill(out: PackedByteArray, from: int, count: int, value: int) -> void:
	for i in count: out[from + i] = value

# --- Fields -----------------------------------------------------------------

## Child fields [tag, start, end] of a node, [] for a leaf or malformed data.
func _kids(node: Array) -> Array:
	if node.is_empty(): return []
	return ELSingleScenario.binary_children(_bytes, node[1], node[2])

func _field(node: Array, tag: int) -> Array:
	for child: Array in _kids(node):
		if child[0] == tag: return child
	return []

func _all(node: Array, tag: int) -> Array:
	var result: Array = []
	for child: Array in _kids(node):
		if child[0] == tag: result.append(child)
	return result

func _int(node: Array) -> int:
	if node.is_empty() or node[2] - node[1] < 4: return 0
	return _bytes.decode_s32(node[1])

func _dword(at: int) -> int:
	return _bytes.decode_s32(at)

## The section's element count (field 1).
func _count(node: Array) -> int:
	return maxi(0, _int(_field(node, 1)))

## Start of record i of the given size inside a data field, or -1.
func _record(node: Array, i: int, size: int) -> int:
	if node.is_empty(): return -1
	var at: int = node[1] + i * size
	return at if at + size <= node[2] else -1

## Start of a fixed-size record field, or -1 (and an error) when too short.
func _fixed(node: Array, size: int) -> int:
	if node.is_empty() or node[2] - node[1] < size:
		_fail("Malformed map record.")
		return -1
	return node[1]

## The scenario's permanent id of a record (stored one lower).
func _id(at: int) -> int:
	var value := _dword(at) + 1
	_last_id = maxi(_last_id, value)
	return value

func _place(at: int) -> String:
	var rotation := _dword(at + 8)
	return "<place x=\"%d\" y=\"%d\"%s/>" % [_dword(at), _dword(at + 4), (" mr=\"%d\"" % rotation) if rotation != 0 else ""]

func _color(index: int) -> String:
	return COLORS[index] if index >= 0 and index < COLORS.size() else COLORS[0]

func _resource(index: int) -> String:
	return RESOURCES[index] if index >= 0 and index < RESOURCES.size() else RESOURCES[0]

## Windows-1251 text of a field, escaped for XML.
func _text(node: Array) -> String:
	if node.is_empty() or node[2] <= node[1]: return ""
	return ELBinaryMap.escape(ELText.ansi(_bytes.slice(node[1], node[2])))

static func escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
