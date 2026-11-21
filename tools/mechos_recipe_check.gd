extends SceneTree
## Headless check of the second game's Mechos artifact recipe (MT_E2_ARTEFACT_
## RECIPE_3, the tracker's BA2), run by the shipped artifact tracker
## (ArtifactTracker.scp) in real duels: the hero summons one of each Mechos
## (Brass, Iron, Steel), a Mechos's Destroy finishes an enemy creature after a
## real fight, and the enemy hero then dies: the Rod of Mechoses. No Destroy
## kill, or a Mechos type missing at the end, makes none.
##
##   godot --headless --path game --script ../tools/mechos_recipe_check.gd
##
## It needs the second game's files (user://profiles.json); without them it is
## skipped.

const MECHOS := ["BRMC", "IRMC", "STMC"]

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
	print("MECHOS RECIPE: %d failure(s)" % failures.size())
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

func _summon(duel: ELDuel, side: int, card: String) -> int:
	var before := duel.next_id
	if not duel.cast_free(side, card, [], false): check(false, "%s is summoned: %s" % [card, duel.error])
	return before if duel.creatures.has(before) else -1

## A non-Wall creature that outlives a Mechos's blow and barely hurts it back:
## the most toughness over power, toughness above the Mechos's power.
func _sturdy(profile: ELProfile, duel: ELDuel, mechos: int) -> String:
	var best := ""
	var best_margin := -1000
	var power := int(duel.creatures[mechos].power)
	for card: String in profile.table("CombatCreatures"):
		if not profile.table("CombatSpells").has(card) or card in MECHOS: continue
		var row: Dictionary = profile.table("CombatCreatures")[card]
		if str(row.get("Race", "")) == "Wall": continue
		var toughness := int(row.get("Toughness", row.get("Defence", 0)))
		var attack := int(row.get("Power", row.get("Attack", 0)))
		if toughness <= power: continue
		var margin := toughness - attack * 2
		if margin > best_margin:
			best = card
			best_margin = margin
	return best

func _vm(duel: ELDuel) -> ELLuaVM:
	return duel.scripts.states[0].vm

func _made(duel: ELDuel) -> Dictionary:
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", "")), "charges": made.get("ConstructorArtefactCharges")}

## The tracker's Mechos record: living ids per type and the Destroy kills.
func _record(duel: ELDuel) -> String:
	var vm := _vm(duel)
	var mech: Variant = vm.globals.get("ba2_mech")
	var rows := []
	if mech is ELLuaVM.Table:
		var count := int((mech as ELLuaVM.Table).values.get("count", 0.0))
		for i in count:
			var row: Variant = (mech as ELLuaVM.Table).values.get(float(i))
			if row is ELLuaVM.Table: rows.append([(row as ELLuaVM.Table).values.get("type"), (row as ELLuaVM.Table).values.get("id")])
	return "mech=%s dcount=%s destroy_flag=%s" % [str(rows), str(vm.globals.get("ba2_dcount")), str(vm.globals.get("bCreatureKilledByDestroy"))]

## Brings the duel to side 0's own attack phase.
func _to_own_attack(duel: ELDuel) -> bool:
	for i in 12:
		if duel.phase == ELDuel.Phase.FINISHED: return false
		if duel.attacker == 0 and duel.phase == ELDuel.Phase.ATTACK: return true
		if not duel.end_phase():
			check(false, "a phase ends: %s" % duel.error)
			return false
	return false

## A real fight: `mechos` attacks, `blocker` blocks it; true once it is over.
func _fight(duel: ELDuel, mechos: int, blocker: int) -> bool:
	if not _to_own_attack(duel): return false
	duel.creatures[mechos].sick = false
	if not duel.toggle_attack(mechos):
		check(false, "the Mechos attacks: %s" % duel.error)
		return false
	if not duel.end_phase():
		check(false, "the attack is declared: %s" % duel.error)
		return false
	# Summoned this turn: the blocker stands ready, as one from an earlier turn.
	duel.creatures[blocker].sick = false
	duel.creatures[blocker].resting = false
	if not duel.assign_block(blocker, mechos):
		check(false, "the enemy creature blocks the Mechos: %s" % duel.error)
		return false
	if not duel.end_phase():
		check(false, "the fight is fought: %s" % duel.error)
		return false
	return true

## All three Mechos, the Iron one fighting `blocker_card`; `fight` false skips
## the fight, `types` the Mechos summoned.
func _prepare(profile: ELProfile, types: Array, fight: bool) -> ELDuel:
	var duel := _duel(profile)
	if duel == null: return null
	var ids := {}
	if not _to_own_attack(duel): return null
	for card: String in types: ids[card] = _summon(duel, 0, card)
	if not fight: return duel
	var attacker: int = ids.get("IRMC", ids.values()[0])
	var card := _sturdy(profile, duel, attacker)
	if card.is_empty():
		check(false, "the second game has a creature to block a Mechos")
		return null
	var blocker := _summon(duel, 1, card)
	var toughness := int(duel.creatures[blocker].toughness)
	if not _fight(duel, attacker, blocker): return null
	check(not duel.creatures.has(blocker), "the %s blocker (toughness %d) is destroyed after the fight: %s" % [card, toughness, _record(duel)])
	# A Mechos that fell in the fight is summoned again: the recipe asks for
	# each type under the hero's control at the end.
	for type: String in types:
		if not duel.creatures.has(int(ids[type])): _summon(duel, 0, type)
	return duel

func _recipe(profile: ELProfile) -> void:
	for key: String in ["MT_E2_ARTEFACT_RECIPE_3", "T_CUSTOM_ARTEFACT_ROD_OF_MECHOSES"]:
		check(profile.texts.has(key), "the game's text has %s" % key)

	# The recipe in full.
	var duel := _prepare(profile, MECHOS, true)
	if duel == null: return
	check(_vm(duel).globals.get("ba2_dcount") == 1.0, "the tracker counts one Destroy kill: %s" % _record(duel))
	duel.script_damage(1, 999, 0)
	var result := _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and result.made and result.name == "T_CUSTOM_ARTEFACT_ROD_OF_MECHOSES" and result.spell in MECHOS,
		"three Mechos and a Destroy kill make the Rod of Mechoses: %s (%s)" % [str(result), _record(duel)])
	check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
	duel.scripts.close()

	# No Destroy kill: no rod.
	duel = _prepare(profile, MECHOS, false)
	if duel == null: return
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and not result.made, "three Mechos without a Destroy kill make no rod: %s" % str(result))
	duel.scripts.close()

	# The Steel Mechos missing: no rod.
	duel = _prepare(profile, ["BRMC", "IRMC"], true)
	if duel == null: return
	duel.script_damage(1, 999, 0)
	result = _made(duel)
	check(duel.phase == ELDuel.Phase.FINISHED and not result.made, "two Mechos types and a Destroy kill make no rod: %s (%s)" % [str(result), _record(duel)])
	duel.scripts.close()
