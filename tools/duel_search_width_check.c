/* Build with cc -O2 tools/duel_search_width_check.c -lm -pthread -o width_check */
#include "../game/native/el_duel_brain.c"
#include <stdio.h>

/* CNBL and CANV can each sacrifice any of ten creatures.
 * Only CANV on the three-power creature defeats the opposing hero.
 * In the ordered reply list that creature can fall on either side of the
 * shortlist cutoff as its board position changes. */
int main(void) {
	static Search search;
	static State board;
	search.width = 16;
	search.ai = 1;
	search.maximum[0] = search.maximum[1] = 20;
	search.hand[1][0] = (Card){.effect = EFF_DAMAGE, .aim = AIM_ANY, .cost = 1, .amount = 1};
	search.hand[1][1] = (Card){.effect = EFF_SACRIFICE_HEAL, .aim = AIM_CREATURE, .cost = 3, .own = 1};
	search.hand[1][2] = (Card){.effect = EFF_DEVOUR, .aim = AIM_CREATURE, .cost = 2, .own = 1};
	board.rules = &search;
	board.second = 1;
	board.attacker = 1;
	board.held[1] = 3;
	board.health[0] = 3;
	board.health[1] = 14;
	board.ether[1] = board.channels[1] = 5;
	board.n = 10;
	for (int i = 0; i < board.n; i++) {
		Unit *u = &board.u[i];
		u->id = i + 2;
		u->owner = 1;
		u->power = 1;
		u->toughness = u->raw = 1;
		u->flags = F_RESTING;
		u->blocks = -1;
	}
	for (int target = 0; target < board.n; target++) {
		board.u[target].power = 3;
		Move moves[MAX_MOVES];
		Plan plans[MAX_PLANS];
		int count = generate(&search, &board, moves, 1, 0, 0, plans);
		Move lethal = {3, 2, target, 0};
		State played = board;
		if (count <= search.width || !apply_command(&search, &played, (const int32_t *)&lethal)
				|| played.health[0] > 0 || played.health[1] <= 0) {
			fputs("Expected a crowded position with a legal lethal sacrifice.\n", stderr);
			return 1;
		}
		int kept = keep_width(&search, &board, moves, count, NULL, 1);
		int present = 0;
		for (int i = 0; i < kept; i++) present |= same_move(&moves[i], &lethal);
		if (!present) {
			fprintf(stderr, "The winning reply on creature %d was discarded.\n", target);
			return 1;
		}
		board.u[target].power = 1;
	}
	return 0;
}
