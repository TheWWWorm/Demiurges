extends SceneTree
## Headless check of the second game's cantrip artifact recipe (MT_E2_ARTEFACT_
## RECIPE_9, Rod of Cantrips), run by the shipped artifact tracker in real
## duels. The tracker (CHookBA9_*) counts every enchantment removal since the
## last turn start or Lesser Unsummon cast, adds that run to its total when the
## hero's Lesser Unsummon cast is reported, clears its "valid" flag on any spell
## of the hero's that is no cantrip (AVSC, LSDS, TWEN, ENFL, LSUS), and at the
## enemy hero's death wants it still valid with more than 3 removals in total.
##
##   godot --headless --path game --script ../tools/cantrips_recipe_check.gd

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
	print("CANTRIPS RECIPE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _duel(profile: ELProfile) -> ELDuel:
	var player := {"faction": "Black", "deck": ELCatalog.STARTERS.Black, "level": 6}
	var duel := ELDuel.new()
	if not duel.start(profile, 4100, {"players": [player, player.duplicate(true)], "scripts": [{"name": ELSecondArtifacts.TRACKER, "side": 0}], "script_variables": {"ConstructorIsArtefact": 0.0}}):
		check(false, "a duel with the artifact tracker starts: %s" % duel.error)
		return null
	if duel.scripts == null or duel.scripts.states.size() != 1:
		check(false, "the artifact tracker loads")
		return null
	duel.scripts.in_combat = true
	return duel

func _vm(duel: ELDuel) -> ELLuaVM:
	return duel.scripts.states[0].vm

func _made(duel: ELDuel) -> Dictionary:
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", ""))}

func _globals(duel: ELDuel) -> String:
	var vm := _vm(duel)
	return "valid=%s total=%s run=%s max=%s" % [vm.globals.get("ba9_valid"), vm.globals.get("ba9_disp_tot"), vm.globals.get("ba9_disp_in_row_cur"), vm.globals.get("ba9_disp_in_row_max")]

func _summon(duel: ELDuel, side: int, card: String) -> int:
	var before := duel.next_id
	if not duel.cast_free(side, card, [], false): check(false, "%s is summoned: %s" % [card, duel.error])
	return before if duel.creatures.has(before) else -1

## An enemy creature carrying `count` enchantments the enemy put on it
## (Enfeeblement-like cantrips cast by side 1), unsummoned by the hero's
## Lesser Unsummon.
func _unsummon_enchanted(duel: ELDuel, count: int) -> bool:
	var id := _summon(duel, 1, "AVSC")
	if id < 0: return false
	for i in count:
		if not duel.cast_free(1, "ENFL" if i % 2 == 0 else "TWEN", [id], false):
			check(false, "an enchantment goes on the enemy creature: %s" % duel.error)
			return false
	check(duel.creatures[id].enchantments.size() == count, "the enemy creature carries %d enchantments (%d)" % [count, duel.creatures[id].enchantments.size()])
	if not duel.cast_free(0, "LSUS", [id], false):
		check(false, "Lesser Unsummon is cast: %s" % duel.error)
		return false
	check(not duel.creatures.has(id), "Lesser Unsummon returns the creature")
	return true

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_9", "T_CUSTOM_ARTEFACT_ROD_OF_CANTRIPS"]:
		check(profile.texts.has(key), "the game's text has %s" % key)

	var duel := _duel(profile)
	if duel == null: return
	duel.scripts.turn_start(0, 2)
	_unsummon_enchanted(duel, 4)
	check(_vm(duel).globals.get("ba9_disp_tot") == 4.0, "the tracker counts four enchantments removed by Lesser Unsummon: %s" % _globals(duel))
	duel.script_damage(1, 999, 0)
	var result := _made(duel)
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_ROD_OF_CANTRIPS" and result.spell == "LSUS", "four enchantments removed by Lesser Unsummon give the Rod of Cantrips: %s (%s)" % [str(result), _globals(duel)])
	check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
	duel.scripts.close()

	# Two Lesser Unsummons of two enchantments each, on different turns.
	duel = _duel(profile)
	if duel == null: return
	duel.scripts.turn_start(0, 2)
	_unsummon_enchanted(duel, 2)
	duel.scripts.turn_start(1, 2)
	duel.scripts.turn_start(0, 3)
	_unsummon_enchanted(duel, 2)
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(result.made and result.spell == "LSUS", "two unsummons of two enchantments give the rod too: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()

	# Only three: no rod.
	duel = _duel(profile)
	if duel == null: return
	duel.scripts.turn_start(0, 2)
	_unsummon_enchanted(duel, 3)
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(not result.made, "three enchantments give no rod: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()

	# A spell that is no cantrip: no rod.
	duel = _duel(profile)
	if duel == null: return
	duel.scripts.turn_start(0, 2)
	_unsummon_enchanted(duel, 4)
	if not duel.cast_free(0, "MGHT", [], false): duel.cast_free(0, "HEAL", [0], false)
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(not result.made and _vm(duel).globals.get("ba9_valid") == null, "a spell that is no cantrip gives no rod: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()
