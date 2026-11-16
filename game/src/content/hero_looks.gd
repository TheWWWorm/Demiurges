class_name ELHeroLooks
extends RefCounted
## Second-game campaign lords grow into a grander look as they gain levels, as
## in the original. A hero keeps a short list of shapes (Shapes rows); setting
## one of the lords' first shapes (by the map or ExSetHeroShape) lists the
## lord's later shapes after it, any other shape stands alone. The hero wears
## the list entry of its level step: the first below level 4, the second from
## 4, the third from 8 and the fourth from 12, or the last one listed. Each
## step changes the whole look: battle figure and skins, map figure, mount and
## portrait. A level lost again to colourless zones does not take it back.

## A lord's first shape and how many shapes its list holds ("-1", "-2", ...).
const LORDS := {"GreenMainHero-1": 3, "BlackMainHero-1": 3, "BlueMainHero-1": 3, "RedMainHero-1": 3, "DiamandaMainHero-1": 4}
## The lowest level of each step after the first.
const STEPS: Array[int] = [4, 8, 12]

## The shapes a hero set to `shape` wears from its lowest level step up.
static func shapes(shape: String) -> Array[String]:
	var result: Array[String] = [shape]
	var count := int(LORDS.get(shape, 1))
	var stem := shape.trim_suffix("1")
	for step in range(2, count + 1): result.append(stem + str(step))
	return result

## Which entry of a hero's shape list a level wears (0-3).
static func step(level: int) -> int:
	var result := 0
	for lowest: int in STEPS:
		if level >= lowest: result += 1
	return result

## The shape a hero set to `shape` wears at `level`; the set shape itself in
## the first game, below the first step, or when the later shape is missing
## from the installed Shapes table.
static func shape_at(profile: ELProfile, shape: String, level: int) -> String:
	if profile == null or profile.id != "el2" or not LORDS.has(shape): return shape
	var list := shapes(shape)
	var worn := list[mini(step(level), list.size() - 1)]
	return worn if profile.table("Shapes").has(worn) else shape

## The shape a map hero wears now (empty for heroes drawn from their template).
static func worn(profile: ELProfile, hero: Dictionary) -> String:
	var shape := str(hero.get("shape", ""))
	if shape.is_empty(): return shape
	var level := maxi(int(hero.get("level", 1)), int(hero.get("level_history", 0)))
	return shape_at(profile, shape, level)
