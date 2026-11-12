class_name ELTextFixes
extends RefCounted
## Corrections to original card and spell texts that describe something other
## than what the games (and this remake) actually do. The player's own texts
## stay the source: each correction replaces one phrase of the English or the
## Russian original when that phrase is present, so other language editions
## and re-worded versions of a text are left untouched.
##
## Each entry is [old phrase, new phrase]. An empty old phrase appends the new
## one, once.

## Effects that the texts call "until end of turn" last until the end of the
## caster's opponent's turn: cast in the caster's own turn they also cover the
## opponent's whole next turn; cast while defending they end with that turn.
const _OPPONENT_TURN_EN := [["until end of turn", "until the end of the enemy hero's turn"], ["Until end of turn", "Until the end of the enemy hero's turn"]]
const _OPPONENT_TURN_RU := [["до конца хода", "до конца хода противника"]]

const SHARED := {
	# Unsummoned creatures return to their original owner, even when stolen.
	"UNSMTt": [["it's controller's hand", "its owner's hand"], ["its controller's hand", "its owner's hand"]],
	"LSUSTt": [["it's controller's hand", "its owner's hand"], ["its controller's hand", "its owner's hand"]],
	"GRUNTt": [["their controller's hand", "their owners' hands"]],
	# Either hero may be chosen.
	"NOISTt": [["Opponent discards 3 spells", "Target hero discards 3 spells"], ["Противник сбрасывает с руки 3", "Указанный герой сбрасывает с руки 3"]],
	# Its gaze may target the player's own creatures too.
	"BHWRTt": [["указанное создание противника, которое", "указанное создание, которое"]],
	# The damage comes at the end of each of the affected hero's own turns.
	"MDNSTt": [["at the end of each turn", "at the end of each of his or her turns"], ["в конце каждого хода", "в конце каждого своего хода"]],
	"IRRTTt": [["at the end of each turn", "at the end of each of his or her turns"], ["в конце каждого хода", "в конце каждого своего хода"]],
	"RDISTt": [
		["Controller of the enchanted creature is dealt 2 damage each turn.", "Controller of the enchanted creature suffers 2 damage at the end of each of his or her turns."],
		["Controller of the enchanted creature is dealt 2 damage each turn", "Controller of the enchanted creature suffers 2 damage at the end of each of his or her turns. Enchanted creature can't use abilities"],
		["Владелец зачарованного создания получает 2 ед. урона в конце каждого хода", "Владелец зачарованного создания получает 2 ед. урона в конце каждого своего хода. Зачарованное создание не может использовать свои способности"]],
	"TRSNTt": [["to that hero at the end of each turn", "to that hero at the end of each of his or her turns"], ["этому герою 1 ед. урона в конце каждого хода", "этому герою 1 ед. урона в конце каждого его хода"]],
	"SWSNTt": [["to that hero at the end of each turn", "to that hero at the end of each of his or her turns"], ["этому герою 1 ед. урона в конце каждого хода", "этому герою 1 ед. урона в конце каждого его хода"]],
	"FOGGTt": [["no combat damage this turn", "no combat damage until the end of the enemy hero's turn"], ["на текущем ходу", "до конца хода противника"]],
	"ASSTTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"FDBKTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"LNRDTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"ETCHTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"PLSLTt": _OPPONENT_TURN_EN + [["До конца хода", "До конца хода противника"]],
	"ORPLTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"ASLTTt": [["Until the end of turn,", "Until the end of the enemy hero's turn,"]] + _OPPONENT_TURN_RU,
	# Creature bonuses last until the end of a turn of the creature owner's opponent.
	"BLSSTt": [["until end of turn", "until the end of its owner's opponent's turn"], ["до конца хода", "до конца хода противника его владельца"]],
	"CMBNTt": [["until the end of turn", "until the end of its owner's opponent's turn"], ["до конца хода", "до конца хода противника его владельца"]],
	"ALSTTt": [["At the end of turn", "At the end of the opponent's turn"], ["В конце текущего хода", "В конце хода противника"]],
	# The wall's paralysis stops attacks rather than damage.
	"WLDTTt": [
		["prevent all combat damage dealt this turn", "creatures cannot attack until the end of the enemy hero's turn"],
		["делает невозможным причинение физического урона на текущем ходу", "делает невозможной атаку созданиями до конца хода противника"],
		["делает невозможной атаку созданиями )", "делает невозможной атаку созданиями до конца хода противника)"]],
	"EWLDTt": [["Prevent all combat damage dealt this turn", "Creatures cannot attack until the end of the enemy hero's turn"], ["До конца хода создания", "До конца хода противника создания"]],
	# The returned creature must cost exactly X.
	"SCBRTt": [["casting cost X or less", "casting cost X"], ["стоимостью вызова X или меньше", "стоимостью вызова X"]],

	# --- Creatures ---
	# The bat flies (its table says so), but its text never mentions it.
	"VBATTt": [["Rest, pay 3 ether: drain", "Flying. Rest, pay 3 ether: drain"], ["Вкус крови (", "Летает. Вкус крови ("]],
	# Any damage since the end of the controller's previous turn saves a Velos.
	"SMVLTt": [["receives no damage this turn", "has received no damage since the end of its controller's previous turn"],
		["не получает урона до конца хода", "не получал урона с конца предыдущего хода своего владельца"]],
	"BGVLTt": [["receives no damage before the end of it's controller's turn", "has received no damage since the end of its controller's previous turn"],
		["receives no damage before the end of its controller's turn", "has received no damage since the end of its controller's previous turn"],
		["не получил урона до конца хода", "не получал урона с конца предыдущего хода своего владельца"]],
	# Wall and spirit boosts last until the end of the opponent's turn.
	"WLLVTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"WLIFTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"WLWDTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"PHWLTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	"WZSPTt": _OPPONENT_TURN_EN + _OPPONENT_TURN_RU,
	# The burn lasts until the end of the elemental's controller's turn.
	"FRELTt": [["until the next turn", "until the end of the Fire Elemental controller's turn"], ["до начала следующего хода", "до конца хода владельца элементаля огня"]],
	# The frenzy reaches only the Mother Bee's own bees.
	"MOBETt": [["All Bees gain Berserk until", "All friendly Bees gain Berserk until"], ["все пчелы становятся агрессивными", "все дружественные пчелы становятся агрессивными"]],
	# Hoppers rise only at the end of their owner's turn.
	"HOPRTt": [["At the end of turn if", "At the end of its owner's turn if"], ["если в конце хода в могильнике", "если в конце хода владельца в могильнике"]],
	"MXHPTt": [["At the end of turn if", "At the end of its owner's turn if"], ["если в конце хода в могильнике", "если в конце хода владельца в могильнике"]],
	"MNHPTt": [["At the end of turn if", "At the end of its owner's turn if"], ["если в конце хода в могильнике", "если в конце хода владельца в могильнике"]],
	"KBELTt": [["get up all kobolds", "get up all friendly Kobolds"], ["поднимает всех кобольдов", "поднимает всех дружественных кобольдов"]],
	# Only untapped targets are counted.
	"MTSCTt": [["number of enemy Walls", "number of untapped enemy Walls"], ["количество телохранителей противника", "количество не отдыхающих телохранителей противника"]],
	"MTPTTt": [["number of enemy creatures", "number of untapped enemy creatures"], ["количество созданий противника", "количество не отдыхающих созданий противника"]],
	# The Russian Steel and Iron Mechos texts name the Bronze one.
	"STMCTt": [["урон от бронзового мехоса", "урон от стального мехоса"]],
	"IRMCTt": [["урон от бронзового мехоса", "урон от железного мехоса"]],
	"LMWKTt": [["Rest: owner draws", "Rest: controller draws"]],
	# Halos take what the opponent has, up to their number.
	"RVHLTt": [["отбирает у противника 2 ед.", "отбирает у противника до 2 ед."]],
	"SEHLTt": [["отбирает у противника 4 ед.", "отбирает у противника до 4 ед."]],
	"SWHLTt": [["отбирает у противника 6 ед.", "отбирает у противника до 6 ед."]],
}

const EDITIONS := {
	"el1": {
		# Every creature it strikes counts, including those that survive.
		"FRNTTt": [["where X - number of destroyed creatures", "where X is the number of creatures it strikes, including those that survive"],
			["где X – число уничтоженных созданий", "где X – число созданий, которые оно поразило, включая выживших"]],
		# Only the caster's own castle is repaired.
		"GlSpTtBNNT": [["Heal 4 Damage to all friendly castles", "Heal 4 damage to your castle"], ["энергию всех дружественных Замков", "энергию вашего Замка"]],
	},
	"el2": {
		# Unsummoned creatures return to their original owner; Lock Aspect hurts the owner.
		"PRBNTt": [["enchanted creature's controller loses life", "enchanted creature's owner loses life"]],
		# Counts the caster's creatures that are not Pale, in either aspect.
		"OFLXTt": [["number of bright aspect creatures under control", "number of non-Pale creatures under the caster's control"],
			["сколько эфирных созданий находится под контролем героя", "сколько не бесцветных созданий находится под контролем героя"]],
		# It can only be used with ether in the pool, though none is spent.
		"SACRTt": [["Sacrifice creature: draw 2 spells", "Sacrifice creature: draw 2 spells. Needs at least 1 ether, which is not spent"],
			["За принесение в жертву создания дает 2 заклинания", "За принесение в жертву создания дает 2 заклинания. Требует хотя бы 1 ед. эфира, которая не тратится"]],
		# Pale Devourers: Walls are valid prey, the life is the prey's remaining
		# toughness, and every reward needs the prey to die.
		"OUD1Tt": [["target non-Wall bright aspect creature", "target bright aspect creature"], ["equal to destroyed creature's toughness", "equal to destroyed creature's remaining toughness"],
			["которое не является телохранителем и его сила меньше", "если его сила меньше"],
			["Владелец получает столько здоровья, сколько здоровья было у уничтоженного создания", "Если создание погибло, владелец получает столько здоровья, сколько здоровья у него оставалось"]],
		"OUD2Tt": [["Владелец получает столько здоровья", "Если создание погибло, владелец получает столько здоровья"]],
		"OUD3Tt": [["Владелец получает 1 эфирный канал", "Если создание погибло, владелец получает 1 эфирный канал"]],
		# The spell given up to manifest is a random one.
		"OSJ1Tt": [["Sacrifice spell from hand", "Discard a random spell from hand"], ["жертвой заклинания с руки", "жертвой случайного заклинания с руки"]],
		"OSJ2Tt": [["Sacrifice spell from hand", "Discard a random spell from hand"], ["жертвой заклинания с руки", "жертвой случайного заклинания с руки"]],
		"OSJ3Tt": [["Sacrifice spell from hand", "Discard a random spell from hand"], ["жертвой заклинания с руки", "жертвой случайного заклинания с руки"]],
	},
}

const _NO_EFFECT_EN := " (This spell has no effect.)"
const _NO_EFFECT_RU := " (Это заклинание ничего не делает.)"

## `value`, the text `key` of `edition`, with its corrections applied.
static func apply(edition: String, key: String, value: String) -> String:
	var fixes: Array = SHARED.get(key, []) + Dictionary(EDITIONS.get(edition, {})).get(key, [])
	if edition == "el1" and key.begins_with("GlSpTt"):
		var code := key.trim_prefix("GlSpTt")
		if code in ELGlobalSpells.UPKEEP_ONLY or code in ELGlobalSpells.CONSUMED:
			fixes = fixes + [["", _NO_EFFECT_RU if RegEx.create_from_string("[\\x{0400}-\\x{04FF}]").search(value) != null else _NO_EFFECT_EN]]
	for fix: Array in fixes:
		var old: String = fix[0]
		var new: String = fix[1]
		if old.is_empty():
			if not value.strip_edges().ends_with(new.strip_edges()): value = value.strip_edges() + new
		else:
			value = value.replace(old, new)
	return value
