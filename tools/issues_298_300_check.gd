extends SceneTree
## Regression check for #298 and #300 (both measured on the original games'
## combat code).
##
## #298, second game: Colourless Revival destroys a creature in the Colourless
## Plane, but a creature's own printed regeneration still saves it (its owner
## pays as usual, and the revival still brings back its graveyard card). The
## regeneration that coloured enchantments (Self-restoration) or army auras
## (Vitality) lend is dormant in the plane, so such a creature dies.
##
## #300, both games: a pteros (plain or reinforced) pays the removed
## enchantment's cost only after taking it off, and Flicker pays that part of
## its price after the removal too (its own cost before, as any spell). So
## removing the only Prickly Ether costs no health, removing one of two pricks
## once, and Flicker on the only one pricks only its own cost.
##
##   godot --headless --path game --script ../tools/issues_298_300_check.gd
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
	for edition: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(edition):
			print("SKIP: no %s files configured (user://profiles.json)" % edition)
			continue
		var profile := ELProfile.new()
		if not profile.mount(edition, str(paths[edition])):
			print("SKIP: %s files could not be mounted" % edition)
			continue
		if edition == "el2": _revival(profile)
		_thorns(profile)
	print("ISSUES 298/300: %d failure(s)" % failures)
	quit(int(failures > 0))

## A fresh duel with no creatures, side 0 to act in its attack phase, both
## heroes at 20 health and 10 ether, without skills or specialisations.
func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	duel.start(profile, 5, {})
	for id: int in duel.creatures.keys(): duel.creatures.erase(id)
	if duel.active_side() != 0: duel.end_phase()
	for i in 4:
		if duel.active_side() == 0 and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		hero.health = 20
		hero.maximum = maxi(int(hero.get("maximum", 20)), 20)
		hero.mana = 10
		hero.hand = []
		hero.hand_slots = []
		hero.hand_view = []
		hero.enchantments = []
		hero.grave = []
		hero.spec = "NONE"
		hero.skills = {}
	return duel

func _summoned(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key):
			duel.creatures[key].sick = false
			duel.creatures[key].resting = false
			return key
	return -1

func _enchantments(duel: ELDuel, holder: int, card: String) -> Array[int]:
	var out: Array[int] = []
	for e: Dictionary in duel.entity(holder).get("enchantments", []):
		if e.card == card: out.append(int(e.id))
	return out

# --- #298 --------------------------------------------------------------------------

## Colourless Revival on side 1's creature in the plane, bringing back the
## Giant Bat side 1's graveyard holds.
func _revival_case(profile: ELProfile, label: String, card: String, worn: String, aura: String, survives: bool, cost: int) -> void:
	var duel := _duel(profile)
	var victim := _summoned(duel, 1, card)
	if worn != "": check(duel.cast_free(1, worn, [victim], false), "el2 %s: %s laid" % [label, worn])
	if aura != "": check(duel.cast_free(1, aura, [], false), "el2 %s: %s laid" % [label, aura])
	check(duel.plane_change(victim, true) and duel.in_plane(victim), "el2 %s: the creature is in the Colourless Plane" % label)
	duel.heroes[1].grave = ["GBAT"]
	duel.heroes[1].mana = 5
	duel._give_card(0, "ORFT")
	var before := duel.army(0).size()
	var ok := duel.cast(duel.heroes[0].hand.find("ORFT"), victim, ELDuel.GRAVE_SIDE)
	check(ok, "el2 %s: Colourless Revival is cast (%s)" % [label, duel.error])
	check(duel.creatures.has(victim) == survives, "el2 %s: the creature %s" % [label, "regenerates" if survives else "is destroyed"])
	check(int(duel.heroes[1].mana) == 5 - cost, "el2 %s: its hero pays %d ether (%d left)" % [label, cost, int(duel.heroes[1].mana)])
	if survives:
		check(duel.army(0).size() == before and duel.heroes[1].grave == ["GBAT"], "el2 %s: the bat stays in the grave when the target survives" % label)
	else:
		check(duel.army(0).size() == before + 1 and duel.heroes[1].grave == [card], "el2 %s: the caster revives the bat when the target dies" % label)

func _revival(profile: ELProfile) -> void:
	var own := int(ELCatalog.flags(profile.table("CombatCreatures").get("TANT", {})).filter(func(f: String) -> bool: return f.begins_with("Regen(")).map(func(f: String) -> int: return int(f.trim_prefix("Regen(").trim_suffix(")"))).front())
	_revival_case(profile, "treant's own regeneration", "TANT", "", "", true, own)
	_revival_case(profile, "iron abomination's own regeneration", "IRAB", "", "", true, 1)
	_revival_case(profile, "Self-restoration on a wall", "TIWR", "SLRP", "", false, 0)
	_revival_case(profile, "Vitality over a wall", "TIWR", "", "VTLY", false, 0)
	_revival_case(profile, "treant with Self-restoration", "TANT", "SLRP", "", true, own)
	_revival_case(profile, "plain wall", "TIWR", "", "", false, 0)
	# Its hero without the ether to pay: the creature dies.
	var duel := _duel(profile)
	var victim := _summoned(duel, 1, "TANT")
	duel.plane_change(victim, true)
	duel.heroes[1].grave = ["GBAT"]
	duel.heroes[1].mana = 0
	duel._give_card(0, "ORFT")
	check(duel.cast(duel.heroes[0].hand.find("ORFT"), victim, ELDuel.GRAVE_SIDE) and not duel.creatures.has(victim), "el2 treant whose hero has no ether: destroyed")

# --- #300 --------------------------------------------------------------------------

## `thorns`: the sides that cast a Prickly Ether, in order; the remover takes
## the last one off. Returns [health, ether] of side 0 afterwards.
func _remove_thorns(profile: ELProfile, remover: String, thorns: Array) -> Array:
	var duel := _duel(profile)
	for side: int in thorns: duel.cast_free(side, "MNTH", [], false)
	var holder := int(thorns.back())
	var target: int = _enchantments(duel, holder, "MNTH").back()
	var ok := false
	if remover == "FLIC":
		duel._give_card(0, "FLIC")
		ok = duel.cast(duel.heroes[0].hand.find("FLIC"), holder, target)
	else:
		var pteros := _summoned(duel, 0, remover)
		var key := "disenchant" if remover == "RFPT" else "dispel"
		ok = duel.use_ability(pteros, key, holder, target)
	check(ok, "%s %s: takes off a Prickly Ether (%s)" % [profile.id, remover, duel.error])
	check(duel.global_enchantment_count("MNTH") == thorns.size() - 1, "%s %s: one Prickly Ether is gone" % [profile.id, remover])
	return [int(duel.heroes[0].health), int(duel.heroes[0].mana)]

func _thorns(profile: ELProfile) -> void:
	var game := profile.id
	var price := int(profile.table("CombatSpells").MNTH.Cost)
	var flicker := int(profile.table("CombatSpells").FLIC.Cost)
	for remover: String in ["PTRS", "RFPT"]:
		for holder: int in [0, 1]:
			var after := _remove_thorns(profile, remover, [holder])
			check(after == [20, 10 - price], "%s %s: the only Prickly Ether (on hero %d) costs %d ether and no health (%s)" % [game, remover, holder, price, str(after)])
		var after := _remove_thorns(profile, remover, [0, 1])
		check(after == [20 - price, 10 - price], "%s %s: one of two Prickly Ethers pricks once for %d (%s)" % [game, remover, price, str(after)])
		after = _remove_thorns(profile, remover, [1, 1])
		check(after == [20 - price, 10 - price], "%s %s: one of two on the same hero pricks once (%s)" % [game, remover, str(after)])
	var after := _remove_thorns(profile, "FLIC", [1])
	check(after == [20 - flicker, 10 - flicker - price], "%s Flicker: the only Prickly Ether pricks only Flicker's own cost (%s)" % [game, str(after)])
	after = _remove_thorns(profile, "FLIC", [0, 1])
	check(after == [20 - 2 * flicker - price, 10 - flicker - price], "%s Flicker: with two, its cost pricks twice and the removed one's once (%s)" % [game, str(after)])
	# Removing another enchantment still pays under the thorns in play.
	var duel := _duel(profile)
	duel.cast_free(1, "MNTH", [], false)
	var wall := _summoned(duel, 1, "TIWR")
	duel.cast_free(1, "SLRP", [wall], false)
	var pteros := _summoned(duel, 0, "RFPT")
	var restoration := int(profile.table("CombatSpells").SLRP.Cost)
	check(duel.use_ability(pteros, "disenchant", wall, _enchantments(duel, wall, "SLRP").front()) and int(duel.heroes[0].health) == 20 - restoration and int(duel.heroes[0].mana) == 10 - restoration,
		"%s RFPT: removing Self-restoration under a Prickly Ether pricks for its %d" % [game, restoration])
