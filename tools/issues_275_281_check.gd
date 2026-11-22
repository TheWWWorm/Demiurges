extends SceneTree
## Regression checks for two battle reports:
## - #275: the first game's Blinding Illusion specialisation (BWIT). When a
##   Wall of Illusion strikes what it blocks, the original holds the attacker
##   down for good by a mark on the creature itself, not by an enchantment:
##   no dispelling spell can find it (Purify has nothing to aim at) and
##   Cleanse leaves the creature held. The remake shows that hold as a fixed
##   mark, named and described as the specialisation and drawn with the
##   specialisation icon the battle uses, not the empty cell of a card the
##   spell table does not have.
## - #281: the second game's Ice Storm (ICST), like Glade (GLDT), passes over
##   a creature in the Colourless Plane, and so does Rally (ENAL); a pale
##   creature that has manifested is reached as any other.
##
##   godot --headless --path game --script ../tools/issues_275_281_check.gd
##
## Needs the player's game files (user://profiles.json); a game without them
## is skipped. tools/duel_rules_check.gd -- --parity holds the same #281
## positions against the compiled lookahead.

const Fixtures := preload("res://../tools/duel_fixtures.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, caption: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + caption)
	if not ok: failures += 1

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	for id: String in ["el1", "el2"]:
		if paths is not Dictionary or not paths.has(id):
			print("SKIP: no %s files configured (user://profiles.json)" % id)
			continue
		var profile := ELProfile.new()
		if not profile.mount(id, str(paths[id])):
			print("SKIP: %s files could not be mounted" % id)
			continue
		if id == "el1": _blinding_illusion(profile)
		else: _colourless_plane(profile)
		if profile.metal_masks != null: profile.metal_masks.stop()
	print("ISSUES 275 281: %d failure(s)" % failures)
	quit(int(failures > 0))

func _blinding_illusion(profile: ELProfile) -> void:
	var spec := {"heroes": [{"health": 20, "mana": 20, "maximum": 20, "hand": ["CLSN", "PRFY"]}, {"health": 20, "mana": 0, "maximum": 20, "spec": "BWIT", "spec_level": 20, "luck": 3}],
		"creatures": [{"card": "TIWR", "owner": 0}, {"card": "WLIL", "owner": 1}]}
	var d := Fixtures.build(profile, spec)
	if d == null:
		_check(false, "The Blinding Illusion position restores")
		return
	# Specialisations by their odds, as the rules check plays them: a roll
	# this sure always succeeds.
	d.expected_specs = true
	d.fair_specs = true
	var played := d.toggle_attack(2) and d.end_phase() and d.assign_block(3, 2) and d.end_phase()
	_check(played, "The tick attacks and the Wall of Illusion blocks it")
	var mark := {}
	for e: Dictionary in d.creatures.get(2, {}).get("enchantments", []):
		if e.card == "BWIT": mark = e
	_check(not mark.is_empty() and mark.get("fixed", false), "Blinding Illusion marks the attacker with a fixed hold")
	if mark.is_empty(): return
	# Back to the attacker's own turn: it stays down.
	played = d.end_phase() and d.end_phase()
	while d.active_side() != 0 and d.phase != ELDuel.Phase.FINISHED and d.end_phase(): pass
	_check(d.active_side() == 0 and bool(d.creatures[2].resting), "The held attacker does not rise on its hero's next turn")
	_check(not d.dispellable(2, mark), "The hold is no enchantment a dispel can remove (the original keeps none)")
	_check(not d.valid_enchantment_targets("PRFY").has(int(mark.id)), "Purify cannot aim at the hold")
	var cleanse: int = d.heroes[0].hand.find("CLSN")
	d.heroes[0].mana = 20
	var cast := cleanse >= 0 and d.cast(cleanse)
	print("  Cleanse: ", "cast" if cast else d.error)
	var kept := false
	for e: Dictionary in d.creatures[2].enchantments: kept = kept or e.card == "BWIT"
	_check(kept and bool(d.creatures[2].resting), "Cleanse leaves the attacker held")
	# What the strip shows for it.
	var row: Dictionary = profile.table("HeroesSpecs").BWIT
	_check(profile.specialisation_mark("BWIT") and not profile.specialisation_mark("WLIL"), "BWIT reads as a specialisation's mark, a card code does not")
	_check(d.card_name("BWIT") == profile.text(str(row.Name)) and d.card_name("BWIT") != "BWIT", "The mark is named after the specialisation (%s)" % d.card_name("BWIT"))
	_check(profile.card_description("BWIT") == profile.text(str(row.Desc)), "The mark's text is the specialisation's description")
	var icon := profile.card_icon("BWIT") as AtlasTexture
	var expected := profile.specialisation_icon() as AtlasTexture
	var blank := profile.icon_at(0) as AtlasTexture
	_check(icon != null and expected != null and icon.atlas != null and icon.atlas == expected.atlas and icon.region == expected.region,
		"The mark is drawn with the specialisation icon")
	_check(icon != null and blank != null and not (icon.atlas == blank.atlas and icon.region == blank.region), "The mark no longer shows the spell sheet's first cell")
	_check(d.card_name("WLIL") == profile.text(str(profile.table("CombatSpells").WLIL.Name)), "Card names are unchanged")

func _colourless_plane(profile: ELProfile) -> void:
	for card: String in ["ICST", "GLDT"]:
		for manifested: bool in [false, true]:
			var d := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 20, "hand": [card]}, {"health": 20, "mana": 0}],
				"creatures": [{"card": "TIWR", "owner": 1}, {"card": "OUD3", "owner": 1}]})
			if d == null:
				_check(false, "%s position restores" % card)
				return
			d.creatures[3].plane = not manifested
			_check(d.cast(0), "%s is cast" % d.card_name(card))
			var where := "a manifested pale creature" if manifested else "a creature in the Colourless Plane"
			_check(bool(d.creatures[2].resting), "%s rests an ordinary enemy" % card)
			_check(bool(d.creatures[3].resting) == manifested, "%s %s %s" % [card, "rests" if manifested else "spares", where])
	var rally := Fixtures.build(profile, {"heroes": [{"health": 20, "mana": 20, "hand": ["ENAL"]}, {"health": 20, "mana": 0}],
		"creatures": [{"card": "TIWR", "owner": 0, "resting": true}, {"card": "OUD3", "owner": 0, "resting": true}]})
	if rally == null:
		_check(false, "Rally position restores")
		return
	rally.creatures[3].plane = true
	_check(rally.cast(0), "Rally is cast")
	_check(not bool(rally.creatures[2].resting) and bool(rally.creatures[3].resting), "Rally readies the tick and leaves the creature in the plane resting")
