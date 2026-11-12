extends SceneTree
## Headless multiplayer check: a host and a guest in one process connect over
## ENet on 127.0.0.1 for online autochess (Etherlords II), network duels (both
## editions) and the strategic game (Etherlords I), then exchange a few
## messages and confirm both sides stay in sync. Folders default to the ones
## saved in the game's settings:
##
##   godot --headless --path game --script ../tools/network_check.gd -- [--el1="C:/Games/Etherlords"] [--el2="C:/Games/Etherlords II"]

var failures: Array[String] = []

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
	if el2 != null: await _autochess(el2)
	if el1 != null: await _duel(el1, 27284)
	if el2 != null: await _duel(el2, 27285)
	if el1 != null: await _strategic(el1)
	print("network check: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

# --- Autochess (EL2) -------------------------------------------------------
func _autochess(profile: ELProfile) -> void:
	print("== Autochess (EL2) ==")
	var host := ELAutochessOnline.new()
	var guest := ELAutochessOnline.new()
	var log := []
	host.closed.connect(func(r): log.append("host closed: " + r))
	guest.closed.connect(func(r): log.append("guest closed: " + r))
	var guest_started := [false]
	guest.started.connect(func(_g, s): guest_started[0] = true; print("  guest seat ", s))
	check(host.host(profile, 27290, "Host", "") == OK, "autochess host opens port")
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
	for l in log: print("  ", l)
	check(log.is_empty(), "autochess no disconnects")
	guest.close(); host.close()

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
	var guest := ELNetworkDuel.new()
	var log := []
	host.closed.connect(func(r): log.append("host closed: " + r))
	guest.closed.connect(func(r): log.append("guest closed: " + r))
	host.message.connect(func(t): print("  host: ", t))
	guest.message.connect(func(t): print("  guest: ", t))
	var offered := [false]
	guest.offer_received.connect(func(_a, _b, _c, _d, _e): offered[0] = true)
	check(host.host(profile, port, deck, arenas[0], level, 1) == OK, "%s duel host opens port" % tag)
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
		# Pass a few phases from whichever side is active; every step must stay in sync.
		var steps := 0
		for i in 6:
			if host.duel == null or guest.duel == null or host.duel.phase == ELDuel.Phase.FINISHED: break
			var active := host.duel.active_side()
			var actor := host if active == 0 else guest
			actor.duel.end_phase()
			var target := actor._sequence
			var other := guest if actor == host else host
			await _wait(func(): return other._sequence == target and other._pending.is_empty(), polls, 5.0)
			if other._sequence != target: break
			steps += 1
		check(steps >= 3, "%s duel %d phase changes applied on both sides" % [tag, steps])
		if host.duel != null and guest.duel != null:
			check(host._digest() == guest._digest(), "%s duel states identical after play" % tag)
	for l in log: print("  ", l)
	check(log.is_empty(), "%s duel no disconnects/desync" % tag)
	guest.close(); host.close()

# --- Strategic (EL1) -------------------------------------------------------
func _strategic(profile: ELProfile) -> void:
	print("== Strategic (EL1) ==")
	var maps := ELStrategicLobby.catalogue(profile)
	check(not maps.is_empty(), "EL1 strategic has %d eligible maps" % maps.size())
	if maps.is_empty(): return
	var entry: Dictionary = maps[0]
	print("  map ", entry.id, " seats ", entry.seats)
	var host := ELNetworkStrategy.new()
	var guest := ELNetworkStrategy.new()
	var log := []
	host.closed.connect(func(r): log.append("host closed: " + r))
	guest.closed.connect(func(r): log.append("guest closed: " + r))
	var players := Vector2i(entry.seats[0].id, entry.seats[1].id)
	check(host.host(profile, entry.id, 27296, players, 1, 4242) == OK, "strategic host opens port")
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
