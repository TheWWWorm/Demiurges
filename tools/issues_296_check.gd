extends SceneTree
## Regression check for #296: the Wall of Lava, Hellfire Wall and Wall of Wind
## pay any X of ether (at least 1, at most what the hero holds) for +X power
## (+X health for the hellfire wall), as often as the ether lasts, in both
## games (measured on the originals). The X choice opens at all the hero's ether and
## pays what is chosen. The computer, smart or not, pours all its ether into a
## wall it pumps in its defence (the originals' own reckoning only weighs X =
## all ether; what a defender keeps is gone when its turn begins) rather than a
## point at a time; the second game's original opponent keeps what its own
## priorities keep.
##
##   godot --headless --path game --script ../tools/issues_296_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. Settings are never written.

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _summoned(duel: ELDuel, side: int, card: String) -> int:
	var known := duel.creatures.keys()
	duel._summon(side, card)
	for key: int in duel.creatures:
		if not known.has(key):
			duel.creatures[key].sick = false
			duel.creatures[key].resting = false
			return key
	return -1

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
		_rules(profile)
		_computer(profile)
	await _choice()
	print("ISSUE 296: %d failure(s)" % failures)
	quit(int(failures > 0))

## A fresh duel with no creatures, in the active side's attack phase.
func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	duel.start(profile, 5, {})
	for id: int in duel.creatures.keys(): duel.creatures.erase(id)
	return duel

func _rules(profile: ELProfile) -> void:
	var edition := profile.id
	for card: String in ["WLLV", "WLIF", "WLWD"]:
		var stat := "toughness" if card == "WLIF" else "power"
		var duel := _duel(profile)
		var side := duel.active_side()
		duel.heroes[side].mana = 5
		var wall := _summoned(duel, side, card)
		var key: String = ELCatalog.first_ability(profile, card).key
		var before := int(duel.creatures[wall][stat])
		check(not duel.use_ability(wall, key, -1, -1, 0), "%s %s: X = 0 is refused" % [edition, card])
		check(not duel.use_ability(wall, key, -1, -1, 6), "%s %s: X above the ether is refused" % [edition, card])
		check(duel.use_ability(wall, key, -1, -1, 2) and int(duel.creatures[wall][stat]) == before + 2 and int(duel.heroes[side].mana) == 3,
			"%s %s: X = 2 gives +2 %s for 2 ether" % [edition, card, stat])
		check(duel.use_ability(wall, key, -1, -1, 3) and int(duel.creatures[wall][stat]) == before + 5 and int(duel.heroes[side].mana) == 0,
			"%s %s: used again for 3, +5 in all" % [edition, card])

## The computer defending with each wall against an attacker it can kill.
func _computer(profile: ELProfile) -> void:
	var edition := profile.id
	for card: String in ["WLLV", "WLWD", "WLIF"]:
		for smart: bool in [true, false]:
			var duel := _duel(profile)
			var side := duel.active_side()
			var foe := 1 - side
			duel.heroes[side].mana = 10
			duel.heroes[foe].mana = 7
			# A 2/2 for the lava and wind walls to kill; the hellfire wall must
			# live through a 9/9 trampling horror's blow.
			var attacker := _summoned(duel, side, "WKHR" if card == "WLIF" else "TIWR")
			if card == "WLIF":
				duel.creatures[attacker].base = [12, 30]
				duel._refresh_stats(duel.creatures[attacker])
			var wall := _summoned(duel, foe, card)
			if not duel.toggle_attack(attacker):
				check(false, "%s %s: the attack is declared (%s)" % [edition, card, duel.error])
				continue
			duel.end_phase()
			duel.smart_sides.clear()
			if smart: duel.smart_sides.append(foe)
			var pumps: Array = []
			for step in 8:
				if duel.phase != ELDuel.Phase.DEFENCE: break
				var command := ELCombatSearch.think(duel, {})
				if command.is_empty() or command.kind == "end_phase": break
				if command.kind == "ability" and int(command.id) == wall: pumps.append(int(command.amount))
				if not ELCombatSearch.apply(duel, command): break
			# The second game's original opponent keeps the share its own
			# priorities keep (one ether for lava and wind, three for hellfire).
			var expected := 7 if smart or edition == "el1" else (4 if card == "WLIF" else 6)
			check(pumps == [expected], "%s %s (%s): the computer pumps the wall once with %d of its 7 ether (%s)" % [edition, card, "smart" if smart else "original", expected, pumps])

## The player's X choice: it opens at all the ether and pays what is chosen.
func _choice() -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	view.demo = true
	root.add_child(view)
	await process_frame
	if not view.profiles.has("el1"):
		view.queue_free()
		return
	var profile: ELProfile = view.profiles.el1
	var players := [{"faction": "Red", "level": 3, "map_level": 2, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)},
		{"faction": "Red", "level": 5, "cards": ELCatalog.available_cards(profile, "Red").slice(0, 8)}]
	view._start("el1", {"arena": ELDuelMatch.arenas(profile)[0], "adventure": true, "players": players})
	view.demo = false
	for i in 10: await process_frame
	var duel: ELDuel = view.duel
	if duel == null or not view._human_turn():
		check(false, "el1: a battle for the X choice starts on the player's turn")
		view.queue_free()
		return
	var side := duel.active_side()
	duel.heroes[side].mana = 6
	var wall := _summoned(duel, side, "WLLV")
	var before := int(duel.creatures[wall].power)
	view._select_ability(wall, duel.abilities(wall)[0])
	check(view.power_dialog.visible and view.power_dialog.value() == 6 and int(view.power_amount.max_value) == 6, "el1: the lava wall's X choice opens at all 6 ether")
	view.power_dialog.set_value(4)
	view._confirm_power()
	check(int(duel.creatures[wall].power) == before + 4 and int(duel.heroes[side].mana) == 2, "el1: choosing 4 gives +4 power for 4 ether")
	view.queue_free()
	await process_frame
