extends SceneTree
## Headless check of the second game's ether-harvest artifact recipe
## (MT_E2_ARTEFACT_RECIPE_6, tracker BA6), run by the shipped artifact tracker
## (ArtifactTracker.scp) in real duels with the duel's own turn flow: Ether
## Thorns active since the start of the hero's turn, an Ether Drop, Tap or
## Draw cast that turn, no ether left and no healing spell when the enemy's
## turn begins; the enemy hero's later death makes the Wand of Ether Harvest.
## Thorns cast only during that turn, a healing spell, ether left over, or no
## ether spell make none.
##
##   godot --headless --path game --script ../tools/harvest_recipe_check.gd
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
	print("HARVEST RECIPE: %d failure(s)" % failures.size())
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

func _globals(duel: ELDuel) -> String:
	var g: Dictionary = duel.scripts.states[0].vm.globals
	var table := func(name: String) -> String:
		var t: Variant = g.get(name)
		return str((t as ELLuaVM.Table).values) if t is ELLuaVM.Table else str(t)
	return "thorns=%s bof=%s edt=%s turn_valid=%s recp_valid=%s atcreated=%s mana=%d" % [table.call("ba6_thorns_counter"), table.call("ba6_tc_bof"), table.call("ba6_edt"),
		str(g.get("ba6_bTurnValid")), str(g.get("ba6_RecpValid")), str(g.get("ba6_atcreated")), int(duel.heroes[0].mana)]

## Ends phases until `side`'s turn has begun.
func _until_turn_of(duel: ELDuel, side: int) -> bool:
	for i in 12:
		if int(duel.attacker) == side and duel.phase == ELDuel.Phase.ATTACK: return true
		if duel.phase == ELDuel.Phase.FINISHED: return false
		if not duel.end_phase():
			check(false, "the phase ends: %s" % duel.error)
			return false
	return int(duel.attacker) == side

## Thorns before the turn (`thorns_before`) or during it, `spells` cast in
## the hero's turn, ether spent when `spend`. The hero's turn then ends.
func _prepare(profile: ELProfile, thorns_before: bool, spells: Array, spend: bool) -> ELDuel:
	var duel := _duel(profile)
	if duel == null: return null
	if not _until_turn_of(duel, 0): return null
	if thorns_before and not duel.cast_free(0, "MNTH", [], false): check(false, "Ether Thorns is cast: %s" % duel.error)
	# The hero's next turn: thorns are active from its beginning.
	if not _until_turn_of(duel, 1) or not _until_turn_of(duel, 0): return null
	if not thorns_before and not duel.cast_free(0, "MNTH", [], false): check(false, "Ether Thorns is cast: %s" % duel.error)
	for card: String in spells:
		if not duel.cast_free(0, card, [], false): check(false, "%s is cast: %s" % [card, duel.error])
	if spend: duel.heroes[0].mana = 0
	elif int(duel.heroes[0].mana) == 0: duel.heroes[0].mana = 3
	if not _until_turn_of(duel, 1): return null
	return duel

func _finish(duel: ELDuel) -> Dictionary:
	duel.script_damage(1, 999, 0)
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", "")), "charges": made.get("ConstructorArtefactCharges")}

func _recipe(profile: ELProfile) -> void:
	check(profile.texts.has("T_CUSTOM_ARTEFACT_WAND_OF_ETHER_HARVEST"), "the game's text has T_CUSTOM_ARTEFACT_WAND_OF_ETHER_HARVEST")
	for spells: Array in [["MNDP"], ["MNTP", "MNTP", "MNDW"]]:
		var duel := _prepare(profile, true, spells, true)
		if duel == null: return
		var state := _globals(duel)
		var result := _finish(duel)
		var most: String = "MNTP" if spells.size() > 1 else "MNDP"
		check(result.made and result.name == "T_CUSTOM_ARTEFACT_WAND_OF_ETHER_HARVEST" and result.spell == most,
			"thorns, %s and no ether left make the Wand of Ether Harvest (%s): %s [%s]" % [str(spells), most, str(result), state])
		check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
		duel.scripts.close()
	var cases := [
		["thorns only cast during the turn", false, ["MNDP"], true],
		["a healing spell that turn", true, ["MNDP", "HEAL"], true],
		["ether left over", true, ["MNDP"], false],
		["no ether spell", true, [], true],
	]
	for c: Array in cases:
		var duel := _prepare(profile, c[1], c[2], c[3])
		if duel == null: return
		var state := _globals(duel)
		var result := _finish(duel)
		check(not result.made, "%s: no Wand of Ether Harvest: %s [%s]" % [c[0], str(result), state])
		duel.scripts.close()
