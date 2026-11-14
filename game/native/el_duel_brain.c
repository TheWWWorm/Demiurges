/*
 * Combat lookahead for the computer opponent (GDExtension, C).
 *
 * The duel rules live in GDScript (src/duel/state.gd), where one position
 * costs about a millisecond to play. This library looks further with a compact
 * model of the fight: both armies with their combat keywords, the heroes'
 * health and ether. It searches whole turns (which creatures attack, how the
 * defender blocks, the fight, the next turn) with alpha-beta, a few hundred
 * thousand fights in the time GDScript plays a few dozen positions.
 * ELCombatSearch keeps playing the real rules for the move it is choosing and
 * asks this library what follows; without the library it looks one turn
 * ahead, as before.
 *
 * Exposed as one static method of the class ELNativeDuelBrain:
 *   search(state: PackedByteArray) -> PackedByteArray
 * Both arrays hold little-endian 32-bit integers.
 *
 * Input: HEADER integers
 *    0 version (the packer's, src/duel/combat_brain.gd: the full and
 *      current account of this layout is there, and what follows here
 *      names only its oldest parts)
 *                              1 the computer's side
 *    2 side whose turn it is   3 phase: 0 attackers to choose, 1 blockers,
 *      2 play out the declared fight alone and give back the board it leaves,
 *      3 the same for ending the turn
 *    4 turns to look ahead     5 fights it may play (budget)
 *    6 edition (0 first game, 1 second)
 *    7 worth of a health point, in thousandths
 *    8 ether an attacker costs to send (attack tax)
 *    9 1 when nothing can attack in the current turn
 *   10 width: 0 for scoring a position, 1 for choosing a move
 *   11 number of creatures
 *   12 cards: 1 when the sides also play cards in the turns looked at
 *   13 1 when the side to move has yet to play its cards this turn
 *   14 worth of a point of the other hero's health, in hundredths of the
 *      computer's own (0 = the same)
 *   15 heroes whose creatures cannot regenerate at all (bit per side)
 *   16 commands that follow the creatures (phase 4)
 *   17 phase of play: 0 the attack, 1 the defence
 *   18 worth of a card in hand, in thousandths
 *   19 worth of an ether channel, in thousandths
 *   20 turns of fighting played out where a searched line stops
 *   21 how far behind a command may look and still be read, in thousandths
 *   22 whether a played-out duel fights as well as the lookahead can
 *   23 worth of a point of power on a creature that attacks, in thousandths
 *   24 the same on one that cannot attack
 *   25 worth of a point of a creature's health, in thousandths
 *   26 whether a line that stops where a hero could still attack has that
 *      hero attack before it is weighed
 *   27 how much of a line's worth is the position where it stops, as it
 *      stands, in hundredths; the rest is what the fighting to come brings
 * then, per hero, 17 integers (health, ether, channels, stone skins,
 * lifeguards, damage reflections, damage mirrors, unknown cards in hand,
 * chance in thousandths that an unknown card is a creature, the same chance
 * already saved up, the channels gained in each of its next six turns, the
 * ether it opens a turn with beyond those channels, the cards in its hand,
 * what its own enchantments are worth, the health it began the duel with,
 * the creatures in its graveyard, ether it gets once at its next turn's
 * start, the ether vortices multiplying what its channels give, the
 * health the ether disturbance takes at the start of each of its next six
 * turns, the forest on it: one more than the greatest power it holds
 * at home, or 0, and what that forest is worth, how many copies of each
 * enchantment the engine has a rule for stand on it, in the order of HE_*,
 * and how many copies of each that gives an ability were used this turn);
 * per hero, the typical creature of its colour for each cost 1..8 (power,
 * toughness, worth when ready, worth when resting); per hero, eight cards in
 * hand and then the six it will draw, in the order it draws them (cost or
 * -1, power, toughness, flags, regeneration cost, worth when ready, worth
 * when resting, race number, effect, scope, amount, whether it takes an X,
 * what an enchantment lends in power and health, the flags it lends, the
 * ether that frees what it holds, what it may be aimed at, and whether only
 * at its caster's own (bit 0) and whether it may be cast in defence (bit 1));
 * and 13 per
 * creature (id, owner, power, toughness, flags, regeneration cost, stone
 * skins, lifeguards, worth when ready, worth when resting (thousandths),
 * race number, id of the attacker it already blocks or -1, ether that wakes
 * it from enfeeblement or 0 (and whether that also costs health), damage
 * already taken, the creatures whose aura
 * lends it strength as a bit each, and the strength its own aura lends
 * (power times 256 plus health), and the health its owner pays for it at
 * the end of each turn).
 *
 * With cards on, a side starts each turn looked at by gaining its channels,
 * waking what it can, summoning the known creature cards it can pay for
 * (dearest first) and, as often as its unknown cards are likely to hold one,
 * a typical creature for the ether left. Which creatures attack and block is
 * searched; what is summoned is not.
 *
 * Output: status (1 the computer wins within the horizon, -1 it loses, else
 * 0), the line's worth minus the position's own (thousandths) or, with a
 * status, the turn that decides it (1 = the one to play), fights played,
 * turns searched, count, then the choice: attacker ids, or (blocker id,
 * attacker id) pairs for the blockers not yet assigned.
 *
 * In phases 2, 3 and 4 the output is the board that left: the commands
 * played (0 for phases 2 and 3), both heroes' health, their ether, their
 * channels, the side to attack, the phase, then three integers per creature
 * (id, damage taken or -1 when it died, 1 when it is resting).
 *
 * Phase 8 plays every command out to the end of the duel over and over and
 * gives back, for each, how often it won: a count, then six integers each
 * (the command, twice the wins plus the draws, and the games played).
 * Field 16 is the rounds a game may run to.
 *
 * Phase 5 searches the commands themselves and gives back the worth of the
 * line, the command to give now (kind, then its three numbers), the
 * positions played, whether the budget ran out, how deep it reached, and
 * then the whole line it means to play: a count and four integers each. Field 16 is then the
 * longest line in commands, field 4 the phase changes to look through.
 *
 * A phase-4 state is followed by its commands, four integers each: the kind
 * (0 end the phase, 1 attack, 2 block, 3 play a card, 4 free a creature an
 * enchantment holds down, 5 send the whole attack the lookahead likes, as a
 * bit per creature in two halves, 6 block as the block search advises, 7 a
 * creature uses its ability on what the second number names, 8 the hero
 * uses the ability an enchantment gives it (which one, then on what)), then
 * for an attack
 * the creature, for a block the blocker and the attacker, and for a card its
 * place in hand, what it names and the ether paid into X. Places past the
 * hand's own and those of the cards come back are the things a hero carries
 * into the duel (ART_BASE on), played the same way. Creatures are named by
 * their place in the state, heroes by -1 and -2, and nothing by -99.
 */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>

#include "include/gdextension_interface.h"

#if defined(_WIN32)
#define EL_EXPORT __declspec(dllexport)
#else
#define EL_EXPORT __attribute__((visibility("default")))
#endif

/* --------------------------------------------------------------------- model */

#define HEADER 32
/* Enchantments a hero lays on itself, by the game's own names for them. Each
 * is a rule of its own further down; what one lends the hero's army, what it
 * is worth and whether it ends with the other hero's turn the caller says. */
enum { HE_LSHE, HE_FRBL, HE_RNST, HE_ENRG, HE_RPST, HE_CMBN, HE_RBRT, HE_SCBR, HE_SPLK, HE_BROT, HE_SACR, HE_OEXC,
	HE_STWO, HE_ENWO, HE_DOMN, HE_JYHD, HE_CRBL, HE_IMML, HE_ASLT, HE_VTLY,
	HE_BLKD, HE_HAST, HE_RDDF, HE_DMRD, HE_ORPL, HE_DRGS, HE_DPGS, HE_FRGS, HE_MNTX, HE_FOGG, HE_HOAM, HE_SFGS, HE_SMOK,
	HE_FLOD, HE_CNAR, HE_ENLH, HE_TRLB, HE_PLWP,
	/* What a wall of distortion leaves on its hero as it goes. */
	HE_WLDT,
	/* Those that work on the duel rather than on an army. */
	HE_MNVR, HE_MNTH, HE_MNBN, HE_STSI, HE_SPTR, HE_FTDS, HE_COPL, HE_FDBK, HE_LNRD, HE_FURY, HE_ASST, HE_SPWB, HE_ETCH,
	HE_BASO, HE_PRWT, HE_PLSL, HE_OST1, HE_OST2, HE_OST3, HE_LCWR, HE_GCWR, HE_LSWR, HE_GSWR, HE_LEWR, HE_GEWR,
	/* Those laid on the other hero; on either; and on a hero or a creature. */
	HE_WETX, HE_STTX, HE_WTX2, HE_ESWS,
	HE_ENVM, HE_PRWR,
	HE_STSK, HE_LFGR, HE_ENBR, HE_COUNT };
#define HE_FIELDS 14
/* Two more things a hero may have laid on it, which the engine keeps apart
 * from those: its share of the attack tax, and its forest. */
#define HE_TAX HE_COUNT
#define HE_FOREST (HE_COUNT + 1)
/* And a water link, which its caster holds and which names a creature. */
#define HE_WATER (HE_COUNT + 2)
/* And a war banner: a point of power and of health for every creature, for
 * each other of its race in play. */
#define HE_BANNER (HE_COUNT + 3)
/* The enchantments on creatures, each told apart so that one may be taken
 * off alone. */
#define MAX_ENCH 48
#define ENCH_FIELDS 13
/* The plain numbers told of each hero, before its enchantments. */
#define HERO_SCALARS 40
/* The first of them give their hero an ability, each copy once a turn. */
#define HERO_ABILITIES 12
/* The creature cards the engine knows by kind, so that one that leaves the
 * board can be played again; the newest cards of a graveyard it is told;
 * and the cards come back into a hand that it may hold at once. */
#define POOL 32
#define GRAVES 12
#define BACK 4
#define HERO_FIELDS (HERO_SCALARS + HE_COUNT + HERO_ABILITIES + 1 + GRAVES)
#define COSTS 8
#define TYPICAL_FIELDS 4
#define HAND 8
/* Cards each hero is about to draw, which the engine is told in full. */
#define DRAWS 6
#define SLOTS (HAND + DRAWS)
#define CARD_FIELDS 25
#define UNIT_FIELDS 66
/* What a hero carries into the duel beside its book: each thing is told as
 * the card it stands for, with the uses it has left, the round it may next
 * be used in, the rounds it then waits, and how it is used. Before them, the
 * turns the duel has seen begin and what ether to come is worth (below); and
 * for each hero, the uses the duel allows
 * it and those it has had. They are played as cards from places of their own. */
#define MAX_ART 8
#define ART_FIELDS (CARD_FIELDS + 5)
#define ART_BASE (SLOTS + BACK)
#define ARTS (2 + 2 * (2 + MAX_ART * ART_FIELDS))
#define FIXED (HEADER + 2 * (HERO_FIELDS + COSTS * TYPICAL_FIELDS + SLOTS * CARD_FIELDS) + HE_COUNT * HE_FIELDS + POOL * CARD_FIELDS + ARTS)
#define ARMY 10
#define MAX_UNITS 32
#define MAX_SETS 96
#define MAX_PLANS 320
#define MAX_TURNS 6
#define MAX_COMMANDS 48
#define MAX_MOVES 256
/* Commands of the chosen line given back to the caller. */
#define MAX_LINE 12
/* First commands a choice may have set aside before it is made again. */
#define MAX_BANS 6
/* A command that names nothing; heroes are -1 and -2, creatures their place. */
#define NO_TARGET (-99)
#define WIN 100000000
#define LETHAL 30000
/* What a win or loss the leaf forecast sees is worth beside the board. */
#define FORECAST 300000

enum {
	F_FLY = 1, F_FIRST = 2, F_TRAMPLE = 4, F_UNBLOCKABLE = 8, F_ELUSIVE = 16, F_WALL = 32, F_NO_ATTACK = 64,
	F_RESTLESS = 128, F_NO_UNTAP = 256, F_DESTROY = 512, F_LIFETAP = 1024, F_BERSERK = 2048, F_TEAM = 4096,
	F_RESTING = 8192, F_SICK = 16384, F_PLANE = 32768, F_ATTACKING = 65536, F_NO_REGEN = 1 << 17,
	/* A strike that strips every enchantment from what it hits. */
	F_DISENCHANT = 1 << 18,
	F_DESTROY_UNWALLED = 1 << 19, F_STINGER = 1 << 20,
	/* A bright pale creature, which dissipates into the plane rather than
	 * die; and a burning strike, which leaves no room to regenerate. */
	F_DISSIPATES = 1 << 21, F_BURN = 1 << 22, F_VENOM = 1 << 23,
	/* Nothing may be aimed at this creature; and a strike that destroys the
	 * flying creature it hits (a hellfire wall's whirl). */
	F_NO_AFFECT = 1 << 24, F_DESTROY_FLYER = 1 << 25,
	/* Destroys itself at its owner's turn end unless something hit it, and
	 * the mark of having been hit since that hero's last turn end. */
	F_FATALIST = 1 << 26, F_HIT = 1 << 27,
	/* Set by the model, above every flag it is given. */
	F_DEAD = 1 << 28, F_REGENERATED = 1 << 29, F_POISONED = 1 << 30,
	/* Left the fight alive (dissipated). */
	F_GONE = 1u << 31,
};

/* What a creature can do of its own accord, by the name the rules give it. */
enum { AB_NONE, AB_SPORES, AB_SPORES_POWER, AB_STING, AB_SHOOT, AB_SLAY, AB_GAZE_TOUGHNESS, AB_GAZE_POWER, AB_HUNT,
	AB_WALL_BREAK, AB_SIPHON, AB_BREATH_FLYING, AB_BREATH_GROUND, AB_BAT_DRAIN, AB_RALLY, AB_TAP_TARGET, AB_TAP_WALLS,
	AB_TAP_RACE, AB_ETHER, AB_DRAW, AB_SACRIFICE,
	/* A mother's brood (the amount names the creature card it lays); a card
	 * gnawed out of a graveyard, and a plague that empties one from its
	 * oldest end; a card of the user's race called back into the hand (the
	 * amount is the race), a warrior spirit called back into play, and any
	 * creature cheap enough raised out of either graveyard (the amount is the
	 * most it may cost). */
	AB_BROOD, AB_GNAW, AB_PLAGUE, AB_RECALL, AB_RAISE_OWN, AB_NECROMANCY,
	/* A wall that goes and takes the whole attack with it; ether poured into
	 * power or into health for the turn; two points of power once a round;
	 * every resting warrior spirit roused, once a round; and every warrior
	 * spirit given wings. */
	AB_DISTORTION, AB_POWER_X, AB_HEALTH_X, AB_PHANTASM, AB_ROUSE, AB_SPIRIT_FLIGHT,
	/* One enchantment taken off for what it costs to remove; and the same
	 * for an ether channel given up. */
	AB_DISPEL, AB_ORC_RITE,
	/* Any enchantment at all taken off, for what its card costs. */
	AB_DISENCHANT,
	/* Its health becomes one more than the cards in its hero's graveyard. */
	AB_ILLUSION };
/* What the second game's pale creatures may do: go into the plane; come out
 * of it for a card of a graveyard, a creature of their own army, an ether
 * channel, an enchantment their hero laid, or a card of the hand; give
 * themselves up for a card; and what one of them does of its own: a channel
 * for three ether, the other hero's ether turned into harm, health for every
 * creature, an enchantment taken off for its ether, copied into the hand, or
 * taken into it, and a weaker creature eaten. */
enum { PA_NONE, PA_DISSIPATE, PA_SINISTER, PA_CRUEL, PA_FIENDISH, PA_MYSTIC, PA_CRYPTIC, PA_COURTESY, PA_CHANNEL, PA_PLEA, PA_HEAL,
	PA_ABSORB, PA_WEAVE, PA_TRANSPOSE, PA_DEVOUR };
/* How it is used: the creature must be ready and out of the fight, and rests
 * for it; only while its hero attacks; only while it rests. */
enum { AT_TAPS = 1, AT_ATTACK = 2, AT_TAPPED = 4,
	/* Not a way of using it: while it lives its hero opens each turn with
	 * one ether more. */
	AT_INCOME = 8 };

typedef struct {
	int32_t id, ready_worth, resting_worth;
	uint32_t flags;
	/* Creatures whose death takes their aura's strength off this one, and
	 * the strength this one lends to each creature its own aura covers. */
	uint32_t leaders;
	int16_t power, toughness, damage, gives_power, gives_toughness;
	/* Health its owner pays at the end of each of its turns. */
	int16_t upkeep;
	int8_t owner, regeneration, skins, guards, race, blocks, wake;
	/* Nothing may be aimed at this creature (its own ether shield), and
	 * whether freeing it costs its hero health as well as ether. */
	int8_t shielded, wake_hurts;
	/* What its card costs: some spells reach only the cheap. */
	int16_t cost;
	/* Twisted enhancements on it: each takes a point of power and of
	 * health at every end of its owner's turn, and in the end its life. */
	int8_t twisted;
	/* A walking horror: its arrival, and its leaving play by any road,
	 * hurts every other creature by three. */
	int8_t horror;
	/* The second game's bat, whose death costs the other hero a card, and
	 * its giant bat, whose blow on a hero draws its own hero one. */
	int8_t mourned, feeds;
	/* A snake whose blow on a hero leaves its venom there, and the energy
	 * barriers on the creature: three off whatever hurts it but a blow. */
	int8_t envenoms, barriers;
	/* Alpha strikes on it: each leaves it no more than a point of health. */
	int8_t alpha;
	/* What a pale creature may do: bits 0-3 what brings it out of the plane,
	 * bit 4 it may give itself up for a card, bits 5-8 what it does of its
	 * own, 9-12 the ether that costs, 13-14 what it measures its prey by.
	 * And what it has done this round: 1 gone into the plane by itself, 2
	 * its own ability; 4, it was resting as it dissipated. */
	int32_t pale_bits;
	int8_t pale_used;
	/* What the war banners give it just now, and how many of them pass it by. */
	int8_t kin, spared;
	/* Its ability (AB_*), the ether that costs, the amount it works by (or
	 * the race number it counts) and how it is used (AT_*). */
	int8_t ability, ability_cost, ability_amount, ability_traits;
	/* Flags it has only from an enchantment on its hero that will end. */
	uint32_t lent;
	/* Its health before the floor of one point, and the points taken past
	 * that floor: `toughness` is always the one less the other. */
	int16_t raw, lethal;
	/* Overloads on it: each burns two points of power and of health out of
	 * it at every end of its hero's turn. */
	int8_t overload;
	/* What the enchantments on it have made of it, for the strike that
	 * strips them: how many they are; the power, health, points past the
	 * floor, flags and worth they gave; and what it has without them. */
	int8_t worn, bare_regeneration, bare_wake, bare_shielded, bare_ability;
	int16_t worn_power, worn_health, worn_lethal;
	uint32_t worn_flags;
	int32_t worn_ready, worn_resting;
	/* What becomes of it once they are gone (FATE_*), and the army it goes
	 * back to when one of them brought it over, plus one (0 for none). */
	int8_t fate, home;
	/* When it was sent to attack or set to block, among all that were this
	 * turn (0 for not yet): the fight is played in that order. */
	uint8_t rank;
	/* The rest of the aura it lends: the flags, whom it reaches (one more
	 * than a race's number, or 200 for the one card it names; 0 for no
	 * aura) and whether only in its own army. Then the flags this creature
	 * has only from such auras, and whether it is that one card. */
	uint32_t gives_flags, aura_flags;
	uint8_t gives_to;
	int8_t gives_own, tribe;
	/* Pain links on it: its hero takes what it takes, once for each. */
	int8_t linked;
	/* A pale creature, which a pale warp may take. */
	int8_t pale;
	/* Of what it wears, the part that lasts only until a turn of the other
	 * hero's ends (a blessing): how many, and what they gave. */
	int8_t brief;
	/* Cards its blow on a hero takes out of that hero's hand. */
	int8_t discards;
	int16_t brief_power, brief_health;
	uint32_t brief_flags;
	int32_t brief_ready, brief_resting;
	/* How far its power stands below nothing: power shows no less than
	 * nothing, and what is added later counts from where it really is. */
	int16_t under;
	/* What it has only until a turn that is not its hero's ends (a boost it
	 * gave itself): how many such things, and what they gave. */
	int8_t passing;
	/* Which card it is, as the engine numbers the creature cards it knows
	 * (one more than its place among them; 0 for one it does not know). */
	int8_t kind;
	/* Of the cards its blow takes, how many it owes to what it wears. */
	int8_t worn_discards;
	int16_t passing_power, passing_health;
	uint32_t passing_flags;
	int32_t passing_ready, passing_resting;
	/* It has used, since its hero's turn began, an ability that may be used
	 * once a round. */
	int8_t spent;
} Unit;

enum { FATE_DIES = 1, FATE_DESTROYED = 2, FATE_READY = 8 };

/* A card in hand, or the typical creature of a cost. A spell the model does
 * not know carries EFF_NONE and is never played. */
enum { EFF_NONE, EFF_SUMMON, EFF_DAMAGE, EFF_WAVE, EFF_DESTROY, EFF_HEAL, EFF_MANA, EFF_CHANNELS, EFF_ENCHANT,
	/* Spells that are each a rule of their own, by the name the rules give them. */
	EFF_UNSUMMON, EFF_EXILE, EFF_ANNIHILATE, EFF_FULL_HEAL, EFF_HALF_HEAL, EFF_DRAW, EFF_REST_ENEMIES,
	EFF_RALLY_ALL, EFF_BURN_MANA, EFF_DRAIN_MANA, EFF_DRAIN_LIFE, EFF_CHANNEL, EFF_HUNGER, EFF_HUNGER_ALL,
	EFF_HUNGER_BOTH, EFF_SACRIFICE_HEAL, EFF_DEVOUR, EFF_POLYMORPH, EFF_SYMBIOSIS, EFF_TWISTER, EFF_BOUNCE_ALL,
	EFF_MIND_BLAST, EFF_DISCARD_ALL, EFF_REVIVE, EFF_FURY, EFF_GRAVE_FIRE, EFF_DISCARD_CREATURES,
	/* Enchantments laid on the caster's own hero: one more ether for every
	 * attacker sent, by either hero; and a forest, which holds the other
	 * army's weak creatures at home. */
	EFF_TAX, EFF_FOREST,
	/* Any other enchantment a hero lays on itself: `amount` says which (HE_*). */
	EFF_CHARM,
	/* A creature of the other army comes over to the caster's; and one whose
	 * power and health change places. */
	EFF_CONTROL, EFF_DELUSION,
	/* A hero loses cards from its hand, which ones being a matter of chance. */
	EFF_DISCARD,
	/* A creature card out of the caster's graveyard back into its hand, and
	 * one out of either graveyard into play under the caster; both hands
	 * given up; cards banned out of hands; a second creature of the kind
	 * aimed at; a creature given for one out of the graveyard; one given so
	 * that another is destroyed; and a hand given up and dealt again. */
	EFF_REPAIR, EFF_REANIMATE, EFF_AMNESIA, EFF_BAN, EFF_CLONE, EFF_EXCHANGE, EFF_SWAP, EFF_REDRAW,
	/* One enchantment taken off whatever it is aimed at; every one that can
	 * be, off everything; and a creature given so that one goes anywhere. */
	EFF_DISPEL, EFF_CLEANSE, EFF_TRADE,
	/* A creature of the caster's own given to the other hero for good. */
	EFF_GIFT,
	/* The second game's plane: a pale creature sent into it; harm to all in
	 * it by the caster's creatures that are not pale; the last enchantment
	 * off a creature and three to a pale one; a card from each hand for
	 * every creature in the plane; a pale creature destroyed or another sent
	 * home; one destroyed in the plane for one out of a graveyard; a card
	 * taken for every pale race; every pale creature sent into the plane;
	 * and three to all in the plane with an enchantment for the caster. */
	EFF_BANISH, EFF_FLUX, EFF_PALE_BLAST, EFF_PALE_CALAMITY, EFF_PALE_CLEAVE, EFF_PALE_REVIVAL, EFF_PALE_THEFT, EFF_VAPORIZE, EFF_RIPPLE,
	/* Power and health for a creature until a turn that is not its hero's ends. */
	EFF_BLESS,
	/* A war banner for the caster: what nothing affects as it is raised it
	 * passes by. */
	EFF_BANNER };
/* What a card names beside its target: a card of the graveyard aimed at, a
 * card of the caster's own graveyard, another creature, an enchantment on
 * what it is aimed at (the kind of a hero's, the card's number of a
 * creature's), or one anywhere (that, and 4096 for each step of its holder:
 * the heroes first, then the creatures). */
enum { CHOICE_NONE, CHOICE_GRAVE, CHOICE_OWN_GRAVE, CHOICE_UNIT, CHOICE_ENCH, CHOICE_ANY_ENCH,
	/* A card of either graveyard: its place, and 64 for the second hero's. */
	CHOICE_ANY_GRAVE };
enum { SCOPE_ENEMY, SCOPE_HEROES, SCOPE_GROUND, SCOPE_FLYING, SCOPE_ALL, SCOPE_BEHIND, SCOPE_SELF, SCOPE_BOTH, SCOPE_STEAL };
enum { AIM_NONE, AIM_CREATURE, AIM_HERO, AIM_ANY };

typedef struct {
	int32_t ready_worth, resting_worth;
	/* A creature's own flags, and those an enchantment lends its target. */
	uint32_t flags, lends;
	int16_t cost, power, toughness, gives_power, gives_toughness;
	int32_t amount;
	int8_t regeneration, race, effect, scope, variable;
	/* An enchantment that holds its target down, and the ether that frees it. */
	int8_t holds, wake;
	/* What it may be aimed at (AIM_*), and whether only at its caster's own. */
	int8_t aim, own;
	/* It may also be cast by the hero that defends. */
	int8_t defence;
	/* A creature's aura beyond `gives_power` and `gives_toughness`, as a
	 * creature in play carries it. */
	uint32_t aura_flags;
	uint8_t aura_to;
	int8_t aura_own, tribe, pale, discards, kind;
	/* Buried under three cards or more, it comes back into play. */
	int8_t rises;
	/* No card at all: the draw that should have brought it will fail. */
	int8_t none;
	/* What the card costs as printed, whatever it costs to play just now. */
	int16_t printed;
	/* Buried, it comes back into its hero's hand as that hero's turn begins. */
	int8_t returns;
	/* The ether channels it costs beside its ether, and what it names beside
	 * its target (CHOICE_*). */
	int8_t channels, choice;
	/* What it does when the other hero makes its holder give it up (the
	 * second game): 1, a creature that walks into play; 2, three cards taken
	 * out of that hero's hand in turn. */
	int8_t answers;
	/* Its class, for what tells them apart (1 a creature, 2 a sorcery, 3 an
	 * enchantment); and for a spell jammer, which trap lets it out. */
	int8_t klass, jams;
	/* The caller's number for the card; whether, once laid on a creature,
	 * nothing takes it off again; and whether it comes back to its caster's
	 * hand as the creature leaves play (1), or only as it dies or is exiled (2). */
	int16_t code;
	int8_t fixed, comes_back;
	/* What an enchantment for a creature does beyond the points it gives. */
	int8_t special;
	/* What a pale creature may do (as for a creature in play). */
	int32_t pale_bits;
	/* The only creatures it may be aimed at: 1 walls, 2 those that fly,
	 * 4 those sent to attack. */
	int8_t only;
	/* No card of a hand but a thing its hero carries: 1 it simply does what
	 * it does, 2 it casts its spell, and either way it costs nothing. And
	 * what it deals everything else on the side of what it hurts. */
	int8_t free, splash;
} Card;
/* It gives its X as power, or as health; a point of each for every pale
 * creature of the other army; the creature's printed power for a turn, which
 * then dies; it takes what would hurt its hero; it keeps the whole race from
 * rising; it keeps the creature out of the plane; it deals a card after every
 * turn of the other hero's; it opens a channel, or gives three ether, each
 * turn; it keeps the creature's wounds open. */
enum { SP_NONE, SP_X_POWER, SP_X_HEALTH, SP_MARK, SP_ALPHA, SP_REDIRECT, SP_BONDS, SP_LOCK, SP_CRIPPLE, SP_STORM, SP_BREEZE, SP_RIOT,
	/* Its caster holds it: as the creature dies it heals that hero by the
	 * creature's health and brings the creature back under it. */
	SP_WATER };

/* What an enchantment on a hero is worth (each copy, and once for the kind,
 * in thousandths), what it lends that hero's creatures and whether it ends
 * with the next turn that is not its hero's. */
typedef struct {
	int32_t each, kind;
	int16_t power, toughness, lethal, regeneration;
	uint32_t flags;
	int8_t expires;
	/* The ether its ability costs and the amount that works by. */
	int8_t cost, amount;
	/* Whose creatures it reaches: its hero's (0), everyone's (1), the other
	 * hero's (2). And the ether it costs to remove, -1 for one nothing removes. */
	int8_t reach;
	int16_t price;
	/* Whether nothing dispels it: 1 one there for good, 2 a trap. */
	int8_t fixed;
	/* The caller's number for its card. */
	int16_t code;
} Charm;

/* What makes an enchantment on a creature more than the points it gives. */
enum { EN_PLAIN, EN_HOLD, EN_TWIST, EN_OVERLOAD, EN_LINK, EN_SKIN, EN_GUARD, EN_BARRIER, EN_CONTROL, EN_DELUSION, EN_ALPHA, EN_QUICK,
	EN_HURTS, EN_REDIRECT, EN_BONDS, EN_WATER, EN_LOCK, EN_CRIPPLE, EN_STORM, EN_BREEZE, EN_RIOT, EN_GIFT };
/* One enchantment on one creature: who laid it, what it is, what it costs
 * to remove (-1 where nothing removes it), and what it gave. */
typedef struct {
	int8_t unit, caster, kind;
	/* It ends with a turn; its card comes back to its caster (as for a
	 * card); and the cards it lets its creature's blow take. */
	int8_t brief, comes_back, robs;
	/* Nothing dispels it; it keeps anything from being aimed at its
	 * creature; it keeps the creature from what it can do; and what the
	 * creature pays to regenerate without it, plus one (nothing: as with it). */
	int8_t fixed, shields, mutes, regen;
	/* What it takes from the health of its creature's hero as each of that
	 * hero's turns ends. */
	int8_t tick;
	int16_t code, price, power, health, lethal;
	uint32_t flags;
	int32_t ready, resting;
} Ench;

typedef struct {
	Unit u[MAX_UNITS];
	int n;
	int health[2], ether[2], channels[2];
	int attacker;
	int phase; /* 0 the attack, 1 the defence */
	int calm; /* nothing can attack this turn */
	int extra[2]; /* ether each hero opens its turn with beyond its channels */
	int held[2]; /* cards in hand when the search began */
	int drawn[2]; /* how many of the cards to come have been drawn */
	int more[2]; /* cards gained or lost beyond those: returned, revived, discarded */
	int grave[2]; /* creatures in this hero's graveyard */
	/* The newest of them by kind, the last to die last; how many of them
	 * are listed; and the cards come back into each hand, by kind. */
	int8_t graves[2][GRAVES], known[2], back[2][BACK];
	int aura_worth[2]; /* what this hero's own enchantments are worth */
	int tax; /* ether an attacker costs to send */
	int taxes[2]; /* how much of that each hero's own enchantments make */
	int ranks; /* attackers sent and blockers set so far this turn */
	/* The cards each hero was to draw are no longer the ones the engine was
	 * told: something drew out of turn, or chance took a card. What is drawn
	 * from here on is a card it cannot name. */
	int blind;
	const void *rules; /* the search this position belongs to */
	int in_fight; /* the declared fight is being played out */
	/* A spirit wizard of this hero has given every warrior spirit wings,
	 * until a turn that is not this hero's ends. */
	int8_t flight[2];
	/* The second game's ether vortices this hero laid in the turn it is
	 * having, which outlast it; and the turns of its own that its stasis has
	 * seen begin. */
	int8_t young[2], stasis_age[2];
	/* Creatures given to each hero since the position was told: every one
	 * brings its ether disturbance two turns nearer. */
	int8_t gifted[2];
	/* What the forest on each hero costs to remove. */
	int16_t forest_price[2];
	int enchs;
	Ench ench[MAX_ENCH];
	int8_t he[2][HE_COUNT]; /* copies of each enchantment standing on each hero */
	int8_t used[2][HERO_ABILITIES]; /* of those with an ability, the copies used this turn */
	/* The forest on each hero: the greatest power a creature of the other
	 * army may have and still be held at home (-1 for none), and what that
	 * forest counts for in `aura_worth`. */
	int forest[2], forest_worth[2];
	int second; /* the second game, whose venom bites before the lethal check */
	/* Card play: known cards already summoned (bits), unknown cards held, the
	 * saved-up chance of a creature among them, own turns begun. */
	int played[2], unknown[2], chance[2], turns[2];
	/* What each hero carries: the uses each thing has left, the round it may
	 * next be used in, and the uses the hero has had of them all. */
	int8_t art_left[2][MAX_ART], art_used[2];
	/* The cards each hero has cast out of its hand: each spent a use of its book. */
	int8_t cast[2];
	/* The war banners each hero holds; whether any creature has anything
	 * from one; and whether they are being reckoned just now. */
	int8_t banner[2], kinned, in_banner;
	int16_t art_ready[2][MAX_ART];
} State;

/* One position the search has already read: what it was worth with so many
 * phases and commands still allowed, whether that is the worth itself or
 * only a bound on it, and the command that was best there. Commands given
 * in another order often arrive at the same position, and it is read once. */
typedef struct {
	uint64_t key;
	int32_t value;
	int32_t kind, a, b, c;
	int8_t phases, steps, bound, filled;
} Entry;
enum { BOUND_EXACT, BOUND_LOWER, BOUND_UPPER };

typedef struct {
	int ai, edition, health_worth, foe_worth, wide, width, leaf_turns, margin, fight_well;
	int power_worth, guard_worth, tough_worth, leaf_attack, blend;
	int64_t nodes, budget;
	int aborted;
	int cards;
	int card_worth, channel_worth;
	int maximum[2]; /* the health each hero began the duel with */
	int opening[2]; /* ether a hero gets once, at the start of its next turn */
	/* The ether disturbance: what each of a hero's next turns costs it in
	 * health as it begins, once a duel has run long. */
	int disturbance[2][MAX_TURNS];
	int chance_step[2], income[2][MAX_TURNS];
	Charm charm[HE_COUNT];
	Card hand[2][SLOTS], typical[2][COSTS], pool[POOL];
	/* Positions already read (none when the search runs without them), and
	 * how many were met again. */
	Entry *table;
	uint64_t mask;
	int64_t met;
	/* When the search must stop, by the clock (0 for never). */
	double deadline;
	/* How many phases ahead the answer was read, when further than asked. */
	int far;
	/* Whether a draw out of turn or a card lost to chance ends the engine's
	 * knowledge of the cards to come. Without it the cards it was told of
	 * stand in for the ones that will really be dealt: not the same cards,
	 * but cards of the same book, and a line is not thought worse merely
	 * for passing through chance. */
	int blinds;
	/* Whether a turn that ends with nobody sent counts for two phases. */
	int even;
	/* Whether, below the first command, a set of attackers or of blocks is
	 * tried in one order only. */
	int ordered;
	/* Below the first command an attack is chosen whole, from this many of
	 * the sets the lookahead ranks best, and a defence whole, from this many
	 * of its block plans; 0 leaves them to be built a creature at a time. */
	int sets, plans;
	/* The order in which each hero's hand as it stands is given up when it
	 * holds too many: a place for every four bits, the first to go lowest. */
	uint32_t trim[2];
	/* A hero whose book is spent: no draw brings it a card any more. */
	int dry[2];
	/* The most cards a hand given up and dealt again can come to, by what
	 * the hero's book still holds: of creatures, and of the rest. */
	int deals[2][2];
	/* Cards in each hand as the search began that are not of its hero's
	 * book, and take up none of its uses. */
	int loose[2];
	/* The wardings that stood on both heroes as the search began, lesser and
	 * greater, by the class of card they make dearer: what a card is told to
	 * cost already counts them. And the spell jammers among the creature
	 * cards known by kind, by the trap that lets each out (0 for none). */
	int wards[4][2];
	int8_t jammers[3];
	/* What a copy of the attack tax costs to remove, and what it is worth. */
	int tax_price, tax_worth;
	/* What each hero carries, as cards; the rounds each waits after a use,
	 * the phases it may be used in (1 the attack, 2 the defence); the uses
	 * the duel allows each hero; and the turns begun before the search. */
	Card art[2][MAX_ART];
	int8_t art_gap[2][MAX_ART], art_phase[2][MAX_ART];
	int art_limit[2], serial;
	/* What an ether storm or breeze on a creature counts for, in thousandths
	 * of the worth the caller gives them: they pay on turns a reading may
	 * not reach. */
	int later;
	/* What a war banner costs to remove. */
	int banner_price;
	/* A reading that only asks whether the engine's hero wins whatever the
	 * other does: every command of both is read, nothing is weighed, and a
	 * line that ends undecided counts as not won. `prove` is how many of its
	 * own turns such a win is looked for in before the usual reading, and
	 * `prove_share` the part of the budget, in hundredths, it may take; turns
	 * fewer than `prove_from` were read before, and held no such win. */
	int proof, prove, prove_share, prove_from;
	/* How much of the damage in sight a turn of that reading may be thought
	 * to deal, in hundredths; 0 gives no line up on that count. */
	int sight;
	/* The command chosen is held against the same kind of reading for the
	 * other hero: `guard` of that hero's turns, `guard_share` hundredths of
	 * the budget for each such reading. First commands found to lose that
	 * way are set aside (`banned`) while the choice is made again. */
	int guard, guard_share, bans;
	/* Set for those readings: chance then deals the cards the engine was
	 * told of, as in its usual reading. A win is proved only where chance
	 * has no part, but a hero is not safe from a loss because a card it
	 * cannot name might turn up. */
	int guarding;
	int32_t banned[MAX_BANS][4];
} Search;

/* The time, in thousandths of a second, from a clock that only runs on. */
#if defined(_WIN32)
__declspec(dllimport) int __stdcall QueryPerformanceCounter(long long *count);
__declspec(dllimport) int __stdcall QueryPerformanceFrequency(long long *frequency);
static double now_ms(void) {
	long long count = 0, frequency = 1;
	QueryPerformanceCounter(&count);
	QueryPerformanceFrequency(&frequency);
	return (double)count * 1000.0 / (double)(frequency > 0 ? frequency : 1);
}
#else
static double now_ms(void) {
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1000000.0;
}
#endif

typedef struct { int8_t target[MAX_UNITS]; int score; } Plan;
typedef struct { uint32_t mask; int score; } Set;

static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int64_t imin64(int64_t a, int64_t b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }

/* A hero spends ether: on a card, an ability, an attacker sent under a tax,
 * a creature brought back from its wounds. */
static void hurt_hero(State *s, int side, int amount, int source);
static int army_size(const State *s, int side);
/* How many enchantments of one kind a creature wears. */
static int worn_kind(const State *s, int unit, int kind) {
	int count = 0;
	for (int r = 0; r < s->enchs; r++) count += s->ench[r].unit == unit && s->ench[r].kind == kind;
	return count;
}

/* Those of one kind a hero has laid on creatures still in play. */
static int cast_kind(const State *s, int caster, int kind) {
	int count = 0;
	for (int r = 0; r < s->enchs; r++) count += s->ench[r].caster == caster && s->ench[r].kind == kind && !(s->u[s->ench[r].unit].flags & F_DEAD);
	return count;
}

/* Whether an enchantment keeps a creature from what it can do. */
static int muted(const State *s, int unit) {
	for (int r = 0; r < s->enchs; r++)
		if (s->ench[r].unit == unit && s->ench[r].mutes) return 1;
	return 0;
}

/* Whether earth bonds on a creature of its race keep it from rising. */
static int bound(const State *s, const Unit *u) {
	if (u->flags & F_NO_AFFECT) return 0;
	for (int r = 0; r < s->enchs; r++) {
		const Unit *holder = &s->u[s->ench[r].unit];
		if (s->ench[r].kind == EN_BONDS && !(holder->flags & F_DEAD) && holder->race == u->race) return 1;
	}
	return 0;
}

static int least_unit(const State *s, int side);
typedef struct { int holder, what, gain; } Dispel;
static int dispel_choices(const Search *x, const State *s, int side, Dispel *out, int limit);
static void pay(State *s, int side, int amount) {
	if (amount <= 0) return;
	s->ether[side] -= amount;
	/* Ether thorns in play hurt whoever spends, once for each. */
	for (int copies = s->he[0][HE_MNTH] + s->he[1][HE_MNTH]; copies > 0; copies--) hurt_hero(s, side, amount, -1);
}

/* A stasis in play: no hero's ether is filled again, and in the second game
 * nothing else gives ether or moves a channel either. */
static inline int stasis(const State *s) {
	return s->he[0][HE_STSI] + s->he[1][HE_STSI] > 0;
}

/* Ether a spell or an ability gives a hero, and channels one moves. */
static void gain_ether(State *s, int side, int amount) {
	if (s->second && stasis(s)) return;
	s->ether[side] += amount;
}

static void change_channels(State *s, int side, int delta) {
	if (s->second && stasis(s)) return;
	s->channels[side] += delta;
}

/* The ether vortices that multiply what a hero's channels give: its own in
 * the second game, every one in play in the first. */
static inline int vortices(const State *s, int side) {
	return s->second ? s->he[side][HE_MNVR] : s->he[0][HE_MNVR] + s->he[1][HE_MNVR];
}

/* What a card costs to play now. A warding makes every card of one class
 * dearer for both heroes, the lesser by two and the greater by what the card
 * costs as printed; those laid or gone since the search began change what
 * the engine was told. */
static const int8_t WARD_LESSER[4] = { 0, HE_LCWR, HE_LSWR, HE_LEWR }, WARD_GREATER[4] = { 0, HE_GCWR, HE_GSWR, HE_GEWR };
static int card_cost(const Search *x, const State *s, const Card *c) {
	if (c->free) return 0;
	if (!s->second || c->klass <= 0 || c->cost < 0) return c->cost;
	int lesser = s->he[0][WARD_LESSER[c->klass]] + s->he[1][WARD_LESSER[c->klass]] - x->wards[c->klass][0];
	int greater = s->he[0][WARD_GREATER[c->klass]] + s->he[1][WARD_GREATER[c->klass]] - x->wards[c->klass][1];
	return imax(0, c->cost + 2 * lesser + c->printed * greater);
}

/* A fatal disease keeps creatures from regenerating and from healing: in the
 * first game those of the hero it was not laid by, in the second everyone's. */
static inline int diseased(const State *s, int side) {
	return s->second ? s->he[0][HE_FTDS] + s->he[1][HE_FTDS] > 0 : s->he[1 - side][HE_FTDS] > 0;
}

/* Nobody may attack while a fog or a wall's distortion lies on either hero. */
static inline int fogged(const State *s) {
	return s->calm || s->he[0][HE_FOGG] + s->he[1][HE_FOGG] + s->he[0][HE_WLDT] + s->he[1][HE_WLDT] > 0;
}

/* A creature is sent to attack or set to block: it takes its place in the
 * order the fight will be played in. */
static inline void ranked(State *s, Unit *u) {
	if (s->ranks < 250) s->ranks++;
	u->rank = (uint8_t)s->ranks;
}

/* A guard goes only beside another of its race already sent. */
static int team_partner(const State *s, int i) {
	for (int j = 0; j < s->n; j++)
		if (j != i && (s->u[j].flags & F_ATTACKING) && !(s->u[j].flags & (F_DEAD | F_GONE)) && s->u[j].race == s->u[i].race
			&& s->u[j].owner == s->u[i].owner) return 1;
	return 0;
}

/* Whether every guard in a set of attackers has someone to go beside: one of
 * its race already sent, or one in the set that is no guard and so can be
 * sent before it. */
static int team_fits(const State *s, uint32_t mask) {
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (!(mask >> i & 1) || !(u->flags & F_TEAM) || (u->flags & F_ATTACKING)) continue;
		int partner = team_partner(s, i);
		for (int j = 0; j < s->n && !partner; j++)
			partner = j != i && (mask >> j & 1) && !(s->u[j].flags & F_TEAM) && s->u[j].race == u->race && s->u[j].owner == u->owner;
		if (!partner) return 0;
	}
	return 1;
}

static int same_kind(const Unit *a, const Unit *b) {
	return a->owner == b->owner && a->power == b->power && a->toughness == b->toughness && a->flags == b->flags
		&& a->regeneration == b->regeneration && a->skins == b->skins && a->guards == b->guards
		&& a->ready_worth == b->ready_worth && a->resting_worth == b->resting_worth && a->race == b->race;
}

/* Moves creatures that are alike in every way next to each other. */
static void group_alike(const State *s, int *list, int count) {
	for (int i = 1; i < count; i++) {
		int unit = list[i], at = -1;
		for (int j = i - 1; j >= 0 && at < 0; j--)
			if (same_kind(&s->u[list[j]], &s->u[unit])) at = j;
		if (at < 0 || at == i - 1) continue;
		for (int k = i; k > at + 1; k--) list[k] = list[k - 1];
		list[at + 1] = unit;
	}
}

/* A creature's health as it shows: what only weakens leaves it a point,
 * what kills takes its points after that. */
static inline void settle_health(Unit *u) {
	u->toughness = (int16_t)(imax(1, u->raw) - u->lethal);
	if (u->alpha && u->toughness > 1) u->toughness = 1;
}

/* A creature's power changes, counted from where it stands without the
 * floor of nothing under it. */
static inline void add_power(Unit *u, int change) {
	int real = u->power - u->under + change;
	u->power = (int16_t)imax(0, real);
	u->under = (int16_t)imax(0, -real);
}

static inline int ready(const Unit *u) {
	return !(u->flags & (F_DEAD | F_RESTING | F_SICK | F_PLANE));
}

/* What the rules let attack. The search asks for more than this: a creature
 * with no power is legal but pointless, so `can_attack` leaves it at home. */
static int can_declare(const State *s, const Unit *u) {
	return u->owner == s->attacker && ready(u) && !(u->flags & (F_NO_ATTACK | F_PLANE)) && !fogged(s)
		&& imax(0, u->power) > s->forest[1 - u->owner];
}

static int can_attack(const State *s, const Unit *u) {
	return can_declare(s, u) && u->power > 0;
}

static int can_block(const Unit *attacker, const Unit *blocker) {
	if (attacker->flags & F_UNBLOCKABLE) return 0;
	if ((attacker->flags & F_FLY) && !(blocker->flags & F_FLY)) return 0;
	if ((attacker->flags & F_ELUSIVE) && !(blocker->flags & F_WALL)) return 0;
	return 1;
}

/* ---------------------------------------------------------------- evaluation */

static int health_worth(const Search *x, int health) {
	int v = health * x->health_worth;
	if (x->edition == 1) v += imin(health, 5) * 300 + imin(health, 8) * 200 + imin(health, 12) * 100;
	return v;
}

/* What a hero's ether channels are worth, as the search reckons them. */
static int channel_worth(const Search *x, int channels) {
	if (x->edition != 1) return channels * x->channel_worth;
	int term = channels * x->channel_worth;
	if (channels > 9) term = (channels - 9) * 500 + 5 * x->channel_worth + 3000;
	else if (channels > 5) term = (channels - 5) * 750 + 5 * x->channel_worth;
	if (term > 20000) term = (term - 20000) / 5 + 20000;
	return term;
}

/* Cards still in this hero's hand. */
static int cards_held(const State *s, int side) {
	int played = 0;
	for (int i = 0; i < SLOTS; i++) played += (s->played[side] >> i) & 1;
	for (int j = 0; j < BACK; j++) played -= s->back[side][j] != 0;
	return imax(0, s->held[side] + s->drawn[side] + s->more[side] - played);
}

/* The uses a hero may still have of the things it carries. */
static int uses_left(const Search *x, const State *s, int side) {
	int left = 0;
	for (int k = 0; k < MAX_ART; k++)
		if (x->art[side][k].free) left += s->art_left[side][k];
	return imax(0, imin(left, x->art_limit[side] - s->art_used[side]));
}

/* The position's worth for the computer; `turns` left makes a sooner end count more. */
static int evaluate(const Search *x, const State *s, int turns) {
	int mine = s->health[x->ai], theirs = s->health[1 - x->ai];
	if (mine <= 0) return theirs <= 0 ? 0 : -(WIN + turns * 1000);
	if (theirs <= 0) return WIN + turns * 1000;
	int v = health_worth(x, mine) - health_worth(x, theirs) / 100 * x->foe_worth;
	/* A card in hand, an ether channel and the hero's own enchantments count
	 * as they do in the search this engine stands in for. */
	v += (cards_held(s, x->ai) - cards_held(s, 1 - x->ai)) * x->card_worth;
	v += (uses_left(x, s, x->ai) - uses_left(x, s, 1 - x->ai)) * x->card_worth;
	v += channel_worth(x, s->channels[x->ai]) - channel_worth(x, s->channels[1 - x->ai]);
	v += s->aura_worth[x->ai] - s->aura_worth[1 - x->ai];
	/* A channel every turn, or three ether, for whoever laid it, while its
	 * creature lives: a sturdy one keeps it longer. */
	if (x->later > 0)
		for (int r = 0; r < s->enchs; r++) {
			const Ench *e = &s->ench[r];
			if ((e->kind != EN_STORM && e->kind != EN_BREEZE) || (s->u[e->unit].flags & F_DEAD)) continue;
			int w = ((e->kind == EN_STORM ? 2500 : 2000) + 50 * imax(0, imin(s->u[e->unit].toughness, 10))) * x->later / 1000;
			v += e->caster == x->ai ? w : -w;
		}
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->flags & F_DEAD) continue;
		int w = (u->flags & F_RESTING) ? u->resting_worth : u->ready_worth;
		if (!(u->flags & F_RESTING) && (u->flags & F_SICK) && !(u->flags & F_NO_ATTACK)) w -= 300;
		v += u->owner == x->ai ? w : -w;
	}
	return v;
}

/* Damage the defending hero would take from an attack by everything the side
 * to move can send, after the defender's ready creatures each stop one. */
static int incoming(const Search *x, const State *s) {
	int attackers[MAX_UNITS], count = 0;
	for (int i = 0; i < s->n; i++)
		if (can_attack(s, &s->u[i])) attackers[count++] = i;
	if (count == 0) return 0;
	for (int i = 1; i < count; i++) {
		int k = attackers[i], j = i - 1;
		while (j >= 0 && s->u[attackers[j]].power < s->u[k].power) { attackers[j + 1] = attackers[j]; j--; }
		attackers[j + 1] = k;
	}
	if (s->tax > 0) count = imin(count, s->ether[s->attacker] / s->tax);
	int ground = 0, flying = 0, walls = 0;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->owner == s->attacker || !ready(u)) continue;
		if (u->flags & F_WALL) walls++;
		else if (u->flags & F_FLY) flying++;
		else ground++;
	}
	int through = 0;
	for (int i = 0; i < count; i++) {
		const Unit *a = &s->u[attackers[i]];
		int stopped = 0;
		if (a->flags & F_UNBLOCKABLE) stopped = 0;
		else if (a->flags & F_ELUSIVE) { if (walls) { walls--; stopped = 1; } }
		else if (a->flags & F_FLY) { if (flying) { flying--; stopped = 1; } }
		else if (ground) { ground--; stopped = 1; }
		else if (walls) { walls--; stopped = 1; }
		else if (flying) { flying--; stopped = 1; }
		if (!stopped) through += a->power;
		else if (a->flags & F_TRAMPLE) through += a->power / 2;
	}
	return through;
}

/* The worth of a position where the search stops: what stands, and what the
 * side to move could at once do to the other hero. */
static int evaluate_leaf(const Search *x, const State *s, int turns) {
	int v = evaluate(x, s, turns);
	if (v >= WIN || v <= -WIN) return v;
	int through = incoming(x, s);
	if (through > 0) {
		int cost = through * x->health_worth / 2;
		if (s->attacker == x->ai) cost = cost / 100 * x->foe_worth;
		if (through >= s->health[1 - s->attacker]) cost += LETHAL;
		v += s->attacker == x->ai ? cost : -cost;
	}
	return v;
}

/* ------------------------------------------------------------------- combat */

static void strip_hero(State *s, int side);
static void discard_cards(State *s, int side, int count, int spells, int cause);
static void draw_cards(State *s, int side, int count);

static void lend_army(const Search *x, State *s, int side, int k, int copies);

/* An enchantment comes to stand on a hero, or `copies` of it go. */
static void lay_charm(const Search *x, State *s, int holder, int k) {
	s->aura_worth[holder] += x->charm[k].each + (s->he[holder][k] == 0 ? x->charm[k].kind : 0);
	if (s->he[holder][k] < 100) s->he[holder][k]++;
	lend_army(x, s, holder, k, 1);
}

static void drop_charm(const Search *x, State *s, int holder, int k, int copies) {
	copies = imin(copies, s->he[holder][k]);
	if (copies <= 0) return;
	s->he[holder][k] = (int8_t)(s->he[holder][k] - copies);
	s->aura_worth[holder] -= x->charm[k].each * copies + (s->he[holder][k] == 0 ? x->charm[k].kind : 0);
	if (k < HERO_ABILITIES && s->used[holder][k] > s->he[holder][k]) s->used[holder][k] = s->he[holder][k];
	lend_army(x, s, holder, k, -copies);
}

/* A hero is dealt cards out of turn: not the ones the engine was told of,
 * where it keeps count of that. */
/* Whether a hero's book can put another card into its hand. The first
 * game's deals without end while it has cards at all; the second's holds
 * only so many uses, and deals no card whose uses are all in the hand
 * already - but one given up may be dealt again. */
static int book_room(const Search *x, const State *s, int side) {
	if (!s->second) return x->dry[side] ? 0 : 100;
	return imax(0, x->deals[side][0] + x->deals[side][1] + x->loose[side] - s->cast[side] - cards_held(s, side));
}

static void deal(const Search *x, State *s, int who, int count) {
	if (count <= 0) return;
	if (x->blinds) {
		s->more[who] += imin(count, book_room(x, s, who));
		s->blind = 1;
	} else draw_cards(s, who, count);
}

/* Hurts a hero. `source` is the creature whose blow it is (-1 for anything
 * else); `passed` marks what a feedback, a chain or a pain link sends on,
 * which nothing sends on again. */
static void spell_damage(State *s, int who, int amount);
static void hurt_hero_by(State *s, int side, int amount, int source, int passed) {
	if (amount <= 0) return;
	const Search *x = (const Search *)s->rules;
	/* A stone skin turns blows, not spells. */
	if (source >= 0) amount -= 2 * s->he[side][HE_STSK];
	if (amount <= 0) return;
	int before = s->health[side], landed = 0;
	/* An energy barrier takes three off whatever is no blow; a lifeguard
	 * turns one hurt aside whole, and is gone. */
	if (source < 0) amount -= 3 * s->he[side][HE_ENBR];
	int turned = 0, guarded = amount > 0 && s->he[side][HE_LFGR] > 0;
	if (guarded) drop_charm(x, s, side, HE_LFGR, 1);
	else if (amount > 0 && !passed && s->enchs > 0) {
		/* A redirection on creatures of its army sends the hurt to them,
		 * once for each copy, and the hero takes nothing; a pain link on
		 * one of them does not send it back. */
		int8_t copies[MAX_UNITS];
		int n = s->n;
		for (int i = 0; i < n; i++) {
			copies[i] = s->u[i].owner == side && !(s->u[i].flags & F_DEAD) ? (int8_t)worn_kind(s, i, EN_REDIRECT) : 0;
			turned += copies[i];
		}
		for (int i = 0; turned && i < n; i++) {
			if (!copies[i] || (s->u[i].flags & F_DEAD)) continue;
			int8_t linked = s->u[i].linked;
			s->u[i].linked = 0;
			spell_damage(s, i, amount * copies[i]);
			s->u[i].linked = linked;
		}
	}
	if (amount > 0 && !turned && !guarded) {
		/* A feedback sends it all to the other hero, once for each copy,
		 * and its own hero takes nothing; an ethereal chain sends the same
		 * again beside: once for each in the first game, once in all and
		 * doubled in the second. */
		int copies = passed ? 0 : s->he[side][HE_FDBK] + s->he[side][HE_LNRD];
		for (int i = 0; i < copies && s->health[1 - side] >= 1; i++) hurt_hero_by(s, 1 - side, amount, -1, 1);
		int mirrors = passed ? 0 : s->he[side][HE_ETCH];
		if (s->second) mirrors = imin(mirrors, 1);
		for (int i = 0; i < mirrors && s->health[1 - side] >= 1; i++) hurt_hero_by(s, 1 - side, s->second ? amount * 2 : amount, -1, 1);
		if (copies == 0) {
			s->health[side] = imax(0, before - amount);
			landed = amount;
		}
	}
	if (source < 0) return;
	Unit *a = &s->u[source];
	if (landed) {
		if (a->flags & F_LIFETAP) s->health[a->owner] += imin(landed, before);
		if (a->feeds) draw_cards(s, a->owner, 1);
	}
	if (a->flags & F_STINGER) a->flags |= F_POISONED;
	/* A snake's blow leaves its venom in the hero. */
	if (a->envenoms) lay_charm(x, s, side, HE_ESWS);
	/* A blow that robs takes cards out of the hand of the hero it reaches,
	 * unless a creature took the blow for it. */
	if (a->discards > 0 && !turned) discard_cards(s, side, a->discards, 0, 1 - side);
	/* A stripping strike leaves the hero it reaches with nothing laid on it. */
	if (a->flags & F_DISENCHANT) strip_hero(s, side);
}

static void hurt_hero(State *s, int side, int amount, int source) {
	hurt_hero_by(s, side, amount, source, 0);
}

/* What a pain link passes on to the hero of the creature that was hurt. */
static void pain_hero(State *s, int side, int amount) {
	hurt_hero_by(s, side, amount, -1, 1);
}

/* Whether a creature may change aspect now: a planar seal forbids it, and
 * an aspect ward on its hero must be paid for. */
static int may_shift(const State *s, const Unit *u) {
	if (s->he[0][HE_PLSL] + s->he[1][HE_PLSL] > 0) return 0;
	return s->ether[u->owner] >= s->he[u->owner][HE_PRWR];
}

/* What an aspect ward takes for it: an ether and a point of health for each. */
static void shift_toll(State *s, int owner) {
	int warded = s->he[owner][HE_PRWR];
	s->ether[owner] -= warded;
	for (int i = 0; i < warded; i++) hurt_hero(s, owner, 1, -1);
}

/* A creature at lethal damage: it regenerates if its hero can pay, else a
 * bright pale creature dissipates into the plane (healed, resting and out of
 * the fight), else it dies. */
static void finish_unit(State *s, int index);
static void perish_unit(State *s, int index);
static void spell_damage(State *s, int who, int amount);
static void lost_leader(State *s, int dead);

/* What a creature's leaving play sets off, whichever way it left. */
static void summon(const Search *x, State *s, int side, const Card *c);
static int unbury(State *s, int side, int place);

/* The war banners are reckoned again: each creature they reach has a point
 * of power and of health for every other of its race in play and out of the
 * plane. Whoever that leaves without health goes, and takes its own point
 * from the rest. */
static void banners(State *s) {
	int copies = s->banner[0] + s->banner[1];
	if ((!copies && !s->kinned) || s->in_banner) return;
	const Search *x = (const Search *)s->rules;
	s->in_banner = 1;
	for (int pass = 0; pass < MAX_UNITS; pass++) {
		int fell = 0;
		s->kinned = 0;
		for (int i = 0; i < s->n; i++) {
			Unit *u = &s->u[i];
			if (u->flags & F_DEAD) continue;
			int reach = imax(0, copies - u->spared), kin = 0;
			if (reach > 0)
				for (int j = 0; j < s->n; j++)
					if (j != i && !(s->u[j].flags & (F_DEAD | F_PLANE | F_GONE)) && s->u[j].race == u->race) kin++;
			int want = imin(100, kin * reach), change = want - u->kin;
			if (want) s->kinned = 1;
			if (!change) continue;
			add_power(u, change);
			u->raw = (int16_t)(u->raw + change);
			settle_health(u);
			u->kin = (int8_t)want;
			if (x) {
				int gain = change * (((u->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth) + x->tough_worth);
				u->ready_worth += gain;
				u->resting_worth += gain;
			}
		}
		for (int i = 0; i < s->n; i++) {
			Unit *u = &s->u[i];
			if ((u->flags & (F_DEAD | F_GONE)) || u->damage < u->toughness) continue;
			perish_unit(s, i);
			fell = 1;
		}
		if (!fell) break;
	}
	s->in_banner = 0;
}

/* `how`: 0 it died, 1 it was exiled, 2 it went back to a hand. */
static void left_play(State *s, int index, int how) {
	/* The water links on it, in the order they were laid. */
	int8_t links[MAX_ENCH];
	int linked = 0;
	for (int r = 0; r < s->enchs; r++)
		if (s->ench[r].unit == index && s->ench[r].kind == EN_WATER) links[linked++] = s->ench[r].caster;
	/* What it wore goes with it, and some of that back to the hand of the
	 * hero that laid it. */
	for (int r = s->enchs - 1; r >= 0; r--) {
		const Ench *e = &s->ench[r];
		if (e->unit != index) continue;
		if (e->comes_back == 1 || (e->comes_back == 2 && how != 2)) s->more[e->caster]++;
		/* A lock on a pale creature costs the hero it came with its printed
		 * power as it leaves. */
		if (e->kind == EN_LOCK && s->u[index].pale && s->rules) {
			const Unit *gone = &s->u[index];
			int power = gone->kind > 0 ? ((const Search *)s->rules)->pool[gone->kind - 1].power : 0;
			if (power > 0) hurt_hero(s, gone->home ? gone->home - 1 : gone->owner, power, -1);
		}
		memmove(&s->ench[r], &s->ench[r + 1], (size_t)(s->enchs - r - 1) * sizeof(Ench));
		s->enchs--;
	}
	if (linked && how == 0 && s->rules) {
		/* Each link heals its caster by the dead creature's health (as
		 * printed, in the second game), and the first caster with room
		 * takes the creature back out of the graveyard for its own. */
		const Search *x = (const Search *)s->rules;
		const Unit *dead = &s->u[index];
		int owner = dead->home ? dead->home - 1 : dead->owner, kind = dead->kind, back = 0;
		int health = s->second && kind > 0 ? x->pool[kind - 1].toughness : dead->toughness;
		for (int k = 0; k < linked; k++) {
			int caster = links[k];
			s->health[caster] += imax(0, health);
			int lies = s->known[owner] > 0 && s->graves[owner][s->known[owner] - 1] == kind;
			if (back || kind <= 0 || !lies || army_size(s, caster) >= ARMY || s->n >= MAX_UNITS) continue;
			back = 1;
			/* The first game takes the oldest card of the graveyard, whichever it is. */
			if (s->second) unbury(s, owner, s->known[owner] - 1);
			else if (s->grave[owner] > s->known[owner]) s->grave[owner]--;
			else unbury(s, owner, 0);
			summon(x, s, caster, &x->pool[kind - 1]);
		}
	}
	lost_leader(s, index);
	banners(s);
	/* A walking horror's last wave goes out as it dies or is exiled, not as
	 * it goes back to a hand. */
	if (s->u[index].horror && how != 2) {
		int n = s->n;
		for (int i = 0; i < n; i++)
			if (i != index) spell_damage(s, i, 3);
	}
}

/* A leader's death takes its aura off every creature it covered, which can
 * leave one of them at lethal damage in turn. */
static void lost_leader(State *s, int dead) {
	const Unit *l = &s->u[dead];
	if (l->gives_power == 0 && l->gives_toughness == 0 && l->gives_flags == 0) return;
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (!(u->leaders >> dead & 1)) continue;
		u->leaders &= ~(1u << dead);
		/* What it had from this aura alone goes with it. */
		uint32_t gone = l->gives_flags & u->aura_flags;
		for (int j = 0; j < s->n && gone; j++)
			if ((u->leaders >> j & 1) && !(s->u[j].flags & F_DEAD)) gone &= ~s->u[j].gives_flags;
		u->flags &= ~gone;
		u->aura_flags &= ~gone;
		add_power(u, -l->gives_power);
		u->raw = (int16_t)(u->raw - l->gives_toughness);
		settle_health(u);
		/* Wounds that this leaves fatal kill outright: nothing regenerates. */
		if (!(u->flags & (F_DEAD | F_GONE)) && u->damage >= u->toughness) perish_unit(s, i);
	}
}

/* A dead creature's card lies in the graveyard of the hero that brought it. */
static void bury(State *s, const Unit *t) {
	int side = t->home ? t->home - 1 : t->owner;
	s->grave[side]++;
	if (s->known[side] >= GRAVES) {
		memmove(s->graves[side], s->graves[side] + 1, GRAVES - 1);
		s->known[side] = GRAVES - 1;
	}
	s->graves[side][s->known[side]++] = t->kind;
	const Search *x = (const Search *)s->rules;
	/* Barbed souls deal the dead creature's hero a card for each copy: any
	 * copy in play in the first game, that hero's own in the second. */
	if (x) deal(x, s, t->owner, s->second ? s->he[t->owner][HE_BASO] : s->he[0][HE_BASO] + s->he[1][HE_BASO]);
	/* A spiritual web heals its hero for every creature buried. */
	for (int side = 0; side < 2; side++) s->health[side] += s->he[side][HE_SPWB];
	/* A dying bat takes a card out of the other hero's hand. */
	if (t->mourned) discard_cards(s, 1 - t->owner, 1, 0, t->owner);
}

/* The card at one place of a listed graveyard leaves it; its kind. */
static int unbury(State *s, int side, int place) {
	int kind = 0;
	if (place >= 0 && place < s->known[side]) {
		kind = s->graves[side][place];
		memmove(s->graves[side] + place, s->graves[side] + place + 1, (size_t)(s->known[side] - place - 1));
		s->known[side]--;
	}
	if (s->grave[side] > 0) s->grave[side]--;
	if (s->known[side] > s->grave[side]) s->known[side] = (int8_t)s->grave[side];
	return kind;
}

/* A card comes into a hand from the board or a graveyard: one the engine
 * knows it may play again, while it has room to hold it apart. */
static void take_back(State *s, int side, int kind) {
	if (kind > 0)
		for (int j = 0; j < BACK; j++)
			if (!s->back[side][j]) {
				s->back[side][j] = (int8_t)kind;
				return;
			}
	s->more[side]++;
}

static void finish_unit(State *s, int index) {
	Unit *t = &s->u[index];
	if (t->toughness <= 0) {
		t->flags |= F_DEAD;
		bury(s, t);
		left_play(s, index, 0);
		return;
	}
	if (t->regeneration > 0 && !(t->flags & F_NO_REGEN) && !diseased(s, t->owner) && s->ether[t->owner] >= t->regeneration) {
		/* A complicity heals its hero by five whenever anything regenerates. */
		for (int side = 0; side < 2; side++) s->health[side] += 5 * s->he[side][HE_COPL];
		pay(s, t->owner, t->regeneration);
		t->damage = 0;
		t->flags |= F_REGENERATED;
		/* The second game takes a creature that regenerates outside a fight
		 * out of the attack or the block it stood in. */
		if (s->second && !s->in_fight) {
			t->flags &= ~(uint32_t)F_ATTACKING;
			t->blocks = -1;
		}
	} else if ((t->flags & F_DISSIPATES) && may_shift(s, t) && !worn_kind(s, (int)(t - s->u), EN_LOCK)) {
		shift_toll(s, t->owner);
		t->damage = 0;
		t->pale_used = (int8_t)((t->pale_used & ~4) | ((t->flags & F_RESTING) ? 4 : 0));
		t->flags |= F_RESTING | F_GONE;
		t->flags &= ~(uint32_t)F_ATTACKING;
		banners(s);
	} else {
		t->flags |= F_DEAD;
		bury(s, t);
		left_play(s, index, 0);
	}
}

/* Dies outright, with no chance to regenerate. */
static void kill_unit(State *s, int index) {
	Unit *t = &s->u[index];
	if (t->flags & F_DEAD) return;
	t->flags |= F_DEAD;
	t->flags &= ~(uint32_t)F_ATTACKING;
	bury(s, t);
	left_play(s, index, 0);
}

/* Leaves play without dying: exiled, or back in its owner's hand. */
static void remove_unit(State *s, int index, int to_hand) {
	Unit *t = &s->u[index];
	if (t->flags & F_DEAD) return;
	t->flags |= F_DEAD;
	t->flags &= ~(uint32_t)F_ATTACKING;
	/* Its card goes back to the hero that brought it, whoever commands it now. */
	if (to_hand) take_back(s, t->home ? t->home - 1 : t->owner, t->kind);
	left_play(s, index, to_hand ? 2 : 1);
}

/* Left without health by a change to what it is rather than by a blow:
 * nothing regenerates from that. */
static void perish_unit(State *s, int index) {
	Unit *t = &s->u[index];
	if (t->flags & (F_DEAD | F_GONE)) return;
	if ((t->flags & F_DISSIPATES) && t->toughness > 0) {
		/* It passes into the plane as it stands, not laid to rest by a blow. */
		t->damage = 0;
		t->flags |= F_GONE;
		t->flags &= ~(uint32_t)F_ATTACKING;
		banners(s);
	} else kill_unit(s, index);
}

/* Whether what stands on the hero `holder` reaches the army of `side`. */
static int charm_reaches(const Search *x, int k, int holder, int side) {
	int reach = x->charm[k].reach;
	return reach == 1 || (reach == 2 ? side != holder : side == holder);
}

/* `copies` of an enchantment on its hero come to cover one creature, or,
 * when negative, leave it. */
static void lend_unit(const Search *x, Unit *u, int k, int copies) {
	const Charm *c = &x->charm[k];
	if (u->flags & (F_NO_AFFECT | F_PLANE)) return;
	int had = u->power, before = u->toughness;
	add_power(u, c->power * copies);
	u->raw = (int16_t)(u->raw + c->toughness * copies);
	u->lethal = (int16_t)(u->lethal + c->lethal * copies);
	settle_health(u);
	int gain = (u->power - had) * ((u->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth)
		+ (u->toughness - before) * x->tough_worth;
	u->ready_worth += gain;
	u->resting_worth += gain;
	if (copies > 0) {
		uint32_t added = c->flags & ~u->flags;
		u->flags |= added;
		u->lent |= added;
		if (c->regeneration > 0 && (u->regeneration == 0 || c->regeneration < u->regeneration)) u->regeneration = (int8_t)c->regeneration;
	} else {
		u->flags &= ~(u->lent & c->flags);
		u->lent &= ~c->flags;
	}
}

/* The same for every creature the enchantment on `side`'s hero reaches. */
static void lend_army(const Search *x, State *s, int side, int k, int copies) {
	const Charm *c = &x->charm[k];
	if (!c->power && !c->toughness && !c->lethal && !c->flags && !c->regeneration) return;
	int n = s->n;
	for (int i = 0; i < n; i++) {
		Unit *u = &s->u[i];
		if ((u->flags & (F_DEAD | F_GONE)) || !charm_reaches(x, k, side, u->owner)) continue;
		lend_unit(x, u, k, copies);
	}
	for (int i = 0; i < n; i++)
		if (!(s->u[i].flags & (F_DEAD | F_GONE)) && s->u[i].damage >= s->u[i].toughness) perish_unit(s, i);
}

/* A creature comes out of the Colourless Plane, under whatever stands on
 * the heroes; and one in play goes into it, out from under all that and out
 * of the fight. 0 when it may not change aspect. */
static int manifest(const Search *x, State *s, int i) {
	Unit *u = &s->u[i];
	if ((u->flags & F_DEAD) || !(u->flags & (F_PLANE | F_GONE))) return 1;
	if (!may_shift(s, u)) return 0;
	shift_toll(s, u->owner);
	int plane = (u->flags & F_PLANE) != 0;
	/* One that dissipated comes back as it was when it did. */
	if ((u->flags & F_GONE) && !(u->pale_used & 4)) u->flags &= ~(uint32_t)F_RESTING;
	u->flags &= ~(uint32_t)(F_PLANE | F_GONE);
	/* A pale creature out of the plane goes back into it rather than die. */
	if (s->second && u->pale) u->flags |= F_DISSIPATES;
	for (int k = 0; plane && k < HE_COUNT; k++) {
		int copies = 0;
		for (int holder = 0; holder < 2; holder++)
			if (charm_reaches(x, k, holder, u->owner)) copies += s->he[holder][k];
		if (copies > 0) lend_unit(x, u, k, copies);
	}
	banners(s);
	if (!(u->flags & (F_DEAD | F_GONE)) && u->damage >= u->toughness) perish_unit(s, i);
	return 1;
}

static int banish(const Search *x, State *s, int i) {
	Unit *u = &s->u[i];
	if (u->flags & (F_DEAD | F_PLANE | F_GONE)) return 1;
	if (!may_shift(s, u) || worn_kind(s, i, EN_LOCK)) return 0;
	shift_toll(s, u->owner);
	for (int k = 0; k < HE_COUNT; k++) {
		int copies = 0;
		for (int holder = 0; holder < 2; holder++)
			if (charm_reaches(x, k, holder, u->owner)) copies += s->he[holder][k];
		if (copies > 0) lend_unit(x, u, k, -copies);
	}
	u->flags |= F_PLANE;
	u->flags &= ~(uint32_t)F_ATTACKING;
	u->blocks = -1;
	banners(s);
	return 1;
}

/* Whether a creature is kept from recovering as its hero's turn begins:
 * thick air holds the flyers, and without it a flood holds the rest. */
static int held_down(const State *s, const Unit *u) {
	if (u->flags & F_NO_AFFECT) return 0;
	if (s->he[0][HE_CNAR] + s->he[1][HE_CNAR] > 0) return (u->flags & F_FLY) != 0;
	if (s->he[0][HE_FLOD] + s->he[1][HE_FLOD] > 0) return !(u->flags & F_FLY);
	return 0;
}

/* Remembers what an enchantment has just changed in a creature, against how
 * it stood `before`, for the strike that may strip it. `fresh`: the
 * enchantment is a new one rather than one already on it at work. */
static void wears(Unit *t, const Unit *before, int fresh, uint32_t flags) {
	if (fresh) {
		if (!t->worn) {
			t->bare_regeneration = before->regeneration;
			t->bare_wake = before->wake;
			t->bare_shielded = before->shielded;
		}
		if (t->worn < 100) t->worn++;
	}
	t->worn_power = (int16_t)(t->worn_power + (t->power - t->under) - (before->power - before->under));
	t->worn_health = (int16_t)(t->worn_health + t->toughness - before->toughness);
	t->worn_lethal = (int16_t)(t->worn_lethal + t->lethal - before->lethal);
	t->worn_flags |= flags & ~before->flags;
	t->worn_ready += t->ready_worth - before->ready_worth;
	t->worn_resting += t->resting_worth - before->resting_worth;
}

/* An enchantment has just been laid on a creature: what it changed, against
 * how the creature stood before, is kept so that it may be taken off alone. */
static Ench *note_ench(State *s, int unit, const Unit *was, int caster, int kind, int code, int price, int brief, int comes_back, int robs) {
	if (s->enchs >= MAX_ENCH) return NULL;
	const Unit *t = &s->u[unit];
	Ench *e = &s->ench[s->enchs++];
	memset(e, 0, sizeof(*e));
	e->unit = (int8_t)unit;
	e->caster = (int8_t)caster;
	e->kind = (int8_t)kind;
	e->brief = (int8_t)brief;
	e->comes_back = (int8_t)comes_back;
	e->robs = (int8_t)robs;
	e->code = (int16_t)code;
	/* A price below nothing tells one that is there for good. */
	if (price < 0) {
		e->fixed = 1;
		price = -1 - price;
	}
	e->price = (int16_t)price;
	e->power = (int16_t)((t->power - t->under) - (was->power - was->under));
	e->health = (int16_t)(t->toughness - was->toughness);
	e->lethal = (int16_t)(t->lethal - was->lethal);
	e->flags = t->worn_flags & ~was->worn_flags;
	e->ready = t->ready_worth - was->ready_worth;
	e->resting = t->resting_worth - was->resting_worth;
	return e;
}

/* A record goes, and nothing else. */
static void forget_ench(State *s, int r) {
	memmove(&s->ench[r], &s->ench[r + 1], (size_t)(s->enchs - r - 1) * sizeof(Ench));
	s->enchs--;
}

/* A lifeguard on a creature has turned one hurt aside, and is gone. */
static void spend_guard(State *s, int unit) {
	Unit *u = &s->u[unit];
	u->guards--;
	for (int r = 0; r < s->enchs; r++)
		if (s->ench[r].unit == unit && s->ench[r].kind == EN_GUARD) {
			forget_ench(s, r);
			if (u->worn > 0) u->worn--;
			break;
		}
}

static void destroy_unit(State *s, int index, int no_regeneration);

/* One enchantment comes off a creature: what it gave goes and what it took
 * comes back. */
static void unwear(State *s, int r) {
	Ench e = s->ench[r];
	forget_ench(s, r);
	Unit *u = &s->u[e.unit];
	/* A water link is its caster's, and changes nothing in the creature. */
	if ((u->flags & F_DEAD) || e.kind == EN_WATER) return;
	uint32_t others = 0;
	int controls = 0, shields = 0, mutes = 0, holds = 0;
	for (int j = 0; j < s->enchs; j++)
		if (s->ench[j].unit == e.unit) {
			others |= s->ench[j].flags;
			controls += s->ench[j].kind == EN_CONTROL;
			holds += s->ench[j].kind == EN_HOLD;
			shields += s->ench[j].shields;
			mutes += s->ench[j].mutes;
		}
	if (e.regen) u->regeneration = (int8_t)(e.regen - 1);
	if (e.shields && !shields) u->shielded = 0;
	if (e.mutes && !mutes && u->bare_ability) {
		u->ability = u->bare_ability;
		u->bare_ability = 0;
	}
	if (e.kind == EN_DELUSION) {
		/* Power and health change places again. */
		int power = u->power, health = u->toughness;
		u->power = (int16_t)imax(0, health);
		u->under = 0;
		u->raw = (int16_t)imax(1, power);
		u->lethal = (int16_t)(u->raw - power);
		u->toughness = (int16_t)power;
	} else {
		int health = u->toughness - e.health;
		add_power(u, -e.power);
		if (worn_kind(s, e.unit, EN_DELUSION) & 1) {
			/* Health that was power a moment ago has no floor of one. */
			u->raw = (int16_t)imax(1, health);
			u->lethal = (int16_t)(u->raw - health);
			u->toughness = (int16_t)health;
		} else {
			u->lethal = (int16_t)(u->lethal - e.lethal);
			u->raw = (int16_t)(health + u->lethal);
			settle_health(u);
		}
	}
	uint32_t gone = e.flags & ~others;
	u->flags &= ~gone;
	u->worn_flags &= ~gone;
	u->ready_worth -= e.ready;
	u->resting_worth -= e.resting;
	if (u->worn > 0) u->worn--;
	u->worn_power = (int16_t)(u->worn_power - e.power);
	u->worn_health = (int16_t)(u->worn_health - e.health);
	u->worn_lethal = (int16_t)(u->worn_lethal - e.lethal);
	u->worn_ready -= e.ready;
	u->worn_resting -= e.resting;
	if (e.brief && u->brief > 0) {
		u->brief--;
		u->brief_power = (int16_t)(u->brief_power - e.power);
		u->brief_health = (int16_t)(u->brief_health - e.health);
		u->brief_flags &= ~gone;
		u->brief_ready -= e.ready;
		u->brief_resting -= e.resting;
	}
	if (e.robs) {
		u->discards = (int8_t)imax(0, u->discards - e.robs);
		u->worn_discards = (int8_t)imax(0, u->worn_discards - e.robs);
	}
	switch (e.kind) {
	case EN_HOLD:
		if (!holds) {
			u->wake = u->bare_wake;
			u->wake_hurts = 0;
		}
		break;
	case EN_TWIST:
		if (u->twisted > 0) u->twisted--;
		break;
	case EN_OVERLOAD:
		if (u->overload > 0) u->overload--;
		break;
	case EN_LINK:
		if (u->linked > 0) u->linked--;
		break;
	case EN_SKIN:
		if (u->skins > 0) u->skins--;
		break;
	case EN_GUARD:
		if (u->guards > 0) u->guards--;
		break;
	case EN_BARRIER:
		if (u->barriers > 0) u->barriers--;
		break;
	case EN_CONTROL:
		/* It goes home as it stands, out of the fight, to wait a turn. */
		if (!controls && u->home > 0) {
			int home = u->home - 1;
			u->home = 0;
			if (home != u->owner) {
				u->owner = (int8_t)home;
				if (u->fate & FATE_READY) u->flags &= ~(uint32_t)F_SICK;
				else u->flags |= F_SICK;
				u->flags &= ~(uint32_t)F_ATTACKING;
				u->blocks = -1;
			}
		}
		break;
	case EN_ALPHA:
		/* An alpha strike always costs the creature its life. */
		kill_unit(s, e.unit);
		return;
	case EN_QUICK:
		/* A quick fix undone destroys what it raised, past regenerating and
		 * past the plane. */
		u->flags &= ~(uint32_t)F_DISSIPATES;
		u->guards = 0;
		destroy_unit(s, e.unit, 1);
		return;
	default:
		break;
	}
	if (u->damage >= u->toughness) perish_unit(s, e.unit);
}

/* Every enchantment comes off a creature: what they gave goes and what they
 * took comes back, one brought over goes home, and one that lived by them
 * dies. */
static void strip_unit(State *s, int index) {
	Unit *u = &s->u[index];
	for (int r = s->enchs - 1; r >= 0; r--)
		if (s->ench[r].unit == index && s->ench[r].kind != EN_WATER) forget_ench(s, r);
	if (!u->worn || (u->flags & F_DEAD)) return;
	int health = u->toughness - u->worn_health, fate = u->fate, home = u->home;
	add_power(u, -u->worn_power);
	u->discards = (int8_t)imax(0, u->discards - u->worn_discards);
	u->worn_discards = 0;
	u->lethal = (int16_t)(u->lethal - u->worn_lethal);
	u->raw = (int16_t)(health + u->lethal);
	settle_health(u);
	u->flags &= ~u->worn_flags;
	u->ready_worth -= u->worn_ready;
	u->resting_worth -= u->worn_resting;
	u->regeneration = u->bare_regeneration;
	u->wake = u->bare_wake;
	u->shielded = u->bare_shielded;
	if (u->bare_ability) u->ability = u->bare_ability;
	u->skins = u->guards = u->barriers = u->wake_hurts = u->twisted = u->overload = u->linked = u->alpha = 0;
	u->worn = u->bare_ability = u->fate = u->brief = 0;
	u->brief_power = u->brief_health = 0;
	u->brief_flags = 0;
	u->brief_ready = u->brief_resting = 0;
	u->worn_power = u->worn_health = u->worn_lethal = 0;
	u->worn_flags = 0;
	u->worn_ready = u->worn_resting = 0;
	u->home = 0;
	if (home > 0 && home - 1 != u->owner) {
		/* It goes back as it stands, out of the fight, to wait a turn. */
		u->owner = (int8_t)(home - 1);
		if (fate & FATE_READY) u->flags &= ~(uint32_t)F_SICK;
		else u->flags |= F_SICK;
		u->flags &= ~(uint32_t)F_ATTACKING;
		u->blocks = -1;
	}
	if (fate & (FATE_DIES | FATE_DESTROYED)) kill_unit(s, index);
	else if (u->damage >= u->toughness) perish_unit(s, index);
}

/* The same for a hero: everything laid on it goes, and with that whatever it
 * lent the creatures. */
static void strip_hero(State *s, int side) {
	const Search *x = (const Search *)s->rules;
	for (int k = 0; k < HE_COUNT; k++) {
		int copies = s->he[side][k];
		if (copies <= 0) continue;
		s->he[side][k] = 0;
		if (x) lend_army(x, s, side, k, -copies);
	}
	for (int r = s->enchs - 1; r >= 0; r--)
		if (s->ench[r].kind == EN_WATER && s->ench[r].caster == side) forget_ench(s, r);
	memset(s->used[side], 0, sizeof(s->used[side]));
	s->tax -= s->taxes[side];
	s->taxes[side] = 0;
	s->forest[side] = -1;
	s->forest_worth[side] = 0;
	s->young[side] = s->stasis_age[side] = 0;
	s->aura_worth[side] = 0;
	if (s->banner[side]) {
		s->banner[side] = 0;
		banners(s);
	}
}

/* A hero draws: the cards it is known to draw next, and past those a card
 * the engine cannot name. */
static void draw_cards(State *s, int side, int count) {
	const Search *x = (const Search *)s->rules;
	for (int i = 0; i < count; i++) {
		if (!s->blind && s->drawn[side] < DRAWS) {
			/* A draw the engine was told will fail brings nothing: its place
			 * is taken up, and counts as a card already gone. */
			int none = x->hand[side][HAND + s->drawn[side]].none;
			if (none) s->played[side] |= 1u << (HAND + s->drawn[side]);
			s->drawn[side]++;
			/* The second game's book may by now have a card to give after
			 * all: one that was given up since. Which, nobody knows. */
			if (none && s->second && book_room(x, s, side) > 0) s->more[side]++;
		} else if (book_room(x, s, side) > 0) s->more[side]++;
	}
}

/* A hero loses cards it does not choose. Which of them go is a matter of
 * chance the engine cannot follow, so it takes them as they come; and the
 * same chance deals the cards, so no draw it was told of holds after. */
static void summon(const Search *x, State *s, int side, const Card *c);

/* What a card does as the other hero makes its holder give it up. */
static void discard_answer(const Search *x, State *s, int holder, const Card *c, int cause) {
	if (!x || !s->second || cause == holder || cause < 0 || !c->answers) return;
	if (c->answers == 1) summon(x, s, holder, c);
	else discard_cards(s, cause, 3, 0, holder);
}

/* A hero gives up every card it holds; how many that was. */
static int empty_hand(const Search *x, State *s, int hero, int cause) {
	int count = cards_held(s, hero);
	for (int i = 0; i < HAND + s->drawn[hero] && i < SLOTS; i++) {
		/* A place that holds no card is not one given up. */
		if ((s->played[hero] >> i & 1) || (i < HAND ? i >= s->held[hero] : x->hand[hero][i].none)) continue;
		s->played[hero] |= 1u << i;
		if (x->hand[hero][i].cost >= 0) discard_answer(x, s, hero, &x->hand[hero][i], cause);
	}
	for (int j = 0; j < BACK; j++) {
		int kind = s->back[hero][j];
		s->back[hero][j] = 0;
		if (kind > 0) discard_answer(x, s, hero, &x->pool[kind - 1], cause);
	}
	s->more[hero] -= cards_held(s, hero);
	return count;
}

static void discard_cards(State *s, int side, int count, int spells, int cause) {
	const Search *x = (const Search *)s->rules;
	if (spells) {
		/* Only cards that are no creatures go, as many as there are of them:
		 * a card the engine holds no rule for is never a creature. Where all
		 * of them go, it is certain which did. */
		int open = 0;
		for (int i = 0; x && i < imin(SLOTS, HAND + s->drawn[side]); i++) {
			const Card *c = &x->hand[side][i];
			if ((s->played[side] >> i & 1) || c->none) continue;
			if (c->cost < 0 ? i >= imin(s->held[side], HAND) : c->effect == EFF_SUMMON) continue;
			open++;
		}
		int every = open <= count, gone = 0;
		for (int i = 0; x && i < imin(SLOTS, HAND + s->drawn[side]) && count > 0; i++) {
			const Card *c = &x->hand[side][i];
			if ((s->played[side] >> i & 1) || c->none) continue;
			if (c->cost < 0 ? i >= imin(s->held[side], HAND) : c->effect == EFF_SUMMON) continue;
			s->played[side] |= 1u << i;
			count--;
			gone++;
			if (every && c->cost >= 0) discard_answer(x, s, side, c, cause);
		}
		/* Chance is asked only where there is a card to take. */
		if (x && x->blinds && gone > 0) s->blind = 1;
		return;
	}
	/* An empty hand gives nothing up, and chance is not asked. */
	if (count <= 0 || cards_held(s, side) <= 0) return;
	/* Every card it holds: no chance in that. */
	if (x && count > 0 && count >= cards_held(s, side)) {
		empty_hand(x, s, side, cause);
		if (x->blinds) s->blind = 1;
		return;
	}
	for (int k = 0; k < count; k++) {
		int held = cards_held(s, side);
		if (held <= 0) break;
		int pick = (int)((unsigned)(s->health[0] * 7 + s->health[1] * 13 + s->ether[side] * 3 + k) % (unsigned)held);
		int gone = -1;
		for (int i = 0; x && i < imin(SLOTS, HAND + s->drawn[side]) && gone < 0; i++) {
			if ((s->played[side] >> i & 1) || x->hand[side][i].cost < 0) continue;
			if (pick-- == 0) gone = i;
		}
		if (gone >= 0) s->played[side] |= 1u << gone;
		else {
			int back = -1;
			for (int j = 0; j < BACK; j++)
				if (s->back[side][j]) back = j;
			if (back >= 0) s->back[side][back] = 0;
			else s->more[side]--;
		}
	}
	if (x && x->blinds) s->blind = 1;
}

static void hurt_unit(State *s, int source, int target, int amount) {
	Unit *t = &s->u[target];
	if (t->flags & (F_DEAD | F_GONE)) return;
	amount -= 2 * t->skins;
	if (amount <= 0) return;
	const Unit *a = &s->u[source];
	/* A stripping strike takes every enchantment off what it hits: in the
	 * first game before the blow lands, in the second after it. */
	int strips = (a->flags & F_DISENCHANT) != 0;
	if (strips && !s->second) {
		strip_unit(s, target);
		if (t->flags & (F_DEAD | F_GONE)) return;
	}
	if (t->guards > 0) {
		spend_guard(s, (int)(t - s->u));
		if (strips) strip_unit(s, target);
		return;
	}
	/* A lake snake's bite takes 1 of power and 1 of health from whatever it
	 * hits: in the second game before the lethal check, in the first after it,
	 * and there it kills on its own when it leaves too little health. */
	int venom = (a->flags & F_VENOM) && !(t->flags & F_NO_AFFECT);
	if (venom && s->second) {
		Unit was = *t;
		add_power(t, -1);
		t->lethal++;
		settle_health(t);
		wears(t, &was, 1, 0);
	}
	{
		/* A pain link passes on no more than the creature had left to lose. */
		int pain = imin(amount, imax(0, t->toughness - t->damage));
		for (int k = 0; k < t->linked; k++) pain_hero(s, t->owner, pain);
	}
	t->damage = (int16_t)(t->damage + amount);
	t->flags |= F_HIT;
	if ((a->flags & F_DESTROY) || ((a->flags & F_DESTROY_UNWALLED) && !(t->flags & F_WALL))
		|| ((a->flags & F_DESTROY_FLYER) && (t->flags & F_FLY))) t->flags |= F_POISONED;
	/* A fire elemental's burn lands before the lethal check. */
	if ((a->flags & F_BURN) && !(t->flags & F_NO_REGEN)) {
		Unit was = *t;
		t->flags |= F_NO_REGEN;
		wears(t, &was, 1, F_NO_REGEN);
	}
	if (t->damage >= t->toughness) finish_unit(s, target);
	if (venom && !s->second && !(t->flags & (F_DEAD | F_GONE))) {
		Unit was = *t;
		add_power(t, -1);
		t->lethal++;
		settle_health(t);
		wears(t, &was, 1, 0);
		if (t->damage >= t->toughness) finish_unit(s, target);
	}
	if (strips && !(t->flags & F_DEAD)) strip_unit(s, target);
}

/* Plays the declared attack against the blocks in `target` (the index of the
 * attacker each creature blocks, or -1). */
static void resolve(State *s, const int8_t *target) {
	int defender = 1 - s->attacker;
	uint32_t before = 0;
	for (int i = 0; i < s->n; i++)
		if (s->u[i].flags & F_REGENERATED) before |= 1u << i;
	s->in_fight = 1;
	/* The attackers fight in the order they were sent, and each meets its
	 * blockers in the order they were set against it; what the search only
	 * supposes comes after what has been said, as it stands on the board. */
	int8_t order[MAX_UNITS], met[MAX_UNITS];
	int sent = 0;
	for (int i = 0; i < s->n; i++) {
		if ((s->u[i].flags & (F_DEAD | F_GONE)) || !(s->u[i].flags & F_ATTACKING)) continue;
		int key = s->u[i].rank ? s->u[i].rank : 256 + i, at = sent++;
		while (at > 0 && (s->u[order[at - 1]].rank ? s->u[order[at - 1]].rank : 256 + order[at - 1]) > key) {
			order[at] = order[at - 1];
			at--;
		}
		order[at] = (int8_t)i;
	}
	for (int turn = 0; turn < sent; turn++) {
		int i = order[turn];
		Unit *a = &s->u[i];
		if ((a->flags & (F_DEAD | F_GONE)) || !(a->flags & F_ATTACKING)) continue;
		/* The first game: an attacker that regenerated while the defender
		 * moved stays sent, but neither fights nor rests. */
		if (!s->second && (before >> i & 1)) continue;
		if (!(a->flags & F_RESTLESS)) a->flags |= F_RESTING;
		int remaining = imax(0, a->power);
		int blocked = 0, meets = 0;
		for (int j = 0; j < s->n; j++) {
			if (target[j] != i) continue;
			int key = s->u[j].rank && s->u[j].blocks == i ? s->u[j].rank : 256 + j, at = meets++;
			while (at > 0 && (s->u[met[at - 1]].rank && s->u[met[at - 1]].blocks == i ? s->u[met[at - 1]].rank : 256 + met[at - 1]) > key) {
				met[at] = met[at - 1];
				at--;
			}
			met[at] = (int8_t)j;
		}
		for (int m = 0; m < meets; m++) {
			int j = met[m];
			Unit *b = &s->u[j];
			if (b->flags & (F_DEAD | F_GONE)) continue;
			blocked = 1;
			if (a->flags & (F_DEAD | F_REGENERATED | F_GONE)) break;
			int first = (b->flags & F_FIRST) && !(a->flags & F_FIRST);
			if (first) {
				hurt_unit(s, j, i, imax(0, b->power));
				if (a->flags & (F_DEAD | F_REGENERATED | F_GONE)) break;
			}
			int dealt = imin(remaining, imax(0, b->toughness - b->damage) + 2 * b->skins);
			remaining -= dealt;
			hurt_unit(s, i, j, dealt);
			if (!first && !(b->flags & (F_DEAD | F_REGENERATED | F_GONE))) hurt_unit(s, j, i, imax(0, b->power));
		}
		if (!blocked) hurt_hero(s, defender, remaining, i);
		else if (!(a->flags & (F_DEAD | F_REGENERATED | F_GONE)) && (a->flags & F_TRAMPLE) && remaining > 0) hurt_hero(s, defender, remaining, i);
		/* What kept it from resting may have died in this very fight. */
		if (!(a->flags & (F_DEAD | F_GONE | F_RESTLESS))) a->flags |= F_RESTING;
		if (s->health[0] <= 0 || s->health[1] <= 0) break;
	}
	/* A destroying strike kills what it marked, unless that creature already
	 * regenerated in this fight; regeneration and dissipation still answer. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (!(u->flags & F_POISONED) || (u->flags & (F_DEAD | F_GONE))) continue;
		if ((u->flags & F_REGENERATED) && !(before >> i & 1)) continue;
		u->damage = (int16_t)imax(u->damage, u->toughness);
		finish_unit(s, i);
	}
	s->in_fight = 0;
}

/* Whether a leader's aura reaches a creature: one of the race it names, or
 * the one card, and in its own army where it says so. */
static int covers(const Unit *l, const Unit *u) {
	if (!l->gives_to) return 0;
	if (l->gives_to == 200 ? u->tribe != 1 : u->race + 1 != l->gives_to) return 0;
	return !l->gives_own || l->owner == u->owner;
}

/* A leader's aura comes over a creature. */
static void led(const Search *x, Unit *u, const Unit *l) {
	int before = u->toughness;
	uint32_t added = l->gives_flags & ~u->flags;
	add_power(u, l->gives_power);
	u->raw = (int16_t)(u->raw + l->gives_toughness);
	settle_health(u);
	u->flags |= added;
	u->aura_flags |= added;
	int gain = l->gives_power * ((u->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth) + (u->toughness - before) * x->tough_worth;
	u->ready_worth += gain;
	u->resting_worth += gain;
}

static void summon(const Search *x, State *s, int side, const Card *c) {
	if (s->n >= MAX_UNITS) return;
	int army = 0;
	for (int i = 0; i < s->n; i++) army += s->u[i].owner == side && !(s->u[i].flags & F_DEAD);
	if (army >= ARMY) return;
	Unit *u = &s->u[s->n];
	memset(u, 0, sizeof(*u));
	/* Not a creature of the duel: its id is never a choice the caller can use. */
	u->id = -1 - s->n;
	u->owner = (int8_t)side;
	u->power = c->power;
	u->toughness = c->toughness;
	u->raw = c->toughness;
	u->flags = c->flags;
	/* A prime watch in play sends whatever arrives into the Colourless Plane. */
	if (s->second && s->he[0][HE_PRWT] + s->he[1][HE_PRWT] > 0 && !(u->flags & F_NO_AFFECT)) u->flags |= F_PLANE;
	u->regeneration = c->regeneration;
	u->race = c->race;
	u->ready_worth = c->ready_worth;
	u->resting_worth = c->resting_worth;
	u->cost = c->cost;
	u->blocks = -1;
	/* A creature card says in `amount` what health it costs its hero each
	 * turn, and in `lends` what else it is: bit 0, nothing may be aimed at
	 * it; bit 1, a walking horror; and above those its ability, that
	 * ability's cost, its amount and how it is used. */
	u->upkeep = c->amount;
	u->shielded = (int8_t)(c->lends & 1);
	u->horror = (int8_t)((c->lends & 2) != 0);
	u->mourned = (int8_t)((c->lends >> 23) & 1);
	u->feeds = (int8_t)((c->lends >> 24) & 1);
	u->envenoms = (int8_t)((c->lends >> 25) & 1);
	u->ability = (int8_t)((c->lends >> 2) & 63);
	u->ability_cost = (int8_t)((c->lends >> 8) & 15);
	u->ability_amount = (int8_t)((c->lends >> 12) & 127);
	u->ability_traits = (int8_t)((c->lends >> 19) & 15);
	/* It comes under the auras of the creatures in play, and brings its own
	 * to them and to itself. */
	u->gives_power = c->gives_power;
	u->gives_toughness = c->gives_toughness;
	u->gives_flags = c->aura_flags;
	u->gives_to = c->aura_to;
	u->gives_own = c->aura_own;
	u->tribe = c->tribe;
	u->pale = c->pale;
	u->pale_bits = c->pale_bits;
	if (s->second && u->pale && !(u->flags & F_PLANE)) u->flags |= F_DISSIPATES;
	u->discards = c->discards;
	u->kind = c->kind;
	/* Health shows no less than one, whatever the card says. */
	settle_health(u);
	if (c->tribe == 1 && (s->flight[0] || s->flight[1])) u->flags |= F_FLY;
	for (int i = 0; i < s->n; i++) {
		if ((s->u[i].flags & F_DEAD) || !covers(&s->u[i], u)) continue;
		u->leaders |= 1u << i;
		led(x, u, &s->u[i]);
	}
	if (u->gives_to)
		for (int i = 0; i <= s->n; i++) {
			Unit *v = &s->u[i];
			if ((i < s->n && (v->flags & F_DEAD)) || !covers(u, v)) continue;
			v->leaders |= 1u << s->n;
			led(x, v, u);
		}
	/* It comes under what stands on its hero and under the gases, and
	 * arrives resting where the other hero keeps newcomers down. */
	for (int k = 0; k < HE_COUNT; k++) {
		int copies = 0;
		for (int holder = 0; holder < 2; holder++)
			if (charm_reaches(x, k, holder, side)) copies += s->he[holder][k];
		if (copies > 0) lend_unit(x, u, k, copies);
	}
	if (s->he[1 - side][HE_HOAM] > 0 && !(s->second && (u->flags & (F_NO_AFFECT | F_PLANE)))) u->flags |= F_RESTING;
	s->n++;
	banners(s);
	if (!(u->flags & F_DEAD) && u->toughness <= 0) perish_unit(s, s->n - 1);
	if (u->horror) {
		int me = s->n - 1;
		for (int i = 0; i < me; i++) spell_damage(s, i, 3);
	}
}

/* The side to move plays its cards: wakes enfeebled creatures worth the ether,
 * summons the known creatures it can pay for, dearest first, and a typical
 * creature when its unknown cards are likely to hold one. */
static void develop(const Search *x, State *s, int side) {
	if (!x->cards) return;
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->owner != side || (u->flags & F_DEAD) || u->wake <= 0 || !(u->flags & F_RESTING)) continue;
		if (u->power < 2 || s->ether[side] < u->wake) continue;
		s->ether[side] -= u->wake;
		u->wake = 0;
		u->flags &= ~(uint32_t)(F_RESTING | F_NO_UNTAP);
	}
	for (;;) {
		int best = -1;
		for (int c = 0; c < SLOTS; c++) {
			const Card *card = &x->hand[side][c];
			if (card->cost < 0 || card->effect != EFF_SUMMON) continue;
			if ((s->played[side] >> c & 1) || card_cost(x, s, card) > s->ether[side]) continue;
			if (best < 0 || card->cost > x->hand[side][best].cost) best = c;
		}
		if (best < 0) break;
		s->played[side] |= 1 << best;
		s->ether[side] -= card_cost(x, s, &x->hand[side][best]);
		summon(x, s, side, &x->hand[side][best]);
	}
	s->chance[side] += x->chance_step[side];
	if (s->chance[side] >= 1000 && s->unknown[side] > 0) {
		int cost = imin(s->ether[side], COSTS);
		while (cost >= 1 && x->typical[side][cost - 1].cost < 0) cost--;
		if (cost >= 1) {
			s->ether[side] -= cost;
			s->unknown[side]--;
			s->chance[side] -= 1000;
			summon(x, s, side, &x->typical[side][cost - 1]);
		}
	}
}

/* The turn passes: wounds heal, the side that attacked loses its summoning
 * sickness, the other side rises, gains its channels, refills its ether, draws
 * and plays its cards. */
static void settle_illusions(State *s);

static void end_turn(const Search *x, State *s) {
	int next = 1 - s->attacker;
	s->ranks = 0;
	settle_illusions(s);
	/* A hand of more than five loses cards as the turn ends, from the far
	 * end of the row: the cards it held to begin with in their order, then
	 * the ones drawn since, the earliest first. */
	while (cards_held(s, s->attacker) > 5) {
		int a = s->attacker, gone = -1, returned = -1;
		/* A card that came back stands at the far end, and goes first. */
		for (int j = 0; j < BACK; j++)
			if (s->back[a][j]) returned = j;
		if (returned >= 0) {
			s->back[a][returned] = 0;
			continue;
		}
		for (int k = 0; k < 8 && gone < 0; k++) {
			int place = (int)(x->trim[a] >> (4 * k)) & 15;
			if (place < HAND && !(s->played[a] >> place & 1)) gone = place;
		}
		for (int i = HAND; gone < 0 && i < imin(SLOTS, HAND + s->drawn[a]); i++)
			if (!(s->played[a] >> i & 1)) gone = i;
		if (gone >= 0) s->played[a] |= 1u << gone;
		else s->more[a]--;
	}
	/* The turn ends, and wounds close: a fatal disease keeps them open, and
	 * so does the second game's bloodlessness. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->flags & F_DEAD) continue;
		if (!diseased(s, u->owner) && !(s->second && s->enchs > 0 && worn_kind(s, i, EN_RIOT))) u->damage = 0;
	}
	/* A creature that fatally waits destroys itself unless something hit
	 * it, and a parasite drains the hero holding it. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->owner != s->attacker || (u->flags & (F_DEAD | F_GONE))) continue;
		if (!(u->flags & F_FATALIST) || (u->flags & F_SICK)) continue;
		if (u->flags & (F_HIT | F_REGENERATED)) continue;
		/* It hurts itself by all its health, as any other harm would. */
		spell_damage(s, i, u->toughness);
	}
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->owner == s->attacker && !(u->flags & F_DEAD) && u->upkeep > 0) hurt_hero(s, u->owner, u->upkeep, -1);
	}
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		/* The fight is over, and no block of it stands into the next: a
		 * creature that blocked is free to be set against another. */
		u->blocks = -1;
		if (u->flags & F_DEAD) continue;
		u->flags &= ~(uint32_t)(F_ATTACKING | F_REGENERATED | F_POISONED);
		/* The mark of a blow lasts until its own hero's turn has ended. */
		if (u->owner == s->attacker) u->flags &= ~(uint32_t)F_HIT;
		u->rank = 0;
		/* Thick air and a flood keep what they hold as it is, and smoke keeps
		 * the resting at rest; none of them reaches into the plane. */
		int apart = (u->flags & (F_PLANE | F_GONE | F_NO_AFFECT)) != 0;
		if (!(u->flags & (F_PLANE | F_GONE)) && held_down(s, u)) continue;
		if (u->owner == s->attacker) u->flags &= ~(uint32_t)F_SICK;
		else {
			/* What it may do once a round, it may do again. */
			u->spent = 0;
			u->pale_used &= 4;
			if (!(u->flags & F_NO_UNTAP) && !(s->enchs > 0 && bound(s, u)) && (apart || s->he[0][HE_SMOK] + s->he[1][HE_SMOK] == 0))
				u->flags &= ~(uint32_t)F_RESTING;
		}
	}
	/* A hopper lying under three cards or more climbs back out of the grave
	 * of the hero whose turn ends, the oldest first. The first game takes the
	 * card out even when a full army leaves it nowhere to go. */
	for (int i = 0, a = s->attacker; i < s->known[a]; ) {
		int kind = s->graves[a][i], army = 0;
		for (int j = 0; j < s->n; j++) army += s->u[j].owner == a && !(s->u[j].flags & F_DEAD);
		if (s->second && army >= ARMY) break;
		if (kind <= 0 || !x->pool[kind - 1].rises || s->known[a] - 1 - i < 3) {
			i++;
			continue;
		}
		unbury(s, a, i);
		int before = s->n;
		summon(x, s, a, &x->pool[kind - 1]);
		if (s->n > before) s->u[before].flags &= ~(uint32_t)F_SICK;
		i = 0;
	}
	/* A twisted enhancement wears off a point at a time and then goes on
	 * taking: the creature dies once only the floor of one keeps it alive. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->owner != s->attacker || (u->flags & (F_DEAD | F_GONE))) continue;
		for (int k = 0; k < u->twisted && !(u->flags & F_DEAD); k++) {
			int under = u->toughness - 1;
			Unit was = *u;
			add_power(u, -1);
			u->raw--;
			settle_health(u);
			u->ready_worth -= x->power_worth + x->tough_worth;
			u->resting_worth -= x->power_worth + x->tough_worth;
			wears(u, &was, 0, 0);
			for (int r = 0, left = k; r < s->enchs; r++)
				if (s->ench[r].unit == i && s->ench[r].kind == EN_TWIST && left-- == 0) {
					s->ench[r].power--;
					s->ench[r].health--;
					s->ench[r].ready -= x->power_worth + x->tough_worth;
					s->ench[r].resting -= x->power_worth + x->tough_worth;
					break;
				}
			if (u->damage >= imin(u->toughness, under)) kill_unit(s, i);
		}
	}
	/* An overload burns its creature out. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->owner != s->attacker || (u->flags & (F_DEAD | F_GONE))) continue;
		for (int k = 0; k < u->overload && !(u->flags & F_DEAD); k++) {
			int had = u->power, before = u->toughness;
			add_power(u, -2);
			u->lethal = (int16_t)(u->lethal + 2);
			settle_health(u);
			int loss = (had - u->power) * x->power_worth + (before - u->toughness) * x->tough_worth;
			u->ready_worth -= loss;
			u->resting_worth -= loss;
			if (u->damage >= u->toughness) kill_unit(s, i);
		}
	}
	/* Suffocating gas on the hero whose turn ends hurts everything by two. */
	for (int copy = 0; copy < s->he[s->attacker][HE_SFGS]; copy++)
		for (int side = 0; side < 2; side++) {
			int n = s->n;
			for (int i = 0; i < n; i++)
				if (s->u[i].owner == side) spell_damage(s, i, 2);
			hurt_hero(s, side, 2, -1);
		}
	/* What stands on the heroes and bites as a turn ends: an ether burn
	 * gives the hero whose turn it was the ether it has left as damage; the
	 * taxes hurt their hero after every turn that was not its own; venom
	 * hurts its hero after its own. */
	{
		int a = s->attacker;
		for (int copy = s->he[0][HE_MNBN] + s->he[1][HE_MNBN]; copy > 0 && s->ether[a] > 0; copy--) hurt_hero(s, a, s->ether[a], -1);
		for (int copy = s->he[next][HE_WETX] + s->he[next][HE_WTX2]; copy > 0; copy--) hurt_hero(s, next, 1, -1);
		for (int copy = s->he[next][HE_STTX]; copy > 0; copy--) hurt_hero(s, next, 3, -1);
		for (int copy = s->he[a][HE_ENVM]; copy > 0; copy--) hurt_hero(s, a, 2, -1);
		for (int copy = s->he[a][HE_ESWS]; copy > 0; copy--) hurt_hero(s, a, 1, -1);
		/* An irritation or a madness on a creature of the hero whose turn
		 * ends hurts that hero (not from the plane, in the second game); and
		 * a cripple deals the hero facing its creature a card after every
		 * turn that was not its caster's. */
		int8_t ticks[MAX_ENCH];
		int hurts = 0, dealt[2] = {0, 0};
		for (int r = 0; r < s->enchs; r++) {
			const Ench *e = &s->ench[r];
			const Unit *u = &s->u[e->unit];
			if (u->flags & F_DEAD) continue;
			if (e->tick > 0 && u->owner == a && !(s->second && (u->flags & (F_PLANE | F_GONE)))) ticks[hurts++] = e->tick;
			if (e->kind == EN_CRIPPLE && e->caster != a) dealt[1 - u->owner]++;
		}
		for (int i = 0; i < hurts; i++) hurt_hero(s, a, ticks[i], -1);
		for (int side = 0; side < 2; side++) deal(x, s, side, dealt[side]);
		/* The second game's vortex ends with the next turn of its hero's. */
		if (s->second) drop_charm(x, s, a, HE_MNVR, s->he[a][HE_MNVR] - s->young[a]);
		s->young[a] = 0;
	}
	/* A blessing ends with a turn that is not its creature's own hero's. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (!u->brief || (u->flags & F_DEAD) || (u->home ? u->home - 1 : u->owner) == s->attacker) continue;
		int health = u->toughness - u->brief_health;
		add_power(u, -u->brief_power);
		if (s->enchs > 0 && (worn_kind(s, i, EN_DELUSION) & 1)) {
			/* Health that was power a moment ago has no floor of one. */
			u->raw = (int16_t)imax(1, health);
			u->lethal = (int16_t)(u->raw - health);
			u->toughness = (int16_t)health;
		} else {
			u->raw = (int16_t)(health + u->lethal);
			settle_health(u);
		}
		u->flags &= ~u->brief_flags;
		u->ready_worth -= u->brief_ready;
		u->resting_worth -= u->brief_resting;
		u->worn = (int8_t)imax(0, u->worn - u->brief);
		u->worn_power = (int16_t)(u->worn_power - u->brief_power);
		u->worn_health = (int16_t)(u->worn_health - u->brief_health);
		u->worn_flags &= ~u->brief_flags;
		u->worn_ready -= u->brief_ready;
		u->worn_resting -= u->brief_resting;
		u->brief = 0;
		u->brief_power = u->brief_health = 0;
		u->brief_flags = 0;
		u->brief_ready = u->brief_resting = 0;
		int dies = 0;
		for (int r = s->enchs - 1; r >= 0; r--)
			if (s->ench[r].unit == i && s->ench[r].brief) {
				/* An alpha strike always costs the creature its life. */
				dies |= s->ench[r].kind == EN_ALPHA;
				forget_ench(s, r);
			}
		if (dies) kill_unit(s, i);
		else if (!(u->flags & F_GONE) && u->damage >= u->toughness) perish_unit(s, i);
	}
	/* What a creature gave itself for the turn goes the same way. */
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (!u->passing || (u->flags & F_DEAD) || u->owner == s->attacker) continue;
		add_power(u, -u->passing_power);
		u->raw = (int16_t)(u->raw - u->passing_health);
		settle_health(u);
		u->flags &= ~u->passing_flags;
		u->ready_worth -= u->passing_ready;
		u->resting_worth -= u->passing_resting;
		u->passing = 0;
		u->passing_power = u->passing_health = 0;
		u->passing_flags = 0;
		u->passing_ready = u->passing_resting = 0;
		if (!(u->flags & F_GONE) && u->damage >= u->toughness) perish_unit(s, i);
	}
	/* The wings a spirit wizard gave end with a turn that is not its hero's. */
	if (s->flight[next]) {
		s->flight[next] = 0;
		if (!s->flight[s->attacker])
			for (int i = 0; i < s->n; i++) {
				Unit *u = &s->u[i];
				if (u->tribe != 1 || (u->flags & F_DEAD)) continue;
				if (u->kind > 0 && (x->pool[u->kind - 1].flags & F_FLY)) continue;
				u->flags &= ~(uint32_t)F_FLY;
			}
	}
	/* What lasts only until the other hero's turn is over ends here. */
	for (int k = 0; k < HE_COUNT; k++) {
		if (x->charm[k].expires) drop_charm(x, s, next, k, s->he[next][k]);
	}
	/* A hero that fell to any of that never hands the turn on. */
	if (s->health[0] <= 0 || s->health[1] <= 0) return;
	s->attacker = next;
	/* A long duel wears on the hero whose turn begins, and that can end it. */
	{
		int wear = x->disturbance[next][imin(s->turns[next] + 2 * s->gifted[next], MAX_TURNS - 1)];
		if (wear > 0) s->health[next] = imax(0, s->health[next] - wear);
		/* Its turn never begins if that was the end of it. */
		if (s->health[next] <= 0) return;
	}
	/* What its enchantments let it do once a turn, it may do again. */
	memset(s->used[next], 0, sizeof(s->used[next]));
	/* The first game's dragons do not stay dead: each comes back out of its
	 * hero's graveyard into the hand as that hero's turn begins. */
	for (int i = 0; i < s->known[next]; ) {
		int kind = s->graves[next][i];
		if (kind > 0 && x->pool[kind - 1].returns) take_back(s, next, unbury(s, next, i));
		else i++;
	}
	/* What was sent into the Colourless Plane and is no pale creature comes
	 * back as its own hero's turn begins. */
	if (s->second)
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if ((u->flags & F_DEAD) || !(u->flags & F_PLANE) || u->pale || (u->home ? u->home - 1 : u->owner) != next) continue;
			manifest(x, s, i);
		}
	/* The hero to move opens its channels, which grow by its own table. A
	 * stasis leaves its ether as it was, and in the second game its channels. */
	int still = stasis(s);
	/* The second game: an ether storm the hero laid on a creature still in
	 * play is one more channel each turn, and an ether breeze three ether. */
	if (!still || !s->second) s->channels[next] += x->income[next][imin(s->turns[next], MAX_TURNS - 1)] + (s->second ? cast_kind(s, next, EN_STORM) : 0);
	s->turns[next]++;
	if (!still) {
		s->ether[next] = s->channels[next] * (1 + vortices(s, next)) + s->extra[next];
		/* The second game gives the hero that moves second one more on its first turn. */
		if (s->turns[next] == 1) s->ether[next] += x->opening[next];
		if (s->second) s->ether[next] += 3 * cast_kind(s, next, EN_BREEZE);
		for (int i = 0; i < s->n; i++)
			if (s->u[i].owner == next && !(s->u[i].flags & (F_DEAD | F_GONE)) && (s->u[i].ability_traits & AT_INCOME)) s->ether[next]++;
	}
	/* A pale warp on the hero whose turn begins takes, for each copy, the
	 * pale creature with the least health left, whoever's it is; with none
	 * to take, that copy ends. */
	for (int copy = s->he[next][HE_PLWP]; copy > 0; copy--) {
		int chosen = -1, least = 0;
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if ((u->flags & F_DEAD) || !u->pale) continue;
			if (chosen < 0 || u->toughness - u->damage < least) {
				chosen = i;
				least = u->toughness - u->damage;
			}
		}
		if (chosen < 0) {
			s->he[next][HE_PLWP]--;
			s->aura_worth[next] -= x->charm[HE_PLWP].each + (s->he[next][HE_PLWP] == 0 ? x->charm[HE_PLWP].kind : 0);
			continue;
		}
		Unit *t = &s->u[chosen];
		int blow = imax(1, t->toughness - t->damage);
		t->damage = (int16_t)(t->damage + blow);
		t->flags |= F_HIT;
		for (int k = 0; k < t->linked; k++) pain_hero(s, t->owner, blow);
		/* One already in the plane has nowhere left to go. */
		if (t->flags & (F_GONE | F_PLANE)) kill_unit(s, chosen);
		else finish_unit(s, chosen);
	}
	/* The hero to move draws, and the engine knows what; every enlightenment
	 * in play is one card more. */
	draw_cards(s, next, 1 + s->he[0][HE_ENLH] + s->he[1][HE_ENLH]);
	if (x->cards) s->unknown[next]++;
	s->calm = 0;
	/* A stasis is paid for by the hero that laid it as each of its turns
	 * begins, or goes: two ether in the first game, two more with every turn
	 * in the second. */
	if (s->he[next][HE_STSI] > 0) {
		if (s->stasis_age[next] < 100) s->stasis_age[next]++;
		int price = s->second ? 2 * s->stasis_age[next] : 2;
		for (int copy = s->he[next][HE_STSI]; copy > 0; copy--) {
			if (s->ether[next] < price) drop_charm(x, s, next, HE_STSI, 1);
			else pay(s, next, price);
		}
	}
	/* A spirit trap in play costs the hero to move an ether for every
	 * creature it has, as far as its ether goes. */
	for (int copy = s->he[0][HE_SPTR] + s->he[1][HE_SPTR]; copy > 0; copy--) pay(s, next, imin(army_size(s, next), s->ether[next]));
	if (s->health[0] <= 0 || s->health[1] <= 0) return;
	develop(x, s, next);
}

static void declare(const Search *x, State *s, uint32_t mask) {
	/* The guards last: each needs one of its race sent before it. */
	for (int pass = 0; pass < 2; pass++)
		for (int i = 0; i < s->n; i++) {
			if (!(mask >> i & 1) || (s->u[i].flags & F_ATTACKING) || ((s->u[i].flags & F_TEAM) != 0) != pass) continue;
			s->u[i].flags |= F_ATTACKING;
			ranked(s, &s->u[i]);
			pay(s, s->attacker, s->tax);
		}
}

/* ------------------------------------------------------------ block choices */

static int add_plan(Plan *plans, int count, int limit, const int8_t *target, int n) {
	if (count >= limit) return count;
	for (int i = 0; i < count; i++)
		if (memcmp(plans[i].target, target, (size_t)n) == 0) return count;
	memcpy(plans[count].target, target, (size_t)n);
	return count + 1;
}

static int score_plan(Search *x, const State *declared, const int8_t *target, int turns) {
	State t = *declared;
	resolve(&t, target);
	end_turn(x, &t);
	x->nodes++;
	return evaluate_leaf(x, &t, turns);
}

typedef struct {
	const State *s;
	int blockers[MAX_UNITS], count;
	int8_t options[MAX_UNITS][MAX_UNITS + 1];
	int option_count[MAX_UNITS];
	int choice[MAX_UNITS];
	int8_t target[MAX_UNITS];
	Plan *plans;
	int plan_count, limit;
} Blocks;

static void every_plan(Blocks *b, int at) {
	if (b->plan_count >= b->limit) return;
	if (at == b->count) {
		memcpy(b->plans[b->plan_count++].target, b->target, (size_t)b->s->n);
		return;
	}
	int unit = b->blockers[at];
	/* Creatures alike in every way are interchangeable: the later one never
	 * takes an earlier option than the one before it. */
	int from = 0;
	if (at > 0 && same_kind(&b->s->u[unit], &b->s->u[b->blockers[at - 1]])) from = b->choice[at - 1];
	for (int c = from; c < b->option_count[at]; c++) {
		b->choice[at] = c;
		b->target[unit] = b->options[at][c];
		every_plan(b, at + 1);
	}
	b->target[unit] = -1;
}

/* The defender's block plans for the declared attack, best for the defender
 * first. `base` holds the blocks already made. */
static int block_plans(Search *x, const State *s, const int8_t *base, Plan *plans, int limit, int turns) {
	Blocks b;
	b.s = s;
	b.count = 0;
	b.plans = plans;
	b.plan_count = 0;
	b.limit = MAX_PLANS;
	memcpy(b.target, base, (size_t)s->n);
	int defender = 1 - s->attacker;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->owner != defender || !ready(u) || base[i] >= 0) continue;
		int able = 0;
		for (int j = 0; j < s->n && !able; j++) {
			const Unit *a = &s->u[j];
			able = (a->flags & F_ATTACKING) && !(a->flags & F_DEAD) && can_block(a, u);
		}
		if (able) b.blockers[b.count++] = i;
	}
	if (b.count == 0) {
		memcpy(plans[0].target, base, (size_t)s->n);
		plans[0].score = score_plan(x, s, base, turns);
		return 1;
	}
	group_alike(s, b.blockers, b.count);
	double total = 1.0;
	for (int i = 0; i < b.count; i++) {
		const Unit *u = &s->u[b.blockers[i]];
		int k = 0;
		b.options[i][k++] = -1;
		for (int j = 0; j < s->n; j++) {
			const Unit *a = &s->u[j];
			if ((a->flags & F_ATTACKING) && !(a->flags & F_DEAD) && can_block(a, u)) b.options[i][k++] = (int8_t)j;
		}
		b.option_count[i] = k;
		total *= k;
	}
	int count = 0;
	/* Every way to block while they are few enough to play through; the best
	 * `limit` of them are kept. With one blocker more a good block must not
	 * drop out of sight: a creature would look better dead than at home. */
	if (total <= (double)(x->wide ? MAX_PLANS : imax(limit, 64))) {
		every_plan(&b, 0);
		count = b.plan_count;
		for (int i = 0; i < count; i++) plans[i].score = score_plan(x, s, plans[i].target, turns);
	} else {
		int8_t t[MAX_UNITS];
		/* No block, and every single block. */
		memcpy(t, base, (size_t)s->n);
		count = add_plan(plans, count, MAX_PLANS, t, s->n);
		for (int i = 0; i < b.count; i++)
			for (int c = 1; c < b.option_count[i]; c++) {
				memcpy(t, base, (size_t)s->n);
				t[b.blockers[i]] = b.options[i][c];
				count = add_plan(plans, count, MAX_PLANS, t, s->n);
			}
		/* Attackers nothing blocks yet come first, the strongest of them
		 * first: the cheapest blocker for each; then the blocker that kills it
		 * and lives, kills it, or lives. */
		uint32_t met = 0;
		for (int i = 0; i < s->n; i++)
			if (base[i] >= 0) met |= 1u << base[i];
		for (int style = 0; style < 2; style++) {
			memcpy(t, base, (size_t)s->n);
			uint32_t done = 0;
			for (;;) {
				int best = -1;
				for (int j = 0; j < s->n; j++) {
					const Unit *a = &s->u[j];
					if (!(a->flags & F_ATTACKING) || (a->flags & F_DEAD) || (done >> j & 1)) continue;
					if (best < 0) { best = j; continue; }
					int open = !(met >> j & 1), best_open = !(met >> best & 1);
					if (open != best_open ? open : a->power > s->u[best].power) best = j;
				}
				if (best < 0) break;
				done |= 1u << best;
				const Unit *a = &s->u[best];
				int pick = -1, pick_score = -1000000;
				for (int i = 0; i < b.count; i++) {
					int unit = b.blockers[i];
					const Unit *u = &s->u[unit];
					if (t[unit] >= 0 || !can_block(a, u)) continue;
					int score;
					if (style == 0) score = -u->ready_worth;
					else {
						int kills = u->power >= a->toughness, lives = u->toughness > a->power;
						if (!kills && !lives) continue;
						score = (kills ? 2000000 : 0) + (lives ? 1000000 : 0) - u->ready_worth;
					}
					if (score > pick_score) { pick_score = score; pick = unit; }
				}
				if (pick >= 0) t[pick] = (int8_t)best;
			}
			count = add_plan(plans, count, MAX_PLANS, t, s->n);
		}
		/* Gangs: for each attacker, the strongest first, the fewest free
		 * blockers whose blows together kill it. */
		memcpy(t, base, (size_t)s->n);
		for (uint32_t done = 0;;) {
			int best = -1;
			for (int j = 0; j < s->n; j++) {
				const Unit *a = &s->u[j];
				if (!(a->flags & F_ATTACKING) || (a->flags & F_DEAD) || (done >> j & 1)) continue;
				if (best < 0 || a->power > s->u[best].power) best = j;
			}
			if (best < 0) break;
			done |= 1u << best;
			const Unit *a = &s->u[best];
			int need = a->toughness - a->damage, sum = 0, gang[MAX_UNITS], size = 0;
			while (sum < need) {
				int pick = -1;
				for (int i = 0; i < b.count; i++) {
					int unit = b.blockers[i];
					const Unit *u = &s->u[unit];
					if (t[unit] >= 0 || u->power <= 0 || !can_block(a, u)) continue;
					if (pick < 0 || u->power > s->u[pick].power) pick = unit;
				}
				if (pick < 0) break;
				t[pick] = (int8_t)best;
				gang[size++] = pick;
				sum += s->u[pick].power;
			}
			if (sum < need)
				for (int i = 0; i < size; i++) t[gang[i]] = -1;
		}
		count = add_plan(plans, count, MAX_PLANS, t, s->n);
		for (int i = 0; i < count; i++) plans[i].score = score_plan(x, s, plans[i].target, turns);
		/* Improve the best of these one blocker at a time. */
		int sign = s->attacker == x->ai ? -1 : 1;
		int best = 0;
		for (int i = 1; i < count; i++)
			if (plans[i].score * sign > plans[best].score * sign) best = i;
		memcpy(t, plans[best].target, (size_t)s->n);
		int best_score = plans[best].score;
		for (int pass = 0; pass < 3 && count < MAX_PLANS - 1; pass++) {
			int improved = 0;
			for (int i = 0; i < b.count && count < MAX_PLANS - 1; i++) {
				int unit = b.blockers[i];
				int8_t kept = t[unit];
				for (int c = 0; c < b.option_count[i]; c++) {
					if (b.options[i][c] == kept) continue;
					t[unit] = b.options[i][c];
					int score = score_plan(x, s, t, turns);
					if (score * sign > best_score * sign) {
						best_score = score;
						kept = t[unit];
						improved = 1;
						int before = count;
						count = add_plan(plans, count, MAX_PLANS, t, s->n);
						if (count > before) plans[before].score = score;
					}
				}
				t[unit] = kept;
			}
			if (!improved) break;
		}
	}
	/* Best for the defender first. */
	int sign = s->attacker == x->ai ? 1 : -1;
	for (int i = 1; i < count; i++) {
		Plan p = plans[i];
		int j = i - 1;
		while (j >= 0 && plans[j].score * sign > p.score * sign) { plans[j + 1] = plans[j]; j--; }
		plans[j + 1] = p;
	}
	return imin(count, limit);
}

/* ----------------------------------------------------------- attack choices */

static int add_set(Set *sets, int count, uint32_t mask) {
	if (count >= MAX_SETS) return count;
	for (int i = 0; i < count; i++)
		if (sets[i].mask == mask) return count;
	sets[count].mask = mask;
	sets[count].score = 0;
	return count + 1;
}

/* Guards attack only beside another attacker of their race; the tax is paid. */
static int legal_set(const Search *x, const State *s, uint32_t mask) {
	int fresh = 0;
	for (int i = 0; i < s->n; i++) {
		if (!(mask >> i & 1)) continue;
		const Unit *u = &s->u[i];
		if (!(u->flags & F_ATTACKING)) fresh++;
	}
	if (!team_fits(s, mask)) return 0;
	return s->tax <= 0 || fresh * s->tax <= s->ether[s->attacker];
}

/* A set's worth after the defender's quick answers (no block, every attacker
 * chumped, the best single blocks). */
static int score_set(Search *x, const State *s, uint32_t mask, int turns) {
	State d = *s;
	declare(x, &d, mask);
	int8_t base[MAX_UNITS];
	memset(base, -1, sizeof(base));
	if (mask == 0) {
		end_turn(x, &d);
		x->nodes++;
		return evaluate_leaf(x, &d, turns);
	}
	int best = score_plan(x, &d, base, turns);
	int sign = s->attacker == x->ai ? -1 : 1;
	for (int style = 0; style < 2; style++) {
		int8_t t[MAX_UNITS];
		memset(t, -1, sizeof(t));
		uint32_t done = 0;
		int any = 0;
		for (;;) {
			int top = -1;
			for (int j = 0; j < d.n; j++) {
				const Unit *a = &d.u[j];
				if (!(a->flags & F_ATTACKING) || (a->flags & F_DEAD) || (done >> j & 1)) continue;
				if (top < 0 || a->power > d.u[top].power) top = j;
			}
			if (top < 0) break;
			done |= 1u << top;
			const Unit *a = &d.u[top];
			int pick = -1, pick_score = -1000000;
			for (int i = 0; i < d.n; i++) {
				const Unit *u = &d.u[i];
				if (u->owner == d.attacker || !ready(u) || t[i] >= 0 || !can_block(a, u)) continue;
				int score;
				if (style == 0) score = -u->ready_worth;
				else {
					int kills = u->power >= a->toughness, lives = u->toughness > a->power;
					if (!kills && !lives) continue;
					score = (kills ? 2000000 : 0) + (lives ? 1000000 : 0) - u->ready_worth;
				}
				if (score > pick_score) { pick_score = score; pick = i; }
			}
			if (pick >= 0) { t[pick] = (int8_t)top; any = 1; }
		}
		if (!any) continue;
		int score = score_plan(x, &d, t, turns);
		if (score * sign > best * sign) best = score;
	}
	return best;
}

/* The attack sets worth trying, best for the attacker first. */
static int attack_sets(Search *x, const State *s, Set *sets, int limit, int turns) {
	uint32_t forced = 0, free_mask = 0;
	int free_units[MAX_UNITS], free_count = 0;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->owner != s->attacker || (u->flags & F_DEAD)) continue;
		if (u->flags & F_ATTACKING) { forced |= 1u << i; continue; }
		if (!can_attack(s, u)) continue;
		if ((u->flags & F_BERSERK) && s->tax == 0 && !(u->flags & F_TEAM)) { forced |= 1u << i; continue; }
		free_units[free_count++] = i;
		free_mask |= 1u << i;
	}
	int count = 0;
	/* Like creatures side by side: of a group only its first k attack. */
	group_alike(s, free_units, free_count);
	double total = 1.0;
	for (int i = 0; i < free_count; ) {
		int j = i + 1;
		while (j < free_count && same_kind(&s->u[free_units[i]], &s->u[free_units[j]])) j++;
		total *= j - i + 1;
		i = j;
	}
	if (total <= (double)limit && free_count <= 16) {
		for (uint32_t bits = 0; bits < (1u << free_count) && count < MAX_SETS; bits++) {
			int canonical = 1;
			for (int i = 1; i < free_count && canonical; i++)
				if ((bits >> i & 1) && !(bits >> (i - 1) & 1) && same_kind(&s->u[free_units[i]], &s->u[free_units[i - 1]])) canonical = 0;
			if (!canonical) continue;
			uint32_t mask = forced;
			for (int i = 0; i < free_count; i++)
				if (bits >> i & 1) mask |= 1u << free_units[i];
			if (legal_set(x, s, mask)) count = add_set(sets, count, mask);
		}
	} else {
		/* Nobody, everybody, each alone, everybody but one, the strongest k,
		 * and those the defender cannot block at all. */
		int order[MAX_UNITS];
		for (int i = 0; i < free_count; i++) order[i] = free_units[i];
		for (int i = 1; i < free_count; i++) {
			int k = order[i], j = i - 1;
			while (j >= 0 && s->u[order[j]].power < s->u[k].power) { order[j + 1] = order[j]; j--; }
			order[j + 1] = k;
		}
		uint32_t candidates[MAX_SETS];
		int made = 0;
		candidates[made++] = forced;
		candidates[made++] = forced | free_mask;
		uint32_t evasive = forced;
		for (int i = 0; i < free_count; i++) {
			const Unit *a = &s->u[free_units[i]];
			int stoppable = 0;
			for (int j = 0; j < s->n && !stoppable; j++) {
				const Unit *u = &s->u[j];
				stoppable = u->owner != s->attacker && ready(u) && can_block(a, u);
			}
			if (!stoppable) evasive |= 1u << free_units[i];
		}
		candidates[made++] = evasive;
		uint32_t prefix = forced;
		for (int i = 0; i < free_count && made < MAX_SETS - 2; i++) {
			prefix |= 1u << order[i];
			candidates[made++] = prefix;
			candidates[made++] = evasive | prefix;
		}
		for (int i = 0; i < free_count && made < MAX_SETS - 2; i++) {
			candidates[made++] = forced | (1u << free_units[i]);
			candidates[made++] = (forced | free_mask) & ~(1u << free_units[i]);
		}
		for (int i = 0; i < made; i++)
			if (legal_set(x, s, candidates[i])) count = add_set(sets, count, candidates[i]);
	}
	if (count == 0) count = add_set(sets, count, forced);
	for (int i = 0; i < count; i++) sets[i].score = score_set(x, s, sets[i].mask, turns);
	int sign = s->attacker == x->ai ? -1 : 1;
	for (int i = 1; i < count; i++) {
		Set p = sets[i];
		int j = i - 1;
		while (j >= 0 && sets[j].score * sign > p.score * sign) { sets[j + 1] = sets[j]; j--; }
		sets[j + 1] = p;
	}
	return imin(count, limit);
}

/* ------------------------------------------------------------------- search */

static int set_limit(const Search *x, int level) {
	static const int wide[4] = { 64, 10, 6, 4 }, narrow[4] = { 12, 6, 4, 3 };
	return (x->wide ? wide : narrow)[imin(level, 3)];
}

static int plan_limit(const Search *x, int level) {
	static const int wide[4] = { 240, 16, 8, 6 }, narrow[4] = { 24, 8, 6, 4 };
	return (x->wide ? wide : narrow)[imin(level, 3)];
}

static int search_turn(Search *x, const State *s, int turns, int level, int alpha, int beta, uint32_t *best_set);

/* The declared attack `d` against the defender's best blocks. */
static int search_blocks(Search *x, const State *d, const int8_t *base, int turns, int level, int alpha, int beta, int8_t *best_plan) {
	Plan plans[MAX_PLANS];
	int count = block_plans(x, d, base, plans, plan_limit(x, level), turns);
	int maximise = d->attacker != x->ai;
	int best = maximise ? -2 * WIN : 2 * WIN;
	for (int i = 0; i < count; i++) {
		int v;
		if (turns <= 1 || x->nodes >= x->budget) {
			if (turns > 1) x->aborted = 1;
			v = plans[i].score;
		} else {
			State t = *d;
			resolve(&t, plans[i].target);
			x->nodes++;
			if (t.health[0] <= 0 || t.health[1] <= 0) {
				/* Decided in this turn's fight. */
				v = evaluate(x, &t, turns);
			} else {
				end_turn(x, &t);
				v = search_turn(x, &t, turns - 1, level + 1, alpha, beta, NULL);
			}
		}
		if (maximise ? v > best : v < best) {
			best = v;
			if (best_plan) memcpy(best_plan, plans[i].target, (size_t)d->n);
		}
		if (maximise) alpha = imax(alpha, best);
		else beta = imin(beta, best);
		if (alpha >= beta) break;
	}
	return best;
}

/* The side to move chooses its attackers; `turns` whole turns are played. */
static int search_turn(Search *x, const State *s, int turns, int level, int alpha, int beta, uint32_t *best_set) {
	if (s->health[0] <= 0 || s->health[1] <= 0) return evaluate(x, s, turns);
	if (turns <= 0) return evaluate_leaf(x, s, turns);
	if (x->nodes >= x->budget) {
		x->aborted = 1;
		return evaluate_leaf(x, s, turns);
	}
	Set sets[MAX_SETS];
	int count = attack_sets(x, s, sets, set_limit(x, level), turns);
	int maximise = s->attacker == x->ai;
	int best = maximise ? -2 * WIN : 2 * WIN;
	int8_t base[MAX_UNITS];
	memset(base, -1, sizeof(base));
	for (int i = 0; i < count; i++) {
		int v;
		State d = *s;
		declare(x, &d, sets[i].mask);
		if (sets[i].mask == 0) {
			if (turns <= 1) v = sets[i].score;
			else {
				end_turn(x, &d);
				x->nodes++;
				v = search_turn(x, &d, turns - 1, level + 1, alpha, beta, NULL);
			}
		} else {
			v = search_blocks(x, &d, base, turns, level, alpha, beta, NULL);
		}
		if (maximise ? v > best : v < best) {
			best = v;
			if (best_set) *best_set = sets[i].mask;
		}
		if (maximise) alpha = imax(alpha, best);
		else beta = imin(beta, best);
		if (alpha >= beta) break;
	}
	return best;
}

/* ----------------------------------------------------------------- interface */

/* ------------------------------------------------------------ playing cards */

/* Whatever the spell reaches: a single target, or a whole scope. */
static int spell_targets(const State *s, int side, const Card *c, int target, int *out) {
	int count = 0;
	if (c->effect != EFF_WAVE) {
		if (target != NO_TARGET) out[count++] = target;
		return count;
	}
	if (c->scope == SCOPE_HEROES) {
		out[count++] = -1;
		out[count++] = -2;
		return count;
	}
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->flags & (F_DEAD | F_GONE)) continue;
		if (c->scope == SCOPE_ENEMY && u->owner == side) continue;
		if (c->scope == SCOPE_GROUND && (u->flags & F_FLY)) continue;
		if (c->scope == SCOPE_FLYING && !(u->flags & F_FLY)) continue;
		out[count++] = i;
	}
	return count;
}

/* Hurts a hero (-1, -2 name hero 0 and 1) or a creature by index. */
static void spell_damage(State *s, int who, int amount) {
	if (amount <= 0) return;
	if (who < 0) hurt_hero(s, -who - 1, amount, -1);
	else if (who >= 0 && who < s->n) {
		Unit *t = &s->u[who];
		/* Nothing may be aimed at an unaffected creature, and nothing in the
		 * Colourless Plane is reached at all. */
		if (t->flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE)) return;
		/* An energy barrier takes three off it, and a lifeguard turns it
		 * aside whole and is gone: in the second game even when the barrier
		 * left nothing of it. */
		amount -= 3 * t->barriers;
		if (amount <= 0 && !s->second) return;
		if (t->guards > 0) {
			spend_guard(s, (int)(t - s->u));
			return;
		}
		if (amount <= 0) return;
		t->damage = (int16_t)(t->damage + amount);
		t->flags |= F_HIT;
		for (int k = 0; k < t->linked; k++) pain_hero(s, t->owner, amount);
		if (t->damage >= t->toughness) finish_unit(s, who);
	}
}

/* The first game's wall of illusion that took on less health than it has
 * wounds dies only once a spell has been cast or the fight is over. */
static void settle_illusions(State *s) {
	if (s->second) return;
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->ability == AB_ILLUSION && u->spent && !(u->flags & (F_DEAD | F_GONE)) && u->damage >= u->toughness) perish_unit(s, i);
	}
}

/* Harm that reaches a creature in the Colourless Plane, where nothing
 * dissipates: it regenerates or dies. */
static void plane_damage(State *s, int who, int amount) {
	Unit *t = &s->u[who];
	if ((t->flags & (F_DEAD | F_NO_AFFECT)) || !(t->flags & (F_PLANE | F_GONE))) return;
	amount -= 3 * t->barriers;
	if (amount <= 0 && !s->second) return;
	if (t->guards > 0) {
		spend_guard(s, who);
		return;
	}
	if (amount <= 0) return;
	t->damage = (int16_t)(t->damage + amount);
	t->flags |= F_HIT;
	for (int k = 0; k < t->linked; k++) pain_hero(s, t->owner, amount);
	if (t->damage >= t->toughness) {
		uint32_t fades = t->flags & F_DISSIPATES;
		t->flags &= ~(uint32_t)F_DISSIPATES;
		finish_unit(s, who);
		if (!(t->flags & F_DEAD)) t->flags |= fades;
	}
}

/* The side to move plays the card in `slot` of its hand. 0 when the rules
 * refuse it: an unknown spell, one already played, or ether it cannot pay. */
/* The card at a place of a hero's hand: one it was dealt or will draw, or
 * past those one that came back to it. NULL where there is none to play. */
static const Card *card_at(const Search *x, const State *s, int side, int slot) {
	if (slot >= ART_BASE) {
		/* A thing the hero carries: with a use left, in its round and phase. */
		int k = slot - ART_BASE;
		if (k >= MAX_ART) return NULL;
		const Card *c = &x->art[side][k];
		if (!c->free || c->effect == EFF_NONE || c->cost < 0) return NULL;
		if (s->art_left[side][k] <= 0 || s->art_used[side] >= x->art_limit[side]) return NULL;
		if (s->art_ready[side][k] > (x->serial + s->turns[0] + s->turns[1]) / 2 + 1) return NULL;
		if (!(x->art_phase[side][k] & (s->phase == 0 ? 1 : 2))) return NULL;
		return c;
	}
	if (slot < 0 || slot >= SLOTS + BACK) return NULL;
	if (slot >= SLOTS) {
		int kind = s->back[side][slot - SLOTS];
		return kind > 0 && kind <= POOL ? &x->pool[kind - 1] : NULL;
	}
	if (s->played[side] >> slot & 1) return NULL;
	/* A card still to be drawn cannot be played yet. */
	if (slot >= HAND && slot - HAND >= s->drawn[side]) return NULL;
	return &x->hand[side][slot];
}

static void destroy_unit(State *s, int index, int no_regeneration);

/* What a creature's card costs as printed. */
static int printed_cost(const Search *x, const Unit *u) {
	return x && u->kind > 0 ? x->pool[u->kind - 1].printed : u->cost;
}

/* The ether that takes one enchantment off a hero (-1, -2) or a creature,
 * or -1 where nothing does. `what` is the kind of a hero's, or the number of
 * the card laid on a creature; `aimed` asks that its holder can be named (1),
 * for whatever is there, even what no spell takes off (2), or for what has
 * a caster, wherever it lies (3). */
static int ench_price(const Search *x, const State *s, int holder, int what, int aimed) {
	if (holder == -1 || holder == -2) {
		int side = -holder - 1;
		if (what == HE_TAX) return s->taxes[side] > 0 ? x->tax_price : -1;
		if (what == HE_FOREST) return s->forest[side] >= 0 ? s->forest_price[side] : -1;
		if (what == HE_WATER) {
			for (int r = 0; r < s->enchs; r++)
				if (s->ench[r].kind == EN_WATER && s->ench[r].caster == side) return s->ench[r].price;
			return -1;
		}
		if (what == HE_BANNER) return s->banner[side] > 0 ? x->banner_price : -1;
		if (what < 0 || what >= HE_COUNT || s->he[side][what] <= 0) return -1;
		if (aimed != 2 && (aimed == 3 ? x->charm[what].fixed == 1 : x->charm[what].fixed)) return -1;
		return x->charm[what].price;
	}
	if (holder < 0 || holder >= s->n) return -1;
	const Unit *u = &s->u[holder];
	if ((u->flags & F_DEAD) || (aimed != 3 && (u->flags & F_GONE))) return -1;
	if (aimed < 2 && (u->flags & F_PLANE)) return -1;
	if (aimed == 1 && u->shielded) return -1;
	for (int r = 0; r < s->enchs; r++) {
		const Ench *e = &s->ench[r];
		if (e->unit != holder || e->code != what || e->kind == EN_WATER) continue;
		if (aimed == 2) return e->price;
		if (e->fixed) continue;
		/* One brought over stays while its own army has no room for it. */
		if (aimed != 3 && e->kind == EN_CONTROL && u->home > 0 && u->home - 1 != u->owner && army_size(s, u->home - 1) >= ARMY) continue;
		return e->price;
	}
	return -1;
}

/* It goes; with `any`, even one that is there for good. */
static void dispel(const Search *x, State *s, int holder, int what, int any) {
	if (holder == -1 || holder == -2) {
		int side = -holder - 1;
		if (what == HE_TAX) {
			if (s->taxes[side] > 0) {
				s->taxes[side]--;
				s->tax--;
				s->aura_worth[side] -= x->tax_worth;
			}
		} else if (what == HE_FOREST) {
			s->aura_worth[side] -= s->forest_worth[side];
			s->forest[side] = -1;
			s->forest_worth[side] = 0;
		} else if (what == HE_WATER) {
			for (int r = 0; r < s->enchs; r++)
				if (s->ench[r].kind == EN_WATER && s->ench[r].caster == side) {
					forget_ench(s, r);
					break;
				}
		} else if (what == HE_BANNER) {
			if (s->banner[side] > 0) {
				s->banner[side]--;
				banners(s);
			}
		} else if (what >= 0 && what < HE_COUNT) drop_charm(x, s, side, what, 1);
		return;
	}
	for (int r = 0; r < s->enchs; r++)
		if (s->ench[r].unit == holder && s->ench[r].code == what && s->ench[r].kind != EN_WATER && (any || !s->ench[r].fixed)) {
			unwear(s, r);
			return;
		}
}

/* The holder an enchantment anywhere is named with, out of its number. */
static inline int ench_holder(int choice) {
	int step = choice / 4096;
	return step < 2 ? -1 - step : step - 2;
}

static int cast_card(const Search *x, State *s, int side, int slot, int target, int power) {
	const Card *c = card_at(x, s, side, slot);
	if (!c || c->effect == EFF_NONE || c->cost < 0) return 0;
	/* A card that names a second thing is told it where another is told its X. */
	int choice = c->choice ? power : 0;
	if (c->choice) power = 0;
	if (power < 0 || (power > 0 && !c->variable)) return 0;
	if (c->channels > s->channels[side]) return 0;
	/* A channel's X is paid in the caster's health, not in ether. */
	int price = card_cost(x, s, c) + (c->variable && c->effect != EFF_CHANNEL ? power : 0);
	/* What a hero carries costs it nothing, whatever the spell would. */
	if (c->free) price = -30000;
	/* The second game charges these two another ether for every creature
	 * they reach. */
	if (s->second && (c->effect == EFF_ANNIHILATE || c->effect == EFF_BOUNCE_ALL))
		for (int i = 0; i < s->n; i++)
			if (!(s->u[i].flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE))) price++;
	if (price > s->ether[side]) return 0;
	int amount = c->variable ? power : c->amount;
	/* A data attraction on the caster answers every spell that is no creature. */
	int pulls = c->effect != EFF_SUMMON && c->free != 1 ? s->he[side][HE_TRLB] : 0;
	if (c->effect == EFF_CHANNEL && power > s->health[side]) return 0;
	if (c->effect == EFF_REVIVE && s->grave[side] <= 0) return 0;
	if (c->effect == EFF_DISCARD && target != -1 && target != -2) return 0;
	/* Channels are evened out only by the hero that has fewer, and taken
	 * only from a hero that has them. */
	if (c->effect == EFF_CHANNELS) {
		if (c->scope == SCOPE_BEHIND && s->channels[side] >= s->channels[1 - side]) return 0;
		if ((c->scope == SCOPE_ENEMY || c->scope == SCOPE_STEAL) && s->channels[1 - side] < amount) return 0;
	}
	/* A spell aimed at one creature needs one it can reach. */
	if (c->effect == EFF_UNSUMMON || c->effect == EFF_EXILE || c->effect == EFF_HUNGER || c->effect == EFF_SACRIFICE_HEAL
		|| c->effect == EFF_DEVOUR || c->effect == EFF_POLYMORPH || c->effect == EFF_TWISTER || c->effect == EFF_CLONE
		|| c->effect == EFF_EXCHANGE || c->effect == EFF_SWAP) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if (t->flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE)) return 0;
		if (c->own && t->owner != side) return 0;
		if (c->effect == EFF_UNSUMMON && t->cost > c->amount) return 0;
		/* One that pays the price of the creature it takes as well. */
		if (c->effect == EFF_EXILE && (c->amount & 1)) {
			price += printed_cost(x, t);
			if (price > s->ether[side]) return 0;
		}
		/* A second of its kind needs a card the engine knows, and room. */
		if (c->effect == EFF_CLONE && (t->kind <= 0 || army_size(s, side) >= ARMY || s->n >= MAX_UNITS)) return 0;
		if (c->effect == EFF_EXCHANGE && (choice < 0 || choice >= s->known[side] || s->graves[side][choice] <= 0 || s->n >= MAX_UNITS)) return 0;
		if (c->effect == EFF_SWAP) {
			if (choice < 0 || choice >= s->n) return 0;
			const Unit *v = &s->u[choice];
			if ((v->flags & (F_DEAD | F_GONE | F_PLANE)) || v->shielded) return 0;
		}
	}
	/* A card of a graveyard must be a creature the engine knows. */
	if (c->effect == EFF_REPAIR || c->effect == EFF_REANIMATE) {
		if (target != -1 && target != -2) return 0;
		int whose = -target - 1;
		if ((c->effect == EFF_REPAIR || c->own) && whose != side) return 0;
		if (choice < 0 || choice >= s->known[whose] || s->graves[whose][choice] <= 0) return 0;
		if (c->effect == EFF_REANIMATE) {
			if (army_size(s, side) >= ARMY || s->n >= MAX_UNITS) return 0;
			if ((c->amount & 1) && army_size(s, whose) >= ARMY) return 0;
		}
	}
	/* An enchantment to take off must be one that comes off; the one that
	 * pays what it cost pays that on top. */
	if (c->effect == EFF_DISPEL) {
		int owed = ench_price(x, s, target, choice, 1);
		if (owed < 0) return 0;
		if (c->amount & 1) price += owed;
		if (price > s->ether[side]) return 0;
	}
	/* One that takes only walls, only what flies, or only what attacks. */
	if (c->only) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if (((c->only & 1) && !(t->flags & F_WALL)) || ((c->only & 2) && !(t->flags & F_FLY)) || ((c->only & 4) && !(t->flags & F_ATTACKING))) return 0;
	}
	if (c->effect == EFF_BLESS) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if ((t->flags & (F_DEAD | F_GONE | F_PLANE)) || t->shielded) return 0;
	}
	if (c->effect == EFF_BANISH) {
		/* A pale creature that can go into the plane now. */
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if ((t->flags & (F_DEAD | F_GONE | F_PLANE)) || t->shielded || !t->pale) return 0;
		if (!may_shift(s, t) || worn_kind(s, target, EN_LOCK)) return 0;
	}
	if (c->effect == EFF_PALE_BLAST || c->effect == EFF_PALE_CLEAVE || c->effect == EFF_PALE_REVIVAL) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if ((t->flags & F_DEAD) || t->shielded) return 0;
		int away = (t->flags & (F_PLANE | F_GONE)) != 0;
		if (c->effect == EFF_PALE_CLEAVE && away) return 0;
		if (c->effect == EFF_PALE_REVIVAL) {
			if (!away || choice < 0 || choice / 64 > 1) return 0;
			if (choice % 64 >= s->known[choice / 64] || s->graves[choice / 64][choice % 64] <= 0) return 0;
		}
	}
	if (c->effect == EFF_GIFT) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if ((t->flags & (F_DEAD | F_GONE | F_PLANE)) || t->shielded || t->owner != side || army_size(s, 1 - side) >= ARMY) return 0;
	}
	if (c->effect == EFF_TRADE) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if ((t->flags & (F_DEAD | F_GONE | F_PLANE)) || t->shielded || t->owner != side) return 0;
		if (choice < 0 || ench_holder(choice) == target || ench_price(x, s, ench_holder(choice), choice % 4096, 1) < 0) return 0;
	}
	/* The second game's cleansing costs an ether more for every enchantment
	 * in play that is not there for good. */
	if (c->effect == EFF_CLEANSE && s->second) {
		for (int holder = 0; holder < 2; holder++) {
			for (int k = 0; k < HE_COUNT; k++)
				if (x->charm[k].fixed != 1) price += s->he[holder][k];
			price += s->taxes[holder] + (s->forest[holder] >= 0) + s->banner[holder];
		}
		for (int r = 0; r < s->enchs; r++) price += !s->ench[r].fixed && !(s->u[s->ench[r].unit].flags & F_DEAD);
		if (price > s->ether[side]) return 0;
	}
	/* The second game's ban needs the other hero to hold more than its caster keeps. */
	if (c->effect == EFF_BAN && s->second && cards_held(s, 1 - side) - (cards_held(s, side) - 1) <= 0) return 0;
	/* One aimed at a hero needs a hero. */
	if (c->effect == EFF_BURN_MANA || c->effect == EFF_DISCARD_ALL || c->effect == EFF_DISCARD_CREATURES) {
		if (target != -1 && target != -2) return 0;
	}
	/* An enchantment needs a creature nothing shields. */
	if (c->effect == EFF_ENCHANT || c->effect == EFF_CONTROL || c->effect == EFF_DELUSION) {
		if (target < 0 || target >= s->n) return 0;
		const Unit *t = &s->u[target];
		if (t->flags & (F_DEAD | F_GONE | F_NO_AFFECT)) return 0;
		/* A cripple is laid on a pale creature in the plane, and nothing else is. */
		if (c->effect == EFF_ENCHANT && c->special == SP_CRIPPLE) {
			if (!(t->flags & F_PLANE) || !t->pale || t->shielded) return 0;
		} else if (t->flags & F_PLANE) return 0;
	}
	/* An enchantment laid on a hero that is named, or on a hero or a creature. */
	if (c->effect == EFF_CHARM && c->aim != AIM_NONE) {
		if (target == NO_TARGET || target < -2 || target >= s->n) return 0;
		if (target >= 0 && (c->aim != AIM_ANY || (s->u[target].flags & (F_DEAD | F_GONE | F_PLANE)) || s->u[target].shielded)) return 0;
	}
	/* Only a creature of the other army that stands out of the fight comes
	 * over, and only to an army with room for it. */
	if (c->effect == EFF_CONTROL) {
		const Unit *t = &s->u[target];
		int army = 0;
		for (int i = 0; i < s->n; i++) army += s->u[i].owner == side && !(s->u[i].flags & F_DEAD);
		if (t->owner == side || (t->flags & F_ATTACKING) || t->blocks >= 0 || army >= ARMY) return 0;
	}
	if (c->effect == EFF_SUMMON) {
		int army = 0;
		for (int i = 0; i < s->n; i++) army += s->u[i].owner == side && !(s->u[i].flags & (F_DEAD));
		if (army >= ARMY || s->n >= MAX_UNITS) return 0;
	}
	if (slot >= ART_BASE) {
		/* One use the fewer, and it waits its rounds. */
		int k = slot - ART_BASE;
		s->art_left[side][k]--;
		s->art_ready[side][k] = (int16_t)((x->serial + s->turns[0] + s->turns[1]) / 2 + 1 + x->art_gap[side][k]);
		s->art_used[side]++;
	} else if (slot >= SLOTS) s->back[side][slot - SLOTS] = 0;
	else {
		s->played[side] |= 1u << slot;
		if (s->cast[side] < 100) s->cast[side]++;
	}
	/* The spell traps that stand as it is cast are the ones it springs. */
	int8_t set[2][3];
	for (int owner = 0; owner < 2; owner++)
		for (int j = 0; j < 3; j++) set[owner][j] = (int8_t)(s->second && c->klass == 2 && c->free != 1 ? s->he[owner][HE_OST1 + j] : 0);
	if (!c->free) pay(s, side, price);
	switch (c->effect) {
	case EFF_SUMMON:
		summon(x, s, side, c);
		/* An ether tax on a hero pays it two for every creature that arrives
		 * by a spell. */
		if (c->free != 1)
			for (int r = 0; r < 2; r++) gain_ether(s, r, 2 * s->he[r][HE_MNTX]);
		break;
	case EFF_DAMAGE:
	case EFF_WAVE: {
		int who[MAX_UNITS + 2];
		int count = spell_targets(s, side, c, target, who);
		/* One that also strikes the rest of the side it hurts: who they
		 * are is settled before the first blow. */
		int also[MAX_UNITS + 1], others = 0;
		if (c->splash > 0 && count == 1) {
			int victims = who[0] < 0 ? -who[0] - 1 : s->u[who[0]].owner;
			if (who[0] >= 0) also[others++] = -1 - victims;
			for (int i = 0; i < s->n; i++)
				if (i != who[0] && s->u[i].owner == victims && !(s->u[i].flags & F_DEAD)) also[others++] = i;
		}
		for (int i = 0; i < count; i++) spell_damage(s, who[i], amount);
		for (int i = 0; i < others; i++) {
			if (also[i] >= 0 && (s->u[also[i]].flags & F_DEAD)) continue;
			spell_damage(s, also[i], c->splash);
		}
		break;
	}
	case EFF_DESTROY:
		if (target >= 0 && target < s->n) destroy_unit(s, target, c->amount & 1);
		break;
	case EFF_BANNER:
		for (int i = 0; i < s->n; i++)
			if (!(s->u[i].flags & F_DEAD) && (s->u[i].flags & F_NO_AFFECT) && s->u[i].spared < 100) s->u[i].spared++;
		if (s->banner[side] < 100) s->banner[side]++;
		if (c->printed > 0) ((Search *)x)->banner_price = c->printed;
		banners(s);
		break;
	case EFF_BLESS: {
		Unit *t = &s->u[target];
		add_power(t, c->gives_power);
		t->raw = (int16_t)(t->raw + c->gives_toughness);
		settle_health(t);
		int gain = (c->gives_power * ((t->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth) + c->gives_toughness * x->tough_worth) / 2;
		t->ready_worth += gain;
		t->resting_worth += gain;
		if (t->passing < 100) t->passing++;
		t->passing_power = (int16_t)(t->passing_power + c->gives_power);
		t->passing_health = (int16_t)(t->passing_health + c->gives_toughness);
		t->passing_ready += gain;
		t->passing_resting += gain;
		break;
	}
	case EFF_HEAL:
		/* Aimed at nothing, it heals its caster. */
		if (target == NO_TARGET) s->health[side] += amount;
		else if (target < 0) s->health[-target - 1] += amount;
		else if (target < s->n) s->u[target].damage = (int16_t)imax(0, s->u[target].damage - amount);
		break;
	case EFF_ENCHANT: {
		Unit *t = &s->u[target];
		Unit was = *t;
		if (c->special == SP_WATER) {
			note_ench(s, target, &was, side, EN_WATER, c->code, c->printed, 0, 0, 0);
			break;
		}
		int gives_power = c->gives_power, gives_toughness = c->gives_toughness;
		switch (c->special) {
		case SP_X_POWER:
			gives_power += amount;
			break;
		case SP_X_HEALTH:
			gives_toughness += amount;
			break;
		case SP_MARK:
			for (int i = 0; i < s->n; i++)
				if (s->u[i].owner != side && s->u[i].pale && !(s->u[i].flags & F_DEAD)) {
					gives_power++;
					gives_toughness++;
				}
			break;
		case SP_ALPHA:
			/* It is healed, and strikes with its printed power on top. */
			t->damage = 0;
			gives_power += t->kind > 0 ? x->pool[t->kind - 1].power : t->power;
			break;
		default:
			break;
		}
		add_power(t, gives_power);
		/* What an enchantment takes leaves a creature at least one point of
		 * health, unless it is of the kind that kills (`amount` bit 0). */
		if (c->amount & 1) t->lethal = (int16_t)(t->lethal - gives_toughness);
		else t->raw = (int16_t)(t->raw + gives_toughness);
		settle_health(t);
		/* An alpha strike leaves it one point of health. */
		if (c->special == SP_ALPHA) {
			t->alpha++;
			settle_health(t);
		}
		/* One that lets it regenerate, for the least it then may pay. */
		int regrows = (c->amount >> 11) & 15, regen_was = -1;
		if (regrows > 0 && (t->regeneration == 0 || t->regeneration > regrows)) {
			regen_was = t->regeneration;
			t->regeneration = (int8_t)regrows;
		}
		/* One nothing can be aimed past, and one that keeps it from what it
		 * can do. */
		if (c->amount & 128) t->shielded = 1;
		if ((c->amount & 64) && t->ability) {
			t->bare_ability = t->ability;
			t->ability = 0;
		}
		if (c->amount & 2) t->twisted++;
		if (c->amount & 4) t->overload++;
		/* One that makes its creature a robber. */
		if ((c->amount >> 8) & 7) {
			int robs = (c->amount >> 8) & 7;
			t->discards = (int8_t)imin(100, t->discards + robs);
			t->worn_discards = (int8_t)imin(100, t->worn_discards + robs);
		}
		if (c->amount & 8) t->linked++;
		/* One that stirs its creature at once. */
		if (c->amount & 32) t->flags &= ~(uint32_t)F_RESTING;
		t->flags |= c->lends;
		/* What it lends is worth what the same points are worth on any
		 * creature; without this an enchantment only ever costs its card. */
		{
			int gain = gives_power * ((t->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth)
				+ gives_toughness * x->tough_worth;
			/* What lasts a turn is worth half of what lasts. */
			if (c->amount & 16) gain /= 2;
			t->ready_worth += gain;
			t->resting_worth += gain;
		}
		if (c->holds) {
			/* It taps at once; the second game also calls back an attacker. */
			t->flags |= F_RESTING | F_NO_UNTAP;
			if (s->second) t->flags &= ~(uint32_t)F_ATTACKING;
			if (c->wake > 0) {
				t->wake = c->wake;
				/* Paralysis and immobility are broken for a turn at the cost
				 * of health as well; enfeeblement is thrown off for good. */
				t->wake_hurts = (int8_t)(c->holds == 2);
			}
		}
		wears(t, &was, 1, c->lends | (c->holds ? F_NO_UNTAP : 0));
		if (!(c->holds && c->fixed)) {
			static const int8_t KINDS[] = { EN_PLAIN, EN_PLAIN, EN_PLAIN, EN_PLAIN, EN_ALPHA, EN_REDIRECT, EN_BONDS, EN_LOCK, EN_CRIPPLE, EN_STORM, EN_BREEZE, EN_RIOT };
			int kind = c->holds ? EN_HOLD : ((c->amount & 2) ? EN_TWIST : ((c->amount & 4) ? EN_OVERLOAD : ((c->amount & 8) ? EN_LINK : EN_PLAIN)));
			if (c->special > 0 && c->special <= SP_RIOT) kind = KINDS[c->special];
			int tick = (c->amount >> 15) & 3;
			if (tick && kind == EN_PLAIN) kind = EN_HURTS;
			Ench *e = note_ench(s, target, &was, side, kind, c->code, c->fixed ? -1 - c->printed : c->printed, (c->amount & 16) != 0, c->comes_back, (c->amount >> 8) & 7);
			if (e) {
				e->tick = (int8_t)tick;
				e->mutes = (int8_t)((c->amount & 64) != 0);
				e->shields = (int8_t)((c->amount & 128) && !was.shielded);
				if (regen_was >= 0) e->regen = (int8_t)(regen_was + 1);
			}
		}
		if (c->amount & 16) {
			if (t->brief < 100) t->brief++;
			t->brief_power = (int16_t)(t->brief_power + (t->power - t->under) - (was.power - was.under));
			t->brief_health = (int16_t)(t->brief_health + t->toughness - was.toughness);
			t->brief_flags |= c->lends & ~was.flags;
			t->brief_ready += t->ready_worth - was.ready_worth;
			t->brief_resting += t->resting_worth - was.resting_worth;
		}
		if (t->damage >= t->toughness) perish_unit(s, target);
		break;
	}
	case EFF_MANA:
		gain_ether(s, side, amount);
		break;
	case EFF_UNSUMMON:
		remove_unit(s, target, 1);
		break;
	case EFF_EXILE:
		remove_unit(s, target, 0);
		break;
	case EFF_ANNIHILATE: {
		/* Each side's power is totalled before anything dies; then its
		 * creatures are destroyed and the other hero takes the total. */
		int totals[2] = {0, 0};
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if (u->flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE)) continue;
			totals[u->owner] += imax(0, u->power);
		}
		for (int victim = 0; victim < 2; victim++) {
			int n = s->n;
			for (int i = 0; i < n; i++) {
				Unit *u = &s->u[i];
				if (u->owner != victim || (u->flags & (F_DEAD | F_GONE | F_PLANE | F_NO_AFFECT))) continue;
				u->damage = u->toughness;
				u->flags |= F_HIT;
				finish_unit(s, i);
			}
			hurt_hero(s, 1 - victim, totals[victim], -1);
		}
		break;
	}
	case EFF_FULL_HEAL:
		/* The first game also lowers a surplus to the starting health. */
		if (!s->second || s->health[side] < x->maximum[side]) s->health[side] = x->maximum[side];
		break;
	case EFF_HALF_HEAL:
		if (s->health[side] < x->maximum[side] / 2) s->health[side] = x->maximum[side] / 2;
		break;
	case EFF_DRAW:
		/* Cards drawn out of turn are not the ones the engine was told of,
		 * and they change every draw that follows. */
		if (x->blinds) {
			int who = target == -1 || target == -2 ? -target - 1 : side;
			s->more[who] += imin(amount, book_room(x, s, who));
			s->blind = 1;
		} else draw_cards(s, target == -1 || target == -2 ? -target - 1 : side, amount);
		break;
	case EFF_REST_ENEMIES:
		/* `amount` bit 0: walls are spared rather than the restless; bit 1:
		 * a creature already sent to attack is called back. */
		for (int i = 0; i < s->n; i++) {
			Unit *u = &s->u[i];
			if (u->owner == side || (u->flags & (F_DEAD | F_GONE | F_RESTING))) continue;
			if ((c->amount & 1) ? (u->flags & F_WALL) != 0 : (u->flags & F_RESTLESS) != 0) continue;
			if (s->second && ((u->flags & F_NO_AFFECT) || (!(c->amount & 1) && (u->flags & F_PLANE)))) continue;
			u->flags |= F_RESTING;
			if (c->amount & 2) u->flags &= ~(uint32_t)F_ATTACKING;
		}
		break;
	case EFF_RALLY_ALL:
		for (int i = 0; i < s->n; i++) {
			Unit *u = &s->u[i];
			if (u->owner != side || (u->flags & (F_DEAD | F_GONE)) || !(u->flags & F_RESTING)) continue;
			if ((u->flags & F_ATTACKING) || u->blocks >= 0 || (s->second && (u->flags & F_NO_AFFECT))) continue;
			u->flags &= ~(uint32_t)F_RESTING;
		}
		break;
	case EFF_BURN_MANA: {
		int hero = -target - 1, burnt = s->ether[hero];
		s->ether[hero] = 0;
		hurt_hero(s, hero, burnt, -1);
		break;
	}
	case EFF_DRAIN_MANA: {
		int taken = imin(amount, s->ether[1 - side]);
		s->ether[1 - side] -= taken;
		gain_ether(s, side, taken);
		break;
	}
	case EFF_DRAIN_LIFE: {
		int before = s->health[1 - side];
		hurt_hero(s, 1 - side, amount, -1);
		if (s->health[1 - side] < before) s->health[side] += imin(amount, before);
		break;
	}
	case EFF_CHANNEL:
		/* X damage to the caster, ether for it (and four more in the first
		 * game), and the other hero heals X. */
		hurt_hero(s, side, amount, -1);
		s->ether[side] += amount + (s->second ? 0 : 4);
		if (amount > 0) s->health[1 - side] += amount;
		break;
	case EFF_HUNGER:
		if (s->u[target].power > 0) spell_damage(s, target, s->u[target].power);
		break;
	case EFF_HUNGER_ALL:
	case EFF_HUNGER_BOTH: {
		int n = s->n;
		for (int i = 0; i < n; i++) {
			const Unit *u = &s->u[i];
			if ((u->flags & (F_DEAD | F_GONE)) || u->power <= 0) continue;
			if (c->effect == EFF_HUNGER_ALL && u->owner == side) continue;
			spell_damage(s, i, u->power);
		}
		break;
	}
	case EFF_SACRIFICE_HEAL: {
		int gain = s->u[target].toughness;
		kill_unit(s, target);
		s->health[side] += gain;
		break;
	}
	case EFF_DEVOUR: {
		int strength = imax(0, s->u[target].power), gain = s->u[target].toughness;
		kill_unit(s, target);
		s->health[side] += gain;
		hurt_hero(s, 1 - side, strength, -1);
		if (s->second) draw_cards(s, side, 1);
		break;
	}
	case EFF_POLYMORPH: {
		/* The caster's health becomes the creature's toughness, and in the
		 * second game its power as well. */
		int value = s->u[target].toughness + (s->second ? imax(0, s->u[target].power) : 0);
		kill_unit(s, target);
		s->health[side] = value;
		break;
	}
	case EFF_SYMBIOSIS: {
		int living = 0;
		for (int i = 0; i < s->n; i++) living += !(s->u[i].flags & F_DEAD);
		s->health[side] += 2 * living;
		break;
	}
	case EFF_TWISTER: {
		/* It can no longer regenerate and is destroyed, and the hero whose
		 * turn it is takes its power: read without what it wears or gave
		 * itself for the turn. */
		Unit *t = &s->u[target];
		Unit was = *t;
		int strength = imax(0, t->power - t->under - t->worn_power - t->passing_power);
		t->flags |= F_NO_REGEN;
		wears(t, &was, 1, F_NO_REGEN);
		note_ench(s, target, &was, side, EN_PLAIN, c->code, -1 - c->printed, 0, 0, 0);
		destroy_unit(s, target, 0);
		hurt_hero(s, s->attacker, strength, -1);
		break;
	}
	case EFF_BOUNCE_ALL: {
		int n = s->n;
		for (int i = 0; i < n; i++) {
			if (s->u[i].flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE)) continue;
			remove_unit(s, i, 1);
		}
		break;
	}
	case EFF_DISCARD:
		discard_cards(s, -target - 1, amount, c->scope != SCOPE_ALL, side);
		break;
	case EFF_MIND_BLAST:
		/* Every card a hero holds over five hurts it. */
		for (int victim = 0; victim < 2; victim++)
			hurt_hero(s, victim, (s->second ? 3 : 2) * (cards_held(s, victim) - 5), -1);
		break;
	case EFF_DISCARD_ALL:
		empty_hand(x, s, -target - 1, side);
		break;
	case EFF_REPAIR: {
		/* The card comes back to the hand, and the other hero takes its
		 * printed power in the second game and one point in the first. */
		int kind = unbury(s, side, choice);
		take_back(s, side, kind);
		hurt_hero(s, 1 - side, s->second ? x->pool[kind - 1].power : 1, -1);
		break;
	}
	case EFF_REANIMATE: {
		int kind = unbury(s, -target - 1, choice), first = s->n;
		summon(x, s, side, &x->pool[kind - 1]);
		if ((c->amount & 2) && s->n > first) {
			/* A quick fix stays on what it raised, a point off its power and
			 * its health: taken off, it destroys the creature for good. */
			Unit *t = &s->u[first];
			Unit was = *t;
			add_power(t, -1);
			t->raw--;
			settle_health(t);
			t->ready_worth -= x->power_worth + x->tough_worth;
			t->resting_worth -= x->power_worth + x->tough_worth;
			t->fate |= FATE_DESTROYED;
			wears(t, &was, 1, 0);
			note_ench(s, first, &was, side, EN_QUICK, c->code, c->printed, 0, 2, 0);
			if (!(t->flags & (F_PLANE | F_GONE)) && t->damage >= t->toughness) perish_unit(s, first);
		}
		break;
	}
	case EFF_GIFT: {
		/* It changes hands for good, out of any fight, and waits a turn
		 * unless it is of the kind that never does. */
		Unit *t = &s->u[target];
		Unit was = *t;
		if (t->flags & F_ATTACKING)
			for (int k = 0; k < s->n; k++)
				if (s->u[k].blocks == target) s->u[k].blocks = -1;
		t->flags &= ~(uint32_t)F_ATTACKING;
		t->blocks = -1;
		t->owner = (int8_t)(1 - side);
		t->home = 0;
		if (t->kind <= 0 || (x->pool[t->kind - 1].flags & F_SICK)) t->flags |= F_SICK;
		wears(t, &was, 1, 0);
		note_ench(s, target, &was, side, EN_GIFT, c->code, -1 - c->printed, 0, 0, 0);
		if (s->gifted[1 - side] < 50) s->gifted[1 - side]++;
		break;
	}
	case EFF_AMNESIA:
		empty_hand(x, s, 0, side);
		empty_hand(x, s, 1, side);
		if (s->second) deal(x, s, side, 1);
		break;
	case EFF_BAN:
		/* The second game brings the other hand down to the caster's; the
		 * first takes two cards from each. */
		if (s->second) discard_cards(s, 1 - side, cards_held(s, 1 - side) - cards_held(s, side), 0, side);
		else
			for (int victim = 0; victim < 2; victim++) discard_cards(s, victim, 2, 0, side);
		break;
	case EFF_CLONE:
		summon(x, s, side, &x->pool[s->u[target].kind - 1]);
		break;
	case EFF_EXCHANGE: {
		/* The card leaves the graveyard before the creature given for it lies there. */
		int kind = unbury(s, side, choice);
		kill_unit(s, target);
		summon(x, s, side, &x->pool[kind - 1]);
		break;
	}
	case EFF_SWAP: {
		/* The creature given dies first; the hero of the one then destroyed
		 * gains its health, whether or not it lives through that. Naming the
		 * one given twice only gives it, for the health it has of itself. */
		Unit *given = &s->u[target];
		if (choice == target) {
			int gain = given->toughness - given->worn_health - given->passing_health, controller = given->owner;
			kill_unit(s, target);
			s->health[controller] += gain;
		} else {
			kill_unit(s, target);
			const Unit *v = &s->u[choice];
			if (!(v->flags & (F_DEAD | F_GONE))) {
				int gain = v->toughness, controller = v->owner;
				destroy_unit(s, choice, 0);
				s->health[controller] += gain;
			}
		}
		break;
	}
	case EFF_DISPEL:
		dispel(x, s, target, choice, 0);
		break;
	case EFF_TRADE:
		/* The creature given dies first. */
		kill_unit(s, target);
		if (ench_price(x, s, ench_holder(choice), choice % 4096, 1) >= 0) dispel(x, s, ench_holder(choice), choice % 4096, 0);
		break;
	case EFF_CLEANSE:
		for (int holder = 0; holder < 2; holder++) {
			for (int k = 0; k < HE_COUNT; k++)
				if (!x->charm[k].fixed) drop_charm(x, s, holder, k, s->he[holder][k]);
			while (s->taxes[holder] > 0) dispel(x, s, -1 - holder, HE_TAX, 0);
			if (s->forest[holder] >= 0) dispel(x, s, -1 - holder, HE_FOREST, 0);
			while (s->banner[holder] > 0) dispel(x, s, -1 - holder, HE_BANNER, 0);
		}
		for (;;) {
			int found = -1;
			for (int r = 0; r < s->enchs && found < 0; r++)
				if (s->ench[r].kind == EN_WATER || (!s->ench[r].fixed && ench_price(x, s, s->ench[r].unit, s->ench[r].code, 0) >= 0)) found = r;
			if (found < 0) break;
			unwear(s, found);
		}
		break;
	case EFF_BANISH:
		/* A pale creature sent into the plane is a card for the caster. */
		if (banish(x, s, target) && (s->u[target].flags & F_PLANE)) deal(x, s, side, 1);
		break;
	case EFF_FLUX: {
		/* As much as the caster has creatures that are not pale. */
		int harm = 0, all = s->n;
		for (int i = 0; i < all; i++) harm += s->u[i].owner == side && !s->u[i].pale && !(s->u[i].flags & F_DEAD);
		for (int i = 0; harm > 0 && i < all; i++) plane_damage(s, i, harm);
		break;
	}
	case EFF_RIPPLE: {
		int all = s->n;
		for (int i = 0; i < all; i++) plane_damage(s, i, 3);
		lay_charm(x, s, side, HE_ORPL);
		break;
	}
	case EFF_PALE_BLAST: {
		/* The enchantment laid on it last goes, if any can; a pale creature
		 * then takes three, wherever it is. */
		Unit *t = &s->u[target];
		if (!(t->flags & (F_PLANE | F_GONE)))
			for (int r = s->enchs - 1; r >= 0; r--) {
				const Ench *e = &s->ench[r];
				if (e->unit != target || e->kind == EN_WATER || e->fixed) continue;
				if (e->kind == EN_CONTROL && t->home > 0 && t->home - 1 != t->owner && army_size(s, t->home - 1) >= ARMY) continue;
				unwear(s, r);
				break;
			}
		if (!(t->flags & F_DEAD) && t->pale) {
			if (t->flags & (F_PLANE | F_GONE)) plane_damage(s, target, 3);
			else spell_damage(s, target, 3);
		}
		break;
	}
	case EFF_PALE_CALAMITY:
		for (int victim = 0; victim < 2; victim++) {
			int away = 0;
			for (int i = 0; i < s->n; i++) away += s->u[i].owner == victim && !(s->u[i].flags & F_DEAD) && (s->u[i].flags & (F_PLANE | F_GONE)) != 0;
			discard_cards(s, victim, away, 0, side);
		}
		break;
	case EFF_PALE_CLEAVE: {
		Unit *t = &s->u[target];
		if (t->pale) {
			/* Destroyed where it stands: it may regenerate, never dissipate. */
			uint32_t fades = t->flags & F_DISSIPATES;
			t->flags &= ~(uint32_t)F_DISSIPATES;
			destroy_unit(s, target, 0);
			if (!(t->flags & F_DEAD)) t->flags |= fades;
		} else remove_unit(s, target, 1);
		break;
	}
	case EFF_PALE_REVIVAL: {
		/* Destroyed in the plane past regenerating, though a lifeguard still
		 * turns that; then the card comes out of its graveyard for the caster. */
		Unit *t = &s->u[target];
		int whose = choice / 64, kind = s->graves[whose][choice % 64];
		if (!(t->flags & F_NO_AFFECT)) {
			if (t->guards > 0) spend_guard(s, target);
			else {
				int left = imax(1, t->toughness - t->damage);
				for (int k = 0; k < t->linked; k++) pain_hero(s, t->owner, left);
				kill_unit(s, target);
			}
		}
		if (army_size(s, side) < ARMY && s->n < MAX_UNITS) {
			int place = -1;
			for (int p = 0; p < s->known[whose]; p++)
				if (s->graves[whose][p] == kind) place = p;
			if (place >= 0) {
				unbury(s, whose, place);
				summon(x, s, side, &x->pool[kind - 1]);
			}
		}
		break;
	}
	case EFF_PALE_THEFT:
		for (int victim = 0; victim < 2; victim++) {
			/* A card for every race of pale creature it commands. */
			int races = 0;
			for (int i = 0; i < s->n; i++) {
				const Unit *u = &s->u[i];
				if (u->owner != victim || !u->pale || (u->flags & F_DEAD)) continue;
				int seen = 0;
				for (int j = 0; j < i && !seen; j++)
					seen = s->u[j].owner == victim && s->u[j].pale && !(s->u[j].flags & F_DEAD) && s->u[j].race == u->race;
				races += !seen;
			}
			int lost = imin(races, cards_held(s, victim));
			discard_cards(s, victim, lost, 0, side);
			deal(x, s, 1 - victim, lost);
		}
		break;
	case EFF_VAPORIZE: {
		int all = s->n;
		for (int i = 0; i < all; i++)
			if (s->u[i].pale && !(s->u[i].flags & (F_DEAD | F_PLANE | F_GONE))) banish(x, s, i);
		break;
	}
	case EFF_REDRAW:
		/* A hand given up and dealt again, as many cards as it was: of one
		 * class only (`amount` bit 0 no creatures, bit 1 nothing else), or
		 * whatever comes (bit 2). */
		for (int victim = 0; victim < 2; victim++) {
			if (c->scope != SCOPE_BOTH && victim != side) continue;
			int count = empty_hand(x, s, victim, side);
			/* No more than the hero's book still holds of the kind. */
			if (c->amount & 1) count = imin(count, x->deals[victim][1]);
			else if (c->amount & 2) count = imin(count, x->deals[victim][0]);
			else count = imin(count, x->deals[victim][0] + x->deals[victim][1]);
			if (x->blinds || !(c->amount & 4)) {
				s->more[victim] += count;
				if (x->blinds) s->blind = 1;
			} else draw_cards(s, victim, count);
		}
		break;
	case EFF_DISCARD_CREATURES: {
		/* The newest creature cards go first. */
		int hero = -target - 1, left = amount;
		for (int j = BACK - 1; j >= 0 && left > 0; j--)
			if (s->back[hero][j]) {
				int kind = s->back[hero][j];
				s->back[hero][j] = 0;
				left--;
				discard_answer(x, s, hero, &x->pool[kind - 1], side);
			}
		for (int i = imin(SLOTS, HAND + s->drawn[hero]) - 1; i >= 0 && left > 0; i--) {
			if ((s->played[hero] >> i & 1) || x->hand[hero][i].effect != EFF_SUMMON || x->hand[hero][i].cost < 0) continue;
			s->played[hero] |= 1u << i;
			left--;
			discard_answer(x, s, hero, &x->hand[hero][i], side);
		}
		break;
	}
	case EFF_CHARM: {
		int k = c->amount;
		if (k < 0 || k >= HE_COUNT) break;
		/* On a creature: a stone skin, a lifeguard or an energy barrier of its own. */
		if (target >= 0) {
			Unit *t = &s->u[target];
			Unit was = *t;
			if (k == HE_STSK) t->skins++;
			else if (k == HE_LFGR) t->guards++;
			else if (k == HE_ENBR) t->barriers++;
			wears(t, &was, 1, 0);
			note_ench(s, target, &was, side, k == HE_STSK ? EN_SKIN : (k == HE_LFGR ? EN_GUARD : EN_BARRIER), c->code, c->fixed ? -1 - c->printed : c->printed, 0, c->comes_back, 0);
			break;
		}
		/* Where it is laid: on its caster, on the other hero, or on the one named. */
		int holder = c->scope == 1 ? 1 - side : (c->scope == 2 && target != NO_TARGET ? -target - 1 : side);
		if (k == HE_STSI && s->he[holder][k] == 0) s->stasis_age[holder] = 0;
		if (k == HE_MNVR) s->young[holder]++;
		lay_charm(x, s, holder, k);
		/* An enlightenment changes how many cards every turn deals. */
		if (k == HE_ENLH && x->blinds) s->blind = 1;
		/* A fog and a rain of ash call every creature home, a blockade the caster's own. */
		if (k == HE_FOGG || k == HE_BLKD || k == HE_ASST)
			for (int i = 0; i < s->n; i++) {
				if (k == HE_BLKD && s->u[i].owner != side) continue;
				s->u[i].flags &= ~(uint32_t)F_ATTACKING;
				s->u[i].blocks = -1;
			}
		break;
	}
	case EFF_CONTROL: {
		/* It changes sides as it stands, and must wait a turn to act. */
		Unit *t = &s->u[target];
		Unit was = *t;
		if (!t->home) t->home = (int8_t)(t->owner + 1);
		wears(t, &was, 1, 0);
		note_ench(s, target, &was, side, EN_CONTROL, c->code, c->fixed ? -1 - c->printed : c->printed, 0, c->comes_back, 0);
		t->owner = (int8_t)side;
		/* The second game's creatures that need no rest act at once, and
		 * go home as ready. */
		if (s->second && t->kind > 0 && !(x->pool[t->kind - 1].flags & F_SICK)) {
			t->fate |= FATE_READY;
			t->flags &= ~(uint32_t)F_SICK;
		} else t->flags |= F_SICK;
		t->flags &= ~(uint32_t)F_ATTACKING;
		t->blocks = -1;
		break;
	}
	case EFF_DELUSION: {
		/* Power and health change places; no floor of one holds here. */
		Unit *t = &s->u[target];
		Unit was = *t;
		int power = t->power, health = t->toughness;
		int gain = (health - power) * ((t->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth) + (power - health) * x->tough_worth;
		t->power = (int16_t)imax(0, health);
		t->under = 0;
		t->raw = (int16_t)imax(1, power);
		t->lethal = (int16_t)(t->raw - power);
		t->toughness = (int16_t)power;
		t->ready_worth += gain;
		t->resting_worth += gain;
		wears(t, &was, 1, 0);
		note_ench(s, target, &was, side, EN_DELUSION, c->code, c->fixed ? -1 - c->printed : c->printed, 0, c->comes_back, 0);
		if (t->damage >= t->toughness) perish_unit(s, target);
		break;
	}
	case EFF_TAX:
		if (c->printed > 0) ((Search *)x)->tax_price = c->printed;
		s->taxes[side]++;
		s->tax++;
		s->aura_worth[side] += c->ready_worth;
		break;
	case EFF_FOREST:
		/* Forests do not add up: the deepest one on a hero is the one that holds. */
		if (c->amount > s->forest[side]) {
			s->aura_worth[side] += c->ready_worth - s->forest_worth[side];
			s->forest[side] = c->amount;
			s->forest_worth[side] = c->ready_worth;
			s->forest_price[side] = c->printed;
		}
		break;
	case EFF_REVIVE:
		/* The last creature to die returns to the hand, and the other hero takes one. */
		take_back(s, side, unbury(s, side, s->known[side] - 1));
		hurt_hero(s, 1 - side, 1, -1);
		break;
	case EFF_FURY: {
		int n = s->n, deaths = 0, tried = 0;
		uint32_t stood = 0;
		for (int i = 0; i < n; i++)
			if (!(s->u[i].flags & F_DEAD)) stood |= 1u << i;
		for (int i = 0; i < n; i++) {
			Unit *u = &s->u[i];
			if (u->flags & (F_DEAD | F_GONE)) continue;
			tried++;
			/* Counted as struck, but nothing reaches these. */
			if (u->flags & (F_NO_AFFECT | F_PLANE)) continue;
			u->damage = u->toughness;
			u->flags |= F_HIT;
			finish_unit(s, i);
		}
		/* Every creature that is no longer there counts, whatever took it:
		 * the death of another does for some. */
		for (int i = 0; i < n; i++)
			if ((stood >> i & 1) && (s->u[i].flags & F_DEAD)) deaths++;
		/* The second game deals the other hero a card for each death; the
		 * first hurts the hero whose turn it is by one for each creature
		 * struck, whether or not it lived. */
		if (s->second) draw_cards(s, 1 - side, deaths);
		else hurt_hero(s, s->attacker, tried, -1);
		break;
	}
	case EFF_GRAVE_FIRE:
		for (int victim = 0; victim < 2; victim++)
			if (s->grave[victim] > 0) hurt_hero(s, victim, (s->second ? 3 : 2) * s->grave[victim], -1);
		if (s->second) {
			s->grave[0] = s->grave[1] = 0;
			s->known[0] = s->known[1] = 0;
		}
		break;
	case EFF_CHANNELS:
		switch (c->scope) {
		case SCOPE_BEHIND:
			if (s->channels[1 - side] > s->channels[side]) change_channels(s, side, amount);
			break;
		case SCOPE_BOTH:
			change_channels(s, 0, amount);
			change_channels(s, 1, amount);
			break;
		case SCOPE_ENEMY:
			change_channels(s, 1 - side, -amount);
			break;
		case SCOPE_STEAL:
			change_channels(s, 1 - side, -amount);
			change_channels(s, side, amount);
			break;
		default:
			change_channels(s, side, amount);
			break;
		}
		break;
	default:
		break;
	}
	/* What it costs in ether channels: a wave nothing was poured into costs none. */
	if (c->channels && !(c->effect == EFF_WAVE && amount <= 0)) change_channels(s, side, -c->channels);
	for (int i = 0; i < pulls; i++) {
		if (x->blinds) {
			if (book_room(x, s, side) > 0) s->more[side]++;
			s->blind = 1;
		} else draw_cards(s, side, 1);
		/* Nothing protects from the second game's. */
		if (s->second) s->health[side] = imax(0, s->health[side] - 2);
		else hurt_hero(s, side, 3, -1);
	}
	/* The second game's spell traps: after a sorcery each lets its jammer
	 * out for its own hero and is gone. The third answers only the other
	 * hero's sorceries; the second's jammer is as strong as the sorcery is
	 * dear as printed, the third's as that and what was poured into it. */
	for (int owner = 0; owner < 2; owner++)
		for (int j = 0; j < 3; j++)
			for (int copy = set[owner][j]; copy > 0; copy--) {
				if (s->he[owner][HE_OST1 + j] <= 0 || army_size(s, owner) >= ARMY) continue;
				if (j == 2 && side == owner) continue;
				int kind = x->jammers[j], before = s->n;
				if (kind > 0) summon(x, s, owner, &x->pool[kind - 1]);
				if (s->n > before && j > 0) {
					Unit *u = &s->u[before];
					int strength = c->printed + (j == 2 ? power : 0);
					add_power(u, strength - x->pool[kind - 1].power);
					u->raw = (int16_t)(u->raw + strength - x->pool[kind - 1].toughness);
					settle_health(u);
					if (strength <= 0 && !(u->flags & F_DEAD)) kill_unit(s, before);
				}
				drop_charm(x, s, owner, HE_OST1 + j, 1);
			}
	banners(s);
	settle_illusions(s);
	return 1;
}

typedef struct { int32_t kind, a, b, c; } Move;
static inline int same_move(const Move *a, const Move *b) {
	return a->kind == b->kind && a->a == b->a && a->b == b->b && a->c == b->c;
}

/* Whether a spell of this card may be aimed at that creature. */
static int may_aim(const State *s, int side, const Card *c, int i) {
	const Unit *u = &s->u[i];
	if (u->flags & F_DEAD) return 0;
	/* A cripple is for a pale creature in the plane, and a pale blast finds
	 * one there too; nothing else reaches into it. */
	if (c->effect == EFF_ENCHANT && c->special == SP_CRIPPLE) {
		if (!(u->flags & F_PLANE) || !u->pale) return 0;
	} else if ((u->flags & (F_PLANE | F_GONE)) && c->effect != EFF_PALE_BLAST) return 0;
	if (c->effect == EFF_PALE_BLAST && !u->pale && !u->worn) return 0;
	if (c->effect == EFF_BANISH && (!u->pale || !may_shift(s, u) || worn_kind(s, i, EN_LOCK))) return 0;
	if (u->shielded || (u->flags & F_NO_AFFECT)) return 0;
	if (c->own && u->owner != side) return 0;
	if (((c->only & 1) && !(u->flags & F_WALL)) || ((c->only & 2) && !(u->flags & F_FLY)) || ((c->only & 4) && !(u->flags & F_ATTACKING))) return 0;
	/* What pays its caster while the creature lives is laid on a creature
	 * of the caster's own, whose fate it has in hand, where it has one. */
	if (c->effect == EFF_ENCHANT && (c->special == SP_STORM || c->special == SP_BREEZE) && u->owner != side && army_size(s, side) > 0) return 0;
	if (c->effect == EFF_UNSUMMON && u->cost > c->amount) return 0;
	if (c->effect == EFF_CONTROL && (u->owner == side || (u->flags & F_ATTACKING) || u->blocks >= 0)) return 0;
	if (c->effect == EFF_EXILE && (c->amount & 1) && card_cost((const Search *)s->rules, s, c) + printed_cost((const Search *)s->rules, u) > s->ether[side]) return 0;
	if (c->effect == EFF_CLONE && (u->kind <= 0 || army_size(s, side) >= ARMY)) return 0;
	if (c->effect == EFF_GIFT && army_size(s, 1 - side) >= ARMY) return 0;
	return 1;
}

/* Whether the spell, cast now at `target` (NO_TARGET for one aimed at
 * nothing), would find nothing to work on. The rules allow such a cast, but
 * it only spends the card, so it is never offered. */
static int idle_cast(const Search *x, const State *s, int side, const Card *c, int target) {
	int living = 0, mine_resting = 0, theirs_ready = 0;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->flags & (F_DEAD | F_GONE)) continue;
		living++;
		if (u->owner == side && (u->flags & F_RESTING) && !(u->flags & F_ATTACKING) && u->blocks < 0) mine_resting++;
		if (u->owner != side && !(u->flags & F_RESTING)) theirs_ready++;
	}
	switch (c->effect) {
	case EFF_DRAIN_MANA: return s->ether[1 - side] <= 0;
	case EFF_BURN_MANA: return target == NO_TARGET || s->ether[-target - 1] <= 0;
	case EFF_RALLY_ALL: return mine_resting == 0;
	case EFF_REST_ENEMIES: return theirs_ready == 0;
	case EFF_FULL_HEAL: return s->health[side] >= x->maximum[side];
	case EFF_HALF_HEAL: return s->health[side] >= x->maximum[side] / 2;
	case EFF_GRAVE_FIRE: return s->grave[0] + s->grave[1] <= 0;
	case EFF_FOREST: return c->amount <= s->forest[side];
	case EFF_CHARM:
		/* One laid on a hero that is named is laid on the other hero. */
		if (c->aim == AIM_HERO && -target - 1 == side) return 1;
		if (c->amount == HE_ASST && s->he[0][HE_ASST] + s->he[1][HE_ASST] > 0) return 1;
		return c->amount == HE_FOGG && s->he[0][HE_FOGG] + s->he[1][HE_FOGG] > 0;
	case EFF_MIND_BLAST: return cards_held(s, 0) <= 5 && cards_held(s, 1) <= 5;
	case EFF_DISCARD: return target == NO_TARGET || -target - 1 == side || cards_held(s, -target - 1) <= 0;
	case EFF_DISCARD_ALL:
	case EFF_DISCARD_CREATURES: return target == NO_TARGET || cards_held(s, -target - 1) <= 0;
	case EFF_AMNESIA:
	case EFF_BAN: return cards_held(s, 1 - side) <= 0;
	case EFF_CLEANSE: {
		/* Only where there is something the caster is better off without. */
		Dispel found[1];
		return dispel_choices(x, s, side, found, 1) == 0;
	}
	case EFF_FLUX:
	case EFF_VAPORIZE:
	case EFF_PALE_CALAMITY:
	case EFF_PALE_THEFT: {
		/* Each wants something of its own in play to work on. */
		int mine_plain = 0, away = 0, theirs_away = 0, bright = 0, theirs_pale = 0;
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if (u->flags & F_DEAD) continue;
			int gone = (u->flags & (F_PLANE | F_GONE)) != 0;
			mine_plain += u->owner == side && !u->pale;
			away += gone;
			theirs_away += gone && u->owner != side;
			bright += u->pale && !gone;
			theirs_pale += u->pale && u->owner != side;
		}
		if (c->effect == EFF_FLUX) return mine_plain == 0 || away == 0;
		if (c->effect == EFF_VAPORIZE) return bright == 0;
		if (c->effect == EFF_PALE_CALAMITY) return theirs_away == 0 || cards_held(s, 1 - side) <= 0;
		return theirs_pale == 0 || cards_held(s, 1 - side) <= 0;
	}
	/* The card itself is still counted among those held. */
	case EFF_REDRAW: return cards_held(s, side) <= 1;
	case EFF_ANNIHILATE:
	case EFF_BOUNCE_ALL:
	case EFF_FURY:
	case EFF_SYMBIOSIS:
	case EFF_HUNGER_ALL:
	case EFF_HUNGER_BOTH: return living == 0;
	default: return 0;
	}
}

/* ------------------------------------------------------ creature abilities */

static int army_size(const State *s, int side) {
	int count = 0;
	for (int i = 0; i < s->n; i++) count += s->u[i].owner == side && !(s->u[i].flags & F_DEAD);
	return count;
}

static int count_race(const State *s, int side, int race) {
	int count = 0;
	for (int i = 0; i < s->n; i++)
		count += s->u[i].owner == side && !(s->u[i].flags & (F_DEAD | F_GONE)) && s->u[i].race == race;
	return count;
}

/* Whether creature `i` may use its ability now on `target` (a creature's
 * place, -1 or -2 for a hero, NO_TARGET for nothing), and in `price` the
 * ether that costs. Everything the rules check before anything is paid. */
static int ability_fits(const State *s, int i, int target, int extra, int *price) {
	if (i < 0 || i >= s->n) return 0;
	const Unit *u = &s->u[i];
	const Search *x = (const Search *)s->rules;
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
	if (u->owner != side || !u->ability || (u->flags & (F_DEAD | F_GONE | F_PLANE))) return 0;
	if ((u->ability_traits & AT_ATTACK) && s->phase != 0) return 0;
	if ((u->ability_traits & AT_TAPS) && (!ready(u) || ((u->flags & F_ATTACKING || u->blocks >= 0) && u->ability != AB_DISENCHANT))) return 0;
	if ((u->ability_traits & AT_TAPPED) && (!(u->flags & F_RESTING) || (u->flags & F_SICK))) return 0;
	const Unit *t = target >= 0 && target < s->n && !(s->u[target].flags & (F_DEAD | F_GONE)) ? &s->u[target] : NULL;
	int hero = target == -1 || target == -2;
	/* Nothing names a creature behind a screen or in the plane, but spores do. */
	int reached = t && !t->shielded && !(t->flags & F_PLANE);
	*price = u->ability_cost;
	switch (u->ability) {
	case AB_DISPEL:
	case AB_DISENCHANT:
	case AB_ORC_RITE: {
		/* An enchantment that comes off: for its price, or for a channel. */
		int owed = ench_price(x, s, target, extra, u->ability == AB_DISENCHANT ? 2 : 1);
		if (owed < 0) return 0;
		if (u->ability != AB_ORC_RITE) *price = owed;
		else if (s->channels[side] < 1) return 0;
		break;
	}
	case AB_SPORES:
	case AB_SPORES_POWER:
		/* Only the stinging kind may name itself, and then it only dies. */
		if ((target == i && u->ability != AB_SPORES_POWER) || (!t && !hero)) return 0;
		break;
	case AB_STING:
		if (!hero && !reached) return 0;
		break;
	case AB_SHOOT:
		if (!reached || t->owner == side || !(t->flags & F_ATTACKING)) return 0;
		break;
	case AB_SLAY:
		if (!reached || target == i || !(t->flags & F_RESTING) || (t->flags & F_ATTACKING) || t->blocks >= 0) return 0;
		break;
	case AB_GAZE_TOUGHNESS:
	case AB_GAZE_POWER: {
		if (!reached) return 0;
		int beholders = count_race(s, side, u->ability_amount);
		if (u->ability == AB_GAZE_POWER && (t->flags & F_WALL)) return 0;
		if ((u->ability == AB_GAZE_POWER ? t->power : t->toughness) > beholders) return 0;
		break;
	}
	case AB_HUNT:
		if (!reached || t->power < 4) return 0;
		break;
	case AB_WALL_BREAK:
		if (!reached || !(t->flags & F_WALL)) return 0;
		break;
	case AB_SIPHON:
		if (s->second && s->ether[1 - side] <= 0) return 0;
		break;
	case AB_TAP_TARGET:
		if (!reached) return 0;
		break;
	case AB_TAP_WALLS:
		*price = 0;
		for (int k = 0; k < s->n; k++) {
			const Unit *w = &s->u[k];
			if (w->owner != side && !(w->flags & (F_DEAD | F_GONE | F_RESTING)) && (w->flags & F_WALL)) (*price)++;
		}
		break;
	case AB_TAP_RACE:
		if (!t || t->owner == side) return 0;
		if (s->second && !reached) return 0;
		*price = 0;
		for (int k = 0; k < s->n; k++) {
			const Unit *w = &s->u[k];
			if (w->owner == side || (w->flags & (F_DEAD | F_GONE | F_RESTING)) || w->race != t->race) continue;
			if (s->second && (w->flags & F_PLANE)) continue;
			(*price)++;
		}
		break;
	case AB_SACRIFICE:
		if (!reached || target == i || t->owner != side) return 0;
		break;
	case AB_BROOD: {
		int kind = u->ability_amount;
		if (kind <= 0 || kind > POOL || x->pool[kind - 1].cost < 0) return 0;
		if (army_size(s, side) >= ARMY || s->n >= MAX_UNITS) return 0;
		break;
	}
	case AB_GNAW:
		/* Any card of either graveyard, named by its place there. */
		if (!hero || extra < 0 || extra >= s->known[-target - 1]) return 0;
		break;
	case AB_PLAGUE:
		/* The ether poured in is the number of cards that go. */
		if (!hero || extra < 0) return 0;
		*price = extra;
		break;
	case AB_RECALL:
	case AB_RAISE_OWN: {
		if (target != -1 - side || extra < 0 || extra >= s->known[side]) return 0;
		int kind = s->graves[side][extra];
		if (kind <= 0) return 0;
		if (u->ability == AB_RECALL ? x->pool[kind - 1].race != u->ability_amount : x->pool[kind - 1].tribe != 1) return 0;
		break;
	}
	case AB_NECROMANCY: {
		if (!hero || extra < 0 || extra >= s->known[-target - 1]) return 0;
		int kind = s->graves[-target - 1][extra];
		if (kind <= 0 || x->pool[kind - 1].cost < 0 || x->pool[kind - 1].printed > u->ability_amount) return 0;
		/* The second game refuses when there is no room for what it raises. */
		if (s->second && army_size(s, side) >= ARMY) return 0;
		break;
	}
	case AB_POWER_X:
	case AB_HEALTH_X:
		if (extra < 1) return 0;
		*price = extra;
		break;
	case AB_PHANTASM:
	case AB_ROUSE:
	case AB_ILLUSION:
		if (u->spent) return 0;
		break;
	default:
		break;
	}
	return *price <= s->ether[side];
}

/* No block stands on a creature that has gone, or against one. */
static void drop_blocks(State *s) {
	for (int k = 0; k < s->n; k++) {
		Unit *b = &s->u[k];
		if (b->flags & (F_DEAD | F_GONE)) b->blocks = -1;
		else if (b->blocks >= 0 && ((s->u[b->blocks].flags & (F_DEAD | F_GONE)) || !(s->u[b->blocks].flags & F_ATTACKING)))
			b->blocks = -1;
	}
}

/* A creature destroyed outright: it may still regenerate unless told not to. */
static void destroy_unit(State *s, int index, int no_regeneration) {
	Unit *t = &s->u[index];
	if (t->flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE)) return;
	/* A lifeguard turns even that aside. */
	if (t->guards > 0) {
		spend_guard(s, (int)(t - s->u));
		return;
	}
	if (no_regeneration) t->flags |= F_NO_REGEN;
	/* It is hurt by all the health it has left, and a pain link passes that on. */
	int left = imax(1, t->toughness - t->damage);
	t->damage = (int16_t)(t->damage + left);
	t->flags |= F_HIT;
	for (int k = 0; k < t->linked; k++) pain_hero(s, t->owner, left);
	finish_unit(s, index);
}

/* The enchantments in play that the hero `side` would be better off
 * without, the best riddance first: what the other hero laid on itself or
 * its creatures to their good, and what lies on its own to their harm. */
static int offer_dispel(Dispel *out, int count, int limit, int holder, int what, int gain) {
	if (gain <= 0) return count;
	for (int i = 0; i < count; i++)
		if (out[i].holder == holder && out[i].what == what) return count;
	int at = count;
	while (at > 0 && out[at - 1].gain < gain) at--;
	if (at >= limit) return count;
	if (count < limit) count++;
	for (int i = count - 1; i > at; i--) out[i] = out[i - 1];
	out[at] = (Dispel){ holder, what, gain };
	return count;
}

static int dispel_choices(const Search *x, const State *s, int side, Dispel *out, int limit) {
	int count = 0;
	for (int holder = 0; holder < 2; holder++) {
		for (int k = 0; k < HE_COUNT; k++) {
			if (s->he[holder][k] <= 0 || x->charm[k].fixed) continue;
			int worth = x->charm[k].each + (s->he[holder][k] == 1 ? x->charm[k].kind : 0);
			/* What a hero laid on itself is to its good unless it is worth
			 * less than nothing; what the other laid on it never is. */
			int own = k < HE_WETX || k >= HE_STSK, gain;
			if (holder != side) gain = own ? imax(worth, 500) : 0;
			else gain = own ? -worth : imax(-worth, 500);
			count = offer_dispel(out, count, limit, -1 - holder, k, gain);
		}
		if (holder != side && s->forest[holder] >= 0) count = offer_dispel(out, count, limit, -1 - holder, HE_FOREST, imax(s->forest_worth[holder], 500));
		if (s->banner[holder] > 0) {
			/* A banner gone is worth what it gives the other army beyond the caster's. */
			int gain = 0, copies = s->banner[0] + s->banner[1];
			for (int i = 0; i < s->n; i++) {
				const Unit *u = &s->u[i];
				if (u->flags & F_DEAD) continue;
				gain += (u->owner == side ? -1 : 1) * u->kin * (x->power_worth + x->tough_worth) / copies;
			}
			count = offer_dispel(out, count, limit, -1 - holder, HE_BANNER, gain);
		}
	}
	for (int r = 0; r < s->enchs; r++) {
		const Ench *e = &s->ench[r];
		const Unit *u = &s->u[e->unit];
		if (e->fixed || (u->flags & (F_DEAD | F_GONE | F_PLANE)) || u->shielded) continue;
		int mine = u->owner == side, gain = mine ? -e->ready : e->ready;
		if (mine && (e->kind == EN_HOLD || e->kind == EN_TWIST || e->kind == EN_OVERLOAD || e->kind == EN_LINK)) gain = imax(gain, u->ready_worth / 2);
		if (e->kind == EN_CONTROL) gain = !mine && u->home - 1 == side ? 2 * u->ready_worth : 0;
		if (e->kind == EN_ALPHA || e->kind == EN_QUICK) gain = mine ? 0 : u->ready_worth;
		count = offer_dispel(out, count, limit, e->unit, e->code, gain);
	}
	return count;
}

/* The creature uses its ability. 0 when the rules refuse it. */
static int use_ability(State *s, int i, int target, int extra) {
	int price = 0;
	if (!ability_fits(s, i, target, extra, &price)) return 0;
	const Search *x = (const Search *)s->rules;
	Unit *u = &s->u[i];
	int side = u->owner, amount = u->ability_amount;
	if (u->ability_traits & AT_TAPS) u->flags |= F_RESTING;
	pay(s, side, price);
	switch (u->ability) {
	case AB_ORC_RITE:
		/* The channel is the price of the rite: no stasis spares it. */
		s->channels[side] = (int8_t)imax(0, s->channels[side] - 1);
		dispel(x, s, target, extra, 0);
		break;
	case AB_DISPEL:
		dispel(x, s, target, extra, 0);
		break;
	case AB_DISENCHANT:
		/* It leaves the fight it was in, and whoever blocked it stands free. */
		if (u->flags & F_ATTACKING) {
			u->flags &= ~(uint32_t)F_ATTACKING;
			for (int k = 0; k < s->n; k++)
				if (s->u[k].blocks == i) s->u[k].blocks = -1;
		}
		u->blocks = -1;
		dispel(x, s, target, extra, 1);
		break;
	case AB_SPORES:
	case AB_SPORES_POWER:
		/* Its spores hurt what it names, and it dies of them. */
		if (target != i) spell_damage(s, target, u->ability == AB_SPORES_POWER ? imax(0, u->power) : 1);
		kill_unit(s, i);
		break;
	case AB_STING:
	case AB_SHOOT:
		spell_damage(s, target, amount);
		break;
	case AB_SLAY:
	case AB_GAZE_TOUGHNESS:
	case AB_GAZE_POWER:
	case AB_HUNT:
		destroy_unit(s, target, 0);
		break;
	case AB_WALL_BREAK:
		destroy_unit(s, target, 1);
		break;
	case AB_SIPHON: {
		int moved = imin(amount, imax(0, s->ether[1 - side]));
		s->ether[1 - side] -= moved;
		gain_ether(s, side, moved);
		break;
	}
	case AB_BREATH_FLYING:
	case AB_BREATH_GROUND: {
		int n = s->n;
		for (int k = 0; k < n; k++) {
			const Unit *v = &s->u[k];
			if (v->owner == side || (v->flags & (F_DEAD | F_GONE))) continue;
			if (((v->flags & F_FLY) != 0) != (u->ability == AB_BREATH_FLYING)) continue;
			spell_damage(s, k, amount);
		}
		break;
	}
	case AB_BAT_DRAIN: {
		/* A point for every bat its hero has, and that hero heals by what lands. */
		int bats = count_race(s, side, amount), before = s->health[1 - side];
		hurt_hero(s, 1 - side, bats, -1);
		int dealt = before - s->health[1 - side];
		if (dealt > 0) s->health[side] += s->second ? imin(dealt, before) : bats;
		break;
	}
	case AB_RALLY:
		for (int k = 0; k < s->n; k++) {
			Unit *v = &s->u[k];
			if (v->owner != side || (v->flags & (F_DEAD | F_GONE)) || v->race != amount || v->ability == AB_RALLY) continue;
			v->flags &= ~(uint32_t)F_RESTING;
		}
		break;
	case AB_TAP_TARGET:
		s->u[target].flags |= F_RESTING;
		break;
	case AB_TAP_WALLS:
		for (int k = 0; k < s->n; k++) {
			Unit *v = &s->u[k];
			if (v->owner != side && !(v->flags & (F_DEAD | F_GONE)) && (v->flags & F_WALL)) v->flags |= F_RESTING;
		}
		break;
	case AB_TAP_RACE: {
		int race = s->u[target].race;
		for (int k = 0; k < s->n; k++) {
			Unit *v = &s->u[k];
			if (v->owner == side || (v->flags & (F_DEAD | F_GONE)) || v->race != race) continue;
			if (s->second && (v->flags & F_PLANE)) continue;
			v->flags |= F_RESTING;
		}
		break;
	}
	case AB_ETHER:
		gain_ether(s, side, 1);
		break;
	case AB_DRAW:
		draw_cards(s, side, 1);
		break;
	case AB_SACRIFICE:
		kill_unit(s, target);
		if (!(u->flags & (F_DEAD | F_GONE))) u->flags &= ~(uint32_t)F_RESTING;
		break;
	case AB_BROOD:
		summon(x, s, side, &x->pool[amount - 1]);
		break;
	case AB_GNAW:
		unbury(s, -target - 1, extra);
		break;
	case AB_PLAGUE: {
		/* The oldest cards go first: those too old to be listed, then the
		 * listed ones from their old end. Ether poured in past the last card
		 * is lost. */
		int whose = -target - 1;
		for (int k = imin(extra, s->grave[whose]); k > 0; k--) {
			if (s->grave[whose] > s->known[whose]) s->grave[whose]--;
			else unbury(s, whose, 0);
		}
		break;
	}
	case AB_RECALL:
		take_back(s, side, unbury(s, side, extra));
		break;
	case AB_RAISE_OWN:
	case AB_NECROMANCY: {
		/* The card leaves its graveyard even when a full army leaves the
		 * creature nowhere to go. */
		int kind = unbury(s, -target - 1, extra);
		if (kind > 0) summon(x, s, side, &x->pool[kind - 1]);
		break;
	}
	case AB_DISTORTION:
		/* The wall goes, not to any graveyard, every creature sent or set to
		 * block comes home, and nothing more is sent while its mark lasts. */
		for (int k = 0; k < s->n; k++) {
			s->u[k].flags &= ~(uint32_t)F_ATTACKING;
			s->u[k].blocks = -1;
		}
		s->he[side][HE_WLDT]++;
		remove_unit(s, i, 0);
		break;
	case AB_POWER_X:
	case AB_PHANTASM: {
		int gain = u->ability == AB_PHANTASM ? 2 : extra;
		add_power(u, gain);
		if (u->passing < 100) u->passing++;
		u->passing_power = (int16_t)(u->passing_power + gain);
		if (u->ability == AB_PHANTASM) u->spent = 1;
		break;
	}
	case AB_HEALTH_X:
		u->raw = (int16_t)(u->raw + extra);
		settle_health(u);
		if (u->passing < 100) u->passing++;
		u->passing_health = (int16_t)(u->passing_health + extra);
		break;
	case AB_ROUSE:
		u->spent = 1;
		for (int k = 0; k < s->n; k++)
			if (s->u[k].tribe == 1 && !(s->u[k].flags & (F_DEAD | F_GONE))) s->u[k].flags &= ~(uint32_t)F_RESTING;
		break;
	case AB_ILLUSION: {
		/* For as long as what it gives itself lasts, its health is one more
		 * than the cards in its hero's graveyard. */
		int health = s->grave[side] + 1 - (u->kind > 0 ? x->pool[u->kind - 1].toughness : u->toughness);
		u->spent = 1;
		u->raw = (int16_t)(u->raw + health);
		settle_health(u);
		if (u->passing < 100) u->passing++;
		u->passing_health = (int16_t)(u->passing_health + health);
		/* The second game lets it die of that at once. */
		if (s->second && u->damage >= u->toughness) perish_unit(s, i);
		break;
	}
	case AB_SPIRIT_FLIGHT:
		s->flight[side] = 1;
		for (int k = 0; k < s->n; k++)
			if (s->u[k].tribe == 1 && !(s->u[k].flags & (F_DEAD | F_GONE))) s->u[k].flags |= F_FLY;
		break;
	default:
		break;
	}
	drop_blocks(s);
	return 1;
}

static int add_ability(Move *out, int count, int unit, int target, int extra) {
	if (count >= MAX_MOVES - 2) return count;
	out[count].kind = 7;
	out[count].a = unit;
	out[count].b = target;
	out[count].c = extra;
	return count + 1;
}

/* Whether anything can still be done with the cards of this hero's
 * graveyard, so that taking one out of it is worth a thought: a creature
 * that climbs back out by itself, or someone who calls the dead back. */
static int grave_matters(const Search *x, const State *s, int side) {
	for (int i = 0; i < s->known[side]; i++) {
		int kind = s->graves[side][i];
		if (kind > 0 && x->pool[kind - 1].rises) return 1;
	}
	if (s->he[side][HE_RPST] > 0) return 1;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->flags & (F_DEAD | F_GONE)) continue;
		if (u->ability == AB_NECROMANCY) return 1;
		if (u->owner == side && (u->ability == AB_RECALL || u->ability == AB_RAISE_OWN)) return 1;
	}
	return 0;
}

/* The card of a listed graveyard a creature's ability would best be used
 * on: the dearest that `user` may name, the oldest of those alike; -1 when
 * there is none. */
static int grave_choice(const State *s, int user, int whose) {
	const Search *x = (const Search *)s->rules;
	int best = -1, price = 0;
	for (int i = 0; i < s->known[whose]; i++) {
		int kind = s->graves[whose][i];
		if (!ability_fits(s, user, -1 - whose, i, &price)) continue;
		int worth = kind > 0 ? x->pool[kind - 1].ready_worth + (x->pool[kind - 1].rises ? 100000 : 0) : 0;
		if (best < 0) best = i;
		else {
			int held = s->graves[whose][best];
			if (worth > (held > 0 ? x->pool[held - 1].ready_worth + (x->pool[held - 1].rises ? 100000 : 0) : 0)) best = i;
		}
	}
	return best;
}

/* ---------------------------------------------------------- hero abilities */

/* Whether the hero to move may use the ability enchantment `k` gives it on
 * `target`: a copy not yet used this turn, the ether, and something the
 * ability can work on. */
static int best_buried(const Search *x, const State *s, int whose);

/* What an enchantment that outlasts only the turn gives a creature: power,
 * health and flags, until a turn that is not its own hero's has ended. */
static void bless_unit(const Search *x, State *s, int target, int power, int health, uint32_t flags) {
	Unit *t = &s->u[target];
	Unit was = *t;
	add_power(t, power);
	t->raw = (int16_t)(t->raw + health);
	settle_health(t);
	t->flags |= flags;
	int gain = (power * ((t->flags & F_NO_ATTACK) ? x->guard_worth : x->power_worth) + health * x->tough_worth) / 2;
	t->ready_worth += gain;
	t->resting_worth += gain;
	wears(t, &was, 1, flags);
	note_ench(s, target, &was, t->owner, EN_PLAIN, x->charm[HE_CMBN].code, x->charm[HE_CMBN].fixed ? -1 - x->charm[HE_CMBN].price : x->charm[HE_CMBN].price, 1, 0, 0);
	if (t->brief < 100) t->brief++;
	t->brief_power = (int16_t)(t->brief_power + (t->power - t->under) - (was.power - was.under));
	t->brief_health = (int16_t)(t->brief_health + t->toughness - was.toughness);
	t->brief_flags |= flags & ~was.flags;
	t->brief_ready += t->ready_worth - was.ready_worth;
	t->brief_resting += t->resting_worth - was.resting_worth;
	if (t->damage >= t->toughness) perish_unit(s, target);
}

/* The creature of a hero's own that is worth least and may be given up. */
static int least_unit(const State *s, int side) {
	int best = -1;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->owner != side || (u->flags & (F_DEAD | F_GONE | F_PLANE)) || u->shielded) continue;
		if (best < 0 || u->ready_worth < s->u[best].ready_worth) best = i;
	}
	return best;
}

static int hero_ability_fits(const Search *x, const State *s, int k, int target, int extra) {
	if (k < 0 || k >= HERO_ABILITIES) return 0;
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
	if (s->he[side][k] - s->used[side][k] <= 0 || s->ether[side] < x->charm[k].cost) return 0;
	const Unit *t = target >= 0 && target < s->n && !(s->u[target].flags & (F_DEAD | F_GONE)) ? &s->u[target] : NULL;
	/* One of the hero's own to give up, which nothing shields; and the
	 * second thing an ability names, where that is a creature in play. */
	int gives = t && t->owner == side && !(t->flags & F_PLANE) && !t->shielded;
	const Unit *v = extra >= 0 && extra < s->n && !(s->u[extra].flags & (F_DEAD | F_GONE)) ? &s->u[extra] : NULL;
	if (v && ((v->flags & F_PLANE) || v->shielded)) v = NULL;
	switch (k) {
	case HE_CMBN:
		if (!gives || !v) return 0;
		break;
	case HE_BROT:
		if (!gives || extra == target || (extra != -1 && extra != -2 && !v)) return 0;
		break;
	case HE_SPLK:
	case HE_SACR:
		if (!gives) return 0;
		break;
	case HE_RBRT:
	case HE_SCBR:
		/* A creature card of its own graveyard that the engine knows, and room for it. */
		if (army_size(s, side) >= ARMY || s->n >= MAX_UNITS) return 0;
		if (extra < 0 || extra >= s->known[side] || s->graves[side][extra] <= 0) return 0;
		if (k == HE_SCBR && s->ether[side] < x->pool[s->graves[side][extra] - 1].printed) return 0;
		break;
	case HE_OEXC: {
		/* A creature in the Colourless Plane for one in play. */
		if (target < 0 || target >= s->n || !v) return 0;
		const Unit *p = &s->u[target];
		if ((p->flags & F_DEAD) || !(p->flags & (F_PLANE | F_GONE)) || p->shielded) return 0;
		if (s->he[0][HE_PLSL] + s->he[1][HE_PLSL] > 0) return 0;
		break;
	}
	case HE_FRBL:
		if (target != -1 && target != -2 && (!t || (t->flags & F_PLANE))) return 0;
		break;
	case HE_ENRG:
		if (!t || (t->flags & F_PLANE) || !(t->flags & F_RESTING) || (t->flags & F_ATTACKING) || t->blocks >= 0) return 0;
		break;
	case HE_RPST:
		if (s->grave[side] <= 0) return 0;
		break;
	default:
		break;
	}
	return 1;
}

static int use_hero_ability(const Search *x, State *s, int k, int target, int extra) {
	if (!hero_ability_fits(x, s, k, target, extra)) return 0;
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker, amount = x->charm[k].amount;
	/* A sacrifice needs its ether but does not spend it; a second birth
	 * costs what the creature costs as printed. */
	int price = k == HE_SACR ? 0 : (k == HE_SCBR ? x->pool[s->graves[side][extra] - 1].printed : x->charm[k].cost);
	s->used[side][k]++;
	/* A rebirth costs its hero two points of health as well. */
	if (k == HE_RBRT) hurt_hero(s, side, 2, -1);
	pay(s, side, price);
	switch (k) {
	case HE_CMBN: {
		/* The creature given up lends another its strength for the turn. */
		int power = s->u[target].power, health = s->u[target].toughness;
		kill_unit(s, target);
		if (extra != target && !(s->u[extra].flags & (F_DEAD | F_GONE))) bless_unit(x, s, extra, power, health, F_TRAMPLE);
		break;
	}
	case HE_BROT: {
		/* Its power burns whatever was named. */
		int power = imax(0, s->u[target].power);
		kill_unit(s, target);
		spell_damage(s, extra, power);
		break;
	}
	case HE_SPLK:
		kill_unit(s, target);
		change_channels(s, side, amount);
		break;
	case HE_SACR: {
		/* The first game turns it into ether, its power and health less
		 * one; the second deals its hero two cards. */
		int value = s->u[target].power + s->u[target].toughness;
		kill_unit(s, target);
		if (s->second) deal(x, s, side, 2);
		else s->ether[side] = imax(0, s->ether[side] + value - 1);
		break;
	}
	case HE_RBRT:
	case HE_SCBR: {
		int kind = unbury(s, side, extra);
		summon(x, s, side, &x->pool[kind - 1]);
		break;
	}
	case HE_OEXC:
		manifest(x, s, target);
		banish(x, s, extra);
		break;
	case HE_LSHE:
		s->health[side] += amount;
		break;
	case HE_FRBL:
		spell_damage(s, target, amount);
		break;
	case HE_RNST: {
		int n = s->n;
		for (int i = 0; i < n; i++)
			if (s->u[i].owner != side) spell_damage(s, i, amount);
		break;
	}
	case HE_ENRG:
		s->u[target].flags &= ~(uint32_t)F_RESTING;
		break;
	case HE_RPST: {
		/* The creature card named comes back out of the graveyard - the
		 * dearest where none is - and the other hero takes one. */
		int best = -1;
		if (extra >= 0 && extra < s->known[side] && s->graves[side][extra] > 0 && s->graves[side][extra] <= POOL) best = extra;
		for (int i = 0; best < 0 && i < s->known[side]; i++) {
			int kind = s->graves[side][i];
			if (kind <= 0 || kind > POOL) continue;
			int dearest = i;
			for (int j = i + 1; j < s->known[side]; j++) {
				int other = s->graves[side][j];
				if (other > 0 && other <= POOL && x->pool[other - 1].cost > x->pool[s->graves[side][dearest] - 1].cost) dearest = j;
			}
			best = dearest;
		}
		take_back(s, side, unbury(s, side, best));
		hurt_hero(s, 1 - side, 1, -1);
		break;
	}
	default:
		break;
	}
	drop_blocks(s);
	return 1;
}

/* Whether the card at a place of a graveyard is a creature of a kind that
 * no earlier place holds. */
static int fresh_kind(const State *s, int whose, int place) {
	int kind = s->graves[whose][place];
	if (kind <= 0) return 0;
	for (int p = 0; p < place; p++)
		if (s->graves[whose][p] == kind) return 0;
	return 1;
}

static int add_hero_ability(Move *out, int count, int k, int target, int extra) {
	if (count >= MAX_MOVES - 2) return count;
	out[count].kind = 8;
	out[count].a = k;
	out[count].b = target;
	out[count].c = extra;
	return count + 1;
}

/* What the hero to move may do through its own enchantments. */
/* The hero that laid an enchantment standing on a hero: its own, but for
 * the ones that are laid on the other. */
static inline int charm_caster(int k, int holder) {
	return k < HE_WETX || k >= HE_STSK ? holder : 1 - holder;
}

/* The first enchantment of that name on a creature that the hero `caster`
 * laid and that comes off: its place among them, or -1. */
static int own_ench(const State *s, int holder, int what, int caster) {
	if (holder < 0 || holder >= s->n) return -1;
	const Unit *u = &s->u[holder];
	if ((u->flags & (F_DEAD | F_GONE | F_PLANE)) || u->shielded) return -1;
	for (int r = 0; r < s->enchs; r++) {
		const Ench *e = &s->ench[r];
		if (e->unit != holder || e->code != what || e->kind == EN_WATER || e->fixed || e->caster != caster) continue;
		if (e->kind == EN_CONTROL && u->home > 0 && u->home - 1 != u->owner && army_size(s, u->home - 1) >= ARMY) continue;
		return r;
	}
	return -1;
}

/* Whether the pale creature `i` may use the ability `key` on `target`,
 * naming `extra` with it; and the ether that costs. */
static int pale_fits(const Search *x, const State *s, int i, int key, int target, int extra, int *price) {
	if (!s->second || i < 0 || i >= s->n || key <= PA_NONE || key > PA_DEVOUR) return 0;
	const Unit *u = &s->u[i];
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
	if (u->owner != side || !u->pale || (u->flags & F_DEAD) || muted(s, i)) return 0;
	int away = (u->flags & (F_PLANE | F_GONE)) != 0;
	int sealed = s->he[0][HE_PLSL] + s->he[1][HE_PLSL] > 0;
	int busy = (u->flags & (F_RESTING | F_SICK | F_ATTACKING)) || u->blocks >= 0;
	/* What it rests for, and may do once a round. */
	int rests = key == PA_DISSIPATE || key >= PA_CHANNEL;
	if (key >= PA_SINISTER && key <= PA_CRYPTIC) {
		if ((u->pale_bits & 15) != key) return 0;
	} else if (key == PA_COURTESY) {
		if (!((u->pale_bits >> 4) & 1)) return 0;
	} else if (key != PA_DISSIPATE && ((u->pale_bits >> 5) & 15) != key) return 0;
	if (rests && (busy || (u->pale_used & (key == PA_DISSIPATE ? 1 : 2)))) return 0;
	*price = key == PA_COURTESY ? 1 : (key >= PA_CHANNEL ? (u->pale_bits >> 9) & 15 : 0);
	if (*price > s->ether[side]) return 0;
	const Unit *t = target >= 0 && target < s->n && !(s->u[target].flags & F_DEAD) ? &s->u[target] : NULL;
	int hero = target == -1 || target == -2;
	switch (key) {
	case PA_DISSIPATE:
		if (away || sealed || worn_kind(s, i, EN_LOCK)) return 0;
		break;
	case PA_SINISTER:
		if (!away || !hero || extra < 0 || extra >= s->known[-target - 1]) return 0;
		break;
	case PA_CRUEL:
		if ((away && sealed) || !t || target == i || t->owner != side || t->shielded) return 0;
		break;
	case PA_FIENDISH:
		if (!away || sealed || s->channels[side] < 1) return 0;
		break;
	case PA_CRYPTIC:
		if (!away || cards_held(s, side) <= 0) return 0;
		break;
	case PA_MYSTIC:
		/* One its own hero laid, and that comes off. */
		if (!away) return 0;
		if (hero) {
			if (ench_price(x, s, target, extra, 1) < 0) return 0;
			if (extra < HE_COUNT ? charm_caster(extra, -target - 1) != side : -target - 1 != side) return 0;
		} else if (own_ench(s, target, extra, side) < 0) return 0;
		break;
	case PA_COURTESY:
		if (busy) return 0;
		break;
	case PA_CHANNEL:
		if (s->channels[side] < 1) return 0;
		break;
	case PA_PLEA:
		if (s->ether[1 - side] <= 0 || (!hero && (!t || t->shielded || (t->flags & (F_PLANE | F_GONE))))) return 0;
		break;
	case PA_ABSORB:
		if (ench_price(x, s, target, extra, 1) < 0) return 0;
		break;
	case PA_WEAVE:
	case PA_TRANSPOSE: {
		/* What the enchantment's card costs is paid on top. */
		int owed = ench_price(x, s, target, extra, key == PA_WEAVE ? 3 : 1);
		if (owed < 0) return 0;
		*price += owed;
		break;
	}
	case PA_DEVOUR: {
		if (!t || target == i || t->shielded || (t->flags & (F_PLANE | F_GONE))) return 0;
		int measure = (u->pale_bits >> 13) & 3;
		if (measure == 1 && (t->flags & F_WALL)) return 0;
		if (measure != 2 && t->power >= u->power) return 0;
		if (measure != 1 && t->toughness >= u->toughness) return 0;
		break;
	}
	default:
		break;
	}
	return *price <= s->ether[side];
}

/* The pale creature uses it: `packed` is the ability and, in its low half,
 * what it names beside its target. 0 when the rules refuse. */
static int use_pale(const Search *x, State *s, int i, int target, int packed) {
	int key = packed >> 16, extra = packed & 0xffff, price = 0;
	if (packed < 0 || !pale_fits(x, s, i, key, target, extra, &price)) return 0;
	Unit *u = &s->u[i];
	int side = u->owner;
	if (key == PA_DISSIPATE || key >= PA_CHANNEL) {
		u->pale_used |= key == PA_DISSIPATE ? 1 : 2;
		u->flags |= F_RESTING;
	}
	pay(s, side, price);
	switch (key) {
	case PA_DISSIPATE:
		banish(x, s, i);
		if (!(u->flags & F_DEAD) && u->damage >= u->toughness) kill_unit(s, i);
		break;
	case PA_SINISTER:
		/* The card is gone even where a seal keeps the creature pale. */
		manifest(x, s, i);
		unbury(s, -target - 1, extra);
		break;
	case PA_CRUEL:
		kill_unit(s, target);
		manifest(x, s, i);
		break;
	case PA_FIENDISH:
		manifest(x, s, i);
		change_channels(s, side, -1);
		break;
	case PA_MYSTIC:
		if (target < 0) dispel(x, s, target, extra, 0);
		else {
			int r = own_ench(s, target, extra, side);
			if (r >= 0) unwear(s, r);
		}
		manifest(x, s, i);
		break;
	case PA_CRYPTIC:
		manifest(x, s, i);
		discard_cards(s, side, 1, 0, side);
		break;
	case PA_COURTESY:
		kill_unit(s, i);
		deal(x, s, side, 1);
		break;
	case PA_CHANNEL:
		/* Under a stasis nothing of it happens. */
		if (!stasis(s)) {
			s->ether[side] += 3;
			s->channels[side]--;
		}
		break;
	case PA_PLEA: {
		int drained = s->ether[1 - side];
		s->ether[1 - side] = 0;
		if (target < 0) hurt_hero(s, -target - 1, drained, -1);
		else spell_damage(s, target, drained);
		break;
	}
	case PA_HEAL:
		s->health[side] += army_size(s, side);
		break;
	case PA_ABSORB: {
		int worth = ench_price(x, s, target, extra, 1);
		dispel(x, s, target, extra, 0);
		gain_ether(s, side, worth);
		break;
	}
	case PA_WEAVE:
		s->more[side]++;
		break;
	case PA_TRANSPOSE:
		dispel(x, s, target, extra, 0);
		s->more[side]++;
		break;
	case PA_DEVOUR: {
		Unit *t = &s->u[target];
		int left = t->toughness - t->damage, strength = t->power, measure = (u->pale_bits >> 13) & 3;
		destroy_unit(s, target, 0);
		if (!(t->flags & F_DEAD) || (u->flags & F_DEAD)) break;
		if (measure == 3) change_channels(s, side, 1);
		else {
			/* It grows by a point of each for good, and its hero heals. */
			Unit was = *u;
			add_power(u, 1);
			u->raw++;
			settle_health(u);
			u->ready_worth += x->power_worth + x->tough_worth;
			u->resting_worth += x->power_worth + x->tough_worth;
			wears(u, &was, 1, 0);
			note_ench(s, i, &was, side, EN_PLAIN, 0, -1, 0, 0, 0);
			s->health[side] += imax(0, measure == 1 ? left : strength);
		}
		break;
	}
	default:
		break;
	}
	drop_blocks(s);
	return 1;
}

static int add_pale(const Search *x, const State *s, Move *out, int count, int i, int key, int target, int extra) {
	int price = 0;
	if (count >= MAX_MOVES - 2 || !pale_fits(x, s, i, key, target, extra, &price)) return count;
	out[count] = (Move){ 11, i, target, (key << 16) | extra };
	return count + 1;
}

/* What the pale creatures of the hero to move may do, the likely ones only. */
static int pale_moves(const Search *x, const State *s, Move *out, int count, int light) {
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker, fades = 0;
	for (int i = 0; i < s->n && count < MAX_MOVES - 4; i++) {
		const Unit *u = &s->u[i];
		if (u->owner != side || !u->pale || (u->flags & F_DEAD)) continue;
		int away = (u->flags & (F_PLANE | F_GONE)) != 0;
		switch (away ? u->pale_bits & 15 : PA_NONE) {
		case PA_SINISTER: {
			/* The dearest card of the other graveyard, or failing that any of its own. */
			int whose = s->known[1 - side] > 0 ? 1 - side : side;
			int place = best_buried(x, s, whose);
			if (place < 0) place = s->known[whose] - 1;
			if (place >= 0) count = add_pale(x, s, out, count, i, PA_SINISTER, -1 - whose, place);
			break;
		}
		case PA_CRUEL: {
			/* For the creature of its army worth least, if that is worth less. */
			int given = -1;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (j == i || t->owner != side || (t->flags & F_DEAD) || t->shielded) continue;
				if (given < 0 || t->ready_worth < s->u[given].ready_worth) given = j;
			}
			if (given >= 0 && s->u[given].ready_worth < u->ready_worth) count = add_pale(x, s, out, count, i, PA_CRUEL, given, 0);
			break;
		}
		case PA_FIENDISH:
			count = add_pale(x, s, out, count, i, PA_FIENDISH, NO_TARGET, 0);
			break;
		case PA_CRYPTIC:
			count = add_pale(x, s, out, count, i, PA_CRYPTIC, NO_TARGET, 0);
			break;
		case PA_MYSTIC: {
			/* The enchantment of its hero's that is least loss. */
			int holder = 0, what = -1, least = 0;
			for (int g = 0; g < 2; g++)
				for (int k = 0; k < HE_COUNT; k++) {
					if (s->he[g][k] <= 0 || x->charm[k].fixed || charm_caster(k, g) != side) continue;
					int loss = g == side ? x->charm[k].each + (s->he[g][k] == 1 ? x->charm[k].kind : 0) : 500;
					if (what < 0 || loss < least) {
						holder = -1 - g;
						what = k;
						least = loss;
					}
				}
			for (int r = 0; r < s->enchs; r++) {
				const Ench *e = &s->ench[r];
				if (e->caster != side || own_ench(s, e->unit, e->code, side) != r) continue;
				int loss = s->u[e->unit].owner == side ? e->ready : -e->ready;
				if (what < 0 || loss < least) {
					holder = e->unit;
					what = e->code;
					least = loss;
				}
			}
			if (what >= 0) count = add_pale(x, s, out, count, i, PA_MYSTIC, holder, what);
			break;
		}
		default:
			break;
		}
		if (((u->pale_bits >> 4) & 1) && !light) count = add_pale(x, s, out, count, i, PA_COURTESY, NO_TARGET, 0);
		switch ((u->pale_bits >> 5) & 15) {
		case PA_CHANNEL:
		case PA_HEAL:
			count = add_pale(x, s, out, count, i, (u->pale_bits >> 5) & 15, NO_TARGET, 0);
			break;
		case PA_PLEA: {
			/* At the other hero, or at the dearest creature it would kill. */
			int prey = -1;
			count = add_pale(x, s, out, count, i, PA_PLEA, -2 + side, 0);
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & (F_DEAD | F_GONE | F_PLANE | F_NO_AFFECT)) || t->shielded) continue;
				if (t->toughness - t->damage > s->ether[1 - side] - 3 * t->barriers) continue;
				if (prey < 0 || t->ready_worth > s->u[prey].ready_worth) prey = j;
			}
			if (prey >= 0 && !light) count = add_pale(x, s, out, count, i, PA_PLEA, prey, 0);
			break;
		}
		case PA_ABSORB:
		case PA_TRANSPOSE: {
			Dispel found[1];
			if (dispel_choices(x, s, side, found, 1) > 0) count = add_pale(x, s, out, count, i, (u->pale_bits >> 5) & 15, found[0].holder, found[0].what);
			break;
		}
		case PA_WEAVE: {
			/* A second copy of the best thing its hero has laid on itself. */
			int what = -1;
			for (int k = 0; k < HE_COUNT && !light; k++) {
				if (s->he[side][k] <= 0 || x->charm[k].fixed == 1 || charm_caster(k, side) != side) continue;
				if (what < 0 || x->charm[k].each + x->charm[k].kind > x->charm[what].each + x->charm[what].kind) what = k;
			}
			if (what >= 0 && x->charm[what].each + x->charm[what].kind > 0) count = add_pale(x, s, out, count, i, PA_WEAVE, -1 - side, what);
			break;
		}
		case PA_DEVOUR: {
			/* The dearest creatures of the other army it can eat. */
			int eaten[2] = { -1, -1 }, price = 0;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & F_NO_AFFECT) || !pale_fits(x, s, i, PA_DEVOUR, j, 0, &price)) continue;
				if (eaten[0] < 0 || t->ready_worth > s->u[eaten[0]].ready_worth) {
					eaten[1] = eaten[0];
					eaten[0] = j;
				} else if (eaten[1] < 0 || t->ready_worth > s->u[eaten[1]].ready_worth) eaten[1] = j;
			}
			for (int k = 0; k < (light ? 1 : 2); k++)
				if (eaten[k] >= 0) count = add_pale(x, s, out, count, i, PA_DEVOUR, eaten[k], 0);
			break;
		}
		default:
			break;
		}
		/* Out of harm's way, where it is wounded or about to be struck. */
		if (!light && !away && fades < 2 && (u->damage > 0 || s->phase != 0)) {
			int before = count;
			count = add_pale(x, s, out, count, i, PA_DISSIPATE, NO_TARGET, 0);
			fades += count > before;
		}
	}
	return count;
}

static int hero_ability_moves(const Search *x, const State *s, Move *out, int count, int light) {
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
	for (int k = 0; k < HERO_ABILITIES; k++) {
		if (s->he[side][k] - s->used[side][k] <= 0 || s->ether[side] < x->charm[k].cost) continue;
		switch (k) {
		case HE_FRBL:
			count = add_hero_ability(out, count, k, -1 - (1 - side), 0);
			if (light) break;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & F_NO_AFFECT)) continue;
				if (hero_ability_fits(x, s, k, j, 0)) count = add_hero_ability(out, count, k, j, 0);
			}
			break;
		case HE_CMBN: {
			/* The creature worth least, for any other of the hero's own. */
			int given = least_unit(s, side);
			for (int j = 0; given >= 0 && j < s->n; j++) {
				if (j == given || s->u[j].owner != side || !hero_ability_fits(x, s, k, given, j)) continue;
				count = add_hero_ability(out, count, k, given, j);
				if (light) break;
			}
			break;
		}
		case HE_BROT: {
			/* The strongest of the hero's own, at the other hero or at a
			 * creature that would kill. */
			int given = -1;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner != side || t->power <= 0 || (t->flags & (F_DEAD | F_GONE | F_PLANE)) || t->shielded) continue;
				if (given < 0 || t->power > s->u[given].power) given = j;
			}
			if (given < 0) break;
			count = add_hero_ability(out, count, k, given, -1 - (1 - side));
			if (light) break;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & F_NO_AFFECT) || t->toughness - t->damage > s->u[given].power) continue;
				if (hero_ability_fits(x, s, k, given, j)) count = add_hero_ability(out, count, k, given, j);
			}
			break;
		}
		case HE_SPLK:
		case HE_SACR: {
			int given = least_unit(s, side);
			if (given >= 0 && hero_ability_fits(x, s, k, given, 0)) count = add_hero_ability(out, count, k, given, 0);
			break;
		}
		case HE_RBRT:
		case HE_SCBR: {
			int place = best_buried(x, s, side);
			if (place >= 0 && hero_ability_fits(x, s, k, -1 - side, place)) count = add_hero_ability(out, count, k, -1 - side, place);
			/* A search for a certain win is told of every other kind buried. */
			for (int p = 0; x->proof && p < s->known[side]; p++)
				if (p != place && fresh_kind(s, side, p) && hero_ability_fits(x, s, k, -1 - side, p)) count = add_hero_ability(out, count, k, -1 - side, p);
			break;
		}
		case HE_RPST:
			if (!hero_ability_fits(x, s, k, NO_TARGET, -1)) break;
			count = add_hero_ability(out, count, k, NO_TARGET, -1);
			for (int p = 0; x->proof && p < s->known[side]; p++)
				if (fresh_kind(s, side, p) && s->graves[side][p] <= POOL) count = add_hero_ability(out, count, k, NO_TARGET, p);
			break;
		case HE_OEXC: {
			/* The best of its own out of the plane, for the best of the other army. */
			int mine = -1, theirs = -1;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->flags & F_DEAD) continue;
				if (t->owner == side && (t->flags & (F_PLANE | F_GONE)) && (mine < 0 || t->ready_worth > s->u[mine].ready_worth)) mine = j;
				if (t->owner != side && !(t->flags & (F_PLANE | F_GONE)) && (theirs < 0 || t->ready_worth > s->u[theirs].ready_worth)) theirs = j;
			}
			if (mine >= 0 && theirs >= 0 && hero_ability_fits(x, s, k, mine, theirs)) count = add_hero_ability(out, count, k, mine, theirs);
			break;
		}
		case HE_RNST: {
			int found = 0;
			for (int j = 0; j < s->n && !found; j++)
				found = s->u[j].owner != side && !(s->u[j].flags & (F_DEAD | F_GONE | F_NO_AFFECT | F_PLANE));
			if (found) count = add_hero_ability(out, count, k, NO_TARGET, 0);
			break;
		}
		case HE_ENRG:
			for (int j = 0; j < s->n; j++)
				if (s->u[j].owner == side && hero_ability_fits(x, s, k, j, 0)) {
					count = add_hero_ability(out, count, k, j, 0);
					if (light) break;
				}
			break;
		default:
			if (hero_ability_fits(x, s, k, NO_TARGET, 0)) count = add_hero_ability(out, count, k, NO_TARGET, 0);
			break;
		}
	}
	return count;
}

/* The abilities the side to move may use now, each on what is worth naming:
 * the rules allow far more than is ever of use. */
static int ability_moves(const State *s, Move *out, int count, int light) {
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker, price = 0;
	for (int i = 0; i < s->n && count < MAX_MOVES - 2; i++) {
		const Unit *u = &s->u[i];
		if (u->owner != side || !u->ability) continue;
		switch (u->ability) {
		case AB_DISPEL:
		case AB_DISENCHANT:
		case AB_ORC_RITE: {
			Dispel found[2];
			int wide = dispel_choices((const Search *)s->rules, s, side, found, light ? 1 : 2);
			for (int k = 0; k < wide; k++)
				if (ability_fits(s, i, found[k].holder, found[k].what, &price)) count = add_ability(out, count, i, found[k].holder, found[k].what);
			break;
		}
		case AB_SPORES:
		case AB_SPORES_POWER:
		case AB_STING: {
			int amount = u->ability == AB_STING ? u->ability_amount : (u->ability == AB_SPORES ? 1 : imax(0, u->power));
			if (amount <= 0) break;
			if (ability_fits(s, i, -1 - (1 - side), 0, &price)) count = add_ability(out, count, i, -1 - (1 - side), 0);
			if (light) break;
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & F_NO_AFFECT)) continue;
				/* A fingus dies of its spores: only for a creature they finish. */
				if (u->ability != AB_STING && t->toughness - t->damage > amount) continue;
				if (ability_fits(s, i, j, 0, &price)) count = add_ability(out, count, i, j, 0);
			}
			break;
		}
		case AB_SHOOT:
		case AB_SLAY:
		case AB_GAZE_TOUGHNESS:
		case AB_GAZE_POWER:
		case AB_HUNT:
		case AB_WALL_BREAK:
		case AB_TAP_TARGET:
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & F_NO_AFFECT)) continue;
				if (u->ability == AB_TAP_TARGET && (t->flags & F_RESTING)) continue;
				if (ability_fits(s, i, j, 0, &price)) {
					count = add_ability(out, count, i, j, 0);
					if (light) break;
				}
			}
			break;
		case AB_TAP_RACE:
			for (int j = 0; j < s->n; j++) {
				const Unit *t = &s->u[j];
				if (t->owner == side || (t->flags & (F_DEAD | F_GONE | F_RESTING))) continue;
				/* One of a race stands for them all. */
				int seen = 0;
				for (int k = 0; k < j && !seen; k++)
					seen = s->u[k].owner != side && !(s->u[k].flags & (F_DEAD | F_GONE | F_RESTING)) && s->u[k].race == t->race;
				if (!seen && ability_fits(s, i, j, 0, &price)) count = add_ability(out, count, i, j, 0);
			}
			break;
		case AB_SACRIFICE: {
			/* Only the creature its hero would miss least. */
			int least = -1;
			for (int j = 0; j < s->n; j++) {
				if (!ability_fits(s, i, j, 0, &price)) continue;
				if (least < 0 || s->u[j].ready_worth < s->u[least].ready_worth) least = j;
			}
			if (least >= 0 && !light) count = add_ability(out, count, i, least, 0);
			break;
		}
		case AB_GNAW:
		case AB_PLAGUE: {
			/* Only out of the other hero's graveyard, and only while its cards
			 * can still come to something. */
			const Search *x = (const Search *)s->rules;
			int whose = 1 - side;
			if (light || s->grave[whose] <= 0 || !grave_matters(x, s, whose)) break;
			if (u->ability == AB_GNAW) {
				int place = grave_choice(s, i, whose);
				if (place >= 0) count = add_ability(out, count, i, -1 - whose, place);
			} else {
				int most = imin(s->ether[side], s->grave[whose]);
				if (most > 0 && ability_fits(s, i, -1 - whose, most, &price)) count = add_ability(out, count, i, -1 - whose, most);
			}
			break;
		}
		case AB_RECALL:
		case AB_RAISE_OWN: {
			int place = grave_choice(s, i, side);
			if (place >= 0 && !light && (u->ability == AB_RECALL || army_size(s, side) < ARMY))
				count = add_ability(out, count, i, -1 - side, place);
			break;
		}
		case AB_NECROMANCY:
			/* The best it may raise out of each graveyard. */
			if (light || army_size(s, side) >= ARMY) break;
			for (int whose = 0; whose < 2; whose++) {
				int place = grave_choice(s, i, whose);
				if (place >= 0) count = add_ability(out, count, i, -1 - whose, place);
			}
			break;
		case AB_POWER_X:
		case AB_HEALTH_X:
		case AB_PHANTASM: {
			/* Only for the fight it stands in: the ether that lets it kill what
			 * it blocks, or live through the blow. */
			if (light || s->phase != 1 || u->blocks < 0 || (u->flags & (F_DEAD | F_GONE))) break;
			const Unit *a = &s->u[u->blocks];
			if (a->flags & (F_DEAD | F_GONE)) break;
			int need = u->ability == AB_HEALTH_X ? imax(0, a->power) - (u->toughness - u->damage) + 1
				: (a->toughness - a->damage) - imax(0, u->power);
			if (need <= 0) break;
			if (u->ability == AB_PHANTASM) {
				if (need <= 2 && ability_fits(s, i, NO_TARGET, 0, &price)) count = add_ability(out, count, i, NO_TARGET, 0);
			} else if (ability_fits(s, i, NO_TARGET, need, &price)) count = add_ability(out, count, i, NO_TARGET, need);
			break;
		}
		case AB_DISTORTION:
			/* The wall is given up to call an attack off: the one that stands,
			 * or the other hero's next. */
			if (light || !ability_fits(s, i, NO_TARGET, 0, &price)) break;
			if (s->phase == 1 || army_size(s, 1 - side) > 0) count = add_ability(out, count, i, NO_TARGET, 0);
			break;
		case AB_ILLUSION: {
			/* Only where it leaves the wall with more health than it has. */
			const Search *rules = (const Search *)s->rules;
			if (!ability_fits(s, i, NO_TARGET, 0, &price)) break;
			if (s->grave[side] + 1 > (u->kind > 0 ? rules->pool[u->kind - 1].toughness : u->toughness)) count = add_ability(out, count, i, NO_TARGET, 0);
			break;
		}
		case AB_ROUSE:
		case AB_SPIRIT_FLIGHT: {
			if (!ability_fits(s, i, NO_TARGET, 0, &price)) break;
			int found = 0;
			for (int j = 0; j < s->n && !found; j++) {
				const Unit *t = &s->u[j];
				if (t->owner != side || t->tribe != 1 || (t->flags & (F_DEAD | F_GONE))) continue;
				found = u->ability == AB_ROUSE ? (t->flags & F_RESTING) != 0 : !(t->flags & F_FLY);
			}
			if (found) count = add_ability(out, count, i, NO_TARGET, 0);
			break;
		}
		default: {
			if (!ability_fits(s, i, NO_TARGET, 0, &price)) break;
			/* One that would find nothing to work on is not offered. */
			int idle = 0, found = 0;
			if (u->ability == AB_SIPHON) idle = s->ether[1 - side] <= 0;
			if (u->ability == AB_TAP_WALLS) idle = price <= 0;
			if (u->ability == AB_BREATH_FLYING || u->ability == AB_BREATH_GROUND || u->ability == AB_RALLY) {
				for (int j = 0; j < s->n && !found; j++) {
					const Unit *t = &s->u[j];
					if (t->flags & (F_DEAD | F_GONE)) continue;
					if (u->ability == AB_RALLY)
						found = t->owner == side && (t->flags & F_RESTING) && t->race == u->ability_amount && t->ability != AB_RALLY;
					else
						found = t->owner != side && !(t->flags & (F_NO_AFFECT | F_PLANE))
							&& ((t->flags & F_FLY) != 0) == (u->ability == AB_BREATH_FLYING);
				}
				idle = !found;
			}
			if (!idle) count = add_ability(out, count, i, NO_TARGET, 0);
			break;
		}
		}
	}
	return count;
}

/* Every command the rules allow the side to move, ordered so that the ones
 * worth most come first: the search cuts off sooner that way. */
/* What a command looks worth before it is played: enough to order by. */
static int move_score(const Search *x, const State *s, const Move *m) {
	switch (m->kind) {
	case 1: return 2000 + s->u[m->a].power * 10 + s->u[m->a].toughness;
	case 2: return 1000 + s->u[m->a].power * 10;
	case 3: {
		const Card *card = card_at(x, s, s->phase == 0 ? s->attacker : 1 - s->attacker, m->a);
		return 500 + (card ? (card->free ? card->printed : card->cost) : 0) * 10 + m->c;
	}
	case 4: return 1500 + s->u[m->a].power * 10;
	/* Whole attacks and whole defences first, as they were ranked. */
	case 5:
	case 9:
	case 10: return 3000 - m->c;
	case 7: return m->b >= 0 ? 1800 + s->u[m->b].power * 10 : (m->b == NO_TARGET ? 1200 : 100);
	case 11: return m->b >= 0 ? 1700 + s->u[m->b].power * 10 : 1100;
	case 8: return m->b >= 0 ? 1300 + s->u[m->b].power * 10 : 600;
	default: return 0;
	}
}

/* The dearest creature card the engine knows in a listed graveyard: its
 * place there, or -1. */
static int best_buried(const Search *x, const State *s, int whose) {
	int best = -1;
	for (int p = 0; p < s->known[whose]; p++) {
		int kind = s->graves[whose][p];
		if (kind <= 0) continue;
		if (best < 0 || x->pool[kind - 1].ready_worth > x->pool[s->graves[whose][best] - 1].ready_worth) best = p;
	}
	return best;
}

/* The casts of a card that names a second thing beside its target. Of a
 * graveyard only the dearest creature is offered, and to be given up only
 * the two creatures worth least. */
static int choice_moves(const Search *x, const State *s, int side, const Card *c, int h, Move *out, int count, int light) {
	if (c->effect == EFF_DISPEL || c->effect == EFF_TRADE) {
		/* The enchantments best rid of; for a trade, at the price of the
		 * creature worth least. */
		Dispel found[3];
		int wide = dispel_choices(x, s, side, found, light ? 1 : 3), given = c->effect == EFF_TRADE ? least_unit(s, side) : -1;
		if (c->effect == EFF_TRADE && given < 0) return count;
		for (int k = 0; k < wide && count < MAX_MOVES - 2; k++) {
			if (c->effect == EFF_TRADE) {
				if (found[k].holder == given) continue;
				out[count++] = (Move){ 3, h, given, (found[k].holder < 0 ? -found[k].holder - 1 : found[k].holder + 2) * 4096 + found[k].what };
			} else if (card_cost(x, s, c) + ((c->amount & 1) ? ench_price(x, s, found[k].holder, found[k].what, 1) : 0) <= s->ether[side])
				out[count++] = (Move){ 3, h, found[k].holder, found[k].what };
		}
		return count;
	}
	if (c->effect == EFF_PALE_REVIVAL) {
		/* A creature of the other army in the plane, for the dearest card
		 * of either graveyard. */
		int whose = -1, place = -1;
		for (int g = 0; g < 2; g++) {
			int p = best_buried(x, s, g);
			if (p >= 0 && (place < 0 || x->pool[s->graves[g][p] - 1].ready_worth > x->pool[s->graves[whose][place] - 1].ready_worth)) {
				whose = g;
				place = p;
			}
		}
		if (place < 0 || army_size(s, side) >= ARMY) return count;
		for (int i = 0; i < s->n && count < MAX_MOVES - 2; i++) {
			const Unit *v = &s->u[i];
			if (v->owner == side || (v->flags & F_DEAD) || !(v->flags & (F_PLANE | F_GONE)) || v->shielded) continue;
			out[count++] = (Move){ 3, h, i, whose * 64 + place };
			if (light) break;
		}
		return count;
	}
	if (c->effect == EFF_REPAIR || c->effect == EFF_REANIMATE) {
		for (int whose = 0; whose < 2 && count < MAX_MOVES - 2; whose++) {
			if ((c->effect == EFF_REPAIR || c->own) && whose != side) continue;
			int place = best_buried(x, s, whose);
			if (place < 0) continue;
			if (c->effect == EFF_REANIMATE && (army_size(s, side) >= ARMY || ((c->amount & 1) && army_size(s, whose) >= ARMY))) continue;
			out[count++] = (Move){ 3, h, -1 - whose, place };
			/* A search for a certain win is told of every other kind buried. */
			for (int p = 0; x->proof && p < s->known[whose] && count < MAX_MOVES - 2; p++)
				if (p != place && fresh_kind(s, whose, p)) out[count++] = (Move){ 3, h, -1 - whose, p };
		}
		return count;
	}
	int given[2] = { -1, -1 };
	for (int i = 0; i < s->n; i++) {
		if (s->u[i].owner != side || !may_aim(s, side, c, i)) continue;
		int worth = s->u[i].ready_worth;
		if (given[0] < 0 || worth < s->u[given[0]].ready_worth) {
			given[1] = given[0];
			given[0] = i;
		} else if (given[1] < 0 || worth < s->u[given[1]].ready_worth) given[1] = i;
	}
	for (int g = 0; g < (light ? 1 : 2) && count < MAX_MOVES - 2; g++) {
		if (given[g] < 0) continue;
		if (c->effect == EFF_EXCHANGE) {
			int place = best_buried(x, s, side);
			if (place >= 0) out[count++] = (Move){ 3, h, given[g], place };
			continue;
		}
		for (int i = 0; i < s->n && count < MAX_MOVES - 2; i++) {
			const Unit *v = &s->u[i];
			if (v->owner == side || (v->flags & (F_DEAD | F_GONE | F_PLANE | F_NO_AFFECT)) || v->shielded) continue;
			out[count++] = (Move){ 3, h, given[g], i };
			if (light) break;
		}
	}
	return count;
}

/* The cards the hero to move may play from its hand: any of them while it
 * attacks, only those that may be cast in defence while it defends. */
static int card_moves(const Search *x, const State *s, int side, Move *out, int count, int light) {
	for (int h = 0; h < ART_BASE + MAX_ART && count < MAX_MOVES - 2; h++) {
		const Card *c = card_at(x, s, side, h);
		if (!c || c->cost < 0 || c->effect == EFF_NONE) continue;
		if (s->phase != 0 && !c->defence && h < ART_BASE) continue;
		if (card_cost(x, s, c) > s->ether[side] || c->channels > s->channels[side]) continue;
		if (c->choice) {
			count = choice_moves(x, s, side, c, h, out, count, light);
			continue;
		}
		/* Two cards alike that came back are one choice. */
		if (h > SLOTS && h < ART_BASE) {
			int twin = 0;
			for (int j = SLOTS; j < h; j++) twin |= s->back[side][j - SLOTS] == s->back[side][h - SLOTS];
			if (twin) continue;
		}
		/* A wave with nothing in its reach is not worth its card. */
		if (c->effect == EFF_WAVE) {
			int who[MAX_UNITS + 2];
			if (spell_targets(s, side, c, NO_TARGET, who) == 0) continue;
		}
		/* How much ether to pour into an X: all of it, half, or none. */
		int powers[3], wide = 0;
		if (c->effect == EFF_REVIVE && s->grave[side] <= 0) continue;
		if (c->effect == EFF_CHANNEL) {
			/* Health for ether: none of it, a little, or a good deal. */
			int most = imin(s->health[side] - 1, 6);
			powers[wide++] = 0;
			if (most >= 2) powers[wide++] = imin(most, 3);
			if (!light && most > 3) powers[wide++] = most;
		} else if (c->variable) {
			int most = s->ether[side] - c->cost;
			powers[wide++] = most;
			if (!light && most / 2 > 0 && most / 2 != most) powers[wide++] = most / 2;
			if (!light && most > 1) powers[wide++] = 1;
		} else powers[wide++] = 0;
		for (int p = 0; p < wide && count < MAX_MOVES - 2; p++) {
			if (c->aim == AIM_NONE) {
				if (idle_cast(x, s, side, c, NO_TARGET)) continue;
				out[count].kind = 3;
				out[count].a = h;
				out[count].b = NO_TARGET;
				out[count].c = powers[p];
				count++;
				continue;
			}
			if (c->aim != AIM_CREATURE)
				for (int side_at = 0; side_at < 2 && count < MAX_MOVES - 2; side_at++) {
					if (c->own && side_at != side) continue;
					if (idle_cast(x, s, side, c, -1 - side_at)) continue;
					out[count].kind = 3;
					out[count].a = h;
					out[count].b = -1 - side_at;
					out[count].c = powers[p];
					count++;
				}
			if (c->aim != AIM_HERO)
				for (int i = 0; i < s->n && count < MAX_MOVES - 2; i++) {
					if (!may_aim(s, side, c, i)) continue;
					out[count].kind = 3;
					out[count].a = h;
					out[count].b = i;
					out[count].c = powers[p];
					count++;
					/* A play-out tries one creature, not every one. */
					if (light) break;
				}
		}
	}
	return count;
}

/* `sorted` orders the commands for the search; `light` keeps the list short
 * for a play-out, where one target and the whole X will do. */
static int generate(const Search *x, const State *s, Move *out, int sorted, int light, int whole, Plan *kept) {
	int count = 0;
	/* Whole attacks and whole defences in place of single creatures. */
	int grouped = kept != NULL && !light && x->sets > 0 && x->plans > 0;
	/* Below the first command the same attackers sent, or the same blocks
	 * set, in another order are one choice: each creature is taken up only
	 * after the last one that was, so a set is tried once and not once for
	 * every order it can be named in. */
	int after = -1;
	if (x->ordered && !whole && !light && !grouped) {
		int newest = 0;
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if (u->flags & (F_DEAD | F_GONE)) continue;
			if (s->phase == 0 ? !(u->flags & F_ATTACKING) : u->blocks < 0) continue;
			if (u->rank >= newest) {
				newest = u->rank;
				after = i;
			}
		}
	}
	if (s->phase == 0) {
		int side = s->attacker;
		for (int i = 0; i < s->n && count < MAX_MOVES - 2 && !grouped; i++) {
			const Unit *u = &s->u[i];
			if ((u->flags & F_ATTACKING) || !can_attack(s, u)) continue;
			if ((u->flags & F_TEAM) && !team_partner(s, i)) continue;
			/* A guard waits on its partner, wherever that one stands. */
			if (i < after && !(u->flags & F_TEAM)) continue;
			out[count].kind = 1;
			out[count].a = i;
			out[count].b = 0;
			out[count].c = 0;
			count++;
		}
		count = card_moves(x, s, side, out, count, light);
	} else {
		count = card_moves(x, s, 1 - s->attacker, out, count, light);
		for (int i = 0; i < s->n && count < MAX_MOVES - 2 && !grouped; i++) {
			const Unit *u = &s->u[i];
			if (u->owner == s->attacker || (u->flags & (F_DEAD | F_GONE)) || !ready(u) || u->blocks >= 0) continue;
			if (i < after) continue;
			for (int a = 0; a < s->n && count < MAX_MOVES - 2; a++) {
				const Unit *t = &s->u[a];
				if (!(t->flags & F_ATTACKING) || (t->flags & (F_DEAD | F_GONE)) || !can_block(t, u)) continue;
				out[count].kind = 2;
				out[count].a = i;
				out[count].b = a;
				out[count].c = 0;
				count++;
				/* A play-out blocks the first attacker it can, not each. */
				if (light) break;
			}
		}
	}
	/* Either hero may free a creature an enchantment holds down. */
	{
		int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
		for (int i = 0; i < s->n && count < MAX_MOVES - 2; i++) {
			const Unit *u = &s->u[i];
			if (u->owner != side || (u->flags & (F_DEAD | F_GONE)) || !(u->flags & F_RESTING)) continue;
			if (u->wake <= 0 || s->ether[side] < u->wake) continue;
			out[count].kind = 4;
			out[count].a = i;
			out[count].b = 0;
			out[count].c = 0;
			count++;
		}
	}
	count = ability_moves(s, out, count, light);
	if (s->second) count = pale_moves(x, s, out, count, light);
	count = hero_ability_moves(x, s, out, count, light);
	/* At the first command, the attack that the lookahead — which reads the
	 * defender's blocks properly — finds best is offered whole. Building an
	 * attack one creature at a time is how the engine walks into blocks. */
	if (whole && !grouped && s->phase == 0 && count < MAX_MOVES - 2) {
		Set sets[MAX_SETS];
		int found = attack_sets((Search *)x, s, sets, 1, 1);
		if (found > 0 && sets[0].mask) {
			out[count].kind = 5;
			out[count].a = (int32_t)(sets[0].mask & 0xffffu);
			out[count].b = (int32_t)(sets[0].mask >> 16);
			out[count].c = 0;
			count++;
		}
	}
	if (grouped && s->phase == 0) {
		/* The attacks the lookahead ranks best, each sent whole and the phase
		 * ended with it. Sending nobody further is the plain end below. The
		 * first command only sends one, and has more of them to choose from. */
		Set sets[MAX_SETS];
		uint32_t sent = 0;
		for (int i = 0; i < s->n; i++)
			if ((s->u[i].flags & F_ATTACKING) && !(s->u[i].flags & (F_DEAD | F_GONE))) sent |= 1u << i;
		int most = whole ? imax(x->sets, 12) : x->sets;
		int found = attack_sets((Search *)x, s, sets, imax(most + 1, 12), 1);
		int given = 0;
		for (int i = 0; i < found && given < most && count < MAX_MOVES - 2; i++) {
			if ((sets[i].mask & ~sent) == 0) continue;
			out[count].kind = whole ? 5 : 9;
			out[count].a = (int32_t)(sets[i].mask & 0xffffu);
			out[count].b = (int32_t)(sets[i].mask >> 16);
			out[count].c = given++;
			count++;
		}
	} else if (grouped) {
		/* The defences the block search ranks best, each set whole and the
		 * phase ended with it. Blocking with nobody further is the plain end. */
		int8_t base[MAX_UNITS];
		memset(base, -1, sizeof(base));
		for (int i = 0; i < s->n; i++) base[i] = s->u[i].blocks;
		int most = whole ? imax(x->plans, 12) : x->plans;
		int found = block_plans((Search *)x, s, base, kept, most + 1, 1);
		int given = 0;
		for (int i = 0; i < found && given < most && count < MAX_MOVES - 2; i++) {
			if (memcmp(kept[i].target, base, (size_t)s->n) == 0) continue;
			out[count].kind = 10;
			out[count].a = i;
			out[count].b = 0;
			out[count].c = given++;
			count++;
		}
	}
	out[count].kind = 0;
	out[count].a = 0;
	out[count].b = 0;
	out[count].c = 0;
	count++;
	if (!sorted) return count;
	/* Strongest first: the heaviest attacker, the dearest card, the stoutest
	 * blocker, and ending the phase last of all. Alpha-beta cuts far more of
	 * the tree away when it meets the best commands early. */
	int score[MAX_MOVES];
	for (int i = 0; i < count; i++) score[i] = move_score(x, s, &out[i]);
	for (int i = 1; i < count; i++) {
		Move m = out[i];
		int v = score[i], j = i - 1;
		while (j >= 0 && score[j] < v) {
			out[j + 1] = out[j];
			score[j + 1] = score[j];
			j--;
		}
		out[j + 1] = m;
		score[j + 1] = v;
	}
	return count;
}

/* After every command the attack is put right as the rules have it: what
 * can no longer attack comes home, and what must attack is sent at once
 * (unless attacking costs ether). */
static void sync_attack(State *s) {
	if (s->phase != 0 || s->health[0] <= 0 || s->health[1] <= 0) return;
	int fog = fogged(s);
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (!(u->flags & F_ATTACKING) || (u->flags & (F_DEAD | F_GONE))) continue;
		/* One already sent may have been laid to rest since and still goes. */
		if (fog || u->owner != s->attacker || (u->flags & (F_SICK | F_NO_ATTACK | F_PLANE)) || imax(0, u->power) <= s->forest[1 - u->owner])
			u->flags &= ~(uint32_t)F_ATTACKING;
	}
	if (s->tax > 0) return;
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->owner != s->attacker || (u->flags & (F_DEAD | F_GONE | F_ATTACKING)) || !(u->flags & F_BERSERK)) continue;
		if (!can_declare(s, u) || ((u->flags & F_TEAM) && !team_partner(s, i))) continue;
		u->flags |= F_ATTACKING;
		ranked(s, u);
	}
}

static int apply_inner(const Search *x, State *s, const int32_t *cmd);

/* One command of the side to move, named as the game names them: end the
 * phase, send or recall an attacker, block, or play a card. 0 when these
 * rules refuse it. */
static int apply_command(const Search *x, State *s, const int32_t *cmd) {
	int done = apply_inner(x, s, cmd);
	/* Sending a creature, or calling one back, settles nothing else: what
	 * must attack goes with the next command of another kind. */
	if (done && cmd[0] != 1) sync_attack(s);
	return done;
}

/* Every block of a plan not yet set, and the defence ended. */
static int block_whole(const Search *x, State *s, const Plan *plan) {
	static const int32_t end[4] = { 0, 0, 0, 0 };
	if (s->phase != 1) return 0;
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (plan->target[i] < 0 || u->blocks >= 0) continue;
		u->blocks = plan->target[i];
		ranked(s, u);
	}
	return apply_inner(x, s, end);
}

static int apply_inner(const Search *x, State *s, const int32_t *cmd) {
	if (s->health[0] <= 0 || s->health[1] <= 0) return 0;
	switch (cmd[0]) {
	case 0:
		if (s->phase == 0) {
			int any = 0;
			/* Ending the attack sends every creature that must attack, unless
			 * attacking costs ether. */
			if (s->tax == 0)
				for (int pass = 0; pass < 2; pass++)
					for (int i = 0; i < s->n; i++) {
						Unit *u = &s->u[i];
						if (u->owner != s->attacker || (u->flags & (F_DEAD | F_GONE | F_ATTACKING))) continue;
						if (!(u->flags & F_BERSERK) || !can_declare(s, u)) continue;
						/* A guard goes only beside another of its race already sent. */
						if ((u->flags & F_TEAM) && !team_partner(s, i)) continue;
						u->flags |= F_ATTACKING;
						ranked(s, u);
					}
			for (int i = 0; i < s->n; i++)
				if ((s->u[i].flags & F_ATTACKING) && !(s->u[i].flags & (F_DEAD | F_GONE))) any = 1;
			if (any) {
				/* What regenerated while its hero moved is whole again. */
				for (int i = 0; i < s->n; i++) s->u[i].flags &= ~(uint32_t)F_REGENERATED;
				s->phase = 1;
				return 1;
			}
			end_turn(x, s);
			return 1;
		} else {
			int8_t t[MAX_UNITS];
			for (int i = 0; i < s->n; i++) t[i] = s->u[i].blocks;
			resolve(s, t);
			s->phase = 0;
			if (s->health[0] > 0 && s->health[1] > 0) end_turn(x, s);
			return 1;
		}
	case 1: {
		int i = cmd[1];
		if (s->phase != 0 || i < 0 || i >= s->n) return 0;
		Unit *u = &s->u[i];
		if (u->owner != s->attacker || (u->flags & (F_DEAD | F_GONE))) return 0;
		if (u->flags & F_ATTACKING) {
			/* One that must attack cannot be called back, nor one a guard
			 * already sent is leaning on. */
			if (u->flags & F_BERSERK) return 0;
			u->flags &= ~(uint32_t)F_ATTACKING;
			for (int j = 0; j < s->n; j++) {
				const Unit *g = &s->u[j];
				if (j == i || !(g->flags & F_ATTACKING) || (g->flags & (F_DEAD | F_GONE)) || !(g->flags & F_TEAM)) continue;
				int partner = 0;
				for (int k = 0; k < s->n && !partner; k++)
					partner = k != j && (s->u[k].flags & F_ATTACKING) && !(s->u[k].flags & (F_DEAD | F_GONE | F_TEAM))
						&& s->u[k].race == g->race && s->u[k].owner == g->owner;
				if (!partner) {
					u->flags |= F_ATTACKING;
					return 0;
				}
			}
			return 1;
		}
		if (!can_declare(s, u)) return 0;
		if ((u->flags & F_TEAM) && !team_partner(s, i)) return 0;
		/* Sending a creature costs ether while attacking is taxed. */
		if (s->tax > s->ether[s->attacker]) return 0;
		pay(s, s->attacker, s->tax);
		u->flags |= F_ATTACKING;
		ranked(s, u);
		return 1;
	}
	case 2: {
		int i = cmd[1], a = cmd[2];
		if (s->phase != 1 || i < 0 || i >= s->n || a < 0 || a >= s->n) return 0;
		Unit *u = &s->u[i];
		if (u->owner == s->attacker || (u->flags & (F_DEAD | F_GONE)) || !ready(u) || u->blocks >= 0) return 0;
		if (!(s->u[a].flags & F_ATTACKING) || (s->u[a].flags & (F_DEAD | F_GONE)) || !can_block(&s->u[a], u)) return 0;
		u->blocks = (int8_t)a;
		ranked(s, u);
		return 1;
	}
	case 3: {
		/* The defender has only the few cards that may be cast in defence. */
		int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
		if (s->phase != 0 && cmd[1] < ART_BASE && (cmd[1] < 0 || cmd[1] >= SLOTS || !x->hand[side][cmd[1]].defence)) return 0;
		if (!cast_card(x, s, side, cmd[1], cmd[2], cmd[3])) return 0;
		drop_blocks(s);
		return 1;
	}
	case 6: {
		/* Block the way the block search says, all at once. */
		if (s->phase != 1) return 0;
		int8_t base[MAX_UNITS], plan[MAX_UNITS];
		for (int i = 0; i < s->n; i++) base[i] = s->u[i].blocks;
		memcpy(plan, base, (size_t)s->n);
		search_blocks((Search *)x, s, base, 1, 2, -2 * WIN, 2 * WIN, plan);
		int any = 0;
		for (int i = 0; i < s->n; i++)
			if (plan[i] != base[i] && plan[i] >= 0) {
				s->u[i].blocks = plan[i];
				ranked(s, &s->u[i]);
				any = 1;
			}
		return any;
	}
	case 5: {
		/* The whole attack the block-reading lookahead likes best. */
		if (s->phase != 0) return 0;
		uint32_t mask = ((uint32_t)cmd[1] & 0xffffu) | ((uint32_t)cmd[2] << 16);
		int any = 0;
		for (int i = 0; i < s->n; i++)
			if ((mask >> i & 1) && !(s->u[i].flags & F_ATTACKING) && can_declare(s, &s->u[i])) any++;
		if (!any || any * s->tax > s->ether[s->attacker] || !team_fits(s, mask)) return 0;
		declare(x, s, mask);
		return 1;
	}
	case 9: {
		/* A whole attack sent and the phase ended with it. */
		static const int32_t send_end[4] = { 0, 0, 0, 0 };
		int32_t send[4] = { 5, cmd[1], cmd[2], 0 };
		if (!apply_inner(x, s, send)) return 0;
		return apply_inner(x, s, send_end);
	}
	case 10: {
		/* A whole defence, the one of that place among those the block search
		 * ranks best, and the phase ended with it. */
		if (s->phase != 1 || cmd[1] < 0 || x->plans <= 0) return 0;
		Plan plans[MAX_PLANS];
		int8_t base[MAX_UNITS];
		memset(base, -1, sizeof(base));
		for (int i = 0; i < s->n; i++) base[i] = s->u[i].blocks;
		int found = block_plans((Search *)x, s, base, plans, MAX_PLANS, 1);
		if (cmd[1] >= found) return 0;
		return block_whole(x, s, &plans[cmd[1]]);
	}
	case 7:
		return use_ability(s, cmd[1], cmd[2], cmd[3]);
	case 11:
		return use_pale(x, s, cmd[1], cmd[2], cmd[3]);
	case 8:
		return use_hero_ability(x, s, cmd[1], cmd[2], cmd[3]);
	case 4: {
		/* Freeing a creature an enchantment holds down. */
		int i = cmd[1];
		if (i < 0 || i >= s->n) return 0;
		Unit *u = &s->u[i];
		int side = u->owner;
		if ((u->flags & (F_DEAD | F_GONE)) || !(u->flags & F_RESTING) || u->wake <= 0 || muted(s, i)) return 0;
		if (side != (s->phase == 0 ? s->attacker : 1 - s->attacker)) return 0;
		if (s->ether[side] < u->wake) return 0;
		pay(s, side, u->wake);
		if (u->wake_hurts) {
			/* It rises this once; what holds it down stays on it. */
			hurt_hero(s, side, u->wake, -1);
			u->flags &= ~(uint32_t)F_RESTING;
			return 1;
		}
		/* What held it down comes off: with more of it left, it stays down. */
		int held = 0;
		for (int r = 0; r < s->enchs; r++) held += s->ench[r].unit == i && s->ench[r].kind == EN_HOLD;
		for (int r = 0; r < s->enchs; r++)
			if (s->ench[r].unit == i && s->ench[r].kind == EN_HOLD) {
				unwear(s, r);
				break;
			}
		if (held > 1) return 1;
		u->flags &= ~(uint32_t)(F_RESTING | F_NO_UNTAP);
		u->wake = 0;
		return 1;
	}
	}
	return 0;
}

/* --------------------------------------------------- playing games out */

/* A duel played to its end from here, both heroes giving commands by the
 * plain ordering above with a little chance mixed in. Returns 2 for a win,
 * from the computer's side: 1000 for a win, less the turns it took, 0 for a
 * loss plus the turns it held out, and the health between the heroes when
 * neither falls. Nothing about the board is weighed but its health, so that
 * two commands that both win can still be told apart by how surely and how
 * soon they do. */
static uint32_t roll(uint32_t *seed) {
	uint32_t v = *seed;
	v ^= v << 13;
	v ^= v >> 17;
	v ^= v << 5;
	*seed = v;
	return v;
}

/* The command a play-out gives: the strongest one going, with one in four
 * taken at random instead. Nothing is listed or sorted — a play-out visits
 * millions of positions, so each step only walks the board once. */
static void pick_command(const Search *x, const State *s, uint32_t *seed, Move *out) {
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
	int wild = (roll(seed) & 3) == 0;
	int seen = 0, best = -1;
	Move chosen = { 0, 0, 0, 0 }, candidate;
	/* Ending the phase is always there, and is what we fall back to. */
	out->kind = 0;
	out->a = 0;
	out->b = 0;
	out->c = 0;
	if (s->phase == 1 && x->fight_well) {
		/* Blocking badly in a play-out is what makes a hopeless attack look
		 * sound, so the defender blocks as the block search advises. */
		out->kind = 6;
		return;
	}
	if (s->phase == 0) {
		if (x->fight_well && !wild) {
			int declared = 0;
			for (int i = 0; i < s->n; i++)
				if (s->u[i].flags & F_ATTACKING) declared = 1;
			if (!declared) {
				Set sets[MAX_SETS];
				if (attack_sets((Search *)x, s, sets, 1, 1) > 0 && sets[0].mask) {
					out->kind = 5;
					out->a = (int32_t)(sets[0].mask & 0xffffu);
					out->b = (int32_t)(sets[0].mask >> 16);
					out->c = 0;
					return;
				}
			}
		}
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if ((u->flags & F_ATTACKING) || !can_attack(s, u)) continue;
			candidate.kind = 1;
			candidate.a = i;
			candidate.b = 0;
			candidate.c = 0;
			int score = 2000 + u->power * 10 + u->toughness;
			if (wild) {
				if ((int)(roll(seed) % (uint32_t)(++seen)) == 0) chosen = candidate;
			} else if (score > best) {
				best = score;
				chosen = candidate;
			}
		}
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if (u->owner != side || (u->flags & (F_DEAD | F_GONE)) || !(u->flags & F_RESTING)) continue;
			if (u->wake <= 0 || s->ether[side] < u->wake) continue;
			candidate.kind = 4;
			candidate.a = i;
			candidate.b = 0;
			candidate.c = 0;
			int score = 1500 + u->power * 10;
			if (wild) {
				if ((int)(roll(seed) % (uint32_t)(++seen)) == 0) chosen = candidate;
			} else if (score > best) {
				best = score;
				chosen = candidate;
			}
		}
		for (int h = 0; h < SLOTS; h++) {
			const Card *c = &x->hand[side][h];
			if (c->cost < 0 || c->effect == EFF_NONE || (s->played[side] >> h & 1)) continue;
			if (h >= HAND && h - HAND >= s->drawn[side]) continue;
			if (c->cost > s->ether[side]) continue;
			int target = NO_TARGET;
			if (c->aim == AIM_HERO) target = c->own ? -1 - side : -2 + side;
			else if (c->aim != AIM_NONE) {
				for (int i = 0; i < s->n; i++)
					if (may_aim(s, side, c, i)) {
						target = i;
						break;
					}
				if (target == NO_TARGET && c->aim == AIM_ANY) target = c->own ? -1 - side : -2 + side;
				if (target == NO_TARGET) continue;
			}
			candidate.kind = 3;
			candidate.a = h;
			candidate.b = target;
			candidate.c = c->variable ? s->ether[side] - c->cost : 0;
			int score = 500 + c->cost * 10;
			if (wild) {
				if ((int)(roll(seed) % (uint32_t)(++seen)) == 0) chosen = candidate;
			} else if (score > best) {
				best = score;
				chosen = candidate;
			}
		}
	} else {
		for (int i = 0; i < s->n; i++) {
			const Unit *u = &s->u[i];
			if (u->owner == s->attacker || (u->flags & (F_DEAD | F_GONE)) || !ready(u) || u->blocks >= 0) continue;
			for (int a = 0; a < s->n; a++) {
				const Unit *t = &s->u[a];
				if (!(t->flags & F_ATTACKING) || (t->flags & (F_DEAD | F_GONE)) || !can_block(t, u)) continue;
				candidate.kind = 2;
				candidate.a = i;
				candidate.b = a;
				candidate.c = 0;
				int score = 1000 + u->power * 10;
				if (wild) {
					if ((int)(roll(seed) % (uint32_t)(++seen)) == 0) chosen = candidate;
				} else if (score > best) {
					best = score;
					chosen = candidate;
				}
				break;
			}
		}
	}
	/* One step in eight ends the phase even with something left to do, so
	 * that a play-out does not spend every card and creature every turn. */
	if ((wild ? seen > 0 : best >= 0) && (roll(seed) & 7) != 0) *out = chosen;
}

static int play_out(Search *x, const State *start, uint32_t *seed, int rounds) {
	State s = *start;
	int ends = 0;
	/* Every game counts against the budget, even one that is over before it
	 * starts: otherwise a decided position spins here for ever. */
	x->nodes++;
	for (int step = 0; step < 160; step++) {
		if (s.health[0] <= 0 || s.health[1] <= 0) break;
		if (ends >= rounds * 2) break;
		Move step_move;
		pick_command(x, &s, seed, &step_move);
		if (step_move.kind == 0) ends++;
		x->nodes++;
		if (!apply_command(x, &s, (const int32_t *)&step_move)) {
			/* Whatever the rules refuse, the phase ends instead. */
			Move done = { 0, 0, 0, 0 };
			ends++;
			if (!apply_command(x, &s, (const int32_t *)&done)) break;
		}
	}
	int mine = s.health[x->ai], theirs = s.health[1 - x->ai];
	int turns = ends / 2;
	if (theirs <= 0 && mine > 0) return 1000 - imin(turns, 20) * 10 + imin(mine, 40);
	if (mine <= 0 && theirs > 0) return -1000 + imin(turns, 20) * 10 - imin(theirs, 40);
	if (mine <= 0 && theirs <= 0) return 0;
	/* Neither hero fell inside the rounds played: the health between them. */
	return imin(imax(mine - theirs, -500), 500);
}

/* ------------------------------------------------- searching the commands */

/* A line that stops while an attack stands is worth what that attack comes
 * to: the defender blocks as well as it can and the fight is played out.
 * Without this, sending a creature looks free and the search sends them all. */
static int settle_whole(Search *x, const State *s, int phases);

/* The worth of a line where it stops. What the fighting still to come is
 * read to bring is only as sure as the reading, so it is weighed against the
 * position as it stands, the way the original weighs the position before
 * and after the phase ends. */
static int settle(Search *x, const State *s, int phases) {
	int later = settle_whole(x, s, phases);
	if (x->blend <= 0 || later >= WIN / 2 || later <= -WIN / 2) return later;
	int now = evaluate(x, s, phases);
	return (int)(((int64_t)later * (100 - x->blend) + (int64_t)now * x->blend) / 100);
}

static int settle_whole(Search *x, const State *s, int phases) {
	State d = *s;
	int any = 0;
	for (int i = 0; i < d.n; i++)
		if ((d.u[i].flags & F_ATTACKING) && !(d.u[i].flags & (F_DEAD | F_GONE))) any = 1;
	/* A line that stops where a hero could still attack is not weighed as if
	 * that hero then stood idle. A line in which the engine attacked ends at
	 * the start of the other hero's turn, and passing that turn unplayed
	 * would hide the answer to the attack - the blow that falls on creatures
	 * left resting - while a line in which it held back has the other hero's
	 * attack read in full. So the hero to move sends the attack the
	 * lookahead finds best before the turn passes. */
	if (!any && x->leaf_attack && d.phase == 0) {
		Set sets[MAX_SETS];
		if (attack_sets(x, &d, sets, 1, 1) > 0 && sets[0].mask) {
			int fresh = 0;
			for (int i = 0; i < d.n; i++)
				if ((sets[0].mask >> i & 1) && !(d.u[i].flags & F_ATTACKING)) fresh++;
			if (fresh > 0 && fresh * d.tax <= d.ether[d.attacker]) {
				declare(x, &d, sets[0].mask);
				d.phase = 1;
				any = 1;
			}
		}
	}
	if (any) {
		int8_t base[MAX_UNITS], plan[MAX_UNITS];
		for (int i = 0; i < d.n; i++) base[i] = d.u[i].blocks;
		memcpy(plan, base, (size_t)d.n);
		search_blocks(x, &d, base, 1, 2, -2 * WIN, 2 * WIN, plan);
		resolve(&d, plan);
		d.phase = 0;
		if (d.health[0] <= 0 || d.health[1] <= 0) return evaluate(x, &d, phases);
	}
	/* The turn always passes before the line is weighed, whether it ended in
	 * a fight or not. Weighing one line before the turn and another after it
	 * would count the hero's own coming attack as a gain in the first and the
	 * other hero's as a loss in the second, and nothing would ever attack. */
	end_turn(x, &d);
	int base = evaluate_leaf(x, &d, phases);
	/* A duel the turn's passing itself decided is worth just that. */
	if (x->leaf_turns <= 0 || base >= WIN || base <= -WIN) return base;
	/* What the fighting of the turns ahead adds to the board, as the search
	 * prices it: a win or loss foreseen that far off is worth a bounded
	 * amount, and a gain is discounted, since neither is yet a fact. The
	 * forecast adjusts the board's worth; it does not replace it. */
	int v = search_turn(x, &d, x->leaf_turns, 2, -2 * WIN, 2 * WIN, NULL);
	if (v >= WIN) return base + FORECAST;
	if (v <= -WIN) return base - FORECAST;
	int delta = v - evaluate(x, &d, phases);
	if (delta > 0) delta = delta * 9 / 10;
	return base + delta;
}

/* A number that stands for a position: every creature in play and all the
 * rest of the state, so that two lines arriving at one position are known
 * for the same. */
static uint64_t state_key(const State *s) {
	uint64_t h = 0x9E3779B97F4A7C15ull ^ (uint64_t)s->n;
	/* All of it but the word that says whose reading the position is in:
	 * where that lies in memory is no part of the position, and a number
	 * that changed from one run to the next would make each run fill its
	 * table differently. */
	const unsigned char *after = (const unsigned char *)&s->rules + sizeof(s->rules);
	const unsigned char *parts[3] = { (const unsigned char *)s->u, (const unsigned char *)&s->n, after };
	size_t sizes[3] = { sizeof(Unit) * (size_t)s->n, offsetof(State, rules) - offsetof(State, n),
		sizeof(State) - offsetof(State, rules) - sizeof(s->rules) };
	for (int part = 0; part < 3; part++) {
		const unsigned char *p = parts[part];
		size_t left = sizes[part];
		while (left >= 8) {
			uint64_t w;
			memcpy(&w, p, 8);
			h = (h ^ w) * 0xD6E8FEB86659FD93ull;
			h ^= h >> 32;
			p += 8;
			left -= 8;
		}
		if (left) {
			uint64_t w = 0;
			memcpy(&w, p, left);
			h = (h ^ w) * 0xD6E8FEB86659FD93ull;
			h ^= h >> 32;
		}
	}
	return h ? h : 1;
}

/* Alpha-beta over every command both heroes may give. `phases` counts the
 * phase changes still allowed and `steps` the commands left in this line, so
 * that a line cannot wander for ever; `x->budget` caps the whole search.
 * Returns the worth of the line and, in `best`, the command to give now. */
/* The most a hero could take off the other in one turn, counted with an
 * open hand: all its creatures' power, that of every creature card it
 * holds or is to draw, and what its spells deal or lend. A search for a
 * certain win gives up a line whose turns left cannot reach the other
 * hero's health even at half as much again: such a line is not read to
 * its end only to find the hero standing. */
static int damage_in_sight(const Search *x, const State *s, int side) {
	int sum = 0;
	for (int i = 0; i < s->n; i++) {
		const Unit *u = &s->u[i];
		if (u->owner != side || (u->flags & (F_DEAD | F_GONE))) continue;
		sum += imax(0, u->power);
	}
	for (int i = 0; i < SLOTS; i++) {
		const Card *c = &x->hand[side][i];
		if ((s->played[side] >> i & 1) || c->none || c->cost < 0) continue;
		/* A spell as strong as the ether poured into it. */
		if (c->variable || c->effect == EFF_WAVE) sum += imax(1, s->ether[side] + s->channels[side]);
		else if (c->effect == EFF_SUMMON) sum += imax(0, c->power);
		else if (c->effect == EFF_DAMAGE) sum += imax(1, c->amount);
		else sum += 1 + imax(0, c->power);
	}
	for (int j = 0; j < BACK; j++)
		if (s->back[side][j] > 0) sum += imax(0, x->pool[s->back[side][j] - 1].power);
	return sum;
}

static int search_moves(Search *x, State *s, int phases, int steps, int alpha, int beta, Move *best, const Move *first, Move *line, int *line_length) {
	Move below[MAX_LINE];
	int below_length = 0;
	if (line_length) *line_length = 0;
	if (s->health[0] <= 0 || s->health[1] <= 0) return evaluate(x, s, phases);
	/* Nothing is proved past a card that chance took or dealt. */
	if (x->proof && s->blind) return 0;
	if (x->proof && x->sight) {
		/* Its own turns among the phases left, this one counted. */
		int mine = s->attacker == x->ai;
		int turns = (phases + (mine ? (s->phase != 0 ? 3 : 2) : (s->phase != 0 ? 1 : 0))) / 4;
		if (s->health[1 - x->ai] > turns * (damage_in_sight(x, s, x->ai) * x->sight / 100 + 2)) return 0;
	}
	/* A position read before, to at least this depth, is not read again;
	 * one read less deeply still says which command to try first. */
	Entry *entry = NULL;
	uint64_t key = 0;
	int low = alpha, high = beta;
	Move remembered;
	if (x->table && best == NULL) {
		key = state_key(s);
		entry = &x->table[key & x->mask];
		if (entry->filled && entry->key == key) {
			if (entry->phases == phases && entry->steps >= steps) {
				if (entry->bound == BOUND_EXACT || (entry->bound == BOUND_LOWER && entry->value >= beta)
					|| (entry->bound == BOUND_UPPER && entry->value <= alpha)) {
					x->met++;
					return entry->value;
				}
			}
			if (!first && entry->kind >= 0) {
				remembered.kind = entry->kind;
				remembered.a = entry->a;
				remembered.b = entry->b;
				remembered.c = entry->c;
				first = &remembered;
			}
		}
	}
	if (phases <= 0 || steps <= 0) {
		int v = x->proof ? 0 : settle(x, s, phases);
		if (entry && !x->aborted) {
			entry->key = key;
			entry->value = v;
			entry->kind = -1;
			entry->phases = (int8_t)phases;
			entry->steps = (int8_t)steps;
			entry->bound = BOUND_EXACT;
			entry->filled = 1;
		}
		return v;
	}
	if (x->deadline > 0 && (x->nodes & 255) == 0 && now_ms() > x->deadline) x->budget = x->nodes;
	if (x->nodes >= x->budget) {
		x->aborted = 1;
		return x->proof ? 0 : settle(x, s, phases);
	}
	Move moves[MAX_MOVES];
	Plan plans[MAX_PLANS];
	int count = generate(x, s, moves, 1, 0, best != NULL, plans);
	/* Deeper in, only the most promising commands are played through, so that
	 * the search reaches far enough to see a whole turn. Ending the phase is
	 * always among them. */
	if (best == NULL && count > x->width) {
		moves[x->width - 1] = moves[count - 1];
		count = x->width;
	}
	/* What was best last time is tried first. */
	if (first)
		for (int i = 1; i < count; i++)
			if (same_move(&moves[i], first)) {
				Move m = moves[i];
				for (int j = i; j > 0; j--) moves[j] = moves[j - 1];
				moves[0] = m;
				break;
			}
	int side = s->phase == 0 ? s->attacker : 1 - s->attacker;
	int maximise = side == x->ai;
	/* Commands that already leave the board far worse than the best of them
	 * are not read at all. With hundreds to choose from, reading every one
	 * shallowly is worth less than reading the few that can matter deeply.
	 * Ending the phase is always kept, and so is the line held from before. */
	if (x->margin > 0 && steps >= 3 && count > 4) {
		int scores[MAX_MOVES], top = -2 * WIN;
		for (int i = 0; i < count; i++) {
			State t = *s;
			if (!apply_command(x, &t, (const int32_t *)&moves[i])) {
				scores[i] = -2 * WIN;
				continue;
			}
			int v = evaluate(x, &t, phases);
			scores[i] = maximise ? v : -v;
			if (scores[i] > top) top = scores[i];
		}
		int kept = 0;
		for (int i = 0; i < count; i++) {
			int spare = moves[i].kind == 0 || (first && same_move(&moves[i], first));
			if (!spare && scores[i] < top - x->margin) continue;
			moves[kept++] = moves[i];
		}
		if (kept > 0) count = kept;
	}
	int value = maximise ? -2 * WIN : 2 * WIN;
	int played = 0, chosen = -1;
	for (int i = 0; i < count; i++) {
		State t = *s;
		if (best && x->bans) {
			int set_aside = 0;
			for (int k = 0; k < x->bans && !set_aside; k++) set_aside = same_move(&moves[i], (const Move *)x->banned[k]);
			if (set_aside) continue;
		}
		if (moves[i].kind == 10) {
			if (!block_whole(x, &t, &plans[moves[i].a])) continue;
		} else if (!apply_command(x, &t, (const int32_t *)&moves[i])) continue;
		x->nodes++;
		played++;
		/* A turn ended with nobody sent has no defence to it, and counts for
		 * both of its phases: every line is read the same number of turns
		 * ahead, whether it attacks or not. */
		int spent = moves[i].kind != 0 ? 0 : (s->phase == 0 && t.phase == 0 && x->even) ? 2 : 1;
		int v = search_moves(x, &t, imax(0, phases - spent), steps - 1, alpha, beta, NULL, NULL,
			line ? below : NULL, line ? &below_length : NULL);
		if (maximise ? v > value : v < value) {
			value = v;
			chosen = i;
			if (best) *best = moves[i];
			if (line && line_length) {
				/* The line this command opens, for the caller to follow. */
				line[0] = moves[i];
				int kept = imin(below_length, MAX_LINE - 1);
				for (int k = 0; k < kept; k++) line[k + 1] = below[k];
				*line_length = kept + 1;
			}
		}
		if (maximise) {
			if (value > alpha) alpha = value;
		} else if (value < beta) beta = value;
		if (alpha >= beta) break;
	}
	if (!played) return x->proof ? 0 : settle(x, s, phases);
	if (entry && !x->aborted) {
		entry->key = key;
		entry->value = value;
		entry->kind = chosen >= 0 ? moves[chosen].kind : -1;
		entry->a = chosen >= 0 ? moves[chosen].a : 0;
		entry->b = chosen >= 0 ? moves[chosen].b : 0;
		entry->c = chosen >= 0 ? moves[chosen].c : 0;
		entry->phases = (int8_t)phases;
		entry->steps = (int8_t)steps;
		entry->bound = (int8_t)(value <= low ? BOUND_UPPER : value >= high ? BOUND_LOWER : BOUND_EXACT);
		entry->filled = 1;
	}
	return value;
}

/* Whether the engine's hero wins within `turns` of its own turns whatever
 * the other hero does: 0, or the turns it takes, with the command to give
 * now (when it is the one to move) and the line it opens. Every command of
 * both heroes is read - none is set aside as unpromising, and attacks and
 * defences are built a creature at a time - and a line that is still
 * undecided when its turns are up counts as not won, and so does one in
 * which chance has taken or dealt a card, so what this finds is a win and
 * not a hope of one. The fewest turns are tried first, from `from` on, and
 * one turn may take an eighth of `nodes`, what the whole may read, and two
 * a third, so that most is left for three and more. A number of turns
 * whose part runs out unsettled is left for the next: a win is far sooner
 * found than its absence shown, so the longer reading often ends where the
 * shorter could not. `settled` is the most turns read whole without a win,
 * and `cut` says whether a longer reading ran out. Where the other hero is
 * the one to move and no win is found, `best` is a command of that hero's
 * that holds out for the turns settled. */
static int prove_win(const Search *x, const State *s, int from, int turns, int64_t nodes, double deadline, Move *best, Move *line, int *line_length, int64_t *read, int *settled, int *cut) {
	Search p = *x;
	p.proof = 1;
	p.width = MAX_MOVES;
	p.margin = 0;
	p.sets = 0;
	p.plans = 0;
	p.ordered = 1;
	p.even = 1;
	p.blend = 0;
	/* Chance ends what is known of the cards to come, and with it the proof
	 * of any line that passes through it. */
	p.blinds = x->guarding ? x->blinds : 1;
	p.sight = x->sight;
	p.nodes = 0;
	nodes = imax(8, (int)imin64(nodes, 2000000000));
	p.deadline = deadline;
	p.met = 0;
	uint64_t size = 1u << 12;
	while (size < (uint64_t)nodes && size < (1u << 21)) size <<= 1;
	p.table = (Entry *)calloc((size_t)size, sizeof(Entry));
	p.mask = size - 1;
	int won = 0;
	*cut = 0;
	*settled = imax(0, from - 1);
	for (int n = imax(1, from); n <= turns && !won; n++) {
		/* Its own attack and the defence to it, and both phases of each of
		 * the other hero's turns between; from the other hero's turn, the
		 * rest of that one first. */
		int phases = (s->attacker == x->ai ? 4 * n - 2 : 4 * n) - (s->phase != 0 ? 1 : 0);
		State t = *s;
		t.rules = &p;
		if (p.nodes >= nodes || (deadline > 0 && now_ms() > deadline)) {
			*cut = 1;
			break;
		}
		p.budget = (int)imin64(nodes, imax(p.nodes + 1, n == 1 ? nodes / 8 : n == 2 ? nodes / 3 : nodes));
		Move found = { 0, 0, 0, 0 };
		Move read_line[MAX_LINE];
		int length = 0;
		p.aborted = 0;
		int v = search_moves(&p, &t, phases, MAX_COMMANDS, WIN - 1, WIN, &found, NULL, read_line, &length);
		if (p.aborted) {
			*cut = 1;
			continue;
		}
		/* Read whole: whatever was cut before it is settled with it. */
		*settled = n;
		*cut = 0;
		if (v >= WIN) {
			won = n;
			*best = found;
			*line_length = imin(length, MAX_LINE);
			for (int k = 0; k < *line_length; k++) line[k] = read_line[k];
		} else if ((s->phase == 0 ? s->attacker : 1 - s->attacker) != x->ai) {
			/* The other hero to move, and a command of its own that holds
			 * out for these turns. */
			*best = found;
		}
	}
	free(p.table);
	*read = p.nodes;
	return won;
}

static void read_card(const int32_t *r, Card *c) {
	c->cost = (int16_t)imax(-1, imin(r[0], 1000));
	c->none = (int8_t)(r[0] == -2);
	c->power = (int16_t)r[1];
	c->toughness = (int16_t)r[2];
	c->flags = (uint32_t)r[3] & 0x07ffffff;
	c->regeneration = (int8_t)imin(r[4], 100);
	c->ready_worth = r[5];
	c->resting_worth = r[6];
	c->race = (int8_t)(r[7] & 0x7f);
	c->effect = (int8_t)r[8];
	c->scope = (int8_t)r[9];
	c->amount = r[10];
	c->variable = (int8_t)(r[11] != 0);
	c->gives_power = (int16_t)r[12];
	c->gives_toughness = (int16_t)r[13];
	c->lends = (uint32_t)r[14] & 0x0fffffffu;
	c->holds = (int8_t)(r[15] > 0 ? ((r[15] & 256) ? 2 : 1) : 0);
	c->wake = (int8_t)(imax(0, r[15]) & 255);
	c->aim = (int8_t)r[16];
	c->own = (int8_t)((r[17] & 1) != 0);
	c->defence = (int8_t)((r[17] & 2) != 0);
	c->aura_flags = (uint32_t)r[18] & 0x07ffffff;
	c->aura_to = (uint8_t)(r[19] & 255);
	c->aura_own = (int8_t)((r[19] >> 8) & 1);
	c->tribe = (int8_t)((r[19] >> 9) & 3);
	c->pale = (int8_t)((r[19] >> 11) & 1);
	c->discards = (int8_t)((r[19] >> 12) & 7);
	c->rises = (int8_t)((r[19] >> 15) & 1);
	c->returns = (int8_t)((r[19] >> 16) & 1);
	c->kind = (int8_t)imax(0, imin(r[20], POOL));
	c->printed = (int16_t)imax(0, imin(r[21], 1000));
	c->channels = (int8_t)(r[22] & 15);
	c->choice = (int8_t)((r[22] >> 4) & 7);
	c->answers = (int8_t)((r[22] >> 7) & 3);
	c->klass = (int8_t)((r[22] >> 9) & 3);
	c->jams = (int8_t)((r[22] >> 11) & 3);
	c->fixed = (int8_t)((r[22] >> 13) & 1);
	c->comes_back = (int8_t)((r[22] >> 14) & 3);
	c->special = (int8_t)((r[22] >> 16) & 31);
	c->only = (int8_t)((r[22] >> 21) & 7);
	c->free = c->splash = 0;
	c->pale_bits = r[24] & 0xffff;
	c->code = (int16_t)imax(0, imin(r[23], 30000));
}

static int read_state(const int32_t *in, int64_t length, Search *x, State *s, int *phase, int *turns, int *develop_now) {
	if (length < FIXED || in[0] != 9) return 0;
	int n = in[11];
	if (n < 0 || n > MAX_UNITS || length < FIXED + (int64_t)n * UNIT_FIELDS) return 0;
	memset(s, 0, sizeof(*s));
	memset(x, 0, sizeof(*x));
	x->ai = in[1] & 1;
	s->attacker = in[2] & 1;
	*phase = in[3];
	*turns = imax(1, imin(in[4], MAX_TURNS));
	x->budget = imax(1, in[5]);
	x->edition = in[6];
	s->second = in[6] != 0;
	x->health_worth = in[7];
	x->foe_worth = in[14] > 0 ? in[14] : 100;
	x->width = imax(4, imin(in[10] > 1 ? in[10] : 16, MAX_MOVES));
	x->leaf_turns = imax(0, imin(in[20], MAX_TURNS));
	x->margin = in[21] > 0 ? in[21] : 0;
	x->fight_well = (in[22] & 1) != 0;
	x->blinds = (in[22] & 2) != 0;
	x->even = (in[22] & 4) != 0;
	x->ordered = (in[22] & 8) != 0;
	x->sets = (in[22] >> 8) & 15;
	x->plans = (in[22] >> 12) & 15;
	x->prove = (in[22] >> 16) & 15;
	x->prove_share = (in[22] >> 20) & 127;
	x->prove_from = (in[22] >> 27) & 15;
	x->sight = ((in[22] >> 4) & 15) * 25;
	x->guard = (in[31] >> 16) & 15;
	x->guard_share = (in[31] >> 20) & 127;
	x->bans = 0;
	x->guarding = 0;
	x->power_worth = in[23];
	x->guard_worth = in[24];
	x->tough_worth = in[25];
	x->leaf_attack = in[26] != 0;
	x->blend = imax(0, imin(in[27], 100));
	x->trim[0] = (uint32_t)in[29];
	x->trim[1] = (uint32_t)in[30];
	x->card_worth = in[18];
	x->channel_worth = in[19];
	s->phase = in[17] != 0;
	s->tax = imax(0, in[8]);
	s->rules = x;
	x->tax_price = imax(0, in[9]);
	x->wide = in[10] != 0;
	x->cards = in[12] != 0;
	*develop_now = in[13] != 0;
	s->n = n;
	const int32_t *at = in + HEADER;
	for (int side = 0; side < 2; side++, at += HERO_FIELDS) {
		s->health[side] = at[0];
		s->ether[side] = at[1];
		s->channels[side] = at[2];
		s->unknown[side] = imax(0, at[7]);
		x->chance_step[side] = imax(0, imin(at[8], 1000));
		s->chance[side] = imax(0, imin(at[9], 1000));
		for (int i = 0; i < MAX_TURNS; i++) x->income[side][i] = imax(0, at[10 + i]);
		s->extra[side] = imax(0, at[16]);
		s->held[side] = imax(0, at[17]);
		s->aura_worth[side] = at[18];
		x->maximum[side] = imax(1, at[19]);
		s->grave[side] = imax(0, at[20]);
		s->known[side] = (int8_t)imin(s->grave[side], GRAVES);
		for (int i = 0; i < s->known[side]; i++)
			s->graves[side][i] = (int8_t)imax(0, imin(at[HERO_SCALARS + HE_COUNT + HERO_ABILITIES + 1 + i], POOL));
		x->opening[side] = imax(0, at[21]);
		for (int i = 0; i < MAX_TURNS; i++) x->disturbance[side][i] = imax(0, at[23 + i]);
		s->forest[side] = imax(0, at[29]) - 1;
		s->forest_worth[side] = at[30];
		s->flight[side] = (int8_t)(at[31] != 0);
		x->deals[side][0] = imax(0, at[32]);
		x->deals[side][1] = imax(0, at[33]);
		x->loose[side] = imax(0, imin(at[38], 100));
		s->young[side] = (int8_t)imax(0, imin(at[34], 100));
		/* Told one more than it is: a stasis laid in the other hero's turn has yet to see less than none. */
		s->stasis_age[side] = (int8_t)(imax(0, imin(at[35], 100)) - 1);
		s->forest_price[side] = (int16_t)imax(0, imin(at[36], 1000));
		x->tax_worth = at[37];
		s->banner[side] = (int8_t)imax(0, imin(at[39] & 255, 100));
		if (s->banner[side] > 0 || !x->banner_price) x->banner_price = imax(0, imin(at[39] >> 8, 1000));
		for (int k = 0; k < HE_COUNT; k++) s->he[side][k] = (int8_t)imax(0, imin(at[HERO_SCALARS + k], 100));
		for (int k = 0; k < HERO_ABILITIES; k++) s->used[side][k] = (int8_t)imax(0, imin(at[HERO_SCALARS + HE_COUNT + k], 100));
		s->taxes[side] = imax(0, imin(at[HERO_SCALARS + HE_COUNT + HERO_ABILITIES], s->tax));
	}
	for (int side = 0; side < 2; side++)
		for (int cost = 0; cost < COSTS; cost++, at += TYPICAL_FIELDS) {
			Card *c = &x->typical[side][cost];
			memset(c, 0, sizeof(*c));
			c->cost = (int16_t)(at[0] + at[1] > 0 ? cost + 1 : -1);
			c->power = (int16_t)at[0];
			c->toughness = (int16_t)at[1];
			c->ready_worth = at[2];
			c->resting_worth = at[3];
			c->flags = F_SICK;
			c->effect = EFF_SUMMON;
		}
	/* The hand, then the cards that hero will draw, in the order it draws
	 * them: the engine plays with both heroes' cards open. */
	for (int side = 0; side < 2; side++) {
		for (int i = 0; i < SLOTS; i++, at += CARD_FIELDS) read_card(at, &x->hand[side][i]);
		x->dry[side] = x->hand[side][SLOTS - 1].none;
	}
	for (int k = 0; k < HE_COUNT; k++, at += HE_FIELDS) {
		Charm *c = &x->charm[k];
		c->each = at[0];
		c->kind = at[1];
		c->power = (int16_t)at[2];
		c->toughness = (int16_t)at[3];
		c->lethal = (int16_t)at[4];
		c->regeneration = (int16_t)at[5];
		c->flags = (uint32_t)at[6] & 0x00ffffffu;
		c->expires = (int8_t)(at[7] != 0);
		c->cost = (int8_t)imax(0, imin(at[8], 100));
		c->amount = (int8_t)imax(0, imin(at[9], 100));
		c->reach = (int8_t)imax(0, imin(at[10], 2));
		c->price = (int16_t)imax(0, imin(at[11], 1000));
		c->fixed = (int8_t)imax(0, imin(at[12], 2));
		c->code = (int16_t)imax(0, imin(at[13], 30000));
	}
	/* The creature cards known by kind. */
	memset(x->jammers, 0, sizeof(x->jammers));
	for (int k = 0; k < POOL; k++, at += CARD_FIELDS) {
		read_card(at, &x->pool[k]);
		if (x->pool[k].jams > 0 && x->pool[k].cost >= 0) x->jammers[x->pool[k].jams - 1] = (int8_t)(k + 1);
	}
	/* What the heroes carry. */
	x->serial = imax(0, imin(at[0], 100000));
	x->later = s->second ? imax(0, imin(at[1], 100000)) : 0;
	at += 2;
	for (int side = 0; side < 2; side++) {
		x->art_limit[side] = imax(0, imin(at[0], 100));
		s->art_used[side] = (int8_t)imax(0, imin(at[1], 100));
		at += 2;
		for (int k = 0; k < MAX_ART; k++, at += ART_FIELDS) {
			Card *c = &x->art[side][k];
			const int32_t *more = at + CARD_FIELDS;
			read_card(at, c);
			s->art_left[side][k] = (int8_t)imax(0, imin(more[0], 100));
			s->art_ready[side][k] = (int16_t)imax(0, imin(more[1], 30000));
			x->art_gap[side][k] = (int8_t)imax(0, imin(more[2], 100));
			x->art_phase[side][k] = (int8_t)(more[3] & 3);
			c->free = (int8_t)((more[3] >> 2) & 3);
			c->splash = (int8_t)imax(0, imin(more[4], 100));
			/* A spell whose strength is poured into it is never one of these. */
			if (c->variable) c->free = 0;
		}
	}
	for (int klass = 1; klass < 4; klass++) {
		x->wards[klass][0] = s->he[0][WARD_LESSER[klass]] + s->he[1][WARD_LESSER[klass]];
		x->wards[klass][1] = s->he[0][WARD_GREATER[klass]] + s->he[1][WARD_GREATER[klass]];
	}
	for (int i = 0; i < n; i++) {
		const int32_t *r = at + i * UNIT_FIELDS;
		Unit *u = &s->u[i];
		u->id = r[0];
		u->owner = (int8_t)(r[1] & 1);
		u->power = (int16_t)r[2];
		u->toughness = (int16_t)r[3];
		u->flags = (uint32_t)r[4] & 0x0fffffffu;
		u->regeneration = (int8_t)imin(r[5], 100);
		u->skins = (int8_t)imin(r[6], 100);
		u->guards = (int8_t)imin(r[7], 100);
		u->ready_worth = r[8];
		u->resting_worth = r[9];
		u->race = (int8_t)(r[10] & 0x7f);
		u->blocks = -1;
		u->wake = (int8_t)imax(0, imin(r[12], 100));
		u->damage = (int16_t)imax(0, r[13]);
		u->leaders = (uint32_t)r[14];
		u->gives_power = (int16_t)(r[15] >> 8);
		u->gives_toughness = (int16_t)(r[15] & 0xff);
		u->upkeep = (int16_t)imax(0, r[16]);
		u->shielded = (int8_t)(r[17] != 0);
		u->wake_hurts = (int8_t)(r[18] != 0);
		u->cost = (int16_t)imax(0, imin(r[19], 1000));
		u->twisted = (int8_t)imax(0, imin(r[20], 100));
		u->horror = (int8_t)(r[21] & 1);
		u->mourned = (int8_t)((r[21] >> 1) & 1);
		u->feeds = (int8_t)((r[21] >> 2) & 1);
		u->envenoms = (int8_t)((r[21] >> 3) & 1);
		u->barriers = (int8_t)imax(0, imin(r[62], 100));
		u->alpha = (int8_t)(r[63] & 127);
		u->pale_bits = r[64] & 0xffff;
		u->pale_used = (int8_t)(r[65] & 3);
		u->kin = (int8_t)imax(0, imin((r[65] >> 8) & 255, 100));
		u->spared = (int8_t)imax(0, imin((r[65] >> 16) & 255, 100));
		if (u->kin) s->kinned = 1;
		u->ability = (int8_t)imax(0, imin(r[22], 63));
		u->ability_cost = (int8_t)imax(0, imin(r[23], 100));
		u->ability_amount = (int8_t)imax(0, imin(r[24], 127));
		u->ability_traits = (int8_t)(r[25] & 15);
		u->lent = (uint32_t)r[26] & 0x00ffffffu;
		u->overload = (int8_t)imax(0, imin(r[27], 100));
		u->worn = (int8_t)imax(0, imin(r[28], 100));
		u->worn_power = (int16_t)r[29];
		u->worn_health = (int16_t)r[30];
		u->worn_flags = (uint32_t)r[31] & 0x0fffffffu & ~(uint32_t)(F_RESTING | F_SICK | F_PLANE | F_ATTACKING | F_HIT | F_DISSIPATES);
		u->bare_regeneration = (int8_t)imax(0, imin(r[32], 100));
		u->fate = (int8_t)(r[33] & 15);
		u->bare_shielded = (int8_t)((r[33] >> 4) & 1);
		u->bare_wake = (int8_t)((r[33] >> 8) & 127);
		u->bare_ability = (int8_t)((r[33] >> 16) & 63);
		u->home = (int8_t)imax(0, imin(r[34], 2));
		u->worn_ready = r[35];
		u->worn_resting = r[36];
		u->gives_flags = (uint32_t)r[38] & 0x07ffffff;
		u->gives_to = (uint8_t)(r[39] & 255);
		u->gives_own = (int8_t)((r[39] >> 8) & 1);
		u->aura_flags = (uint32_t)r[40] & 0x07ffffff;
		u->tribe = (int8_t)(r[41] & 3);
		u->linked = (int8_t)imax(0, imin(r[42], 100));
		u->pale = (int8_t)(r[43] & 1);
		/* One that regenerated while the other hero moved. */
		if (r[43] & 2) u->flags |= F_REGENERATED;
		u->under = (int16_t)imax(0, imin(r[51], 100));
		u->kind = (int8_t)imax(0, imin(r[59], POOL));
		u->worn_discards = (int8_t)imax(0, imin(r[60], u->discards));
		u->passing = (int8_t)imax(0, imin(r[53], 100));
		u->passing_power = (int16_t)r[54];
		u->passing_health = (int16_t)r[55];
		u->passing_flags = (uint32_t)r[56] & 0x0fffffffu & ~(uint32_t)(F_RESTING | F_SICK | F_PLANE | F_ATTACKING | F_HIT | F_DISSIPATES);
		u->passing_ready = r[57];
		u->passing_resting = r[58];
		u->discards = (int8_t)imax(0, imin(r[50], 100));
		u->spent = (int8_t)(r[61] != 0);
		u->brief = (int8_t)imax(0, imin(r[44], 100));
		u->brief_power = (int16_t)r[45];
		u->brief_health = (int16_t)r[46];
		u->brief_flags = (uint32_t)r[47] & u->worn_flags;
		/* What lasts a turn is worth half of what lasts. */
		u->brief_ready = r[48] - r[48] / 2;
		u->brief_resting = r[49] - r[49] / 2;
		u->ready_worth -= r[48] / 2;
		u->resting_worth -= r[49] / 2;
		u->worn_ready -= r[48] / 2;
		u->worn_resting -= r[49] / 2;
		u->rank = (uint8_t)imax(0, imin(r[37], 250));
		if (u->rank > s->ranks) s->ranks = u->rank;
		/* What stands on its hero has already taken its points past the floor. */
		if (!(u->flags & (F_NO_AFFECT | F_PLANE)))
			for (int k = 0; k < HE_COUNT; k++) u->lethal = (int16_t)(u->lethal + s->he[u->owner][k] * x->charm[k].lethal);
		/* Health shows no less than one: what is added counts from where it really is. */
		u->raw = (int16_t)(u->toughness + u->lethal - imax(0, imin(r[52], 100)));
		/* Under an alpha strike its health is told as it would be without. */
		if (u->alpha) u->raw = (int16_t)(imax(0, imin(r[63] >> 8, 1000)) + u->lethal);
	}
	/* Blocks already made name their attacker by id. */
	for (int i = 0; i < n; i++) {
		int32_t wanted = at[i * UNIT_FIELDS + 11];
		if (wanted < 0) continue;
		for (int j = 0; j < n; j++)
			if (s->u[j].id == wanted) s->u[i].blocks = (int8_t)j;
	}
	/* The enchantments on the creatures, each by itself, in the order they
	 * were laid. */
	int worn = imax(0, imin(in[15], 1000));
	if (length < FIXED + (int64_t)n * UNIT_FIELDS + (int64_t)worn * ENCH_FIELDS) return 0;
	for (int i = 0; i < imin(worn, MAX_ENCH); i++) {
		const int32_t *r = in + FIXED + (int64_t)n * UNIT_FIELDS + (int64_t)i * ENCH_FIELDS;
		if (r[0] < 0 || r[0] >= n) continue;
		Ench *e = &s->ench[s->enchs++];
		e->unit = (int8_t)r[0];
		e->caster = (int8_t)(r[1] & 1);
		e->kind = (int8_t)imax(0, imin(r[2], EN_GIFT));
		e->code = (int16_t)imax(0, imin(r[3], 30000));
		e->price = (int16_t)imax(0, imin(r[4], 1000));
		e->power = (int16_t)r[5];
		e->health = (int16_t)r[6];
		e->lethal = (int16_t)r[7];
		e->flags = (uint32_t)r[8] & 0x0fffffffu & ~(uint32_t)(F_RESTING | F_SICK | F_PLANE | F_ATTACKING | F_HIT | F_DISSIPATES);
		e->ready = r[9];
		e->resting = r[10];
		e->brief = (int8_t)(r[11] & 1);
		e->comes_back = (int8_t)((r[11] >> 1) & 3);
		e->robs = (int8_t)((r[11] >> 3) & 7);
		e->fixed = (int8_t)((r[11] >> 6) & 1);
		e->shields = (int8_t)((r[11] >> 7) & 1);
		e->mutes = (int8_t)((r[11] >> 8) & 1);
		e->tick = (int8_t)((r[11] >> 9) & 3);
		e->regen = (int8_t)imax(0, imin(r[12], 101));
	}
	return 1;
}

/* Fills `out` (room for 8 + 3 * MAX_UNITS integers); returns its length. */
static int run_search(const int32_t *in, int64_t length, int32_t *out) {
	Search x;
	State s;
	int phase, turns, develop_now;
	memset(out, 0, sizeof(int32_t) * 5);
	if (!read_state(in, length, &x, &s, &phase, &turns, &develop_now)) return 5;
	if (phase == 8) {
		/* Every command the side to move may give, each played out to the end
		 * of the duel as often as the budget allows. The answer is simply how
		 * often each one won. */
		Move moves[MAX_MOVES];
		int count = generate(&x, &s, moves, 1, 0, 1, NULL);
		int rounds = imax(2, imin(in[16], 40));
		/* A win or loss that can be read is read, not sampled: a tenth of the
		 * budget goes to the plain search first, and a forced win is taken.
		 * Sampling finds such a line only by luck. */
		{
			int64_t whole = x.budget;
			Move tactical;
			tactical.kind = 0;
			tactical.a = 0;
			tactical.b = 0;
			tactical.c = 0;
			x.budget = x.nodes + whole / 10;
			int v = search_moves(&x, &s, 2, 8, -2 * WIN, 2 * WIN, &tactical, NULL, NULL, NULL);
			x.budget = whole;
			if (v >= WIN) {
				out[0] = 1;
				out[1] = tactical.kind;
				out[2] = tactical.a;
				out[3] = tactical.b;
				out[4] = tactical.c;
				out[5] = 1000;
				out[6] = 1;
				return 7;
			}
		}
		uint32_t seed = (uint32_t)(in[5] * 2654435761u + 1u);
		int said = 0;
		int32_t score[MAX_MOVES], played[MAX_MOVES];
		State after[MAX_MOVES];
		int kinds[MAX_MOVES];
		/* Only the most promising commands are played out: the budget buys far
		 * more games each, and a game tells little until there are many. */
		int room = imin(count, imax(4, x.width));
		for (int i = 0; i < room && said < 40; i++) {
			State t = s;
			if (!apply_command(&x, &t, (const int32_t *)&moves[i])) continue;
			after[said] = t;
			kinds[said] = i;
			score[said] = 0;
			played[said] = 0;
			said++;
		}
		/* Sequential halving: every command is tried, the weaker half is set
		 * aside, and the games saved go to the rest. A hundred games apiece
		 * cannot tell twenty commands apart, while a thousand can tell two.
		 * The passes repeat while the budget holds, so no command is dropped
		 * for good on the strength of a few games. */
		int alive[MAX_MOVES];
		for (int i = 0; i < said; i++) alive[i] = i;
		int living = said;
		while (x.nodes < x.budget) {
			int passes = 1;
			for (int n = living; n > 1; n /= 2) passes++;
			int each = imax(4, (int)((x.budget - x.nodes) / (int64_t)imax(1, living * passes * 160)));
			while (x.nodes < x.budget) {
				for (int k = 0; k < living && x.nodes < x.budget; k++) {
					int i = alive[k];
					for (int g = 0; g < each && x.nodes < x.budget; g++) {
						score[i] += play_out(&x, &after[i], &seed, rounds);
						played[i]++;
					}
				}
				if (living <= 1) break;
				/* The better half goes on. */
				for (int a = 1; a < living; a++) {
					int keep = alive[a], b = a - 1;
					while (b >= 0 && (int64_t)score[alive[b]] * played[keep] < (int64_t)score[keep] * played[alive[b]]) {
						alive[b + 1] = alive[b];
						b--;
					}
					alive[b + 1] = keep;
				}
				living /= 2;
			}
			living = said;
		}
		out[0] = said;
		for (int i = 0; i < said; i++) {
			const Move *m = &moves[kinds[i]];
			out[1 + i * 6] = m->kind;
			out[1 + i * 6 + 1] = m->a;
			out[1 + i * 6 + 2] = m->b;
			out[1 + i * 6 + 3] = m->c;
			out[1 + i * 6 + 4] = score[i];
			out[1 + i * 6 + 5] = played[i];
		}
		return 1 + said * 6;
	}
	if (phase == 9) {
		/* Only whether the engine's hero wins whatever the other does, within
		 * so many of its own turns. */
		Move best = { 0, 0, 0, 0 }, line[MAX_LINE];
		int line_length = 0, cut = 0, settled = 0;
		int64_t read = 0;
		/* Each number of turns may take the whole budget here, and the first
		 * left unsettled ends it: the answer is the fewest turns. */
		int won = 0;
		for (int n = 1; n <= imin(turns, 15) && !won && !cut; n++) {
			int64_t part = 0;
			won = prove_win(&x, &s, n, n, x.budget, 0, &best, line, &line_length, &part, &settled, &cut);
			read += part;
		}
		out[0] = won;
		out[1] = best.kind;
		out[2] = best.a;
		out[3] = best.b;
		out[4] = best.c;
		out[5] = (int32_t)imin64(read, 2000000000);
		out[6] = cut;
		/* The line that wins, for whoever asks to see it. */
		out[7] = won ? line_length : 0;
		for (int k = 0; k < out[7]; k++) {
			out[8 + k * 4] = line[k].kind;
			out[9 + k * 4] = line[k].a;
			out[10 + k * 4] = line[k].b;
			out[11 + k * 4] = line[k].c;
		}
		return 8 + out[7] * 4;
	}
	if (phase == 7) {
		/* Every command the side to move may give, with what this engine
		 * makes of it: for holding its reckoning against the search's. */
		Move moves[MAX_MOVES];
		int count = generate(&x, &s, moves, 1, 0, 1, NULL);
		int steps = imax(2, imin(in[16], MAX_COMMANDS));
		int said = 0;
		for (int i = 0; i < count && said < 40; i++) {
			State t = s;
			if (!apply_command(&x, &t, (const int32_t *)&moves[i])) continue;
			int v = search_moves(&x, &t, imax(1, turns), steps - 1, -2 * WIN, 2 * WIN, NULL, NULL, NULL, NULL);
			out[1 + said * 5] = moves[i].kind;
			out[1 + said * 5 + 1] = moves[i].a;
			out[1 + said * 5 + 2] = moves[i].b;
			out[1 + said * 5 + 3] = moves[i].c;
			out[1 + said * 5 + 4] = v;
			said++;
		}
		out[0] = said;
		return 1 + said * 5;
	}
	if (phase == 6) {
		/* What this engine makes of the position, for holding its reckoning
		 * against the search's own. */
		out[0] = evaluate(&x, &s, 0);
		out[1] = evaluate_leaf(&x, &s, 0);
		return 2;
	}
	if (phase == 5) {
		/* The command the rules themselves say is best, searched here. */
		Move best, kept[MAX_LINE];
		int kept_length = 0;
		int64_t proved = 0;
		best.kind = 0;
		best.a = 0;
		best.b = 0;
		best.c = 0;
		int steps = imax(2, imin(in[16], MAX_COMMANDS));
		double began = in[28] > 0 ? now_ms() : 0;
		/* A win that cannot be stopped is looked for first, and taken. */
		int settled = 0, cut = 0;
		if (x.prove > 0 && x.prove_from <= x.prove) {
			Move line[MAX_LINE];
			int line_length = 0;
			int64_t read = 0;
			int share = x.prove_share > 0 ? x.prove_share : 50;
			double until = in[28] > 0 ? began + (double)in[28] * share / 100.0 : 0;
			int won = prove_win(&x, &s, x.prove_from, x.prove, x.budget * share / 100, until, &best, line, &line_length, &read, &settled, &cut);
			if (won) {
				out[0] = WIN / 1000 * 1000 + (MAX_TURNS - imin(won, MAX_TURNS)) * 1000;
				out[1] = best.kind;
				out[2] = best.a;
				out[3] = best.b;
				out[4] = best.c;
				out[5] = (int32_t)imin64(read, 2000000000);
				out[6] = 0;
				out[7] = steps + (((s.attacker == x.ai ? 4 * won - 2 : 4 * won) - (s.phase != 0 ? 1 : 0)) << 8) + (won << 16);
				out[8] = line_length;
				for (int k = 0; k < line_length; k++) {
					out[9 + k * 4] = line[k].kind;
					out[9 + k * 4 + 1] = line[k].a;
					out[9 + k * 4 + 2] = line[k].b;
					out[9 + k * 4 + 3] = line[k].c;
				}
				return 9 + line_length * 4;
			}
			proved = read;
		}
		/* Positions already read are kept through the whole search, a table
		 * about as large as the search is allowed to grow. */
		if (in[28] > 0) x.deadline = began + (double)in[28];
		if (in[22] & 1) {
			uint64_t size = 1u << 12;
			while (size < (uint64_t)x.budget && size < (1u << 20)) size <<= 1;
			x.table = (Entry *)calloc((size_t)size, sizeof(Entry));
			x.mask = size - 1;
		}
		/* A command deeper each pass while the budget holds, keeping the last
		 * whole answer rather than half of a deeper one. */
		int value = 0, reached = 0;
		for (int depth = 1; depth <= steps; depth++) {
			Move found = best;
			x.aborted = 0;
			Move line[MAX_LINE];
			int line_length = 0;
			int v = search_moves(&x, &s, imax(1, turns), depth, -2 * WIN, 2 * WIN, &found, reached ? &best : NULL, line, &line_length);
			if (x.aborted && reached) break;
			best = found;
			value = v;
			reached = depth;
			kept_length = imin(line_length, MAX_LINE);
			for (int k = 0; k < kept_length; k++) kept[k] = line[k];
			if (x.nodes >= x.budget) break;
		}
		/* With most of the budget still unspent the position is a small one,
		 * and it is read again a whole turn of each hero further, and again:
		 * a win or a loss that lies past the usual reach is found this way.
		 * A further reading counts only when it was read whole. */
		int spare = imax(1, (in[31] >> 8) & 127);
		for (int phases = imax(1, turns) + 2; phases <= imin(in[31] & 255, 12); phases += 2) {
			if (reached < steps || x.aborted || x.nodes * spare >= x.budget || value >= WIN || value <= -WIN) break;
			Move found = best;
			Move line[MAX_LINE];
			int line_length = 0;
			/* As many commands to a phase as the first reading had: a line cut
			 * short by its count of commands, not by its phases, ends in the
			 * middle of a turn, and lines of unlike length are then weighed
			 * at unlike moments. */
			int further = imin(MAX_COMMANDS, steps * phases / imax(1, turns));
			int v = search_moves(&x, &s, phases, further, -2 * WIN, 2 * WIN, &found, &best, line, &line_length);
			if (x.aborted) {
				x.aborted = 0;
				break;
			}
			best = found;
			value = v;
			kept_length = imin(line_length, MAX_LINE);
			for (int k = 0; k < kept_length; k++) kept[k] = line[k];
			x.far = phases;
		}
		/* The command chosen is held against a reading of every command of
		 * both heroes: one after which the other hero wins whatever is done,
		 * within `guard` of its turns, is set aside and the choice made again
		 * among the rest, while there is one that reading does not condemn.
		 * The usual reading keeps to the likeliest commands of a crowded
		 * board and to so many commands a line, and a loss can hide past
		 * either - or a way out of one, where that reading sees none: then
		 * the command that holds out longest is the one given. */
		int guarded = 0;
		if (x.guard > 0 && value < WIN && best.kind < 9) {
			Search g = x;
			g.ai = 1 - x.ai;
			g.table = NULL;
			g.bans = 0;
			g.guarding = 1;
			int64_t part = imax(1000, (int)(x.budget * imax(1, x.guard_share) / 100));
			int read_phases = x.far > 0 ? x.far : imax(1, turns);
			int read_steps = x.far > 0 ? imin(MAX_COMMANDS, steps * x.far / imax(1, turns)) : imax(1, reached);
			double until = in[28] > 0 ? began + (double)in[28] * 3 / 2 : 0;
			Move answer = { 0, 0, 0, 0 }, answers[MAX_LINE];
			int answers_length = 0, whole = 0, ran_out = 0, lost = 0;
			int64_t read = 0;
			State t = s;
			if (apply_command(&x, &t, (const int32_t *)&best) && t.health[0] > 0 && t.health[1] > 0) {
				lost = prove_win(&g, &t, 1, x.guard, part, until, &answer, answers, &answers_length, &read, &whole, &ran_out);
				proved += read;
			}
			if (lost) {
				/* How long the other hero needs whatever is done here, and a
				 * command that holds out: for good, as far as was read, or
				 * at least longer than the one chosen. */
				Move escape = { -1, 0, 0, 0 };
				int doomed = prove_win(&g, &s, 1, x.guard, part * 2, until, &escape, answers, &answers_length, &read, &whole, &ran_out);
				proved += read;
				int holds = doomed ? 0 : whole;
				if (doomed > lost) {
					escape.kind = -1;
					int sooner = prove_win(&g, &s, 1, doomed - 1, part, until, &escape, answers, &answers_length, &read, &whole, &ran_out);
					proved += read;
					holds = sooner ? 0 : whole;
				}
				guarded = 15;
				if (holds >= lost && escape.kind >= 0) {
					/* The choice is made again without what was condemned, and
					 * what it then prefers is held against the same reading;
					 * failing that, the command known to hold out is given. */
					Move tried = best;
					guarded = 14;
					for (int attempt = 0; attempt < 3 && guarded == 14; attempt++) {
						memcpy(x.banned[x.bans++], &tried, sizeof(Move));
						Move found = { -1, 0, 0, 0 };
						Move line[MAX_LINE];
						int line_length = 0;
						int64_t allowed = x.budget;
						x.aborted = 0;
						x.budget = x.nodes + part;
						x.deadline = until;
						int v = search_moves(&x, &s, read_phases, read_steps, -2 * WIN, 2 * WIN, &found, NULL, line, &line_length);
						x.budget = allowed;
						x.aborted = 0;
						if (found.kind < 0) break;
						tried = found;
						State u = s;
						if (!apply_command(&x, &u, (const int32_t *)&found)) continue;
						int bad = u.health[x.ai] <= 0;
						if (!bad && u.health[1 - x.ai] > 0) {
							bad = prove_win(&g, &u, 1, holds, part, until, &answer, answers, &answers_length, &read, &whole, &ran_out) > 0 || ran_out;
							proved += read;
						}
						if (bad) continue;
						best = found;
						value = v;
						kept_length = imin(line_length, MAX_LINE);
						for (int k = 0; k < kept_length; k++) kept[k] = line[k];
						guarded = attempt + 1;
					}
					x.bans = 0;
					if (guarded == 14) {
						best = escape;
						kept[0] = escape;
						kept_length = 1;
					}
				}
			}
		}
		/* The line past its first command is read back out of the table,
		 * where a position met again cut the reading short. */
		if (x.table && kept_length >= 1 && kept_length < MAX_LINE) {
			State t = s;
			int whole = 1;
			for (int k = 0; k < kept_length && whole; k++) whole = apply_command(&x, &t, (const int32_t *)&kept[k]);
			while (whole && kept_length < MAX_LINE && t.health[0] > 0 && t.health[1] > 0) {
				uint64_t key = state_key(&t);
				const Entry *entry = &x.table[key & x.mask];
				if (!entry->filled || entry->key != key || entry->kind < 0) break;
				Move next;
				next.kind = entry->kind;
				next.a = entry->a;
				next.b = entry->b;
				next.c = entry->c;
				if (!apply_command(&x, &t, (const int32_t *)&next)) break;
				kept[kept_length++] = next;
			}
		}
		free(x.table);
		x.table = NULL;
		/* A whole defence is handed over as the blocks it is made of. */
		if (best.kind == 10) {
			Plan plans[MAX_PLANS];
			int8_t base[MAX_UNITS];
			memset(base, -1, sizeof(base));
			for (int i = 0; i < s.n; i++) base[i] = s.u[i].blocks;
			int found = block_plans(&x, &s, base, plans, MAX_PLANS, 1);
			kept_length = 0;
			if (best.a >= 0 && best.a < found)
				for (int i = 0; i < s.n && kept_length < MAX_LINE; i++) {
					if (plans[best.a].target[i] < 0 || base[i] >= 0) continue;
					kept[kept_length].kind = 2;
					kept[kept_length].a = i;
					kept[kept_length].b = plans[best.a].target[i];
					kept[kept_length].c = 0;
					kept_length++;
				}
			if (kept_length > 0) best = kept[0];
			else {
				best.kind = 0;
				best.a = 0;
				best.b = 0;
				best.c = 0;
			}
		}
		out[0] = value;
		out[1] = best.kind;
		out[2] = best.a;
		out[3] = best.b;
		out[4] = best.c;
		out[5] = (int32_t)imin64(x.nodes + proved, 2000000000);
		out[6] = x.aborted;
		out[7] = reached + (x.far << 8) + (settled << 20) + (cut << 24) + (guarded << 25);
		out[8] = kept_length;
		for (int k = 0; k < kept_length; k++) {
			out[9 + k * 4] = kept[k].kind;
			out[9 + k * 4 + 1] = kept[k].a;
			out[9 + k * 4 + 2] = kept[k].b;
			out[9 + k * 4 + 3] = kept[k].c;
		}
		return 9 + kept_length * 4;
	}
	if (phase == 2 || phase == 3 || phase == 4) {
		/* The fight, the turn's end, or a list of commands played out: all
		 * three for holding these rules against the game's own. */
		if (phase == 4) {
			int wanted = imax(0, imin(in[16], MAX_COMMANDS));
			int64_t before = FIXED + (int64_t)s.n * UNIT_FIELDS + (int64_t)imax(0, imin(in[15], 1000)) * ENCH_FIELDS;
			const int32_t *cmd = in + before;
			if (length >= before + (int64_t)wanted * 4)
				for (int i = 0; i < wanted; i++) out[0] += apply_command(&x, &s, cmd + (int64_t)i * 4);
		} else if (phase == 2) {
			int8_t t[MAX_UNITS];
			for (int i = 0; i < s.n; i++) t[i] = s.u[i].blocks;
			resolve(&s, t);
		} else {
			end_turn(&x, &s);
		}
		out[1] = s.health[0];
		out[2] = s.health[1];
		out[3] = s.ether[0];
		out[4] = s.ether[1];
		out[5] = s.channels[0];
		out[6] = s.channels[1];
		out[7] = s.attacker;
		out[8] = s.phase;
		int said = 0;
		for (int i = 0; i < s.n; i++) {
			out[9 + said++] = s.u[i].id;
			out[9 + said++] = (s.u[i].flags & F_DEAD) ? -1 : s.u[i].damage;
			out[9 + said++] = (s.u[i].flags & F_RESTING) ? 1 : 0;
			out[9 + said++] = s.u[i].blocks >= 0 && s.u[i].blocks < s.n ? s.u[s.u[i].blocks].id : -1;
		}
		/* Last, what else the two sets of rules can be held against each
		 * other by: the cards in each hand and in each graveyard, and the
		 * creatures of each army. */
		out[9 + said++] = -1000000;
		out[9 + said++] = cards_held(&s, 0) | (cards_held(&s, 1) << 8);
		out[9 + said++] = s.grave[0] | (s.grave[1] << 8);
		{
			int armies[2] = {0, 0};
			for (int i = 0; i < s.n; i++)
				if (!(s.u[i].flags & F_DEAD)) armies[s.u[i].owner]++;
			out[9 + said++] = armies[0] | (armies[1] << 8);
		}
		return 9 + said;
	}
	int root = evaluate(&x, &s, 0);
	int own = s.n;
	if (develop_now && phase == 0) develop(&x, &s, s.attacker);
	int8_t base[MAX_UNITS], plan[MAX_UNITS], kept_plan[MAX_UNITS];
	memset(base, -1, sizeof(base));
	for (int i = 0; i < s.n; i++) base[i] = s.u[i].blocks;
	memcpy(kept_plan, base, sizeof(base));
	uint32_t set = 0, kept_set = 0;
	for (int i = 0; i < s.n; i++)
		if (s.u[i].flags & F_ATTACKING) kept_set |= 1u << i;
	int value = root, searched = 0;
	/* Deeper each time while the budget lasts; a cut-short pass is dropped. */
	for (int depth = x.wide ? 1 : turns; depth <= turns; depth++) {
		x.aborted = 0;
		int v;
		memcpy(plan, base, sizeof(base));
		set = kept_set;
		if (phase == 1) v = search_blocks(&x, &s, base, depth, 0, -2 * WIN, 2 * WIN, plan);
		else v = search_turn(&x, &s, depth, 0, -2 * WIN, 2 * WIN, &set);
		if (x.aborted && searched > 0) break;
		value = v;
		searched = depth;
		kept_set = set;
		memcpy(kept_plan, plan, sizeof(plan));
		if (x.nodes >= x.budget) break;
	}
	out[0] = value >= WIN ? 1 : (value <= -WIN ? -1 : 0);
	if (out[0] != 0) {
		/* The turn that decides it: a sooner end is worth a thousand more. */
		int left = ((value > 0 ? value : -value) - WIN) / 1000;
		out[1] = imax(1, searched - left + 1);
	} else {
		out[1] = value - root;
	}
	out[2] = (int32_t)x.nodes;
	out[3] = searched;
	int count = 0;
	if (phase == 1) {
		for (int i = 0; i < own; i++) {
			if (kept_plan[i] < 0 || base[i] >= 0) continue;
			out[5 + count++] = s.u[i].id;
			out[5 + count++] = s.u[(int)kept_plan[i]].id;
		}
	} else {
		for (int i = 0; i < own; i++)
			if (kept_set >> i & 1) out[5 + count++] = s.u[i].id;
	}
	out[4] = count;
	return 5 + count;
}

/* ------------------------------------------------------------ Godot binding */

static GDExtensionInterfaceGetProcAddress get_proc;
static GDExtensionClassLibraryPtr library;

static GDExtensionInterfaceVariantGetType variant_get_type;
static GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst pba_index_const;
static GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new;
static GDExtensionInterfaceStringNewWithLatin1Chars string_new;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionPtrConstructor pba_new;
static GDExtensionPtrDestructor pba_free, string_name_free, string_free;
static GDExtensionPtrBuiltInMethod pba_size, pba_resize;
static GDExtensionTypeFromVariantConstructorFunc pba_from_variant;
static GDExtensionVariantFromTypeConstructorFunc variant_from_pba;

/* Opaque storage for builtin types (64-bit builds: PackedByteArray 16 bytes,
 * StringName and String 8). */
typedef struct { _Alignas(8) uint8_t data[16]; } PackedBytes;
typedef struct { _Alignas(8) uint8_t data[8]; } Name;
typedef struct { _Alignas(8) uint8_t data[8]; } Text;

/* Replaces `result` (uninitialised) with the search's answer for `state`. */
static void native_search(PackedBytes *state, PackedBytes *result) {
	int32_t out[1 + 40 * 6 + 4 * MAX_UNITS + 16];
	int64_t bytes = 0;
	pba_size(state, NULL, &bytes, 0);
	int32_t *in = NULL;
	int64_t length = bytes / 4;
	int count = 5;
	memset(out, 0, sizeof(out));
	if (length > 0) {
		/* The array's storage is not promised to be aligned for integers. */
		in = (int32_t *)malloc((size_t)length * 4);
		if (in) {
			memcpy(in, pba_index_const(state, 0), (size_t)length * 4);
			count = run_search(in, length, out);
			free(in);
		}
	}
	pba_new(result, NULL);
	int64_t want = (int64_t)count * 4, err = 0;
	const GDExtensionConstTypePtr resize_args[1] = { &want };
	pba_resize(result, resize_args, &err, 1);
	if (err == 0) memcpy(pba_index(result, 0), out, (size_t)want);
}

static void ptrcall(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	(void)method;
	(void)instance;
	/* `ret` holds a constructed PackedByteArray: replace it. */
	pba_free(ret);
	native_search((PackedBytes *)args[0], (PackedBytes *)ret);
}

static void call(void *method, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt count, GDExtensionVariantPtr ret, GDExtensionCallError *error) {
	(void)method;
	(void)instance;
	error->error = GDEXTENSION_CALL_OK;
	if (count != 1) {
		error->error = count < 1 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		error->expected = 1;
		return;
	}
	if (variant_get_type(args[0]) != GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY) {
		error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
		error->argument = 0;
		error->expected = GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY;
		return;
	}
	PackedBytes state, out;
	pba_from_variant(&state, (GDExtensionVariantPtr)args[0]);
	native_search(&state, &out);
	pba_free(&state);
	variant_from_pba(ret, &out);
	pba_free(&out);
}

static Name class_name, parent_name, empty_name;
static Text empty_text;

static GDExtensionPropertyInfo info(GDExtensionVariantType type, Name *name) {
	GDExtensionPropertyInfo p;
	p.type = type;
	p.name = name;
	p.class_name = &empty_name;
	p.hint = 0;
	p.hint_string = &empty_text;
	p.usage = 6; /* PROPERTY_USAGE_DEFAULT */
	return p;
}

static void free_instance(void *userdata, GDExtensionClassInstancePtr instance) {
	(void)userdata;
	(void)instance;
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	string_name_new(&class_name, "ELNativeDuelBrain", 0);
	string_name_new(&parent_name, "Object", 0);
	string_name_new(&empty_name, "", 0);
	string_new(&empty_text, "");
	GDExtensionClassCreationInfo6 ci;
	memset(&ci, 0, sizeof(ci));
	ci.is_abstract = 1;
	ci.is_exposed = 1;
	ci.free_instance_func = free_instance;
	register_class(library, &class_name, &parent_name, &ci);
	Name method, argument;
	string_name_new(&method, "search", 0);
	string_name_new(&argument, "state", 0);
	GDExtensionPropertyInfo args[1] = { info(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &argument) };
	GDExtensionClassMethodArgumentMetadata meta[1] = { GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE };
	GDExtensionPropertyInfo ret_info = info(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &empty_name);
	GDExtensionClassMethodInfo mi;
	memset(&mi, 0, sizeof(mi));
	mi.name = &method;
	mi.call_func = call;
	mi.ptrcall_func = ptrcall;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_STATIC;
	mi.has_return_value = 1;
	mi.return_value_info = &ret_info;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	mi.argument_count = 1;
	mi.arguments_info = args;
	mi.arguments_metadata = meta;
	register_method(library, &class_name, &mi);
	string_name_free(&method);
	string_name_free(&argument);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	unregister_class(library, &class_name);
	string_name_free(&class_name);
	string_name_free(&parent_name);
	string_name_free(&empty_name);
	string_free(&empty_text);
}

#define LOAD(var, type, name) var = (type)get_proc(name); if (!var) return 0

EL_EXPORT GDExtensionBool el_duel_brain_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	get_proc = p_get_proc_address;
	library = p_library;
	LOAD(variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	LOAD(pba_index, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
	LOAD(pba_index_const, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
	LOAD(string_name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	LOAD(string_new, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
	LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
	GDExtensionInterfaceVariantGetPtrConstructor get_constructor;
	GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
	GDExtensionInterfaceVariantGetPtrBuiltinMethod get_method;
	GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;
	GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
	LOAD(get_constructor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
	LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	LOAD(get_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
	LOAD(get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
	LOAD(get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	pba_new = get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
	pba_free = get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	string_name_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
	string_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
	Name size_name, resize_name;
	string_name_new(&size_name, "size", 0);
	string_name_new(&resize_name, "resize", 0);
	pba_size = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &size_name, 3173160232);
	pba_resize = get_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &resize_name, 848867239);
	string_name_free(&size_name);
	string_name_free(&resize_name);
	pba_from_variant = get_to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	variant_from_pba = get_from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!pba_new || !pba_free || !string_name_free || !string_free || !pba_size || !pba_resize || !pba_from_variant || !variant_from_pba)
		return 0;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	return 1;
}
