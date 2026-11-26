extends SceneTree
## Regression check for the second game's Pale issues #313, #314, #316 and
## #317, as the original game plays them:
##
## - #313: a manifested Pale creature with Redirection that a redirected hit
##   on its hero kills dies (to the graveyard); it does not dissipate. A
##   direct lethal hit still makes it dissipate.
## - #314: a Pale spell-jammer (Avenger, Punisher, Redeemer) enters play as an
##   enchantment. Brought back from a graveyard (Repair/QKFX, Grave Pact,
##   Bloody Exchange, Water Link) its trap goes to the reviving hero instead
##   of the creature; sent back to the hand (Repair, Unsummon) it comes back
##   as its trap card.
## - #316: a strike that breaks enchantments leaves the spell-jammer traps on
##   the hero (other hero enchantments go).
## - #317: the Redeemer's stats are all the ether paid for the enemy spell
##   (cost plus surcharges: Cleanse, Annihilation, Flicker; plus X); the
##   Punisher's stay the spell's printed cost.
##
##   godot --headless --path game --script ../tools/issues_313_317_check.gd
##
## Needs the second game's files (user://profiles.json); without them the
## check is skipped. Settings are never written.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no el2 files configured (user://profiles.json)")
	else:
		var profile := ELProfile.new()
		if not profile.mount("el2", str(paths["el2"])):
			print("SKIP: el2 files could not be mounted")
		else:
			_redirect(profile)
			_revival(profile)
			_hand_returns(profile)
			_disenchant(profile)
			_redeemer(profile)
	print("ISSUES 313-317: %d failure(s)" % failures)
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
func _cast(duel: ELDuel, side: int, card: String, target := -1, choice := -1, power := 0) -> bool:
	_turn(duel, side)
	duel._give_card(side, card)
	return duel.cast(duel.heroes[side].hand.find(card), target, choice, power)

func _hero_cards(duel: ELDuel, side: int) -> Array:
	return duel.heroes[side].enchantments.map(func(e: Dictionary) -> String: return String(e.card))

func _cards(duel: ELDuel, side: int) -> Array:
	return duel.army(side).map(func(c: Dictionary) -> String: return String(c.card))

func _redirect(profile: ELProfile) -> void:
	for lethal: bool in [true, false]:
		var duel := _duel(profile)
		_summoned(duel, 0, "TIWR")
		var pale := _summoned(duel, 1, "OUD1")
		_turn(duel, 1)
		check(duel.use_ability(pale, "fiendish") and not duel.in_plane(pale), "#313: side 1 manifests its devourer (%s)" % duel.error)
		check(_cast(duel, 1, "REDR", pale), "#313: side 1 puts Redirection on it (%s)" % duel.error)
		_turn(duel, 0)
		var c: Dictionary = duel.creatures[pale]
		c.damage = int(c.toughness) - 1 if lethal else 0
		check(_cast(duel, 0, "ZAPP", 1), "#313: side 0 zaps hero 1 (%s)" % duel.error)
		if lethal:
			check(not duel.creatures.has(pale) and duel.heroes[1].grave.has("OUD1") and int(duel.heroes[1].health) == 20,
				"#313: the redirected lethal hit kills the Pale creature (grave %s)" % str(duel.heroes[1].grave))
		else:
			check(duel.creatures.has(pale) and int(duel.creatures[pale].damage) == 1 and not duel.in_plane(pale),
				"#313: a smaller redirected hit only damages it")
	# A direct lethal hit still makes it dissipate.
	var duel := _duel(profile)
	var pale := _summoned(duel, 1, "OUD1")
	_turn(duel, 1)
	duel.use_ability(pale, "fiendish")
	_turn(duel, 0)
	duel.creatures[pale].damage = int(duel.creatures[pale].toughness) - 1
	check(_cast(duel, 0, "ZAPP", pale) and duel.creatures.has(pale) and duel.in_plane(pale), "#313: a direct lethal hit still makes it dissipate")

## Side 0's graveyard holds `jammer`; side 0 has a wall.
func _with_dead_jammer(profile: ELProfile, jammer: String) -> ELDuel:
	var duel := _duel(profile)
	_summoned(duel, 0, "TIWR")
	_summoned(duel, 1, "TIWR")
	duel.heroes[0].grave = [jammer]
	return duel

func _revival(profile: ELProfile) -> void:
	for jammer: String in ["OSJ1", "OSJ2", "OSJ3"]:
		var trap := "OST" + jammer.substr(3)
		for spell: String in ["QKFX", "GRPL"]:
			var duel := _with_dead_jammer(profile, jammer)
			var ok := _cast(duel, 0, spell, 0, 0)
			check(ok and duel.heroes[0].grave.is_empty() and not _cards(duel, 0).has(jammer) and _hero_cards(duel, 0).count(trap) == 1
				and not duel.creatures.values().any(func(c: Dictionary) -> bool: return c.enchantments.any(func(e: Dictionary) -> bool: return e.card == spell)),
				"#314: %s brings %s back as its trap %s on the caster's hero (%s; army %s, hero %s)" % [spell, jammer, trap, duel.error, str(_cards(duel, 0)), str(_hero_cards(duel, 0))])
		var duel := _with_dead_jammer(profile, jammer)
		var wall: int = duel.army(0)[0].id
		check(_cast(duel, 0, "BDEX", wall, 0) and not _cards(duel, 0).has(jammer) and _hero_cards(duel, 0).has(trap) and duel.heroes[0].grave == ["TIWR"],
			"#314: Bloody Exchange swaps the wall for the %s trap (%s; hero %s, grave %s)" % [trap, duel.error, str(_hero_cards(duel, 0)), str(duel.heroes[0].grave)])
	# Water Link: the Avenger arrives manifested; linked by side 0, cleaved by side 1.
	var duel := _duel(profile)
	_summoned(duel, 0, "TIWR")
	var avenger := _summoned(duel, 0, "OSJ1")
	check(not duel.in_plane(avenger), "#314: the Avenger stands in the ethereal aspect")
	check(_cast(duel, 0, "WTLK", avenger), "#314: side 0 links it with Water Link (%s)" % duel.error)
	check(_cast(duel, 1, "OCLV", avenger) and not duel.creatures.has(avenger), "#314: side 1 cleaves it (%s)" % duel.error)
	check(duel.heroes[0].grave.is_empty() and not _cards(duel, 0).has("OSJ1") and _hero_cards(duel, 0).has("OST1"),
		"#314: Water Link brings it back as the Avenger trap (hero %s, grave %s)" % [str(_hero_cards(duel, 0)), str(duel.heroes[0].grave)])

func _hand_returns(profile: ELProfile) -> void:
	var duel := _with_dead_jammer(profile, "OSJ2")
	check(_cast(duel, 0, "REPR", 0, 0) and duel.heroes[0].hand == ["OST2"], "#314: Repair returns the Punisher as its trap card (hand %s, %s)" % [str(duel.heroes[0].hand), duel.error])
	duel = _duel(profile)
	_summoned(duel, 1, "TIWR")
	var avenger := _summoned(duel, 0, "OSJ1")
	check(_cast(duel, 1, "UNSM", avenger) and not duel.creatures.has(avenger) and duel.heroes[0].hand == ["OST1"],
		"#314: Unsummon returns the Avenger as its trap card (hand %s, %s)" % [str(duel.heroes[0].hand), duel.error])

func _disenchant(profile: ELProfile) -> void:
	for trap: String in ["OST1", "OST2", "OST3"]:
		var duel := _duel(profile)
		var striker := _summoned(duel, 0, "TIWR")
		check(_cast(duel, 1, trap) and _cast(duel, 1, "SPWB"), "#316: side 1 lays %s and Spiritual Web (%s)" % [trap, duel.error])
		check(_cast(duel, 0, "SGHT", striker) and duel.has_flag(striker, "Disenchant"), "#316: side 0's wall breaks enchantments (%s)" % duel.error)
		duel.creatures[striker].resting = false
		duel.creatures[striker].sick = false
		check(duel.toggle_attack(striker) and duel.end_phase() and duel.end_phase(), "#316: it attacks hero 1 unblocked (%s)" % duel.error)
		check(int(duel.heroes[1].health) < 20 and _hero_cards(duel, 1) == [trap],
			"#316: the strike breaks Spiritual Web but leaves %s (hero %s)" % [trap, str(_hero_cards(duel, 1))])

## Side 1 lays `trap`, then side 0 casts `spell` against a board with a few
## enchantments; returns [the jammer's base, the ether side 0 paid].
func _jammer_after(profile: ELProfile, trap: String, spell: String, target := -1, choice := -1, power := 0) -> Array:
	var duel := _duel(profile)
	var walls := [_summoned(duel, 0, "TIWR"), _summoned(duel, 0, "TIWR"), _summoned(duel, 1, "TIWR"), _summoned(duel, 1, "TIWR")]
	_cast(duel, 1, trap)
	_cast(duel, 1, "WEAK", walls[0])
	_cast(duel, 0, "LSST", walls[1])
	if spell == "FLIC": choice = duel.creatures[walls[0]].enchantments[0].id
	if spell == "FLIC": target = walls[0]
	_turn(duel, 0)
	var before := int(duel.heroes[0].mana)
	duel._give_card(0, spell)
	var ok := duel.cast(duel.heroes[0].hand.find(spell), target, choice, power)
	var paid := before - int(duel.heroes[0].mana)
	var jammer := "OSJ" + trap.substr(3)
	for c: Dictionary in duel.creatures.values():
		if c.card == jammer: return [ok, int(c.base[0]), int(c.base[1]), paid, duel.error]
	return [ok, -1, -1, paid, duel.error]

func _redeemer(profile: ELProfile) -> void:
	var printed := func(card: String) -> int: return int(profile.table("CombatSpells")[card].Cost)
	for spell: String in ["CLSN", "DECN", "ANHL", "GRUN", "FLIC", "COMT"]:
		var power := 4 if spell == "COMT" else 0
		var got := _jammer_after(profile, "OST3", spell, 1 if spell == "COMT" else -1, -1, power)
		check(got[0] and got[1] == got[3] and got[2] == got[3] and got[3] > 0,
			"#317: the Redeemer after %s is %d/%d, the %d ether paid (%s)" % [spell, got[1], got[2], got[3], got[4]])
		if spell in ["CLSN", "FLIC", "COMT"]:
			var punisher := _jammer_after(profile, "OST2", spell, 1 if spell == "COMT" else -1, -1, power)
			check(punisher[0] and punisher[1] == printed.call(spell), "#317: the Punisher after %s is %d/%d, the printed cost %d" % [spell, punisher[1], punisher[2], printed.call(spell)])
