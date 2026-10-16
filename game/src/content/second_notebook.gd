class_name ELSecondNotebook
extends RefCounted
## Second-game Notebook (CAdventureNotebook): a campaign-wide journal the engine
## fills itself. Scripts choose which dialogue lines are journaled through the
## notebook flag of the dialogue natives; won battles of the local player are
## journaled with the hero's health and level before and after. Entries are
## never edited inside a chapter; a chapter transition carries them over and
## clears their current-mission flag.
const PHRASE := "phrase"
const BATTLE := "battle"
## Filter values of the original: 0 untyped, 1 phrases, 2 battles, 3 all.
const FILTER_UNTYPED := 0
const FILTER_PHRASE := 1
const FILTER_BATTLE := 2
const FILTER_ALL := 3
const FILTER_TEXT := {0: "T_NOTEBOOK_FILTER_UNTYPED", 1: "T_NOTEBOOK_FILTER_PHRASE", 2: "T_NOTEBOOK_FILTER_BATTLE", 3: "T_NOTEBOOK_FILTER_ALL"}
## a phrase whose speaker is not a hero uses this name and face 0xcd.
const UNKNOWN_NAME := "T_UNKNOWN_HERO_NAME"
const UNKNOWN_FACE := 0xcd
const MAX_ENTRIES := 20000
const MAX_TEXT := 8192

static func applies(state: ELAdventureSession) -> bool:
	return state != null and state.map != null and state.map.profile.id == "el2"

## Lua boolean argument as the wrappers read it: nil is false, a
## number counts when its truncation is non-zero, anything else is true.
static func lua_flag(value: Variant) -> bool:
	if value == null: return false
	if value is float or value is int: return int(value) != 0
	if value is bool: return value
	return true

## Face id of a map hero (Shapes/HeroTemplates Face), regardless of whether it
## is currently shown; -1 when the art row has none.
static func face_of(state: ELAdventureSession, hero: Dictionary) -> int:
	if hero.is_empty() or not hero.has("node"): return -1
	var probe := hero.duplicate()
	probe.visible = true
	probe.erase("ship")
	var row: Dictionary = ELAdventureArt.new(state.map).resolve(probe).get("row", {})
	return int(row.get("Face", -1))

static func _hero(state: ELAdventureSession, id: Variant) -> Dictionary:
	if not (id is float or id is int): return {}
	var item := state.object(id)
	return item if not item.is_empty() and str(item.get("group", "")) in ["heroes", "np_heroes"] else {}

## The world point stored with an entry: the camera target, or in a session
## without a view the given hero's (else the main hero's) cell.
static func _point(state: ELAdventureSession, hero: Dictionary) -> Array:
	if state.view_point.x >= 0: return [state.view_point.x, state.view_point.y]
	var anchor := hero if not hero.is_empty() and int(hero.get("x", -1)) >= 0 else state.object(state.main_hero)
	if anchor.is_empty(): return [-1.0, -1.0]
	return [float(anchor.x) + 0.5, float(anchor.y) + 0.5]

static func _base(state: ELAdventureSession, kind: String, hero: Dictionary) -> Dictionary:
	var entry := {"id": state.notebook_next, "kind": kind, "day": state.day, "current": true, "mission": state.map.id, "point": _point(state, hero)}
	state.notebook_next += 1
	return entry

## A journaled phrase. `speaker` false: no name or face; true: the
## hero's name and face, or "Unknown" for a missing hero.
static func add_phrase(state: ELAdventureSession, text: Variant, speaker_id: Variant, speaker: bool) -> Dictionary:
	if not applies(state) or text == null: return {}
	var hero := _hero(state, speaker_id) if speaker else {}
	var entry := _base(state, PHRASE, hero)
	entry.text = str(text).left(MAX_TEXT)
	entry.speaker = ""
	entry.face = -1
	if speaker:
		if hero.is_empty():
			entry.speaker = state.map.profile.text(UNKNOWN_NAME)
			entry.face = UNKNOWN_FACE
		else:
			entry.speaker = str(hero.get("title", hero.get("name", "")))
			entry.face = face_of(state, hero)
	state.notebook.append(entry)
	state.event.emit({"kind": "notebook_entry", "id": entry.id, "entry": PHRASE})
	return entry

## A won battle of the local player. `before` holds the
## winner's health and level before the experience award.
static func add_battle(state: ELAdventureSession, winner: Dictionary, loser: Dictionary, before: Dictionary, experience: int, loot: Array = []) -> Dictionary:
	if not applies(state) or winner.is_empty() or loser.is_empty(): return {}
	var entry := _base(state, BATTLE, winner)
	entry.opponent = str(loser.get("title", loser.get("name", "")))
	entry.opponent_face = face_of(state, loser)
	entry.opponent_level = int(loser.get("level", 1))
	entry.opponent_life = int(loser.get("health", 0))
	entry.hero = str(winner.get("title", winner.get("name", "")))
	entry.life_before = int(before.get("health", winner.get("health", 0)))
	entry.life_after = int(winner.get("health", 0))
	entry.level_before = int(before.get("level", winner.get("level", 1)))
	entry.level_after = int(winner.get("level", 1))
	entry.experience = experience
	entry.loot = loot.duplicate(true)
	state.notebook.append(entry)
	state.event.emit({"kind": "notebook_entry", "id": entry.id, "entry": BATTLE})
	return entry

## Entries shown for a filter: all, or one kind; optionally only
## the current chapter's.
static func filtered(entries: Array, filter: int, current_only: bool) -> Array:
	var result: Array = []
	for entry: Dictionary in entries:
		if current_only and not entry.get("current", false): continue
		if filter != FILTER_ALL and entry.get("kind") != (PHRASE if filter == FILTER_PHRASE else BATTLE): continue
		result.append(entry)
	return result

## Chapter capture: a copy for the next chapter; the live entries
## lose their current-mission flag.
static func carry(state: ELAdventureSession) -> Array:
	var result: Array = []
	for entry: Dictionary in state.notebook:
		entry.current = false
		result.append(entry.duplicate(true))
	return result

## Chapter apply: the carried entries replace the new notebook.
static func apply(state: ELAdventureSession, raw: Variant) -> bool:
	var entries: Variant = decode(raw)
	if entries == null: return false
	for entry: Dictionary in entries: entry.current = false
	state.notebook = entries
	state.notebook_next = next_id(entries)
	return true

static func next_id(entries: Array) -> int:
	var result := 0
	for entry: Dictionary in entries: result = maxi(result, int(entry.id) + 1)
	return result

static func encode(state: ELAdventureSession) -> Array:
	return state.notebook.duplicate(true)

## Validated copy of saved entries with integer fields restored, or null.
static func decode(raw: Variant) -> Variant:
	if not raw is Array or raw.size() > MAX_ENTRIES: return null
	var result: Array = []
	for value: Variant in raw:
		if not value is Dictionary: return null
		var entry: Dictionary = value.duplicate(true)
		if not entry.get("kind") in [PHRASE, BATTLE] or not entry.get("current") is bool or not entry.get("mission") is String: return null
		if not _integer(entry.get("id"), 0, 0x7fffffff) or not _integer(entry.get("day"), 0, 0x7fffffff): return null
		var point: Variant = entry.get("point")
		if not point is Array or point.size() != 2 or not (point[0] is float or point[0] is int) or not (point[1] is float or point[1] is int): return null
		entry.point = [float(point[0]), float(point[1])]
		entry.id = int(entry.id)
		entry.day = int(entry.day)
		if entry.kind == PHRASE:
			if not entry.get("text") is String or not entry.get("speaker") is String or not _integer(entry.get("face"), -1, 0xffff): return null
			if entry.text.length() > MAX_TEXT: return null
			entry.face = int(entry.face)
		else:
			for key: String in ["opponent", "hero"]:
				if not entry.get(key) is String: return null
			for key: String in ["opponent_face", "opponent_level", "opponent_life", "life_before", "life_after", "level_before", "level_after", "experience"]:
				if not _integer(entry.get(key), -1, 10000000): return null
				entry[key] = int(entry[key])
			if not ELSecondLoot.valid(entry.get("loot")): return null
			entry.loot = entry.loot.map(func(item: Array) -> Array: return [str(item[0]), int(item[1])])
		result.append(entry)
	return result

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or (value is float and value == floorf(value))) and value >= low and value <= high
