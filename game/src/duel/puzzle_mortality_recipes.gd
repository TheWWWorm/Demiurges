class_name ELMortalityPuzzleRecipes
extends RefCounted
## Proposals built from ordinary death, healing and graveyard rules.
## The shared generator must still certify every concrete position.

const FAMILY_IDS := ["funeral_math", "grave_priority"]

static func families(edition: String) -> Array[String]:
	var out: Array[String] = []
	if edition in ["el1", "el2"]: out.assign(FAMILY_IDS)
	return out

static func supports(family: String, difficulty: int) -> bool:
	if family == "funeral_math": return difficulty in [2, 3, 4]
	if family == "grave_priority": return difficulty in [3, 4]
	return false

static func variants(family: String, difficulty: int) -> Array[String]:
	var out: Array[String] = []
	if not supports(family, difficulty): return out
	if family == "funeral_math":
		if difficulty == 2: out.assign(["consume_for_survival"])
		elif difficulty == 3: out.assign(["web_for_survival"])
		else: out.assign(["feed_then_burn", "web_recover_burn"])
	else: out.assign(["choose_return" if difficulty == 4 else "single_return"])
	return out

static func build(profile: ELProfile, family: String, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	if profile == null or profile.id not in ["el1", "el2"] or not supports(family, difficulty): return {}
	var entry: Dictionary = {}
	match family:
		"funeral_math": entry = _funeral_math(profile, rng, difficulty)
		"grave_priority": entry = _grave_priority(profile, rng, difficulty)
	if entry.is_empty(): return entry
	if family == "funeral_math":
		var second := {"label": "Sacrifice healing is necessary", "without_player": {"effects": ["sacrifice_heal"]}}
		if difficulty == 4: second = {"label": "Grave-count damage is necessary", "without_player": {"effects": ["grave_fire"]}}
		elif str(entry.generated.variant) == "web_for_survival": second = {"label": "Death-trigger healing is necessary", "without_player": {"casts": ["SPWB"]}}
		entry.generated.development_requirements = [{"label": "Global power accounting is necessary", "without_player": {"effects": ["annihilate"]}}, second]
	else:
		entry.generated.development_requirements = [{"label": "Newest-corpse recovery is necessary", "without_player": {"effects": ["revive"]}}, {"label": "Sacrifice creates the return target", "without_player": {"abilities": ["sacrifice"]}}]
	return entry

static func _funeral_math(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var use_web := difficulty == 3 or (difficulty == 4 and rng.randi_range(0, 1) == 0)
	var burn := difficulty == 4
	if use_web: return _web_accounting(profile, rng, burn)
	var attacker := str(ELPuzzleRecipes._pick(rng, ["GROG", "LMWA", "SHWL", "IRMC"]))
	var enemy := str(ELPuzzleRecipes._pick(rng, ["GROG", "IRMC", "SHWL", "TIWR"]))
	var enemy_power := ELPuzzleRecipes._power(profile, enemy)
	var wall := "WLFC" if enemy_power >= 6 else "RKWL"
	var per_corpse := 3 if profile.id == "el2" else 2
	var units: Array = [ELPuzzleRecipes._unit(profile, attacker, 2, 0, {"resting": true}), ELPuzzleRecipes._unit(profile, wall, 3, 0), ELPuzzleRecipes._unit(profile, enemy, 4, 1)]
	var hand: Array = ["CNBL", "ANHL"]
	if burn: hand.append("BRGR")
	var target_health := ELPuzzleRecipes._power(profile, attacker) + (per_corpse if burn else 0)
	# EL2 adds one ether per affected creature still present at the cast.
	# Cannibalism has already removed one creature when Annihilation is paid.
	var surcharge := units.size() - 1 if profile.id == "el2" else 0
	var position := ELPuzzleRecipes._state(profile, units, hand, ELPuzzleRecipes._cost(profile, hand) + surcharge, target_health)
	position.heroes[0].health = rng.randi_range(1, mini(3, enemy_power))
	var solution: Array = [ELPuzzleRecipes._cast("CNBL", 3), ELPuzzleRecipes._cast("ANHL")]
	if burn: solution.append(ELPuzzleRecipes._cast("BRGR"))
	var entry := ELPuzzleRecipes._entry(position, "The Last Accounting", "Последний расчёт",
		["Count both heroes' outcomes. Clearing the board can still lose the duel.", "One ally stores the power needed to kill the enemy. The other stores toughness that can keep you alive.", "Consume the wall for its toughness, preserving the fighting creature's power for Annihilation." + (" Burn the graves only after Annihilation has created the enemy corpse; include your own two corpses in the damage calculation." if burn else " The enemy's surviving power is also counted before the creatures are destroyed.")],
		["Посчитайте результат для обоих героев. Очистка поля может закончиться поражением.", "Один союзник хранит силу, нужную для гибели врага. Другой хранит выносливость, которая поможет вам выжить.", "Поглотите стену ради её выносливости, сохранив силу бойца для Аннигиляции." + (" Поджигайте могилы только после того, как Аннигиляция создаст вражескую могилу; учитывайте урон от двух ваших собственных могил." if burn else " Сила врага тоже учитывается до уничтожения существ.")],
		"Annihilation records both armies' power before destroying them, then damages the opposing heroes by those totals. Consuming the high-toughness wall preserves the offensive total while buying the health needed to survive the opposing total." + (" Burning Graves supplies the final damage, but also punishes the two creatures in your own graveyard." if burn else " Consuming the fighter instead removes the damage the finish depends on."),
		"Аннигиляция запоминает силу обеих армий до уничтожения существ, затем наносит соответствующий урон противоположным героям. Поглощение выносливой стены сохраняет атакующую сумму и даёт здоровье, нужное против суммы врага." + (" Горящие Могилы добавляют завершающий урон, но наказывают и за двух существ в вашей собственной могиле." if burn else " Поглощение бойца вместо стены убирает урон, на котором держится завершение."), solution)
	_finish_entry(entry, profile, "Annihilation can defeat both heroes at once; a draw does not complete the challenge.", "Аннигиляция может одновременно погубить обоих героев; ничья не решает задачу.", burn)
	entry.generated = {"planned_own_turns": 1, "variant": "feed_then_burn" if burn else "consume_for_survival", "mechanics": ["sacrifice for healing", "army power accounting", "simultaneous lethal", "grave-count damage" if burn else "preserve offensive power"]}
	entry.refutations = [{"label": "Consume the fighting creature instead of the wall", "commands": [ELPuzzleRecipes._cast("CNBL", 2)]}]
	return entry

static func _web_accounting(profile: ELProfile, rng: RandomNumberGenerator, burn: bool) -> Dictionary:
	var attacker := str(ELPuzzleRecipes._pick(rng, ["GROG", "LMWA", "SHWL", "IRMC"]))
	var enemies: Array = ELPuzzleRecipes._pick(rng, [["STRT", "GROG"], ["TIWR", "SHWL"], ["TIWR", "TIWR"]])
	var enemy_power := ELPuzzleRecipes._power(profile, str(enemies[0])) + ELPuzzleRecipes._power(profile, str(enemies[1]))
	var own_power := ELPuzzleRecipes._power(profile, attacker)
	var per_corpse := 3 if profile.id == "el2" else 2
	var repair_damage := own_power if profile.id == "el2" else 1
	var units: Array = [ELPuzzleRecipes._unit(profile, attacker, 2, 0, {"resting": true}), ELPuzzleRecipes._unit(profile, str(enemies[0]), 3, 1), ELPuzzleRecipes._unit(profile, str(enemies[1]), 4, 1)]
	var hand: Array = ["SPWB", "ANHL"]
	if burn: hand.append_array(["REPR", "BRGR"])
	var target_health := own_power + (per_corpse * 2 + repair_damage if burn else 0)
	var surcharge := units.size() if profile.id == "el2" else 0
	var position := ELPuzzleRecipes._state(profile, units, hand, ELPuzzleRecipes._cost(profile, hand) + surcharge, target_health)
	# Three deaths heal three before the opposing army's power is dealt.
	position.heroes[0].health = enemy_power - 2
	var solution: Array = [ELPuzzleRecipes._cast("SPWB"), ELPuzzleRecipes._cast("ANHL")]
	if burn:
		var repair := ELPuzzleRecipes._cast("REPR", 0)
		repair.grave = 0 # Exactly one own corpse exists, independently of board order.
		solution.append(repair)
		solution.append(ELPuzzleRecipes._cast("BRGR"))
	var entry := ELPuzzleRecipes._entry(position, "Life in the Aftermath", "Жизнь после гибели",
		["The battlefield's deaths can change your health before the last damage is settled.", "A healing trigger must already be present when the creatures die. Count every death, including the enemy's.", "Install Spiritual Web, then cast Annihilation. Its three deaths leave you alive." + (" Repair your own corpse before Burning Graves: the recovered card is no longer a source of grave damage against you." if burn else " Without the death-trigger healing, the same explosion loses the duel.")],
		["Гибель существ может изменить ваше здоровье до расчёта последнего урона.", "Лечение от смертей должно быть подготовлено заранее. Учитывайте все смерти, в том числе вражеские.", "Подготовьте Духовную Паутину, затем примените Аннигиляцию. Три смерти оставят вас в живых." + (" До Горящих Могил верните собственную погибшую карту Ремонтом: возвращённая карта больше не причиняет вам могильный урон." if burn else " Без лечения от смертей тот же взрыв проигрывает бой.")],
		"The Web heals for all three deaths during Annihilation, so the enemy army's recorded power leaves exactly one hero health." + (" Burning Graves would then kill you from your own corpse. Repair removes that corpse and adds its edition-specific damage; only then is the symmetric grave burn safe and lethal." if burn else " Playing the healing enchantment after the deaths cannot recover this lost timing window."),
		"Паутина лечит за все три смерти во время Аннигиляции, поэтому запомненная сила армии врага оставляет герою ровно одно здоровье." + (" После этого Горящие Могилы убили бы вас из-за собственной погибшей карты. Ремонт убирает её и добавляет урон по правилам этой редакции; только затем симметричный поджог становится безопасным и смертельным для врага." if burn else " Зачарование лечения, сыгранное после смертей, уже не вернёт упущенное событие."), solution)
	_finish_entry(entry, profile, "Spiritual Web heals its hero whenever a creature dies, on either side.", "Духовная Паутина лечит своего героя при гибели существа с любой стороны.", burn)
	var mechanics: Array = ["death-trigger healing", "army power accounting", "simultaneous lethal"]
	if burn: mechanics.append_array(["recover before burning", "grave-count damage"])
	entry.generated = {"planned_own_turns": 1, "variant": "web_recover_burn" if burn else "web_for_survival", "mechanics": mechanics}
	entry.refutations = [{"label": "Cast Annihilation before installing the healing trigger", "commands": [ELPuzzleRecipes._cast("ANHL")]}]
	return entry

static func _grave_priority(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var choose_return := difficulty == 4
	# Three direct damage can be obtained by recovering and resummoning the
	# spore creature. Four lethal damage keeps the Hopper's attack essential.
	var fast := "MXHP"
	var weaker := str(ELPuzzleRecipes._pick(rng, ["MNHP", "HOPR"]))
	var guard := str(ELPuzzleRecipes._pick(rng, ["STRT", "BEWR"]))
	var units: Array = [ELPuzzleRecipes._unit(profile, fast, 2, 0, {"resting": true}), ELPuzzleRecipes._unit(profile, "SPFG", 3, 0), ELPuzzleRecipes._unit(profile, guard, 4, 1)]
	if choose_return: units.append(ELPuzzleRecipes._unit(profile, weaker, 5, 0, {"resting": true}))
	var required_mana := ELPuzzleRecipes._cost(profile, ["JRRG", fast])
	var sacrifice_gain := ELPuzzleRecipes._power(profile, fast) + ELPuzzleRecipes._toughness(profile, fast) - 1
	var initial_mana := maxi(1, required_mana - sacrifice_gain) if profile.id == "el1" else required_mana
	var position := ELPuzzleRecipes._state(profile, units, ["JRRG"], initial_mana, ELPuzzleRecipes._power(profile, fast) + 1)
	position.heroes[0].grave = ["GROG"]
	ELPuzzleRecipes._hero_enchantment(position, profile, 0, "SACR")
	var return_id := int(position.next_id)
	var solution: Array = [ELPuzzleRecipes._ability(3, "spores", 4), ELPuzzleRecipes._ability(0, "sacrifice:1", 2), ELPuzzleRecipes._cast("JRRG"), ELPuzzleRecipes._cast(fast)]
	ELPuzzleRecipes._finish_attacks(solution, [return_id])
	var entry := ELPuzzleRecipes._entry(position, "The Newest Grave", "Самая свежая могила",
		["Recovery does not let you choose any corpse. Which creature will be newest when it resolves?", "Both the spore ability and Dissolution add a creature to your graveyard. The creature you need must not be buried beneath the wrong one.", "Remove the guard with spores and arrange for the lethal Hopper to be the newest corpse when you cast Reanimate. It returns to hand, deals one hero damage, and can then be summoned to attack immediately. A smaller return cannot finish this total."],
		["Возвращение не позволяет выбрать любую погибшую карту. Кто будет лежать сверху в момент его применения?", "И споровая способность, и Растворение добавляют существо в вашу могилу. Нужное существо не должно оказаться под неправильной картой.", "Уберите защитника спорами и сделайте победного Прыгуна самым новым погибшим к моменту Реанимации. Он вернётся в руку, нанесёт одно повреждение герою и после призыва сможет немедленно атаковать. Меньшего возвращения для нужной суммы не хватит."],
		"Reanimate takes the newest own corpse, not a chosen graveyard slot. Returning the resting Hopper gives it a new ready body with haste; its printed attack plus Reanimate's one damage is exact. The spore creature clears the guard but becomes an unwanted newest corpse if the deaths are ordered carelessly.",
		"Реанимация берёт самую новую собственную погибшую карту, а не выбранную позицию могилы. Возвращение отдыхающего Прыгуна даёт ему новое готовое тело, способное сразу атаковать; его печатная сила и единица урона Реанимации дают точную сумму. Споровое существо убирает защитника, но при неосторожном порядке смертей само становится нежелательной верхней картой.", solution)
	var edition_fact := "Dissolution requires one ether to activate here and gains power plus toughness minus one as ether." if profile.id == "el1" else "Dissolution's ordinary card draws are disabled by this puzzle's fixed supply; it still sends the sacrificed creature to the graveyard."
	var edition_fact_ru := "Для активации Растворения здесь нужен один эфир; оно приносит эфир в размере силы плюс выносливость минус один." if profile.id == "el1" else "Обычный добор Растворения отключён фиксированным снабжением этой задачи; жертва всё равно отправляется в могилу."
	_finish_entry(entry, profile, "The graveyard is ordered oldest to newest. Both Reanimate and a new creature's summon use their normal ether costs. " + edition_fact, "Могила упорядочена от старых карт к новым. И Реанимация, и призыв возвращённого существа имеют обычную стоимость в эфире. " + edition_fact_ru)
	entry.generated = {"planned_own_turns": 1, "variant": "choose_return" if choose_return else "single_return", "mechanics": ["order own deaths", "newest-corpse recovery", "sacrifice for access", "resummon to refresh", "haste"]}
	entry.refutations = [{"label": "Bury the needed Hopper beneath the spore creature", "commands": [ELPuzzleRecipes._ability(0, "sacrifice:1", 2), ELPuzzleRecipes._ability(3, "spores", 4)]}]
	if choose_return:
		entry.refutations.push_front({"label": "Choose the smaller Hopper for the return", "commands": [ELPuzzleRecipes._ability(3, "spores", 4), ELPuzzleRecipes._ability(0, "sacrifice:1", 5)]})
	return entry

static func _finish_entry(entry: Dictionary, profile: ELProfile, facts: String, facts_ru: String, burns_graves: bool = false) -> void:
	entry.briefing = "Win within one of your turns. Normal card draws and channel growth are disabled; card effects can still return cards from the graveyard. " + facts
	entry.briefing_ru = "Победите в пределах одного вашего хода. Обычный добор карт и рост каналов отключены; эффекты карт всё ещё могут возвращать карты из могилы. " + facts_ru
	if profile.id == "el2" and entry.state.heroes[0].hand.has("ANHL"):
		entry.briefing += " Annihilation also costs one ether for each affected creature still in play."
		entry.briefing_ru += " Аннигиляция дополнительно стоит один эфир за каждое затрагиваемое существо, которое ещё находится на поле."
	if burns_graves:
		var per_corpse := 3 if profile.id == "el2" else 2
		entry.briefing += " Burning Graves deals %d damage per creature card in each hero's own graveyard." % per_corpse
		entry.briefing_ru += " Горящие Могилы наносят по %d урона за карту существа в собственной могиле каждого героя." % per_corpse
