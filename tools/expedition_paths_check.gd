extends SceneTree
## Study-path catalog checks using printed wiki data or installed tables.
## No campaign assets/checkpoints are written. This checks offer eligibility,
## not combat outcomes or the original game's numeric balance.
## python3 tools/expedition_balance_fixture.py --workspace /tmp/expedition-balance
## godot --headless --path game --script ../tools/expedition_paths_check.gd -- \
##   --fixture=/tmp/expedition-balance/fixture.json

const Paths := preload("res://src/expedition/paths.gd")
const DraftCheck := preload("arena_draft_check.gd")
const FACTIONS := ["Red", "Green", "Blue", "Black"]
var checks := 0
var failures := 0

func _arg(name: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return ""

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile: ELProfile
	if not _arg("el2").is_empty():
		profile = ELProfile.new()
		if not profile.mount("el2", _arg("el2")):
			printerr(profile.error)
			quit(1)
			return
	elif not _arg("fixture").is_empty():
		profile = DraftCheck.synthetic_profile(_arg("fixture"))
	if profile == null:
		printerr("Supply --fixture with generated wiki data, or --el2 with an installation.")
		quit(1)
		return
	var pool: Array[String] = []
	pool.assign(profile.table("CombatSpells").keys())
	pool.sort()
	var ids: Array[String] = []
	for faction: String in FACTIONS:
		var available := Paths.paths(profile, faction)
		check(available.size() == 3, faction + ": three distinct study choices")
		for path: Dictionary in available:
			ids.append(path.id)
			var prefix := str(path.id) + ": "
			check(path.faction == faction and not str(path.title).is_empty() and not str(path.description).is_empty(), prefix + "localized identity and faction are complete")
			check(Paths.find(profile, path.id) == path, prefix + "lookup reproduces the offered identity")
			var legal: bool = not path.cards.is_empty()
			var unique := {}
			for card: String in path.cards:
				legal = legal and ELDuelCosts.spell_allowed(profile, card, faction) and not ELCatalog.rule(profile, card).is_empty()
				unique[card] = true
			var sorted_cards: Array = path.cards.duplicate()
			sorted_cards.sort()
			check(legal and unique.size() == path.cards.size() and sorted_cards == path.cards, prefix + "full catalog supplies sorted unique playable nonartifact cards")
			var counts: Array[int] = []
			for act in range(1, 4):
				var focused := Paths.candidates(profile, path.id, pool, act)
				counts.append(focused.size())
				var affordable := not focused.is_empty()
				for card: String in focused:
					affordable = affordable and card in pool and card in path.cards and ELEncyclopaedia.cost(profile, card) <= [3, 5, 8][act - 1]
				check(affordable, prefix + "Act %d has affordable legal candidates within the supplied pool" % act)
			var restricted: Array[String] = [str(path.cards[0]), str(path.cards[0])]
			check(Paths.candidates(profile, path.id, restricted, 3).size() <= 1, prefix + "duplicate pool entries never duplicate an offer")
			var excluded: Array[String] = pool.duplicate()
			excluded.erase(path.cards[0])
			check(path.cards[0] not in Paths.candidates(profile, path.id, excluded, 3), prefix + "a caller-excluded or copy-capped spell cannot return")
			var shuffled: Array[String] = pool.duplicate()
			shuffled.reverse()
			check(Paths.candidates(profile, path.id, shuffled, 2) == Paths.candidates(profile, path.id, pool, 2), prefix + "input catalog order does not affect candidate order")
			print("POOL: %s total=%d affordable=%s" % [path.id, path.cards.size(), counts])
	check(ids.size() == 12 and _unique(ids) == 12, "All twelve path IDs are unique")
	_check_boundaries(profile, pool)
	_check_filtering(profile)
	_check_localization(profile)
	print("Expedition study paths: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _unique(values: Array[String]) -> int:
	var seen := {}
	for value: String in values: seen[value] = true
	return seen.size()

func _check_boundaries(profile: ELProfile, pool: Array[String]) -> void:
	var empty: Array[String] = []
	check(Paths.paths(null, "Red").is_empty() and Paths.paths(profile, "White").is_empty(), "Missing profiles and unsupported starter factions have no paths")
	check(Paths.find(profile, "missing").is_empty() and Paths.candidates(profile, "missing", pool, 1).is_empty(), "Unknown path IDs cannot bias rewards")
	check(Paths.candidates(profile, "red_raiders", empty, 1).is_empty(), "An exhausted supplied pool falls back without inventing a spell")
	check(Paths.candidates(profile, "red_raiders", pool, 0).is_empty() and Paths.candidates(profile, "red_raiders", pool, 4).is_empty(), "Invalid acts cannot bypass the affordability ceiling")
	var four: Array[String] = ["WRSP"]
	check(Paths.candidates(profile, "blue_spirits", four, 1).is_empty() and Paths.candidates(profile, "blue_spirits", four, 2) == four, "Printed four-ether Warrior Spirit is deferred until Act II")
	var seven: Array[String] = ["GRFG"]
	check(Paths.candidates(profile, "green_grove", seven, 2).is_empty() and Paths.candidates(profile, "green_grove", seven, 3) == seven, "Printed seven-ether Gargantuan Fingus is deferred until Act III")
	var original := Paths.find(profile, "red_raiders")
	var edited := Paths.find(profile, "red_raiders")
	edited.cards.clear()
	edited.title = "edited"
	check(Paths.find(profile, "red_raiders") == original, "Returned metadata and card arrays do not alias shared definitions")
	var faction_paths := Paths.paths(profile, "Red")
	faction_paths[0].cards.append("missing")
	faction_paths.clear()
	check(Paths.find(profile, "red_raiders") == original, "Editing a returned faction list cannot affect later calls")
	var previous_id := profile.id
	profile.id = "el1"
	check(Paths.paths(profile, "Red").is_empty() and Paths.find(profile, "red_raiders").is_empty(), "First-game profiles never acquire Expedition study paths")
	profile.id = previous_id

func _check_filtering(profile: ELProfile) -> void:
	var spells := profile.table("CombatSpells")
	var original: Dictionary = spells.STRT.duplicate(true)
	for change: Array in [["IsArtifact", "True"], ["IsArtifact", true], ["Support", "True"], ["Use", "-"], ["Color", "Blue"]]:
		spells.STRT = original.duplicate(true)
		spells.STRT[change[0]] = change[1]
		check("STRT" not in Paths.find(profile, "red_raiders").cards, "A matching code is excluded for %s=%s" % [change[0], str(change[1])])
	spells.STRT = original
	spells["PATH_UNIMPLEMENTED"] = {"Class": "Creature", "Color": "Red", "Cost": 1, "Use": "+"}
	profile.tables.CombatCreatures["PATH_UNIMPLEMENTED"] = {"Race": "Rat", "Power": 1, "Toughness": 1, "Flags": []}
	check("PATH_UNIMPLEMENTED" not in Paths.find(profile, "red_raiders").cards, "A matching printed race never bypasses implemented-rule validation")
	spells.erase("PATH_UNIMPLEMENTED")
	profile.tables.CombatCreatures.erase("PATH_UNIMPLEMENTED")
	var saved := profile.tables
	profile.tables = {"CombatSpells": {}, "CombatCreatures": {}}
	var empty: Array[String] = []
	check(Paths.paths(profile, "Red").size() == 3 and Paths.find(profile, "red_raiders").cards.is_empty() and Paths.candidates(profile, "red_raiders", empty, 1).is_empty(), "Partial catalogs retain stable identities but never force an unavailable card")
	profile.tables = saved

func _check_localization(profile: ELProfile) -> void:
	var previous := OS.get_environment("DEMIURGES_LANGUAGE")
	OS.set_environment("DEMIURGES_LANGUAGE", "en")
	var english := Paths.find(profile, "blue_sky")
	OS.set_environment("DEMIURGES_LANGUAGE", "ru")
	var russian := Paths.find(profile, "blue_sky")
	check(english.title != russian.title and english.description != russian.description, "Study path titles and descriptions have English and Russian text")
	check(english.id == russian.id and english.cards == russian.cards, "Language never changes path identity or spell eligibility")
	if previous.is_empty(): OS.unset_environment("DEMIURGES_LANGUAGE")
	else: OS.set_environment("DEMIURGES_LANGUAGE", previous)
