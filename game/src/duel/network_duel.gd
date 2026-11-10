class_name ELNetworkDuel
extends RefCounted
## Two peers play the same edition and resolve the same ordered duel commands.
## The host chooses the arena, resource cap and seed.
signal message(text: String)
signal offer_received(resource_level: int, arena: String, rounds: int, turn_seconds: int, deck_seconds: int)
signal started(battle: ELDuel)
signal round_ready()
signal chat_opened()
signal chat_posted(side: int, text: String)
signal closed(reason: String)

const PORT := 27184
const VERSION := 9
const MAX_PACKET := 4096
const MAX_PENDING := 128
const MAX_CHAT_LENGTH := 240
const MAX_CHAT_HISTORY := 50
const MIN_TURN_SECONDS := 10
const MAX_TURN_SECONDS := 3600
const CUSTOM_FIELDS := ["faction", "resource_level", "level", "specialization", "skills", "cards", "runes", "reserve", "artifacts"]
const FIELDS := {
	"cast": ["hand_index", "target", "grave", "power", "card"],
	"artifact": ["index", "target", "choice"],
	"attack": ["id"],
	"retreat": ["id"],
	"block": ["id", "target"],
	"ability": ["id", "ability", "target", "enchantment", "amount"],
	"end_phase": [],
	"surrender": [],
}

var profile: ELProfile
var duel: ELDuel
var match_state: ELDuelMatch
var recording: ELDuelRecording
var local_side := 0
var live := false
var chat_history: Array[Dictionary] = []
var _chat_enabled := false
var _peer: ENetMultiplayerPeer
var _remote := 0
var _selection: Variant
var _arena := ""
var _resource_level := 0
var _rounds := 1
var _turn_seconds := 0
var _deck_seconds := 0
var _deck_deadline := 0
var _next_presets: Array[Dictionary] = [{}, {}]
var _clock_phase := Vector2i(-1, -1)
var _clock_deadline := 0
var _round_index := 0
var _first_attacker := 0
var _local_ready := false
var _remote_ready := false
var _awaiting_pick := false
var _joining := false
var _ready_deadline := 0
var _sequence := 0
var _applying := false
var _pending: Array[Array] = []
var _failure := ""
var _departure := ""
var _discovery: ELNetworkDiscovery

func host(data: ELProfile, port: int, deck: String, arena: String, resource_level: int, rounds: int, advertise := false, turn_seconds := 0, deck_seconds := 0) -> Error:
	if _peer != null: return ERR_ALREADY_IN_USE
	if port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	if not ELDuelMatch.arenas(data).has(arena) or not _valid_level(data, resource_level): return ERR_INVALID_PARAMETER
	if not ELLuaSave._integer(rounds, 1, ELDuelMatch.MAX_ROUNDS): return ERR_INVALID_PARAMETER
	if not valid_time_limit(data, turn_seconds) or not valid_time_limit(data, deck_seconds): return ERR_INVALID_PARAMETER
	var selection: Variant = _preset_selection(data, deck, resource_level)
	if selection == null: return ERR_INVALID_PARAMETER
	_open(data, 0)
	_selection = selection
	_arena = arena
	_resource_level = resource_level
	_rounds = rounds
	_turn_seconds = turn_seconds
	_deck_seconds = deck_seconds
	var result := _peer.create_server(port, 1)
	if result != OK:
		close()
		return result
	var status := "Waiting for a player on UDP port %d." % port
	if advertise:
		_discovery = ELNetworkDiscovery.new()
		if _discovery.listen(VERSION, data.id, port, arena, resource_level) != OK:
			_discovery = null
			status += " LAN discovery unavailable. Players can join by address."
	message.emit(status)
	return result

func join(data: ELProfile, address: String, port: int) -> Error:
	if _peer != null: return ERR_ALREADY_IN_USE
	if address.is_empty() or address.length() > 253 or port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	_open(data, 1)
	var result := _peer.create_client(address, port)
	if result != OK: close()
	else:
		_remote = MultiplayerPeer.TARGET_PEER_SERVER
		_joining = true
		_ready_deadline = Time.get_ticks_msec() + 15000
		message.emit("Connecting to the host…")
	return result

func confirm_preset(deck: String) -> Error:
	if local_side != 1 or not _awaiting_pick: return ERR_UNCONFIGURED
	var selection: Variant = _preset_selection(profile, deck, _resource_level)
	if selection == null: return ERR_INVALID_PARAMETER
	_selection = selection
	_awaiting_pick = false
	_ready_deadline = Time.get_ticks_msec() + 15000
	_send(["pick", _selection])
	return OK

static func _preset_selection(data: ELProfile, deck: String, resource_level: int) -> Variant:
	var custom_deck := deck.begins_with("user:")
	var choices := ELDuelPresets.load_user(data) if custom_deck else ELDuelPresets.shipped(data)
	var preset := ELDuelPresets.find(choices, deck)
	if preset.is_empty() or not ELDuelMatch.side_valid(choices, preset, resource_level): return null
	var selection: Variant = deck
	if custom_deck:
		var custom := {}
		for key: String in CUSTOM_FIELDS: custom[key] = preset[key]
		selection = custom
	return selection if JSON.stringify(selection).to_utf8_buffer().size() <= MAX_PACKET - 512 else null

static func _valid_level(data: ELProfile, level: Variant) -> bool:
	var limits := ELDuelCosts.resource_levels(data)
	return ELLuaSave._integer(level, limits.x, limits.y)

static func valid_time_limit(data: ELProfile, seconds: Variant) -> bool:
	return ELLuaSave._integer(seconds, 0, 0) or (data.id == "el2" and ELLuaSave._integer(seconds, MIN_TURN_SECONDS, MAX_TURN_SECONDS))

func _open(data: ELProfile, side: int) -> void:
	profile = data
	match_state = null
	local_side = side
	recording = ELDuelRecording.new() if data.id == "el2" else null
	if recording != null: recording.local_side = side
	_peer = ENetMultiplayerPeer.new()
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.peer_connected.connect(_connected)
	_peer.peer_disconnected.connect(_disconnected)

func _connected(id: int) -> void:
	if local_side != 0: return
	_stop_discovery()
	_remote = id
	_ready_deadline = Time.get_ticks_msec() + 15000
	message.emit("Player connected. Checking game data…")

func _disconnected(id: int) -> void:
	if id == _remote and _departure.is_empty(): _departure = "The other player disconnected."

func poll(allow_action: bool, advance_phase := Callable()) -> void:
	if _peer == null: return
	_peer.poll()
	if _discovery != null: _discovery.poll()
	var connection := _peer.get_connection_status()
	if _joining and connection == MultiplayerPeer.CONNECTION_CONNECTED:
		_joining = false
		_send(["hello", VERSION, profile.id])
	if connection == MultiplayerPeer.CONNECTION_DISCONNECTED and _departure.is_empty():
		_departure = "The connection to the other player closed."
	for packet in mini(64, _peer.get_available_packet_count()):
		var sender := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		if sender != _remote: continue
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() <= MAX_PACKET else null
		if value is Array and not value.is_empty(): _receive(value)
		else: _failure = "Invalid network message."
		if not _failure.is_empty(): break
	if _ready_deadline > 0 and Time.get_ticks_msec() > _ready_deadline:
		_failure = "The other player did not finish connecting."
	if _failure.is_empty() and live and allow_action:
		if not _pending.is_empty():
			var command: Array = _pending.pop_front()
			if command[0] == "next": _receive_round_ready(command)
			else: _apply_remote(command)
		elif _departure.is_empty(): _tick_turn_clock(advance_phase)
		if _failure.is_empty() and _deck_deadline > 0 and Time.get_ticks_msec() >= _deck_deadline:
			continue_round()
		if _failure.is_empty() and _departure.is_empty() and _local_ready and _remote_ready:
			for side in 2:
				if not _next_presets[side].is_empty(): match_state.presets[side] = _next_presets[side]
			var seed := ELDuelMatch._mix(match_state.seed_value + match_state.played) & 0x7fffffff
			if _prepare_round(seed): _start()
			else: _failure = "Could not start the next round."
	if _failure.is_empty() and not _departure.is_empty() and _pending.is_empty():
		_failure = _departure
	if not _failure.is_empty():
		var reason := _failure
		close()
		closed.emit(reason)

func _receive(packet: Array) -> void:
	match packet[0]:
		"hello":
			if local_side != 0 or duel != null or _awaiting_pick or packet.size() < 3: return _invalid()
			if packet[1] != VERSION or packet[2] != profile.id:
				_send(["reject", "version"])
				_ready_deadline = Time.get_ticks_msec() + 1000
				return
			if packet.size() != 3: return _invalid()
			_awaiting_pick = true
			_ready_deadline = 0
			_send(["offer", _resource_level, _arena, _rounds, _turn_seconds, _deck_seconds])
			message.emit("Waiting for the other player to choose a hero.")
			_enable_chat()
		"offer":
			if local_side != 1 or _resource_level != 0 or packet.size() != 6 or not _valid_level(profile, packet[1]):
				return _invalid()
			if not packet[2] is String or not ELDuelMatch.arenas(profile).has(packet[2]): return _invalid()
			if not ELLuaSave._integer(packet[3], 1, ELDuelMatch.MAX_ROUNDS): return _invalid()
			if not valid_time_limit(profile, packet[4]) or not valid_time_limit(profile, packet[5]): return _invalid()
			_resource_level = int(packet[1])
			_arena = packet[2]
			_rounds = int(packet[3])
			_turn_seconds = int(packet[4])
			_deck_seconds = int(packet[5])
			_awaiting_pick = true
			_ready_deadline = 0
			offer_received.emit(_resource_level, _arena, _rounds, _turn_seconds, _deck_seconds)
			_enable_chat()
		"pick":
			if local_side != 0 or not _awaiting_pick or packet.size() != 2: return _invalid()
			_awaiting_pick = false
			var seed := randi() & 0x7fffffff
			if not _prepare(_selection, packet[1], seed):
				_send(["reject", "preset"])
				_ready_deadline = Time.get_ticks_msec() + 1000
				return
			_ready_deadline = Time.get_ticks_msec() + 15000
			_send(["setup", _selection, seed, _digest()])
		"setup":
			if local_side != 1 or duel != null or _selection == null or packet.size() != 4: return _invalid()
			if not ELLuaSave._integer(packet[2], 0, 0x7fffffff): return _invalid()
			if not _prepare(packet[1], _selection, int(packet[2])) or packet[3] != _digest():
				_failure = "The installed game data differs from the host."
				return
			_send(["ready", _digest()])
		"ready":
			if local_side != 0 or live or duel == null or packet.size() != 2 or packet[1] != _digest(): return _invalid()
			_send(["start"])
			_start()
		"start":
			if local_side != 1 or live or duel == null or packet.size() != 1: return _invalid()
			_start()
		"action":
			if not live or packet.size() != 6 or _pending.size() >= MAX_PENDING: return _invalid()
			_pending.append(packet)
		"next":
			if not live or packet.size() != 5 or _pending.size() >= MAX_PENDING: return _invalid()
			_pending.append(packet)
		"chat":
			if can_chat() and packet.size() == 2 and packet[1] is String and packet[1].length() <= MAX_CHAT_LENGTH:
				_post_chat(1 - local_side, _clean_chat(packet[1]))
		"reject":
			_failure = "A hero preset does not meet the match rules." if packet.size() == 2 and packet[1] == "preset" else "Use the same Demiurges version and game edition."
		"leave":
			_departure = "The other player left the duel."
		_:
			_invalid()

func _invalid() -> void:
	_failure = "Invalid or out-of-order network message."

func _enable_chat() -> void:
	_chat_enabled = true
	chat_opened.emit()

func can_chat() -> bool:
	return _chat_enabled and _failure.is_empty() and _departure.is_empty()

func send_chat(value: String) -> bool:
	if not can_chat() or value.length() > MAX_CHAT_LENGTH: return false
	var line := _clean_chat(value)
	if line.is_empty(): return false
	_send(["chat", line])
	if not _failure.is_empty(): return false
	_post_chat(local_side, line)
	return true

static func _clean_chat(value: String) -> String:
	var line := ""
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159) or code in [0x2028, 0x2029]:
			line += " "
		elif code not in [0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069]:
			line += value[index]
	return line.strip_edges()

func _post_chat(side: int, line: String) -> void:
	if line.is_empty(): return
	if chat_history.size() == MAX_CHAT_HISTORY: chat_history.pop_front()
	chat_history.append({"side": side, "text": line})
	chat_posted.emit(side, line)

func _read_preset(selection: Variant, shipped: Array[Dictionary]) -> Dictionary:
	if selection is String: return ELDuelPresets.find(shipped, selection)
	if selection is not Dictionary or selection.size() != CUSTOM_FIELDS.size() or not selection.has_all(CUSTOM_FIELDS):
		return {}
	var preset := ELDuelPresets.normalize(selection)
	if preset.is_empty() or not ELDuelCosts.errors(profile, preset).is_empty(): return {}
	return preset

func _prepare(host_pick: Variant, guest_pick: Variant, seed: int) -> bool:
	var shipped := ELDuelPresets.shipped(profile)
	var host_preset := _read_preset(host_pick, shipped)
	var guest_preset := _read_preset(guest_pick, shipped)
	if host_preset.is_empty() or guest_preset.is_empty(): return false
	var next_match := ELDuelMatch.new()
	if not next_match.begin(profile, shipped, [host_preset, guest_preset], _resource_level, _rounds, _arena, seed).is_empty():
		return false
	match_state = next_match
	_first_attacker = seed & 1
	if profile.id == "el1" and host_preset.level != guest_preset.level:
		_first_attacker = 0 if host_preset.level > guest_preset.level else 1
	return _prepare_round(seed)

func _prepare_round(seed: int) -> bool:
	var options := match_state.round_options(profile)
	# The original network seed advances by an odd amount between rounds.
	options.first_side = _first_attacker ^ (match_state.played & 1)
	var battle := ELDuel.new()
	if not battle.start(profile, seed, options): return false
	if duel != null and duel.gate == self: duel.gate = null
	duel = battle
	duel.gate = self
	if recording != null:
		recording.track(duel, seed, self)
		if match_state.played == 0:
			recording.label_heroes(duel, match_state.presets.map(func(preset: Dictionary): return preset.name))
	_round_index = match_state.played
	_local_ready = false
	_remote_ready = false
	_clock_phase = Vector2i(-1, -1)
	_clock_deadline = 0
	_deck_deadline = 0
	_next_presets.assign([{}, {}])
	return true

func clock_remaining() -> int:
	if not live or duel == null or duel.phase == ELDuel.Phase.FINISHED or _clock_deadline == 0: return -1
	if _clock_phase != Vector2i(duel.turn_serial, duel.phase): return -1
	return maxi(0, ceili(float(_clock_deadline - Time.get_ticks_msec()) / 1000.0))

func _tick_turn_clock(advance_phase: Callable) -> void:
	if _turn_seconds == 0 or duel == null or duel.phase == ELDuel.Phase.FINISHED: return
	var phase := Vector2i(duel.turn_serial, duel.phase)
	var now := Time.get_ticks_msec()
	if _clock_phase != phase:
		_clock_phase = phase
		_clock_deadline = now + _turn_seconds * 1000
	if now >= _clock_deadline and duel.active_side() == local_side:
		if advance_phase.is_valid(): advance_phase.call()
		else: duel.end_phase()

func _record_round() -> void:
	if duel.phase == ELDuel.Phase.FINISHED and match_state.played == _round_index:
		match_state.record(duel.winner)
		if recording != null: recording.finish_round(duel)

func can_continue_round() -> bool:
	return live and match_state.played == _round_index + 1 and not match_state.finished()

func begin_round_selection() -> void:
	if can_continue_round() and not _local_ready and _deck_seconds > 0 and _deck_deadline == 0:
		_deck_deadline = Time.get_ticks_msec() + _deck_seconds * 1000

func deck_time_remaining() -> int:
	if _deck_deadline == 0: return -1
	return maxi(0, ceili(float(_deck_deadline - Time.get_ticks_msec()) / 1000.0))

func round_preset() -> Dictionary:
	var draft := _next_presets[local_side]
	return (match_state.presets[local_side] if draft.is_empty() else draft).duplicate(true)

func swap_round_spell(slot: int, code: String) -> bool:
	if not can_continue_round() or profile.id != "el2" or _local_ready or not _departure.is_empty() or deck_time_remaining() == 0:
		return false
	var draft := round_preset()
	if slot < 0 or slot >= draft.cards.size() or int(draft.reserve.get(code, 0)) <= 0: return false
	draft.cards[slot] = code
	var validated := ELDuelPresets.with_reserve_deck(match_state.presets[local_side], draft.cards)
	if validated.is_empty(): return false
	_next_presets[local_side] = validated
	return true

func continue_round() -> bool:
	if not can_continue_round() or _local_ready or not _departure.is_empty(): return false
	_local_ready = true
	_deck_deadline = 0
	_send(["next", match_state.played, _sequence, _digest(), _next_presets[local_side].get("cards")])
	round_ready.emit()
	return true

func _receive_round_ready(packet: Array) -> void:
	if not can_continue_round() or _remote_ready or packet[1] != match_state.played or packet[2] != _sequence or packet[3] != _digest():
		return _invalid()
	if packet[4] != null:
		if profile.id != "el2" or packet[4] is not Array: return _invalid()
		var remote_side := 1 - local_side
		var preset := ELDuelPresets.with_reserve_deck(match_state.presets[remote_side], packet[4])
		if preset.is_empty(): return _invalid()
		_next_presets[remote_side] = preset
	_remote_ready = true

func _start() -> void:
	_ready_deadline = 0
	live = true
	started.emit(duel)

func _digest() -> String:
	var state := duel.snapshot()
	for hero: Dictionary in state.heroes:
		hero.erase("title")
		hero.erase("name")
	return JSON.stringify(state).sha256_text()

func _send(packet: Array) -> void:
	if _peer == null or _remote == 0: return
	_peer.set_target_peer(_remote)
	if _peer.put_packet(JSON.stringify(packet).to_utf8_buffer()) != OK:
		_failure = "The network message could not be sent."

## Rule calls from the UI use the same gate as commands received from the
## other peer. Neither peer can apply a command on behalf of the other.
func gate_check(target: ELDuel, action: Dictionary) -> bool:
	var side := 1 - local_side if _applying else local_side
	return live and (_applying or _departure.is_empty()) and target == duel and action.get("side") == side and FIELDS.has(action.get("kind")) and duel.active_side() == side

func gate_done(target: ELDuel, action: Dictionary, ok: bool) -> void:
	if target != duel or not ok or _applying: return
	var values: Array = []
	for key: String in FIELDS[action.kind]: values.append(action[key])
	_sequence += 1
	_send(["action", _sequence, action.kind, local_side, values, _digest()])
	if recording != null: recording.gate_done(duel, action, true)
	_record_round()

func _apply_remote(packet: Array) -> void:
	if packet[1] != _sequence + 1 or not packet[2] is String or packet[3] != 1 - local_side or not packet[4] is Array or not packet[5] is String or packet[5].length() != 64:
		return _invalid()
	var kind: String = packet[2]
	var keys: Array = FIELDS.get(kind, [])
	var values: Array = packet[4]
	if not FIELDS.has(kind) or keys.size() != values.size(): return _invalid()
	var action := {"kind": kind, "side": 1 - local_side}
	for index in keys.size():
		var key: String = keys[index]
		var value: Variant = values[index]
		if key in ["card", "ability"]:
			if not value is String or value.length() > 64: return _invalid()
			action[key] = value
		else:
			if not ELLuaSave._integer(value, -1, 0x7fffffff): return _invalid()
			action[key] = int(value)
	_applying = true
	var ok := _surrender(action.side) if kind == "surrender" else ELDuelReplayPlayer.apply_command(duel, action)
	_applying = false
	if not ok or packet[5] != _digest():
		_failure = "The duel went out of sync."
		return
	_sequence += 1
	if recording != null: recording.gate_done(duel, action, true)
	_record_round()

func surrender() -> bool:
	return _surrender(local_side)

func _surrender(side: int) -> bool:
	var action := {"kind": "surrender", "side": side}
	if duel == null or duel.phase == ELDuel.Phase.FINISHED or not gate_check(duel, action): return false
	duel.heroes[side].health = 0
	duel._check_winner()
	duel.changed.emit()
	gate_done(duel, action, true)
	return true

func close() -> void:
	_stop_discovery()
	if duel != null and duel.gate == self: duel.gate = null
	duel = null
	if match_state == null or not match_state.finished():
		match_state = null
		if recording != null: recording.untrack()
		recording = null
	live = false
	if _peer != null:
		if _failure.is_empty() and _remote != 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_send(["leave"])
			_peer.get_host().flush()
		_peer.close()
	_peer = null
	_chat_enabled = false
	chat_history.clear()
	_selection = null
	_resource_level = 0
	_rounds = 1
	_turn_seconds = 0
	_deck_seconds = 0
	_deck_deadline = 0
	_next_presets.assign([{}, {}])
	_clock_deadline = 0
	_round_index = 0
	_local_ready = false
	_remote_ready = false
	_awaiting_pick = false
	_pending.clear()
	_ready_deadline = 0
	_remote = 0
	_sequence = 0
	_joining = false
	_failure = ""
	_departure = ""

func _stop_discovery() -> void:
	if _discovery == null: return
	_discovery.close()
	_discovery = null
