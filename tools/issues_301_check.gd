extends SceneTree
## Regression check for #301: several control enchantments (Subjugation CHCM,
## the Ring of Subjugation's RDCM) on one creature, measured on the original
## games' combat code (measured on both games):
##
## - Only the latest control enchantment cast has effect: the creature belongs
##   to its caster. Removing it hands the creature to the caster of the newest
##   one left, or to its original owner when none is left. Removing an older
##   one changes nothing (no change of hands, no rest).
## - A creature that changes hands waits a turn to act; one that stays is
##   untouched.
## - Army limit: the second game refuses a dispel that would send the creature
##   into a full army; the first refuses one whose caster's army is full
##   without the creature, and otherwise lets the creature stay where it is
##   when the army it would go to is full.
## - Second game: control sleeps in the Colourless Plane. A controlled creature
##   that enters the plane (its own dissipation, Banishment, a lethal blow)
##   goes back to its original owner with the enchantment still on it, and
##   goes back to the controller when it manifests.
## - A save of a creature back home under an overruled or sleeping control
##   enchantment loads.
##
##   godot --headless --path game --script ../tools/issues_301_check.gd
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
		_stacks(profile)
		_full(profile)
		if edition == "el2": _plane(profile)
	print("ISSUE 301: %d failure(s)" % failures)
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
func _cast(duel: ELDuel, side: int, card: String, target: int, choice := -1) -> bool:
	_turn(duel, side)
	duel._give_card(side, card)
	return duel.cast(duel.heroes[side].hand.find(card), target, choice)

func _controls(duel: ELDuel, id: int) -> Array[int]:
	var out: Array[int] = []
	for e: Dictionary in duel.creatures[id].enchantments:
		if e.card in ELCatalog.CONTROL: out.append(int(e.id))
	return out

## Side 1's wall stolen by side 0, taken back by side 1 and so on: `count`
## alternating control enchantments, each in its caster's turn.
func _stacked(profile: ELProfile, count: int, cards := ["CHCM", "CHCM", "CHCM"]) -> Array:
	var duel := _duel(profile)
	var wall := _summoned(duel, 1, "TIWR")
	_summoned(duel, 0, "TIWR")
	for k in count:
		var ok := _cast(duel, k % 2, cards[k], wall)
		check(ok and int(duel.creatures[wall].owner) == k % 2, "%s: control %d (%s) passes the wall to side %d (%s)" % [profile.id, k + 1, cards[k], k % 2, duel.error])
	return [duel, wall]

## Side 0 dispels enchantment `eid` from the wall with Purify in its own turn.
func _purify(duel: ELDuel, wall: int, eid: int, side := 0) -> bool:
	return _cast(duel, side, "PRFY", wall, eid)

func _state(duel: ELDuel, wall: int) -> String:
	var c: Dictionary = duel.creatures[wall]
	return "owner %d sick %s resting %s origin %s" % [int(c.owner), c.sick, c.resting, str(c.get("origin", "-"))]

func _stacks(profile: ELProfile) -> void:
	var game := profile.id
	# Two controls: the latest goes, the older one takes over.
	var run := _stacked(profile, 2)
	var duel: ELDuel = run[0]
	var wall: int = run[1]
	var ids := _controls(duel, wall)
	check(_purify(duel, wall, ids[1]) and int(duel.creatures[wall].owner) == 0 and duel.creatures[wall].sick and not duel.creatures[wall].resting,
		"%s two controls, latest dispelled: the wall goes to the older one's caster and waits a turn (%s)" % [game, _state(duel, wall)])
	check(_purify(duel, wall, ids[0]) and int(duel.creatures[wall].owner) == 1 and duel.creatures[wall].sick and not duel.creatures[wall].has("origin"),
		"%s two controls, then the older one: the wall goes home (%s)" % [game, _state(duel, wall)])
	# Two controls: the older one goes, nothing changes.
	run = _stacked(profile, 2)
	duel = run[0]
	wall = run[1]
	ids = _controls(duel, wall)
	_turn(duel, 0)
	duel.creatures[wall].sick = false
	check(_purify(duel, wall, ids[0]) and int(duel.creatures[wall].owner) == 1 and not duel.creatures[wall].sick and not duel.creatures[wall].resting,
		"%s two controls, older dispelled: the wall stays with the latest caster, ready (%s)" % [game, _state(duel, wall)])
	check(_purify(duel, wall, ids[1]) and int(duel.creatures[wall].owner) == 1 and not duel.creatures[wall].sick and not duel.creatures[wall].has("origin"),
		"%s two controls, then the latest (its owner's): the wall stays home, ready (%s)" % [game, _state(duel, wall)])
	# Three controls (side 0, side 1, side 0).
	run = _stacked(profile, 3)
	duel = run[0]
	wall = run[1]
	ids = _controls(duel, wall)
	check(_purify(duel, wall, ids[1]) and int(duel.creatures[wall].owner) == 0, "%s three controls, middle dispelled: side 0 keeps the wall (%s)" % [game, _state(duel, wall)])
	duel.creatures[wall].sick = false
	check(_purify(duel, wall, ids[2]) and int(duel.creatures[wall].owner) == 0 and not duel.creatures[wall].sick,
		"%s then the latest: the first one is side 0's too, so nothing changes (%s)" % [game, _state(duel, wall)])
	check(_purify(duel, wall, ids[0]) and int(duel.creatures[wall].owner) == 1 and duel.creatures[wall].sick, "%s then the first: home (%s)" % [game, _state(duel, wall)])
	run = _stacked(profile, 3)
	duel = run[0]
	wall = run[1]
	ids = _controls(duel, wall)
	check(_purify(duel, wall, ids[2]) and int(duel.creatures[wall].owner) == 1, "%s three controls, latest dispelled: side 1's takes over (%s)" % [game, _state(duel, wall)])
	check(_purify(duel, wall, ids[1]) and int(duel.creatures[wall].owner) == 0, "%s then side 1's: side 0's first one rules again (%s)" % [game, _state(duel, wall)])
	# The ring and the spell stack alike (the second game's ring is also a hand card).
	if game == "el2":
		run = _stacked(profile, 2, ["RDCM", "CHCM"])
		duel = run[0]
		wall = run[1]
		ids = _controls(duel, wall)
		check(_purify(duel, wall, ids[1], 1) and int(duel.creatures[wall].owner) == 0, "%s ring then spell, spell dispelled: the ring's caster has the wall (%s)" % [game, _state(duel, wall)])
	# A save with the wall home under an overruled control loads.
	run = _stacked(profile, 2)
	duel = run[0]
	var saved: Variant = JSON.parse_string(JSON.stringify(duel.snapshot()))
	var decoded := ELMatchSave.decode(profile, saved)
	check(not decoded.has("error"), "%s a save with the wall home under an overruled control loads (%s)" % [game, decoded.get("error", "")])

func _full(profile: ELProfile) -> void:
	var game := profile.id
	# Single control, the original owner's army full.
	var duel := _duel(profile)
	_summoned(duel, 0, "TIWR")
	var wall := _summoned(duel, 1, "GBAT")
	for i in 9: _summoned(duel, 1, "TIWR")
	_cast(duel, 0, "CHCM", wall)
	_summoned(duel, 1, "TIWR")
	var eid: int = _controls(duel, wall)[0]
	var allowed := duel.valid_enchantment_targets("PRFY", wall).has(eid)
	if game == "el2":
		check(not allowed, "el2 single control, owner's army full: it cannot be dispelled")
	else:
		check(allowed and _purify(duel, wall, eid, 1) and int(duel.creatures[wall].owner) == 0 and _controls(duel, wall).is_empty(),
			"el1 single control, owner's army full: dispelled, the creature stays (%s)" % _state(duel, wall))
	# Two controls [side 0, side 1], the creature with side 1, side 0's army full without it.
	duel = _duel(profile)
	for i in 9: _summoned(duel, 0, "TIWR")
	wall = _summoned(duel, 1, "GBAT")
	_summoned(duel, 1, "TIWR")
	_cast(duel, 0, "CHCM", wall)
	_cast(duel, 1, "CHCM", wall)
	_summoned(duel, 0, "TIWR")
	var ids := _controls(duel, wall)
	var latest_ok := duel.valid_enchantment_targets("PRFY", wall).has(ids[1])
	var older_ok := duel.valid_enchantment_targets("PRFY", wall).has(ids[0])
	if game == "el2":
		check(not latest_ok and older_ok, "el2 stack, latest's removal would fill side 0 past ten: refused; the older one may go")
	else:
		check(latest_ok and not older_ok, "el1 stack, side 0 full: side 1's may go, side 0's (its caster full) may not")
		check(_purify(duel, wall, ids[1], 1) and int(duel.creatures[wall].owner) == 1 and _controls(duel, wall) == [ids[0]],
			"el1 stack: side 1's dispelled, the creature stays with side 1 (%s)" % _state(duel, wall))

func _plane(profile: ELProfile) -> void:
	for how: String in ["dissipate", "banish", "blow"]:
		var duel := _duel(profile)
		_summoned(duel, 0, "TIWR")
		var pale := _summoned(duel, 1, "OUD1")
		_turn(duel, 1)
		check(duel.use_ability(pale, "fiendish") and not duel.in_plane(pale), "el2 %s: side 1 manifests its devourer (%s)" % [how, duel.error])
		check(_cast(duel, 0, "CHCM", pale) and int(duel.creatures[pale].owner) == 0, "el2 %s: side 0 takes it (%s)" % [how, duel.error])
		duel.creatures[pale].sick = false
		var ok := false
		match how:
			"dissipate": ok = duel.use_ability(pale, "dissipate")
			"banish": ok = _cast(duel, 0, "BNSH", pale)
			"blow":
				duel._damage(pale, 99)
				ok = true
		check(ok and duel.in_plane(pale) and int(duel.creatures[pale].owner) == 1 and duel.creatures[pale].sick and _controls(duel, pale).size() == 1,
			"el2 %s: in the plane it is side 1's again, its control asleep on it (%s)" % [how, _state(duel, pale)])
		var saved: Variant = JSON.parse_string(JSON.stringify(duel.snapshot()))
		var decoded := ELMatchSave.decode(profile, saved)
		check(not decoded.has("error"), "el2 %s: a save with the control asleep loads (%s)" % [how, decoded.get("error", "")])
		_turn(duel, 1)
		check(duel.use_ability(pale, "fiendish") and not duel.in_plane(pale) and int(duel.creatures[pale].owner) == 0 and duel.creatures[pale].sick,
			"el2 %s: manifested by side 1, it goes back to side 0 and waits (%s, %s)" % [how, _state(duel, pale), duel.error])
