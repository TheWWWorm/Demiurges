class_name ELStrategicBattleRelay
extends RefCounted
## Synchronizes one already-prepared campaign duel on the strategy connection.
## The host owns all unassigned sides and alone reports a confirmed result.

signal outbound(battle_id: int, payload: Array)
signal host_finished(battle_id: int, winner: int)
signal failed(reason: String)

const MAX_PENDING := ELNetworkDuel.MAX_PENDING
const MAX_ID := 0x7fffffff

var duel: ELDuel
var battle_id := 0
var local_side := -1
var remote_side := -1
var is_host := false
var error := ""
var sequence := 0
var _queue: Array[Array] = []
var _outstanding: Array = []
var _applying_side := -1
var _ai_side := -1
var _announced := false
var _phase_seconds := 0
var _phase_clock := Vector2i(-1, -1)
var _phase_deadline := 0
var _departure_winner := -1

func attach(id: int, battle: ELDuel, hosting: bool, host_side: int, guest_side: int, phase_seconds := 0) -> bool:
	if duel != null or id < 1 or id > MAX_ID or battle == null or battle.gate != null:
		return false
	if host_side not in [-1, 0, 1] or guest_side not in [-1, 0, 1] or host_side == guest_side:
		return false
	battle_id = id
	duel = battle
	is_host = hosting
	local_side = host_side if hosting else guest_side
	remote_side = guest_side if hosting else host_side
	_phase_seconds = phase_seconds
	battle.gate = self
	return true

func detach() -> void:
	if duel != null and duel.gate == self: duel.gate = null
	duel = null
	battle_id = 0
	local_side = -1
	remote_side = -1
	sequence = 0
	_queue.clear()
	_outstanding.clear()
	_applying_side = -1
	_ai_side = -1
	_announced = false
	_phase_seconds = 0
	_phase_clock = Vector2i(-1, -1)
	_phase_deadline = 0
	_departure_winner = -1
	error = ""

## The original resolves a departed commander's current battle in favour of
## the opposite hero. The replacement AI takes over on the strategic map.
func guest_departed() -> void:
	if not is_host or duel == null or remote_side < 0: return
	if duel.phase != ELDuel.Phase.FINISHED: _departure_winner = 1 - remote_side
	remote_side = -1
	_queue.clear()
	_phase_deadline = 0

## Compare after both sides have restored the same authoritative checkpoint.
func digest() -> String:
	var state := duel.snapshot()
	for hero: Dictionary in state.heroes:
		hero.erase("title")
		hero.erase("name")
	# Compare the wire form. A restored authored 2.0 can become the integer 2
	# in a setup dictionary without changing the state or any Lua value.
	var wire_state: Variant = JSON.parse_string(JSON.stringify(state, "", true, true))
	return JSON.stringify(wire_state, "", true, true).sha256_text()

func receive(id: int, payload: Array) -> bool:
	if duel == null or id != battle_id or not error.is_empty(): return false
	if _queue.size() >= MAX_PENDING:
		_fail("Too many pending strategic battle commands.")
		return false
	_queue.append(payload.duplicate(true))
	return true

func poll(allow_action: bool) -> void:
	if duel == null or not error.is_empty() or not allow_action: return
	if _departure_winner >= 0:
		var winner := _departure_winner
		_departure_winner = -1
		if duel.phase != ELDuel.Phase.FINISHED:
			duel.heroes[1 - winner].health = 0
			duel._declare_victory(winner)
			duel.changed.emit()
	elif _queue.is_empty(): _tick_phase_clock()
	else: _receive(_queue.pop_front())
	_finish_if_ready()

func _current_phase() -> Vector2i:
	return Vector2i(duel.turn_serial, duel.phase)

func clock_remaining() -> int:
	if duel == null or duel.phase == ELDuel.Phase.FINISHED or _phase_deadline == 0 or _phase_clock != _current_phase(): return -1
	return maxi(0, ceili(float(_phase_deadline - Time.get_ticks_msec()) / 1000.0))

func _tick_phase_clock() -> void:
	if _phase_seconds <= 0 or duel == null or duel.phase == ELDuel.Phase.FINISHED or not error.is_empty(): return
	var phase_key := _current_phase()
	var now := Time.get_ticks_msec()
	if _phase_clock != phase_key:
		_phase_clock = phase_key
		_phase_deadline = now + _phase_seconds * 1000
	# Each client advances only the phase it owns. A guest's last action must
	# be acknowledged before it can send the automatic phase change.
	if now >= _phase_deadline and can_play(): duel.end_phase()

func can_play() -> bool:
	return duel != null and local_side >= 0 and _departure_winner < 0 and error.is_empty() and _outstanding.is_empty() \
		and duel.phase != ELDuel.Phase.FINISHED and duel.active_side() == local_side

func result_confirmed() -> bool:
	return duel != null and duel.phase == ELDuel.Phase.FINISHED and _queue.is_empty() and _outstanding.is_empty()

func gate_check(target: ELDuel, action: Dictionary) -> bool:
	if target != duel or duel == null or _departure_winner >= 0 or not error.is_empty() or duel.phase == ELDuel.Phase.FINISHED \
		or not ELNetworkDuel.FIELDS.has(action.get("kind")): return false
	var side := int(action.get("side", -1))
	var source := _applying_side if _applying_side >= 0 else (_ai_side if _ai_side >= 0 else local_side)
	return side >= 0 and side == source and duel.active_side() == side and _outstanding.is_empty()

func gate_done(target: ELDuel, action: Dictionary, ok: bool) -> void:
	if target != duel or not ok or _applying_side >= 0: return
	var values: Array = []
	for key: String in ELNetworkDuel.FIELDS[action.kind]: values.append(action[key])
	var packet := ["commit" if is_host else "intent", sequence + 1, action.kind, action.side, values, digest()]
	if is_host:
		sequence += 1
	else:
		_outstanding = packet.slice(1)
	outbound.emit(battle_id, packet)

func surrender() -> bool:
	var action := {"kind": "surrender", "side": local_side}
	if not gate_check(duel, action): return false
	var ok := ELDuelReplayPlayer.apply_command(duel, action)
	gate_done(duel, action, ok)
	return ok

func step_neutral_ai() -> void:
	if not is_host or duel == null or _departure_winner >= 0 or not error.is_empty() or duel.phase == ELDuel.Phase.FINISHED: return
	var side := duel.active_side()
	if side in [local_side, remote_side]: return
	_ai_side = side
	ELPracticeAI.step(duel)
	_ai_side = -1

func _receive(packet: Array) -> void:
	if packet.size() != 6 or packet[0] != ("intent" if is_host else "commit") \
		or not ELLuaSave._integer(packet[1], 1, MAX_ID) or int(packet[1]) != sequence + 1 \
		or not packet[2] is String or not ELLuaSave._integer(packet[3], 0, 1) \
		or not packet[4] is Array or not packet[5] is String or packet[5].length() != 64:
		_fail("Invalid or out-of-order strategic battle command.")
		return
	var kind: String = packet[2]
	var side := int(packet[3])
	var values: Array = packet[4]
	if not ELNetworkDuel.FIELDS.has(kind) or values.size() != ELNetworkDuel.FIELDS[kind].size():
		_fail("Invalid strategic battle command fields.")
		return
	if is_host and side != remote_side:
		_fail("The guest does not control that battle side.")
		return
	var action := {"kind": kind, "side": side}
	for index in values.size():
		var key: String = ELNetworkDuel.FIELDS[kind][index]
		var value: Variant = values[index]
		if key in ["card", "ability"]:
			if not value is String or value.length() > 64:
				_fail("Invalid strategic battle command text.")
				return
			action[key] = value
		else:
			if not ELLuaSave._integer(value, -1, MAX_ID):
				_fail("Invalid strategic battle command number.")
				return
			action[key] = int(value)
	var normalized: Array = []
	for key: String in ELNetworkDuel.FIELDS[kind]: normalized.append(action[key])
	if not is_host and side == local_side:
		var confirmation := [int(packet[1]), kind, side, normalized, packet[5]]
		if _outstanding.is_empty() or confirmation != _outstanding or packet[5] != digest():
			_fail("The host acknowledged a different strategic battle command.")
			return
		_outstanding.clear()
		sequence += 1
		return
	if duel.phase == ELDuel.Phase.FINISHED or duel.active_side() != side or not _outstanding.is_empty():
		_fail("The strategic battle command arrived outside its action phase.")
		return
	_applying_side = side
	var ok := ELDuelReplayPlayer.apply_command(duel, action)
	_applying_side = -1
	if not ok or packet[5] != digest():
		_fail("The strategic battle went out of sync.")
		return
	sequence += 1
	if is_host:
		packet[0] = "commit"
		outbound.emit(battle_id, packet)

func _finish_if_ready() -> void:
	if duel != null and is_host and error.is_empty() and not _announced and duel.phase == ELDuel.Phase.FINISHED:
		_announced = true
		host_finished.emit(battle_id, duel.winner)

## Called when the strategic link cannot send an outbound packet.
func transport_failed() -> void:
	_fail("The strategic battle command could not be sent.")

func _fail(reason: String) -> void:
	if not error.is_empty(): return
	error = reason
	failed.emit(reason)
