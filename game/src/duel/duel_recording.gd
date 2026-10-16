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
## Set when this saves an original replay again (with its edited comments):
## it is written as .rpl, one file, keeping every other recorded byte.
var original: ELDuelReplay
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
	if original != null: return FileAccess.file_exists(directory(edition).path_join(name + ".rpl"))
	for file: String in file_names(name):
		if FileAccess.file_exists(directory(edition).path_join(file + EXTENSION)): return true
	return false

## Writes every round; "" or an error text.
func save(name: String) -> String:
	if clean_name(name) != name: return "Invalid replay name."
	if not complete(): return "This duel was not recorded from its start."
	var folder := directory(edition)
	if DirAccess.make_dir_recursive_absolute(folder) != OK and not DirAccess.dir_exists_absolute(folder): return "The replay folder cannot be created."
	if original != null:
		var bytes := original.encode(name)
		if bytes.is_empty(): return "The replay cannot be written."
		var out := FileAccess.open(folder.path_join(name + ".rpl"), FileAccess.WRITE)
		if out == null: return "The replay cannot be written."
		out.store_buffer(bytes)
		out.close()
		return ""
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
		# A comment written in the replay editor.
		if action.has("note") and action.note is not String: return {}
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

## The original's own replays (.rpl, versions 4-7) in the game's Replays
## folder and in this edition's replay folder: {name, path, labels, faces,
## original}. Files that do not decode are left out, as the original's list
## skips unreadable headers.
static func list_original(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or profile.id != "el2": return result
	var paths: Array[String] = []
	for key: String in profile.files_under("Replays/"):
		if key.get_extension() == "rpl" and not key.trim_prefix("replays/").contains("/"): paths.append(profile.file(key))
	var folder := directory(profile.id)
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension().to_lower() == "rpl": paths.append(folder.path_join(file))
	for path: String in paths:
		var replay := ELDuelReplay.new()
		if path.is_empty() or not replay.decode(FileAccess.get_file_as_bytes(path)): continue
		var labels := original_labels(profile, replay)
		var faces: Array[int] = []
		for side in 2:
			var hero: Dictionary = replay.heroes[side ^ replay.local_side] if replay.local_side in [0, 1] else replay.heroes[side]
			faces.append(int(profile.table("HeroTemplates").get(String(hero.template), {}).get("Face", -1)))
		result.append({"name": original_name(replay, path), "path": path, "labels": labels, "faces": faces, "original": true})
	return result

## A replay's name: the recorded one, else its file name.
static func original_name(replay: ELDuelReplay, path: String) -> String:
	return replay.name.strip_edges() if not replay.name.strip_edges().is_empty() else path.get_file().get_basename()

## My hero, the enemy hero (local player first), then their templates.
static func original_labels(profile: ELProfile, replay: ELDuelReplay) -> Array[String]:
	var flip := replay.local_side if replay.local_side in [0, 1] else 0
	var result: Array[String] = ["", "", "", ""]
	for side in 2:
		var hero: Dictionary = replay.heroes[side ^ flip]
		var recorded := replay.labels[side ^ flip] if replay.labels.size() == 4 else ""
		result[side] = recorded if not recorded.is_empty() else String(hero.name)
		result[side + 2] = String(hero.template)
	return result

## Only the remake's replay folder is ever written to; files in the game's
## own folder stay untouched.
static func removable(path: String) -> bool:
	return path.begins_with("user://duel/") and (path.ends_with(EXTENSION) or path.get_extension().to_lower() == "rpl")

static func remove(path: String) -> bool:
	return removable(path) and DirAccess.remove_absolute(path) == OK
