extends SceneTree
## Headless regression for custom adventure spellbooks and hidden map models.
## Pass a folder of unpacked custom map files and its map ID to test real
## encounters as well. Requires Etherlords II in user://profiles.json.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2: ELCustomMaps.extra_roots.append(args[0])
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	var profile := ELProfile.new()
	if paths is not Dictionary or not profile.mount("el2", str(paths.get("el2", ""))):
		printerr("Configure Etherlords II in user://profiles.json.")
		quit(1)
		return
	_hidden_model()
	_spells(profile)
	if args.size() >= 2: _encounters(profile, args[1])
	print("CUSTOM ENCOUNTERS: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

func _hidden_model() -> void:
	var model := ELModel.new()
	root.add_child(model)
	model.skip_hidden_pose = true
	model.clip = "cidle"
	model._clip_frames = 4
	model.playing = true
	model.timing.cidle = {"events": [1]}
	var cues := []
	model.frame_event.connect(func(clip: String): cues.append(clip))
	model.hide()
	model._process(2.0 / 30.0)
	check(model.frame == 2.0 and model.sample_count == 0 and cues == ["cidle"],
		"A hidden map model advances its animation and cues without sampling the pose")
	model.show()
	check(model.frame == 2.0 and model.sample_count == 1, "Revealing a model immediately samples its current pose")
	model.free()

func _spells(profile: ELProfile) -> void:
	var cards := ["DMRD", "LNRD", "RDCM", "RDHL", "RDRS", "WNBL", "RDCL", "SPRG"]
	var players := [{"faction": "Black", "cards": cards}, {"faction": "Green", "cards": ["GBAT"]}]
	var duel := ELDuel.new()
	var started := duel.start(profile, 212, {"players": players, "adventure": true})
	check(started, "Artifact spell codes can be part of an adventure deck")
	if not started: return
	check(not ELDuel.new().start(profile, 212, {"players": players}), "The same selection is excluded from regular duel decks")
	var hero := duel.heroes[0]
	var enemy := duel.heroes[1]
	var health := int(hero.health)
	check(_cast(duel, "RDHL") and int(hero.health) == health + 7, "Rod of Healing casts for seven health")
	duel._summon(0, "GBAT")
	var own := duel.next_id - 1
	duel._summon(1, "GBAT")
	var opposing := duel.next_id - 1
	var power := int(duel.entity(own).power)
	check(_cast(duel, "DMRD") and int(duel.entity(own).power) == power + 1, "Rod of Dominance buffs the caster's army")
	check(_cast(duel, "LNRD") and duel._enchantment_count(0, "LNRD") == 1, "Lightning Rod applies its reflection enchantment")
	check(not _cast(duel, "RDCM", own) and _cast(duel, "RDCM", opposing) and duel.entity(opposing).owner == 0,
		"Rod of Command takes control of an opposing creature")
	check(_cast(duel, "WNBL", own) and int(duel.entity(own).power) == power + 5, "Wand of Bless restores its temporary +4/+4 effect")
	hero.grave = ["GBAT"]
	enemy.grave = ["GBAT"]
	check(not _cast(duel, "RDRS", 1, 0) and _cast(duel, "RDRS", 0, 0) and hero.grave.is_empty() and enemy.grave == ["GBAT"],
		"Rod of Resurrection summons from the caster's graveyard")
	duel._summon(1, "GBAT")
	var target := duel.next_id - 1
	health = int(enemy.health)
	check(_cast(duel, "RDCL", target) and not duel.creatures.has(target) and int(enemy.health) == health - 1,
		"Rod of Colossus hits the target and splashes its hero")
	duel._summon(1, "GBAT")
	target = duel.next_id - 1
	duel.attacker = 1
	duel.phase = ELDuel.Phase.DEFENCE
	var refused := not _cast(duel, "SPRG", target)
	duel.attacks.append(target)
	check(refused and _cast(duel, "SPRG", target) and not duel.creatures.has(target),
		"Spear of Rage can destroy only an attacking creature and can be cast in defence")
	var reserve := {"spell_stock": {}}
	check(ELSpellInventory.add(profile, reserve, "RDHL") and reserve.spell_stock.get("RDHL") == 1,
		"An authored spell reward can add a rod to the reserve")

func _cast(duel: ELDuel, card: String, target := -1, choice := -1) -> bool:
	var hero := duel.heroes[0]
	hero.hand = [card]
	hero.hand_slots = [-1]
	hero.mana = 10
	return duel.cast(0, target, choice)

func _encounters(profile: ELProfile, id: String) -> void:
	var map := ELAdventureMap.new()
	var loaded := map.load_map(profile, id)
	check(loaded, "Load custom scenario " + id)
	if not loaded: return
	for difficulty in 3:
		var state := ELAdventureSession.new()
		var director := ELAdventureDirector.new()
		var built := state.start(map, difficulty) and director.build(state)
		check(built, "Start custom scenario on difficulty %d" % difficulty)
		if not built:
			state.close()
			continue
		var hero := state.object(state.main_hero)
		var count := 0
		for opponent: Dictionary in state.objects.values():
			if opponent.uid == state.main_hero or not opponent.alive or opponent.type not in ["hero", "monster"]: continue
			director.battle_refusal = ""
			director._begin_encounter(hero, opponent)
			if director.encounter != null and director.encounter.battle != null:
				director.encounter.battle.attach_session(null)
				count += 1
			else: check(false, "%s on difficulty %d: %s" % [opponent.name, difficulty, director.battle_refusal])
			director.encounter = null
		check(count > 0, "%d encounters start on difficulty %d" % [count, difficulty])
		state.close()
