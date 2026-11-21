extends SceneTree
## Headless check of the second game's gas artifact recipe (MT_E2_ARTEFACT_
## RECIPE_2), run by the shipped artifact tracker (ArtifactTracker.scp) in real
## duels: the hero casts all four gases, puts Pain Link on two of its own
## summoned creatures, and
## the enemy hero dies of Suffocation Gas at the end of the hero's turn while
## both links hold. The tracker reads its "killed by Suffocation Gas" flag at
## the hero's death, between the enchantment's start and finish hooks, so the
## death must be told inside that window. Also: a missing gas, a single Pain
## Link, or a death outside the gas's turn end make no ring.
##
##   godot --headless --path game --script ../tools/gas_recipe_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped.

const GASES := ["DRGS", "DPGS", "FRGS", "SFGS"]

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
	print("GAS RECIPE: %d failure(s)" % failures.size())
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
	return duel

## A summonable creature tough enough to outlive Frenzy Gas and a Suffocation
## Gas tick (toughness of at least 6).
func _sturdy(profile: ELProfile) -> String:
	var best := ""
	var best_toughness := 0
	for card: String in profile.table("CombatCreatures"):
		var row: Dictionary = profile.table("CombatCreatures")[card]
		var toughness := int(row.get("Toughness", row.get("Defence", 0)))
		if toughness >= 6 and toughness > best_toughness and profile.table("CombatSpells").has(card):
			best = card
			best_toughness = toughness
	return best

func _summon(duel: ELDuel, side: int, card: String) -> int:
	var before := duel.next_id
	if not duel.cast_free(side, card, [], false): check(false, "%s is summoned: %s" % [card, duel.error])
	return before if duel.creatures.has(before) else -1

func _vm(duel: ELDuel) -> ELLuaVM:
	return duel.scripts.states[0].vm

func _made(duel: ELDuel) -> Dictionary:
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", "")), "charges": made.get("ConstructorArtefactCharges")}

## Sets up the recipe: `links` Pain Links on the hero's own summoned
## creatures (the tracker records only its hero's summons), the
## gases in `gases` cast by the hero (Suffocation Gas last), the enemy hero
## left at `health`.
func _prepare(profile: ELProfile, links: int, gases: Array, health: int) -> ELDuel:
	var duel := _duel(profile)
	if duel == null: return null
	var card := _sturdy(profile)
	if card.is_empty():
		check(false, "the second game has a creature with toughness 6 or more")
		return null
	for i in links:
		var id := _summon(duel, 0, card)
		if id >= 0 and not duel.cast_free(0, "PALN", [id], false): check(false, "Pain Link goes on creature %d: %s" % [id, duel.error])
	for gas: String in gases:
		if not duel.cast_free(0, gas, [], false): check(false, "%s is cast: %s" % [gas, duel.error])
	duel.heroes[1].health = health
	duel.attacker = 0
	return duel

## The end of the hero's turn: end-of-turn enchantments, then the winner.
func _end_turn(duel: ELDuel) -> void:
	duel._turn_enchantments(false)
	duel._check_winner()

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_2", "T_CUSTOM_ARTEFACT_RING_OF_GASES", "T_CUSTOM_ARTEFACT_RING_OF_SUFFOCATION"]:
		check(profile.texts.has(key), "the game's text has %s" % key)

	# The recipe in full: the enemy hero dies of Suffocation Gas.
	var duel := _prepare(profile, 2, GASES, 2)
	if duel == null: return
	var vm := _vm(duel)
	var counts: Variant = vm.globals.get("ba3_gas_count")
	var table := {}
	if counts is ELLuaVM.Table:
		for i in 5:
			var row: Variant = (counts as ELLuaVM.Table).values.get(float(i))
			if row is ELLuaVM.Table: table[i] = [(row as ELLuaVM.Table).values.get("casted"), (row as ELLuaVM.Table).values.get("alive")]
	check(table.size() == 5 and table[4][1] == 2.0 and GASES.size() == 4 and [0, 1, 2, 3].all(func(i: int) -> bool: return table[i][0] >= 1.0),
		"the tracker counts each gas once and two living Pain Links: %s" % str(table))
	_end_turn(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and duel.winner == 0, "Suffocation Gas kills the enemy hero (health %d)" % int(duel.heroes[1].health))
	var result := _made(duel)
	check(result.made and result.name in ["T_CUSTOM_ARTEFACT_RING_OF_GASES", "T_CUSTOM_ARTEFACT_RING_OF_SUFFOCATION"] and result.spell in GASES,
		"the enemy hero's death by Suffocation Gas makes a gas ring: %s" % str(result))
	check(vm.globals.get("ba3_damage_by_suffgas") == null, "the finish hook clears the Suffocation Gas flag afterwards")
	check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
	duel.scripts.close()

	# Only one Pain Link: no ring.
	duel = _prepare(profile, 1, GASES, 2)
	if duel == null: return
	_end_turn(duel)
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and not result.made, "a single Pain Link makes no ring: %s" % str(result))
	duel.scripts.close()

	# Frenzy Gas never cast: no ring.
	duel = _prepare(profile, 2, ["DRGS", "DPGS", "SFGS"], 2)
	if duel == null: return
	_end_turn(duel)
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and not result.made, "three of the four gases make no ring: %s" % str(result))
	duel.scripts.close()

	# The enemy hero killed by other damage, not the gas: no ring.
	duel = _prepare(profile, 2, GASES, 20)
	if duel == null: return
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and not result.made, "a death not caused by Suffocation Gas makes no ring: %s" % str(result))
	duel.scripts.close()
