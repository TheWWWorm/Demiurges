extends SceneTree
## Printed-card offer checks and controlled route/save states. No battles are
## played and no player checkpoint is read or written. This is not win-rate
## evidence. The frozen v13 core supplies the legacy offer comparison.
## godot --headless --path game --script ../tools/expedition_v14_offers_check.gd -- \
##   --fixture=/path/to/fixture.json --baseline=/path/to/v13/run.gd --output=/tmp/v14-offers.json

const DraftCheck := preload("arena_draft_check.gd")
const STARTERS := {"Red": "STR1", "Green": "STG1", "Blue": "STU1", "Black": "STB1"}
const RULES := 14
const SEEDS := 16
var checks := 0
var failures: Array[String] = []
var sections: Array[String] = []
var legacy_cases := 0
var offer_cases := 0
var archive_cases: Array[Dictionary] = []
var source: ELProfile
var frozen: GDScript

func _arg(name: String, fallback := "") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.trim_prefix("--" + name + "=")
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: return
	failures.append(label)
	if failures.size() <= 30: printerr("FAIL: " + label)

func _run() -> void:
	var began := Time.get_ticks_msec()
	source = _profile()
	check(source != null, "Printed catalog and recorded starter books load")
	var baseline := _arg("baseline")
	check(not baseline.is_empty() and FileAccess.file_exists(baseline), "A frozen v13 core is supplied")
	if source != null and not baseline.is_empty() and FileAccess.file_exists(baseline):
		frozen = GDScript.new()
		frozen.source_code = FileAccess.get_file_as_string(baseline).replace("class_name ELExpeditionRun\n", "")
		check(frozen.reload() == OK and frozen.can_instantiate(), "Frozen v13 core loads read only")
		if frozen.can_instantiate(): _legacy_offers()
		_path_boundaries()
		_focus_ownership()
		_actual_offer_slots()
		_reward_reload()
		_archive_choices()
		_shrine_text()
	check(legacy_cases == 156, "Every version/faction/act legacy comparison completed")
	check(offer_cases == SEEDS * 3, "Every early reward scenario completed")
	check(sections.size() == 7 and checks >= 1500, "The complete focused suite executed")
	var result := {"rules": RULES, "checks": checks, "failures": failures, "sections": sections,
		"legacy_cases": legacy_cases, "offer_cases": offer_cases, "archive_cases": archive_cases,
		"fixture": _arg("fixture"), "baseline": baseline, "elapsed_ms": Time.get_ticks_msec() - began,
		"assumptions": ["Printed wiki spell/creature rows and recorded starter books; synthetic hero metadata.",
			"Uses actual run offer, choice, route, and JSON restore functions in controlled states.",
			"Constructed reward/checkpoint histories do not assert played victories or combat balance.",
			"Frozen v13 core uses current shared localization and the default legacy path API.",
			"No original campaign assets, player saves, or AI battles are used."]}
	var output := _arg("output")
	check(not output.is_empty(), "A saved report destination is supplied")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		check(file != null, "Focused offer report opens")
		if file != null:
			result.checks = checks
			file.store_string(JSON.stringify(result, "\t", true, true))
	print("EXPEDITION V14 OFFERS: %d checks, %d failures; %d legacy cases, %d offer cases" % [checks, failures.size(), legacy_cases, offer_cases])
	for entry: Dictionary in archive_cases: print("ARCHIVE CASE: ", JSON.stringify(entry))
	quit(0 if failures.is_empty() else 1)

func _profile() -> ELProfile:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_arg("fixture")))
	if raw is not Dictionary or raw.get("expedition_balance", {}).get("books") is not Dictionary: return null
	var profile := DraftCheck.synthetic_profile(_arg("fixture"))
	if profile == null: return null
	profile.tables.DuelPresets = {}
	profile.tables.HeroesSpecialization = {}
	for faction: String in STARTERS:
		var id := "V14Offers" + faction
		profile.tables.CombatDecks[id] = {"Spells": raw.expedition_balance.books[STARTERS[faction]].cards.duplicate()}
		profile.tables.DuelPresets[id] = {"InGame": "True", "MagicColor": faction, "ResourceLevel": 1,
			"HeroLevel": 1, "Specialization": "NONE", "Skills": ["PRVD(1)"], "Deck": id}
	return profile

func _new(faction := "Blue", seed_value := 0, version := RULES, chapter := 1) -> ELExpeditionRun:
	var run := ELExpeditionRun.new()
	if not run.create(source, "V14Offers" + faction, seed_value, version):
		check(false, "Create controlled run: " + run.error)
		return null
	if run.phase == "boon": run.choose("relic:amber_seed")
	if run.phase == "discipline": run.choose("study:none")
	if chapter != 1:
		run._reset(source, run.preset, seed_value, chapter)
		run.health = run.max_health
	run.gold = 200
	return run

func _at(run: Variant, room: Dictionary, phase: String) -> void:
	run._clear_room_state()
	run.current = room.id
	run.visited.assign([String(room.id)])
	run.phase = phase
	run.pending_card = ""

func _room(run: Variant, kind: String, minimum_floor := 0) -> Dictionary:
	for row: Array in run._route:
		for room: Dictionary in row:
			if room.kind == kind and int(room.floor) >= minimum_floor: return room
	return {}

func _option(run: ELExpeditionRun, id: String) -> Dictionary:
	for offer: Dictionary in run.choices():
		if offer.id == id: return offer
	return {}

func _unique(cards: Array[String]) -> bool:
	var seen := {}
	for card: String in cards:
		if seen.has(card): return false
		seen[card] = true
	return true

func _legal(run: ELExpeditionRun, cards: Array[String]) -> bool:
	for card: String in cards:
		if card not in run._eligible_spells(): return false
	return _unique(cards)

func _legacy_offers() -> void:
	for version in range(1, 14):
		for faction: String in STARTERS:
			for chapter in range(1, 4):
				var seed_value := 43 + version
				var left := _new(faction, seed_value, version, chapter)
				var right: Variant = frozen.new()
				check(right.create(source, "V14Offers" + faction, seed_value, version), "Frozen run initializes")
				if right.phase == "boon": right.choose("relic:amber_seed")
				if right.phase == "discipline": right.choose("study:none")
				right._reset(source, right.preset, seed_value, chapter)
				right.health = right.max_health
				right.gold = 200
				if version >= 10:
					var focus := str(ELExpeditionPaths.paths(source, faction)[2].id)
					left.study_path = focus
					right.study_path = focus
				check(left.route() == right.route(), "Rules %d %s act%d retain frozen routes" % [version, faction, chapter])
				for kind: String in ["fight", "elite", "boss"]:
					var room := _room(left, kind)
					_at(left, room, "reward")
					_at(right, room, "reward")
					for roll in [0, 1]:
						check(left._offered_cards(roll) == right._offered_cards(roll), "Rules %d preserve %s reward roll %d" % [version, kind, roll])
				for phase: String in ["shop", "haven"]:
					var room := _room(left, "boss")
					_at(left, room, phase)
					_at(right, room, phase)
					left._prepare_shop()
					right._prepare_shop()
					check(left._shop_stock == right._shop_stock and left._shop_relic == right._shop_relic, "Rules %d retain frozen %s stock" % [version, phase])
				if version >= 10:
					check(left._study_choices(true) == right._study_choices(true), "Legacy starting study examples are unchanged")
					check(left._study_choices(false) == right._study_choices(false), "Legacy paid study offers are unchanged")
				legacy_cases += 1
	sections.append("legacy_offers")

func _path_boundaries() -> void:
	var run := _new()
	var pool := run._eligible_spells()
	var old := ELExpeditionPaths.candidates(source, "blue_spirits", pool, 1)
	var current := ELExpeditionPaths.candidates(source, "blue_spirits", pool, 1, true)
	check(old == ELExpeditionPaths.candidates(source, "blue_spirits", pool, 1, false), "Omitted path flag retains the old API")
	check("WRSP" not in old and "SHSP" not in old and old.size() == 7, "Legacy Spirit path retains its seven early support cards")
	var added: Array[String] = []
	for card: String in current:
		if card not in old: added.append(card)
	check(added == ["SHSP", "WRSP"], "Only the two printed four-ether Spirits enter the new early pool")
	check(int(source.table("CombatSpells").WRSP.Cost) == 4 and int(source.table("CombatSpells").SHSP.Cost) == 4, "Printed Spirit costs stay four")
	for faction: String in STARTERS:
		for path: Dictionary in ELExpeditionPaths.paths(source, faction):
			for chapter in range(1, 4):
				if path.id == "blue_spirits" and chapter == 1: continue
				check(ELExpeditionPaths.candidates(source, path.id, pool, chapter, true) == ELExpeditionPaths.candidates(source, path.id, pool, chapter), "Other path/act eligibility is unchanged")
	var only: Array[String] = ["WRSP", "WRSP", "SHSP"]
	check(ELExpeditionPaths.candidates(source, "blue_spirits", only, 1, true) == ["SHSP", "WRSP"], "The exception remains sorted, unique, and restricted to the supplied pool")
	var original: Dictionary = source.tables.CombatSpells.WRSP.duplicate(true)
	source.tables.CombatSpells.WRSP.Cost = 5
	check("WRSP" not in ELExpeditionPaths.candidates(source, "blue_spirits", pool, 1, true), "A more expensive custom Spirit cannot bypass the ceiling")
	source.tables.CombatSpells.WRSP = original
	check(ELExpeditionPaths.candidates(source, "blue_spirits", pool, 0, true).is_empty() and ELExpeditionPaths.candidates(source, "blue_spirits", pool, 4, true).is_empty(), "Invalid acts remain rejected")
	sections.append("path_boundaries")

func _focus_ownership() -> void:
	var run := _new()
	var pool := run._eligible_spells()
	check(run._focus_candidates("blue_spirits", pool) == ["SHSP", "WRSP"], "A Spirit-free book first sees eligible Spirits")
	var without_warrior := pool.duplicate()
	without_warrior.erase("WRSP")
	check(run._focus_candidates("blue_spirits", without_warrior) == ["SHSP"], "One remaining Spirit is still preferred")
	without_warrior.erase("SHSP")
	check(run._focus_candidates("blue_spirits", without_warrior) == ELExpeditionPaths.candidates(source, "blue_spirits", without_warrior, 1, true), "Exhausted creature offers fall back to supported school spells")
	for code: String in ["WRSP", "WZSP"]:
		run.reserve.assign([code])
		check(run._focus_candidates("blue_spirits", run._eligible_spells()) == ELExpeditionPaths.candidates(source, "blue_spirits", run._eligible_spells(), 1, true), "Any reserved Spirit ends the initial preference")
	run.reserve.clear()
	var outgoing := run.deck[0]
	run.deck[0] = "SHSP"
	check(run._focus_candidates("blue_spirits", run._eligible_spells()) == ELExpeditionPaths.candidates(source, "blue_spirits", run._eligible_spells(), 1, true), "An active Spirit ends the initial preference")
	run.deck[0] = outgoing
	for index in 4: run.deck[index] = "WRSP"
	run.reserve.assign(["SHSP", "SHSP"])
	run.deck[4] = "SHSP"
	run.deck[5] = "SHSP"
	check(run.owned_copies("WRSP") == 4 and run.owned_copies("SHSP") == 4, "Construct combined-copy boundaries")
	var capped := run._focus_candidates("blue_spirits", run._eligible_spells())
	check("WRSP" not in capped and "SHSP" not in capped and not capped.is_empty(), "The new preference never adds a fifth owned copy")
	sections.append("focus_ownership")

func _actual_offer_slots() -> void:
	for seed_value in SEEDS:
		var run := _new("Blue", seed_value)
		var old := _new("Blue", seed_value, 13)
		run.study_path = "blue_spirits"
		old.study_path = "blue_spirits"
		for kind: String in ["fight", "elite", "boss"]:
			var room := _room(run, kind)
			_at(run, room, "reward")
			_at(old, room, "reward")
			var offers := run._offered_cards()
			var previous := old._offered_cards()
			check(offers.size() == previous.size(), "The school never adds another reward slot")
			check(offers.slice(0, 2) == previous.slice(0, 2), "The ordinary creature/noncreature slots retain their seeded offers")
			check(offers[2] in ["WRSP", "SHSP"], "The actual focused battle slot establishes a Spirit")
			check(_legal(run, offers), "Battle offers remain legal, unique, and below ownership caps")
			var redraw := run._offered_cards(1)
			check(redraw.size() == offers.size() and _legal(run, redraw) and redraw == run._offered_cards(1), "Redraw preserves count, legality, and deterministic choices")
			check(redraw.all(func(card: String): return card not in offers), "A full catalog redraw excludes the previous set")
			offer_cases += 1
		var shop := _room(run, "shop")
		_at(run, shop, "shop")
		_at(old, shop, "shop")
		var before := run.snapshot()
		var preview := run._shop_cards_for(int(shop.seed), run.study_path)
		check(run.snapshot() == before, "Previewing merchant cards cannot mutate the visit")
		run._prepare_shop()
		old._prepare_shop()
		check(run._shop_stock == preview and run._shop_stock.size() == 4, "Real merchant stock matches its pure preview")
		check(run._shop_stock.slice(0, 3) == old._shop_stock.slice(0, 3), "The three ordinary merchant slots retain their seeded offers")
		check(run._shop_stock[3] in ["WRSP", "SHSP"] and _legal(run, run._shop_stock), "The fourth merchant slot offers an eligible Spirit")
	var initial := _new()
	var school: Dictionary = initial._study_choices(true).filter(func(offer: Dictionary): return offer.id == "study:blue_spirits")[0]
	check(str(school.context).contains(initial._card_title("WRSP")) and str(school.context).contains(initial._card_title("SHSP")), "Starting examples show both newly available Spirits")
	sections.append("actual_offer_slots")

func _json(raw: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(raw, "", true, true))

func _restore(run: ELExpeditionRun, label: String) -> ELExpeditionRun:
	var next := ELExpeditionRun.new()
	var ok := next.restore_snapshot(source, _json(run.snapshot()))
	check(ok, label + ": " + next.error)
	if not ok: return null
	check(next.snapshot() == run.snapshot() and next.choices() == run.choices(), label + " retains exact state and choices")
	return next

func _reward_reload() -> void:
	var run := _new("Blue", 173)
	run.study_path = "blue_spirits"
	check(run.choose_node(run.available()[0]), "Enter a real first-floor route node")
	# Controlled post-victory state; no battle outcome is claimed.
	run.phase = "reward"
	var offered := run._offered_cards()
	var card := offered[2]
	var before := run.snapshot()
	check(run.choose("card:" + card) and run.pending_card == card, "Inspect the new Spirit reward")
	var resumed := _restore(run, "Pending early Spirit reward JSON roundtrip")
	if resumed != null:
		check(resumed.choose("back") and resumed.snapshot() == before, "Back restores the same offer without a page or payment")
		check(resumed.choose("card:" + card) and resumed.choose("reserve_add"), "A preferred Spirit can be stored normally")
		check(resumed.reserve == [card] and resumed.deck == run.deck, "Storage grants exactly one page and does not change the active book")
		_restore(resumed, "Stored Spirit JSON roundtrip")
	check(run.choose("back") and run.choose("reroll_reward"), "Redraw the early reward through the real action")
	var after := run._offered_cards()
	var restored := _restore(run, "Redrawn early Spirit reward JSON roundtrip")
	if restored != null: check(restored._offered_cards() == after and after != offered, "Reload cannot reroll the redrawn Spirit selection")
	sections.append("reward_reload")

func _to_node(run: ELExpeditionRun, target: String) -> Array[String]:
	var queue: Array[Array] = []
	for room: Dictionary in run._route[0]: queue.append([String(room.id)])
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var id := str(path.back())
		if id == target:
			var result: Array[String] = []
			result.assign(path)
			return result
		for next: String in run._nodes[id].next:
			var branch := path.duplicate()
			branch.append(next)
			queue.append(branch)
	return []

func _valid_history(run: ELExpeditionRun) -> void:
	run.visited = _to_node(run, run.current)
	run._previous_paths.clear()
	run._keystone_claimed.clear()
	for chapter in range(1, run.act):
		var previous := _new(str(run.preset.faction), run.seed_value, run._version, chapter)
		var boss := _room(previous, "boss")
		run._previous_paths[str(chapter)] = _to_node(previous, str(boss.id))
		run._keystone_claimed.append(chapter)

func _dead_archive(version: int) -> ELExpeditionRun:
	for seed_value in 1024:
		var run := _new("Blue", seed_value, version, 3)
		run.study_path = "blue_sky"
		for room: Dictionary in run._route[5]:
			if room.kind != "event" or int(room.event) != 14: continue
			if not room.next.all(func(id: String): return run._nodes[id].kind == "treasure"): continue
			_at(run, room, "event")
			var boss := _room(run, "boss")
			var counter := run._study_spell()
			var original := run._shop_cards_for(int(boss.seed), run.study_path, true)
			if counter.is_empty() or original.size() != 4 or original[3] != counter or counter in original.slice(0, 3): continue
			var same := true
			for path_id: String in ["none", "blue_tide", "blue_spirits"]:
				if run._shop_cards_for(int(boss.seed), path_id, true) != original: same = false
			if not same: continue
			_valid_history(run)
			archive_cases.append({"rules": version, "seed": seed_value, "room": room.id, "next": room.next.duplicate(),
				"haven_cards": original, "missing_counter": counter, "initial_path": run.study_path})
			return run
	return null

func _archive_choices() -> void:
	var old := _dead_archive(13)
	check(old != null, "Find the exact no-benefit Archive case in preserved v13 routes")
	if old != null:
		var offer := _option(old, "refocus:blue_spirits")
		check(not offer.is_empty() and not bool(offer.get("disabled", false)) and int(offer.cost) == 18, "The frozen rules still offer the ineffective purchase")
		var paid := old.gold
		check(old.choose("refocus:blue_spirits") and old.gold == paid - 18, "The old no-benefit purchase is reproduced without changing old rules")
	var run := _dead_archive(RULES)
	check(run != null, "Find the exact no-benefit Archive case in new routes")
	if run == null: return
	var before := run.snapshot()
	for path_id: String in ["none", "blue_tide", "blue_spirits"]:
		var offer := _option(run, "refocus:" + path_id)
		check(not run._refocus_has_future_use(path_id) and bool(offer.get("disabled", false)), "A provably ineffective refocus is disabled: " + path_id)
		check(not run.choose("refocus:" + path_id) and run.snapshot() == before, "Rejected refocus keeps all gold, pages, and room state")
	_restore(run, "Disabled late Archive JSON roundtrip")
	var preview_before := run.snapshot()
	run._refocus_has_future_use("blue_spirits")
	check(run.snapshot() == preview_before, "Archive eligibility preview is read only")
	run.keystones.assign(["wayfarer_compass"])
	check(run._refocus_has_future_use("blue_spirits") and not bool(_option(run, "refocus:blue_spirits").get("disabled", false)), "An unused Compass keeps reachable elite/camp alternatives available")
	run._detours_used.assign([3])
	check(not run._refocus_has_future_use("blue_spirits"), "A spent Compass cannot invent a future opportunity")
	run.keystones.clear()
	run._detours_used.clear()
	var counter := run._study_spell()
	var outgoing := run.deck[0]
	run.deck[0] = counter
	var useful := ""
	for path_id: String in ["none", "blue_tide", "blue_spirits"]:
		if run._refocus_has_future_use(path_id): useful = path_id; break
	check(not useful.is_empty(), "An already learned counter can leave a useful Haven focus slot")
	if not useful.is_empty():
		var gold_before := run.gold
		var book := run.deck.duplicate()
		check(not bool(_option(run, "refocus:" + useful).get("disabled", false)) and run.choose("refocus:" + useful), "A useful late refocus remains available")
		check(run.gold == gold_before - 18 and run.deck == book and run.study_path == useful and run.phase == "map", "Useful refocus pays exactly once without changing pages")
		_restore(run, "Useful late refocus JSON roundtrip")
	var notes := _dead_archive(RULES)
	check(notes != null, "Recreate the notes alternative")
	if notes != null:
		var starting := notes.gold
		check(notes.choose("archive_notes") and notes.gold == starting + 12 and notes.phase == "map", "A blocked refocus still leaves the twelve-gold notes action")
		_restore(notes, "Archive notes JSON roundtrip")
	var earlier := _new("Blue", 21, RULES, 2)
	earlier.study_path = "blue_sky"
	check(earlier._refocus_has_future_use("blue_spirits"), "Earlier acts are not restricted by the late-opportunity guard")
	var with_battle := _new("Blue", 21, RULES, 3)
	with_battle.current = str(with_battle._route[3][0].id)
	check(with_battle._refocus_has_future_use("blue_spirits"), "Remaining Act III battles preserve refocus opportunities")
	# Isolate the combat kind from other services in a controlled graph. The
	# Haven stock is identical, so only the ordinary fight can justify refocus.
	var isolated := _new("Blue", 32, RULES, 3)
	isolated.study_path = "blue_sky"
	isolated.current = "3-6-3"
	var final_room := _room(isolated, "boss")
	isolated._nodes[isolated.current].next.assign(["audit-fight"])
	isolated._nodes["audit-fight"] = {"id": "audit-fight", "kind": "fight", "floor": 6, "next": ["audit-treasure"]}
	isolated._nodes["audit-treasure"] = {"id": "audit-treasure", "kind": "treasure", "floor": 7, "next": [String(final_room.id)]}
	check(isolated._shop_cards_for(int(final_room.seed), "blue_sky", true) == isolated._shop_cards_for(int(final_room.seed), "blue_spirits", true), "Controlled continuation has no independent Haven benefit")
	check(isolated._refocus_has_future_use("blue_spirits"), "An ordinary fight followed only by treasure and Haven can still reward a focused spell")
	isolated._nodes["audit-fight"].kind = "treasure"
	check(not isolated._refocus_has_future_use("blue_spirits"), "Removing that fight removes the only future focus opportunity")
	sections.append("archive_choices")

func _shrine_text() -> void:
	var original := OS.get_environment("DEMIURGES_LANGUAGE")
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		var scene := ELExpeditionContent.event(source, 17, true)
		check(scene.title == ("Shrine of Knowledge" if language == "en" else "Святыня Знания"), "Shrine uses the original localized object name")
		check(not str(scene.description).is_empty(), "The Shrine has a scene in " + language)
		check(not ELExpeditionContent.outcome(source, "17:opening_spell").is_empty() and not ELExpeditionContent.outcome(source, "17:scholar_notes").is_empty(), "Both Shrine outcomes are localized")
		check(ELExpeditionContent.event(source, 17).is_empty(), "The legacy event API does not expose the Shrine")
	OS.set_environment("DEMIURGES_LANGUAGE", original)
	check(ELExpeditionContent.SCENES.size() == 18 and ELExpeditionContent.OUTCOME_LINES.size() == 35 and ELExpeditionContent.EVENTS.size() == 12, "Only the current scene/endings append; legacy event indices remain unchanged")
	sections.append("shrine_text")
