class_name ELExpeditionArtifacts
extends RefCounted
## A small Expedition recipe whitelist for the original EL2 constructor.
## The spell itself is unchanged. The run owns the project, item and charges;
## the duel owns target legality, timing, shared use limits and actual effects.

const NAME_PREFIX := "ExpeditionField_"
const CAPACITY := 2
const COOLDOWN := 1
const DEFINITIONS := [
	{"id": "mndp", "card": "MNDP", "first": 1, "effect": "mana",
		"description": ["Gain 2 ether.", "Получите 2 ед. эфира."],
		"note": ["Stasis can prevent the ether gain.", "Стазис может помешать получению эфира."]},
	{"id": "unsm", "card": "UNSM", "first": 1, "effect": "unsummon",
		"description": ["Return a target creature to its owner's hand.", "Верните выбранное создание в руку его владельца."],
		"note": ["Needs a creature that can be targeted. You may return your own creature.", "Нужно создание, которое можно выбрать целью. Можно вернуть своё создание."]},
	{"id": "repr", "card": "REPR", "first": 1, "effect": "repair",
		"description": ["Return a creature from your graveyard to your hand. The enemy hero takes damage equal to its printed power.",
			"Верните создание из своего могильника в руку. Герой противника получает урон, равный его базовой силе."],
		"note": ["Needs a creature in your graveyard. Returning it does not recharge the pages in your book.", "Нужно создание в вашем могильнике. Его возвращение не восстанавливает заряды страниц книги."]},
	{"id": "prfy", "card": "PRFY", "first": 2, "effect": "dispel",
		"description": ["Remove one enchantment from a creature or hero.", "Снимите одни чары с создания или героя."],
		"note": ["Needs an enchantment that can be dispelled. Selective Purification can still remove the target's other enchantments.", "Нужны чары, которые можно развеять. Тщательная очистка по-прежнему может снять с цели остальные чары."]},
	{"id": "enlh", "card": "ENLH", "first": 2, "effect": "redraw",
		"description": ["Discard your hand, then draw the same number of spells from your book.", "Сбросьте карты из руки, затем получите столько же заклинаний из книги."],
		"note": ["An empty hand gains nothing; exhausted pages can leave you with fewer cards. This does not add spell charges.", "Пустая рука ничего не получает; из-за исчерпанных страниц карт может стать меньше. Новые заряды не появляются."]},
	{"id": "aslt", "card": "ASLT", "first": 3, "effect": "enchant",
		"description": ["Until the end of the enemy hero's turn, your creatures gain +2 power, +2 toughness, Trample and Berserk.",
			"До конца хода противника ваши создания получают +2 к силе и здоровью, Кровожадность и Берсерк."],
		"note": ["Berserk creatures must attack when able. Creatures unaffected by magic keep their normal rules.", "Создания с Берсерком обязаны атаковать, если могут. Невосприимчивые к магии создания сохраняют обычные правила."]},
]

static func catalog(profile: ELProfile) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or profile.id != "el2": return result
	for definition: Dictionary in DEFINITIONS: result.append(_entry(profile, definition))
	return result

static func find(profile: ELProfile, id: String) -> Dictionary:
	if profile == null or profile.id != "el2": return {}
	for definition: Dictionary in DEFINITIONS:
		if definition.id == id: return _entry(profile, definition)
	return {}

static func available(profile: ELProfile) -> Array[String]:
	var result: Array[String] = []
	if profile == null or profile.id != "el2": return result
	for definition: Dictionary in DEFINITIONS:
		if _supported(profile, definition): result.append(str(definition.id))
	return result

## A canonical, fresh duel entry, including its initial ready round. Accept
## integral JSON numbers but never truncate a fraction or coerce a string/bool.
static func battle_entry(profile: ELProfile, id: String, charges: Variant) -> Dictionary:
	if not _integer(charges, 0, CAPACITY): return {}
	var row := find(profile, id)
	if row.is_empty() or id not in available(profile): return {}
	var text_key: String = profile.table("CombatSpells")[row.card].Name
	return {"name": NAME_PREFIX + id, "spell": row.card, "charges": int(charges), "ready_round": int(row.first),
		"custom": {"elk_name": text_key, "spell": row.card, "first": int(row.first), "gap": COOLDOWN,
			"max": CAPACITY, "icon": -1, "r_count": 0, "r_duration": 0}}

## Validate one finished/saved duel's field item before the run writes back
## its real charges. Ordinary carried artifacts are left alone. Missing,
## duplicated or alien reserved entries are invalid, including for no item.
## ARTF can conserve a charge, but combat can never increase the starting count.
static func remaining_charges(profile: ELProfile, id: String, starting_charges: Variant, entries: Array) -> int:
	if profile == null or profile.id != "el2" or not _integer(starting_charges, 0, CAPACITY): return -1
	if id.is_empty() and int(starting_charges) != 0: return -1
	var expected := {} if id.is_empty() else battle_entry(profile, id, starting_charges)
	if not id.is_empty() and expected.is_empty(): return -1
	var found := false
	var remaining := 0
	for raw: Variant in entries:
		if raw is not Dictionary or raw.get("name") is not String: return -1
		if not str(raw.name).begins_with(NAME_PREFIX): continue
		if found or expected.is_empty() or raw.name != expected.name: return -1
		found = true
		if raw.get("spell") is not String or raw.spell != expected.spell: return -1
		if not _integer(raw.get("charges"), 0, int(starting_charges)): return -1
		if not _integer(raw.get("ready_round"), int(expected.ready_round), 2147483647): return -1
		var custom: Variant = raw.get("custom")
		if custom is not Dictionary or custom.size() != expected.custom.size(): return -1
		for key: String in expected.custom:
			var value: Variant = expected.custom[key]
			if value is String:
				if custom.get(key) is not String or custom[key] != value: return -1
			elif not _integer(custom.get(key), int(value), int(value)): return -1
		remaining = int(raw.charges)
	return remaining if found or id.is_empty() else -1

static func _entry(profile: ELProfile, definition: Dictionary) -> Dictionary:
	var language := int(ELRemakeText.language(profile) == "ru")
	var card: String = definition.card
	var spell: Dictionary = profile.table("CombatSpells").get(card, {})
	var title := profile.text(str(spell.get("Name", card)))
	var timing := ("From round %d, in your attack phase. Uses no ether or hand card. Holds up to two charges and shares your normal artifact-use limit." if language == 0
		else "С %d-го раунда, в свою фазу атаки. Эфир и карта из руки не расходуются. Вместимость — два заряда; действует общий лимит применений артефактов за бой.") % int(definition.first)
	return {"id": str(definition.id), "card": card, "spell": card, "title": title,
		"description": str(definition.description[language]), "context": timing + " " + str(definition.note[language]),
		"capacity": CAPACITY, "first": int(definition.first), "gap": COOLDOWN,
		"source": "card-" + card.to_lower()}

static func _supported(profile: ELProfile, definition: Dictionary) -> bool:
	var card: String = definition.card
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	if (row.is_empty() or row.get("Name") is not String or str(row.Name).is_empty()
		or row.get("Class") != "Sorcery" or row.get("Use", "+") != "+"
		or row.get("UseIn", "Both") not in ["Both", "Attack"]
		or str(row.get("IsArtifact", "False")).to_lower() == "true"
		or str(row.get("Support", "False")).to_lower() == "true"
		or ELCatalog.adventure_only_card(profile, card)): return false
	var rule := ELCatalog.rule(profile, card)
	return (not rule.is_empty() and rule.get("effect") == definition.effect
		and not rule.get("variable", false) and int(rule.get("splash_side", 0)) == 0)

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
		and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high))
