extends SceneTree
## Regression check for player reports #320, #321 and #311 (both games):
##
## - #320: hero enchantment abilities light up only while they have a legal
##   target: Self-Sacrifice, Burning, Ether Feeding and Dissipation need a
##   creature of one's own, Recharge a resting creature out of combat,
##   Rebirth, Second Birth and Repair Workshop a creature card in the own
##   graveyard (Second Birth one the hero can pay for).
## - #321: artifacts light up only while they have a legal target: a
##   creature (Subjugation, Ether Protection, Paralysis, Fire, Blessing), an
##   attacking creature (Destruction), a removable enchantment (Cleansing) or
##   a creature card in the own graveyard (Resurrection).
## - #311: the Plague Rat's Insatiable Scavenger is offered whatever the
##   graveyards hold, and the battle screen asks for the hero before the
##   ether to pay.
##
##   godot --headless --path game --script ../tools/issues_311_321_check.gd
##
## Needs the original games' files (user://profiles.json); a game without them
## is skipped. The battle screen part may write settings, as other checks do.

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
		_hero_abilities(profile)
		_artifacts(profile)
		_plague(profile)
	for edition: String in ["el1", "el2"]:
		if paths is Dictionary and paths.has(edition): await _plague_screen(edition)
	print("ISSUES 311/321: %d failure(s)" % failures)
	quit(int(failures > 0))

## A fresh duel with no creatures, side 0 to act in its attack phase, both
## heroes at 20 health and 30 ether, without skills or specialisations.
func _duel(profile: ELProfile) -> ELDuel:
	var duel := ELDuel.new()
	duel.start(profile, 5, {})
	for id: int in duel.creatures.keys(): duel.creatures.erase(id)
	for i in 8:
		if duel.active_side() == 0 and duel.phase == ELDuel.Phase.ATTACK: break
		duel.end_phase()
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
		hero.artifacts = []
		hero.artifact_uses = 0
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

func _usable(duel: ELDuel, card: String) -> bool:
	for ability: Dictionary in duel.abilities(0):
		if ability.get("enchantment_card", "") == card: return duel.can_use_ability(0, ability.key)
	return false

func _hero_abilities(profile: ELProfile) -> void:
	var game := profile.id
	var cards := ["CMBN", "BROT", "SPLK", "SACR", "ENRG", "RBRT", "SCBR", "RPST", "LSHE"]
	var duel := _duel(profile)
	for card: String in cards: duel._enchant(card, 0, 0, ELCatalog.rule(profile, card))
	for card: String in cards:
		check(_usable(duel, card) == (card == "LSHE"), "%s #320: %s %s with no creatures and empty graveyards" % [game, card, "lit" if card == "LSHE" else "unlit"])
	# An enemy creature is no sacrifice; a resting one may be recharged.
	var enemy := _summoned(duel, 1, "STRT")
	for card: String in ["CMBN", "BROT", "SPLK", "SACR", "ENRG"]:
		check(not _usable(duel, card), "%s #320: %s unlit with only an enemy creature, awake" % [game, card])
	duel.creatures[enemy].resting = true
	check(_usable(duel, "ENRG"), "%s #320: Recharge lit with a resting creature" % game)
	_summoned(duel, 0, "STRT")
	for card: String in ["CMBN", "BROT", "SPLK", "SACR"]:
		check(_usable(duel, card), "%s #320: %s lit with a creature of one's own" % [game, card])
	# A card in the enemy graveyard or a spell card in the own revives nothing.
	duel.heroes[1].grave = ["STRT"]
	duel.heroes[0].grave = ["FRBL"] if profile.table("CombatSpells").has("FRBL") else []
	for card: String in ["RBRT", "SCBR", "RPST"]:
		check(not _usable(duel, card), "%s #320: %s unlit without a creature card in the own graveyard" % [game, card])
	duel.heroes[0].grave.append("STRT")
	for card: String in ["RBRT", "SCBR", "RPST"]:
		check(_usable(duel, card), "%s #320: %s lit with a creature card in the own graveyard" % [game, card])
	# Second Birth pays the revived creature's printed cost.
	duel.heroes[0].mana = int(profile.table("CombatSpells")["STRT"].Cost) - 1
	check(not _usable(duel, "SCBR"), "%s #320: Second Birth unlit when no graveyard creature can be paid for" % game)

## The template whose battle spell is `spell`, ready with charges.
func _artifact(duel: ELDuel, spell: String) -> bool:
	for name: String in duel.profile.table("Artefacts"):
		if String(duel.profile.table("Artefacts")[name].get("SpellType", "")) != spell: continue
		var entry := ELDuel.artifact_entry(duel.profile, {"name": name})
		if entry.is_empty(): continue
		entry.charges = 3
		entry.ready_round = 0
		duel.heroes[0].artifacts = [entry]
		duel.heroes[0].artifact_uses = 0
		return true
	return false

func _artifact_lit(duel: ELDuel, spell: String) -> bool:
	return _artifact(duel, spell) and duel.can_use_ability(0, "artifact:0")

func _artifacts(profile: ELProfile) -> void:
	var game := profile.id
	var duel := _duel(profile)
	var creature_targets := ["RDCM", "ETAM", "WNPZ", "BRRD", "WNBL"]
	for spell: String in creature_targets + ["SPBR", "RDRS", "SPRG", "RDLG", "RDHL"]:
		if not _artifact(duel, spell):
			print("SKIP: %s has no artifact casting %s" % [game, spell])
			continue
		var lit := spell in ["RDLG", "RDHL"]
		check(duel.can_use_ability(0, "artifact:0") == lit and duel.artifact_error(0, 0).is_empty(),
			"%s #321: %s %s on an empty battlefield" % [game, spell, "lit" if lit else "unlit"])
	var enemy := _summoned(duel, 1, "STRT")
	for spell: String in creature_targets:
		if _artifact(duel, spell): check(duel.can_use_ability(0, "artifact:0"), "%s #321: %s lit with a creature to aim at" % [game, spell])
	if _artifact(duel, "SPRG"): check(not duel.can_use_ability(0, "artifact:0"), "%s #321: Destruction unlit without an attacker" % game)
	if _artifact(duel, "SPBR"):
		check(not duel.can_use_ability(0, "artifact:0"), "%s #321: Cleansing unlit without an enchantment" % game)
		duel._enchant("ETAM", 1, enemy, ELCatalog.ARTIFACT_EFFECTS["ETAM"])
		check(not duel.can_use_ability(0, "artifact:0"), "%s #321: Cleansing unlit when the only enchantment is on a screened creature" % game)
		duel._enchant("DMRD", 1, 1, ELCatalog.ARTIFACT_EFFECTS["DMRD"])
		check(duel.can_use_ability(0, "artifact:0"), "%s #321: Cleansing lit with an enchantment to remove" % game)
	else: duel._enchant("ETAM", 1, enemy, ELCatalog.ARTIFACT_EFFECTS["ETAM"])
	# Ether Protection screens the creature from every creature artifact.
	for spell: String in creature_targets:
		if _artifact(duel, spell): check(not duel.can_use_ability(0, "artifact:0"), "%s #321: %s unlit when the only creature is screened" % [game, spell])
	if _artifact(duel, "RDRS"):
		duel.heroes[1].grave = ["STRT"]
		check(not duel.can_use_ability(0, "artifact:0"), "%s #321: Resurrection unlit with a creature only in the enemy graveyard" % game)
		duel.heroes[0].grave = ["STRT"]
		check(duel.can_use_ability(0, "artifact:0"), "%s #321: Resurrection lit with a creature in the own graveyard" % game)

	# A generated artifact follows its spell's own targets.
	var made := ELDuel.artifact_entry(profile, {"name": "made", "custom": {"elk_name": "", "spell": "FAIL", "first": 0, "gap": 0, "max": 3}})
	if not made.is_empty():
		var bare := _duel(profile)
		bare.heroes[0].artifacts = [made]
		check(bare.artifact_error(0, 0).is_empty() and not bare.can_use_ability(0, "artifact:0"), "%s #321: a generated creature artifact unlit on an empty battlefield" % game)
		_summoned(bare, 1, "STRT")
		check(bare.can_use_ability(0, "artifact:0"), "%s #321: a generated creature artifact lit with a creature to aim at" % game)

func _plague(profile: ELProfile) -> void:
	var game := profile.id
	var duel := _duel(profile)
	var rat := _summoned(duel, 0, "PRAT")
	check(duel.can_use_ability(rat, "plague"), "%s #311: Insatiable Scavenger lit with both graveyards empty" % game)
	check(duel.use_ability(rat, "plague", 1, -1, 1) and int(duel.heroes[0].mana) == 29 and duel.creatures[rat].resting,
		"%s #311: it can be used on an empty graveyard (%s)" % [game, duel.error])

## The battle screen asks for the hero first, then the ether.
func _plague_screen(edition: String) -> void:
	var view: Node = load("res://scenes/duel.tscn").instantiate()
	root.add_child(view)
	for i in 3: await process_frame
	if not view.profiles.has(edition):
		view.queue_free()
		return
	view._hide_front_menu()
	view._start(edition, {"first_side": 0}, null, 311)
	var duel: ELDuel = view.duel
	duel.heroes[0].mana = 10
	duel.heroes[1].grave = ["STRT", "STRT", "STRT"]
	var rat := _summoned(duel, 0, "PRAT")
	view._skip_battle_presentation()
	var ability: Dictionary = {}
	for item: Dictionary in duel.abilities(rat):
		if item.key == "plague": ability = item
	view._select_ability(rat, ability)
	check(not view.power_dialog.visible and view.ability_selection.get("key") == "plague" and view.ability_selection.get("target") == "hero",
		"%s #311: choosing the ability first asks for a hero" % edition)
	view._target(1)
	check(view.power_dialog.visible and int(view.pending_power.get("target", -1)) == 1, "%s #311: then the ether to pay for that hero's graveyard" % edition)
	view.power_amount.value = 2
	view._confirm_power()
	check(duel.heroes[1].grave.size() == 1 and int(duel.heroes[0].mana) == 8, "%s #311: two creatures leave the chosen graveyard for 2 ether" % edition)
	view.queue_free()
	for i in 2: await process_frame
