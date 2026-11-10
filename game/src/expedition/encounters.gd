class_name ELExpeditionEncounters
extends RefCounted
## Opponents reuse the mounted Etherlords II campaign's mob definitions.

const BOSSES := [
	["e2mission31_41_51", "m41 - Worm Queen"],
	["e2mission23", "m23 - Mother Tick"],
	["e2mission34_44_54", "m54 - White Lord"],
]
const ALTERNATE_BOSSES := [
	[["e2mission13", "m13 - Bee Hive Boss"], 4, 21],
	[["e2mission24_32", "m24 - Red Dragon"], 5, 32],
]
const FIGHTS := [
	[
		["e2mission11", "m11 - Fingus Spitting"],
		["e2mission11", "m11 - Bee Warrior"],
		["e2mission21", "m21 - Stink Rat"],
		["e2mission21", "m21 - River Halo"],
		["e2mission31_41_51", "m41 - Bronze Abomination"],
	],
	[
		["e2mission22_53", "m22 - Disease Rat"],
		["e2mission22_53", "m22 - Magic Hornet"],
		["e2mission22_53", "m22 - Orc Guard"],
		["e2mission21", "m21 - Aviak Assassin"],
	],
	[
		["e2mission33", "m33 - Sorcerer2"],
		["e2mission33", "m33 - Shaman Spirit"],
		["e2mission33", "m33 - Bee Queen"],
		["e2mission43", "m43 - Wyrm"],
	],
]
const ELITES := [
	[
		["e2mission11", "m11 - Synth Boss"],
		["e2mission21", "m21 - KHero03"],
	],
	[
		["e2mission22_53", "m22 - SHero1"],
		["e2mission22_53", "m22 - KHero2"],
		["e2mission23", "m23 - Pale Reaper"],
	],
	[
		["e2mission33", "m33 - Lamia Warlord"],
		["e2mission43", "m43 - Fighter3"],
		["e2mission43", "m43 - Devourer3 (Boss)"],
	],
]
const BOSS_LEVELS := [3, 7, 7]
const BOSS_HEALTH := [19, 30, 45]
const BOSS_VARIABLES := [{"Adv_WormsCount": 2.0}, {"Adv_TickCount": 2.0}, {}]

## Returns a duel player specification for side 1. Arena and optional script
## keys are battle options. Health and mana levels are tuned to the run.
static func build(profile: ELProfile, kind: String, floor: int, seed: int, varied_guardians := false, met: Array[String] = []) -> Dictionary:
	if profile == null or profile.id != "el2" or kind not in ["fight", "elite", "boss"]: return {}
	var index := maxi(0, floor - 1)
	@warning_ignore("integer_division")
	var act := clampi(index / 6, 0, BOSSES.size() - 1)
	var offset := index % 6
	var arena_roll := (seed >> 9) ^ floor
	if kind == "boss":
		# A different seed bit from the one that chooses the opening side.
		if varied_guardians and act < ALTERNATE_BOSSES.size() and (seed & 0x100) != 0:
			var choice: Array = ALTERNATE_BOSSES[act]
			var alternate := _opponent(profile, choice[0], arena_roll)
			if not alternate.is_empty():
				alternate.level = choice[1]
				alternate.health = choice[2]
				return alternate
		var boss := _opponent(profile, BOSSES[act], arena_roll)
		if boss.is_empty(): return {}
		boss.health = BOSS_HEALTH[act]
		boss.level = BOSS_LEVELS[act]
		boss.script_variables = BOSS_VARIABLES[act].duplicate()
		# The final expedition boss keeps his original spells and wards. The
		# campaign's gentler script setting gives a drafted book time to act.
		if act == BOSSES.size() - 1: boss.script_difficulty = 0
		return boss
	var elite := kind == "elite"
	var pool: Array = ELITES[act] if elite else FIGHTS[act]
	var random := RandomNumberGenerator.new()
	random.seed = seed ^ (floor * 0x9e3779b9)
	var first := random.randi_range(0, pool.size() - 1)
	var fresh: Array = []
	var repeats: Array = []
	for i in pool.size():
		var source: Array = pool[(first + i) % pool.size()]
		if source[1] in met: repeats.append(source)
		else: fresh.append(source)
	fresh.append_array(repeats)
	for source: Array in fresh:
		var opponent := _opponent(profile, source, arena_roll)
		if opponent.is_empty(): continue
		@warning_ignore("integer_division")
		opponent.level = 1 + 2 * act + offset / 3 + int(elite)
		opponent.health = (14 + 8 * act if elite else 10 + 6 * act) + offset
		return opponent
	return {}

static func _opponent(profile: ELProfile, source: Array, arena_roll: int) -> Dictionary:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, source[0]): return {}
	var variants: Dictionary = map.mobs.get(source[1], {})
	var mob: Dictionary = variants.get(1, {})
	if mob.is_empty(): return {}
	var shape := String(mob.attrs.get("shape", ""))
	var shape_row: Dictionary = profile.table("Shapes").get(shape, {})
	var faction := String(shape_row.get("Color", ""))
	if not ELCatalog.faction_known(profile, faction): return {}
	var cards: Array[String] = []
	for spell: Dictionary in ELXml.children(ELXml.child(mob, "deck"), "spell"):
		var code := String(spell.attrs.get("code", ""))
		if ELCatalog.rule(profile, code).is_empty(): return {}
		cards.append(code)
	if cards.is_empty(): return {}
	var skills := {}
	for skill: Dictionary in ELXml.children(ELXml.child(mob, "skills"), "skill"):
		skills[String(skill.attrs.type)] = int(skill.attrs.level)
	var arena := faction + ".001"
	# White Lord begins offstage in the campaign. Keep the Expedition finale
	# in his citadel and use the source terrain for placed opponents elsewhere.
	if source != BOSSES.back():
		for placed: Dictionary in map.objects:
			if placed.name != source[1] or placed.group not in ["heroes", "np_heroes"]: continue
			if placed.x < 0 or placed.y < 0: continue
			arena = ELAdventureEncounter.second_terrain_arena(map, Vector2i(placed.x, placed.y), arena_roll)
			break
	if not profile.table("CombatSceneDB").has(arena): arena = "Green.001"
	var opponent := {
		"id": source[1], "title": profile.text(mob.attrs.get("ElkName", source[1])),
		"faction": faction, "hero": ELCatalog.default_hero(profile, faction), "shape": shape,
		"kind": "hero" if mob.attrs.get("IsHero", "0") == "1" else "monster",
		"cards": cards, "skills": skills, "specialization": String(mob.attrs.get("Spec", "NONE")),
		"arena": arena,
	}
	var script := String(mob.attrs.get("Script", ""))
	if not script.is_empty(): opponent.scripts = [{"name": script, "side": 1}]
	return opponent
