extends SceneTree
## Presentation checks for three player reports, in both games:
##
## - #322: a hero using an artifact plays the gesture its spell's kind asks
##   for, as a cast of that spell does (instant, enchantment or summoning,
##   falling back to the instant and the attack clip), with that gesture's
##   voice; the artifact's own sound waits for the gesture's release. "Hide
##   casting animations" drops gesture and voice.
## - #318: Wall of Lava, Wall of Hellfire and Wall of Wind play an action
##   clip (their figures have no instant clip: the attack clip) with its
##   sound when their ether ability is used, besides PosAttack/PosDefence.
## - #312: the same sound started for many creatures at once (a gas, an
##   Orc Chieftain's tirelessness) is heard once, at the nearest creature's
##   level, not once per creature; the same sound a moment later plays again.
##
##   godot --headless --path game --script ../tools/issues_312_322_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	view.settings.values.hide_cast = false
	view.settings.values.heroes_voices = true
	view.battle_audio.settings.heroes_voices = true
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])) or not view.profiles.has(edition):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		view._start(edition)
		await _idle(view)
		await _artifact_gesture(view, edition)
		await _wall_abilities(view, edition)
		await _mass_sounds(view, edition)
	view.queue_free()
	await process_frame
	print("ISSUES 312/318/322: %d failure(s)" % failures)
	quit(int(failures > 0))

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() \
				and view._effect_cast.is_empty() and not view._shown_held() and not view.figures_turning(): return

func _frames(count: int) -> void:
	for i in count: await process_frame

func _seconds(view: Node, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		view.ai_clock = -1000.0
		await process_frame

## Removes every creature and gives both heroes plenty of health and ether.
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
	for i in 8:
		if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK: return
		duel.end_phase()
		await _idle(view)

## A fresh creature of `card` on `side`, awake and settled.
func _creature(view: Node, side: int, card: String) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 40)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	for id: int in duel.creatures:
		if before.has(id): continue
		duel.creatures[id].sick = false
		duel.creatures[id].resting = false
		await _idle(view)
		return id
	return -1

## An untargeted artifact `side` may use now: the Rod of Healing if the
## edition has one, else the first such artifact; with `gesture`, the first
## whose spell asks for that casting gesture.
func _ready_artifact(view: Node, duel: ELDuel, side: int, gesture := "") -> Dictionary:
	var names: Array = duel.profile.table("Artefacts").keys()
	names.sort()
	names.sort_custom(func(a: String, b: String) -> bool:
		return String(duel.profile.table("Artefacts")[a].get("SpellType", "")) == "RDHL" and String(duel.profile.table("Artefacts")[b].get("SpellType", "")) != "RDHL")
	for name: String in names:
		var entry := ELDuel.artifact_entry(duel.profile, {"name": name})
		if entry.is_empty() or entry.has("custom") or duel.is_summon(String(entry.spell)): continue
		if not gesture.is_empty() and view._cast_gesture(String(entry.spell)) != gesture: continue
		if String(duel.artifact_rule(entry).get("target", "none")) != "none": continue
		entry.charges = 1
		entry.ready_round = 0
		duel.heroes[side].artifacts = [entry]
		duel.heroes[side].artifact_uses = 0
		if duel.artifact_error(side, 0).is_empty(): return entry
	return {}

func _artifact_gesture(view: Node, edition: String) -> void:
	var duel: ELDuel = view.duel
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	var hero: ELModel = view.models[side]
	for run: Array in [[false, ""], [true, ""], [false, "uenchantment"]]:
		var hidden: bool = run[0]
		var what := "%s #322%s%s" % [edition, " (casting animations hidden)" if hidden else "", (" " + String(run[1])) if not String(run[1]).is_empty() else ""]
		view.settings.values.hide_cast = hidden
		var item := _ready_artifact(view, duel, side, String(run[1]))
		if item.is_empty():
			if not String(run[1]).is_empty():
				print("SKIP: %s: no untargeted artifact of that kind" % what)
				continue
			check(false, "%s: an untargeted artifact can be used" % what)
			continue
		var gesture: String = view._artifact_clip(side, String(item.spell))
		check(gesture == view._cast_clip(side, String(item.spell)) and not gesture.is_empty(),
			"%s: %s asks for its spell's casting gesture (%s for %s)" % [what, item.name, gesture, view._cast_gesture(String(item.spell))])
		var voice := "Creatures/%s/voice/%s" % [String(hero.get_meta("sound_directory", "")), gesture.trim_prefix("u")]
		var sounds: Array[String] = view.battle_audio.spell_paths(String(item.spell))
		var clips: Array[String] = []
		var listen := func(clip: String) -> void: clips.append(clip)
		hero.animation_started.connect(listen)
		view.battle_audio.requested.clear()
		check(duel.use_artifact(side, 0), "%s: the hero uses %s (%s)" % [what, item.name, duel.error])
		await process_frame
		var early: Array = view.battle_audio.requested.duplicate()
		await _seconds(view, 2.5)
		await _idle(view)
		hero.animation_started.disconnect(listen)
		var spoke: bool = view.battle_audio.requested.any(func(path: String) -> bool: return path.begins_with(voice))
		if hidden:
			check(not clips.has(gesture) and not spoke, "%s: no gesture and no voice (%s)" % [what, ", ".join(clips)])
		else:
			check(clips.has(gesture), "%s: the hero plays its %s gesture (%s)" % [what, gesture, ", ".join(clips)])
			check(spoke, "%s: the hero's %s voice is heard (%s*)" % [what, gesture.trim_prefix("u"), voice])
			check(sounds.is_empty() or not sounds.any(func(path: String) -> bool: return early.has(path)),
				"%s: the artifact's sound waits for the gesture's release (%s)" % [what, str(sounds)])
		check(sounds.all(func(path: String) -> bool: return view.battle_audio.requested.has(path)),
			"%s: the artifact's own sound plays (%s)" % [what, str(sounds)])
	view.settings.values.hide_cast = false

func _wall_abilities(view: Node, edition: String) -> void:
	var duel: ELDuel = view.duel
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	for card: String in ["WLLV", "WLIF", "WLWD"]:
		var what := "%s #318 %s" % [edition, duel.card_name(card)]
		if not duel.profile.table("CombatCreatures").has(card):
			print("SKIP: %s not in this game" % what)
			continue
		var wall := await _creature(view, side, card)
		if wall < 2:
			check(false, "%s: the wall stands" % what)
			continue
		var model: ELModel = view.models[wall]
		var ability: Dictionary = ELCatalog.first_ability(duel.profile, card)
		var effect := "PosDefence" if ability.key == "hellfire_health" else "PosAttack"
		var clips: Array[String] = []
		var listen := func(clip: String) -> void: clips.append(clip)
		model.animation_started.connect(listen)
		view.battle_audio.requested.clear()
		view.effects.started.clear()
		duel.heroes[side].mana = 40
		check(duel.use_ability(wall, String(ability.key), -1, -1, 2), "%s: the ability is used (%s)" % [what, duel.error])
		await _frames(3)
		model.animation_started.disconnect(listen)
		var action := "uinstant" if model.has_clip("uinstant") else "uattack"
		check(clips.has(action), "%s: the wall plays its %s clip (%s)" % [what, action, ", ".join(clips)])
		var own: String = view.battle_audio.unit_path(model, action.trim_prefix("u"))
		check(view.battle_audio.requested.has(own), "%s: with its own sound %s" % [what, own])
		var magic: String = view.battle_audio.effect_sound(effect)
		check(view.battle_audio.requested.has(magic) and view.effects.started.has(effect), "%s: %s is shown and heard" % [what, effect])
		await _idle(view)

func _mass_sounds(view: Node, edition: String) -> void:
	var duel: ELDuel = view.duel
	var audio: ELBattleAudio = view.battle_audio
	await _clear(view)
	await _attack_turn(view, duel.attacker)
	var side: int = duel.attacker
	# The sound itself: five starts in one moment are one voice.
	var path := audio.effect_sound("PosAttack")
	audio.requested.clear()
	audio.played.clear()
	var taken: Array = []
	for i in 5:
		audio.play(path, 0.2 + i * 0.1)
		if not taken.has(audio._last_voice): taken.append(audio._last_voice)
	check(audio.played.count(path) == 1 and taken.size() == 1, "%s #312: five starts of %s at once take one voice (%d played, %d voices)" % [edition, path, audio.played.count(path), taken.size()])
	check(taken.size() == 1 and is_instance_valid(taken[0]) and is_equal_approx(float(taken[0].get_meta("spatial_gain", 0.0)), ELAudio.placed_gain(0.6, edition)),
		"%s #312: that voice has the loudest start's level" % edition)
	await _seconds(view, 0.2)
	audio.play(path)
	check(audio.played.count(path) == 2, "%s #312: the same sound a moment later plays again" % edition)
	# A gas reaching every creature of the opponent.
	var gas := "DPGS"
	if duel.profile.table("CombatSpells").has(gas):
		for i in 4: await _creature(view, 1 - side, "ORWR")
		var effects: Array = preload("res://src/duel/combat_sound_table.gd").AURA_EFFECTS[gas]
		var cue := audio.effect_sound(String(effects[0]))
		await _idle(view)
		audio.requested.clear()
		audio.played.clear()
		check(duel.cast_free(side, gas, [], true), "%s #312: the gas is cast (%s)" % [edition, duel.error])
		await _seconds(view, 3.0)
		await _idle(view)
		check(audio.requested.count(cue) >= 4 and audio.played.count(cue) == 1,
			"%s #312: the gas's %s is heard once for its %d creatures (%d played)" % [edition, cue, audio.requested.count(cue), audio.played.count(cue)])
	# The Orc Chieftain's tirelessness on every orc.
	await _clear(view)
	if duel.profile.table("CombatCreatures").has("OREL"):
		for i in 3: await _creature(view, side, "ORWR")
		var cue := audio.effect_sound("Restless")
		audio.requested.clear()
		audio.played.clear()
		await _creature(view, side, "OREL")
		await _seconds(view, 1.0)
		check(cue.is_empty() or audio.requested.count(cue) <= 1 or audio.played.count(cue) == 1,
			"%s #312: the chieftain's Restless is heard once for its orcs (%d requested, %d played)" % [edition, audio.requested.count(cue), audio.played.count(cue)])
