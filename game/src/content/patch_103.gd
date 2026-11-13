class_name ELPatch103
extends RefCounted
## Etherlords II update 1.03, the game's final official version. The remake
## plays the second game by its rules whichever release the player installed.
##
## Release 1.01 (still sold in some Russian editions) keeps the older card
## values and descriptions in its data. They are brought up to 1.03 here when
## the data is mounted: the changed table values (costs, statistics, flags, the
## Rebirth chance) and the descriptions of the changed cards. Release 1.03 data
## already carries them and is left as it is. The rules the remake implements
## itself follow 1.03 directly (ELDuel, ELCatalog); what the player's own
## scripts, maps and pictures contain stays as installed.

## The release a second-game card table belongs to.
const RELEASE_OLD := "1.01"
const RELEASE_CURRENT := "1.03"

## Card table values that 1.03 changed: {table: {row: {key: value}}}. `Flags`
## lists flags to add.
const TABLES := {
	"combatspells": {
		"ETCH": {"Cost": 4},
		"GBBR": {"Cost": 1, "OriginalCost": 1},
		"GBIN": {"Cost": 2, "OriginalCost": 2},
		"GIFT": {"Cost": 2, "OriginalCost": 2},
		# Ether Breeze and Ether Storm became creature enchantments.
		"MNBR": {"Class": "Enchantment", "Cost": 3, "OriginalCost": 3, "Ability": 365, "AbilityIcon": 450, "AbilityText": "Ab365"},
		"MNST": {"Class": "Enchantment", "Cost": 3, "OriginalCost": 3, "Ability": 366, "AbilityIcon": 455, "AbilityText": "Ab366"},
		# Ether Vortex became a one-turn sorcery.
		"MNVR": {"Class": "Sorcery", "Cost": 1, "OriginalCost": 1},
	},
	"combatcreatures": {
		"OGKN": {"Power": 7, "Toughness": 8},
		"KBGD": {"Flags": ["Disenchant"]},
		"ORGD": {"Flags": ["Disenchant"]},
	},
	"heroesspecs": {"RVVE": {"Chance": "Med"}},
}

## Which release `spells` (the parsed CombatSpells table) comes from: 1.01
## still has Ether Breeze as a sorcery.
static func release(spells: Dictionary) -> String:
	return RELEASE_OLD if str(spells.get("MNBR", {}).get("Class", "")) == "Sorcery" else RELEASE_CURRENT

## Brings a freshly parsed second-game table up to 1.03 in place.
## `old` tells whether the mounted data is release 1.01.
static func upgrade_table(name: String, table: Dictionary, old: bool) -> void:
	var changes: Dictionary = TABLES.get(name.to_lower(), {})
	if not old or changes.is_empty(): return
	for row_name: String in changes:
		if not table.has(row_name): continue
		var row: Dictionary = table[row_name]
		var values: Dictionary = changes[row_name]
		for key: String in values:
			if key == "Flags":
				var flags := ELCatalog.flags(row)
				for flag: String in values.Flags:
					if not flags.has(flag): flags.append(flag)
				row.Flags = Array(flags)
			else: row[key] = values[key]

## Descriptions of the cards 1.03 changed, for release 1.01 texts:
## {key: [English, Russian]}.
const TEXTS := {
	"VOLCTt": ["Gain 3 ether channels", "Дает 3 эфирных канала"],
	"MNBRTt": ["Cast on a creature. At the start of each of his or her turns, the enchantment's owner gains 3 ether",
		"Накладывается на создание. В начале каждого своего хода владелец чары получает 3 кванта эфира"],
	"Ab365": ["Ether Breeze. At the start of each of his or her turns, the enchantment's owner gains 3 ether",
		"Эфирный Бриз. В начале каждого своего хода владелец чары получает 3 кванта эфира"],
	"MNSTTt": ["Cast on a creature. At the start of each of his or her turns, the enchantment's owner gains 1 ether channel",
		"Накладывается на создание. В начале каждого своего хода владелец чары получает 1 эфирный канал"],
	"Ab366": ["Ether Storm. At the start of each of his or her turns, the enchantment's owner gains 1 ether channel",
		"Эфирный Шторм. В начале каждого своего хода владелец чары получает 1 эфирный канал"],
	"MNVRTt": ["At the start of the hero's next turn, every ether channel gives 1 more ether",
		"В начале следующего хода героя каждый эфирный канал дает 1 дополнительный квант эфира"],
	"Ab167": ["Ether Vortex. At the start of the hero's next turn, every ether channel gives 1 more ether",
		"Эфирный Вихрь. В начале следующего хода героя каждый эфирный канал дает 1 дополнительный квант эфира"],
	"ETCHTt": ["Until end of turn, whenever the enchanted hero takes damage, the enemy hero takes twice as much. More copies do not add to it",
		"Всякий раз до конца хода, когда зачарованный герой получает урон, его противник получает вдвое больший урон. Несколько копий этого заклинания урон не увеличивают"],
	"Ab81": ["Ethereal Resonance. Whenever the enchanted hero takes damage, the enemy hero takes twice as much. More copies do not add to it",
		"Эфирный Резонанс. Всякий раз, когда зачарованный герой получает урон, его противник получает вдвое больший урон. Несколько копий этого заклинания урон не увеличивают"],
	"TRLBTt": ["For every enchantment or sorcery cast, the enchantment's owner draws 1 spell and takes 2 damage. Nothing can prevent this damage",
		"За каждые сотворенные чары или колдовство владелец чар получает в руку 1 заклинание и 2 ед. урона. Этот урон ничем нельзя предотвратить"],
	"Ab255": ["Data Attraction. For every enchantment or sorcery cast, the enchantment's owner draws 1 spell and takes 2 damage. Nothing can prevent this damage",
		"Притяжение Данных. За каждые сотворенные чары или колдовство владелец чар получает в руку 1 заклинание и 2 ед. урона. Этот урон ничем нельзя предотвратить"],
	"BASOTt": ["Draw 1 spell for each of your own creatures destroyed", "За каждое свое уничтоженное создание получить в руку 1 заклинание"],
	"Ab17": ["Barbed Souls. Draw 1 spell for each of your own creatures destroyed", "Шипы Душ. За каждое свое уничтоженное создание получить в руку 1 заклинание"],
	"ORSHTt": ["The owner gains 1 ether at the start of each of his or her turns. Orc Ritual: rest, sacrifice an ether channel: remove target enchantment",
		"Владелец получает 1 квант эфира в начале каждого своего хода. Орковский обряд: принудительный отдых, пожертвовать эфирный канал: снять указанные чары"],
	"Ab179": ["Orc Ritual. Rest, sacrifice an ether channel: remove target enchantment",
		"Орковский обряд. Принудительный отдых, пожертвовать эфирный канал: снять указанные чары"],
	"BATTTt": ["Flying. When the Bat dies, the enemy hero discards a spell", "Летает. Когда Летучая мышь погибает, противник ее владельца сбрасывает заклинание"],
	"GBATTt": ["Flying. Whenever the Giant Bat deals combat damage to the enemy hero, its owner draws 1 spell",
		"Летает. Всякий раз, когда Гигантская летучая мышь наносит боевой урон герою противника, ее владелец получает 1 заклинание"],
	"GROGTt": ["Restless. If the opponent makes its hero discard this spell, the Gray Ogre enters the battlefield instead",
		"Неутомимый. Если противник заставил сбросить это заклинание с руки, Серый людоед вызывается на поле"],
	"OGKNTt": ["Restless. Trample. If the opponent makes its hero discard this spell, the Ogre King enters the battlefield instead",
		"Неутомимый. Кровожадный. Если противник заставил сбросить это заклинание с руки, Вождь людоедов вызывается на поле"],
	"BRGRTt": ["Every hero takes 3 damage for each creature in his or her graveyard. Then all creatures leave the graveyards",
		"Каждый герой получает 3 ед. урона за каждое создание в своем могильнике. Затем все создания удаляются из могильников"],
}

## Sentences added to a 1.01 description: {key: [English, Russian]}.
const ADDED := {
	"WEAKTt": ["If the opponent makes its hero discard this spell, the opponent discards 3 spells", "Если противник заставил сбросить это заклинание с руки, он сам сбрасывает 3 заклинания"],
	"CLIGTt": ["If the opponent makes its hero discard this spell, the opponent discards 3 spells", "Если противник заставил сбросить это заклинание с руки, он сам сбрасывает 3 заклинания"],
	"KBGDTt": ["Disenchant", "Разбивает чары"],
	"ORGDTt": ["Disenchant", "Разбивает чары"],
}

## Phrases replaced in a 1.01 description: {key: [[old, new], ...]}.
const REPLACED := {
	# The Pale Scourge no longer devours walls.
	"OUD1Tt": [["уничтожить создание в Эфирном Плане, если его сила меньше", "уничтожить создание в Эфирном Плане, которое не является телохранителем, если его сила меньше"]],
	"Ab333": [["уничтожить создание в Эфирном Плане, если его сила меньше", "уничтожить создание в Эфирном Плане, которое не является телохранителем, если его сила меньше"]],
}

## Brings release 1.01 texts up to 1.03 in place (`texts`: key → text).
static func upgrade_texts(texts: Dictionary, old: bool) -> void:
	if not old: return
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var russian := cyrillic.search(str(texts.get("MNBRNm", texts.get("VOLCNm", "")))) != null
	var language := 1 if russian else 0
	for key: String in TEXTS: texts[key] = TEXTS[key][language]
	for key: String in ADDED:
		if not texts.has(key): continue
		var value := String(texts[key]).strip_edges()
		var sentence: String = ADDED[key][language]
		if value.contains(sentence): continue
		texts[key] = (value + ("" if value.is_empty() or value.ends_with(".") else ".") + " " + sentence).strip_edges()
	for key: String in REPLACED:
		if not texts.has(key): continue
		for pair: Array in REPLACED[key]: texts[key] = String(texts[key]).replace(pair[0], pair[1])
	# The main menu's version line shows the rules being played.
	if texts.has("T_MAIN_MENU_VERSION"):
		texts["T_MAIN_MENU_VERSION"] = String(texts["T_MAIN_MENU_VERSION"]).replace("1.01", RELEASE_CURRENT).replace("1.02", RELEASE_CURRENT)
