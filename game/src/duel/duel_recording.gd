class_name ELDuelRecording
extends RefCounted
## Second-game Duel mode replays. The original records every round of a Duel
## mode match; at the end of the match the round-result panel offers "Save duel
## replay", which opens the ReplayScreen in save mode and writes one file per
## round (a match of several rounds adds _01, _02 ... to the name). Duel ->
## Replay lists the saved replays and plays one back.
##
## The remake records its own battles in an equivalent per-edition file: the
## round's start options and battle seed plus every action the rules accepted,
## in order. Playing it back (ELDuelReplayPlayer) starts the same battle and
## runs the same actions through the rules, so the battle unfolds as it was
## played. Files live in user://duel/<edition>/Replays/<name>.json.

const FORMAT := "etherlords-remake-duel-replay"
const VERSION := 1
const FOLDER := "Replays"
const EXTENSION := ".json"
## Characters T_MB_WRONG_REPLAY_NAME forbids (an empty name is refused too).
const FORBIDDEN := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", ".", "[", "]", ",", ";", "="]
const KINDS := ["cast", "artifact", "attack", "retreat", "block", "ability", "end_phase", "surrender"]
const MAX_NAME := 64

var edition := ""
## My hero name, enemy hero name, my hero template, enemy hero template.
var labels: Array[String] = ["", "", "", ""]
## Hero portrait (face) indices of the two sides.
var faces: Array[int] = [-1, -1]
## Per round: {seed, options, actions, winner, complete}.
var rounds: Array[Dictionary] = []
var _duel: WeakRef

## Starts recording a round of the match: the battle as started and its seed.
## The recording vets nothing; it only notes each accepted action.
func track(duel: ELDuel, seed_value: int) -> void:
	untrack()
	edition = duel.profile.id
	rounds.append({"seed": seed_value, "options": duel.setup.duplicate(true), "actions": [], "winner": -1, "complete": false})
	_duel = weakref(duel)
	if duel.gate == null: duel.gate = self

func tracking(duel: ELDuel) -> bool:
	return _duel != null and _duel.get_ref() == duel and duel.gate == self

func untrack() -> void:
	var duel: ELDuel = _duel.get_ref() if _duel != null else null
	if duel != null and duel.gate == self: duel.gate = null
	_duel = null

## ELDuel gate: every action may run; accepted ones are recorded.
func gate_check(target: ELDuel, _action: Dictionary) -> bool:
	return true

func gate_done(target: ELDuel, action: Dictionary, ok: bool) -> void:
	if not ok or rounds.is_empty() or not tracking(target): return
	rounds[-1].actions.append(action.duplicate(true))

## Surrender ends the round outside the duel's own actions.
func note_surrender(duel: ELDuel, side: int) -> void:
	if not rounds.is_empty() and tracking(duel): rounds[-1].actions.append({"kind": "surrender", "side": side})

## The round ended: complete when the same battle was tracked to its end (a
## round resumed from a saved game was not).
func finish_round(duel: ELDuel) -> void:
	if rounds.is_empty(): return
	rounds[-1].winner = duel.winner
	rounds[-1].complete = tracking(duel) and duel.phase == ELDuel.Phase.FINISHED
	untrack()

func complete() -> bool:
	return not rounds.is_empty() and rounds.all(func(r: Dictionary): return bool(r.complete))

# --- Files ----------------------------------------------------------------------

static func directory(edition_id: String) -> String:
	return "user://duel/%s/%s" % [edition_id, FOLDER]

## The trimmed name, or "" when it is empty or uses a forbidden character.
static func clean_name(value: String) -> String:
	var name := value.strip_edges()
	if name.is_empty() or name.length() > MAX_NAME: return ""
	for character: String in FORBIDDEN:
		if name.contains(character): return ""
	for index in name.length():
		if name.unicode_at(index) < 32: return ""
	return name

## File names a save writes: the name itself, or name_01.. for several rounds.
func file_names(name: String) -> Array[String]:
	var result: Array[String] = []
	if rounds.size() == 1: result.append(name)
	else:
		for index in rounds.size(): result.append("%s_%02d" % [name, index + 1])
	return result

func exists(name: String) -> bool:
	for file: String in file_names(name):
		if FileAccess.file_exists(directory(edition).path_join(file + EXTENSION)): return true
	return false

## Writes every round; "" or an error text.
func save(name: String) -> String:
	if clean_name(name) != name: return "Invalid replay name."
	if not complete(): return "This duel was not recorded from its start."
	var folder := directory(edition)
	if DirAccess.make_dir_recursive_absolute(folder) != OK and not DirAccess.dir_exists_absolute(folder): return "The replay folder cannot be created."
	var names := file_names(name)
	for index in rounds.size():
		var round: Dictionary = rounds[index]
		var data := {"format": FORMAT, "version": VERSION, "edition": edition, "name": names[index], "labels": labels.duplicate(),
			"faces": faces.duplicate(), "round": index + 1, "rounds": rounds.size(), "seed": int(round.seed),
			"options": round.options, "actions": round.actions, "winner": int(round.winner)}
		var file := FileAccess.open(folder.path_join(names[index] + EXTENSION), FileAccess.WRITE)
		if file == null: return "The replay cannot be written."
		file.store_string(JSON.stringify(JSON.from_native(data)))
		file.close()
	return ""

## A replay file's contents (typed values restored), or {} when it is not a
## valid replay of this edition.
static func read(path: String, edition_id: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	# Files are written with JSON.from_native (typed values); anything else is not a replay.
	if parsed is not Dictionary or parsed.get("type") != "Dictionary": return {}
	var data: Variant = JSON.to_native(parsed)
	if data is not Dictionary or data.get("format") != FORMAT or data.get("version") != VERSION or data.get("edition") != edition_id: return {}
	if data.get("options") is not Dictionary or data.get("actions") is not Array or data.get("seed") is not int: return {}
	if data.get("labels") is not Array or data.labels.size() != 4 or data.get("faces") is not Array or data.faces.size() != 2: return {}
	for action: Variant in data.actions:
		if action is not Dictionary or not KINDS.has(action.get("kind")) or action.get("side") not in [0, 1]: return {}
	return data

## Saved replays of an edition: {name, path, labels, faces}, by name.
static func list(edition_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var folder := directory(edition_id)
	if not DirAccess.dir_exists_absolute(folder): return result
	for file: String in DirAccess.get_files_at(folder):
		if not file.ends_with(EXTENSION): continue
		var path := folder.path_join(file)
		var data := read(path, edition_id)
		if data.is_empty(): continue
		result.append({"name": file.trim_suffix(EXTENSION), "path": path, "labels": data.labels, "faces": data.faces})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return result

static func remove(path: String) -> bool:
	return path.begins_with("user://duel/") and path.ends_with(EXTENSION) and DirAccess.remove_absolute(path) == OK
