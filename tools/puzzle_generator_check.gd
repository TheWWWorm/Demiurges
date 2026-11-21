extends SceneTree
## Test the production generator and the production puzzle observer together.
## Invoke through puzzle_generator_check.py for the asset-free fixture.

const ProofChecks = preload("puzzle_proof_check.gd")

var failures := 0
var checks := 0
var generated: Array = []
var timings: Array = []
var invariant_editions := {}
var rows: Array = []
var session_rows: Array = []
var plan_counts := {}
var decision_counts := {}
var decision_structures := {}
var decision_families := {}
var session_decision_counts := {}
var proof_reports: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, fallback := "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value == "--" + key: return "true"
		if value.begins_with("--" + key + "="): return value.substr(key.length() + 3)
	return fallback

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAILED " + label)

func _profile(edition: String) -> ELProfile:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var profile := ELProfile.new()
	profile.id = edition
	profile.title = edition
	profile.tables = fixture[edition].duplicate(true)
	profile.texts = profile.tables.texts.duplicate()
	var levels := {}
	for level in range(1, 21): levels["Level%d" % level] = 0
	profile.tables.CombatManaIncome = {"1": levels}
	profile.tables.CombatSceneDB = {"Green.001": {}}
	profile.tables.HeroTemplates = {}
	for name: String in profile.tables.HeroTemplateSources:
		profile.tables.HeroTemplates[name] = {"BaseHealth": 20, "HealthIncrease": 0}
	return profile

func _finish(job: RefCounted, quota := 32, usecs := 6000) -> Dictionary:
	var calls := 0
	var maximum_step := 0
	while not job.done:
		var before := Time.get_ticks_usec()
		job.step(quota, usecs)
		maximum_step = maxi(maximum_step, Time.get_ticks_usec() - before)
		calls += 1
		if calls > 1000000:
			_expect(false, "job did not terminate")
			return {}
	job.result["test_step_calls"] = calls
	job.result["test_maximum_step_ms"] = maximum_step / 1000.0
	return job.result

func _replay(profile: ELProfile, entry: Dictionary) -> bool:
	var solved_before := ELPuzzles._solved.duplicate(true)
	var mastery_before := ELPuzzles._mastery.duplicate(true)
	var definition_before := JSON.stringify(entry)
	var run := ELPuzzles.Run.new()
	if not run.begin_entry(profile, entry, false, false):
		_expect(false, "runtime restore " + run.error)
		return false
	for raw: Dictionary in entry.solution:
		if not run.outcome.is_empty() or int(raw.get("side", run.duel.active_side())) != run.duel.active_side():
			_expect(false, "witness side / command after terminal")
			return false
		if not ELCombatSearch.apply(run.duel, ELPuzzleProof.command(run.duel, raw)):
			_expect(false, "illegal witness " + run.duel.error)
			return false
		run.watch()
	_expect(run.outcome == "solved", "witness reaches runtime solved")
	_expect(ELPuzzles._solved == solved_before and ELPuzzles._mastery == mastery_before, "generated play does not change progress")
	_expect(JSON.stringify(entry) == definition_before, "playing does not mutate reusable definition")
	return run.outcome == "solved"

func _invariants(profile: ELProfile, entry: Dictionary) -> void:
	var meta: Dictionary = entry.generated
	var decoded := ELPuzzleGenerator.parse_code(meta.code)
	_expect(decoded.get("ok", false) and decoded.seed == meta.seed and decoded.difficulty == meta.difficulty and decoded.edition == profile.id, "code round trip")
	_expect(ELPuzzleGenerator.parse_code("ELP6:%s:5:17" % profile.id).get("ok", false), "Master is a supported share-code tier")
	for invalid: String in ["", "ELP1:el1:3:1", "ELP2:el1:3:1", "ELP3:el1:3:1", "ELP4:el1:3:1", "ELP5:el1:3:1", "ELP6:el3:3:1", "ELP6:el1:1:1", "ELP6:el1:6:1", "ELP6:el1:3:0", "ELP6:el1:3:-1", "ELP6:el1:3:2147483648", "ELP6:el1:3:99999999999999999999", "ELP6:el1:3:1e3"]:
		_expect(not ELPuzzleGenerator.parse_code(invalid).get("ok", false), "reject malformed code " + invalid)
	var retry := _finish(ELPuzzleGenerator.start(profile, meta.seed, meta.difficulty), 1, 1)
	_expect(not retry.get("entry", {}).is_empty(), "same seed with tiny slices succeeds")
	if not retry.get("entry", {}).is_empty():
		_expect(JSON.stringify(retry.entry.state, "", false) == JSON.stringify(entry.state, "", false), "same seed has same ordered position independent of time slices")
		_expect(JSON.stringify(retry.entry.solution, "", false) == JSON.stringify(entry.solution, "", false), "same seed has same witness independent of time slices")
	var inventory := ELPuzzleGenerator.spell_inventory(profile, entry)
	_expect(inventory.cards == meta.get("spell_cards", []) and inventory.roles == meta.get("spell_roles", []),
		"spell exposure is taken from the performed reference, not unused hand cards")
	var decoy := entry.duplicate(true)
	decoy.state.heroes[0].hand.append("STRT")
	_expect(ELPuzzleGenerator.spell_inventory(profile, decoy) == inventory,
		"an unused hand card does not manufacture spell variety")
	var renamed := entry.duplicate(true)
	ELPuzzleGenerator._shuffle_layout(renamed, 97341, profile)
	_expect(ELPuzzleGenerator.tactical_signature(renamed) == meta.tactical_signature, "layout and hand order do not count as material novelty")
	# Fingerprint uses the independently verified recipe line, so map that
	# reference too when testing a second presentation shuffle.
	var reference := entry.duplicate(true)
	reference.solution = meta.recipe_solution.duplicate(true)
	reference.generated.erase("recipe_solution")
	ELPuzzleGenerator._shuffle_layout(reference, 97341, profile)
	_expect(ELPuzzleGenerator.plan_signature(profile, reference) == meta.plan_signature, "plan fingerprint ignores entity IDs and commuting presentation changes")
	_expect(ELPuzzleGenerator.decision_signature(profile, reference) == meta.decision_signature, "decision fingerprint ignores entity IDs and presentation changes")
	var history := ELPuzzleGenerator.Session.new()
	history.note(entry)
	history.note(entry)
	_expect(history.recent().size() == 1, "retrying a code does not fill recent history")
	_expect(history.recent()[0].variant_key == ELPuzzleGenerator.variant_key(entry), "history retains the semantic variant independently of fine plan changes")
	_expect(history.recent()[0].decision == meta.decision_signature, "history remembers the cross-family decision graph")
	var history_copy := history.recent()
	history_copy.clear()
	_expect(history.recent().size() == 1, "history snapshot cannot mutate session")
	var cancelled := history.start(profile, meta.difficulty)
	cancelled.step(1, 1)
	_expect(history.recent().size() == 1, "generation and cancellation do not record an unplayed puzzle")
	cancelled = null
	for index in ELPuzzleGenerator.Session.MAX_RECENT:
		var filler := entry.duplicate(true)
		filler.generated.code = "history-%d" % index
		filler.generated.tactical_signature = "material-%d" % index
		history.note(filler)
	_expect(history.recent().size() == ELPuzzleGenerator.Session.MAX_RECENT, "history keeps a bounded window")
	history.note(entry)
	var newer := entry.duplicate(true)
	newer.generated.code = "history-newest"
	newer.generated.tactical_signature = "material-newest"
	history.note(newer)
	_expect(history.recent().any(func(record: Dictionary) -> bool: return record.signature == meta.tactical_signature), "manual replay refreshes recency before the next eviction")
	var exhausted := _finish(ELPuzzleProof.start(profile, entry, {"budget": 1, "depth": 24}))
	_expect(exhausted.get("status") == "unknown", "search budget exhaustion is unknown")
	var shallow := _finish(ELPuzzleProof.start(profile, entry, {"budget": 100, "depth": 0}))
	_expect(shallow.get("status") == "invalid", "invalid depth bound is rejected")
	var unsupported := entry.duplicate(true)
	unsupported.objective = {"type": "clear"}
	_expect(_finish(ELPuzzleProof.start(profile, unsupported)).get("status") == "invalid", "unsupported objective is not certified")
	var wrong_edition := entry.duplicate(true)
	wrong_edition.state.profile = "el2" if profile.id == "el1" else "el1"
	_expect(_finish(ELPuzzleProof.start(profile, wrong_edition)).get("status") == "invalid", "wrong edition is rejected")
	var seen: Array = []
	var visited := {}
	var family := String(meta.family)
	for _i in ELPuzzleGenerator.available_families(profile.id, meta.difficulty).size():
		var seed_value := ELPuzzleGenerator.new_seed(profile, meta.difficulty, family)
		var next := ELPuzzleGenerator.family_for_seed(profile.id, seed_value, meta.difficulty)
		_expect(next != family, "next changes tactical family")
		seen.append(next)
		visited[next] = true
		family = next
	_expect(seen.size() == ELPuzzleGenerator.available_families(profile.id, meta.difficulty).size() and visited.size() == seen.size(), "next visits every family before repeating")
	var first := ELPuzzles.Run.new()
	var second := ELPuzzles.Run.new()
	_expect(first.begin_entry(profile, entry, false, false) and second.begin_entry(profile, entry, false, false), "two independent attempts start")
	first.duel.heroes[0].health = 0
	_expect(second.duel.heroes[0].health == int(entry.state.heroes[0].health), "retries own independent state")

func _selection_checks(profile: ELProfile) -> void:
	var saved_rng := ELPuzzleGenerator._seed_rng
	ELPuzzleGenerator._seed_rng = RandomNumberGenerator.new()
	ELPuzzleGenerator._seed_rng.seed = 329443
	var families := ELPuzzleGenerator.available_families(profile.id, 4)
	var history: Array = []
	var counts := {}
	var cycles := {}
	for cycle in 3:
		var visited: Array = []
		for index in families.size():
			var ordered := ELPuzzleGenerator.family_schedule(profile, 4, history)
			_expect(ordered.size() == families.size() and ordered.all(func(family: String) -> bool: return family in families), "balanced schedule retains supported families")
			var chosen: String = ordered[0]
			_expect(not chosen in visited, "balanced shuffle covers every family before the next cycle")
			if not history.is_empty(): _expect(chosen != history[-1].family, "balanced selection avoids the immediately previous mechanic")
			visited.append(chosen)
			counts[chosen] = int(counts.get(chosen, 0)) + 1
			history.append({"edition": profile.id, "difficulty": 4, "family": chosen})
			var seed_value := ELPuzzleGenerator.seed_for_family(profile, 4, chosen)
			_expect(seed_value >= 1 and seed_value <= ELPuzzleGenerator.MAX_SEED and ELPuzzleGenerator.family_for_seed(profile.id, seed_value, 4) == chosen, "family-selected seed retains code-only determinism")
		cycles[JSON.stringify(visited)] = true
	_expect(cycles.size() > 1 and counts.values().all(func(count: int) -> bool: return count == 3), "fresh family order varies while balancing encounters")
	ELPuzzleGenerator._seed_rng.seed = 7751
	var own_order := ELPuzzleGenerator.family_schedule(profile, 4, history)
	history.append({"edition": "el2" if profile.id == "el1" else "el1", "difficulty": 4, "family": own_order[0]})
	ELPuzzleGenerator._seed_rng.seed = 7751
	_expect(ELPuzzleGenerator.family_schedule(profile, 4, history) == own_order, "another edition does not bias family selection")
	var variant_history: Array = [{"edition": profile.id, "difficulty": 5, "family": "restless_horizon",
		"variant": "deny_reply_spell", "variant_key": "restless_horizon:deny_reply_spell", "signature": "one", "plan": "fine-plan-one", "decision": "reply-denial"}]
	var fresh := ELPuzzleGenerator.FreshJob.new()
	fresh._start(profile, 5, variant_history)
	fresh._family_order = ["restless_horizon"]
	fresh._select_family()
	_expect(fresh._preferred_variants == ["heal_before_reply"], "semantic novelty prefers the unplayed response to a hostile spell")
	variant_history.append({"edition": profile.id, "difficulty": 5, "family": "restless_horizon",
		"variant": "heal_before_reply", "variant_key": "restless_horizon:heal_before_reply", "signature": "two", "plan": "fine-plan-two", "decision": "prepare-survival"})
	fresh = ELPuzzleGenerator.FreshJob.new()
	fresh._start(profile, 5, variant_history)
	fresh._family_order = ["restless_horizon"]
	fresh._select_family()
	_expect(fresh._preferred_variants == ["deny_reply_spell"], "finite semantic variants rotate by recency after each has been encountered")
	var alternate := {"entry": {"state": {"profile": profile.id}, "generated": {
		"family": "restless_horizon", "variant": "heal_before_reply", "tactical_signature": "new-material-a", "plan_signature": "new-plan-a", "decision_signature": "prepare-survival"}}}
	fresh._proofs = 1
	_expect(fresh._offer(alternate) and not fresh.done and not fresh._fallback.is_empty(), "a certified but unpreferred variant is retained while seeking an alternative")
	var preferred := alternate.duplicate(true)
	preferred.entry.generated.variant = "deny_reply_spell"
	preferred.entry.generated.tactical_signature = "new-material-b"
	preferred.entry.generated.plan_signature = "new-plan-b"
	preferred.entry.generated.decision_signature = "different-decisions"
	fresh._proofs = 2
	_expect(fresh._offer(preferred) and fresh.done and fresh.result.entry.generated.variant == "deny_reply_spell", "the bounded second proof can select a genuinely different verified variant")
	fresh = ELPuzzleGenerator.FreshJob.new()
	fresh._start(profile, 5, variant_history)
	fresh._family_order = ["restless_horizon"]
	fresh._select_family()
	fresh._proofs = 1
	fresh._offer(alternate)
	fresh._proofs = ELPuzzleGenerator.FreshJob.MAX_PROOFS
	fresh.step(1, 1)
	_expect(fresh.done and fresh.result.entry.generated.tactical_signature == "new-material-a" and not fresh.result.variety.preferred_variant_matched,
		"exhausting the novelty search still delivers its certified non-repeating fallback honestly")
	fresh = ELPuzzleGenerator.FreshJob.new()
	fresh._start(profile, 5, variant_history)
	var repeated := alternate.duplicate(true)
	repeated.entry.generated.tactical_signature = "one"
	_expect(not fresh._offer(repeated) and fresh._fallback.is_empty(), "a repeated material position can never become the novelty fallback")
	fresh._proofs = 2
	fresh._total_nodes = 5931
	_expect(fresh._can_prove(), "two cheap duplicate results leave room for a full ordinary recovery job")
	fresh._total_nodes = ELPuzzleGenerator.node_limit(5)
	_expect(fresh._can_prove(), "an exactly fitting final full job is allowed at the combined node boundary")
	fresh._total_nodes = ELPuzzleGenerator.node_limit(5) + 1
	_expect(not fresh._can_prove(), "a new full job cannot exceed the original two-job node ceiling")
	fresh._total_nodes = 0
	fresh._proofs = ELPuzzleGenerator.FreshJob.MAX_PROOFS
	_expect(not fresh._can_prove(), "zero-node failures cannot create an unbounded retry loop")
	var duplicate_plan: Dictionary = preferred.entry.generated.duplicate(true)
	duplicate_plan.family = "entirely-new-family-name"
	duplicate_plan.variant = "new-label"
	duplicate_plan.plan_signature = "fresh-editorial-plan"
	duplicate_plan.decision_signature = "prepare-survival"
	_expect(not fresh._novel_decision(duplicate_plan), "relabeling a family or plan cannot make its recent decisions new")
	var genuinely_different: Dictionary = duplicate_plan.duplicate()
	genuinely_different.decision_signature = "another-mechanism"
	_expect(fresh._preference(genuinely_different, []) > fresh._preference(duplicate_plan, ["new-label"]), "cross-family decision diversity outranks a preferred variant label")
	var window_history: Array = []
	for index in ELPuzzleGenerator.FreshJob.DECISION_WINDOW + 2:
		window_history.append({"edition": profile.id, "difficulty": 4, "family": "rising_floor", "signature": str(index), "decision": "d%d" % index})
	fresh = ELPuzzleGenerator.FreshJob.new()
	fresh._start(profile, 4, window_history)
	_expect(fresh._decisions.size() == ELPuzzleGenerator.FreshJob.DECISION_WINDOW and not fresh._decisions.has("d0") and fresh._decisions.has("d13"), "decision preference uses a finite, explicit recent window")
	ELPuzzleGenerator._seed_rng = saved_rng

func _decision_checks(profile: ELProfile) -> void:
	var entry := ProofChecks._entry(profile)
	entry.state.heroes[0].mana = 10
	entry.state.heroes[0].channels = 0
	entry.state.heroes[0].hand = ["MGHT"]
	entry.state.heroes[0].hand_slots = [-1]
	entry.state.heroes[1].health = 1
	entry.state.creatures = {"2": ProofChecks._creature(profile, 2, 0, "CAFG"), "3": ProofChecks._creature(profile, 3, 0, "CAFG")}
	entry.state.next_id = 4
	entry.solution = [{"kind": "cast", "card": "MGHT", "target": 2}, {"kind": "ability", "id": 2, "key": "spores", "target": 1}]
	var signature := ELPuzzleGenerator.decision_signature(profile, entry)
	_expect(not signature.is_empty(), "decision fixture replays to a real victory")
	var padded := entry.duplicate(true)
	padded.state.creatures["99"] = ProofChecks._creature(profile, 99, 1, "WLAR")
	padded.state.creatures["99"].resting = true
	padded.state.next_id = 100
	_expect(ELPuzzleGenerator.decision_signature(profile, padded) == signature, "an untouched resting body cannot manufacture decision novelty")
	var changed := entry.duplicate(true)
	changed.id = "new-title"
	changed.title = "An unrelated story"
	changed.generated = {"family": "new-family", "variant": "new-variant", "mechanics": ["invented novelty"], "development_requirements": [{"effect": "unrelated"}]}
	changed.state.heroes[0].health = 37
	changed.state.heroes[0].maximum = 37
	changed.state.heroes[0].mana = 17
	changed.state.heroes[0].hand = ["STRG"]
	changed.solution[0].card = "STRG"
	_expect(ELPuzzleGenerator.decision_signature(profile, changed) == signature, "family labels, story, numeric resources and same-direction numeric bonuses cannot manufacture decision novelty")
	ELPuzzleGenerator._shuffle_layout(changed, 381234, profile)
	_expect(ELPuzzleGenerator.decision_signature(profile, changed) == signature, "decision graph is invariant under layout and entity renumbering")
	changed = entry.duplicate(true)
	changed.solution[1].id = 3
	_expect(ELPuzzleGenerator.decision_signature(profile, changed) != signature, "enhance A then sacrifice A differs from enhance A then sacrifice identical B")
	var independent := entry.duplicate(true)
	independent.state.heroes[0].hand = ["MGHT", "SHSK"]
	independent.state.heroes[0].hand_slots = [-1, -1]
	independent.solution.insert(1, {"kind": "cast", "card": "SHSK", "target": 3})
	var order := ELPuzzleGenerator.decision_signature(profile, independent)
	changed = independent.duplicate(true)
	changed.solution[0] = independent.solution[1].duplicate()
	changed.solution[1] = independent.solution[0].duplicate()
	_expect(not order.is_empty() and ELPuzzleGenerator.decision_signature(profile, changed) == order, "commuting independent preparations have one decision structure")
	independent.solution[1].target = 2
	order = ELPuzzleGenerator.decision_signature(profile, independent)
	changed = independent.duplicate(true)
	changed.solution[0] = independent.solution[1].duplicate()
	changed.solution[1] = independent.solution[0].duplicate()
	_expect(not order.is_empty() and ELPuzzleGenerator.decision_signature(profile, changed) == order, "commuting power and armour preparations on the same piece do not invent ordering novelty")
	changed.state.heroes[0].hand.reverse()
	_expect(ELPuzzleGenerator.decision_signature(profile, changed) == order, "hand presentation order is absent from the decision graph")
	var dependent := entry.duplicate(true)
	dependent.state.creatures["2"] = ProofChecks._creature(profile, 2, 0, "SPFG")
	dependent.state.heroes[0].hand = ["ENFL", "ENAL"]
	dependent.state.heroes[0].hand_slots = [-1, -1]
	dependent.solution = [{"kind": "cast", "card": "ENFL", "target": 3}, {"kind": "cast", "card": "ENAL"}, entry.solution[1].duplicate()]
	order = ELPuzzleGenerator.decision_signature(profile, dependent)
	changed = dependent.duplicate(true)
	changed.solution[0] = dependent.solution[1].duplicate()
	changed.solution[1] = dependent.solution[0].duplicate()
	var reverse := ELPuzzleGenerator.decision_signature(profile, changed)
	_expect(not order.is_empty() and not reverse.is_empty() and order != reverse, "consequential rest/ready ordering on shared material remains visible")
	var enabling := entry.duplicate(true)
	enabling.state.heroes[0].hand = ["MGHT", "ENAL"]
	enabling.state.heroes[0].hand_slots = [-1, -1]
	enabling.state.creatures["3"] = ProofChecks._creature(profile, 3, 0, "MNTS")
	enabling.state.creatures["3"].resting = true
	enabling.state.creatures["4"] = ProofChecks._creature(profile, 4, 1, "WLAR")
	enabling.state.next_id = 5
	enabling.solution = [entry.solution[0].duplicate(), {"kind": "cast", "card": "ENAL"},
		{"kind": "ability", "id": 3, "key": "tap_target", "target": 4}, entry.solution[1].duplicate()]
	order = ELPuzzleGenerator.decision_signature(profile, enabling)
	changed = enabling.duplicate(true)
	changed.solution[0] = enabling.solution[1].duplicate()
	changed.solution[1] = enabling.solution[0].duplicate()
	_expect(not order.is_empty() and ELPuzzleGenerator.decision_signature(profile, changed) == order, "independent preparation crossing an enable/use chain cannot manufacture dependencies")
	var marked := entry.duplicate(true)
	marked.state.heroes[0].hand = []
	marked.state.heroes[0].hand_slots = []
	marked.state.heroes[0].enchantments = [{"id": 17, "card": "ENRG", "owner": 0, "born": 1, "power": 0, "toughness": 0}]
	marked.state.next_enchantment = 18
	marked.state.creatures["2"] = ProofChecks._creature(profile, 2, 0, "SPFG")
	marked.state.creatures["2"].resting = true
	marked.solution = [{"kind": "ability", "id": 0, "key": "energize:17", "target": 2}, entry.solution[1].duplicate()]
	order = ELPuzzleGenerator.decision_signature(profile, marked)
	changed = marked.duplicate(true)
	changed.state.heroes[0].enchantments[0].id = 91
	changed.state.next_enchantment = 92
	changed.solution[0].key = "energize:91"
	_expect(not order.is_empty() and ELPuzzleGenerator.decision_signature(profile, changed) == order, "hero ability source-copy numbers are not structural novelty")
	marked.state.heroes[0].hand = ["MGHT", "ENRG"]
	marked.state.heroes[0].hand_slots = [-1, -1]
	marked.state.heroes[0].enchantments = []
	marked.state.next_enchantment = 1
	marked.solution = [{"kind": "cast", "card": "MGHT", "target": 3}, {"kind": "cast", "card": "ENRG"},
		{"kind": "ability", "id": 0, "key": "energize:2", "target": 2}, entry.solution[1].duplicate()]
	order = ELPuzzleGenerator.decision_signature(profile, marked)
	changed = marked.duplicate(true)
	changed.solution[0] = marked.solution[1].duplicate()
	changed.solution[1] = marked.solution[0].duplicate()
	changed.solution[2].key = "energize:1"
	_expect(not order.is_empty() and ELPuzzleGenerator.decision_signature(profile, changed) == order, "independent buff crossing ability creation/use keeps source-copy identity without its allocation order")
	var structure := ELPuzzleGenerator.decision_structure(profile, entry)
	var encoded := JSON.stringify(structure)
	_expect(not encoded.contains("MGHT") and not encoded.contains("CAFG") and not encoded.contains(profile.id) and not encoded.contains("new-family"), "decision report contains functional roles instead of card codes, edition or recipe labels")
	changed = entry.duplicate(true)
	changed.solution[0].target = 99
	_expect(ELPuzzleGenerator.decision_structure(profile, changed).is_empty(), "illegal reference cannot produce a structural novelty claim")
	var accounting := ELPuzzleRecipes.build(profile, "funeral_math", 1, 2)
	var accounting_signature := ELPuzzleGenerator.decision_signature(profile, accounting)
	for carrier: String in ["GROG", "LMWA", "SHWL", "IRMC"]:
		var carrier_case := accounting.duplicate(true)
		carrier_case.state.creatures[2] = ProofChecks._creature(profile, 2, 0, carrier)
		carrier_case.state.heroes[1].health = int(profile.table("CombatCreatures")[carrier].Power)
		_expect(not accounting_signature.is_empty() and ELPuzzleGenerator.decision_signature(profile, carrier_case) == accounting_signature,
			"unused printed combat traits cannot relabel a spell-only power accounting plan: " + carrier)
	var ids := {2: 8, 3: 9}
	for key: String in ["combine:17", "burnout:17", "recycle:17"]:
		var command := {"kind": "ability", "id": 0, "key": key, "target": 2, "choice": 3, "amount": 2}
		ELPuzzleGenerator._remap_command(command, ids, profile)
		_expect(command.target == 8 and command.choice == 9 and command.key == key and command.amount == 2, "layout maps both creature choices without corrupting ability source or scalar: " + key)
	var swap := {"kind": "cast", "card": "TRAD", "target": 2, "grave": 3, "power": 2}
	ELPuzzleGenerator._remap_command(swap, ids, profile)
	_expect(swap.target == 8 and swap.grave == 9 and swap.power == 2, "layout maps a swap spell's overloaded second creature selector")
	for card: String in ["PRFY", "BDEX"]:
		var command := {"kind": "cast", "card": card, "target": 2, "grave": 3}
		ELPuzzleGenerator._remap_command(command, ids, profile)
		_expect(command.target == 8 and command.grave == 3, "layout keeps grave/enchantment selectors outside the creature namespace: " + card)

func _generator_semantics(profile: ELProfile) -> void:
	var entry := ProofChecks._entry(profile)
	entry.turns = 2
	entry.state.heroes[0].mana = 1
	entry.state.heroes[0].channels = 1
	entry.state.heroes[0].health = 2
	entry.state.creatures = {"2": ProofChecks._creature(profile, 2, 1, "KBSH")}
	entry.state.creatures["2"].resting = true
	entry.state.next_id = 3
	var after_pass := ELPuzzleGenerator.mistake_position(profile, entry, [{"kind": "end_phase", "side": 0}])
	_expect(after_pass.get("ok", false) and after_pass.get("remaining_own_turns") == 1,
		"empty first attack consumes one own turn when verifying a committed mistake")
	var one_turn := entry.duplicate(true)
	one_turn.turns = 1
	_expect(not ELPuzzleGenerator.mistake_position(profile, one_turn, [{"kind": "end_phase", "side": 0}]).get("ok", false),
		"mistake continuation never invents a fresh turn after the allowance is spent")
	var with_attacker := entry.duplicate(true)
	with_attacker.state.creatures["3"] = ProofChecks._creature(profile, 3, 0)
	with_attacker.state.next_id = 4
	var during_defence := ELPuzzleGenerator.mistake_position(profile, with_attacker, [{"kind": "attack", "id": 3}, {"kind": "end_phase", "side": 0}])
	_expect(during_defence.get("ok", false) and during_defence.get("remaining_own_turns") == 2 and during_defence.entry.state.attacker == 0,
		"enemy defence still belongs to the current own turn in mistake verification")
	_expect(not ELPuzzleGenerator.mistake_position(profile, entry, [{"kind": "end_phase", "side": 0}, {"kind": "end_phase", "side": 1}]).get("ok", false),
		"mistakes cannot rely on a prescribed cooperative enemy reply")
	var win := _finish(ELPuzzleProof.start(profile, entry, {"depth": 44}))
	var shortcut := _finish(ELPuzzleProof.start(profile, entry, {"depth": 44, "max_tactics": 1}))
	var shorter := entry.duplicate(true)
	shorter.turns = 1
	var horizon := _finish(ELPuzzleProof.start(profile, shorter, {"depth": 44}))
	_expect(win.get("status") == "forced" and shortcut.get("status") == "refuted" and horizon.get("status") == "refuted", "conditional acceptance fixture has genuine tactic and turn floors")
	entry.solution = win.get("witness", []).duplicate(true)
	var structure := ELPuzzleGenerator.plan_structure(profile, entry)
	_expect(structure.get("phases", []).any(func(phase: Dictionary) -> bool: return phase.own_turn == 2 and phase.side == 0), "plan fingerprint follows the second own turn after an empty attack")
	var phases: Array = structure.get("phases", [])
	_expect(phases.size() >= 2 and phases[0].side == 0 and phases[0].phase == ELDuel.Phase.ATTACK
		and phases[1].side == 1 and phases[1].phase == ELDuel.Phase.ATTACK,
		"the initial empty attack passes directly to the hostile attack in plan fingerprints")
	var cooperative: Array = [{"kind": "cast", "card": "ZAPP", "target": 1, "side": 0},
		{"kind": "end_phase", "side": 0}, {"kind": "ability", "id": 2, "key": "sting", "target": 1, "side": 1}]
	var replay := ELPuzzleGenerator.replay_line(profile, entry, cooperative)
	_expect(replay.ok and replay.tactics == 1 and replay.turns == 1, "a cooperative reply may shorten the principal replay without lowering guaranteed difficulty")
	var trap_command := {"kind": "cast", "card": "ZAPP", "target": 0, "side": 0}
	var duel := ELDuel.new()
	var legal := duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": entry.state.duplicate(true)})
	legal = legal and ELPuzzleProof.apply(duel, trap_command)
	_expect(legal, "conditional fixture's tempting self-damage is legal")
	var altered := entry.duplicate(true)
	altered.state = duel.snapshot()
	altered.erase("solution")
	var trap := _finish(ELPuzzleProof.start(profile, altered, {"depth": 44}))
	_expect(trap.get("status") == "refuted", "conditional fixture has a fully refuted legal mistake")
	entry.solution = cooperative.duplicate(true)
	entry.generated = {"version": ELPuzzleGenerator.VERSION, "seed": 1, "difficulty": 3,
		"family": "acceptance-regression", "code": ELPuzzleGenerator.code(profile.id, 3, 1)}
	var job := ELPuzzleGenerator.Job.new()
	job._profile = profile
	job._difficulty = 3
	job._candidate = entry
	job._win = win.duplicate(true)
	job._win.witness = cooperative.duplicate(true)
	job._horizon = horizon
	job._trap = {"label": "Spend health before the hostile Shaman wakes", "commands": [trap_command], "proof": {"status": trap.get("status"), "nodes": trap.get("nodes", 0)}}
	job._accept(shortcut)
	_expect(job.done and not job.result.get("entry", {}).is_empty(), "acceptance uses the adversarial tactic certificate instead of rejecting a shorter cooperative trace")
	if job.done and not job.result.get("entry", {}).is_empty():
		var verification: Dictionary = job.result.entry.generated.verification
		_expect(verification.guaranteed_strategy_tactic_floor == 2 and verification.witness_tactical_actions == 1 and verification.guaranteed_strategy_turn_floor == 2,
			"stored guarantee and individual replay measurements stay distinct")

func _run() -> void:
	ELPuzzles.remember = false
	var editions: Array = ["el1", "el2"] if _arg("edition", "both") == "both" else [_arg("edition")]
	var difficulties: Array = [2, 3, 4, 5] if _arg("difficulty", "all") == "all" else [int(_arg("difficulty"))]
	var samples := int(_arg("samples", "1"))
	var offset := int(_arg("offset", "0"))
	var requested: Dictionary = {}
	if not _arg("code").is_empty():
		requested = ELPuzzleGenerator.parse_code(_arg("code"))
		if not requested.get("ok", false):
			printerr(requested.get("error", "Invalid challenge code."))
			quit(2)
			return
		editions = [requested.edition]
		difficulties = [requested.difficulty]
		samples = 1
	var signature_counts := {}
	var started := Time.get_ticks_msec()
	for edition: String in editions:
		var profile := _profile(edition)
		if _arg("skip-invariants") != "true":
			var proof_checks := ProofChecks.run(profile)
			proof_reports.append(proof_checks)
			checks += int(proof_checks.checks)
			failures += int(proof_checks.failures)
			_generator_semantics(profile)
			_selection_checks(profile)
			_decision_checks(profile)
		for difficulty: int in difficulties:
			var families := ELPuzzleGenerator.available_families(edition, difficulty)
			for index in families.size():
				var family: String = families[index]
				if not requested.is_empty():
					if family != ELPuzzleGenerator.family_for_seed(edition, requested.seed, difficulty): continue
				elif not _arg("family").is_empty() and family != _arg("family"): continue
				for sample in samples:
					var seed_value := (12345 + (sample + offset) * 7919) * families.size() + index + 1
					if not requested.is_empty(): seed_value = int(requested.seed)
					var result := _finish(ELPuzzleGenerator.start(profile, seed_value, difficulty))
					var row := {"edition": edition, "difficulty": difficulty, "family": family, "seed": seed_value,
						"attempts": result.get("attempts", 0), "nodes": result.get("nodes", 0), "elapsed_ms": result.get("elapsed_ms", 0),
						"maximum_step_ms": result.get("test_maximum_step_ms", 0), "step_calls": result.get("test_step_calls", 0),
						"rejections": result.get("rejections", {}), "error": result.get("error", "")}
					rows.append(row)
					_expect(not result.get("entry", {}).is_empty(), "generate %s/%d/%s/%d: %s" % [edition, difficulty, family, seed_value, row.error])
					if result.get("entry", {}).is_empty():
						print("REJECTED " + JSON.stringify(row))
						continue
					var entry: Dictionary = result.entry
					generated.append(entry)
					timings.append(float(row.elapsed_ms))
					var signature := ELPuzzleGenerator.tactical_signature(entry)
					signature_counts[signature] = int(signature_counts.get(signature, 0)) + 1
					row.signature = signature
					row.plan_signature = entry.generated.plan_signature
					row.decision_signature = entry.generated.decision_signature
					decision_counts[row.decision_signature] = int(decision_counts.get(row.decision_signature, 0)) + 1
					if not decision_structures.has(row.decision_signature): decision_structures[row.decision_signature] = ELPuzzleGenerator.decision_structure(profile, entry)
					if not decision_families.has(row.decision_signature): decision_families[row.decision_signature] = []
					if not decision_families[row.decision_signature].has(family): decision_families[row.decision_signature].append(family)
					_expect(not String(row.decision_signature).is_empty() and not decision_structures[row.decision_signature].is_empty(), "accepted reference has a cross-family decision description")
					row.variant = entry.generated.get("variant", "")
					row.code = entry.generated.code
					_expect(row.variant in ELPuzzleRecipes.variants(family, difficulty), "semantic variant is declared for this family and tier")
					row.mechanics = entry.generated.get("mechanics", [])
					plan_counts[row.plan_signature] = int(plan_counts.get(row.plan_signature, 0)) + 1
					row.verification = entry.generated.verification
					_expect(entry.generated.verification.forced_win and entry.generated.verification.shortcut_status == "refuted", "forced victory and shortcut rejection")
					_expect(entry.generated.verification.get("recipe_reference_replay", false), "shuffled reference behind hints also replays")
					_expect(entry.generated.verification.get("reference_and_witness_playable", false), "reference and principal player abilities are available through the battle interface")
					_expect(entry.generated.verification.get("meaningful_mistake", {}).get("proof", {}).get("status") == "refuted", "a legal natural mistake loses the guaranteed win")
					_expect(int(entry.turns) <= 2 and int(entry.turns) >= 1, "short turn horizon")
					if int(entry.turns) == 2:
						_expect(entry.generated.verification.get("short_horizon_status") == "refuted", "two-turn position has no guaranteed one-turn shortcut")
					if difficulty == 5:
						_expect(int(entry.turns) == 2 and int(entry.generated.verification.guaranteed_strategy_tactic_floor) >= 4, "Master requires a two-turn plan and four tactical actions in its guaranteed strategy")
						_expect(int(entry.generated.verification.get("strategy", {}).get("max_enemy_decisions", 0)) >= 1, "Master's certified strategy includes an adversarial choice")
					_expect(not entry.generated.verification.get("strategy", {}).is_empty(), "winning proof retains certified strategy metrics")
					_replay(profile, entry)
					if not invariant_editions.has(edition) and _arg("skip-invariants") != "true":
						_invariants(profile, entry)
						invariant_editions[edition] = true
					print("OK " + JSON.stringify(row))
					_write_reports(signature_counts, started)
			if int(_arg("session-samples", "0")) > 0:
				_session_checks(profile, difficulty, int(_arg("session-samples")))
	_expect(not generated.is_empty(), "at least one challenge generated")
	_write_reports(signature_counts, started)
	print("TOTAL generated=%d unique_positions=%d distinct_reference_plans=%d distinct_decision_graphs=%d session_generated=%d checks=%d failures=%d elapsed_ms=%d" % [generated.size(), signature_counts.size(), plan_counts.size(), decision_counts.size(), session_rows.size(), checks, failures, Time.get_ticks_msec() - started])
	quit(1 if failures > 0 else 0)

func _session_checks(profile: ELProfile, difficulty: int, count: int) -> void:
	var saved_rng := ELPuzzleGenerator._seed_rng
	ELPuzzleGenerator._seed_rng = RandomNumberGenerator.new()
	ELPuzzleGenerator._seed_rng.seed = 7331 + difficulty * 100 + (1 if profile.id == "el2" else 0)
	var session := ELPuzzleGenerator.Session.new()
	var recent: Array = []
	var cycle := {}
	var family_count := ELPuzzleGenerator.available_families(profile.id, difficulty).size()
	for index in count:
		var before := session.recent()
		var result := _finish(session.start(profile, difficulty))
		_expect(session.recent() == before, "only launching a delivered puzzle records history")
		_expect(not result.get("entry", {}).is_empty(), "fresh session %s/%d/%d: %s" % [profile.id, difficulty, index, result.get("error", "")])
		if result.get("entry", {}).is_empty(): continue
		var entry: Dictionary = result.entry
		var metadata: Dictionary = entry.generated
		_expect(not recent.has(metadata.tactical_signature), "fresh session avoids recent material repeats")
		_expect(not result.get("variety", {}).get("recent_position_repeated", true), "session reports its verified non-repeat gate")
		_expect(int(result.get("nodes", 0)) <= ELPuzzleGenerator.node_limit(difficulty) * ELPuzzleGenerator.FreshJob.NODE_BUDGET_MULTIPLIER
			and int(result.variety.proof_jobs) <= ELPuzzleGenerator.FreshJob.MAX_PROOFS, "fresh recovery stays within its node ceiling and job cap")
		_expect(int(result.variety.previews) <= ELPuzzleGenerator.FreshJob.MAX_PROPOSALS, "fresh decision previews remain bounded")
		var decisions: Array = []
		for record: Dictionary in before:
			if record.get("edition") == profile.id and not String(record.get("decision", "")).is_empty(): decisions.append(record.decision)
		decisions = decisions.slice(maxi(0, decisions.size() - ELPuzzleGenerator.FreshJob.DECISION_WINDOW))
		var repeated := decisions.has(metadata.decision_signature)
		_expect(result.variety.recent_decision_repeated == repeated and result.variety.decision_preference_relaxed == repeated,
			"fresh session honestly reports repeated decisions instead of claiming family labels as novelty")
		var repeated_family: bool = cycle.has(metadata.family)
		if index < family_count: cycle[metadata.family] = true
		session_decision_counts[metadata.decision_signature] = int(session_decision_counts.get(metadata.decision_signature, 0)) + 1
		recent.append(metadata.tactical_signature)
		while recent.size() > ELPuzzleGenerator.Session.MAX_RECENT: recent.pop_front()
		session.note(entry)
		if index == 0:
			var replay := _finish(ELPuzzleGenerator.start(profile, metadata.seed, difficulty))
			_expect(not replay.get("entry", {}).is_empty(), "session-selected code also works outside its history")
			if not replay.get("entry", {}).is_empty():
				_expect(JSON.stringify(entry, "", false) == JSON.stringify(replay.entry, "", false), "history never changes a shared code's complete entry")
			_replay(profile, entry)
		var row := {"edition": profile.id, "difficulty": difficulty, "index": index, "family": metadata.family,
			"code": metadata.code, "variant": metadata.get("variant", "base"), "signature": metadata.tactical_signature, "plan_signature": metadata.plan_signature,
			"decision_signature": metadata.decision_signature, "family_repeated_in_initial_cycle": repeated_family if index < family_count else false,
			"elapsed_ms": result.elapsed_ms, "nodes": result.nodes, "variety": result.variety}
		session_rows.append(row)
		print("FRESH " + JSON.stringify(row))
	ELPuzzleGenerator._seed_rng = saved_rng

func _write_reports(signatures: Dictionary, started: int) -> void:
	var destination := _arg("report-dir")
	if destination.is_empty(): return
	var ordered := timings.duplicate()
	ordered.sort()
	var cross_family: Array = []
	for decision: String in decision_families:
		if decision_families[decision].size() > 1: cross_family.append({"decision_signature": decision, "families": decision_families[decision], "count": decision_counts[decision]})
	var report := {"checks": checks, "failures": failures, "generated": generated.size(), "unique_positions": signatures.size(),
		"proof_reports": proof_reports,
		"distinct_reference_plans": plan_counts.size(), "session_rows": session_rows,
		"decision_proxy": "Replay-derived anonymous effects, participants, phase boundaries and observed ordering. One reference per puzzle; no claim of human uniqueness or exhaustive strategy diversity.",
		"distinct_decision_graphs": decision_counts.size(), "decision_distribution": decision_counts,
		"decision_structures": decision_structures, "cross_family_decision_overlaps": cross_family,
		"session_distinct_decision_graphs": session_decision_counts.size(), "session_decision_distribution": session_decision_counts,
		"elapsed_ms": Time.get_ticks_msec() - started, "rows": rows,
		"median_generation_ms": ordered[ordered.size() / 2] if not ordered.is_empty() else 0,
		"maximum_generation_ms": ordered[-1] if not ordered.is_empty() else 0}
	var file := FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for edition: String in ["el1", "el2"]:
		var entries: Array = generated.filter(func(entry: Dictionary) -> bool: return entry.state.profile == edition)
		if entries.is_empty(): continue
		file = FileAccess.open(destination.path_join(edition + "-generated.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"format": "etherlords-puzzles", "version": 2, "game": edition, "puzzles": entries}, "\t"))
		file.close()
