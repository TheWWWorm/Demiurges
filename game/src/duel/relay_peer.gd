class_name ELRelayPeer
extends MultiplayerPeerExtension
## Online play through the Demiurges relay (a WebSocket room on the website),
## so nobody has to open a port and the browser build can play too. It stands
## in for ENetMultiplayerPeer: the host is peer 1, guests get ids from the
## relay, and every packet is delivered reliably and in order. Frames are
## [u32 peer][u8 channel][u8 flags][data]; large packets travel as several
## frames with flag 1 on all but the last.

const URL := "wss://demiurges.wwworm.com/relay"
const VERSION := 1
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const FRAME := 256 * 1024
const BUFFER := 8 * 1024 * 1024
const MAX_PACKET := 16 * 1024 * 1024
const HEADER := 6

var close_reason := ""
var _socket := WebSocketPeer.new()
var _id := 0
var _server := false
var _status := CONNECTION_DISCONNECTED
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _refuse := false
var _peers := {}
var _incoming: Array[Array] = []
var _partial := {}

## The relay address; DEMIURGES_RELAY overrides it for a local test server.
static func relay_url() -> String:
	var custom := OS.get_environment("DEMIURGES_RELAY")
	return custom if not custom.is_empty() else URL

static func new_code() -> String:
	var code := ""
	var bytes := Crypto.new().generate_random_bytes(CODE_LENGTH)
	for value in bytes: code += CODE_LETTERS[value % CODE_LETTERS.length()]
	return code

## Room codes are typed by players: spaces and case do not matter.
static func clean_code(text: String) -> String:
	var code := text.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if code.length() != CODE_LENGTH: return ""
	for letter in code:
		if not CODE_LETTERS.contains(letter): return ""
	return code

func host_room(code: String, max_guests: int) -> Error:
	_server = true
	return _connect("%s?room=%s&role=host&max=%d&v=%d" % [relay_url(), code, max_guests, VERSION])

func join_room(code: String) -> Error:
	_server = false
	return _connect("%s?room=%s&role=guest&v=%d" % [relay_url(), code, VERSION])

func _connect(url: String) -> Error:
	_socket.inbound_buffer_size = BUFFER
	_socket.outbound_buffer_size = BUFFER
	_socket.max_queued_packets = 8192
	var result := _socket.connect_to_url(url)
	if result == OK: _status = CONNECTION_CONNECTING
	return result

## Sends what is queued now (before closing, for a last goodbye message).
func flush() -> void:
	_socket.poll()

func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED: return
	_socket.poll()
	# Frames that arrived just before the room closed (such as the reason a
	# host turned this player away) are still read.
	while _socket.get_available_packet_count() > 0:
		var bytes := _socket.get_packet()
		if _socket.was_string_packet(): _control(bytes.get_string_from_utf8())
		else: _frame(bytes)
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		close_reason = _socket.get_close_reason()
		if close_reason.is_empty() and _id == 0: close_reason = "Could not reach the room. Check the code."
		_drop_all()

func _control(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary: return
	var id := int(message.get("id", 0))
	match String(message.get("t", "")):
		"welcome":
			_id = id
			_status = CONNECTION_CONNECTED
			if not _server:
				_peers[1] = true
				peer_connected.emit(1)
		"join":
			if _server and id > 1 and not _peers.has(id):
				_peers[id] = true
				peer_connected.emit(id)
		"leave":
			if _peers.erase(id): peer_disconnected.emit(id)

func _frame(bytes: PackedByteArray) -> void:
	if bytes.size() < HEADER: return
	var from := bytes.decode_u32(0)
	if not _peers.has(from): return
	var key := from * 256 + bytes[4]
	var data: PackedByteArray = _partial.get(key, PackedByteArray())
	data.append_array(bytes.slice(HEADER))
	if data.size() > MAX_PACKET:
		_partial.erase(key)
		return
	if bytes[5] & 1:
		_partial[key] = data
		return
	_partial.erase(key)
	_incoming.append([from, bytes[4], data])

func _drop_all() -> void:
	_status = CONNECTION_DISCONNECTED
	var lost := _peers.keys()
	_peers.clear()
	_partial.clear()
	for id: int in lost: peer_disconnected.emit(id)

func _get_available_packet_count() -> int:
	return _incoming.size()

func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty(): return PackedByteArray()
	return _incoming.pop_front()[2]

func _get_packet_peer() -> int:
	return _incoming[0][0] if not _incoming.is_empty() else 0

func _get_packet_channel() -> int:
	return _incoming[0][1] if not _incoming.is_empty() else 0

func _get_packet_mode() -> TransferMode:
	return TRANSFER_MODE_RELIABLE

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED: return ERR_UNCONFIGURED
	if buffer.size() > MAX_PACKET: return ERR_OUT_OF_MEMORY
	var target := _target if _server else 1
	var offset := 0
	while true:
		var piece := buffer.slice(offset, offset + FRAME)
		offset += piece.size()
		var frame := PackedByteArray()
		frame.resize(HEADER)
		frame.encode_u32(0, maxi(target, 0))
		frame[4] = _channel & 0xff
		frame[5] = 1 if offset < buffer.size() else 0
		frame.append_array(piece)
		var result := _socket.put_packet(frame)
		if result != OK: return result
		if offset >= buffer.size(): return OK
	return OK

func _get_max_packet_size() -> int:
	return MAX_PACKET

func _set_target_peer(peer: int) -> void:
	_target = peer

func _get_unique_id() -> int:
	return _id

func _is_server() -> bool:
	return _server

func _get_connection_status() -> ConnectionStatus:
	return _status

func _close() -> void:
	if _socket.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]: _socket.close()
	_status = CONNECTION_DISCONNECTED
	_peers.clear()
	_incoming.clear()
	_partial.clear()

func _disconnect_peer(peer: int, _force: bool) -> void:
	if not _server or not _peers.erase(peer): return
	_socket.send_text(JSON.stringify({"t": "kick", "id": peer}))
	peer_disconnected.emit(peer)

func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable
	if _server and _status == CONNECTION_CONNECTED: _socket.send_text(JSON.stringify({"t": "refuse", "on": enable}))

func _is_refusing_new_connections() -> bool:
	return _refuse

func _is_server_relay_supported() -> bool:
	return false

func _set_transfer_channel(channel: int) -> void:
	_channel = channel

func _get_transfer_channel() -> int:
	return _channel

func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode

func _get_transfer_mode() -> TransferMode:
	return _mode
