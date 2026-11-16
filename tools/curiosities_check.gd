extends "puzzle_lab.gd"
## Content QA using actual battle rules and the Run observer copied by the lab.
## A losing example is not proof that all continuations from its prefix lose.

func _attempt(profile: ELProfile, entries: Array, entry: Dictionary) -> ELPuzzles.Run:
	ELPuzzles._lists[profile.id] = entries
	var attempt := ELPuzzles.Run.new()
	if not attempt.begin(profile, entries.find(entry)):
		printerr("RESTORE %s: %s" % [entry.id, attempt.error])
		return null
	attempt.duel.searching = true
	return attempt

func _coverage(profile: ELProfile, entries: Array, entry: Dictionary) -> Dictionary:
	var attempt := _attempt(profile, entries, entry)
	if attempt == null: return {"ok": false, "error": "Could not restore reference"}
	var missing: Array = []
	for index in entry.solution.size():
		var command := _command(attempt.duel, entry.solution[index])
		var canonical := _ordering_command(attempt.duel, command)
		var found := false
		for legal: Dictionary in _legal_moves(attempt.duel):
			if _same_action(legal, canonical):
				found = true
				break
		if not found: missing.append({"step": index + 1, "command": command})
		if not ELCombatSearch.apply(attempt.duel, command):
			return {"ok": false, "missing": missing, "step": index + 1, "error": attempt.duel.error}
	return {"ok": missing.is_empty(), "missing": missing, "checked_actions": entry.solution.size(),
		"scope": "All reference actions occur in the lab move list; not an exhaustive move-generator proof."}

func _simple_attempt(profile: ELProfile, entries: Array, entry: Dictionary, mode: String) -> Dictionary:
	var attempt := _attempt(profile, entries, entry)
	if attempt == null: return {"outcome": "error", "error": "Could not restore baseline"}
	var duel := attempt.duel
	duel.smart_sides.assign([1])
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_budget = 200000
	var trace: Array = []
	for step in 160:
		var terminal := _terminal(duel)
		if terminal != 0:
			return {"outcome": "solved" if terminal == 1 else "failed", "steps": step, "trace": trace,
				"opponent": "Goal-aware game AI, 200000-node setting per decision"}
		var side := duel.active_side()
		var command: Dictionary
		if side == 1: command = ELCombatSearch.think(duel, {})
		elif mode == "charge": command = _charge(duel)
		else: command = {"kind": "end_phase"}
		if command.is_empty(): command = {"kind": "end_phase"}
		if not ELCombatSearch.apply(duel, command):
			return {"outcome": "error", "steps": step, "error": duel.error, "command": command, "trace": trace}
		attempt.watch()
		trace.append({"side": side, "command": command, "terminal": _terminal(duel)})
	return {"outcome": "unknown", "steps": 160, "trace": trace}

func _run() -> void:
	var path := _arg("file")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if document is not Dictionary or document.get("puzzles") is not Array or document.puzzles.is_empty():
		printerr("Expected a nonempty puzzle pack: " + path)
		quit(2)
		return
	var edition := String(document.game)
	var profile := _profile(edition, document.puzzles)
	if profile == null:
		quit(2)
		return
	ELPuzzles.remember = false
	var results: Array = []
	for entry: Dictionary in document.puzzles:
		current_entry = entry
		initial = entry.state
		var result := {"id": entry.id, "edition": edition,
			"definition": {"state": entry.state.duplicate(true), "turns": entry.turns,
				"objective": entry.get("objective", {"type": "win"}).duplicate(true),
				"solution": entry.solution.duplicate(true), "refutations": entry.get("refutations", []).duplicate(true)}}
		var attempt := _attempt(profile, document.puzzles, entry)
		if attempt == null:
			result.error = "Restore failed"
			results.append(result)
			failures += 1
			continue
		result.initial_terminal = _terminal(attempt.duel)
		result.solution = _replay(attempt.duel, entry.solution, attempt)
		result.action_coverage = _coverage(profile, document.puzzles, entry)
		if result.initial_terminal != 0 or not result.solution.ok or result.solution.get("terminal") != 1 or not result.action_coverage.ok:
			failures += 1
		result.alternative_solutions = []
		for alternative: Dictionary in entry.get("alternative_solutions", []):
			attempt = _attempt(profile, document.puzzles, entry)
			var alternate_replay := _replay(attempt.duel, alternative.commands, attempt)
			result.alternative_solutions.append({"label": alternative.get("label", ""),
				"commands": alternative.commands.duplicate(true), "replay": alternate_replay})
			if not alternate_replay.ok or alternate_replay.get("terminal") != 1:
				failures += 1
		var branches: Array = []
		for refutation: Dictionary in entry.get("refutations", []):
			var branch := {"label": refutation.get("label", "")}
			attempt = _attempt(profile, document.puzzles, entry)
			branch.prefix = _replay(attempt.duel, refutation.get("commands", []), attempt)
			if not branch.prefix.ok: failures += 1
			branch.evidence = "terminal loss" if branch.prefix.ok and branch.prefix.get("terminal") == -1 else "live prefix; no loss demonstrated here"
			if refutation.has("failure_line"):
				attempt = _attempt(profile, document.puzzles, entry)
				branch.failure_line = _replay(attempt.duel, refutation.failure_line, attempt)
				if branch.failure_line.ok and branch.failure_line.get("terminal") == -1:
					branch.evidence = "legal losing continuation (not a proof of irrecoverability)"
				else: failures += 1
			branches.append(branch)
		result.refutations = branches
		if _arg("baselines") == "true":
			result.baselines = {}
			for mode in ["pass", "charge"]:
				result.baselines[mode] = _simple_attempt(profile, document.puzzles, entry, mode)
				if result.baselines[mode].outcome != "failed": failures += 1
		results.append(result)
		print("CHECKED " + String(entry.id))
	var report := {"fixture": "Checked-in wiki card data; actual ELDuel GDScript rules and Run observer",
		"scope": "Reference replay, initial objective, authored-action coverage, explicit losing examples and optional naive policies; no universal forced-win claim",
		"count": results.size(), "failures": failures, "results": results}
	if not _arg("report").is_empty():
		var file := FileAccess.open(_arg("report"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("CURIOSITIES QA puzzles=%d failures=%d" % [results.size(), failures])
	quit(1 if failures > 0 else 0)
