class_name ELCombatBrain
extends RefCounted
## The computer opponent's link to the compiled combat lookahead
## (el_duel_brain.c): packs a duel position into the compact model that
## library searches (armies with their combat keywords, health, ether and the
## creature cards to come) and reads back its answer. ELCombatSearch plays the
## real rules for the move it is choosing and asks here what the fighting of
## the next turns leads to. Without the library (the browser version) nothing
## is asked.
##
## With `ELCombatSearch.smart_brain_cards` (off: it measured no stronger) the
## model's sides also play cards. It knows the computer's own creature cards
## in hand. Of the other hand it knows only what a player sees: how many
## cards it holds and the hero's colour, so it expects a typical creature of
## that colour as often as that colour's cards are creatures.

static var available := ClassDB.class_exists(&"ELNativeDuelBrain")

const HEADER := 40
## The layout of the state the library is handed: it answers no other.
const VERSION := 11
## Enchantments a hero lays on itself that the engine has a rule for, in the
## engine's own order.
const CHARMS := ["LSHE", "FRBL", "RNST", "ENRG", "RPST", "CMBN", "RBRT", "SCBR", "SPLK", "BROT", "SACR", "OEXC",
	"STWO", "ENWO", "DOMN", "JYHD", "CRBL", "IMML", "ASLT", "VTLY",
	"BLKD", "HAST", "RDDF", "DMRD", "ORPL", "DRGS", "DPGS", "FRGS", "MNTX", "FOGG", "HOAM", "SFGS", "SMOK", "FLOD", "CNAR",
	"ENLH", "TRLB", "PLWP", "WLDT",
	"MNVR", "MNTH", "MNBN", "STSI", "SPTR", "FTDS", "COPL", "FDBK", "LNRD", "FURY", "ASST", "SPWB", "ETCH",
	"BASO", "PRWT", "PLSL", "OST1", "OST2", "OST3", "LCWR", "GCWR", "LSWR", "GSWR", "LEWR", "GEWR",
	"WETX", "STTX", "WTX2", "ESWS",
	"ENVM", "PRWR",
	"STSK", "LFGR", "ENBR"]
## Marks that stand for one of those under another name: the second game's
## distortion is a card of its own, and a snake's venom in a hero is the same
## whichever snake left it.
const CHARM_TWINS := {"EWLD": "WLDT", "TRSN": "ESWS", "SWSN": "ESWS", "ETRS": "ESWS", "PCDU": "ASST"}
const CHARM_FIELDS := 14
## The first of them give their hero an ability, by the rules' name for it.
const HERO_KEYS := ["heal", "fireball", "stone_rain", "energize", "repair", "combine", "rebirth", "second_birth", "spirit_lock",
	"burnout", "sacrifice", "recycle"]
## Those that end with the next turn that is not their caster's.
const CHARMS_ENDING := ["ASLT", "RDDF", "ORPL", "FOGG", "WLDT", "FDBK", "LNRD", "FURY", "ASST", "ETCH", "PLSL"]
## Those the engine lays on a hero or on a creature alike.
const CHARMS_ANY := ["STSK", "LFGR", "ENBR"]
## Snakes whose blow on a hero leaves their venom in it.
const ENVENOMS := ["TRSN", "SWSN"]
## Enchantments on a creature that end with a turn of the other hero's.
const BRIEF := ["BLSS", "ALST", "CMBN", "RLSS"]
## What each gas takes from every creature: [power, toughness].
const GASES := {"DRGS": [-1, 0], "DPGS": [-2, 0], "FRGS": [0, -2]}
const EFFECT_CHARM := 38
const EFFECT_CONTROL := 39
const EFFECT_DELUSION := 40
## Creature cards the engine is told by kind, so that one that leaves the
## board can be played again; and the newest cards of a graveyard it is told.
const POOL := 48
const GRAVES := 12
## The plain numbers told of each hero, before its enchantments.
const HERO_SCALARS := 80
const HERO_FIELDS := HERO_SCALARS + 73 + 12 + 1 + GRAVES
const COSTS := 8
const TYPICAL_FIELDS := 4
## Measuring aid: a list of commands played by the compiled rules (`fight`,
## mode 4) takes cards drawn out of turn for unknown ones, whatever the engine
## itself is set to. A check that replays the engine's own line turns this off
## so that the replay draws what the engine counted on.
static var fight_blind := true
const HAND := 16
## Cards each hero is about to draw, which the engine is told in full.
const DRAWS := 10
const SLOTS := HAND + DRAWS
const CARD_FIELDS := 25
## Fields 66-74 of a creature: whether it has changed sides (1), and then,
## for each hero, which of that hero's army enchantments still cover it, as
## the place of each copy among those of its kind (oldest first) - four kinds
## of `ARMY_KINDS` to a field, a byte each.
const UNIT_FIELDS := 75
## The army enchantments a creature keeps when it changes sides, in the
## engine's order (`CHARMS` from "STWO" on).
const ARMY_FIRST := 12
const ARMY_KINDS := 13
## What a hero carries into the duel beside its book: each thing is told as
## the card it stands for, then the uses it has left, the round it may next be
## used in, the rounds it then waits, how it is used (the phases, and whether
## it casts a spell), and what it deals the rest of the side it hurts. Before
## them the turns the duel has seen begin and what the ether storms and
## breezes on creatures count for (`smart_income`), and for each hero the uses the duel
## allows it and those it has had. The engine plays them as cards from places
## of their own, after the hand's and those of the cards come back.
const MAX_ART := 16
const ART_FIELDS := CARD_FIELDS + 5
## Cards come back into a hand that the engine may hold at once.
const BACK := 8
const ART_BASE := SLOTS + BACK
const ARTS := 2 + 2 * (2 + MAX_ART * ART_FIELDS)
## What the battle's scripts make of each hero's creature of a kind as it is
## summoned: [power | health << 16, flags given, flags taken].
const SHAPES := 2 * POOL * 3
const FIXED := HEADER + 2 * (HERO_FIELDS + COSTS * TYPICAL_FIELDS + SLOTS * CARD_FIELDS) + 73 * CHARM_FIELDS + POOL * CARD_FIELDS + ARTS + SHAPES
const MAX_UNITS := 32
## The enchantments on creatures the engine is told one by one, and the
## fields of each.
const MAX_WORN := 48
const WORN_FIELDS := 13
## What makes an enchantment on a creature more than the points it gives.
const WORN_KINDS := {"TWEN": 2, "OVRL": 3, "PALN": 4, "STSK": 5, "LFGR": 6, "ENBR": 7, "DELS": 9, "ALST": 10, "QKFX": 11,
	"IRRT": 12, "MDNS": 12, "RDIS": 12, "REDR": 13, "ERBN": 14, "WTLK": 15, "PRBN": 16, "OCRP": 17, "MNST": 18, "MNBR": 19, "RIOT": 20, "GIFT": 21, "PRGD": 22}
## Enchantments for a creature that do more than give it points, by the
## engine's numbers for what they do.
const SPECIALS := {"PSBR": 1, "SHFR": 2, "ALNS": 3, "ALST": 4, "REDR": 5, "ERBN": 6, "PRBN": 7, "OCRP": 8, "MNST": 9, "MNBR": 10, "RIOT": 11, "WTLK": 12, "PRGD": 13}
## What an enchantment on a creature takes from its hero as a turn ends.
const TICKS := {"IRRT": 1, "MDNS": 2, "RDIS": 2}
## What a creature lays on a hero costs to remove, in the first game and
## the second: no card's price.
const MARK_PRICES := {"WLDT": [0, 10], "ESWS": [0, 1]}
## Enchantments that keep a creature from what it can do.
const MUTING := ["IRRT", "MDNS", "RDIS"]
## Own turns whose channel income and ether disturbance the model is told.
const INCOME_TURNS := 16

## Creature flags the model knows, by the rules' names.
const FLAGS := {"Fly": 1, "FS": 2, "Trample": 4, "UB": 8, "Elusive": 16, "NoAttack": 64, "Restless": 128, "NoUntap": 256,
	"Destroy": 512, "Lifetap": 1024, "Berserk": 2048, "TeamAttack": 4096, "NoRegen": 1 << 17,
	"Disenchant": 1 << 18, "NoAffect": 1 << 24}
const F_ELUSIVE := 16
const F_WALL := 32
const F_NO_UNTAP := 256
const F_RESTING := 8192
const F_SICK := 16384
const F_PLANE := 32768
const F_ATTACKING := 65536
const F_DESTROY_UNWALLED := 1 << 19
const F_STINGER := 1 << 20
## A bright pale creature dissipates into the plane rather than die; a fire
## elemental's burn leaves its target no room to regenerate.
const F_DISSIPATES := 1 << 21
const F_BURN := 1 << 22
## The lake snake, whose bite shrinks what it hits.
const F_VENOM := 1 << 23
## The hellfire wall, whose whirl destroys the flyers it wounded.
const F_DESTROY_FLYER := 1 << 25
## A velo, which destroys itself at its owner's turn end unless it was hit,
## and the mark of having been hit since that hero's last turn end.
const F_FATALIST := 1 << 26
const F_HIT := 1 << 27
## The fire elemental, whose strike marks what it hits, and the lake snake.
const BURNS := "FREL"
const VENOMOUS := "LASN"
const WHIRLS := "WLIF"
## The effects the model can play itself, by the rules' names for them.
const EFFECTS := {"summon": 1, "damage": 2, "wave": 3, "destroy": 4, "heal": 5, "mana": 6, "channels": 7,
	"enchant": 8,
	# Spells that are each a rule of their own, in the order the library numbers them.
	"unsummon": 9, "exile": 10, "annihilate": 11, "full_heal": 12, "half_heal": 13, "draw": 14, "rest_enemies": 15,
	"rally_all": 16, "burn_mana": 17, "drain_mana": 18, "drain_life": 19, "channel": 20, "hunger": 21,
	"hunger_all": 22, "hunger_both": 23, "sacrifice_heal": 24, "devour": 25, "polymorph": 26, "symbiosis": 27,
	"twister": 28, "bounce_all": 29, "mind_blast": 30, "discard_all": 31, "revive": 32, "fury_of_nature": 33,
	"grave_fire": 34, "discard_creatures": 35, "random_discard": 41,
	"repair": 42, "reanimate": 43, "amnesia": 44, "ban": 45, "clone": 46, "exchange": 47, "swap": 48, "redraw": 49,
	"dispel": 50, "cleanse": 51, "trade": 52, "gift": 53,
	"banish": 54, "flux": 55, "pale_blast": 56, "pale_calamity": 57, "pale_cleave": 58, "pale_revival": 59, "pale_theft": 60,
	"vaporize": 61, "ripple": 62, "bless": 63}
## What a card names beside its target, by its effect: a card of the graveyard
## aimed at (1), one of the caster's own graveyard (2), another creature (3).
const CHOICES := {"repair": 1, "reanimate": 1, "exchange": 2, "swap": 3, "dispel": 4, "trade": 5, "pale_revival": 6}
## What the second game's pale creatures may do, by the engine's numbers.
const PALE_KEYS := ["", "dissipate", "sinister", "cruel", "fiendish", "mystic", "cryptic", "courtesy", "channel_ether", "ether_plea",
	"pale_heal", "absorb", "weave", "transpose", "pale_devour"]
## Abilities that name an enchantment on what they are aimed at.
const DISPELLING := ["dispel", "orc_rite", "disenchant"]
## The second game's spell jammers, in the order of the traps that let them out.
const JAMMERS := ["OSJ1", "OSJ2", "OSJ3"]
const JAMMER_TRAPS := ["OST1", "OST2", "OST3"]
## Enchantments that hold a creature down, and the ether that frees it.
const HOLDS := {"ENFL": 3, "IMMB": 2, "WNPZ": 4}
const HOLDS_SECOND := {"ENFL": 3, "IMMB": 3, "WNPZ": 4}
const SCOPES := {"enemy": 0, "heroes": 1, "ground": 2, "flying": 3, "all": 4, "behind": 5, "self": 6, "both": 7, "steal": 8}
## What a creature enchantment's rule may say and still be one the model
## holds: anything else is a rule of the card's own.
const PLAIN_ENCHANTMENT := ["effect", "target", "power", "toughness", "own", "lethal", "fixed"]
## Enchantments that do more than their rule says (see ELDuel._enchant).
const SPECIAL_ENCHANTMENTS := ["ALNS", "ALST", "WRBN"]
## What a spell may be aimed at.
const AIMS := {"none": 0, "creature": 1, "hero": 2, "any": 3, "enchantment": 3}
## Creatures that burst into spores: burning (one point) or stinging (its power).
const FINGI := {"SPFG": 1, "CAFG": 2}
## Creature abilities the engine has a rule for, by the engine's own numbers.
const ABILITIES := {"sting": 3, "shoot": 4, "slay": 5, "gaze": 6, "hunt": 8, "wall_break": 9, "siphon": 10, "breath": 11,
	"bat_drain": 13, "rally": 14, "tap_target": 15, "tap_walls": 16, "tap_race": 17, "ether": 18, "draw": 19, "sacrifice": 20,
	"brood": 21, "gnaw": 22, "plague": 23, "recall_lamia": 24, "recall_rat": 24, "recall_spirit": 25, "necromancy": 26,
	"distortion": 27, "lava_power": 28, "hellfire_health": 29, "phantasm": 30, "rouse": 31, "spirit_flight": 32,
	"dispel": 33, "orc_rite": 34, "disenchant": 35, "illusion": 36}
const ABILITY_BROOD := 21
## Abilities that name a card of a graveyard, and those that take an X.
const GRAVE_ABILITIES := ["gnaw", "recall_lamia", "recall_rat", "recall_spirit", "necromancy"]
const X_ABILITIES := ["plague", "lava_power", "hellfire_health"]
## Effects of the engine's own for enchantments a hero lays on itself.
## A war banner, which a hero raises out of a thing it carries.
const EFFECT_BANNER := 64
const EFFECT_TAX := 36
const EFFECT_FOREST := 37
## Ether that breaks a creature's enfeeblement (ELDuel's "wake" ability).
const WAKE_COST := 3
## The lamia warlord: every lamia costs two less while one stands.
const LAMIA_WARLORD := "LMWD"
## The heroes' specialisations, in the order the engine numbers them (from 1).
const SPECS := ["RKBC", "UAVC", "ARTF", "GMTM", "RSFN", "STHN", "MNCH", "RLSS", "BMWM", "RMBD", "UHGW", "BPRC", "RPLO", "GFNS", "UGUS", "UMBD", "BVLD", "GHLD",
	"CEXC", "GHRI", "RBNO", "GSLO", "BENG", "BRST", "GFNR", "MSEN", "ETEN", "BMZP", "BSGP", "GBLP", "ETTI", "UFLP", "RSMP", "QIHN", "GBHD", "RWSW", "UWAW",
	"BCTR", "UOCR", "BWIT", "UMTD", "RORT", "GSNV", "BFGL", "GTRL", "RBTD", "BPTD", "RRTR", "IRSK", "ATMF", "DRSK", "DRSL", "FRBD", "WRBD", "RVVE", "GSWS", "UWLS"]
## The specialisation that works for the creatures of a race, and for a card.
const RACE_MASTERY := {"Kobold": "RKBC", "Aviak": "UAVC", "Velos": "BVLD", "Halo": "GHLD", "Hornet": "GHRI", "Rat": "RRTR", "Fingus": "GFNR",
	"Beholder": "GBHD", "Cutter": "BCTR", "Gibberling": "UOCR", "Lamia": "UMTD", "Orc": "RORT", "Snake": "GSNV", "Fighter": "BFGL", "Treant": "GTRL", "Bat": "RBTD"}
const CARD_MASTERY := {"WLBR": "RWSW", "SLWL": "RWSW", "RKWL": "RWSW", "WLAR": "UWAW", "WLWD": "UWAW", "WLBZ": "UWAW", "WLIL": "BWIT", "PTRS": "BPTD", "RFPT": "BPTD"}

## The typical creature of a colour by cost, per game: {"share": creature
## cards per thousand, "stats": [[power, toughness] for costs 1..8]}.
static var _typical := {}
static var _codes := {}
static var _races := {}
## Whether the last position packed held more than the model has room for
## (for tools: a proof of it can be no more than unknown).
static var last_crowded := false
## And what it held more of than that, by name ("hand0", "enchantments", ...).
static var last_crowding: Array[String] = []
## The last position packed, as the engine was told it (for tools).
static var last_packed := PackedByteArray()
## A puzzle's objective, told after the rest of the state.
const GOAL_FIELDS := 24

## What the fighting of the next `turns` turns leads to from `s`, where the
## side to move chooses its attackers (attack phase) or the defender its
## blocks (defence phase):
##   status  1 the computer wins within those turns, -1 it loses, else 0
##   turns   with a status, the turn that decides it (1 = the one to play)
##   value   the worth gained or lost against the position as it stands
##   ids     the attackers to send, or (blocker, attacker) pairs still to assign
## Empty when the library is missing or the armies do not fit the model.
## `budget` is the number of fights played; `wide` looks at more choices, for
## picking a move rather than scoring a line.
## `mode` overrides the phase field, for the rules check (2, 3 and 4), whose
## `commands` are played out in the model.
static func ask(ctx: ELCombatSearch.Context, s: ELDuel, turns: int, budget: int, wide: bool, mode := -1, commands: Array = [], steps := 0, width := 0) -> Dictionary:
	if not available or s.creatures.size() > MAX_UNITS or s.phase == ELDuel.Phase.FINISHED: return {}
	# The compiled model packs the current modifier as a single value. If an
	# aspect change can suppress or restore it, let the full duel search play
	# the position. Diagnostic replay and move-list modes can still compare it.
	if ctx.second and mode not in [2, 3, 4, 10, 11] and _plane_sensitive(ctx, s, mode): return {}
	var state := PackedInt32Array()
	var worn_rows := 0
	for c: Dictionary in s.creatures.values(): worn_rows += c.enchantments.size()
	# And the water links, which their casters hold.
	for side in 2:
		for e: Dictionary in s.heroes[side].enchantments:
			if String(e.card) == "WTLK" and s.creatures.has(int(e.get("link", -1))): worn_rows += 1
	var worn_needed := worn_rows
	worn_rows = mini(worn_rows, MAX_WORN)
	state.resize(FIXED + s.creatures.size() * UNIT_FIELDS + worn_rows * WORN_FIELDS + commands.size() * 4)
	state[0] = VERSION
	state[1] = ctx.ai
	state[2] = s.attacker
	state[3] = mode if mode >= 0 else (0 if s.phase == ELDuel.Phase.ATTACK else 1)
	state[4] = turns
	state[5] = budget
	state[6] = 1 if ctx.second else 0
	state[7] = int(ctx.w[2] * 1000.0)
	state[8] = s.global_enchantment_count("LSDS")
	# What a copy of the attack tax costs to remove.
	state[9] = int(s.profile.table("CombatSpells").get("LSDS", {}).get("Cost", 0))

	# Each reading of the engine's own (a choice, 5; every first command
	# weighed, 7; played-out duels, 8) is told its own settings in full: the
	# commands it plays through at a node (10), the commands of a line or the
	# rounds of a played-out duel (16), and how a line is scored where it
	# stops (20, 21, 26, 27), so that the worth of a command weighed alone is
	# the worth the choice gives it.
	var reading := mode == 5 or mode == 7 or mode == 8
	state[10] = 1 if wide else 0
	if reading: state[10] = width if width > 1 else ELCombatSearch.smart_engine_width
	state[11] = s.creatures.size()
	state[12] = 1 if ctx.brain_cards else 0
	# The side to move still has its cards of this turn to play.
	state[13] = 1 if s.phase == ELDuel.Phase.ATTACK else 0
	state[14] = int(ctx.foe_health * 100.0)
	state[15] = worn_rows
	state[16] = steps if reading else commands.size()
	state[17] = 0 if s.phase == ELDuel.Phase.ATTACK else 1
	state[18] = int(ctx.w[4] * 1000.0)
	state[19] = int(ctx.w[3] * 1000.0)
	state[20] = ELCombatSearch.smart_engine_leaf if mode == 5 or mode == 7 else 0
	state[21] = int(ELCombatSearch.smart_engine_margin * 1000.0) if mode == 5 or mode == 7 else 0
	# What the engine is told of how to read: 1 remember positions (or, in a
	# play-out, fight as the lookahead advises), 2 cards drawn out of turn are
	# unknown, 4 a turn ended with nobody sent counts for both its phases,
	# 8 a set of attackers or of blocks is tried in one order only, 16 blocks
	# already set may be gone back on at the first command; then four
	# bits each for the whole attacks and the whole defences it chooses from.
	var blind: bool = ELCombatSearch.smart_engine_blind or (mode != 5 and mode != 9 and (mode != 4 or fight_blind))
	state[22] = (1 if (ELCombatSearch.smart_engine_fights and mode == 8) or (ELCombatSearch.smart_engine_table and (mode == 5 or mode == 7)) else 0) 		| (2 if blind else 0) | (16 if _revises(ctx) else 0) | (4 if ELCombatSearch.smart_engine_even else 0) | (8 if ELCombatSearch.smart_engine_ordered else 0) 		| (clampi(ELCombatSearch.smart_engine_sets, 0, 15) << 8) | (clampi(ELCombatSearch.smart_engine_plans, 0, 15) << 12) \
		| (((clampi(ELCombatSearch.smart_engine_prove, 0, 15) << 16) | (clampi(ctx.prove_share if ctx.prove_share > 0 else ELCombatSearch.smart_engine_prove_share, 1, 100) << 20) \
			| (clampi(ctx.prove_from, 0, 15) << 27)) if mode == 5 else 0)
	state[23] = int(ctx.w[6] * 1000.0)
	state[24] = int(ctx.w[7] * 1000.0)
	state[25] = int(ctx.w[8] * 1000.0)
	state[26] = 1 if ELCombatSearch.smart_engine_answer and (mode == 5 or mode == 7) else 0
	state[27] = int(ELCombatSearch.smart_engine_blend * 100.0) if mode == 5 or mode == 7 else 0
	# How many phases ahead a small position may be read when the budget allows.
	state[31] = (clampi(ELCombatSearch.smart_engine_reach, 0, 255) | (clampi(ELCombatSearch.smart_engine_spare, 1, 64) << 8) | (clampi(ELCombatSearch.smart_engine_guard, 0, 15) << 16) | (clampi(ELCombatSearch.smart_engine_guard_share, 1, 100) << 20)) if mode == 5 else 0
	# The order in which each hand gives up its cards when it holds too many:
	# from the far end of the row, five bits a place, six places to a field
	# (header 32-35).
	for side in 2:
		var row: Array[int] = s.hand_display(side)
		for k in 12:
			var place := 30
			if k < row.size(): place = row[row.size() - 1 - k] if row[row.size() - 1 - k] < HAND else 31
			state[32 + 2 * side + k / 6] |= place << (5 * (k % 6))
	# The creature cards told by kind: those on the board, the newest in each
	# graveyard, and those in a hand or about to be drawn.
	var kinds: Array = []
	var kinds_needed := 0
	var coming_cards: Array = []
	# What the engine is told each hand holds, and what each hero will draw:
	# with the information policy "fair" (`ELCombatSearch.smart_engine_info`),
	# the other hand and every card to come are sampled out of the hero's own
	# book instead, and no copy of the duel's chance foretells a draw.
	var fair := fair_info(ctx, s, mode)
	# Whose knowledge the reading is held to: the hero it is made for.
	var knower := ctx.viewer if ctx.viewer >= 0 else ctx.ai
	var holdings: Array = [s.heroes[0].hand.slice(0, HAND), s.heroes[1].hand.slice(0, HAND)]
	if fair: holdings[1 - knower] = known_hand(s, 1 - knower).slice(0, HAND)
	if (mode >= 2 or (ctx.brain_cards and ELCombatSearch.smart_brain_own)) and (ELCombatSearch.smart_engine_draws or (mode >= 2 and mode != 5)):
		coming_cards = [sampled(s, 0, DRAWS, 1), sampled(s, 1, DRAWS, 1)] if fair else foreseen(s)
	if mode >= 2:
		for c: Dictionary in s.creatures.values():
			if not kinds.has(c.card): kinds.append(c.card)
		for side in 2:
			for card: String in s.heroes[side].grave.slice(-GRAVES):
				if not kinds.has(card): kinds.append(card)
		var creatures_table: Dictionary = s.profile.table("CombatCreatures")
		for side in 2:
			var cards: Array = []
			cards.append_array(holdings[side])
			if not coming_cards.is_empty(): cards.append_array(coming_cards[side])
			for card: String in cards:
				if not card.is_empty() and creatures_table.has(card) and not kinds.has(card): kinds.append(card)
		# So is the jammer of a spell trap that stands or may be laid.
		if ctx.second:
			var laid_traps: Array = []
			for side in 2:
				for e: Dictionary in s.heroes[side].enchantments: laid_traps.append(String(e.card))
				laid_traps.append_array(holdings[side])
			for n in JAMMERS.size():
				if laid_traps.has(JAMMER_TRAPS[n]) and not kinds.has(JAMMERS[n]): kinds.append(JAMMERS[n])
		# So is what a thing a hero carries brings into play.
		for side in 2:
			for item: Dictionary in s.heroes[side].get("artifacts", []):
				var brought := String(item.get("spell", ""))
				if creatures_table.has(brought) and not kinds.has(brought): kinds.append(brought)
		# What a mother's brood lays is a card the engine must know too.
		for card: String in kinds.duplicate():
			var laid := String(ELCatalog.first_ability(s.profile, card).get("summon", ""))
			if not laid.is_empty() and not kinds.has(laid): kinds.append(laid)
		kinds_needed = kinds.size()
		kinds = kinds.slice(0, POOL)
		# After the creatures, while there is room: the enchantment cards that
		# may come into a hand as a line is played, which the engine then
		# holds by name and can cast again.
		for card: String in _returning(s, holdings, coming_cards):
			if kinds.size() < POOL and not kinds.has(card): kinds.append(card)
	# A forest on a hero holds the weak creatures of the other army.
	var held := [-1, -1]
	var auras := [0, 0]
	var income: Dictionary = s.profile.table("CombatManaIncome")
	for side in 2:
		var hero: Dictionary = s.heroes[side]
		var at := HEADER + side * HERO_FIELDS
		var skins := 0
		var guards := 0
		var reflects := 0
		var mirrors := 0
		var cards: Array = []
		for e: Dictionary in hero.enchantments:
			cards.append(String(CHARM_TWINS.get(e.card, e.card)))
			match String(e.card):
				"STSK": skins += 1
				"LFGR": guards += 1
				"FDBK", "LNRD": reflects += 1
				"ETCH": mirrors += 1
				"DNFR", "DRFR", "ANFR": held[side] = maxi(held[side], s.forest_limit(e.card))
		auras[side] = cards.hash()
		state[at] = int(hero.health)
		state[at + 1] = s.available_mana(side)
		state[at + 2] = int(hero.channels)
		# The specialisation that doubles a race's blows, and its chance; one
		# of any other kind is told only as being there.
		state[at + 3] = _spec_word(s, side)
		var odds := PackedFloat64Array([ELSpecs.expected(s, side, String(hero.get("spec", "NONE")))]).to_byte_array()
		state[at + 74] = odds.decode_s32(0)
		state[at + 75] = odds.decode_s32(4)
		state[at + 77] = 1 if hero.get("revived", false) else 0
		state[at + 4] = guards
		state[at + 5] = reflects
		state[at + 6] = mini(mirrors, 1) if ctx.second else mirrors
		state[at + 17] = hero.hand.size()
		# The most cards a hand given up and dealt again can come to, of
		# creatures and of the rest: the first game deals without end, the
		# second no more than the charges its book has left.
		var deals := [0, 0]
		for place in hero.deck.size():
			var uses := int(hero.spell_uses[place]) if place < hero.spell_uses.size() else 0
			var which := 0 if String(s.profile.table("CombatSpells").get(hero.deck[place], {}).get("Class", "")) == "Creature" else 1
			deals[which] = mini(99, int(deals[which]) + (99 if uses < 0 or s.profile.id == "el1" else uses))
		state[at + 32] = deals[0]
		state[at + 33] = deals[1]
		# Cards in the hand that are not of the book, and take up none of its uses.
		for place in hero.hand.size():
			if place >= hero.hand_slots.size() or int(hero.hand_slots[place]) < 0: state[at + 38] += 1
		for e: Dictionary in hero.enchantments:
			# The second game's vortices laid in the turn now being had, which
			# outlast it; and the turns of its own the oldest stasis has seen.
			if String(e.card) == "MNVR" and ctx.second and int(s.attacker) == side and int(e.get("born", -1)) == int(s.turn_serial): state[at + 34] += 1
			if String(e.card) == "STSI":
				# One more than the turns of its hero's it has seen begin, less
				# one for a stasis whose price has an odd turn still to wait.
				var waited := int(s.turn_serial) - int(e.get("born", s.turn_serial)) - (0 if int(s.attacker) == side else 1)
				state[at + 35] = maxi(state[at + 35], floori(float(waited) / 2.0) + 1)
		state[at + 18] = int(ELCombatSearch.hero_enchantment_worth(ctx, hero) * 1000.0)
		state[at + 19] = int(hero.get("maximum", hero.health))
		state[at + 20] = hero.grave.size()
		var buried: Array = hero.grave.slice(-GRAVES)
		for i in buried.size(): state[at + HERO_SCALARS + CHARMS.size() + HERO_KEYS.size() + 1 + i] = kinds.find(buried[i]) + 1
		# A spirit wizard of this hero has given the warrior spirits wings.
		for effect: Dictionary in hero.get("temporary", []):
			if String(effect.get("kind", "")) == "spirit_flight": state[at + 31] = 1
		# The forest on this hero, which holds the other army's weak creatures
		# at home: one more than the power it reaches, and what it is worth.
		for k in CHARMS.size(): state[at + HERO_SCALARS + k] = cards.count(CHARMS[k])
		# Copies whose ability the hero has already used this turn.
		for e: Dictionary in hero.enchantments:
			var which := CHARMS.find(String(e.card))
			if which >= 0 and which < HERO_KEYS.size() and e.get("used", false): state[at + HERO_SCALARS + CHARMS.size() + which] += 1
		state[at + 29] = int(held[side]) + 1
		# What its forest costs to remove, and what a copy of the tax is worth.
		for e: Dictionary in hero.enchantments:
			if s.forest_limit(String(e.card)) >= 0 and state[at + 36] == 0: state[at + 36] = clampi(s.enchantment_price(e), 0, 1000)
		state[at + 37] = int(float(ELCombatSearch.EACH[ctx.edition].get("LSDS", 0.0)) * 1000.0)
		# Its war banners, and what one costs to remove.
		var banner_price := int(s.profile.table("CombatSpells").get("WRBN", {}).get("Cost", 0))
		for e: Dictionary in hero.enchantments:
			if String(e.card) != "WRBN": continue
			if state[at + 39] == 0: banner_price = s.enchantment_price(e)
			state[at + 39] += 1
		state[at + 39] = mini(state[at + 39], 100) | (clampi(banner_price, 0, 1000) << 8)
		# How much of the attack tax stands on this hero.
		state[at + HERO_SCALARS + CHARMS.size() + HERO_KEYS.size()] = cards.count("LSDS")
		for forest: String in ["ANFR", "DRFR", "DNFR"]:
			if not cards.has(forest): continue
			state[at + 30] = int(float(ELCombatSearch.KIND[ctx.edition].get(forest, 0.0)) * 1000.0)
			break
		# The second game: the hero moving second opens its first turn with
		# one ether more; and only a hero's own vortex multiplies its ether,
		# where the first game counts every vortex in play.
		if ctx.second and int(hero.turns) == 0 and side != s.first_side() and not s.setup.get("combat_tutorial", false): state[at + 21] = 1
		state[at + 22] = s._enchantment_count(side, "MNVR") if ctx.second else s.global_enchantment_count("MNVR")
		# Second-game ether beyond the channels: an ether breeze on a creature
		# gives three each turn. (An orc shaman's one is told with the shaman.)
		# The ether disturbance: what each coming turn of this hero's takes
		# from its health as it begins, once the duel has run long.
		# And whether its Regeneration gives it a point back as that turn
		# begins (bit 20), once it has lived through the disturbance, and
		# whether its Concentration draws it a card more then (bit 21).
		for turn in INCOME_TURNS:
			var then := {"turns": int(hero.turns) + 1 + turn, "level": hero.level, "skills": hero.get("skills", {})}
			state[at + 56 + turn] = mini(ELHeroEffects.disturbance(s.profile.id, then, s.heroes[1 - side], 0), 100000) \
				| ((1 << 20) if ELHeroEffects.regenerates(then) else 0) | ((1 << 21) if ELHeroEffects.extra_draw(then) else 0)
		# The second game: each ether storm this hero cast on a creature
		# still in play is one more channel every turn.
		# The turns the disturbance has run as the first turn told begins
		# (ELHeroEffects.disturbance), so that the engine follows it past
		# the turns told; and whether the table of channels ends with them.
		state[at + 72] = (1 << 30) | clampi(int(hero.turns) - int(hero.level) - 10 - (int(hero.get("skills", {}).get("CNLG", -1)) + 1)
			+ (int(s.heroes[1 - side].get("skills", {}).get("CNLG", -1)) + 1) + 100000, 0, 0xfffff)
		state[at + 73] = 1 if s.setup.get("puzzle_fixed_channels", false) or int(hero.turns) + 1 + INCOME_TURNS >= income.size() else 0
		for turn in INCOME_TURNS:
			var number := int(hero.turns) + 1 + turn
			if not s.setup.get("puzzle_fixed_channels", false) and number < income.size(): state[at + 40 + turn] = int(income.get(str(number), {}).get("Level%d" % int(hero.level), 0))
		if not ctx.brain_cards: continue
		var typical := _typical_of(s.profile, String(hero.faction))
		var share := int(typical.share) if ELCombatSearch.smart_brain_typical else 0
		state[at + 8] = share
		if side != ctx.ai and not ELCombatSearch.smart_open_hand:
			# The other hand is unknown to the typical-creature guess of the
			# card-playing lookahead (`smart_brain_cards`). This hides nothing
			# from the engine's own readings (phases 5 and 9), which are told
			# both hands unless the information policy is "fair".
			state[at + 7] = hero.hand.size()
			state[at + 9] = maxi(0, mini(1000, hero.hand.size() * share) - share)
		var slot := HEADER + 2 * HERO_FIELDS + side * COSTS * TYPICAL_FIELDS
		for stats: Array in typical.stats:
			if int(stats[0]) + int(stats[1]) > 0:
				var worth := ctx.w[5] + float(stats[1]) * ctx.w[8] + float(stats[0]) * ctx.w[6]
				state[slot] = int(stats[0])
				state[slot + 1] = int(stats[1])
				state[slot + 2] = _card_worth(ctx, worth)
				state[slot + 3] = _card_worth(ctx, worth - 0.5)
			slot += TYPICAL_FIELDS
	var hand := HEADER + 2 * (HERO_FIELDS + COSTS * TYPICAL_FIELDS)
	for i in 2 * SLOTS: state[hand + i * CARD_FIELDS] = -1
	if mode >= 2 or (ctx.brain_cards and ELCombatSearch.smart_brain_own):
		# The computer's own cards, as far as the model has room. The engine's
		# readings (mode 2 and above) are told both hands whatever
		# `smart_open_hand` says - only the information policy "fair" puts
		# sampled cards in place of the other hand - and so is a rules check,
		# which plays named cards from them. Below mode 2 the other hand is
		# told only with `smart_open_hand` (a cheat).
		# What each hero will draw. Both draw from the one run of chance, each
		# at the start of its own turn, so the cards are told apart in the
		# order the turns come: reading six ahead for one hero alone names
		# cards it will never be dealt. A draw that fails keeps its place.
		var coming: Array = coming_cards
		for side in 2:
			if mode < 2 and side != ctx.ai and not ELCombatSearch.smart_open_hand: continue
			var holding: Array = []
			holding.append_array(holdings[side])
			# What this hero will draw next, in order: the engine plays with
			# both books open, so a line can count on the cards to come.
			if not coming.is_empty():
				while holding.size() < HAND: holding.append("")
				holding.append_array(coming[side])
			# A hero fought for without its spells casts no card of its book:
			# those it holds or will draw are told as cards it cannot play
			# (they still count as held), and only a card an effect gave it
			# during the duel is told by name (as ELCombatSearch._casts has it).
			var bookless := ctx.restricted and side == ctx.ai
			var from_book: Array = s.heroes[side].hand_slots
			for place in mini(holding.size(), SLOTS):
				var card: String = holding[place]
				if card.is_empty():
					# A draw that will fail - the book is spent - is told as
					# such (-2), so that the engine counts no card for it.
					if place >= HAND: state[hand + side * SLOTS * CARD_FIELDS + place * CARD_FIELDS] = -2
					continue
				if bookless and (place >= HAND or (place < from_book.size() and int(from_book[place]) >= 0)): continue
				var record: Variant = ctx.cards.get(card)
				if record == null:
					record = _card(ctx, s, card)
					ctx.cards[card] = record
				if record.is_empty(): continue
				var slot := hand + side * SLOTS * CARD_FIELDS + place * CARD_FIELDS
				state[slot] = s.cost(card)
				for i in record.size(): state[slot + 1 + i] = int(record[i])
				state[slot + 20] = kinds.find(card) + 1
				_card_extras(s, card, record, kinds, state, slot)
				# For the specialisations of the book: the card's place in its
				# hero's book (one more; none for a card that is not of it) and
				# the uses that place has left (one more; none for no end of them).
				var page := -1
				if place >= HAND: page = (s.heroes[side].deck as Array).find(card)
				elif place < from_book.size(): page = int(from_book[place])
				if page >= 0:
					var uses := int(s.heroes[side].spell_uses[page]) if page < s.heroes[side].spell_uses.size() else -1
					state[slot + 23] |= ((mini(page, 62) + 1) << 16) | ((0 if uses < 0 else mini(uses, 126) + 1) << 22)
	# Which creatures lend strength to which: a leader's death takes its aura
	# off the creatures it covered, and can kill one of them outright.
	var order: Array = s.creatures.values()
	var races: Dictionary = s.profile.table("CombatCreatures")
	var lends := {}
	for i in order.size():
		var leader: Dictionary = order[i]
		var aura := ELCatalog.creature_aura(s.profile, String(leader.card))
		if not aura.is_empty(): lends[i] = aura
	var at := FIXED
	var index := -1
	var worn_at := 0
	var banners := s.global_enchantment_count("WRBN")
	for c: Dictionary in order:
		index += 1
		var owner := int(c.owner)
		# A creature's own record does not change while it stands as it is under the
		# same hero enchantments.
		var key := [c.hash(), auras[owner]].hash()
		var unit: Variant = ctx.units.get(key)
		if unit == null:
			unit = _unit(ctx, s, c)
			unit.append(_bare(ctx, s, c, unit))
			unit.append(_bare(ctx, s, c, unit, BRIEF))
			unit.append(_passing(ctx, s, c, unit))
			unit.append(_worn(ctx, s, c, unit))
			ctx.units[key] = unit
		for row: Array in unit[11]:
			if worn_at >= worn_rows: break
			var slot := FIXED + s.creatures.size() * UNIT_FIELDS + worn_at * WORN_FIELDS
			state[slot] = index
			for i in row.size(): state[slot + 1 + i] = int(row[i])
			worn_at += 1
		var flags := int(unit[0])
		if s.attacks.has(int(c.id)): flags |= F_ATTACKING
		state[at] = int(c.id)
		state[at + 1] = owner
		state[at + 2] = int(c.power)
		state[at + 3] = int(c.toughness)
		state[at + 4] = flags
		state[at + 5] = int(unit[1])
		state[at + 6] = int(unit[2])
		state[at + 7] = int(unit[3])
		state[at + 8] = int(unit[4])
		state[at + 9] = int(unit[5])
		state[at + 10] = int(unit[6])
		state[at + 11] = int(s.blocks.get(int(c.id), -1))
		state[at + 12] = int(unit[7])
		state[at + 13] = int(c.get("damage", 0))
		var leaders := 0
		var kind := String(races.get(c.card, {}).get("Race", ""))
		for i: int in lends:
			var aura: Dictionary = lends[i]
			var leader: Dictionary = order[i]
			if String(aura.get("race", kind)) != kind or String(aura.get("card", c.card)) != String(c.card): continue
			if bool(aura.get("own", false)) and int(leader.owner) != owner: continue
			leaders |= 1 << i
			# Flags it has from such an aura alone go when the last leader does.
			for flag: String in aura.get("flags", []):
				if not c.flags.has(flag): state[at + 40] |= int(FLAGS.get(flag, 0))
		state[at + 14] = leaders
		var mine: Dictionary = lends.get(index, {})
		state[at + 15] = (int(mine.get("power", 0)) << 8) | (int(mine.get("toughness", 0)) & 0xff)
		for flag: String in mine.get("flags", []): state[at + 38] |= int(FLAGS.get(flag, 0))
		state[at + 39] = _reach(s.profile, mine)
		state[at + 41] = (1 if String(c.card) == "WRSP" else 0) | (4 if String(c.card) == LAMIA_WARLORD else 0) | (8 if String(c.card) == "GRSN" else 0)
		state[at + 42] = s._enchantment_count(int(c.id), "PALN")
		state[at + 16] = int(ELCatalog.PARASITES.get(c.card, 0))
		state[at + 17] = 1 if s.has_flag(int(c.id), "NoTarget") else 0
		# Breaking paralysis or immobility costs health as well as ether.
		state[at + 18] = 1 if not s.enfeebled(int(c.id)) else 0
		state[at + 19] = s.cost(String(c.card))
		state[at + 20] = s._enchantment_count(int(c.id), "TWEN")
		state[at + 21] = (1 if c.card == "WKHR" else 0) | ((2 if c.card == "BATT" else 0) | (4 if c.card == "GBAT" else 0) if ctx.second else 0) \
			| (8 if c.card in ENVENOMS else 0) | (16 if c.card == "BHMO" else 0) | (32 if s.race(int(c.id)) == "Beholder" else 0)
		state[at + 62] = s._enchantment_count(int(c.id), "ENBR")
		# Alpha strikes on it, and the health it would have without their cap.
		var alphas := s._enchantment_count(int(c.id), "ALST")
		if alphas > 0:
			var all_worn: Array = c.enchantments
			c.enchantments = all_worn.filter(func(e: Dictionary) -> bool: return String(e.card) != "ALST")
			var free := s.creature_stats(c)
			c.enchantments = all_worn
			state[at + 63] = mini(alphas, 127) | (maxi(0, free.y) << 8)
		state[at + 27] = s._enchantment_count(int(c.id), "OVRL")
		# When it was sent or set to block: the fight is played in that order.
		var sent: int = s.attacks.find(int(c.id))
		if sent >= 0: state[at + 37] = sent + 1
		elif s.blocks.has(int(c.id)): state[at + 37] = s.attacks.size() + s.blocks.keys().find(int(c.id)) + 1
		# What its enchantments have made of it, for a strike that strips them.
		var bare: Array = unit[8]
		for i in bare.size(): state[at + 28 + i] = int(bare[i])
		# And of that, what lasts only until a turn of the other hero's ends.
		var brief: Array = unit[9]
		state[at + 44] = int(brief[0])
		state[at + 45] = int(brief[1])
		state[at + 46] = int(brief[2])
		state[at + 47] = int(brief[3])
		state[at + 48] = int(brief[7])
		state[at + 49] = int(brief[8])
		state[at + 43] = (1 if s.pale(int(c.id)) else 0) | (2 if c.get("regenerated", false) else 0)
		# How far its power and health stand below the least they show.
		var under := _under(s, c)
		state[at + 59] = kinds.find(c.card) + 1
		state[at + 51] = under.x
		state[at + 52] = under.y
		# What it gave itself for the turn only.
		var passing: Array = unit[10]
		for i in passing.size(): state[at + 53 + i] = int(passing[i])
		# Cards its blow takes out of the hand of the hero it reaches.
		var robs := 0
		for flag: String in c.flags:
			if flag.begins_with("Discard("): robs += int(flag.trim_prefix("Discard(").trim_suffix(")"))
		var lent := 0
		for e: Dictionary in c.enchantments: lent += ELCatalog.granted_discard(s.profile, String(e.card))
		state[at + 50] = robs + lent
		state[at + 60] = lent
		# Flags it has only from an enchantment on its hero (or one it kept
		# from the army it left).
		for e: Dictionary in (s.army_auras(c) if c.has("auras") else s.heroes[owner].enchantments):
			if not String(e.card) in CHARMS: continue
			for flag: String in ELCatalog.ARMY_AURAS.get(e.card, {}).get("flags", []):
				if not c.flags.has(flag): state[at + 26] |= int(FLAGS.get(flag, 0))
		# And those it has from what lies on either hero for both armies, or
		# for the other one.
		if not c.flags.has("NoAffect"):
			for hero: Dictionary in s.heroes:
				for e: Dictionary in hero.enchantments:
					var over: Dictionary = ELCatalog.HERO_AURAS.get(e.card, {})
					if over.is_empty() or not String(e.card) in CHARMS or (over.scope == "enemy" and owner == int(e.owner)): continue
					for flag: String in over.flags:
						if not c.flags.has(flag): state[at + 26] |= int(FLAGS.get(flag, 0))
		# One that changed sides keeps the army enchantments it had then and
		# gains only those its new hero lays later: which copies, by place.
		if c.has("auras"):
			state[at + 66] = 1
			var kept := {}
			for id: Variant in c.auras: kept[int(id)] = true
			for side in 2:
				var places := {}
				for e: Dictionary in s.heroes[side].enchantments:
					var k := CHARMS.find(String(e.card)) - ARMY_FIRST
					if k < 0 or k >= ARMY_KINDS: continue
					var place: int = places.get(k, 0)
					places[k] = place + 1
					# The fourth kind's byte is the field's top one (and its sign).
					if place < 8 and kept.has(int(e.id)): state[at + 67 + side * 4 + (k >> 2)] |= 1 << (8 * (k & 3) + place)
		# What the creature can do of its own accord, unless an enchantment
		# has taken that away.
		var able := ability_of(s.profile, String(c.card))
		for i in 4: state[at + 22 + i] = int(able[i])
		if int(able[0]) == ABILITY_BROOD: state[at + 24] = kinds.find(String(ELCatalog.first_ability(s.profile, String(c.card)).get("summon", ""))) + 1
		# A mother bee's death sends its hero's bees into a frenzy (bit 4); a
		# bee in one now is berserk only until its hero's turn ends (bit 5).
		if String(c.card) == "MOBE": state[at + 25] |= 16
		for effect: Dictionary in c.get("temporary", []):
			if String(effect.get("kind", "")) == "frenzy" and not c.flags.has("Berserk"): state[at + 25] |= 32
		# An ability that may be used once a round, and has been.
		var done: Dictionary = c.get("ability_used", {})
		if done.get("rouse", false) or done.get("illusion", false): state[at + 61] = 1
		# What a pale creature may do, and has done this round.
		var shade := _pale_bits(s.profile, String(c.card))
		if shade != 0 and s.pale(int(c.id)):
			state[at + 64] = shade
			var own_key: String = PALE_KEYS[(shade >> 5) & 15]
			state[at + 65] = (1 if done.get("dissipate", false) else 0) | (2 if not own_key.is_empty() and done.get(own_key, false) else 0)
		# What the war banners give it just now, and how many pass it by.
		if banners > 0:
			var passed := 0
			for holder: Dictionary in s.heroes:
				for e: Dictionary in holder.enchantments:
					if String(e.card) == "WRBN" and e.get("exempt", []).has(int(c.id)): passed += 1
			state[at + 65] |= (clampi(s._kin(c) * (banners - passed), 0, 100) << 8) | (mini(passed, 100) << 16)
		if s._enchantment_count(int(c.id), "IRRT") + s._enchantment_count(int(c.id), "MDNS") + s._enchantment_count(int(c.id), "RDIS") > 0:
			# It comes back with the enchantment's going.
			state[at + 22] = 0
			state[at + 33] |= int(able[0]) << 16
		at += UNIT_FIELDS
	for side in 2:
		for e: Dictionary in s.heroes[side].enchantments:
			if String(e.card) != "WTLK" or not s.creatures.has(int(e.get("link", -1))) or worn_at >= worn_rows: continue
			var slot := FIXED + s.creatures.size() * UNIT_FIELDS + worn_at * WORN_FIELDS
			state[slot] = s.creatures.keys().find(int(e.link))
			state[slot + 1] = side
			state[slot + 2] = 15
			state[slot + 3] = _code(s.profile, "WTLK")
			state[slot + 4] = clampi(s.enchantment_price(e), 0, 1000)
			worn_at += 1
	at += worn_rows * WORN_FIELDS
	for command: Array in commands:
		for i in 4: state[at + i] = int(command[i])
		at += 4
	# What each enchantment a hero lays on itself is worth and lends its army.
	# One that stands tells its own price, and whether it is there for good.
	var stands := {}
	for side in 2:
		for e: Dictionary in s.heroes[side].enchantments:
			var kind := String(CHARM_TWINS.get(e.card, e.card))
			if e.get("fixed", false):
				if not stands.has(kind): stands[kind] = [clampi(s.enchantment_price(e), 0, 1000), 1]
			elif not stands.has(kind) or int(stands[kind][1]) == 1: stands[kind] = [clampi(s.enchantment_price(e), 0, 1000), 0]
	for k in CHARMS.size():
		var card: String = CHARMS[k]
		var slot := FIXED - SHAPES - ARTS - POOL * CARD_FIELDS - (CHARMS.size() - k) * CHARM_FIELDS
		var aura: Dictionary = ELCatalog.ARMY_AURAS.get(card, {})
		var gas: Array = GASES.get(card, [0, 0])
		var given := 0
		for flag: String in aura.get("flags", []): given |= int(FLAGS.get(flag, 0))
		# Whose creatures it reaches: its hero's, everyone's (1) or the other
		# hero's (2); and the ether it costs to remove, if anything removes it.
		var reach := 1 if GASES.has(card) else 0
		var beyond: Dictionary = ELCatalog.HERO_AURAS.get(card, {})
		if not beyond.is_empty():
			for flag: String in beyond.get("flags", []): given |= int(FLAGS.get(flag, 0))
			reach = 2 if String(beyond.get("scope", "")) == "enemy" else 1
		state[slot + 10] = reach
		state[slot + 11] = clampi(int(s.profile.table("CombatSpells").get(card, {}).get("Cost", 999)), 0, 1000)
		state[slot + 12] = 2 if card in ELDuel.TRAPS else (1 if ELCatalog.rule(s.profile, card).get("fixed", false) or not s.profile.table("CombatSpells").has(card) else 0)
		# A ripple leaves its enchantment for good.
		if card == "ORPL": state[slot + 12] = 1
		if MARK_PRICES.has(card):
			state[slot + 11] = int(MARK_PRICES[card][1 if ctx.second else 0])
			state[slot + 12] = 0
		if stands.has(card) and int(state[slot + 12]) != 2:
			state[slot + 11] = int(stands[card][0])
			state[slot + 12] = int(stands[card][1])
		state[slot + 13] = _code(s.profile, card)
		state[slot] = int(float(ELCombatSearch.EACH[ctx.edition].get(card, 0.0)) * 1000.0)
		state[slot + 1] = int(float(ELCombatSearch.KIND[ctx.edition].get(card, 0.0)) * 1000.0)
		state[slot + 2] = int(aura.get("power", 0)) + int(gas[0])
		state[slot + 3] = int(aura.get("toughness", 0)) + int(gas[1])
		state[slot + 4] = int(aura.get("lethal", 0))
		state[slot + 5] = int(aura.get("regeneration", 0))
		state[slot + 6] = given
		state[slot + 7] = 1 if card in CHARMS_ENDING else 0
		if k < HERO_KEYS.size():
			var gift: Dictionary = ELCatalog.HERO_ABILITIES.get(card, {}).duplicate()
			if ctx.second: gift.merge(ELCatalog.SECOND_HERO_ABILITIES.get(card, {}), true)
			state[slot + 8] = int(gift.get("cost", 0))
			state[slot + 9] = int(gift.get("amount", 0))
	# The creature cards by kind, each as it would be played from a hand.
	var pool := FIXED - SHAPES - ARTS - POOL * CARD_FIELDS
	for i in POOL: state[pool + i * CARD_FIELDS] = -1
	var shapes := _shapes(s, kinds)
	for i in kinds.size():
		var card: String = kinds[i]
		var record: Variant = ctx.cards.get(card)
		if record == null:
			record = _card(ctx, s, card)
			ctx.cards[card] = record
		# A creature's card, or an enchantment's that may come into a hand.
		if record.size() < 8 or (int(record[7]) != int(EFFECTS.summon) and s.profile.table("CombatCreatures").has(card)): continue
		var slot := pool + i * CARD_FIELDS
		state[slot] = s.cost(card)
		for k in record.size(): state[slot + 1 + k] = int(record[k])
		state[slot + 20] = i + 1
		_card_extras(s, card, record, kinds, state, slot)
		# What the battle's scripts make of a creature of the kind as it is summoned.
		if shapes.has(card):
			for whose in 2:
				var shaped: Array = shapes[card][whose]
				var packed := (int(shaped[0]) & 0xffff) | ((int(shaped[1]) & 0xffff) << 16)
				var spot := FIXED - SHAPES + (whose * POOL + i) * 3
				state[spot] = packed - 0x100000000 if packed >= 0x80000000 else packed
				state[spot + 1] = int(shaped[2])
				state[spot + 2] = int(shaped[3])
	# What the heroes carry; a hero fought for without its spells uses none.
	var arts := FIXED - SHAPES - ARTS
	state[arts] = int(s.turn_serial)
	state[arts + 1] = int(ctx.income * 1000.0)
	for side in 2:
		var base := arts + 2 + side * (2 + MAX_ART * ART_FIELDS)
		state[base] = s.artifact_limit(side)
		state[base + 1] = int(s.heroes[side].get("artifact_uses", 0))
		if mode < 2 or (ctx.restricted and side == ctx.ai): continue
		var carried: Array = s.heroes[side].get("artifacts", [])
		for k in mini(carried.size(), MAX_ART):
			var item: Dictionary = carried[k]
			var told := artifact_card(ctx, s, item)
			if told.is_empty(): continue
			var slot := base + 2 + k * ART_FIELDS
			var record: Array = told[0]
			for i in record.size(): state[slot + 1 + i] = int(record[i])
			state[slot + 20] = kinds.find(String(item.spell)) + 1
			_card_extras(s, String(item.spell), record, kinds, state, slot, told[1])
			state[slot + CARD_FIELDS] = clampi(int(item.get("charges", 0)), 0, 100)
			state[slot + CARD_FIELDS + 1] = clampi(int(item.get("ready_round", 0)), 0, 30000)
			state[slot + CARD_FIELDS + 2] = clampi(s._artifact_gap(item), 0, 100)
			state[slot + CARD_FIELDS + 3] = int(told[2])
			state[slot + CARD_FIELDS + 4] = int(told[3])
	# Told in every phase (header 31, bits 27-31): a puzzle's objective
	# follows everything else; no draw brings a card (a puzzle's fixed hands);
	# the cards to come are sampled; the position already holds more than the
	# model has room for, so that no proof may stand on it; and the order of
	# the graveyards matters to something that may be played.
	var graves_matter := _graves_matter(ctx, s, holdings, coming_cards)
	# What was left out, by name (`last_crowding`): a decision may not stand
	# on a model that dropped any of it (see ELCombatSearch._engine).
	var crowding: Array[String] = []
	if worn_needed > MAX_WORN: crowding.append("enchantments")
	if kinds_needed > POOL: crowding.append("kinds")
	if shapes.has(""): crowding.append("scripts")
	# Battle scripts that act at turns or after the duel's events (scripted
	# casts, cards, ether): the model has no such turns, so no proof may stand
	# on a line through them.
	if s.scripted_turns or (s.scripts != null and not s.scripts.search_only and s.scripts.acts_on_turns()): crowding.append("turns")
	# The first game's prepared battles may name an event that strikes a
	# creature down by chance as a turn begins: the model has no such turn.
	if String(s.setup.get("combat_event", "")) in ELDuel.EL1_TURN_EVENTS: crowding.append("event")
	for side in 2:
		if s.heroes[side].hand.size() > HAND: crowding.append("hand%d" % side)
		if s.heroes[side].get("artifacts", []).size() > MAX_ART: crowding.append("artifacts%d" % side)
		if graves_matter and s.heroes[side].grave.size() > GRAVES: crowding.append("grave%d" % side)
		# The enfeeblement a shadow wall's mastery lays, where there was no room to tell its card.
		if ctx.second and mode >= 2 and int(state[HEADER + side * HERO_FIELDS + 3]) == SPECS.find("BWIT") + 1 and not kinds.has("ENFL") and not crowding.has("kinds"):
			crowding.append("kinds")
	state[37] = kinds.find("ENFL") + 1
	# The cards three specialisations go by, ten bits a number: the blessing,
	# the lightning storm, the purification; and the mark the storm's mastery
	# leaves, with what it costs to remove.
	var named := func(card: String) -> int:
		var number := _code(s.profile, card)
		return number if number < 1024 else 0
	state[38] = int(named.call("BLSS")) | (int(named.call("LGST")) << 10) | (int(named.call("PRFY")) << 20)
	state[39] = int(named.call("RLSS")) | (clampi(s.enchantment_price({"card": "RLSS"}), 0, 1000) << 10)
	# Sampled cards in the other hand are no knowledge of what it can do,
	# and neither hero's coming cards are known: the engine is told whose
	# hand is hidden, which places of it the sampled cards take, and the
	# least ether a card of that book costs, and proves nothing past a move
	# that hero has the ether to make with a card nobody saw.
	if fair:
		state[1] |= _veil(s, 1 - knower)
		var hidden: Dictionary = s.heroes[1 - knower]
		for i in mini(hidden.hand.size(), HAND):
			if i >= hidden.hand_slots.size() or int(hidden.hand_slots[i]) >= 0: state[36] |= 1 << i
	var crowded := not crowding.is_empty()
	last_crowding = crowding
	var goal: Dictionary = s.setup.get("puzzle_goal", {})
	state[31] |= (1 << 27 if not goal.is_empty() else 0) | (1 << 28 if s.setup.get("puzzle_fixed_hands", false) == true else 0) \
		| (1 << 29 if fair else 0) | (1 << 30 if crowded else 0) | (1 << 31 if graves_matter else 0)
	if not goal.is_empty():
		var told := _goal_fields(s, goal)
		var base := state.size()
		state.resize(base + GOAL_FIELDS)
		for i in GOAL_FIELDS: state[base + i] = told[i]
	last_crowded = crowded
	# The longest the engine may think, in thousandths of a second (0: no
	# limit), and no later than the whole decision's deadline where the
	# caller set one (`deadline_usec`, a Time.get_ticks_usec() value): told
	# last, so that the packing itself is on the clock too. It is the time
	# left as the engine is called, and the engine keeps every reading of
	# the call within it. A lookahead's answer is remembered by the position
	# alone, whatever time was left when it was asked.
	state[28] = 0
	var bytes := state.to_byte_array()
	var position := 0
	if mode < 0:
		position = hash(bytes)
		var known: Variant = ctx.asked.get(position)
		if known != null:
			last_packed = bytes
			return known
	bytes.encode_s32(28 * 4, time_left(ctx, mode))
	last_packed = bytes
	if mode >= 0:
		return {"raw": (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", bytes) as PackedByteArray).to_int32_array()}
	var out: PackedInt32Array = (ClassDB.class_call_static(&"ELNativeDuelBrain", &"search", bytes) as PackedByteArray).to_int32_array()
	var result := {}
	if out.size() >= 5 and int(out[3]) > 0:
		var ids: Array[int] = []
		for i in int(out[4]): ids.append(int(out[5 + i]))
		var decided := int(out[0]) != 0
		result = {"status": int(out[0]), "value": 0.0 if decided else float(out[1]) * 0.001, "turns": int(out[1]) if decided else 0, "ids": ids}
	ctx.asked[position] = result
	ctx.fights += int(out[2]) if out.size() >= 5 else 0
	return result

## Whether the reading may go back on the blocks the position holds, at its
## first command (bit 4 of header 22): any reading of a position as it stands
## may; one begun from a position a command of the same decision led to may
## not (ELCombatSearch.Context.revise), or a block would be weighed there as
## one that can be taken back at once and never for what it does.
static func _revises(ctx: ELCombatSearch.Context) -> bool:
	var revise: Variant = ctx.get("revise")
	return revise == null or bool(revise)

## The thousandths of a second a reading of `mode` may take (0: no limit):
## a reading of the engine's own keeps to `smart_engine_ms`, and every reading
## of a decision - a proof, or the lookahead of the search written in the
## game's language (below mode 2) - to that decision's deadline. The rules
## check (modes 2 to 4) and the listings are never timed.
static func time_left(ctx: ELCombatSearch.Context, mode: int) -> int:
	var ms: int = ELCombatSearch.engine_ms() if mode == 5 or mode == 7 or mode == 8 else 0
	var deadline: Variant = ctx.get("deadline_usec")
	if (mode < 2 or (mode >= 5 and mode <= 9)) and deadline != null and int(deadline) > 0:
		var left := maxi(1, (int(deadline) - Time.get_ticks_usec()) / 1000)
		ms = left if ms <= 0 else mini(ms, left)
	return ms

## What of the hero `side`'s own means the model has no room for ("hand0",
## "artifacts1"; empty when it holds them all): a choice made without them is
## no choice among all the hero can do, so the engine is not asked for one.
static func own_crowding(s: ELDuel, side: int) -> String:
	if s.heroes[side].hand.size() > HAND: return "hand%d" % side
	if s.heroes[side].get("artifacts", []).size() > MAX_ART: return "artifacts%d" % side
	return ""

## Whether the engine's readings know only what that hero could know (the
## information policy "fair", `ELCombatSearch.smart_engine_info`): its own
## hand, the board and what has been seen. The rules check (modes 2-4) is
## always told everything.
static func fair_info(_ctx: ELCombatSearch.Context, s: ELDuel, mode: int) -> bool:
	if mode >= 2 and mode <= 4: return false
	return ELCombatSearch.info_policy(s) == "fair"

## `count` cards sampled out of a hero's own book (each place by its uses
## left), the same for the same turn and purpose, and drawn from no copy of
## the duel's chance. "" where the book has nothing to deal.
static func sampled(s: ELDuel, side: int, count: int, purpose: int) -> Array:
	var deck: Array = s.heroes[side].deck
	var out: Array = []
	for place: int in sampled_places(s, side, count, purpose): out.append(String(deck[place]) if place >= 0 else "")
	return out

## The places of a hero's book that `sampled` takes its cards from (-1 where
## the book has nothing to deal).
static func sampled_places(s: ELDuel, side: int, count: int, purpose: int) -> Array:
	var hero: Dictionary = s.heroes[side]
	var places: Array = []
	for place in hero.deck.size():
		var uses := int(hero.spell_uses[place]) if place < hero.spell_uses.size() else -1
		if uses != 0: places.append(place)
	var out: Array = []
	if places.is_empty() or s.setup.get("puzzle_fixed_hands", false) == true:
		# A book with nothing to deal, or one that deals nothing.
		for i in count: out.append(-1)
		return out
	var random := RandomNumberGenerator.new()
	random.seed = hash([int(s.turn_serial), side, purpose, s.profile.id])
	for i in count: out.append(places[random.randi() % places.size()])
	return out

## What the engine is told of a hand that holds cards the other hero cannot
## know (the first header word past its lowest bit): the hero (one more
## than its side, bits 1-2; the places of its hand those cards take are
## told in header 36), and the least ether a card of its book costs while it defends
## (bits 16-23) and while it attacks (bits 24-30) - nothing at all where a
## specialisation of its own might spare it the price.
static func _veil(s: ELDuel, side: int) -> int:
	var hero: Dictionary = s.heroes[side]
	var floors := [127, 255]
	var spells: Dictionary = s.profile.table("CombatSpells")
	for place in hero.deck.size():
		var uses := int(hero.spell_uses[place]) if place < hero.spell_uses.size() else -1
		if uses == 0: continue
		var card := String(hero.deck[place])
		var row: Dictionary = spells.get(card, {})
		# As printed or as it stands now, whichever is less; a lamia's price
		# falls with every warlord.
		var price := mini(int(row.get("Cost", 0)), s.cost(card))
		if String(s.profile.table("CombatCreatures").get(card, {}).get("Race", "")) == "Lamia": price = mini(price, 1)
		var use_in := String(row.get("UseIn", "Both"))
		var defends: bool = use_in in ["Defence", "Defense"]
		if not defends: floors[0] = mini(int(floors[0]), price)
		if defends or card in ELDuel.DEFENCE_SPELLS.get(s.profile.id, []): floors[1] = mini(int(floors[1]), price)
	if String(hero.get("spec", "NONE")) != "NONE" and s.setup.get("specs", true): floors = [0, 0]
	return ((side + 1) << 1) | (clampi(int(floors[1]), 0, 255) << 16) | (clampi(int(floors[0]), 0, 127) << 24)

## A hero's hand as the other hero could know it: the cards that came into
## it in the open (returned from the board or a graveyard, copied from an
## enchantment in play: those of no place in the book) by name, and a card
## sampled out of the book in place of each one it drew.
static func known_hand(s: ELDuel, side: int) -> Array:
	var hero: Dictionary = s.heroes[side]
	var guess := sampled(s, side, hero.hand.size(), 0)
	var out: Array = []
	for i in hero.hand.size():
		var open: bool = i < hero.hand_slots.size() and int(hero.hand_slots[i]) < 0
		out.append(String(hero.hand[i]) if open else String(guess[i]))
	return out


## Whether anything that may be played reads a graveyard card by card, so
## that losing the oldest of one changes what can be done.
static func _graves_matter(ctx: ELCombatSearch.Context, s: ELDuel, holdings: Array, coming: Array) -> bool:
	for side in 2:
		for e: Dictionary in s.heroes[side].enchantments:
			if String(e.card) in ["RPST", "RBRT", "SCBR"]: return true
		var cards: Array = holdings[side].duplicate()
		if coming.size() > side: cards.append_array(coming[side])
		for card: String in cards:
			if card.is_empty(): continue
			var effect := String(ELCatalog.rule(s.profile, card).get("effect", ""))
			if int(CHOICES.get(effect, 0)) in [1, 2, 6] or effect in ["revive", "grave_fire"]: return true
			if String(ability_key(s.profile, card)) in GRAVE_ABILITIES + ["plague"]: return true
	for c: Dictionary in s.creatures.values():
		if String(ability_key(s.profile, String(c.card))) in GRAVE_ABILITIES + ["plague"]: return true
		if _pale_bits(s.profile, String(c.card)) != 0: return true
	return false

## The objective of a puzzle being played, as the engine is told it (see
## ELPuzzles.Run.begin, which keeps it in the duel's setup): its kind, the
## side that must meet it, the turns allowed and the one under way, the other
## hero's turns to see through and those it has begun, the health it may not
## fall below, what must be left at the end, and the creatures to take and
## to keep, by their place among the creatures told.
static func _goal_fields(s: ELDuel, goal: Dictionary) -> Array:
	var out: Array = []
	out.resize(GOAL_FIELDS)
	out.fill(0)
	var side := int(goal.get("side", 0))
	var ids: Array = s.creatures.keys()
	out[0] = int({"win": 0, "clear": 1, "survive": 2, "control": 3}.get(String(goal.get("type", "win")), 0))
	out[1] = side
	out[2] = int(goal.get("allowed", 1))
	out[3] = int(goal.get("first", 0)) + int(s.heroes[side].turns) - int(goal.get("begun", 0))
	out[4] = int(goal.get("enemy_turns", 0 if String(goal.get("type", "win")) == "control" else 1))
	out[5] = int(goal.get("enemy_first", 0)) + int(s.heroes[1 - side].turns) - int(goal.get("enemy_begun", 0))
	out[6] = int(goal.get("min_health", 1))
	out[7] = int(goal.get("finish_health", 1))
	out[8] = int(goal.get("finish_mana", 0))
	out[9] = int(goal.get("min_allies", 0))
	var targets: Array = goal.get("targets", [])
	out[10] = mini(targets.size(), 4)
	for k in mini(targets.size(), 4): out[11 + k] = ids.find(int(targets[k]))
	var protect: Array = goal.get("protect", [])
	out[15] = mini(protect.size(), 4)
	for k in mini(protect.size(), 4): out[16 + k] = ids.find(int(protect[k]))
	return out

## Fills the shared tables a think reads, before one starts on another thread.
static func prepare(duel: ELDuel) -> void:
	for hero: Dictionary in duel.heroes: _typical_of(duel.profile, String(hero.faction))
	race_number(duel.profile, "")

## What is told of a card beside its record, which is the same wherever the
## card lies: what it costs as printed, and for a mother the place among the
## creature cards told by kind of the one its brood lays.
## What the battle's scripts make of each creature card's creature as it is
## summoned (the one hook of theirs a lookahead runs): {card: for hero 0's
## and for hero 1's, [points of power given, of health, plain flags given,
## plain flags taken]}. The model holds no more than that, taken where the
## position stands: a script that does anything else there (to a hero, to
## another creature, to what else the new one can do), or makes the second
## creature of a kind something other than the first, is under the key ""
## and the position is told crowded.
static func _shapes(s: ELDuel, kinds: Array) -> Dictionary:
	var out := {}
	if s.scripts == null: return out
	if not s.scripts.search_only:
		var hooked := false
		for layer: Dictionary in s.scripts.states:
			if (layer.hooks as Dictionary).has("CHook_OnLogicSummon"): hooked = true
		if not hooked: return out
	var beasts: Dictionary = s.profile.table("CombatCreatures")
	var words := {}
	for side in 2:
		# The same summons with the scripts and without, every kind twice.
		var plain := s.search_copy()
		if plain.scripts != null and plain.scripts.search_only: plain.scripts.close()
		plain.scripts = null
		var trial := s.search_copy()
		if trial.scripts == null: return out
		var odd := false
		for card: String in kinds:
			if not beasts.has(card): continue
			var first := trial.next_id
			for copy in 2:
				plain._summon(side, card)
				trial._summon(side, card)
			if not trial.creatures.has(first) or not trial.creatures.has(first + 1) or not plain.creatures.has(first) or trial.creatures.size() != plain.creatures.size():
				odd = true
				break
			var printed := [int(beasts[card].Power), int(beasts[card].Toughness)]
			var made: Array = trial.creatures[first].get("base", printed)
			var has: Array = trial.creatures[first].flags
			var had: Array = plain.creatures[first].flags
			if trial.creatures[first + 1].get("base", printed) != made or trial.creatures[first + 1].flags != has \
					or bool(trial.creatures[first].sick) != bool(plain.creatures[first].sick):
				odd = true
				break
			var power := int(made[0]) - int(printed[0])
			var health := int(made[1]) - int(printed[1])
			var given := 0
			var taken := 0
			for flag: String in has:
				if had.has(flag): continue
				if not FLAGS.has(flag) or flag == "NoAffect": odd = true
				else: given |= int(FLAGS[flag])
			for flag: String in had:
				if has.has(flag): continue
				if not FLAGS.has(flag) or flag == "NoAffect": odd = true
				else: taken |= int(FLAGS[flag])
			if odd or absi(power) > 1000 or absi(health) > 1000:
				odd = true
				break
			if not words.has(card): words[card] = [[0, 0, 0, 0], [0, 0, 0, 0]]
			words[card][side] = [power, health, given, taken]
		for hero in 2:
			for key: String in ["health", "mana", "channels"]:
				if int(trial.heroes[hero][key]) != int(plain.heroes[hero][key]): odd = true
		if trial.scripts != null and trial.scripts.search_only: trial.scripts.close()
		if odd: out[""] = 0
	for card: String in words:
		if words[card] != [[0, 0, 0, 0], [0, 0, 0, 0]]: out[card] = words[card]
	return out

static func _card_extras(s: ELDuel, card: String, record: Array, kinds: Array, state: PackedInt32Array, slot: int, given: Dictionary = {}) -> void:
	var rule := given if not given.is_empty() else ELCatalog.rule(s.profile, card)
	# A lamia is told at its cost before the warlords' cut, which the engine
	# counts as the card is cast; and a warlord is told as one.
	if String(s.profile.table("CombatCreatures").get(card, {}).get("Race", "")) == "Lamia":
		if state[slot] >= 0 and state[slot] == s.cost(card): state[slot] = _uncut_cost(s, card)
		state[slot + 19] |= 1 << 17
	if card == LAMIA_WARLORD: state[slot + 19] |= 1 << 18
	state[slot + 21] = int(s.profile.table("CombatSpells").get(card, {}).get("Cost", 0))
	# The ether channels it costs, and what it names beside its target.
	state[slot + 22] = mini(s.channel_cost(card), 15) | (int(CHOICES.get(String(rule.get("effect", "")), 0)) << 4)
	# The second game's cards that answer being taken out of a hand.
	if s.profile.id == "el2": state[slot + 22] |= (1 if card in ELCatalog.DISCARD_SUMMONS else (2 if card in ELCatalog.DISCARD_RETORTS else 0)) << 7
	# Its class, which the wardings and the spell traps go by; and for a
	# spell jammer, the trap that lets it out.
	state[slot + 22] |= int({"Creature": 1, "Sorcery": 2, "Enchantment": 3}.get(String(s.profile.table("CombatSpells").get(card, {}).get("Class", "")), 0)) << 9
	if card in JAMMERS: state[slot + 22] |= (JAMMERS.find(card) + 1) << 11
	# Laid on a creature: whether it is there for good, and whether it comes
	# back to its caster's hand as the creature leaves play.
	if rule.get("fixed", false) or (card == "ENFL" and s.profile.id == "el1"): state[slot + 22] |= 1 << 13
	state[slot + 22] |= _comes_back(s.profile, card) << 14
	if String(rule.get("effect", "")) == "enchant": state[slot + 22] |= int(SPECIALS.get(card, 0)) << 16
	# The only creatures it may be aimed at: walls, those that fly, those sent
	# to attack.
	state[slot + 22] |= ((1 if String(rule.get("race", "")) == "Wall" else 0) | (2 if rule.get("flying", false) else 0) | (4 if rule.get("attacking", false) else 0)) << 21
	state[slot + 23] = _code(s.profile, card)
	state[slot + 24] = _pale_bits(s.profile, card)
	if record.size() > 13 and int(record[7]) == int(EFFECTS.summon) and ((int(record[13]) >> 2) & 63) == ABILITY_BROOD:
		var laid := kinds.find(String(ELCatalog.first_ability(s.profile, card).get("summon", ""))) + 1
		state[slot + 14] = (int(record[13]) & ~(127 << 12)) | (laid << 12)

## What a card costs before the lamia warlords' cut (ELDuel.cost without it).
static func _uncut_cost(s: ELDuel, card: String) -> int:
	var base := int(s.profile.table("CombatSpells").get(card, {}).get("Cost", 999))
	if s.profile.id == "el2":
		var printed := base
		var kind := str(s.profile.table("CombatSpells").get(card, {}).get("Class", ""))
		for ward: String in ELCatalog.WARDINGS:
			if ELCatalog.WARDINGS[ward][0] == kind: base += s.global_enchantment_count(ward) * (printed if ELCatalog.WARDINGS[ward][1] else 2)
	return base

## A hero's specialisation as the engine is told it: its number (0 for none,
## for one that cannot work and for one no rule rolls for).
static func _spec_word(s: ELDuel, side: int) -> int:
	var hero: Dictionary = s.heroes[side]
	var code := String(hero.get("spec", "NONE"))
	if code == "NONE" or ELSpecs.expected(s, side, code) <= 0.0: return 0
	if code == "ARTF" and not s.setup.get("expert_artificer", true): return 0
	return SPECS.find(code) + 1

## A creature's race as the engine is told it: the race's number, and above
## it (bits 8-14) the specialisation that works for that race or that card.
static func _race_word(profile: ELProfile, race: String, card: String) -> int:
	return race_number(profile, race) | ((SPECS.find(String(CARD_MASTERY.get(card, RACE_MASTERY.get(race, "")))) + 1) << 8)

## A number for every card an enchantment may be of, the same all through a
## run.
static func _code(profile: ELProfile, card: String) -> int:
	if not _codes.has(profile.id):
		var table := {}
		for name: String in profile.table("CombatSpells").keys(): table[name] = table.size() + 1
		_codes[profile.id] = table
	var known: Dictionary = _codes[profile.id]
	if not known.has(card): known[card] = known.size() + 1
	return int(known[card])

## What a pale creature of the second game may do: bits 0-3 what brings it
## out of the plane, bit 4 it may give itself up for a card, bits 5-8 what
## it does of its own, 9-12 the ether that costs, 13-14 what it measures its
## prey by.
static func _pale_bits(profile: ELProfile, card: String) -> int:
	if profile.id != "el2": return 0
	var row: Dictionary = profile.table("CombatCreatures").get(card, {})
	if row.is_empty() or not ELCatalog.flags(row).has("Outerplanar"): return 0
	var race := str(row.get("Race", ""))
	var bits := maxi(0, PALE_KEYS.find(String(ELCatalog.PALE_RACE_ABILITIES.get(race, {}).get("key", "-"))))
	if race == "OutSpellJammer": bits |= 16
	var own: Dictionary = ELCatalog.PALE_ABILITIES.get(card, {})
	if not own.is_empty():
		bits |= maxi(0, PALE_KEYS.find(String(own.key))) << 5
		bits |= clampi(int(own.get("cost", 0)), 0, 15) << 9
		bits |= int({"power": 1, "toughness": 2, "both": 3}.get(String(own.get("measure", "")), 0)) << 13
	return bits

## The enchantment cards that may come into a hand in the middle of a line:
## those that go back to their caster's hand as their creature leaves play
## (worn now, or held and still to be laid), and, where a pale creature that
## copies or takes enchantments is in play or in a hand, every enchantment in
## play that has a caster. The engine is told them by kind after the
## creatures' cards.
static func _returning(s: ELDuel, holdings: Array, coming: Array) -> Array:
	var found: Array = []
	var spells: Dictionary = s.profile.table("CombatSpells")
	var named: Array = []
	for c: Dictionary in s.creatures.values():
		named.append(String(c.card))
		for e: Dictionary in c.enchantments:
			if _comes_back(s.profile, String(e.card)) != 0 and not found.has(String(e.card)): found.append(String(e.card))
	for side in 2:
		var cards: Array = []
		cards.append_array(holdings[side])
		if not coming.is_empty(): cards.append_array(coming[side])
		for card: String in cards:
			if card.is_empty(): continue
			named.append(card)
			if _comes_back(s.profile, card) != 0 and not found.has(card): found.append(card)
	var copies := false
	if s.profile.id == "el2":
		for card: String in named:
			if String(ELCatalog.PALE_ABILITIES.get(card, {}).get("key", "")) in ["weave", "transpose"]: copies = true
	if copies:
		for holder: int in [0, 1] + s.creatures.keys():
			for e: Dictionary in s.entity(holder).enchantments:
				var card := String(e.card)
				if e.get("fixed", false) or found.has(card): continue
				if String(ELCatalog.rule(s.profile, card).get("effect", "")) == "enchant": found.append(card)
	# The first game's eternal enchantment gives its hero back the card of an
	# enchantment of its own that is dispelled.
	if s.profile.id == "el1":
		for side in 2:
			if String(s.heroes[side].get("spec", "NONE")) != "ETEN": continue
			for holder: int in [0, 1] + s.creatures.keys():
				for e: Dictionary in s.entity(holder).enchantments:
					if int(e.get("owner", -1)) == side and not e.get("fixed", false) and not found.has(String(e.card)): found.append(String(e.card))
			var cards: Array = []
			cards.append_array(holdings[side])
			if not coming.is_empty(): cards.append_array(coming[side])
			for card: String in cards:
				if not card.is_empty() and String(spells.get(card, {}).get("Class", "")) == "Enchantment" and not found.has(card): found.append(card)
	# The second game's shadow walls enfeeble what they strike, by their hero's mastery.
	if s.profile.id == "el2":
		for side in 2:
			if String(s.heroes[side].get("spec", "NONE")) == "BWIT" and not found.has("ENFL"): found.append("ENFL")
	return found.filter(func(card: String) -> bool: return spells.has(card) and not s.profile.table("CombatCreatures").has(card))

## Whether an enchantment's card goes back to its caster's hand as its
## creature leaves play (1), or only as it dies or is exiled (2).
static func _comes_back(profile: ELProfile, card: String) -> int:
	if card == "RIOT" or (profile.id == "el2" and card in ["DELS", "PRBN", "ALNS"]): return 1
	return 2 if card == "QKFX" else 0

## Whether nothing but earth bonds on a creature of its race keeps `c` down.
static func _bound_only(s: ELDuel, c: Dictionary) -> bool:
	var id := int(c.id)
	if c.flags.has("NoUntap") or s.enfeebled(id) or s._enchantment_count(id, "IMMB") > 0: return false
	if c.get("granted", []).count("NoUntap") != 1 or c.flags.has("NoAffect"): return false
	for holder: Dictionary in s.creatures.values():
		if s._enchantment_count(int(holder.id), "ERBN") > 0 and s.race(int(holder.id)) == s.race(id): return true
	return false

static func _plane_sensitive(ctx: ELCombatSearch.Context, s: ELDuel, mode: int) -> bool:
	var exchange_target := false
	for c: Dictionary in s.creatures.values():
		if c.enchantments.is_empty() or not c.enchantments.any(func(e: Dictionary) -> bool: return s.coloured_enchantment(e.card)): continue
		var id := int(c.id)
		if s.in_plane(id) or s.pale(id): return true
		exchange_target = exchange_target or (s.targetable(id) and s.can_change_aspect(id, true))
	if not exchange_target or not s.creatures.keys().any(func(id: int) -> bool: return s.in_plane(id) and not s.has_flag(id, "NoTarget")):
		return false
	# Dissipate names Pale creatures only. A regular creature can be sent to
	# the plane by Transfer Aspects when there's another to bring back.
	var side := s.active_side()
	for e: Dictionary in s.heroes[side].enchantments:
		if e.card == "OEXC" and s.can_use_ability(side, "recycle:%d" % int(e.id)): return true
	# Keep a hidden enemy hand out of the decision to fall back.
	var knower := ctx.viewer if ctx.viewer >= 0 else ctx.ai
	if fair_info(ctx, s, mode) and side != knower: return false
	if s.available_mana(side) < s.cost("OEXC") + int(ELCatalog.HERO_ABILITIES.OEXC.cost): return false
	var hand: Array = s.heroes[side].hand
	for i in hand.size():
		if hand[i] == "OEXC" and s.can_cast_from_hand(i): return true
	return false

## How the engine names an enchantment on `holder` (a hero, or a creature's
## id): the kind of a hero's, the attack tax and a forest coming after the
## kinds; the number of the card of a creature's. -1 for one it has no name for.
static func enchantment_name(s: ELDuel, holder: int, e: Dictionary) -> int:
	var card := String(e.card)
	if holder >= 2: return _code(s.profile, card)
	if card == "LSDS": return CHARMS.size()
	if s.forest_limit(card) >= 0: return CHARMS.size() + 1
	if card == "WTLK": return CHARMS.size() + 2
	if card == "WRBN": return CHARMS.size() + 3
	return CHARMS.find(String(CHARM_TWINS.get(card, card)))

## The enchantment on `holder` that the engine names `what`: the first that
## can be dispelled, or the first there is (`mode` 1), or the first that has
## a caster (2); with `caster`, only what that hero laid. -1 when there is none.
## Of a hero's copies alike, one whose ability is unused this turn goes first:
## the engine counts a hero's copies and their uses apart, and takes a copy
## away with the uses kept as long as copies are left for them.
static func enchantment_named(s: ELDuel, holder: int, what: int, mode := 0, caster := -1) -> int:
	var found := -1
	for e: Dictionary in s.entity(holder).get("enchantments", []):
		if enchantment_name(s, holder, e) != what or (caster >= 0 and int(e.get("owner", -1)) != caster): continue
		# What may be dispelled; whatever is there; or what has a caster.
		if mode == 1 or (mode == 2 and not e.get("fixed", false)) or (mode == 0 and s.dispellable(holder, e)):
			if holder >= 2 or not e.get("used", false): return int(e.id)
			if found < 0: found = int(e.id)
	return found

## The enchantments on a creature, each by itself and in the order they were
## laid: [who laid it, what kind it is, its card's number, what removing it
## costs, the power, the health and the points past the floor it gives, its
## flags, what it adds to the creature's worth ready and resting, how it
## behaves, and what the creature pays to regenerate without it (plus one)].
static func _worn(ctx: ELCombatSearch.Context, s: ELDuel, c: Dictionary, unit: Array) -> Array:
	var rows: Array = []
	var worn: Array = c.enchantments
	if worn.is_empty(): return rows
	var id := int(c.id)
	var power := int(c.power)
	var toughness := int(c.toughness)
	var granted: Variant = c.get("granted")
	var under := _under(s, c)
	var shielded := s.has_flag(id, "NoTarget")
	var holds: Dictionary = HOLDS_SECOND if ctx.second else HOLDS
	var gave := {}
	for e: Dictionary in worn:
		var card := String(e.card)
		if not gave.has(card):
			# The creature is looked at once without one copy and put back.
			var kept := worn.duplicate()
			kept.remove_at(worn.find(e))
			c.enchantments = kept
			s._refresh_stats(c)
			var without := _unit(ctx, s, c)
			gave[card] = [(power - under.x) - (int(c.power) - _under(s, c).x), toughness - int(c.toughness), int(unit[0]) & ~int(without[0]),
				int(unit[4]) - int(without[4]), int(unit[5]) - int(without[5]),
				(maxi(0, int(without[1])) + 1) if int(without[1]) != int(unit[1]) else 0,
				1 if shielded and not s.has_flag(id, "NoTarget") else 0]
			c.enchantments = worn
			c.power = power
			c.toughness = toughness
			if granted == null: c.erase("granted")
			else: c.granted = granted
		var given: Array = gave[card]
		var kind := int(WORN_KINDS.get(card, 0))
		if holds.has(card): kind = 1
		elif card in ELCatalog.CONTROL: kind = 8
		var caster := int(e.get("owner", c.owner))
		if caster < 0 or caster > 1: caster = int(c.owner)
		rows.append([caster, kind, _code(s.profile, card), clampi(s.enchantment_price(e), 0, 1000), int(given[0]), int(given[1]), 0, int(given[2]), int(given[3]), int(given[4]),
			(1 if card in BRIEF else 0) | (_comes_back(s.profile, card) << 1) | (mini(ELCatalog.granted_discard(s.profile, card), 7) << 3)
			| ((1 if e.get("fixed", false) else 0) << 6) | (int(given[6]) << 7) | ((1 if card in MUTING else 0) << 8) | (int(TICKS.get(card, 0)) << 9) | ((1 if card == "WTLK" else 0) << 11), int(given[5])])
	return rows

## A card's worth once summoned, in thousandths: a creature still to be played
## counts for less than one in play, and its card leaves the hand.
static func _card_worth(ctx: ELCombatSearch.Context, worth: float) -> int:
	return int((worth - ctx.w[4]) * ELCombatSearch.smart_brain_discount * 1000.0)

## The cards each hero will draw at the start of its next turns, soonest
## first: `[[side 0's], [side 1's]]`, an empty name where a draw fails.
static func foreseen(s: ELDuel) -> Array:
	var coming: Array = [[], []]
	var ahead := s.search_copy()
	var who := 1 - int(s.attacker)
	# Every enlightenment in play is one card more at the start of each turn,
	# and a hero's Concentration one more on the turns it works.
	var each := 1 + s.global_enchantment_count("ENLH")
	var turn := [0, 0]
	for i in 2 * DRAWS:
		var hero: Dictionary = s.heroes[who]
		turn[who] += 1
		var more := 1 if ELHeroEffects.extra_draw({"turns": int(hero.turns) + int(turn[who]), "skills": hero.get("skills", {})}) else 0
		for copy in each + more:
			var before: int = ahead.heroes[who].hand.size()
			var drew: bool = ahead._draw(who) and ahead.heroes[who].hand.size() > before
			coming[who].append(String(ahead.heroes[who].hand.back()) if drew else "")
		who = 1 - who
	for side in 2: coming[side] = coming[side].slice(0, DRAWS)
	if ahead.scripts != null and ahead.scripts.search_only: ahead.scripts.close()
	return coming

## A number for each race of the game's creatures, the same for a whole
## duel and no two alike: the engine tells races apart by it.
static func race_number(profile: ELProfile, race: String) -> int:
	if not _races.has(profile.id):
		var names := {}
		for row: Dictionary in profile.table("CombatCreatures").values(): names[str(row.get("Race", ""))] = true
		var sorted := names.keys()
		sorted.sort()
		var numbers := {}
		for i in sorted.size(): numbers[sorted[i]] = mini(i + 1, 127)
		_races[profile.id] = numbers
	return int(_races[profile.id].get(race, 0))

## Whom a leader's aura reaches, as the engine is told it: one more than the
## number of the race, or 200 for the one card an aura may name; and 256 more
## when it stays in its own army. 0 for no aura.
static func _reach(profile: ELProfile, aura: Dictionary) -> int:
	if aura.is_empty(): return 0
	return (race_number(profile, String(aura.race)) + 1 if aura.has("race") else 200) | (256 if aura.get("own", false) else 0)

## Whether an ability command is one the engine plays itself.
static func plays_ability(s: ELDuel, command: Dictionary, ctx: ELCombatSearch.Context = null) -> bool:
	var id := int(command.get("id", -1))
	var key := String(command.get("key", ""))
	if id >= 0 and id < 2 and key.begins_with("artifact:"):
		# A thing the hero carries, where the engine has a rule for its spell.
		var carried: Array = s.heroes[id].get("artifacts", [])
		var which := int(key.get_slice(":", 1))
		if ctx == null or which < 0 or which >= mini(carried.size(), MAX_ART) or (ctx.restricted and id == ctx.ai): return false
		return not artifact_card(ctx, s, carried[which]).is_empty()
	if id >= 0 and id < 2: return HERO_KEYS.has(key.get_slice(":", 0)) and CHARMS.has(String(_ability_card(s, id, key)))
	if not s.creatures.has(id): return false
	if s.profile.id == "el2" and PALE_KEYS.has(key) and s.pale(id): return true
	return key in ["wake", "awaken", "unparalyze"] or key == ability_key(s.profile, String(s.creatures[id].card))

## A thing a hero carries into the duel, as the engine plays it: [the record
## of the card it stands for, the rule that card goes by, how it is used
## (bit 0 while attacking, bit 1 while defending, then 1 for one that simply
## does what it does and 2 for one that casts its spell), and what it deals
## the rest of the side it hurts]. Empty for one the engine has no rule for.
static func artifact_card(ctx: ELCombatSearch.Context, s: ELDuel, item: Dictionary) -> Array:
	var spell := String(item.get("spell", ""))
	var row: Dictionary = s.profile.table("CombatSpells").get(spell, {})
	if row.is_empty(): return []
	var use_in := String(row.get("UseIn", "Both"))
	var phases := 1 if use_in == "Attack" else (2 if use_in in ["Defence", "Defense"] else 3)
	var rule := {}
	var free := 1
	if item.has("custom"):
		# One made to order casts its spell, and only while its hero attacks.
		rule = ELCatalog.rule(s.profile, spell)
		if rule.is_empty() or rule.get("variable", false) or rule.get("splash_side", 0) > 0: return []
		phases &= 1
		free = 2
	else:
		if not ELCatalog.ARTIFACT_EFFECTS.has(spell): return []
		rule = (ELCatalog.ARTIFACT_EFFECTS[spell] as Dictionary).duplicate()
		match String(rule.get("phase", "attack")):
			"defence": phases &= 2
			"attack": phases &= 1
		# A creature out of its hero's own graveyard, and nothing laid on it.
		if String(rule.get("effect", "")) == "reanimate":
			rule.plain = true
			rule.own = true
	if phases == 0: return []
	var record := _card(ctx, s, spell, rule)
	if record.is_empty(): return []
	return [record, rule, phases | (free << 2), 1 if spell == "RDCL" and free == 1 else 0]

## The enchantment card behind a hero's ability.
static func _ability_card(s: ELDuel, side: int, key: String) -> String:
	var wanted := int(key.get_slice(":", 1))
	for e: Dictionary in s.heroes[side].enchantments:
		if int(e.id) == wanted: return String(e.card)
	return ""

## The name the rules give the ability of `card` that the engine plays, or
## an empty one.
static func ability_key(profile: ELProfile, card: String) -> String:
	if FINGI.has(card): return "spores"
	if card == "RFPT": return "disenchant"
	if card == "WLIL": return "illusion"
	var key := String(ELCatalog.first_ability(profile, card).get("key", ""))
	return key if ABILITIES.has(key) else ""

## [ability, its cost, its amount (or the race number it counts), how it is
## used] of a creature card, all zero for one with nothing the engine plays.
static func ability_of(profile: ELProfile, card: String) -> Array:
	if FINGI.has(card): return [int(FINGI[card]), 0, 0, 0]
	# The reinforced pteros takes any enchantment off, and rests for it.
	if card == "RFPT": return [int(ABILITIES.disenchant), 0, 0, 1]
	# The wall of illusion takes its health from its hero's graveyard, for an ether.
	if card == "WLIL": return [int(ABILITIES.illusion), 1, 0, 0]
	var rule := ELCatalog.first_ability(profile, card)
	var kind := int(ABILITIES.get(String(rule.get("key", "")), 0))
	# The second game's orc shaman gives its hero an ether each turn (bit 3).
	if kind == 0: return [0, 0, 0, 8 if card == "ORSH" and profile.id == "el2" else 0]
	var amount := int(rule.get("amount", 1))
	match String(rule.key):
		"gaze":
			if String(rule.get("measure", "")) == "power": kind += 1
			amount = race_number(profile, "Beholder")
		"breath":
			if String(rule.get("scope", "")) == "ground": kind += 1
		"bat_drain": amount = race_number(profile, "Bat")
		"rally": amount = race_number(profile, "Kobold")
		"recall_lamia": amount = race_number(profile, "Lamia")
		"recall_rat": amount = race_number(profile, "Rat")
		# The dearest creature it may raise.
		"necromancy": amount = int(rule.get("maximum", 0))
		# Which card its brood lays is told with the position.
		"brood": amount = 0
	# Bit 0: it must be ready and rests for it; bit 1: only while its hero
	# attacks; bit 2: only while it rests.
	var traits := (1 if rule.get("ready", true) else 0) | (2 if String(rule.get("phase", "")) == "attack" else 0) | (4 if rule.get("tapped", false) else 0)
	if card == "ORSH" and profile.id == "el2": traits |= 8
	return [kind, maxi(0, int(rule.get("cost", 0))), clampi(amount, 0, 127), traits]

## [flags, regeneration cost, stone skins, lifeguards, worth ready, worth
## resting (thousandths), race number, wake cost] of one creature.
static func _unit(ctx: ELCombatSearch.Context, s: ELDuel, c: Dictionary) -> Array:
	var id := int(c.id)
	var flags := 0
	for flag: String in c.flags + c.get("granted", []):
		flags |= int(FLAGS.get(flag, 0))
	var race := s.race(id)
	if race == "Wall": flags |= F_WALL
	if c.card in ELCatalog.WALL_BLOCKED: flags |= F_ELUSIVE
	if c.card in ELCatalog.MECHOS: flags |= F_DESTROY_UNWALLED
	if c.card in ELCatalog.STINGERS: flags |= F_STINGER
	if s.cannot_rise(id): flags |= F_NO_UNTAP
	# Earth bonds hold a whole race down for as long as they last: the engine
	# reckons with them itself, and is told only what else holds a creature.
	if flags & F_NO_UNTAP and _bound_only(s, c): flags &= ~F_NO_UNTAP
	if c.card == BURNS: flags |= F_BURN
	if c.card == VENOMOUS: flags |= F_VENOM
	if c.card == WHIRLS: flags |= F_DESTROY_FLYER
	if c.card in ELCatalog.FATALISTS: flags |= F_FATALIST
	if c.get("hit", false): flags |= F_HIT
	if ctx.second and s.pale(id) and not s.in_plane(id) and int(c.toughness) > 0: flags |= F_DISSIPATES
	if c.resting: flags |= F_RESTING
	if c.sick: flags |= F_SICK
	if s.in_plane(id): flags |= F_PLANE
	# What frees it from what holds it down: enfeeblement, or else a
	# paralysis or immobility laid on it.
	var wake := WAKE_COST if s.enfeebled(id) else 0
	if wake == 0:
		for held: String in ["WNPZ", "IMMB"]:
			if s._enchantment_count(id, held) > 0:
				wake = int((HOLDS_SECOND if ctx.second else HOLDS)[held])
				break
	# The search's own worth of the creature, ready and resting.
	var probe := c.duplicate()
	probe.resting = false
	probe.sick = false
	var ready_worth := ELCombatSearch.creature_value(ctx, s, probe)
	probe.resting = true
	var resting_worth := ELCombatSearch.creature_value(ctx, s, probe)
	return [flags, s.regeneration_cost(id), s._enchantment_count(id, "STSK"), s._enchantment_count(id, "LFGR"),
		int(ready_worth * 1000.0), int(resting_worth * 1000.0), _race_word(s.profile, race, String(c.card)), wake]

## What the enchantments on a creature have made of it, by `unit` (its own
## record): [how many they are, the power and the health they gave, the flags,
## its regeneration cost without them, what becomes of it without them, the
## army it then goes back to (plus one), the worth they gave it ready and
## resting]. The creature is looked at once without them and put back as it was.
## How far a creature's power and health stand below the least they may
## show (nothing, and one): what is added to them later counts from there.
static func _under(s: ELDuel, c: Dictionary) -> Vector2i:
	if int(c.power) > 0 and int(c.toughness) > 1: return Vector2i.ZERO
	# One whose power and health have changed places has no such floor to read.
	if c.enchantments.filter(func(e: Dictionary) -> bool: return String(e.card) == "DELS").size() % 2 == 1: return Vector2i.ZERO
	var held: Variant = c.get("temporary")
	var probe: Array = [] if held == null else (held as Array).duplicate()
	probe.append({"power": 100, "toughness": 100})
	c.temporary = probe
	var raised := s.creature_stats(c)
	if held == null: c.erase("temporary")
	else: c.temporary = held
	var under := Vector2i(int(c.power) - (raised.x - 100), int(c.toughness) - (raised.y - 100))
	# Health held at one by a card that caps it reads as nonsense here.
	if under.x < 0 or under.x > 50: under.x = 0
	if under.y < 0 or under.y > 50: under.y = 0
	return under

## What a creature has only until a turn that is not its hero's ends: [how
## many such things, the power, health and flags they give, and what they add
## to its worth ready and resting].
static func _passing(ctx: ELCombatSearch.Context, s: ELDuel, c: Dictionary, unit: Array) -> Array:
	var held: Variant = c.get("temporary")
	if held == null: return [0, 0, 0, 0, 0, 0]
	var going: Array = (held as Array).filter(func(e: Dictionary) -> bool:
		return String(e.get("kind", "")) == "bless" or (not e.has("until_turn_of") and not e.has("keeper")))
	if going.is_empty(): return [0, 0, 0, 0, 0, 0]
	var power := int(c.power)
	var toughness := int(c.toughness)
	var granted: Variant = c.get("granted")
	var under := _under(s, c)
	var rest: Array = (held as Array).filter(func(e: Dictionary) -> bool: return not going.has(e))
	if rest.is_empty(): c.erase("temporary")
	else: c.temporary = rest
	s._refresh_stats(c)
	var without := _unit(ctx, s, c)
	var below := _under(s, c)
	var record := [going.size(), (power - under.x) - (int(c.power) - below.x), (toughness - under.y) - (int(c.toughness) - below.y),
		int(unit[0]) & ~int(without[0]), int(unit[4]) - int(without[4]), int(unit[5]) - int(without[5])]
	c.temporary = held
	c.power = power
	c.toughness = toughness
	if granted == null: c.erase("granted")
	else: c.granted = granted
	return record

static func _bare(ctx: ELCombatSearch.Context, s: ELDuel, c: Dictionary, unit: Array, only: Array = []) -> Array:
	var worn: Array = c.enchantments
	# With `only`, just the enchantments of those cards are taken off.
	var kept: Array = [] if only.is_empty() else worn.filter(func(e: Dictionary) -> bool: return not String(e.card) in only)
	if worn.size() == kept.size(): return [0, 0, 0, 0, 0, 0, 0, 0, 0]
	var id := int(c.id)
	var power := int(c.power)
	var toughness := int(c.toughness)
	var granted: Variant = c.get("granted")
	var under := _under(s, c)
	c.enchantments = kept
	s._refresh_stats(c)
	var without := _unit(ctx, s, c)
	var record := [worn.size() - kept.size(), (power - under.x) - (int(c.power) - _under(s, c).x), toughness - int(c.toughness), int(unit[0]) & ~int(without[0]), int(without[1]),
		(16 if s.has_flag(id, "NoTarget") else 0) | (int(without[7]) << 8), 0,
		int(unit[4]) - int(without[4]), int(unit[5]) - int(without[5])]
	c.enchantments = worn
	c.power = power
	c.toughness = toughness
	if granted == null: c.erase("granted")
	else: c.granted = granted
	if not only.is_empty(): return record
	for e: Dictionary in worn:
		match String(e.card):
			"ALST": record[5] = int(record[5]) | 1
			"QKFX": record[5] = int(record[5]) | 2
	if c.has("origin"):
		record[6] = int(c.origin) + 1
		# The second game's creatures that need no rest, and its men, come back ready.
		if ctx.second and (c.flags.has("NSS") or String(c.card) in ["RZMN", "CTMN", "SWMN"]): record[5] = int(record[5]) | 8
	return record

## [power, toughness, flags, regeneration cost, worth ready, worth resting,
## race number, effect, scope, amount, X] of a card in hand. Empty for a card
## whose effect the model cannot play, which it then never plays.
static func _card(ctx: ELCombatSearch.Context, s: ELDuel, card: String, ruled: Dictionary = {}) -> Array:
	var rule := ruled if not ruled.is_empty() else ELCatalog.rule(s.profile, card)
	# The compiled model has a splash slot for carried artifacts only.
	if ruled.is_empty() and rule.get("splash_side", 0) > 0: return []
	var effect := int(EFFECTS.get(String(rule.get("effect", "")), 0))
	if effect == 0: return []
	# Enchantments a hero lays on itself that change who may attack: the
	# attack tax, worth what each copy is; and a forest, worth what its kind is.
	if effect == EFFECTS.enchant and String(rule.get("target", "")) == "none" and rule.get("self", false):
		if card == "WRBN": return [0, 0, 0, 0, 0, 0, 0, EFFECT_BANNER, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		if card == "LSDS":
			return [0, 0, 0, 0, int(float(ELCombatSearch.EACH[ctx.edition].get(card, 0.0)) * 1000.0), 0, 0, EFFECT_TAX, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		if s.forest_limit(card) >= 0:
			return [0, 0, 0, 0, int(float(ELCombatSearch.KIND[ctx.edition].get(card, 0.0)) * 1000.0), 0, 0, EFFECT_FOREST, 0, s.forest_limit(card), 0, 0, 0, 0, 0, 0, 0]
		var charm := String(CHARM_TWINS.get(card, card))
		if charm in CHARMS:
			return [0, 0, 0, 0, 0, 0, 0, EFFECT_CHARM, 0, CHARMS.find(charm), 0, 0, 0, 0, 0, 0, 2 if card in ELDuel.DEFENCE_SPELLS.get(s.profile.id, []) else 0]
	# Those laid on the other hero (1), and on a hero that is named or on a
	# hero or a creature alike (2): these the engine offers on its own side
	# only, out of habit (bit 2) and not by the rules - a list of every
	# command the rules allow holds the other side's hero and creatures too.
	if effect == EFFECTS.enchant and card in CHARMS:
		var where := String(rule.get("target", ""))
		var tells := 2 if card in ELDuel.DEFENCE_SPELLS.get(s.profile.id, []) else 0
		if where == "none" and rule.get("opponent", false):
			return [0, 0, 0, 0, 0, 0, 0, EFFECT_CHARM, 1, CHARMS.find(card), 0, 0, 0, 0, 0, 0, tells]
		if where == "hero" or (where == "any" and card in CHARMS_ANY):
			return [0, 0, 0, 0, 0, 0, 0, EFFECT_CHARM, 2, CHARMS.find(card), 0, 0, 0, 0, 0, int(AIMS[where]), tells | (5 if where == "any" else 0)]
	# A card of a graveyard is aimed at the hero whose graveyard it is.
	var aimed := String(rule.get("target", "none"))
	var tail := [effect, int(SCOPES.get(String(rule.get("scope", "enemy")), 0)),
		s.effect_amount(rule), 1 if rule.get("variable", false) else 0, 0, 0, 0, 0,
		int(AIMS.get("hero" if aimed == "grave" else aimed, -1)), 1 if rule.get("own", false) else 0]
	# A spell aimed at something the model does not hold is left unplayed.
	if int(tail[8]) < 0: return []
	# The few spells the defending hero may cast as well.
	if card in ELDuel.DEFENCE_SPELLS.get(s.profile.id, []): tail[9] = int(tail[9]) | 2
	# Harm, which the original opponent never aims at its own side
	# (ELCombatSearch.SPELL_SIDES): bit 3 at its creatures, bit 4 at its hero.
	var sides := int(ELCombatSearch.SPELL_SIDES.get(s.profile.id, {}).get(card, 0))
	if sides & 2: tail[9] = int(tail[9]) | 8
	if sides & 8: tail[9] = int(tail[9]) | 16
	match String(rule.get("effect", "")):
		# Ether channels go to the caster unless the card says otherwise.
		"channels": tail[1] = int(SCOPES.get(String(rule.get("scope", "self")), 6))
		# Only creatures whose card costs no more than this come back.
		"unsummon": tail[2] = int(rule.get("maximum", 999))
		# One that pays the printed price of the creature it takes as well.
		"exile": tail[2] = 1 if rule.get("priced_target", false) else 0
		# A creature out of a graveyard: bit 0, only while the hero whose
		# graveyard it is has room too; bit 1, it comes back under the card
		# itself, laid on it as an enchantment.
		"reanimate":
			tail[2] = (1 if rule.get("grave_owner_cap", false) else 0) | (0 if rule.get("plain", false) else 2)
			if rule.get("own_grave", false): tail[9] = int(tail[9]) | 1
		# A creature of the caster's own goes over to the other hero.
		"gift":
			tail[2] = 0
			tail[9] = int(tail[9]) | 1
		# Only a creature of the caster's own is given for another.
		"exchange": tail[9] = int(tail[9]) | 1
		# Whose hand, and what is dealt in its place: bit 0 no creatures, bit 1
		# nothing but creatures, bit 2 whatever comes.
		"redraw":
			tail[1] = int(SCOPES.get(String(rule.get("scope", "self")), 6))
			tail[2] = (1 if rule.get("reject", "") == "creatures" else 0) | (2 if rule.get("reject", "") == "spells" else 0) | (0 if rule.get("retry", true) else 4)
		"amnesia", "ban", "clone", "repair", "swap", "cleanse": tail[2] = 0
		"banish", "flux", "pale_blast", "pale_calamity", "pale_cleave", "pale_revival", "pale_theft", "vaporize", "ripple": tail[2] = 0
		# One that pays what the enchantment cost as well.
		"dispel": tail[2] = 1 if rule.get("priced", false) else 0
		# One that leaves nothing to regenerate.
		"destroy": tail[2] = 1 if rule.get("no_regeneration", false) else 0
		# Power and health that last until a turn not its creature's hero's ends.
		"bless":
			tail[2] = 0
			tail[4] = int(rule.get("power", 0))
			tail[5] = int(rule.get("toughness", 0))
		# A creature of the caster's own is given for it.
		"trade":
			tail[2] = 0
			tail[9] = int(tail[9]) | 1
		# Bit 0: walls are spared rather than the restless; bit 1: the
		# second game's glade also calls back a creature sent to attack.
		"rest_enemies": tail[2] = (1 if rule.get("scope", "") == "not_walls" else 0) | (2 if ctx.second and card == "GLDT" else 0)
		# Only cards that are no creatures go, unless the card takes any.
		"random_discard": tail[1] = int(SCOPES.all) if rule.get("any", false) else 0
	if effect == EFFECTS.enchant:
		# Only the ones laid on a single creature; those on a hero or on a
		# whole army are a shape of their own and the model leaves them alone.
		if String(rule.get("target", "")) != "creature": return []
		var lends := 0
		for flag: String in ELCatalog.GRANTED_FLAGS.get(card, []): lends |= int(FLAGS.get(flag, 0))
		# A creature that comes over to the caster, and one whose power and
		# health change places, are rules of their own in the engine.
		if card in ELCatalog.CONTROL: return [0, 0, 0, 0, 0, 0, 0, EFFECT_CONTROL] + tail.slice(1)
		if card == "DELS": return [0, 0, 0, 0, 0, 0, 0, EFFECT_DELUSION] + tail.slice(1)
		var holds: Dictionary = HOLDS_SECOND if ctx.second else HOLDS
		# What it does beyond its points, where the engine has a rule for it.
		var regrows := int(ELCatalog.GRANTED_REGENERATION.get(card, 0))
		var known := SPECIALS.has(card) or TICKS.has(card) or regrows > 0 or card == "ETAM"
		# The first game's redirection also keeps its creature from regenerating.
		if card == "REDR" and not ctx.second: lends |= int(FLAGS.NoRegen)
		# One with a rule of its own is left to the duel's rules, except the
		# twisted enhancement, whose wearing off the model follows.
		if not holds.has(card) and not card in ["TWEN", "OVRL", "PALN"] and not known:
			if card in SPECIAL_ENCHANTMENTS or card in ELDuel.END_OF_TURN_CARDS: return []
			for key: String in rule:
				if not key in PLAIN_ENCHANTMENT: return []
		# Bit 0: it can take a creature's last point of health; bit 1: it
		# wears off turn by turn.
		# Bits 8-10: the cards its creature's blow then takes from a hand.
		var robbing := mini(ELCatalog.granted_discard(s.profile, card), 7)
		tail[2] = (1 if rule.get("lethal", false) else 0) | (2 if card == "TWEN" else 0) | (4 if card == "OVRL" else 0) | (8 if card == "PALN" else 0) \
			| (16 if card in BRIEF else 0) | (32 if card == "SPWR" else 0) | (robbing << 8) \
			| (64 if card in MUTING else 0) | (128 if card == "ETAM" else 0) | (mini(regrows, 15) << 11) | (int(TICKS.get(card, 0)) << 15)
		tail[4] = int(rule.get("power", 0))
		tail[5] = int(rule.get("toughness", 0))
		tail[6] = lends
		# The ether that frees it, and (256) whether that costs health too and
		# leaves the creature held.
		tail[7] = int(holds.get(card, 0)) | (256 if holds.has(card) and card != "ENFL" else 0)
		# One that lends no strength, no ability and holds nothing down does
		# its work some other way (ether, for one), which the model has no
		# rule for: it is left to the duel's own rules.
		if int(tail[4]) == 0 and int(tail[5]) == 0 and lends == 0 and int(tail[7]) == 0 and card != "PALN" and robbing == 0 and not known: return []
		return [0, 0, 0, 0, 0, 0, 0] + tail
	if effect != EFFECTS.summon: return [0, 0, 0, 0, 0, 0, 0] + tail
	var row: Dictionary = s.profile.table("CombatCreatures").get(card, {})
	if row.is_empty(): return []
	var flags := 0
	var regeneration := 0
	var names := ELCatalog.flags(row)
	for flag: String in names:
		flags |= int(FLAGS.get(flag, 0))
		if flag.begins_with("Regen("): regeneration = int(flag.trim_prefix("Regen(").trim_suffix(")"))
	if not names.has("NSS"): flags |= F_SICK
	var race := str(row.get("Race", ""))
	if race == "Wall": flags |= F_WALL
	if card in ELCatalog.WALL_BLOCKED: flags |= F_ELUSIVE
	if card in ELCatalog.MECHOS: flags |= F_DESTROY_UNWALLED
	if card in ELCatalog.STINGERS: flags |= F_STINGER
	if card == BURNS: flags |= F_BURN
	if card == VENOMOUS: flags |= F_VENOM
	if card == WHIRLS: flags |= F_DESTROY_FLYER
	if card in ELCatalog.FATALISTS: flags |= F_FATALIST
	var robs := 0
	for flag: String in names:
		if flag.begins_with("Discard("): robs += int(flag.trim_prefix("Discard(").trim_suffix(")"))
	# The second game's pale creatures arrive in the Colourless Plane.
	var pale: bool = names.has("Outerplanar")
	if ctx.second and pale and card != "OSJ1": flags |= F_PLANE
	var power := int(row.Power)
	var toughness := int(row.Toughness)
	var worth := ctx.w[5] + float(toughness) * ctx.w[8] + float(power) * (ctx.w[7] if names.has("NoAttack") else ctx.w[6])
	if names.has("Fly"): worth += (0.6 + float(power) * 0.1) if ctx.second else 0.1
	# What else the creature is, for the one the model summons itself: the
	# health it costs its hero each turn, whether anything may be aimed at
	# it, and whether it is a walking horror.
	tail[2] = int(ELCatalog.PARASITES.get(card, 0))
	var able := ability_of(s.profile, card)
	tail[6] = (1 if names.has("NoTarget") else 0) | (2 if card == "WKHR" else 0) \
		| (((1 << 23) if card == "BATT" else 0) | ((1 << 24) if card == "GBAT" else 0) if ctx.second else 0) \
		| ((1 << 25) if card in ENVENOMS else 0) | ((1 << 26) if card == "MOBE" else 0) 		| ((1 << 27) if card == "BHMO" else 0) | ((1 << 28) if str(row.get("Race", "")) == "Beholder" else 0) \
		| (int(able[0]) << 2) | (mini(int(able[1]), 15) << 8) | (int(able[2]) << 12) | (int(able[3]) << 19)
	# The plain worth of the creature it would put on the board: the engine
	# counts the card leaving the hand on its own, and `_card_worth` would
	# take that off a second time.
	# The aura it brings with it.
	var aura := ELCatalog.creature_aura(s.profile, card)
	var given := 0
	for flag: String in aura.get("flags", []): given |= int(FLAGS.get(flag, 0))
	tail[4] = int(aura.get("power", 0))
	tail[5] = int(aura.get("toughness", 0))
	return [power, toughness, flags, regeneration, int(worth * 1000.0), int((worth - 0.5) * 1000.0), _race_word(s.profile, race, card)] + tail \
		+ [given, _reach(s.profile, aura) | (512 if card == "WRSP" else 0) | (2048 if pale else 0) | (mini(robs, 7) << 12) | (32768 if _rises(s.profile, card) else 0) | (65536 if s.profile.id == "el1" and card in ELDuel.EL1_IMMORTAL_DRAGONS else 0)]

## Whether `card`, buried under three cards or more, comes back into play
## when its hero's turn ends.
static func _rises(profile: ELProfile, card: String) -> bool:
	if card not in ELCatalog.FIRST_RISING: return false
	return profile.id == "el1" or card in ELCatalog.RISING or ELCatalog.shared(profile, card)

## The average creature of `faction` for each cost, and how many of the
## colour's cards are creatures.
static func _typical_of(profile: ELProfile, faction: String) -> Dictionary:
	var key := profile.id + ":" + faction
	if _typical.has(key): return _typical[key]
	var sums: Array = []
	for cost in COSTS: sums.append([0, 0, 0])
	var cards := ELCatalog.available_cards(profile, faction)
	var creatures := 0
	for card: String in cards:
		if ELCatalog.rule(profile, card).get("effect", "") != "summon": continue
		var row: Dictionary = profile.table("CombatCreatures").get(card, {})
		if row.is_empty(): continue
		creatures += 1
		var cost := int(profile.table("CombatSpells")[card].Cost)
		if cost < 1 or cost > COSTS: continue
		sums[cost - 1][0] += int(row.Power)
		sums[cost - 1][1] += int(row.Toughness)
		sums[cost - 1][2] += 1
	var stats: Array = []
	for sum: Array in sums:
		stats.append([roundi(float(sum[0]) / float(sum[2])), roundi(float(sum[1]) / float(sum[2]))] if int(sum[2]) > 0 else [0, 0])
	var result := {"share": creatures * 1000 / maxi(1, cards.size()), "stats": stats}
	_typical[key] = result
	return result

## What the engine makes of the position as it stands, and where a line
## stopping here would be scored: for holding its reckoning against the
## search's own.
static func reckon(ctx: ELCombatSearch.Context, s: ELDuel) -> Dictionary:
	var raw: PackedInt32Array = ask(ctx, s, 1, 1, true, 6).get("raw", PackedInt32Array())
	if raw.size() < 2: return {}
	return {"worth": float(raw[0]) * 0.001, "leaf": float(raw[1]) * 0.001}

## Every command played out to the end of the duel over and over: the one
## that won most often, with the whole table. Nothing is weighed but who won.
static func gamble(ctx: ELCombatSearch.Context, s: ELDuel, rounds: int, budget: int) -> Dictionary:
	var raw: PackedInt32Array = ask(ctx, s, 1, budget, true, 8, [], rounds, ELCombatSearch.smart_engine_width).get("raw", PackedInt32Array())
	if raw.size() < 1 or int(raw[0]) <= 0: return {}
	var ids: Array = s.creatures.keys()
	var table: Array = []
	var best := -1.0
	var command := {}
	var games := 0
	for i in int(raw[0]):
		var at := 1 + i * 6
		if at + 5 >= raw.size(): break
		var played := int(raw[at + 5])
		if played <= 0: continue
		var share := float(raw[at + 4]) / float(played)
		var what := _command_of(s, ids, int(raw[at]), int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3]))
		table.append({"command": what, "share": share, "games": played})
		games += played
		if share > best:
			best = share
			command = what
	if command.is_empty(): return {}
	return {"command": command, "share": best, "games": games, "table": table}

## Every command the engine would weigh here, with its worth, for holding
## its reckoning against the search's own.
## Each is read as the choice (`choose`) reads a first command, with the same
## phases, commands a line, width and scoring, within the budget and the
## decision's deadline: `complete` is false for one whose reading was cut
## short. A command the clock left unread is not listed.
static func weigh(ctx: ELCombatSearch.Context, s: ELDuel, phases: int, budget: int, steps: int, width := 0) -> Array:
	var raw: PackedInt32Array = ask(ctx, s, phases, budget, true, 7, [], steps, width if width > 0 else ELCombatSearch.smart_engine_width).get("raw", PackedInt32Array())
	if raw.size() < 1: return []
	var ids: Array = s.creatures.keys()
	var out: Array = []
	for i in int(raw[0]):
		var at := 1 + i * 6
		if at + 5 >= raw.size(): break
		out.append({"command": _command_of(s, ids, int(raw[at]), int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3])),
			"value": float(raw[at + 4]) * 0.001, "complete": int(raw[at + 5]) != 0})
	return out

## Whether `ctx.ai` wins within `turns` of its own turns whatever the other
## hero does, as the compiled engine reads every command of both. Either hero
## may be the one to move; in a puzzle (ELPuzzles.Run keeps its objective in
## the duel's setup) "wins" means meets the puzzle's objective, and failing
## it is a loss. Empty when the library is missing or the position does not
## fit the model. The answer has three values:
##   turns > 0   a proven win in that many own turns: every command the
##               defender has was read, and none stops it (`line` the win);
##   settled     the most turns read whole with no win: a proof that there
##               is none within them;
##   past those  unknown: `aborted` (the budget ran out), `unknown` (the
##               reading met what it cannot follow: chance, more than the
##               model has room for, a line longer than it may read, more
##               commands than it may list), or `incomplete` (the position
##               itself holds more than the model has room for).
## So "no win" may be claimed only for `turns <= settled`; `turns == 0` with
## `aborted` or `unknown` claims nothing.
static func prove(ctx: ELCombatSearch.Context, s: ELDuel, turns: int, budget: int) -> Dictionary:
	var raw: PackedInt32Array = ask(ctx, s, turns, budget, true, 9).get("raw", PackedInt32Array())
	if raw.size() < 7: return {}
	var line: Array = []
	var told := int(raw[7]) if raw.size() > 7 else 0
	for k in told: line.append([int(raw[8 + k * 4]), int(raw[9 + k * 4]), int(raw[10 + k * 4]), int(raw[11 + k * 4])])
	var tail := int(raw[8 + told * 4]) if raw.size() > 8 + told * 4 else 0
	var status := "unknown"
	match (tail >> 16) & 15:
		1: status = "proven"
		2: status = "no_forced_win"
		5: status = "unsupported"
	# A win is proved only on a model that held the whole position.
	if status == "proven" and (tail & 2) != 0: status = "unsupported"
	return {"turns": int(raw[0]) if status == "proven" else 0, "positions": int(raw[5]), "aborted": raw[6] != 0, "line": line if status == "proven" else [],
		"unknown": (tail & 1) != 0, "incomplete": (tail & 2) != 0, "settled": (tail >> 8) & 255, "status": status}

## The command the compiled engine chooses by searching the commands itself,
## with the worth of the line it found and the positions it played. The
## command is the game's own kind, ready for ELCombatSearch.apply. Empty when
## the library is missing or the position does not fit the model. Of the
## win it looked for first (see `prove`): `proven` the turns of a proven win
## (0 for none), `settled` the most turns read whole without one, `cut` the
## budget ran out on a longer reading, and `unknown` a longer reading met
## what it cannot follow - with either, the turns past `settled` are unknown,
## not won and not lost.
static func choose(ctx: ELCombatSearch.Context, s: ELDuel, phases: int, budget: int, steps: int, width := 16) -> Dictionary:
	var raw: PackedInt32Array = ask(ctx, s, phases, budget, true, 5, [], steps, width).get("raw", PackedInt32Array())
	if raw.size() < 7: return {}
	var ids: Array = s.creatures.keys()
	var command := _command_of(s, ids, int(raw[1]), int(raw[2]), int(raw[3]), int(raw[4]))
	var result := _result(raw)
	# A command the engine named that the game has no command for is an
	# error of the engine's, told as one, not a quiet end of the phase.
	if String(command.kind) == "end_phase" and int(raw[1]) != 0 and int(raw[1]) != 5:
		result.error = "unmapped engine command %s" % str([int(raw[1]), int(raw[2]), int(raw[3]), int(raw[4])])
	# A whole attack is given to the game one creature at a time.
	if int(raw[1]) == 5:
		var mask := (int(raw[2]) & 0xffff) | (int(raw[3]) << 16)
		var sending: Array = []
		for i in ids.size():
			if mask & (1 << i) and not s.attacks.has(int(ids[i])): sending.append({"kind": "attack", "id": int(ids[i])})
		# The guards last: each needs one of its race sent before it.
		var guards := sending.filter(func(step: Dictionary) -> bool: return s.has_flag(int(step.id), "TeamAttack"))
		sending = sending.filter(func(step: Dictionary) -> bool: return not s.has_flag(int(step.id), "TeamAttack")) + guards
		if sending.is_empty(): return {"error": "an attack of creatures that cannot be sent", "status": "unknown", "positions": int(raw[5])}
		var whole := {"command": sending[0], "line": sending, "value": float(raw[0]) * 0.001, "raw": raw, "proven": (int(raw[7]) >> 16) & 15,
			"settled": (int(raw[7]) >> 20) & 15, "cut": (int(raw[7]) >> 24) & 1, "guarded": (int(raw[7]) >> 25) & 15, "unknown": (int(raw[7]) >> 29) & 1,
			"positions": int(raw[5]), "aborted": raw[6] != 0, "depth": int(raw[7]) & 255, "far": (int(raw[7]) >> 8) & 255}
		whole.merge(result)
		if String(whole.status) != "proven": whole.proven = 0
		return whole
	# The rest of the line it means to play. A later card would name a place
	# in a hand that the first command has already changed, so the line stops
	# at the first one.
	var line: Array = [command]
	var count := int(raw[8]) if raw.size() > 8 else 0
	for i in range(1, count):
		var at := 9 + i * 4
		if at + 3 >= raw.size() or int(raw[at]) == 3: break
		var step := _command_of(s, ids, int(raw[at]), int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3]))
		if String(step.kind) == "end_phase": break
		line.append(step)
	var chosen := {"command": command, "line": line, "value": float(raw[0]) * 0.001, "positions": int(raw[5]), "raw": raw, "proven": (int(raw[7]) >> 16) & 15 if raw.size() > 7 else 0,
		"settled": (int(raw[7]) >> 20) & 15 if raw.size() > 7 else 0, "cut": (int(raw[7]) >> 24) & 1 if raw.size() > 7 else 0, "guarded": (int(raw[7]) >> 25) & 15 if raw.size() > 7 else 0,
		"unknown": (int(raw[7]) >> 29) & 1 if raw.size() > 7 else 0,
		"aborted": raw[6] != 0, "depth": (int(raw[7]) & 255) if raw.size() > 7 else 0, "far": ((int(raw[7]) >> 8) & 255) if raw.size() > 7 else 0}
	chosen.merge(result)
	# Proven only where every reply was read on a model that held it all.
	if String(chosen.status) != "proven": chosen.proven = 0
	return chosen

## What the engine says of its choice (`choose`), after its line: {status
## ("proven" a forced win, every reply read; "no_forced_win" none within the
## turns the proof read whole, the command itself judged; "heuristic" judged
## with no proof asked; "unknown" the budget, the clock or something the
## proof cannot follow ended it; "unsupported" the position holds more than
## the model has room for), terminal (the worth is a decided duel), covered
## (every reply was read), exact (the worth is no estimate), selective_win
## ("refuted" or "unverified": a win the usual reading foresaw that a
## reading of every reply did not bear out), crowding (what the model left
## out, see `last_crowding`)}.
static func _result(raw: PackedInt32Array) -> Dictionary:
	var count := int(raw[8]) if raw.size() > 8 else 0
	var word := int(raw[9 + count * 4]) if raw.size() > 9 + count * 4 else 0
	var status: String = ["unknown", "proven", "no_forced_win", "heuristic", "unknown", "unsupported"][clampi(word & 15, 0, 5)]
	if last_crowded: status = "unsupported"
	return {"status": status, "terminal": (word & 16) != 0, "covered": (word & 32) != 0 and status == "proven",
		"exact": (word & 64) != 0 and status == "proven", "selective_win": "refuted" if word & 128 else ("unverified" if word & 256 else ""),
		"crowding": last_crowding.duplicate()}

## One command of the engine's own kind, as the game names them.
static func _command_of(s: ELDuel, ids: Array, kind: int, a: int, b: int, c: int) -> Dictionary:
	match kind:
		1:
			if a >= 0 and a < ids.size(): return {"kind": "attack", "id": int(ids[a])}
		4:
			# Whichever of the three the creature actually carries.
			if a >= 0 and a < ids.size():
				var id := int(ids[a])
				for ability: Dictionary in s.abilities(id):
					if String(ability.key) in ["wake", "awaken", "unparalyze"] and s.can_use_ability(id, String(ability.key)):
						return {"kind": "ability", "id": id, "key": String(ability.key), "target": -1, "choice": -1, "amount": -1}
		2:
			if a >= 0 and a < ids.size() and b >= 0 and b < ids.size():
				return {"kind": "block", "id": int(ids[a]), "target": int(ids[b])}
		8:
			# The hero's own ability, through the first copy not yet used.
			var side := s.active_side()
			if a >= 0 and a < HERO_KEYS.size() and (b == -99 or (b >= -2 and b < ids.size())):
				for ability: Dictionary in s.abilities(side):
					if String(ability.get("effect", "")) != HERO_KEYS[a] or ability.get("used", false): continue
					var target := -1 if b == -99 else (-1 - b if b < 0 else int(ids[b]))
					var choice := -1
					if HERO_KEYS[a] == "repair":
						# The creature card the engine named comes back, by its
						# place among the newest of its own graveyard; where it
						# named none, the dearest.
						target = side
						var allowed: Array = s.grave_ability_targets(side, String(ability.key), side)
						var buried: int = s.heroes[side].grave.size()
						if c >= 0 and allowed.has(buried - mini(buried, GRAVES) + c): choice = buried - mini(buried, GRAVES) + c
						else:
							for index: int in allowed:
								if choice < 0 or s.cost(String(s.heroes[side].grave[index])) > s.cost(String(s.heroes[side].grave[choice])): choice = index
						if choice < 0: break
					elif HERO_KEYS[a] in ["rebirth", "second_birth"]:
						# The card of its own graveyard the engine named, by its
						# place among the newest.
						target = side
						var size: int = s.heroes[side].grave.size()
						choice = size - mini(size, GRAVES) + c
						if choice < 0 or choice >= size: break
					elif HERO_KEYS[a] in ["combine", "burnout", "recycle"]:
						# The second thing it names: a creature, or a hero.
						if c < -2 or c >= ids.size(): break
						choice = -1 - c if c < 0 else int(ids[c])
					return {"kind": "ability", "id": side, "key": String(ability.key), "target": target, "choice": choice, "amount": -1}
		7:
			# A creature's ability, on a hero (-1, -2), a creature or nothing.
			if a >= 0 and a < ids.size() and (b == -99 or (b >= -2 and b < ids.size())):
				var user := int(ids[a])
				var key := ability_key(s.profile, String(s.creatures[user].card))
				if not key.is_empty():
					var target := -1 if b == -99 else (-1 - b if b < 0 else int(ids[b]))
					var choice := -1
					var amount := -1
					if key in GRAVE_ABILITIES:
						# A card of a graveyard, by its place among the newest of
						# them, which are the ones the engine is told.
						if target < 0 or target > 1: return {"kind": "end_phase"}
						var size: int = s.heroes[target].grave.size()
						choice = size - mini(size, GRAVES) + c
						if choice < 0 or choice >= size: return {"kind": "end_phase"}
					elif key in X_ABILITIES: amount = c
					elif key in DISPELLING:
						# The enchantment it takes off what it is aimed at.
						if target < 0: return {"kind": "end_phase"}
						choice = enchantment_named(s, target, c, 1 if key == "disenchant" else 0)
						if choice < 0: return {"kind": "end_phase"}
					return {"kind": "ability", "id": user, "key": key, "target": target, "choice": choice, "amount": amount}
		11:
			# What a pale creature does: which of its abilities is told in
			# the high half, and what it names beside its target in the low.
			if a >= 0 and a < ids.size() and (b == -99 or (b >= -2 and b < ids.size())) and c >= 0 and (c >> 16) > 0 and (c >> 16) < PALE_KEYS.size():
				var shade := int(ids[a])
				var does: String = PALE_KEYS[c >> 16]
				var named := c & 0xffff
				var aim := -1 if b == -99 else (-1 - b if b < 0 else int(ids[b]))
				var chosen := -1
				if does == "sinister":
					if aim < 0 or aim > 1: return {"kind": "end_phase"}
					var buried: int = s.heroes[aim].grave.size()
					chosen = buried - mini(buried, GRAVES) + named
					if chosen < 0 or chosen >= buried: return {"kind": "end_phase"}
				elif does in ["mystic", "absorb", "weave", "transpose"]:
					if aim < 0: return {"kind": "end_phase"}
					chosen = enchantment_named(s, aim, named, 2 if does == "weave" else 0, s.active_side() if does == "mystic" else -1)
					if chosen < 0: return {"kind": "end_phase"}
				return {"kind": "ability", "id": shade, "key": does, "target": aim, "choice": chosen, "amount": -1}
		3:
			var hand: Array = s.heroes[s.active_side()].hand
			var carried: Array = s.heroes[s.active_side()].get("artifacts", [])
			# A card of the hand, or a thing the hero carries.
			var does := ""
			if a >= ART_BASE and a - ART_BASE < carried.size():
				var item: Dictionary = carried[a - ART_BASE]
				does = String((ELCatalog.rule(s.profile, String(item.spell)) if item.has("custom") else ELCatalog.ARTIFACT_EFFECTS.get(String(item.spell), {})).get("effect", "-"))
			# (A card that came back into the hand in the middle of a line has a
			# place past the hand's in the engine. Such a place never names
			# the command to give now: the position is told afresh for every
			# decision, with that card in the hand like any other, and a line
			# kept for later stops at its next card - see `choose`.)
			elif a >= 0 and a < mini(hand.size(), SLOTS): does = String(ELCatalog.rule(s.profile, String(hand[a])).get("effect", "-"))
			if not does.is_empty():
				var target := -1
				if b >= -2 and b < 0: target = -1 - b
				elif b >= 0 and b < ids.size(): target = int(ids[b])
				# What the card names beside its target stands where an X would.
				var named := -1
				var power := c
				match int(CHOICES.get(does, 0)):
					1, 2:
						var whose := target if int(CHOICES.get(does, 0)) == 1 else s.active_side()
						if whose < 0 or whose > 1: return {"kind": "end_phase"}
						var size: int = s.heroes[whose].grave.size()
						named = size - mini(size, GRAVES) + c
						if named < 0 or named >= size: return {"kind": "end_phase"}
						power = 0
					3:
						if c < 0 or c >= ids.size(): return {"kind": "end_phase"}
						named = int(ids[c])
						power = 0
					4:
						# An enchantment on what the card is aimed at.
						if target < 0: return {"kind": "end_phase"}
						named = enchantment_named(s, target, c)
						if named < 0: return {"kind": "end_phase"}
						power = 0
					6:
						# A card of either graveyard, by its place among the
						# newest of that one.
						var whose := c / 64
						if c < 0 or whose > 1: return {"kind": "end_phase"}
						var lying: int = s.heroes[whose].grave.size()
						var place := lying - mini(lying, GRAVES) + c % 64
						if place < 0 or place >= lying: return {"kind": "end_phase"}
						named = whose * ELDuel.GRAVE_SIDE + place
						power = 0
					5:
						# One anywhere: its holder is told with it.
						var step := c / 4096
						if c < 0 or step - 2 >= ids.size(): return {"kind": "end_phase"}
						named = enchantment_named(s, step if step < 2 else int(ids[step - 2]), c % 4096)
						if named < 0: return {"kind": "end_phase"}
						power = 0
				if a >= ART_BASE: return {"kind": "ability", "id": s.active_side(), "key": "artifact:%d" % (a - ART_BASE), "target": target, "choice": named, "amount": -1}
				return {"kind": "cast", "index": a, "card": String(hand[a]), "target": target, "grave": named, "power": power}
	return {"kind": "end_phase"}

## The board the declared fight leaves (`mode` 2), the one the turn's end
## leaves (3), or the one a list of `commands` leaves (4), played by the
## compiled rules alone and nothing else:
## `{"health": [both], "ether": [both], "channels": [both], "attacker": side,
## "units": {id: damage, or -1 for a creature that died}, "resting":
## {id: bool}, "blocks": {id: the attacker's id}}`. Empty when the library is
## missing. Used by tools/duel_rules_check.gd to hold these rules against the
## game's own.
static func fight(ctx: ELCombatSearch.Context, s: ELDuel, mode := 2, commands: Array = [], budget := 1) -> Dictionary:
	var raw: PackedInt32Array = ask(ctx, s, 1, budget, false, mode, commands).get("raw", PackedInt32Array())
	if raw.size() < 9: return {}
	var units := {}
	var resting := {}
	var blocks := {}
	var at := 9
	var counts := {}
	var order: Array[int] = []
	while at + 3 < raw.size():
		if int(raw[at]) == -1000000:
			# What else the engine counts: cards held, cards buried, armies.
			counts = {"hands": [int(raw[at + 1]) & 255, int(raw[at + 1]) >> 8], "graves": [int(raw[at + 2]) & 255, int(raw[at + 2]) >> 8],
				"armies": [int(raw[at + 3]) & 255, int(raw[at + 3]) >> 8]}
			at += 4
			break
		units[int(raw[at])] = int(raw[at + 1])
		resting[int(raw[at])] = raw[at + 2] != 0
		if int(raw[at + 3]) >= 0: blocks[int(raw[at])] = int(raw[at + 3])
		order.append(int(raw[at]))
		at += 4
	var out := {"health": [int(raw[1]), int(raw[2])], "ether": [int(raw[3]), int(raw[4])],
		"channels": [int(raw[5]), int(raw[6])], "attacker": int(raw[7]), "phase": int(raw[8]),
		"played": int(raw[0]), "units": units, "resting": resting, "blocks": blocks, "counts": counts}
	# Then, from a library that tells it, the rest of what the rules leave:
	# each creature's power, health, spent ability and worn enchantments; the
	# cards of each hand the model knows by name (as the caller's numbers);
	# what each hero wears, and the copies of it used this turn.
	if at < raw.size() and int(raw[at]) == -2000000 and at + 1 + order.size() * 4 + 2 <= raw.size():
		at += 1
		var stats := {}
		for id: int in order:
			stats[id] = {"power": int(raw[at]), "toughness": int(raw[at + 1]), "spent": raw[at + 2] != 0, "worn": int(raw[at + 3])}
			at += 4
		var named: Array = [[], []]
		for side in 2:
			var count := int(raw[at]) if at < raw.size() else 0
			at += 1
			for k in count:
				if at < raw.size(): named[side].append(int(raw[at]))
				at += 1
		var worn: Array = [[], []]
		var used: Array = [[], []]
		for side in 2:
			for k in CHARMS.size():
				worn[side].append(int(raw[at]) if at < raw.size() else 0)
				at += 1
		for side in 2:
			for k in HERO_KEYS.size():
				used[side].append(int(raw[at]) if at < raw.size() else 0)
				at += 1
		out.stats = stats
		out.named = named
		out.hero_worn = worn
		out.hero_used = used
		# Whether the model followed the line to its end: no more than it has
		# room for (`limit`), and no card that chance took or dealt (`blind`).
		# (The last three numbers of the answer.)
		if raw.size() >= 3 and int(raw[raw.size() - 3]) == -3000000:
			out.limit = int(raw[raw.size() - 2])
			out.blind = int(raw[raw.size() - 1])
	return out
