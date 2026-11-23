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
	_aspect_ward_exchange(profile)
	_orc_rite_once(profile)
	_pale_revival_lifeguard(profile)
	_reflected_trade(profile)
	_subjugated_pale(profile)
	_ash_storm_dispels(profile)
	_lake_snake_lifeguard(profile)
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

## #307, as the original Transfer Aspects: the use
## is refused whole unless the user can also pay its own Aspect Ward for its
## creature that moves; a pair of enemy creatures needs no ward ether.
func _aspect_ward_exchange(profile: ELProfile) -> void:
	for mana: int in [0, 1, 2]:
		var duel := ELDuel.new()
		if not _check(duel.start(profile, 11), "#307: duel starts"): return
		duel.heroes[0].mana = 20
		var own_pale := duel.next_id
		duel._summon(0, "OUD1")
		var own := duel.next_id
		duel._summon(0, "ORSH")
		var enemy_pale := duel.next_id
		duel._summon(1, "OUD1")
		var enemy := duel.next_id
		duel._summon(1, "ORSH")
		if not _check(_cast(duel, "PRWR", 0) and duel._enchantment_count(0, "PRWR") == 1, "#307: Aspect Ward on the user"): return
		if not _check(_cast(duel, "OEXC"), "#307: Transfer Aspects is cast"): return
		var ability: Dictionary = duel.abilities(0).back()
		duel.heroes[0].mana = mana
		var health := int(duel.heroes[0].health)
		# #309: the first choice only in the Colourless Plane, the second only in the Ether.
		if mana == 2:
			var pending := {"ability": ability, "source": 0, "first": -1}
			_check(ELCursors._valid_target(duel, own_pale, pending) and not ELCursors._valid_target(duel, own, pending), "#309: first choice in the Colourless Plane only")
			pending.first = own_pale
			_check(ELCursors._valid_target(duel, enemy, pending) and not ELCursors._valid_target(duel, enemy_pale, pending), "#309: second choice in the Ether only")
		match mana:
			0: _check(not duel.can_use_ability(0, ability.key), "#307: no ether, Transfer Aspects is inactive")
			1:
				_check(duel.can_use_ability(0, ability.key), "#307: 1 ether still pays an exchange of enemy creatures")
				_check(not duel.use_ability(0, ability.key, own_pale, enemy) and duel.in_plane(own_pale) and not duel.in_plane(enemy) \
					and duel.heroes[0].mana == 1, "#307: an own creature's unaffordable ward refuses the whole exchange")
				_check(duel.use_ability(0, ability.key, enemy_pale, enemy) and not duel.in_plane(enemy_pale) and duel.in_plane(enemy) \
					and duel.heroes[0].mana == 0, "#307: enemy creatures exchange for the cost alone")
			2:
				_check(not duel.use_ability(0, ability.key, own_pale, own), "#307: two own creatures need 3 ether")
				_check(duel.use_ability(0, ability.key, own_pale, enemy) and not duel.in_plane(own_pale) and duel.in_plane(enemy) \
					and duel.heroes[0].mana == 0 and duel.heroes[0].health == health - 1, "#307: the ward costs 1 ether and 1 life")

## #308, as update 1.03: the Orc Shaman's rite marks itself used, so a
## shaman readied again in the same turn cannot dispel a second time.
func _orc_rite_once(profile: ELProfile) -> void:
	var duel := ELDuel.new()
	if not _check(duel.start(profile, 11), "#308: duel starts"): return
	duel.heroes[0].mana = 20
	duel.heroes[0].channels = 5
	var shaman := duel.next_id
	duel._summon(0, "ORSH")
	var other := duel.next_id
	duel._summon(0, "ORSH")
	duel.creatures[shaman].sick = false
	if not _check(_cast(duel, "MGHT", other) and _cast(duel, "MGHT", other), "#308: two enchantments to remove"): return
	var key := "orc_rite"
	if not _check(duel.can_use_ability(shaman, key), "#308: the rite is offered"): return
	var first_enchantment: int = int(duel.creatures[other].enchantments[0].id)
	_check(duel.use_ability(shaman, key, other, first_enchantment) and duel.creatures[other].enchantments.size() == 1, "#308: the rite removes one enchantment")
	duel.creatures[shaman].resting = false
	_check(not duel.can_use_ability(shaman, key), "#308: a readied shaman's rite stays used this turn")
	_check(not duel.use_ability(shaman, key, other, int(duel.creatures[other].enchantments[0].id)), "#308: a second rite is refused")

## #306, as update 1.03: Pale Revival brings a creature back only
## when its target dies; a Lifeguard saves the target and nothing returns.
func _pale_revival_lifeguard(profile: ELProfile) -> void:
	for guarded: bool in [false, true]:
		var label := "#306 (%s)" % ("Lifeguard" if guarded else "unguarded")
		var duel := ELDuel.new()
		if not _check(duel.start(profile, 11), label + ": duel starts"): return
		duel.heroes[0].mana = 30
		var pale := duel.next_id
		duel._summon(1, "OUD1")
		if guarded:
			duel.plane_change(pale, false)
			if not _check(_cast(duel, "LFGR", pale) and duel._enchantment_count(pale, "LFGR") == 1, label + ": Lifeguard on the manifested creature"): return
			duel.plane_change(pale, true)
		duel.heroes[1].grave.append("TIWR")
		var grave_index: int = 1 * ELDuel.GRAVE_SIDE + duel.heroes[1].grave.size() - 1
		var army_before := duel.army(0).size()
		duel._give_card(0, "ORFT")
		if not _check(duel.in_plane(pale) and duel.cast(duel.heroes[0].hand.size() - 1, pale, grave_index), label + ": Pale Revival is cast"): return
		if guarded:
			_check(duel.creatures.has(pale) and duel._enchantment_count(pale, "LFGR") == 0 and duel.army(0).size() == army_before \
				and duel.heroes[1].grave.has("TIWR"), label + ": the target survives and nothing returns")
		else:
			_check(not duel.creatures.has(pale) and duel.army(0).size() == army_before + 1 and not duel.heroes[1].grave.has("TIWR"),
				label + ": the target dies and the creature returns")

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

## A charmed Pale creature that dissipates for any reason goes back to its original owner, the
## charm still attached but inert in the plane (#267; the original keeps a blocked attacker with
## the charmer, which the port deliberately does not reproduce).
func _subjugated_pale(profile: ELProfile) -> void:
	for scenario: String in ["zap by the charmer", "zap by the owner", "zap while attacking", "dies blocking", "dies attacking"]:
		var label := "#267 (%s): " % scenario
		var duel := ELDuel.new()
		if not _check(duel.start(profile, 11), label + "duel starts"): continue
		if not _attack_phase(duel, 0, label): continue
		duel.heroes[0].mana = 80
		duel.heroes[1].mana = 80
		var id := duel.next_id
		duel._summon(1, "OUD1")
		if not _check(duel.plane_change(id, false) and _cast(duel, "CHCM", id) and duel.entity(id).owner == 0, label + "side 0 charms side 1's manifested Pale creature"): continue
		var stolen: Dictionary = duel.entity(id)
		stolen.sick = false
		stolen.resting = false
		var foe := duel.next_id
		duel._summon(1, "ORSH")
		duel.entity(foe).sick = false
		duel.entity(foe).resting = false
		# Blocked fights are sequential: a blocker the attacker kills never strikes back, so the
		# foe must outlast the Pale creature's blow.
		duel.entity(foe).base = [2, 20]
		duel._refresh_stats(duel.entity(foe))
		stolen.damage = int(stolen.toughness) - 1
		var prediction := {}
		match scenario:
			"zap by the charmer":
				_check(_cast(duel, "ZAPP", id), label + "Zap is cast")
			"zap by the owner":
				_check(duel.cast_free(1, "ZAPP", [id], false), label + "Zap is cast")
			"zap while attacking":
				if not _check(duel.toggle_attack(id) and duel.end_phase() and duel.phase == ELDuel.Phase.DEFENCE, label + "the stolen creature attacks"): continue
				_check(duel.cast_free(1, "ZAPP", [id], false), label + "Zap is cast in defence")
			"dies blocking":
				if not _attack_phase(duel, 1, label): continue
				stolen.damage = int(stolen.toughness) - 1
				if not _check(duel.toggle_attack(foe) and duel.end_phase() and duel.assign_block(id, foe), label + "the stolen creature blocks"): continue
				prediction = ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 2)
				duel.end_phase()
			"dies attacking":
				if not _check(duel.toggle_attack(id) and duel.end_phase() and duel.assign_block(foe, id), label + "the stolen creature attacks and is blocked"): continue
				prediction = ELCombatBrain.fight(Fixtures.context(profile, 0), duel, 2)
				duel.end_phase()
		if not _check(duel.creatures.has(id) and duel.in_plane(id), label + "it dissipates"): continue
		var charmed: bool = stolen.enchantments.any(func(e: Dictionary) -> bool: return e.card == "CHCM")
		_check(int(stolen.owner) == 1 and charmed, label + "it returns to its owner, the charm still attached")
		_check(stolen.enchantments.size() == 1 and Vector2i(stolen.power, stolen.toughness) == duel.creature_stats(stolen), label + "the charm is inert in the plane")
		if ELCombatBrain.available and not prediction.is_empty():
			var armies := [duel.army(0).size(), duel.army(1).size()]
			_check(prediction.get("counts", {}).get("armies", []) == armies, label + "the native rules send it home too %s vs %s" % [prediction.get("counts", {}).get("armies"), armies])

## Ends phases until `side` attacks.
func _attack_phase(duel: ELDuel, side: int, label: String) -> bool:
	for i in 8:
		if duel.attacker == side and duel.phase == ELDuel.Phase.ATTACK: return true
		duel.end_phase()
	return _check(false, label + "side %d's attack phase comes" % side)

## The cast Ash Storm is an ordinary hero enchantment in the second game: the
## single-target dispels and both cleanses remove it (the original, #268). The
## Scroll of Ash Storm's storm (PCDU) keeps no card and none of them removes it.
func _ash_storm_dispels(profile: ELProfile) -> void:
	for dispel: String in ["PRFY", "FLIC", "CLNP", "CLSN", "DECN"]:
		var label := "#268 (%s): " % dispel
		var duel := ELDuel.new()
		if not _check(duel.start(profile, 11), label + "duel starts"): continue
		if not _attack_phase(duel, 0, label): continue
		duel.heroes[0].mana = 80
		if not _check(_cast(duel, "ASST") and duel.global_enchantment_count("ASST") == 1, label + "Ash Storm is cast"): continue
		var storm: Dictionary = duel.heroes[0].enchantments.filter(func(e: Dictionary) -> bool: return e.card == "ASST")[0]
		_check(duel.dispellable(0, storm), label + "Ash Storm can be removed")
		duel._give_card(0, dispel)
		var aimed: bool = ELCatalog.rule(profile, dispel).get("target") == "enchantment"
		_check(duel.cast(duel.heroes[0].hand.size() - 1, 0 if aimed else -1, int(storm.id) if aimed else -1) \
			and duel.global_enchantment_count("ASST") == 0, label + "it removes Ash Storm")
	var scroll := ""
	for key: String in profile.table("Artefacts"):
		if profile.table("Artefacts")[key].get("SpellType") == "PCDU":
			scroll = key
			break
	if not _check(not scroll.is_empty(), "#268: the Scroll of Ash Storm exists"): return
	var duel := ELDuel.new()
	var players := [{"faction": "Green", "cards": ["CHNL"], "health": 20, "skills": {},
		"artifacts": [{"name": scroll, "charges": 1, "ready_round": 0}]},
		{"faction": "Black", "cards": [], "health": 20, "skills": {}}]
	if not _check(duel.start(profile, 12, {"players": players, "adventure": true}) and _attack_phase(duel, 0, "#268 (scroll): ") \
		and duel.use_artifact(0, 0) and duel.global_enchantment_count("PCDU") == 1, "#268: the Scroll raises its storm"): return
	duel.heroes[0].mana = 80
	_check(_cast(duel, "CLSN") and duel.global_enchantment_count("PCDU") == 1, "#268: Cleanse leaves the Scroll's storm")

## A Lake Snake's blow that a lifeguard turns away leaves no venom: the guarded
## creature keeps its power and health (the original, #269).
func _lake_snake_lifeguard(profile: ELProfile) -> void:
	var duel := ELDuel.new()
	if not _check(duel.start(profile, 11), "#269: duel starts"): return
	if not _attack_phase(duel, 0, "#269: "): return
	duel.heroes[1].mana = 80
	var snake := duel.next_id
	duel._summon(0, "LASN")
	var bat := duel.next_id
	duel._summon(1, "GBAT")
	duel.entity(snake).sick = false
	duel.entity(snake).resting = false
	duel.entity(bat).resting = false
	duel.entity(bat).sick = false
	var printed := Vector2i(duel.entity(bat).power, duel.entity(bat).toughness)
	if not _check(duel.cast_free(1, "LFGR", [bat], false) and duel._enchantment_count(bat, "LFGR") == 1, "#269: Lifeguard guards the blocker"): return
	if not _check(duel.toggle_attack(snake) and duel.end_phase() and duel.assign_block(bat, snake), "#269: the snake attacks and is blocked " + duel.error): return
	duel.end_phase()
	var blocker: Dictionary = duel.entity(bat)
	_check(not blocker.is_empty() and blocker.damage == 0 and Vector2i(blocker.power, blocker.toughness) == printed \
		and not blocker.enchantments.any(func(e: Dictionary) -> bool: return e.card in ["LASN", "LFGR"]), "#269: the guarded blocker keeps its stats and takes no venom")
	_check(not duel.creatures.has(snake), "#269: the blocker's return blow kills the snake")
