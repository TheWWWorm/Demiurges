class_name ELPuzzleRecipes
extends RefCounted
## Small tactical grammars. A recipe proposes a position, never certifies it.
## ELPuzzleGenerator must prove the resulting position and its quality gates.
## Randomness changes resources, bodies and assignments, not combat rules.

const VERSION := 5
const FAMILY_IDS := ["rising_floor", "crossfire", "air_corridor", "breakthrough", "pin_and_strike", "sheltered_sweep", "promotion", "inversion", "reservoir", "counterattack", "reserve_counter", "restless_horizon", "grave_clock", "borrowed_army", "survivor_route", "control_fork", "hand_overload", "funeral_math", "grave_priority", "aspect_toll", "comet_split", "trade_compensation", "carnivore_choice"]

static func families(edition: String) -> Array[String]:
	var out: Array[String] = []
	if edition not in ["el1", "el2"]: return out
	for family: String in FAMILY_IDS:
		if family in ELPuzzleZoneRecipes.FAMILIES and family not in ELPuzzleZoneRecipes.families(edition): continue
		if family in ELPuzzleSpellRecipes.FAMILIES and family not in ELPuzzleSpellRecipes.families(edition): continue
		out.append(family)
	return out

static func supports(family: String, difficulty: int) -> bool:
	if family in ELPuzzleZoneRecipes.FAMILIES: return ELPuzzleZoneRecipes.supports(family, difficulty)
	if family in ELPuzzleSpellRecipes.FAMILIES: return ELPuzzleSpellRecipes.supports(family, difficulty)
	if family in ELMortalityPuzzleRecipes.FAMILY_IDS: return ELMortalityPuzzleRecipes.supports(family, difficulty)
	if family in ["survivor_route", "control_fork"]: return difficulty in [4, 5]
	if family in ["reserve_counter", "restless_horizon"]: return difficulty in [3, 4, 5]
	if family == "grave_clock": return difficulty in [4, 5]
	if family == "borrowed_army": return difficulty in [3, 4]
	return family in FAMILY_IDS and difficulty in [2, 3, 4] and not (family in ["air_corridor", "reservoir"] and difficulty == 4)

## Semantic alternatives, used for soft session novelty. A declared variant
## remains a proposal: each concrete state still has to pass every proof gate.
static func variants(family: String, difficulty: int) -> Array[String]:
	var out: Array[String] = []
	if not supports(family, difficulty): return out
	if family in ELPuzzleZoneRecipes.FAMILIES: return ELPuzzleZoneRecipes.variants(family, difficulty)
	if family in ELPuzzleSpellRecipes.FAMILIES: return ELPuzzleSpellRecipes.variants(family, difficulty)
	if family in ELMortalityPuzzleRecipes.FAMILY_IDS: return ELMortalityPuzzleRecipes.variants(family, difficulty)
	match family:
		"rising_floor": out.assign(["three_threats" if difficulty == 2 else "two_threats"])
		"crossfire": out.assign(["unequal_pings", "equal_pings"])
		"pin_and_strike": out.assign(["enhance_one_finisher" if difficulty == 4 else "open_two_air_lanes"])
		"counterattack": out.assign(["wake_then_intercept" if difficulty == 4 else "wound_then_intercept"])
		"reserve_counter": out.assign(["prepare_energize" if difficulty >= 4 else "spend_energize"])
		"restless_horizon": out.assign(["deny_reply_spell", "heal_before_reply"] if difficulty == 5 else ["protect_two_attacks"])
		"grave_clock": out.assign(["buried_relay", "living_temporary_armour", "living_lasting_armour"])
		"borrowed_army": out.assign(["evade_the_line", "pierce_the_guard"])
		"survivor_route": out.assign(["summon_sentry", "borrow_enemy_sentry"])
		"control_fork": out.assign(["air_or_ground", "trample_or_first_strike"])
		_: out.assign(["base"])
	return out

static func build(profile: ELProfile, family: String, seed_value: int, difficulty: int) -> Dictionary:
	if profile == null or profile.id not in ["el1", "el2"] or not supports(family, difficulty): return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var entry: Dictionary = {}
	match family:
		"rising_floor": entry = _rising_floor(profile, rng, difficulty)
		"crossfire": entry = _crossfire(profile, rng)
		"air_corridor": entry = _air_corridor(profile, rng)
		"breakthrough": entry = _breakthrough(profile, rng, difficulty)
		"pin_and_strike": entry = _pin_and_strike(profile, rng, difficulty)
		"sheltered_sweep": entry = _sheltered_sweep(profile, rng, difficulty)
		"promotion": entry = _promotion(profile, rng)
		"inversion": entry = _inversion(profile, rng)
		"reservoir": entry = _reservoir(profile, rng)
		"counterattack": entry = _counterattack(profile, rng, difficulty)
		"reserve_counter": entry = _reserve_counter(profile, rng, difficulty)
		"restless_horizon": entry = _restless_horizon(profile, rng, difficulty)
		"grave_clock": entry = _grave_clock(profile, rng, difficulty)
		"borrowed_army": entry = _borrowed_army(profile, rng)
		"survivor_route": entry = _survivor_route(profile, rng)
		"control_fork": entry = _control_fork(profile, rng)
		_:
			if family in ELPuzzleZoneRecipes.FAMILIES: entry = ELPuzzleZoneRecipes.build(profile, family, rng, difficulty)
			elif family in ELPuzzleSpellRecipes.FAMILIES: entry = ELPuzzleSpellRecipes.build(profile, family, rng, difficulty)
			elif family in ELMortalityPuzzleRecipes.FAMILY_IDS: entry = ELMortalityPuzzleRecipes.build(profile, family, rng, difficulty)
	if entry.is_empty(): return {}
	entry.id = "%s_random_v%d_%s_%d_%d" % [profile.id, VERSION, family, seed_value, difficulty]
	entry.level = difficulty
	var generated: Dictionary = entry.get("generated", {}).duplicate(true)
	generated.merge({"family": family, "recipe_version": VERSION, "seed": seed_value, "difficulty": difficulty}, true)
	if not generated.has("planned_own_turns"): generated.planned_own_turns = int(entry.turns)
	if not generated.has("mechanics"): generated.mechanics = _mechanics(family)
	if not generated.has("variant"):
		generated.variant = "base"
		if family == "rising_floor": generated.variant = "three_threats" if difficulty == 2 else "two_threats"
		if family == "pin_and_strike": generated.variant = "enhance_one_finisher" if difficulty == 4 else "open_two_air_lanes"
		if family == "crossfire": generated.variant = "unequal_pings" if str(entry.state.creatures["5"].card) == "KBSH" else "equal_pings"
		if family == "counterattack": generated.variant = "wake_then_intercept" if difficulty == 4 else "wound_then_intercept"
	entry.generated = generated
	if not entry.has("refutations"): entry.refutations = _traps(entry, family)
	entry.authored = true
	entry.show_supply = true
	entry.state.rng = (seed_value & 0x7fffffff) + 1
	# Decode the same boundary as a saved duel, then let actual aura/stat rules
	# settle the board. Never use the encyclopedia's English prose as a rule.
	var duel := ELDuel.new()
	duel.searching = true
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.state}): return {}
	duel._refresh_armies()
	for creature: Dictionary in duel.creatures.values():
		if int(creature.damage) >= int(creature.toughness): return {}
	entry.state = duel.snapshot()
	if not ELPuzzles.valid_entry(entry, profile.id): return {}
	return entry

static func _mechanics(family: String) -> Array:
	var tags := {
		"rising_floor": ["enhancement allocation", "worst-case blocking"],
		"crossfire": ["split removal", "damage thresholds", "flying"],
		"air_corridor": ["evasion", "remove air cover", "resource allocation"],
		"breakthrough": ["trample", "lower toughness", "ether budget"],
		"pin_and_strike": ["rest a blocker", "targeted removal", "flying"],
		"sheltered_sweep": ["global damage", "protect before sweeping", "flying"],
		"promotion": ["enhance an enemy", "power threshold", "reuse an ability"],
		"inversion": ["swap statistics", "retained damage", "creature ability"],
		"reservoir": ["ether transfer", "resource-dependent damage"],
		"counterattack": ["first strike", "defensive assignment", "channel refill"]}
	return tags.get(family, []).duplicate()

## Two attacks with a choice between an immediate counterattack and a held
## defence. The solution must retain a response to both enemy plans.
static func _reserve_counter(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var buff := str(_pick(rng, ["MGHT", "STRG"]))
	var defender := str(_pick(rng, ["LMWA", "STMC", "IRMC"]))
	var flyer := str(_pick(rng, ["BATT", "AVSC"]))
	var wall_options: Array = ["WLAR"]
	if _power(profile, defender) > _toughness(profile, "WLBZ"): wall_options.append("WLBZ")
	var wall := str(_pick(rng, wall_options))
	var power := _power(profile, "LMWD") + _bonus(profile, buff)
	var armour_options: Array = [""]
	for armour: String in ["SCSK", "SHSK"]:
		if _toughness(profile, defender) + int(ELCatalog.rule(profile, armour).toughness) < power: armour_options.append(armour)
	var armour := str(_pick(rng, armour_options))
	var guard := _unit(profile, defender, 4, 1, {"resting": true})
	if not armour.is_empty(): guard.enchantments.append(_enchant(profile, armour))
	var guard_toughness := _toughness(profile, defender) + (0 if armour.is_empty() else int(ELCatalog.rule(profile, armour).toughness))
	var hand: Array = [buff, "LSUS"]
	var preparation: Array = [_cast(buff, 2)]
	if difficulty >= 4:
		hand.append("ENRG")
		preparation.push_front(_cast("ENRG"))
	if difficulty == 5:
		hand.append("ENAL")
		preparation.push_front(_cast("ENAL"))
	var units: Array = [_unit(profile, "LMWD", 2, 0, {"resting": difficulty == 5}), _unit(profile, wall, 3, 0), guard, _unit(profile, flyer, 5, 1, {"resting": true})]
	var initial_mana := _cost(profile, hand) # The one-ether bounce is the defensive reserve.
	var position := _state(profile, units, hand, initial_mana, power * 2 - guard_toughness)
	var unready_leak := _power(profile, defender) - _toughness(profile, wall)
	# Even after an early bounce, the wall alone must not cover the ground
	# counterattack after Zap. Otherwise the reserve would be unnecessary.
	position.heroes[0].health = rng.randi_range(2, mini(6, unready_leak + 1))
	position.heroes[0].channels = 1
	position.heroes[1].channels = 1
	position.heroes[1].hand = ["ZAPP"]
	position.heroes[1].hand_slots = [-1]
	position.heroes[1].hand_view = [0]
	var energize_id := int(position.next_enchantment)
	if difficulty == 3:
		_hero_enchantment(position, profile, 0, "ENRG")
	# Existing defensive armour is allocated an enchantment ID first.
	var solution: Array = preparation.duplicate(true)
	_finish_attacks(solution, [2])
	var zap := _cast("ZAPP", 0)
	zap.side = 1
	solution.append(zap)
	solution.append(_attack_side(4, 1))
	solution.append(_attack_side(5, 1))
	solution.append(_end(1))
	solution.append(_ability(0, "energize:%d" % energize_id, 2))
	solution.append(_block(2, 4))
	solution.append(_block(3, 5))
	solution.append(_end())
	solution.append(_cast("LSUS", 5))
	_finish_attacks(solution, [2])
	var entry := _entry(position, "Keep a Reply", "Сохраните ответ",
		["The first attack is only part of the plan. What happens if the opponent attacks back, and what if it keeps both guards?", "A held ground guard can absorb part of the final attack. A counterattack instead demands a ready first-striker and the flying wall.", "Enhance the Warlord, prepare Energize when needed, and retain one ether after attacking. Ready the Warlord only when the counterattack requires it. On your next turn, the single-channel refill can bounce the small flyer if it still obstructs the finish."],
		["Первая атака — лишь часть плана. Что делать, если враг контратакует, а что — если оставит обоих защитников?", "Оставшийся дома наземный защитник поглотит часть завершающей атаки. Контратака требует готового бойца с первым ударом и летающей стены.", "Усильте Военачальника, при необходимости подготовьте Подзарядку и сохраните один эфир после атаки. Поднимайте Военачальника, когда этого требует контратака. На следующем ходу единственный канал позволит вернуть малого летуна в руку, если он мешает завершению."],
		"The first attack and the final trample damage together reach the target. Spending the defensive reserve early leaves a losing counterattack; saving it lets first strike defeat the ground attacker. If the opponent holds its army back, the next refill removes the flying blocker and opens enough trample damage instead.",
		"Первая атака и завершающий натиск вместе дают нужный урон. Ранняя трата запаса эфира оставляет проигрышную контратаку; сохранённый запас позволяет первому удару уничтожить наземного врага. Если враг оставит армию в защите, новое пополнение уберёт летающего защитника и откроет достаточный урон натиском.", solution)
	_two_turns(entry, "You have one channel. The enemy also has one channel and a Zap, with no ether initially. The enemy creatures are resting now but recover for their turn. Each Energize enchantment refreshes only when your own turn starts.", "У вас один канал. У врага также один канал и Разряд, но сейчас нет эфира. Вражеские существа отдыхают, но восстановятся к своему ходу. Каждая Подзарядка снова доступна только в начале вашего собственного хода.")
	entry.generated = {"planned_own_turns": 2, "mechanics": ["ether reserve", "conditional defence", "first strike", "trample", "channel refill"], "variant": "prepare_energize" if difficulty >= 4 else "spend_energize"}
	entry.refutations = [{"label": "Spend the reserve bouncing the flyer before the first attack", "commands": [_cast("LSUS", 5)]}]
	return entry

## The ordinary recovery step cannot ready an Instigator. Protection, attack
## readiness and the hero's safety have to be planned before the empty refill.
static func _restless_horizon(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var buff := str(_pick(rng, ["SHCL", "MGHT", "STRG"]))
	var deny_spell := difficulty == 5 and rng.randi_range(0, 1) == 0
	var shooter := str(_pick(rng, ["KBSH", "GRFG"]))
	var shot := 1 if shooter == "KBSH" else 2
	var armour := "SCSK" if shot == 1 or deny_spell else "SHSK"
	var established_buff := str(_pick(rng, ["", "SHCL", "MGHT"]))
	var attacker := _unit(profile, "GBIN", 2, 0)
	if not established_buff.is_empty(): attacker.enchantments.append(_enchant(profile, established_buff))
	var established_power := _power(profile, "GBIN") + (0 if established_buff.is_empty() else _bonus(profile, established_buff))
	var hand: Array = [buff, armour, "SPWR"]
	var solution: Array = [_cast(buff, 2), _cast(armour, 2), _cast("SPWR", 2)]
	if difficulty == 5:
		hand.append("MALS" if deny_spell else "GRHE")
		if deny_spell: solution.append(_cast("MALS", 1))
		else: solution.push_front(_cast("GRHE"))
	var units: Array = [attacker, _unit(profile, shooter, 4, 1)]
	var position := _state(profile, units, hand, _cost(profile, hand), (established_power + _bonus(profile, buff)) * 2)
	position.heroes[0].health = shot * 2 + 1 if deny_spell else (1 if difficulty == 5 else shot * 2 + 2)
	position.heroes[1].mana = 1
	position.heroes[1].channels = 1
	if difficulty == 5:
		position.heroes[1].hand = ["ZAPP"]
		position.heroes[1].hand_slots = [-1]
		position.heroes[1].hand_view = [0]
	solution.append(_attack(2))
	solution.append(_end())
	var sting := _ability(4, "sting", 2)
	sting.side = 1
	solution.append(sting)
	solution.append(_end(1))
	if difficulty == 5 and not deny_spell:
		var lightning := _cast("ZAPP", 0)
		lightning.side = 1
		solution.append(lightning)
	solution.append(_end(1))
	_finish_attacks(solution, [2])
	var entry := _entry(position, "A Second Wind", "Второе дыхание",
		["Reaching the enemy once will not be enough. Check which creature fails to recover normally.", "The enemy can aim its support damage at the attacker or the hero. Compare the full damage window with both health totals.", "Prepare the Instigator's power, toughness and Spirit of War before the first attack. At Master difficulty, also answer the enemy spell before passing: spend the useful preparations before Malison, or restore the hero when healing is available."],
		["Одного удара по врагу недостаточно. Проверьте, какое существо не восстанавливается обычным образом.", "Враг может направлять урон поддержки в атакующего или в героя. Сравните весь возможный урон с обоими запасами здоровья.", "До первой атаки подготовьте силу, выносливость и Дух Войны Подстрекателя. На уровне Мастер заранее ответьте и на заклинание врага: выполните полезную подготовку до Проклятия либо восстановите героя, если доступно лечение."],
		"The unblockable creature needs two attacks but cannot recover from resting naturally. Spirit of War keeps it ready and armour defeats the support's damage. Passing to combat before completing those preparations exposes the only winning creature. With no channels, delaying an essential preparation until the second turn cannot be repaired by a refill.",
		"Неблокируемому существу нужны две атаки, но оно не выходит из отдыха обычным образом. Дух Войны сохраняет готовность, а броня выдерживает урон поддержки. Переход к бою до завершения подготовки подставляет единственное победное существо. Каналов нет, поэтому отложенную подготовку на втором ходу нечем оплатить.", solution)
	_two_turns(entry, "Your next ether refill is zero. The opponent has one channel and its support can act in either combat phase." + (" Its fixed hand contains one Zap." if difficulty == 5 else ""), "Следующее пополнение вашего эфира равно нулю. У противника один канал; поддержка может действовать в обеих фазах боя." + (" В фиксированной руке врага один Разряд." if difficulty == 5 else ""))
	entry.generated = {"planned_own_turns": 2, "mechanics": ["no recovery", "restless", "protect the attacker", "damage window", "hand disruption" if deny_spell else "survive damage"], "variant": "deny_reply_spell" if deny_spell else ("heal_before_reply" if difficulty == 5 else "protect_two_attacks")}
	entry.refutations = [{"label": "Attack for immediate damage before preparing protection", "commands": [_cast(buff, 2), _attack(2), _end()]}]
	return entry

## A corpse becomes the next untap payment. The three-newer-corpses rule and
## the Cutter's lack of natural recovery make the ordering matter.
static func _grave_clock(profile: ELProfile, rng: RandomNumberGenerator, _difficulty: int) -> Dictionary:
	if rng.randi_range(0, 1) == 0: return _living_relay(profile, rng)
	var returnee := str(_pick(rng, ["MNHP", "HOPR"]))
	var fodder := str(_pick(rng, ["TIWR", "STRT", "MCWO"]))
	var units: Array = [_unit(profile, "CTMN", 2, 0, {"resting": true}), _unit(profile, "WLFC", 3, 0), _unit(profile, fodder, 4, 0),
		_unit(profile, "IRMZ", 5, 1), _unit(profile, "BUDG", 6, 1)]
	var hand: Array = ["OVRL", "CLFR", "ENAL"]
	var position := _state(profile, units, hand, _cost(profile, ["OVRL", "CLFR"]), _power(profile, "CTMN") * 2 + 8)
	position.heroes[0].health = 1
	position.heroes[0].grave = [returnee, "STRT", "KBSH"]
	var solution: Array = [_ability(2, "sacrifice", 4), _cast("OVRL", 2), _cast("CLFR", 2)]
	_finish_attacks(solution, [2])
	solution.append(_attack_side(5, 1))
	solution.append(_attack_side(6, 1))
	solution.append(_end(1))
	solution.append(_ability(2, "sacrifice", int(position.next_id)))
	solution.append(_block(2, 5))
	solution.append(_block(3, 6))
	solution.append(_end())
	_finish_attacks(solution, [2])
	var entry := _entry(position, "The Buried Relay", "Эстафета из могилы",
		["Your strongest creature is resting and will not recover naturally. What can pay for its readiness twice?", "The buried Hopper returns at your turn end only after three newer creatures lie above it. One sacrifice can start two different parts of the plan.", "Sacrifice the small creature to wake the Cutter, then give it Overload and Cloak of Fear. The new corpse brings back the buried Hopper at turn end. Sacrifice that returnee only if the enemy attack requires a ready Cutter; the flying wall must cover the Dragon."],
		["Ваше сильнейшее существо отдыхает и не восстанавливается само. Чем оплатить его готовность дважды?", "Погребённый Прыгун вернётся в конце вашего хода, только если над ним окажутся три более новых существа. Одна жертва может запустить сразу две части плана.", "Пожертвуйте малым существом, чтобы поднять Резчика, затем дайте ему Перегрузку и Плащ Страха. Новая могила вернёт погребённого Прыгуна в конце хода. Пожертвуйте вернувшимся, когда для ответа на атаку нужен готовый Резчик; летающая стена должна прикрыть Дракона."],
		"The first sacrifice unlocks the first attack and completes the graveyard's return condition. The returned creature is a second readiness payment. Overload decays, so the final attack uses its reduced bonus. If the Mechozaurus attacks, the Cutter survives and kills it; if it stays home, its controller loses health to the parasite instead.",
		"Первая жертва открывает первую атаку и выполняет условие возвращения из могилы. Вернувшееся существо оплачивает вторую готовность. Перегрузка ослабевает, поэтому последняя атака использует уменьшенную прибавку. Если Мехозавр атакует, Резчик переживает бой и убивает его; если остаётся дома, паразит отнимает здоровье у своего хозяина.", solution)
	_two_turns(entry, "You have no channels. The graveyard order is oldest to newest; a Hopper returns at your turn end when three newer creatures cover it.", "Каналов нет. Порядок могилы — от старых существ к новым; Прыгун возвращается в конце вашего хода, когда над ним лежат три более новых существа.")
	entry.generated = {"planned_own_turns": 2, "mechanics": ["graveyard order", "return from grave", "sacrifice for readiness", "decaying enhancement", "parasite deadline"], "variant": "buried_relay"}
	entry.refutations = [{"label": "Spend ether on Energize All to wake the Cutter", "commands": [_cast("ENAL")]}, {"label": "Sacrifice the flying wall to wake the Cutter", "commands": [_ability(2, "sacrifice", 3)]}]
	return entry

static func _living_relay(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var temporary := rng.randi_range(0, 1) == 0
	var armour := "BLSS" if temporary else "SHSK"
	# Small printed walls cannot introduce irrelevant extra attacks, while
	# their low toughness still lets the enemy trample kill an unprotected hero.
	var first_body := str(_pick(rng, ["WLAR", "WLBR"]))
	var reserve_body := str(_pick(rng, ["WLAR", "WLBR"]))
	var enemy := str(_pick(rng, ["BRMZ", "IRMZ"]))
	var units: Array = [_unit(profile, "CTMN", 2, 0, {"resting": true}), _unit(profile, first_body, 3, 0, {"sick": true}),
		_unit(profile, reserve_body, 4, 0, {"sick": true}), _unit(profile, enemy, 5, 1)]
	var hand: Array = [armour, "CLFR", "ENAL"]
	var position := _state(profile, units, hand, _cost(profile, [armour, "CLFR"]), _power(profile, "CTMN") * 2 + (4 if temporary else 0))
	position.heroes[0].health = 1
	var solution: Array = [_ability(2, "sacrifice", 3), _cast(armour, 2), _cast("CLFR", 2)]
	_finish_attacks(solution, [2])
	solution.append(_attack_side(5, 1))
	solution.append(_end(1))
	solution.append(_ability(2, "sacrifice", 4))
	solution.append(_block(2, 5))
	solution.append(_end())
	_finish_attacks(solution, [2])
	var entry := _entry(position, "The Living Relay", "Живая эстафета",
		["There are two attacks to make, but the strongest creature cannot recover naturally. Count its readiness payments before spending a body.", "The small creatures have a job beyond their attack power. One can wake the first attack; the other must still be available after it.", "Sacrifice one small creature to wake the Cutter. Give the Cutter protection and Cloak of Fear, then attack. Keep the second small creature to ready the Cutter against a counterattack or for the second attack if the enemy waits."],
		["Нужны две атаки, но сильнейшее существо не восстанавливается само. Посчитайте плату за готовность, прежде чем тратить тело.", "Малые существа полезны не только своей силой. Одно может поднять первую атаку; второе должно остаться доступным после неё.", "Пожертвуйте одним малым существом, чтобы поднять Резчика. Дайте ему защиту и Плащ Страха, затем атакуйте. Сохраните второе малое существо, чтобы поднять Резчика для ответа на контратаку либо для второй атаки, если враг ждёт."],
		"Both living allies are resources for the Cutter's unusual recovery. Its protection makes a counterattack survivable; Cloak prevents the enemy from spending its body to absorb the entire first hit. If the parasite stays home, its controller pays the turn-end health cost. " + ("Bless expires before the final attack, so count the Cutter's printed power for that last hit." if temporary else "Shell Skin adds toughness rather than attack damage: its purpose is preserving the second attack."),
		"Оба живых союзника оплачивают необычное восстановление Резчика. Защита позволяет пережить контратаку; Плащ не даёт врагу потратить своё тело на поглощение всего первого удара. Если паразит остаётся дома, его хозяин теряет здоровье в конце хода. " + ("Благословение исчезнет до последней атаки, поэтому для завершающего удара считайте печатную силу Резчика." if temporary else "Панцирь повышает выносливость, а не урон: его задача — сохранить вторую атаку."), solution)
	_two_turns(entry, "You have no channels and only one health. Both small allies are newly summoned; the graveyard starts empty.", "Каналов нет, здоровье равно единице. Оба малых союзника только что призваны; могила в начале пуста.")
	entry.generated = {"planned_own_turns": 2, "mechanics": ["sacrifice for readiness", "reserve a creature", "temporary protection" if temporary else "defensive enhancement", "unblockable", "parasite deadline"], "variant": "living_temporary_armour" if temporary else "living_lasting_armour"}
	entry.refutations = [{"label": "Spend ether on Energize All instead of the first sacrifice", "commands": [_cast("ENAL")]}]
	return entry

## Revival must solve both readiness and evasion. Choosing the biggest corpse
## is a plausible failure, even when it has much greater printed power.
static func _borrowed_army(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var evade := rng.randi_range(0, 1) == 0
	var fast_creature := str(_pick(rng, ["MNHP", "HOPR"]))
	var slow_creature := str(_pick(rng, ["GROG", "OGKN"]))
	var guard := str(_pick(rng, ["TIWR", "HOPR", "GRTN"]))
	var original := "MCWO" if _power(profile, fast_creature) > _power(profile, "MCWO") else "WLAR"
	var units: Array = [_unit(profile, original, 2, 0)]
	var hand: Array = ["BDEX", "STRG", "CLFR"] if evade else ["BDEX", "BLSS", "ALST"]
	if evade:
		units.append(_unit(profile, "STAB", 3, 1))
		units.append(_unit(profile, "WLFC", 4, 1))
	else: units.append(_unit(profile, guard, 3, 1))
	var enemy_health := _power(profile, fast_creature) + _bonus(profile, "STRG") if evade else _power(profile, fast_creature) * 2 + _bonus(profile, "BLSS") - _toughness(profile, guard)
	var position := _state(profile, units, hand, _cost(profile, hand), enemy_health)
	var fast_slot := rng.randi_range(0, 1)
	position.heroes[0].grave = [fast_creature, slow_creature] if fast_slot == 0 else [slow_creature, fast_creature]
	var exchange := _cast("BDEX", 2)
	exchange.grave = fast_slot
	var arrived := int(position.next_id)
	var solution: Array = [exchange, _cast(str(hand[1]), arrived), _cast(str(hand[2]), arrived)]
	var blocks: Array = [] if evade else [_block(3, arrived, 1)]
	_finish_attacks(solution, [arrived], blocks)
	var entry := _entry(position, "Borrowed Readiness", "Готовность взаймы",
		["The graveyard offers more than printed power. Which returned creature can actually act in time?", "The small creature in play cannot reach lethal damage with the available enhancements. Choose a replacement, then solve the blocking problem.", "Exchange your original creature for the Hopper with haste. In the wall variant, Strength and Cloak of Fear bypass both guards. In the single-guard variant, Bless and Alpha Strike produce a first-strike trampling attack; Alpha Strike adds printed power, not the enhanced total."],
		["Могила предлагает больше, чем печатную силу. Какое вернувшееся существо успеет действовать?", "Малому существу на поле не хватит доступных усилений для победного урона. Выберите замену, затем решите задачу блокирования.", "Обменяйте исходное существо на Прыгуна, способного атаковать сразу. Против стен Сила и Плащ Страха обходят обоих защитников. Против одного защитника Благословение и Альфа-Удар создают атаку с первым ударом и натиском; Альфа-Удар прибавляет печатную, а не усиленную силу."],
		"The Hopper's immediate readiness is more valuable than the Ogre's larger body. Reviving the correct creature is only the first step: the enhancement and evasion combination must then make every permitted block lose.",
		"Немедленная готовность Прыгуна важнее большого тела Огра. Вернуть правильное существо — лишь первый шаг: затем усиление и обход защиты должны сделать любой допустимый блок проигрышным.", solution)
	entry.generated = {"planned_own_turns": 1, "mechanics": ["grave selection", "body exchange", "haste", "unblockable" if evade else "first strike and trample"], "variant": "evade_the_line" if evade else "pierce_the_guard"}
	var wrong := _cast("BDEX", 2)
	wrong.grave = 1 - fast_slot
	entry.refutations = [{"label": "Revive the larger Ogre instead of the ready Hopper", "commands": [wrong]}]
	return entry

static func _hero_enchantment(position: Dictionary, profile: ELProfile, side: int, card: String) -> void:
	var enchantment := _enchant(profile, card)
	enchantment.merge({"id": int(position.next_enchantment), "owner": side, "born": int(position.turn_serial), "used": false}, true)
	position.heroes[side].enchantments.append(enchantment)
	position.next_enchantment = int(position.next_enchantment) + 1

## The enemy decides which attacker survives. The two-ether refill buys
## passage for a ground survivor or power for an airborne one, not both.
## A sentry activated in the enemy turn recovers for the final own turn.
static func _survivor_route(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var borrowed := rng.randi_range(0, 1) == 0
	var sentry := str(_pick(rng, ["GIFG", "GRFG"]))
	var shot := 1 if sentry == "GIFG" else 2
	var ground := str(_pick(rng, ["STRT", "TIWR"]))
	var flyer := str(_pick(rng, ["AVSC", "BEWR"]))
	var enemy_flyer := "BEWR" if shot == 1 else "AVSC"
	var wall := str(_pick(rng, ["RKWL", "SLWL"]))
	var units: Array = [_unit(profile, ground, 2, 0, {"sick": true}), _unit(profile, flyer, 3, 0, {"sick": true}),
		_unit(profile, wall, 4, 1), _unit(profile, enemy_flyer, 5, 1)]
	if borrowed: units.append(_unit(profile, sentry, 6, 1))
	var preparation := "CHCM" if borrowed else sentry
	var hand: Array = [preparation, "STRG", "CLFR"]
	var position := _state(profile, units, hand, _cost(profile, [preparation]), _power(profile, ground) + shot)
	position.heroes[0].health = 1
	position.heroes[0].channels = 2
	position.heroes[1].channels = _cost(profile, ["CLIG"])
	position.heroes[1].hand = ["CLIG"]
	position.heroes[1].hand_slots = [-1]
	position.heroes[1].hand_view = [0]
	var sentry_id := 6 if borrowed else int(position.next_id)
	var solution: Array = [_cast(preparation, 6 if borrowed else -1), _end()]
	var removal := _cast("CLIG", 3)
	removal.side = 1
	solution.append(removal)
	solution.append(_attack_side(5, 1))
	solution.append(_end(1))
	solution.append(_ability(sentry_id, "sting", 5))
	solution.append(_end())
	solution.append(_ability(sentry_id, "sting", 1))
	solution.append(_cast("CLFR", 2))
	_finish_attacks(solution, [2])
	var entry := _entry(position, "After Their Choice", "После их выбора",
		["You do not control which small attacker the Lightning leaves alive. Can your first preparation keep both possible endings open?", "The refill buys only one major spell. A ground survivor needs a route past the wall; a flying survivor can pass over it, but check whether the enemy flyer is still guarding.", "Acquire the sentry before passing. Sting a lethal flying attack during defence. On your next turn, the refreshed sentry can add the damage needed by a ground survivor with Cloak. If your flyer survives, use Strength and remove any enemy flyer that still guards its route."],
		["Вы не выбираете, какого малого бойца оставит в живых Молния. Сохранит ли первая подготовка оба возможных завершения?", "Пополнение оплатит лишь одно крупное заклинание. Наземному выжившему нужен путь мимо стены; летун может пролететь над ней, но проверьте, остался ли в защите вражеский летун.", "Получите часового до передачи хода. Уколом остановите смертельную воздушную атаку в фазе защиты. На следующем вашем ходу восстановившийся часовой добавит урон, нужный наземному выжившему с Плащом. Если выжил ваш летун, используйте Силу и уберите вражеского летуна, если тот всё ещё защищает путь."],
		"The opponent's removal determines the final route. Spending the first ether on an enhancement abandons the defensive preparation. After the enemy commits, the sentry can cover the air attack and then recover for a second activation. The two-channel refill cannot pay for both Strength and Cloak, so the surviving creature's movement determines which spell is useful.",
		"Удаление со стороны врага определяет завершающий путь. Ранняя трата эфира на усиление оставляет вас без защитной подготовки. После решения врага часовой может остановить воздушную атаку, затем восстановиться для второго действия. Два канала не оплатят одновременно Силу и Плащ, поэтому полезное заклинание зависит от способа передвижения выжившего.", solution)
	_two_turns(entry, "Your two small attackers are newly summoned. You have %d health and %d channels. The opponent has Lightning, %d ether now, and %d channels; it may remove either attacker on its turn. " % [int(position.heroes[0].health), int(position.heroes[0].channels), int(position.heroes[1].mana), int(position.heroes[1].channels)] + ("The durable sentry starts under enemy control." if borrowed else "The durable sentry is in your hand."),
		"Два ваших малых бойца только что призваны. Ваше здоровье: %d, каналы: %d. У противника Молния, сейчас эфира: %d, каналов: %d; на своём ходу он может убрать любого из бойцов. " % [int(position.heroes[0].health), int(position.heroes[0].channels), int(position.heroes[1].mana), int(position.heroes[1].channels)] + ("Прочный часовой начинает под контролем врага." if borrowed else "Прочный часовой находится у вас в руке."))
	entry.generated = {"planned_own_turns": 2, "mechanics": ["conditional survivor", "summoning sickness", "capture a defender" if borrowed else "summon a defender", "reuse across turns", "limited refill", "choose power or evasion"], "variant": "borrow_enemy_sentry" if borrowed else "summon_sentry"}
	entry.refutations = [{"label": "Enhance an attacker before acquiring the defensive sentry", "commands": [_cast("STRG", 2)]}]
	return entry

## A single capture is vulnerable to the opponent's dispel. Securing two
## candidates makes the second-turn finisher depend on the enemy's choice.
static func _control_fork(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var air_route := rng.randi_range(0, 1) == 0
	var rosters: Array = [["GBAT", "GROG"], ["AVSC", "TIWR"], ["BEHD", "SHWL"]] if air_route else [["LMWD", "LMWA"], ["FREL", "LMWA"], ["LMWD", "STMC"]]
	var roster: Array = _pick(rng, rosters)
	var first := str(roster[0])
	var second := str(roster[1])
	var buff := str(_pick(rng, ["STRG", "MGHT", "SHCL"]))
	var units: Array = [_unit(profile, first, 2, 1), _unit(profile, second, 3, 1)]
	var hand: Array = ["CHCM", "CHCM", "CHCM", buff, "CLFR"]
	var enemy_health := mini(_power(profile, first), _power(profile, second)) + _bonus(profile, buff)
	var position := _state(profile, units, hand, _cost(profile, ["CHCM", "CHCM"]), enemy_health)
	position.heroes[0].health = rng.randi_range(1, mini(3, mini(_power(profile, first), _power(profile, second))))
	position.heroes[0].channels = _cost(profile, [buff, "CLFR"])
	position.heroes[1].channels = _cost(profile, ["CLNP"])
	position.heroes[1].hand = ["CLNP"]
	position.heroes[1].hand_slots = [-1]
	position.heroes[1].hand_view = [0]
	var dispel := _cast("CLNP", 2)
	dispel.grave = 1 # The first Change of Command is enchantment 1.
	dispel.side = 1
	var solution: Array = [_cast("CHCM", 2), _cast("CHCM", 3), _end(), dispel, _end(1), _cast(buff, 3), _cast("CLFR", 3)]
	_finish_attacks(solution, [3])
	var entry := _entry(position, "The One Still Loyal", "Тот, кто остался верен",
		["The opponent can undo one capture. What preparation leaves a winning attacker whichever creature it frees?", "Regaining the lost creature spends the refill and makes that creature wait again. Compare that with finishing through the creature you still control.", "Use the first turn to capture both creatures. After the enemy dispels one control enchantment, enhance the one that remains yours. Use Cloak when the returned defender can obstruct that attack; an airborne survivor may already have a clear route."],
		["Враг может отменить один захват. Какая подготовка оставит победного бойца независимо от того, кого он освободит?", "Повторный захват потратит пополнение и снова заставит существо ждать. Сравните его с завершением боя через того, кто всё ещё под вашим контролем.", "На первом ходу захватите обоих существ. Когда враг рассеет одно заклятие контроля, усильте оставшегося у вас. Используйте Плащ, если вернувшийся защитник мешает этой атаке; у выжившего летуна путь уже может быть открыт."],
		"The two captures insure different possible finishers against one dispel. Both acquisitions must wait before acting, so the initial setup cannot win immediately. On the second turn, spending ether to recapture the returned creature gives up the timely attack. The surviving creature's evasion and the returned defender's traits determine the finishing spell sequence.",
		"Два захвата страхуют разных возможных завершающих бойцов от одного рассеивания. Оба приобретения должны подождать перед действием, поэтому начальная подготовка не может сразу победить. На втором ходу трата эфира на повторный захват лишает вас своевременной атаки. Уклонение оставшегося бойца и свойства вернувшегося защитника определяют порядок завершающих заклинаний.", solution)
	_two_turns(entry, "You have %d ether now and %d channels. The opponent has Lesser Disenchant, %d ether now, and %d channels. A change of controller makes these creatures wait before acting, including when a capture is dispelled." % [int(position.heroes[0].mana), int(position.heroes[0].channels), int(position.heroes[1].mana), int(position.heroes[1].channels)],
		"Сейчас у вас эфира: %d, каналов: %d. У противника Малое Рассеивание, сейчас эфира: %d, каналов: %d. Смена владельца заставляет этих существ подождать перед действием, в том числе при рассеивании захвата." % [int(position.heroes[0].mana), int(position.heroes[0].channels), int(position.heroes[1].mana), int(position.heroes[1].channels)])
	entry.generated = {"planned_own_turns": 2, "mechanics": ["temporary control", "opponent dispel", "conditional finisher", "summoning sickness", "spend on attack or recapture"], "variant": "air_or_ground" if air_route else "trample_or_first_strike"}
	entry.refutations = [{"label": "Enhance the first capture before securing the second", "commands": [_cast("CHCM", 2), _cast(buff, 2)]}]
	return entry

static func _attack_side(id: int, side: int) -> Dictionary:
	var command := _attack(id)
	command.side = side
	return command

static func _two_turns(entry: Dictionary, facts: String, facts_ru: String) -> void:
	entry.turns = 2
	entry.briefing = "Win within two of your turns, including the current one. The opponent may choose any legal actions on its intervening turn. No cards are drawn and channels do not grow automatically. " + facts
	entry.briefing_ru = "Победите за два ваших хода, включая текущий. На промежуточном ходу противник может выбирать любые допустимые действия. Новые карты не берутся; каналы не растут автоматически. " + facts_ru

## Plausible losing ideas for the verifier to test. These are hypotheses,
## not declarations that a move loses; only a completed proof may say so.
static func _traps(entry: Dictionary, family: String) -> Array:
	var hand: Array = entry.state.heroes[0].hand
	match family:
		"rising_floor":
			var greedy: Array = []
			for card: String in hand: greedy.append(_cast(card, 2))
			return [{"label": "Invest every enhancement in the strongest attacker", "commands": greedy}]
		"crossfire": return [{"label": "Use the first sting on the enemy hero", "commands": [_ability(4, "sting", 1)]}]
		"air_corridor": return [{"label": "Enhance the imposing ground attacker", "commands": [_cast(str(hand[1]), 2)]}]
		"breakthrough": return [{"label": "Buy extra armour before the assault", "commands": [_cast("SHSK", 2)]}]
		"pin_and_strike": return [{"label": "Rest the fragile guard instead of the wall", "commands": [_ability(4, "tap_target", 6)]}]
		"sheltered_sweep": return [{"label": "Sweep before protecting the fragile attacker", "commands": [_cast("LGST")]}]
		"promotion": return [{"label": "Enhance your own Huntress", "commands": [_cast(str(hand[0]), 2)]}]
		"inversion": return [{"label": "Swap the wounded creature's statistics immediately", "commands": [_cast("DELS", 2)]}]
		"reservoir": return [{"label": "Take the larger ether transfer", "commands": [_ability(3, "siphon")]}]
		"counterattack":
			if int(entry.get("level", 2)) == 4:
				return [{"label": "Spend both support activations on the flying attacker", "commands": [_ability(4, "sting", 7), _cast("ENAL"), _ability(4, "sting", 7)]}]
			return [{"label": "Spend the support damage on the flying attacker", "commands": [_ability(4, "sting", 7)]}]
	return []

static func _pick(rng: RandomNumberGenerator, choices: Array) -> Variant:
	return choices[rng.randi_range(0, choices.size() - 1)]

static func _power(profile: ELProfile, card: String) -> int:
	return int(profile.table("CombatCreatures").get(card, {}).get("Power", 0))

static func _toughness(profile: ELProfile, card: String) -> int:
	return int(profile.table("CombatCreatures").get(card, {}).get("Toughness", 0))

static func _cost(profile: ELProfile, cards: Array) -> int:
	var total := 0
	for card: String in cards: total += int(profile.table("CombatSpells").get(card, {}).get("Cost", 999))
	return total

static func _bonus(profile: ELProfile, card: String) -> int:
	return int(ELCatalog.rule(profile, card).get("power", 0))

static func _name(profile: ELProfile, card: String) -> String:
	return profile.text(str(profile.table("CombatSpells").get(card, {}).get("Name", card)))

static func _unit(profile: ELProfile, card: String, id: int, side: int, extra: Dictionary = {}) -> Dictionary:
	var row: Dictionary = profile.table("CombatCreatures").get(card, {})
	var flags := ELCatalog.flags(row)
	var value := {"id": id, "owner": side, "card": card, "power": int(row.get("Power", 0)), "toughness": int(row.get("Toughness", 1)),
		"damage": 0, "resting": false, "sick": false, "flying": flags.has("Fly"), "flags": flags, "enchantments": [], "regenerated": false}
	value.merge(extra, true)
	return value

static func _hero(profile: ELProfile, side: int, hand: Array, mana: int, health: int) -> Dictionary:
	var faction := "Blue" if side == 0 else "Red"
	var slots: Array = []
	for _card in hand: slots.append(-1)
	return {"id": side, "faction": faction, "template": ELCatalog.default_hero(profile, faction), "level": 4, "turns": 4 - side,
		"health": health, "maximum": maxi(20, health), "mana": mana, "channels": 0, "kind": "hero", "hand": hand.duplicate(),
		"hand_slots": slots, "hand_view": range(hand.size()), "deck": ["STRT"], "spell_uses": [-1 if profile.id == "el1" else 1],
		"grave": [], "drawn": [], "skills": {}, "spec": "NONE", "spec_level": 4, "luck": 0, "suppression": 0,
		"enchantments": [], "artifacts": [], "artifact_uses": 0}

static func _state(profile: ELProfile, units: Array, hand: Array, mana: int, enemy_health: int) -> Dictionary:
	var creatures := {}
	var next_id := 2
	var next_enchantment := 1
	for raw: Dictionary in units:
		var c: Dictionary = raw.duplicate(true)
		next_id = maxi(next_id, int(c.id) + 1)
		for e: Dictionary in c.enchantments:
			e.id = next_enchantment
			e.owner = int(c.owner)
			e.born = 7
			e.used = false
			next_enchantment += 1
		creatures[str(c.id)] = c
	var arena := "Green.001"
	if not profile.table("CombatSceneDB").has(arena):
		var arenas: Array = profile.table("CombatSceneDB").keys()
		if not arenas.is_empty(): arena = str(arenas[0])
	return {"profile": profile.id, "charge_version": 2, "payment_version": 1, "round": 4, "phase": 0, "attacker": 0,
		"heroes": [_hero(profile, 0, hand, mana, 20), _hero(profile, 1, [], 0, enemy_health)], "creatures": creatures,
		"attacks": [], "blocks": {}, "winner": -1, "rng": 712367, "next_id": next_id, "next_enchantment": next_enchantment, "turn_serial": 7,
		"setup": {"arena": arena, "puzzle_fixed_hands": true, "puzzle_fixed_channels": true, "players": [{"faction": "Blue", "level": 4}, {"faction": "Red", "level": 4}]}}

static func _enchant(profile: ELProfile, card: String) -> Dictionary:
	var rule := ELCatalog.rule(profile, card)
	return {"card": card, "power": int(rule.get("power", 0)), "toughness": int(rule.get("toughness", 0))}

static func _entry(state: Dictionary, title: String, title_ru: String, hints: Array, hints_ru: Array, explanation: String, explanation_ru: String, solution: Array) -> Dictionary:
	return {"state": state, "title": title, "title_ru": title_ru, "category": "Random challenge", "category_ru": "Случайная задача", "turns": 1,
		"objective": {"type": "win"}, "briefing": "Win within the displayed one-turn budget. The opponent may choose any legal defence. Your hand and natural channel growth are fixed.",
		"briefing_ru": "Победите в пределах указанного лимита в один ваш ход. Противник может выбирать любую допустимую защиту. Новых карт и автоматического роста каналов нет.",
		"hints": hints, "hints_ru": hints_ru, "explanation": explanation, "explanation_ru": explanation_ru, "solution": solution}

static func _cast(card: String, target: int = -1) -> Dictionary:
	return {"kind": "cast", "card": card, "target": target}

static func _ability(id: int, key: String, target: int = -1) -> Dictionary:
	return {"kind": "ability", "id": id, "key": key, "target": target}

static func _attack(id: int) -> Dictionary:
	return {"kind": "attack", "id": id}

static func _block(id: int, target: int, side: int = 0) -> Dictionary:
	return {"kind": "block", "id": id, "target": target, "side": side}

static func _end(side: int = 0) -> Dictionary:
	return {"kind": "end_phase", "side": side}

static func _finish_attacks(solution: Array, ids: Array, blocks: Array = []) -> void:
	for id: int in ids: solution.append(_attack(id))
	solution.append(_end())
	solution.append_array(blocks)
	solution.append(_end(1))

## Exhaustively optimize the weakest unblocked threats for this tiny recipe.
## This is only a construction heuristic; actual defence is proved separately.
static func _allocation(profile: ELProfile, powers: Array, cards: Array, blockers: int, at: int = 0, targets: Array = []) -> Dictionary:
	if at >= cards.size():
		var sorted: Array = powers.duplicate()
		sorted.sort()
		var damage := 0
		for i in maxi(0, sorted.size() - blockers): damage += int(sorted[i])
		return {"damage": damage, "targets": targets.duplicate(), "powers": powers.duplicate()}
	var best := {"damage": -1}
	for i in powers.size():
		var changed: Array = powers.duplicate()
		changed[i] = int(changed[i]) + _bonus(profile, str(cards[at]))
		var picked: Array = targets.duplicate()
		picked.append(i)
		var candidate := _allocation(profile, changed, cards, blockers, at + 1, picked)
		if int(candidate.damage) > int(best.damage): best = candidate
	return best

static func _rising_floor(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var choices: Array = [["GBAT", "BATT", "AVSC"], ["GBAT", "GBAT", "AVSC"], ["GBAT", "BATT", "BATT"]]
	# More cards create the allocation difficulty, not a larger army. With
	# two threats the defender stops the stronger; every available enhancement
	# must improve the weaker guaranteed hit at the harder settings.
	if difficulty >= 3: choices = [["GBAT", "AVSC"], ["GBAT", "BATT"], ["BATT", "AVSC"]]
	var roster: Array = _pick(rng, choices).duplicate()
	var blockers := 1
	var hand: Array = []
	for _i in difficulty - 1: hand.append(_pick(rng, ["SHCL", "MGHT", "STRG"]))
	var powers: Array = []
	var units: Array = []
	for i in roster.size():
		powers.append(_power(profile, str(roster[i])))
		units.append(_unit(profile, str(roster[i]), i + 2, 0))
	for i in blockers: units.append(_unit(profile, str(_pick(rng, ["WLBZ", "WLFC"])), roster.size() + 2 + i, 1))
	var plan := _allocation(profile, powers, hand, blockers)
	# An extra card must actually raise the best guaranteed damage.
	if hand.size() > 1:
		for omitted in hand.size():
			var reduced: Array = hand.duplicate()
			reduced.remove_at(omitted)
			if int(_allocation(profile, powers, reduced, blockers).damage) >= int(plan.damage): return {}
	var solution: Array = []
	for i in hand.size(): solution.append(_cast(str(hand[i]), int(plan.targets[i]) + 2))
	var attack_ids: Array = range(2, roster.size() + 2)
	var ranked: Array = attack_ids.duplicate()
	ranked.sort_custom(func(a: int, b: int) -> bool: return int(plan.powers[a - 2]) > int(plan.powers[b - 2]))
	var blocks: Array = []
	for i in blockers: blocks.append(_block(roster.size() + 2 + i, int(ranked[i]), 1))
	_finish_attacks(solution, attack_ids, blocks)
	var position := _state(profile, units, hand, _cost(profile, hand), int(plan.damage))
	if difficulty >= 3:
		# A visible, real counterspell clock makes a failed attack immediately
		# refutable. Zero initial ether keeps Zap unavailable during defence;
		# the existing channel funds it only on the opponent's following turn.
		position.heroes[0].health = 1
		position.heroes[1].hand = ["ZAPP"]
		position.heroes[1].hand_slots = [-1]
		position.heroes[1].hand_view = [0]
		position.heroes[1].channels = 1
	var entry := _entry(position, "A Narrow Front", "Узкий фронт",
		["Count the threats the enemy cannot block, rather than your total power.", "A larger strongest creature may absorb another block without adding any damage to the hero.", "Distribute your enhancements so that the weakest surviving group is still lethal, then attack with the whole flying formation."],
		["Считайте тех, кого враг не сможет заблокировать, а не общую силу армии.", "Ещё более сильное крупнейшее существо может просто получить блок без дополнительного урона герою.", "Распределите усиления так, чтобы даже самая слабая оставшаяся группа была смертельной, и атакуйте всеми летающими существами."],
		"The defender chooses which threats to stop. Improving the minimum damage of the unblocked group makes every legal blocking assignment lose.",
		"Защитник сам выбирает, кого остановить. Усиление минимального урона незаблокированной группы делает любое распределение блоков проигрышным.", solution)
	if difficulty >= 3:
		entry.briefing += " You have one health. The enemy holds Zap but has no ether now; its one channel funds a lethal reply when its next turn starts."
		entry.briefing_ru += " У вас одно здоровье. Враг держит Искру, но сейчас не имеет эфира; один канал оплатит смертельный ответ в начале его следующего хода."
	return entry

static func _crossfire(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var mixed := rng.randi_range(0, 1) == 1
	var spell := "CLIG" if mixed else "ZAPP"
	var flyer_a := str(_pick(rng, ["GBAT", "BATT"]))
	# One already enhanced finisher keeps the decision on damage allocation,
	# without the exponential declaration combinations of a wide army.
	# Its required damage exceeds all available direct pings together.
	var units: Array = [_unit(profile, flyer_a, 2, 0, {"enchantments": [_enchant(profile, "BLSS")]}), _unit(profile, "GRFG", 4, 0),
		_unit(profile, "KBSH" if mixed else "GRFG", 5, 0), _unit(profile, "WLAR", 6, 1), _unit(profile, "GBAT", 7, 1, {"damage": 0 if mixed else 1})]
	var solution: Array = [_ability(4, "sting", 6), _ability(5, "sting", 7), _cast(spell, 7)]
	_finish_attacks(solution, [2])
	return _entry(_state(profile, units, [spell], _cost(profile, [spell]), _power(profile, flyer_a) + _bonus(profile, "BLSS")), "Crossed Lines", "Пересекающиеся линии",
		["The guards have different amounts of health left. Your damage sources do not all deal the same amount.", "A little overkill on one guard can leave the other alive and able to stop the lethal attack.", "Use the two-point sting on the smaller guard. Combine the remaining sting and spell against the larger guard, then attack with the enhanced flyer."],
		["У защитников разное оставшееся здоровье. Ваши источники урона тоже различаются.", "Лишний урон одному защитнику может оставить второго в живых и сорвать смертельную атаку.", "Двухочковым уколом уберите меньшего защитника. Оставшийся укол и заклинание направьте в большего, затем атакуйте усиленным летуном."],
		"The separate damage sources must cover both interception points. Spending them on the hero leaves a guard that prevents the full flying attack.",
		"Разные источники урона должны убрать обоих перехватчиков. Урон прямо в героя оставляет защитника, который не пропустит полную воздушную атаку.", solution)

static func _air_corridor(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var ground := str(_pick(rng, ["LMWD", "WKHR", "LMWA"]))
	var flyer := str(_pick(rng, ["BATT", "GBAT", "AVSC"]))
	var buff := str(_pick(rng, ["MGHT", "STRG", "SHCL"]))
	var guard := str(_pick(rng, ["BATT", "WLAR", "AVSC"]))
	var hand: Array = ["CLIG", buff]
	var units: Array = [_unit(profile, ground, 2, 0), _unit(profile, flyer, 3, 0), _unit(profile, "STAB", 4, 1), _unit(profile, "LMMN", 5, 1), _unit(profile, guard, 6, 1)]
	# EL2 Bat death discards a card: spend the enhancement before the kill.
	var solution: Array = [_cast(buff, 3), _cast("CLIG", 6)]
	_finish_attacks(solution, [2, 3], [_block(4, 2, 1), _block(5, 2, 1)])
	return _entry(_state(profile, units, hand, _cost(profile, hand), _power(profile, flyer) + _bonus(profile, buff)), "An Open Horizon", "Открытый горизонт",
		["The impressive ground attacker is facing more defence than it can break.", "Only one enemy can intercept a flyer. Decide where your removal and enhancement produce reliable damage.", "Enhance your flyer, then remove its flying guard with lightning. Spending the enhancement first also avoids losing it to a dying Bat in Etherlords II."],
		["Внушительному наземному бойцу противостоит слишком прочная оборона.", "Только один враг может перехватить летуна. Найдите, где удаление и усиление дадут гарантированный урон.", "Усильте своего летуна, затем уберите его летающего защитника молнией. Такой порядок также не даст гибнущей Мыши в Etherlords II сбросить ваше усиление."],
		"The ground formation draws attention, but the aerial route is the reliable finish. Resources spent on breaking the ground wall leave too little damage.",
		"Наземные силы отвлекают внимание, но надёжное завершение находится в воздухе. Попытка проломить наземную оборону расходует нужные для победы ресурсы.", solution)

static func _breakthrough(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var big := str(_pick(rng, ["LMWD", "WKHR", "LMWA"]))
	var small := str(_pick(rng, ["ANTN", "LMWA"]))
	var buff := str(_pick(rng, ["STRG", "MGHT"]))
	var hand: Array = [buff, "WEAK"]
	var budget := _cost(profile, hand)
	var units: Array = [_unit(profile, big, 2, 0), _unit(profile, small, 3, 0), _unit(profile, "STAB", 4, 1), _unit(profile, "LMMN", 5, 1)]
	var solution: Array = [_cast(buff, 2), _cast("WEAK", 5)]
	if difficulty == 4:
		hand.append("CLIG")
		budget += _cost(profile, ["CLIG"])
		solution.append(_cast("CLIG", 5))
	# This legal defensive investment competes for the exact lethal budget.
	# It is accepted as a trap only when the verifier actually refutes it.
	hand.append("SHSK")
	var damage := _power(profile, big) + _power(profile, small) + _bonus(profile, buff) - _toughness(profile, "STAB") - maxi(1, _toughness(profile, "LMMN") - 4)
	if difficulty == 4: damage += 3
	if damage < 2: return {}
	_finish_attacks(solution, [2, 3], [_block(4, 3, 1), _block(5, 2, 1)])
	return _entry(_state(profile, units, hand, budget, damage), "The Last Yard", "Последний шаг",
		["Trample turns the defenders' remaining toughness into a shared obstacle.", "An untargetable defender does not prevent you from changing the other half of the formation.", "Enhance a trampling attacker and weaken the targetable large defender. If lightning is available, damage that same defender as well before attacking with both threats."],
		["Натиск превращает оставшуюся стойкость защитников в общее препятствие.", "Недоступный для заклинаний защитник не мешает изменить другую часть обороны.", "Усильте атакующего с натиском и ослабьте крупного доступного защитника. Если есть молния, также повредите ею того же защитника до атаки обоими бойцами."],
		"Raising attack and lowering the defence combine to force lethal trample damage. A stacked block merely moves the leak to the other attacker.",
		"Усиление атаки и снижение защиты совместно обеспечивают смертельный урон натиском. Групповой блок лишь переносит проходящий урон на другого атакующего.", solution)

static func _pin_and_strike(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var small := str(_pick(rng, ["BATT", "AVSC", "GBAT"]))
	var durable := str(_pick(rng, ["WLBZ", "WLFC"]))
	var fragile := str(_pick(rng, ["BATT", "WLAR", "AVSC"]))
	var hand: Array = ["CLIG"]
	var solution: Array = [_ability(4, "tap_target", 5), _cast("CLIG", 6)]
	var damage := _power(profile, "GBAT") + _power(profile, small)
	var units: Array = [_unit(profile, "GBAT", 2, 0), _unit(profile, small, 3, 0), _unit(profile, "MNTS", 4, 0), _unit(profile, durable, 5, 1), _unit(profile, fragile, 6, 1)]
	var attackers: Array = [2, 3]
	if difficulty == 4:
		var buff := str(_pick(rng, ["MGHT", "STRG"]))
		var finisher := str(_pick(rng, ["BATT", "GBAT"]))
		hand.append(buff)
		solution.push_front(_cast(buff, 2))
		damage = _power(profile, finisher) + _bonus(profile, buff)
		units = [_unit(profile, finisher, 2, 0), _unit(profile, "MNTS", 4, 0), _unit(profile, durable, 5, 1), _unit(profile, fragile, 6, 1)]
		attackers = [2]
	_finish_attacks(solution, attackers)
	return _entry(_state(profile, units, hand, _cost(profile, hand) + 1, damage), "Two Gatekeepers", "Два привратника",
		["Your support creature has two possible jobs: attack, or prevent a block.", "Damage is a poor way to remove the durable guard; resting it costs the same regardless of its toughness.", "Rest the durable guard with the Mantis and use lightning on the fragile one. Attack through the air; apply the available enhancement to your flyer first if one is in your hand."],
		["Существо поддержки может атаковать или не дать врагу блокировать.", "Урон плохо справляется с прочным стражем; отправить его отдыхать стоит одинаково при любой стойкости.", "Богомолом уложите прочного стража, молнией уберите хрупкого. Атакуйте по воздуху; если в руке есть усиление, заранее примените его к летуну."],
		"The Mantis is more valuable opening a route than adding its own attack. Different tools answer the two different guards.",
		"Богомол приносит больше пользы, открывая путь, чем участвуя в атаке. Два разных защитника требуют разных средств.", solution)

static func _sheltered_sweep(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var vulnerable := str(_pick(rng, ["BATT", "AVSC"]))
	var buff := str(_pick(rng, ["OVRL", "BLSS", "TWEN"]))
	var hand: Array = [buff, "LGST"]
	var units: Array = [_unit(profile, "GBAT", 2, 0), _unit(profile, vulnerable, 3, 0), _unit(profile, "BATT", 5, 1), _unit(profile, "WLAR", 6, 1)]
	var solution: Array = [_cast(buff, 3)]
	var mana := _cost(profile, hand)
	if difficulty == 4:
		units.append(_unit(profile, "MNTS", 4, 0))
		units.append(_unit(profile, "WLBZ", 7, 1))
		solution.append(_ability(4, "tap_target", 7))
		mana += 1
	solution.append(_cast("LGST"))
	_finish_attacks(solution, [2, 3])
	var damage := _power(profile, "GBAT") + _power(profile, vulnerable) + _bonus(profile, buff)
	return _entry(_state(profile, units, hand, mana, damage), "After the Storm", "После бури",
		["A global damage spell changes your army as well as the enemy's.", "One friendly flyer needs help surviving the sweep. Spending that help on a creature that already survives wastes the opportunity.", "Enhance the fragile friendly flyer before casting Lightning Storm. If the enemy has a durable wall, rest it with the Mantis as well, then attack through the cleared sky."],
		["Массовый урон изменяет и вашу армию, и вражескую.", "Одному союзному летуну нужна помощь, чтобы пережить удар. Усиление того, кто и так выживет, упускает эту возможность.", "Усильте хрупкого союзного летуна до Грозы. Если у врага есть прочная стена, также уложите её Богомолом, затем атакуйте по чистому небу."],
		"Protection before removal preserves the missing attacker. Casting in the opposite order destroys a resource that the finishing attack needs.",
		"Защита перед зачисткой сохраняет необходимого атакующего. Обратный порядок уничтожает ресурс, без которого не хватает завершающего урона.", solution)

static func _promotion(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var pair: Array = _pick(rng, [["BATT", "STAT"], ["BATT", "TWEN"], ["AVSC", "MGHT"]])
	var low := str(pair[0])
	var buff := str(pair[1])
	var finisher := str(_pick(rng, ["BATT", "GBAT"]))
	var hand: Array = [buff, "SPWR"]
	# The established blessing makes the finisher's damage indispensable:
	# enhancing the Huntress and attacking with her cannot replace it while
	# a remaining aerial guard blocks the finisher.
	var units: Array = [_unit(profile, "WNHR", 2, 0), _unit(profile, finisher, 3, 0, {"enchantments": [_enchant(profile, "BLSS")]}), _unit(profile, low, 4, 1), _unit(profile, "GBAT", 5, 1)]
	# Kill the smaller guard last: in EL2 a Bat death may discard a card,
	# so all required spells must already have been spent when it dies.
	var solution: Array = [_cast(buff, 4), _ability(2, "hunt", 5), _cast("SPWR", 2), _ability(2, "hunt", 4)]
	_finish_attacks(solution, [3])
	return _entry(_state(profile, units, hand, _cost(profile, hand), _power(profile, finisher) + _bonus(profile, "BLSS")), "A Dangerous Invitation", "Опасное приглашение",
		["One enemy is too weak for your specialist to target.", "An enhancement can be removal preparation when it changes a target threshold. Your specialist must also act twice.", "Raise the weaker guard to at least four power. Hunt the naturally stronger guard first, ready the Huntress with Spirit of War, then hunt the enhanced guard. Your flyer finishes."],
		["Один из врагов слишком слаб, чтобы ваш специалист мог выбрать его целью.", "Усиление может подготовить удаление, изменяя порог допустимой цели. Специалисту также нужно действовать дважды.", "Поднимите силу слабого стража хотя бы до четырёх. Сначала уберите Охотницей изначально сильного, поднимите её Духом Войны и уберите усиленного. Летун завершит бой."],
		"Helping an enemy briefly makes both guards vulnerable to the same specialist. The readying spell provides the second activation instead of improving an ordinary attack.",
		"Краткое усиление врага делает обоих стражей уязвимыми для одного специалиста. Поднимающее заклинание даёт вторую активацию вместо усиления обычной атаки.", solution)

static func _inversion(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var power_buff := str(_pick(rng, ["MGHT", "STRG", "SHCL"]))
	var balanced := str(_pick(rng, ["TWEN", "BLSS"]))
	var damage := int(ELCatalog.rule(profile, balanced).get("power", 0))
	var hand: Array = [power_buff, balanced, "DELS", "SHSK"]
	var units: Array = [_unit(profile, "CAFG", 2, 0, {"damage": damage}), _unit(profile, "WLFC", 3, 1)]
	var health := _toughness(profile, "CAFG") + int(ELCatalog.rule(profile, balanced).get("toughness", 0))
	var solution: Array = [_cast(power_buff, 2), _cast(balanced, 2), _cast("DELS", 2), _ability(2, "spores", 1)]
	return _entry(_state(profile, units, hand, _cost(profile, [power_buff, balanced, "DELS"]), health), "A Fractured Reflection", "Треснувшее отражение",
		["The creature is already wounded. Changing its statistics does not erase the damage.", "A large future power value is useless if the new toughness is already lethal. Account for both sides of the exchange.", "Apply both the power enhancement and the balanced enhancement before Delusion. Then sacrifice the surviving Fingus with its spores aimed at the opposing hero."],
		["Существо уже ранено. Изменение его характеристик не убирает полученный урон.", "Большая будущая сила бесполезна, если новая стойкость уже смертельно мала. Учитывайте обе стороны обмена.", "До Иллюзии примените усиление силы и сбалансированное усиление. Затем пожертвуйте выжившим грибом, направив его споры во вражеского героя."],
		"The pre-swap power is a survival requirement; the pre-swap toughness becomes the finishing damage. Retained wounds make the attractive toughness-only route fail.",
		"Сила до обмена нужна для выживания, а стойкость до обмена становится завершающим уроном. Сохранившиеся раны ломают заманчивый план с одним лишь усилением стойкости.", solution)

static func _reservoir(profile: ELProfile, rng: RandomNumberGenerator) -> Dictionary:
	var larger := str(_pick(rng, ["SEHL", "SWHL"]))
	var reserve := rng.randi_range(8, 14)
	var units: Array = [_unit(profile, "RVHL", 2, 0), _unit(profile, larger, 3, 0), _unit(profile, "WLFC", 4, 1)]
	var position := _state(profile, units, ["BRRL"], 0, reserve - 2)
	position.heroes[1].mana = reserve
	var solution: Array = [_ability(2, "siphon"), _cast("BRRL", 1)]
	return _entry(position, "The Other Reserve", "Чужой резерв",
		["Your opponent's ether can be a weapon, not just something to deny.", "You need enough ether to cast the finishing spell. Stealing more also reduces the damage it can inflict.", "Take only two ether with River Halo, then burn the opposing hero's remaining pool with Broken Reality."],
		["Эфир врага может стать оружием, а не только ресурсом, который нужно отнять.", "Вам нужно оплатить завершающее заклинание. Более крупная кража уменьшает урон этого заклинания.", "Речным нимбом заберите только два эфира, затем сожгите оставшийся запас вражеского героя Разрушением Реальности."],
		"The smallest sufficient transfer preserves the largest lethal burn. The larger siphon wins more ether and loses the available finish.",
		"Минимальная достаточная кража сохраняет максимальный смертельный урон. Более крупная кража приносит больше эфира, но лишает завершения.", solution)

static func _counterattack(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var pair: Array = _pick(rng, [["SHWL", "STMC", "KBSH"], ["FREL", "LMWA", "KBSH"], ["LMWD", "CCLP", "KBSH"]])
	var fighter := str(pair[0])
	var enemy := str(pair[1])
	var support := str(pair[2])
	var buff := str(_pick(rng, ["MGHT", "STRG"]))
	var fodder := str(_pick(rng, ["AVSC", "BATT"]))
	var units: Array = [_unit(profile, fighter, 2, 0), _unit(profile, fodder, 3, 0), _unit(profile, support, 4, 0), _unit(profile, enemy, 6, 1), _unit(profile, "GBAT", 7, 1)]
	# Every large attacker tramples: sacrificing the tiny support instead of
	# using first strike cannot safely preserve the counterattacker for free.
	units[3].damage = maxi(0, _toughness(profile, enemy) - _power(profile, fighter) - 1)
	var solution: Array = [_ability(4, "sting", 6)]
	var hand: Array = [buff]
	var initial_mana := 0
	if difficulty == 4:
		# Energize All is explicitly defence-castable in both games. It must
		# restore the resting first-striker before the current combat; the
		# finishing enhancement waits for the ordinary turn-start refill.
		units[0].resting = true
		hand.append("ENAL")
		initial_mana = _cost(profile, ["ENAL"])
		solution.push_front(_cast("ENAL"))
	var position := _state(profile, units, hand, initial_mana, _power(profile, fighter) + _bonus(profile, buff))
	position.phase = 1
	position.attacker = 1
	position.attacks = [6, 7]
	position.heroes[0].health = 3
	position.heroes[0].turns = 3
	position.heroes[0].channels = _cost(profile, [buff])
	position.heroes[1].turns = 4
	solution.append(_block(2, 6))
	solution.append(_block(3, 7))
	solution.append(_end())
	solution.append(_cast(buff, 2))
	_finish_attacks(solution, [2])
	var entry := _entry(position, "The Turning Point", "Поворотный момент",
		["Merely surviving is not enough. Keep the creature that can win the counterattack.", "First strike can prevent the return hit, but only if the enemy is already within its damage threshold.", "Use your support's damage on the large attacker before assigning your first-striker to it. Sacrifice the small flyer against the enemy flyer; on your attack, spend the channel refill enhancing your survivor."],
		["Просто выжить недостаточно. Сохраните существо, которое выиграет ответную атаку.", "Первый удар предотвращает ответ только тогда, когда враг уже находится в пределах его урона.", "До блока повредите крупного врага поддержкой и назначьте против него бойца с первым ударом. Пожертвуйте малым летуном против вражеского; в ответной атаке потратьте пополнение каналов на усиление выжившего."],
		"First-strike preparation stops the large trampling attacker before it can hit back and preserves the survivor needed for the counterattack. A wrong defensive assignment can lose either the hero or the finishing creature.",
		"Подготовка первого удара останавливает крупного врага с натиском до ответного удара и сохраняет бойца для контратаки. Неверное распределение защитников может погубить героя или завершающее существо.", solution)
	if difficulty == 4:
		entry.hints[2] = "Wake the resting first-striker with Energize All and sting the large attacker before blocking it. Sacrifice the small flyer against the flying attack. Your next-turn channel refill pays for the enhancement that makes the counterattack lethal."
		entry.hints_ru[2] = "Массовой Подзарядкой поднимите отдыхающего бойца с первым ударом и до блока уколите крупного врага. Пожертвуйте малым летуном против воздушной атаки. Пополнение каналов на вашем ходу оплатит усиление для смертельной контратаки."
	entry.briefing = "Defend the current attack, then win within the displayed one-turn budget. You start with %d ether and have %d channels; those channels refill your ether when your turn starts. No new cards or natural channels are added." % [initial_mana, int(position.heroes[0].channels)]
	entry.briefing_ru = "Защититесь от текущей атаки, затем победите в пределах указанного лимита в один ваш ход. Сейчас эфира: %d, каналов: %d; каналы пополнят эфир в начале вашего хода. Новых карт и автоматического роста каналов нет." % [initial_mana, int(position.heroes[0].channels)]
	if difficulty == 4:
		entry.briefing += " Your first-strike defender is resting. Energize All can be cast during defence."
		entry.briefing_ru += " Ваш защитник с первым ударом отдыхает. Массовую Подзарядку можно применять в фазе защиты."
	return entry
