extends SceneTree
## godot --headless --path game --script ../tools/d2_combat_rules_check.gd
## Requires Etherlords II in user://profiles.json.

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures := 0

func _initialize() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
	var profile := ELProfile.new()
	if paths is not Dictionary or not profile.mount("el2", str(paths.get("el2", ""))):
		printerr("Configure Etherlords II in user://profiles.json.")
		quit(1)
		return
	_colourless_enchantments(profile)
	_transfer_aspects(profile)
	_reflected_trade(profile)
	print("D2 COMBAT RULES: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

func _check(ok: bool, label: String) -> bool:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1
	return ok

func _cast(duel: ELDuel, card: String, target := -1, power := 0) -> bool:
	var hero: Dictionary = duel.heroes[duel.active_side()]
	duel._give_card(duel.active_side(), card)
	return duel.cast(hero.hand.size() - 1, target, -1, power)

func _colourless_enchantments(profile: ELProfile) -> void:
	var duel := ELDuel.new()
	if not _check(duel.start(profile, 11), "#232: duel starts"): return
	duel.heroes[0].mana = 80
	duel.heroes[0].channels = 3
	var id := duel.next_id
	duel._summon(0, "OUD1")
	if not _check(duel.use_ability(id, "fiendish"), "#232: the Pale creature manifests"): return
	var creature := duel.entity(id)
	var printed := duel.creature_stats(creature)
	if not _check(_cast(duel, "MGHT", id) and _cast(duel, "SHSK", id) and _cast(duel, "SGHT", id) \
		and _cast(duel, "ENBR", id), "#232: coloured and Colourless enchantments are attached"): return
	var modified := duel.creature_stats(creature)
	var attached: Array = creature.enchantments.duplicate(true)
	_check(modified == printed + Vector2i(3, 4) and duel.has_flag(id, "Disenchant"), "#232: coloured effects apply in the Ether")
	var ctx := Fixtures.context(profile, 0)
	if ELCombatBrain.available:
		_check(ELCombatBrain.choose(ctx, duel, 1, 100, 1).is_empty(), "#232: lookahead defers to full duel rules when effects can be suspended")
	if not _check(_cast(duel, "BNSH", id) and duel.in_plane(id), "#232: Banish moves the enchanted creature"): return
	_check(Vector2i(creature.power, creature.toughness) == printed and not duel.has_flag(id, "Disenchant") \
		and creature.enchantments == attached, "#232: coloured stats and abilities are suspended without detaching enchantments")
	if ELCombatBrain.available:
		_check(ELCombatBrain.choose(ctx, duel, 1, 100, 1).is_empty(), "#232: lookahead defers when manifestation can restore effects")
	_check(duel._damage(id, 3, false, false, true, true) == 0, "#232: a Colourless Energy Barrier still works in the plane")
	var saved := duel.snapshot()
	var saved_creature: Dictionary = saved.creatures[id]
	saved_creature.power = modified.x
	saved_creature.toughness = modified.y
	saved_creature.granted = ["Disenchant"]
	var restored := ELDuel.new()
	_check(restored.restore(profile, {"format": "etherlords-duel", "version": 1, "state": saved}) \
		and Vector2i(restored.entity(id).power, restored.entity(id).toughness) == printed \
		and not restored.has_flag(id, "Disenchant"), "#232: loading old saves recalculates suspended effects")
	saved_creature.damage = printed.y
	_check(restored.restore(profile, {"format": "etherlords-duel", "version": 1, "state": saved}) \
		and not restored.creatures.has(id), "#232: lethal wounds in an older save are settled on load")
	_check(duel.use_ability(id, "fiendish") and Vector2i(creature.power, creature.toughness) == modified \
		and duel.has_flag(id, "Disenchant") and creature.enchantments == attached, "#232: the same effects return on manifestation")
	creature.damage = printed.y
	_check(duel.plane_change(id, true) and not duel.creatures.has(id), "#232: retained damage becomes lethal when the extra toughness is suspended")
	var reentry := duel.next_id
	duel._summon(0, "OUD1")
	if not _check(duel.plane_change(reentry, false) and _cast(duel, "ALST", reentry) \
		and duel.plane_change(reentry, true) and _cast(duel, "PRWR", 0), "#232: prepare a wounded Pale with Alpha Strike and Aspect Ward"): return
	duel.entity(reentry).damage = 1
	var health: int = duel.heroes[0].health
	var mana: int = duel.heroes[0].mana
	_check(duel.plane_change(reentry, false) and duel.in_plane(reentry) and duel.entity(reentry).damage == 0 \
		and duel.heroes[0].health == health - 2 and duel.heroes[0].mana == mana - 2, \
		"#232: lethal manifestation dissipates once, recovers and pays the ward in both directions")

func _transfer_aspects(profile: ELProfile) -> void:
	if not ELCombatBrain.available: return
	var duel := ELDuel.new()
	if not _check(duel.start(profile, 11), "#232: duel starts for Transfer Aspects"): return
	duel.heroes[0].mana = 20
	var regular := duel.next_id
	duel._summon(0, "ORSH")
	var printed: int = duel.entity(regular).power
	var pale := duel.next_id
	duel._summon(0, "OUD1")
	if not _check(_cast(duel, "MGHT", regular), "#232: a regular creature receives a coloured enchantment"): return
	duel._give_card(0, "OEXC")
	var ctx := Fixtures.context(profile, 0)
	_check(ELCombatBrain.choose(ctx, duel, 1, 100, 1).is_empty(), "#232: a castable Transfer Aspects triggers fallback")
	if not _check(duel.cast(duel.heroes[0].hand.size() - 1), "#232: Transfer Aspects is cast"): return
	_check(ELCombatBrain.choose(ctx, duel, 1, 100, 1).is_empty(), "#232: an available aspect exchange triggers fallback")
	var ability: Dictionary = duel.abilities(0).back()
	_check(duel.use_ability(0, ability.key, pale, regular) and duel.in_plane(regular) and duel.entity(regular).power == printed,
		"#232: aspect exchange suspends effects on a regular creature too")

func _reflected_trade(profile: ELProfile) -> void:
	var rod := ""
	for key: String in profile.table("Artefacts"):
		if profile.table("Artefacts")[key].get("SpellType") == "LNRD":
			rod = key
			break
	if not _check(not rod.is_empty(), "#217: Rod of Reflection exists"): return
	for health: int in [5, 3]:
		var duel := ELDuel.new()
		var players := [{"faction": "Green", "cards": ["CHNL"], "health": 20, "skills": {},
			"artifacts": [{"name": rod, "charges": 1, "ready_round": 0}]},
			{"faction": "Black", "cards": [], "health": health, "skills": {}}]
		if not _check(duel.start(profile, 12, {"players": players, "adventure": true}) \
			and duel.use_artifact(0, 0), "#217: the caster activates the Rod"): continue
		duel.heroes[0].mana = 10
		duel._give_card(0, "CHNL")
		var index: int = duel.heroes[0].hand.size() - 1
		var prediction := ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 4, [[3, index, -99, 3]])
		duel.history.clear()
		if not _check(duel.cast(index, -1, -1, 3), "#217: Ether Trade resolves with X = 3"): continue
		var events: Array = duel.history.filter(func(event: Dictionary) -> bool: return event.get("target") == 1 and event.kind in ["damage", "heal"])
		var outcomes := events.map(func(event: Dictionary) -> String: return event.kind)
		if health == 5:
			_check(outcomes == ["damage", "heal"] and duel.heroes[1].health == 5, "#217: nonlethal reflected damage lands before healing")
		else:
			_check(outcomes == ["damage"] and duel.winner == 0 and duel.heroes[1].health == 0, "#217: lethal reflected damage ends the duel before healing")
		if ELCombatBrain.available:
			_check(prediction.get("played", 0) == 1 and prediction.health == [int(duel.heroes[0].health), int(duel.heroes[1].health)] \
				and prediction.ether == [int(duel.heroes[0].mana), int(duel.heroes[1].mana)], "#217: native lookahead agrees with reported damage and ether")
