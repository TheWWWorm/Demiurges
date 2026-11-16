extends SceneTree
## Frame times of a battle with many copies of one hero enchantment in play
## (player reports: battles with about fifty copies of Sacrifice, Fireball,
## Lesser Healing or Ether Harvest (MNTX) on a hero ran at a few frames a second),
## measured through the battle screen itself (res://scenes/duel.tscn).
##
## A case is a game, an enchantment, a number of copies on each hero and the
## computer opponent's level (setting "duel_ai": 2 Smarter, 1 Original). The
## battle is started against the computer, both heroes are given the copies
## and two creatures, and three phases are played, each for --seconds:
##   idle      the player's phase, the player's hero selected (its
##             enchantments on the upper strip), nothing done;
##   acting    the player selects the hero and a creature in turn, reads the
##             hero's tooltip, starts a hero ability from the strip and gives
##             it its target, and summons a creature;
##   computer  the player ends each phase at once and the computer plays
##             (four times as long: its casts are shown at the game's pace).
## Every frame's length is taken from one process_frame to the next, with
## no frame cap of the game's. A headless frame still lasts at least 6.9 ms
## (the engine's pause for a window it cannot draw to), so an idle frame
## reads 6.9 ms and only work longer than that shows. Per phase the line
## gives the frames, their mean, 99th percentile and longest, and the three
## longest with what happened in them (full refreshes, strip rebuilds,
## commands taken, rule events, the step the player made).
## TIMING lines give single calls of the screen's and the rules' functions
## on the position the battle has come to (milliseconds, the mean of a few
## calls; _log with the battle log's lines).
##
## A phase FAILS when a frame is longer than --limit milliseconds (0 only
## reports; 100 by default: with fifty copies the longest frames are about
## 15 to 25 ms, 50 to 80 with the battle log open, and were 130 to 5000 ms
## before the screen was made to cope). The run is headless: nothing is
## drawn, so the numbers are the scripts' and the scene tree's share of a
## frame (panel rebuilds, tooltips, the log, rules, starting effects and
## sounds), not the renderer's: a frame that is long here is long in the
## game, a frame that is short here can still be slow to draw. The texts are
## in the language of the game's files; the Russian ones cost more to show.
## The first case of a run also pays for sounds and effects first used
## (frames of 30 to 50 ms).
##
##   godot --headless --path game --script ../tools/crowded_battle_check.gd -- \
##       [--game=el1|el2|both] [--cards=SACR,FRBL,LSHE,MNTX] [--copies=1,10,50]
##       [--levels=2,1] [--seconds=3] [--limit=100] [--on=both|own|foe]
##       [--size=1920x1080] [--slide=N] [--log=1] [--seed=N] [--timing=0|1]
##
## --log=1 plays with the battle log (L) open.
## --slide chooses the readout panels' slide on a wide screen
## (ELCombatGapPanel.SLIDES; the adviser reads the battle only while shown).
## Settings are changed in memory only. Needs the player's game files; a game
## without them, and a card a game does not have, are skipped.

const BOOKS := [["Green", "PRG3", 6], ["Red", "PRR3", 6]]
const STEP_MS := 150
const HEALTH := 500

var view: Node
var failures: Array[String] = []
var limit := 100.0
var seconds := 3.0

## Frame sampling: one entry per frame while `sampling`.
var sampling := false
var samples: Array = []
var _last_usec := 0
var _events := 0
var _note := ""
var _marks := [0, 0, 0]

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _count(name: String) -> int:
	var value: Variant = view.get(name)
	return int(value) if value != null else 0

## Called first in every frame: the frame that just ended, with what it did.
func _frame() -> void:
	var now := Time.get_ticks_usec()
	if sampling and view != null and view.duel != null:
		var duel: ELDuel = view.duel
		var marks := [_count("refresh_count"), _count("strip_fill_count"), duel.accepted_serial]
		samples.append([float(now - _last_usec) / 1000.0, marks[0] - _marks[0], marks[1] - _marks[1], marks[2] - _marks[2], _events, _note, duel.active_side(), _profile()])
		_marks = marks
	elif Engine.has_meta("prof"): Engine.get_meta("prof").clear()
	_events = 0
	_note = ""
	_last_usec = now

## Only with an instrumented copy of the game's scripts (a development aid:
## each function adds its time to the dictionary in Engine's "prof" meta):
## the functions that took longest in the frame, "name=ms/calls".
func _profile() -> String:
	if not Engine.has_meta("prof"): return ""
	var taken: Dictionary = Engine.get_meta("prof")
	var names: Array = taken.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return taken[a][0] > taken[b][0])
	var parts: Array[String] = []
	for name: String in names.slice(0, 14): parts.append("%s=%.1f/%d" % [name, taken[name][0] / 1000.0, taken[name][1]])
	taken.clear()
	return " ".join(parts)

func _begin_sampling() -> void:
	samples = []
	_marks = [_count("refresh_count"), _count("strip_fill_count"), view.duel.accepted_serial]
	_events = 0
	_note = ""
	Engine.max_fps = 0
	sampling = true

## Ends a phase: prints its line and checks the longest frame.
func _report(name: String, phase: String) -> void:
	sampling = false
	if samples.is_empty():
		print("  PHASE %-8s no frames" % phase)
		return
	var sorted := samples.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var total := 0.0
	for sample: Array in samples: total += float(sample[0])
	var p99: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.01))][0]
	var longest: float = sorted[0][0]
	var over := 0
	for sample: Array in samples:
		if float(sample[0]) > 16.7: over += 1
	print("  PHASE %-8s frames=%d mean=%.2f p99=%.1f max=%.1f ms, over 16.7 ms: %d" % [phase, samples.size(), total / samples.size(), p99, longest, over])
	for sample: Array in sorted.slice(0, 3):
		print("      %.1f ms: refreshes=%d strip_fills=%d commands=%d events=%d side=%d %s" % [sample[0], sample[1], sample[2], sample[3], sample[4], sample[6], sample[5]])
		if not String(sample[7]).is_empty(): print("  PROF  " + String(sample[7]))
	if limit > 0.0 and longest > limit:
		failures.append("%s %s: a frame of %.1f ms (limit %.0f)" % [name, phase, longest, limit])
		print("  FAIL: %s %s: a frame of %.1f ms (limit %.0f)" % [name, phase, longest, limit])

func _run() -> void:
	limit = float(_arg("limit", "100"))
	seconds = float(_arg("seconds", "3"))
	var size := _arg("size", "1920x1080")
	root.size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	Engine.max_fps = 0
	if _arg("prof", "") == "1": Engine.set_meta("prof", {})
	view = (load("res://scenes/duel.tscn") as PackedScene).instantiate()
	view.demo = false
	root.add_child(view)
	for i in 10: await process_frame
	process_frame.connect(_frame)
	var games: Array[String] = []
	for game: String in ["el1", "el2"]:
		if _arg("game", "both") in [game, "both"]: games.append(game)
	print("CROWDED BATTLE: compiled engine %s, window %s, %s s a phase, limit %s ms" % [str(ELCombatBrain.available), size, seconds, limit])
	var cases := 0
	for game: String in games:
		if not view.profiles.has(game) or view.profiles[game] == null:
			print("SKIP %s: no game files" % game)
			continue
		for card: String in _arg("cards", "SACR,FRBL,LSHE,MNTX").split(","):
			if not (view.profiles[game] as ELProfile).table("CombatSpells").has(card):
				print("SKIP %s %s: the game has no such card" % [game, card])
				continue
			for copies: String in _arg("copies", "1,10,50").split(","):
				for level: String in _arg("levels", "2,1").split(","):
					cases += 1
					await _case(game, card, int(copies), int(level))
	ELPracticeAI.finish()
	view.queue_free()
	for i in 5: await process_frame
	print("CROWDED BATTLE: %d case(s), %d failure(s)" % [cases, failures.size()])
	for what: String in failures: print("  failed: " + what)
	quit(1 if not failures.is_empty() else 0)

func _settled() -> bool:
	return not view._cast_busy() and not view._presentation_held() and not view._melee_busy() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty()

func _settle(frames := 900) -> void:
	for i in frames:
		await process_frame
		if _settled(): return

func _warm() -> void:
	var began := Time.get_ticks_msec()
	while view.battle_warmup != null and is_instance_valid(view.battle_warmup) and view.battle_warmup.decoded_at < 0 and Time.get_ticks_msec() - began < 30000: await process_frame
	for i in 30: await process_frame

func _army(duel: ELDuel, side: int) -> Array[int]:
	var result: Array[int] = []
	for id: int in duel.creatures:
		if int(duel.creatures[id].owner) == side: result.append(id)
	return result

func _top_up(duel: ELDuel) -> void:
	for side in 2:
		duel.heroes[side].health = HEALTH
		duel.heroes[side].maximum = HEALTH
		duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 12)

func _case(game: String, card: String, copies: int, level: int) -> void:
	var name := "%s %s x%d duel_ai=%d" % [game, card, copies, level]
	print("CASE " + name)
	var players: Array = []
	for book: Array in BOOKS: players.append({"faction": book[0], "deck": book[1], "level": book[2]})
	ELCombatSearch.reset_caches()
	# The battle before (the screen's own first one) finishes decoding first.
	await _warm()
	view._start(game, {"players": players}, null, int(_arg("seed", "7")))
	view.settings.values["duel_ai"] = level
	# No frame cap (the stored "frame_rate" is applied at start): a frame is
	# as long as its work.
	view.settings.values["frame_rate"] = 0
	Engine.max_fps = 0
	if _arg("log", "") == "1": view.log_text.visible = true
	if _arg("slide", "") != "":
		view.settings.values["battle_gap"] = int(_arg("slide", "0"))
		for panel: ELCombatGapPanel in view.gap_panels: panel.slide = int(_arg("slide", "0"))
	for i in 5: await process_frame
	var duel: ELDuel = view.duel
	if duel == null or duel.phase == ELDuel.Phase.FINISHED:
		failures.append(name + ": the battle did not start")
		print("  FAIL: the battle did not start")
		return
	duel.event.connect(func(_data: Dictionary) -> void: _events += 1)
	var human: int = view._battle_player_side(duel)
	var summons: Array[String] = []
	for row: String in view.profile.table("CombatCreatures"):
		if duel.is_summon(row): summons.append(row)
	_top_up(duel)
	for side in 2:
		for i in 2: duel.cast_free(side, summons[i], [], false)
	await _settle()
	var on := _arg("on", "both")
	var placed := [0, 0]
	for side in 2:
		if (on == "own" and side != human) or (on == "foe" and side == human): continue
		for i in copies:
			duel.heroes[side].mana = 99
			if duel.cast_free(side, card, [side], false): placed[side] += 1
		await _settle()
	_top_up(duel)
	print("  copies in play: %s, creatures %d, player side %d, to act %d" % [str(placed), duel.creatures.size(), human, duel.active_side()])
	var began := Time.get_ticks_msec()
	# The player's phase first.
	for i in 2000:
		if view._human_turn() and _settled(): break
		view.ai_clock += 1.0
		await process_frame
	if not view._human_turn():
		failures.append(name + ": the player's phase did not come")
		print("  FAIL: the player's phase did not come")
		return
	view._target(human)
	await _settle()
	# The battle's warm-up (decoding the figures', effects' and sounds' files
	# over the first seconds) is not what is measured here.
	await _warm()
	# Idle.
	_begin_sampling()
	began = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - began) < seconds * 1000.0: await process_frame
	await process_frame
	_report(name, "idle")
	# Acting.
	_begin_sampling()
	began = Time.get_ticks_msec()
	var step := 0
	var next := began
	var tip: ELCombatTooltip = view.combat_tip
	while float(Time.get_ticks_msec() - began) < seconds * 1000.0 and duel.phase != ELDuel.Phase.FINISHED:
		await process_frame
		if Time.get_ticks_msec() < next or not view._human_turn() or not _settled() or view._display_lagging(): continue
		next = Time.get_ticks_msec() + STEP_MS
		_top_up(duel)
		var own := _army(duel, human)
		match step % 6:
			0:
				_note = "select hero"
				view._target(human)
			1:
				_note = "hero tooltip"
				if tip != null:
					tip.panel.set_content(-1, view._hero_tip(human, view.portraits[human]))
					tip.panel.show()
			2:
				_note = "ability from the strip"
				if tip != null: tip.hide_tip()
				var strip: ELCombatStrip = view.rail.strip if view.rail != null else null
				if strip != null:
					for index in strip.buttons.size():
						if strip.buttons[index].disabled: continue
						view._strip_pressed(index)
						break
			3:
				_note = "ability target"
				if not view.ability_selection.is_empty():
					var wanted := String(view.ability_selection.get("target", ""))
					if wanted == "any": view._target(1 - human)
					elif wanted == "creature" and not own.is_empty(): view._target(own[-1])
					if not view.ability_selection.is_empty():
						view.ability_selection.clear()
						view._refresh()
			4:
				_note = "summon"
				if own.size() < 6: duel.cast_free(human, summons[0], [], false)
			5:
				_note = "select creature"
				if not own.is_empty(): view._target(own[0])
		step += 1
	if tip != null: tip.hide_tip()
	await process_frame
	_report(name, "acting")
	# The computer's play: the player ends each phase at once.
	view.ability_selection.clear()
	view._target(human)
	_begin_sampling()
	began = Time.get_ticks_msec()
	var thinks := 0
	var waiting := -1
	var longest_wait := 0
	var seen: Dictionary = ELPracticeAI.last_decision
	var serial := duel.accepted_serial
	while float(Time.get_ticks_msec() - began) < seconds * 4000.0 and duel.phase != ELDuel.Phase.FINISHED and view.duel == duel:
		await process_frame
		# How long the computer's side stood ready before its command came
		# (its thinking, on a worker thread, and the 0.85 s between its steps).
		if duel.active_side() != human and _settled() and waiting < 0: waiting = Time.get_ticks_msec()
		if not is_same(ELPracticeAI.last_decision, seen):
			seen = ELPracticeAI.last_decision
			thinks += 1
			if waiting >= 0: longest_wait = maxi(longest_wait, Time.get_ticks_msec() - waiting)
			waiting = -1
			_note = "computer: %s %s" % [str(seen.get("engine", "")), str(seen.get("command", {}).get("kind", "end"))]
		if view._human_turn() and _settled() and not view._display_lagging():
			_top_up(duel)
			_note += " player ends the phase"
			view._end_phase()
	await process_frame
	_report(name, "computer")
	if _arg("timing", "1") == "1" and duel.phase != ELDuel.Phase.FINISHED and view.duel == duel: await _timing(duel, human)
	var sent := 0
	for entry: Dictionary in duel.accepted:
		if int(entry.serial) > serial and int(entry.side) != human: sent += 1
	print("  computer: %d decisions (longest wait for one %.1f s), %d commands taken, round %d, creatures %d, enchantments %s" % [thinks, longest_wait / 1000.0, sent, duel.round_number, duel.creatures.size(), str([duel.heroes[0].enchantments.size(), duel.heroes[1].enchantments.size()])])

## Single calls on the standing position, the mean of `times` in ms.
func _time(what: Callable, times := 5) -> float:
	var began := Time.get_ticks_usec()
	for i in times: what.call()
	return float(Time.get_ticks_usec() - began) / 1000.0 / times

func _timing(duel: ELDuel, human: int) -> void:
	view.selected_creature = human
	view.inspect_graveyard = false
	var listed: Array = duel.abilities(human)
	var parts: Array[String] = []
	var add := func(label: String, what: Callable, times := 5) -> void: parts.append("%s=%.2f" % [label, _time(what, times)])
	add.call("_refresh", func() -> void: view._refresh())
	add.call("_refresh_inspector", func() -> void: view._refresh_inspector())
	add.call("_fill_strip", func() -> void: view._fill_strip())
	add.call("_strip_enchantments", func() -> void: view._strip_enchantments(human))
	add.call("_fill_gap", func() -> void: view._fill_gap(false))
	add.call("_refresh_buttons", func() -> void: view._refresh_buttons())
	add.call("_show_hero_stats", func() -> void: view._show_hero_stats())
	add.call("_update_cursor", func() -> void: view._update_cursor())
	add.call("_hero_tip", func() -> void: view._hero_tip(human, view.portraits[human]))
	var lines: int = view.logs.size()
	add.call("_log(%d lines)" % lines, func() -> void: view._log("Timing line."))
	add.call("_process", func() -> void: view._process(0.0))
	print("  TIMING screen (ms): " + " ".join(parts))
	parts.clear()
	add.call("abilities", func() -> void: duel.abilities(human), 20)
	add.call("can_use_ability_all", func() -> void:
		for ability: Dictionary in listed: duel.can_use_ability(human, ability.key))
	add.call("search_copy", func() -> void: duel.search_copy())
	add.call("snapshot_hash", func() -> void: [duel._snapshot()].hash())
	add.call("_position", func() -> void: ELCombatSearch._position(duel))
	add.call("request", func() -> void: ELCombatSearch.request(duel, false))
	add.call("win_chance", func() -> void: ELCombatSearch.win_chance(ELCombatSearch.plain_context(duel, human), duel, human))
	add.call("brain_prepare", func() -> void: ELCombatBrain.prepare(duel))
	print("  TIMING rules (ms): " + " ".join(parts))
