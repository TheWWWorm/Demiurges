class_name ELEncyclopaedia
extends RefCounted
## Second-game Encyclopaedia catalogue: the CombatSpells cards of one race and
## class. Races 0..4 are the colours with IsArtifact False; race 5 lists every
## IsArtifact card. Some cards are never listed, and support cards only when
## they are in SUPPORT_SHOWN.
## Sorting follows the original comparators: each column
## compares its keys in a fixed order and a descending sort reverses every key;
## names compare as their CP1251 bytes.
const RACES := ["Red", "Green", "Blue", "Black", "White"]
const ARTIFACTS := 5
const RACE_COUNT := 6
## Popup order: creatures, enchantments, sorcery.
const MODES := ["Creature", "Enchantment", "Sorcery"]
const MODE_TEXTS := ["T_ENC_CREATURES", "T_ENC_ENCHANTMENTS", "T_ENC_SORCERY"]
const HIDDEN := ["OST1", "OST2", "OST3", "RDKN", "WNHR", "WNMG"]
const SUPPORT_SHOWN := ["OSJ1", "OSJ2", "OSJ3", "EKON", "EHUN", "EMAG"]
const RARITY := {"Cantrip": 0, "Common": 1, "Rare": 2, "Unique": 3}
const SORT_NONE := ""
const SORTS := ["rarity", "name", "cost", "power", "toughness"]
## Keys compared in turn by each column: creature list and enchantment/sorcery
## list. Attack and defence exist for creatures only.
const CREATURE_KEYS := {"rarity": ["rarity", "cost", "power", "toughness", "name"], "name": ["name"],
	"cost": ["cost", "power", "toughness", "rarity", "name"], "power": ["power", "toughness", "cost", "rarity", "name"],
	"toughness": ["toughness", "power", "cost", "rarity", "name"]}
const SPELL_KEYS := {"rarity": ["rarity", "cost", "name"], "name": ["name"], "cost": ["cost", "rarity", "name"]}
## Creature page ability icons in the original order: creature flag
## and icon number n (CombatSymbols cell ELCombatSymbols.ICON_CODES[n], tooltip
## T_CREATURE_ICON_<n+1>C and T_CREATURE_ICON_<n+1>). Regen and Discard
## match their numbered forms.
const ABILITY_ICONS := [["Fly", 3], ["Berserk", 15], ["NoUntap", 12], ["NoAttack", 2], ["Restless", 6], ["Trample", 5],
	["TeamAttack", 16], ["FS", 4], ["Disenchant", 10], ["NSS", 14], ["Lifetap", 7], ["Destroy", 11], ["UB", 13],
	["Elusive", 17], ["Outerplanar", 18], ["Discard", 9], ["Regen", 8]]

static func listed(code: String, row: Dictionary, race: int, mode: int) -> bool:
	if code in HIDDEN or str(row.get("Class", "")) != MODES[clampi(mode, 0, 2)]: return false
	if str(row.get("Support", "False")) == "True" and not code in SUPPORT_SHOWN: return false
	var artifact := str(row.get("IsArtifact", "False")) == "True"
	if race == ARTIFACTS: return artifact
	return not artifact and str(row.get("Color", "")) == RACES[clampi(race, 0, 4)]

## Card codes in catalogue order, then sorted by the chosen column, ascending
## or descending (ties beyond every key keep catalogue order).
static func codes(profile: ELProfile, race: int, mode: int, sort := SORT_NONE, ascending := true) -> Array[String]:
	var spells := profile.table("CombatSpells")
	var result: Array[String] = []
	for code: String in spells:
		if listed(code, spells[code], race, mode): result.append(code)
	var columns: Dictionary = CREATURE_KEYS if clampi(mode, 0, 2) == 0 else SPELL_KEYS
	if sort.is_empty() or not columns.has(sort): return result
	var order := {}
	for index in result.size(): order[result[index]] = index
	var names: Array = columns[sort]
	var keys := {}
	for code: String in result:
		var values: Array = []
		for column: String in names: values.append(key(profile, code, column))
		keys[code] = values
	result.sort_custom(func(a: String, b: String) -> bool:
		var left: Array = keys[a]
		var right: Array = keys[b]
		for index in left.size():
			if left[index] != right[index]: return (left[index] < right[index]) == ascending
		return int(order[a]) < int(order[b]))
	return result

static func key(profile: ELProfile, code: String, sort: String) -> Variant:
	var row: Dictionary = profile.table("CombatSpells").get(code, {})
	match sort:
		"rarity": return int(RARITY.get(str(row.get("Rarity", "")), 0))
		"cost": return int(row.get("Cost", 0))
		"power": return int(profile.table("CombatCreatures").get(code, {}).get("Power", 0))
		"toughness": return int(profile.table("CombatCreatures").get(code, {}).get("Toughness", 0))
	return byte_order(name(profile, code))

## A string whose code points are the CP1251 bytes of `text`, so that string
## comparison follows the original byte order (Ё/ё before А, then А..я).
static func byte_order(text: String) -> String:
	var result := PackedInt32Array()
	for index in text.length():
		var point := text.unicode_at(index)
		if point < 0x80: result.append(point)
		elif point >= 0x410 and point <= 0x44f: result.append(point - 0x410 + 0xc0)
		elif point == 0x401: result.append(0xa8)
		elif point == 0x451: result.append(0xb8)
		else: result.append(int(CP1251_EXTRA.get(point, 0x3f)))
	var out := ""
	for value in result: out += String.chr(value)
	return out

## CP1251 bytes of the punctuation that occurs besides ASCII and Cyrillic.
const CP1251_EXTRA := {0xa0: 0xa0, 0xab: 0xab, 0xbb: 0xbb, 0x2013: 0x96, 0x2014: 0x97, 0x2018: 0x91, 0x2019: 0x92,
	0x201c: 0x93, 0x201d: 0x94, 0x201e: 0x84, 0x2026: 0x85, 0x2116: 0xb9, 0xb0: 0xb0, 0xb7: 0xb7}

## Ability icon numbers of a creature card in the page's order.
static func ability_icons(profile: ELProfile, code: String) -> Array[int]:
	var flags: Variant = profile.table("CombatCreatures").get(code, {}).get("Flags", [])
	var owned: Array = flags if flags is Array else ([flags] if not str(flags).is_empty() else [])
	var names: Array[String] = []
	for flag: Variant in owned: names.append(str(flag).strip_edges().get_slice("(", 0))
	var result: Array[int] = []
	for entry: Array in ABILITY_ICONS:
		if names.has(str(entry[0])): result.append(int(entry[1]))
	return result

static func name(profile: ELProfile, code: String) -> String:
	return profile.text(str(profile.table("CombatSpells").get(code, {}).get("Name", code)))

static func cost(profile: ELProfile, code: String) -> int:
	return int(profile.table("CombatSpells").get(code, {}).get("Cost", 0))

## "power/toughness" of a creature card, "" for other cards.
static func strength(profile: ELProfile, code: String) -> String:
	var creature: Dictionary = profile.table("CombatCreatures").get(code, {})
	if creature.is_empty(): return ""
	return "%s/%s" % [str(creature.get("Power", "X")), str(creature.get("Toughness", "X"))]

## The three 256x256 parts of a creature's encyclopaedia picture, or [] when absent.
static func picture(profile: ELProfile, code: String) -> Array:
	var parts: Array = []
	for index in 3:
		var texture := profile.texture("Interface/Encyclopaedia/%s_%d" % [code, index + 1])
		if texture == null: return []
		parts.append(texture)
	return parts
