class_name ELPuzzleZoneRecipes
extends RefCounted
## Zone and targeting puzzles. These return raw recipes; ELPuzzleRecipes
## performs the shared normalization and the generator proves every request.

const FAMILIES := ["hand_overload", "aspect_toll"]
const WALLS := ["WLAR", "WLBZ", "WLMG", "WLFC"]
const CHEAP_WALLS := ["WLAR", "WLBZ", "WLMG"]
const LARGE_CARDS := ["BLDG", "BUDG", "RDDG"]

static func families(edition: String) -> Array[String]:
	var result: Array[String] = []
	if edition in ["el1", "el2"]: result.append("hand_overload")
	if edition == "el2": result.append("aspect_toll")
	return result

static func supports(family: String, difficulty: int) -> bool:
	return family in FAMILIES and difficulty in [3, 4]

static func variants(family: String, difficulty: int) -> Array[String]:
	var result: Array[String] = []
	if not supports(family, difficulty): return result
	if family == "aspect_toll":
		result.assign(["unlock_the_incoming_aspect" if difficulty == 4 else "opposing_transition_tolls"])
		return result
	result.assign(["return_then_blast"] if difficulty == 3 else ["spend_before_return", "discard_your_creatures"])
	return result

static func build(profile: ELProfile, family: String, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	if profile == null or family not in families(profile.id) or not supports(family, difficulty): return {}
	if family == "aspect_toll": return _aspect_toll(profile, rng, difficulty)
	return _hand_overload(profile, rng, difficulty)

## Both subjects of Transfer Aspects can belong to the opponent. Aspect Ward
## charges that controller for each successful transition. A locked incoming
## creature makes the two halves asymmetric: the first change can succeed
## while the second fails, consuming the once-per-turn exchange ability.
static func _aspect_toll(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var locked := difficulty == 4
	var outgoing := ELPuzzleRecipes._unit(profile, String(ELPuzzleRecipes._pick(rng, ["OUD1", "OUD2", "SMWB"])), 4, 1, {"plane": true})
	var incoming := ELPuzzleRecipes._unit(profile, String(ELPuzzleRecipes._pick(rng, ["OUD1", "OUD2", "SMTG"])), 5, 1)
	if locked: incoming.enchantments.append(ELPuzzleRecipes._enchant(profile, "PRBN"))
	var units: Array = [
		ELPuzzleRecipes._unit(profile, String(ELPuzzleRecipes._pick(rng, ["WLAR", "WLBZ"])), 2, 0, {"plane": true}),
		ELPuzzleRecipes._unit(profile, String(ELPuzzleRecipes._pick(rng, ["WLBZ", "WLMG"])), 3, 0), outgoing, incoming]
	var hand: Array = ["PRWR"]
	if locked: hand.append("CLNP")
	var state := ELPuzzleRecipes._state(profile, units, hand, ELPuzzleRecipes._cost(profile, hand) + 1, 2)
	state.heroes[0].health = 7
	state.heroes[1].mana = 2
	ELPuzzleRecipes._hero_enchantment(state, profile, 0, "OEXC")
	var source := int(state.heroes[0].enchantments[-1].id)
	var exchange := ELPuzzleRecipes._ability(0, "recycle:%d" % source, 4)
	exchange.choice = 5
	var solution: Array = []
	if locked:
		var dispel := ELPuzzleRecipes._cast("CLNP", 5)
		dispel.grave = int(state.creatures["5"].enchantments[0].id)
		solution.append(dispel)
	solution.append(ELPuzzleRecipes._cast("PRWR", 1))
	solution.append(exchange)
	var title := "A Costly Exchange"
	var title_ru := "Цена обмена"
	var hints: Array = [
		"Transfer Aspects chooses two creatures, but neither choice has to belong to you. Who pays when each one changes aspect?",
		"Aspect Ward charges the creature's controller one ether and one health in either direction. A single exchange can make the same hero pay twice.",
		"Place Aspect Ward on the opposing hero. Use Transfer Aspects on their creature in the Colourless Plane, then select their other creature in the Ether. Both transitions charge the opponent."
	]
	var hints_ru: Array = [
		"Обмен Планами выбирает двух существ, и ни одно из них не обязано быть вашим. Кто платит за смену плана каждого существа?",
		"Планарный Барьер берёт у владельца существа один эфир и одно здоровье при смене плана в любом направлении. Один обмен может заставить того же героя заплатить дважды.",
		"Наложите Планарный Барьер на вражеского героя. Обменом Планами выберите его существо в бесцветном плане, затем другое его существо в Эфире. Обе смены плана оплачивает противник."
	]
	var explanation := "The useful targets are both enemy creatures. The creature returning from the Colourless Plane and the creature entering it each charge their controller through Aspect Ward. The opponent's two ether enable the two health payments that defeat them."
	var explanation_ru := "Нужные цели — оба вражеских существа. И возвращение из бесцветного плана, и уход в него заставляют владельца заплатить через Планарный Барьер. Два эфира противника позволяют взять два здоровья и победить его."
	var wrong := exchange.duplicate(true)
	wrong.choice = 3
	var trap := {"label": "Send your own creature away instead of making the opponent pay twice", "commands": [ELPuzzleRecipes._cast("PRWR", 1), wrong]}
	if locked:
		title = "Two Directions"
		title_ru = "Два направления"
		hints[0] = "The two directions of an exchange do not face the same obstacle. Which creature is forbidden to enter the Colourless Plane?"
		hints[2] = "Remove Lock Aspect from the enemy creature in the Ether. Place Aspect Ward on their hero, then exchange the two enemy creatures: the first returns from the plane and the unlocked second enters it."
		hints_ru[0] = "Два направления обмена встречают разные препятствия. Какому существу запрещено входить в бесцветный план?"
		hints_ru[2] = "Снимите Эфирные Узы с вражеского существа в Эфире. Наложите Планарный Барьер на его героя, затем обменяйте двух вражеских существ: первое вернётся из бесцветного плана, а второе сможет войти в него."
		explanation += " Lock Aspect would prevent only the incoming transition. Removing it first is necessary: an incomplete exchange spends the ability but collects only one toll."
		explanation_ru += " Эфирные Узы запретили бы только вход. Сначала их нужно снять: неполный обмен тратит способность, но взимает лишь одну плату."
		trap = {"label": "Use the exchange before removing the incoming creature's Lock Aspect", "commands": [ELPuzzleRecipes._cast("PRWR", 1), exchange.duplicate(true)]}
	var entry := ELPuzzleRecipes._entry(state, title, title_ru, hints, hints_ru, explanation, explanation_ru, solution)
	entry.briefing += " The Ether and health costs of an aspect change are paid by that creature's controller. Each of the two transitions is checked separately. The opponent has two ether and no channels."
	entry.briefing_ru += " Плату эфиром и здоровьем за смену плана вносит владелец существа. Каждая из двух смен плана проверяется отдельно. У врага два эфира и нет каналов."
	entry.refutations = [trap]
	entry.generated = {"variant": "unlock_the_incoming_aspect" if locked else "opposing_transition_tolls",
		"mechanics": ["paired targets", "aspect changes", "opposing resource payments", "directional enchantment restriction" if locked else "ownership of triggered costs"],
		"development_requirements": [
			{"label": "The opposing Aspect Ward is essential", "without_player": {"casts": ["PRWR"]}},
			{"label": "The paired Transfer Aspects ability is essential", "without_player": {"abilities": ["recycle"]}}
		]}
	if locked: entry.generated.development_requirements.append({"label": "Removing Lock Aspect is essential", "without_player": {"effects": ["dispel"]}})
	return entry

static func _hand_overload(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var variant := "return_then_blast" if difficulty == 3 else String(ELPuzzleRecipes._pick(rng, ["spend_before_return", "discard_your_creatures"]))
	var self_discard := variant == "discard_your_creatures"
	var spend_first := variant == "spend_before_return"
	var own_count := 3 if spend_first else 4
	var enemy_count := rng.randi_range(2, 3)
	var per_card := 3 if profile.id == "el2" else 2
	var hand: Array = ["GRUN", "MDBL"]
	var targeted := String(ELPuzzleRecipes._pick(rng, ["LSUS", "UNSM"]))
	if spend_first: hand.append(targeted)
	elif self_discard: hand.append("CURS")
	var fillers := 4 if self_discard else (2 if spend_first else 1)
	for _index in fillers: hand.append(ELPuzzleRecipes._pick(rng, LARGE_CARDS))
	var units: Array = []
	for index in own_count:
		var options: Array = CHEAP_WALLS if index == 0 else WALLS
		# In the first game the unused targeted spell leaves one spare ether.
		# A one-cost returned wall could otherwise be recast after the global
		# return, defeating the intended loss of target availability.
		if spend_first: options = ["WLBZ", "WLMG"] if index == 0 else ["WLBZ", "WLMG", "WLFC"]
		units.append(ELPuzzleRecipes._unit(profile, String(ELPuzzleRecipes._pick(rng, options)), index + 2, 0))
	for index in enemy_count:
		units.append(ELPuzzleRecipes._unit(profile, String(ELPuzzleRecipes._pick(rng, WALLS)), own_count + index + 2, 1))
	var mana := ELPuzzleRecipes._cost(profile, ["GRUN", "MDBL"])
	if spend_first: mana += ELPuzzleRecipes._cost(profile, [targeted])
	elif self_discard: mana += ELPuzzleRecipes._cost(profile, ["CURS"])
	if profile.id == "el2": mana += own_count + enemy_count - (1 if spend_first else 0)
	var state := ELPuzzleRecipes._state(profile, units, hand, mana, per_card)
	state.heroes[0].health = per_card
	var enemy_hand: Array = []
	for _index in 6 - enemy_count: enemy_hand.append(ELPuzzleRecipes._pick(rng, LARGE_CARDS))
	state.heroes[1] = ELPuzzleRecipes._hero(profile, 1, enemy_hand, 0, per_card)
	var solution: Array = []
	if spend_first: solution.append(ELPuzzleRecipes._cast(targeted, 2))
	elif self_discard: solution.append(ELPuzzleRecipes._cast("CURS", 0))
	solution.append(ELPuzzleRecipes._cast("GRUN"))
	solution.append(ELPuzzleRecipes._cast("MDBL"))
	var title := "A Crowded Hand"
	var title_ru := "Переполненная рука"
	var hints: Array = [
		"Count the cards each hero would hold after the creatures return. Which hand can turn into damage?",
		"Mind Blast hurts both heroes. Work out your own hand size after the casting card leaves it, as well as the opponent's.",
		"Return the armies with Greater Unsummoning, then cast Mind Blast. The opponent must hold more than five cards while your own overflow remains harmless."
	]
	var hints_ru: Array = [
		"Посчитайте карты у каждого героя после возвращения существ. Чья рука может превратиться в урон?",
		"Удар по Разуму ранит обоих героев. Учтите свою руку после ухода разыгрываемой карты, а также руку противника.",
		"Верните армии Великим Развоплощением, затем разыграйте Удар по Разуму. У врага должно быть больше пяти карт, а ваше переполнение не должно стать смертельным."
	]
	var explanation := "Returning the enemy army crosses Mind Blast's hand-size threshold. Your own returned creatures also count, so the winning line manages both hands before the symmetric damage resolves."
	var explanation_ru := "Возвращение вражеской армии превышает порог карт для Удара по Разуму. Ваши вернувшиеся существа тоже учитываются, поэтому перед общим уроном нужно рассчитать обе руки."
	var trap := {"label": "Spend Mind Blast before returning the enemy creatures", "commands": [ELPuzzleRecipes._cast("MDBL")]}
	if spend_first:
		title = "Before the Board Empties"
		title_ru = "Пока поле не опустело"
		hints[0] = "The right damage spell can still defeat its caster. Which card will become impossible to spend after the board empties?"
		hints[2] = "Use the targeted Unsummoning while a legal creature remains, then Greater Unsummoning and Mind Blast. That extra card spent keeps your own hand at five."
		hints_ru[0] = "Нужное заклинание урона может погубить самого заклинателя. Какую карту нельзя будет потратить, когда поле опустеет?"
		hints_ru[2] = "Используйте обычное Развоплощение, пока есть допустимая цель, затем Великое Развоплощение и Удар по Разуму. Потраченная заранее карта оставит у вас ровно пять карт."
		explanation += " The targeted return must be used before the global return removes its targets; saving that card leaves a lethal extra card in your hand."
		explanation_ru += " Сначала нужно потратить прицельное возвращение: после общего возвращения у него не останется целей, а лишняя карта в руке станет смертельной."
		trap = {"label": "Empty the battlefield before spending the targeted return", "commands": [ELPuzzleRecipes._cast("GRUN")]}
	elif self_discard:
		title = "Lighten the Load"
		title_ru = "Лишний груз"
		hints[0] = "Discard is usually aimed at the enemy. Which hero actually needs a smaller hand here?"
		hints[2] = "Cast Curse on your own hero to discard three creature cards. Greater Unsummoning then fills the enemy hand, and Mind Blast finishes without killing you."
		hints_ru[0] = "Сброс карт обычно направляют во врага. Чью руку в этой задаче действительно нужно уменьшить?"
		hints_ru[2] = "Наложите Напасть на своего героя, чтобы сбросить три карты существ. Великое Развоплощение заполнит руку врага, а Удар по Разуму завершит бой, не убив вас."
		explanation += " Curse must empty your creature cards, not the enemy's: their large hand is the source of your lethal damage. Summoning a creature before returning it does not shrink your final hand."
		explanation_ru += " Напасть должна убрать ваши карты существ, а не вражеские: большая рука противника обеспечивает смертельный урон. Призвать существо перед его возвращением — не значит уменьшить итоговую руку."
		trap = {"label": "Discard the opponent's creatures instead of your own", "commands": [ELPuzzleRecipes._cast("CURS", 1)]}
	var entry := ELPuzzleRecipes._entry(state, title, title_ru, hints, hints_ru, explanation, explanation_ru, solution)
	entry.briefing += " Mind Blast counts both hands when it resolves; its own card has already left your hand. The opponent has no ether or channels."
	entry.briefing_ru += " Удар по Разуму считает обе руки в момент действия; его карта к этому времени уже покинула вашу руку. У врага нет эфира и каналов."
	if profile.id == "el2":
		entry.briefing += " Greater Unsummoning also costs one ether per creature it returns."
		entry.briefing_ru += " Великое Развоплощение дополнительно стоит один эфир за каждое возвращённое существо."
	entry.refutations = [trap]
	entry.generated = {"variant": variant, "mechanics": ["return to hand", "hand-size damage", "symmetric damage", "self-discard" if self_discard else ("target availability" if spend_first else "hand-count threshold")],
		"development_requirements": [
			{"label": "Mind Blast is essential", "without_player": {"casts": ["MDBL"]}},
			{"label": "Returning both armies is essential", "without_player": {"effects": ["bounce_all"]}}
		]}
	if spend_first:
		entry.generated.development_requirements.append({"label": "The targeted return is essential before its targets disappear", "without_player": {"effects": ["unsummon"]}})
	elif self_discard:
		entry.generated.development_requirements.append({"label": "Discarding creature cards is essential", "without_player": {"casts": ["CURS"]}})
	return entry
