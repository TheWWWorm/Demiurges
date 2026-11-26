extends SceneTree
## Headless check of four pieces of duel presentation player feedback:
##
## - A creature that regenerates from a spell's hit (a rat under Rat
##   Immortality struck by Chain Lightning) shows its regeneration, and the
##   specialisation behind it, when the spell's hit lands, not before it.
## - The battle is over once the winner's victory clip has played, as in
##   both originals; the fanfare is not waited for and plays on.
## - The phase banner plays its sound (Buttons/Begin_Combat.wav) at each
##   phase change, in quick duels and in both games' campaign battles, and
##   the end-of-phase button plays its control's sound (CombatMenu2) when
##   clicked. A click does not cut the banner sound, and the opponent's
##   banner shows again after the local side's defence.
## - While a cast is shown, the corner menu control (and so its hover
##   tooltip) is hidden, so it never covers a spell's full-screen effect.
## Runs for each game whose files are configured.
##
##   godot --headless --path game --script ../tools/feedback_duel_timing_check.gd
##
## Needs the original games' files (user://profiles.json, as set up by the
## game); without them a game is skipped. Settings are never written.

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		await _regeneration(edition)
		await _phase_sound(edition)
		await _end_button(edition)
		await _corner_menu(edition)
		await _ending(edition)
		await _campaign_phase_sound(edition)
	print("FEEDBACK DUEL TIMING: %d failure(s)" % failures)
	quit(int(failures > 0))

func _view(edition: String, position: ELDuel = null) -> Node:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		print("SKIP: %s files could not be mounted" % edition)
		view.queue_free()
		await process_frame
		return null
	view.settings.values.hide_cast = false
	if position != null:
		view.demo = false
		view._start(edition, {}, position)
	else: view._start(edition)
	await _idle(view)
	return view

func _close(view: Node) -> void:
	view.queue_free()
	await process_frame
	await process_frame

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 600:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return

## Side 0 strikes side 1's Stinking Rat with Chain Lightning; side 1's hero
## holds Rat Immortality with luck enough to make it all but certain.
func _regeneration(edition: String) -> void:
	var profile := ELProfile.new()
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if not profile.mount(edition, str(paths[edition])): return
	var position := Fixtures.build(profile, {"attacker": 0, "phase": "attack", "fixed": true,
		"heroes": [{"health": 20, "mana": 20, "hand": []}, {"health": 20, "mana": 20, "hand": []}],
		"creatures": [{"card": "STRT", "owner": 1}]})
	var view: Node = await _view(edition, position)
	if view == null: return
	var what := "%s Rat Immortality against Chain Lightning" % edition
	var duel: ELDuel = view.duel
	var rat := -1
	for id: int in duel.creatures: rat = id
	duel.heroes[1].spec = "RRTR"
	duel.heroes[1].spec_level = 20
	duel.heroes[1].luck = 40
	duel.heroes[0].suppression = 0
	var regenerated := false
	var hit := 0.0
	var regen_at := -1.0
	var spec_at := -1.0
	for attempt in 6:
		if not duel.creatures.has(rat): break
		duel.creatures[rat].damage = maxi(0, int(duel.creatures[rat].toughness) - 1)
		duel.heroes[0].mana = 20
		await _idle(view)
		view._figure_effects_now.clear()
		var events_before: int = duel.events.size() if "events" in duel else 0
		var start: float = view.elapsed
		if not duel.cast_free(0, "CLIG", [rat], true):
			check(false, "%s: the cast is legal (%s)" % [what, duel.error])
			break
		regenerated = duel.creatures.has(rat) and bool(duel.creatures[rat].get("regenerated", false))
		hit = float(view._effect_cast.get("hit", 0.0))
		regen_at = -1.0
		spec_at = -1.0
		for i in 2000:
			view.ai_clock = -1000.0
			var seconds: float = view.elapsed - start
			if regen_at < 0.0 and view._figure_effects_now.has("RegenEffect|%d" % rat): regen_at = seconds
			if spec_at < 0.0 and view._figure_effects_now.has("Specialisation|1"): spec_at = seconds
			if seconds > hit + 0.6: break
			await process_frame
		if regenerated: break
	check(regenerated, "%s: the rat regenerates (Rat Immortality worked)" % what)
	if regenerated:
		check(hit > 0.1, "%s: the spell hits after the cast (%.2f s)" % [what, hit])
		check(regen_at >= hit - 0.03, "%s: the regeneration shows at the hit (%.2f s), not before (shown at %.3f s)" % [what, hit, regen_at])
		check(spec_at >= hit - 0.03, "%s: the specialisation shows at the hit (%.2f s), not before (shown at %.3f s)" % [what, hit, spec_at])
	await _close(view)

## Phase changes play the banner sound.
func _phase_sound(edition: String) -> void:
	var view: Node = await _view(edition)
	if view == null: return
	var duel: ELDuel = view.duel
	view.settings.values.combat_phases = true
	var heard := 0
	var phases := 0
	for k in 4:
		await _idle(view)
		ELUiSounds.history.clear()
		var before := duel.turn_serial
		duel.end_phase()
		phases += 1
		for i in 240:
			view.ai_clock = -1000.0
			await process_frame
			if ELUiSounds.history.has("Buttons/Begin_Combat.wav"): break
		if ELUiSounds.history.has("Buttons/Begin_Combat.wav"): heard += 1
	print("  %s: banner sound heard at %d of %d phase changes" % [edition, heard, phases])
	check(heard >= phases - 1 and heard > 0, "%s: phase changes play the banner sound (%d of %d)" % [edition, heard, phases])
	# Both originals start the banner sound on their general sample pool, so
	# a button's click right after it does not cut it off.
	view.notices.show_banner(0)
	for i in 60:
		await process_frame
		if ELUiSounds.player_of("phase") != null and ELUiSounds.player_of("phase").playing: break
	var phase_voice := ELUiSounds.player_of("phase")
	ELUiSounds.play(view.profile, ELUiSounds.DEFAULT)
	check(phase_voice != null and phase_voice.playing and phase_voice != ELUiSounds.player_of(), "%s: a click after the banner sound does not cut it" % edition)
	await _close(view)
	await _banner_latch(edition)

## The opponent's banner shows once per opposing turn: the local side's
## attack or defence banner opens it again (both originals clear the latch
## on either banner).
func _banner_latch(edition: String) -> void:
	var profile := ELProfile.new()
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	if not profile.mount(edition, str(paths[edition])): return
	var position := Fixtures.build(profile, {"attacker": 0, "phase": "attack", "fixed": true,
		"heroes": [{"health": 20, "mana": 20, "hand": []}, {"health": 20, "mana": 20, "hand": []}], "creatures": []})
	var view: Node = await _view(edition, position)
	if view == null: return
	view.settings.values.combat_phases = true
	var local := 0 if view._local_side(0) and not view._local_side(1) else (1 if view._local_side(1) and not view._local_side(0) else -1)
	if local < 0:
		print("SKIP: %s: no single local side in this battle" % edition)
		await _close(view)
		return
	var shown := func(side: int, attack: bool) -> int:
		view.notices.banner = -1
		view._phase_notice(side, attack, 1)
		return view.notices.banner
	shown.call(1 - local, true)
	check(shown.call(1 - local, false) == -1, "%s: the opponent's banner shows once per opposing turn" % edition)
	check(shown.call(local, false) == 1, "%s: the local defence shows the defence banner" % edition)
	check(shown.call(1 - local, true) == 2, "%s: after the local defence the opponent's banner shows again" % edition)
	check(shown.call(local, true) == 0, "%s: the local attack shows the attack banner" % edition)
	await _close(view)

## A won duel: the battle is over when the victory clip ends.
func _ending(edition: String) -> void:
	var view: Node = await _view(edition)
	if view == null: return
	var duel: ELDuel = view.duel
	var caster := duel.active_side()
	duel.heroes[1 - caster].health = 1
	duel.heroes[caster].mana = 20
	await _idle(view)
	if not duel.cast_free(caster, "ZAPP", [1 - caster], true):
		check(false, "%s: the deciding cast is legal (%s)" % [edition, duel.error])
		await _close(view)
		return
	var victory_at := -1.0
	var over_at := -1.0
	var clip_length := 0.0
	var fanfare := 0.0
	var start: float = view.elapsed
	for i in 4000:
		view.ai_clock = -1000.0
		await process_frame
		var seconds: float = view.elapsed - start
		if victory_at < 0.0 and not view.ending.is_empty() and String(view.ending.stage) == "victory":
			victory_at = seconds
			clip_length = view.models[caster].clip_seconds(String(view.ending.get("clip", ""))) if view.ending.has("clip") else 0.0
			fanfare = float(view.ending.get("fanfare", 0.0))
		if view.ending_over() and not view.ending.is_empty():
			over_at = seconds
			break
		if seconds > 30.0: break
	var wait := over_at - victory_at
	var recording := 0.0
	var stream: AudioStream = ELAudio.sound(view.profile, "buttons/%svictory.wav" % String(duel.heroes[caster].get("faction", "Red")))
	if stream != null: recording = stream.get_length()
	var fanfare_on := false
	for node: Node in root.get_children():
		if node is AudioStreamPlayer and String(node.name).begins_with("BattleFanfare") and node.playing and node.stream == stream: fanfare_on = true
	print("  %s: victory clip %.2f s, fanfare %.2f s audible of %.2f s, over %.2f s after the victory began" % [edition, clip_length, fanfare, recording, wait])
	check(victory_at >= 0.0 and over_at > victory_at, "%s: the winner celebrates and the battle ends" % edition)
	check(fanfare > 0.0 and fanfare < recording, "%s: the fanfare's closing silence is measured (%.2f of %.2f s)" % [edition, fanfare, recording])
	# Both originals close the battle (GameOver) when the victory clip ends;
	# the fanfare is not waited for and plays on.
	check(wait >= clip_length - 0.05, "%s: the battle does not end before the victory clip (%.2f s)" % [edition, wait])
	check(wait <= clip_length + 0.1, "%s: the battle ends with the victory clip, not the fanfare (%.2f s for a %.2f s clip)" % [edition, wait, clip_length])
	check(fanfare <= clip_length or fanfare_on, "%s: the fanfare is still playing as the battle closes" % edition)
	await _close(view)

## A human player's click on the end-of-phase button plays CombatMenu2's sound.
func _end_button(edition: String) -> void:
	var view: Node = await _view(edition)
	if view == null: return
	view.demo = false
	var sound: String = ELUiSounds.sound_of(view.profile, "CombatMenu2")
	var ready := false
	for i in 900:
		view.ai_clock = -1000.0 if not view._human_turn() else 0.0
		await process_frame
		if view._human_turn() and not view.end_button.disabled:
			ready = true
			break
	check(ready, "%s: the player's turn comes (end-of-phase button open)" % edition)
	if ready:
		ELUiSounds.history.clear()
		view.end_button.pressed.emit()
		check(ELUiSounds.history.has(sound), "%s: the end-of-phase click plays %s (%s)" % [edition, sound, ELUiSounds.history])
	await _close(view)

## The corner menu control steps aside while a cast is shown.
func _corner_menu(edition: String) -> void:
	var view: Node = await _view(edition)
	if view == null: return
	var duel: ELDuel = view.duel
	var caster := duel.active_side()
	duel.heroes[caster].mana = 30
	duel.heroes[1 - caster].health = 30
	await _idle(view)
	var corner: Control = view.game_menu_button if view._game_menu_art else view.menu_button
	check(corner.visible, "%s: the corner menu control shows between casts" % edition)
	if not duel.cast_free(caster, "ZAPP", [1 - caster], true):
		check(false, "%s: the cast is legal (%s)" % [edition, duel.error])
		await _close(view)
		return
	var hidden := false
	for i in 30:
		view.ai_clock = -1000.0
		await process_frame
		if not corner.visible: hidden = true
	check(hidden, "%s: the corner menu control hides while the cast is shown" % edition)
	await _idle(view)
	view.ai_clock = -1000.0
	await process_frame
	check(corner.visible, "%s: the corner menu control comes back after the cast" % edition)
	await _close(view)

## A campaign map battle: each phase change plays the banner sound.
func _campaign_phase_sound(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has(edition):
		await _close(view)
		return
	view.settings.values.show_tutorial = false
	var row := {}
	if edition == "el2":
		row = {"file_name": "Maps/e2mission13", "script": "Maps/e2mission13"}
	else:
		ELFirstTutorial.for_settings(view.settings).persist = false
		var campaign := ELCampaign.new()
		campaign.load_campaign(view.profiles.el1, "Good")
		row = campaign.scenarios[0].duplicate()
		row.campaign = "Good"
	await view._begin_campaign(edition, row, 1)
	var map: ELAdventureView = view.campaign_view
	if map == null:
		check(false, "%s: a campaign map loads" % edition)
		await _close(view)
		return
	var state := map.state
	var opponent := -1
	if edition == "el2": opponent = int(state.vm.globals.ID_C_BOSS)
	else:
		for id: int in state.objects:
			var item: Dictionary = state.objects[id]
			if item.get("type") == "monster" and item.alive:
				opponent = id
				break
	var encounter := ELAdventureEncounter.new()
	var prepared := opponent >= 0 and encounter.prepare(state, state.main_hero, opponent)
	check(prepared, "%s: a campaign battle is set up (%s)" % [edition, encounter.error])
	if not prepared:
		await _close(view)
		return
	map.director.encounter = encounter
	view._begin_encounter(state.main_hero, opponent)
	view.settings.values.combat_phases = true
	var changes := 0
	var heard := 0
	var last := "%d/%d" % [view.duel.active_side(), view.duel.phase]
	var waiting := false
	var since := 0.0
	var start: float = view.elapsed
	while view.elapsed - start < 25.0 and view.duel.phase != ELDuel.Phase.FINISHED and changes < 4:
		await process_frame
		var now := "%d/%d" % [view.duel.active_side(), view.duel.phase]
		if now != last:
			last = now
			changes += 1
			waiting = true
			since = view.elapsed
			ELUiSounds.history.clear()
		if waiting and ELUiSounds.history.has("Buttons/Begin_Combat.wav"):
			heard += 1
			waiting = false
		if waiting and view.elapsed - since > 6.0: waiting = false
		if view._human_turn() and not view.end_button.disabled and view.ai_clock > 1.0: view._end_phase()
	print("  %s campaign: banner sound at %d of %d phase changes" % [edition, heard, changes])
	check(changes > 0 and heard >= changes - 1, "%s: campaign battle phase changes play the banner sound (%d of %d)" % [edition, heard, changes])
	await _close(view)
