class_name ELPuzzleSpellRecipes
extends RefCounted
## Spell-centric constructions which do not estimate damage from card names.
## They replay the actual spells on a safe high-health board, then set the
## lethal threshold from the observed engine result. Replay is only a recipe
## precondition: the generator must still prove the win, minimum tactic count,
## shorter horizon, and a losing mistake against all legal enemy replies.

const FAMILIES := ["comet_split", "trade_compensation", "carnivore_choice"]

static func families(edition: String) -> Array[String]:
	if edition == "el2": return ["comet_split", "trade_compensation", "carnivore_choice"]
	if edition == "el1": return ["comet_split", "trade_compensation"]
	return []

static func supports(family: String, difficulty: int) -> bool:
	return family in FAMILIES and difficulty in [3, 4]

static func variants(family: String, difficulty: int) -> Array[String]:
	if not supports(family, difficulty): return []
	match family:
		"comet_split": return ["reserve_life_drain"] if difficulty == 3 else ["reserve_then_third_hit"]
		"trade_compensation": return ["pay_the_defender"] if difficulty == 3 else ["enhance_before_exchange"]
		"carnivore_choice": return ["feed_the_wall"] if difficulty == 3 else ["prepare_the_meal"]
	return []

static func build(profile: ELProfile, family: String, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	if profile == null or family not in families(profile.id) or not supports(family, difficulty): return {}
	match family:
		"comet_split": return _comet_split(profile, rng, difficulty)
		"trade_compensation": return _trade_compensation(profile, rng, difficulty)
		"carnivore_choice": return _carnivore_choice(profile, rng, difficulty)
	return {}

static func _spell_exists(profile: ELProfile, cards: Array) -> bool:
	var rows: Dictionary = profile.table("CombatSpells")
	for card: String in cards:
		if not rows.has(card): return false
	return true

## Calibrate only from spells actually accepted by ELDuel. Replaying a
## reference against a large health pool avoids baking in unverified X scaling,
## edition-specific sacrifice bonuses, or a compensation amount for Trade.
## The final lethal position is independently restored and verified later.
static func _spell_delta(profile: ELProfile, state: Dictionary, actions: Array) -> Dictionary:
	var probe: Dictionary = state.duplicate(true)
	# Leave healing headroom: Trade compensates the second target's owner.
	# Measuring at maximum health would erase that compensation and create
	# a wrong lethal threshold when the real target starts wounded.
	probe.heroes[1].health = 60
	probe.heroes[1].maximum = 99
	probe.heroes[0].maximum = maxi(20, int(probe.heroes[0].health))
	var duel := ELDuel.new()
	duel.searching = true
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": probe}): return {}
	var initial_enemy := int(duel.heroes[1].health)
	for raw: Dictionary in actions:
		if duel.phase == ELDuel.Phase.FINISHED or not ELPuzzleProof.apply(duel, raw): return {}
		if duel.winner == 1 or int(duel.heroes[0].health) <= 0: return {}
	return {"damage": initial_enemy - int(duel.heroes[1].health), "mana": int(duel.heroes[0].mana),
		"own_health": int(duel.heroes[0].health), "state": duel.snapshot()}

static func _finish_spell_entry(profile: ELProfile, state: Dictionary, prep: Array, attack_power: int,
		title: String, title_ru: String, hints: Array, hints_ru: Array, explanation: String,
		explanation_ru: String, solution: Array, metadata: Dictionary, trap: Dictionary) -> Dictionary:
	var measurement := _spell_delta(profile, state, prep)
	if measurement.is_empty(): return {}
	# No fixed threshold is assumed for direct damage or opponent healing.
	var target_health := int(measurement.damage) + attack_power
	if target_health <= 0 or target_health > 50: return {}
	state.heroes[1].health = target_health
	# Preserve healing room here too; otherwise a measurement that included
	# Trade's life gain would be inconsistent with the final board.
	state.heroes[1].maximum = maxi(40, target_health + 25)
	var entry := ELPuzzleRecipes._entry(state, title, title_ru, hints, hints_ru, explanation, explanation_ru, solution)
	entry.id = "spell_recipe_candidate"
	entry.level = 3
	entry.generated = metadata
	entry.refutations = [trap]
	entry.briefing += " The displayed ether is the entire budget; variable-X spells and ordered secondary targets use their normal costs."
	entry.briefing_ru += " Указанный эфир — весь запас; переменные значения X и упорядоченные дополнительные цели подчиняются обычным правилам стоимости."
	# Avoid handing users an unplayable reference. This is not a replacement
	# for the adversarial proof or its meaningful-mistake/difficulty checks.
	if not ELPuzzleGenerator.replay_line(profile, entry, solution).get("ok", false): return {}
	return entry

## Comet's X and Tap Life's X are paid from the SAME reservoir and deal the
## same damage per ether, so the choice is WHERE the Comet goes: only Comet
## can clear the blocker, and only an unblocked attacker turns the rest of
## the reservoir into a win. The attacker's power exceeds blocker toughness
## plus Tap Life's (and Zap's) base cost, so burning the hero instead always
## falls short. Expert adds a second, one-toughness blocker for Zap.
static func _comet_split(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var expert := difficulty == 4
	var hand: Array = ["TPLF", "COMT"]
	if expert: hand.append("ZAPP")
	if not _spell_exists(profile, hand): return {}
	var overhead := ELPuzzleRecipes._cost(profile, ["TPLF"] + (["ZAPP"] if expert else []))
	var attackers: Array = []
	for card: String in ["LMWK", "GBAT"]:
		# Even a one-toughness blocker must leave the attack ahead of a burn.
		if profile.table("CombatCreatures").has(card) and ELPuzzleRecipes._power(profile, card) > 1 + overhead: attackers.append(card)
	if attackers.is_empty(): return {}
	var attacker := String(ELPuzzleRecipes._pick(rng, attackers))
	var flying := ELCatalog.flags(profile.table("CombatCreatures")[attacker]).has("Fly")
	# Blockers must be able to stop the attacker: flyers for a flyer.
	var walls: Array = ["WLAR", "AVSC", "BATT", "BEWR"] if flying else ["WLAR", "SPFG", "AVSC", "STRT", "BATT"]
	var small: Array = ["BEWR"] if flying else ["STRT", "BEWR"]
	var wall := String(ELPuzzleRecipes._pick(rng, walls))
	var units: Array = [ELPuzzleRecipes._unit(profile, attacker, 2, 0), ELPuzzleRecipes._unit(profile, wall, 3, 1)]
	var toughness := ELPuzzleRecipes._toughness(profile, wall)
	if expert:
		var second := String(ELPuzzleRecipes._pick(rng, small))
		if ELPuzzleRecipes._toughness(profile, second) != 1: return {}
		units.append(ELPuzzleRecipes._unit(profile, second, 4, 1))
	var power := ELPuzzleRecipes._power(profile, attacker)
	if toughness < 1 or power <= toughness + overhead: return {}
	var reserve := rng.randi_range(2, 4)
	var budget := ELPuzzleRecipes._cost(profile, hand) + toughness + reserve
	var state := ELPuzzleRecipes._state(profile, units, hand, budget, 30)
	state.heroes[0].health = rng.randi_range(2, 5)
	var comet := ELPuzzleRecipes._cast("COMT", 3)
	comet.power = toughness
	var prep: Array = [comet]
	if expert: prep.append(ELPuzzleRecipes._cast("ZAPP", 4))
	var drain := ELPuzzleRecipes._cast("TPLF", 1)
	drain.power = reserve
	prep.append(drain)
	var solution: Array = prep.duplicate(true)
	ELPuzzleRecipes._finish_attacks(solution, [2])
	var wrong := ELPuzzleRecipes._cast("COMT", 1)
	wrong.power = budget - ELPuzzleRecipes._cost(profile, ["COMT"])
	var variant := "reserve_then_third_hit" if expert else "reserve_life_drain"
	return _finish_spell_entry(profile, state, prep, power,
		"The Same Reservoir", "Общий запас",
		["Comet and Tap Life draw from one ether reserve and deal the same damage per ether. What differs is what each can target.",
			"Your attacker hits harder than any spell this reserve can pay for, but only if nothing stands in its way.",
			"Spend exactly enough X on Comet to destroy the blocker (use Zap on the frail one in the harder variant), pour the rest into Tap Life, then attack."],
		["Комета и Поглощение Жизни берут эфир из одного запаса и наносят одинаковый урон за единицу эфира. Различаются их цели.",
			"Ваш боец бьёт сильнее, чем позволяет этот запас заклинаниям, — но только если путь свободен.",
			"Вложите в Комету ровно столько X, чтобы уничтожить защитника (в сложном варианте хрупкого добейте Искрой), остальное — в Поглощение Жизни, затем атакуйте."],
		"Every ether spent on Tap Life or on Comet at the hero is worth one damage, but an unblocked attacker is worth more than the ether a blocker costs to remove. Aim the variable spell at the creature, not the hero.",
		"Каждая единица эфира в Поглощении Жизни или в Комете по герою — это единица урона, но свободная атака стоит дороже эфира на устранение защитника. Направьте переменное заклинание в существо, а не в героя.",
		solution, {"variant": variant, "planned_own_turns": 1,
			"mechanics": ["variable X allocation", "life transfer", "shared ether reserve", "clear the blocker"],
			"development_requirements": [{"label": "Life transfer must contribute", "without_player": {"casts": ["TPLF"]}},
				{"label": "The Comet is necessary", "without_player": {"casts": ["COMT"]}}]},
		{"label": "Spend the whole reserve on a Comet at the hero", "commands": [wrong]})

## Trade destroys two chosen creatures but its compensation goes to the
## second creature's controller. The removal can open an air lane while
## simultaneously making the opposing hero harder to kill.
static func _trade_compensation(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var hand: Array = ["TRAD", "COMT"]
	var enhanced := difficulty == 4
	if enhanced: hand.append("STRG")
	if not _spell_exists(profile, hand): return {}
	# Comet could also kill the guard without healing its owner. X above the
	# guard's toughness makes Trade's debt cheaper than that, and a strong
	# flyer keeps a pure Comet at the hero short. The fodder cannot attack.
	# Strength (+4 for 2 ether) beats putting the same ether into Comet's X.
	var flyer := "GBAT"
	var fodder := String(ELPuzzleRecipes._pick(rng, ["WLAR", "WLBZ"]))
	var guard := String(ELPuzzleRecipes._pick(rng, ["BATT", "AVSC"]))
	var units: Array = [ELPuzzleRecipes._unit(profile, flyer, 2, 0),
		ELPuzzleRecipes._unit(profile, fodder, 3, 0), ELPuzzleRecipes._unit(profile, guard, 4, 1)]
	var x := rng.randi_range(3, 5)
	if x <= ELPuzzleRecipes._toughness(profile, guard): return {}
	var mana := ELPuzzleRecipes._cost(profile, hand) + x
	var state := ELPuzzleRecipes._state(profile, units, hand, mana, 30)
	var trade := ELPuzzleRecipes._cast("TRAD", 3)
	trade.grave = 4
	var comet := ELPuzzleRecipes._cast("COMT", 1)
	comet.power = x
	var prep: Array = [trade]
	if enhanced: prep.append(ELPuzzleRecipes._cast("STRG", 2))
	prep.append(comet)
	var solution: Array = prep.duplicate(true)
	ELPuzzleRecipes._finish_attacks(solution, [2])
	var attack_power := ELPuzzleRecipes._power(profile, flyer) + (ELPuzzleRecipes._bonus(profile, "STRG") if enhanced else 0)
	var wrong := ELPuzzleRecipes._cast("TRAD", 2)
	wrong.grave = 4
	return _finish_spell_entry(profile, state, prep, attack_power,
		"The Price of a Passage", "Цена прохода",
		["The enemy's flying defender can stop your attacker. Removing it also changes the opposing hero's life total.",
			"Trade's two creature choices are ordered: the second creature's controller receives the compensation. Preserve your own creature that can attack.",
			"Trade the disposable creature for the flying guard, account for the enemy's healing, then spend Comet's X and attack with your surviving flyer."],
		["Летающий защитник врага остановит вашу атаку. Но его устранение также изменит здоровье вражеского героя.",
			"У Торга две упорядоченные цели: компенсацию получает хозяин второго существа. Сохраните своего бойца, способного атаковать.",
			"Обменяйте ненужное существо на летучего стража, учтите лечение врага, затем примените Комету с X и атакуйте оставшимся летуном."],
		"A removal spell can create a health debt. Trade removes the sole air blocker but rewards its owner; the remaining spells and flying attack must pay that debt and still reach lethal.",
		"Устранение стража может создать долг по здоровью. Торг убирает единственного воздушного защитника, но вознаграждает его хозяина; оставшиеся заклинания и удар летуна должны перекрыть долг и завершить бой.",
		solution, {"variant": "enhance_before_exchange" if enhanced else "pay_the_defender", "planned_own_turns": 1,
			"mechanics": ["ordered two-target trade", "opponent compensation", "clear flying guard", "variable X followup"],
			"development_requirements": [{"label": "Trade opens the lane", "without_player": {"casts": ["TRAD"]}},
				{"label": "Comet funds the finishing damage", "without_player": {"casts": ["COMT"]}}]},
		{"label": "Trade away the sole aerial attacker", "commands": [wrong]})

## In EL2 Carnivorous consumes a living creature, draws/heals the caster,
## and damages the opponent for a positive-power meal. The meal competes
## with the attacker: eating the flying finisher looks convenient but fails.
static func _carnivore_choice(profile: ELProfile, rng: RandomNumberGenerator, difficulty: int) -> Dictionary:
	var prepare := difficulty == 4
	var hand: Array = ["CANV", "CLIG"]
	if prepare: hand.append("STRG")
	if not _spell_exists(profile, hand): return {}
	var meal := String(ELPuzzleRecipes._pick(rng, ["LMWA", "IRMC"]))
	var flyer := String(ELPuzzleRecipes._pick(rng, ["BATT", "AVSC", "GBAT"]))
	# Lightning must actually destroy the aerial guard (3 damage).
	var guard := String(ELPuzzleRecipes._pick(rng, ["BATT", "AVSC", "AVEL"]))
	if ELPuzzleRecipes._toughness(profile, guard) > 3: return {}
	var units: Array = [ELPuzzleRecipes._unit(profile, meal, 2, 0, {"resting": true}),
		ELPuzzleRecipes._unit(profile, flyer, 3, 0), ELPuzzleRecipes._unit(profile, guard, 4, 1)]
	var state := ELPuzzleRecipes._state(profile, units, hand, ELPuzzleRecipes._cost(profile, hand), 30)
	state.heroes[0].health = rng.randi_range(2, 5)
	# The fixed deck contains a harmless, unaffordable large creature; a
	# Carnivorous draw is an actual effect, never a surprise new winning spell.
	state.heroes[0].deck = ["BLDG"]
	var prep: Array = []
	if prepare: prep.append(ELPuzzleRecipes._cast("STRG", 2))
	prep.append(ELPuzzleRecipes._cast("CANV", 2))
	prep.append(ELPuzzleRecipes._cast("CLIG", 4))
	var solution: Array = prep.duplicate(true)
	ELPuzzleRecipes._finish_attacks(solution, [3])
	return _finish_spell_entry(profile, state, prep, ELPuzzleRecipes._power(profile, flyer),
		"Which Creature to Feed?", "Кого скормить?",
		["A creature is both battlefield pressure and a resource for Carnivorous. Not every sacrifice leaves a way to attack.",
			"The ground creature is resting while the flyer can strike this turn. Reserve the flyer and deal with its aerial blocker.",
			"Prepare the resting meal if the extra enhancement is present; feed it to Carnivorous, remove the flying guard with lightning, then attack with your untouched flyer."],
		["Существо — это и сила на поле, и пища для Плотоядности. Не каждая жертва оставляет возможность атаковать.",
			"Наземный боец отдыхает, а летун способен ударить сейчас. Сохраните летуна и устраните его воздушного защитника.",
			"В усиленном варианте сначала подготовьте отдыхающую жертву; скормите её Плотоядности, уберите летучего стража молнией и атакуйте оставшимся летуном."],
		"Carnivorous converts a disposable ground body into an immediate spell effect. The flying creature is more valuable alive, because it supplies the attack after the defender disappears.",
		"Плотоядность превращает ненужного наземного бойца в немедленный эффект. Летуна выгоднее сохранить: именно он нанесёт удар после устранения защитника.",
		solution, {"variant": "prepare_the_meal" if prepare else "feed_the_wall", "planned_own_turns": 1,
			"mechanics": ["sacrifice timing", "Carnivorous life and draw", "preserve evasive attacker", "remove aerial blocker"],
			"development_requirements": [{"label": "Carnivorous must contribute", "without_player": {"casts": ["CANV"]}},
				{"label": "Lightning opens the attack", "without_player": {"casts": ["CLIG"]}}]},
		{"label": "Devour the sole flying attacker", "commands": [ELPuzzleRecipes._cast("CANV", 3)]})
