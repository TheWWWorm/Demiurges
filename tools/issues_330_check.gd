extends SceneTree
## Regression check for issue #330, Quick Fix (QKFX) on a mechozaurus, an
## unaffected creature, as the original games play it:
##
## - In both games the raised mechozaurus keeps its printed power and
##   toughness (an ordinary creature loses a point of each).
## - First game: a disenchanting strike or a mass dispel (Greater Disenchant,
##   Cleansing) takes the quick fix off, and the mechozaurus lives on, as the
##   destruction that follows is damage, which it ignores.
## - Second game (update 1.03): taking the quick fix off kills what it raised
##   outright, so the mechozaurus dies, by a disenchanting strike as by a mass
##   dispel. The first game on the second game's card balance plays it the
##   second game's way; puzzles keep the first game's rules.
##
##   godot --headless --path game --script ../tools/issues_330_check.gd
##
## Needs the games' files (user://profiles.json); a game without them is
## skipped. Settings are never written.

const MECHO := "STMZ"
const PLAIN := "TIWR"

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary: paths = {}
	var profiles := {}
	for id: String in ["el1", "el2"]:
		if not paths.has(id):
			print("SKIP: no %s files configured (user://profiles.json)" % id)
			continue
		var profile := ELProfile.new()
		if profile.mount(id, str(paths[id])): profiles[id] = profile
		else: print("SKIP: %s files could not be mounted" % id)
	if profiles.has("el1"): _game(profiles.el1, "el1", false)
	if profiles.has("el2"): _game(profiles.el2, "el2", true)
	if profiles.has("el1") and profiles.has("el2"):
		if ELSecondBalance.apply(profiles.el1, profiles.el2, true):
			_game(profiles.el1, "el1 on the second game's balance", true)
			ELSecondBalance.apply(profiles.el1, null, false)
		else:
			check(false, "the second game's balance applies to the first game")
	print("ISSUE 330: %d failure(s)" % failures)
	quit(int(failures > 0))

## A fresh duel with no creatures, side 0 to act in its attack phase, both
## heroes at 20 health and 30 ether, without skills or specialisations.
func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	duel.start(profile, 5, {})
	for id: int in duel.creatures.keys(): duel.creatures.erase(id)
	_turn(duel, 0)
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		hero.health = 20
		hero.maximum = maxi(int(hero.get("maximum", 20)), 20)
		hero.mana = 30
		hero.channels = 5
		hero.hand = []
		hero.hand_slots = []
		hero.hand_view = []
		hero.enchantments = []
		hero.grave = []
		hero.spec = "NONE"
		hero.skills = {}
	return duel

## Ends phases until `side` acts in its attack phase.
func _turn(duel: ELDuel, side: int) -> void:
	for i in 8:
		if duel.active_side() == side and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
	for hero: Dictionary in duel.heroes:
		hero.mana = 30
		hero.health = 20

func _summoned(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key):
			duel.creatures[key].sick = false
			duel.creatures[key].resting = false
			return key
	return -1

## `side` casts `card` from its hand in its own turn.
func _cast(duel: ELDuel, side: int, card: String, target := -1, choice := -1) -> bool:
	_turn(duel, side)
	duel._give_card(side, card)
	return duel.cast(duel.heroes[side].hand.find(card), target, choice)

func _with_fix(e: Dictionary) -> bool:
	return e.card == "QKFX"

## Side 0 raises `card` from its graveyard with Quick Fix; returns its id (or -1).
func _raised(duel: ELDuel, card: String) -> int:
	duel.heroes[0].grave = [card]
	var known := duel.creatures.keys()
	if not _cast(duel, 0, "QKFX", 0, 0):
		check(false, "side 0 casts Quick Fix on %s (%s)" % [card, duel.error])
		return -1
	for key: int in duel.creatures:
		if not known.has(key) and duel.creatures[key].card == card: return key
	return -1

func _game(profile: ELProfile, label: String, second: bool) -> void:
	_stats(profile, label)
	_strike(profile, label, second)
	for spell: String in ["DECN", "CLSN"]: _mass_dispel(profile, label, second, spell)

func _stats(profile: ELProfile, label: String) -> void:
	for card: String in [MECHO, PLAIN]:
		var duel := _duel(profile)
		_summoned(duel, 1, PLAIN)
		var id := _raised(duel, card)
		var printed: Dictionary = profile.table("CombatCreatures")[card]
		var loss := 0 if card == MECHO else 1
		check(id >= 0 and int(duel.creatures[id].power) == int(printed.Power) - loss and int(duel.creatures[id].toughness) == maxi(1, int(printed.Toughness) - loss)
			and duel.creatures[id].enchantments.any(_with_fix),
			"%s: Quick Fix raises %s at %s (printed %d/%d)" % [label, card,
				("%d/%d" % [duel.creatures[id].power, duel.creatures[id].toughness]) if id >= 0 else "nothing", int(printed.Power), int(printed.Toughness)])

## What became of the raised mechozaurus once its quick fix came off.
func _fate(duel: ELDuel, id: int, label: String, how: String, second: bool) -> void:
	if second:
		check(not duel.creatures.has(id) and duel.heroes[0].grave.has(MECHO) and not duel.heroes[0].hand.has("QKFX"),
			"%s: %s kills the raised mechozaurus (grave %s, hand %s)" % [label, how, str(duel.heroes[0].grave), str(duel.heroes[0].hand)])
	else:
		check(duel.creatures.has(id) and not duel.creatures[id].enchantments.any(_with_fix) and not duel.heroes[0].grave.has(MECHO),
			"%s: %s takes the quick fix off and the mechozaurus lives (grave %s)" % [label, how, str(duel.heroes[0].grave)])

func _strike(profile: ELProfile, label: String, second: bool) -> void:
	var duel := _duel(profile)
	var striker := _summoned(duel, 1, PLAIN)
	var id := _raised(duel, MECHO)
	if id < 0: return
	check(_cast(duel, 1, "SGHT", striker) and duel.has_flag(striker, "Disenchant"), "%s: side 1's creature breaks enchantments (%s)" % [label, duel.error])
	duel.creatures[striker].resting = false
	duel.creatures[striker].sick = false
	duel.creatures[id].resting = false
	check(duel.toggle_attack(striker) and duel.end_phase(), "%s: it attacks (%s)" % [label, duel.error])
	check(duel.assign_block(id, striker) and duel.end_phase(), "%s: the raised mechozaurus blocks it (%s)" % [label, duel.error])
	_fate(duel, id, label, "the disenchanting strike", second)

func _mass_dispel(profile: ELProfile, label: String, second: bool, spell: String) -> void:
	var duel := _duel(profile)
	_summoned(duel, 1, PLAIN)
	var id := _raised(duel, MECHO)
	if id < 0: return
	if not _cast(duel, 1, spell):
		check(false, "%s: side 1 casts %s (%s)" % [label, spell, duel.error])
		return
	_fate(duel, id, label, spell, second)
