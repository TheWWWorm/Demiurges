class_name ELNetworkStrategy
extends RefCounted
## One guest submits orders to the authoritative host. Map state and battle
## messages use separate reliable ENet channels.
signal message(text: String)
signal started(setup: Dictionary)
signal plan_received(player: int, day: int, plan: Array)
signal command_received(player: int, day: int, request: int, command: Array)
signal command_replied(day: int, request: int, accepted: bool, error: String)
signal readiness_changed(player: int, day: int, ready: bool)
signal clock_event(kind: String, day: int)
signal snapshot_received(day: int, document: Dictionary)
signal battle_received(battle_id: int, payload: Array)
signal closed(reason: String)
signal guest_departed(voluntary: bool)

const PORT := 27186
const DISCOVERY_PORT := 27187
# v11 peers wait for the final tactical commit before installing a result.
const VERSION := 12
const MAX_TURN_SECONDS := 3600
const EDITION := "el1"
const PROTOCOL := "DemiurgesStrategy"
const CONTROL := 1
const BATTLE := 2
const MAX_CONTROL := 16 * 1024
const MAX_SNAPSHOT := 4 * 1024 * 1024
const SNAPSHOT_MARKER := 0x53
## Marker followed by three little-endian u32 values: revision, day, size.
const SNAPSHOT_HEADER := 13
const MAX_DAY := 0x7fffffff
const MAX_SEED := 0xffffffff
const CONNECT_TIMEOUT := 15000
const STARTUP_TRANSPORT_TIMEOUT := 60000
const PACKETS_PER_POLL := 32
const MAX_QUEUED := 128
const MAX_REQUESTS := 16
const MAX_COMMAND_FIELDS := 32
const MAX_COMMAND_KIND := 48
const MAX_COMMAND_TEXT := 96
const MAX_COMMAND_ERROR := 256
const VISIT_ORDERS := ["visit_buy_runes", "visit_buy_spells", "visit_close"]

enum State { CLOSED, WAIT_GUEST, WAIT_HELLO, WAIT_SETUP, WAIT_READY, WAIT_START, LIVE, REJECTED }
enum Departure { NONE, LEFT, LOST }

var is_host := false
var live := false
var local_authority := false
var can_replace_guest: Callable
var local_player := 0
var remote_player := 0
var current_day := 1
var snapshot_revision := 0
var _profile: ELProfile
var _peer: ENetMultiplayerPeer
var _state := State.CLOSED
var _remote := 0
var _setup: Dictionary = {}
var _bounds := Vector2i.ZERO
var _local_ready := false
var _remote_ready := false
var _request_sequence := 0
## Request ID to original day. The guest tracks sent requests and the host
## tracks received requests until each is acknowledged.
var _pending_commands: Dictionary[int, int] = {}
var _hello_sent := false
var _early_battle: Array[Array] = []
var _deadline := 0
var _startup_transport_until := 0
var _failure := ""
var _rejection := ""
var _departure := Departure.NONE
var _discovery: ELNetworkDiscovery

func host(profile: ELProfile, map_id: String, port: int, players: Vector2i, difficulty: int, seed: int, day := 1, turn_seconds := 0, combat_seconds := 0, advertise := false) -> Error:
	if _peer != null or live: return ERR_ALREADY_IN_USE
	if (not _valid_profile(profile, port) or not _valid_map_id(map_id)
		or difficulty < 0 or difficulty > 4 or seed < 0 or seed > MAX_SEED or day < 1 or day > MAX_DAY
		or turn_seconds < 0 or turn_seconds > MAX_TURN_SECONDS or combat_seconds < 0 or combat_seconds > MAX_TURN_SECONDS):
		return ERR_INVALID_PARAMETER
	var map := ELAdventureMap.new()
	if not map.load_map(profile, map_id) or not _valid_players(map, players): return ERR_INVALID_PARAMETER
	var map_hash := _map_hash(profile, map_id)
	if not _valid_hash(map_hash): return ERR_INVALID_DATA
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, 1, BATTLE)
	if result != OK: return result
	_open(profile, peer, true, State.WAIT_GUEST)
	_bounds = Vector2i(map.width, map.height)
	local_player = players.x
	remote_player = players.y
	_setup = {"map": map_id, "map_hash": map_hash, "players": [players.x, players.y], "difficulty": difficulty,
		"seed": seed, "day": day, "turn_seconds": turn_seconds, "combat_seconds": combat_seconds}
	var status := "Waiting for a strategic player on UDP port %d." % port
	if advertise:
		_discovery = ELNetworkDiscovery.new(DISCOVERY_PORT, PROTOCOL)
		if _discovery.listen(VERSION, EDITION, port, map_id, day) != OK:
			_stop_discovery()
			status += " " + ELRemakeText.t("LAN discovery unavailable. You can join by address.", profile)
	message.emit(status)
	return OK

func join(profile: ELProfile, address: String, port: int) -> Error:
	if _peer != null or live: return ERR_ALREADY_IN_USE
	if not _valid_profile(profile, port) or address.is_empty() or address.length() > 253 or address != address.strip_edges():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port, BATTLE)
	if result != OK: return result
	_open(profile, peer, false, State.WAIT_SETUP)
	_remote = MultiplayerPeer.TARGET_PEER_SERVER
	_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT
	message.emit("Connecting to the strategic host…")
	return OK

func _open(profile: ELProfile, peer: ENetMultiplayerPeer, host_side: bool, state: State) -> void:
	_profile = profile
	_peer = peer
	is_host = host_side
	_state = state
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.peer_connected.connect(_connected)
	_peer.peer_disconnected.connect(_disconnected)

func _connected(id: int) -> void:
	var link := _peer.get_peer(id)
	# The first map builds synchronously on each peer. It can suspend ENet
	# polling while the other peer already has a live connection.
	if link != null: link.set_timeout(32, STARTUP_TRANSPORT_TIMEOUT, STARTUP_TRANSPORT_TIMEOUT)
	if _state != State.WAIT_GUEST: return
	_stop_discovery()
	_remote = id
	_state = State.WAIT_HELLO
	_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT
	_peer.refuse_new_connections = true
	message.emit("Player connected. Checking strategic map data…")

func _disconnected(id: int) -> void:
	if id == _remote and _failure.is_empty():
		_departure = Departure.LOST

func poll() -> void:
	if _peer == null: return
	var peer := _peer
	peer.poll()
	if peer != _peer: return
	if _discovery != null: _discovery.poll()
	var connection := peer.get_connection_status()
	if _departure == Departure.NONE and connection == MultiplayerPeer.CONNECTION_CONNECTED and _startup_transport_until > 0 and Time.get_ticks_msec() >= _startup_transport_until:
		_startup_transport_until = 0
		var transport := peer.get_peer(_remote)
		if transport != null: transport.set_timeout(32, 5000, CONNECT_TIMEOUT)
	if _state == State.WAIT_SETUP and not _hello_sent and connection == MultiplayerPeer.CONNECTION_CONNECTED:
		_hello_sent = _send(["hello", PROTOCOL, VERSION, EDITION])
	if peer.get_available_packet_count() > MAX_QUEUED: _invalid()
	for index in mini(PACKETS_PER_POLL, peer.get_available_packet_count()):
		if not _failure.is_empty(): break
		var sender := peer.get_packet_peer()
		var channel := peer.get_packet_channel()
		var mode := peer.get_packet_mode()
		var bytes := peer.get_packet()
		if sender != _remote or mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE or channel not in [CONTROL, BATTLE]:
			_invalid()
			break
		_receive(bytes, channel)
		if peer != _peer: return
	if _failure.is_empty():
		if _departure == Departure.LOST:
			_failure = _rejection if not _rejection.is_empty() else "The other player disconnected."
		elif connection == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_departure = Departure.LOST
			_failure = "The strategic connection closed."
	elif _departure == Departure.LOST:
		_departure = Departure.NONE
	if _deadline > 0 and Time.get_ticks_msec() >= _deadline and _failure.is_empty():
		_failure = _rejection if not _rejection.is_empty() else "The other player did not finish connecting."
	if not _failure.is_empty():
		if live and is_host and _departure != Departure.NONE and can_replace_guest.is_valid() and can_replace_guest.call():
			var voluntary := _departure == Departure.LEFT
			_peer.close()
			_peer = null
			_remote_ready = false
			_pending_commands.clear()
			_failure = ""
			_departure = Departure.NONE
			_startup_transport_until = 0
			local_authority = true
			guest_departed.emit(voluntary)
			return
		var reason := _failure
		close()
		closed.emit(reason)

func _receive(bytes: PackedByteArray, channel: int) -> void:
	if _state == State.REJECTED: return
	if not bytes.is_empty() and bytes[0] == SNAPSHOT_MARKER and channel == CONTROL:
		_receive_snapshot(bytes)
		return
	if bytes.is_empty() or bytes.size() > MAX_CONTROL:
		_invalid()
		return
	var packet: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not packet is Array or packet.is_empty() or not packet[0] is String:
		_invalid()
		return
	if channel == BATTLE:
		_receive_battle(packet)
		return
	match packet[0]:
		"hello": _receive_hello(packet)
		"setup": _receive_setup(packet)
		"ready": _receive_start_ready(packet)
		"start":
			if _state != State.WAIT_START or packet.size() != 1: _invalid()
			else: _start()
		"plan": _receive_plan(packet)
		"command": _receive_command(packet)
		"command_reply": _receive_command_reply(packet)
		"day_ready": _receive_day_ready(packet)
		"clock_open", "clock_start", "clock_expire": _receive_clock(packet)
		"reject":
			if live or _state == State.WAIT_GUEST or packet.size() != 2 or not packet[1] is String or packet[1] not in ["version", "map"]: _invalid()
			else: _failure = _rejection_text(packet[1])
		"leave":
			if packet.size() != 1: _invalid()
			else:
				_departure = Departure.LEFT
				_failure = "The other player left the strategic game."
		_: _invalid()

func _receive_hello(packet: Array) -> void:
	if _state != State.WAIT_HELLO or packet.size() != 4:
		_invalid()
		return
	if not _compatible(packet):
		_reject("version")
		return
	_state = State.WAIT_READY
	_send(["setup", PROTOCOL, VERSION, EDITION, _setup.map, _setup.map_hash, _setup.players, _setup.difficulty,
		_setup.seed, _setup.day, _setup.turn_seconds, _setup.combat_seconds])

func _receive_setup(packet: Array) -> void:
	if _state != State.WAIT_SETUP or not _hello_sent or packet.size() != 12:
		_invalid()
		return
	if not _compatible(packet):
		_reject("version")
		return
	if (not _valid_map_id(packet[4]) or not _valid_hash(packet[5]) or not packet[6] is Array or packet[6].size() != 2
		or not ELLuaSave._integer(packet[7], 0, 4) or not ELLuaSave._integer(packet[8], 0, MAX_SEED)
		or not ELLuaSave._integer(packet[9], 1, MAX_DAY) or not ELLuaSave._integer(packet[10], 0, MAX_TURN_SECONDS)
		or not ELLuaSave._integer(packet[11], 0, MAX_TURN_SECONDS)):
		_invalid()
		return
	var seats: Array = packet[6]
	if not ELLuaSave._integer(seats[0], 1, MAX_DAY) or not ELLuaSave._integer(seats[1], 1, MAX_DAY):
		_invalid()
		return
	var players := Vector2i(int(seats[0]), int(seats[1]))
	var map := ELAdventureMap.new()
	if _map_hash(_profile, packet[4]) != packet[5] or not map.load_map(_profile, packet[4]) or not _valid_players(map, players):
		_reject("map")
		return
	_bounds = Vector2i(map.width, map.height)
	local_player = players.y
	remote_player = players.x
	_setup = {"map": packet[4], "map_hash": packet[5], "players": [players.x, players.y], "difficulty": int(packet[7]),
		"seed": int(packet[8]), "day": int(packet[9]), "turn_seconds": int(packet[10]), "combat_seconds": int(packet[11])}
	_state = State.WAIT_START
	_send(["ready", _setup.map_hash])

func _receive_start_ready(packet: Array) -> void:
	if _state != State.WAIT_READY or packet.size() != 2 or not packet[1] is String or packet[1] != _setup.map_hash:
		_invalid()
		return
	if _send(["start"]): _start()

func _start() -> void:
	_deadline = 0
	_startup_transport_until = Time.get_ticks_msec() + STARTUP_TRANSPORT_TIMEOUT
	_state = State.LIVE
	current_day = _setup.day
	live = true
	started.emit(_setup.duplicate(true))
	while live and _failure.is_empty() and not _early_battle.is_empty():
		var packet: Array = _early_battle.pop_front()
		battle_received.emit(int(packet[1]), packet[2])

func _reject(code: String) -> void:
	if not _send(["reject", code]): return
	_state = State.REJECTED
	_rejection = _rejection_text(code)
	_deadline = Time.get_ticks_msec() + 1000

static func _rejection_text(code: String) -> String:
	return "The installed original strategic map differs from the host." if code == "map" else "Use the same Demiurges version and Etherlords I edition."

func submit_plan(day: int, plan: Array) -> bool:
	if not live or day != current_day or _local_ready or not _valid_plan(plan): return false
	if is_host:
		plan_received.emit(local_player, day, _normalized_plan(plan))
		return live and _failure.is_empty()
	return _send(["plan", day, plan])

func _receive_plan(packet: Array) -> void:
	if not live or not is_host or _remote_ready or packet.size() != 3 or not ELLuaSave._integer(packet[1], current_day, current_day) or not _valid_plan(packet[2]):
		_invalid()
		return
	plan_received.emit(remote_player, current_day, _normalized_plan(packet[2]))

func _valid_plan(value: Variant) -> bool:
	if not value is Array or value.size() != 1 or not value[0] is Array or value[0].size() != 4: return false
	var row: Array = value[0]
	if not ELLuaSave._integer(row[0], 0, MAX_DAY) or not ELLuaSave._integer(row[1], -1, _bounds.x - 1) or not ELLuaSave._integer(row[2], -1, _bounds.y - 1) or not ELLuaSave._integer(row[3], -1, MAX_DAY):
		return false
	return (row[1] >= 0 and row[2] >= 0) or (row[1] == -1 and row[2] == -1 and row[3] == -1)

static func _normalized_plan(plan: Array) -> Array:
	var row: Array = plan[0]
	return [[int(row[0]), int(row[1]), int(row[2]), int(row[3])]]

## The guest sends consecutive request IDs for this connection.
func submit_command(day: int, request: int, command: Array) -> bool:
	if (not live or is_host or day != current_day or not _next_request(request) or not _valid_command(command)
		or (_local_ready and command[0] not in VISIT_ORDERS)):
		return false
	if not _send(["command", day, request, command]): return false
	_request_sequence = request
	_pending_commands[request] = day
	return true

func _receive_command(packet: Array) -> void:
	if (not live or not is_host or packet.size() != 4
		or not ELLuaSave._integer(packet[1], current_day, current_day)
		or not _next_request(packet[2]) or not _valid_command(packet[3])
		or (_remote_ready and packet[3][0] not in VISIT_ORDERS)):
		_invalid()
		return
	var request := int(packet[2])
	var command: Array = packet[3]
	for index in range(1, command.size()):
		if command[index] is float: command[index] = int(command[index])
	_request_sequence = request
	_pending_commands[request] = current_day
	command_received.emit(remote_player, current_day, request, command)

func _next_request(request: Variant) -> bool:
	var expected := _request_sequence + 1
	return expected <= MAX_DAY and _pending_commands.size() < MAX_REQUESTS and ELLuaSave._integer(request, expected, expected)

static func _valid_command(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > MAX_COMMAND_FIELDS: return false
	var kind: Variant = value[0]
	if (not kind is String or kind.length() > MAX_COMMAND_KIND
		or not kind.is_valid_identifier() or kind.to_utf8_buffer().size() != kind.length()):
		return false
	for index in range(1, value.size()):
		var argument: Variant = value[index]
		if argument is String and argument.to_utf8_buffer().size() <= MAX_COMMAND_TEXT: continue
		if argument is bool or ELLuaSave._integer(argument, -0x80000000, MAX_DAY): continue
		return false
	return true

## The authority responds to a guest request after applying the game rules.
func reply_command(day: int, request: int, accepted: bool, error: String) -> bool:
	if not live or not is_host or day < 1 or _pending_commands.get(request, 0) != day or not _valid_command_reply(accepted, error):
		return false
	if not _send(["command_reply", day, request, accepted, error]): return false
	_pending_commands.erase(request)
	return true

func _receive_command_reply(packet: Array) -> void:
	if (not live or is_host or packet.size() != 5
		or not ELLuaSave._integer(packet[1], 1, MAX_DAY) or not ELLuaSave._integer(packet[2], 1, MAX_DAY)
		or not _valid_command_reply(packet[3], packet[4])):
		_invalid()
		return
	var day := int(packet[1])
	var request := int(packet[2])
	if _pending_commands.get(request, 0) != day:
		_invalid()
		return
	_pending_commands.erase(request)
	command_replied.emit(day, request, packet[3], packet[4])

static func _valid_command_reply(accepted: Variant, error: Variant) -> bool:
	return (accepted is bool and error is String and error.to_utf8_buffer().size() <= MAX_COMMAND_ERROR
		and (not accepted or error.is_empty()))

func can_checkpoint() -> bool:
	return live and is_host and not _local_ready and not _remote_ready and _pending_commands.is_empty()

## Readiness is irrevocable until the host starts the next day.
func set_ready(day: int, ready: bool) -> bool:
	if not live or day != current_day or not ready or _local_ready: return false
	if not local_authority and not _send(["day_ready", day]): return false
	_local_ready = true
	readiness_changed.emit(local_player, day, true)
	return live and _failure.is_empty()

func send_leave() -> void:
	if live and _send(["leave"]): _peer.get_host().flush()

func open_local(map: ELAdventureMap, players: Array[int], day: int) -> void:
	local_authority = true
	is_host = true
	live = true
	_state = State.LIVE
	local_player = players[0]
	remote_player = players[1]
	current_day = day
	_bounds = Vector2i(map.width, map.height)

func finish_local_day(day: int) -> void:
	if local_authority and day == current_day + 1: _apply_snapshot(day, snapshot_revision)

func _receive_day_ready(packet: Array) -> void:
	if not live or _remote_ready or packet.size() != 2 or not ELLuaSave._integer(packet[1], current_day, current_day):
		_invalid()
		return
	_remote_ready = true
	readiness_changed.emit(remote_player, current_day, true)

func send_clock(kind: String, day: int) -> bool:
	return live and _setup.turn_seconds > 0 and day == current_day and _send([kind, day])

func _receive_clock(packet: Array) -> void:
	if (not live or _setup.turn_seconds <= 0 or packet.size() != 2
		or not ELLuaSave._integer(packet[1], current_day, current_day)
		or is_host != (packet[0] == "clock_open")):
		_invalid()
		return
	clock_event.emit(packet[0], current_day)

func publish_snapshot(day: int, document: Dictionary) -> bool:
	if not live or not is_host or not _valid_snapshot_day(day) or snapshot_revision == MAX_DAY or document.is_empty() or not _plain(document, 32, true):
		return false
	var data := JSON.stringify(document, "", true, true).to_utf8_buffer()
	if data.size() > MAX_SNAPSHOT: return false
	var compressed := data.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty() or compressed.size() + SNAPSHOT_HEADER > MAX_SNAPSHOT: return false
	var revision := snapshot_revision + 1
	var packet := PackedByteArray()
	packet.resize(SNAPSHOT_HEADER)
	packet[0] = SNAPSHOT_MARKER
	packet.encode_u32(1, revision)
	packet.encode_u32(5, day)
	packet.encode_u32(9, data.size())
	packet.append_array(compressed)
	if not _send_bytes(packet, CONTROL): return false
	_apply_snapshot(day, revision)
	return true

func _receive_snapshot(packet: PackedByteArray) -> void:
	if not live or is_host or packet.size() <= SNAPSHOT_HEADER or packet.size() > MAX_SNAPSHOT:
		_invalid()
		return
	var revision := packet.decode_u32(1)
	var day := packet.decode_u32(5)
	var size := packet.decode_u32(9)
	if revision != snapshot_revision + 1 or revision > MAX_DAY or not _valid_snapshot_day(day) or size < 2 or size > MAX_SNAPSHOT:
		_invalid()
		return
	var data := packet.slice(SNAPSHOT_HEADER).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if data.size() != size:
		_invalid()
		return
	var document: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not document is Dictionary or document.is_empty() or not _plain(document, 32):
		_invalid()
		return
	_apply_snapshot(day, revision)
	snapshot_received.emit(current_day, document)

func _valid_snapshot_day(day: int) -> bool:
	return day == current_day or (day == current_day + 1 and day <= MAX_DAY and _local_ready and _remote_ready)

func _apply_snapshot(day: int, revision: int) -> void:
	snapshot_revision = revision
	if day == current_day: return
	current_day = day
	_local_ready = false
	_remote_ready = false

func send_battle(battle_id: int, payload: Array) -> bool:
	if not live or battle_id < 1 or battle_id > MAX_DAY or payload.is_empty() or not _plain(payload, 8): return false
	return _send(["battle", battle_id, payload], BATTLE)

func _receive_battle(packet: Array) -> void:
	if packet.size() != 3 or packet[0] != "battle" or not ELLuaSave._integer(packet[1], 1, MAX_DAY) or not packet[2] is Array or packet[2].is_empty() or not _plain(packet[2], 8):
		_invalid()
		return
	if live:
		battle_received.emit(int(packet[1]), packet[2])
	elif _state == State.WAIT_START and _early_battle.size() < PACKETS_PER_POLL:
		# Reliable ordering is per channel. The first battle frame can beat
		# the control channel's start frame after the guest verified the map.
		_early_battle.append(packet)
	else:
		_invalid()

func _send(packet: Array, channel := CONTROL) -> bool:
	var bytes := JSON.stringify(packet, "", true, true).to_utf8_buffer()
	return bytes.size() <= MAX_CONTROL and _send_bytes(bytes, channel)

func _send_bytes(bytes: PackedByteArray, channel: int) -> bool:
	if _peer == null or _remote == 0 or not _failure.is_empty(): return false
	_peer.set_target_peer(_remote)
	_peer.transfer_channel = channel
	if _peer.put_packet(bytes) == OK: return true
	_failure = "The strategic network message could not be sent."
	return false

func abort(reason: String) -> void:
	if local_authority:
		close()
		closed.emit(reason)
		return
	if _peer != null and _failure.is_empty():
		_failure = reason if not reason.is_empty() else "The strategic session ended."

func _invalid() -> void:
	abort("Invalid or out-of-order strategic network message.")

func close() -> void:
	_stop_discovery()
	if _peer != null:
		if _state != State.REJECTED and _remote != 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			if _send(["leave"]): _peer.get_host().flush()
		_peer.close()
	_peer = null
	_profile = null
	_state = State.CLOSED
	_remote = 0
	_deadline = 0
	_startup_transport_until = 0
	_failure = ""
	_rejection = ""
	_departure = Departure.NONE
	_hello_sent = false
	_early_battle.clear()
	_setup.clear()
	_bounds = Vector2i.ZERO
	_local_ready = false
	_remote_ready = false
	_request_sequence = 0
	_pending_commands.clear()
	is_host = false
	live = false
	local_authority = false
	local_player = 0
	remote_player = 0
	current_day = 1
	snapshot_revision = 0

func _stop_discovery() -> void:
	if _discovery == null: return
	_discovery.close()
	_discovery = null

static func _compatible(packet: Array) -> bool:
	return packet[1] is String and packet[1] == PROTOCOL and ELLuaSave._integer(packet[2], VERSION, VERSION) and packet[3] is String and packet[3] == EDITION

static func _valid_profile(profile: ELProfile, port: int) -> bool:
	return profile != null and profile.id == EDITION and port >= 1024 and port <= 65535

static func _valid_map_id(value: Variant) -> bool:
	return value is String and value.length() <= 64 and value.is_valid_identifier() and value.to_utf8_buffer().size() == value.length()

static func _valid_hash(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number(false)

static func _map_hash(profile: ELProfile, map_id: String) -> String:
	var path := profile.file("Maps/" + map_id + ".map")
	return FileAccess.get_sha256(path) if not path.is_empty() else ""

static func _valid_players(map: ELAdventureMap, players: Vector2i) -> bool:
	if players.x == players.y: return false
	var seats := authored_seats(map)
	return players.x in seats and players.y in seats

## A commander can begin with a castle and use an authored summon spell to
## field the first hero. A starting hero also qualifies the authored seat.
static func authored_seats(map: ELAdventureMap) -> Array[int]:
	var seats: Array[int] = []
	if not ELXml.child(map.document, "campaign").is_empty(): return seats
	var owners := {}
	for item: Dictionary in map.objects:
		if item.group == "heroes" or ELFirstScenario.is_castle(item): owners[int(item.owner)] = true
	for player: Dictionary in map.players:
		var id := int(player.attrs.get("id", 0))
		if id > 0 and owners.has(id):
			seats.append(id)
			owners.erase(id)
	return seats

static func _plain(value: Variant, depth: int, save_keys := false) -> bool:
	if depth < 0: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING: return value.length() <= 1024 * 1024
		TYPE_ARRAY:
			if value.size() > 100000: return false
			for child: Variant in value:
				if not _plain(child, depth - 1, save_keys): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 100000: return false
			for key: Variant in value:
				if not key is String and not (save_keys and (key is int or key is StringName)): return false
				if key is int and value.has(str(key)): return false
				if str(key).length() > 1024 or not _plain(value[key], depth - 1, save_keys): return false
			return true
		_: return false
