extends "res://puzzle_generator_check.gd"
## Audit real effects/relationships and remove claimed essential operations.
## No family name, editorial tag or semantic label enters a decision signature.

const ORIGINAL_FAMILIES := ["rising_floor", "crossfire", "air_corridor", "breakthrough", "pin_and_strike", "sheltered_sweep", "promotion", "inversion", "reservoir", "counterattack", "reserve_counter", "restless_horizon", "grave_clock", "borrowed_army", "survivor_route", "control_fork"]

func _run() -> void:
	ELPuzzles.remember = false
	var inputs: Variant = JSON.parse_string(_arg("files", "[]"))
	var records: Array = []
	var decisions := {}
	var families := {}
	var original_decisions := {}
	var all_operations := 0
	var proven_essential := 0
	var begun := Time.get_ticks_msec()
	_expect(inputs is Array and not inputs.is_empty(), "at least one input pack is supplied")
	if inputs is not Array: inputs = []
	for source: String in inputs:
		var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		_expect(pack is Dictionary and pack.get("game", "") in ["el1", "el2"] and pack.get("puzzles") is Array, "valid per-edition input pack")
		if pack is not Dictionary or pack.get("game", "") not in ["el1", "el2"] or pack.get("puzzles") is not Array: continue
		var profile := _profile(String(pack.game))
		for entry: Dictionary in pack.puzzles:
			var metadata: Dictionary = entry.get("generated", {})
			var family := String(metadata.get("family", "unclassified"))
			var structure := ELPuzzleGenerator.decision_structure(profile, entry)
			var signature := "" if structure.is_empty() else JSON.stringify(structure).sha256_text()
			_expect(not signature.is_empty(), "reference has a valid completed decision structure: " + String(entry.get("id", "")))
			if signature.is_empty(): continue
			var reference: Array = metadata.get("recipe_solution", entry.get("solution", []))
			var replay := ELPuzzleGenerator.replay_line(profile, entry, reference)
			_expect(replay.get("ok", false), "reference is playable through the actual puzzle Run")
			var row := {"edition": profile.id, "family": family, "variant": metadata.get("variant", "base"),
				"code": metadata.get("code", ""), "id": entry.get("id", ""), "decision_signature": signature,
				"decision_structure": structure, "reference_solved": replay.get("ok", false), "operation_audits": []}
			if not families.has(family): families[family] = {"entries": 0, "decisions": {}, "essential_audits": 0}
			families[family].entries += 1
			families[family].decisions[signature] = true
			if not decisions.has(signature): decisions[signature] = {"families": {}, "entries": 0, "editions": {}}
			decisions[signature].families[family] = true
			decisions[signature].editions[profile.id] = true
			decisions[signature].entries += 1
			if family in ORIGINAL_FAMILIES: original_decisions[signature] = true
			var requirements: Variant = metadata.get("development_requirements", [])
			_expect(requirements is Array, "operation requirements are an array")
			if requirements is not Array: requirements = []
			var unrestricted_status := "not_requested"
			if not requirements.is_empty():
				var unrestricted := _finish(ELPuzzleProof.start(profile, entry, {"budget": int(_arg("budget", "24000")), "depth": 24 if int(entry.turns) == 1 else 44}))
				unrestricted_status = String(unrestricted.get("status", "invalid"))
				row.unrestricted = {"status": unrestricted_status, "nodes": unrestricted.get("nodes", 0), "elapsed_ms": unrestricted.get("elapsed_ms", 0)}
				_expect(unrestricted_status == "forced", "a mechanism-necessity audit first establishes an unrestricted forced win")
			for requirement: Variant in requirements:
				var valid: bool = requirement is Dictionary and not String(requirement.get("label", "")).is_empty() and requirement.get("without_player") is Dictionary and not requirement.without_player.is_empty()
				_expect(valid, "a claimed essential operation names a nonempty player restriction")
				if not valid: continue
				var result := _finish(ELPuzzleProof.start(profile, entry, {"without_player": requirement.without_player,
					"budget": int(_arg("budget", "24000")), "depth": 24 if int(entry.turns) == 1 else 44}))
				var audit := {"label": requirement.label, "without_player": requirement.without_player,
					"status": result.get("status", "invalid"), "nodes": result.get("nodes", 0), "elapsed_ms": result.get("elapsed_ms", 0)}
				if result.get("status") == "forced": audit.counterexample = result.get("witness", [])
				row.operation_audits.append(audit)
				all_operations += 1
				if result.get("status") == "refuted" and unrestricted_status == "forced":
					proven_essential += 1
					families[family].essential_audits += 1
				_expect(result.get("status") == "refuted", "distinctive operation is necessary for a guaranteed win: %s / %s / %s" % [profile.id, family, requirement.label])
			records.append(row)
			print("VARIETY %s/%s/%s operations=%d" % [profile.id, family, row.code, row.operation_audits.size()])
	var overlaps: Array = []
	for signature: String in decisions:
		if decisions[signature].families.size() > 1:
			var names: Array = decisions[signature].families.keys()
			names.sort()
			overlaps.append({"decision_signature": signature, "families": names, "entries": decisions[signature].entries})
	var family_report := {}
	for family: String in families:
		var novel := 0
		for signature: String in families[family].decisions:
			if not original_decisions.has(signature): novel += 1
		family_report[family] = {"entries": families[family].entries, "distinct_decisions": families[family].decisions.size(),
			"decisions_absent_from_original_families": novel, "essential_operation_audits": families[family].essential_audits}
	for family: String in _arg("require-new-families").split(",", false):
		_expect(not original_decisions.is_empty(), "new-decision comparison includes original-family samples")
		_expect(family_report.has(family) and int(family_report[family].decisions_absent_from_original_families) > 0,
			"new family has an observed decision structure absent from the original-family samples: " + family)
	_expect(not records.is_empty(), "at least one reference was audited")
	var report := {"checks": checks, "failures": failures, "entries": records.size(), "distinct_decisions": decisions.size(),
		"original_family_decisions": original_decisions.size(), "operation_audits": all_operations, "proven_essential_operations": proven_essential,
		"by_family": family_report, "cross_family_overlaps": overlaps, "rows": records, "elapsed_ms": Time.get_ticks_msec() - begun,
		"scope": "Replay-derived decision structures are descriptive, not human novelty or difficulty ratings. Operation refutations restrict only the listed player actions; all opposing choices remain available. Comparisons cover the supplied samples, not all possible seeds."}
	var file := FileAccess.open(_arg("report"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("VARIETY_TOTAL entries=%d decisions=%d essential=%d/%d checks=%d failures=%d" % [records.size(), decisions.size(), proven_essential, all_operations, checks, failures])
	quit(1 if failures > 0 else 0)
