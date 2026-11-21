extends SceneTree
## Headless check of the second game's battle flow around a fight:
## - #237: a creature home from its attack lies down (tap clip) before the
##   turn goes on; when the rules have already moved to its owner's next turn
##   it then gets up with its untap clip, never jumping from one idle to the
##   other, and the shown phase changes only after it has lain down;
## - #244, #272: Space (the battle's skip key) ends the current attacker's
##   exchange only: its blows land with their hit sounds and it walks home
##   while the next attacker sets off; a creature killed in a skipped
##   exchange still plays its death; the death of a hero is never skipped
##   (its clip plays out and its sound is not cut); Space ends the winner's
##   victory clip at once, but the battle lasts until the victory fanfare
##   has played out;
## - Hide movement: the tap and untap clips are not played, the figure
##   changes idle at once.
##
##   godot --headless --path game --script ../tools/duel_flow_check.gd
##
## Needs the second game's files (user://profiles.json); without them the
## check is skipped. Settings are never written.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no el2 files configured (user://profiles.json)")
		quit(0)
		return
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has("el2"):
		print("SKIP: el2 files could not be mounted")
		view.queue_free()
		quit(0)
		return
	view.settings.values.hide_cast = false
	view.settings.values.hide_motion = false
	view._start("el2")
	await _idle(view)
	await _rest_before_turn(view, false)
	await _rest_before_turn(view, true)
	await _skip_attacks(view)
	await _hidden_movement(view)
	await _cast_sounds(view)
	await _hero_death(view)
	view.queue_free()
	await process_frame
	print("DUEL FLOW: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

## `racing`: the rules reach the treant's next turn while its fight is still
## shown; otherwise the opponent ends each phase as soon as the computer
## player may act again (0.85 s after the fight has been shown).
func _rest_before_turn(view: Node, racing: bool) -> void:
	var what := "#237 (%s)" % ("turn settled during the fight" if racing else "quick opponent")
	var duel: ELDuel = view.duel
	var treant := _card(view, "Treant")
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var attacker := await _creature(view, side, treant, 2, 9)
	var blocker := await _creature(view, 1 - side, treant, 2, 9)
	if attacker < 2 or blocker < 2 or not duel.toggle_attack(attacker):
		check(false, "%s: a treant attacks (%s)" % [what, duel.error])
		return
	await _idle(view)
	duel.end_phase()
	await _idle(view)
	duel.assign_block(blocker, attacker)
	await _idle(view)
	var model: ELModel = view.models[attacker]
	var clips: Array[String] = []
	model.animation_started.connect(func(clip: String) -> void: clips.append(clip))
	duel.end_phase()
	if racing:
		for i in 6:
			if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK: break
			duel.end_phase()
		check(duel.attacker == side and not bool(duel.creatures[attacker].resting), "%s: the rules already woke the treant for its next turn" % what)
	# Clips seen when the first phase after the fight is shown.
	var at_phase := -1
	var shown_phase: Variant = view._shown.get("phase")
	var shown_active: Variant = view._shown.get("active")
	var clock := 0.0
	for i in 2000:
		view.ai_clock = -1000.0
		await process_frame
		if view._melee_busy(): continue
		if at_phase < 0 and (view._shown.get("phase") != shown_phase or view._shown.get("active") != shown_active): at_phase = clips.size()
		if not racing and not (duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK):
			clock += get_root().get_process_delta_time()
			if clock >= 0.85:
				clock = 0.0
				duel.end_phase()
		if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK and view._cast_queue.is_empty() and not view.figures_turning() and model.clip == "cidle": break
	var tap := clips.find("utap")
	check(tap >= 0, "%s: the treant lies down at home (%s)" % [what, ", ".join(clips)])
	if not racing:
		check(at_phase > tap and clips.slice(tap, at_phase).has("ctapidle"), "%s: the next phase is shown once it has lain down (%s | %s)" % [what, ", ".join(clips.slice(0, at_phase)), ", ".join(clips.slice(at_phase))])
	var jumped := false
	for index in range(1, clips.size()):
		if clips[index] == "cidle" and clips[index - 1] in ["utap", "ctapidle"]: jumped = true
	check(not jumped and clips.has("uuntap"), "%s: it gets up with its untap clip instead of jumping to its idle (%s)" % [what, ", ".join(clips)])
	await _idle(view)

## Two unblocked attackers and one whose blocker dies: one Space while the
## first attacker is on its way ends its exchange alone; the next attacker
## then sets off (#272). Another Space during the blocked attacker's
## exchange still shows its blocker's death.
func _skip_attacks(view: Node) -> void:
	var duel: ELDuel = view.duel
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var treant := _card(view, "Treant")
	var ids: Array[int] = []
	for power: int in [1, 1, 6]:
		var id := await _creature(view, side, treant, power, 9)
		if id >= 2: ids.append(id)
	var blocker := await _creature(view, 1 - side, "GBBR", 1, 2)
	if ids.size() < 3 or blocker < 2:
		check(false, "#244: three attackers and a blocker stand")
		return
	# The blocked attacker kills its blocker outright (no trampling on).
	duel.creatures[ids[2]].flags.erase("Trample")
	for id: int in ids: duel.toggle_attack(id)
	await _idle(view)
	duel.end_phase()
	await _idle(view)
	if not duel.assign_block(blocker, ids[2]):
		check(false, "#244: the blocker is assigned (%s)" % duel.error)
		return
	await _idle(view)
	var clips := {}
	for id: int in ids + [blocker]:
		clips[id] = []
		view.models[id].animation_started.connect(func(clip: String) -> void: clips[id].append(clip))
	var blocker_model: ELModel = view.models[blocker]
	var hit_path: String = view.battle_audio.hit_path(view.models[ids[1]], view.models[1 - side])
	var death_path: String = view.battle_audio.unit_path(blocker_model, "death")
	duel.end_phase()
	# The first attacker is on its way to the hero.
	for i in 600:
		await process_frame
		if view.melee._in_blows and view.melee.moving(ids[0]) and ELMeleePlayback.flat_distance(view.models[ids[0]].position, view.homes[ids[0]]) > 1.0: break
	view.battle_audio.requested.clear()
	view.battle_audio.played.clear()
	for id: int in clips: clips[id].clear()
	var first: int = view.melee._current_attacker
	var shown_before: int = int(view.melee._next_blow)
	view._skip_battle_step()
	await process_frame
	await process_frame
	check(view.melee._in_blows and int(view.melee._next_blow) == shown_before + 1, "#272: one Space lands the current attacker's blow alone (%d -> %d shown)" % [shown_before, int(view.melee._next_blow)])
	check(view.melee.moving(first) and view.melee.away(first), "#272: the skipped attacker walks home")
	var second: int = view.melee._current_attacker
	check(second >= 2 and second != first and view.melee.moving(second) and view.melee._skip_attacker != second, "#272: the next attacker sets off as usual")
	check(hit_path.is_empty() or view.battle_audio.requested.has(hit_path) or view.battle_audio.requested.has(view.battle_audio.hit_path(view.models[first], view.models[1 - side])), "#244: the skipped blow's hit is still heard")
	# The blocked attacker's exchange, skipped in its turn.
	for i in 1200:
		await process_frame
		if not view.melee._in_blows or view.melee._current_attacker == ids[2]: break
	check(view.melee._current_attacker == ids[2], "#272: the blocked attacker's exchange comes in its turn")
	view.battle_audio.played.clear()
	clips[blocker].clear()
	view._skip_battle_step()
	await process_frame
	await process_frame
	check(clips[blocker].has("udeath") and is_instance_valid(blocker_model) and blocker_model.clip == "udeath" and blocker_model.playing,
		"#244: the blocker killed in a skipped exchange still plays its death (%s)" % str(clips[blocker]))
	check(death_path.is_empty() or view.battle_audio.played.has(death_path), "#244: its death sound plays")
	check(not duel.creatures.has(blocker), "#244: the rules killed the blocker")
	await _idle(view)
	check(ids.all(func(id: int) -> bool: return not view.melee.away(id) and view.models[id].base_clip() == "ctapidle"),
		"#272: the attackers are home and lying down to rest (%s)" % str(ids.map(func(id: int) -> String: return view.models[id].clip)))
	check(int(view.shown_health(1 - side)) == int(duel.heroes[1 - side].health), "#244: every blow is shown in the end")

func _hidden_movement(view: Node) -> void:
	var duel: ELDuel = view.duel
	view.settings.values.hide_motion = true
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var id := await _creature(view, side, _card(view, "Treant"), 1, 9)
	if id < 2 or not duel.toggle_attack(id):
		check(false, "hide movement: a treant attacks")
		view.settings.values.hide_motion = false
		return
	await _idle(view)
	var clips: Array[String] = []
	view.models[id].animation_started.connect(func(clip: String) -> void: clips.append(clip))
	view.battle_audio.requested.clear()
	duel.end_phase()
	if duel.phase == ELDuel.Phase.DEFENCE: duel.end_phase()
	await _idle(view)
	for i in 6:
		if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
		await _idle(view)
	var tap_sound: bool = view.battle_audio.requested.any(func(path: String) -> bool: return path.ends_with("/tap.wav") or path.ends_with("/untap.wav"))
	check(clips.has("uattack") and clips.has("ctapidle") and not clips.has("utap") and not clips.has("uuntap") and not tap_sound,
		"hide movement: the treant lies down and gets up without its tap clips or sounds (%s)" % ", ".join(clips))
	view.settings.values.hide_motion = false

## Space during a spell ends its gesture but not its sounds; "Hide casting
## animations" drops the gesture together with the caster's voice.
func _cast_sounds(view: Node) -> void:
	var duel: ELDuel = view.duel
	await _clear(view)
	var side: int = duel.active_side()
	var target := await _creature(view, 1 - side, _card(view, "Treant"), 1, 20)
	var spell := "ZAPP"
	var paths: Array[String] = view.battle_audio.spell_paths(spell)
	if target < 2 or paths.is_empty():
		check(false, "#244: Electroshock has a target and a sound")
		return
	# The audio readouts keep only recent entries: start them afresh.
	view.battle_audio.played.clear()
	view.battle_audio.requested.clear()
	check(duel.cast_free(side, spell, [target], true), "#244: Electroshock is cast (%s)" % duel.error)
	await process_frame
	view._skip_battle_step()
	for i in 10: await process_frame
	var heard: Array = view.battle_audio.played
	check(paths.any(func(path: String) -> bool: return heard.has(path)), "#244: Space leaves the spell's sound (%s in %s)" % [str(paths), str(heard)])
	await _idle(view)
	var voice_folder := "Creatures/%s/" % String(view.models[side].get_meta("sound_directory", ""))
	view.settings.values.hide_cast = true
	view.battle_audio.requested.clear()
	duel.cast_free(side, spell, [target], true)
	for i in 10: await process_frame
	var requested: Array = view.battle_audio.requested
	check(not requested.any(func(path: String) -> bool: return path.begins_with(voice_folder)), "#244: hidden casting animations take the caster's voice with them (%s)" % str(requested))
	view.settings.values.hide_cast = false
	await _idle(view)

## A lethal attack with Space pressed every frame: the hero still falls.
func _hero_death(view: Node) -> void:
	var duel: ELDuel = view.duel
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var loser := 1 - side
	var id := await _creature(view, side, _card(view, "Treant"), 9, 9)
	if id < 2 or not duel.toggle_attack(id):
		check(false, "#244: a lethal attacker stands")
		return
	await _idle(view)
	duel.heroes[loser].health = 3
	var death_path: String = view.battle_audio.unit_path(view.models[loser], "death")
	view.battle_audio.played.clear()
	duel.end_phase()
	if duel.phase == ELDuel.Phase.DEFENCE: duel.end_phase()
	var dying := 0.0
	var victory := 0.0
	var clip_cut := false
	var start := Time.get_ticks_usec()
	# Whether the death sound still plays a moment into the fall.
	var sounding := false
	var probed := false
	var death_sound := ELAudio.sound(view.profile, death_path) if not death_path.is_empty() else null
	var heard_death := false
	for i in 2000:
		view._skip_battle_step()
		await process_frame
		if view.battle_audio.played.has(death_path): heard_death = true
		if not view.ending.is_empty() and String(view.ending.stage) == "dying":
			dying += get_root().get_process_delta_time()
			if dying >= 0.3 and not probed:
				probed = true
				for voice: AudioStreamPlayer in view.battle_audio.voices:
					if voice.playing and death_sound != null and voice.stream == death_sound: sounding = true
		if not view.ending.is_empty() and String(view.ending.stage) == "victory":
			victory += get_root().get_process_delta_time()
			if victory > 0.1 and view.models[side].clip == "cidle": clip_cut = true
		if not view.ending.is_empty() and view.ending_over(): break
	var clip: float = maxf(view.models[loser].clip_seconds("udeath"), 0.0)
	check(duel.phase == ELDuel.Phase.FINISHED and view.ending_over(), "#244: the battle ends")
	check(dying >= clip - 0.1, "#244: Space never cuts the fallen hero's death clip (%.2f s of %.2f s)" % [dying, clip])
	check(death_path.is_empty() or heard_death, "#244: the fallen hero's death sound plays")
	check(death_sound == null or death_sound.get_length() < 0.4 or sounding, "#244: Space does not stop the death sound")
	# Space ends the winner's victory clip at once, but the battle lasts
	# until its fanfare has played out (#272).
	var fanfare := float(view.ending.get("fanfare", 0.0))
	check(clip_cut or view.victory_clip(view.models[side]).is_empty(), "#244: Space ends the victory clip at once (%s)" % view.models[side].clip)
	check(victory >= fanfare - 0.1, "#272: the battle lasts until the victory fanfare (%.2f s) has played out (%.2f s)" % [fanfare, victory])
	print("ending took %.2f s" % ((Time.get_ticks_usec() - start) / 1e6))

func _card(view: Node, race: String) -> String:
	var table: Dictionary = view.profile.table("CombatCreatures")
	for card: String in table:
		if str(table[card].get("Race", "")) == race and view.duel.is_summon(card) and str(table[card].get("Model", "")) != "": return card
	return ""

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held() and not view.figures_turning(): return

## A fresh creature of `card` on `side`, ready to act, with the given stats.
func _creature(view: Node, side: int, card: String, power: int, toughness: int) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 40)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if before.has(id): continue
		var c: Dictionary = duel.creatures[id]
		c.base = [power, toughness]
		c.sick = false
		c.resting = false
		duel._refresh_stats(c)
		await _idle(view)
		return id
	return -1

## Removes every creature, so each case starts on an empty field.
func _clear(view: Node) -> void:
	var duel: ELDuel = view.duel
	for id: int in duel.creatures.keys():
		duel.creatures.erase(id)
		view._remove_model(id)
	for side in 2:
		duel.heroes[side].health = 30
		duel.heroes[side].mana = 40
	await _idle(view)

## Brings `side`'s attack phase.
func _attack_turn(view: Node, side: int) -> void:
	var duel: ELDuel = view.duel
	for i in 6:
		if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
		await _idle(view)
