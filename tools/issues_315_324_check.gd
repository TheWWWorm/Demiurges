extends SceneTree
## Regression checks for the second game's Pale presentation reports:
##
## - #315: the Pale Reaper, Destroyer and Slayer (OUD1-3) stream PaleDrainLife
##   to their prey; their hero's GainLife (Reaper, Destroyer) or GainMana
##   (Slayer) shows only when the prey dies. A prey that survives (a bright
##   Pale creature dissipates) shows no gain at the hero.
## - #323: the Pale Hammer (OCLV) on an ordinary creature recalls it as
##   Unsummon does: BlueDeath at the creature and Draw at the hero its card
##   goes back to, with their sounds, and no OutplaneSpellDeath. On a Pale
##   creature it shows OutplaneSpellDeath alone.
## - #324: the Pale Ripple (ORPL) shows its stat gains (PosAttack, PosDefence,
##   PosRune) only at the caster's creatures in the Ether, none at creatures
##   of the Colourless Plane; a spell-jammer that the Ripple springs from a
##   trap stays hidden until the hero's cast and the spell's effects are over,
##   then appears in its own summon effect (OutplanarSummon).
##
##   godot --headless --path game --script ../tools/issues_315_324_check.gd
##
## Needs the second game's files (user://profiles.json); without them it is
## skipped. Settings are never written.

var failures := 0
## Every effect request (name and bound figures) and every sound path the
## battle view asks for.
var fx: Array[Dictionary] = []
var sound: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no el2 files configured (user://profiles.json)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el2", str(paths["el2"])):
		print("SKIP: el2 files could not be mounted")
		quit(0)
		return
	_devour_rules(profile)
	await _view_checks()
	print("ISSUES 315-324: %d failure(s)" % failures)
	quit(int(failures > 0))

## A fresh second-game duel with no creatures, side 0 to act in its attack
## phase with plenty of ether.
func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	duel.start(profile, 5, {})
	for id: int in duel.creatures.keys(): duel.creatures.erase(id)
	for i in 8:
		if duel.active_side() == 0 and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
	for hero: Dictionary in duel.heroes:
		hero.health = 20
		hero.mana = 30
		hero.hand = []
		hero.hand_slots = []
		hero.hand_view = []
		hero.enchantments = []
		hero.spec = "NONE"
		hero.skills = {}
	return duel

func _summoned(duel: ELDuel, side: int, card: String, plane := false) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key):
			duel.creatures[key].sick = false
			duel.creatures[key].resting = false
			duel.creatures[key].plane = plane
			return key
	return -1

func _kinds(entries: Array) -> Array:
	return entries.map(func(e: Dictionary) -> String: return String(e.kind))

## The rules' cue for the devourer's gain comes with a kill only.
func _devour_rules(profile: ELProfile) -> void:
	for card: String in ["OUD1", "OUD2", "OUD3"]:
		for survives: bool in [false, true]:
			var duel := _duel(profile)
			var devourer := _summoned(duel, 0, card)
			duel.creatures[devourer].power = 9
			duel.creatures[devourer].toughness = 9
			# A bright Pale prey dissipates instead of dying; a plain one dies.
			var prey := _summoned(duel, 1, "SMFX" if survives else "STRT")
			duel.creatures[prey].power = 1
			duel.creatures[prey].toughness = 1
			var start := duel.history.size()
			var used := duel.use_ability(devourer, "pale_devour", prey)
			var events := duel.history.slice(start)
			var cue := events.filter(func(e: Dictionary) -> bool: return e.kind == "devour_gain_cue")
			var what := "%s devours a %s prey" % [card, "surviving" if survives else "dying"]
			check(used, what + ": the ability is used (%s)" % duel.error)
			if survives:
				check(duel.creatures.has(prey) and cue.is_empty() and not _kinds(events).has("heal") and not _kinds(events).has("channels"),
					what + ": the prey lives on and the hero gains nothing, so no gain cue (%s)" % str(_kinds(events)))
			else:
				check(not duel.creatures.has(prey) and cue.size() == 1 and int(cue[0].side) == 0 and String(cue[0].card) == card,
					what + ": one gain cue for the devourer's hero (%s)" % str(_kinds(events)))

## Waits until nothing of the previous action is on screen.
func _idle(view: Node) -> void:
	for i in 900:
		view.ai_clock = -1000.0
		await process_frame
		if not view._cast_busy() and not view._presentation_held() and view._hits_waiting.is_empty() and view._arrivals.is_empty() and view._effect_cast.is_empty(): return

func _put(view: Node, side: int, card: String, plane: bool) -> int:
	var duel: ELDuel = view.duel
	var before: Array = duel.creatures.keys()
	duel.heroes[side].mana = maxi(int(duel.heroes[side].mana), 30)
	duel.cast_free(side, card, [], false)
	await _idle(view)
	var id := -1
	for key: int in duel.creatures:
		if not before.has(key): id = key
	if id >= 2:
		duel.creatures[id].sick = false
		duel.creatures[id].resting = false
		if duel.in_plane(id) != plane: duel.plane_change(id, plane)
		await _idle(view)
	return id

## Requests of `effect` since `from`, as the lists of figures bound to `point`.
func _bound(view: Node, from: int, effect: String, point := "Target") -> Array:
	var out: Array = []
	var log: Array = fx
	for i in range(from, log.size()):
		if String(log[i].effect) == effect: out.append(log[i].bindings.get(point, []))
	return out

func _bound_to(view: Node, from: int, effect: String, id: int) -> bool:
	for figures: Array in _bound(view, from, effect):
		if figures.has(view.models.get(id)): return true
	return false

func _heard(view: Node, from: int, effect: String) -> bool:
	var path: String = view.battle_audio.effect_sound(effect)
	return not path.is_empty() and sound.slice(from).has(path)

func _cast(view: Node, side: int, card: String, target: int) -> bool:
	var duel: ELDuel = view.duel
	duel.heroes[side].mana = 30
	duel._give_card(side, card)
	var ok := duel.cast(duel.heroes[side].hand.rfind(card), target, -1)
	if not ok: print("  cast %s: %s" % [card, duel.error])
	return ok

func _view_checks() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has("el2"):
		print("SKIP: el2 files could not be mounted")
		view.queue_free()
		await process_frame
		return
	view.settings.values.hide_cast = false
	view._start("el2")
	view.effects.effect_requested.connect(func(effect: String, bindings: Dictionary) -> void: fx.append({"effect": effect, "bindings": bindings}))
	view.battle_audio.sound_requested.connect(func(path: String) -> void: sound.append(path))
	await _idle(view)
	var duel: ELDuel = view.duel
	var side := duel.active_side()
	for hero: Dictionary in duel.heroes:
		hero.spec = "NONE"
		hero.health = 40
	# Room in both armies.
	for id: int in duel.creatures.keys():
		duel._remove_creature(id, "unsummon")
	await _idle(view)
	await _devour_view(view, side)
	await _hammer_view(view, side)
	await _ripple_view(view, side)
	view.queue_free()
	await process_frame
	await process_frame

## #315 on screen: no hero gain when the prey survives, one when it dies.
func _devour_view(view: Node, side: int) -> void:
	var duel: ELDuel = view.duel
	for card: String in ["OUD1", "OUD3"]:
		var gain := "GainLife" if card == "OUD1" else "GainMana"
		for survives: bool in [true, false]:
			var devourer := await _put(view, side, card, false)
			var prey := await _put(view, 1 - side, "SMFX" if survives else "STRT", false)
			if devourer < 2 or prey < 2:
				check(false, "%s: the devourer and its prey stand" % card)
				return
			duel.creatures[devourer].power = 9
			duel.creatures[devourer].toughness = 9
			duel.creatures[prey].power = 1
			duel.creatures[prey].toughness = 1
			duel.heroes[side].mana = 30
			var from: int = fx.size()
			var heard: int = sound.size()
			var used := duel.use_ability(devourer, "pale_devour", prey)
			await _idle(view)
			var what := "#315 %s on a %s prey" % [card, "surviving" if survives else "dying"]
			check(used and _bound(view, from, "PaleDrainLife", "Finish").any(func(f: Array) -> bool: return f.has(view.models.get(prey)) or (not survives)),
				what + ": PaleDrainLife streams to the prey")
			if survives:
				check(not _bound_to(view, from, gain, side) and not _heard(view, heard, gain), what + ": no %s at the hero" % gain)
			else:
				check(_bound_to(view, from, gain, side) and _heard(view, heard, gain), what + ": %s at the hero" % gain)
			for id: int in [devourer, prey]:
				if duel.creatures.has(id): duel._remove_creature(id, "unsummon")
			await _idle(view)

## #323 on screen.
func _hammer_view(view: Node, side: int) -> void:
	var duel: ELDuel = view.duel
	var plain := await _put(view, 1 - side, "STRT", false)
	var from: int = fx.size()
	var heard: int = sound.size()
	var model: Node = view.models.get(plain)
	var cast := _cast(view, side, "OCLV", plain)
	check(cast and not duel.creatures.has(plain) and duel.heroes[1 - side].hand.has("STRT"), "#323 the Pale Hammer sends an ordinary creature back to its owner's hand")
	check(is_instance_valid(model) and view.models.get(plain) == model, "#323 the recalled figure stays until the spell is released")
	await _idle(view)
	var blue := false
	for figures: Array in _bound(view, from, "BlueDeath"):
		if figures.has(model): blue = true
	check(blue and _heard(view, heard, "BlueDeath"), "#323 the recall shows and sounds BlueDeath at the creature")
	check(_bound_to(view, from, "Draw", 1 - side) and _heard(view, heard, "Draw"), "#323 Draw at the hero the card goes back to")
	check(_bound(view, from, "OutplaneSpellDeath").is_empty() and not _heard(view, heard, "OutplaneSpellDeath"), "#323 no Pale death effect or sound for an ordinary creature")
	check(not view.models.has(plain), "#323 the recalled figure is gone afterwards")
	var bright := await _put(view, 1 - side, "SMFX", false)
	from = fx.size()
	heard = sound.size()
	cast = _cast(view, side, "OCLV", bright)
	await _idle(view)
	check(cast and not duel.creatures.has(bright) and duel.heroes[1 - side].grave.has("SMFX"), "#323 the Pale Hammer destroys a bright Pale creature")
	check(_heard(view, heard, "OutplaneSpellDeath") and not _bound(view, from, "OutplaneSpellDeath").is_empty() and _bound(view, from, "BlueDeath").is_empty() and _bound(view, from, "Draw").is_empty(),
		"#323 a Pale creature destroyed shows OutplaneSpellDeath alone")

## #324 on screen.
func _ripple_view(view: Node, side: int) -> void:
	var duel: ELDuel = view.duel
	var friend_ether := await _put(view, side, "STRT", false)
	var friend_plane := await _put(view, side, "SMWB", true)
	var enemy_plane := await _put(view, 1 - side, "SMWB", true)
	var enemy_ether := await _put(view, 1 - side, "STRT", false)
	# A Pale Avenger trap of the opponent's answers any sorcery.
	duel.heroes[1 - side].mana = 30
	duel.cast_free(1 - side, "OST1", [], true)
	await _idle(view)
	check(duel.heroes[1 - side].enchantments.any(func(e: Dictionary) -> bool: return e.card == "OST1"), "#324 the opponent holds a Pale Avenger trap")
	var before: Array = duel.creatures.keys()
	var from: int = fx.size()
	var begin := Time.get_ticks_usec()
	var cast := _cast(view, side, "ORPL", -1)
	var jammer := -1
	for id: int in duel.creatures:
		if not before.has(id) and String(duel.creatures[id].card) == "OSJ1": jammer = id
	check(cast and jammer >= 2 and view.models.has(jammer), "#324 the Ripple springs the trap: a Pale Avenger comes into play")
	if jammer < 2 or not view.models.has(jammer): return
	var jammer_model: Node = view.models[jammer]
	check(not jammer_model.visible, "#324 the Avenger is not shown while the hero casts")
	var gesture: float = maxf(0.0, view.models[side].clip_seconds(view._cast_clip(side, "ORPL")))
	var shown_at := -1.0
	var effect_at := -1.0
	var ripple_at := -1.0
	for i in 1500:
		view.ai_clock = -1000.0
		await process_frame
		var seconds := (Time.get_ticks_usec() - begin) / 1000000.0
		if ripple_at < 0.0 and not _bound(view, from, "OuterRipple").is_empty(): ripple_at = seconds
		if effect_at < 0.0 and _bound_to(view, from, "OutplanarSummon", jammer): effect_at = seconds
		if shown_at < 0.0 and is_instance_valid(jammer_model) and jammer_model.visible: shown_at = seconds
		if shown_at >= 0.0 and effect_at >= 0.0 and not view._cast_busy() and view._arrivals.is_empty(): break
	await _idle(view)
	print("  cast gesture %.2f s, OuterRipple at %.2f s, Avenger's summon effect at %.2f s, shown at %.2f s" % [gesture, ripple_at, effect_at, shown_at])
	check(ripple_at >= 0.0 and effect_at > ripple_at and effect_at >= gesture - 0.05,
		"#324 the Avenger's summon effect starts after the hero's cast and the Ripple's own effect")
	check(effect_at >= 0.0 and shown_at >= effect_at, "#324 the Avenger appears in its summon effect, not before it")
	var buffs: Array = _bound(view, from, "PosAttack") + _bound(view, from, "PosDefence") + _bound(view, from, "PosRune")
	var on := func(id: int) -> bool:
		for figures: Array in buffs:
			if figures.has(view.models.get(id)): return true
		return false
	check(on.call(friend_ether), "#324 the caster's creature in the Ether shows the stat gain")
	check(not on.call(enemy_plane) and not on.call(enemy_ether), "#324 no stat gain shows at the opponent's creatures")
	check(not on.call(friend_plane), "#324 no stat gain shows at the caster's creatures in the Colourless Plane")
	check(not on.call(jammer), "#324 the sprung Avenger takes no part in the Ripple's effects")
	var hit := false
	for figures: Array in _bound(view, from, "OuterRipple"):
		if figures.has(view.models.get(enemy_plane)) or figures.has(view.models.get(friend_plane)): hit = true
	check(hit, "#324 OuterRipple strikes the creatures in the Colourless Plane")
