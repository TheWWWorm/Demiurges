class_name ELSecondMapTooltips
extends RefCounted
## Second-game adventure-map hover tooltips: what the object under the cursor
## shows, when the panel appears and where it goes.
##
## Contract:
## - Only drawn objects can be picked. Fogged, hidden, removed and garrisoned
##   objects, terrain decoration and empty ground show nothing.
## - With hover tooltips on, the panel appears once the cursor (and the camera)
##   have rested over one object for a second, follows the cursor, and closes
##   after ten seconds; it then stays closed until the cursor reaches another
##   object. Holding the right button shows it at once, whatever the option
##   says, and releasing the button closes it. The wheel hides it and the
##   delay starts again.
## - Placement: 58 px right of the cursor, flipped above or moved below when it
##   would leave the screen, kept 20 px inside the edges.
## - Text keys without text show nothing (not the key); building text is shown
##   as authored, so a literal format code in it stays visible.

const DELAY := 1.0
const STAY := 10.0
## Updates while the camera moves (the original re-picks every 200 ms).
const CAMERA_INTERVAL := 0.2
## Cursor updates are throttled to ten a second.
const MOVE_INTERVAL := 0.1
const OFFSET := 58.0
const DROP := 60.0
const MARGIN := 20.0
## The frame lies this far outside the content on every side.
const FRAME := 10.0
## Pointer travel (px) after a right press before the press becomes a camera drag.
const DRAG_THRESHOLD := 6.0
const PANEL_TEXTURE := "Interface/black/ToolTip"
const PANEL_SOURCE := Rect2(196, 196, 60, 60)
const PANEL_BORDER := 5.0
const MAX_MOB_LEVEL := 20
const ICON_SIZE := Vector2(70, 50)
const PORTRAIT_SIZE := Vector2(100, 70)
const NO_SPECIALIZATION := "NONE"

static func applies(state: ELAdventureSession) -> bool:
	return state != null and state.map != null and state.map.profile.id == "el2"

## A text key's text; a missing key or one without text gives nothing.
static func text(profile: ELProfile, key: String) -> String:
	if key.is_empty() or not profile.texts.has(key): return ""
	return String(profile.texts[key]).strip_edges()

## C-style formatting of %d and %s in order; extra codes stay as written and
## extra values are ignored, as the original's sprintf would print them.
static func format(pattern: String, values: Array) -> String:
	var result := ""
	var index := 0
	var at := 0
	while at < pattern.length():
		var code := pattern.substr(at, 2)
		if code == "%%":
			result += "%"
			at += 2
		elif (code == "%d" or code == "%s") and index < values.size():
			result += str(int(values[index])) if code == "%d" else str(values[index])
			index += 1
			at += 2
		else:
			result += pattern[at]
			at += 1
	return result

## Whether the object is drawn for the local player and so can be picked.
static func pickable(state: ELAdventureSession, item: Dictionary) -> bool:
	if item.is_empty() or item.get("group") == "terrain_objects": return false
	var corpse: bool = item.get("type") == "corpse"
	if not (item.get("alive", false) or corpse) or not item.get("visible", false) or not item.get("placed", true) or item.get("fortified", false): return false
	var player := state.current_player
	return not ELFog.active(state, player) or ELFog.shown(state, player, item)

## The picked object at a map point (tile units): standing figures accept
## points slightly behind them and win over buildings, as they are drawn in
## front; buildings and pickups use their footprint.
static func object_at(state: ELAdventureSession, point: Vector2) -> int:
	var best := -1
	var distance := INF
	var building := -1
	var building_distance := INF
	for id: int in state.objects:
		var item: Dictionary = state.objects[id]
		if item.get("group") == "terrain_objects" or not pickable(state, item): continue
		if item.get("type") in ["hero", "monster"]:
			var offset := point - Vector2(float(item.x) + 0.5, float(item.y) + 0.5)
			if absf(offset.x) < 0.9 and offset.y > -0.9 and offset.y < 2.2 and offset.length() < distance:
				best = id
				distance = offset.length()
		elif best < 0:
			var size := Vector2i.ONE
			if item.get("type") != "corpse" and state.grid != null: size = state.grid.footprints.get(id, {}).get("size", Vector2i.ONE)
			var rect := Rect2(item.x, item.y, size.x, size.y)
			if rect.has_point(point) and point.distance_to(rect.get_center()) < building_distance:
				building = id
				building_distance = point.distance_to(rect.get_center())
	return best if best >= 0 else building

## Tooltip content: labels at content positions and an optional picture.
## `row` is the object's definition row (ELAdventureArt.resolve(item).row).
## An empty result shows nothing.
static func describe(state: ELAdventureSession, item: Dictionary, row: Dictionary) -> Dictionary:
	if not pickable(state, item): return {}
	var profile := state.map.profile
	var group := str(item.get("group", ""))
	if item.get("type") == "corpse":
		var corpse: Dictionary = profile.table("AdditionalBuildings").get("Corpse", {})
		if item.get("ship", false): return generic(text(profile, "T_SHIP_CORPSE_NAME"), text(profile, "T_SHIP_CORPSE_DESC"), -1)
		return generic(text(profile, str(corpse.get("ELKName", ""))), text(profile, str(corpse.get("ToolTip", ""))), int(corpse.get("Icon", -1)))
	if item.get("type") in ["hero", "monster"]: return _figure(state, item, row)
	match group:
		"additional_buildings": return _building(state, item)
		"buildings":
			# Castles and other main-map buildings: the colour's Buildings row.
			return generic(text(profile, str(row.get("Name", ""))), text(profile, str(row.get("ToolTip", ""))), int(row.get("Icon", -1)))
		"forts":
			return _fort(state, item, row)
		"laboratories", "factories":
			# Shop name and icon; the original also draws a symbol glyph (not ported).
			return _title_beside_icon(text(profile, str(row.get("ELKName", ""))), int(row.get("Icon", -1)))
		"mines":
			return _mine(state, item)
		"mana_nodes":
			var node := ELResourceSites.definition(profile, item)
			var amount := ELResourceSites.mana_production(item, str(state.players.get(state.current_player, {}).get("color", "")))
			return generic(text(profile, str(node.get("Name", ""))), format(text(profile, "T_MANA_NODE_TT"), [amount]), int(node.get("Icon", -1)))
		"resource_cuts":
			return _resources(state, item)
		"artefacts":
			return {"labels": [_label(text(profile, str(profile.table("Artefacts").get(str(item.name), {}).get("ELKName", ""))), Vector2.ZERO, true)], "picture": {}}
		"global_spells":
			return {"labels": [_label(text(profile, str(profile.table("GlobalSpellCut").get(str(item.name), {}).get("ELKName", ""))), Vector2.ZERO, true)], "picture": {}}
	return {}

## The common building layout: a 70x50 icon with the title beside it and the
## text below; without an icon the title is on top and the text under it.
static func generic(title: String, body: String, icon: int) -> Dictionary:
	var labels: Array = []
	var picture := {}
	if icon >= 0:
		picture = {"kind": "building", "index": icon, "at": Vector2.ZERO, "size": ICON_SIZE}
		labels.append(_label(title, Vector2(80, 34), true))
		if not body.is_empty(): labels.append(_label(body, Vector2(0, 60)))
	else:
		labels.append(_label(title, Vector2.ZERO, true))
		if not body.is_empty(): labels.append(_label(body, Vector2(0, 20)))
	return {"labels": labels, "picture": picture}

static func _title_beside_icon(title: String, icon: int) -> Dictionary:
	if icon < 0: return {"labels": [_label(title, Vector2.ZERO, true)], "picture": {}}
	return {"labels": [_label(title, Vector2(80, 18), true)], "picture": {"kind": "building", "index": icon, "at": Vector2.ZERO, "size": ICON_SIZE}}

static func _label(value: String, at: Vector2, title := false) -> Dictionary:
	return {"text": value, "at": at, "title": title}

static func _building(state: ELAdventureSession, item: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var row := ELSecondBuildings.definition(profile, item)
	if row.is_empty(): return {}
	var title := text(profile, str(row.get("ELKName", "")))
	var body := text(profile, str(row.get("ToolTip", "")))
	var icon := int(row.get("Icon", -1))
	match ELSecondBuildings.kind(item):
		"sign":
			var key := ELSecondBuildings.params(item)
			body = text(profile, key)
		"prison":
			# The prisoner's name fills the first %s; a cage without a known
			# prisoner shows an empty name.
			body = ELSecondBuildings.first_placeholder(body, ELSecondBuildings.prisoner_name(state, item))
	if ELSecondGates.is_gate(item) or ELSecondGates.is_warding(item):
		title = ELSecondBuildings.first_placeholder(title, ELSecondGates.key(item))
	return generic(title, body, icon)

## Heroes and creatures: portrait, then name, life and level beside it; the
## active specialization, if any, below. No owner line.
static func _figure(state: ELAdventureSession, item: Dictionary, row: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var level := int(item.get("level", 1))
	if item.get("type") == "monster": level = mini(level, MAX_MOB_LEVEL)
	var lines := "%s\n%s: %d\n%s: %d" % [str(item.get("title", item.get("name", ""))), text(profile, "T_LIFE"), int(item.get("health", 0)), text(profile, "T_LEVEL"), level]
	var labels: Array = [_label(lines, Vector2(115, 8))]
	var code := str(item.get("specialization", NO_SPECIALIZATION))
	var spec: Dictionary = profile.table("HeroesSpecs").get(code, {})
	if code != NO_SPECIALIZATION and not code.is_empty() and not spec.is_empty():
		labels.append(_label(text(profile, "T_TT_SPECIALIZATION_HDR") + " " + text(profile, str(spec.get("Name", ""))), Vector2(0, 80)))
		labels.append(_label(text(profile, str(spec.get("Desc", ""))), Vector2(0, 100)))
	var picture := {}
	if row.has("Face"): picture = {"kind": "portrait", "index": int(row.Face), "at": Vector2.ZERO, "size": PORTRAIT_SIZE}
	return {"labels": labels, "picture": picture}

static func _fort(state: ELAdventureSession, item: Dictionary, row: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var title := text(profile, str(row.get("Name", "")))
	var defender := state.object(int(item.get("garrison", -1)))
	if defender.is_empty(): return _title_beside_icon(title, int(row.get("Icon", -1)))
	# A defended fort introduces its hero (portrait, name, life and level).
	var art := ELAdventureArt.new(state.map)
	var face := _face_row(art, defender)
	var shown := _figure(state, defender, face)
	shown.labels.push_front(_label(format(text(profile, "T_FORT_TT"), [title]), Vector2.ZERO, true))
	for label: Dictionary in shown.labels.slice(1): label.at += Vector2(0, 20)
	if not shown.picture.is_empty(): shown.picture.at += Vector2(0, 20)
	return shown

## A ship hero is drawn as a boat; its portrait still comes from its shape.
static func _face_row(art: ELAdventureArt, actor: Dictionary) -> Dictionary:
	var source := actor.duplicate()
	source.ship = false
	return art.resolve(source).get("row", {})

## The definition row describe() expects for an object.
static func row_for(art: ELAdventureArt, item: Dictionary) -> Dictionary:
	if item.get("type") in ["hero", "monster"]: return _face_row(art, item)
	if item.get("type") == "corpse": return {}
	return art.resolve(item).get("row", {})

## Mines: icon centred on top, name, then the daily amount, resource and the
## payments left (the second game's mine text takes all three).
static func _mine(state: ELAdventureSession, item: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var row := ELResourceSites.definition(profile, item)
	var production := ELResourceSites.production(profile, item)
	var kind := ""
	for entry: Variant in (row.get("Production", []) if row.get("Production", []) is Array else [row.get("Production", "")]):
		kind = str(entry).get_slice("(", 0)
	if profile.id == "el2": kind = str(ELResources.SEQUEL_FIELDS.find_key(kind))
	var index := ELResources.types(profile.id).find(kind)
	var amount := int(production.get(kind, 0))
	var resource := text(profile, "T_RESOURCE_NAME_%d" % (index + 1)) if index >= 0 else ""
	var body := format(text(profile, "T_MINE_TT"), [amount, resource, int(item.get("mine_remaining", 0))])
	var icon := int(row.get("Icon", -1))
	var labels: Array = [_label(text(profile, str(row.get("ELKName", ""))), Vector2(0, 60), true), _label(body, Vector2(0, 80))]
	var picture := {"kind": "building", "index": icon, "at": Vector2.ZERO, "size": ICON_SIZE, "centre": true} if icon >= 0 else {}
	return {"labels": labels, "picture": picture}

static func _resources(state: ELAdventureSession, item: Dictionary) -> Dictionary:
	var profile := state.map.profile
	var amounts := ELResources.read_node(profile.id, ELXml.child(item.get("node", {}), "resources"))
	var body := text(profile, "T_PLUSHKA")
	var types := ELResources.types(profile.id)
	for index in types.size():
		var amount := int(amounts.get(types[index], 0))
		if amount > 0: body += "\n   %d %s" % [amount, text(profile, "T_RESOURCE_NAME_%d" % (index + 1))]
	return {"labels": [_label(body, Vector2.ZERO)], "picture": {}}

## Top-left of the frame (content inflated by FRAME) for a cursor position,
## in screen units. `content` is the content size.
static func place(content: Vector2, cursor: Vector2, screen: Vector2) -> Vector2:
	var limit := Rect2(Vector2(MARGIN, MARGIN), screen - Vector2(MARGIN, MARGIN) * 2.0)
	var frame := Rect2(cursor + Vector2(OFFSET, 0), content + Vector2(FRAME, FRAME) * 2.0)
	if frame.end.y > limit.end.y:
		frame.position += Vector2(-OFFSET, -frame.size.y)
		if frame.position.y < limit.position.y: frame.position.y = cursor.y
		if frame.end.x > limit.end.x: frame.position.x = limit.end.x - frame.size.x
	elif frame.end.x > limit.end.x:
		frame.position.y += DROP
		if frame.end.y > limit.end.y: frame.position += Vector2(-OFFSET, frame.position.y - frame.end.y - DROP)
		if frame.position.y < limit.position.y: frame.position.y = cursor.y
		frame.position.x = limit.end.x - frame.size.x
	if frame.position.x < limit.position.x: frame.position.x = limit.position.x
	return frame.position

## When the tooltip shows. Feed it the object under the cursor on every
## update (cursor move or moving camera) and every frame.
class Timing:
	extends RefCounted
	var subject := -1
	var shown := false
	var dismissed := false
	var held := false
	var hover := true
	var waited := 0.0
	var stayed := 0.0

	## `updated`: the cursor or camera moved this frame.
	func update(id: int, delta: float, updated: bool) -> void:
		if id != subject:
			subject = id
			waited = 0.0
			stayed = 0.0
			dismissed = false
			shown = held and id >= 0
			return
		if subject < 0:
			shown = false
			return
		if held:
			shown = true
			return
		if shown:
			stayed += delta
			if stayed >= STAY:
				shown = false
				dismissed = true
			return
		if updated: waited = 0.0
		else: waited += delta
		if hover and not dismissed and waited >= DELAY:
			shown = true
			stayed = 0.0

	## Right press: show the current object at once.
	func press() -> void:
		held = true
		shown = subject >= 0

	## Right release (or a press that became a camera drag): close until the
	## cursor reaches another object.
	func release() -> void:
		held = false
		close()

	func close() -> void:
		shown = false
		dismissed = subject >= 0

	## The wheel hides it and forgets the object, so the delay starts again.
	func clear() -> void:
		shown = false
		dismissed = false
		subject = -1
		waited = 0.0

	func reset() -> void:
		held = false
		shown = false
		dismissed = false
		subject = -1
		waited = 0.0
