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
 *    0 version (3)             1 the computer's side
 *    2 side whose turn it is   3 phase: 0 attackers to choose, 1 blockers
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
 * then, per hero, 16 integers (health, ether, channels, stone skins,
 * lifeguards, damage reflections, damage mirrors, unknown cards in hand,
 * chance in thousandths that an unknown card is a creature, the same chance
 * already saved up, and the channels gained in each of its next six turns);
 * per hero, the typical creature of its colour for each cost 1..8 (power,
 * toughness, worth when ready, worth when resting); per hero, six known
 * creature cards in hand (cost or -1, power, toughness, flags, regeneration
 * cost, worth when ready, worth when resting, race number); and 13 per
 * creature (id, owner, power, toughness, flags, regeneration cost, stone
 * skins, lifeguards, worth when ready, worth when resting (thousandths),
 * race number, id of the attacker it already blocks or -1, ether that wakes
 * it from enfeeblement or 0).
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
 */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "include/gdextension_interface.h"

#if defined(_WIN32)
#define EL_EXPORT __declspec(dllexport)
#else
#define EL_EXPORT __attribute__((visibility("default")))
#endif

/* --------------------------------------------------------------------- model */

#define HEADER 15
#define HERO_FIELDS 16
#define COSTS 8
#define TYPICAL_FIELDS 4
#define HAND 6
#define CARD_FIELDS 8
#define UNIT_FIELDS 13
#define FIXED (HEADER + 2 * (HERO_FIELDS + COSTS * TYPICAL_FIELDS + HAND * CARD_FIELDS))
#define ARMY 10
#define MAX_UNITS 32
#define MAX_SETS 96
#define MAX_PLANS 320
#define MAX_TURNS 6
#define WIN 100000000
#define LETHAL 30000

enum {
	F_FLY = 1, F_FIRST = 2, F_TRAMPLE = 4, F_UNBLOCKABLE = 8, F_ELUSIVE = 16, F_WALL = 32, F_NO_ATTACK = 64,
	F_RESTLESS = 128, F_NO_UNTAP = 256, F_DESTROY = 512, F_LIFETAP = 1024, F_BERSERK = 2048, F_TEAM = 4096,
	F_RESTING = 8192, F_SICK = 16384, F_PLANE = 32768, F_ATTACKING = 65536, F_NO_REGEN = 1 << 17,
	F_HELD = 1 << 18, F_DESTROY_UNWALLED = 1 << 19, F_STINGER = 1 << 20,
	/* Set by the model. */
	F_DEAD = 1 << 24, F_REGENERATED = 1 << 25, F_POISONED = 1 << 26,
};

typedef struct {
	int32_t id, ready_worth, resting_worth;
	uint32_t flags;
	int16_t power, toughness, damage;
	int8_t owner, regeneration, skins, guards, race, blocks, wake;
} Unit;

/* A creature card: one known in hand, or the typical one of a cost. */
typedef struct {
	int32_t ready_worth, resting_worth;
	uint32_t flags;
	int16_t cost, power, toughness;
	int8_t regeneration, race;
} Card;

typedef struct {
	Unit u[MAX_UNITS];
	int n;
	int health[2], ether[2], channels[2], skins[2], guards[2], reflects[2], mirrors[2];
	int attacker;
	int calm; /* nothing can attack this turn */
	/* Card play: known cards already summoned (bits), unknown cards held, the
	 * saved-up chance of a creature among them, own turns begun. */
	int played[2], unknown[2], chance[2], turns[2];
} State;

typedef struct {
	int ai, edition, health_worth, foe_worth, tax, wide;
	int64_t nodes, budget;
	int aborted;
	int cards;
	int chance_step[2], income[2][MAX_TURNS];
	Card hand[2][HAND], typical[2][COSTS];
} Search;

typedef struct { int8_t target[MAX_UNITS]; int score; } Plan;
typedef struct { uint32_t mask; int score; } Set;

static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }

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

static inline int ready(const Unit *u) {
	return !(u->flags & (F_DEAD | F_RESTING | F_SICK | F_PLANE));
}

static int can_attack(const State *s, const Unit *u) {
	return u->owner == s->attacker && ready(u) && !(u->flags & (F_NO_ATTACK | F_HELD)) && u->power > 0 && !s->calm;
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

/* The position's worth for the computer; `turns` left makes a sooner end count more. */
static int evaluate(const Search *x, const State *s, int turns) {
	int mine = s->health[x->ai], theirs = s->health[1 - x->ai];
	if (mine <= 0) return theirs <= 0 ? 0 : -(WIN + turns * 1000);
	if (theirs <= 0) return WIN + turns * 1000;
	int v = health_worth(x, mine) - health_worth(x, theirs) / 100 * x->foe_worth;
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
	if (x->tax > 0) count = imin(count, s->ether[s->attacker] / x->tax);
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

static void hurt_hero(State *s, int side, int amount, int source) {
	if (amount <= 0 || s->health[side] <= 0) return;
	amount -= 2 * s->skins[side];
	if (amount <= 0) return;
	if (s->guards[side] > 0) { s->guards[side]--; return; }
	if (s->reflects[side] > 0) {
		/* Reflected damage lands on the other hero once per copy. */
		for (int i = 0; i < s->reflects[side]; i++) s->health[1 - side] = imax(0, s->health[1 - side] - amount);
		return;
	}
	for (int i = 0; i < s->mirrors[side]; i++) s->health[1 - side] = imax(0, s->health[1 - side] - amount);
	int before = s->health[side];
	s->health[side] = imax(0, before - amount);
	if (source >= 0) {
		Unit *a = &s->u[source];
		if (a->flags & F_LIFETAP) s->health[a->owner] += imin(amount, before);
		if (a->flags & F_STINGER) a->flags |= F_POISONED;
	}
}

static void hurt_unit(State *s, int source, int target, int amount) {
	Unit *t = &s->u[target];
	if (t->flags & F_DEAD) return;
	amount -= 2 * t->skins;
	if (amount <= 0) return;
	if (t->guards > 0) { t->guards--; return; }
	t->damage = (int16_t)(t->damage + amount);
	const Unit *a = &s->u[source];
	if ((a->flags & F_DESTROY) || ((a->flags & F_DESTROY_UNWALLED) && !(t->flags & F_WALL))) t->flags |= F_POISONED;
	if (t->damage < t->toughness) return;
	if (t->regeneration > 0 && !(t->flags & F_NO_REGEN) && s->ether[t->owner] >= t->regeneration) {
		s->ether[t->owner] -= t->regeneration;
		t->damage = 0;
		t->flags |= F_REGENERATED;
	} else {
		t->flags |= F_DEAD;
	}
}

/* Plays the declared attack against the blocks in `target` (the index of the
 * attacker each creature blocks, or -1). */
static void resolve(State *s, const int8_t *target) {
	int defender = 1 - s->attacker;
	for (int i = 0; i < s->n; i++) {
		Unit *a = &s->u[i];
		if ((a->flags & F_DEAD) || !(a->flags & F_ATTACKING)) continue;
		if (!(a->flags & F_RESTLESS)) a->flags |= F_RESTING;
		int remaining = imax(0, a->power);
		int blocked = 0;
		for (int j = 0; j < s->n; j++) {
			if (target[j] != i) continue;
			Unit *b = &s->u[j];
			if (b->flags & F_DEAD) continue;
			blocked = 1;
			if (a->flags & (F_DEAD | F_REGENERATED)) break;
			int first = (b->flags & F_FIRST) && !(a->flags & F_FIRST);
			if (first) {
				hurt_unit(s, j, i, imax(0, b->power));
				if (a->flags & (F_DEAD | F_REGENERATED)) break;
			}
			int dealt = imin(remaining, imax(0, b->toughness - b->damage) + 2 * b->skins);
			remaining -= dealt;
			hurt_unit(s, i, j, dealt);
			if (!first && !(b->flags & (F_DEAD | F_REGENERATED))) hurt_unit(s, j, i, imax(0, b->power));
		}
		if (!blocked) hurt_hero(s, defender, remaining, i);
		else if (!(a->flags & (F_DEAD | F_REGENERATED)) && (a->flags & F_TRAMPLE) && remaining > 0) hurt_hero(s, defender, remaining, i);
		if (s->health[0] <= 0 || s->health[1] <= 0) break;
	}
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if ((u->flags & F_POISONED) && !(u->flags & F_REGENERATED)) u->flags |= F_DEAD;
	}
}

static void summon(State *s, int side, const Card *c) {
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
	u->flags = c->flags;
	u->regeneration = c->regeneration;
	u->race = c->race;
	u->ready_worth = c->ready_worth;
	u->resting_worth = c->resting_worth;
	u->blocks = -1;
	s->n++;
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
		for (int c = 0; c < HAND; c++) {
			const Card *card = &x->hand[side][c];
			if (card->cost < 0 || (s->played[side] >> c & 1) || card->cost > s->ether[side]) continue;
			if (best < 0 || card->cost > x->hand[side][best].cost) best = c;
		}
		if (best < 0) break;
		s->played[side] |= 1 << best;
		s->ether[side] -= x->hand[side][best].cost;
		summon(s, side, &x->hand[side][best]);
	}
	s->chance[side] += x->chance_step[side];
	if (s->chance[side] >= 1000 && s->unknown[side] > 0) {
		int cost = imin(s->ether[side], COSTS);
		while (cost >= 1 && x->typical[side][cost - 1].cost < 0) cost--;
		if (cost >= 1) {
			s->ether[side] -= cost;
			s->unknown[side]--;
			s->chance[side] -= 1000;
			summon(s, side, &x->typical[side][cost - 1]);
		}
	}
}

/* The turn passes: wounds heal, the side that attacked loses its summoning
 * sickness, the other side rises, gains its channels, refills its ether, draws
 * and plays its cards. */
static void end_turn(const Search *x, State *s) {
	int next = 1 - s->attacker;
	for (int i = 0; i < s->n; i++) {
		Unit *u = &s->u[i];
		if (u->flags & F_DEAD) continue;
		u->damage = 0;
		u->flags &= ~(uint32_t)(F_ATTACKING | F_REGENERATED | F_POISONED);
		if (u->owner == s->attacker) u->flags &= ~(uint32_t)F_SICK;
		else if (!(u->flags & F_NO_UNTAP)) u->flags &= ~(uint32_t)F_RESTING;
	}
	s->attacker = next;
	if (x->cards) {
		s->channels[next] += x->income[next][imin(s->turns[next], MAX_TURNS - 1)];
		s->turns[next]++;
		s->unknown[next]++;
		s->ether[next] = s->channels[next];
	} else {
		s->ether[next] = imax(s->ether[next], s->channels[next]);
	}
	s->calm = 0;
	develop(x, s, next);
}

static void declare(const Search *x, State *s, uint32_t mask) {
	for (int i = 0; i < s->n; i++) {
		if (!(mask >> i & 1) || (s->u[i].flags & F_ATTACKING)) continue;
		s->u[i].flags |= F_ATTACKING;
		s->ether[s->attacker] -= x->tax;
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
		if (!(u->flags & F_TEAM)) continue;
		int partner = 0;
		for (int j = 0; j < s->n && !partner; j++)
			partner = j != i && (mask >> j & 1) && s->u[j].race == u->race;
		if (!partner) return 0;
	}
	return x->tax <= 0 || fresh * x->tax <= s->ether[s->attacker];
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
		if ((u->flags & F_BERSERK) && x->tax == 0 && !(u->flags & F_TEAM)) { forced |= 1u << i; continue; }
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

static void read_card(const int32_t *r, Card *c) {
	c->cost = (int16_t)imax(-1, imin(r[0], 1000));
	c->power = (int16_t)r[1];
	c->toughness = (int16_t)r[2];
	c->flags = (uint32_t)r[3] & 0x00ffffff;
	c->regeneration = (int8_t)imin(r[4], 100);
	c->ready_worth = r[5];
	c->resting_worth = r[6];
	c->race = (int8_t)(r[7] & 0x7f);
}

static int read_state(const int32_t *in, int64_t length, Search *x, State *s, int *phase, int *turns, int *develop_now) {
	if (length < FIXED || in[0] != 3) return 0;
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
	x->health_worth = in[7];
	x->foe_worth = in[14] > 0 ? in[14] : 100;
	x->tax = imax(0, in[8]);
	s->calm = in[9] != 0;
	x->wide = in[10] != 0;
	x->cards = in[12] != 0;
	*develop_now = in[13] != 0;
	s->n = n;
	const int32_t *at = in + HEADER;
	for (int side = 0; side < 2; side++, at += HERO_FIELDS) {
		s->health[side] = at[0];
		s->ether[side] = at[1];
		s->channels[side] = at[2];
		s->skins[side] = at[3];
		s->guards[side] = at[4];
		s->reflects[side] = at[5];
		s->mirrors[side] = at[6];
		s->unknown[side] = imax(0, at[7]);
		x->chance_step[side] = imax(0, imin(at[8], 1000));
		s->chance[side] = imax(0, imin(at[9], 1000));
		for (int i = 0; i < MAX_TURNS; i++) x->income[side][i] = imax(0, at[10 + i]);
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
		}
	for (int side = 0; side < 2; side++)
		for (int i = 0; i < HAND; i++, at += CARD_FIELDS) read_card(at, &x->hand[side][i]);
	for (int i = 0; i < n; i++) {
		const int32_t *r = at + i * UNIT_FIELDS;
		Unit *u = &s->u[i];
		u->id = r[0];
		u->owner = (int8_t)(r[1] & 1);
		u->power = (int16_t)r[2];
		u->toughness = (int16_t)r[3];
		u->flags = (uint32_t)r[4] & 0x00ffffff;
		u->regeneration = (int8_t)imin(r[5], 100);
		u->skins = (int8_t)imin(r[6], 100);
		u->guards = (int8_t)imin(r[7], 100);
		u->ready_worth = r[8];
		u->resting_worth = r[9];
		u->race = (int8_t)(r[10] & 0x7f);
		u->blocks = -1;
		u->wake = (int8_t)imax(0, imin(r[12], 100));
	}
	/* Blocks already made name their attacker by id. */
	for (int i = 0; i < n; i++) {
		int32_t wanted = at[i * UNIT_FIELDS + 11];
		if (wanted < 0) continue;
		for (int j = 0; j < n; j++)
			if (s->u[j].id == wanted) s->u[i].blocks = (int8_t)j;
	}
	return 1;
}

/* Fills `out` (room for 5 + 2 * MAX_UNITS integers); returns its length. */
static int run_search(const int32_t *in, int64_t length, int32_t *out) {
	Search x;
	State s;
	int phase, turns, develop_now;
	memset(out, 0, sizeof(int32_t) * 5);
	if (!read_state(in, length, &x, &s, &phase, &turns, &develop_now)) return 5;
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
	int32_t out[5 + 2 * MAX_UNITS];
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
