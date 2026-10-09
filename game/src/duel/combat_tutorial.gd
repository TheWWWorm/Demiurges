class_name ELCombatTutorial
extends RefCounted
## Second-game combat tutorial (Tutorial screen → Combat). The original plays
## the replay Tutorial\Combat\combat_tutorial.rpl in tutorial mode: the battle
## is set up from the replay and seeded with its seed; the computer side replays
## its recorded commands, and the local player must perform exactly the next
## recorded command; any other action is ignored. Each command's note is the
## tutorial text shown while that command is awaited ("#d" preselects the
## spell to cast).
##
## The remake keeps the local player on side 0, so a replay recorded with the
## local player on side 1 is mirrored: remake side = original side XOR `flip`.
## Hero ids follow their side; creature, card and enchantment ids are the
## battle's own serials and match unchanged while the battle stays identical.
## If the rules ever diverge from the recording (a recorded action the engine
## refuses or that cannot be mapped), playback stops at that command and
## `error` names it; nothing is substituted.

signal note_changed
signal diverged(message: String)

const PATH := "Tutorial/Combat/combat_tutorial.rpl"
const COLOURS := ["Red", "Green", "Blue", "Black", "White"]
## The original renames the recorded heroes.
const HERO_TEXTS := {"Vitals": "T_COMBAT_TUTORIAL_VITALS_HERO_NAME", "Chaots": "T_COMBAT_TUTORIAL_CHAOTS_HERO_NAME"}
const QUIT_TEXT := "T_COMBAT_TUTORIAL_QUIT"

var profile: ELProfile
var replay: ELDuelReplay
var duel: ELDuel
var flip := 0
## Index of the next recorded command.
var index := 0
var error := ""
## Commands accepted so far, in order: {index, kind, side, by}.
var accepted: Array[Dictionary] = []

func load_from(data: ELProfile, path := PATH) -> bool:
	profile = data
	error = ""
	var file := data.file(path)
	if file.is_empty(): return _fail("The combat tutorial replay is missing: " + path)
	replay = ELDuelReplay.new()
	if not replay.decode(FileAccess.get_file_as_bytes(file)): return _fail(replay.error)
	if replay.local_side not in [0, 1]: return _fail("Invalid local side in the replay.")
	flip = replay.local_side
	return true

## Remake side of an original side or hero id.
func side_of(original: int) -> int:
	return original ^ flip

## An original entity id (heroes 0/1, creatures from 2) in remake terms.
func entity_of(original: int) -> int:
	return original ^ flip if original in [0, 1] else original

func hero_title(original_side: int) -> String:
	var recorded := String(replay.heroes[original_side].name)
	var key := String(HERO_TEXTS.get(recorded, ""))
	return profile.text(key) if not key.is_empty() and not profile.text(key).is_empty() else recorded

## Start options for ELDuel.start: the recorded heroes (template, colour,
## level, specialisation, skills, artifacts, deck), the arena, Providence
## charges (every EL2 battle refills them), the opening order and the
## first side from the seed (seed % 2 in a duel).
func start_options() -> Dictionary:
	var players: Array = []
	for side in 2:
		var hero: Dictionary = replay.heroes[side ^ flip]
		var artifacts: Array = []
		for item: Variant in hero.artifacts: artifacts.append({"name": str(item)})
		players.append({"faction": COLOURS[clampi(int(hero.colour), 0, 4)], "hero": hero.template, "cards": hero.deck.duplicate(),
			"level": int(hero.level), "skills": hero.skills.duplicate(), "specialization": hero.specialization,
			"artifacts": artifacts, "title": hero_title(side ^ flip)})
	return {"players": players, "arena": replay.arena, "adventure": true, "first_side": side_of(replay.seed_value & 1),
		"opening_interleave": side_of(0), "card_ids": true, "combat_tutorial": true}

func begin(target: ELDuel) -> bool:
	duel = target
	index = 0
	accepted.clear()
	if not duel.start(profile, replay.seed_value, start_options()): return _fail(duel.error)
	duel.gate = self
	note_changed.emit()
	return true

func current() -> Dictionary:
	return replay.commands[index] if replay != null and index < replay.commands.size() else {}

func done() -> bool:
	return replay != null and index >= replay.commands.size()

## True while the next command belongs to the computer side.
func opponent_due() -> bool:
	var c := current()
	return not c.is_empty() and error.is_empty() and side_of(int(c.side)) != 0

## The tutorial text for the awaited command ("" for none or a blank note).
func note_text() -> String:
	var c := current()
	if c.is_empty() or c.note == null: return ""
	var text := String(c.note.text)
	if text.length() >= 2 and text[0] == "#": text = text.substr(2)
	var shown := profile.text(text)
	return (shown if not shown.is_empty() else text).strip_edges()

## The hand slot named by "#d" (0..5, counted from the newest card), or -1.
func note_slot() -> int:
	var c := current()
	if c.is_empty() or c.note == null: return -1
	var text := String(c.note.text)
	if text.length() < 2 or text[0] != "#": return -1
	var digit := text.unicode_at(1) - 48
	return digit if digit >= 0 and digit < 6 else -1

## Hand index of the spell the note preselects, or -1.
func preselected_index() -> int:
	var c := current()
	if c.is_empty() or c.kind != "cast" or note_slot() < 0: return -1
	return (duel.heroes[side_of(int(c.side))].hand_ids as Array).find(int(c.id))

## Runs the next computer command through the rules. Returns false when none
## is due or the rules refused it (then `error` holds the divergence).
func step_opponent() -> bool:
	if not opponent_due(): return false
	return run_current()

## Executes the awaited command through the duel's public actions (also used
## by checks to stand in for the player's input).
func run_current() -> bool:
	var c := current()
	if c.is_empty() or not error.is_empty(): return false
	var at := index
	var ok := false
	var side := side_of(int(c.side))
	match String(c.kind):
		"next_phase": ok = duel.end_phase()
		"attack", "retreat":
			if duel.attacks.has(int(c.id)) == (c.kind == "attack"):
				# The original's attack handler leaves a creature that
				# is already assigned untouched; the recording keeps such repeats.
				_advance(side)
				return true
			ok = duel.toggle_attack(int(c.id))
		"block": ok = duel.assign_block(int(c.id), int(c.target))
		"cast":
			var hand := (duel.heroes[side].hand_ids as Array).find(int(c.id))
			if hand < 0: return _diverge(at, "card %d is not in the hand" % int(c.id))
			var call := _cast_arguments(duel.heroes[side].hand[hand], c.targets)
			if call.is_empty(): return _diverge(at, "unmapped cast targets %s" % str(c.targets))
			ok = duel.cast(hand, call.target, call.grave, call.power)
		"artifact":
			var targets: Array = c.targets
			if targets.size() != 1: return _diverge(at, "unmapped artifact targets %s" % str(targets))
			var holder := duel.find_enchantment(int(targets[0]))
			ok = duel.use_artifact(side, int(c.id), holder, int(targets[0]))
		"ability":
			var listed := duel.abilities(int(c.id)) if duel.creatures.has(int(c.id)) else []
			if int(c.ability) < 0 or int(c.ability) >= listed.size(): return _diverge(at, "creature %d has no ability %d" % [int(c.id), int(c.ability)])
			var targets: Array = c.targets
			ok = duel.use_ability(int(c.id), String(listed[int(c.ability)].key), entity_of(int(targets[0])) if targets.size() == 1 else -1)
		_:
			return _diverge(at, "unsupported command " + String(c.kind))
	if not ok and error.is_empty(): return _diverge(at, "the rules refused it: " + duel.error)
	return ok and error.is_empty()

## Remake cast arguments for a recorded target list: a variable spell's X, or
## one creature/hero target. Other shapes are not used by the shipped replay.
func _cast_arguments(card: String, targets: Array) -> Dictionary:
	if duel.variable_power(card):
		if targets.size() == 1 and duel.target_kind(card) == "none": return {"target": -1, "grave": -1, "power": int(targets[0])}
		return {}
	if targets.is_empty(): return {"target": -1, "grave": -1, "power": 0}
	if targets.size() == 1 and duel.target_kind(card) != "none": return {"target": entity_of(int(targets[0])), "grave": -1, "power": 0}
	return {}

## ELDuel gate: only the awaited command may run. A cast of the same spell
## from the same charge group as the awaited card is the same click in the
## remake's grouped hand, so it is redirected to the awaited card.
func gate_check(target: ELDuel, action: Dictionary) -> bool:
	if target != duel or not error.is_empty(): return false
	var c := current()
	if c.is_empty(): return false
	if int(action.get("side", -1)) != side_of(int(c.side)): return false
	var kind := String(action.kind)
	if kind == "ability" and String(action.get("ability", "")).begins_with("artifact:"):
		action = {"kind": "artifact", "side": action.side, "index": int(String(action.ability).get_slice(":", 1)), "target": action.target, "choice": action.enchantment}
		kind = "artifact"
	match String(c.kind):
		"next_phase": return kind == "end_phase"
		"attack", "retreat":
			if int(action.id) != int(c.id): return false
			if kind != c.kind and duel.attacks.has(int(c.id)) == (c.kind == "attack"):
				# Clicking a creature already in the recorded state: the original's
				# separate Attack/Retreat commands leave it unchanged.
				_advance(int(action.side))
				return false
			return kind == c.kind
		"block": return kind == "block" and int(action.id) == int(c.id) and int(action.target) == int(c.target)
		"cast":
			if kind != "cast": return false
			var side := side_of(int(c.side))
			var hero: Dictionary = duel.heroes[side]
			var wanted := (hero.hand_ids as Array).find(int(c.id))
			var chosen := int(action.hand_index)
			if wanted < 0 or chosen < 0 or chosen >= hero.hand.size(): return false
			if chosen != wanted:
				if hero.hand[chosen] != hero.hand[wanted] or duel.hand_uses(side, chosen) != duel.hand_uses(side, wanted): return false
				action.hand_index = wanted
			var call := _cast_arguments(hero.hand[wanted], c.targets)
			return not call.is_empty() and int(action.target) == int(call.target) and int(action.grave) == int(call.grave) and int(action.power) == int(call.power)
		"artifact":
			var targets: Array = c.targets
			return kind == "artifact" and int(action.index) == int(c.id) and targets.size() == 1 and int(action.choice) == int(targets[0])
		"ability":
			var listed := duel.abilities(int(c.id)) if duel.creatures.has(int(c.id)) else []
			var targets: Array = c.targets
			if kind != "ability" or int(action.id) != int(c.id) or int(c.ability) >= listed.size(): return false
			return String(action.ability) == String(listed[int(c.ability)].key) and int(action.target) == (entity_of(int(targets[0])) if targets.size() == 1 else -1)
	return false

func gate_done(target: ELDuel, action: Dictionary, ok: bool) -> void:
	if target != duel: return
	if not ok:
		# A vetted, recorded action the rules refuse: the remake no longer matches.
		_diverge(index, "the rules refused it: " + duel.error)
		return
	_advance(int(action.side))

func _advance(side: int) -> void:
	accepted.append({"index": index, "kind": String(current().kind), "side": side})
	index += 1
	note_changed.emit()

func _diverge(at: int, reason: String) -> bool:
	if error.is_empty():
		var c: Dictionary = replay.commands[at] if at < replay.commands.size() else {}
		error = "Combat tutorial diverged at command %d (%s): %s" % [at, String(c.get("kind", "?")), reason]
		diverged.emit(error)
	return false

func _fail(message: String) -> bool:
	error = message
	return false
