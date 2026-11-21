extends SceneTree
## Headless check of the second game's hunger artifact recipe (tracker BA5;
## the shipped MT_E2_ARTEFACT_RECIPE_5 text repeats recipe 4's), run by the
## shipped artifact tracker (ArtifactTracker.scp) in real duels: the hero
## summons exactly one creature that never dies, casts exactly one hunger
## spell (Hunger, Raven Hunger or Crowd Hunger), and the enemy hero dies with
## at least five cards in its graveyard: the Wand of Hunger. A second summon,
## a second hunger spell, the creature's death or a graveyard of four make none.
##
##   godot --headless --path game --script ../tools/hunger_recipe_check.gd
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
	print("HUNGER RECIPE: %d failure(s)" % failures.size())
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

func _globals(duel: ELDuel) -> String:
	var g: Dictionary = duel.scripts.states[0].vm.globals
	return "cr_id=%s hung_used=%s recp_valid=%s enemy_grave=%d" % [str(g.get("ba5_cr_id")), str(g.get("ba5_hung_used")), str(g.get("ba5_recp_valid")), duel.heroes[1].grave.size()]

## The enemy hero dies; the tracker's result.
func _finish(duel: ELDuel) -> Dictionary:
	duel.script_damage(1, 999, 0)
	var made := duel.scripts.local_variables
	return {"made": made.get("ConstructorIsArtefact") == 1.0, "name": str(made.get("ConstructorArtefactName", "")), "spell": str(made.get("ConstructorArtefactSpell", "")), "charges": made.get("ConstructorArtefactCharges")}

## `summons` creatures of the hero, `hungers` hunger spells on the first, the
## enemy graveyard filled to `grave` cards; `kill` lets the creature die.
func _prepare(profile: ELProfile, summons: int, hungers: Array, grave: int, kill := false) -> ELDuel:
	var duel := _duel(profile)
	if duel == null: return null
	var first := -1
	for i in summons:
		var id := _summon(duel, 0, "SKEL" if profile.table("CombatSpells").has("SKEL") else _any_creature(profile))
		if first < 0: first = id
	for card: String in hungers:
		var target: Array = [first] if ELCatalog.rule(profile, card).get("target", "none") == "creature" else []
		if not duel.cast_free(0, card, target, false): check(false, "%s is cast: %s" % [card, duel.error])
	if kill and first >= 0 and duel.creatures.has(first): duel._kill(first)
	var grave_cards: Array = duel.heroes[1].grave
	while grave_cards.size() < grave: grave_cards.append("SKEL")
	while grave_cards.size() > grave: grave_cards.pop_back()
	return duel

func _any_creature(profile: ELProfile) -> String:
	for card: String in profile.table("CombatCreatures"):
		if profile.table("CombatSpells").has(card): return card
	return ""

func _recipe(profile: ELProfile) -> void:
	for key: String in ["T_CUSTOM_ARTEFACT_WAND_OF_HUNGER"]:
		check(profile.texts.has(key), "the game's text has %s" % key)
	for hunger: String in ["HUNG", "RVHG", "CRHG"]:
		var duel := _prepare(profile, 1, [hunger], 5)
		if duel == null: return
		var state := _globals(duel)
		var result := _finish(duel)
		check(result.made and result.name == "T_CUSTOM_ARTEFACT_WAND_OF_HUNGER" and result.spell == hunger,
			"one living creature, one %s and five enemy graves make the Wand of Hunger: %s [%s]" % [hunger, str(result), state])
		check(duel.scripts.notes.is_empty(), "no script errors: %s" % str(duel.scripts.notes))
		duel.scripts.close()
	var cases := [
		["two summoned creatures", 2, ["HUNG"], 5, false],
		["two hunger spells", 1, ["HUNG", "CRHG"], 5, false],
		["the creature died", 1, ["HUNG"], 5, true],
		["four enemy graves", 1, ["HUNG"], 4, false],
		["no hunger spell", 1, [], 5, false],
	]
	for c: Array in cases:
		var duel := _prepare(profile, c[1], c[2], c[3], c[4])
		if duel == null: return
		var state := _globals(duel)
		var result := _finish(duel)
		check(not result.made, "%s: no Wand of Hunger: %s [%s]" % [c[0], str(result), state])
		duel.scripts.close()
