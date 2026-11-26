/* Run with: cc -O2 tools/duel_aura_worth_check.c -lm -o aura_check */
#include "../game/native/el_duel_brain.c"
#include <stdio.h>

/* A survivor retains only the bonuses of leaders still on the board.
 * The evaluator reads separate values for a ready and a resting creature. */
int main(void) {
	static Search search;
	static State board;
	search.power_worth = 1400;
	search.tough_worth = 600;
	board.rules = &search;
	board.n = 3;
	Unit *power_leader = &board.u[0], *health_leader = &board.u[1], *unit = &board.u[2];
	power_leader->gives_power = 1;
	health_leader->gives_toughness = 2;
	unit->power = 1;
	unit->raw = unit->toughness = 3;
	unit->ready_worth = 4800;
	unit->resting_worth = 3800;
	led(&search, &board, unit, power_leader);
	led(&search, &board, unit, health_leader);
	unit->leaders = 3;

	health_leader->flags |= F_DEAD;
	lost_leader(&board, 1);
	if (unit->leaders != 1 || unit->power != 2 || unit->toughness != 3 ||
	    unit->ready_worth != 6200 || unit->resting_worth != 5200) {
		fputs("Losing the health aura must leave only the power bonus.\n", stderr);
		return 1;
	}
	power_leader->flags |= F_DEAD;
	lost_leader(&board, 0);
	if (unit->leaders || unit->power != 1 || unit->toughness != 3 ||
	    unit->ready_worth != 4800 || unit->resting_worth != 3800) {
		fputs("Losing both auras must restore the original stats and values.\n", stderr);
		return 1;
	}
	return 0;
}
