class_name ELNetworkDiscovery
extends RefCounted
## IPv4 LAN discovery is separate from the ENet match. A waiting host answers
## local queries with its location, a mode-specific number, and match port.

const PORT := 27185
const MAGIC := "DemiurgesDuel"
const QUERY_INTERVAL := 1000
const SESSION_LIFETIME := 3500
const MAX_PACKET := 160
const MAX_SESSIONS := 32

var sessions: Dictionary = {}
var _socket := PacketPeerUDP.new()
var _service_port: int
var _service_name: String
var _version := ""
var _edition := ""
var _token := ""
var _match_port := 0
var _location := ""
var _detail := 0
var _max_detail := 0
var _next_query := 0

func _init(service_port := PORT, service_name := MAGIC) -> void:
	_service_port = service_port
	_service_name = service_name

func listen(version: int, edition: String, match_port: int, location: String, detail: int) -> Error:
	if location.contains("|") or location.to_utf8_buffer().size() > 64: return ERR_INVALID_PARAMETER
	_match_port = match_port
	_location = location
	_detail = detail
	return _bind(version, edition, _service_port)

func browse(version: int, edition: String, max_detail: int) -> Error:
	_match_port = 0
	_next_query = 0
	_max_detail = max_detail
	return _bind(version, edition, 0)

func _bind(version: int, edition: String, port: int) -> Error:
	close()
	_version = str(version)
	_edition = edition
	_token = Crypto.new().generate_random_bytes(8).hex_encode()
	var result := _socket.bind(port, "0.0.0.0")
	if result == OK: _socket.set_broadcast_enabled(true)
	return result

func close() -> void:
	_socket.close()
	sessions.clear()

## True when the browser list changes. Refreshes of the same host leave the
## UI selection alone.
func poll() -> bool:
	if not _socket.is_bound(): return false
	var now := Time.get_ticks_msec()
	if _match_port == 0 and now >= _next_query:
		var query := "|".join([_service_name, "Q", _version, _edition, _token])
		_send("255.255.255.255", _service_port, query)
		# Two instances on one machine can still find each other.
		_send("127.0.0.1", _service_port, query)
		_next_query = now + QUERY_INTERVAL
	var changed := false
	for i in mini(_socket.get_available_packet_count(), 32):
		var bytes := _socket.get_packet()
		if bytes.size() > MAX_PACKET: continue
		var parts := bytes.get_string_from_utf8().split("|")
		if parts.size() < 5 or parts[0] != _service_name or parts[2] != _version or parts[3] != _edition: continue
		var address := _socket.get_packet_ip()
		var port := _socket.get_packet_port()
		if _match_port != 0:
			if parts.size() != 5 or parts[1] != "Q" or not _valid_token(parts[4]): continue
			var reply := "|".join([_service_name, "A", _version, _edition, parts[4], _token, str(_match_port), _location, str(_detail)])
			_send(address, port, reply)
		elif port == _service_port and _receive(parts, address, now):
			changed = true
	for id: String in sessions.keys():
		if now >= int(sessions[id].expires):
			sessions.erase(id)
			changed = true
	return changed

func _receive(parts: PackedStringArray, address: String, now: int) -> bool:
	if parts.size() != 9 or parts[1] != "A" or parts[4] != _token or not _valid_token(parts[5]): return false
	if not parts[6].is_valid_int() or not parts[8].is_valid_int(): return false
	var port := int(parts[6])
	var detail := int(parts[8])
	if port < 1024 or port > 65535 or parts[7].is_empty() or detail < 1 or detail > _max_detail: return false
	var id := parts[5]
	var previous: Dictionary = sessions.get(id, {})
	if previous.is_empty() and sessions.size() >= MAX_SESSIONS: return false
	# Prefer loopback once received so two replies from a local host produce
	# one stable, directly reachable row.
	if previous.get("address") == "127.0.0.1": address = "127.0.0.1"
	var changed: bool = previous.is_empty() or previous.address != address or previous.port != port or previous.location != parts[7] or previous.detail != detail
	sessions[id] = {"address": address, "port": port, "location": parts[7], "detail": detail, "expires": now + SESSION_LIFETIME}
	return changed

func _send(address: String, port: int, packet: String) -> void:
	if _socket.set_dest_address(address, port) == OK: _socket.put_packet(packet.to_utf8_buffer())

static func _valid_token(token: String) -> bool:
	return token.length() == 16 and token.is_valid_hex_number(false)
