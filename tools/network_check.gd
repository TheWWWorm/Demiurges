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
## (`npx wrangler dev` serves one locally from worker.js).

var failures: Array[String] = []
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
	if not relay.is_empty():
		OS.set_environment("DEMIURGES_RELAY", relay)
		modes.append(relay)
	for mode: String in modes:
		print("#### %s" % ("relay " + mode if not mode.is_empty() else "direct (ENet)"))
		if el2 != null:
			_room = ELRelayPeer.new_code() if not mode.is_empty() else ""
			await _autochess(el2)
		if el1 != null:
			_room = ELRelayPeer.new_code() if not mode.is_empty() else ""
			await _duel(el1, 27284)
		if el2 != null:
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
		var guard := 0
		while host.game.stage == "fight" and guard < 2000:
			host.game.process(0.5)
			guard += 1
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
	for l in log: print("  ", l)
	check(log.is_empty(), "%s duel no disconnects/desync" % tag)
	if host.live and guest.live:
		await _duel_rejoin(profile, port, tag, host, guest, log)
	guest.close(); host.close()

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
	for l in log: print("  ", l)
	check(log.is_empty(), "strategic no disconnects")
	guest.close(); host.close()
