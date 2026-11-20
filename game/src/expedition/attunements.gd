class_name ELExpeditionAttunements
extends RefCounted
## Expedition guardian rewards built from existing EL2 skills and spells.
## Printed rules remain unchanged. Opening enchantments are ordinary,
## dispellable copies; attaching them is not a spell cast.
## The run owns acquisition, its two major-reward slots and inactive powers.

const OPENING_MARKER := "expedition_opening_powers"
const DEFINITIONS := [
	{"id": "power_burnout", "faction": "Red", "card": "BROT",
		"title": ["Burnout", "Сожжение"],
		"description": ["Begin each duel with Burnout in play. Pay 1 ether and sacrifice one of your creatures to deal damage equal to its power to another creature or hero.",
			"Начинайте каждый бой с чарами «Сожжение». За 1 ед. эфира принесите своё создание в жертву, чтобы нанести другому созданию или герою урон, равный его силе."],
		"context": ["Once per own turn. The sacrifice is lost; the enchantment can be dispelled.",
			"Один раз за свой ход. Создание погибает; чары можно развеять."]},
	{"id": "power_crystal_ball", "faction": "Red", "card": "CRBL",
		"title": ["Crystal Ball", "Огненный Кулак"],
		"description": ["Begin each duel with Crystal Ball in play. Your creatures gain First Strike.",
			"Начинайте каждый бой с чарами «Огненный Кулак». Ваши создания получают Первый удар."],
		"context": ["Covers creatures already in play and later summons. The enchantment can be dispelled; creatures unaffected by magic keep their normal rules.",
			"Действует на уже вызванных и новых созданий. Чары можно развеять; невосприимчивые к магии создания сохраняют обычные правила."]},
	{"id": "power_ether_feeding", "faction": "Green", "card": "SPLK",
		"title": ["Ether Feeding", "Эфирная Подпитка"],
		"description": ["Begin each duel with Ether Feeding in play. Pay 2 ether and sacrifice one of your creatures to gain 2 ether channels.",
			"Начинайте каждый бой с чарами «Эфирная Подпитка». За 2 ед. эфира принесите своё создание в жертву, чтобы получить 2 эфирных канала."],
		"context": ["Once per own turn. Channels grow at the cost of your army. The enchantment can be dispelled.",
			"Один раз за свой ход. Число каналов растёт ценой вашей армии. Чары можно развеять."]},
	{"id": "power_martyrdom", "faction": "Green", "card": "CMBN",
		"title": ["Martyrdom", "Самопожертвование"],
		"description": ["Begin each duel with Martyrdom in play. Pay 1 ether and sacrifice one of your creatures to give its power and toughness to another creature, which also gains Trample.",
			"Начинайте каждый бой с чарами «Самопожертвование». За 1 ед. эфира принесите своё создание в жертву, чтобы передать его силу и здоровье другому созданию и дать ему Кровожадность."],
		"context": ["The boost lasts through the end of its controller's opponent's turn. Usable while blocking, once per own turn; the enchantment can be dispelled.",
			"Усиление длится до конца хода противника владельца усиленного создания. Можно применять в фазу защиты, один раз за свой ход; чары можно развеять."]},
	{"id": "power_hostile_ambience", "faction": "Blue", "card": "HOAM",
		"title": ["Hostile Ambience", "Враждебное Окружение"],
		"description": ["Begin each duel with Hostile Ambience in play. Enemy creatures enter play rested.",
			"Начинайте каждый бой с чарами «Враждебное Окружение». Создания противника входят в игру отдыхающими."],
		"context": ["Does not rest creatures already in play. Arrivals in Pale aspect stay ready, and creatures unaffected by magic ignore it. The enchantment can be dispelled.",
			"Не меняет состояние уже вызванных созданий. При появлении в Бесцветном Плане создания не отдыхают; невосприимчивые к магии создания тоже не затронуты. Чары можно развеять."]},
	{"id": "power_concentration", "faction": "Blue", "skill": "CONC", "rank": 1,
		"title": ["Concentration", "Медитация"],
		"description": ["Draw one additional spell every third own turn. Grants at least advanced Concentration.",
			"Каждый третий свой ход получайте одно дополнительное заклинание. Даёт как минимум вторую ступень Медитации."],
		"context": ["An existing expert rank is preserved. Drawing a spell does not create extra spellbook charges.",
			"Уже изученный экспертный ранг сохраняется. Получение заклинаний не добавляет зарядов страницам книги."]},
	{"id": "power_second_birth", "faction": "Black", "card": "SCBR",
		"title": ["Second Birth", "Второе Рождение"],
		"description": ["Begin each duel with Second Birth in play. Pay a creature's printed ether cost to return it from your graveyard to play.",
			"Начинайте каждый бой с чарами «Второе Рождение». Заплатите базовую стоимость вызова создания, чтобы вернуть его из своего могильника в игру."],
		"context": ["Once per own turn. Returning a creature does not restore spellbook charges. The enchantment can be dispelled.",
			"Один раз за свой ход. Возвращение создания не восстанавливает заряды книги. Чары можно развеять."]},
	{"id": "power_data_attraction", "faction": "Black", "card": "TRLB",
		"title": ["Data Attraction", "Притяжение Данных"],
		"description": ["Begin each duel with Data Attraction in play. Each enchantment or sorcery you cast draws one spell and deals 2 unavoidable damage to you.",
			"Начинайте каждый бой с чарами «Притяжение Данных». Каждые сотворённые вами чары или колдовство дают одно заклинание и наносят вам 2 ед. неизбежного урона."],
		"context": ["Creature spells do not trigger it. Energy Barrier cannot prevent this damage. The enchantment can be dispelled.",
			"Вызов созданий не вызывает этот эффект. Энергетический Барьер не защищает от этого урона. Чары можно развеять."]},
	{"id": "power_energy_barrier", "faction": "Colorless", "card": "ENBR",
		"title": ["Energy Barrier", "Энергетический Барьер"],
		"description": ["Begin each duel with Energy Barrier on your hero. Each magical attack deals 3 less damage to you.",
			"Начинайте каждый бой с Энергетическим Барьером на герое. Каждая магическая атака наносит вам на 3 ед. меньше урона."],
		"context": ["Does not reduce melee damage or unavoidable damage. The enchantment can be dispelled.",
			"Не уменьшает урон в ближнем бою и неизбежный урон. Чары можно развеять."]},
	{"id": "power_transfer_aspects", "faction": "Colorless", "card": "OEXC",
		"title": ["Transfer Aspects", "Обмен Планами"],
		"description": ["Begin each duel with Transfer Aspects in play. Pay 1 ether to manifest a creature in pale aspect and dissipate another creature in bright aspect.",
			"Начинайте каждый бой с чарами «Обмен Планами». За 1 ед. эфира верните создание из Бесцветного Плана и отправьте туда другое создание из Эфирного Плана."],
		"context": ["Needs one target in each aspect. Offered when your book and reserve contain suitable Pale and bright creatures. Once per own turn; the enchantment can be dispelled.",
			"Нужна цель в каждом плане. Предлагается при наличии в книге и запасе подходящих созданий для обоих планов. Один раз за свой ход; чары можно развеять."]},
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

static func is_power(id: String) -> bool:
	for definition: Dictionary in DEFINITIONS:
		if definition.id == id: return true
	return false

static func available(profile: ELProfile, race: String, book: Array[String], owned: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or profile.id != "el2" or race not in ["Red", "Green", "Blue", "Black"]: return result
	for definition: Dictionary in DEFINITIONS:
		if definition.id in owned or definition.faction not in [race, "Colorless"] or not _supported(profile, definition): continue
		if definition.id == "power_transfer_aspects" and not _aspect_pair(profile, race, book): continue
		result.append(_entry(profile, definition))
	return result

## Availability considers active and reserve pages together; the run can use
## this same target check on just the active book to explain battle readiness.
## Losing a suitable page never removes ownership of the learned power.
static func has_aspect_pair(profile: ELProfile, race: String, book: Array[String]) -> bool:
	if profile == null or profile.id != "el2" or race not in ["Red", "Green", "Blue", "Black"]: return false
	return _aspect_pair(profile, race, book)

## Used for setup only: no caller-owned skills, card or artifact arrays alias.
## The run filters inactive IDs and no-benefit Concentration offers.
static func prepare_hero(hero: Dictionary, ids: Array[String]) -> Dictionary:
	var result := hero.duplicate(true)
	if "power_concentration" in ids:
		var skills: Dictionary = result.get("skills", {}).duplicate()
		# Skill validation requires String keys, including a newly granted rank.
		skills["CONC"] = maxi(1, int(skills.get("CONC", -1)))
		result.skills = skills
	return result

## Called after the original start sequence, before the first player decision.
## This does not call cast_free: attachment must not trigger TRLB, spend a
## charge, roll specialization, or run a boss's post-cast hook.
## The marker is saved with the duel. A resumed or dispelled power is never
## reapplied. Its IDs follow caller order for the run's identity validation.
static func apply_opening(duel: ELDuel, ids: Array[String]) -> bool:
	if duel == null or duel.profile == null or duel.profile.id != "el2" or duel.heroes.size() != 2: return false
	var selected: Array[String] = []
	for id: String in ids:
		if is_power(id) and id not in selected: selected.append(id)
		elif id.begins_with("power_") and not is_power(id): return false
	if duel.setup.has(OPENING_MARKER):
		return duel.setup[OPENING_MARKER] is Array and duel.setup[OPENING_MARKER] == selected
	if duel.phase == ELDuel.Phase.FINISHED or duel.round_number != 1: return false
	# Validate the whole plan before attaching the first enchantment.
	var definitions: Array[Dictionary] = []
	for id: String in selected:
		var definition := find(duel.profile, id)
		if definition.is_empty() or definition.faction not in [str(duel.heroes[0].faction), "Colorless"] or not _supported(duel.profile, definition): return false
		if definition.skill == "CONC" and int(duel.heroes[0].skills.get("CONC", -1)) < 1: return false
		definitions.append(definition)
	for definition: Dictionary in definitions:
		if not str(definition.card).is_empty():
			duel._enchant(definition.card, 0, 0, ELCatalog.rule(duel.profile, definition.card))
	duel.setup[OPENING_MARKER] = selected.duplicate()
	return true

static func _entry(profile: ELProfile, definition: Dictionary) -> Dictionary:
	var language := int(ELRemakeText.language(profile) == "ru")
	var card := str(definition.get("card", ""))
	var skill := str(definition.get("skill", ""))
	return {"id": str(definition.id), "faction": str(definition.faction), "card": card, "skill": skill,
		"rank": int(definition.get("rank", -1)), "title": definition.title[language],
		"description": definition.description[language], "context": definition.context[language],
		"source": ("card-" + card.to_lower()) if not card.is_empty() else ("skill-" + skill.to_lower())}

static func _supported(profile: ELProfile, definition: Dictionary) -> bool:
	if str(definition.get("skill", "")) == "CONC":
		return not ELHeroSkills.definition(profile, "CONC", 1).is_empty()
	var card := str(definition.get("card", ""))
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	var expected := "White" if definition.faction == "Colorless" else str(definition.faction)
	return (not row.is_empty() and row.get("Class") == "Enchantment" and row.get("Color") == expected
		and _usable_spell(profile, card) and ELCatalog.rule(profile, card).get("effect") == "enchant")

static func _usable_spell(profile: ELProfile, card: String) -> bool:
	var row: Dictionary = profile.table("CombatSpells").get(card, {})
	return (not row.is_empty() and row.get("Use", "+") == "+"
		and str(row.get("IsArtifact", "False")).to_lower() != "true"
		and str(row.get("Support", "False")).to_lower() != "true"
		and not ELCatalog.adventure_only_card(profile, card) and not ELCatalog.rule(profile, card).is_empty())

static func _aspect_pair(profile: ELProfile, race: String, book: Array[String]) -> bool:
	var pale := false
	var bright := false
	for card: String in book:
		if not _usable_spell(profile, card) or not ELDuelCosts.spell_allowed(profile, card, race): continue
		if ELCatalog.rule(profile, card).get("effect") != "summon": continue
		var creature: Dictionary = profile.table("CombatCreatures").get(card, {})
		if creature.is_empty(): continue
		var flags := ELCatalog.flags(creature)
		if "NoTarget" in flags: continue
		# The first Pale Jammer enters in bright aspect, unlike other Pale
		# summons. It cannot by itself supply the required initial pale target.
		if "Outerplanar" in flags and card != "OSJ1": pale = true
		else: bright = true
	return pale and bright
