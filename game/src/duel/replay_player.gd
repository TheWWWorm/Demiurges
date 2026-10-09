class_name ELDuelReplayPlayer
extends RefCounted
## Plays back a saved Duel mode replay (ELDuelRecording file): the battle is
## started from the recorded options and seed, and the recorded actions run
## one at a time through the rules. Nothing else may act on the battle while
## it plays. The controls follow the original replay player (TutPlayer panel):
## Play/Pause, Rewind (back to the start, paused), Pause at comment, and in
## editor mode Next command / Next phase / Next turn, which play until that
## point and pause. If the rules refuse a recorded action, playback stops and
## `error` names it; nothing is substituted.

signal changed
signal diverged(message: String)

const NONE := 0
const COMMAND := 1
const PHASE := 2
const TURN := 3

var profile: ELProfile
var data: Dictionary = {}
var path := ""
var duel: ELDuel
var index := 0
var error := ""
var playing := false
## Pause at comment: recorded notes stop playback (remake recordings carry none).
var pause_at_comment := false
## The pending step of editor mode (COMMAND, PHASE or TURN), or NONE.
var step_mode := NONE
var _running := false
var _turn := 0

func load_file(source: ELProfile, file: String) -> bool:
	profile = source
	path = file
	data = ELDuelRecording.read(file, source.id)
	error = "" if not data.is_empty() else "Error loading replay"
	return error.is_empty()

## Starts (or restarts) the recorded battle in `target`, paused at the start.
func begin(target: ELDuel) -> bool:
	release()
	duel = target
	index = 0
	error = ""
	playing = false
	step_mode = NONE
	if not duel.start(profile, int(data.seed), data.options): return _fail(duel.error)
	duel.gate = self
	_turn = duel.turn_serial
	changed.emit()
	return true

func actions() -> Array:
	return data.get("actions", [])

func done() -> bool:
	return duel == null or index >= actions().size() or duel.phase == ELDuel.Phase.FINISHED

func title() -> String:
	return String(data.get("name", ""))

## TP_Play: play from here, or pause. Playing clears a pending step.
func set_playing(on: bool) -> void:
	playing = on and error.is_empty() and not done()
	if on: step_mode = NONE
	changed.emit()

## Editor-mode step buttons: play until the next command, phase or turn.
func play_step(mode: int) -> void:
	if not error.is_empty() or done(): return
	step_mode = mode
	_turn = duel.turn_serial
	playing = true
	changed.emit()

## Runs the next recorded action. Returns false at the end or on divergence.
func step() -> bool:
	if done() or not error.is_empty():
		playing = false
		changed.emit()
		return false
	var action: Dictionary = actions()[index]
	var ok := _apply(action)
	if not ok:
		playing = false
		_fail("Replay diverged at action %d (%s): %s" % [index, String(action.kind), duel.error if not duel.error.is_empty() else "it no longer applies"])
		diverged.emit(error)
		changed.emit()
		return false
	index += 1
	match step_mode:
		COMMAND: _pause()
		PHASE: if String(action.kind) == "end_phase": _pause()
		TURN: if duel.turn_serial != _turn: _pause()
	if pause_at_comment and action.get("note") is String and not String(action.note).is_empty(): _pause()
	if done(): playing = false
	changed.emit()
	return true

func _pause() -> void:
	playing = false
	step_mode = NONE

func _apply(action: Dictionary) -> bool:
	_running = true
	var ok := false
	var side := int(action.side)
	match String(action.kind):
		"end_phase": ok = duel.active_side() == side and duel.end_phase()
		"cast":
			var hand: Array = duel.heroes[side].hand
			var at := int(action.get("hand_index", -1))
			ok = duel.active_side() == side and at >= 0 and at < hand.size() and hand[at] == String(action.get("card", "")) \
				and duel.cast(at, int(action.get("target", -1)), int(action.get("grave", -1)), int(action.get("power", 0)))
		"artifact": ok = duel.use_artifact(side, int(action.index), int(action.get("target", -1)), int(action.get("choice", -1)))
		"attack", "retreat":
			var id := int(action.id)
			ok = duel.attacks.has(id) == (action.kind == "retreat") and duel.toggle_attack(id)
		"block": ok = duel.assign_block(int(action.id), int(action.target))
		"ability": ok = duel.use_ability(int(action.id), String(action.ability), int(action.get("target", -1)), int(action.get("enchantment", -1)), int(action.get("amount", -1)))
		"surrender":
			if duel.phase != ELDuel.Phase.FINISHED:
				duel.heroes[side].health = 0
				duel._check_winner()
				duel.changed.emit()
				ok = true
	_running = false
	return ok

## ELDuel gate: only the player's own recorded actions may run.
func gate_check(target: ELDuel, _action: Dictionary) -> bool:
	return target == duel and _running

func gate_done(_target: ELDuel, _action: Dictionary, _ok: bool) -> void:
	pass

func release() -> void:
	if duel != null and duel.gate == self: duel.gate = null
	playing = false

func _fail(message: String) -> bool:
	if error.is_empty(): error = message
	return false
