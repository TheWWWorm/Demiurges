extends SceneTree
## Headless check of the second game's venom artifact recipe (MT_E2_ARTEFACT_
## RECIPE_8, Rod of Venom), run by the shipped artifact tracker in real duels.
## The tracker (CHookBA8_*) reads the enemy hero's health at each end-of-turn
## enchantment's start hook and adds the loss to that enchantment's poison type
## at its finish hook; at the enemy hero's death it wants more than half the
## health the enemy had at the first turn start lost to poisons, and the last
## enchantment started to be a poison. The original wraps each enchantment's
## end-of-turn callback in its own start/finish pair.
##
##   godot --headless --path game --script ../tools/venom_recipe_check.gd

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
	print("VENOM RECIPE: %d failure(s)" % failures.size())
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
	var damage: Variant = vm.globals.get("ba8_poison_dmg")
	var table := {}
	if damage is ELLuaVM.Table: table = (damage as ELLuaVM.Table).values
	return "start=%s cur=%s pt=%s dmg=%s" % [vm.globals.get("ba8_enemy_hp_start"), vm.globals.get("ba8_enemy_cur_hp"), vm.globals.get("ba8_pt"), str(table)]

func _summon(duel: ELDuel, side: int, card: String) -> int:
	var before := duel.next_id
	if not duel.cast_free(side, card, [], false): check(false, "%s is summoned: %s" % [card, duel.error])
	return before if duel.creatures.has(before) else -1

## The enemy hero's health, also as the tracker's battle-start reading (its
## first turn-start hook ran when the duel began, at full health).
func _enemy_starts_at(duel: ELDuel, health: int) -> void:
	duel.heroes[1].health = health
	_vm(duel).globals["ba8_enemy_hp_start"] = float(health)

## The hero's turn end: end-of-turn enchantments, then the winner.
func _end_turn(duel: ELDuel) -> void:
	duel.attacker = 0
	duel._turn_enchantments(false)
	duel._check_winner()

## Strong Toxin on the enemy hero (3 a turn end of the hero's), the enemy at 4
## when the turns start: two turn ends kill it, all by venom. With `twist`, a
## Twisted Enhancement on a creature of the hero's, cast after the toxin, ends
## its turns after it (a cantrip whose end-of-turn hook does nothing here).
func _scenario(profile: ELProfile, twist: String) -> ELDuel:
	var duel := _duel(profile)
	if duel == null: return null
	var creature := -1
	if twist != "":
		creature = _summon(duel, 0, "AVSC")
	if twist == "before" and creature >= 0 and not duel.cast_free(0, "TWEN", [creature], false): check(false, "Twisted Enhancement goes on: %s" % duel.error)
	if not duel.cast_free(0, "STTX", [], false): check(false, "Strong Toxin is cast: %s" % duel.error)
	if twist == "after" and creature >= 0 and not duel.cast_free(0, "TWEN", [creature], false): check(false, "Twisted Enhancement goes on: %s" % duel.error)
	_enemy_starts_at(duel, 4)
	duel.scripts.turn_start(0, 1)
	_end_turn(duel)
	duel.scripts.turn_start(1, 1)
	duel.scripts.turn_start(0, 2)
	_end_turn(duel)
	return duel

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_8", "T_CUSTOM_ARTEFACT_ROD_OF_VENOM"]:
		check(profile.texts.has(key), "the game's text has %s" % key)

	var duel := _scenario(profile, "")
	if duel == null: return
	var result := _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and duel.winner == 0, "Strong Toxin kills the enemy hero (health %d)" % int(duel.heroes[1].health))
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_ROD_OF_VENOM" and result.spell == "STTX", "a hero killed only by Strong Toxin gives the Rod of Venom: %s (%s)" % [str(result), _globals(duel)])
	check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
	duel.scripts.close()

	# Another end-of-turn enchantment started before the toxin: still a rod.
	duel = _scenario(profile, "before")
	if duel == null: return
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and result.made and result.spell == "STTX", "an earlier Twisted Enhancement keeps the Rod of Venom: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()

	# One started after the toxin, in the same turn ends: the original's pair
	# per enchantment still counts the toxin's damage and its death.
	duel = _scenario(profile, "after")
	if duel == null: return
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and result.made and result.spell == "STTX", "a later Twisted Enhancement keeps the Rod of Venom: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()

	# Less than half the enemy's health lost to venom, then killed by other
	# damage: no rod.
	duel = _duel(profile)
	if duel == null: return
	duel.cast_free(0, "STTX", [], false)
	_enemy_starts_at(duel, 8)
	duel.scripts.turn_start(0, 1)
	_end_turn(duel)
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and not result.made, "3 of 8 health lost to venom, then other damage, gives no rod: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()
