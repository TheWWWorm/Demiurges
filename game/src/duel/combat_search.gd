class_name ELCombatSearch
extends RefCounted
## The combat opponent's decision: a budgeted lookahead over copies of the duel
## that plays the real rules. Each think returns one command, the first step of
## the best line; the opponent thinks again before its next command.
##
## Moves come in the original order: next phase (priority 1.1), the acting
## hero's hand spells and artifacts (opponent lines never cast), hero
## abilities, then the whole-army attack plan or the four block plans, then each
## creature's abilities and lone attack. Moves are tried by priority; a
## priority under 0.01 is never tried. Positions are scored with nine weights
## drawn from the battle's random sequence without advancing it.

const THRESHOLD := 0.01
const BUDGET := 1000
## The positions the original opponent reads per decision: BUDGET, or
## EASY_BUDGET for the "Easy" duel opponent (setting "duel_ai" 0), which
## then settles on its first ideas instead of weighing them out.
const EASY_BUDGET := 40
static var original_budget := BUDGET
## Remake option (ELDuel.smart_sides), for both games: the middle of each
## weight's range instead of a random draw (no misjudged position on an
## unlucky roll), more replies per position, the compiled combat lookahead
## and the fixes for plainly poor plays below (`smart_order` and after).
## Measured in computer-vs-computer duels (tools/duel_ai_bench.gd) against
## the original opponent it wins about 59 duels in 100, and of the pairings
## that play, not the cards, decides some 43 against 10. A larger budget, a
## further phase of lookahead and casting replies measured no stronger for
## their thinking time, so they are off. tools/duel_ai_audit.gd counts the
## poor plays and tools/duel_ai_check.gd replays the positions they were
## found in.
static var smart_budget := 1500
static var smart_phases := 0
static var smart_steady := true
static var smart_replies := false
## Replies tried per position (the original stops after three, two past depth
## four and one past depth nine).
static var smart_width := 6
## The opponent's coming attack counts against a line that ends the computer's
## own turn: each point of damage its ready creatures cannot stop costs this
## share of a health point, and damage that would finish the hero costs
## `smart_lethal`. 0 leaves the attack out, as the original does.
static var smart_threat := 0.0
static var smart_lethal := 0.0
const FALLBACK_THREAT := 0.5
const FALLBACK_LETHAL := 300.0
## The compiled combat lookahead (ELCombatBrain), where the library is present.
## A line that ends a turn is scored by `smart_brain_turns` further turns of
## fighting (0 = off), within `smart_brain_budget` fights; the attackers and
## blocks it finds best join the moves tried (`smart_brain_moves`), looked for
## `smart_brain_move_turns` turns ahead within `smart_brain_move_budget`
## fights for the move being chosen. Looking further than this measured no
## stronger.
static var smart_brain_turns := 2
static var smart_brain_budget := 4000
static var smart_brain_moves := true
static var smart_brain_move_turns := 3
static var smart_brain_move_budget := 200000
## The lookahead can also have its sides play cards in the turns it looks at
## (`smart_brain_cards`): the computer's own creature cards
## (`smart_brain_own`), the typical creatures expected from cards it cannot
## see (`smart_brain_typical`), and waking enfeebled creatures; a creature
## still to be played counts for `smart_brain_discount` of one in play. Off:
## over some 2500 duels in both games, with either part, both, a zero
## discount and a deeper search, it won 48 to 50 in 100 against the armies
## alone.
static var smart_brain_cards := false
static var smart_brain_discount := 0.7
static var smart_brain_own := true
static var smart_brain_typical := true
## The order moves are tried in (`smart_order`). The original tries every
## spell and ability of a position before any attack or block, and its budget
## often ends there: with a handful of spells or one ability that can be used
## many ways, attacking or blocking was never looked at (in about one think in
## seven, measured), so the computer let a won fight go or died without
## blocking. With this on, ending the phase, the lookahead's attackers or
## blocks and the whole-army plans come first, then spells and abilities, then
## lone attackers; and each further form of a spell or ability already tried
## counts for `smart_family` of its priority, so that one spell with many
## targets or amounts does not crowd out the others.
static var smart_order := true
static var smart_family := 0.8
## A plan of several attackers or blocks, once chosen, is carried out without
## thinking again between its commands (`smart_follow`): thought over anew
## after each one, the computer would at times change its mind half way, send
## one of the two attackers a win needed or pile its blockers on one attacker.
static var smart_follow := true
## A spell or ability that would change nothing (every creature raised when
## none rests, ether taken from a hero that has none) is not played, nor a
## spell that only gives ether when the plays after it need no more ether than
## the hero already holds and no creature of its army can regenerate.
static var smart_idle := true
## Hero entries a spell spends or reorders without having done anything.
const IDLE_KEYS := ["hand", "hand_slots", "hand_view", "hand_ids", "mana", "grave", "spell_uses", "drawn"]
## A win or loss the lookahead foresees is worth `smart_forced`, less
## `smart_forced_step` for every turn it is away, on top of the line's own
## worth: far below a duel really won, so winning now beats expecting to, and
## among lost lines the one that holds out and keeps the most still wins.
static var smart_forced := 300.0
static var smart_forced_step := 20.0
## A point of the other hero's health counts for `smart_foe_health` of one of
## the computer's own (1 = the same, as the original).
static var smart_foe_health := 1.0
## A gain the lookahead only foresees counts for `smart_later` of one already
## made, so that the computer does not put a good attack off turn after turn.
static var smart_later := 0.9
## Second-game spells that pay only on later turns, which a lookahead of one
## turn does not reach, count for the hero that cast them, `smart_income`
## times: 2.5 for an ether storm (a channel every turn) and 2.0 for an ether
## breeze (3 ether every turn) on a creature in play, a little more on a
## sturdy one, and for an ether vortex 0.2 for each ether of the hand's cost
## that next turn's channels alone will not pay. 0 leaves them unvalued.
static var smart_income := 1.0
## Remake option: the last use of a spell that summons nothing is spent only
## when its line is at least `smart_margin` better than the best line without
## it. Off: a hoarded spell is often never cast at all, and the worth of a
## card in hand is already counted (weight 4). At 1.0 it wins 46 duels in 100
## against casting whatever is best by a hair, in both games, and 46 again
## when it holds back every spell rather than the last use alone.
static var smart_margin := 0.0
## Remake option: while the compiled lookahead, which plays the defender's
## blocks out, names the creatures to send, no other creature is offered an
## attack of its own. Without it the search adds attackers one by one, each
## worth sending on its own reckoning, and hands the defender creatures its
## blocks kill for nothing: over 300 duels it sends 18 such attacks in the
## first game against 15 with it, while winning as many duels either way.
static var smart_set_only := true
## Remake option: the model is told the other hero's creature cards instead
## of guessing a typical creature of its colour. The computer would be seeing
## a hand no player can see, so this is a cheat, and it needs
## `smart_brain_cards` to do anything at all.
static var smart_open_hand := false
## Remake option: the compiled engine searches the commands itself, under the
## rules ported beside it, instead of this search playing the game's rules on
## copies of the duel. It is the same choice of move made some thousand times
## faster, and it can only play the cards whose effects are ported; a card it
## does not know it leaves in hand. On: read two turns of each hero ahead,
## and further where the position is small, it wins 62 duels in 100 against
## this search in the first game and 58 in the second. Where the library is
## missing (the browser version) this search plays instead.
static var smart_engine := true
## Phase changes it looks through, commands in one line, and positions it may
## play (`smart_engine_budget`). Two turns of each hero and two million
## positions is where it was measured against this search: with the further
## reading of `smart_engine_reach` it won 62 duels in 100 in the first game
## and 57 in the second, thinking about half as long again.
static var smart_engine_phases := 4
static var smart_engine_steps := 16
## Commands it plays through at a node below the first.
static var smart_engine_width := 16
## Turns of fighting played out where a line stops (0 guesses instead).
static var smart_engine_leaf := 1
## Remake option: instead of weighing positions, the engine plays every
## command out to the end of the duel over and over and keeps the one that
## won most often. Nothing is weighed but who won.
static var smart_engine_rollouts := false
## Remake option: how much of a line's worth, to the engine, is the position
## where the line stops just as it stands; the rest is what the fighting
## read on from there brings. 0 trusts the reading wholly.
static var smart_engine_blend := 0.0
## Remake option: a line the engine reads to its end has the hero then to
## move send its best attack before the position is weighed. Without it a
## line in which the engine attacked is weighed with the other hero's whole
## turn passed over, so the blow that answers the attack is never counted.
## Off: it won the engine no more duels against the search (35 and 41 in 100
## with it, 38 and 41 without), and with it the engine passes up the sound
## attack of the position `el2_attack_sawers`.
static var smart_engine_answer := false
## Remake option: the weight of the compiled engine's opinion beside the
## search's own worth of a first move (see `_second_opinion`); 0 asks nothing.
static var smart_second := 0.0
## How many of the search's leading first moves the engine is asked about,
## and how far behind the best one may be and still be asked about.
static var smart_second_moves := 3
static var smart_second_within := 1.5
## Remake option: the engine does not cast a spell that the original's own
## reckoning of spells rules out for this target and moment (see `_unlikely`).
static var smart_engine_likely := true
## Measuring aid: classes of decision the engine leaves to the search (see
## `_decision_class`); 0 for none.
static var smart_engine_defer := 0
## Remake option: how many of the spells and abilities the compiled engine
## has no rule for are tried by the duel's own rules at each think (see
## `_beyond`). 0 leaves the engine to what it models.
static var smart_engine_beyond := 8
## How much better than the engine's own best command such a spell or ability
## must leave the position before it is played.
static var smart_engine_beyond_margin := 0.2
## How much worse it may leave the position where the engine would otherwise
## only end the phase.
static var smart_engine_beyond_idle := 1.0
## Remake option: the engine is told the cards both heroes are about to
## draw, in the order the turns deal them, so a line can count on them. Both
## heroes draw from the one run of chance, so the cards are read off a copy
## of the duel in turn order (`ELCombatBrain.foreseen`); in the first game
## every card foreseen six turns ahead is the one then dealt.
static var smart_engine_draws := true
## Remake option: how far behind the best a command may leave the board and
## still be read. A command that already costs much more than another can
## hardly be the right one, and leaving it unread buys the depth to tell the
## rest apart. 0 reads every command.
static var smart_engine_margin := 0.0
## Remake option: each of the nine weights the opponent reckons a position
## by, when it is to be something other than the middle of the original's
## range. -999 leaves the weight as it was. They are tunable so that the
## compiled engine's judgement can be fitted to games won rather than taken
## from the original, whose numbers were chosen for its own one-turn look.
static var smart_w0 := -999.0
static var smart_w1 := -999.0
static var smart_w2 := -999.0
static var smart_w3 := -999.0
static var smart_w4 := -999.0
static var smart_w5 := -999.0
static var smart_w6 := -999.0
static var smart_w7 := -999.0
static var smart_w8 := -999.0

## The weights as set, the middle of each range unless one was named.
static func chosen_weights(second: bool) -> PackedFloat64Array:
	var w := steady_weights(second)
	var named := [smart_w0, smart_w1, smart_w2, smart_w3, smart_w4, smart_w5, smart_w6, smart_w7, smart_w8]
	for i in mini(named.size(), w.size()):
		if float(named[i]) > -900.0: w[i] = float(named[i])
	return w

## Remake option: a played-out duel fights as well as the compiled lookahead
## can, sending the attack it chooses and blocking as it advises, instead of
## simply sending the strongest creature. A play-out that blocks badly makes
## a hopeless attack look sound, so what it says of a command is only worth
## as much as the fighting in it.
static var smart_engine_fights := true
## The engine remembers the positions it has read, so that commands given in
## another order, arriving at the same position, are not read twice.
static var smart_engine_table := true
## The longest the engine may think over one command, in thousandths of a
## second; 0 leaves it to the budget of positions alone.
static var smart_engine_ms := 2500
## Whether a draw out of turn, or a card lost to chance, ends the engine's
## knowledge of the cards to come. Off, the cards it was told of stand in for
## the ones that will really be dealt, so that a line is not thought the
## worse merely for passing through chance. Off: knowing nothing past such a
## draw, the engine would not send a creature whose blow costs a card.
static var smart_engine_blind := false
## A turn that ends with no creature sent has no defence phase. Counted as
## one phase it lets a line that holds back be read half a turn further than
## one that attacks, and holding back then looks better than it is; counted
## as two, every line is read the same number of turns ahead.
static var smart_engine_even := true
## Below its first command the engine tries a set of attackers, or of blocks,
## in one order only instead of once for every order it can be named in, and
## reads that much deeper for the same budget.
static var smart_engine_ordered := true
## Below its first command the engine chooses an attack whole, from this many
## of the sets its lookahead ranks best, and a defence whole, from this many
## of its block plans, instead of building either a creature at a time: a
## turn then costs it two commands, not one for every creature, and a board
## full of creatures is read turns ahead. 0 for either builds them singly.
## Off: with four of each it won 55 duels in 100 where building them singly
## won 62 and 57, and thought nearly twice as long.
static var smart_engine_sets := 0
static var smart_engine_plans := 0
## How many phases ahead the engine may read a position small enough to be
## read that far within its budget; 0 keeps to `smart_engine_phases`. Reading
## every position six phases ahead instead costs three times the thinking
## and wins less (57 in 100 against 62 in the first game).
static var smart_engine_reach := 8
## Remake option: before its usual reading the engine looks for a win that
## no defence stops, within this many of its own turns (0 for never). Every
## command of both heroes is read there and nothing is weighed, so what it
## finds is certain, and it is played as found. `smart_engine_prove_share`
## is the part of the budget and of the time, in hundredths, it may take: in
## play nine such wins in ten are found within a hundredth of the budget, and
## where there is none the whole part is spent finding that out. Three parts
## in ten are what the hardest of the kept puzzles need to be won in the
## fewest turns, and cost about an eighth more reading.
static var smart_engine_prove := 4
static var smart_engine_prove_share := 30
## That search gives a line up as soon as the turns it has left could not
## bring the other hero down: a turn is thought to deal at most this many
## hundredths of the damage in sight - the power of the hero's creatures and
## of the creature cards it holds or will draw, and what its spells deal -
## and two points more. Without it most of the search's time goes into
## reading such lines to their end. 0 gives none up; steps of 25.
static var smart_engine_sight := 150
## Remake option: the command the engine chooses is held against the same
## kind of reading for the other hero. One after which that hero wins
## whatever is done, within this many of its turns, is set aside and the
## choice made again among the rest, while there is a command that reading
## does not condemn (0 for never). The engine's usual reading keeps to the
## likeliest commands of a crowded board and to so many commands a line, and
## a loss can lie past either. `smart_engine_guard_share` is the part of the
## budget, in hundredths, each such reading may take.
static var smart_engine_guard := 2
static var smart_engine_guard_share := 10
## What that search has settled in the phase being played, by the turn, the
## phase, the hero to move and the state of chance, which no proof reads
## past: {from (the fewest turns still worth reading: fewer were read whole
## and held no win, and a hero's own commands only narrow what it can do),
## cut (a reading ran out of budget; it is tried again after the next
## command, at a quarter of the cost)}. The duel is not part of the key: a
## command is thought out on a copy of it.
static var _proofs := {}
## A further reading is begun only while less than one part in this many of
## the budget is spent: it costs several times the one before it.
static var smart_engine_spare := 8
## Rounds a played-out duel may run to.
static var smart_engine_rounds := 20
## The positions one command may be thought over. Most commands need far
## fewer; what the budget buys is the further readings of a small position
## (`smart_engine_reach`) and the hard ones read to their end. Played against
## itself, the engine with this budget beat the one with a quarter of it in
## 55 duels of 100 in the first game and 52 in the second, at about three
## times the reading; `smart_engine_ms` still ends any one thought.
static var smart_engine_budget := 8000000
## A phone or a tablet reads a fraction of that, so that the computer's turn
## does not drag or warm the device: a quarter takes a recent handheld a
## third of a second a command on average.
static var smart_engine_mobile := 4

## The positions the engine may play on this device.
static func engine_budget() -> int:
	return maxi(100000, smart_engine_budget / maxi(1, smart_engine_mobile)) if OS.has_feature("mobile") else smart_engine_budget
## Remake option: while the computer is behind, it reads the reply to a move
## as `smart_risk` of the way from the worst the opponent can do to the
## average of the replies it tried, so that a line the opponent must answer
## exactly is worth entering. A hero sure of winning fears every reply; one
## about to lose has nothing to lose by hoping. The weight runs from none at
## an even chance to all of `smart_risk` at a hopeless one. 0 is the
## original's plain worst case.
static var smart_risk := 0.0

## Move flags.
const MOVE_FAILED := 1
const MOVE_NEXT := 2
const MOVE_ATTACK := 4
const MOVE_BLOCK := 8
const MOVE_CAST := 0x10
const MOVE_ABILITY := 0x20
const MOVE_ATTACK_PLAN := 0x40
const MOVE_UNLIKELY := 0x80
## The compiled lookahead's block plan (remake option).
const MOVE_BRAIN_BLOCKS := 0x2000
const MOVE_BLOCK_PLANS := 0x3e00
## Moves tried only after the plain ones of a position.
const MOVE_SECOND_PASS := 0x3e4c
## Line flags: a block plan allows only the next phase after it; one attack
## move per line.
const LINE_ONLY_NEXT := 2
const LINE_ATTACKED := 8

const BLOCK_PLANS := [[0x200, 0.999], [0x400, 0.995], [0x800, 0.997], [0x1000, 0.993]]

## Target-side requirements of hand spells: 1 own creature, 2 enemy creature,
## 4 own hero, 8 enemy hero, 0x10 the chosen enchantment must not be the
## caster's, 0x40 the second chosen enchantment must not be the caster's.
const SPELL_SIDES := {
	"el1": {"AILK": 1, "BLSS": 1, "BRRD": 10, "CLFR": 1, "CLIG": 10, "CLNP": 16, "DISM": 2, "DSIG": 2, "DWND": 2, "ENFL": 2,
		"ERBN": 2, "ETAM": 1, "ETTD": 64, "EXIL": 2, "FAIL": 2, "FLIC": 16, "IRRT": 2, "LSST": 1, "MDNS": 2, "MGHT": 1,
		"OVRL": 1, "PALN": 2, "PRFY": 16, "RDCL": 10, "RDIS": 10, "RDLG": 10, "RIFT": 10, "SCSK": 1, "SGHT": 1, "SHCL": 1,
		"SHSK": 1, "SLRP": 1, "SPBA": 1, "SPBR": 16, "SPRG": 2, "SPWR": 1, "STAT": 1, "STRG": 1, "TGSK": 1, "THIF": 1,
		"UPGD": 1, "WEAK": 2, "WHAS": 64, "WNBL": 1, "ZAPP": 10},
	"el2": {"AILK": 1, "ALNS": 1, "BLSS": 1, "BNSH": 2, "BRRD": 10, "CLFR": 1, "CLIG": 10, "CLNP": 16, "DISM": 2, "DSIG": 2,
		"DWND": 2, "ENBR": 5, "ENFL": 2, "ERBN": 2, "ETAM": 1, "ETTD": 64, "EXIL": 2, "FAIL": 2, "FLIC": 16, "IMMB": 2,
		"IRRT": 2, "LFGR": 5, "LSST": 1, "MDNS": 2, "MGHT": 1, "MNBR": 1, "MNST": 1, "OBLS": 2, "OCLV": 2, "OCRP": 2, "ORFT": 2, "OVRL": 1,
		"PALN": 2, "PRFY": 16, "PRGD": 1, "PRWR": 10, "RDCL": 10, "RDIS": 10, "RDLG": 10, "RIFT": 10, "SCSK": 1, "SGHT": 1,
		"SHCL": 1, "SHSK": 1, "SLRP": 1, "SPBA": 1, "SPBR": 16, "SPRG": 2, "SPWR": 1, "STAT": 1, "STRG": 1, "STSK": 5,
		"TGSK": 1, "THIF": 1, "UPGD": 1, "WEAK": 2, "WHAS": 64, "WNBL": 1, "ZAPP": 10},
}

## Sacrificing creatures' starting priority, before the victim's cost (both games).
const SACRIFICE_PRIOR := {"CTMN": 0.75, "RZMN": 0.85, "SWMN": 0.8}

## Hero enchantment worth: per copy (EACH), once per kind (KIND), and by copy
## count (COUNT, see `_count_value`). Creature enchantments add only COUNT.
const EACH := {
	"el1": {"BASO": 1.0, "BLKD": 1.0, "FRBL": 1.0, "DOMN": 1.0, "ENWO": 1.0, "ENLH": 0.5, "ENVM": -1.0, "IMML": 0.75, "JYHD": 1.0,
		"LSDS": 1.0, "LSHE": 1.0, "MNTX": 1.0, "QKFX": 0.5, "RNST": 1.0, "SPLK": 1.0, "SPWB": 1.0, "STWO": 1.0, "SWSN": -1.0,
		"STTX": -3.0, "WETX": -1.0, "TRLB": -2.0, "TRSN": -1.0},
	"el2": {"QKFX": 0.5, "WETX": -1.0, "STTX": -3.0, "LSDS": 1.0, "MNTX": 1.0, "LSHE": 1.0, "SPWB": 1.0, "TRLB": -2.0, "STWO": 1.0,
		"ENWO": 1.0, "DOMN": 1.0, "ENVM": -1.0, "FRBL": 1.0, "RNST": 1.0, "JYHD": 1.0, "IMML": 0.75, "BLKD": 1.0, "BASO": 1.0,
		"OEXC": 0.75, "PRWT": 0.75, "PRWR": -0.75, "PRBN": 0.75, "PRGD": 0.75, "PLSL": 0.75, "LCWR": 0.75, "GCWR": 0.75,
		"LSWR": 0.75, "GSWR": 0.75, "LEWR": 0.75, "GEWR": 0.75, "OST1": 1.0, "OST2": 1.0, "OST3": 1.0, "TRSN": -1.0,
		"SWSN": -1.1, "WTX2": -1.0},
}
const KIND := {
	"el1": {"ANFR": 2.0, "BROT": 1.0, "CMBN": 1.0, "COPL": 1.0, "CNAR": 1.0, "CRBL": 1.0, "DRFR": 1.5, "DNFR": 1.0, "ENRG": 1.0,
		"ENVM": -1.0, "ETCH": 1.0, "FTDS": 1.0, "FDBK": 1.7, "FLOD": 1.0, "HAST": 1.0, "HOAM": 1.5, "RBRT": 1.0, "SACR": 1.0,
		"SCBR": 1.0, "SPTR": 1.0, "RPST": 1.0, "TRLB": 3.5, "VTLY": 1.0},
	"el2": {"LNRD": 1.0, "ENRG": 1.0, "RBRT": 1.0, "SCBR": 1.0, "RPST": 1.0, "HOAM": 1.5, "CNAR": 1.0, "FLOD": 1.0, "COPL": 1.0,
		"SPTR": 1.0, "FDBK": 1.7, "SACR": 1.0, "TRLB": 3.5, "HAST": 1.0, "VTLY": 1.0, "FTDS": 1.0, "CMBN": 1.0, "ENVM": -1.0,
		"ANFR": 2.0, "DRFR": 1.5, "DNFR": 1.0, "CRBL": 1.0, "ETCH": 1.0, "LFGR": 3.0},
}

## Second-game cutters, sawers and razors: their resting is part of the design.
const SELF_RESTING := ["CTMN", "SWMN", "RZMN"]

class Line:
	var parent: Line
	var depth := 0
	var phases := 0
	var command := {}
	## The command actually sent: a plan's first successful attack or block;
	## and all of the plan's commands in order.
	var sent := {}
	var steps: Array = []
	var budget := -1
	var used := 0
	var prior := -1e6
	var value := 0.0
	var picked := false
	var second_pass := false
	var move := 0
	var flags := 0
	var explored := 0
	var children: Array[Line] = []
	## Remake option: spells and abilities already tried here, by kind.
	var families := {}
	## Remake option: for a first move that only gains ether, the ether the
	## hero held before it (see `smart_idle`).
	var without := -1

class Context:
	var ai := 0
	var w := PackedFloat64Array()
	var limit := 0
	var edition := "el1"
	var second := false
	var registered: Array[Line] = []
	var positions := 0
	## Remake option: the opponent's replies in the lookahead may cast too.
	var replies := false
	var width := 0
	## Auto-combat without "use spells": no artifacts and no spellbook copies
	## that spend charges (the hero's enchantment abilities stay).
	var restricted := false
	## Remake option: see `smart_threat` and `smart_lethal`.
	var threat := 0.0
	var lethal := 0.0
	## Remake option: the compiled lookahead (see `smart_brain_turns`), its
	## creature records and answers of this think, and the fights it played.
	var brain_turns := 0
	var brain_moves := false
	var units := {}
	var asked := {}
	var fights := 0
	var brain_cards := false
	## The engine's search for a certain win (`smart_engine_prove`): the
	## turns it need not read again (see `_proofs`), and its part of the
	## budget when that is not the usual one.
	var prove_from := 0
	var prove_share := 0
	var cards := {}
	## Remake option: see `smart_order` and `smart_foe_health`.
	var orderly := false
	var foe_health := 1.0
	var income := 0.0
	## Remake option: how far a reply is read towards the average rather than
	## the worst (see `smart_risk`).
	var hope := 0.0
	## Remake option: creature worths of this think (see `side_value`).
	var remember := false
	var worths := {}
	## For tools: the first moves tried, with their worth (see `think`).
	var tracing := false
	var trace: Array = []
	var offered := 0
	var untried: Array = []

## The opponent's next command for the acting side, as a command dictionary
## (see `apply`). `stats`, when given, receives the number of positions; with
## a "trace" entry it also receives every first move tried, as {command,
## prior, value, positions}, the number of first moves there were ("offered")
## and the commands of those the budget did not reach ("untried").
static func think(duel: ELDuel, stats: Dictionary = {}, restricted := false) -> Dictionary:
	if duel.phase == ELDuel.Phase.FINISHED:
		if duel.scripts != null and duel.scripts.search_only: duel.scripts.close()
		return {}
	var ctx := Context.new()
	ctx.restricted = restricted
	ctx.ai = duel.active_side()
	ctx.edition = duel.profile.id
	ctx.second = ctx.edition == "el2"
	var smart := duel.smart_sides.has(ctx.ai)
	if smart and smart_follow and not stats.has("trace"):
		var planned := _recall(duel)
		if not planned.is_empty():
			stats.positions = 0
			stats.fights = 0
			return planned
	ctx.w = chosen_weights(ctx.second) if smart and smart_steady else weights(duel.rng_state, ctx.second)
	ctx.limit = (1 if duel.phase == ELDuel.Phase.ATTACK else 0) + (smart_phases if smart else 0)
	var root := Line.new()
	root.budget = smart_budget if smart else original_budget
	ctx.replies = smart and smart_replies
	ctx.width = smart_width if smart else 0
	if smart:
		ctx.remember = true
		ctx.orderly = smart_order
		ctx.foe_health = smart_foe_health
		ctx.income = smart_income if ctx.second else 0.0
		if smart_risk > 0.0: ctx.hope = smart_risk * clampf((0.5 - win_chance(ctx, duel, ctx.ai)) * 2.0, 0.0, 1.0)
		ctx.threat = smart_threat
		ctx.lethal = smart_lethal
		if ELCombatBrain.available:
			ctx.brain_turns = smart_brain_turns
			ctx.brain_moves = smart_brain_moves
			ctx.brain_cards = smart_brain_cards
		elif smart_threat <= 0.0 and smart_lethal <= 0.0:
			# Without the library (the browser version) the coming attack is
			# estimated from the armies as they stand.
			ctx.threat = FALLBACK_THREAT
			ctx.lethal = FALLBACK_LETHAL
	ctx.tracing = stats.has("trace")
	if smart and smart_engine and ELCombatBrain.available:
		var proof_key := hash([duel.turn_serial, duel.phase, ctx.ai, duel.rng_state, duel.round_number, engine_budget(), smart_engine_prove, smart_engine_prove_share])
		_plans_lock.lock()
		var settled: Dictionary = _proofs.get(proof_key, {})
		_plans_lock.unlock()
		if not settled.is_empty():
			ctx.prove_from = int(settled.from)
			if settled.cut: ctx.prove_share = maxi(1, smart_engine_prove_share / 4)
		var found := ELCombatBrain.gamble(ctx, duel, smart_engine_rounds, engine_budget()) if smart_engine_rollouts 			else ELCombatBrain.choose(ctx, duel, smart_engine_phases, engine_budget(), smart_engine_steps, smart_engine_width)
		if smart_engine_prove > 0 and not smart_engine_rollouts and not found.is_empty() and int(found.get("proven", 0)) == 0:
			_plans_lock.lock()
			if _proofs.size() > 256: _proofs.clear()
			_proofs[proof_key] = {"from": maxi(ctx.prove_from, int(found.get("settled", 0)) + 1), "cut": int(found.get("cut", 0)) != 0}
			_plans_lock.unlock()
		# What follows asks the engine about other positions.
		ctx.prove_from = 0
		ctx.prove_share = 0
		# Measuring aid: how far the engine read, and whether its budget ran out.
		stats.far = int(found.get("far", 0))
		stats.depth = int(found.get("depth", 0))
		stats.guarded = int(found.get("guarded", 0))
		stats.cut = bool(found.get("aborted", false))
		# A spell the original would not think of casting here - at that
		# target, at that moment - is passed over for the engine's best
		# command that it would.
		# A win read to its end is played as it was read.
		if int(found.get("proven", 0)) > 0:
			stats.positions = int(found.get("positions", 0))
			stats.fights = 0
			stats.value = float(found.value)
			stats.proven = int(found.proven)
			var won: Array = found.get("line", [])
			if smart_follow and won.size() > 1: _remember(duel, won)
			return found.command
		if smart_engine_likely and not smart_engine_rollouts and not found.is_empty() and _unlikely(ctx, duel, found.command):
			var better := {}
			for item: Dictionary in ELCombatBrain.weigh(ctx, duel, smart_engine_phases, engine_budget() * 2, smart_engine_steps):
				if item.command.is_empty() or _unlikely(ctx, duel, item.command): continue
				if better.is_empty() or float(item.value) > float(better.value): better = item
			stats.unlikely = int(stats.get("unlikely", 0)) + 1
			if not better.is_empty(): found = {"command": better.command, "value": better.value, "positions": found.get("positions", 0)}
		# An ether spell that nothing in the line after it needs stays in the
		# hand, and the line goes on without it.
		if smart_idle and not smart_engine_rollouts and not found.is_empty():
			var instead := _unneeded(duel, found)
			if not instead.is_empty(): found = instead
		# Measuring aid: the engine's whole line as it gave it, for a caller
		# that asks for it.
		if stats.has("line"): stats.line = found.get("raw", PackedInt32Array())
		var beyond := _beyond(ctx, duel, found) if smart_engine_beyond > 0 and not smart_engine_rollouts else {}
		# Measuring aid: a class of the engine's decisions is handed back to
		# the search, to see how much of the difference between them it holds.
		if smart_engine_defer != 0:
			var chosen: Dictionary = beyond.command if not beyond.is_empty() else found.get("command", {})
			if chosen.is_empty() or smart_engine_defer & _decision_class(duel, ctx.ai, chosen):
				beyond = {}
				found = {}
		if not beyond.is_empty():
			stats.positions = int(beyond.positions) + int(found.get("positions", 0))
			stats.fights = 0
			stats.value = float(beyond.value)
			return beyond.command
		if not found.is_empty():
			stats.positions = int(found.get("positions", found.get("games", 0)))
			stats.fights = 0
			stats.value = float(found.get("value", found.get("share", 0.0)))
			var line: Array = found.get("line", [])
			if smart_follow and line.size() > 1: _remember(duel, line)
			return found.command
	var start := duel.search_copy(ctx.second)
	if ctx.second: start.spec_expect = ELSpecs.sample_expectation(duel)
	_search(ctx, root, start)
	if ctx.tracing:
		stats.trace = ctx.trace
		stats.offered = ctx.offered
		stats.untried = ctx.untried
	# The lookahead script layer lives for one think.
	if start.scripts != null and start.scripts.search_only: start.scripts.close()
	stats.positions = ctx.positions
	stats.fights = ctx.fights
	var best: Line = null
	# Root moves set aside: an ether spell whose line never uses the ether (a
	# hand over five loses the card at the end of the turn anyway), and a
	# spell that gains too little to be worth the card.
	var rejected: Array[Line] = []
	for attempt in 3:
		best = null
		var leaf: Line = null
		var runner := -1e9
		for line: Line in ctx.registered:
			var first := line
			while first.parent != null and first.parent.parent != null: first = first.parent
			if rejected.has(first): continue
			if leaf == null or line.value > leaf.value:
				if leaf != null and best != first: runner = maxf(runner, leaf.value)
				leaf = line
				best = first
			elif best != first: runner = maxf(runner, line.value)
		if best == null: return {"kind": "end_phase"}
		if attempt < 2 and smart and best.without >= 0 and duel.heroes[ctx.ai].hand.size() <= 5 and not _needs(duel, leaf, best):
			rejected.append(best)
			continue
		if attempt < 2 and smart and smart_margin > 0.0 and runner > -1e8 and leaf.value - runner < smart_margin and _minor(duel, ctx.ai, best):
			rejected.append(best)
			continue
		break
	if smart and smart_second > 0.0 and ELCombatBrain.available: best = _second_opinion(ctx, duel, best, rejected)
	stats.value = best.value
	if smart and smart_follow and best.steps.size() > 1: _remember(duel, best.steps)
	return best.sent if not best.sent.is_empty() else best.command

## Remake option (`smart_second`): the compiled engine's opinion of the first
## moves the search likes best. The search reads few positions with the
## duel's own rules and the original's judgement of what is worth trying; the
## engine reads tens of thousands, knowing both hands and the cards both
## heroes will draw. Each of the search's leading moves is played on a copy
## and the engine reads on from there; its worth, weighted, is added to the
## search's own, and the move that leads on both counts is the one played.
static func _second_opinion(ctx: Context, duel: ELDuel, best: Line, rejected: Array[Line]) -> Line:
	var leading := {}
	for line: Line in ctx.registered:
		var first := line
		while first.parent != null and first.parent.parent != null: first = first.parent
		if rejected.has(first): continue
		if not leading.has(first) or line.value > float(leading[first]): leading[first] = line.value
	if leading.size() < 2 or not leading.has(best): return best
	var top := float(leading[best])
	var firsts: Array = leading.keys().filter(func(first: Line) -> bool: return top - float(leading[first]) <= smart_second_within)
	if firsts.size() < 2: return best
	firsts.sort_custom(func(a: Line, b: Line) -> bool: return float(leading[a]) > float(leading[b]))
	firsts = firsts.slice(0, smart_second_moves)
	var chosen := best
	var chosen_score := -1e18
	var share := maxi(2000, engine_budget() / firsts.size())
	for first: Line in firsts:
		var copy := duel.search_copy(ctx.second)
		var steps: Array = first.steps if not first.steps.is_empty() else [first.sent if not first.sent.is_empty() else first.command]
		var played := true
		for step: Dictionary in steps:
			if not apply(copy, step):
				played = false
				break
		var opinion := 0.0
		var known := false
		if played:
			if copy.phase == ELDuel.Phase.FINISHED:
				opinion = 1e4 if copy.winner == ctx.ai else -1e4
				known = true
			else:
				var after := ELCombatBrain.choose(ctx, copy, smart_engine_phases, share, smart_engine_steps, smart_engine_width)
				if not after.is_empty():
					opinion = float(after.value)
					known = true
		if copy.scripts != null and copy.scripts.search_only: copy.scripts.close()
		# Without the engine's word on every one of them the search stands.
		if not known: return best
		var score := float(leading[first]) + smart_second * opinion
		if score > chosen_score:
			chosen_score = score
			chosen = first
	return chosen

## Remake option (`smart_margin`): a first move that spends the last use of a
## spell that summons no creature.
static func _minor(duel: ELDuel, side: int, line: Line) -> bool:
	if String(line.command.get("kind", "")) != "cast": return false
	if duel.profile.table("CombatCreatures").has(String(line.command.card)): return false
	var hero: Dictionary = duel.heroes[side]
	var index := int(line.command.get("index", -1))
	if index < 0 or index >= hero.hand_slots.size(): return false
	var slot := int(hero.hand_slots[index])
	# An unlimited slot (-1 uses, first-game runes) is never the last.
	return slot >= 0 and slot < hero.spell_uses.size() and int(hero.spell_uses[slot]) == 1

## Whether a spell is one the original's own reckoning of spells and their
## targets rules out here. Only spells are judged: its reckoning of attacks
## and blocks belongs to its one-turn look, which the engine replaces.
static func _unlikely(ctx: Context, duel: ELDuel, command: Dictionary) -> bool:
	if String(command.get("kind", "")) != "cast": return false
	var card := String(command.get("card", ""))
	if card.is_empty(): return false
	return _spell_prior(ctx, duel, ctx.ai, card, int(command.get("target", -1)), int(command.get("grave", -1)), int(command.get("power", 0))) < THRESHOLD

## Remake option (`smart_idle`): the command the engine's line goes on to
## when the ether spell at its head pays for nothing in it - every card and
## attack that follows in the turn was within the ether the hero held before
## the spell. Read to different depths, a line with the spell and one without
## come out a hair apart either way, and the engine then burns the card for
## nothing. Empty when the spell is needed, when the line is not known to the
## end of the phase, or when ether left over has a use: an army that can
## regenerate spends it through the other hero's turn, and the price of an
## ability is not known here.
static func _unneeded(duel: ELDuel, found: Dictionary) -> Dictionary:
	var command: Dictionary = found.get("command", {})
	if String(command.get("kind", "")) != "cast": return {}
	if String(ELCatalog.rule(duel.profile, String(command.get("card", ""))).get("effect", "")) != "mana": return {}
	var side := duel.active_side()
	for c: Dictionary in duel.army(side):
		if duel.regeneration_cost(c.id) > 0: return {}
	var raw: PackedInt32Array = found.get("raw", PackedInt32Array())
	var count := int(raw[8]) if raw.size() > 8 else 0
	var hand: Array = duel.heroes[side].hand
	var left := duel.available_mana(side)
	var tax := duel.global_enchantment_count("LSDS")
	var ids: Array = duel.creatures.keys()
	var next := {}
	for i in range(1, count):
		var at := 9 + i * 4
		if at + 3 >= raw.size(): return {}
		var kind := int(raw[at])
		var price := 0
		if kind == 0:
			# The phase ends with everything paid for.
			if next.is_empty(): next = {"kind": "end_phase"}
			return {"command": next, "line": [next], "value": found.get("value", 0.0), "positions": found.get("positions", 0), "raw": raw}
		elif kind == 1: price = tax
		elif kind == 5:
			var mask := (int(raw[at + 1]) & 0xffff) | (int(raw[at + 2]) << 16)
			for k in ids.size():
				if mask & (1 << k) and not duel.attacks.has(int(ids[k])): price += tax
		elif kind == 3:
			var slot := int(raw[at + 1])
			if slot < 0 or slot >= mini(hand.size(), ELCombatBrain.HAND): return {}
			var rule := ELCatalog.rule(duel.profile, String(hand[slot]))
			# A second ether spell changes what the rest can cost.
			if String(rule.get("effect", "")) == "mana": return {}
			price = duel.cost(String(hand[slot])) + (int(raw[at + 3]) if rule.get("x_source", "") != "health" else 0)
		else: return {}
		if price > left: return {}
		left -= price
		if next.is_empty():
			# Only a command that can be handed over as it stands.
			if kind == 5: return {}
			next = ELCombatBrain._command_of(duel, ids, kind, int(raw[at + 1]), int(raw[at + 2]), int(raw[at + 3]))
			if String(next.get("kind", "end_phase")) == "end_phase": return {}
	return {}

## The class of a decision, as a bit: 1 summoning, 2 enchanting, 4 any other
## spell, 8 sending an attacker, 16 ending the attack, 32 anything in defence,
## 64 an ability.
static func _decision_class(duel: ELDuel, side: int, command: Dictionary) -> int:
	if duel.phase != ELDuel.Phase.ATTACK: return 32
	match String(command.get("kind", "")):
		"cast":
			var hand: Array = duel.heroes[side].hand
			var index := int(command.get("index", -1))
			if index < 0 or index >= hand.size(): return 4
			var effect := String(ELCatalog.rule(duel.profile, String(hand[index])).get("effect", ""))
			return 1 if effect == "summon" else (2 if effect == "enchant" else 4)
		"attack": return 8
		"ability": return 64
	return 16

## Remake option (`smart_engine_beyond`): the spells and abilities the
## compiled engine holds no rule for - reviving, unsummoning, enchanting a hero
## or an army, a creature's own ability - tried here by the duel's own rules.
## The engine then reads the position each one leaves, and the best of them is
## played when that beats the best command the engine found by itself. Without
## this the engine ends its turn holding the very cards the search would play.
static func _beyond(ctx: Context, duel: ELDuel, found: Dictionary) -> Dictionary:
	var root := Line.new()
	var asked := ctx.brain_moves
	ctx.brain_moves = false
	_generate(ctx, root, duel)
	ctx.brain_moves = asked
	var hand: Array = duel.heroes[ctx.ai].hand
	var extra: Array[Line] = []
	for child: Line in root.children:
		# What the original would not think of doing here is not tried: its
		# reckoning knows when a spell has nothing to work on.
		if child.move & MOVE_UNLIKELY: continue
		var kind := String(child.command.get("kind", ""))
		if kind == "cast":
			var index := int(child.command.get("index", -1))
			if index < 0 or index >= hand.size(): continue
			var card := String(hand[index])
			var record: Variant = ctx.cards.get(card)
			if record == null:
				record = ELCombatBrain._card(ctx, duel, card)
				ctx.cards[card] = record
			if not record.is_empty(): continue
		elif kind == "ability":
			# What the engine plays itself it has already weighed.
			if ELCombatBrain.plays_ability(duel, child.command, ctx): continue
		else: continue
		extra.append(child)
	if extra.is_empty(): return {}
	extra.sort_custom(func(a: Line, b: Line) -> bool: return a.prior > b.prior)
	var best := {}
	var strict := float(found.get("value", -1e9)) + smart_engine_beyond_margin
	var best_value := strict
	# Where the engine would only end the phase, such a card need not look
	# better, only no worse than the card it costs: what a standing
	# enchantment is worth is just what the engine cannot see, and ether left
	# unspent is lost.
	if not found.is_empty() and String(found.command.get("kind", "")) == "end_phase":
		best_value = float(found.value) - smart_engine_beyond_idle
	var here := _position(duel)
	var positions := 0
	var share := maxi(2000, engine_budget() / 4)
	for i in mini(extra.size(), smart_engine_beyond):
		var copy := duel.search_copy(ctx.second)
		var value := -1e9
		# A spell that did nothing but spend its card is never worth it, and
		# one that only gained ether must earn its place like any command.
		var spent := 1
		if apply(copy, extra[i].command) and _position(copy) != here: spent = _spent(duel, copy, extra[i])
		if spent != 1:
			if copy.phase == ELDuel.Phase.FINISHED: value = 1e6 if copy.winner == ctx.ai else -1e6
			else:
				var after := ELCombatBrain.choose(ctx, copy, smart_engine_phases, share, maxi(2, smart_engine_steps - 1), smart_engine_width)
				if not after.is_empty():
					value = float(after.value)
					positions += int(after.get("positions", 0))
		if copy.scripts != null and copy.scripts.search_only: copy.scripts.close()
		if spent == 2 and value <= strict: continue
		if value > best_value:
			best_value = value
			best = {"command": extra[i].command, "value": value}
	if best.is_empty(): return {}
	best.positions = positions
	return best

## Remake option (`smart_follow`): the commands that follow a chosen plan, by
## the position each is to be sent from.
static var _plans := {}
static var _plans_lock := Mutex.new()

## Forgets every kept plan and proof, for a fresh attempt (a puzzle, a check).
static func reset_caches() -> void:
	_plans_lock.lock()
	_proofs.clear()
	_plans.clear()
	_plans_lock.unlock()

static func _position(d: ELDuel) -> int:
	return hash([d.phase, d.attacker, d.round_number, d.attacks, d.blocks, d.creatures, d.heroes])

static func _remember(duel: ELDuel, steps: Array) -> void:
	var copy := duel.search_copy()
	_plans_lock.lock()
	if _plans.size() > 256: _plans.clear()
	# A step is kept only once the rules have taken it from the position it
	# is to be sent from: a line read ahead can name a command the duel will
	# refuse by then, such as sending a creature that had to attack anyway.
	for i in steps.size():
		var from := _position(copy)
		if not apply(copy, steps[i]): break
		if i > 0: _plans[from] = steps[i]
	_plans_lock.unlock()
	if copy.scripts != null and copy.scripts.search_only: copy.scripts.close()

static func _recall(duel: ELDuel) -> Dictionary:
	_plans_lock.lock()
	var planned: Dictionary = _plans.get(_position(duel), {})
	_plans_lock.unlock()
	return planned

## Sends a command to the duel; false when the rules refuse it.
static func apply(d: ELDuel, command: Dictionary) -> bool:
	match String(command.get("kind", "")):
		"end_phase": return d.end_phase()
		"cast": return d.cast(int(command.index), int(command.target), int(command.grave), int(command.power))
		"ability": return d.use_ability(int(command.id), String(command.key), int(command.target), int(command.choice), int(command.amount))
		"attack": return d.toggle_attack(int(command.id))
		"block": return d.assign_block(int(command.id), int(command.target))
	return false

## The nine evaluation weights for one think, drawn from a copy of the battle's
## random state (the battle itself does not advance).
static func weights(state: int, second: bool) -> PackedFloat64Array:
	var ranges := _ranges(second)
	var result := PackedFloat64Array()
	var x := state & 0xffffffff
	for r: Array in ranges:
		x = (x * 0x343fd + 0x269ec3) & 0xffffffff
		var t := float(((x >> 16) & 0x7fff) % 1000) * 0.001
		result.append(float(r[0]) + t * (float(r[1]) - float(r[0])) + float(r[2]))
	return result

static func _ranges(second: bool) -> Array:
	var ranges := [[-0.1, 0.5, 0.3], [-0.05, 0.0, -0.01], [-0.1, 0.3, 1.5], [0.0, 1.0, 1.5], [-0.1, 0.1, 0.8],
		[-0.1, 0.1, 0.6], [-0.1, 0.1, 1.2], [0.0, 0.2, 0.3], [-0.1, 0.1, 0.8]]
	if not second:
		ranges[3] = [0.0, 1.5, 1.5]
		ranges[7] = [0.0, 0.5, 0.1]
	return ranges

## The middle of each weight's range (remake option).
static func steady_weights(second: bool) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for r: Array in _ranges(second): result.append(float(r[0]) + 0.5 * (float(r[1]) - float(r[0])) + float(r[2]))
	return result

static func _search(ctx: Context, line: Line, before: ELDuel) -> bool:
	var s := before
	if line.parent != null:
		s = before.search_copy()
		if not _execute(ctx, line, s): return false
		if ctx.orderly and smart_idle and line.depth == 1 and line.move & (MOVE_CAST | MOVE_ABILITY):
			var spent := _spent(before, s, line)
			if spent == 1: return _fail(line)
			if spent == 2: line.without = int(before.heroes[before.active_side()].mana)
	ctx.positions += 1
	var finished := s.phase == ELDuel.Phase.FINISHED
	var maximise := s.active_side() == ctx.ai
	line.value = -1e6 if maximise else 1e6
	var total := 0.0
	var tried := 0
	if line.parent != null and line.parent.phases == 0 and (line.move & MOVE_NEXT or finished): ctx.registered.append(line)
	if line.phases > ctx.limit or finished:
		line.value = _leaf(ctx, line, s)
		return true
	_generate(ctx, line, s)
	while true:
		var child := _pick_orderly(line) if ctx.orderly else _pick(line)
		if child == null: break
		if not _allot(line, child, ctx.width): break
		var ok := _search(ctx, child, s)
		line.used += child.used
		if ctx.tracing and line.parent == null and ok:
			ctx.trace.append({"command": child.sent if not child.sent.is_empty() else child.command, "plan": child.command, "prior": child.prior, "value": child.value, "positions": child.used})
		if ok:
			line.explored += 1
			line.value = maxf(line.value, child.value) if maximise else minf(line.value, child.value)
			total += child.value
			tried += 1
	# A reply the computer has little left to lose by chancing (`smart_risk`).
	if not maximise and tried > 1 and ctx.hope > 0.0:
		line.value += (total / float(tried) - line.value) * ctx.hope
	if ctx.tracing and line.parent == null:
		ctx.offered = line.children.size()
		for c: Line in line.children:
			if not c.picked and c.prior >= THRESHOLD: ctx.untried.append(c.command)
	# Lines keep only their parent link once searched (no reference cycles).
	line.children.clear()
	return true

static func _execute(ctx: Context, line: Line, s: ELDuel) -> bool:
	if line.move & (MOVE_ATTACK | MOVE_ATTACK_PLAN):
		if line.flags & LINE_ATTACKED: return _fail(line)
		line.flags |= LINE_ATTACKED
		if line.move & MOVE_ATTACK_PLAN:
			if line.command.kind == "attack_set": return _attack_set(line, s) or _fail(line)
			return _attack_plan(ctx, line, s) or _fail(line)
	elif line.move & MOVE_BLOCK_PLANS:
		if line.flags & LINE_ONLY_NEXT: return _fail(line)
		line.flags |= LINE_ONLY_NEXT
		if line.move & MOVE_BRAIN_BLOCKS: return _block_set(line, s) or _fail(line)
		return _block_plan(ctx, line, s) or _fail(line)
	if line.move & MOVE_NEXT and s.phase == ELDuel.Phase.ATTACK and s.attacks.is_empty(): line.phases += 1
	line.used += 1
	return apply(s, line.command) or _fail(line)

static func _fail(line: Line) -> bool:
	line.move |= MOVE_FAILED
	return false

## Highest priority first among the untried moves (the first wins a tie); plans
## and attacks come after the plain moves of the same position.
static func _pick(line: Line) -> Line:
	for pass_index in [0, 1]:
		if pass_index == 0 and line.second_pass: continue
		var best: Line = null
		for c: Line in line.children:
			if c.picked or c.move & MOVE_FAILED or c.prior < THRESHOLD: continue
			if line.flags & LINE_ONLY_NEXT and not c.move & MOVE_NEXT: continue
			if line.flags & LINE_ATTACKED and c.move & (MOVE_ATTACK | MOVE_ATTACK_PLAN): continue
			if bool(c.move & MOVE_SECOND_PASS) != (pass_index == 1): continue
			if best == null or c.prior > best.prior: best = c
		if best != null:
			best.picked = true
			return best
		line.second_pass = true
	return null

## Remake option (`smart_order`): the highest rank first among the untried
## moves. Ending the phase, then the plans, then spells and abilities, then
## lone attackers; within a group the higher priority, a spell or ability
## already tried in other forms giving way.
static func _pick_orderly(line: Line) -> Line:
	var best: Line = null
	var top := -1.0
	var kind := ""
	for c: Line in line.children:
		if c.picked or c.move & MOVE_FAILED or c.prior < THRESHOLD: continue
		if line.flags & LINE_ONLY_NEXT and not c.move & MOVE_NEXT: continue
		if line.flags & LINE_ATTACKED and c.move & (MOVE_ATTACK | MOVE_ATTACK_PLAN): continue
		var rank := c.prior
		var family := ""
		if c.move & MOVE_NEXT: rank += 6.0
		elif c.move & (MOVE_ATTACK_PLAN | MOVE_BLOCK_PLANS): rank += 4.0
		elif c.move & MOVE_ATTACK: rank = minf(rank, 0.99)
		else:
			family = "%s %s %s" % [c.command.kind, c.command.get("card", c.command.get("key", "")), c.command.get("id", "")]
			rank = 2.0 + rank * pow(smart_family, float(line.families.get(family, 0)))
		if rank > top:
			best = c
			top = rank
			kind = family
	if best == null: return null
	best.picked = true
	if not kind.is_empty(): line.families[kind] = int(line.families.get(kind, 0)) + 1
	return best

## Remake option (`smart_idle`): what the spell or ability of `line` did from
## `before` to `after` beyond spending the caster's card and ether: 0
## something, 1 nothing, 2 nothing but ether gained.
static func _spent(before: ELDuel, after: ELDuel, line: Line) -> int:
	if after.phase != before.phase or after.creatures.hash() != before.creatures.hash() or after.attacks != before.attacks or after.blocks.hash() != before.blocks.hash(): return 0
	var side := before.active_side()
	if after.heroes[1 - side].hash() != before.heroes[1 - side].hash(): return 0
	var was: Dictionary = before.heroes[side]
	var now: Dictionary = after.heroes[side]
	var card := String(line.command.get("card", "")) if line.command.kind == "cast" else ""
	for key: String in ["hand", "grave"]:
		var held: Array = now[key].duplicate()
		var had: Array = was[key].duplicate()
		if not card.is_empty():
			if key == "hand": held.append(card)
			elif held.size() > had.size(): had.append(card)
		held.sort()
		had.sort()
		if held != had: return 0
	for key: String in was:
		if key in IDLE_KEYS: continue
		if not now.has(key) or hash(now[key]) != hash(was[key]): return 0
	return 2 if int(now.mana) > int(was.mana) else 1

## Remake option (`smart_idle`): whether the line ending in `leaf` goes on,
## after the ether spell `top`, to a play that the ether there was before the
## spell would not have paid for. Refunds are left out, and an ability, whose
## price is not known here, counts as needing it. So does an army that can
## regenerate: ether left over pays for that through the other hero's turn.
static func _needs(duel: ELDuel, leaf: Line, top: Line) -> bool:
	for c: Dictionary in duel.army(duel.active_side()):
		if duel.regeneration_cost(c.id) > 0: return true
	var plays: Array[Line] = []
	var at := leaf
	while at != null and at != top:
		plays.push_front(at)
		at = at.parent
	var left := top.without
	var tax := duel.global_enchantment_count("LSDS")
	for play: Line in plays:
		var price := 0
		match String(play.command.get("kind", "")):
			"cast":
				var card := String(play.command.card)
				price = duel.cost(card) + (int(play.command.power) if ELCatalog.rule(duel.profile, card).get("x_source", "") != "health" else 0)
			"attack": price = tax
			"attack_set", "attack_plan": price = tax * play.steps.size()
			"ability": return true
		if price > left: return true
		left -= price
	return false

## Shares the position budget: up to a fifth per root move, then half for the
## first reply and a third for later ones; deeper positions try fewer replies.
static func _allot(line: Line, child: Line, width := 0) -> bool:
	var d := line.depth
	var e := line.explored
	if width > 0:
		if (d > 0 and e >= width) or (d > 4 and e >= maxi(2, width / 2)) or (d > 9 and e > 0): return false
	elif (d > 0 and e > 2) or (d > 4 and e > 1) or (d > 9 and e > 0): return false
	var share := line.budget / 5 if d == 0 else (line.budget / 3 if e != 0 else line.budget / 2)
	child.budget = maxi(0, mini(share, line.budget - line.used))
	return child.budget > 0 or (e < 2 and d < 20)

static func _add(line: Line, command: Dictionary, prior: float, move: int) -> Line:
	var c := Line.new()
	c.parent = line
	c.depth = line.depth + 1
	c.phases = line.phases + (1 if move & MOVE_NEXT else 0)
	c.flags = line.flags
	c.command = command
	c.prior = prior
	c.move = move | (MOVE_UNLIKELY if prior < THRESHOLD else 0)
	line.children.append(c)
	return c

static func _generate(ctx: Context, line: Line, s: ELDuel) -> void:
	var side := s.active_side()
	_add(line, {"kind": "end_phase"}, 1.1, MOVE_NEXT)
	var restricted := ctx.restricted and side == ctx.ai
	if side == ctx.ai or ctx.replies:
		_casts(ctx, line, s, side)
		if not restricted: _artifacts(ctx, line, s, side)
	# Restricted (auto-combat without runes) skips only the artifacts above; the
	# hero's enchantment abilities are still used (original EL1/EL2 thinks).
	for ability: Dictionary in s.abilities(side):
		if ability.effect == "artifact" or not s.can_use_ability(side, ability.key): continue
		_ability_moves(ctx, line, s, side, side, ability)
	var army := s.army(side)
	if s.phase == ELDuel.Phase.ATTACK:
		for c: Dictionary in army:
			if _free(s, c) and not s.has_flag(c.id, "NoAttack"):
				_add(line, {"kind": "attack_plan"}, 1.0, MOVE_ATTACK_PLAN)
				break
	elif not s.attacks.is_empty() and not army.is_empty():
		for plan: Array in BLOCK_PLANS: _add(line, {"kind": "block_plan", "plan": plan[0]}, plan[1], plan[0])
	# The attackers the lookahead chose, when it is asked and `smart_set_only`.
	var only := {}
	if ctx.brain_moves and not army.is_empty() and not (line.flags & (LINE_ATTACKED | LINE_ONLY_NEXT)): only = _brain_moves(ctx, line, s)
	for c: Dictionary in army:
		if not s.creatures.has(c.id): continue
		for ability: Dictionary in s.abilities(c.id):
			if s.can_use_ability(c.id, ability.key): _ability_moves(ctx, line, s, side, c.id, ability)
		if s.phase == ELDuel.Phase.ATTACK and _free(s, c) and int(c.power) > 0:
			if only.has("set") and not only.set.has(int(c.id)): continue
			_add(line, {"kind": "attack", "id": c.id}, _attack_prior(s, c), MOVE_ATTACK)

## Remake option: the attackers or the blocks the compiled lookahead finds best
## join the moves; the move being chosen is looked for deeper than the replies.
## Returns `{"set": [ids]}` with the attack it chose (`smart_set_only`).
static func _brain_moves(ctx: Context, line: Line, s: ELDuel) -> Dictionary:
	var attacking := s.phase == ELDuel.Phase.ATTACK
	if not attacking and s.attacks.is_empty(): return {}
	var root := line.depth == 0
	var answer := ELCombatBrain.ask(ctx, s, smart_brain_move_turns if root else maxi(1, ctx.brain_turns), smart_brain_move_budget if root else smart_brain_budget, root)
	if answer.is_empty(): return {}
	if not attacking:
		if not answer.ids.is_empty(): _add(line, {"kind": "block_set", "pairs": answer.ids}, 0.9995, MOVE_BRAIN_BLOCKS)
		return {}
	var ids: Array[int] = []
	for id: int in answer.ids:
		if not s.attacks.has(id): ids.append(id)
	if not ids.is_empty(): _add(line, {"kind": "attack_set", "ids": ids}, 1.05, MOVE_ATTACK_PLAN)
	# A win or loss it already sees is no advice on what to send.
	if not smart_set_only or not root or int(answer.status) != 0: return {}
	var chosen: Array[int] = []
	chosen.assign(answer.ids)
	for id: int in s.attacks:
		if not chosen.has(id): chosen.append(id)
	return {"set": chosen}

static func _attack_set(line: Line, s: ELDuel) -> bool:
	for id: int in line.command.ids:
		line.used += 1
		if s.creatures.has(id) and not s.attacks.has(id) and s.toggle_attack(id):
			line.steps.append({"kind": "attack", "id": id})
			if line.sent.is_empty(): line.sent = line.steps[0]
	return not line.sent.is_empty()

static func _block_set(line: Line, s: ELDuel) -> bool:
	var pairs: Array = line.command.pairs
	line.used += 2
	for i in range(0, pairs.size() - 1, 2):
		if s.blocks.get(int(pairs[i]), -1) == int(pairs[i + 1]): continue
		_block_now(line, s, int(pairs[i]), int(pairs[i + 1]))
	return not line.sent.is_empty()

## Ready, rested and not yet in combat.
static func _free(s: ELDuel, c: Dictionary) -> bool:
	return not c.resting and not c.sick and not s.attacks.has(c.id) and not s.blocks.has(c.id)

# --- Hand spells and artifacts ------------------------------------------------

static func _casts(ctx: Context, line: Line, s: ELDuel, side: int) -> void:
	var hero: Dictionary = s.heroes[side]
	var seen := {}
	# Both originals keep the hand newest card first (the add-card path inserts
	# at the list head), so equal priors are tried, and ties kept, from the
	# newest card; a repeated card is generated from its newest copy.
	for i in range(hero.hand.size() - 1, -1, -1):
		var card: String = hero.hand[i]
		if ctx.restricted and i < hero.hand_slots.size() and int(hero.hand_slots[i]) >= 0: continue
		if seen.has(card): continue
		seen[card] = true
		if s.cost(card) > s.available_mana(side): continue
		if not s.phase_allows(card): continue
		if card == "STSI":
			var prior := _stasis_prior(s, side, card)
			_add(line, {"kind": "cast", "index": i, "card": card, "target": -1, "grave": -1, "power": 0}, prior, MOVE_CAST)
			continue
		var rule := ELCatalog.rule(s.profile, card)
		if rule.is_empty(): continue
		var effect := String(rule.get("effect", ""))
		var powers: Array[int] = [0]
		if s.variable_power(card):
			powers = []
			if rule.get("x_source") == "health":
				for x in s.maximum_power(card) + 1: powers.append(x)
			else:
				for x in range(s.maximum_power(card), -1, -1): powers.append(x)
		var targets: Array[int] = [-1]
		if s.target_kind(card) != "none": targets = _ordered(s, s.valid_targets(card))
		for power: int in powers:
			for target: int in targets:
				for grave: int in _spell_choices(s, card, effect, target):
					var prior := _spell_prior(ctx, s, side, card, target, grave, power)
					_add(line, {"kind": "cast", "index": i, "card": card, "target": target, "grave": grave, "power": power}, prior, MOVE_CAST)

static func _spell_choices(s: ELDuel, card: String, effect: String, target: int) -> Array:
	match effect:
		"exchange", "pale_revival": return s.valid_grave_targets(card)
		"reanimate", "repair": return s.valid_grave_targets(card, target)
		"dispel", "trade": return s.valid_enchantment_targets(card, target)
		"swap": return s.swap_targets(card, target)
	return [-1]

## Heroes first, then creatures in play order.
static func _ordered(s: ELDuel, ids: Array) -> Array[int]:
	var result: Array[int] = []
	for id: int in [0, 1]:
		if ids.has(id): result.append(id)
	for id: int in s.creatures:
		if ids.has(id): result.append(id)
	return result

static func _artifacts(ctx: Context, line: Line, s: ELDuel, side: int) -> void:
	var items: Array = s.heroes[side].get("artifacts", [])
	for index in items.size():
		if not s.artifact_error(side, index).is_empty(): continue
		var item: Dictionary = items[index]
		var rule := s.artifact_rule(item)
		var ability := {"key": "artifact:%d" % index, "target": rule.get("target", "none"), "card": item.spell}
		for args: Array in _arguments(s, side, ability):
			if rule.get("target", "none") != "none" and ELCatalog.ARTIFACT_EFFECTS.has(item.spell) and not s.artifact_target_error(side, item.spell, args[0], args[1]).is_empty(): continue
			var prior := _spell_prior(ctx, s, side, String(item.spell), int(args[0]), int(args[1]), 0)
			_add(line, {"kind": "ability", "id": side, "key": ability.key, "target": args[0], "choice": args[1], "amount": -1}, prior, MOVE_CAST)

# --- Abilities -----------------------------------------------------------------

static func _ability_moves(ctx: Context, line: Line, s: ELDuel, side: int, id: int, ability: Dictionary) -> void:
	var card := String(ability.get("card", s.creatures[id].card if s.creatures.has(id) else ""))
	if id < 2:
		for e: Dictionary in s.heroes[id].enchantments:
			if e.id == ability.get("enchantment", -1): card = e.card
	for args: Array in _arguments(s, id, ability):
		var prior := _ability_prior(ctx, s, side, id, card, ability, args)
		_add(line, {"kind": "ability", "id": id, "key": ability.key, "target": args[0], "choice": args[1], "amount": args[2]}, prior, MOVE_ABILITY)

## [target, choice, amount] candidates for an ability or artifact.
static func _arguments(s: ELDuel, id: int, ability: Dictionary) -> Array:
	var key := String(ability.key)
	var effect := String(ability.get("effect", key))
	var side := int(s.entity(id).get("owner", id)) if id >= 2 else id
	var targets: Array = []
	match String(ability.get("target", "none")):
		"hero": targets = [[0, -1], [1, -1]]
		"creature":
			for c: int in s.creatures: targets.append([c, -1])
		"any":
			targets = [[0, -1], [1, -1]]
			for c: int in s.creatures: targets.append([c, -1])
		"enchantment":
			for holder: int in [0, 1] + s.creatures.keys():
				for e: Dictionary in s.entity(holder).get("enchantments", []): targets.append([holder, int(e.id)])
		"grave":
			for owner in [0, 1]:
				var indexes: Array = s.grave_ability_targets(id, key, owner)
				if key.begins_with("artifact:") and owner == side and indexes.is_empty():
					for index in s.heroes[side].grave.size():
						if s.profile.table("CombatCreatures").has(s.heroes[side].grave[index]): indexes.append(index)
				for index: int in indexes: targets.append([owner, index])
		_: targets = [[-1, -1]]
	var second := String(ability.get("second", "creature" if effect == "combine" else ""))
	if not second.is_empty():
		var paired: Array = []
		for t: Array in targets:
			var others: Array = ([0, 1] if second == "any" else []) + s.creatures.keys()
			for other: int in others:
				if other != t[0]: paired.append([t[0], other])
		targets = paired
	var amounts: Array = [-1]
	if ability.get("variable", false):
		amounts = []
		for x in range(s.available_mana(side), int(ability.get("minimum", 0)) - 1, -1): amounts.append(x)
	var result: Array = []
	for amount: int in amounts:
		for t: Array in targets: result.append([t[0], t[1], amount])
	return result

## Ability priorities: 0.75 unless the ability names its own rule.
static func _ability_prior(ctx: Context, s: ELDuel, side: int, id: int, card: String, ability: Dictionary, args: Array) -> float:
	var key := String(ability.key).get_slice(":", 0)
	var target := int(args[0])
	match key:
		"spores":
			# The second game's carnivorous fingus needs power and caps its priority.
			if ctx.second and card == "CAFG":
				if int(s.creatures[id].power) <= 0: return 0.0
				return minf(0.35, _side_check(s, side, 0xa, target, -1))
			return _side_check(s, side, 0xa, target, -1)
		"fireball", "sting", "gaze", "hunt":
			return _side_check(s, side, 0xa, target, -1)
		"tap_target", "tap_race":
			if s.creatures.has(target) and (s.creatures[target].resting or s.creatures[target].sick): return 0.0
			return _side_check(s, side, 0xa, target, -1)
		"energize":
			return _side_check(s, side, 5, target, -1)
		"dispel", "disenchant":
			return _side_check(s, side, 0x10, target, int(args[1]))
		"orc_rite":
			# Update 1.03's rite costs a channel: kept for a hero with channels to spare.
			if int(s.heroes[side].channels) < 3: return 0.0
			return _side_check(s, side, 0x10, target, int(args[1])) * 0.5
		"siphon":
			var c: Dictionary = s.creatures[id]
			return 0.5 if not c.resting and not c.sick and not s.attacks.has(id) and int(s.heroes[1 - side].mana) > 0 else 0.0
		"sacrifice":
			# Cutter, razor and sawer men: both games price the battle's first
			# creature (object 2) rather than the chosen victim, so every victim ties
			# and nothing is offered once that creature is gone. The hero's
			# Sacrifice keeps the default.
			if id >= 2 and SACRIFICE_PRIOR.has(card):
				if not s.creatures.has(2): return 0.0
				var victim: Dictionary = s.creatures[2]
				var value := float(SACRIFICE_PRIOR[card]) - 0.1 * float(s.cost(victim.card))
				if not victim.resting and not victim.sick: value -= 0.1
				return maxf(value, 0.0) if ctx.second else value
		"rebirth", "second_birth", "repair":
			# Dearer creatures first; a second birth needs the printed cost in ether.
			var grave: Array = s.heroes[target].grave
			var index := int(args[1])
			if index < 0 or index >= grave.size(): return 0.0
			var mana := int(s.heroes[side].mana)
			if key == "second_birth" and mana < _printed_cost(s, grave[index]): return 0.0
			var price := s.cost(grave[index])
			return minf(0.9, (0.71 if key == "repair" and mana < price else 0.75) + 0.1 * float(price))
	if not ctx.second: return 0.75
	match key:
		"slay", "breath", "wall_break": return 0.5
		"dissipate", "cruel": return 0.0
		"illusion": return 0.5 if s.heroes[side].hand.size() >= 3 else 0.0
		"spirit_lock": return 0.45 if int(s.heroes[side].mana) < 7 else 0.0
		"lava_power":
			var mana := int(s.heroes[side].mana)
			if int(args[2]) == mana: return 0.45
			return 0.75 if mana >= 4 and int(args[2]) == mana - 1 else 0.0
		"hellfire_health":
			var mana := int(s.heroes[side].mana)
			if int(args[2]) == mana: return 0.5
			return 0.75 if mana >= 6 and int(args[2]) == mana - 3 else 0.0
		"burnout": return 0.7 if int(args[1]) < 2 else 0.5
		"channel_ether": return 0.45
		"pale_devour": return _side_check(s, side, 0xa, target, -1)
		"mystic": return 0.75 if card == "OUE1" else 0.0
		"stone_rain":
			for c: Dictionary in s.army(1 - side):
				if not s.in_plane(c.id) and not s.has_flag(c.id, "NoAffect"): return 0.75
			return 0.0
	return 0.75

## The shared side test of spells and abilities: 0.75 when the target suits
## the flags (see SPELL_SIDES), else 0.
static func _side_check(s: ELDuel, side: int, flags: int, target: int, choice: int) -> float:
	return 0.75 if _sides_ok(s, side, flags, target, choice, true) else 0.0

static func _sides_ok(s: ELDuel, side: int, flags: int, target: int, choice: int, second: bool) -> bool:
	if flags & 0xf and target >= 0:
		if target < 2:
			# The first game's test reads only the creature requirements, which
			# a hero target never meets.
			if not second: return not bool(flags & 3)
			if target == side and flags & 8: return false
			if target != side and flags & 4: return false
		elif s.creatures.has(target):
			var owner := int(s.creatures[target].owner)
			if owner != side and flags & 1: return false
			if owner == side and flags & 2: return false
		else: return false
	if flags & 0x50 and choice >= 0:
		var holder := s.find_enchantment(choice)
		if holder >= 0:
			var e := s._enchantment_by_id(holder, choice)
			if int(e.get("owner", s.entity(holder).get("owner", holder))) == side: return false
	return true

# --- Spell priorities -------------------------------------------------------------

static func _spell_prior(ctx: Context, s: ELDuel, side: int, card: String, target: int, choice: int, x: int) -> float:
	var flags := int(SPELL_SIDES[ctx.edition].get(card, 0))
	match card:
		"COMT": return _comet_prior(ctx, s, side, target, x)
		"CHNL", "CTST", "ERQA", "FRST", "SNOV", "TPLF", "WNFL":
			return 0.0 if x == 0 else 0.5
		"HEAL":
			if not ctx.second: return 0.0 if x == 0 else 0.5
		"ZAPP", "DSIG":
			var amount := 1000000 if card == "DSIG" else s.effect_amount(ELCatalog.rule(s.profile, card))
			if target < 2:
				if target == side or target < 0: return 0.0
				return 1.0 if amount >= int(s.heroes[target].health) else 0.5
			if not s.creatures.has(target) or int(s.creatures[target].owner) == side: return 0.0
			var c: Dictionary = s.creatures[target]
			return (0.74 if amount >= int(c.toughness) - int(c.damage) else 0.24) + float(_worth(s, c.card)) * 0.01
		"BLSS", "WNBL":
			if s.creatures.has(target):
				var c: Dictionary = s.creatures[target]
				if c.resting or c.sick or s.has_flag(target, "NoAttack"): return 0.0
		"PSBR", "SHFR":
			if not s.creatures.has(target) or int(s.creatures[target].owner) != side: return 0.0
			return 0.5 if x > (3 if card == "PSBR" else 4) else 0.0
		"FRWN": return 0.5 if x >= 2 else 0.0
		"ENBR", "LFGR", "STSK":
			if ctx.second: return 0.5 if target >= 0 and target < 2 and _sides_ok(s, side, flags, target, choice, true) else 0.0
		"ASLT": return _assault_prior(s, side)
		"RDRS":
			if choice < 0 or choice >= s.heroes[side].grave.size(): return 0.0
			return minf(0.9, 0.1 * float(_printed_cost(s, s.heroes[side].grave[choice])) + 0.75)
		"OFLX": return _outer_flux_prior(s, side)
	return 0.5 if _sides_ok(s, side, flags, target, choice, ctx.second) else 0.0

static func _printed_cost(s: ELDuel, card: String) -> int:
	return int(s.profile.table("CombatSpells").get(card, {}).get("Cost", 0))

## Exactly lethal damage first, then overkill; a creature only for an exact kill.
static func _comet_prior(ctx: Context, s: ELDuel, side: int, target: int, x: int) -> float:
	if target < 0: return 0.0
	if target < 2:
		if target == side: return 0.0
		var health := int(s.heroes[target].health)
		if health == x: return 1.0
		if ctx.second:
			if health < x: return 0.95
			return minf(0.9, float(x) * 0.025 + 0.4) if x > 4 else 0.0
		# The first game ranks a wounding blast above overkill.
		if health > x: return 0.95
		return minf(0.9, float(x) * 0.025 + (0.3 if x < 5 else 0.4))
	if not s.creatures.has(target) or int(s.creatures[target].owner) == side: return 0.0
	var c: Dictionary = s.creatures[target]
	if x != int(c.toughness) - int(c.damage): return 0.0
	return minf(0.95, float(_worth(s, c.card)) * 0.05 + 0.4)

## Printed cost, plus one for a rare card and two for a unique one.
static func _worth(s: ELDuel, card: String) -> int:
	var worth := _printed_cost(s, card)
	match String(s.profile.table("CombatSpells").get(card, {}).get("Rarity", "")):
		"Rare": worth += 1
		"Unique": worth += 2
	return worth

## A whole-army boost: enough ready attackers against those still resting.
static func _assault_prior(s: ELDuel, side: int) -> float:
	var ready := 0
	var waiting := 0
	var resting := 0
	for c: Dictionary in s.army(side):
		if s.has_flag(c.id, "NoAttack"): continue
		if not c.resting and not c.sick: ready += 1
		elif c.sick or not s.has_flag(c.id, "NoUntap"):
			waiting += 1
			if c.resting: resting += 1
	return 0.5 if ready != 0 and (ready > 2 or waiting * 3 - resting <= ready * 3) else 0.0

## Worth casting when a pale enemy is no tougher than the caster's army is large.
static func _outer_flux_prior(s: ELDuel, side: int) -> float:
	var count := s.army(side).size()
	if count == 0: return 0.0
	for c: Dictionary in s.army(1 - side):
		if s.in_plane(c.id) and int(c.toughness) <= count: return 0.5
	return 0.0

## Stasis pays off with a larger army and spare ether.
static func _stasis_prior(s: ELDuel, side: int, card: String) -> float:
	var mana := int(s.heroes[side].mana)
	var price := s.cost(card)
	if mana < price + 6: return 0.0
	var lead := float(s.army(side).size() - s.army(1 - side).size()) - float(s.heroes[1 - side].mana) * 0.5
	return clampf(lead * float((mana - price) >> 1) * 0.033, 0.0, 0.95)

## A lone attacker's priority from its cost, evasion and the enemy's ready blockers.
static func _attack_prior(s: ELDuel, c: Dictionary) -> float:
	var power := int(c.power)
	if power == 0: return 0.0
	var worth := float(_printed_cost(s, c.card)) * 0.01
	if s.has_flag(c.id, "UB"): return minf(0.95, worth + 0.84)
	var total := 0
	var largest := 0
	var any_ready := false
	var flier := false
	var wall := false
	for e: Dictionary in s.army(1 - int(c.owner)):
		if e.resting or e.sick: continue
		var left := int(e.toughness) - int(e.damage)
		total += left
		largest = maxi(largest, left)
		any_ready = true
		if s.has_flag(e.id, "Fly"): flier = true
		if s.race(e.id) == "Wall": wall = true
	if not any_ready: return minf(0.95, worth + 0.79)
	if s.has_flag(c.id, "Fly") and not flier: return minf(0.95, worth + 0.79)
	if _elusive(s, c) and not wall: return minf(0.95, worth + 0.79)
	if total < power: return minf(0.95, worth + 0.69)
	if largest < power: return minf(0.95, worth + 0.59)
	return minf(0.95, float(power) * 0.025 + 0.3 - worth)

static func _elusive(s: ELDuel, c: Dictionary) -> bool:
	return c.card in ELCatalog.WALL_BLOCKED or s.has_flag(c.id, "Elusive")

# --- Attack and block plans --------------------------------------------------------

## Every free creature with power attacks. The second game moves each new best
## lone-attack priority to the front; the first game keeps army order
## (EL1 walks the army list without scoring).
static func _attack_plan(ctx: Context, line: Line, s: ELDuel) -> bool:
	var order: Array[int] = []
	var top := 0.0
	for c: Dictionary in s.army(s.active_side()):
		if not _free(s, c) or int(c.power) <= 0: continue
		line.used += 1
		if not ctx.second:
			order.append(int(c.id))
			continue
		var score := _attack_prior(s, c)
		if score > top:
			top = score
			order.push_front(int(c.id))
		else: order.append(int(c.id))
	for id: int in order:
		if s.creatures.has(id) and not s.attacks.has(id) and s.toggle_attack(id):
			line.steps.append({"kind": "attack", "id": id})
			if line.sent.is_empty(): line.sent = line.steps[0]
	return not line.sent.is_empty()

static func _block_plan(ctx: Context, line: Line, s: ELDuel) -> bool:
	if s.attacks.is_empty(): return false
	line.used += 2
	match int(line.command.plan):
		0x200: _block_smallest(line, s)
		0x400: _block_scored(line, s, 2)
		0x800: _block_scored(line, s, 3)
		0x1000: _block_scored(line, s, 4)
	return not line.sent.is_empty()

static func _block_now(line: Line, s: ELDuel, blocker: int, attacker: int) -> bool:
	line.used += 1
	var ok := s.assign_block(blocker, attacker)
	if ok:
		line.steps.append({"kind": "block", "id": blocker, "target": attacker})
		if line.sent.is_empty(): line.sent = line.steps[0]
	return ok

static func _can_block(s: ELDuel, attacker: int, blocker: int) -> bool:
	return s.block_problem(blocker, attacker).is_empty()

## Strongest attackers first: the least tough blocker that can stop each, or
## the toughest one against trample. Unblockable attackers are left alone.
static func _block_smallest(line: Line, s: ELDuel) -> void:
	var blockers: Array[Dictionary] = []
	for c: Dictionary in s.army(s.active_side()):
		if _free(s, c): blockers.append(c)
	blockers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.toughness) < int(b.toughness))
	var attackers: Array[Dictionary] = []
	for id: int in s.attacks:
		if s.creatures.has(id): attackers.append(s.creatures[id])
	# Descending power; equal powers keep the later attacker first.
	attackers.reverse()
	attackers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.power) > int(b.power))
	for a: Dictionary in attackers:
		if blockers.is_empty(): break
		if s.has_flag(a.id, "UB"): continue
		var order := blockers.duplicate()
		if s.has_flag(a.id, "Trample"): order.reverse()
		for b: Dictionary in order:
			if not _can_block(s, a.id, b.id): continue
			if _block_now(line, s, b.id, a.id):
				blockers.erase(b)
				break

## An attacker's fight so far: power still to absorb, toughness left, blockers
## and whether it is stopped.
static func _fight(s: ELDuel, a: Dictionary) -> Dictionary:
	return {"id": int(a.id), "power": int(a.power), "toughness": int(a.toughness), "count": 0, "stopped": false}

static func _with_blocker(s: ELDuel, f: Dictionary, b: Dictionary) -> void:
	if not s.has_flag(f.id, "FS") and s.has_flag(b.id, "FS") and f.toughness <= int(b.power):
		f.power = -1
		f.toughness = 0
		f.stopped = true
	else:
		f.power -= int(b.toughness)
		if f.power < 0:
			f.power = -1
			f.toughness -= int(b.power)
			f.stopped = true
		elif not (s.has_flag(f.id, "Trample") and f.power > 0):
			f.stopped = true
	f.count += 1

## Scored block plans: 2 stops each attacker with one blocker that survives or
## kills it; 3 gangs up while the blockers can still kill; 4 gangs up only
## when the attacker dies.
static func _block_scored(line: Line, s: ELDuel, plan: int) -> void:
	var side := s.active_side()
	var fights: Array[Dictionary] = []
	for id: int in s.attacks:
		if not s.creatures.has(id): continue
		var f := _fight(s, s.creatures[id])
		for blocker: int in s.blocks:
			if int(s.blocks[blocker]) == id and s.creatures.has(blocker): _with_blocker(s, f, s.creatures[blocker])
		if f.toughness > 0 and (plan != 2 or f.power > 0): fights.append(f)
	var free: Array[Dictionary] = []
	for c: Dictionary in s.army(side):
		if _free(s, c): free.append(c)
	while not fights.is_empty() and not free.is_empty():
		var at := 0
		for i in fights.size():
			if int(fights[i].power) > int(fights[at].power): at = i
		var f: Dictionary = fights[at]
		fights.remove_at(at)
		if plan == 2 and f.stopped: continue
		var candidates: Array[Dictionary] = []
		for b: Dictionary in free:
			if _can_block(s, f.id, b.id): candidates.append(b)
		if candidates.is_empty(): continue
		var chosen: Array[Dictionary] = []
		while not candidates.is_empty() and (f.count == 0 if plan == 2 else f.toughness > 0):
			var best := -1e6
			var pick: Dictionary = {}
			for b: Dictionary in candidates:
				var trial := f.duplicate()
				var score := -1e6
				if plan == 2:
					_with_blocker(s, trial, b)
					if trial.toughness < 1: score = 3000.0 - float(b.power) * 1.5 - float(b.toughness)
					elif trial.power < 0: score = 2000.0 - float(b.power) * 1.5 - float(b.toughness) - (2.5 if s.has_flag(b.id, "FS") else 0.0)
				else:
					if not (f.power > 0 or int(b.power) > 0): continue
					_with_blocker(s, trial, b)
					if plan == 3 and not (trial.count < 2 or trial.power < 0): continue
					if trial.toughness < 1: score = 3000.0 - float(b.power) * 1.5 - float(b.toughness)
					else:
						if trial.power < 0: score = 2000.0 + float(b.power) * 1.5 - float(b.toughness)
						elif trial.power == 0: score = 1000.0 - float(b.power) * 1.5 - float(b.toughness)
						else: score = float(b.toughness) - float(b.power) * 1.5
						if s.has_flag(b.id, "FS"): score -= 2.5
				if score > best:
					best = score
					pick = b
			if pick.is_empty(): break
			_with_blocker(s, f, pick)
			chosen.append(pick)
			candidates.erase(pick)
		if plan == 4 and f.toughness > 0: continue
		for b: Dictionary in chosen:
			if not _block_now(line, s, b.id, f.id): return
			free.erase(b)

# --- Evaluation ----------------------------------------------------------------

## A finished line counts its length against it; otherwise the position is
## blended with the one after the side to act passes its phase.
static func _leaf(ctx: Context, line: Line, s: ELDuel) -> float:
	var now := side_value(ctx, s, ctx.ai) - side_value(ctx, s, 1 - ctx.ai) + float(line.depth) * ctx.w[1]
	if s.phase == ELDuel.Phase.FINISHED: return now - float(line.depth)
	var after := s.search_copy()
	after.end_phase()
	ctx.positions += 1
	var later := side_value(ctx, after, ctx.ai) - side_value(ctx, after, 1 - ctx.ai)
	var blend := 0.001 if after.phase == ELDuel.Phase.FINISHED else ctx.w[0]
	var value := blend * later + (1.0 - blend) * now - _threat(ctx, s)
	if ctx.brain_turns > 0 and s.phase == ELDuel.Phase.ATTACK:
		# What the fighting of the coming turns adds to or takes from the line.
		var answer := ELCombatBrain.ask(ctx, s, ctx.brain_turns, smart_brain_budget, false)
		if not answer.is_empty():
			if answer.status != 0: value += float(answer.status) * maxf(smart_forced - smart_forced_step * float(int(answer.turns) - 1), smart_forced * 0.5)
			elif answer.value > 0.0: value += float(answer.value) * smart_later
			else: value += float(answer.value)
	return value

## Remake option: what the opponent's attack would cost when the computer has
## just ended its own turn. Every creature that can attack does; the
## computer's ready creatures each stop one attacker, the strongest first.
static func _threat(ctx: Context, s: ELDuel) -> float:
	if ctx.threat <= 0.0 and ctx.lethal <= 0.0: return 0.0
	if s.phase != ELDuel.Phase.ATTACK or s.attacker == ctx.ai: return 0.0
	var through := incoming(s)
	if through <= 0: return 0.0
	if through >= int(s.heroes[ctx.ai].health): return ctx.lethal + float(through) * ctx.threat * ctx.w[2]
	return float(through) * ctx.threat * ctx.w[2]

## Damage the defending hero would take from an attack by every creature of
## the side to move, after the defender's ready creatures block to spare it.
static func incoming(s: ELDuel) -> int:
	var foe := s.attacker
	var attackers: Array[Dictionary] = []
	for c: Dictionary in s.army(foe):
		if int(c.power) > 0 and s.can_attack(c.id): attackers.append(c)
	if attackers.is_empty(): return 0
	attackers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.power) > int(b.power))
	# An attack tax leaves only the attackers the hero's ether pays for.
	var tax := s.attack_cost(int(attackers[0].id))
	if tax > 0: attackers.resize(mini(attackers.size(), s.available_mana(foe) / tax))
	# Ground creatures block first, keeping flyers and walls for what only they stop.
	var ground: Array[Dictionary] = []
	var flying: Array[Dictionary] = []
	var walls: Array[Dictionary] = []
	for c: Dictionary in s.army(1 - foe):
		if c.resting or c.sick or s.in_plane(c.id): continue
		if s.race(c.id) == "Wall": walls.append(c)
		elif s.has_flag(c.id, "Fly"): flying.append(c)
		else: ground.append(c)
	var through := 0
	for a: Dictionary in attackers:
		var power := int(a.power)
		if s.has_flag(a.id, "UB"):
			through += power
			continue
		var pools: Array = [walls] if _elusive(s, a) else ([flying] if s.has_flag(a.id, "Fly") else [ground, walls, flying])
		var blocker := {}
		for pool: Array in pools:
			if pool.is_empty(): continue
			if not s.has_flag(a.id, "Trample"):
				blocker = pool.pop_back()
				break
			# The toughest blocker soaks up the most of a trampler.
			var at := 0
			for i in pool.size():
				if int(pool[i].toughness) > int(pool[at].toughness): at = i
			if blocker.is_empty() or int(pool[at].toughness) > int(blocker.toughness):
				blocker = pool[at]
		if blocker.is_empty():
			through += power
		elif s.has_flag(a.id, "Trample"):
			for pool: Array in pools: pool.erase(blocker)
			through += maxi(0, power - int(blocker.toughness))
	return through

## One side's position worth: army, health, hand, channels and enchantments.
## The chance `side` goes on to win, from the worth the search reads in the
## position. Fitted to the turns of some 3800 computer-vs-computer duels: a
## hero 26 ahead in the first game won nine in ten, one 36 behind one in five,
## and over a whole duel the curve names the winner about three turns in four.
const ODDS := {"el1": [0.0368, -2.25], "el2": [0.0404, -1.83]}

static func win_chance(ctx: Context, s: ELDuel, side: int) -> float:
	return worth_chance(ctx.edition, side_value(ctx, s, side) - side_value(ctx, s, 1 - side))

## The chance to win of a side that stands `worth` ahead.
static func worth_chance(edition: String, worth: float) -> float:
	var odds: Array = ODDS.get(edition, ODDS.el1)
	return 1.0 / (1.0 + exp(clampf(-float(odds[0]) * (worth - float(odds[1])), -30.0, 30.0)))

## A context that reads positions for `side` with the steady weights and
## nothing else of the remake's options.
static func plain_context(duel: ELDuel, side: int) -> Context:
	var ctx := Context.new()
	ctx.ai = side
	ctx.edition = duel.profile.id
	ctx.second = ctx.edition == "el2"
	ctx.w = steady_weights(ctx.second)
	return ctx

## The battle adviser's reading of `position` for the side to act: the
## original lookahead with the steady weights, every first move it tried and
## what each is worth. It sees what the player sees: the other side's lines
## never cast, the compiled engine (which knows both hands and the cards to
## come) is not asked, and no plan is kept for the computer to follow.
## Returns {"side", "value", "moves": [{command, plan, prior, value}]}; the
## best move is the one worth most.
static func study(position: ELDuel) -> Dictionary:
	if position.phase == ELDuel.Phase.FINISHED: return {}
	var ctx := plain_context(position, position.active_side())
	ctx.limit = 1 if position.phase == ELDuel.Phase.ATTACK else 0
	ctx.tracing = true
	var root := Line.new()
	root.budget = BUDGET
	var start := position.search_copy(ctx.second)
	if ctx.second: start.spec_expect = ELSpecs.sample_expectation(position)
	_search(ctx, root, start)
	if start.scripts != null and start.scripts.search_only: start.scripts.close()
	return {"side": ctx.ai, "value": root.value, "moves": ctx.trace}

static func side_value(ctx: Context, s: ELDuel, side: int) -> float:
	if s.phase == ELDuel.Phase.FINISHED:
		var lost := s.winner != side
		if lost: return 0.0 if s.winner < 0 else -10.0 * float(s.turn_serial)
		return 100000.0 if ctx.second else 10000.0
	var w := ctx.w
	var hero: Dictionary = s.heroes[side]
	var value := 0.0
	if ctx.remember:
		# A creature's worth does not change while it stands as it is under the
		# same hero enchantments; the remake option keeps it for the think.
		var cards: Array = []
		for e: Dictionary in hero.enchantments: cards.append(e.card)
		var auras := cards.hash()
		for c: Dictionary in s.creatures.values():
			if int(c.owner) != side: continue
			var key := [c.hash(), auras].hash()
			var worth: Variant = ctx.worths.get(key)
			if worth == null:
				worth = creature_value(ctx, s, c)
				ctx.worths[key] = worth
			value += float(worth)
	else:
		for c: Dictionary in s.army(side): value += creature_value(ctx, s, c)
	var health := float(hero.health)
	var channels := float(hero.channels)
	value += health * w[2] * (1.0 if side == ctx.ai else ctx.foe_health) + float(hero.hand.size()) * w[4]
	if ctx.second:
		var term := channels * w[3]
		if channels > 9.0: term = (channels - 9.0) * 0.5 + 5.0 * w[3] + 3.0
		elif channels > 5.0: term = (channels - 5.0) * 0.75 + 5.0 * w[3]
		var whole := int(term)
		if whole > 20: whole = int(float(whole - 20) * 0.2 + 20.0)
		value += float(whole) + minf(health, 5.0) * 0.3 + minf(health, 8.0) * 0.2 + minf(health, 12.0) * 0.1
	else:
		value += channels * w[3]
	value += _hero_enchantments(ctx, hero)
	if ctx.income > 0.0: value += ctx.income * _income(s, side, hero)
	return clampf(value, 0.0, 20000.0 if ctx.second else 2000.0)

## Remake option (`smart_income`): what the hero's ether storms, breezes and
## vortex will bring on later turns.
static func _income(s: ELDuel, side: int, hero: Dictionary) -> float:
	var total := 0.0
	for c: Dictionary in s.creatures.values():
		for e: Dictionary in c.enchantments:
			if int(e.owner) != side: continue
			if e.card == "MNST": total += 2.5 + 0.05 * minf(float(c.toughness), 10.0)
			elif e.card == "MNBR": total += 2.0 + 0.05 * minf(float(c.toughness), 10.0)
	for e: Dictionary in hero.enchantments:
		if e.card != "MNVR" or int(e.owner) != side: continue
		var channels := int(hero.channels)
		var wanted := -channels
		for card: String in hero.hand: wanted += s.cost(card)
		total += 0.2 * float(clampi(wanted, 0, channels))
		break
	return total

## What a hero's own enchantments are worth (for the compiled engine).
static func hero_enchantment_worth(ctx: Context, hero: Dictionary) -> float:
	return _hero_enchantments(ctx, hero)

static func _hero_enchantments(ctx: Context, hero: Dictionary) -> float:
	var each: Dictionary = EACH[ctx.edition]
	var kind: Dictionary = KIND[ctx.edition]
	var counts := {}
	var total := 0.0
	for e: Dictionary in hero.enchantments:
		total += float(each.get(e.card, 0.0))
		counts[e.card] = int(counts.get(e.card, 0)) + 1
	# Forests do not stack: the ancient forest replaces the others, the dark the dense.
	if counts.has("ANFR"):
		counts.erase("DRFR")
		counts.erase("DNFR")
	elif counts.has("DRFR"): counts.erase("DNFR")
	for card: String in counts:
		total += float(kind.get(card, 0.0))
		if ctx.second: total += _count_value(card, int(counts[card]), true)
	return total

static func _count_value(card: String, count: int, on_hero: bool) -> float:
	match card:
		"SPLK": return 1.5 if count == 1 else 2.5
		"BROT": return 1.5
		"OCRP": return -1.5
		"STSK", "ENBR": return float(count - 1) * 2.0 + 3.0 if on_hero else 0.0
	return 0.0

static func _flag_amount(s: ELDuel, c: Dictionary, name: String) -> int:
	var best := 0
	for flag: String in c.flags + c.get("granted", []):
		if flag == name: best = maxi(best, 1)
		elif flag.begins_with(name + "("): best = maxi(best, int(flag.trim_prefix(name + "(").trim_suffix(")")))
	return best

## A creature's worth from its current stats, keywords and readiness (damage
## does not count).
static func creature_value(ctx: Context, s: ELDuel, c: Dictionary) -> float:
	var w := ctx.w
	var id := int(c.id)
	var second := ctx.second
	var base := w[5] + float(c.toughness) * w[8]
	var bonus := 0.0
	var factor := 0.0
	var regeneration := s.regeneration_cost(id)
	if regeneration > 0 and not s.has_flag(id, "NoRegen"):
		if regeneration == 1: bonus += 0.5
		elif regeneration == 2: bonus += 0.1
	match String(s.profile.table("CombatSpells").get(c.card, {}).get("Rarity", "")):
		"Rare": bonus += 0.1
		"Unique": bonus += 0.2
	if s.has_flag(id, "Fly"):
		if second:
			factor = 0.1
			bonus += 0.6
		else: bonus += 0.1
	if s.has_flag(id, "FS"): bonus += 0.1
	if s.has_flag(id, "NoTarget"): bonus += 0.1
	if s.has_flag(id, "NoAffect"): bonus += 1.5
	if s.has_flag(id, "Destroy"): bonus += 0.1
	if second:
		if s.in_plane(id): bonus -= 0.3
		var skins := s._enchantment_count(id, "STSK")
		if skins > 0: bonus += minf(1.5, float(skins) * w[8] * 1.1)
		var barriers := s._enchantment_count(id, "ENBR")
		if barriers > 0: bonus += minf(2.5, float(barriers) * w[8])
		if s._enchantment_count(id, "LFGR") > 0: bonus += 1.5
		if c.card == "OSP1": bonus += 1.0
		elif c.card in ["OSP2", "OSP3"]: bonus += 2.0
	var resting: bool = c.resting
	if not s.has_flag(id, "NoAttack"):
		factor += w[6]
		if s.has_flag(id, "Trample"): factor += 0.05
		if s.has_flag(id, "Lifetap"):
			factor += 0.1
			bonus += 0.1
		if s.has_flag(id, "UB"):
			factor += 0.05
			bonus += 0.1
		bonus += float(_flag_amount(s, c, "Discard")) * 0.05
		if s.has_flag(id, "NSS"): bonus += 0.05
		if s.has_flag(id, "TeamAttack"): factor -= 0.3
		if s.has_flag(id, "Berserk"): bonus -= 0.1
		if resting: bonus -= 0.5
		elif c.sick: bonus -= 0.3
	else:
		factor += w[7]
		if resting: bonus -= 0.5
	var restless := s.has_flag(id, "Restless")
	if restless: bonus += 0.1
	if s.has_flag(id, "NoUntap"):
		if second and c.card in SELF_RESTING:
			base *= 0.8
			factor *= 0.8
			if bonus > 0.0: bonus *= 0.8
		elif not resting:
			if not restless: bonus -= 0.2
		else:
			base *= 0.5
			factor *= 0.5
			if bonus > 0.0: bonus *= 0.5
	var blocked := s._enchantment_count(id, "IRRT") + s._enchantment_count(id, "MDNS") + s._enchantment_count(id, "RDIS") > 0
	if not blocked:
		if second and c.card == "WNHR": bonus += 5.0
		elif second and s._enchantment_count(id, "OCRP") > 0: bonus -= 0.5
		elif second and String(s.profile.table("CombatSpells").get(c.card, {}).get("Color", "")) == "White":
			bonus += 0.1 * float(s.abilities(id).size())
	var power := float(c.power)
	var spores := power * 0.5 if second and c.card == "CAFG" else 0.0
	var value := maxf(power * factor + spores + bonus + base, 0.01)
	if second:
		var counts := {}
		for e: Dictionary in c.enchantments: counts[e.card] = int(counts.get(e.card, 0)) + 1
		for card: String in counts: value += _count_value(card, int(counts[card]), false)
	return value
