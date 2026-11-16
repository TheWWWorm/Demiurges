extends SceneTree
## Headless multiplayer check: a host and a guest in one process connect over
## ENet on 127.0.0.1 for online autochess (Etherlords II), network duels (both
## editions) and the strategic game (Etherlords I), then exchange a few
## messages and confirm both sides stay in sync. Folders default to the ones
## saved in the game's settings:
##
##   godot --headless --path game --script ../tools/network_check.gd -- [--el1="C:/Games/Etherlords"] [--el2="C:/Games/Etherlords II"] [--relay=ws://127.0.0.1:8787/relay]
##
## With --relay every test runs a second time through that online relay
## (`npx wrangler dev` serves one locally from worker.js). --relay=local runs
## them through a stand-in for the relay in this process (LocalRelay below,
## the same rooms and routing as RelayRoom in worker.js), so the relay path
## is checked without the internet. Without --relay, the strategic game still
## plays once through the local stand-in, as it is the one that uses more
## than one channel.

var failures: Array[String] = []
var _local_relay: LocalRelay
## The room code of the current test when it runs through the relay.
var _room := ""

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.trim_prefix("--" + name + "=")
	return fallback

func _profile(id: String) -> ELProfile:
	var folder := _arg(id, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(id, ""))
	var p := ELProfile.new()
	if folder.is_empty() or not p.mount(id, folder): return null
	return p

## A relay room exists once the host is connected; guests join after that.
func _hosted(host: Object) -> void:
	await _wait(func(): return host._peer != null and host._peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, [func(): if host._peer != null: host._peer.poll()], 10.0)

func _wait(cond: Callable, polls: Array[Callable], seconds := 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if _local_relay != null: _local_relay.poll()
		for p in polls: p.call()
		if cond.call(): return true
		await process_frame
		OS.delay_msec(5)
	return false

func _run() -> void:
	var el1 := _profile("el1")
	var el2 := _profile("el2")
	check(el1 != null, "EL1 data mounted (pass --el1=<folder>)")
	check(el2 != null, "EL2 data mounted (pass --el2=<folder>)")
	var modes := [""]
	var relay := _arg("relay", "")
	var strategic_only := relay.is_empty()
	if relay.is_empty() or relay == "local":
		_local_relay = LocalRelay.new()
		var port := 27380
		while _local_relay.start(port) != OK and port < 27400: port += 1
		relay = "ws://127.0.0.1:%d/relay" % port
	OS.set_environment("DEMIURGES_RELAY", relay)
	modes.append(relay)
	for mode: String in modes:
		print("#### %s" % ("relay " + mode if not mode.is_empty() else "direct (ENet)"))
		var all := mode.is_empty() or not strategic_only
		if el2 != null and all:
			_room = ELRelayPeer.new_code() if not mode.is_empty() else ""
			await _autochess(el2)
		if el1 != null and all:
			_room = ELRelayPeer.new_code() if not mode.is_empty() else ""
			await _duel(el1, 27284)
		if el2 != null and all:
			_room = ELRelayPeer.new_code() if not mode.is_empty() else ""
			await _duel(el2, 27285)
		if el1 != null:
			_room = ELRelayPeer.new_code() if not mode.is_empty() else ""
			await _strategic(el1)
		if not mode.is_empty():
			# A room nobody hosts fails quickly with a reason.
			var lost := ELNetworkDuel.new()
			lost.relay_room = ELRelayPeer.new_code()
			var reason := [""]
			lost.closed.connect(func(r): reason[0] = r)
			lost.join(el1 if el1 != null else el2, "", ELNetworkDuel.PORT)
			await _wait(func(): return not reason[0].is_empty(), [func(): lost.poll(true)], 10.0)
			check(not reason[0].is_empty(), "relay: joining an empty room fails (%s)" % reason[0])
			lost.close()
	if _local_relay != null: _local_relay.stop()
	print("network check: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

# --- Autochess (EL2) -------------------------------------------------------
func _autochess(profile: ELProfile) -> void:
	print("== Autochess (EL2) ==")
	var host := ELAutochessOnline.new()
	host.relay_room = _room
	var guest := ELAutochessOnline.new()
	guest.relay_room = _room
	var log := []
	host.closed.connect(func(r): log.append("host closed: " + r))
	guest.closed.connect(func(r): log.append("guest closed: " + r))
	var guest_started := [false]
	guest.started.connect(func(_g, s): guest_started[0] = true; print("  guest seat ", s))
	check(host.host(profile, 27290, "Host", "") == OK, "autochess host opens port")
	await _hosted(host)
	check(guest.join(profile, "127.0.0.1", 27290, "Guest", "") == OK, "autochess guest starts connecting")
	var polls: Array[Callable] = [func(): host.poll(0.016), func(): guest.poll(0.016)]
	check(await _wait(func(): return host.lobby.size() == 2 and guest.lobby.size() == 2, polls), "autochess guest joins lobby (host sees %d, guest sees %d)" % [host.lobby.size(), guest.lobby.size()])
	var game := host.start_match(12345)
	check(game != null, "autochess host starts match")
	check(await _wait(func(): return guest_started[0], polls), "autochess guest receives start")
	if guest_started[0]:
		check(guest.game.stage == host.game.stage, "autochess stages match (%s / %s)" % [guest.game.stage, host.game.stage])
		# A guest command reaches the host.
		guest.send_command("ready", [])
		await _wait(func(): return host.game.ready[1], polls, 3.0)
		check(host.game.ready[1], "autochess guest 'ready' command reaches host")
		# During a battle (no states are sent then) a guest's refresh still
		# comes back to it, and the battle speed is shared by the table.
		host.game.companies[1].ether = 50
		host.game.start_fight()
		check(await _wait(func(): return guest.game.stage == "fight", polls), "autochess guest enters the battle")
		var shop_before: Array = guest.game.companies[1].shop.duplicate(true)
		guest.send_command("refresh", [])
		var refreshed := func() -> bool: return guest.game.companies[1].shop != shop_before and guest.game.companies[1].shop == host.game.companies[1].shop
		check(await _wait(refreshed, polls, 5.0), "autochess guest refresh during a battle reaches the guest")
		check(guest.game.stage == "fight", "autochess guest stays in its battle after shopping")
		guest.send_command("speed", [2.0])
		check(await _wait(func(): return host.game.speed == 2.0 and guest.game.speed == 2.0, polls, 5.0), "autochess guest's ×2 reaches the whole table")
		# The host settles the battle, so the rejoin below seats at once.
		# Both machines play the round's battles themselves; the guest
		# compares its results with the host's settled ones.
		var guard := 0
		while (host.game.stage == "fight" or guest.game.stage == "fight") and guard < 2000:
			if host.game.stage == "fight": host.game.process(0.5)
			if guest.game.stage == "fight": guest.process_guest(0.5)
			guard += 1
		var heard := []
		guest.message.connect(func(t): heard.append(t))
		await _wait(func(): return guest._checked_round == guest.game.round_number, polls, 5.0)
		check(guest._checked_round == host.game.round_number and guest.divergences == 0, "autochess guest's own battles match the host's results (%s)" % str(heard))
	for l in log: print("  ", l)
	check(log.is_empty(), "autochess no disconnects")
	if guest_started[0]:
		# The guest drops; the computer takes the hero until the guest rejoins.
		guest.close()
		await _wait(func(): return host.game.controllers[1] == "computer", [func(): host.poll(0.016)], 10.0)
		check(host.game.controllers[1] == "computer", "autochess computer takes a dropped guest's hero")
		# A stranger cannot take the seat.
		var own_token := ELAutochessOnline.token()
		ELAutochessOnline._token = "stranger"
		var stranger := ELAutochessOnline.new()
		stranger.relay_room = _room
		var refused := [""]
		stranger.closed.connect(func(r): refused[0] = r)
		stranger.join(profile, "127.0.0.1", 27290, "Stranger", "")
		await _wait(func(): return not refused[0].is_empty(), [func(): host.poll(0.016), func(): stranger.poll(0.016)], 10.0)
		check(refused[0] == "The game has already started.", "autochess stranger refused after start (%s)" % refused[0])
		stranger.close()
		ELAutochessOnline._token = own_token
		var back := ELAutochessOnline.new()
		back.relay_room = _room
		var back_seat := [-1]
		back.started.connect(func(_g, s): back_seat[0] = s)
		back.join(profile, "127.0.0.1", 27290, "Guest", "")
		await _wait(func(): return back_seat[0] >= 0, [func(): host.poll(0.016), func(): back.poll(0.016)], 10.0)
		check(back_seat[0] == 1 and host.game.controllers[1] == "remote" and not host.game.names[1].ends_with(" (AI)"), "autochess guest rejoins its own seat (seat %d)" % back_seat[0])
		back.close()
	guest.close(); host.close()
	# Join-box addresses.
	check(ELAutochessOnline.parse_address("example.org") == ["example.org", ELAutochessOnline.PORT], "address without port")
	check(ELAutochessOnline.parse_address("10.0.0.2:4000") == ["10.0.0.2", 4000], "IPv4 address with port")
	check(ELAutochessOnline.parse_address("fe80::1") == ["fe80::1", ELAutochessOnline.PORT], "bare IPv6 address")
	check(ELAutochessOnline.parse_address("[2001:db8::5]:4000") == ["2001:db8::5", 4000], "bracketed IPv6 address with port")
	check(ELAutochessOnline.parse_address("[::1]") == ["::1", ELAutochessOnline.PORT], "bracketed IPv6 address without port")

# --- Duel (EL1 / EL2) ------------------------------------------------------
func _duel(profile: ELProfile, port: int) -> void:
	var tag := profile.id.to_upper()
	print("== Network duel (%s) ==" % tag)
	var shipped := ELDuelPresets.shipped(profile)
	var arenas := ELDuelMatch.arenas(profile)
	var level := ELDuelCosts.resource_levels(profile).y
	if profile.id == "el2": level -= 1  # stay off the sandbox level
	var deck := ""
	for p in shipped:
		if ELDuelMatch.side_valid(shipped, p, level):
			deck = String(p.id); break
	check(not deck.is_empty() and not arenas.is_empty(), "%s duel has a preset (%s) and arena (%s)" % [tag, deck, arenas[0] if not arenas.is_empty() else "-"])
	var host := ELNetworkDuel.new()
	host.relay_room = _room
	var guest := ELNetworkDuel.new()
	guest.relay_room = _room
	var log := []
	host.closed.connect(func(r): log.append("host closed: " + r))
	guest.closed.connect(func(r): log.append("guest closed: " + r))
	host.message.connect(func(t): print("  host: ", t))
	guest.message.connect(func(t): print("  guest: ", t))
	var offered := [false]
	guest.offer_received.connect(func(_a, _b, _c, _d, _e): offered[0] = true)
	check(host.host(profile, port, deck, arenas[0], level, 1) == OK, "%s duel host opens port" % tag)
	await _hosted(host)
	check(guest.join(profile, "127.0.0.1", port) == OK, "%s duel guest starts connecting" % tag)
	var polls: Array[Callable] = [func(): host.poll(true), func(): guest.poll(true)]
	check(await _wait(func(): return offered[0], polls), "%s duel guest receives offer" % tag)
	if offered[0]:
		check(guest.confirm_preset(deck) == OK, "%s duel guest picks preset" % tag)
		check(await _wait(func(): return host.live and guest.live, polls), "%s duel both sides live" % tag)
	if host.live and guest.live:
		check(host._digest() == guest._digest(), "%s duel initial states identical" % tag)
		check(guest.send_chat("hello"), "%s duel chat send" % tag)
		await _wait(func(): return host.chat_history.size() > 0, polls, 3.0)
		check(host.chat_history.size() > 0, "%s duel chat received" % tag)
		var steps: int = await _phases(host, guest, polls, 6)
		check(steps >= 3, "%s duel %d phase changes applied on both sides" % [tag, steps])
		if host.duel != null and guest.duel != null:
			check(host._digest() == guest._digest(), "%s duel states identical after play" % tag)
		await _clock_authority(host, guest, polls, tag)
	for l in log: print("  ", l)
	check(log.is_empty(), "%s duel no disconnects/desync" % tag)
	if host.live and guest.live:
		await _duel_rejoin(profile, port, tag, host, guest, log)
	guest.close(); host.close()

## The host owns the turn clock: a guest that never ends its timed-out
## phase (here it keeps no clock at all) has it ended by the host.
func _clock_authority(host: ELNetworkDuel, guest: ELNetworkDuel, polls: Array[Callable], tag: String) -> void:
	var guard := 0
	while host.duel != null and host.duel.phase != ELDuel.Phase.FINISHED and host.duel.active_side() == 0 and guard < 6:
		guard += 1
		host.duel.end_phase()
		var target := host._sequence
		await _wait(func(): return guest._sequence == target and guest._pending.is_empty(), polls, 5.0)
	if host.duel == null or host.duel.phase == ELDuel.Phase.FINISHED or host.duel.active_side() != 1:
		check(false, "%s duel reaches a guest phase for the clock check" % tag)
		return
	var before := Vector2i(host.duel.turn_serial, host.duel.phase)
	host._turn_seconds = 10
	host.poll(true)
	host._clock_deadline = Time.get_ticks_msec() - 4000
	var moved := func() -> bool: return Vector2i(guest.duel.turn_serial, guest.duel.phase) != before and guest._sequence == host._sequence and guest._pending.is_empty()
	var ok: bool = await _wait(moved, polls, 5.0)
	host._turn_seconds = 0
	check(ok and host._digest() == guest._digest(), "%s duel host ends a guest's expired phase (%s -> %s)" % [tag, before, Vector2i(guest.duel.turn_serial, guest.duel.phase)])
	# The guest's own end of the phase crosses the host's forced end.
	guard = 0
	while host.duel.phase != ELDuel.Phase.FINISHED and host.duel.active_side() == 0 and guard < 6:
		guard += 1
		host.duel.end_phase()
		var target := host._sequence
		await _wait(func(): return guest._sequence == target and guest._pending.is_empty(), polls, 5.0)
	if host.duel.phase == ELDuel.Phase.FINISHED or host.duel.active_side() != 1: return
	before = Vector2i(host.duel.turn_serial, host.duel.phase)
	guest.duel.end_phase()
	host._force_phase_end()
	var settled := func() -> bool: return guest._sequence == host._sequence and guest._pending.is_empty() and host._pending.is_empty()
	await _wait(settled, polls, 3.0)
	await _wait(func(): return false, polls, 0.3)
	check(host.live and guest.live and host._digest() == guest._digest() and guest._sequence == host._sequence, "%s duel a guest's own phase end crossing the host's forced end stays in sync" % tag)

## Ends phases from whichever side is active; returns how many reached both sides.
func _phases(host: ELNetworkDuel, guest: ELNetworkDuel, polls: Array[Callable], count: int) -> int:
	var steps := 0
	for i in count:
		if host.duel == null or guest.duel == null or host.duel.phase == ELDuel.Phase.FINISHED: break
		var actor := host if host.duel.active_side() == 0 else guest
		var other := guest if actor == host else host
		actor.duel.end_phase()
		var target := actor._sequence
		await _wait(func(): return other._sequence == target and other._pending.is_empty(), polls, 5.0)
		if other._sequence != target: break
		steps += 1
	return steps

func _duel_rejoin(profile: ELProfile, port: int, tag: String, host: ELNetworkDuel, guest: ELNetworkDuel, log: Array) -> void:
	var notices := []
	host.connection_notice.connect(func(t): notices.append(t))
	# Drop the guest's connection without a goodbye.
	guest._remote = 0
	guest.close()
	await _wait(func(): return host._rejoin_deadline > 0, [func(): host.poll(true)], 10.0)
	check(host._rejoin_deadline > 0 and host.live, "%s duel host waits for a dropped guest" % tag)
	# The host keeps playing its own turn meanwhile.
	if host.duel.active_side() == 0: host.duel.end_phase()
	# The clock of the guest's phase (Etherlords II duels have one) stands
	# still while the guest is away: here
	# 1.5 s are left when it drops, and it stays away for 5 s.
	var held := host.duel.phase != ELDuel.Phase.FINISHED and host.duel.active_side() == 1 and ELNetworkDuel.valid_time_limit(profile, 10)
	if held:
		host._turn_seconds = 10
		host.poll(true)
		host._clock_deadline = Time.get_ticks_msec() + 1500
		await _wait(func(): return false, [func(): host.poll(true)], 5.0)
		var left := host._clock_deadline - Time.get_ticks_msec()
		check(left > 1000, "%s duel a guest's phase clock stands still while it is away (%d ms left)" % [tag, left])
	elif ELNetworkDuel.valid_time_limit(profile, 10): check(false, "%s duel reaches a guest phase for the away clock check" % tag)
	# Somebody else is turned away and the host keeps waiting.
	var own_token := ELNetworkDuel.player_token()
	ELNetworkDuel._token = "0".repeat(32)
	var stranger := ELNetworkDuel.new()
	stranger.relay_room = _room
	stranger.join(profile, "127.0.0.1", port)
	var stranger_closed := [""]
	stranger.closed.connect(func(r): stranger_closed[0] = r)
	await _wait(func(): return not stranger_closed[0].is_empty(), [func(): host.poll(true), func(): stranger.poll(true)], 10.0)
	check(stranger_closed[0] == "This duel is waiting for its own player to return." and host._rejoin_deadline > 0 and host.live, "%s duel stranger cannot take the seat (%s)" % [tag, stranger_closed[0]])
	stranger.close()
	ELNetworkDuel._token = own_token
	var back := ELNetworkDuel.new()
	back.relay_room = _room
	back.closed.connect(func(r): log.append("rejoined guest closed: " + r))
	back.join(profile, "127.0.0.1", port)
	var polls: Array[Callable] = [func(): host.poll(true), func(): back.poll(true)]
	check(await _wait(func(): return back.live and host._rejoin_deadline == 0, polls, 20.0), "%s duel guest rejoins" % tag)
	if back.live and held:
		var phase := Vector2i(host.duel.turn_serial, host.duel.phase)
		var remaining := back.clock_remaining()
		await _wait(func(): return false, polls, 0.3)
		check(remaining >= 1 and remaining <= 2 and Vector2i(host.duel.turn_serial, host.duel.phase) == phase and host.duel.active_side() == 1,
			"%s duel the returning guest gets the time it had left (%d s) and keeps its phase" % [tag, remaining])
		host._turn_seconds = 0
		back._turn_seconds = 0
	if back.live:
		check(back._digest() == host._digest() and back._sequence == host._sequence, "%s duel rejoined state identical" % tag)
		var steps: int = await _phases(host, back, polls, 4)
		check(steps >= 2 and back._digest() == host._digest(), "%s duel play continues in sync after rejoin (%d phases)" % [tag, steps])
	check(notices.size() == 2, "%s duel host told of drop and return (%s)" % [tag, notices])
	check(log.is_empty(), "%s duel no failures around rejoin %s" % [tag, log])
	back.close()

# --- Strategic (EL1) -------------------------------------------------------
func _strategic(profile: ELProfile) -> void:
	print("== Strategic (EL1) ==")
	var maps := ELStrategicLobby.catalogue(profile)
	check(not maps.is_empty(), "EL1 strategic has %d eligible maps" % maps.size())
	if maps.is_empty(): return
	var entry: Dictionary = maps[0]
	print("  map ", entry.id, " seats ", entry.seats)
	var host := ELNetworkStrategy.new()
	host.relay_room = _room
	var guest := ELNetworkStrategy.new()
	guest.relay_room = _room
	var log := []
	host.closed.connect(func(r): log.append("host closed: " + r))
	guest.closed.connect(func(r): log.append("guest closed: " + r))
	var players := Vector2i(entry.seats[0].id, entry.seats[1].id)
	check(host.host(profile, entry.id, 27296, players, 1, 4242) == OK, "strategic host opens port")
	await _hosted(host)
	check(guest.join(profile, "127.0.0.1", 27296) == OK, "strategic guest starts connecting")
	var polls: Array[Callable] = [func(): host.poll(), func(): guest.poll()]
	check(await _wait(func(): return host.live and guest.live, polls, 30.0), "strategic both sides live")
	if host.live and guest.live:
		check(guest.local_player == players.y and host.local_player == players.x, "strategic seats assigned")
		var got := [null]
		guest.snapshot_received.connect(func(_d, doc): got[0] = doc)
		check(host.publish_snapshot(host.current_day, {"probe": 1}), "strategic host publishes snapshot")
		await _wait(func(): return got[0] != null, polls, 5.0)
		check(got[0] != null and int(got[0].probe) == 1, "strategic guest receives snapshot")
		var plans := []
		host.plan_received.connect(func(p, _d, plan): plans.append(p))
		check(guest.submit_plan(guest.current_day, [[0, -1, -1, -1]]), "strategic guest submits plan")
		await _wait(func(): return not plans.is_empty(), polls, 5.0)
		check(plans == [players.y], "strategic host receives guest plan")
		# Battle frames travel on their own channel.
		var battles := []
		guest.battle_received.connect(func(id, payload): battles.append([id, payload]))
		check(host.send_battle(3, ["probe", "seven"]), "strategic host sends a battle frame")
		await _wait(func(): return not battles.is_empty(), polls, 5.0)
		check(battles.size() == 1 and int(battles[0][0]) == 3 and battles[0][1] == ["probe", "seven"], "strategic guest receives the battle frame (%s)" % str(battles))
	for l in log: print("  ", l)
	check(log.is_empty(), "strategic no disconnects")
	guest.close(); host.close()

# --- Local relay ------------------------------------------------------------
## A stand-in for the online relay (RelayRoom in worker.js) on 127.0.0.1:
## the same rooms, ids and routing, without the rate limits. The host is
## peer 1; each binary frame's leading u32 is the target when sent and the
## sender when delivered; guests reach only the host, the host one guest or
## all of them with 0. Text frames are welcome/join/leave from the relay
## and refuse/kick from the host.
class LocalRelay:
	var _server := TCPServer.new()
	## Connections: {"ws", "room", "id", "open"}; id 0 until admitted.
	var _sockets: Array[Dictionary] = []
	## Rooms by code: {"max", "refuse", "next"}.
	var _rooms := {}

	func start(port: int) -> Error:
		return _server.listen(port, "127.0.0.1")

	func stop() -> void:
		for s: Dictionary in _sockets: s.ws.close()
		_sockets.clear()
		_server.stop()

	func poll() -> void:
		while _server.is_connection_available():
			var ws := WebSocketPeer.new()
			ws.inbound_buffer_size = ELRelayPeer.BUFFER
			ws.outbound_buffer_size = ELRelayPeer.BUFFER
			ws.max_queued_packets = 8192
			if ws.accept_stream(_server.take_connection()) == OK: _sockets.append({"ws": ws, "room": "", "id": 0, "open": false})
		for s: Dictionary in _sockets.duplicate():
			var ws: WebSocketPeer = s.ws
			ws.poll()
			var state := ws.get_ready_state()
			if state == WebSocketPeer.STATE_OPEN and not s.open:
				s.open = true
				_admit(s)
			while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and int(s.id) > 0 and ws.get_available_packet_count() > 0:
				var bytes := ws.get_packet()
				if ws.was_string_packet(): _control(s, bytes.get_string_from_utf8())
				else: _route(s, bytes)
			if state == WebSocketPeer.STATE_CLOSED:
				_sockets.erase(s)
				_left(s)

	func _query(url: String) -> Dictionary:
		var values := {}
		var at := url.find("?")
		if at < 0: return values
		for pair: String in url.substr(at + 1).split("&"):
			values[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode()
		return values

	func _in_room(room: String) -> Array[Dictionary]:
		var found: Array[Dictionary] = []
		for s: Dictionary in _sockets:
			if s.room == room and int(s.id) > 0: found.append(s)
		return found

	func _peer(room: String, id: int) -> Dictionary:
		for s: Dictionary in _in_room(room):
			if int(s.id) == id: return s
		return {}

	func _admit(s: Dictionary) -> void:
		var ws: WebSocketPeer = s.ws
		var query := _query(ws.get_requested_url())
		var room := String(query.get("room", "")).to_upper()
		var role := String(query.get("role", ""))
		if ELRelayPeer.clean_code(room) != room or role not in ["host", "guest"] or String(query.get("v", "")) != str(ELRelayPeer.VERSION):
			ws.close(4400, "Invalid room.")
			return
		var host := _peer(room, 1)
		var id := 1
		if role == "host":
			if not host.is_empty():
				ws.close(4409, "This room is already hosted.")
				return
			_rooms[room] = {"max": clampi(int(query.get("max", "1")), 1, 8), "refuse": false, "next": 2}
		else:
			if host.is_empty():
				ws.close(4404, "No game is hosted in this room.")
				return
			var settings: Dictionary = _rooms[room]
			if settings.refuse or _in_room(room).size() - 1 >= int(settings.max):
				ws.close(4403, "This room is full.")
				return
			id = int(settings.next)
			settings.next = id + 1
		s.room = room
		s.id = id
		ws.send_text(JSON.stringify({"t": "welcome", "id": id}))
		if id != 1: host.ws.send_text(JSON.stringify({"t": "join", "id": id}))

	func _control(s: Dictionary, text: String) -> void:
		if int(s.id) != 1: return
		var control: Variant = JSON.parse_string(text)
		if not control is Dictionary: return
		if control.get("t") == "refuse": _rooms[s.room].refuse = bool(control.get("on", false))
		elif control.get("t") == "kick":
			var guest := _peer(s.room, int(control.get("id", 0)))
			if not guest.is_empty() and int(guest.id) > 1: guest.ws.close(4000, "Removed by the host.")

	func _route(s: Dictionary, bytes: PackedByteArray) -> void:
		if bytes.size() < ELRelayPeer.HEADER: return
		var target := bytes.decode_u32(0)
		var from := int(s.id)
		bytes.encode_u32(0, from)
		for other: Dictionary in _in_room(s.room):
			if other == s: continue
			var to := int(other.id)
			if (from != 1 and to == 1 and target == 1) or (from == 1 and (target == 0 or target == to)):
				other.ws.put_packet(bytes)

	func _left(s: Dictionary) -> void:
		var id := int(s.id)
		if id == 0: return
		s.id = 0
		for other: Dictionary in _in_room(s.room):
			if id == 1: other.ws.close(4001, "The host left.")
			elif int(other.id) == 1: other.ws.send_text(JSON.stringify({"t": "leave", "id": id}))
