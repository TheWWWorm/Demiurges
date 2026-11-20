extends SceneTree
## Mechanical offer-distribution audit, not a combat or win-rate test.
## Uses wiki-backed printed cards, recorded starter books, real seeded routes,
## and ELExpeditionRun._offered_cards/_prepare_shop. No battles or saves occur.
## godot --headless --path game --script ../tools/expedition_draft_audit.gd -- \
##   --fixture=/path/to/expedition_balance/fixture.json --seeds=64 \
##   --output=/tmp/expedition-draft-audit.jsonl

const DraftCheck := preload("arena_draft_check.gd")
const STARTERS := {"Red": "STR1", "Green": "STG1", "Blue": "STU1", "Black": "STB1"}
var checks := 0
var failures := 0
var cases := 0
var boundary_cases := 0
var output: FileAccess
var profile: ELProfile
var fixture := {}

func _arg(name: String, fallback := "") -> String:
	var prefix := "--" + name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	if failures <= 20: printerr("FAIL: " + label)

func _write(row: Dictionary) -> void:
	output.store_line(JSON.stringify(row, "", true, true))
	output.flush()

func _run() -> void:
	var fixture_path := _arg("fixture")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if raw is not Dictionary or raw.get("expedition_balance") is not Dictionary or raw.expedition_balance.get("books") is not Dictionary:
		printerr("Supply the generated Expedition balance --fixture, including recorded starter books.")
		quit(1)
		return
	fixture = raw
	profile = DraftCheck.synthetic_profile(fixture_path)
	if profile == null:
		quit(1)
		return
	output = FileAccess.open(_arg("output", "user://expedition-draft-audit.jsonl"), FileAccess.WRITE)
	if output == null:
		printerr("Could not open audit output.")
		quit(1)
		return
	var seeds := clampi(int(_arg("seeds", "64")), 1, 128)
	var seed_base := int(_arg("seed-base", "0"))
	var began := Time.get_ticks_msec()
	var budget := clampi(int(_arg("total-ms", "120000")), 1000, 600000)
	_write({"type": "settings", "fixture": fixture_path, "seeds": seeds, "seed_base": seed_base,
		"rules_version": 10, "battle_simulations": 0,
		"scope": "Real reward/shop functions over printed cards and recorded starter books; constructed room state, no claimed run or combat outcomes."})
	var totals := _counts()
	for faction: String in STARTERS:
		for path: Dictionary in ELExpeditionPaths.paths(profile, faction):
			for act in range(1, 4):
				var group := _counts()
				for index in seeds:
					if Time.get_ticks_msec() - began >= budget:
						_write({"type": "limit", "path": path.id, "act": act, "next_seed": seed_base + index,
							"cases_completed": cases, "checks": checks, "failures": failures})
						output.close()
						quit(2)
						return
					var result := _case(profile, path, act, seed_base + index)
					for key: String in group:
						group[key] += int(result[key])
						totals[key] += int(result[key])
					cases += 1
				_boundaries(path, act, seed_base)
				_write({"type": "group", "path": path.id, "faction": faction, "act": act, "counts": group})
				print("DRAFT %s act%d: reward focus %d/%d vs baseline %d/%d; merchant focus %d/%d vs baseline %d/%d" % [path.id, act,
					group.reward_focused, group.samples, group.reward_baseline, group.samples,
					group.shop_focused, group.samples, group.shop_baseline, group.samples])
	var summary := {"type": "summary", "complete": true, "cases": cases, "boundary_cases": boundary_cases,
		"reward_and_shop_pairs": cases * 2, "checks": checks, "failures": failures,
		"elapsed_ms": Time.get_ticks_msec() - began, "counts": totals, "battle_simulations": 0}
	_write(summary)
	output.close()
	print("DRAFT AUDIT: ", JSON.stringify(summary))
	quit(1 if failures > 0 else 0)

func _counts() -> Dictionary:
	return {"samples": 0, "reward_candidates_available": 0, "reward_baseline": 0, "reward_focused": 0,
		"shop_candidates_available": 0, "shop_baseline": 0, "shop_focused": 0,
		"reward_first_two_preserved": 0, "shop_first_three_preserved": 0,
		"baseline_reward_focus_cards": 0, "focused_reward_focus_cards": 0,
		"baseline_shop_focus_cards": 0, "focused_shop_focus_cards": 0}

func _run_at(source: ELProfile, faction: String, act: int, seed: int, cards: Array[String]) -> ELExpeditionRun:
	var chosen := ELDuelPresets.normalize({"id": "Recorded" + STARTERS[faction], "name": "Recorded starter benchmark",
		"faction": faction, "resource_level": 1, "level": 1, "cards": cards,
		"skills": {"PRVD": 0}, "specialization": "NONE", "artifacts": []})
	var run := ELExpeditionRun.new()
	run._version = 10
	run._reset(source, chosen, seed, act)
	run.deck.assign(cards)
	run.health = run.max_health
	return run

func _book(faction: String) -> Array[String]:
	var cards: Array[String] = []
	cards.assign(fixture.expedition_balance.books[STARTERS[faction]].cards)
	return cards

func _offers(run: ELExpeditionRun, path: String, shop: bool) -> Array[String]:
	run.study_path = path
	if shop:
		for room: Dictionary in run._nodes.values():
			if room.kind == "shop":
				run.current = room.id
				break
		run.phase = "shop"
		run._prepare_shop()
		return run._shop_stock.duplicate()
	run.current = str(run._route[0][0].id)
	run.phase = "reward"
	return run._offered_cards()

func _case(source: ELProfile, path: Dictionary, act: int, seed: int) -> Dictionary:
	var run := _run_at(source, path.faction, act, seed, _book(path.faction))
	var pool := run._eligible_spells()
	var focus := ELExpeditionPaths.candidates(source, path.id, pool, act)
	var result := _counts()
	result.samples = 1
	for shop: bool in [false, true]:
		var baseline := _offers(run, "none", shop)
		var focused := _offers(run, path.id, shop)
		var prefix := "%s/act%d/seed%d/%s: " % [path.id, act, seed, "shop" if shop else "reward"]
		var expected := 4 if shop else 3
		var kept := 3 if shop else 2
		_check(baseline.size() == expected and focused.size() == expected, prefix + "offer count unchanged")
		_check(baseline.slice(0, kept) == focused.slice(0, kept), prefix + "normal preference slots unchanged")
		_check(source.table("CombatSpells")[focused[0]].get("Class") == "Creature" and source.table("CombatSpells")[focused[1]].get("Class") != "Creature", prefix + "creature and noncreature preference retained")
		_check(_valid_offers(run, baseline) and _valid_offers(run, focused), prefix + "offers are unique, legal, and below the four-copy cap")
		var selected := _in_focus(focused, focus)
		var natural := _in_focus(baseline, focus)
		_check(focus.is_empty() or selected > 0, prefix + "an available affordable focus appears")
		var remaining: Array[String] = pool.duplicate()
		for code: String in focused.slice(0, kept): remaining.erase(code)
		var slot_focus := ELExpeditionPaths.candidates(source, path.id, remaining, act)
		_check(slot_focus.is_empty() or focused[kept] in slot_focus, prefix + "only the designated final slot is focused")
		var name := "shop" if shop else "reward"
		result[name + "_candidates_available"] = int(not focus.is_empty())
		result[name + "_focused"] = int(selected > 0)
		result[name + "_baseline"] = int(natural > 0)
		result["baseline_" + name + "_focus_cards"] = natural
		result["focused_" + name + "_focus_cards"] = selected
		result["shop_first_three_preserved" if shop else "reward_first_two_preserved"] = int(baseline.slice(0, kept) == focused.slice(0, kept))
	return result

func _valid_offers(run: ELExpeditionRun, cards: Array[String]) -> bool:
	var seen := {}
	for code: String in cards:
		if seen.has(code) or run.deck.count(code) >= 4 or not ELDuelCosts.spell_allowed(run.profile, code, run.preset.faction) or ELCatalog.rule(run.profile, code).is_empty(): return false
		seen[code] = true
	return true

func _in_focus(cards: Array[String], focus: Array[String]) -> int:
	var count := 0
	for code: String in cards:
		if code in focus: count += 1
	return count

func _boundaries(path: Dictionary, act: int, seed: int) -> void:
	var run := _run_at(profile, path.faction, act, seed, _book(path.faction))
	var focus := ELExpeditionPaths.candidates(profile, path.id, run._eligible_spells(), act)
	if focus.is_empty():
		_check(false, str(path.id) + ": boundary fixture requires an affordable focus card")
		return
	var capped := str(focus[(act - 1) % focus.size()])
	for copies in [4, 5]:
		run.deck.assign(_book(path.faction))
		for index in run.deck.size():
			if run.deck.count(capped) >= copies: break
			if run.deck[index] != capped: run.deck[index] = capped
		_check(run.deck.count(capped) == copies, "Construct %d-copy boundary" % copies)
		for shop: bool in [false, true]:
			_check(capped not in _offers(run, path.id, shop), "%s/act%d: %d owned copies excluded from %s" % [path.id, act, copies, "shop" if shop else "reward"])
		boundary_cases += 1
	# Small catalogs retain real printed rows but deliberately contain only
	# two focus spells, both already owned at four copies, or no focus spells.
	# Each constructed active book is a legal16-card book; no battles occur.
	for exhausted: bool in [true, false]:
		var outside: Array[String] = []
		var bodies: Array[String] = []
		var support: Array[String] = []
		for code: String in profile.table("CombatSpells"):
			if code in path.cards or not ELDuelCosts.spell_allowed(profile, code, path.faction) or ELCatalog.rule(profile, code).is_empty(): continue
			if profile.table("CombatSpells")[code].get("Class") == "Creature": bodies.append(code)
			else: support.append(code)
		bodies.sort()
		support.sort()
		outside.append_array(bodies.slice(0, 5))
		outside.append_array(support.slice(0, 5))
		var chosen: Array[String] = outside.duplicate()
		if exhausted: chosen.append_array(focus.slice(0, 2))
		var narrow := ELProfile.new()
		narrow.id = "el2"
		narrow.tables = profile.tables.duplicate(true)
		narrow.tables.CombatSpells = {}
		for code: String in chosen: narrow.tables.CombatSpells[code] = profile.tables.CombatSpells[code].duplicate(true)
		var book: Array[String] = []
		var owned: Array[String] = [outside[0], outside[5]]
		if exhausted: owned.append_array(focus.slice(0, 2))
		else: owned.append_array([outside[1], outside[6]])
		for code: String in owned:
			for copy in 4: book.append(code)
		var sample := _run_at(narrow, path.faction, act, seed, book)
		_check(ELExpeditionPaths.candidates(narrow, path.id, sample._eligible_spells(), act).is_empty(), str(path.id) + ": boundary truly has no eligible focus")
		for shop: bool in [false, true]:
			var baseline := _offers(sample, "none", shop)
			var focused := _offers(sample, path.id, shop)
			_check(baseline == focused and _valid_offers(sample, focused), "%s/act%d: %s focus keeps exact ordinary %s" % [path.id, act, "copy-exhausted" if exhausted else "missing", "merchant" if shop else "reward"])
		boundary_cases += 1
