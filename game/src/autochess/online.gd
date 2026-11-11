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
const VERSION := 1
const MAX_PACKET := 262144
const MAX_GUESTS := ELAutochessRules.PLAYER_COUNT - 1
const STATE_INTERVAL := 0.25
const HEARTBEAT := 1.0

var profile: ELProfile
var is_host := true
var game: ELAutochessMatch
var seat := 0
## Lobby rows: {"peer", "name", "character"}; the host is row 0.
var lobby: Array[Dictionary] = []
var _peer: ENetMultiplayerPeer
var _joining := false
var _deadline := 0
var _dirty := false
var _since_state := 0.0
var _since_heartbeat := 0.0
var _seats := {}
var _last_stage := ""
var _closed := false

## A fingerprint of the creature data, so both sides fight identical lines.
static func signature(data: ELProfile) -> String:
	var parts := PackedStringArray()
	for line in ELAutochessRules.FAMILIES.size():
		for rank in 3:
			var code := ELAutochessRules.form(line, rank)
			var row := ELAutochessRules.stats(data, code, ELAutochessRules.tier(line), rank, line)
			parts.append("%s:%d:%d:%d:%.2f" % [code, int(row.health), roundi(float(row.damage) * 10), roundi(float(row.defense) * 10), float(row.interval)])
	return str(",".join(parts).hash())

func host(data: ELProfile, port: int, name: String, character: String) -> Error:
	profile = data
	is_host = true
	seat = 0
	lobby = [{"peer": 1, "name": name, "character": character}]
	_open()
	var result := _peer.create_server(port, MAX_GUESTS)
	if result != OK:
		close()
		return result
	message.emit(ELAutochessText.t(profile, "Waiting for players… %d joined.") % 0)
	return OK

func join(data: ELProfile, address: String, port: int, name: String, character: String) -> Error:
	profile = data
	is_host = false
	lobby = [{"peer": 0, "name": name, "character": character}]
	if address.is_empty() or address.length() > 253: return ERR_INVALID_PARAMETER
	_open()
	var result := _peer.create_client(address, port)
	if result != OK:
		close()
		return result
	_joining = true
	_deadline = Time.get_ticks_msec() + 15000
	message.emit(ELAutochessText.t(profile, "Connecting…"))
	return OK

func _open() -> void:
	_closed = false
	_peer = ENetMultiplayerPeer.new()
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
	for index in range(lobby.size() - 1, 0, -1):
		if int(lobby[index].peer) == id: lobby.remove_at(index)
	if _seats.has(id):
		# A departed guest's hero is played by the computer from now on.
		var lost := int(_seats[id])
		_seats.erase(id)
		if game != null:
			game.controllers[lost] = "computer"
			game.bot_plans[lost] = ELAutochessBot.new_plan(lost)
			game.names[lost] += " (AI)"
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
		_send(1, ["hello", VERSION, signature(profile), String(lobby[0].name), String(lobby[0].character)])
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
			if game != null or packet.size() < 5 or lobby.size() > MAX_GUESTS:
				_send(sender, ["refused", "The game has already started."])
				return
			if int(packet[1]) != VERSION or String(packet[2]) != signature(profile):
				_send(sender, ["refused", "The game differs from the host's. Use the same Etherlords II installation."])
				return
			var name := String(packet[3]).strip_edges().left(24)
			if name.is_empty(): name = "Player %d" % lobby.size()
			lobby.append({"peer": sender, "name": name, "character": ELAutochessCharacters.valid(profile, String(packet[4]))})
			message.emit(ELAutochessText.t(profile, "Waiting for players… %d joined.") % (lobby.size() - 1))
			_broadcast_lobby()
		"cmd":
			if game == null or not _seats.has(sender) or packet.size() < 3 or not packet[2] is Array: return
			var who := int(_seats[sender])
			var op := String(packet[1])
			if op == "concede":
				game.companies[who].health = 0
				game.controllers[who] = "computer"
				game.bot_plans[who].done = true
				_dirty = true
				return
			var error := ELAutochessCommands.apply(game, who, op, packet[2])
			if not error.is_empty(): _send(sender, ["error", error])
			_dirty = true

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
	if game.stage == "fight": return
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
