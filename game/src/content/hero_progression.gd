class_name ELHeroProgression
extends RefCounted
## Experience thresholds are edition data; level history prevents repeated
## skill awards when temporary experience penalties lower the effective level.
const MAX_LEVEL := 20
const LEARNING := {"el1": [0.25, 0.50, 1.0], "el2": [0.15, 0.30, 0.45]}

static func threshold(profile: ELProfile, level: int) -> int:
	return int(profile.table("HeroesStats").get("ExpNeeded", {}).get("Level%d" % clampi(level, 1, MAX_LEVEL), 0))

static func battle_reward(profile: ELProfile, level: int) -> int:
	return int(profile.table("HeroesStats").get("ExpForNPC", {}).get("Level%d" % clampi(level, 1, MAX_LEVEL), 0))

static func effective(hero: Dictionary) -> int:
	return maxi(0, int(float(hero.get("experience", 0)) - float(hero.get("experience_penalty", 0))))

static func level_for(profile: ELProfile, experience: int) -> int:
	var result := 1
	for level in range(2, MAX_LEVEL + 1):
		if experience < threshold(profile, level): break
		result = level
	return result

static func initialize(profile: ELProfile, hero: Dictionary, growth := 3) -> void:
	hero.level = clampi(int(hero.get("level", 1)), 1, MAX_LEVEL)
	hero.experience = threshold(profile, hero.level)
	hero.experience_penalty = 0.0
	hero.level_history = hero.level
	hero.skill_points = 0
	hero.skill_offers = []
	hero.health_growth = growth
	hero.health_base = int(hero.health) - hero.level * growth
	if not hero.has("skills"): hero.skills = {}
	recalculate_health(hero)

static func recalculate_health(hero: Dictionary) -> void:
	var health := int(hero.health_base) + int(hero.level) * int(hero.health_growth)
	var rank := int(hero.get("skills", {}).get("HEAL", -1))
	if rank >= 0 and rank < 3: health = int(float(health) * [1.1, 1.2, 1.3][rank] + 0.5)
	# First-game Healers' Citadels add a tenth per citadel held by the owner;
	# spring bonuses are added after that percentage.
	var healers := int(hero.get("citadel_bonus", [0, 0])[0])
	if healers > 0: health += int(health * healers * 0.1 + 0.5)
	for buff: Array in hero.get("temp_buffs", []): health += int(buff[0])
	hero.health = maxi(1, health)

static func award(profile: ELProfile, hero: Dictionary, amount: int) -> int:
	if amount <= 0 or hero.get("type") != "hero": return 0
	var rank := int(hero.get("skills", {}).get("LEAR", -1))
	# Original Learning bonuses are stored as single-precision values, and the
	# final award is truncated. Preserve boundary cases such as 100 * 1.45 = 144.
	var bonus := float(PackedFloat32Array([LEARNING[profile.id][rank]])[0]) if rank >= 0 and rank < 3 else 0.0
	var granted := int(float(PackedFloat32Array([amount])[0]) * (1.0 + bonus))
	var total := int(hero.experience) + granted
	var cap := threshold(profile, MAX_LEVEL)
	if total > cap:
		hero.experience_penalty = maxf(0, float(hero.get("experience_penalty", 0)) - (total - cap))
	hero.experience = mini(total, cap)
	var level := level_for(profile, effective(hero))
	var gained := maxi(0, level - int(hero.level_history))
	hero.level_history = maxi(int(hero.level_history), level)
	hero.skill_points = int(hero.skill_points) + gained
	hero.level = level
	recalculate_health(hero)
	ELHeroSkills.prepare(profile, hero)
	return granted
