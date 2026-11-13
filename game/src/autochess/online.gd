class_name ELAutochessOnline
extends RefCounted
## Online autochess over ENet (direct address or LAN). The host owns the
## match: guests send their actions by name, the host applies them with the
## same validated commands and sends the state back. Battles are not sent:
## every machine fights them itself from the same formations and seed, so a
## guest watches real-time battles without a stream of positions.

signal message(text: String)
signal lobby_changed
signal started(game: ELAutochessMatch, seat: int)
signal closed(reason: String)

const PORT := 27190
const VERSION := 3
const MAX_PACKET := 262144
const MAX_GUESTS := ELAutochessRules.PLAYER_COUNT - 1
const STATE_INTERVAL := 0.25
const HEARTBEAT := 1.0

var profile: ELProfile
var is_host := true
var game: ELAutochessMatch
var seat := 0
## Lobby rows: {"peer", "name", "character", "token"}; the host is row 0.
var lobby: Array[Dictionary] = []
var _peer: MultiplayerPeer
## A room code: play through the online relay instead of a direct address.
var relay_room := ""
var _joining := false
var _deadline := 0
var _dirty := false
var _since_state := 0.0
var _since_heartbeat := 0.0
var _sent_speed := 1.0
var _seats := {}
var _last_stage := ""
var _closed := false
## Seat by rejoin token, for guests who dropped out of a running match.
var _departed := {}
## Seat by peer for returning guests waiting for the current battle to end.
var _returning := {}
## Kept for the whole run, so a guest that drops can take its seat back.
static var _token := ""

static func token() -> String:
	if _token.is_empty(): _token = "%08x%08x" % [randi(), randi()]
	return _token

## A fingerprint of the creature data, so both sides fight identical lines.
static func signature(data: ELProfile) -> String:
	var parts := PackedStringArray()
	for line in ELAutochessRules.FAMILIES.size():
		for rank in 3:
			var code := ELAutochessRules.form(line, rank)
			var row := ELAutochessRules.stats(data, code, ELAutochessRules.tier(line), rank, line)
			parts.append("%s:%d:%d:%d:%.2f" % [code, int(row.health), roundi(float(row.damage) * 10), roundi(float(row.defense) * 10), float(row.interval)])
	return str(",".join(parts).hash())

## Splits "host", "host:port", "[ipv6]" or "[ipv6]:port" into [address, port].
## A bare IPv6 address has several colons and never carries a port.
static func parse_address(text: String) -> Array:
	var address := text.strip_edges()
	var port := PORT
	if address.begins_with("["):
		var close := address.find("]")
		if close > 0:
			var rest := address.substr(close + 1)
			address = address.substr(1, close - 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int(): port = int(rest.substr(1))
	elif address.count(":") == 1 and address.get_slice(":", 1).is_valid_int():
		port = int(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	return [address, port]

func host(data: ELProfile, port: int, name: String, character: String) -> Error:
	profile = data
	is_host = true
	seat = 0
	lobby = [{"peer": 1, "name": name, "character": character}]
	_open()
	var result := (_peer as ELRelayPeer).host_room(relay_room, MAX_GUESTS) if _peer is ELRelayPeer else (_peer as ENetMultiplayerPeer).create_server(port, MAX_GUESTS)
	if result != OK:
		close()
		return result
	message.emit(ELAutochessText.t(profile, "Waiting for players… %d joined.") % 0)
	return OK

func join(data: ELProfile, address: String, port: int, name: String, character: String) -> Error:
	profile = data
	is_host = false
	lobby = [{"peer": 0, "name": name, "character": character}]
	if relay_room.is_empty() and (address.is_empty() or address.length() > 253): return ERR_INVALID_PARAMETER
	if not relay_room.is_empty() and ELRelayPeer.clean_code(relay_room) != relay_room: return ERR_INVALID_PARAMETER
	_open()
	var result := (_peer as ELRelayPeer).join_room(relay_room) if _peer is ELRelayPeer else (_peer as ENetMultiplayerPeer).create_client(address, port)
	if result != OK:
		close()
		return result
	_joining = true
	_deadline = Time.get_ticks_msec() + 15000
	message.emit(ELAutochessText.t(profile, "Connecting…"))
	return OK

func _open() -> void:
	_closed = false
	_peer = ELRelayPeer.new() if not relay_room.is_empty() else ENetMultiplayerPeer.new()
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.peer_connected.connect(_connected)
	_peer.peer_disconnected.connect(_disconnected)

func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null

func _fail(reason: String) -> void:
	if _closed: return
	_closed = true
	close()
	closed.emit(reason)

func _connected(_id: int) -> void:
	pass

func _disconnected(id: int) -> void:
	if not is_host:
		if id == 1: _fail("The connection was lost.")
		return
	var token := ""
	for index in range(lobby.size() - 1, 0, -1):
		if int(lobby[index].peer) == id:
			token = String(lobby[index].get("token", ""))
			lobby.remove_at(index)
	_returning.erase(id)
	if _seats.has(id):
		# A departed guest's hero is played by the computer until it rejoins.
		var lost := int(_seats[id])
		_seats.erase(id)
		if game != null:
			game.controllers[lost] = "computer"
			game.bot_plans[lost] = ELAutochessBot.new_plan(lost)
			if not game.names[lost].ends_with(" (AI)"): game.names[lost] += " (AI)"
			if not token.is_empty() and game.companies[lost].health > 0: _departed[token] = lost
			_dirty = true
	lobby_changed.emit()

func _send(target: int, packet: Array) -> void:
	if _peer == null: return
	_peer.set_target_peer(target)
	_peer.put_packet(JSON.stringify(packet).to_utf8_buffer())

## Network work for both sides; the host also runs the match here.
func poll(delta: float) -> void:
	if _peer == null: return
	_peer.poll()
	if _peer == null: return
	if _joining and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_joining = false
		_send(1, ["hello", VERSION, signature(profile), String(lobby[0].name), String(lobby[0].character), token()])
	if is_host and _peer is ELRelayPeer and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var lost: String = (_peer as ELRelayPeer).close_reason
		_fail(lost if not lost.is_empty() else "Lost the connection to the online room.")
		return
	if _joining and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED and _peer is ELRelayPeer:
		var reason: String = (_peer as ELRelayPeer).close_reason
		_fail(reason if not reason.is_empty() else "Could not connect.")
		return
	if _joining and Time.get_ticks_msec() > _deadline:
		_fail("Could not connect.")
		return
	for _index in mini(64, _peer.get_available_packet_count()):
		if _peer == null: return
		var sender := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		var value: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() <= MAX_PACKET else null
		if not value is Array or value.is_empty(): continue
		if is_host: _host_receive(sender, value)
		else: _guest_receive(value)
	if is_host and game != null: _host_step(delta)

# --- Host -------------------------------------------------------------------

func _host_receive(sender: int, packet: Array) -> void:
	match String(packet[0]):
		"hello":
			if packet.size() < 6 or int(packet[1]) != VERSION or String(packet[2]) != signature(profile):
				_send(sender, ["refused", "The game differs from the host's. Use the same Etherlords II installation."])
				return
			var token := String(packet[5]).left(32)
			if game != null:
				_rejoin(sender, token)
				return
			if lobby.size() > MAX_GUESTS:
				_send(sender, ["refused", "The tournament is full."])
				return
			var name := String(packet[3]).strip_edges().left(24)
			if name.is_empty(): name = "Player %d" % lobby.size()
			lobby.append({"peer": sender, "name": name, "character": ELAutochessCharacters.valid(profile, String(packet[4])), "token": token})
			message.emit(ELAutochessText.t(profile, "Waiting for players… %d joined.") % (lobby.size() - 1))
			_broadcast_lobby()
		"cmd":
			if game == null or not _seats.has(sender) or packet.size() < 3 or not packet[2] is Array: return
			var who := int(_seats[sender])
			var op := String(packet[1])
			if op == "concede":
				for key: String in _departed.keys():
					if int(_departed[key]) == who: _departed.erase(key)
				game.companies[who].health = 0
				game.controllers[who] = "computer"
				game.bot_plans[who].done = true
				_dirty = true
				return
			var error := ELAutochessCommands.apply(game, who, op, packet[2])
			if not error.is_empty(): _send(sender, ["error", error])
			# No states go out during a fight, so a guest shopping then (a
			# refresh, a purchase, training) gets just its own company back.
			if game.stage == "fight" and op != "speed": _send(sender, ["company", game.companies[who].snapshot()])
			_dirty = true

## A guest that dropped out takes its hero back from the computer. During a
## battle it waits for the result, as battles are never sent.
func _rejoin(sender: int, token: String) -> void:
	if token.is_empty() or not _departed.has(token):
		_send(sender, ["refused", "The game has already started."])
		return
	var seat_index := int(_departed[token])
	_departed.erase(token)
	lobby.append({"peer": sender, "name": game.names[seat_index].trim_suffix(" (AI)"), "character": "", "token": token})
	_returning[sender] = seat_index
	if game.stage != "fight": _seat_returning()

func _seat_returning() -> void:
	for peer: int in _returning:
		var seat_index := int(_returning[peer])
		_seats[peer] = seat_index
		game.controllers[seat_index] = "remote"
		game.names[seat_index] = game.names[seat_index].trim_suffix(" (AI)")
		if game.stage == "prepare": game.ready[seat_index] = false
		_send(peer, ["start", seat_index, _state()])
		message.emit(ELAutochessText.t(profile, "%s rejoined the game.") % game.names[seat_index])
	_returning.clear()
	_dirty = true
	lobby_changed.emit()

func _broadcast_lobby() -> void:
	var rows := []
	for row in lobby: rows.append([String(row.name), String(row.character)])
	for row in lobby.slice(1): _send(int(row.peer), ["lobby", rows])
	lobby_changed.emit()

## Starts the tournament with everyone who joined; computer heroes fill the rest.
func start_match(seed_value: int) -> ELAutochessMatch:
	if not is_host or game != null: return game
	var seats: Array[String] = []
	var names: Array[String] = []
	var characters: Array[String] = []
	var taken: Array[String] = []
	for index in ELAutochessRules.PLAYER_COUNT:
		if index < lobby.size():
			seats.append("human" if index == 0 else "remote")
			names.append(String(lobby[index].name))
			var hero := String(lobby[index].character)
			if hero in taken: hero = ""
			characters.append(hero)
			if not hero.is_empty(): taken.append(hero)
		else:
			seats.append("computer")
			names.append("")
			characters.append("")
	var others := ELAutochessCharacters.opponents(profile, String(lobby[0].character), ELAutochessRules.PLAYER_COUNT, seed_value)
	for index in characters.size():
		if not characters[index].is_empty(): continue
		for hero: String in others:
			if hero not in taken:
				characters[index] = hero
				taken.append(hero)
				break
	game = ELAutochessMatch.new()
	game.auto_save = false
	game.begin(profile, seed_value, characters[0], seats, names, characters)
	for index in range(1, mini(lobby.size(), ELAutochessRules.PLAYER_COUNT)):
		_seats[int(lobby[index].peer)] = index
	game.changed.connect(func(): _dirty = true)
	game.fight_started.connect(_announce_fight)
	for peer: int in _seats: _send(peer, ["start", int(_seats[peer]), _state()])
	_last_stage = game.stage
	started.emit(game, 0)
	return game

func _state() -> Dictionary:
	var state := game.snapshot()
	state["live_stage"] = game.stage
	state["prepare_left"] = game.prepare_left
	state["ready"] = game.ready.duplicate()
	state["controllers"] = game.controllers.duplicate()
	state["speed"] = game.speed
	var results := {}
	for player: int in game.round_results:
		var row: Dictionary = game.round_results[player].duplicate(true)
		results[str(player)] = row
	state["results"] = results
	return state

func _host_step(delta: float) -> void:
	_since_state += delta
	_since_heartbeat += delta
	# Fights are announced with their own packet; states sent during a fight
	# would rewind the guests' boards.
	if game.speed != _sent_speed:
		_sent_speed = game.speed
		for peer: int in _seats: _send(peer, ["speed", game.speed])
	if game.stage == "fight": return
	if not _returning.is_empty(): _seat_returning()
	if (_dirty and _since_state >= STATE_INTERVAL) or _since_heartbeat >= HEARTBEAT or game.stage != _last_stage:
		_dirty = false
		_since_state = 0.0
		_since_heartbeat = 0.0
		_last_stage = game.stage
		var state := _state()
		for peer: int in _seats: _send(peer, ["state", state])

func _announce_fight() -> void:
	# The armies as they were at the bell, so every machine sets up the same battles.
	var state := _state()
	state["stage"] = "prepare"
	state["live_stage"] = "prepare"
	state["health"] = game.round_health.duplicate()
	for row: Dictionary in state.companies: row["stage"] = "prepare"
	for peer: int in _seats: _send(peer, ["fight", state])
	_last_stage = "fight"

# --- Guest ------------------------------------------------------------------

func send_command(op: String, args: Array) -> void:
	if is_host or _peer == null: return
	_send(1, ["cmd", op, args])

func _guest_receive(packet: Array) -> void:
	match String(packet[0]):
		"refused": _fail(String(packet[1]) if packet.size() > 1 else "Could not connect.")
		"lobby":
			if packet.size() < 2 or not packet[1] is Array: return
			lobby.clear()
			for row: Variant in packet[1]:
				if row is Array and row.size() >= 2: lobby.append({"peer": 0, "name": String(row[0]), "character": String(row[1])})
			message.emit(ELAutochessText.t(profile, "Waiting for the host to start."))
			lobby_changed.emit()
		"start":
			if packet.size() < 3 or not packet[2] is Dictionary: return
			seat = clampi(int(packet[1]), 1, ELAutochessRules.PLAYER_COUNT - 1)
			game = ELAutochessMatch.new()
			game.auto_save = false
			if not _apply_state(packet[2]):
				_fail("The game differs from the host's. Use the same Etherlords II installation.")
				return
			started.emit(game, seat)
		"state":
			if game == null or packet.size() < 2 or not packet[1] is Dictionary: return
			# A guest finishing its own copy of the battles keeps them until the host settles too.
			if game.stage == "fight": return
			_apply_state(packet[1])
		"fight":
			if game == null or packet.size() < 2 or not packet[1] is Dictionary: return
			if _apply_state(packet[1]): game.start_fight()
		"company":
			# Its own shop and purse changed during a battle: everything but the
			# health and stage this machine's battle is still deciding.
			if game == null or game.stage != "fight" or packet.size() < 2 or not packet[1] is Dictionary: return
			var own := game.companies[seat]
			var health := own.health
			var stage := own.stage
			if own.restore(profile, packet[1]):
				own.health = health
				own.stage = stage
				game.changed.emit()
		"speed":
			if game != null and packet.size() > 1 and (packet[1] is float or packet[1] is int):
				game.speed = 2.0 if float(packet[1]) >= 2.0 else 1.0
				game.changed.emit()
		"error":
			if packet.size() > 1: message.emit(ELAutochessText.t(profile, String(packet[1])))

func _apply_state(state: Dictionary) -> bool:
	var before := game.round_results.duplicate(true) if game != null else {}
	if not game.restore(profile, state): return false
	game.auto_save = false
	var controllers: Variant = state.get("controllers", [])
	for player in ELAutochessRules.PLAYER_COUNT:
		game.controllers[player] = "human" if player == seat else "remote"
	if controllers is Array and controllers.size() == ELAutochessRules.PLAYER_COUNT:
		for player in ELAutochessRules.PLAYER_COUNT:
			if player != seat and String(controllers[player]) == "computer": game.controllers[player] = "remote"
	var ready: Variant = state.get("ready", [])
	if ready is Array and ready.size() == ELAutochessRules.PLAYER_COUNT:
		for player in ELAutochessRules.PLAYER_COUNT: game.ready[player] = bool(ready[player])
	game.speed = 2.0 if float(state.get("speed", 1.0)) >= 2.0 else 1.0
	game.prepare_left = clampf(float(state.get("prepare_left", 0.0)), 0.0, ELAutochessRules.PREPARATION_SECONDS)
	var live := String(state.get("live_stage", game.stage))
	if live in ["prepare", "result", "over"]: game.stage = live
	game.result_left = 999.0
	var results: Variant = state.get("results", {})
	game.round_results.clear()
	if results is Dictionary and not results.is_empty():
		for key: Variant in results:
			if String(key).is_valid_int() and results[key] is Dictionary: game.round_results[int(key)] = results[key]
	elif game.stage != "prepare": game.round_results = before
	game.changed.emit()
	return true

## The guest's own copy of the battles; preparation and results follow the host.
func process_guest(delta: float) -> void:
	if game == null: return
	if game.stage == "fight": game.process(delta)
