class_name ELRandomDeck
extends RefCounted
## Random Etherlords II duel presets, following the community's random deck
## generator: a random magic, the chosen hero level, skills and one artifact,
## a 16-spell deck weighted towards cantrips and commons, and a 36-spell
## reserve weighted towards rares, uniques and colourless spells. Cards of
## every colour mix freely, so the preset uses the sandbox resource level
## (any colour, no budget), as the generator's modified resources did.

## Cards the generator leaves out of its pools.
const EXCLUDED: Array[String] = ["ZAPP", "TGSK", "JRRG", "CHNL"]
## Colourless creatures and the Barrier pillars (the rest of the colourless
## spells form the other neutral pool).
const NEUTRAL_CREATURES: Array[String] = ["OUD1", "OUD2", "OUD3", "OUE1", "OUE2", "OUE3", "OST1", "OST2", "OST3",
	"OUS1", "OUS2", "OUS3", "SMWB", "SMTG", "SMFX"]
## Colourless removal and control.
const CONTROL: Array[String] = ["ORPL", "OBLS", "ORFT", "OCLV", "OFLX", "PRBN", "OCRP", "PRWR", "OEXC", "PLSL",
	"OMWP", "OMSW", "BNSH", "GBNS", "PLWP"]
## Spells and creatures that remove enchantments.
const DISPEL: Array[String] = ["ORSH", "PTRS", "RFPT", "CLNP", "WHAS", "FLIC", "ETTD", "PRFY", "DECN", "CLSN"]
## Artifacts the generator gives (one each preset).
const ARTIFACTS: Array[String] = ["RDHL", "RDLG", "RDRS", "PCDU", "WNBL", "WNMG", "SPRG"]
## Deck draws: [pools, count]; the pools of one draw are merged.
const DECK := [[["cantrip"], 4], [["cantrip", "common"], 1], [["common"], 10], [["common", "rare"], 1]]
const RESERVE := [[["common", "rare"], 1], [["rare"], 10], [["rare", "unique"], 2], [["unique"], 10],
	[["neutral"], 6], [["neutral", "neutral_creatures"], 1], [["neutral_creatures"], 1], [["control"], 1],
	[["dispel"], 1], [["common"], 1], [["rare"], 1], [["unique"], 1]]
## Skills: Providence and Sorcery always, one of each pair, Concentration.
const SKILL_PAIRS := [["ARTF", "MSTR"], ["REGN", "HEAL"]]

## The spell pools by rarity (coloured cards) and the colourless ones.
static func pools(profile: ELProfile) -> Dictionary:
	var spells := profile.table("CombatSpells")
	var codes: Array = spells.keys()
	codes.sort()
	var result := {"cantrip": [], "common": [], "rare": [], "unique": [], "neutral": [], "neutral_creatures": [], "control": [], "dispel": []}
	var level := ELDuelCosts.EL2_SANDBOX_LEVEL
	for code: String in codes:
		if code in EXCLUDED or not ELDuelCosts.spell_allowed(profile, code, "Red", level): continue
		if String(spells[code].get("Color", "")) == ELDuelCosts.EL2_NEUTRAL:
			result["neutral_creatures" if code in NEUTRAL_CREATURES else "neutral"].append(code)
		else:
			var rarity := String(spells[code].get("Rarity", "")).to_lower()
			if result.has(rarity): result[rarity].append(code)
	for pair: Array in [["control", CONTROL], ["dispel", DISPEL]]:
		for code: String in pair[1]:
			if ELDuelCosts.spell_allowed(profile, code, "Red", level): result[pair[0]].append(code)
	return result

## A new preset at `hero_level`; `name` is kept.
static func make(profile: ELProfile, hero_level: int, name := "", random: RandomNumberGenerator = null) -> Dictionary:
	if random == null:
		random = RandomNumberGenerator.new()
		random.randomize()
	var levels := ELDuelCosts.hero_levels(profile)
	hero_level = clampi(hero_level, levels.x, levels.y)
	var faction: String = ELDuelPresets.RACES[random.randi() % ELDuelPresets.RACES.size()]
	var preset := ELDuelPresets.blank(faction, ELDuelCosts.EL2_SANDBOX_LEVEL)
	preset.name = name
	preset.level = hero_level
	var available := pools(profile)
	var cards: Array[String] = []
	for draw: Array in DECK:
		for i in int(draw[1]): cards.append(_pick(available, draw[0], random))
	preset.cards = cards
	var runes: Array[int] = []
	for card in cards: runes.append(1)
	preset.runes = runes
	var reserve := {}
	for draw: Array in RESERVE:
		for i in int(draw[1]):
			var code := _pick(available, draw[0], random)
			if not code.is_empty(): reserve[code] = int(reserve.get(code, 0)) + 1
	preset.reserve = reserve
	preset.skills = skills(profile, hero_level, random)
	var offered := ELDuelCosts.duel_artifacts(profile)
	var artifacts: Array[String] = []
	var choices := ARTIFACTS.filter(func(code: String): return offered.has(code))
	if not choices.is_empty(): artifacts.append(choices[random.randi() % choices.size()])
	preset.artifacts = artifacts
	return preset

static func _pick(available: Dictionary, names: Array, random: RandomNumberGenerator) -> String:
	var merged: Array = []
	for name: String in names: merged.append_array(available.get(name, []))
	return String(merged[random.randi() % merged.size()]) if not merged.is_empty() else ""

## Hero level + 1 skill points spread at random over Providence, Sorcery
## (at least one each) and one skill of each pair (possibly none), each up to
## the highest rank; Concentration grows with the hero level.
static func skills(profile: ELProfile, hero_level: int, random: RandomNumberGenerator) -> Dictionary:
	var codes: Array[String] = ["PRVD", "SUPR"]
	for pair: Array in SKILL_PAIRS: codes.append(String(pair[random.randi() % pair.size()]))
	var lowest := [1, 1, 0, 0]
	var highest := ELHeroSkills.MAX_RANK + 1
	var left := hero_level + 1
	var result := {}
	for i in codes.size():
		var later_low := 0
		for j in range(i + 1, codes.size()): later_low += lowest[j]
		var later_high := (codes.size() - i - 1) * highest
		# More points than every skill can hold (high hero levels) fill them up.
		var low := mini(highest, maxi(lowest[i], left - later_high))
		var high := mini(highest, left - later_low)
		var points := random.randi_range(low, maxi(low, high))
		left -= points
		if points > 0 and not ELHeroSkills.definition(profile, codes[i], points - 1).is_empty(): result[codes[i]] = points - 1
	var concentration := 1 if hero_level < 4 else (random.randi_range(1, 2) if hero_level < 8 else (random.randi_range(2, 3) if hero_level < 12 else 3))
	if not ELHeroSkills.definition(profile, "CONC", concentration - 1).is_empty(): result["CONC"] = concentration - 1
	return result
