extends SceneTree
## Printed-card mechanical audit. It neither plays battles nor writes saves.
## Uses recovered starter books and the actual legacy mirror for comparison.
## godot --headless --path game --script ../tools/expedition_crafting_check.gd -- \
##   --fixture=/path/to/expedition_balance/fixture.json --seeds=64 \
##   --output=/tmp/expedition-crafting.jsonl

const Crafting := preload("res://src/expedition/crafting.gd")
const DraftCheck := preload("arena_draft_check.gd")
const STARTERS := {"Red": "STR1", "Green": "STG1", "Blue": "STU1", "Black": "STB1"}
var checks := 0
var failures := 0
var cases := 0
var profile: ELProfile
var fixture := {}
var output: FileAccess

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
	if failures <= 30: printerr("FAIL: " + label)

func _write(row: Dictionary) -> void:
	output.store_line(JSON.stringify(row, "", true, true))
	output.flush()

func _run() -> void:
	var fixture_path := _arg("fixture")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if raw is not Dictionary or raw.get("expedition_balance") is not Dictionary or raw.expedition_balance.get("books") is not Dictionary:
		printerr("Supply --fixture with printed Expedition data and recovered starter books.")
		quit(1)
		return
	fixture = raw
	profile = DraftCheck.synthetic_profile(fixture_path)
	if profile == null:
		quit(1)
		return
	output = FileAccess.open(_arg("output", "user://expedition-crafting.jsonl"), FileAccess.WRITE)
	if output == null:
		printerr("Could not open crafting audit output.")
		quit(1)
		return
	var began := Time.get_ticks_msec()
	var seeds := clampi(int(_arg("seeds", "64")), 1, 128)
	var seed_base := int(_arg("seed-base", "0"))
	var budget := clampi(int(_arg("total-ms", "120000")), 1000, 600000)
	_write({"type": "settings", "fixture": fixture_path, "seeds": seeds, "seed_base": seed_base,
		"scope": "Printed-card recipes and library offers over recovered starter books, three acts, all study paths plus Open Road; no battles or campaign outcome claims.",
		"battle_simulations": 0, "act_cost_ceilings": [3, 5, 8]})
	var unchanged := profile.tables.duplicate(true)
	var totals := _counts()
	for faction: String in STARTERS:
		var paths: Array[String] = ["none"]
		for path: Dictionary in ELExpeditionPaths.paths(profile, faction): paths.append(path.id)
		var deck := _book(faction)
		for act in range(1, 4):
			for path: String in paths:
				var group := _counts()
				for index in seeds:
					if Time.get_ticks_msec() - began >= budget:
						_write({"type": "limit", "cases": cases, "checks": checks, "failures": failures})
						output.close()
						quit(2)
						return
					var room_seed := seed_base + index
					var result := _case(faction, deck, act, room_seed, path)
					for key: String in group:
						group[key] += int(result[key])
						totals[key] += int(result[key])
					cases += 1
				_write({"type": "group", "faction": faction, "path": path, "act": act, "counts": group})
				print("CRAFT %s %s act%d: %d recipes, %d anvil recipes, library focus %d/%d" % [faction, path, act,
					group.recipes, group.anvil_recipes, group.library_focus, group.library_focus_possible])
			_legacy(faction, deck, act, seed_base, seeds)
	_boundaries()
	_check(profile.tables == unchanged, "All helper calls leave the printed profile unchanged")
	var summary := {"type": "summary", "complete": true, "cases": cases, "checks": checks, "failures": failures,
		"elapsed_ms": Time.get_ticks_msec() - began, "counts": totals, "battle_simulations": 0}
	_write(summary)
	output.close()
	print("CRAFTING AUDIT: ", JSON.stringify(summary))
	quit(1 if failures > 0 else 0)

func _book(faction: String) -> Array[String]:
	var cards: Array[String] = []
	cards.assign(fixture.expedition_balance.books[STARTERS[faction]].cards)
	return cards

func _counts() -> Dictionary:
	return {"samples": 0, "recipes": 0, "anvil_recipes": 0, "two_choice_recipes": 0,
		"recipe_focus_possible": 0, "recipe_focus": 0, "library_focus_possible": 0, "library_focus": 0,
		"library_offers": 0, "library_cards": 0}

func _legal(source: ELProfile, faction: String, code: String) -> bool:
	var row: Variant = source.table("CombatSpells").get(code)
	return row is Dictionary and row.get("Use", "+") == "+" and str(row.get("IsArtifact", "False")).to_lower() != "true" and str(row.get("Support", "False")).to_lower() != "true" and ELDuelCosts.spell_allowed(source, code, faction) and not ELCatalog.rule(source, code).is_empty()

func _pool(source: ELProfile, faction: String, owned: Array[String], act: int, rare: bool) -> Array[String]:
	var cards: Array[String] = []
	for code: String in source.table("CombatSpells"):
		if not _legal(source, faction, code) or owned.count(code) >= 4 or ELEncyclopaedia.cost(source, code) > [3, 5, 8][act - 1]: continue
		if source.table("CombatSpells")[code].get("Rarity") in (["Rare", "Unique"] if rare else ["Cantrip", "Common"]): cards.append(code)
	cards.sort()
	return cards

func _case(faction: String, deck: Array[String], act: int, room_seed: int, path: String) -> Dictionary:
	var owned: Array[String] = deck.duplicate()
	var before_deck := deck.duplicate()
	var before_owned := owned.duplicate()
	var result := _counts()
	result.samples = 1
	var rare := _pool(profile, faction, owned, act, true)
	var focus := ELExpeditionPaths.candidates(profile, path, rare, act)
	var spells := profile.table("CombatSpells")
	for consume in [1, 2]:
		var rows := Crafting.recipes(profile, faction, deck, owned, act, room_seed, path, consume)
		var label := "%s/%s/act%d/seed%d/consume%d: " % [faction, path, act, room_seed, consume]
		_check(rows == Crafting.recipes(profile, faction, deck, owned, act, room_seed, path, consume), label + "recipes repeat exactly")
		var expected_sources: Array[String] = []
		for code: String in deck:
			if code in expected_sources or deck.count(code) < consume or not _legal(profile, faction, code): continue
			if spells[code].get("Rarity") not in ["Cantrip", "Common"]: continue
			if rare.any(func(incoming: String) -> bool: return spells[incoming].get("Class") == spells[code].get("Class")):
				expected_sources.append(code)
		expected_sources.sort()
		var actual_sources: Array[String] = []
		for row: Dictionary in rows: actual_sources.append(row.source)
		_check(actual_sources == expected_sources, label + "every eligible active source appears once, sorted")
		result["recipes" if consume == 1 else "anvil_recipes"] += rows.size()
		for row: Dictionary in rows:
			var candidates: Array[String] = []
			for code: String in rare:
				if spells[code].get("Class") == spells[row.source].get("Class"): candidates.append(code)
			var incoming: Array[String] = row.incoming
			_check(int(row.consume) == consume and incoming.size() == mini(2, candidates.size()) and _unique(incoming) == incoming.size(), label + row.source + " has the exact consumption and distinct alternatives")
			_check(incoming.all(func(code: String) -> bool: return code in candidates), label + row.source + " alternatives are affordable legal rarer pages of the same class")
			var focused: Array[String] = []
			var broad: Array[String] = []
			for code: String in candidates:
				if code in focus: focused.append(code)
				else: broad.append(code)
			_check(focused.is_empty() or incoming[0] in focused, label + row.source + " path-first preference")
			_check(focused.is_empty() or broad.is_empty() or incoming.size() < 2 or incoming[1] in broad, label + row.source + " independent broad alternative")
			result.two_choice_recipes += int(incoming.size() == 2)
			result.recipe_focus_possible += int(not focused.is_empty())
			result.recipe_focus += int(not focused.is_empty() and incoming[0] in focused)
			var conserved := true
			for code: String in incoming:
				var active_after: Array[String] = deck.duplicate()
				var owned_after: Array[String] = owned.duplicate()
				for index in consume:
					active_after.erase(row.source)
					owned_after.erase(row.source)
				active_after.append(code)
				owned_after.append(code)
				conserved = conserved and active_after.size() == deck.size() - consume + 1 and owned_after.size() == owned.size() - consume + 1 and active_after.count(row.source) == deck.count(row.source) - consume and active_after.count(code) == deck.count(code) + 1 and owned_after.count(code) <= 4
			_check(conserved, label + row.source + " each offered exchange consumes exactly the stated active pages")
	var basic := _pool(profile, faction, owned, act, false)
	var library := Crafting.library_offers(profile, faction, owned, act, room_seed, path)
	var baseline := Crafting.library_offers(profile, faction, owned, act, room_seed, "none")
	var label := "%s/%s/act%d/seed%d/library: " % [faction, path, act, room_seed]
	_check(library == Crafting.library_offers(profile, faction, owned, act, room_seed, path), label + "repeat exactly")
	_check(library.size() == mini(3, basic.size()) and _unique(library) == library.size() and library.all(func(code: String) -> bool: return code in basic), label + "distinct legal affordable basic pages")
	_check(library.slice(0, 2) == baseline.slice(0, 2), label + "focus preserves first two normal offers")
	var remaining: Array[String] = basic.duplicate()
	if not library.is_empty():
		_check(not remaining.any(func(code: String) -> bool: return spells[code].get("Class") == "Creature") or spells[library[0]].get("Class") == "Creature", label + "creature preference")
		remaining.erase(library[0])
	if library.size() >= 2:
		_check(not remaining.any(func(code: String) -> bool: return spells[code].get("Class") != "Creature") or spells[library[1]].get("Class") != "Creature", label + "noncreature preference")
		remaining.erase(library[1])
	var library_focus := ELExpeditionPaths.candidates(profile, path, basic, act)
	var slot_focus := ELExpeditionPaths.candidates(profile, path, remaining, act)
	_check(slot_focus.is_empty() or (library.size() >= 3 and library[2] in slot_focus), label + "third slot prefers remaining focus")
	var focused_library := library.any(func(code: String) -> bool: return code in library_focus)
	_check(library_focus.is_empty() or focused_library, label + "an available focus appears somewhere")
	result.library_focus_possible += int(not library_focus.is_empty())
	result.library_focus += int(focused_library)
	result.library_offers += 1
	result.library_cards += library.size()
	_check(deck == before_deck and owned == before_owned, label + "caller arrays are unchanged")
	return result

func _legacy(faction: String, deck: Array[String], act: int, seed_base: int, count: int) -> void:
	var run := ELExpeditionRun.new()
	run._version = 10
	run.profile = profile
	run.preset = {"faction": faction}
	run.act = act
	run.deck.assign(deck)
	run.health = 24
	run.current = "audit"
	var offered := 0
	var expensive := 0
	var costs := {}
	for index in count:
		run._nodes = {"audit": {"seed": seed_base + index}}
		var exchange := run._mirror_exchange(false)
		if exchange.is_empty(): continue
		offered += 1
		var cost := ELEncyclopaedia.cost(profile, exchange.incoming)
		expensive += int(cost > [3, 5, 8][act - 1])
		costs[str(cost)] = int(costs.get(str(cost), 0)) + 1
	_write({"type": "legacy_mirror", "faction": faction, "act": act, "offers": offered,
		"above_act_ceiling": expensive, "incoming_cost_counts": costs,
		"scope": "Actual v10 mirror function, fixed room seeds and unchanged recovered starter; not a campaign frequency estimate."})

func _unique(cards: Array[String]) -> int:
	var seen := {}
	for code: String in cards: seen[code] = true
	return seen.size()

func _narrow(codes: Array[String]) -> ELProfile:
	var result := ELProfile.new()
	result.id = "el2"
	result.tables = profile.tables.duplicate(true)
	result.tables.CombatSpells = {}
	for code: String in codes:
		result.tables.CombatSpells[code] = profile.tables.CombatSpells[code].duplicate(true)
	return result

func _boundaries() -> void:
	var empty: Array[String] = []
	var deck: Array[String] = ["STRT", "STRT", "ZAPP", "ZAPP"]
	var baseline := Crafting.recipes(profile, "Red", deck, deck, 2, 17, "red_raiders")
	_check(not baseline.is_empty(), "Boundary source has printed recipes")
	_check(Crafting.recipes(null, "Red", deck, deck, 1, 0, "none").is_empty() and Crafting.library_offers(null, "Red", deck, 1, 0, "none").is_empty(), "Null profile returns no offers")
	for faction: String in ["White", "Unknown", ""]:
		_check(Crafting.recipes(profile, faction, deck, deck, 1, 0, "none").is_empty() and Crafting.library_offers(profile, faction, deck, 1, 0, "none").is_empty(), "Unsupported faction has no offers: " + faction)
	for act in [0, 4]:
		_check(Crafting.recipes(profile, "Red", deck, deck, act, 0, "none").is_empty() and Crafting.library_offers(profile, "Red", deck, act, 0, "none").is_empty(), "Invalid act has no offers")
	for consume in [0, 3, -1]:
		_check(Crafting.recipes(profile, "Red", deck, deck, 1, 0, "none", consume).is_empty(), "Unsupported consumption has no recipes")
	var first_game := _narrow(["STRT", "STRG"])
	first_game.id = "el1"
	_check(Crafting.recipes(first_game, "Red", deck, deck, 1, 0, "none").is_empty() and Crafting.library_offers(first_game, "Red", deck, 1, 0, "none").is_empty(), "First-game profiles have no Expedition crafting")
	var no_cards := _narrow(empty)
	_check(Crafting.recipes(no_cards, "Red", deck, deck, 1, 0, "none").is_empty() and Crafting.library_offers(no_cards, "Red", deck, 1, 0, "none").is_empty(), "Missing catalog returns empty instead of invented cards")
	_check(Crafting.recipes(profile, "Red", empty, deck, 1, 0, "none").is_empty(), "Reserve-owned cards alone cannot be consumed")
	for path: String in ["missing", "blue_sky"]:
		_check(Crafting.recipes(profile, "Red", deck, deck, 2, 17, path) == Crafting.recipes(profile, "Red", deck, deck, 2, 17, "none") and Crafting.library_offers(profile, "Red", deck, 2, 17, path) == Crafting.library_offers(profile, "Red", deck, 2, 17, "none"), "Unknown or wrong-faction path leaves ordinary offers")
	var edited := Crafting.recipes(profile, "Red", deck, deck, 2, 17, "red_raiders")
	edited[0].incoming.clear()
	edited[0].source = "changed"
	_check(Crafting.recipes(profile, "Red", deck, deck, 2, 17, "red_raiders") == baseline, "Recipe dictionaries and nested arrays do not alias later calls")
	var original_library := Crafting.library_offers(profile, "Red", deck, 2, 17, "red_raiders")
	var edited_library := Crafting.library_offers(profile, "Red", deck, 2, 17, "red_raiders")
	edited_library.clear()
	_check(Crafting.library_offers(profile, "Red", deck, 2, 17, "red_raiders") == original_library, "Library arrays do not alias later calls")
	var reversed: Array[String] = deck.duplicate()
	reversed.reverse()
	_check(Crafting.recipes(profile, "Red", reversed, reversed, 2, 17, "red_raiders") == baseline, "Active and owned array order does not reroll recipes")
	var single_source: Array[String] = ["STRT", "STRT"]
	var independent := Crafting.recipes(profile, "Red", single_source, single_source, 2, 17, "red_raiders")
	_check(independent.size() == 1 and independent[0] == baseline.filter(func(row: Dictionary) -> bool: return row.source == "STRT")[0], "Adding an unrelated source never advances another source's RNG")
	var reversed_profile := _narrow(empty)
	var keys: Array = profile.table("CombatSpells").keys()
	keys.reverse()
	for code: String in keys: reversed_profile.tables.CombatSpells[code] = profile.tables.CombatSpells[code].duplicate(true)
	_check(Crafting.recipes(reversed_profile, "Red", deck, deck, 2, 17, "red_raiders") == baseline and Crafting.library_offers(reversed_profile, "Red", deck, 2, 17, "red_raiders") == original_library, "Catalog dictionary order never changes offers")
	_sparse_boundaries()
	_filter_boundaries()

func _sparse_boundaries() -> void:
	var common := "STRT"
	var rare_pool := _pool(profile, "Red", [], 1, true).filter(func(code: String) -> bool: return profile.table("CombatSpells")[code].get("Class") == "Creature")
	_check(rare_pool.size() >= 2, "Printed Act I fixture has at least two craftable red creatures")
	if rare_pool.size() < 2: return
	var rare := str(rare_pool[0])
	var second := str(rare_pool[1])
	var narrow := _narrow([common, rare])
	var one: Array[String] = [common]
	var two: Array[String] = [common, common]
	var rows := Crafting.recipes(narrow, "Red", two, two, 1, 3, "none", 2)
	_check(rows.size() == 1 and rows[0].incoming == [rare] and int(rows[0].consume) == 2, "A single legal candidate remains a single two-page recipe")
	_check(Crafting.recipes(narrow, "Red", one, two, 1, 3, "none", 2).is_empty(), "One active plus one reserved copy cannot satisfy Anvil consumption")
	_check(Crafting.recipes(narrow, "Red", one, one, 1, 3, "none", 1).size() == 1, "One active page still permits a normal recipe")
	for count in [4, 5]:
		var owned: Array[String] = two.duplicate()
		for index in count: owned.append(rare)
		_check(Crafting.recipes(narrow, "Red", two, owned, 1, 3, "none").is_empty(), "%d total owned incoming copies are excluded, including reserve" % count)
	var already_active: Array[String] = [common, rare, rare, rare, rare]
	var empty: Array[String] = []
	_check(Crafting.recipes(narrow, "Red", already_active, empty, 1, 3, "none").is_empty(), "Omitting active pages from owned cannot hide a known copy cap")
	var expanded := _narrow([common, rare, second])
	_check(Crafting.recipes(expanded, "Red", two, two, 1, 3, "none")[0].incoming.size() == 2, "Exactly two available rarer pages are both offered")
	var expensive := _narrow([common, "CCLP"])
	_check(Crafting.recipes(expensive, "Red", two, two, 1, 3, "none").is_empty() and Crafting.recipes(expensive, "Red", two, two, 3, 3, "none").is_empty(), "Nine-ether Cyclops is never forced through any act ceiling")
	var one_basic := _narrow([common])
	_check(Crafting.library_offers(one_basic, "Red", empty, 1, 3, "none") == one, "Single-card Library returns one real page")
	_check(Crafting.library_offers(one_basic, "Red", [common, common, common, common], 1, 3, "none").is_empty(), "Library respects four owned copies")
	_check(Crafting.library_offers(_narrow([rare]), "Red", empty, 1, 3, "none").is_empty(), "Library never substitutes a rare page for an empty basic pool")
	var two_basic := _narrow([common, "ZAPP"])
	_check(Crafting.library_offers(two_basic, "Red", empty, 1, 3, "none") == [common, "ZAPP"], "Two-card sparse Library keeps creature/noncreature order")
	for column: String in ["Class", "Rarity"]:
		var changed := _narrow([common, rare])
		changed.tables.CombatSpells[rare][column] = "Sorcery" if column == "Class" else "Common"
		_check(Crafting.recipes(changed, "Red", two, two, 1, 3, "none").is_empty(), "Incoming page must preserve class and improve rarity: " + column)

func _filter_boundaries() -> void:
	var rare_pool := _pool(profile, "Red", [], 1, true).filter(func(code: String) -> bool: return profile.table("CombatSpells")[code].get("Class") == "Creature")
	if rare_pool.is_empty(): return
	var rare := str(rare_pool[0])
	var book: Array[String] = ["STRT", "STRT"]
	for change: Array in [["IsArtifact", "True"], ["IsArtifact", true], ["Support", "True"], ["Support", true], ["Use", "-"], ["Color", "Blue"]]:
		var bad_source := _narrow(["STRT", rare])
		bad_source.tables.CombatSpells.STRT[change[0]] = change[1]
		_check(Crafting.recipes(bad_source, "Red", book, book, 1, 0, "red_raiders").is_empty() and Crafting.library_offers(bad_source, "Red", [], 1, 0, "red_raiders").is_empty(), "Source and Library reject %s=%s" % [change[0], str(change[1])])
		var bad_incoming := _narrow(["STRT", rare])
		bad_incoming.tables.CombatSpells[rare][change[0]] = change[1]
		_check(Crafting.recipes(bad_incoming, "Red", book, book, 1, 0, "red_raiders").is_empty(), "Recipe target rejects %s=%s" % [change[0], str(change[1])])
	var unsupported := _narrow(["ZAPP"])
	unsupported.tables.CombatSpells.CRAFT_MISSING = {"Class": "Sorcery", "Rarity": "Rare", "Color": "Red", "Use": "+", "Cost": 1}
	var source: Array[String] = ["ZAPP"]
	_check(Crafting.recipes(unsupported, "Red", source, source, 1, 0, "none").is_empty(), "Unimplemented incoming spell is never crafted")
	unsupported.tables.CombatSpells.CRAFT_MISSING.Rarity = "Common"
	_check("CRAFT_MISSING" not in Crafting.library_offers(unsupported, "Red", [], 1, 0, "none"), "Unimplemented basic spell is never offered by Library")
