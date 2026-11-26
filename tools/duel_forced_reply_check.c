/* Build with cc -O2 tools/duel_forced_reply_check.c -lm -pthread -o reply_check */
#include "../game/native/el_duel_brain.c"
#include <stdio.h>

/* A forced defence or an empty enemy attack leads to three attack spells.
 * With one ether to spend, only the last spell can defeat the opponent. */
static int forced_reply(int workers, int enemy, Move *line, int *length, int *peak) {
	static Search search;
	static State board;
	memset(&search, 0, sizeof(search));
	memset(&board, 0, sizeof(board));
	SearchActivity activity;
	atomic_init(&activity.active, 1);
	atomic_init(&activity.peak, 1);
	search.activity = &activity;
	search.root_workers = search.worker_limit = workers;
	search.width = 16;
	search.nodes = 512; /* exercise the worker path without a warm-up search */
	search.budget = 1000000;
	search.maximum[0] = search.maximum[1] = 20;
	search.health_worth = search.foe_worth = 1000;
	search.ai = enemy ? 1 : 0;
	search.hidden = -1;
	for (int i = 0; i < AHEAD; i++) search.income[0][i] = 1;
	board.rules = &search;
	board.second = 1;
	board.attacker = 1;
	board.phase = enemy ? 0 : 1;
	board.held[0] = 3;
	board.health[0] = 20;
	board.health[1] = 5;
	for (int i = 0; i < 3; i++) {
		search.hand[0][i] = (Card){.effect = EFF_DAMAGE, .aim = AIM_ANY, .cost = 1, .amount = i == 2 ? 5 : i + 1};
	}
	set_clock(&search, now_ms() + 30000);
	Move best = {0};
	int value = search_moves(&search, &board, 3, 5, -2 * WIN, 2 * WIN, &best, NULL, line, length);
	*peak = atomic_load(&activity.peak);
	return value;
}

static int check_reply(int enemy) {
	Move serial[MAX_LINE], parallel[MAX_LINE];
	int serial_length, parallel_length, serial_peak, parallel_peak;
	int serial_score = forced_reply(1, enemy, serial, &serial_length, &serial_peak);
	int parallel_score = forced_reply(4, enemy, parallel, &parallel_length, &parallel_peak);
	if (serial_length < 2 || parallel_length != serial_length || serial_score != parallel_score
			|| (enemy ? serial_score > -WIN : serial_score < WIN)
			|| serial[0].kind != 0 || serial[serial_length - 1].kind != 3
			|| serial[serial_length - 1].a != 2 || serial_peak != 1 || parallel_peak < 2) {
		fputs("Workers must read the winning reply beyond a forced phase end.\n", stderr);
		return 1;
	}
	for (int i = 0; i < serial_length; i++) {
		if (!same_move(&serial[i], &parallel[i])) {
			fputs("The serial and parallel searches disagree on the forced line.\n", stderr);
			return 1;
		}
	}
	return 0;
}

int main(void) {
	return check_reply(0) || check_reply(1);
}
