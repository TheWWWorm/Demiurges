extends RefCounted
## Behavioral proof-search regressions, called for each edition by the random
## puzzle checks. Positions are small and constructed independently of recipes.
## These exercise actual combat and Run; no AI decisions or rules are mocked.

static func _check(report: Dictionary, condition: bool, label: String) -> void:
	report.checks = int(report.checks) + 1
	report.results.append({"ok": condition, "check": label})
	if not condition:
		report.failures = int(report.failures) + 1
		printerr("FAILED proof: " + label)

static func _entry(profile: ELProfile) -> Dictionary:
	var heroes: Array = []
	for side in 2:
		heroes.append({"id": side, "health": 10 if side == 0 else 2, "maximum": 10,
			"mana": 2, "channels": 2, "level": 4, "turns": 2 if side == 0 else 1,
			"template": ELCatalog.default_hero(profile, "Red"), "faction": "Red", "kind": "hero",
			"skills": {}, "spec": "NONE", "spec_level": 4, "luck": 0, "suppression": 0,
			"deck": ["ZAPP"], "hand": ["ZAPP", "ZAPP"] if side == 0 else [],
			"hand_slots": [-1, -1] if side == 0 else [],
			"spell_uses": [-1 if profile.id == "el1" else 1], "drawn": [], "grave": [],
			"enchantments": [], "artifacts": [], "artifact_uses": 0})
	return {"id": "proof-regression-" + profile.id, "turns": 1, "objective": {"type": "win"},
		"state": {"profile": profile.id, "charge_version": 2, "payment_version": 1,
			"phase": 0, "attacker": 0, "round": 2, "turn_serial": 3, "rng": 212, "winner": -1,
			"next_id": 2, "next_enchantment": 1, "attacks": [], "blocks": {}, "creatures": {},
			"heroes": heroes, "setup": {"puzzle_fixed_hands": true, "puzzle_fixed_channels": true}}}

static func _creature(profile: ELProfile, id: int, side: int, card := "STRT") -> Dictionary:
	var row: Dictionary = profile.table("CombatCreatures")[card]
	var flags := ELCatalog.flags(row)
	return {"id": id, "card": card, "owner": side, "power": int(row.Power),
		"toughness": int(row.Toughness), "damage": 0, "flags": flags, "flying": "Fly" in flags,
		"enchantments": [], "resting": false, "sick": false, "regenerated": false}

static func _solve(profile: ELProfile, entry: Dictionary, report: Dictionary, limits: Dictionary = {}, tiny_slices := false) -> Dictionary:
	var job := ELPuzzleProof.start(profile, entry, limits)
	var calls := 0
	while not job.done and calls < 100000:
		job.step(1 if tiny_slices else 256, 1 if tiny_slices else 30000)
		calls += 1
	_check(report, job.done, "incremental proof terminates")
	return job.result if job.done else {"status": "unknown", "witness": [], "witness_tactics": 0}

## Compare the solver's canonical assignment paths with a complete BFS of
## actual pure attack/block commands. Inherited orders must remain reorderable;
## every endpoint is compared with its exact order, not just its creature set.
static func _assignment_equivalence(profile: ELProfile, entry: Dictionary, report: Dictionary, label: String) -> void:
	var duel := ELDuel.new()
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.state.duplicate(true)}):
		_check(report, false, label + " fixture restores")
		return
	duel.searching = true
	var material := ELPuzzleProof._material(duel)
	var queue: Array = [duel]
	var full := {ELPuzzleProof._position(duel): true}
	var at := 0
	while at < queue.size() and queue.size() <= 1000:
		var before: ELDuel = queue[at]
		at += 1
		for action: Dictionary in ELPuzzleProof.legal_moves(before):
			if action.kind not in ["attack", "block"]: continue
			var after := before.search_copy()
			if not ELCombatSearch.apply(after, action) or ELPuzzleProof._material(after) != material: continue
			var identity := ELPuzzleProof._position(after)
			if full.has(identity): continue
			full[identity] = true
			queue.append(after)
	_check(report, queue.size() <= 1000, label + " full assignment graph is finite")
	var job := ELPuzzleProof.start(profile, entry, {"budget": 4000, "depth": 24, "max_tactics": 0})
	var reduced := {}
	var calls := 0
	while not job.done and calls < 100000:
		if not job._stack.is_empty():
			var now: ELDuel = job._stack.back().duel
			if ELPuzzleProof._material(now) == material: reduced[ELPuzzleProof._position(now)] = true
		job.step(1, 1)
		calls += 1
	_check(report, job.done and job.result.get("status") == "refuted", label + " impossible victory is fully refuted")
	_check(report, full.size() == reduced.size() and full.keys().all(func(key: String) -> bool: return reduced.has(key)),
		label + " preserves every ordered assignment endpoint (%d full, %d reduced)" % [full.size(), reduced.size()])

static func _compare_full(profile: ELProfile, entry: Dictionary, report: Dictionary, label: String) -> Dictionary:
	var reduced := _solve(profile, entry, report)
	var full := _solve(profile, entry, report, {"canonical_assignments": false})
	_check(report, reduced.get("status") in ["forced", "refuted"] and reduced.get("status") == full.get("status"),
		label + " has the same completed result with and without assignment reduction")
	return reduced

static func _replay(profile: ELProfile, entry: Dictionary, witness: Array, report: Dictionary) -> void:
	var solved_before := ELPuzzles._solved.duplicate(true)
	var mastery_before := ELPuzzles._mastery.duplicate(true)
	var lists_before := ELPuzzles._lists.duplicate(true)
	var plans_before := ELCombatSearch._plans.duplicate(true)
	var proofs_before := ELCombatSearch._proofs.duplicate(true)
	var definition_before := JSON.stringify(entry, "", false)
	var attempt := ELPuzzles.Run.new()
	var restored := attempt.begin_entry(profile, entry, false, false)
	_check(report, restored, "witness starts through the real puzzle Run")
	if not restored: return
	for move: Dictionary in witness:
		_check(report, attempt.outcome.is_empty(), "witness does not continue after termination")
		var legal := ELPuzzleProof.apply(attempt.duel, move)
		_check(report, legal, "witness action is legal for its actual side")
		if not legal: return
		attempt.watch()
	_check(report, attempt.outcome == "solved", "proof witness reaches runtime solved")
	_check(report, ELPuzzles._solved == solved_before and ELPuzzles._mastery == mastery_before,
		"verification leaves completion and mastery unchanged")
	_check(report, ELPuzzles._lists == lists_before, "verification leaves authored catalogs unchanged")
	_check(report, ELCombatSearch._plans == plans_before and ELCombatSearch._proofs == proofs_before,
		"verification does not reset or change the opponent's caches")
	_check(report, JSON.stringify(entry, "", false) == definition_before, "runtime replay leaves input definition unchanged")

static func _two_turn_replies(profile: ELProfile, report: Dictionary) -> void:
	# Two sick Rats cannot attack yet. The opponent's refill funds Lightning
	# against either Rat. Next turn's Strength must target whichever survives.
	var adaptive := _entry(profile)
	adaptive.turns = 2
	adaptive.state.heroes[0].mana = 0
	adaptive.state.heroes[0].channels = 2
	adaptive.state.heroes[0].hand = ["STRG"]
	adaptive.state.heroes[0].hand_slots = [-1]
	adaptive.state.heroes[1].health = 5
	adaptive.state.heroes[1].mana = 0
	adaptive.state.heroes[1].channels = 1
	adaptive.state.heroes[1].hand = ["CLIG"]
	adaptive.state.heroes[1].hand_slots = [-1]
	adaptive.state.creatures = {"2": _creature(profile, 2, 0), "3": _creature(profile, 3, 0)}
	adaptive.state.creatures["2"].sick = true
	adaptive.state.creatures["3"].sick = true
	adaptive.state.next_id = 4
	var forced := _solve(profile, adaptive, report, {"depth": 36})
	var strategy: Dictionary = forced.get("strategy", {})
	_check(report, forced.get("status") == "forced", "a two-turn strategy survives either hostile Lightning target")
	_check(report, strategy.get("min_player_turns") == 2 and strategy.get("max_player_turns") == 2,
		"all conditional winning branches use the second own turn")
	_check(report, strategy.get("max_enemy_replies") == 3 and strategy.get("max_enemy_tactical_replies") == 2,
		"strategy aggregates include pass and both hostile spell targets")
	_check(report, strategy.get("max_enemy_decisions") == 1 and strategy.get("max_enemy_tactics") == 1,
		"strategy aggregates count the adversarial choice and spell on nonprincipal branches")
	_check(report, strategy.get("max_actions") == forced.get("witness", []).size(),
		"maximum strategy length agrees with the longest principal witness")
	var sliced := _solve(profile, adaptive, report, {"depth": 36}, true)
	_check(report, sliced.get("strategy") == strategy and sliced.get("witness") == forced.get("witness"),
		"conditional strategy metrics and witness are deterministic across time slices")
	_replay(profile, adaptive, forced.get("witness", []), report)
	for victim in [2, 3]:
		var duel := ELDuel.new()
		var legal := duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": adaptive.state.duplicate(true)})
		duel.searching = true
		legal = legal and ELPuzzleProof.apply(duel, {"kind": "end_phase", "side": 0})
		_check(report, legal and duel.active_side() == 1 and int(duel.heroes[1].mana) == 1,
			"opponent receives the real channel refill before choosing a target")
		legal = legal and ELPuzzleProof.apply(duel, {"kind": "cast", "side": 1, "card": "CLIG", "target": victim})
		legal = legal and ELPuzzleProof.apply(duel, {"kind": "end_phase", "side": 1})
		_check(report, legal and not duel.creatures.has(victim) and int(duel.heroes[0].mana) == 2,
			"hostile target dies before the player's next-turn refill")
		if not legal: continue
		var continuation := adaptive.duplicate(true)
		continuation.state = duel.snapshot()
		continuation.turns = 1
		var response := _solve(profile, continuation, report)
		_check(report, response.get("status") == "forced" and response.get("witness", []).any(
			func(move: Dictionary) -> bool: return move.get("card") == "STRG" and int(move.get("target", -1)) == 5 - victim),
			"winning continuation enhances the survivor of this particular enemy reply")
		_replay(profile, continuation, response.get("witness", []), report)
	adaptive.turns = 1
	var short := _solve(profile, adaptive, report, {"depth": 36})
	_check(report, short.get("status") == "refuted" and short.get("strategy", {}) == {},
		"a complete one-turn refutation carries no fabricated strategy metrics")

	var hostile := _entry(profile)
	hostile.turns = 2
	hostile.state.heroes[0].mana = 1
	hostile.state.heroes[0].channels = 1
	hostile.state.heroes[0].health = 1
	hostile.state.heroes[1].mana = 0
	hostile.state.heroes[1].channels = 1
	hostile.state.heroes[1].hand = ["ZAPP"]
	hostile.state.heroes[1].hand_slots = [-1]
	_check(report, _solve(profile, hostile, report, {"depth": 36}).get("status") == "refuted",
		"an initially unaffordable enemy spell becomes lethal after its channel refill")
	hostile.state.heroes[1].channels = 0
	_check(report, _solve(profile, hostile, report, {"depth": 36}).get("status") == "forced",
		"removing the hostile refill changes the actual two-turn outcome")

	hostile = _entry(profile)
	hostile.turns = 2
	hostile.state.heroes[0].mana = 1
	hostile.state.heroes[0].channels = 1
	hostile.state.heroes[0].health = 2
	hostile.state.creatures = {"2": _creature(profile, 2, 1, "KBSH")}
	hostile.state.creatures["2"].resting = true
	hostile.state.next_id = 3
	var ability := _solve(profile, hostile, report, {"depth": 36})
	_check(report, ability.get("status") == "forced" and ability.get("strategy", {}).get("max_enemy_tactics") == 1,
		"proof includes an enemy ability that readies at the next hostile turn")
	_check(report, ability.get("strategy", {}).get("min_player_turns") == 1 and ability.get("strategy", {}).get("max_player_turns") == 2,
		"strategy turn extrema include both enemy self-destruction and the longer hostile reply")
	hostile.state.heroes[0].health = 1
	_check(report, _solve(profile, hostile, report, {"depth": 36}).get("status") == "refuted",
		"the same enemy ability refutes the plan when it can kill the hero")
	# Four necessary casts: remove the Shaman before it readies and deliver
	# three hero damage, funded by two ether now and two at the next own turn.
	hostile.state.heroes[0].mana = 2
	hostile.state.heroes[0].channels = 2
	hostile.state.heroes[0].hand = ["ZAPP", "ZAPP", "ZAPP", "ZAPP"]
	hostile.state.heroes[0].hand_slots = [-1, -1, -1, -1]
	hostile.state.heroes[1].health = 3
	var four_tactics := _solve(profile, hostile, report, {"depth": 36})
	_check(report, four_tactics.get("status") == "forced" and four_tactics.get("strategy", {}).get("min_tactics") == 4
		and four_tactics.get("strategy", {}).get("max_tactics") == 4 and four_tactics.get("strategy", {}).get("max_player_turns") == 2,
		"hostile two-turn position has a certified strategy with four actual tactics")
	_check(report, _solve(profile, hostile, report, {"depth": 36, "max_tactics": 3}).get("status") == "refuted",
		"three tactics cannot remove the hostile ability and finish the hero")
	_replay(profile, hostile, four_tactics.get("witness", []), report)
	hostile.turns = 1
	_check(report, _solve(profile, hostile, report, {"depth": 36}).get("status") == "refuted",
		"four-tactic plan genuinely needs the second own-turn refill")

	# A win during the initial defence consumes zero own turns, just as Run
	# reports. This is different from a defence followed by our first attack.
	var defence := _entry(profile)
	defence.state.phase = ELDuel.Phase.DEFENCE
	defence.state.attacker = 1
	defence.state.heroes[1].health = 1
	defence.state.creatures = {"2": _creature(profile, 2, 0, "KBSH"), "3": _creature(profile, 3, 1)}
	defence.state.next_id = 4
	defence.state.attacks = [3]
	defence.solution = [{"kind": "ability", "side": 0, "id": 2, "key": "sting", "target": 1}]
	var immediate := _solve(profile, defence, report)
	_check(report, immediate.get("status") == "forced" and immediate.get("strategy", {}).get("max_player_turns") == 0,
		"initial defence victory uses zero own turns under the runtime convention")
	_replay(profile, defence, immediate.get("witness", []), report)

static func _advice(run: ELPuzzles.Run, report: Dictionary, limits: Dictionary = {}, tiny_slices := false) -> Dictionary:
	var before := JSON.stringify({"position": ELPuzzleProof._position(run.duel), "entry": run.entry,
		"turn": run.turn, "outcome": run.outcome, "hints": run.hints_used, "history": run.duel.history,
		"error": run.duel.error, "searching": run.duel.searching}, "", false)
	var plans := ELCombatSearch._plans.duplicate(true)
	var proofs := ELCombatSearch._proofs.duplicate(true)
	var solved := ELPuzzles._solved.duplicate(true)
	var mastery := ELPuzzles._mastery.duplicate(true)
	var job := ELPuzzleAdvice.start(run, limits)
	var calls := 0
	while not job.done and calls < 100000:
		job.step(1 if tiny_slices else 256, 1 if tiny_slices else 30000)
		calls += 1
	_check(report, job.done and job.is_current(run), "live advice completes for its unchanged attempt")
	_check(report, JSON.stringify({"position": ELPuzzleProof._position(run.duel), "entry": run.entry,
		"turn": run.turn, "outcome": run.outcome, "hints": run.hints_used, "history": run.duel.history,
		"error": run.duel.error, "searching": run.duel.searching}, "", false) == before,
		"live advice changes no battle, attempt, hint count, input or history")
	_check(report, ELCombatSearch._plans == plans and ELCombatSearch._proofs == proofs
		and ELPuzzles._solved == solved and ELPuzzles._mastery == mastery,
		"live advice leaves AI caches and puzzle completion/mastery unchanged")
	return job.result

static func _live_advice(profile: ELProfile, report: Dictionary) -> void:
	var entry := _entry(profile)
	entry.solution = [{"kind": "cast", "card": "ZAPP", "target": 1}, {"kind": "cast", "card": "ZAPP", "target": 1}]
	var attempt := ELPuzzles.Run.new()
	_check(report, attempt.begin_entry(profile, entry, false, false), "live advice fixture starts through Run")
	var first := _advice(attempt, report)
	_check(report, first.get("status") == "proven" and first.get("command", {}).get("card") == "ZAPP"
		and first.get("command", {}).get("target") == 1 and first.get("remaining_own_turns") == 1,
		"live advice certifies a legal next action with the actual remaining turn")
	var sliced := _advice(attempt, report, {}, true)
	_check(report, sliced.get("command") == first.get("command") and sliced.get("nodes") == first.get("nodes")
		and sliced.get("text") == first.get("text"), "live advice is deterministic across time slices")
	var incomplete := _advice(attempt, report, {"budget": 1})
	_check(report, incomplete.get("status") == "unknown" and not incomplete.has("command")
		and not String(incomplete.get("text", "")).is_empty(), "bounded advice is inconclusive, never a fabricated refutation")
	_check(report, _advice(attempt, report, {"depth": 1}).get("status") == "unknown", "advice preserves an action-depth cutoff")
	_check(report, _advice(attempt, report, {"max_tactics": 0}).get("status") == "error", "advice cannot mislabel a restricted search as a full refutation")
	_check(report, _advice(attempt, report, {"without_player": {"effects": ["damage"]}}).get("status") == "error", "development operation exclusions cannot reach the player-facing advice boundary")

	var pending := ELPuzzleAdvice.start(attempt)
	pending.step(1, 1)
	pending.cancel()
	var cancelled := pending.result.duplicate(true)
	pending.step()
	_check(report, pending.done and cancelled.get("status") == "cancelled" and pending.result == cancelled
		and not pending.result.has("command"), "cancelled advice releases work and cannot later reveal a move")
	var same := ELPuzzleAdvice.fingerprint(attempt)
	attempt.hints_used += 1
	_check(report, ELPuzzleAdvice.fingerprint(attempt) == same, "revealing a hint does not stale its own position")
	attempt.duel.rng_state += 1
	_check(report, ELPuzzleAdvice.fingerprint(attempt) != same, "advice fingerprint retains the actual random state")
	attempt.duel.rng_state -= 1
	attempt.allowed += 1
	_check(report, ELPuzzleAdvice.fingerprint(attempt) != same, "the original deadline is part of advice freshness")
	attempt.allowed -= 1
	pending = ELPuzzleAdvice.start(attempt)
	_check(report, ELPuzzleProof.apply(attempt.duel, {"kind": "cast", "card": "ZAPP", "target": 0}), "a legal arbitrary mistake is played outside the hinted plan")
	_check(report, not pending.is_current(attempt), "live changes stale pending advice")
	while not pending.done: pending.step(256, 30000)
	_check(report, pending.result.get("status") == "proven" and not pending.is_current(attempt),
		"a completed old proof remains visibly stale after the live position changes")
	var lost := _advice(attempt, report)
	_check(report, lost.get("status") == "refuted" and not lost.has("command")
		and lost.get("text") != incomplete.get("text"), "advice detects a complete refutation after an arbitrary continuation")
	attempt.begin_entry(profile, entry, false, false)
	_check(report, not pending.is_current(attempt), "restarting the same board invalidates the previous attempt's advice")
	ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase"})
	_check(report, _advice(attempt, report).get("status") == "wrong_phase", "live advice waits during the enemy's decision")
	attempt.begin_entry(profile, entry, false, false)
	ELPuzzleProof.apply(attempt.duel, {"kind": "cast", "card": "ZAPP", "target": 1})
	ELPuzzleProof.apply(attempt.duel, {"kind": "cast", "card": "ZAPP", "target": 1})
	_check(report, attempt.outcome == "solved" and _advice(attempt, report).get("status") == "terminal", "completed attempts do not reveal a further action")

	# A direct copy must preserve next_card and avoid aliases to the live setup.
	attempt.begin_entry(profile, entry, false, false)
	attempt.duel.next_card = 77
	var copied := ELPuzzleProof.from_position(attempt.duel, 1)
	_check(report, not copied.done and copied._stack[0].duel.next_card == 77
		and ELPuzzleProof._position(copied._stack[0].duel) == ELPuzzleProof._position(attempt.duel),
		"current-position proof keeps runtime identity fields omitted by save snapshots")
	copied._stack[0].duel.setup["copy_probe"] = true
	_check(report, not attempt.duel.setup.has("copy_probe"), "current-position proof owns an independent setup")
	attempt.duel.expected_specs = true
	_check(report, ELPuzzleProof.from_position(attempt.duel, 1).result.get("status") == "invalid", "expected-outcome simulation cannot certify live advice")
	attempt.duel.expected_specs = false

	# Inherited declaration toggles can be a solver route, but recalling and
	# restoring an unchanged lone attacker is not a useful next instruction.
	var selected := _entry(profile)
	selected.state.heroes[0].hand = []
	selected.state.heroes[0].hand_slots = []
	selected.state.heroes[1].health = 1
	selected.state.creatures = {"2": _creature(profile, 2, 0)}
	selected.state.next_id = 3
	selected.state.attacks = [2]
	attempt.begin_entry(profile, selected, false, false)
	var commit := _advice(attempt, report)
	_check(report, commit.get("status") == "proven" and commit.get("command", {}).get("kind") == "end_phase",
		"advice omits only an exactly reversible leading recall/redeclare cycle")
	var committed := ELPuzzleProof.apply(attempt.duel, commit.get("command", {}))
	committed = committed and ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase", "side": 1})
	_check(report, committed and attempt.outcome == "solved",
		"the simplified next action still wins through the actual runtime")
	var lethal_now := _entry(profile)
	lethal_now.state.heroes[1].health = 1
	lethal_now.state.heroes[0].hand = ["STRG"]
	lethal_now.state.heroes[0].hand_slots = [-1]
	lethal_now.state.creatures = {"2": _creature(profile, 2, 0, "KBSH")}
	lethal_now.state.next_id = 3
	attempt.begin_entry(profile, lethal_now, false, false)
	var finish_now := _advice(attempt, report)
	_check(report, finish_now.get("status") == "proven" and finish_now.get("command", {}).get("key") == "sting"
		and finish_now.get("command", {}).get("target") == 1, "advice chooses immediate lethal damage before unnecessary preparation")
	_check(report, ELPuzzleProof.apply(attempt.duel, finish_now.get("command", {})) and attempt.outcome == "solved",
		"the immediate-win hint really finishes in the current own turn")
	lethal_now.state.heroes[0].hand = ["STRG", "ZAPP"]
	lethal_now.state.heroes[0].hand_slots = [-1, -1]
	lethal_now.state.heroes[0].mana = 3
	lethal_now.state.creatures["2"] = _creature(profile, 2, 0)
	attempt.begin_entry(profile, lethal_now, false, false)
	var shifted: Array = [{"kind": "cast", "side": 0, "index": 0, "card": "STRG", "target": 2},
		{"kind": "cast", "side": 0, "index": 0, "card": "ZAPP", "target": 1}]
	_check(report, ELPuzzleAdvice._next_action(attempt.duel, shifted).get("card") == "STRG",
		"an immediate-win shortcut never reuses a shifted index as if its earlier card were still there")

	# Starting from a later own turn must not reset the original allowance.
	var late := _entry(profile)
	late.turns = 2
	late.state.heroes[0].mana = 0
	late.state.heroes[0].channels = 1
	attempt.begin_entry(profile, late, false, false)
	ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase"})
	ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase"})
	_check(report, attempt.turn == 2 and attempt.duel.active_side() == 0, "deadline fixture reaches the actual final own turn")
	var deadline := _advice(attempt, report)
	_check(report, deadline.get("status") == "refuted" and deadline.get("remaining_own_turns") == 1,
		"late-turn advice never grants a second copy of the original turn allowance")
	var extra := ELPuzzleProof.from_position(attempt.duel, 2)
	while not extra.done: extra.step(256, 30000)
	_check(report, extra.result.get("status") == "forced", "an extra turn would change the deadline fixture's answer")

	# During the final defence, zero future own turns still permits an
	# immediate defensive ability. It must not permit next-turn ether refill.
	var defence := _entry(profile)
	defence.state.heroes[0].hand = []
	defence.state.heroes[0].hand_slots = []
	defence.state.heroes[1].health = 1
	defence.state.creatures = {"2": _creature(profile, 2, 0, "KBSH"), "3": _creature(profile, 3, 1)}
	defence.state.next_id = 4
	for immediate in [true, false]:
		var position := defence.duplicate(true)
		if not immediate:
			position.state.creatures.erase("2")
			position.state.heroes[0].hand = ["ZAPP"]
			position.state.heroes[0].hand_slots = [-1]
			position.state.heroes[0].mana = 0
			position.state.heroes[0].channels = 1
		attempt.begin_entry(profile, position, false, false)
		var legal := ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase", "side": 0})
		legal = legal and ELPuzzleProof.apply(attempt.duel, {"kind": "attack", "side": 1, "id": 3})
		legal = legal and ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase", "side": 1})
		_check(report, legal and attempt.turn == 1 and attempt.duel.active_side() == 0
			and attempt.duel.attacker == 1, "zero-future-turn fixture is a live final defence")
		var response := _advice(attempt, report)
		_check(report, response.get("remaining_own_turns") == 0
			and response.get("status") == ("proven" if immediate else "refuted"),
			"zero future own turns permits only an actual defence victory")
		if immediate:
			_check(report, response.get("command", {}).get("key") == "sting"
				and ELPuzzleProof.apply(attempt.duel, response.command) and attempt.outcome == "solved",
				"zero-turn defensive hint wins before the original runtime deadline")
		else:
			extra = ELPuzzleProof.from_position(attempt.duel, 1)
			while not extra.done: extra.step(256, 30000)
			_check(report, extra.result.get("status") == "forced", "clamping zero to one would invent a false defensive hint")

	# Both hostile target choices need different advice at the same later turn.
	var adaptive := _entry(profile)
	adaptive.turns = 2
	adaptive.state.heroes[0].mana = 0
	adaptive.state.heroes[0].channels = 2
	adaptive.state.heroes[0].hand = ["STRG"]
	adaptive.state.heroes[0].hand_slots = [-1]
	adaptive.state.heroes[1].health = 5
	adaptive.state.heroes[1].mana = 0
	adaptive.state.heroes[1].channels = 1
	adaptive.state.heroes[1].hand = ["CLIG"]
	adaptive.state.heroes[1].hand_slots = [-1]
	adaptive.state.creatures = {"2": _creature(profile, 2, 0), "3": _creature(profile, 3, 0)}
	adaptive.state.creatures["2"].sick = true
	adaptive.state.creatures["3"].sick = true
	adaptive.state.next_id = 4
	for victim in [2, 3]:
		attempt.begin_entry(profile, adaptive, false, false)
		var wait := _advice(attempt, report)
		_check(report, wait.get("status") == "proven" and wait.get("command", {}).get("kind") == "end_phase",
			"initial live advice certifies waiting through every hostile target choice")
		var legal := ELPuzzleProof.apply(attempt.duel, wait.get("command", {}))
		legal = legal and ELPuzzleProof.apply(attempt.duel, {"kind": "cast", "side": 1, "card": "CLIG", "target": victim})
		legal = legal and ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase", "side": 1})
		_check(report, legal and attempt.turn == 2, "the opponent's actual reply determines the next live position")
		var response := _advice(attempt, report)
		_check(report, response.get("status") == "proven" and response.get("command", {}).get("card") == "STRG"
			and response.get("command", {}).get("target") == 5 - victim and response.get("remaining_own_turns") == 1,
			"live tactical advice targets the survivor of this specific hostile reply")
		_check(report, String(response.get("text", "")).contains("#%d" % (5 - victim)), "hint text identifies the exact surviving piece")
		for step in 6:
			if not attempt.outcome.is_empty(): break
			if attempt.duel.active_side() == 1:
				if not ELPuzzleProof.apply(attempt.duel, {"kind": "end_phase", "side": 1}): break
				continue
			if step > 0: response = _advice(attempt, report)
			if response.get("status") != "proven" or not ELPuzzleProof.apply(attempt.duel, response.get("command", {})): break
		_check(report, attempt.outcome == "solved", "fresh next-action hints solve the contingent branch through Run")

static func _advice_descriptions(profile: ELProfile, report: Dictionary) -> void:
	# These independently legal actions exercise parameters that a plain card
	# name cannot describe: identical rail copies, marks, graves, second targets,
	# hero-granted ability sources and X. Text must preserve those distinctions.
	var entry := _entry(profile)
	entry.state.heroes[0].mana = 30
	entry.state.heroes[0].hand = ["ZAPP", "ZAPP", "PRFY", "BDEX", "QKFX", "TRAD", "COMT"]
	entry.state.heroes[0].hand_slots = [-1, -1, -1, -1, -1, -1, -1]
	entry.state.heroes[0].hand_view = [20, 5, 30, 40, 50, 60, 70]
	entry.state.heroes[0].grave = ["HOPR"]
	entry.state.heroes[1].grave = ["STRT"]
	entry.state.creatures = {"2": _creature(profile, 2, 0), "3": _creature(profile, 3, 0),
		"4": _creature(profile, 4, 1), "5": _creature(profile, 5, 0, "PRAT")}
	entry.state.creatures["2"].resting = true
	entry.state.next_id = 6
	for id in [11, 12, 13]:
		entry.state.heroes[0].enchantments.append({"id": id, "card": "CMBN" if id == 13 else "ENRG",
			"owner": 0, "born": id - 10, "power": 0, "toughness": 0, "used": false})
	entry.state.next_enchantment = 14
	var duel := ELDuel.new()
	var restored := duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.state})
	_check(report, restored, "advice secondary-parameter fixture restores: " + duel.error)
	if not restored: return
	var ru := ELRemakeText.language(profile) == "ru"
	var rail_first := ELPuzzleAdvice.describe(duel, {"kind": "cast", "index": 0, "target": 1})
	var rail_second := ELPuzzleAdvice.describe(duel, {"kind": "cast", "index": 1, "target": 1})
	_check(report, rail_first.contains("карта 2 слева" if ru else "card 2 from the left")
		and rail_second.contains("карта 1 слева" if ru else "card 1 from the left"),
		"duplicate hand references follow visible rail order instead of array indices")
	var choices: Array = [
		{"kind": "cast", "card": "PRFY", "target": 0, "grave": 11},
		{"kind": "cast", "card": "PRFY", "target": 0, "grave": 12},
		{"kind": "ability", "id": 0, "key": "energize:11", "target": 2},
		{"kind": "ability", "id": 0, "key": "energize:12", "target": 2},
		{"kind": "cast", "card": "BDEX", "target": 2, "grave": 0},
		{"kind": "cast", "card": "QKFX", "target": 1, "grave": 0},
		{"kind": "cast", "card": "TRAD", "target": 2, "grave": 4},
		{"kind": "ability", "id": 0, "key": "combine:13", "target": 2, "choice": 3},
		{"kind": "cast", "card": "COMT", "target": 1, "power": 2},
		{"kind": "ability", "id": 5, "key": "plague", "target": 1, "amount": 2},
	]
	var descriptions: Array = []
	for action: Dictionary in choices:
		var text := ELPuzzleAdvice.describe(duel, action)
		_check(report, ELPuzzleProof.apply(duel.search_copy(), action) and not text.is_empty(),
			"secondary-parameter instruction describes a real legal command: " + String(action.kind))
		descriptions.append(text)
	_check(report, descriptions[0] != descriptions[1] and String(descriptions[0]).contains("#11")
		and String(descriptions[1]).contains("#12"), "same-name enchantment targets remain distinct")
	_check(report, descriptions[2] != descriptions[3] and String(descriptions[2]).contains("#11")
		and String(descriptions[3]).contains("#12"), "same-name hero ability sources remain distinct")
	_check(report, String(descriptions[4]).contains(duel.card_name("HOPR"))
		and String(descriptions[5]).contains(duel.card_name("STRT")), "grave instructions retain owner, card and slot")
	_check(report, String(descriptions[6]).contains("#2") and String(descriptions[6]).contains("#4")
		and String(descriptions[7]).contains("#2") and String(descriptions[7]).contains("#3"), "two-target spell and ability instructions retain both ordered choices")
	_check(report, String(descriptions[8]).contains("X = 2.") and String(descriptions[9]).contains("X = 2."),
		"variable spell power and ability amount stay explicit")

static func _complete_ability_choices(profile: ELProfile, report: Dictionary) -> void:
	# Mana Thorns + Ethereal Chain make spending a single ether decisive.
	# With no other creature, Combine's legal same-target sacrifice is the
	# only such action. The AI's paired-target helper deliberately omits it.
	for mode: String in ["combine", "plague"]:
		var entry := _entry(profile)
		entry.state.heroes[0].hand = []
		entry.state.heroes[0].hand_slots = []
		entry.state.heroes[0].mana = 1
		entry.state.heroes[0].channels = 0
		entry.state.heroes[1].health = 1
		entry.state.creatures = {"2": _creature(profile, 2, 0, "WLAR" if mode == "combine" else "PRAT")}
		entry.state.creatures["2"].granted = ["NoAttack"]
		entry.state.next_id = 3
		var cards: Array = ["CMBN", "MNTH", "ETCH"] if mode == "combine" else ["MNTH", "ETCH"]
		for i in cards.size():
			entry.state.heroes[0].enchantments.append({"id": i + 1, "card": cards[i],
				"owner": 0, "born": 1, "power": 0, "toughness": 0, "used": false})
		entry.state.next_enchantment = cards.size() + 1
		var forced := _solve(profile, entry, report, {"budget": 200, "depth": 8})
		_check(report, forced.get("status") == "forced" and forced.get("witness", []).size() == 1,
			"actual legal " + mode + " spending is a winning engine command")
		if forced.get("status") != "forced": continue
		_replay(profile, entry, forced.witness, report)
		if mode == "combine":
			_check(report, forced.witness[0].target == 2 and forced.witness[0].choice == 2,
				"Combine's sacrificed and receiving targets may be the same creature")
		elif profile.id == "el2":
			var attempt := ELPuzzles.Run.new()
			attempt.begin_entry(profile, entry, false, false)
			_check(report, not attempt.duel.can_use_ability(2, "plague"), "EL2 controls disable Plague on empty graveyards")
			_check(report, not ELPuzzleGenerator.replay_line(profile, entry, forced.witness).get("ok", false),
				"generator admission rejects an execution-only principal line unavailable in the controls")
			var advice := _advice(attempt, report)
			_check(report, advice.get("status") == "error" and not advice.has("command"),
				"advice never recommends an execution-only ability unavailable in the controls")

		# Reverse the role: a ground defender cannot block the screened flyer,
		# but this same command can kill our hero before combat resolves. Every
		# paired Combine target other than itself is illegal due to the screen.
		var hostile := _entry(profile)
		hostile.state.phase = ELDuel.Phase.DEFENCE
		hostile.state.heroes[0].health = 1
		hostile.state.heroes[0].hand = []
		hostile.state.heroes[0].hand_slots = []
		hostile.state.heroes[1].health = 2
		hostile.state.heroes[1].mana = 1
		hostile.state.heroes[1].channels = 0
		hostile.state.heroes[1].enchantments = entry.state.heroes[0].enchantments.duplicate(true)
		for enchantment: Dictionary in hostile.state.heroes[1].enchantments: enchantment.owner = 1
		hostile.state.next_enchantment = entry.state.next_enchantment
		hostile.state.creatures = {"2": _creature(profile, 2, 0, "GBAT"), "3": _creature(profile, 3, 1, "WLAR" if mode == "combine" else "PRAT")}
		hostile.state.creatures["2"].granted = ["NoTarget"]
		hostile.state.attacks = [2]
		hostile.state.next_id = 4
		_check(report, _solve(profile, hostile, report, {"budget": 200, "depth": 8}).get("status") == "refuted",
			"enemy's legal " + mode + " reply refutes the otherwise lethal flying attack")

## Production recipes, both semantic variants and both real hostile targets.
## Initial universal guarantees are tested by the generator matrix. Here the
## live adviser must adapt and each resulting branch must really finish in Run.
static func _recipe_advice_branches(profile: ELProfile, report: Dictionary) -> void:
	report.advice_branches = []
	report.advice_replays = []
	for family: String in ["survivor_route", "control_fork"]:
		for seed_value in [1, 2]:
			var entry := ELPuzzleRecipes.build(profile, family, seed_value, 5)
			var expected: String = (["summon_sentry", "borrow_enemy_sentry"] if family == "survivor_route" else ["trample_or_first_strike", "air_or_ground"])[seed_value - 1]
			_check(report, not entry.is_empty() and entry.generated.get("variant") == expected,
				"conditional recipe representative covers " + str(expected))
			if entry.is_empty(): continue
			for victim in [2, 3]:
				var attempt := ELPuzzles.Run.new()
				var legal := attempt.begin_entry(profile, entry, false, false)
				var commands: Array = []
				if family == "control_fork":
					commands = [{"kind": "cast", "side": 0, "card": "CHCM", "target": 2},
						{"kind": "cast", "side": 0, "card": "CHCM", "target": 3}, {"kind": "end_phase", "side": 0},
						{"kind": "cast", "side": 1, "card": "CLNP", "target": victim, "grave": victim - 1},
						{"kind": "end_phase", "side": 1}]
				else:
					var preparation := String(entry.state.heroes[0].hand[0])
					commands = [{"kind": "cast", "side": 0, "card": preparation, "target": 6 if preparation == "CHCM" else -1},
						{"kind": "end_phase", "side": 0}, {"kind": "cast", "side": 1, "card": "CLIG", "target": victim},
						{"kind": "attack", "side": 1, "id": 5}, {"kind": "end_phase", "side": 1}]
				for action: Dictionary in commands: legal = legal and ELPuzzleProof.apply(attempt.duel, action)
				_check(report, legal and attempt.outcome.is_empty() and attempt.duel.active_side() == 0,
					"real opponent choice reaches a live " + family + " branch: " + str(victim))
				if not legal: continue
				var suggested: Array = []
				var nodes := 0
				var elapsed_ms := 0.0
				for step in 24:
					if not attempt.outcome.is_empty(): break
					var action: Dictionary = {}
					if attempt.duel.active_side() == 0:
						var advice := _advice(attempt, report)
						nodes += int(advice.get("nodes", 0))
						elapsed_ms += float(advice.get("elapsed_ms", 0.0))
						_check(report, advice.get("status") == "proven" and advice.get("remaining_own_turns") == 1,
							"conditional next action is proven within the one remaining own turn")
						if advice.get("status") != "proven": break
						action = advice.command.duplicate(true)
						suggested.append(action.duplicate(true))
					else:
						# Exercise a real available block before passing. The adviser
						# already certified every alternative, including reassignments.
						for possible: Dictionary in ELPuzzleProof.legal_moves(attempt.duel):
							if possible.kind == "block" and not attempt.duel.blocks.has(int(possible.id)):
								action = possible
								break
						if action.is_empty(): action = {"kind": "end_phase", "side": 1}
					commands.append(action.duplicate(true))
					legal = ELPuzzleProof.apply(attempt.duel, action)
					_check(report, legal, "a fresh conditional advice/reply command is legal in Run")
					if not legal: break
				_check(report, legal and attempt.outcome == "solved" and attempt.turn == 2,
					"conditional advice actually solves " + family + "/" + str(expected) + "/reply_" + str(victim))
				var surviving: int = 5 - victim
				if family == "survivor_route":
					var spell := "STRG" if surviving == 3 else "CLFR"
					var wrong_spell := "CLFR" if surviving == 3 else "STRG"
					var chose_route := suggested.any(func(action: Dictionary) -> bool: return action.kind == "cast" and action.get("card") == spell and action.get("target") == surviving)
					var instant_air_finish: bool = surviving == 3 and attempt.outcome == "solved" and not suggested.is_empty() \
						and suggested[-1].get("kind") == "ability" and suggested[-1].get("key") == "sting" and suggested[-1].get("target") == 1
					_check(report, (chose_route or instant_air_finish) and not suggested.any(func(action: Dictionary) -> bool: return action.kind == "cast" and action.get("card") == wrong_spell),
						"survivor's movement selects Cloak on the ground or Strength/direct lethal damage in the air")
					_check(report, suggested.any(func(action: Dictionary) -> bool:
						return (action.kind == "ability" and action.get("key") == "sting" and action.get("target") == 5) \
							or (action.kind == "block" and action.get("id") == 3 and action.get("target") == 5)),
						"live defence advice covers the committed flyer with the sentry or surviving flyer")
				else:
					var buff := String(entry.state.heroes[0].hand[3])
					_check(report, suggested.any(func(action: Dictionary) -> bool: return action.kind == "cast" and action.get("card") == buff and action.get("target") == surviving),
						"control-fork advice enhances the creature still loyal after this dispel")
				var replay := entry.duplicate(true)
				replay.id = String(entry.id) + "_reply_" + str(victim)
				replay.solution = commands.duplicate(true)
				report.advice_replays.append(replay)
				report.advice_branches.append({"edition": profile.id, "family": family, "variant": expected,
					"seed": seed_value, "opponent_target": victim, "outcome": attempt.outcome,
					"player_turns": attempt.turn, "advice_nodes": nodes, "advice_ms": elapsed_ms,
					"suggested_commands": suggested, "replay_id": replay.id})

## New mechanisms must remain playable through current-position advice after
## each actual card/ability changes the hand, graveyard, targets or aspects.
## Find representatives by the declared semantic registry rather than relying
## on a particular RNG seed forever. The production layout shuffle exercises
## exact live IDs, ordered grave choices and hand indices in the descriptions.
static func _new_recipe_advice_branches(profile: ELProfile, report: Dictionary) -> void:
	report.new_family_advice_branches = []
	report.new_family_advice_replays = []
	var families: Array[String] = ELPuzzleZoneRecipes.families(profile.id)
	families.append_array(ELMortalityPuzzleRecipes.families(profile.id))
	for family: String in families:
		for difficulty: int in ELPuzzleGenerator.DIFFICULTIES:
			if not ELPuzzleRecipes.supports(family, difficulty): continue
			var expected := ELPuzzleRecipes.variants(family, difficulty)
			var found := {}
			for seed_value in range(1, 129):
				var candidate := ELPuzzleRecipes.build(profile, family, seed_value, difficulty)
				if candidate.is_empty(): continue
				var variant := String(candidate.get("generated", {}).get("variant", ""))
				if variant in expected and not found.has(variant): found[variant] = {"entry": candidate, "seed": seed_value}
				if found.size() == expected.size(): break
			_check(report, not expected.is_empty() and found.size() == expected.size(),
				"new-family advice covers every declared variant: %s / tier %d" % [family, difficulty])
			for variant: String in expected:
				if not found.has(variant): continue
				var entry: Dictionary = found[variant].entry.duplicate(true)
				var seed_value := int(found[variant].seed)
				var shuffle_seed := 90731 + seed_value * 31 + difficulty
				ELPuzzleGenerator._shuffle_layout(entry, shuffle_seed, profile)
				var label := "%s/%s/tier%d/%s" % [profile.id, family, difficulty, variant]
				_check(report, ELPuzzleGenerator.replay_line(profile, entry, entry.solution).get("ok", false),
					"new-family shuffled reference is playable: " + label)
				var attempt := ELPuzzles.Run.new()
				var legal := attempt.begin_entry(profile, entry, false, false)
				_check(report, legal, "new-family live advice starts through Run: " + label)
				if not legal: continue
				var commands: Array = []
				var suggested: Array = []
				var guidance: Array = []
				var nodes := 0
				var elapsed_ms := 0.0
				for step in 32:
					if not attempt.outcome.is_empty(): break
					var action: Dictionary = {}
					if attempt.duel.active_side() == 0:
						var advice := _advice(attempt, report)
						nodes += int(advice.get("nodes", 0))
						elapsed_ms += float(advice.get("elapsed_ms", 0.0))
						var remaining := attempt.allowed - (attempt.turn - (1 if attempt.duel.attacker == 0 else 0))
						_check(report, advice.get("status") == "proven" and advice.get("remaining_own_turns") == remaining,
							"new-family next action is proven within the original deadline: " + label)
						if advice.get("status") != "proven": break
						action = advice.command.duplicate(true)
						var description := ELPuzzleAdvice.describe(attempt.duel, action)
						_check(report, not description.is_empty() and String(advice.get("text", "")).contains(description),
							"new-family useful guidance describes the exact current command: " + label)
						if action.kind == "cast":
							_check(report, attempt.duel.can_cast_from_hand(int(action.index)), "new-family suggested card is enabled in the hand: " + label)
						elif action.kind == "ability":
							_check(report, attempt.duel.can_use_ability(int(action.id), String(action.key)), "new-family suggested ability is enabled in the battle controls: " + label)
						if action.get("kind") == "ability" and String(action.get("key", "")).begins_with("recycle:"):
							var first := int(action.get("target", -1))
							var second := int(action.get("choice", -1))
							_check(report, attempt.duel.in_plane(first) and not attempt.duel.in_plane(second)
								and description.contains("#%d," % first) and description.contains("#%d," % second)
								and description.contains("#%d" % int(String(action.key).get_slice(":", 1))),
								"Transfer Aspects guidance identifies its source and both ordered opposite-plane targets")
						if action.get("kind") == "cast" and ELCatalog.rule(profile, String(action.card)).get("effect") == "dispel":
							var mark := int(action.get("grave", -1))
							_check(report, attempt.duel.find_enchantment(mark) == int(action.target)
								and description.contains("#%d" % mark) and description.contains("#%d," % int(action.target)),
								"Lock Aspect removal guidance identifies the chosen mark and its current holder")
						guidance.append({"command": action.duplicate(true), "description": description,
							"remaining_own_turns": advice.remaining_own_turns, "nodes": advice.get("nodes", 0)})
						suggested.append(action.duplicate(true))
					else:
						# Take a material block if one is available. The previous
						# proof established that every legal reply is covered.
						for possible: Dictionary in ELPuzzleProof.legal_moves(attempt.duel):
							if possible.kind == "block" and not attempt.duel.blocks.has(int(possible.id)):
								action = possible
								break
						if action.is_empty(): action = {"kind": "end_phase", "side": 1}
					commands.append(action.duplicate(true))
					legal = ELPuzzleProof.apply(attempt.duel, action)
					attempt.watch()
					_check(report, legal and attempt.turn <= attempt.allowed, "new-family guidance applies in Run without adding a turn: " + label)
					if not legal: break
				_check(report, legal and attempt.outcome == "solved" and attempt.turn <= int(entry.turns),
					"fresh live hints solve the complete new-family challenge: " + label)
				var replay := entry.duplicate(true)
				replay.id = String(entry.id) + "_live_advice"
				replay.solution = commands.duplicate(true)
				_check(report, ELPuzzleGenerator.replay_line(profile, replay, commands).get("ok", false),
					"saved new-family live-advice sequence independently replays: " + label)
				report.new_family_advice_replays.append(replay)
				report.new_family_advice_branches.append({"edition": profile.id, "language": ELRemakeText.language(profile),
					"family": family, "variant": variant, "difficulty": difficulty, "seed": seed_value,
					"layout_seed": shuffle_seed, "outcome": attempt.outcome, "player_turns": attempt.turn,
					"allowed_turns": attempt.allowed, "advice_nodes": nodes, "advice_ms": elapsed_ms,
					"suggested_commands": suggested, "guidance": guidance, "replay_id": replay.id})

## Remove an operation, not its card or surrounding state, and ask whether a
## guaranteed win remains. This is development evidence of an essential idea;
## normal generation and live advice do not apply these restrictions.
static func _operation_exclusions(profile: ELProfile, report: Dictionary) -> void:
	var entry := _entry(profile)
	for excluded: Dictionary in [{"casts": ["ZAPP"]}, {"effects": ["damage"]}]:
		var answer := _solve(profile, entry, report, {"without_player": excluded})
		_check(report, answer.get("status") == "refuted" and answer.get("without_player") == excluded,
			"removing every player damage route is fully refuted and labels the restriction")
	_check(report, _solve(profile, entry, report, {"without_player": {"effects": ["enchant"]}}).get("status") == "forced",
		"excluding an unrelated effect does not remove damage spells")
	_check(report, _solve(profile, entry, report, {"without_player": {}}).get("status") == "forced",
		"an empty operation exclusion is the ordinary proof")
	_check(report, _solve(profile, entry, report, {"budget": 1, "without_player": {"effects": ["enchant"]}}).get("status") == "unknown",
		"an operation audit still reports an exhausted budget as unknown")
	var exclusions := {"casts": ["ZAPP"]}
	var job := ELPuzzleProof.start(profile, entry, {"without_player": exclusions})
	exclusions.casts.clear()
	while not job.done: job.step(256, 30000)
	_check(report, job.result.get("status") == "refuted" and job.result.get("without_player") == {"casts": ["ZAPP"]},
		"operation exclusions are copied and cannot change during a running proof")

	var ability := _entry(profile)
	ability.state.heroes[0].hand = []
	ability.state.heroes[0].hand_slots = []
	ability.state.heroes[0].mana = 0
	ability.state.heroes[0].channels = 0
	ability.state.heroes[1].health = 1
	ability.state.creatures = {"2": _creature(profile, 2, 0, "KBSH"), "3": _creature(profile, 3, 1, "GBAT")}
	ability.state.next_id = 4
	_check(report, _solve(profile, ability, report).get("status") == "forced",
		"direct creature damage wins through a blocking ground defender")
	_check(report, _solve(profile, ability, report, {"without_player": {"abilities": ["sting"]}}).get("status") == "refuted",
		"the same position has no forced win when that player ability is unavailable")

	var hostile := _entry(profile)
	hostile.turns = 2
	hostile.state.heroes[0].hand = []
	hostile.state.heroes[0].hand_slots = []
	hostile.state.heroes[0].health = 1
	hostile.state.heroes[1].health = 1
	hostile.state.heroes[1].hand = ["ZAPP"]
	hostile.state.heroes[1].hand_slots = [-1]
	hostile.state.heroes[1].mana = 0
	hostile.state.heroes[1].channels = 1
	hostile.state.creatures = {"2": _creature(profile, 2, 0, "AVSC")}
	hostile.state.creatures["2"].sick = true
	hostile.state.next_id = 3
	_check(report, _solve(profile, hostile, report, {"without_player": {"casts": ["ZAPP"], "effects": ["damage"]}}).get("status") == "refuted",
		"player exclusions do not remove the opponent's matching lethal spell after refill")
	hostile.state.heroes[1].channels = 0
	_check(report, _solve(profile, hostile, report, {"without_player": {"casts": ["ZAPP"], "effects": ["damage"]}}).get("status") == "forced",
		"without the hostile refill the delayed flyer wins under the same player restriction")
	hostile.state.heroes[1].hand = []
	hostile.state.heroes[1].hand_slots = []
	hostile.state.creatures["3"] = _creature(profile, 3, 1, "KBSH")
	hostile.state.creatures["3"].resting = true
	hostile.state.next_id = 4
	_check(report, _solve(profile, hostile, report, {"without_player": {"abilities": ["sting"]}}).get("status") == "refuted",
		"player exclusions do not remove a matching enemy ability that readies next turn")
	for invalid: Variant in [[], "damage", {"opponent": ["damage"]}, {"casts": "ZAPP"}, {"effects": [1]}, {"abilities": [""]}]:
		_check(report, _solve(profile, entry, report, {"without_player": invalid}).get("status") == "invalid",
			"malformed operation restrictions are explicitly rejected")

static func run(profile: ELProfile) -> Dictionary:
	var report := {"checks": 0, "failures": 0, "results": [], "edition": profile.id}
	_operation_exclusions(profile, report)
	var entry := _entry(profile)
	var definition_before := JSON.stringify(entry, "", false)
	var forced := _solve(profile, entry, report)
	_check(report, forced.get("status") == "forced" and int(forced.get("witness_tactics", 0)) == 2,
		"two damage points require two actual casts")
	_check(report, forced.get("strategy", {}).get("min_actions") == 2 and forced.get("strategy", {}).get("max_actions") == 2
		and forced.get("strategy", {}).get("min_tactics") == 2 and forced.get("strategy", {}).get("max_tactics") == 2,
		"unbranched two-cast strategy has exact action and tactic extrema")
	_check(report, JSON.stringify(entry, "", false) == definition_before, "proof leaves input snapshot unchanged")
	_check(report, _solve(profile, entry, report, {"max_tactics": 1}).get("status") == "refuted",
		"one-cast restriction rules out every winning strategy")
	_check(report, _solve(profile, entry, report, {"max_tactics": 0}).get("status") == "refuted",
		"passing without tactics cannot solve the damage puzzle")
	_replay(profile, entry, forced.get("witness", []), report)

	var delayed := entry.duplicate(true)
	delayed.turns = 2
	delayed.state.heroes[0].mana = 1
	delayed.state.heroes[0].channels = 1
	var future := _solve(profile, delayed, report)
	_check(report, future.get("status") == "forced" and int(future.get("witness_tactics", 0)) == 2,
		"refilled mana enables the second cast on the next own turn")
	_check(report, future.get("witness", []).any(func(move: Dictionary) -> bool: return int(move.side) == 1),
		"multi-turn witness contains the opponent's response")
	_check(report, _solve(profile, delayed, report, {"max_tactics": 1}).get("status") == "refuted",
		"tactic restriction is not reset at a turn boundary")
	_replay(profile, delayed, future.get("witness", []), report)
	delayed.turns = 1
	_check(report, _solve(profile, delayed, report).get("status") == "refuted",
		"the same two-turn combination fails with a one-turn deadline")

	# The opponent can recall and restore an inherited attacker before ending
	# its phase. That reaches an identical later combat position with two fewer
	# actions available. A cached win must still fit that remaining depth.
	var transposition := entry.duplicate(true)
	transposition.state.attacker = 1
	transposition.state.creatures = {"2": _creature(profile, 2, 1)}
	transposition.state.next_id = 3
	transposition.state.attacks = [2]
	var six_actions := _solve(profile, transposition, report, {"depth": 6})
	_check(report, six_actions.get("status") == "forced" and six_actions.get("witness", []).size() == 6,
		"cached winning strategies preserve their longest opponent branch")
	_check(report, _solve(profile, transposition, report, {"depth": 5}).get("status") == "unknown",
		"a cached six-action strategy cannot certify a five-action search")
	_replay(profile, transposition, six_actions.get("witness", []), report)
	_check(report, six_actions.get("strategy", {}).get("min_actions") == 4 and six_actions.get("strategy", {}).get("max_actions") == 6
		and six_actions.get("strategy", {}).get("max_player_turns") == 1,
		"cached strategy metrics retain the longest branch and defender-start own-turn count")
	_two_turn_replies(profile, report)
	_live_advice(profile, report)
	_advice_descriptions(profile, report)
	_complete_ability_choices(profile, report)
	_recipe_advice_branches(profile, report)
	_new_recipe_advice_branches(profile, report)

	var combat := entry.duplicate(true)
	combat.state.heroes[0].hand = []
	combat.state.heroes[0].hand_slots = []
	combat.state.heroes[1].health = 1
	combat.state.creatures = {"2": _creature(profile, 2, 0)}
	combat.state.next_id = 3
	_check(report, _solve(profile, combat, report).get("status") == "forced", "unblocked attacker has a lethal line")
	combat.state.creatures["3"] = _creature(profile, 3, 1)
	combat.state.next_id = 4
	# This supplied reference wins only if the defender deliberately passes.
	# An ordering hint must not suppress the blocking response.
	combat.solution = [{"kind": "attack", "id": 2}, {"kind": "end_phase"}, {"kind": "end_phase"}]
	_check(report, _solve(profile, combat, report).get("status") == "refuted",
		"legal blocking refutes a cooperative reference solution")
	combat.state.creatures["4"] = _creature(profile, 4, 0)
	combat.state.next_id = 5
	combat.erase("solution")
	var through_block := _solve(profile, combat, report)
	_check(report, through_block.get("status") == "forced", "two attackers beat every assignment of one blocker")
	_check(report, through_block.get("witness", []).any(func(move: Dictionary) -> bool: return move.kind == "block"),
		"principal line includes the opponent's longer blocking response")
	_replay(profile, combat, through_block.get("witness", []), report)
	var sliced := _solve(profile, combat, report, {}, true)
	_check(report, sliced.get("status") == through_block.get("status") and sliced.get("witness") == through_block.get("witness"),
		"one-operation time slices preserve proof and witness deterministically")
	_compare_full(profile, combat, report, "two attackers against a blocker")
	combat.state.attacks = [4, 2]
	_compare_full(profile, combat, report, "inherited attacker ordering")

	var orders := entry.duplicate(true)
	orders.state.heroes[0].hand = []
	orders.state.heroes[0].hand_slots = []
	orders.state.heroes[1].health = 1000000
	orders.state.heroes[1].maximum = 1000000
	orders.state.creatures = {"2": _creature(profile, 2, 0), "3": _creature(profile, 3, 0), "4": _creature(profile, 4, 0)}
	orders.state.next_id = 5
	orders.state.attacks = [3, 2]
	_assignment_equivalence(profile, orders, report, "inherited attack subset and order")
	orders.state.phase = ELDuel.Phase.DEFENCE
	orders.state.attacker = 1
	orders.state.creatures["2"].owner = 1
	orders.state.attacks = [2]
	orders.state.blocks = {"4": 2, "3": 2}
	_assignment_equivalence(profile, orders, report, "inherited blocker insertion order")

	# Repeated paid declarations are useful: each attack tax triggers thorns,
	# and Ethereal Chain reflects it. A zero-power Halo wins by paying three
	# times, recalling between payments. These actions are never pure toggles.
	var taxed := entry.duplicate(true)
	taxed.state.heroes[0].hand = []
	taxed.state.heroes[0].hand_slots = []
	taxed.state.heroes[0].mana = 3
	taxed.state.heroes[1].mana = 0
	taxed.state.heroes[1].health = 3 if profile.id == "el1" else 6
	taxed.state.creatures = {"2": _creature(profile, 2, 0, "RVHL")}
	taxed.state.next_id = 3
	taxed.state.next_enchantment = 4
	for index in 3:
		taxed.state.heroes[0].enchantments.append({"id": index + 1, "card": ["LSDS", "MNTH", "ETCH"][index],
			"power": 0, "toughness": 0, "owner": 0, "born": 3, "used": false})
	var tax_proof := _compare_full(profile, taxed, report, "material attack-tax repetitions")
	_check(report, tax_proof.get("status") == "forced" and tax_proof.get("witness", []).size() == 5,
		"three paid declarations with two recalls remain a winning tactic")
	_replay(profile, taxed, tax_proof.get("witness", []), report)
	var tax_duel := ELDuel.new()
	if tax_duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": taxed.state.duplicate(true)}):
		_check(report, ELPuzzleAdvice._next_action(tax_duel, tax_proof.get("witness", [])) == tax_proof.witness[0],
			"advice cannot remove paid attack repetitions as though they were pure toggles")

	var guarded := entry.duplicate(true)
	guarded.state.heroes[0].hand = []
	guarded.state.heroes[0].hand_slots = []
	guarded.state.heroes[1].health = 3
	guarded.state.creatures = {"2": _creature(profile, 2, 0, "KBGD"), "3": _creature(profile, 3, 0, "KBEL")}
	guarded.state.next_id = 4
	var guard_duel := ELDuel.new()
	if guard_duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": guarded.state.duplicate(true)}):
		_check(report, not ELPuzzleProof._assignment_segment(guard_duel, true).enabled,
			"TeamAttack dependency disables canonical assignment pruning")
	var guard_proof := _compare_full(profile, guarded, report, "TeamAttack partner dependency")
	_check(report, guard_proof.get("status") == "forced" and int(guard_proof.get("equivalent_assignments_skipped", -1)) == 0,
		"guard and partner win without pruning dependency-sensitive assignments")
	guarded.state.creatures["2"] = _creature(profile, 2, 0)
	guarded.state.creatures["2"].granted = ["Berserk"]
	if guard_duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": guarded.state.duplicate(true)}):
		_check(report, not ELPuzzleProof._assignment_segment(guard_duel, true).enabled,
			"compulsory Berserk assignments also disable the reduction")

	var unfinished := _solve(profile, entry, report, {"budget": 1})
	_check(report, unfinished.get("status") == "unknown",
		"node exhaustion is unknown, never a fabricated loss")
	_check(report, unfinished.get("strategy", {}) == {}, "unfinished proof exposes no certified strategy metrics")
	_check(report, _solve(profile, entry, report, {"depth": 1}).get("status") == "unknown",
		"unresolved action-depth cutoff is unknown")
	_check(report, _solve(profile, entry, report, {"depth": 0}).get("status") == "invalid", "invalid proof depth is rejected")
	var unsupported := entry.duplicate(true)
	unsupported.objective = {"type": "win", "finish_health": 10}
	_check(report, _solve(profile, unsupported, report).get("status") == "invalid", "unsupported extra objective is not certified")
	unsupported = entry.duplicate(true)
	unsupported.state.setup.puzzle_fixed_hands = false
	_check(report, _solve(profile, unsupported, report).get("status") == "invalid", "unfixed random draws are not certified")
	unsupported = entry.duplicate(true)
	unsupported.state.heroes[0].artifacts = [{"name": "CustomProof", "spell": "BDEX", "charges": 1,
		"ready_round": 0, "custom": {"elk_name": "Proof artifact", "spell": "BDEX", "first": 0,
			"gap": 0, "max": 1, "icon": -1, "r_count": 0, "r_duration": 0}}]
	var unsupported_artifact := _solve(profile, unsupported, report)
	_check(report, unsupported_artifact.get("status") == "invalid" and String(unsupported_artifact.get("reason", "")).contains("Custom spell artifacts"),
		"custom spell artifact second choices are explicitly outside the complete proof scope")
	var artifact_attempt := ELPuzzles.Run.new()
	artifact_attempt.begin_entry(profile, entry, false, false)
	artifact_attempt.duel.heroes[0].artifacts = unsupported.state.heroes[0].artifacts.duplicate(true)
	var artifact_advice := _advice(artifact_attempt, report)
	_check(report, artifact_advice.get("status") == "error" and not artifact_advice.has("command"),
		"live advice does not certify an unenumerated custom spell artifact position")

	var duel := ELDuel.new()
	var restored := duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.state.duplicate(true)})
	_check(report, restored, "independent move-enumeration fixture restores")
	if restored:
		duel.searching = true
		var copies := {}
		for move: Dictionary in ELPuzzleProof.legal_moves(duel):
			if move.kind == "cast": copies[int(move.index)] = true
		_check(report, copies.size() == 2, "both identical hand-card indices are enumerated")
		var unchanged := ELPuzzleProof._position(duel)
		_check(report, not ELPuzzleProof.apply(duel, {"kind": "cast", "card": "ZAPP", "target": 1, "side": 1}),
			"wrong-side witness assertion is rejected")
		_check(report, ELPuzzleProof._position(duel) == unchanged, "rejected side assertion leaves duel unchanged")
		duel.rng_state += 1
		_check(report, ELPuzzleProof._position(duel) != unchanged, "proof identity retains exact random-generator state")
	print("PROOF_CHECK %s checks=%d failures=%d" % [profile.id, report.checks, report.failures])
	return report
