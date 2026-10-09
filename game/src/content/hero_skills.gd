class_name ELHeroSkills
extends RefCounted
## Persist the offer, rather than drawing new choices each time the panel opens.
const MAX_SKILLS := 5
const MAX_RANK := 2

static func from_template(profile: ELProfile, template: Dictionary) -> Dictionary:
	var result := {}
	var values: Variant = template.get("Skills", [])
	if values is String: values = [values]
	for entry: String in values:
		if entry.contains("("):
			var code := entry.left(4)
			var rank := int(entry.get_slice("(", 1).trim_suffix(")")) - 1
			# Original IDs occupy four bytes. Ignore unregistered authored entries;
			# a misspelled skill must not acquire another skill's effect.
			if not definition(profile, code, rank).is_empty(): result[code] = rank
	return result

static func valid_ranks(profile: ELProfile, value: Variant) -> bool:
	# Authored heroes may hold more than the learnable maximum (EL2 chapter 13's dragon has six).
	if not value is Dictionary or value.size() > 64: return false
	for code: Variant in value:
		if not code is String or not ELLuaSave._integer(value[code], 0, MAX_RANK): return false
		if definition(profile, code, int(value[code])).is_empty(): return false
	return true

static func definition(profile: ELProfile, code: String, rank: int) -> Dictionary:
	for row: Dictionary in profile.table("HeroesSkills").values():
		if row.get("Code") == code and int(row.get("Level", 0)) == rank + 1: return row
	return {}

## Every registered skill not marked out of use. The first game also offers
## Ethereal Attack (ETAT) and Counterstrike (ETDF); the original applies neither,
## so they only occupy a skill slot. Their descriptions promise castle damage, but
## castle damage stays the hero's value (see ELFirstScenario.hero_value).
static func available(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in profile.table("HeroesSkills").values():
		var code := str(row.get("Code", ""))
		if row.get("InUse", "True") == "True" and not code.is_empty() and not result.has(code): result.append(code)
	result.sort()
	return result

static func candidates(profile: ELProfile, hero: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var skills: Dictionary = hero.get("skills", {})
	for code: String in available(profile):
		var rank := int(skills.get(code, -1))
		if rank < MAX_RANK and (rank >= 0 or skills.size() < MAX_SKILLS): result.append(code)
	return result

static func prepare(profile: ELProfile, hero: Dictionary) -> Array:
	if not hero.has("skill_offers"): hero.skill_offers = []
	if int(hero.get("skill_points", 0)) <= 0:
		hero.skill_offers.clear()
		return hero.skill_offers
	if not hero.skill_offers.is_empty(): return hero.skill_offers
	var pool := candidates(profile, hero)
	if pool.is_empty():
		hero.skill_points = 0
		return hero.skill_offers
	# EL1 draws all three offers normally; EL2 prioritizes the Resources skill.
	if profile.id == "el2" and pool.has("PRVD") and not hero.skills.has("PRVD"):
		hero.skill_offers.append("PRVD")
		pool.erase("PRVD")
	var seed_number := int(hero.get("skill_seed", int(hero.get("uid", 0)) ^ 212)) & 0xffffffff
	while hero.skill_offers.size() < 3 and not pool.is_empty():
		seed_number = (seed_number * 214013 + 2531011) & 0xffffffff
		var index := ((seed_number >> 16) & 0x7fff) % pool.size()
		hero.skill_offers.append(pool[index])
		pool.remove_at(index)
	hero.skill_seed = seed_number
	return hero.skill_offers

static func choose(profile: ELProfile, hero: Dictionary, code: String) -> String:
	if int(hero.get("skill_points", 0)) <= 0 or not hero.get("skill_offers", []).has(code): return "Choose one of the offered skills."
	if not candidates(profile, hero).has(code): return "That skill cannot be improved."
	hero.skills[code] = int(hero.skills.get(code, -1)) + 1
	hero.skill_points -= 1
	hero.skill_offers = []
	ELHeroProgression.recalculate_health(hero)
	if profile.id == "el1" and hero.has("strategy_version"): ELStrategy.recalculate(hero)
	prepare(profile, hero)
	return ""

static func restore(profile: ELProfile, hero: Dictionary) -> bool:
	# Old checkpoints have earned points but no persisted offer yet.
	if not hero.has("skill_offers"):
		prepare(profile, hero)
		return true
	if not hero.skill_offers is Array or hero.skill_offers.size() > 3: return false
	if hero.has("skill_seed") and not ELLuaSave._integer(hero.skill_seed, 0, 0xffffffff): return false
	var pool := candidates(profile, hero)
	var seen := {}
	for code: Variant in hero.skill_offers:
		if not code is String or not pool.has(code) or seen.has(code): return false
		seen[code] = true
	if hero.skill_points <= 0 and not hero.skill_offers.is_empty(): return false
	if hero.skill_points > 0 and hero.skill_offers.is_empty(): return false
	if hero.skill_points > 0:
		if hero.skill_offers.size() != mini(3, pool.size()): return false
		if profile.id == "el2" and pool.has("PRVD") and not hero.skills.has("PRVD") and not hero.skill_offers.has("PRVD"): return false
	return true
