extends SceneTree
## Headless check of the second game's Halo artifact recipe (MT_E2_ARTEFACT_
## RECIPE_7, Rod of Halos), run by the shipped artifact tracker in real duels.
## The tracker (CHookBA7_*) records the enemy's ether at the hero's turn start,
## adds what a creature ability with index 0 took from it (the Halos' Ethereal
## Thief), keeps a table of the hero's summoned creatures (by summon card) less
## the dead, and at the enemy hero's death wants some ether drained, one Halo
## of each type (RVHL, SEHL, SWHL) alive and no other summoned creature.
##
##   godot --headless --path game --script ../tools/halos_recipe_check.gd

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
	print("HALOS RECIPE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _duel(profile: ELProfile) -> ELDuel:
	var player := {"faction": "Blue", "deck": ELCatalog.STARTERS.Blue, "level": 6}
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
	var table: Variant = vm.globals.get("ba7_crtable")
	var rows := []
	if table is ELLuaVM.Table:
		for key: Variant in (table as ELLuaVM.Table).values:
			var row: Variant = (table as ELLuaVM.Table).values[key]
			if row is ELLuaVM.Table: rows.append([key, (row as ELLuaVM.Table).values.get("id"), (row as ELLuaVM.Table).values.get("free_data")])
			else: rows.append([key, row])
	return "drain=%s enemy_mana=%s table=%s" % [vm.globals.get("ba7_manadrain"), vm.globals.get("ba7_enemy_mana"), str(rows)]

func _summon(duel: ELDuel, side: int, card: String) -> int:
	var before := duel.next_id
	if not duel.cast_free(side, card, [], false): check(false, "%s is summoned: %s" % [card, duel.error])
	return before if duel.creatures.has(before) else -1

## One Halo of each type summoned; with `drain`, one Halo steals ether at the
## hero's turn; with `extra`, another creature of the hero's stays alive.
func _scenario(profile: ELProfile, drain: bool, extra: String) -> ELDuel:
	var duel := _duel(profile)
	if duel == null: return null
	var halos: Array[int] = []
	for card: String in ["RVHL", "SEHL", "SWHL"]: halos.append(_summon(duel, 0, card))
	if extra != "":
		var other := _summon(duel, 0, extra.trim_suffix("!"))
		# "!": that creature dies before the end, leaving the tracker's table.
		if extra.ends_with("!") and other >= 0: duel._kill(other)
	duel.heroes[1].mana = 10
	duel.attacker = 0
	duel.scripts.turn_start(0, 2)
	if drain and halos[0] >= 0:
		var halo: Dictionary = duel.creatures[halos[0]]
		halo.sick = false
		var keys := duel.abilities(halos[0]).map(func(a: Dictionary) -> String: return a.key)
		if not duel.use_ability(halos[0], "siphon"): check(false, "the Halo's Ethereal Thief is used: %s (abilities %s)" % [duel.error, str(keys)])
		else: check(keys.find("siphon") == 0, "Ethereal Thief is the Halo's first ability (index 0): %s" % str(keys))
	duel.script_damage(1, 999, 0)
	return duel

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_7", "T_CUSTOM_ARTEFACT_ROD_OF_HALOS"]:
		check(profile.texts.has(key), "the game's text has %s" % key)

	var duel := _scenario(profile, true, "")
	if duel == null: return
	var result := _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and duel.winner == 0, "the enemy hero dies")
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_ROD_OF_HALOS" and result.spell in ["RVHL", "SEHL", "SWHL"], "three Halos and a drain give the Rod of Halos: %s (%s, enemy ether %d)" % [str(result), _globals(duel), int(duel.heroes[1].mana)])
	check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
	duel.scripts.close()

	duel = _scenario(profile, false, "")
	if duel == null: return
	result = _made(duel)
	check(not result.made, "no ether drained gives no rod: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()

	duel = _scenario(profile, true, "AVSC")
	if duel == null: return
	result = _made(duel)
	check(not result.made, "another living creature of the hero's gives no rod: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()

	duel = _scenario(profile, true, "AVSC!")
	if duel == null: return
	result = _made(duel)
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_ROD_OF_HALOS", "another creature that died first leaves the rod: %s (%s)" % [str(result), _globals(duel)])
	duel.scripts.close()
