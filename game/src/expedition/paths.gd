class_name ELExpeditionPaths
extends RefCounted
## Study paths select existing printed spells; they never change card rules.
## Caller-owned pools retain the run's copy limits and reward/shop exclusions.
## Missing or unaffordable focus cards leave the ordinary offer in place.

const DEFINITIONS := [
	{"id": "red_raiders", "faction": "Red", "races": ["Rat", "Kobold"],
		"cards": ["STRT", "DRAT", "PRAT", "DMRT", "KBWR", "KBGD", "KBEL", "KBSH", "STRG", "LSST", "JYHD", "CRBL", "IMML", "CLIG"],
		"title": ["Ash Raiders", "Пепельные налётчики"],
		"description": ["Chaot rats and kobolds attack early. Crystal Ball grants First Strike; power spells make the small creatures hit harder.", "Крысы и кобольды Хаотов идут в раннюю атаку. Огненный Кулак даёт первый удар, а усиления помогают небольшим созданиям бить сильнее."]},
	{"id": "red_cinders", "faction": "Red", "races": ["Orc", "Wall"],
		"cards": ["WLBR", "WLMG", "WLLV", "WLIF", "ORSH", "ORGD", "ORWR", "OREL", "ZAPP", "FRWA", "COMT", "FRBL", "RNST", "TREM", "GEYS", "MNBR"],
		"title": ["Cinder Circle", "Круг углей"],
		"description": ["Chaot walls and orcs buy time for Fireball and Rain of Stones. Ether Breeze helps supply the ether they need.", "Стены и орки Хаотов дают время для Огненного Шара и Каменного Дождя. Эфирный Бриз помогает оплатить их применение."]},
	{"id": "red_night", "faction": "Red", "races": ["Bat", "Wolf"],
		"cards": ["BATT", "GBAT", "VBAT", "NWLF", "SHWL", "WEAK", "STRG", "CRBL", "RIOT", "FLIC", "CNBL"],
		"title": ["Night Hunters", "Ночные охотники"],
		"description": ["Chaot wolves press the attack while bats gather overhead. Vampire Bats drain life from the enemy hero, drawing strength from the flock.", "Волки Хаотов наступают, пока над ними собираются летучие мыши. Мышь-вампир отнимает здоровье вражеского героя; чем больше стая, тем сильнее способность."]},
	{"id": "green_swarm", "faction": "Green", "races": ["Bee", "Tick"],
		"cards": ["BEWK", "BEWR", "BEQN", "MOBE", "TIWK", "TIWR", "TIQN", "MOTI", "HAST", "DOMN", "STWO", "SYMB", "MNTX", "ENWO"],
		"title": ["Living Swarm", "Живой рой"],
		"description": ["Vital bees and ticks fill the field. Bee Queens strengthen bees; Mother Ticks summon more Tick Warriors and make ticks Restless.", "Пчёлы и клещи Виталов заполняют поле. Королевы усиливают пчёл; матки призывают новых клещей-воинов и делают клещей неутомимыми."]},
	{"id": "green_grove", "faction": "Green", "races": ["Treant", "Fingus"],
		"cards": ["TNSA", "TANT", "GRTN", "ANTN", "SPFG", "CAFG", "GIFG", "GRFG", "CANV", "CMBN", "BLSS", "UPGD", "VTLY", "SPLK", "ETTD", "SHCL"],
		"title": ["Living Grove", "Живая роща"],
		"description": ["Vital treants regenerate; finguses defend and fire spores instead of attacking. Healing and sacrifice spells support both.", "Древни Виталов регенерируют; фингусы защищаются и стреляют спорами вместо атаки. Обоих поддерживают лечение и жертвоприношения."]},
	{"id": "green_venom", "faction": "Green", "races": ["Snake"],
		"cards": ["GRSN", "TRSN", "SWSN", "LASN", "SPBA", "ENVM", "FTDS", "TRAD", "THIF", "DNFR", "DRFR", "LSHE", "MNTH"],
		"title": ["Venom Trail", "Ядовитая тропа"],
		"description": ["Vital Tree Snakes and Swamp Snakes leave venom when they hit a hero. Envenoming keeps the damage coming while you defend.", "Древесные и болотные змеи Виталов оставляют яд, ранив героя. Отравление продолжает наносить урон, пока вы держите оборону."]},
	{"id": "blue_sky", "faction": "Blue", "races": ["Aviak", "Halo"],
		"cards": ["RVHL", "SEHL", "SWHL", "AVSC", "AVAS", "AVMK", "AVEL", "SPWR", "MGHT", "STAT", "SCSK", "FLOD", "ICST", "CLNP", "AILK"],
		"title": ["Sky Patrol", "Небесный дозор"],
		"description": ["Kinet aviaks and halos fly over ground blockers. Spirit of War gets a creature up and makes it Restless.", "Авиаки и нимбы Кинетов перелетают наземную защиту. Дух Войны поднимает создание и делает его неутомимым."]},
	{"id": "blue_tide", "faction": "Blue", "races": ["Gibberling"],
		"cards": ["GBBR", "GBIN", "GBGN", "LSUS", "UNSM", "FOGG", "HOAM", "ENFR", "LSDS", "BANN", "STAT", "TGSK"],
		"title": ["Mist Skirmishers", "Туманные застрельщики"],
		"description": ["Kinet gibberlings attack through gaps opened by Unsummon. Fog stops combat damage when the enemy's reply is too strong.", "Гибберлины Кинетов атакуют через бреши, открытые Развоплощением. Туман останавливает физический урон, когда ответ противника слишком силён."]},
	{"id": "blue_spirits", "faction": "Blue", "races": ["Spirit", "Elemental"],
		"cards": ["WRSP", "SHSP", "CLSP", "WZSP", "FREL", "EREL", "AREL", "WTEL", "WTLK", "COPL", "BLNC", "JUST", "SHSK", "CLNP", "SGHT", "SHFR"],
		"title": ["Spirit Covenant", "Завет призраков"],
		"description": ["Kinet spirits and elementals sustain a long fight. Life Channel heals your hero whenever any creature uses Regeneration.", "Призраки и элементали Кинетов выдерживают долгий бой. Канал Жизни лечит вашего героя, когда любое создание использует регенерацию."]},
	{"id": "black_forge", "faction": "Black", "races": ["Abomination", "Mechos"],
		"cards": ["BRAB", "IRAB", "STAB", "BRMC", "IRMC", "STMC", "REPR", "RPST", "JRRG", "BDEX", "RBRT", "SCBR", "SLRP", "REDR"],
		"title": ["Scrap Custodians", "Хранители лома"],
		"description": ["Synthet abominations regenerate, while mechos punish close combat. Repair and Reanimate return fallen creatures to your hand.", "Исчадия Синтетов регенерируют, а мехосы опасны в ближнем бою. Ремонт и Реанимация возвращают павших созданий вам в руку."]},
	{"id": "black_augment", "faction": "Black", "races": ["Hopper", "Velos", "Pteros"],
		"cards": ["MNHP", "HOPR", "MXHP", "SMVL", "BGVL", "PTRS", "RFPT", "TWEN", "OVRL", "ALST", "CLFR", "ENAL", "QKFX", "RECL"],
		"title": ["Workshop Vanguard", "Цеховой авангард"],
		"description": ["Synthet hoppers act as soon as they arrive. Enhance your machines, or use Cloak of Fear to make a creature unblockable.", "Прыгуны Синтетов действуют сразу после вызова. Усиливайте машины или применяйте Маску Ужаса, чтобы создание стало неблокируемым."]},
	{"id": "black_toxin", "faction": "Black", "races": ["Mechworm", "Cutter", "Wall"],
		"cards": ["MCWO", "MCWU", "MCWY", "CTMN", "SWMN", "RZMN", "WLIL", "PHWL", "WETX", "STTX", "TPLF", "ENFL", "DWND", "DISM", "IRRT", "MDNS", "PRFY", "DPGS", "DRGS"],
		"title": ["Toxin Foundry", "Ядовитая литейная"],
		"description": ["Synthet Mech Worms attack aggressively; walls buy time for Weak Toxin and Strong Toxin. Cutters strip enchantments from creatures they hit.", "Механические черви Синтетов рвутся в атаку; стены дают время Слабому и Сильному Токсину. Резаки снимают чары с созданий, которых ранят."]},
]

static func paths(profile: ELProfile, faction: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if profile == null or profile.id != "el2": return result
	for definition: Dictionary in DEFINITIONS:
		if definition.faction == faction: result.append(_path(profile, definition))
	return result

static func find(profile: ELProfile, id: String) -> Dictionary:
	if profile == null or profile.id != "el2": return {}
	for definition: Dictionary in DEFINITIONS:
		if definition.id == id: return _path(profile, definition)
	return {}

static func candidates(profile: ELProfile, id: String, pool: Array[String], act: int, practiced := false) -> Array[String]:
	var result: Array[String] = []
	if act < 1 or act > 3: return result
	var path := find(profile, id)
	if path.is_empty(): return result
	var ceiling: int = [3, 5, 8][act - 1]
	for code: String in pool:
		# The first Spirits cost four ether. New journeys can establish this
		# school in Act I; previous rules keep their three-ether support pool.
		var limit := 4 if practiced and act == 1 and id == "blue_spirits" and code in ["WRSP", "SHSP"] else ceiling
		if code not in result and code in path.cards and ELEncyclopaedia.cost(profile, code) <= limit:
			result.append(code)
	result.sort()
	return result

static func _path(profile: ELProfile, definition: Dictionary) -> Dictionary:
	var cards: Array[String] = []
	var spells := profile.table("CombatSpells")
	var creatures := profile.table("CombatCreatures")
	for code: String in spells:
		var row: Dictionary = spells[code]
		var matched: bool = code in definition.cards
		if row.get("Class", "") == "Creature" and creatures.get(code, {}).get("Race", "") in definition.races:
			matched = true
		if not matched or row.get("Use", "+") != "+": continue
		if str(row.get("IsArtifact", "False")).to_lower() == "true": continue
		if not ELDuelCosts.spell_allowed(profile, code, definition.faction) or ELCatalog.rule(profile, code).is_empty(): continue
		cards.append(code)
	cards.sort()
	var language := int(ELRemakeText.language(profile) == "ru")
	return {"id": definition.id, "faction": definition.faction,
		"title": definition.title[language], "description": definition.description[language], "cards": cards}
