// Per-connection limits of the online play relay (RelayRoom in worker.js),
// kept apart so they can be checked with Node: node tools/relay_limits_check.mjs
//
// A binary frame is at most one game frame: the 6-byte header and up to
// 256 KiB of data (ELRelayPeer.FRAME). Text frames are short control
// messages. Each connection has a budget of frames and bytes that refills
// every second; a burst may use the whole budget at once, which covers the
// largest message a game sends (a strategic snapshot of a few MiB, or a
// rejoining duel guest's whole match).

export const HEADER = 6;
export const MAX_FRAME = HEADER + 256 * 1024;
export const MAX_CONTROL = 1024;
export const RATE = {
  bytes: 4 * 1024 * 1024,
  burstBytes: 24 * 1024 * 1024,
  frames: 400,
  burstFrames: 2000,
};

export function newBudget(now) {
  return { bytes: RATE.burstBytes, frames: RATE.burstFrames, at: now };
}

// '' when a frame of `size` bytes may pass at time `now` (milliseconds),
// otherwise why the connection is closed: {code, reason}.
export function admit(budget, size, text, now) {
  if (size > (text ? MAX_CONTROL : MAX_FRAME)) return { code: 1009, reason: 'Message too large.' };
  if (!text && size < HEADER) return { code: 1003, reason: 'Invalid frame.' };
  const elapsed = Math.max(0, now - budget.at) / 1000;
  budget.at = Math.max(budget.at, now);
  budget.bytes = Math.min(RATE.burstBytes, budget.bytes + elapsed * RATE.bytes);
  budget.frames = Math.min(RATE.burstFrames, budget.frames + elapsed * RATE.frames);
  if (budget.frames < 1 || budget.bytes < size) return { code: 1008, reason: 'Too much data sent to the room.' };
  budget.frames -= 1;
  budget.bytes -= size;
  return '';
}
