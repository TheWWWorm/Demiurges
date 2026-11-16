extends SceneTree
## Headless check of the second game's first artifact recipe, run by the
## shipped artifact tracker (ArtifactTracker.scp) in real duels:
## - one Pteros, purified of an enchantment and dead by the end, gives the
##   Wand of Purify; alive, it gives the Rod of Pteroses;
## - a second Pteros (or Reinforced Pteros) summoned breaks the recipe's "one
##   and only one" condition, and no artifact is made (the original's text
##   promises this, its tracker never checks it);
## - the check survives a snapshot and restore, also of a state saved before
##   it existed, and the tracker's other recipes keep their own end steps.
##
##   godot --headless --path game --script ../tools/purify_recipe_check.gd
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
	print("PURIFY RECIPE: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _duel(profile: ELProfile) -> ELDuel:
	var player := {"faction": "Black", "deck": ELCatalog.STARTERS.Black, "level": 6}
	var duel := ELDuel.new()
	# The adventure side sets ConstructorIsArtefact to 0 before a battle; the
	# tracker fills the Constructor* variables when it makes an artifact.
	if not duel.start(profile, 4100, {"players": [player, player.duplicate(true)], "scripts": [{"name": ELSecondArtifacts.TRACKER, "side": 0}], "script_variables": {"ConstructorIsArtefact": 0.0}}):
		check(false, "a duel with the artifact tracker starts: %s" % duel.error)
		return null
	if duel.scripts == null or duel.scripts.states.size() != 1:
		check(false, "the artifact tracker loads: %s" % (str(duel.scripts.notes) if duel.scripts != null else "no scripts"))
		return null
	duel.scripts.in_combat = true
	return duel

func _summon(duel: ELDuel, card: String) -> int:
	var before := duel.next_id
	if not duel.cast_free(0, card, [], false): check(false, "%s is summoned: %s" % [card, duel.error])
	return before if duel.creatures.has(before) else -1

## Enchants the creature with Might, then purifies it of that enchantment.
func _purify(duel: ELDuel, id: int) -> void:
	if id < 0: return
	if not duel.cast_free(0, "MGHT", [id], false):
		check(false, "Might goes on the Pteros: %s" % duel.error)
		return
	var enchantments: Array = duel.creatures[id].enchantments
	if enchantments.is_empty():
		check(false, "the Pteros carries Might")
		return
	if not duel.cast_free(0, "PRFY", [id, int(enchantments[-1].id)], false): check(false, "Purify is cast on the Pteros: %s" % duel.error)

func _artifact(duel: ELDuel) -> Dictionary:
	duel.script_damage(1, 999, 0)
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", "")), "charges": made.get("ConstructorArtefactCharges")}

func _vm(duel: ELDuel) -> ELLuaVM:
	return duel.scripts.states[0].vm

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_1", "T_CUSTOM_ARTEFACT_WAND_OF_PURIFY", "T_CUSTOM_ARTEFACT_ROD_OF_PTEROSES"]:
		check(profile.texts.has(key), "the game's text has %s" % key)
	# The tracker as shipped: the flag is a variable its summon hook clears.
	var duel := _duel(profile)
	if duel == null: return
	var vm := _vm(duel)
	check(vm.globals.get(ELBattleScripts.RECIPE_VALID) == 1.0, "the tracker's init sets ba1_isReceipeValid")
	check(vm.globals.get(ELBattleScripts.RECIPE_GRANT) is ELLuaVM.Native and duel.scripts.states[0].get("recipe_grant") is ELLuaVM.Closure, "the recipe's end step is guarded, the tracker's own function kept")
	for other in range(2, 10):
		check(vm.globals.get("CHookBA%d_OnVisualHeroDeath" % other) is ELLuaVM.Closure, "recipe %d keeps its own end step" % other)
	check(duel.scripts.states[0].hooks.has("CHook_OnVisualHeroDeath"), "the tracker's hero death hook is still bound")

	# One Pteros, purified, then dead: the Wand of Purify.
	var id := _summon(duel, "PTRS")
	_purify(duel, id)
	check(vm.globals.get("ba1_de_num") == 1.0, "the tracker counts the purified enchantment: %s" % str(vm.globals.get("ba1_de_num")))
	duel._kill(id)
	var result := _artifact(duel)
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_WAND_OF_PURIFY" and result.spell == "PRFY", "one dead Pteros gives the Wand of Purify: %s" % str(result))
	check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
	duel.scripts.close()

	# One Pteros alive at the end: the Rod of Pteroses.
	duel = _duel(profile)
	if duel == null: return
	id = _summon(duel, "PTRS")
	_purify(duel, id)
	result = _artifact(duel)
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_ROD_OF_PTEROSES" and result.spell == "PTRS", "one living Pteros gives the Rod of Pteroses: %s" % str(result))
	duel.scripts.close()

	# A second Pteros after the first died: no Wand.
	duel = _duel(profile)
	if duel == null: return
	vm = _vm(duel)
	id = _summon(duel, "PTRS")
	_purify(duel, id)
	duel._kill(id)
	_summon(duel, "PTRS")
	check(vm.globals.get(ELBattleScripts.RECIPE_VALID) == null, "a second Pteros clears ba1_isReceipeValid")
	check(vm.globals.get("ba1_pt_summoned") == 1.0 and vm.globals.get("ba1_de_num") == 1.0 and vm.globals.get("ba1_pt_id") == null, "the tracker's own record still reads as a dead, purified Pteros")
	result = _artifact(duel)
	check(not result.made and result.name.is_empty(), "two Pteroses give no Wand of Purify: %s" % str(result))
	duel.scripts.close()

	# A Reinforced Pteros next to a living Pteros: no Rod either.
	duel = _duel(profile)
	if duel == null: return
	id = _summon(duel, "PTRS")
	_purify(duel, id)
	_summon(duel, "RFPT")
	result = _artifact(duel)
	check(not result.made, "a Pteros and a Reinforced Pteros give no Rod: %s" % str(result))
	duel.scripts.close()

	# Snapshot and restore keep the check, both ways.
	duel = _duel(profile)
	if duel == null: return
	id = _summon(duel, "PTRS")
	_purify(duel, id)
	duel._kill(id)
	_summon(duel, "PTRS")
	var saved := duel.scripts.snapshot()
	check(ELBattleScripts.valid(profile, saved), "the saved script state passes the save check")
	var again := ELBattleScripts.new(duel)
	check(again.restore(JSON.parse_string(JSON.stringify(saved))).is_empty(), "the saved script state restores")
	duel.scripts.close()
	duel.scripts = again
	check(_vm(duel).globals.get(ELBattleScripts.RECIPE_GRANT) is ELLuaVM.Native, "the restored tracker is still guarded")
	result = _artifact(duel)
	check(not result.made, "after a restore two Pteroses still give no Wand: %s" % str(result))
	duel.scripts.close()

	duel = _duel(profile)
	if duel == null: return
	id = _summon(duel, "PTRS")
	_purify(duel, id)
	duel._kill(id)
	# A state saved before the check existed holds the tracker's own function.
	var state: Dictionary = duel.scripts.states[0]
	state.vm.globals[ELBattleScripts.RECIPE_GRANT] = state.recipe_grant
	saved = duel.scripts.snapshot()
	again = ELBattleScripts.new(duel)
	check(again.restore(JSON.parse_string(JSON.stringify(saved))).is_empty(), "an older saved script state restores")
	duel.scripts.close()
	duel.scripts = again
	check(_vm(duel).globals.get(ELBattleScripts.RECIPE_GRANT) is ELLuaVM.Native, "an older saved tracker is guarded after the restore")
	result = _artifact(duel)
	check(result.made and result.name == "T_CUSTOM_ARTEFACT_WAND_OF_PURIFY", "after a restore one dead Pteros still gives the Wand: %s" % str(result))
	duel.scripts.close()
