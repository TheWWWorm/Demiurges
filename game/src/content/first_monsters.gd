class_name ELFirstMonsters
extends RefCounted
## EL1's neutral opponents use the difficulty-indexed Monsters registry.

static func definition(profile: ELProfile, name: String, difficulty: int) -> Dictionary:
	if profile.id != "el1": return {}
	for row: Dictionary in profile.table("Monsters").values():
		if row.get("Name") == name and int(row.get("DifficultyLevel", -1)) == difficulty: return row
	return {}

static func book(row: Dictionary) -> Dictionary:
	var cards: Array[String] = []
	var uses: Array[int] = []
	var entries: Variant = row.get("Deck", [])
	if entries is String: entries = [entries]
	for entry: String in entries:
		cards.append(entry.left(4))
		# The original loader reads the first code and atoi after the first '('.
		# A malformed trailing '. HAST(1)' is not another registry element.
		var value := entry.get_slice("(", 1)
		var digits := ""
		for letter: String in value:
			if letter < "0" or letter > "9": break
			digits += letter
		uses.append(int(digits))
	return {"cards": cards, "uses": uses}

static func initialize(profile: ELProfile, actor: Dictionary, difficulty: int) -> bool:
	var row := definition(profile, actor.name, difficulty)
	if row.is_empty(): return false
	actor.monster_version = 1
	actor.monster_difficulty = difficulty
	actor.type = "monster"
	actor.level = int(row.Level)
	actor.health = int(row.Health)
	actor.title = profile.text(str(row.get("ELKName", actor.name)))
	actor.specialization = row.get("Specialization", "NONE")
	var deck := book(row)
	actor.cards = deck.cards
	actor.skills = ELHeroSkills.from_template(profile, row)
	ELHeroProgression.initialize(profile, actor, 0)
	ELRunes.initialize(profile, actor, deck.uses)
	return true

static func appearance(profile: ELProfile, name: String, difficulty: int) -> Dictionary:
	var row := definition(profile, name, difficulty)
	# The neutral map model is separate from its combat creature model.
	return profile.table("CombatCreatures").get(row.get("Creature", ""), {})

## Loot dice from one Monsters entry, "Kind(NdM+K)", "Kind(NdM-K)" or "Kind(K)",
## as [kind, dice, sides, addition]; malformed entries are skipped.
static func loot_entries(value: Variant) -> Array:
	var result: Array = []
	var entries: Array = value if value is Array else ([value] if value is String else [])
	for entry: Variant in entries:
		var text := str(entry).strip_edges()
		var kind := text.get_slice("(", 0)
		var inner := text.get_slice("(", 1).get_slice(")", 0)
		if kind not in ELResources.ORIGINAL or not text.contains("(") or not text.ends_with(")") or inner.is_empty(): continue
		var dice := 0
		var sides := 0
		var addition := 0
		if inner.contains("d"):
			dice = int(inner.get_slice("d", 0))
			var rest := inner.get_slice("d", 1)
			var sign := 1
			var at := rest.find("+")
			if at < 0:
				at = rest.find("-")
				sign = -1
			sides = int(rest if at < 0 else rest.substr(0, at))
			if at >= 0: addition = sign * int(rest.substr(at + 1))
		else: addition = int(inner)
		result.append([kind, dice, sides, addition])
	return result

## Victory loot from a neutral creature's template: Loot100 always, then one
## percentile roll below 66 adds Loot66 and another below 33 adds Loot33.
## Each entry adds its constant plus `dice` rolls of 1..sides. Totals are kept
## per resource in the original resource order; empty totals are dropped.
static func roll_loot(row: Dictionary, random: Callable) -> Array:
	var totals := {}
	for kind: String in ELResources.ORIGINAL: totals[kind] = 0
	var tiers := [["Loot100", 100], ["Loot66", 66], ["Loot33", 33]]
	for tier: Array in tiers:
		if int(tier[1]) < 100 and int(random.call()) % 100 >= int(tier[1]): continue
		for entry: Array in loot_entries(row.get(tier[0], [])):
			totals[entry[0]] += int(entry[3])
			for roll in int(entry[1]): totals[entry[0]] += (int(random.call()) % int(entry[2]) if int(entry[2]) > 0 else 0) + 1
	var result: Array = []
	for kind: String in ELResources.ORIGINAL:
		if int(totals[kind]) > 0: result.append([kind, int(totals[kind])])
	return result

## The winner's Search skill multiplies each amount (rank I-III: 1.5, 2.25, 3),
## truncating.
static func loot_multiplier(hero: Dictionary) -> float:
	var rank := int(hero.get("skills", {}).get("SRCH", -1))
	return [1.0, 1.5, 2.25, 3.0][clampi(rank + 1, 0, 3)]

static func scale_loot(draws: Array, hero: Dictionary) -> Array:
	var factor := loot_multiplier(hero)
	var result: Array = []
	for entry: Array in draws: result.append([entry[0], int(float(entry[1]) * factor)])
	return result
