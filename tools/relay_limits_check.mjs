// Checks the online relay's per-connection limits (relay_limits.js) without
// a Worker runtime:
//
//   node tools/relay_limits_check.mjs
import { admit, newBudget, MAX_FRAME, MAX_CONTROL, RATE } from '../relay_limits.js';

const failures = [];
function check(ok, what) {
  console.log((ok ? 'PASS: ' : 'FAIL: ') + what);
  if (!ok) failures.push(what);
}

let budget = newBudget(0);
check(admit(budget, MAX_FRAME, false, 0) === '', 'a full game frame passes');
check(admit(budget, MAX_FRAME + 1, false, 0).code === 1009, 'a larger binary frame closes the connection');
check(admit(budget, MAX_CONTROL + 1, true, 0).code === 1009, 'a long control message closes the connection');
check(admit(budget, 3, false, 0).code === 1003, 'a frame shorter than its header is refused');

// A 4 MiB strategic snapshot: 16 full frames at once.
budget = newBudget(0);
let passed = 0;
for (let i = 0; i < 16; i++) if (admit(budget, MAX_FRAME, false, 0) === '') passed++;
check(passed === 16, 'the largest game message passes in one burst');

// A flood of small frames is cut off once the burst is used up...
budget = newBudget(0);
let refused = null;
for (let i = 0; i < 10000 && !refused; i++) {
  const result = admit(budget, 64, false, 0);
  if (result !== '') refused = { at: i, result };
}
check(refused !== null && refused.at === RATE.burstFrames && refused.result.code === 1008, `a frame flood is stopped after ${RATE.burstFrames} frames (${refused?.at})`);

// ...and a byte flood the same way.
budget = newBudget(0);
refused = null;
for (let i = 0; i < 1000 && !refused; i++) {
  const result = admit(budget, MAX_FRAME, false, 0);
  if (result !== '') refused = i;
}
check(refused !== null && refused === Math.floor(RATE.burstBytes / MAX_FRAME), `a byte flood is stopped after ${refused} full frames`);

// Steady play within the rate never runs out: 20 state messages a second
// of 60 KiB each for a minute.
budget = newBudget(0);
let steady = true;
for (let ms = 0; ms < 60000; ms += 50) steady = steady && admit(budget, 60 * 1024, false, ms) === '';
check(steady, 'steady play within the rate is never cut off');

// The budget refills with time.
budget = newBudget(0);
while (admit(budget, MAX_FRAME, false, 0) === '');
check(admit(budget, MAX_FRAME, false, 1000) === '', 'the budget refills after a second');

console.log(`relay limits check: ${failures.length} failures`);
process.exit(failures.length ? 1 : 0);
