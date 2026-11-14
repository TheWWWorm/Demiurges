class_name ELPuzzles
extends RefCounted
## Battle puzzles (a remake addition). Each is a position out of a duel
## between computer players in which the first hero can force a win within
## a few of its own turns: found and checked by tools/duel_ai_puzzles.gd,
## chosen and ordered by tools/duel_puzzle_pack.gd. The player takes the
## first hero's side; the computer defends as well as it can.

const FOLDER := "res://puzzles/"
## Which puzzles the player has solved: {edition: {id: turns taken}}.
const SOLVED := "user://puzzles.json"

## Off for checks that play the puzzles through: what they solve is not
## written to the player's list.
static var remember := true
static var _lists: Dictionary = {}
static var _solved: Dictionary = {}
static var _solved_read := false

## The puzzles of one game, easiest first: [{id, turns, level, hint, state}].
static func list(edition: String) -> Array:
	if _lists.has(edition): return _lists[edition]
	var out: Array = []
	var path := FOLDER + edition + ".json"
	if FileAccess.file_exists(path):
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if document is Dictionary and document.get("format") == "etherlords-puzzles" and document.get("puzzles") is Array:
			for entry: Variant in document.puzzles:
				if entry is Dictionary and entry.get("id") is String and entry.get("state") is Dictionary and int(entry.get("turns", 0)) >= 1: out.append(entry)
	_lists[edition] = out
	return out

static func available(edition: String) -> bool:
	return not list(edition).is_empty()

static func _read_solved() -> void:
	if _solved_read: return
	_solved_read = true
	if not FileAccess.file_exists(SOLVED): return
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOLVED))
	if document is Dictionary:
		for edition: Variant in document:
			if document[edition] is Dictionary: _solved[str(edition)] = document[edition]

## Own turns the player took to solve `id`, or 0 while it is unsolved.
static func solved_in(edition: String, id: String) -> int:
	_read_solved()
	return int(_solved.get(edition, {}).get(id, 0))

static func solved_count(edition: String) -> int:
	var count := 0
	for entry: Dictionary in list(edition):
		if solved_in(edition, String(entry.id)) > 0: count += 1
	return count

## Remembers a solved puzzle (the fewest turns it was solved in).
static func mark(edition: String, id: String, turns: int) -> void:
	_read_solved()
	var before := solved_in(edition, id)
	if before > 0 and before <= turns: return
	if not _solved.has(edition): _solved[edition] = {}
	_solved[edition][id] = maxi(turns, 1)
	if not remember: return
	var file := FileAccess.open(SOLVED, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_solved, "\t"))

## The first puzzle not solved yet (the last one when all are).
static func next_unsolved(edition: String) -> int:
	var entries := list(edition)
	for i in entries.size():
		if solved_in(edition, String(entries[i].id)) == 0: return i
	return maxi(entries.size() - 1, 0)

## One attempt at a puzzle: the duel it is played in and how it stands.
class Run:
	extends RefCounted
	const SIDE := 0
	var edition := ""
	var index := 0
	var entry: Dictionary = {}
	var duel: ELDuel
	## Own turns the puzzle allows, and the one the player is in.
	var allowed := 0
	var turn := 1
	## "" while it is played, then "solved" or "failed".
	var outcome := ""
	## Why it failed: "turns" (out of turns) or "lost".
	var reason := ""
	var error := ""
	## The hero's own count of turns when the puzzle began, and whether the
	## first of them was already under way.
	var _begun := 0
	var _first := 0

	## Sets the position up as a duel of its own.
	func begin(profile: ELProfile, at: int) -> bool:
		var entries := ELPuzzles.list(profile.id)
		if at < 0 or at >= entries.size():
			error = "No such puzzle."
			return false
		edition = profile.id
		index = at
		entry = entries[at]
		allowed = int(entry.turns)
		duel = ELDuel.new()
		if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": (entry.state as Dictionary).duplicate(true)}):
			error = duel.error
			return false
		# A battlefield of its own for each puzzle, the same on every attempt.
		var arenas := ELDuelMatch.arenas(profile)
		if not duel.setup.has("arena") and not arenas.is_empty(): duel.setup["arena"] = arenas[absi(hash(String(entry.id))) % arenas.size()]
		_first = 1 if duel.attacker == SIDE else 0
		_begun = int(duel.heroes[SIDE].turns)
		turn = _first
		outcome = ""
		reason = ""
		return true

	## Follows the duel; true when the attempt has just ended.
	func watch() -> bool:
		if duel == null or not outcome.is_empty(): return false
		# The duel keeps the count of the hero's own turns, so none is missed
		# however much happened since this was last asked.
		turn = _first + int(duel.heroes[SIDE].turns) - _begun
		if turn > allowed:
			turn = allowed
			outcome = "failed"
			reason = "turns"
			return true
		if duel.phase == ELDuel.Phase.FINISHED:
			outcome = "solved" if duel.winner == SIDE else "failed"
			if outcome == "failed": reason = "lost"
			else: ELPuzzles.mark(edition, String(entry.id), maxi(turn, 1))
			return true
		return false

	## The first command of a line that wins, in the player's words.
	func hint() -> String:
		var step: Dictionary = entry.get("hint", {})
		var card := String(step.get("card", ""))
		var name := duel.card_name(card) if duel != null and not card.is_empty() else ""
		var onto := ""
		if step.has("target"): onto = duel.card_name(String(step.target))
		match String(step.get("kind", "")):
			"cast":
				if not onto.is_empty(): return "Start by casting %s on %s." % [name, onto]
				if step.has("target_hero"): return ("Start by casting %s on the enemy hero." if int(step.target_hero) != SIDE else "Start by casting %s on your hero.") % name
				return "Start by casting %s." % name
			"attack": return "Start by attacking with %s." % name
			"ability":
				if String(step.get("key", "")).begins_with("artifact"): return "Start with an artifact."
				return "Start with the ability of %s." % name if not name.is_empty() else "Start with your hero's ability."
			"end_phase": return "Start by ending the phase without attacking."
		return "No hint for this puzzle."
