extends SceneTree
## Version 10 run identity and commitment checks. Synthetic tables and maps
## exercise real run/duel/checkpoint code; victories used by lifecycle tests
## are explicitly forced and are not estimates of combat difficulty.
## godot --headless --path game --script ../tools/expedition_v10_check.gd

const Fixture := preload("expedition_fixture.gd")
const ROOT := "user://expedition_v10_check"
const RULES := 10
# The gate is evaluated before its own check increments this counter.
const MIN_CHECKS := 278
const GOLDEN := {
	8: {"route": "4e43b2b819fb93aa312c0580cd1a7a9891fb3344ba5bfa0af3958405ca9e1d22", "content": "170c379d30b7d95750ea757f0a28518ac48e3655a8332e863d7cd39520a67d87"},
	9: {"route": "5bdc346fee7ffaf28e8bc98dc2d48cad75a3b8d73e7a712bc4f1e5ef716b818e", "content": "03187bf3ae429d3a322f51ce5e9802111fa143ac17794e033eb991ff2dc23952"},
}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures.append(label)

func _run() -> void:
	var source := Fixture.profile_at(ROOT)
	check(source != null, "Version 10 synthetic fixture is available")
	if source != null:
		_legacy_golden(source)
		_study_paths(source)
		_archive(source)
		_keystone_flow(source)
		_keystone_effects(source)
		_detours(source)
		_elite_modes(source)
		_bounty_deadlines(source)
		_battle_commitment(source)
		_battle_identity(source)
		_invalid_saves(source)
	check(checks >= MIN_CHECKS, "The complete version 10 integration suite executed")
	Fixture.clean(ROOT)
	print("EXPEDITION VERSION 10: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _distinct(values: Array) -> bool:
	var seen := {}
	for value: Variant in values:
		if seen.has(value): return false
		seen[value] = true
	return true

func _new(source: ELProfile, seed_value := 12345, version := RULES, faction := "Red", study := "") -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(source, "ExpeditionFixture" + faction, seed_value, version):
		check(false, "Create version %d %s run: %s" % [version, faction, run.error])
		return null
	if run.phase == "boon" and not run.choose("relic:amber_seed"):
		check(false, "Choose the opening relic: " + run.error)
		return null
	if run.phase == "discipline" and not run.choose("study:" + ("none" if study.is_empty() else study)):
		check(false, "Choose the study path: " + run.error)
		return null
	return run

func _roundtrip(run: ELExpeditionRun) -> ELExpeditionRun:
	var restored := ELExpeditionRun.new()
	if not restored.restore_snapshot(run.profile, _json(run.snapshot())):
		check(false, "Restore %s checkpoint: %s" % [run.phase, restored.error])
		return null
	return restored

func _option(run: ELExpeditionRun, prefix: String, enabled_only := true) -> Dictionary:
	for option: Dictionary in run.choices():
		if str(option.id).begins_with(prefix) and (not enabled_only or not bool(option.get("disabled", false))): return option
	return {}

func _end(duel: ELDuel, winner := 0) -> void:
	duel.heroes[1 - winner].health = 0
	duel.winner = winner
	duel.phase = ELDuel.Phase.FINISHED

func _settle(run: ELExpeditionRun) -> bool:
	for step in 12:
		match run.phase:
			"map", "won", "lost": return true
			"battle":
				var duel := run.build_battle()
				if duel == null: return false
				_end(duel)
				if not run.resolve_battle(duel): return false
			"elite_gate":
				if not run.choose("elite:standard"): return false
			"reward":
				if not run.choose("skip"): return false
			"relic_reward", "treasure":
				if not run.choose("skip_relic"): return false
			"keystone_reward":
				if not run.choose("skip_keystone"): return false
			"rest":
				if not run.choose("heal"): return false
			"event", "shop":
				if not run.choose("leave"): return false
			"haven":
				if not run.choose("enter_guardian"): return false
			_: return false
	return false

func _path(run: ELExpeditionRun, kind: String, event_index := -1) -> Array[String]:
	var queue: Array[Array] = []
	for id: String in run.available(): queue.append([id])
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var room: Dictionary = run._nodes[path.back()]
		if room.kind == kind and (event_index < 0 or int(room.get("event", -1)) == event_index):
			var result: Array[String] = []
			result.assign(path)
			return result
		for next: String in room.next:
			var extended := path.duplicate()
			extended.append(next)
			queue.append(extended)
	return []

func _enter(source: ELProfile, kind: String, seed_value := 12345, chapter := 1, version := RULES, event_index := -1, faction := "Red", study := "") -> ELExpeditionRun:
	var run := _new(source, seed_value, version, faction, study)
	if run == null: return null
	# Evolved checkpoints validate the complete previous journey; reach later
	# acts through their actual guardian and reward transitions.
	while run.act < chapter:
		if not _travel(run, "boss") or not _settle(run): return null
	return run if _travel(run, kind, event_index) else null

func _travel(run: ELExpeditionRun, kind: String, event_index := -1) -> bool:
	var path := _path(run, kind, event_index)
	if path.is_empty(): return false
	for index in path.size():
		if not run.choose_node(path[index]): return false
		if index < path.size() - 1 and not _settle(run): return false
	return true

func _event(source: ELProfile, event_index: int, chapter := 2, version := RULES) -> ELExpeditionRun:
	for seed_value in 128:
		var run := _enter(source, "event", seed_value, chapter, version, event_index)
		if run != null: return run
	return null

func _win_current(run: ELExpeditionRun, life := -1, round_number := 8) -> ELDuel:
	if run.phase == "elite_gate" and not run.choose("elite:standard"): return null
	if run.phase == "haven" and not run.choose("enter_guardian"): return null
	var duel := run.build_battle()
	if duel == null: return null
	if life >= 0: duel.heroes[0].health = life
	duel.round_number = round_number
	_end(duel)
	return duel if run.resolve_battle(duel) else null

func _study_paths(source: ELProfile) -> void:
	for faction: String in ELDuelPresets.RACES:
		var fresh := ELExpeditionRun.new()
		check(fresh.create(source, "ExpeditionFixture" + faction, 31784, RULES), faction + ": create a version 10 starter")
		var before := fresh.snapshot()
		check(fresh.phase == "boon" and not fresh.choose("study:none") and fresh.snapshot() == before, faction + ": a study choice cannot bypass the starting relic")
		check(fresh.choose("relic:amber_seed") and fresh.phase == "discipline", faction + ": the starting relic leads to the study decision")
		var paths := ELExpeditionPaths.paths(source, faction)
		var choices := fresh.choices()
		check(paths.size() == 3 and choices.size() == 4 and not _option(fresh, "study:none").is_empty(), faction + ": three faction paths and the Open Road are offered")
		var restored := _roundtrip(fresh)
		check(restored != null and restored.phase == "discipline" and restored.choices() == choices, faction + ": an unfinished study decision restores exactly")
		before = fresh.snapshot()
		var wrong := "blue_sky" if faction != "Blue" else "red_raiders"
		check(fresh.available().is_empty() and not fresh.choose("study:" + wrong) and fresh.snapshot() == before, faction + ": a different faction's study cannot be selected")
		check(fresh.choose("study:none") and fresh.phase == "map" and fresh.study_path == "none" and fresh.gold == 50, faction + ": the Open Road pays ten gold exactly once")
		before = fresh.snapshot()
		check(not fresh.choose("study:none") and fresh.snapshot() == before, faction + ": replaying the Open Road cannot farm gold")
		for path: Dictionary in paths:
			var run := _new(source, 31784, RULES, faction, str(path.id))
			check(run != null and run.study_path == path.id and run.gold == 40, str(path.id) + ": committing to the path pays no Open Road bonus")
			if run == null: continue
			restored = _roundtrip(run)
			check(restored != null and restored.study_path == path.id and restored.study_details() == run.study_details(), str(path.id) + ": path identity and details survive reloading")
			run.choose_node(run.available()[0])
			var duel := _win_current(run)
			check(duel != null and run.phase == "reward", str(path.id) + ": a focused run reaches its real opening reward")
			if duel == null: continue
			var pool := run._eligible_spells()
			var candidates := ELExpeditionPaths.candidates(source, str(path.id), pool, run.act)
			var cards := run._offered_cards()
			check(cards.size() == 3 and cards.all(func(code: String) -> bool: return code in pool) and (candidates.is_empty() or cards.any(func(code: String) -> bool: return code in candidates)), str(path.id) + ": focus uses an affordable legal offer without granting extra cards")
			restored = _roundtrip(run)
			check(restored != null and restored._offered_cards() == cards, str(path.id) + ": focused reward offers remain deterministic after reload")
			var shop := _enter(source, "shop", 12345, 1, RULES, -1, faction, str(path.id))
			check(shop != null, str(path.id) + ": an ordinary focused merchant is reachable")
			if shop == null: continue
			candidates = ELExpeditionPaths.candidates(source, str(path.id), shop._eligible_spells(), shop.act)
			check(shop._shop_stock.size() == 4 and (candidates.is_empty() or shop._shop_stock.any(func(code: String) -> bool: return code in candidates)), str(path.id) + ": an ordinary merchant includes an available focus candidate")
	var capped := _new(source, 92417, RULES, "Red", "red_night")
	if capped != null:
		# The small synthetic Red/night catalog contains only FLIC as a legal
		# focus card, so cap it to exercise the ordinary-selection fallback.
		while capped.deck.count("FLIC") < ELDuelCosts.EL2_COPIES: capped.deck.append("FLIC")
		capped.choose_node(capped.available()[0])
		var duel := _win_current(capped)
		check(duel != null and "FLIC" not in capped._offered_cards() and capped._offered_cards().size() == 3, "A focus cannot bypass the four-copy cap and an exhausted focus keeps normal rewards")

func _archive(source: ELProfile) -> void:
	var run := _event(source, 14)
	check(run != null, "The new archive event is reachable")
	if run == null: return
	var restored := _roundtrip(run)
	check(restored != null and restored.choices() == run.choices(), "Archive choices survive reload without rerolling")
	run.gold = 17
	var offer := _option(run, "refocus:", false)
	var before := run.snapshot()
	check(not offer.is_empty() and bool(offer.get("disabled", false)) and not run.choose(str(offer.id)) and run.snapshot() == before, "An unaffordable refocus cannot change the study or spend gold")
	run.gold = 99
	offer = _option(run, "refocus:")
	var intended := str(offer.get("id", "")).trim_prefix("refocus:")
	check(not offer.is_empty() and run.choose(str(offer.id)) and run.study_path == intended and run.gold == 81 and run.phase == "map", "A confirmed archive refocus costs eighteen gold and completes the encounter")
	before = run.snapshot()
	check(not run.choose(str(offer.get("id", ""))) and run.snapshot() == before, "An archive cannot refocus twice from one visit")
	restored = _roundtrip(run)
	check(restored != null and restored.study_path == intended and restored.snapshot() == run.snapshot(), "The new study identity persists after leaving the archive")
	var notes := _event(source, 14)
	if notes != null:
		var identity := notes.study_path
		var money := notes.gold
		check(notes.choose("archive_notes") and notes.gold == money + 12 and notes.study_path == identity, "Selling archive notes pays twelve gold without changing the study")
		before = notes.snapshot()
		check(not notes.choose("archive_notes") and notes.snapshot() == before, "Archive notes cannot be sold repeatedly")
	var same := _event(source, 14)
	if same != null:
		same.study_path = "red_raiders"
		same.gold = 99
		before = same.snapshot()
		check(_option(same, "refocus:red_raiders", false).is_empty() and not same.choose("refocus:red_raiders") and same.snapshot() == before, "The archive never charges for keeping an identical study path")
		check(same.choose("refocus:none") and same.study_path == "none" and same.gold == 81, "Returning to the Open Road costs eighteen and does not pay the starting bonus")

func _guardian_reward(source: ELProfile, wanted := "") -> ELExpeditionRun:
	for seed_value in 32:
		var run := _enter(source, "boss", seed_value)
		if run == null or _win_current(run, 1) == null: continue
		if wanted.is_empty() or not _option(run, "keystone:" + wanted).is_empty(): return run
	return null

func _grant(source: ELProfile, id: String) -> ELExpeditionRun:
	var run := _guardian_reward(source, id)
	if run == null or not run.choose("keystone:" + id): return null
	return run

func _keystone_flow(source: ELProfile) -> void:
	var run := _guardian_reward(source)
	check(run != null and run.phase == "keystone_reward", "The first guardian opens a keystone reward before its spell reward")
	if run == null: return
	var offers := run.choices().filter(func(choice: Dictionary) -> bool: return str(choice.id).begins_with("keystone:"))
	var ids: Array = offers.map(func(choice: Dictionary) -> String: return str(choice.id))
	check(offers.size() == 3 and _distinct(ids) and not _option(run, "skip_keystone").is_empty(), "A guardian offers three distinct keystones and a supplies alternative")
	var restored := _roundtrip(run)
	check(restored != null and restored.choices() == run.choices(), "An unclaimed guardian keystone selection is deterministic after reload")
	var before := run.snapshot()
	check(not run.choose("keystone:unknown") and not run.choose("relic:amber_seed") and run.snapshot() == before, "The keystone stage rejects unknown stones and ordinary relic actions atomically")
	var money := run.gold
	var selected := str(offers[0].id)
	check(run.choose(selected) and run.keystones.size() == 1 and run.phase == "reward" and run.gold == money and run._keystone_claimed == [1], "Taking a keystone records one guardian claim and advances only to the spell reward")
	before = run.snapshot()
	check(not run.choose(selected) and not run.choose("skip_keystone") and run.snapshot() == before, "A guardian's keystone cannot be taken or skipped a second time")
	restored = _roundtrip(run)
	check(restored != null and restored.snapshot() == run.snapshot() and restored.keystone_details().size() == 1, "The claimed keystone and pending spell reward restore together")
	check(run.choose("skip") and run.act == 2 and run.phase == "map", "Completing the spell reward advances the run to the next act once")
	var first := str(run.keystones[0])
	check(_travel(run, "boss") and _win_current(run) != null and run.phase == "keystone_reward", "The second guardian opens its own keystone selection")
	offers = run.choices().filter(func(choice: Dictionary) -> bool: return str(choice.id).begins_with("keystone:"))
	check(offers.size() == 3 and offers.all(func(choice: Dictionary) -> bool: return str(choice.id) != "keystone:" + first), "The second guardian excludes the already owned keystone")
	if offers.is_empty(): return
	check(run.choose(str(offers[0].id)) and run.keystones.size() == 2 and run._keystone_claimed == [1, 2] and run.choose("skip") and run.act == 3, "Two distinct keystones survive the transition to Act III")
	restored = _roundtrip(run)
	check(restored != null and restored.keystones == run.keystones and restored.max_health == run.max_health, "A two-keystone Act III checkpoint preserves the exact derived life cap")
	check(_travel(run, "boss") and run.phase == "haven" and _win_current(run) != null and run.phase == "won" and run.keystones.size() == 2, "The final guardian ends the run without offering a third keystone")
	var retry := run.retry()
	check(retry != null and retry._version == RULES and retry.seed_value == run.seed_value and retry.phase == "boon" and retry.keystones.is_empty() and retry.study_path.is_empty(), "Retrying a finished version 10 run starts fresh choices at the original seed")
	var skipped := _guardian_reward(source)
	if skipped != null:
		skipped.health = 1
		money = skipped.gold
		var expected := 1 + ceili(skipped.max_health * 0.2)
		check(skipped.choose("skip_keystone") and skipped.gold == money + 20 and skipped.health == expected and skipped.keystones.is_empty() and skipped._keystone_claimed == [1], "Skipping a guardian keystone pays twenty gold, recovers life, and consumes its claim")
		restored = _roundtrip(skipped)
		check(restored != null and restored.snapshot() == skipped.snapshot(), "A declined keystone cannot reappear after restoring its spell reward")

func _keystone_effects(source: ELProfile) -> void:
	var crown := _grant(source, "blood_crown")
	check(crown != null, "Blood Crown can be acquired through a guardian reward")
	if crown != null:
		check(int(crown.battle_preview().level) == int(crown.battle_preview().base_level) + 1, "Blood Crown adds exactly one combat level")
		var before := crown.snapshot()
		check(crown.health < crown.max_health and _option(crown, "recover_reward", false).is_empty() and not crown.choose("recover_reward") and crown.snapshot() == before, "Blood Crown removes spell-reward healing even when life is missing")
		crown.choose("skip")
		if _travel(crown, "rest"):
			crown.health = 1
			var expected := 1 + ceili(crown.max_health * 0.3)
			check(crown.choose("heal") and crown.health == expected, "Blood Crown leaves normal camp recovery available")
		if _travel(crown, "elite") and _win_current(crown) != null:
			crown.health = 1
			var expected := 1 + ceili(crown.max_health * 0.2)
			check(crown.choose("skip_relic") and crown.health == expected and _option(crown, "recover_reward", false).is_empty(), "Blood Crown preserves relic supplies while blocking the following spell-reward recovery")
	var heart := _grant(source, "living_heart")
	check(heart != null, "Living Heart can be acquired through a guardian reward")
	if heart != null:
		check(heart.max_health == 32 and heart.health == 11 and heart.life_bonus == 0, "Living Heart grants eight current and maximum life without consuming the oath allowance")
		var restored := _roundtrip(heart)
		check(restored != null and restored.health == heart.health and restored.max_health == heart.max_health, "Reloading Living Heart does not grant its life increase again")
		var life := heart.health
		check(heart.choose("skip") and heart.act == 2 and heart.max_health == 36 and heart.health == life + ceili(36 * 0.3), "An act transition retains Heart's maximum once and applies only ordinary transition recovery")
		check(heart._merchant_price(24) == 29 and heart._merchant_price(16) == 20 and heart._removal_price() == 48, "Living Heart applies the twenty-percent merchant surcharge with upward rounding")
		heart.relics.append("merchant_seal")
		heart.relics.append("purifier_stone")
		var correct := heart._merchant_price(33) == 32
		for count in 4:
			heart._removals = count
			correct = correct and heart._removal_price() == ceili((15 + 15 * count) * 0.96)
		check(correct, "Heart and Merchant's Seal use one combined rounding after Stone's flat subtraction")
		heart.life_bonus = 12
		heart.max_health += 12
		heart.health = heart.max_health
		restored = _roundtrip(heart)
		check(restored != null and restored.max_health == 48 and restored.health == 48, "Heart and the full independent oath bonus restore within the derived life cap")
	var quill := _grant(source, "prismatic_quill")
	check(quill != null, "Prismatic Quill can be acquired through a guardian reward")
	if quill != null:
		check(quill._offered_cards().size() == 6, "Prismatic Quill adds one choice to the first guardian's five normal offers")
		quill.relics.append("glass_compass")
		var cards := quill._offered_cards()
		check(cards.size() == 7 and _distinct(cards), "Quill and Glass Compass offer distinct additional spells without duplicate choices")
		quill.gold = 0
		var original := quill._offered_cards()
		var offer := _option(quill, "reroll_reward")
		check(not offer.is_empty() and int(offer.cost) == 0 and quill.choose("reroll_reward") and quill.gold == 0 and quill._reroll_used_acts == [1] and quill._offered_cards() != original, "Quill funds one genuine redraw even with no gold")
		var before := quill.snapshot()
		check(not quill.choose("reroll_reward") and quill.snapshot() == before, "A free Quill redraw still consumes the once-per-act allowance")
		var restored := _roundtrip(quill)
		check(restored != null and restored._offered_cards() == quill._offered_cards() and restored._reroll_used_acts == quill._reroll_used_acts, "A free redraw's offers and spent allowance survive reloading")
		quill.choose("skip")
		quill.choose_node(quill.available()[0])
		check(_win_current(quill) != null and not _option(quill, "reroll_reward").is_empty() and int(_option(quill, "reroll_reward").get("cost", -1)) == 0, "Quill renews its free redraw in the next act")
	var spent := _guardian_reward(source, "prismatic_quill")
	if spent != null:
		spent._reroll_used_acts.append(1)
		check(spent.choose("keystone:prismatic_quill") and _option(spent, "reroll_reward").is_empty(), "Acquiring Quill does not reset an already spent redraw allowance")

func _disconnected_next(run: ELExpeditionRun) -> String:
	if run.current.is_empty(): return ""
	var floor_index := int(run._nodes[run.current].floor)
	if floor_index >= run.route().size(): return ""
	for room: Dictionary in run.route()[floor_index]:
		if room.id not in run._nodes[run.current].next: return str(room.id)
	return ""

func _detours(source: ELProfile) -> void:
	var run := _grant(source, "wayfarer_compass")
	check(run != null, "Wayfarer Compass can be acquired through a guardian reward")
	if run == null: return
	check(run.choose("skip") and run.act == 2 and run.available().all(func(id: String) -> bool: return not run.is_detour(id)), "Beginning an act does not spend the Compass on its freely chosen opening lane")
	run.choose_node(run.available()[0])
	check(_settle(run), "The Compass run completes its opening Act II duel")
	var detour := _disconnected_next(run)
	check(not detour.is_empty() and run.is_detour(detour) and detour in run.available(), "The Compass exposes an otherwise disconnected room on the next floor")
	var before := run.snapshot()
	for repeat in 3:
		run.is_detour(detour)
		run.upcoming()
	check(run.snapshot() == before, "Inspecting a detour never consumes it")
	var restored := _roundtrip(run)
	check(restored != null and restored.available() == run.available() and restored.is_detour(detour), "The unused detour survives a checkpoint")
	check(run.choose_node(detour) and run._detours_used == [2], "Entering one disconnected room consumes precisely Act II's detour")
	restored = _roundtrip(run)
	check(restored != null and restored.visited == run.visited and restored._detours_used == [2], "A checkpoint immediately after a disconnected step restores its exact route")
	check(_settle(run), "A detour room settles through its normal lifecycle")
	var blocked := _disconnected_next(run)
	for step in 4:
		if not blocked.is_empty(): break
		if run.available().is_empty() or not run.choose_node(run.available()[0]) or not _settle(run): break
		blocked = _disconnected_next(run)
	before = run.snapshot()
	check(not blocked.is_empty() and blocked not in run.available() and not run.choose_node(blocked) and run.snapshot() == before, "A second disconnected step in the same act is rejected without mutation")
	check(_travel(run, "boss") and _settle(run) and run.act == 3 and run._detours_used == [2], "Finishing Act II preserves its spent marker and begins a fresh Act III allowance")
	restored = _roundtrip(run)
	check(restored != null and restored._previous_paths == run._previous_paths and restored._detours_used == [2], "The previous act's recorded disconnected route remains valid after advancing")
	run.choose_node(run.available()[0])
	_settle(run)
	detour = _disconnected_next(run)
	check(not detour.is_empty() and run.is_detour(detour) and run.choose_node(detour) and run._detours_used == [2, 3], "Act III can use exactly its own renewed detour")
	restored = _roundtrip(run)
	check(restored != null and restored.snapshot() == run.snapshot(), "Both acts' used detours and the current room survive reloading")
	var healthy := run.snapshot()
	for markers: Array in [[], [2], [1, 2], [2, 2], [2, 3, 3]]:
		var damaged := healthy.duplicate(true)
		damaged.detours_used = markers
		check(not run.restore_snapshot(source, _json(damaged)) and run.snapshot() == healthy, "Invalid detour history %s cannot overwrite the live run" % str(markers))

func _elite_modes(source: ELProfile) -> void:
	var gate := _enter(source, "elite", 3456, 2)
	check(gate != null and gate.phase == "elite_gate", "An unscripted Act II elite offers its challenge gate")
	if gate == null: return
	var base := gate.elite_preview(gate.current, "standard")
	var before := gate.snapshot()
	check(not base.is_empty() and gate.build_battle() == null and not gate.choose("elite:unknown") and gate.snapshot() == before, "An elite cannot start or change mode before a legal challenge choice")
	var restored := _roundtrip(gate)
	check(restored != null and restored.choices() == gate.choices(), "The uncommitted elite gate restores its exact options")
	var earnings := {}
	for variant: String in ["standard", "overcharged", "fortified"]:
		var run := _roundtrip(gate)
		if run == null: continue
		var preview := run.elite_preview(run.current, variant)
		var expected_level := int(base.level) + (1 if variant == "overcharged" else (-1 if variant == "fortified" else 0))
		var expected_life := ceili(int(base.health) * 0.85) if variant == "overcharged" else (ceili(int(base.health) * 1.25) if variant == "fortified" else int(base.health))
		check(not preview.is_empty() and int(preview.level) == expected_level and int(preview.health) == expected_life and preview.cards == base.cards and preview.skills == base.skills, variant + ": the preview changes only the promised elite stats")
		check(run.choose("elite:" + variant) and run.phase == "battle" and run.elite_variant == variant and run.opponent_at(run.current) == preview, variant + ": committing after scouting uses the chosen actual opponent")
		var duel := run.build_battle()
		check(duel != null and int(duel.heroes[1].level) == expected_level and int(duel.heroes[1].health) == expected_life, variant + ": the actual duel matches its selected preview")
		if duel == null: continue
		run._battle_checkpoint = duel.snapshot()
		restored = _roundtrip(run)
		var resumed := restored.build_battle() if restored != null else null
		check(resumed != null and restored.elite_variant == variant and int(resumed.heroes[1].health) == expected_life, variant + ": an active elite checkpoint preserves its selected mode")
		var money := run.gold
		_end(duel)
		check(run.resolve_battle(duel) and run.phase == "relic_reward" and int(run._last_reward.get("challenge", -1)) == (0 if variant == "standard" else 10), variant + ": victory pays the matching challenge receipt once")
		earnings[variant] = run.gold - money
		before = run.snapshot()
		check(not run.resolve_battle(duel) and run.snapshot() == before, variant + ": the completed elite cannot award its bonus twice")
		restored = _roundtrip(run)
		check(restored != null and restored.snapshot() == run.snapshot() and _settle(run) and run.elite_variant.is_empty(), variant + ": the rewarded mode restores, then clears when leaving the room")
	check(earnings.size() == 3 and int(earnings.get("overcharged", 0)) == int(earnings.get("standard", 0)) + 10 and int(earnings.get("fortified", 0)) == int(earnings.get("standard", 0)) + 10, "Optional elite variants add exactly ten gold over the same seeded standard victory")
	var early := _enter(source, "elite", 3456, 1)
	if early != null:
		before = early.snapshot()
		check(_option(early, "elite:fortified").is_empty() and not early.choose("elite:fortified") and early.snapshot() == before and not _option(early, "elite:overcharged").is_empty(), "Act I locks Fortified while keeping Overcharged available")
	var high := _roundtrip(gate)
	if high != null:
		high._base_opponent_at(high.current)
		high._opponents[high.current].level = 20
		before = high.snapshot()
		check(high.elite_preview(high.current, "overcharged").is_empty() and not high.choose("elite:overcharged") and high.snapshot() == before, "A level-20 elite cannot trade away life for a clamped-away Overcharged level")
	var low := _roundtrip(gate)
	if low != null:
		low._base_opponent_at(low.current)
		low._opponents[low.current].level = 1
		before = low.snapshot()
		check(low.elite_preview(low.current, "fortified").is_empty() and not low.choose("elite:fortified") and low.snapshot() == before, "A level-1 elite cannot promise a nonexistent Fortified level reduction")
	var scripted := _roundtrip(gate)
	if scripted != null:
		scripted._base_opponent_at(scripted.current)
		scripted._opponents[scripted.current].scripts = [{"name": "fixture-script", "side": 1}]
		check(scripted.elite_preview(scripted.current, "overcharged").is_empty() and scripted.elite_preview(scripted.current, "fortified").is_empty(), "Scripted opponents do not accept optional elite stat rewrites")
	var lost := _roundtrip(gate)
	if lost != null and lost.choose("elite:overcharged"):
		var duel := lost.build_battle()
		if duel != null:
			var money := lost.gold
			_end(duel, 1)
			check(lost.resolve_battle(duel) and lost.phase == "lost" and lost.health == 0 and lost.gold == money and lost._last_reward.is_empty(), "Losing an optional elite challenge ends the run without paying victory gold")
			restored = _roundtrip(lost)
			check(restored != null and restored.phase == "lost" and restored.health == 0, "A failed optional challenge restores as a finished loss")

func _minimum_elite_distance(run: ELExpeditionRun, start: String) -> int:
	# An independent shortest-path measure on the current act's DAG. The
	# score counts scheduled victories, including the target elite itself.
	var distance := {start: 0}
	var result := 99
	for row: Array in run.route():
		for room: Dictionary in row:
			if not distance.has(room.id): continue
			for next: String in room.next:
				var kind: String = run._nodes[next].kind
				var wins := int(distance[room.id]) + int(kind in ELExpeditionRun.COMBAT_ROOMS)
				distance[next] = mini(int(distance.get(next, 99)), wins)
				if kind == "elite": result = mini(result, wins)
	return result

func _bounty_example(source: ELProfile, chapter: int, positive: bool) -> ELExpeditionRun:
	for seed_value in 512:
		var probe := _new(source, seed_value)
		if probe == null: return null
		probe._reset(source, probe.preset, seed_value, chapter)
		for row: Array in probe.route():
			for room: Dictionary in row:
				if room.kind != "event" or int(room.get("event", -1)) != 13: continue
				var distance := _minimum_elite_distance(probe, str(room.id))
				var matches := distance == 1 if positive else (distance > 2 and distance < 99 if chapter == 3 else int(room.floor) == 6 and distance == 99)
				if matches: return _enter(source, "event", seed_value, chapter, RULES, 13)
	return null

func _bounty_deadlines(source: ELProfile) -> void:
	var legacy := _enter(source, "event", 35, 2, 9, 13)
	check(legacy != null and legacy.current == "2-6-3", "The recorded version 9 late-bounty regression retains its exact room")
	if legacy != null:
		check(legacy._nodes[legacy.current].next.all(func(id: String) -> bool: return legacy._nodes[id].kind in ["rest", "treasure"]) and not _option(legacy, "bounty:elite").is_empty(), "Version 9 preserves its original offer despite the guardian-then-opening deadline trap")
	for chapter in range(1, 4):
		var run := _bounty_example(source, chapter, false)
		check(run != null, "Act %d has a concrete board whose next two scheduled wins cannot include an elite" % chapter)
		if run == null: continue
		run.gold = 99
		var before := run.snapshot()
		var offer := _option(run, "bounty:elite", false)
		check(not offer.is_empty() and bool(offer.get("disabled", false)) and not run.choose("bounty:elite") and run.snapshot() == before, "Act %d blocks the impossible elite bounty without taking its ten-gold bond" % chapter)
		check(not _option(run, "bounty:swift").is_empty(), "Act %d still allows a swift bounty when an ordinary scheduled win remains" % chapter)
	var possible := _bounty_example(source, 2, true)
	check(possible != null, "A board with a directly reachable elite provides a positive bounty control")
	if possible != null:
		possible.gold = 99
		var elite_id := ""
		for id: String in possible._nodes[possible.current].next:
			if possible._nodes[id].kind == "elite": elite_id = id
		check(possible.choose("bounty:elite") and possible.gold == 89 and possible._bounty == {"kind": "elite", "remaining": 2}, "A reachable elite bounty still accepts exactly one ten-gold bond")
		check(possible.choose_node(elite_id) and possible.choose("elite:overcharged") and _win_current(possible) != null and int(possible._last_reward.get("bounty", 0)) == 40 and int(possible._last_reward.get("challenge", 0)) == 10 and possible._bounty.is_empty(), "A qualifying optional elite pays its bounty and challenge premium exactly once")

func _legacy_golden(source: ELProfile) -> void:
	# Captured with the released v9 code, before adding any v10 rules. Text
	# labels are omitted from the content digest; legal IDs, costs, disabled
	# states, seeded cards and relics are part of the compatibility contract.
	for version: int in GOLDEN:
		var routes := ""
		var contents := ""
		for seed_value: int in [0, 1, 34567, 0xffffffff]:
			var run := _new(source, seed_value, version)
			if run == null: continue
			for chapter in range(1, 4):
				run._reset(source, run.preset, seed_value, chapter)
				routes += JSON.stringify(run.route(), "", true, true)
				run.gold = 999
				run.health = run.max_health
				for row: Array in run.route():
					for room: Dictionary in row:
						run._clear_room_state()
						run.current = room.id
						run.visited.assign([room.id])
						run._opponents.clear()
						run.phase = room.kind
						var reward := {}
						if room.kind in ["fight", "elite", "boss"]:
							run.phase = "reward"
							reward.cards = run._offered_cards()
							run.phase = "relic_reward"
							reward.relics = run._relic_offers(3)
						elif room.kind == "shop":
							run._prepare_shop()
							reward.stock = run._shop_stock.duplicate()
							reward.relic = run._shop_relic
						var options: Array = []
						for choice: Dictionary in run.choices():
							options.append({"id": choice.id, "cost": choice.get("cost", 0), "disabled": choice.get("disabled", false)})
						contents += JSON.stringify({"room": room.id, "reward": reward, "options": options}, "", true, true)
		check(routes.sha256_text() == GOLDEN[version].route, "Version %d preserves every sampled route and event assignment" % version)
		check(contents.sha256_text() == GOLDEN[version].content, "Version %d preserves seeded card/relic offers, prices, and legal actions" % version)

func _battle_commitment(source: ELProfile) -> void:
	var view = load("res://src/duel/view.gd").new()
	view.demo = false
	for version in [9, RULES]:
		var run := _new(source, 51826, version)
		if run == null: continue
		check(run.choose_node(run.available()[0]), "Version %d enters its opening duel" % version)
		var duel := run.build_battle()
		check(duel != null, "Version %d starts a real duel for retry validation" % version)
		if duel == null: continue
		duel.heroes[0].health = 1
		run._battle_checkpoint = duel.snapshot()
		var before := run.snapshot()
		view.expedition_run = run
		view._expedition_battle = duel
		view.duel = duel
		check(bool(view._can_retry_battle()) == (version < RULES), "Version %d exposes only its permitted mid-duel retry behavior" % version)
		var fresh := run.build_battle(true)
		if version < RULES:
			check(fresh != null and int(fresh.heroes[0].health) == run.health, "Version 9 retains its original fresh-duel restart")
		else:
			check(fresh == null and run.snapshot() == before, "Version 10 rejects a fresh-duel restart without changing the checkpoint")
			var resumed := _roundtrip(run)
			var resumed_duel := resumed.build_battle() if resumed != null else null
			check(resumed_duel != null and int(resumed_duel.heroes[0].health) == 1, "Committed version 10 combat remains resumable at its current life")
	view.free()

func _battle_identity(source: ELProfile) -> void:
	var red := _new(source, 51826)
	var green := _new(source, 51826, RULES, "Green")
	if red == null or green == null: return
	red.choose_node(red.available()[0])
	green.choose_node(green.available()[0])
	var duel := red.build_battle()
	check(duel != null and duel.setup.get("expedition_identity") is String, "Version 10 attaches an opaque immutable identity to the real duel")
	if duel == null: return
	var healthy := green.snapshot()
	var crossed := healthy.duplicate(true)
	crossed.battle = duel.snapshot()
	check(not green.restore_snapshot(source, _json(crossed)) and green.snapshot() == healthy, "A Green run cannot load a Red duel merely because seed, room, and relics match")
	var raw := red.snapshot()
	raw.battle = duel.snapshot()
	for bad_identity: Variant in [null, 17, true, [], {}, "wrong-fingerprint"]:
		var malformed := raw.duplicate(true)
		malformed.battle.setup.expedition_identity = bad_identity
		var before := red.snapshot()
		check(not red.restore_snapshot(source, _json(malformed)) and red.snapshot() == before, "Malformed battle identity %s is rejected atomically without a runtime error" % str(bad_identity))
	var altered_book := red.deck.duplicate()
	altered_book[0] = altered_book[1]
	for change: Array in [["deck", altered_book], ["study_path", "red_raiders"], ["health", red.health - 1]]:
		var changed := raw.duplicate(true)
		changed[change[0]] = change[1]
		var before := red.snapshot()
		check(not red.restore_snapshot(source, _json(changed)) and red.snapshot() == before, "Changing %s cannot attach an existing duel to a different run state" % str(change[0]))
	var old := _new(source, 51826, 9)
	if old != null:
		old.choose_node(old.available()[0])
		var old_duel := old.build_battle()
		if old_duel != null:
			crossed = red.snapshot()
			crossed.battle = old_duel.snapshot()
			healthy = red.snapshot()
			check(not red.restore_snapshot(source, _json(crossed)) and red.snapshot() == healthy, "A legacy duel without the version 10 identity cannot enter a new run")
	_end(duel)
	healthy = green.snapshot()
	check(not green.resolve_battle(duel) and green.snapshot() == healthy, "A different starter's completed duel cannot settle the current run")
	red._battle_checkpoint = duel.snapshot()
	var money := red.gold
	var resumed := _roundtrip(red)
	var finished := resumed.build_battle() if resumed != null else null
	check(finished != null and finished.phase == ELDuel.Phase.FINISHED and resumed.resolve_battle(finished) and resumed.phase == "reward" and resumed.gold > money, "A finished-but-unsettled checkpoint resumes and pays its legitimate victory")
	if resumed != null:
		healthy = resumed.snapshot()
		check(not resumed.resolve_battle(finished) and resumed.snapshot() == healthy, "A restored finished duel cannot be settled a second time")
	var crown := _grant(source, "blood_crown")
	if crown != null:
		crown.choose("skip")
		crown.choose_node(crown.available()[0])
		var crowned_duel := crown.build_battle()
		if crowned_duel != null:
			healthy = crown.snapshot()
			crossed = healthy.duplicate(true)
			crossed.keystones = []
			crossed.battle = crowned_duel.snapshot()
			check(not crown.restore_snapshot(source, _json(crossed)) and crown.snapshot() == healthy, "A saved duel cannot retain a keystone's advantage after the run's keystone identity changes")
	var gate := _enter(source, "elite", 3456, 2)
	if gate != null:
		var standard := _roundtrip(gate)
		gate.choose("elite:overcharged")
		standard.choose("elite:standard")
		var overcharged := gate.build_battle()
		if overcharged != null:
			healthy = standard.snapshot()
			crossed = healthy.duplicate(true)
			crossed.battle = overcharged.snapshot()
			check(not standard.restore_snapshot(source, _json(crossed)) and standard.snapshot() == healthy, "A challenge duel cannot masquerade as the standard elite after reloading")

func _invalid_saves(source: ELProfile) -> void:
	var run := _new(source, 2957)
	if run == null: return
	var healthy := run.snapshot()
	for field: String in ["study_path", "keystones", "keystone_claimed", "detours_used"]:
		var missing := healthy.duplicate(true)
		missing.erase(field)
		check(not run.restore_snapshot(source, _json(missing)) and run.snapshot() == healthy, "A version 10 checkpoint requires its %s field" % field)
	for change: Array in [["study_path", ""], ["study_path", "blue_sky"], ["study_path", "missing"], ["study_path", 17], ["keystones", ["unknown"]], ["keystones", ["blood_crown", "blood_crown"]], ["keystones", ["blood_crown", "living_heart", "prismatic_quill"]], ["keystone_claimed", [2]], ["keystone_claimed", [1]], ["keystone_claimed", [1.5]], ["detours_used", [1]], ["detours_used", [2]], ["elite_variant", "overcharged"], ["elite_variant", "missing"]]:
		var damaged := healthy.duplicate(true)
		damaged[change[0]] = change[1]
		check(not run.restore_snapshot(source, _json(damaged)) and run.snapshot() == healthy, "Malformed %s=%s cannot replace the valid new run" % [str(change[0]), str(change[1])])
	var later := _grant(source, "living_heart")
	if later != null:
		later.choose("skip")
		healthy = later.snapshot()
		var missing := healthy.duplicate(true)
		missing.erase("previous_paths")
		check(not later.restore_snapshot(source, _json(missing)) and later.snapshot() == healthy, "A later version 10 act cannot discard its required previous journey")
		var overhealed := healthy.duplicate(true)
		overhealed.health = later.max_health + 1
		check(not later.restore_snapshot(source, _json(overhealed)) and later.snapshot() == healthy, "A keystone cannot justify life above its actual derived maximum")
