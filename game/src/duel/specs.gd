class_name ELSpecs
extends RefCounted
## Hero specialisations in duels. Each hero carries one code; a hooked event
## rolls on the duel's own random sequence: one draw per trial, plus one more
## per point of difference between the hero's luck (Mastery) and the
## opponent's suppression, keeping the best (luck) or worst (suppression).
## A trial succeeds below the code's chance class for the hero's battle level.

const CLASSES := {"ulow": "SpecChanceULow", "low": "SpecChanceLow", "med": "SpecChanceMed", "high": "SpecChanceHigh"}

static func valid(profile: ELProfile, code: Variant) -> bool:
	return code is String and (code == "NONE" or profile.table("HeroesSpecs").has(code))

## The success chance of `code` at a battle level (1-20).
static func chance(profile: ELProfile, code: String, level: int) -> float:
	var row: Dictionary = profile.table("HeroesSpecs").get(code, {})
	var table := String(CLASSES.get(String(row.get("Chance", "")).to_lower(), ""))
	if table.is_empty(): return 0.0
	return float(profile.table("HeroesStats")[table].get("Level%d" % clampi(level, 1, 20), 0.0))

## Fills the duel hero's specialisation fields from a player choice.
static func prepare(hero: Dictionary, choice: Dictionary) -> void:
	hero.spec = String(choice.get("specialization", "NONE"))
	hero.spec_level = clampi(int(choice.get("spec_level", hero.level)), 1, 20)
	# Mastery and suppression ranks; the Luck and Suppression global spells give
	# two only to a hero without the skill.
	var skills: Dictionary = hero.get("skills", {})
	hero.luck = int(skills.MSTR) + 1 if skills.has("MSTR") else (2 if choice.get("luck_spell", false) else 0)
	hero.suppression = int(skills.SUPR) + 1 if skills.has("SUPR") else (2 if choice.get("suppression_spell", false) else 0)

## Successes out of `trials` for the side's hero, if it holds `code`. A hero
## without that specialisation draws nothing. Successes are announced.
static func roll(d: ELDuel, side: int, code: String, trials := 1, announce := true) -> int:
	var hero: Dictionary = d.heroes[side]
	if hero.get("spec", "NONE") != code or not d.setup.get("specs", true) or trials <= 0: return 0
	var threshold := chance(d.profile, code, int(hero.get("spec_level", hero.level)))
	# Second-game lookahead copies take the expected count without drawing,
	# from the hero's sampled successes per hundred (`sample_expectation`); a
	# success counts once the expectation reaches nine tenths. Five
	# specialisations are never expected.
	if d.expected_specs:
		if code in UNEXPECTED: return 0
		var percent := int(d.spec_expect[side]) if d.spec_expect.size() == 2 else int(threshold * 100.0)
		return (percent * trials + 10) / 100
	var difference := int(hero.get("luck", 0)) - int(d.heroes[1 - side].get("suppression", 0))
	var hits := 0
	for trial in trials:
		var r := _next(d)
		for extra in absi(difference):
			var other := _next(d)
			r = minf(r, other) if difference > 0 else maxf(r, other)
		if r < threshold: hits += 1
	if hits > 0 and announce: d._emit({"kind": "spec", "side": side, "spec": code, "count": hits})
	return hits

static func _next(d: ELDuel) -> float:
	d.rng_state = (d.rng_state * 0x343fd + 0x269ec3) & 0xffffffff
	return float((d.rng_state >> 16) & 0x7fff) / 32767.0

## Specialisations a lookahead never expects to succeed.
const UNEXPECTED := ["RVVE", "ATMF", "IRSK", "DRSK", "DRSL"]

## Successes per hundred trials for each hero, as the second game's think
## samples them before searching: a hundred trials of the real
## roll for hero 0, then for hero 1, on a copy of the random sequence, which
## the duel keeps unchanged. Every hero draws; NONE has its own table row.
static func sample_expectation(d: ELDuel) -> Array[int]:
	var result: Array[int] = [0, 0]
	if not d.setup.get("specs", true): return result
	var state := d.rng_state
	for side in 2:
		var hero: Dictionary = d.heroes[side]
		var code := String(hero.get("spec", "NONE"))
		var threshold := chance(d.profile, code, int(hero.get("spec_level", hero.level)))
		var difference := int(hero.get("luck", 0)) - int(d.heroes[1 - side].get("suppression", 0))
		for trial in 100:
			state = (state * 0x343fd + 0x269ec3) & 0xffffffff
			var r := float((state >> 16) & 0x7fff) / 32767.0
			for extra in absi(difference):
				state = (state * 0x343fd + 0x269ec3) & 0xffffffff
				var other := float((state >> 16) & 0x7fff) / 32767.0
				r = minf(r, other) if difference > 0 else maxf(r, other)
			if r < threshold: result[side] += 1
	return result

## The AI's expectation, without touching the duel's random sequence.
static func expected(d: ELDuel, side: int, code: String) -> float:
	var hero: Dictionary = d.heroes[side]
	if hero.get("spec", "NONE") != code: return 0.0
	return chance(d.profile, code, int(hero.get("spec_level", hero.level)))

## Dragon skin is remapped by campaign difficulty when a hero is created:
## Ancient magic on the two easiest settings, Lord skin on the next two.
static func remap(code: String, difficulty: int) -> String:
	if code != "DRSK": return code
	if difficulty <= 1: return "ATMF"
	if difficulty <= 3: return "DRSL"
	return code

## Second-game difficulty moves specialisation levels: the local side +2 and
## the opponent -1 on the easiest setting, the opponent +2 on the hardest.
static func second_levels(levels: Array[int], difficulty: int) -> Array[int]:
	var change: Array = [[2, -1], [0, 0], [0, 2]][clampi(difficulty, 0, 2)]
	var result: Array[int] = []
	for side in 2: result.append(clampi(levels[side] + int(change[side]), 1, 20))
	return result
