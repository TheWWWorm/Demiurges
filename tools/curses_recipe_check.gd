extends SceneTree
## Headless check of the second game's discard artifact recipe (MT_E2_ARTEFACT_
## RECIPE_4, the tracker's BA4), run by the shipped artifact tracker
## (ArtifactTracker.scp) in real duels: the hero casts only summons (Wand of
## Curses) or only other spells (Wand of Malisons), starts at least three enemy
## turns with an empty hand, and the enemy hero dies with both hands empty.
## Mixing both kinds, a forbidden hand-changing spell, fewer empty turns or a
## card left in either hand makes none.
##
##   godot --headless --path game --script ../tools/curses_recipe_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped.

var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok: failures.append(what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el2"):
		print("SKIP: no second-game files configured (user://profiles.json)")
	else:
		var profile := ELProfile.new()
		if not profile.mount("el2", str(paths.el2)):
			print("SKIP: the second game's files could not be mounted")
		elif profile.script_bytes(ELSecondArtifacts.TRACKER).is_empty():
			print("SKIP: the artifact tracker is not in the scripts archive")
		else:
			_recipe(profile)
		if profile.metal_masks != null: profile.metal_masks.stop()
	print("CURSES RECIPE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _duel(profile: ELProfile) -> ELDuel:
	var player := {"faction": "Black", "deck": ELCatalog.STARTERS.Black, "level": 6}
	var duel := ELDuel.new()
	if not duel.start(profile, 4100, {"players": [player, player.duplicate(true)], "scripts": [{"name": ELSecondArtifacts.TRACKER, "side": 0}], "script_variables": {"ConstructorIsArtefact": 0.0}}):
		check(false, "a duel with the artifact tracker starts: %s" % duel.error)
		return null
	if duel.scripts == null or duel.scripts.states.size() != 1:
		check(false, "the artifact tracker loads: %s" % (str(duel.scripts.notes) if duel.scripts != null else "no scripts"))
		return null
	duel.scripts.in_combat = true
	# No turn-start draws: the hands stay as the test leaves them.
	duel.setup.puzzle_fixed_hands = true
	return duel

func _vm(duel: ELDuel) -> ELLuaVM:
	return duel.scripts.states[0].vm

func _record(duel: ELDuel) -> String:
	var g := _vm(duel).globals
	return "creature=%s spell=%s forbidden=%s zero_turns=%s hands=%d/%d" % [str(g.get("ba4_bCreatureUsed")), str(g.get("ba4_bSpellUsed")), str(g.get("ba4_bForbiddenUsed")), str(g.get("ba4_numZeroTurns")), duel.heroes[0].hand.size(), duel.heroes[1].hand.size()]

func _made(duel: ELDuel) -> Dictionary:
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", "")), "charges": made.get("ConstructorArtefactCharges")}

## Casts `card` for side 0, with no target or the enemy hero.
func _cast(duel: ELDuel, card: String) -> bool:
	if duel.cast_free(0, card, [], false): return true
	if duel.cast_free(0, card, [1], false): return true
	check(false, "%s is cast: %s" % [card, duel.error])
	return false

## Plays phases until side 1 has started `turns` more turns, the hands kept
## as they are (`enemy_card` left in the enemy's hand when not empty).
func _pass_enemy_turns(duel: ELDuel, turns: int) -> void:
	var start := int(duel.heroes[1].turns)
	for i in 40:
		if int(duel.heroes[1].turns) - start >= turns or duel.phase == ELDuel.Phase.FINISHED: break
		if not duel.end_phase():
			check(false, "a phase ends: %s" % duel.error)
			return

## `casts` for side 0; both hands emptied (or the enemy keeping one card);
## `turns` enemy turns started; then the enemy hero dies.
func _play(profile: ELProfile, casts: Array, turns: int, enemy_keeps := false) -> Dictionary:
	var duel := _duel(profile)
	if duel == null: return {}
	for card: String in casts: _cast(duel, card)
	var kept: Array = duel.heroes[1].hand.slice(0, 1) if enemy_keeps else []
	duel.heroes[0].hand.clear()
	duel.heroes[1].hand.clear()
	duel.heroes[1].hand.append_array(kept)
	_pass_enemy_turns(duel, turns)
	var record := _record(duel)
	duel.script_damage(1, 999, 0)
	var result := _made(duel)
	result.record = record
	result.finished = duel.phase == ELDuel.Phase.FINISHED
	result.notes = duel.scripts.notes.duplicate()
	duel.scripts.close()
	return result

## A summon card and a plain spell of the second game: the first creature
## card, and Suffocation Gas (no target, not a hand-changing spell).
func _summon_card(profile: ELProfile) -> String:
	for card: String in profile.table("CombatSpells"):
		if str(profile.table("CombatSpells")[card].get("Class", "")) == "Creature" and profile.table("CombatCreatures").has(card): return card
	return ""

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_4", "T_CUSTOM_ARTEFACT_WAND_OF_CURSES", "T_CUSTOM_ARTEFACT_WAND_OF_MALISONS"]:
		check(profile.texts.has(key), "the game's text has %s" % key)
	var summon := _summon_card(profile)
	var spell := "SFGS"
	check(not summon.is_empty() and str(profile.table("CombatSpells").get(spell, {}).get("Class", "")) != "Creature", "a summon (%s) and a plain spell (%s) to cast" % [summon, spell])

	var result := _play(profile, [summon], 3)
	check(result.get("finished", false) and result.made and result.name == "T_CUSTOM_ARTEFACT_WAND_OF_CURSES" and result.spell == "CURS",
		"summons only and three empty-handed enemy turns make the Wand of Curses: %s" % str(result))
	check(result.get("notes", ["?"]).is_empty(), "no script errors: %s" % str(result.get("notes")))

	result = _play(profile, [spell], 3)
	check(result.get("finished", false) and result.made and result.name == "T_CUSTOM_ARTEFACT_WAND_OF_MALISONS" and result.spell == "MALS",
		"plain spells only make the Wand of Malisons: %s" % str(result))

	result = _play(profile, [summon, spell], 3)
	check(result.get("finished", false) and not result.made, "a summon and a plain spell together make no wand: %s" % str(result))

	result = _play(profile, [summon], 2)
	check(result.get("finished", false) and not result.made, "two empty-handed enemy turns make no wand: %s" % str(result))

	result = _play(profile, [summon], 3, true)
	check(result.get("finished", false) and not result.made, "a card left in the enemy's hand makes no wand: %s" % str(result))

	# A forbidden hand-changing spell, among the tracker's five, that this
	# duel can cast.
	for card: String in ["AMNS", "FRWN", "BANN", "ENFR", "AWAK"]:
		if not profile.table("CombatSpells").has(card): continue
		var probe := _duel(profile)
		if probe == null: return
		var castable := probe.cast_free(0, card, [], false) or probe.cast_free(0, card, [1], false)
		probe.scripts.close()
		if not castable: continue
		result = _play(profile, [spell, card], 3)
		check(result.get("finished", false) and not result.made, "the hand-changing %s with plain spells makes no wand: %s" % [card, str(result)])
		break
