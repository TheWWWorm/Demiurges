extends SceneTree
## Real printed spell/creature rules with synthetic hero life and channel income.
## Mechanical checks, not combat balance or scripted-campaign coverage.
## godot --headless --path game --script ../tools/expedition_attunements_check.gd -- \
##   --fixture=/path/to/expedition_balance/fixture.json --output=/tmp/attunements.json

const Powers := preload("res://src/expedition/attunements.gd")
const DraftCheck := preload("arena_draft_check.gd")
const STARTERS := {"Red": "STR1", "Green": "STG1", "Blue": "STU1", "Black": "STB1"}
const BODY := {"Red": "STRT", "Green": "TIWR", "Blue": "AVSC", "Black": "MCWO"}
var profile: ELProfile
var fixture := {}
var checks := 0
var failures: Array[String] = []
var started := 0
var roundtrips := 0
var native_decisions := 0
var native_rows: Array[Dictionary] = []

func _arg(name: String, fallback := "") -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.trim_prefix("--" + name + "=")
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok: return
	failures.append(label)
	printerr("FAIL: " + label)

func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _run() -> void:
	var fixture_path := _arg("fixture")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if data is not Dictionary or data.get("expedition_balance", {}).get("books") is not Dictionary:
		printerr("Supply --fixture with the printed-card data and recovered starter books.")
		quit(1)
		return
	fixture = data
	profile = DraftCheck.synthetic_profile(fixture_path)
	if profile == null:
		quit(1)
		return
	# The recovered fixture has no CONC rows. Register only its original
	# three rank definitions here; the effect is the unchanged duel rule.
	# Generic synthetic fixtures and their historical save goldens stay intact.
	for rank in 3:
		profile.tables.HeroesSkills["CONC%d" % (rank + 1)] = {
			"Code": "CONC", "Level": rank + 1, "Name": "Concentration", "Duel": "True",
			"Description": "Draw an additional spell every %d own turns." % (4 - rank)}
	profile.tables.HeroesSpecs = {}
	var began := Time.get_ticks_msec()
	var unchanged := profile.tables.duplicate(true)
	_catalog()
	_preparation()
	_openings()
	_atomic_opening()
	_army_auras()
	_sacrifices()
	_second_birth()
	_aspects()
	_attraction_and_barrier()
	_concentration()
	_native()
	_check(profile.tables == unchanged, "All checks leave printed card and skill definitions unchanged")
	var report := {"complete": true, "checks": checks, "failures": failures.size(), "failure_labels": failures,
		"duel_setups": started, "save_roundtrips": roundtrips, "native_available": ELCombatBrain.available,
		"native_decisions": native_decisions, "native": native_rows, "elapsed_ms": Time.get_ticks_msec() - began,
		"fixture": fixture_path, "forced_winners": 0, "complete_ai_battles": 0,
		"scope": "Original printed spells, creatures and recovered starters; isolated original CONC ranks; synthetic hero life and channel income. Focused effect, draw, charge, dispel, save, and bounded native-decision checks, not balance or campaign-script outcomes."}
	var output := FileAccess.open(_arg("output", "user://expedition-attunements.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t", true, true))
		output.close()
	else:
		printerr("Could not write attunement report.")
		failures.append("report write")
	print("ATTUNEMENTS: %d checks, %d failures; %d duel setups, %d save roundtrips, %d native decisions" % [checks, failures.size(), started, roundtrips, native_decisions])
	ELPracticeAI.finish()
	quit(0 if failures.is_empty() else 1)

func _book(faction: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(fixture.expedition_balance.books[STARTERS[faction]].cards)
	return result

func _ids(rows: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in rows: result.append(row.id)
	return result

func _copy_profile() -> ELProfile:
	var result := ELProfile.new()
	result.id = profile.id
	result.root = profile.root
	result.tables = profile.tables.duplicate(true)
	result.texts = profile.texts.duplicate(true)
	return result

func _catalog() -> void:
	var rows := Powers.catalog(profile)
	_check(rows.size() == 10 and _ids(rows).size() == 10, "Ten stable major-power identities")
	var before := profile.tables.duplicate(true)
	for faction: String in STARTERS:
		var book := _book(faction)
		var book_before := book.duplicate()
		var owned: Array[String] = []
		var offers := Powers.available(profile, faction, book, owned)
		_check(offers.size() == 3, faction + ": two faction powers and Energy Barrier for the original starter")
		_check(offers.all(func(row: Dictionary) -> bool: return row.faction in [faction, "Colorless"]), faction + ": no other faction powers")
		_check(_ids(offers) == _ids(Powers.available(profile, faction, book, owned)), faction + ": repeated availability is deterministic")
		owned.assign(_ids(offers))
		_check(Powers.available(profile, faction, book, owned).is_empty(), faction + ": owned powers leave the offer pool")
		_check(book == book_before, faction + ": availability does not mutate its book")
		book.append("OUD3")
		_check("power_transfer_aspects" in _ids(Powers.available(profile, faction, book, [])), faction + ": a supported Pale page unlocks Transfer Aspects")
		_check("power_transfer_aspects" not in _ids(Powers.available(profile, faction, ["OUD3"], [])), faction + ": Pale-only book cannot exchange aspects")
		_check("power_transfer_aspects" not in _ids(Powers.available(profile, faction, ["OSJ1", BODY[faction]], [])), faction + ": first Pale Jammer enters bright and does not supply the Pale target")
		_check("power_transfer_aspects" in _ids(Powers.available(profile, faction, ["OUD3", "OSJ1"], [])), faction + ": first Pale Jammer can supply the bright target")
	_check("power_transfer_aspects" not in _ids(Powers.available(profile, "Black", ["OUD3", "BRMZ"], [])), "Untargetable bright creature cannot qualify Transfer Aspects")
	_check("power_transfer_aspects" not in _ids(Powers.available(profile, "Red", ["OUD3", "TIWR"], [])), "Wrong-faction bright page cannot qualify Transfer Aspects")
	_check(Powers.has_aspect_pair(profile, "Red", ["OUD3", "STRT"]) and not Powers.has_aspect_pair(profile, "Red", ["OUD3"]) and not Powers.has_aspect_pair(null, "Red", ["OUD3", "STRT"]), "Public readiness wrapper uses the same legal two-aspect target requirement and handles a missing profile")
	var empty := ELProfile.new()
	empty.id = "el2"
	_check(Powers.available(empty, "Red", ["OUD3", "STRT"], []).is_empty(), "Missing tables offer no unsupported powers")
	_check(Powers.catalog(empty).size() == 10 and not Powers.find(empty, "power_transfer_aspects").is_empty(), "Catalog identity survives a removed or missing book")
	_check(Powers.available(profile, "White", [], []).is_empty(), "Unsupported starter faction is rejected")
	_check(Powers.catalog(null).is_empty() and Powers.find(null, "power_burnout").is_empty(), "Missing profile is handled")
	empty.id = "el1"
	_check(Powers.catalog(empty).is_empty() and Powers.available(empty, "Red", [], []).is_empty(), "Powers cannot change original EL1 modes")
	for flag: String in ["Use", "IsArtifact", "Support"]:
		var changed := _copy_profile()
		changed.tables.CombatSpells.BROT[flag] = "-" if flag == "Use" else "True"
		_check("power_burnout" not in _ids(Powers.available(changed, "Red", _book("Red"), [])), "Unavailable BROT excluded by " + flag)
		changed = _copy_profile()
		changed.tables.CombatSpells.OUD3[flag] = "-" if flag == "Use" else "True"
		_check("power_transfer_aspects" not in _ids(Powers.available(changed, "Red", ["OUD3", "STRT"], [])), "Ineligible Pale page excluded by " + flag)
	var missing := _copy_profile()
	missing.tables.HeroesSkills.erase("CONC2")
	_check("power_concentration" not in _ids(Powers.available(missing, "Blue", _book("Blue"), [])), "Concentration requires the original advanced-rank definition")
	missing = _copy_profile()
	missing.tables.CombatSpells.erase("ENBR")
	_check("power_energy_barrier" not in _ids(Powers.available(missing, "Red", [], [])), "A missing opening spell is not offered")
	_check(Powers.is_power("power_burnout") and not Powers.is_power("power_unknown") and not Powers.is_power("living_heart"), "Only the whitelist identifies powers")
	var old_language := OS.get_environment("DEMIURGES_LANGUAGE")
	for language: String in ["en", "ru"]:
		OS.set_environment("DEMIURGES_LANGUAGE", language)
		var path := ProjectSettings.globalize_path("res://").path_join("../wiki/catalog/" + language + ".json")
		var wiki: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(wiki is Dictionary and wiki.get("pages") is Array, language + ": checked-in wiki catalog loads")
		if wiki is not Dictionary: continue
		var titles := {}
		for page: Dictionary in wiki.pages: titles[page.key] = page.title
		for row: Dictionary in Powers.catalog(profile):
			_check(titles.get(row.source) == row.title, language + ": " + row.id + " uses the exact original catalog title")
			_check(not row.description.is_empty() and not row.context.is_empty(), language + ": " + row.id + " has effect and limitation text")
	OS.set_environment("DEMIURGES_LANGUAGE", old_language)
	rows[0].title = "Caller edit"
	_check(Powers.catalog(profile)[0].title != "Caller edit", "Catalog rows do not alias later calls")
	_check(profile.tables == before, "Availability and localization are read-only")

func _preparation() -> void:
	for rank in [-1, 0, 1, 2]:
		var hero := {"skills": {"PRVD": 0}, "cards": _book("Blue"), "artifacts": [{"name": "test", "nested": [1]}]}
		if rank >= 0: hero.skills["CONC"] = rank
		var before := hero.duplicate(true)
		var result := Powers.prepare_hero(hero, ["power_concentration"])
		_check(int(result.skills.CONC) == maxi(1, rank), "Concentration grants the minimum rank and preserves rank " + str(rank))
		_check(ELHeroSkills.valid_ranks(profile, result.skills), "Prepared Concentration skill keys and ranks are valid for source rank " + str(rank))
		_check(result.skills.keys().all(func(key: Variant) -> bool: return key is String), "Granted skill keys are String, not StringName")
		_check(hero == before, "Preparation does not mutate source rank " + str(rank))
		result.skills["CONC"] = 0
		result.cards.clear()
		result.artifacts[0].nested.append(2)
		_check(hero == before, "Prepared nested arrays and skills do not alias the source")
	var untouched := {"skills": {"PRVD": 0}, "cards": _book("Red")}
	_check(Powers.prepare_hero(untouched, ["power_burnout"]) == untouched, "Opening enchantments do not alter hero skills or book")
	_check(not Powers.prepare_hero(untouched, []).skills.has("CONC"), "Suppressed Concentration is absent from the prepared hero")

func _duel(faction: String, ids: Array[String] = [], first := 0, prepare := true) -> ELDuel:
	var hero := {"faction": faction, "hero": ELDuelPresets.DEFAULT_HEROES[faction], "cards": _book(faction), "level": 5, "health": 80,
		"skills": {"PRVD": 0}, "specialization": "NONE"}
	if prepare: hero = Powers.prepare_hero(hero, ids)
	var enemy := {"faction": "Red", "hero": ELDuelPresets.DEFAULT_HEROES.Red, "cards": _book("Red"), "level": 5, "health": 80,
		"skills": {"PRVD": 0}, "specialization": "NONE"}
	var duel := ELDuel.new()
	var ok := duel.start(profile, 192837, {"adventure": true, "players": [hero, enemy], "arena": "Green.001", "first_side": first})
	started += 1
	_check(ok, "Real duel starts for %s/%s/first%d: %s" % [faction, ",".join(ids), first, duel.error])
	return duel

func _with_power(faction: String, ids: Array[String], first := 0) -> ELDuel:
	var duel := _duel(faction, ids, first)
	_check(Powers.apply_opening(duel, ids), "Opening applies: " + ",".join(ids))
	return duel

func _roundtrip(duel: ELDuel, label: String) -> ELDuel:
	var before := duel.snapshot()
	var resumed := ELDuel.new()
	var ok := resumed.restore(profile, {"format": "etherlords-duel", "version": 1, "state": _json(before)})
	roundtrips += 1
	_check(ok, label + ": JSON save restores: " + resumed.error)
	if ok: _check(resumed.snapshot() == before, label + ": every saved duel field is exact")
	return resumed

func _openings() -> void:
	for row: Dictionary in Powers.catalog(profile):
		var faction: String = "Red" if row.faction == "Colorless" else row.faction
		var ids: Array[String] = [row.id]
		for first in 2:
			var duel := _duel(faction, ids, first)
			var before := duel.snapshot()
			var history_size := duel.history.size()
			_check(Powers.apply_opening(duel, ids), "%s/first%d attaches after normal startup" % [row.id, first])
			_check(duel.setup.get(Powers.OPENING_MARKER) == ids, row.id + ": stable saved marker")
			var without := duel.snapshot()
			without.setup.erase(Powers.OPENING_MARKER)
			without.heroes[0].enchantments = []
			without.next_enchantment = before.next_enchantment
			_check(without == before, row.id + ": no setup life, mana, draws, channels, charges, RNG, or opponent changes")
			var later_events := duel.history.slice(history_size)
			_check(later_events.all(func(event: Dictionary) -> bool: return event.kind not in ["cast", "draw", "damage", "ether", "skill"]), row.id + ": attachment is not a cast or triggered activation")
			if not row.card.is_empty():
				_check(duel._enchantment_count(0, row.card) == 1 and duel.heroes[1].enchantments.is_empty(), row.id + ": exactly one friendly opening copy")
				var enchantment: Dictionary = duel.heroes[0].enchantments[0]
				_check(not enchantment.get("fixed", false), row.id + ": opening enchantment is dispellable")
				_check(row.card in ELCombatBrain.CHARMS, row.id + ": original enchantment has a native model")
			var saved := duel.snapshot()
			_check(Powers.apply_opening(duel, ids) and duel.snapshot() == saved, row.id + ": applying the same opening twice is inert")
			var resumed := _roundtrip(duel, row.id + "/first" + str(first))
			if resumed.heroes.is_empty(): continue
			saved = resumed.snapshot()
			_check(Powers.apply_opening(resumed, ids) and resumed.snapshot() == saved, row.id + ": resume does not reattach")
			if not row.card.is_empty():
				resumed._dispel(0, int(resumed.heroes[0].enchantments[0].id))
				_check(resumed._enchantment_count(0, row.card) == 0, row.id + ": ordinary dispel removes the opening power")
				saved = resumed.snapshot()
				_check(Powers.apply_opening(resumed, ids) and resumed.snapshot() == saved, row.id + ": the marker cannot resurrect a dispelled power")
				var after_dispel := _roundtrip(resumed, row.id + "/dispel/first" + str(first))
				_check(after_dispel._enchantment_count(0, row.card) == 0, row.id + ": the dispelled state survives save")

func _atomic_opening() -> void:
	for values: Array in [["power_burnout", "power_second_birth"], ["power_burnout", "power_missing"]]:
		var ids: Array[String] = []
		ids.assign(values)
		var duel := _duel("Red")
		var before := duel.snapshot()
		_check(not Powers.apply_opening(duel, ids) and duel.snapshot() == before, "An invalid multi-power plan applies none of its powers")
	var unprepared := _duel("Blue", [], 0, false)
	var before := unprepared.snapshot()
	_check(not Powers.apply_opening(unprepared, ["power_concentration"]) and unprepared.snapshot() == before, "Concentration cannot be injected after initial hero preparation")
	var duel := _with_power("Red", ["power_burnout"])
	before = duel.snapshot()
	_check(not Powers.apply_opening(duel, ["power_energy_barrier"]) and duel.snapshot() == before, "A saved marker rejects a changed identity without mutation")
	duel.setup[Powers.OPENING_MARKER] = "forged"
	before = duel.snapshot()
	_check(not Powers.apply_opening(duel, ["power_burnout"]) and duel.snapshot() == before, "Malformed marker fails safely")
	duel = _duel("Red")
	_check(Powers.apply_opening(duel, ["living_heart", "power_burnout", "power_burnout"]), "Non-power keystones are ignored and repeated power IDs deduplicate")
	_check(duel.setup[Powers.OPENING_MARKER] == ["power_burnout"] and duel._enchantment_count(0, "BROT") == 1, "The marker contains only distinct known powers")
	duel = _duel("Red")
	duel.end_phase()
	duel.end_phase()
	before = duel.snapshot()
	_check(not Powers.apply_opening(duel, ["power_burnout"]) and duel.snapshot() == before, "An unmarked later round cannot acquire opening powers")
	duel = _duel("Red")
	_check(Powers.apply_opening(duel, []) and duel.setup[Powers.OPENING_MARKER] == [], "A suppressed or empty active-power list has an explicit empty marker")

func _summon(duel: ELDuel, side: int, code: String) -> int:
	var id := duel.next_id
	duel._summon(side, code)
	_check(duel.creatures.has(id), "Original summon succeeds for " + code)
	return id

func _ability(duel: ELDuel, card: String) -> Dictionary:
	for row: Dictionary in duel.abilities(0):
		if row.get("enchantment_card") == card: return row
	_check(false, "Expected original hero ability for " + card)
	return {}

func _army_auras() -> void:
	for first in 2:
		var duel := _duel("Red", [], first)
		var original := _summon(duel, 0, "STRT")
		var changed_sides := _summon(duel, 1, "STRT")
		duel._move_army(duel.creatures[changed_sides], 0)
		var immune := _summon(duel, 0, "BRMZ")
		var pale := _summon(duel, 0, "OUD3")
		_check(not duel.has_flag(original, "FS") and not duel.has_flag(changed_sides, "FS"), "Fixture army starts without First Strike")
		_check(Powers.apply_opening(duel, ["power_crystal_ball"]), "Crystal Ball attaches to an already summoned startup army")
		_check(duel.has_flag(original, "FS") and duel.has_flag(changed_sides, "FS"), "Crystal Ball refreshes ordinary and transferred existing creature aura lists")
		_check(not duel.has_flag(immune, "FS") and not duel.has_flag(pale, "FS"), "Original immunity and Pale suppression still apply")
		var newcomer := _summon(duel, 0, "STRT")
		_check(duel.has_flag(newcomer, "FS"), "Crystal Ball covers later arrivals")
		duel.plane_change(pale, false)
		_check(duel.has_flag(pale, "FS"), "A Pale creature receives the aura when it manifests")
		_roundtrip(duel, "Crystal Ball with an existing army")
		duel._dispel(0, int(duel.heroes[0].enchantments[0].id))
		_check(not duel.has_flag(original, "FS") and not duel.has_flag(changed_sides, "FS") and not duel.has_flag(newcomer, "FS"), "Dispelling Crystal Ball refreshes every covered creature")
		duel = _duel("Blue", [], first)
		var existing := _summon(duel, 1, "STRT")
		_check(Powers.apply_opening(duel, ["power_hostile_ambience"]), "Hostile Ambience attaches after startup")
		_check(not duel.creatures[existing].resting, "Hostile Ambience does not retroactively rest an existing army")
		var late := _summon(duel, 1, "STRT")
		var friendly := _summon(duel, 0, "AVSC")
		var immune_enemy := _summon(duel, 1, "BRMZ")
		var pale_enemy := _summon(duel, 1, "OUD3")
		_check(duel.creatures[late].resting and not duel.creatures[friendly].resting, "Hostile Ambience rests only new enemy arrivals")
		_check(not duel.creatures[immune_enemy].resting and not duel.creatures[pale_enemy].resting, "Magic immunity and EL2 Pale arrival exception remain effective")
		duel._dispel(0, int(duel.heroes[0].enchantments[0].id))
		late = _summon(duel, 1, "STRT")
		_check(not duel.creatures[late].resting, "Dispelling Hostile Ambience stops the arrival penalty")

func _sacrifices() -> void:
	var duel := _with_power("Red", ["power_burnout"])
	duel.heroes[0].mana = 10
	var body := _summon(duel, 0, "STRT")
	var second := _summon(duel, 0, "STRT")
	var power := int(duel.creatures[body].power)
	var ability := _ability(duel, "BROT")
	var health := int(duel.heroes[1].health)
	var charges: Array = duel.heroes[0].spell_uses.duplicate()
	_check(duel.use_ability(0, ability.key, body, 1), "Burnout uses the ordinary sacrifice action")
	_check(not duel.creatures.has(body) and duel.heroes[0].mana == 9 and duel.heroes[1].health == health - power and "STRT" in duel.heroes[0].grave, "Burnout pays 1 ether, loses the creature, and deals its power")
	var before := duel.snapshot()
	_check(not duel.use_ability(0, ability.key, second, 1) and duel.snapshot() == before, "Burnout cannot be reused before its normal reset")
	_check(duel.heroes[0].spell_uses == charges, "Burnout does not consume or restore spellbook charges")
	var resumed := _roundtrip(duel, "Used Burnout")
	before = resumed.snapshot()
	_check(not resumed.use_ability(0, ability.key, second, 1) and resumed.snapshot() == before, "Saving cannot reset a used Burnout")
	duel.end_phase()
	duel.end_phase()
	_check(duel.use_ability(0, ability.key, second, 1), "Burnout resets normally at the next own turn")
	duel = _with_power("Green", ["power_ether_feeding"])
	duel.heroes[0].mana = 10
	body = _summon(duel, 0, "TIWR")
	ability = _ability(duel, "SPLK")
	var channels := int(duel.heroes[0].channels)
	_check(duel.use_ability(0, ability.key, body), "Ether Feeding uses the original EL2 activation")
	_check(duel.heroes[0].mana == 8 and duel.heroes[0].channels == channels + 2 and not duel.creatures.has(body), "Ether Feeding exchanges 2 ether and a creature for exactly 2 channels")
	duel = _with_power("Green", ["power_martyrdom"])
	duel.heroes[0].mana = 10
	body = _summon(duel, 0, "TIWR")
	second = _summon(duel, 0, "TIWK")
	var old_power := int(duel.creatures[second].power)
	var old_health := int(duel.creatures[second].toughness)
	var gained_power := int(duel.creatures[body].power)
	var gained_health := int(duel.creatures[body].toughness)
	ability = _ability(duel, "CMBN")
	_check(duel.use_ability(0, ability.key, body, second), "Martyrdom uses the ordinary two-target sacrifice")
	_check(not duel.creatures.has(body) and duel.heroes[0].mana == 9 and duel.creatures[second].power == old_power + gained_power and duel.creatures[second].toughness == old_health + gained_health and duel.has_flag(second, "Trample"), "Martyrdom pays 1 ether and grants the sacrificed stats and Trample")
	_roundtrip(duel, "Temporary Martyrdom boost")
	duel.end_phase()
	_check(duel.creatures[second].power == old_power + gained_power, "Martyrdom remains through the enemy turn")
	duel.end_phase()
	_check(duel.creatures[second].power == old_power and duel.creatures[second].toughness == old_health and not duel.has_flag(second, "Trample"), "Martyrdom expires at the original controller-opponent turn boundary")

func _second_birth() -> void:
	var duel := _with_power("Black", ["power_second_birth"])
	var body := _summon(duel, 0, "MCWO")
	duel._kill(body)
	duel.heroes[0].mana = 10
	var charges: Array = duel.heroes[0].spell_uses.duplicate()
	var ability := _ability(duel, "SCBR")
	var cost := int(profile.table("CombatSpells").MCWO.Cost)
	_check(duel.use_ability(0, ability.key, 0, 0), "Second Birth uses an actual graveyard target")
	_check(duel.heroes[0].grave.is_empty() and duel.army(0).size() == 1 and duel.army(0)[0].card == "MCWO" and duel.heroes[0].mana == 10 - cost, "Second Birth removes one grave entry and pays its printed cost")
	_check(duel.heroes[0].spell_uses == charges, "Second Birth returns a creature without replenishing its finite page charges")
	_roundtrip(duel, "Used Second Birth")

func _aspects() -> void:
	var duel := _with_power("Red", ["power_transfer_aspects"])
	var pale := _summon(duel, 0, "OUD3")
	var bright := _summon(duel, 0, "STRT")
	duel.heroes[0].mana = 10
	var ability := _ability(duel, "OEXC")
	_check(duel.in_plane(pale) and not duel.in_plane(bright), "Transfer Aspects starts from a real Pale/bright pair")
	var before := duel.snapshot()
	_check(not duel.use_ability(0, ability.key, bright, pale) and duel.snapshot() == before, "Reversed aspect targets are rejected without paying")
	_check(duel.use_ability(0, ability.key, pale, bright), "Transfer Aspects accepts its ordinary two targets")
	_check(not duel.in_plane(pale) and duel.in_plane(bright) and duel.heroes[0].mana == 9, "Transfer Aspects pays 1 ether and exchanges both aspects")
	_roundtrip(duel, "Transfer Aspects with a bright creature in the Colourless Plane")
	duel = _with_power("Red", ["power_transfer_aspects"])
	pale = _summon(duel, 0, "OUD3")
	bright = _summon(duel, 0, "STRT")
	duel.heroes[0].mana = 10
	duel._enchant("PLSL", 1, 1, ELCatalog.rule(profile, "PLSL"))
	ability = _ability(duel, "OEXC")
	before = duel.snapshot()
	_check(not duel.use_ability(0, ability.key, pale, bright) and duel.snapshot() == before, "An original Planar Seal blocks the power without consuming its activation")

func _attraction_and_barrier() -> void:
	var duel := _with_power("Black", ["power_data_attraction", "power_energy_barrier"])
	var target := _summon(duel, 1, "STRT")
	var health := int(duel.heroes[0].health)
	var hand: int = duel.heroes[0].hand.size()
	_check(duel.cast_free(1, "ZAPP", [0], false), "Enemy casts a normal magical attack")
	_check(duel.heroes[0].health == health and duel.heroes[0].hand.size() == hand, "Barrier prevents 1 damage and the opponent's spell does not trigger friendly Data Attraction")
	_check(duel.cast_free(0, "TWEN", [target], false), "Owner casts a legal noncreature enchantment")
	_check(duel.heroes[0].health == health - 2 and duel.heroes[0].hand.size() == hand + 1, "Own noncreature spell draws one and deals 2 unavoidable damage through Energy Barrier")
	health = int(duel.heroes[0].health)
	hand = duel.heroes[0].hand.size()
	_check(duel.cast_free(0, "MCWO", [], false), "Owner casts an original summoning spell")
	_check(duel.heroes[0].health == health and duel.heroes[0].hand.size() == hand, "Creature casting does not trigger Data Attraction")
	_check(duel.cast_free(0, "TRLB", [0], false), "A normal second Data Attraction can be cast beside the opening copy")
	_check(duel.heroes[0].health == health - 2 and duel.heroes[0].hand.size() == hand + 1 and duel._enchantment_count(0, "TRLB") == 2, "A newly cast Data Attraction triggers only the already attached copy")
	health = int(duel.heroes[0].health)
	hand = duel.heroes[0].hand.size()
	_check(duel.cast_free(0, "TWEN", [target], false), "Noncreature cast with two ordinary copies succeeds")
	_check(duel.heroes[0].health == health - 4 and duel.heroes[0].hand.size() == hand + 2, "Two Data Attraction copies retain their ordinary double draw and double damage")
	_roundtrip(duel, "Stacked Data Attraction")
	duel = _with_power("Black", ["power_data_attraction", "power_second_birth"])
	var body := _summon(duel, 0, "MCWO")
	duel._kill(body)
	duel.heroes[0].mana = 10
	health = int(duel.heroes[0].health)
	hand = duel.heroes[0].hand.size()
	var ability := _ability(duel, "SCBR")
	_check(duel.use_ability(0, ability.key, 0, 0) and duel.heroes[0].health == health and duel.heroes[0].hand.size() == hand, "An activated power is not a spell cast and does not trigger Data Attraction")
	duel = _with_power("Red", ["power_energy_barrier"])
	health = int(duel.heroes[0].health)
	_check(duel._damage(0, 5) == 2 and duel.heroes[0].health == health - 2, "Energy Barrier reduces an ordinary magical hit by exactly 3")
	health = int(duel.heroes[0].health)
	_check(duel._damage(0, 5, true) == 5 and duel.heroes[0].health == health - 5, "Energy Barrier does not reduce combat damage")
	duel._dispel(0, int(duel.heroes[0].enchantments[0].id))
	health = int(duel.heroes[0].health)
	_check(duel._damage(0, 5) == 5 and duel.heroes[0].health == health - 5, "Dispelling Energy Barrier removes its protection")

func _concentration() -> void:
	for first in 2:
		var duel := _with_power("Blue", ["power_concentration"], first)
		var baseline := _duel("Blue", [], first)
		var turns := int(duel.heroes[0].turns)
		var steps := 0
		while int(duel.heroes[0].turns) < 6 and steps < 16:
			_check(duel.end_phase() and baseline.end_phase(), "Empty-board Concentration turn advances")
			steps += 1
			if int(duel.heroes[0].turns) == turns: continue
			turns = int(duel.heroes[0].turns)
			var extra := 1 if turns % 3 == 0 else 0
			_check(duel.heroes[0].hand.size() == baseline.heroes[0].hand.size() + extra, "Concentration draws exactly once every third own turn: first%d/turn%d" % [first, turns])
			_check(duel.heroes[0].spell_uses == baseline.heroes[0].spell_uses, "Concentration changes draws, not available spellbook charges")
		_check(turns == 6, "Concentration reaches its second extra-draw turn within the fixed test bound")
		_roundtrip(duel, "Concentration after six own turns")

func _native() -> void:
	if not ELCombatBrain.available:
		native_rows.append({"skipped": "Native extension is unavailable; original rules checks still ran."})
		return
	ELCombatSearch.smart_engine = true
	ELCombatSearch.smart_engine_info = "full"
	ELCombatSearch.smart_engine_budget = 2000
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_prove = 0
	ELCombatSearch.smart_engine_beyond = 0
	for row: Dictionary in Powers.catalog(profile):
		var faction: String = "Red" if row.faction == "Colorless" else row.faction
		var ids: Array[String] = [row.id]
		var duel := _with_power(faction, ids)
		duel.smart_sides.assign([0, 1])
		duel.heroes[0].mana = 8
		duel.heroes[0].channels = 8
		_summon(duel, 0, BODY[faction])
		_summon(duel, 1, "STRT")
		if row.card == "OEXC": _summon(duel, 0, "OUD3")
		if row.card == "SCBR": duel.heroes[0].grave.append("MCWO")
		var context := ELCombatSearch.plain_context(duel, duel.active_side())
		var packed := ELCombatBrain.ask(context, duel, 1, 256, true, 6)
		_check(not packed.get("raw", PackedInt32Array()).is_empty(), row.id + ": native evaluator accepts the real power position")
		var packet := ELCombatBrain.last_packed.to_int32_array()
		if not row.card.is_empty():
			var slot := ELCombatBrain.HEADER + ELCombatBrain.HERO_SCALARS + ELCombatBrain.CHARMS.find(row.card)
			_check(packet.size() > slot and packet[slot] == 1, row.id + ": native state contains exactly one active opening enchantment")
		else:
			var turns := ELCombatBrain.HEADER + 56
			_check(packet.size() > turns + 2 and (packet[turns] & (1 << 21)) == 0 and (packet[turns + 1] & (1 << 21)) != 0 and (packet[turns + 2] & (1 << 21)) == 0, "Native future-turn state places Concentration's next extra draw on own turn 3")
		var stats := {}
		var command := ELCombatSearch.think(duel, stats)
		var accepted := not command.is_empty() and ELCombatSearch.apply(duel, command)
		_check(accepted, row.id + ": bounded AI decision is accepted by the real duel: " + duel.error)
		if accepted: native_decisions += 1
		native_rows.append({"id": row.id, "engine": stats.get("engine", ""), "command": command,
			"accepted": accepted, "positions": stats.get("positions", 0), "packed": not packed.is_empty(),
			"crowding": ELCombatBrain.last_crowding})
