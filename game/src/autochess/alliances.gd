class_name ELAutochessAlliances
extends RefCounted
## Overlapping alliances counted from distinct deployed recruit lines. The
## four Etherlords II factions each reward their own style; flying and
## first-strike creatures form two more. Copies and reserves never count.

const RULES := {
	"chaots": {"name": "Chaots", "color": "Red", "thresholds": [2, 4, 6],
		"help": "Chaot members deal 10/20/30% more attack damage at 2/4/6 different Chaot lines."},
	"kinets": {"name": "Kinets", "color": "Blue", "thresholds": [2, 4],
		"help": "Kinet members recharge abilities 20/40% faster and attack 10/20% faster at 2/4 different Kinet lines."},
	"vitals": {"name": "Vitals", "color": "Green", "thresholds": [2, 4],
		"help": "Vital members regenerate 1/2% of their health every second at 2/4 different Vital lines."},
	"synthets": {"name": "Synthets", "color": "Black", "thresholds": [2, 4],
		"help": "Synthet members gain 3/6 defense at 2/4 different Synthet lines."},
	"flyers": {"name": "Flyers", "flag": "Fly", "thresholds": [2, 4],
		"help": "Flying members evade 15/30% of attacks from creatures that cannot fly at 2/4 different flying lines."},
	"strikers": {"name": "First strike", "flag": "FS", "thresholds": [2, 4],
		"help": "First strike members deal 30/60% more damage with their opening blow on each enemy at 2/4 different lines."},
}
const EFFECTS := {
	"chaots": ["+10% attack damage", "+20% attack damage", "+30% attack damage"],
	"kinets": ["+20% recharge, +10% attack speed", "+40% recharge, +20% attack speed"],
	"vitals": ["1% health per second", "2% health per second"],
	"synthets": ["+3 defense", "+6 defense"],
	"flyers": ["15% evasion against ground attacks", "30% evasion against ground attacks"],
	"strikers": ["+30% opening blow", "+60% opening blow"],
}
const ORDER := ["chaots", "kinets", "vitals", "synthets", "flyers", "strikers"]
## Game art for each alliance: a spell of the faction's own magic (fire,
## lightning, healing, a cyborg skull), and the flaming wings and the sword
## of the second game's effect icons for flyers and first strike.
const ICONS := {"chaots": ["spell", "FRST"], "kinets": ["spell", "JUST"], "vitals": ["spell", "HEAL"],
	"synthets": ["spell", "BDEX"], "flyers": ["affect", 12], "strikers": ["affect", 5]}

static var _icons: Dictionary = {}

static func icon(profile: ELProfile, key: String) -> Texture2D:
	var cache := profile.root + "|" + key
	if _icons.has(cache): return _icons[cache]
	var source: Array = ICONS.get(key, ["spell", ""])
	var result: Texture2D
	if source[0] == "spell": result = profile.card_icon(String(source[1]))
	else:
		# The effect sheets keep the spell sheets' 5 x 5 column-major cells.
		var atlas := AtlasTexture.new()
		atlas.atlas = profile.texture("Interface/affects/icon_01")
		var index := int(source[1])
		atlas.region = Rect2((index / 5) * 50, (index % 5) * 50, 50, 50)
		atlas.filter_clip = true
		result = atlas
	_icons[cache] = result
	return result

static var _traits: Dictionary = {}

## Alliance keys of a recruit line (by its forms' colours and flags).
static func traits(profile: ELProfile, index: int) -> Array[String]:
	if index < 0: return []
	var key := profile.root + "|" + str(index)
	if _traits.has(key): return _traits[key]
	var found: Array[String] = []
	var row := ELAutochessRules.family(index)
	for alliance: String in ORDER:
		var rule: Dictionary = RULES[alliance]
		if rule.has("color") and String(row.color) == String(rule.color): found.append(alliance)
	var flags: Array[String] = []
	for code: String in row.forms:
		for flag: String in ELAutochessRules.flags(profile, code):
			if flag not in flags: flags.append(flag)
	if "Fly" in flags: found.append("flyers")
	# A line whose base form already strikes first, or whose middle form does.
	var base := ELAutochessRules.flags(profile, String(row.forms[0]))
	var middle := ELAutochessRules.flags(profile, String(row.forms[1]))
	if "FS" in base or "FS" in middle: found.append("strikers")
	_traits[key] = found
	return found

static func counts(profile: ELProfile, army: Array) -> Dictionary:
	var lines := {}
	for entry: Dictionary in army:
		if entry.get("deployed", false) and int(entry.family) >= 0: lines[int(entry.family)] = true
	var result := {}
	for alliance: String in ORDER: result[alliance] = 0
	for index: int in lines:
		for alliance: String in traits(profile, index): result[alliance] = int(result[alliance]) + 1
	return result

static func rank(key: String, count: int) -> int:
	var result := 0
	for threshold: int in RULES[key].thresholds:
		if count >= threshold: result += 1
	return result

static func next_threshold(key: String, count: int) -> int:
	for threshold: int in RULES[key].thresholds:
		if count < threshold: return threshold
	return int(RULES[key].thresholds.back())

## Active alliance levels of a company: key -> level (1-based, 0 omitted).
static func levels(profile: ELProfile, army: Array) -> Dictionary:
	var result := {}
	var found := counts(profile, army)
	for key: String in found:
		var level := rank(key, int(found[key]))
		if level > 0: result[key] = level
	return result

static func effect(key: String, level: int) -> String:
	if level <= 0: return "No bonus yet."
	return String(EFFECTS[key][clampi(level - 1, 0, EFFECTS[key].size() - 1)])
