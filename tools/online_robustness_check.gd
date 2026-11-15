extends SceneTree
## Headless checks of online play and replay robustness that need no second
## machine: the autochess host's handshake and rejoin bookkeeping, its
## compatibility signature and per-round result comparison, the persisted
## reconnect identity, the relay peer's buffering limits and the terminal
## check of Duel mode replays. Folders default to the ones saved in the
## game's settings:
##
##   godot --headless --path game --script ../tools/online_robustness_check.gd -- [--el2="C:/Games/Etherlords II"]

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

func _run() -> void:
	var el2 := _profile("el2")
	check(el2 != null, "EL2 data mounted (pass --el2=<folder>)")
	if el2 != null:
		_handshake(el2)
		_rejoin_token(el2)
		_signature(el2)
		_result_digests(el2)
		_replay_terminal(el2)
	_persisted_token()
	_relay_limits()
	print("online robustness check: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)

func _hello(online: ELAutochessOnline, profile: ELProfile, token: String, name := "Guest") -> Array:
	return ["hello", ELAutochessOnline.VERSION, ELAutochessOnline.signature(profile), name, "", token]

## A host without a network: its replies go nowhere, its bookkeeping is real.
func _offline_host(profile: ELProfile) -> ELAutochessOnline:
	var online := ELAutochessOnline.new()
	online.profile = profile
	online.is_host = true
	online.lobby = [{"peer": 1, "name": "Host", "character": ""}]
	return online

func _peers(online: ELAutochessOnline) -> Array:
	return online.lobby.map(func(row: Dictionary) -> int: return int(row.peer))

func _handshake(profile: ELProfile) -> void:
	print("== Autochess handshake ==")
	var online := _offline_host(profile)
	var token := "a".repeat(32)
	online._host_receive(42, _hello(online, profile, token))
	online._host_receive(42, _hello(online, profile, token))
	check(_peers(online) == [1, 42], "a repeated hello keeps one lobby row (%s)" % str(_peers(online)))
	online._host_receive(43, _hello(online, profile, token, "Copy"))
	check(_peers(online) == [1, 42], "a second connection with a joined player's token is refused (%s)" % str(_peers(online)))
	online._host_receive(44, _hello(online, profile, "b".repeat(32), "Other"))
	check(_peers(online) == [1, 42, 44], "another player joins (%s)" % str(_peers(online)))
	var game := online.start_match(321)
	online._host_receive(42, _hello(online, profile, token))
	check(_peers(online) == [1, 42, 44] and online._seats.size() == 2, "a repeated hello after the start changes nothing")
	check(game != null and game.controllers[1] == "remote", "the seated guest stays seated")

func _rejoin_token(profile: ELProfile) -> void:
	print("== Autochess rejoin during a battle ==")
	var online := _offline_host(profile)
	var token := "c".repeat(32)
	online._host_receive(42, _hello(online, profile, token))
	var game := online.start_match(654)
	online._disconnected(42)
	check(game.controllers[1] == "computer" and online._departed.has(token), "a dropped guest's seat waits for its token")
	game.stage = "fight"
	online._host_receive(50, _hello(online, profile, token))
	check(online._returning.has(50), "the returning guest waits for the battle to end")
	# The return drops before it is seated, then is tried again.
	online._disconnected(50)
	online._host_receive(51, _hello(online, profile, token))
	check(online._returning.has(51) and int(online._returning[51]) == 1, "a second try after a dropped return keeps the seat (%s)" % str(online._returning))
	# A newer connection with the token replaces one still waiting.
	online._host_receive(52, _hello(online, profile, token))
	check(online._returning.keys() == [52] and not _peers(online).has(51), "a newer return replaces one still waiting (%s)" % str(online._returning))
	game.stage = "prepare"
	online._seat_returning()
	check(int(online._seats.get(52, -1)) == 1 and game.controllers[1] == "remote" and not online._departed.has(token), "the guest is seated and its token is used up")
	online._disconnected(52)
	check(online._departed.has(token), "a guest dropping after it was seated can return again")

func _signature(profile: ELProfile) -> void:
	print("== Autochess compatibility signature ==")
	var before := ELAutochessOnline.signature(profile)
	check(before == ELAutochessOnline.signature(profile), "the signature is stable")
	var code := ELAutochessRules.form(0, 0)
	var row: Dictionary = profile.table("CombatCreatures").get(code, {})
	var flags: Variant = row.get("Flags", [])
	var changed: Array = ([flags] if flags is String else (flags as Array).duplicate()) + ["Fly", "Regen(9)"]
	row["Flags"] = changed
	var after := ELAutochessOnline.signature(profile)
	if flags == null: row.erase("Flags")
	else: row["Flags"] = flags
	check(after != before, "giving %s Fly and Regen(9) changes the signature" % code)
	check(ELAutochessOnline.signature(profile) == before, "restoring the data restores the signature")

func _result_digests(profile: ELProfile) -> void:
	print("== Autochess per-round result comparison ==")
	var host := _offline_host(profile)
	host._host_receive(42, _hello(host, profile, "d".repeat(32)))
	var game := host.start_match(987)
	game.finish_bots()
	game.start_fight()
	var guard := 0
	while game.stage == "fight" and guard < 5000:
		game.process(0.5)
		guard += 1
	check(game.stage == "result", "the host settles round one")
	var state := host._state()
	var guest := ELAutochessOnline.new()
	guest.profile = profile
	guest.is_host = false
	guest.seat = 1
	guest.game = ELAutochessMatch.new()
	guest._apply_state(JSON.parse_string(JSON.stringify(state)))
	var heard := []
	guest.message.connect(func(t: String): heard.append(t))
	# Same results: nothing to report.
	guest.game.stage = "result"
	guest.game.round_results = game.round_results.duplicate(true)
	guest._guest_receive(["state", JSON.parse_string(JSON.stringify(state))])
	check(int(guest.get("divergences")) == 0 if guest.get("divergences") != null else false, "identical battle results are accepted")
	# This machine's battle ended the other way.
	guest.set("_checked_round", 0)
	guest.game.stage = "result"
	var mine := game.round_results.duplicate(true)
	var seat_result: Dictionary = mine[1]
	seat_result.winner = 1 if int(seat_result.winner) == 0 else 0
	guest.game.round_results = mine
	guest._guest_receive(["state", JSON.parse_string(JSON.stringify(state))])
	check(guest.get("divergences") != null and int(guest.get("divergences")) == 1 and not heard.is_empty(), "a different battle result is reported (%s)" % str(heard))

func _persisted_token() -> void:
	print("== Autochess reconnect identity ==")
	var held := ELAutochessOnline._token
	ELAutochessOnline._token = ""
	var first := ELAutochessOnline.token()
	# A restart forgets static memory; the identity comes back from the file.
	ELAutochessOnline._token = ""
	var second := ELAutochessOnline.token()
	check(first == second and first.length() == 32, "the reconnect identity survives a restart")
	ELAutochessOnline._token = held if not held.is_empty() else first

func _frame(from: int, channel: int, more: bool, size: int) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(ELRelayPeer.HEADER + size)
	frame.encode_u32(0, from)
	frame[4] = channel
	frame[5] = 1 if more else 0
	return frame

func _relay_limits() -> void:
	print("== Relay buffering limits ==")
	var relay := ELRelayPeer.new()
	relay._server = true
	relay._status = MultiplayerPeer.CONNECTION_CONNECTED
	relay._peers = {2: true, 3: true, 4: true}
	var left := []
	relay.peer_disconnected.connect(func(id: int): left.append(id))
	relay._frame(_frame(2, 0, true, 1000))
	relay._control(JSON.stringify({"t": "leave", "id": 2}))
	check(relay._partial.is_empty(), "an unfinished packet goes when its sender leaves")
	relay._frame(_frame(4, 7, false, 10))
	check(relay.get_available_packet_count() == 0, "a frame on a channel the games do not use is dropped")
	for i in 10000: relay._frame(_frame(3, 0, false, 10))
	check(relay.get_available_packet_count() < 10000 and not relay._peers.has(3) and left.has(3), "a guest flooding completed packets is removed (%d queued)" % relay.get_available_packet_count())
	check(relay.get_available_packet_count() == 0, "a removed guest's queued packets are dropped")
	relay._peers[5] = true
	relay._frame(_frame(5, 0, true, 100))
	var stale := relay.has_method("_expire")
	if stale:
		for key: int in relay._partial: relay._partial[key].at = Time.get_ticks_msec() - 3600000
		relay.call("_expire", Time.get_ticks_msec())
	check(stale and relay._partial.is_empty(), "an unfinished packet that stopped arriving expires")
	relay._frame(_frame(5, 0, false, 64))
	var got := relay.get_packet()
	check(got.size() == 64 and relay.has_method("buffered_bytes") and int(relay.call("buffered_bytes")) == 0, "read packets release their bytes")
	# A guest's only sender is the host; its flood closes the connection.
	var guest := ELRelayPeer.new()
	guest._status = MultiplayerPeer.CONNECTION_CONNECTED
	guest._peers = {1: true}
	for i in 10000: guest._frame(_frame(1, 0, false, 8))
	check(guest.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED and not guest.close_reason.is_empty(), "a guest leaves a host that floods it (%s)" % guest.close_reason)
	guest._status = MultiplayerPeer.CONNECTION_CONNECTED
	guest._peers = {1: true}
	guest._frame(_frame(9, 0, false, 8))
	check(guest.get_available_packet_count() == 0, "a guest takes packets from the host only")

# --- Duel mode replays ---------------------------------------------------

func _replay_path(name: String) -> String:
	return ELDuelRecording.directory("el2").path_join(name + ELDuelRecording.EXTENSION)

func _play(profile: ELProfile, path: String) -> ELDuelReplayPlayer:
	var player := ELDuelReplayPlayer.new()
	if not player.load_file(profile, path): return player
	var battle := ELDuel.new()
	if not player.begin(battle): return player
	var guard := 0
	while player.step() and guard < 5000: guard += 1
	return player

func _rewrite(path: String, change: Callable) -> void:
	var data: Dictionary = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(path)))
	change.call(data)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(JSON.from_native(data)))
	file.close()

func _replay_terminal(profile: ELProfile) -> void:
	print("== Duel replay terminal check ==")
	var shipped := ELDuelPresets.shipped(profile)
	var level := ELDuelCosts.resource_levels(profile).y - 1
	var picks: Array = []
	for preset in shipped:
		if ELDuelMatch.side_valid(shipped, preset, level): picks.append(preset)
		if picks.size() == 2: break
	var arenas := ELDuelMatch.arenas(profile)
	var game_match := ELDuelMatch.new()
	check(picks.size() == 2 and game_match.begin(profile, shipped, picks, level, 1, arenas[0], 777).is_empty(), "a duel match starts")
	var battle := ELDuel.new()
	check(battle.start(profile, 777, game_match.round_options(profile)), "the battle starts")
	var recording := ELDuelRecording.new()
	recording.track(battle, 777)
	var guard := 0
	while battle.phase != ELDuel.Phase.FINISHED and guard < 600:
		ELPracticeAI.heuristic_step(battle)
		guard += 1
	if battle.phase != ELDuel.Phase.FINISHED:
		recording.note_surrender(battle, 1)
		battle.heroes[1].health = 0
		battle._check_winner()
	recording.finish_round(battle)
	print("  recorded %d actions, winner %d" % [recording.rounds[0].actions.size(), battle.winner])
	var name := "online_robustness_check"
	check(recording.save(name).is_empty(), "the replay saves")
	var path := _replay_path(name)
	var played := _play(profile, path)
	check(played.error.is_empty() and played.done(), "the replay plays to its end (%s)" % played.error)
	check(played.get("verified") == true, "the replay's terminal state is confirmed")
	# A replay whose recorded end differs reports it.
	_rewrite(path, func(data: Dictionary):
		if data.has("terminal"): data.terminal.health = [999, 999])
	played = _play(profile, path)
	check(not played.error.is_empty() and played.get("verified") == false, "a different end is reported (%s)" % played.error)
	# A replay saved before terminal checks still plays.
	_rewrite(path, func(data: Dictionary):
		data.erase("terminal")
		data.erase("rules"))
	played = _play(profile, path)
	check(played.error.is_empty() and played.done() and played.get("verified") != true, "an older replay without a recorded end plays (%s)" % played.error)
	DirAccess.remove_absolute(path)
