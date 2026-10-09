class_name ELDuelCosts
extends RefCounted
## Duel-mode preset budget and price model, per edition. Pure functions over
## the mounted profile's tables; no state.
##
## A preset is an edition-neutral dictionary (see ELDuelPresets):
## faction, resource_level, level, specialization, skills {code: rank 0..2},
## cards [codes], runes [per-slot rune count, EL1], reserve {code: count, EL2},
## artifacts [artifact spell codes].

## Resource types charged by each edition, in the original index order.
const EL1_RESOURCES: Array[String] = ["Root", "Lotus", "Ruby", "Emerald", "Sapphire", "Diamond", "Stone"]
## The second game's builder keeps Root, Ruby and Stone and discards the rest.
const EL2_RESOURCES: Array[String] = ["Root", "Ruby", "Stone"]
## First-game price multiplier for the k-th copy of a spell in the book
## (the spell shop's table).
const MULTIPLIERS: Array[int] = [1, 2, 3, 5, 10, 20, 40, 80, 160, 320, 640, 1280, 2560, 5120, 10240, 20480]
const EL2_NEUTRAL := "White"
const EL2_DECK := 16
const EL2_COPIES := 4
const EL1_BOOK := 15
const MAX_SKILLS := 5

static func resources(profile: ELProfile) -> Array[String]:
	return EL1_RESOURCES if profile.id == "el1" else EL2_RESOURCES

## Selectable resource levels on the Duel screen and in the editor.
static func resource_levels(profile: ELProfile) -> Vector2i:
	return Vector2i(1, 5 if profile.id == "el1" else 3)

## Hero levels the preset editor allows.
static func hero_levels(profile: ELProfile) -> Vector2i:
	return Vector2i(1, 15 if profile.id == "el1" else 13)

static func budget(profile: ELProfile, resource_level: int) -> Dictionary:
	var row: Dictionary = profile.table("DuelResourceLevels").get(str(resource_level), {})
	var result := {}
	for r: String in resources(profile): result[r] = int(row.get(r, 0))
	return result

static func zero(profile: ELProfile) -> Dictionary:
	var result := {}
	for r: String in resources(profile): result[r] = 0
	return result

static func _add(total: Dictionary, row: Dictionary, prefix: String, factor := 1) -> void:
	for r: String in total: total[r] += int(row.get(prefix + r, 0)) * factor

static func hero_level_cost(profile: ELProfile, level: int) -> Dictionary:
	var total := zero(profile)
	var stats := profile.table("HeroesStats")
	for r: String in total: total[r] = int(stats.get("DuelCost" + r, {}).get("Level%d" % level, 0))
	return total

static func spells_cost(profile: ELProfile, preset: Dictionary) -> Dictionary:
	var total := zero(profile)
	var spells := profile.table("CombatSpells")
	var cards: Array = preset.get("cards", [])
	if profile.id == "el1":
		var runes: Array = preset.get("runes", [])
		var seen := {}
		for index in cards.size():
			var row: Dictionary = spells.get(cards[index], {})
			seen[cards[index]] = int(seen.get(cards[index], 0)) + 1
			_add(total, row, "Cost", MULTIPLIERS[mini(int(seen[cards[index]]), MULTIPLIERS.size()) - 1])
			var count := int(runes[index]) if index < runes.size() else 0
			if count > 0 and row.get("Rarity") != "Cantrip": _add(total, row, "Charge", count)
	else:
		# Flat price per copy, active deck and reserve alike.
		for card: String in cards: _add(total, spells.get(card, {}), "Cost")
		var reserve: Dictionary = preset.get("reserve", {})
		for card: String in reserve: _add(total, spells.get(card, {}), "Cost", int(reserve[card]))
	return total

## Total price of a preset per resource type.
static func cost(profile: ELProfile, preset: Dictionary) -> Dictionary:
	var total := hero_level_cost(profile, int(preset.get("level", 1)))
	var spec := String(preset.get("specialization", "NONE"))
	if spec != "NONE": _add(total, profile.table("HeroesSpecs").get(spec, {}), "DuelCost")
	var skills: Dictionary = preset.get("skills", {})
	for code: String in skills: _add(total, ELHeroSkills.definition(profile, code, int(skills[code])), "DuelCost")
	for code: String in preset.get("artifacts", []): _add(total, profile.table("CombatSpells").get(code, {}), "Cost")
	var spells := spells_cost(profile, preset)
	for r: String in total: total[r] += spells[r]
	return total

## Resource types whose price exceeds the budget, with the excess.
static func shortfall(profile: ELProfile, price: Dictionary, resource_level: int) -> Dictionary:
	var limit := budget(profile, resource_level)
	var result := {}
	for r: String in limit:
		if int(price.get(r, 0)) > limit[r]: result[r] = int(price[r]) - limit[r]
	return result

static func fits(profile: ELProfile, preset: Dictionary) -> bool:
	return shortfall(profile, cost(profile, preset), int(preset.get("resource_level", 1))).is_empty()

## Skills the duel editor offers: the `Duel=True` rows.
static func duel_skills(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in profile.table("HeroesSkills").values():
		var code := String(row.get("Code", ""))
		if str(row.get("Duel", "False")) == "True" and not result.has(code): result.append(code)
	result.sort()
	return result

## Specialisations of a race (`MagicColor` lists it).
static func spec_allowed(profile: ELProfile, code: String, faction: String) -> bool:
	if code == "NONE": return true
	var colours: Variant = profile.table("HeroesSpecs").get(code, {}).get("MagicColor", [])
	return (colours is String and colours == faction) or (colours is Array and colours.has(faction))

static func artifact(profile: ELProfile, code: String) -> bool:
	return str(profile.table("CombatSpells").get(code, {}).get("IsArtifact", "False")) == "True"

## Artifacts per second-game preset (the editor's five hero cells); the first
## game sets no limit.
const EL2_ARTIFACTS := 5

## Artifacts the duel editor sells, as artifact spell codes in list order: the
## artifact rows of rarity Common that have an `Artefacts` template. Both games
## leave out the five Rare rods (LNRD, BRRD, RDDF, DMRD, RDIS); the second game
## also leaves out support spells (the Blank) and generated artifacts. The
## first game lists them in spell-table order, the second by template name.
## Copies are allowed in both games and keep the same price.
static func duel_artifacts(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	var spells := profile.table("CombatSpells")
	if profile.id == "el1":
		for code: String in spells:
			if artifact(profile, code) and spells[code].get("Rarity") == "Common" and not ELDuelPresets.artifact_name(profile, code).is_empty(): result.append(code)
		return result
	var rows := profile.table("Artefacts")
	var names: Array = rows.keys()
	names.sort()
	for name: String in names:
		var code := String(rows[name].get("SpellType", ""))
		var row: Dictionary = spells.get(code, {})
		if artifact(profile, code) and row.get("Rarity") == "Common" and str(row.get("Support", "False")).to_lower() != "true" and not result.has(code): result.append(code)
	return result

## The most artifacts a preset may carry (-1: no limit).
static func artifact_limit(profile: ELProfile) -> int:
	return -1 if profile.id == "el1" else EL2_ARTIFACTS

static func spell_allowed(profile: ELProfile, card: String, faction: String) -> bool:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	if row.is_empty() or artifact(profile, card) or str(row.get("Support", "False")).to_lower() == "true": return false
	var colour := String(row.get("Color", ""))
	return colour == faction or (profile.id != "el1" and colour == EL2_NEUTRAL)

## Rune slots hold at most the Providence capacity (5/7/10/15); cantrips carry none.
static func rune_capacity(skills: Dictionary) -> int:
	return ELRunes.capacity({"skills": skills})

## Every rule a saved preset must satisfy. Codes: faction, resource_level,
## hero_level, spec, skills, skill:<code>, book_size, spell:<code>,
## colour:<code>, copies:<code>, runes:<slot>, reserve:<code>,
## artifact:<code> (not sold in duels), artifacts (too many), budget:<resource>.
static func errors(profile: ELProfile, preset: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var faction := String(preset.get("faction", ""))
	if not ELCatalog.FACTIONS.has(faction): result.append("faction")
	var levels := resource_levels(profile)
	var resource_level := int(preset.get("resource_level", 0))
	if resource_level < levels.x or resource_level > levels.y: result.append("resource_level")
	var heroes := hero_levels(profile)
	var level := int(preset.get("level", 0))
	if level < heroes.x or level > heroes.y: result.append("hero_level")
	var spec := String(preset.get("specialization", "NONE"))
	if spec != "NONE" and (not profile.table("HeroesSpecs").has(spec) or not spec_allowed(profile, spec, faction)): result.append("spec")
	var skills: Dictionary = preset.get("skills", {})
	var allowed := duel_skills(profile)
	if skills.size() > MAX_SKILLS: result.append("skills")
	for code: String in skills:
		var rank := int(skills[code])
		if not allowed.has(code) or rank < 0 or rank > ELHeroSkills.MAX_RANK or ELHeroSkills.definition(profile, code, rank).is_empty(): result.append("skill:" + code)
	var cards: Array = preset.get("cards", [])
	if profile.id == "el1":
		if cards.is_empty() or cards.size() > EL1_BOOK: result.append("book_size")
	elif cards.size() != EL2_DECK: result.append("book_size")
	var counts := {}
	for card: String in cards:
		counts[card] = int(counts.get(card, 0)) + 1
		if not profile.table("CombatSpells").has(card): result.append("spell:" + card)
		elif not spell_allowed(profile, card, faction): result.append("colour:" + card)
	if profile.id == "el1":
		var runes: Array = preset.get("runes", [])
		var capacity := rune_capacity(skills)
		for index in cards.size():
			var count := int(runes[index]) if index < runes.size() else 0
			if profile.table("CombatSpells").get(cards[index], {}).get("Rarity") == "Cantrip": continue
			if count < 0 or count > capacity: result.append("runes:%d" % index)
		if not preset.get("reserve", {}).is_empty(): result.append("reserve")
	else:
		for card: String in counts:
			if int(counts[card]) > EL2_COPIES: result.append("copies:" + card)
		var reserve: Dictionary = preset.get("reserve", {})
		for card: String in reserve:
			if int(reserve[card]) < 0 or not spell_allowed(profile, card, faction): result.append("reserve:" + card)
	var offered := duel_artifacts(profile)
	var artifacts: Array = preset.get("artifacts", [])
	for code: String in artifacts:
		if not offered.has(code): result.append("artifact:" + code)
	if artifact_limit(profile) >= 0 and artifacts.size() > artifact_limit(profile): result.append("artifacts")
	for r: String in shortfall(profile, cost(profile, preset), resource_level): result.append("budget:" + r)
	return result
