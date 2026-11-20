class_name ELExpeditionEncounters
extends RefCounted
## Opponents reuse the mounted Etherlords II campaign's mob definitions.

const BOSSES := [
	["e2mission31_41_51", "m41 - Worm Queen"],
	["e2mission23", "m23 - Mother Tick"],
	["e2mission34_44_54", "m54 - White Lord"],
]
const ALTERNATE_BOSSES := [
	[["e2mission13", "m13 - Bee Hive Boss"], 4, 21],
	[["e2mission24_32", "m24 - Red Dragon"], 5, 32],
]
const FIGHTS := [
	[
		["e2mission11", "m11 - Fingus Spitting"],
		["e2mission11", "m11 - Bee Warrior"],
		["e2mission21", "m21 - Stink Rat"],
		["e2mission21", "m21 - River Halo"],
		["e2mission31_41_51", "m41 - Bronze Abomination"],
	],
	[
		["e2mission22_53", "m22 - Disease Rat"],
		["e2mission22_53", "m22 - Magic Hornet"],
		["e2mission22_53", "m22 - Orc Guard"],
		["e2mission21", "m21 - Aviak Assassin"],
	],
	[
		["e2mission33", "m33 - Sorcerer2"],
		["e2mission33", "m33 - Shaman Spirit"],
		["e2mission33", "m33 - Bee Queen"],
		["e2mission43", "m43 - Wyrm"],
	],
]
const ELITES := [
	[
		["e2mission11", "m11 - Synth Boss"],
		["e2mission21", "m21 - KHero03"],
	],
	[
		["e2mission22_53", "m22 - SHero1"],
		["e2mission22_53", "m22 - KHero2"],
		["e2mission23", "m23 - Pale Reaper"],
	],
	[
		["e2mission33", "m33 - Lamia Warlord"],
		["e2mission43", "m43 - Fighter3"],
		["e2mission43", "m43 - Devourer3 (Boss)"],
	],
]
const BOSS_LEVELS := [3, 7, 7]
const BOSS_HEALTH := [19, 30, 45]
const BOSS_VARIABLES := [{"Adv_WormsCount": 2.0}, {"Adv_TickCount": 2.0}, {}]

## Small packages reinforce the original encounter's identity. They do not
## replace a campaign spellbook wholesale, add free creatures, or change boss
## scripts. Early fights keep gentle curves; persistent damage starts in Act II.
const TACTICS := [
	{"id": "brood", "requires": ["BEWK"], "faction": "Green", "act": 1,
		"anchors": ["BEWK", "BEWR", "BEQN", "MOBE"], "races": ["Bee"],
		"cards": ["BEWK", "UPGD", "BEQN", "BEWR", "STWO", "MOBE"],
		"title": ["Brood Keepers", "Хранители роя"],
		"hint": ["Vital bee swarms grow stronger around their queens and support creatures. Remove that support before the swarm fills the field.", "Рой Виталов крепнет вокруг королев и поддерживающих созданий. Уберите поддержку, пока пчёлы не заполнили поле."]},
	{"id": "grove", "requires": ["TNSA", "UPGD"], "faction": "Green", "act": 1,
		"anchors": ["TNSA", "TANT", "GRTN", "ANTN"], "races": ["Treant"],
		"cards": ["TNSA", "UPGD", "TANT", "BLSS", "GRTN", "VTLY"],
		"title": ["Living Grove", "Живая роща"],
		"hint": ["Vital treants can regenerate for ether. Count the enemy's spare ether before trading away your attackers.", "Древни Виталов могут регенерировать за эфир. Перед разменом проверьте, сколько эфира осталось у противника."]},
	{"id": "venom", "requires": ["SWSN"], "faction": "Green", "act": 2,
		"anchors": ["GRSN", "TRSN", "SWSN", "LASN"], "races": ["Snake"],
		"cards": ["SWSN", "SPBA", "TRSN", "UPGD", "TRAD", "THIF"],
		"title": ["Venom Trail", "Ядовитая тропа"],
		"hint": ["Vital Tree and Swamp Snakes poison heroes they hit. Block the hit, or remove Snake Venom afterward.", "Древесные и болотные змеи Виталов отравляют героев, которых ранят. Заблокируйте удар или снимите Змеиный яд после него."]},
	{"id": "offering", "requires": ["CANV"], "faction": "Green", "act": 1,
		"anchors": ["CAFG", "SPFG", "GIFG", "GRFG"], "races": ["Fingus"],
		"cards": ["CAFG", "CANV", "SPFG", "SYMB", "SPLK", "BLSS"],
		"title": ["Fungal Offering", "Грибное подношение"],
		"hint": ["Force of Sacrifice turns a Vital creature into healing, damage and another spell. Remove valuable sacrifices before the enemy can use them.", "Сила жертвоприношения превращает создание Виталов в лечение, урон и новое заклинание. Уничтожайте ценные жертвы до ритуала."]},
	{"id": "raiders", "requires": ["STRG"], "faction": "Red", "act": 1,
		"anchors": ["STRT", "DRAT", "PRAT", "DMRT", "KBWR", "KBGD", "KBEL"], "races": ["Rat", "Kobold"],
		"cards": ["KBWR", "STRG", "DRAT", "CLIG", "KBEL", "PRAT"],
		"title": ["Ash Raiders", "Пепельные налётчики"],
		"hint": ["Chaot rats and kobolds become dangerous with power spells. Trade early, before a small attacker gains a large advantage.", "Крысы и кобольды Хаотов опасны под усиливающими чарами. Разменивайтесь раньше, пока небольшой боец не получил большое преимущество."]},
	{"id": "cinder", "requires": ["ZAPP"], "faction": "Red", "act": 1,
		"anchors": ["ORSH", "ORGD", "ORWR", "OREL", "GROG", "OGKN", "CCLP"], "races": ["Orc", "Ogre", "Cyclope"],
		"cards": ["ORSH", "ZAPP", "COMT", "CLIG", "ORGD", "FRBL"],
		"title": ["Cinder Circle", "Круг углей"],
		"hint": ["Chaot fire and lightning can strike your hero directly. A line of creatures alone will not protect low life.", "Огонь и молнии Хаотов бьют прямо по герою. Одних созданий на поле мало, если здоровья осталось немного."]},
	{"id": "night", "requires": ["BATT", "WEAK"], "faction": "Red", "act": 1,
		"anchors": ["BATT", "GBAT", "VBAT", "NWLF", "SHWL"], "races": ["Bat", "Wolf"],
		"cards": ["BATT", "WEAK", "NWLF", "STRG", "GBAT", "WNFL"],
		"title": ["Night Hunters", "Ночные охотники"],
		"hint": ["Chaot bats fly over ground blockers while weakening spells spoil your defenses. Keep a flying defender or a damage spell ready.", "Летучие мыши Хаотов обходят наземных защитников, а ослабляющие чары мешают обороне. Приберегите летуна или наносящее урон заклинание."]},
	{"id": "sky", "requires": ["SPWR"], "faction": "Blue", "act": 1,
		"anchors": ["RVHL", "SEHL", "SWHL", "AVAS", "AVMK", "AVSC", "AVEL"], "races": ["Halo", "Aviak"],
		"cards": ["RVHL", "SPWR", "AVMK", "CLNP", "SEHL", "AVAS"],
		"title": ["Sky Patrol", "Небесный дозор"],
		"hint": ["Spirit of War makes Kinet flyers Restless. They do not rest after attacking, so expect them to block your reply.", "Дух Войны делает летунов Кинетов неутомимыми. Они не отдыхают после атаки и могут блокировать ваш ответный удар."]},
	{"id": "tide", "requires": ["LSUS"], "faction": "Blue", "act": 1,
		"anchors": ["GBBR", "GBGN", "GBIN"], "races": ["Gibberling"],
		"cards": ["GBBR", "LSUS", "GBIN", "STAT", "UNSM", "SPWR"],
		"title": ["Mist Skirmishers", "Туманные застрельщики"],
		"hint": ["Kinet gibberlings attack when your creatures return to hand. Avoid putting all your ether into one enhanced blocker.", "Гибберлины Кинетов атакуют, когда ваших созданий возвращают в руку. Не вкладывайте весь эфир в одного усиленного защитника."]},
	{"id": "spirits", "requires": ["WTLK"], "faction": "Blue", "act": 2,
		"anchors": ["WRSP", "SHSP", "CLSP", "WZSP"], "races": ["Spirit"],
		"cards": ["WRSP", "WTLK", "SHSP", "SPWR", "WZSP", "CLSP"],
		"title": ["Spirit Covenant", "Завет призраков"],
		"hint": ["Water Link returns a fallen Kinet spirit to play. Remove the enchantment first, or send the creature somewhere other than the graveyard.", "Водная Связь возвращает павшего призрака Кинетов в игру. Сначала снимите чары или уберите создание, не отправляя его в могильник."]},
	{"id": "repair", "requires": ["REPR"], "faction": "Black", "act": 1,
		"anchors": ["BRAB", "IRAB", "STAB", "BRMC", "IRMC", "STMC"], "races": ["Abomination", "Mechos"],
		"cards": ["BRAB", "REPR", "IRAB", "RPST", "BRMC", "BDEX"],
		"title": ["Scrap Custodians", "Хранители лома"],
		"hint": ["Synthet Repair returns a fallen creature to hand and damages your hero. Removing creatures from the graveyard can deny it a target.", "Ремонт Синтетов возвращает павшее создание в руку и ранит вашего героя. Удаление созданий из могильника лишает его цели."]},
	{"id": "augment", "requires": ["TWEN"], "faction": "Black", "act": 1,
		"anchors": ["MNHP", "HOPR", "MXHP", "SMVL", "BGVL", "PTRS", "RFPT"], "races": ["Hopper", "Velos", "Pteros"],
		"cards": ["MNHP", "TWEN", "HOPR", "CLFR", "BGVL", "QKFX"],
		"title": ["Workshop Vanguard", "Цеховой авангард"],
		"hint": ["Enhanced Synthet machines can become unblockable through Cloak of Fear. Keep an answer to their enchantments as well as their bodies.", "Усиленные машины Синтетов могут стать неблокируемыми под Маской Ужаса. Готовьтесь убирать не только создания, но и их чары."]},
	{"id": "toxin", "requires": ["WETX"], "faction": "Black", "act": 2,
		"anchors": ["MCWO", "MCWU", "MCWY", "CTMN", "SWMN", "RZMN"], "races": ["Wurm", "Worm", "Cutter"],
		"cards": ["MCWO", "WETX", "MCWU", "PRFY", "TPLF", "CLFR"],
		"title": ["Toxin Foundry", "Ядовитая литейная"],
		"hint": ["Synthet toxins keep hurting your hero while machines attack. Remove the hero enchantments early, or press for a quick finish.", "Токсины Синтетов продолжают ранить героя, пока машины атакуют. Снимайте чары с героя раньше или торопитесь закончить бой."]},
]

## Returns a duel player specification for side 1. Arena and optional script
## keys are battle options. Health and mana levels are tuned to the run.
static func build(profile: ELProfile, kind: String, floor: int, seed: int, varied_guardians := false, met: Array[String] = [], tactical := false, floors_per_act := 6) -> Dictionary:
	if profile == null or profile.id != "el2" or kind not in ["fight", "elite", "boss"]: return {}
	floors_per_act = maxi(1, floors_per_act)
	var index := maxi(0, floor - 1)
	@warning_ignore("integer_division")
	var act := clampi(index / floors_per_act, 0, BOSSES.size() - 1)
	# New routes have room for more events. Stretch the old strength curve
	# across them rather than accidentally escalating the late floors twice.
	@warning_ignore("integer_division")
	var offset := mini(5, (index % floors_per_act) * 6 / floors_per_act)
	var arena_roll := (seed >> 9) ^ floor
	if kind == "boss":
		# A different seed bit from the one that chooses the opening side.
		if varied_guardians and act < ALTERNATE_BOSSES.size() and (seed & 0x100) != 0:
			var choice: Array = ALTERNATE_BOSSES[act]
			var alternate := _opponent(profile, choice[0], arena_roll)
			if not alternate.is_empty():
				alternate.level = choice[1]
				alternate.health = choice[2]
				return alternate
		var boss := _opponent(profile, BOSSES[act], arena_roll)
		if boss.is_empty(): return {}
		boss.health = BOSS_HEALTH[act]
		boss.level = BOSS_LEVELS[act]
		boss.script_variables = BOSS_VARIABLES[act].duplicate()
		# The final expedition boss keeps his original spells and wards. The
		# campaign's gentler script setting gives a drafted book time to act.
		if act == BOSSES.size() - 1: boss.script_difficulty = 0
		return boss
	var elite := kind == "elite"
	var pool: Array = ELITES[act] if elite else FIGHTS[act]
	var random := RandomNumberGenerator.new()
	random.seed = seed ^ (floor * 0x9e3779b9)
	var first := random.randi_range(0, pool.size() - 1)
	var fresh: Array = []
	var repeats: Array = []
	for i in pool.size():
		var source: Array = pool[(first + i) % pool.size()]
		if source[1] in met: repeats.append(source)
		else: fresh.append(source)
	fresh.append_array(repeats)
	for source: Array in fresh:
		var opponent := _opponent(profile, source, arena_roll)
		if opponent.is_empty(): continue
		@warning_ignore("integer_division")
		opponent.level = 1 + 2 * act + offset / 3 + int(elite)
		opponent.health = (14 + 8 * act if elite else 10 + 6 * act) + offset
		return apply_tactics(profile, opponent, kind, act + 1, offset, seed) if tactical else opponent
	return {}

## The original opponent remains the source of visuals, skills and signature
## creatures. This pure transformation is also used by the asset-free checks.
static func apply_tactics(profile: ELProfile, opponent: Dictionary, kind: String, act: int, offset: int, seed: int) -> Dictionary:
	if profile == null or profile.id != "el2" or opponent.is_empty(): return opponent
	if kind not in ["fight", "elite"] or opponent.has("scripts"): return opponent
	# Keep the opening duel familiar. A quarter of other ordinary opponents
	# also retain their campaign plan, so every encounter is not a variant.
	if kind == "fight" and ((act == 1 and offset == 0) or ((seed >> 5) & 3) == 0): return opponent
	var original: Array = opponent.get("cards", [])
	if original.size() < 4: return opponent
	var faction := str(opponent.get("faction", ""))
	var pool: Array[Dictionary] = []
	var best_score := -1
	for plan: Dictionary in TACTICS:
		if plan.faction != faction or int(plan.act) > act: continue
		var score := _tactic_score(profile, original, plan)
		if score > best_score:
			pool.clear()
			best_score = score
		if score == best_score: pool.append(plan)
	if pool.is_empty(): return opponent
	var random := RandomNumberGenerator.new()
	random.seed = seed ^ 0x34d7e61b
	var first := random.randi_range(0, pool.size() - 1)
	for i in pool.size():
		var plan: Dictionary = pool[(first + i) % pool.size()]
		var cards := _reinforced_cards(profile, original, faction, plan, kind, act, random)
		if cards.is_empty(): continue
		var result := opponent.duplicate(true)
		result.cards = cards
		var language := int(_russian(profile))
		result.strategy_id = plan.id
		result.strategy_title = plan.title[language]
		result.strategy_hint = plan.hint[language]
		return result
	return opponent

static func _tactic_score(profile: ELProfile, cards: Array, plan: Dictionary) -> int:
	var score := 0
	var seen := {}
	for code: String in cards:
		if seen.has(code): continue
		seen[code] = true
		if code in plan.anchors: score += 3
		var creature: Dictionary = profile.table("CombatCreatures").get(code, {})
		if creature.get("Race", "") in plan.races: score += 1
	return score

static func _reinforced_cards(profile: ELProfile, original: Array, faction: String, plan: Dictionary, kind: String, act: int, random: RandomNumberGenerator) -> Array[String]:
	var cards: Array[String] = []
	var unavailable: Array[String] = []
	cards.assign(original)
	var spells := profile.table("CombatSpells")
	var protected := {}
	var signatures := {}
	var original_creatures := 0
	for index in cards.size():
		var code: String = cards[index]
		if spells.get(code, {}).get("Class", "") != "Creature": continue
		original_creatures += 1
		# Retain one copy of every original creature, including a unique boss
		# support or unusual faction creature. Keep the encounter recognisable.
		if not signatures.has(code):
			signatures[code] = true
			protected[index] = true
	@warning_ignore("integer_division")
	var limit := mini(cards.size() / 2, 3 + int(kind == "elite") + int(act == 3))
	var changed := {}
	var creatures := original_creatures
	var minimum_creatures := mini(original_creatures, maxi(4, ceili(original_creatures * 0.5)))
	for incoming: String in plan.cards:
		if changed.size() >= limit: break
		if not ELDuelCosts.spell_allowed(profile, incoming, faction) or ELCatalog.rule(profile, incoming).is_empty(): continue
		if spells[incoming].get("Use", "+") != "+": continue
		if cards.count(incoming) >= ELDuelCosts.EL2_COPIES: continue
		# Act I additions never require more than three ether. The hero's
		# existing late cards stay in place; new content does not clog its draw.
		if ELEncyclopaedia.cost(profile, incoming) > 3 + 2 * (act - 1): continue
		var is_creature: bool = spells[incoming].get("Class", "") == "Creature"
		var preferred: Array[int] = []
		var fallback: Array[int] = []
		for index in cards.size():
			if protected.has(index) or changed.has(index) or cards[index] == incoming: continue
			var was_creature: bool = spells.get(cards[index], {}).get("Class", "") == "Creature"
			if was_creature and not is_creature and creatures <= minimum_creatures: continue
			# Do not make the early game slower by replacing a cheap creature
			# with a higher-cost one while preserving an expensive duplicate.
			if was_creature and is_creature and ELEncyclopaedia.cost(profile, cards[index]) <= 2 and ELEncyclopaedia.cost(profile, incoming) > 2: continue
			fallback.append(index)
			if was_creature == is_creature: preferred.append(index)
		var slots := preferred if not preferred.is_empty() else fallback
		if slots.is_empty(): continue
		var slot: int = slots[random.randi_range(0, slots.size() - 1)]
		var was_creature: bool = spells.get(cards[slot], {}).get("Class", "") == "Creature"
		creatures += int(is_creature) - int(was_creature)
		cards[slot] = incoming
		changed[slot] = true
	# Do not promise an interaction in the scouting hint if an incomplete
	# installation could not supply its essential spell.
	for required: String in plan.requires:
		if required not in cards: return unavailable
	# A tactic must change at least two draws to earn its scouting label.
	if changed.size() < 2: return unavailable
	return cards

static func _russian(profile: ELProfile) -> bool:
	return ELRemakeText.language(profile) == "ru"

static func _opponent(profile: ELProfile, source: Array, arena_roll: int) -> Dictionary:
	var map := ELAdventureMap.new()
	if not map.load_map(profile, source[0]): return {}
	var variants: Dictionary = map.mobs.get(source[1], {})
	var mob: Dictionary = variants.get(1, {})
	if mob.is_empty(): return {}
	var shape := String(mob.attrs.get("shape", ""))
	var shape_row: Dictionary = profile.table("Shapes").get(shape, {})
	var faction := String(shape_row.get("Color", ""))
	if not ELCatalog.faction_known(profile, faction): return {}
	var cards: Array[String] = []
	for spell: Dictionary in ELXml.children(ELXml.child(mob, "deck"), "spell"):
		var code := String(spell.attrs.get("code", ""))
		if ELCatalog.rule(profile, code).is_empty(): return {}
		cards.append(code)
	if cards.is_empty(): return {}
	var skills := {}
	for skill: Dictionary in ELXml.children(ELXml.child(mob, "skills"), "skill"):
		skills[String(skill.attrs.type)] = int(skill.attrs.level)
	var arena := faction + ".001"
	# White Lord begins offstage in the campaign. Keep the Expedition finale
	# in his citadel and use the source terrain for placed opponents elsewhere.
	if source != BOSSES.back():
		for placed: Dictionary in map.objects:
			if placed.name != source[1] or placed.group not in ["heroes", "np_heroes"]: continue
			if placed.x < 0 or placed.y < 0: continue
			arena = ELAdventureEncounter.second_terrain_arena(map, Vector2i(placed.x, placed.y), arena_roll)
			break
	if not profile.table("CombatSceneDB").has(arena): arena = "Green.001"
	var opponent := {
		"id": source[1], "title": profile.text(mob.attrs.get("ElkName", source[1])),
		"faction": faction, "hero": ELCatalog.default_hero(profile, faction), "shape": shape,
		"kind": "hero" if mob.attrs.get("IsHero", "0") == "1" else "monster",
		"cards": cards, "skills": skills, "specialization": String(mob.attrs.get("Spec", "NONE")),
		"arena": arena,
	}
	var script := String(mob.attrs.get("Script", ""))
	if not script.is_empty(): opponent.scripts = [{"name": script, "side": 1}]
	return opponent
