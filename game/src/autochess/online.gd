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
const VERSION := 4
const MAX_PACKET := 262144
const MAX_GUESTS := ELAutochessRules.PLAYER_COUNT - 1
const STATE_INTERVAL := 0.25
const HEARTBEAT := 1.0
const TOKEN_PATH := "user://autochess_token.txt"

var profile: ELProfile
var is_host := true
var game: ELAutochessMatch
var seat := 0
## Lobby rows: {"peer", "name", "character", "token"}; the host is row 0.
var lobby: Array[Dictionary] = []
var _peer: MultiplayerPeer
## A room code: play through the online relay instead of a direct address.
var relay_room := ""
## A guest is joining until the host answers its hello (a lobby, a seat,
## word that its seat waits for a battle, or a refusal); the connection
## timeout runs until then, not just until the transport connects.
var _joining := false
var _hello_sent := false
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
## The signature this machine sends or checks, worked out once per session.
var _signature := ""
## Rounds whose battles ended differently here than on the host (guests).
var divergences := 0
var _checked_round := 0
## Identifies this player to the host across a dropped connection or a
## restart, so a guest that drops can take its seat back.
static var _token := ""

static func token() -> String:
	if not _token.is_empty(): return _token
	if FileAccess.file_exists(TOKEN_PATH):
		var saved := FileAccess.get_file_as_string(TOKEN_PATH).strip_edges()
		if saved.length() == 32 and saved.is_valid_hex_number(): _token = saved
	if _token.is_empty():
		_token = Crypto.new().generate_random_bytes(16).hex_encode()
		var file := FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
		if file != null: file.store_string(_token)
	return _token

## A fingerprint of everything the battles depend on, so every machine of
## the table fights identical battles: the game version, the rule tables
## (lines, prices, pool, alliances, abilities, artifacts, creeps), every
## form's full combat values with its flags, ability and animation timing,
## and the outcome of a few fixed test battles, which also changes when the
## battle code does.
static func signature(data: ELProfile) -> String:
	var parts := {"game": str(ProjectSettings.get_setting("application/config/version", "")), "rules": ELAutochessRules.VERSION}
	for script: Script in [ELAutochessRules, ELAutochessAbilities, ELAutochessAlliances, ELAutochessArtifacts]:
		var constants := {}
		var table := script.get_script_constant_map()
		for key: String in table:
			if typeof(table[key]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_ARRAY, TYPE_DICTIONARY, TYPE_RECT2, TYPE_VECTOR2]:
				constants[key] = var_to_str(table[key])
		parts[script.get_global_name()] = constants
	var forms := {}
	for line in ELAutochessRules.FAMILIES.size():
		for rank in 3:
			var code := ELAutochessRules.form(line, rank)
			var row := ELAutochessRules.original(data, code)
			forms["%d:%d" % [line, rank]] = [code, ELAutochessRules.stats(data, code, ELAutochessRules.tier(line), rank, line),
				ELAutochessAbilities.clip_info(data, code), ELAutochessAlliances.traits(data, line),
				String(row.get("Race", "")), row.get("AtRange", 1.5), row.get("Scale", 1.0), row.get("Flags", [])]
	parts["forms"] = forms
	var creeps := []
	for round_number in range(1, 41):
		if not ELAutochessRules.is_creep_round(round_number): continue
		for placement: Dictionary in ELAutochessRules.creeps(round_number, 1):
			var code := String(placement.get("code", ""))
			creeps.append([round_number, placement, ELAutochessRules.stats(data, code, int(placement.get("tier", 1)), int(placement.get("rank", 0)), int(placement.get("family", -1))),
				ELAutochessAbilities.clip_info(data, code)])
	parts["creeps"] = creeps
	var fights := []
	for test in 3:
		var home := []
		var visitor := []
		for i in 4:
			var a := (test * 7 + i * 5) % ELAutochessRules.FAMILIES.size()
			var b := (test * 11 + i * 3 + 4) % ELAutochessRules.FAMILIES.size()
			home.append({"code": ELAutochessRules.form(a, test % 3), "family": a, "rank": test % 3, "tier": ELAutochessRules.tier(a), "point": [-5.0 - (i % 2) * 5.0, -6.0 + i * 4.0], "uid": i + 1, "item": ""})
			visitor.append({"code": ELAutochessRules.form(b, test % 3), "family": b, "rank": test % 3, "tier": ELAutochessRules.tier(b), "point": [5.0 + (i % 2) * 5.0, 6.0 - i * 4.0], "uid": 101 + i, "item": ""})
		home[0].item = ELAutochessArtifacts.RULES.keys()[test % ELAutochessArtifacts.RULES.size()]
		var battle := ELAutochessBattle.new()
		battle.setup(data, home, visitor, 4242 + test, 1 + test * 4)
		battle.run_to_end()
		fights.append([battle.winner, snappedf(battle.time, 0.001), battle.damage_by_uid(0), battle.damage_by_uid(1)])
	parts["fights"] = fights
	return JSON.stringify(parts, "", true, true).sha256_text()

## The part of a round's results every machine settles alike: who won each
## battle and the health it cost.
static func results_digest(results: Dictionary) -> String:
	var players := []
	for key: Variant in results:
		if str(key).is_valid_int(): players.append(int(key))
	players.sort()
	var rows := PackedStringArray()
	for player: int in players:
		var row: Variant = results.get(player, results.get(str(player), {}))
		if row is Dictionary: rows.append("%d:%d:%d" % [player, int(row.get("winner", -1)), int(row.get("health_lost", 0))])
	return ",".join(rows)

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
	_signature = signature(profile)
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
	_signature = signature(profile)
	_open()
	var result := (_peer as ELRelayPeer).join_room(relay_room) if _peer is ELRelayPeer else (_peer as ENetMultiplayerPeer).create_client(address, port)
	if result != OK:
		close()
		return result
	_joining = true
	_hello_sent = false
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
	if _joining and not _hello_sent and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_hello_sent = true
		_send(1, ["hello", VERSION, _signature, String(lobby[0].name), String(lobby[0].character), token()])
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
			if _signature.is_empty(): _signature = signature(profile)
			if packet.size() < 6 or not (packet[1] is int or packet[1] is float) or int(packet[1]) != VERSION or String(packet[2]) != _signature:
				_send(sender, ["refused", "The game differs from the host's. Use the same Etherlords II installation."])
				return
			var token := String(packet[5]).left(32)
			# A repeated hello from a connection already in the lobby or seated changes nothing.
			if _seats.has(sender) or _returning.has(sender): return
			if lobby.any(func(row: Dictionary) -> bool: return int(row.peer) == sender): return
			if game != null:
				_rejoin(sender, token)
				return
			if not token.is_empty() and lobby.any(func(row: Dictionary) -> bool: return String(row.get("token", "")) == token):
				_send(sender, ["refused", "This player has already joined the tournament."])
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
				game.forfeit(who)
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
	# The seat stays reserved for the token until the guest is seated, so a
	# return that drops while it waits for a battle can be tried again. A
	# newer connection with the same token replaces one still waiting.
	for peer: int in _returning.keys():
		if int(_returning[peer]) != seat_index: continue
		_returning.erase(peer)
		for index in range(lobby.size() - 1, 0, -1):
			if int(lobby[index].peer) == peer: lobby.remove_at(index)
		_send(peer, ["refused", "This player has joined again from another connection."])
		if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED: _peer.disconnect_peer(peer)
	lobby.append({"peer": sender, "name": game.names[seat_index].trim_suffix(" (AI)"), "character": "", "token": token})
	_returning[sender] = seat_index
	if game.stage != "fight": _seat_returning()
	else: _send(sender, ["waiting"])

func _seat_returning() -> void:
	for peer: int in _returning:
		var seat_index := int(_returning[peer])
		for key: String in _departed.keys():
			if int(_departed[key]) == seat_index: _departed.erase(key)
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
	if String(packet[0]) in ["lobby", "start", "waiting"]: _joining = false
	match String(packet[0]):
		"refused": _fail(String(packet[1]) if packet.size() > 1 else "Could not connect.")
		"waiting": message.emit(ELAutochessText.t(profile, "Waiting for the current battle to end…"))
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
			_compare_results(packet[1])
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

## Once per round, the battles this machine played against the host's
## settled results. The host's results count either way; a difference means
## the two machines do not run identical battles.
func _compare_results(state: Dictionary) -> void:
	if game == null or game.stage not in ["result", "over"] or game.round_results.is_empty(): return
	if not String(state.get("live_stage", "")) in ["result", "over"] or int(state.get("round", 0)) != game.round_number: return
	if _checked_round == game.round_number: return
	var results: Variant = state.get("results", {})
	if not results is Dictionary or results.is_empty(): return
	_checked_round = game.round_number
	if results_digest(results) == results_digest(game.round_results): return
	divergences += 1
	push_warning("Autochess round %d: local battle results %s, host %s" % [game.round_number, results_digest(game.round_results), results_digest(results)])
	message.emit(ELAutochessText.t(profile, "The battles on this machine ended differently from the host's. The host's results count."))

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
