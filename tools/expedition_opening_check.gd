extends SceneTree
## Opt-in opening spell mechanics; no run saves or assigned combat winners.
## Printed cards and recovered EL2 starters, synthetic heroes/channel income.
## --baseline points to an untouched pre-hook state.gd: only its original
## start() is loaded as an ELDuel subclass, retaining the unchanged draw rules.
## godot --headless --path game --script ../tools/expedition_opening_check.gd -- \
##   --fixture=/path/to/fixture.json --baseline=/path/to/frozen_v13_state.gd \
##   --output=/tmp/expedition-opening.json

const DraftCheck := preload("arena_draft_check.gd")
const Powers := preload("res://src/expedition/attunements.gd")
const STARTERS := {"Red": "STR1", "Green": "STG1", "Blue": "STU1", "Black": "STB1"}
var fixture := {}
var profiles := {}
var checks := 0
var failures: Array[String] = []
var starts := 0
var legacy_cases := 0
var forced_cases := 0
var natural_cases := 0
var duplicate_hits := 0
var roundtrips := 0
var native_decisions := 0
var frozen: GDScript
var native_rows: Array[Dictionary] = []

func _arg(name: String, fallback := "") -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="): return value.trim_prefix("--" + name + "=")
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 30: printerr("FAIL: " + label)
	return ok

func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _run() -> void:
	var fixture_path := _arg("fixture")
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if loaded is not Dictionary or loaded.get("expedition_balance", {}).get("books") is not Dictionary:
		printerr("Supply the printed-card --fixture with recovered starter books.")
		quit(1)
		return
	fixture = loaded
	for edition: String in ["el1", "el2"]:
		var source := DraftCheck.synthetic_profile(fixture_path)
		source.id = edition
		source.root = "opening-check-" + edition
		source.tables.CombatSpells = Dictionary(fixture[edition].CombatSpells).duplicate(true)
		source.tables.CombatCreatures = Dictionary(fixture[edition].CombatCreatures).duplicate(true)
		source.tables.HeroesSpecs = {}
		for rank in 3:
			source.tables.HeroesSkills["CONC%d" % (rank + 1)] = {"Code": "CONC", "Level": rank + 1, "Name": "Concentration", "Duel": "True"}
		profiles[edition] = source
	var began := Time.get_ticks_msec()
	_load_frozen()
	_legacy()
	_openings()
	_rejections()
	_cast_and_discard()
	_scripts_and_powers()
	_native()
	var report := {"complete": true, "checks": checks, "failures": failures.size(), "failure_labels": failures,
		"duel_setups": starts, "legacy_cases": legacy_cases, "forced_cases": forced_cases,
		"natural_cases": natural_cases, "natural_other_duplicate_cases": duplicate_hits,
		"save_roundtrips": roundtrips, "native_available": ELCombatBrain.available,
		"native_decisions": native_decisions, "native": native_rows, "elapsed_ms": Time.get_ticks_msec() - began,
		"fixture": fixture_path, "baseline": _arg("baseline"),
		"baseline_sha256": FileAccess.get_sha256(_arg("baseline")) if not _arg("baseline").is_empty() else "",
		"complete_ai_battles": 0, "forced_winners": 0,
		"scope": "Mechanical opening/charge/save/script checks and bounded native decisions. Printed cards, synthetic heroes/income; EL1 books use compatible pages of recorded EL2 starters. Frozen original start() exercises the unchanged normal draw implementation. No full-run or combat balance claims."}
	var output := FileAccess.open(_arg("output", "user://expedition-opening-check.json"), FileAccess.WRITE)
	if _check(output != null, "Report file opens"):
		report.checks = checks
		output.store_string(JSON.stringify(report, "\t", true, true))
		output.close()
	print("OPENING SPELLS: %d checks, %d failures; %d frozen starts, %d forced fallbacks, %d natural hits, %d exact saves, %d native decisions" % [checks, failures.size(), legacy_cases, forced_cases, natural_cases, roundtrips, native_decisions])
	ELPracticeAI.finish()
	quit(0 if failures.is_empty() else 1)

func _load_frozen() -> void:
	var path := _arg("baseline")
	if path.is_empty():
		print("Frozen opening comparison omitted; supply --baseline for original-start parity.")
		return
	var source := FileAccess.get_file_as_string(path)
	var begin := source.find("\nfunc start(")
	var end := source.find("\nconst GLOBAL_BATTLE_EFFECTS", begin)
	if not _check(begin >= 0 and end > begin, "Frozen source contains the original start function"): return
	var body := source.substr(begin, end - begin)
	if not _check(not body.contains("opening_slots"), "Frozen original start predates the opt-in hook"): return
	frozen = GDScript.new()
	frozen.source_code = "extends ELDuel\n" + body
	if not _check(frozen.reload() == OK and frozen.can_instantiate(), "Original start compiles as a typed ELDuel subclass"): frozen = null

func _book(source: ELProfile, faction: String) -> Array[String]:
	var result: Array[String] = []
	for code: String in fixture.expedition_balance.books[STARTERS[faction]].cards:
		if source.table("CombatSpells").has(code) and not ELCatalog.rule(source, code).is_empty(): result.append(code)
	return result

func _options(source: ELProfile, faction: String, first := 0, interleave := 0, adventure := true) -> Dictionary:
	var players: Array[Dictionary] = []
	for race: String in [faction, "Red"]:
		var book := _book(source, race)
		var hero := {"faction": race, "hero": ELDuelPresets.DEFAULT_HEROES[race], "cards": book,
			"level": 5, "health": 80, "skills": {"PRVD": 0}, "specialization": "NONE"}
		if source.id == "el1":
			var uses: Array[int] = []
			for code: String in book: uses.append(-1 if source.table("CombatSpells")[code].get("Rarity") == "Cantrip" else 2)
			hero.rune_uses = uses
		players.append(hero)
	return {"adventure": adventure, "players": players, "arena": "Green.001",
		"first_side": first, "opening_interleave": interleave}

func _start(source: ELProfile, options: Dictionary, seed_value := 192837, old := false) -> ELDuel:
	var duel: ELDuel = frozen.new() if old and frozen != null else ELDuel.new()
	starts += 1
	_check(duel.start(source, seed_value, options), "Duel starts: %s/%s seed%d%s: %s" % [source.id, options.players[0].faction, seed_value, " original" if old else "", duel.error])
	return duel

func _legacy() -> void:
	if frozen == null: return
	for edition: String in profiles:
		var source: ELProfile = profiles[edition]
		for faction: String in STARTERS:
			for first in 2:
				for interleave in [-1, 0, 1]:
					for seed_value in [1, 91, 192837]:
						for adventure: bool in [false, true]:
							var options := _options(source, faction, first, interleave, adventure)
							if seed_value == 91: options.card_ids = true
							var current := _start(source, options, seed_value)
							var original := _start(source, options, seed_value, true)
							if current.heroes.size() != 2 or original.heroes.size() != 2: continue
							legacy_cases += 1
							_check(current.snapshot() == original.snapshot() and current.history == original.history, "%s/%s: absent option preserves complete original opening" % [edition, faction])
							for step in 2:
								_check(current.end_phase() == original.end_phase() and current.snapshot() == original.snapshot(), "%s: legacy next-turn draws and RNG remain exact" % edition)
		# Fixed-hand puzzles keep the original empty opening when not opted in.
		var fixed := _options(source, "Red")
		fixed.puzzle_fixed_hands = true
		var current := _start(source, fixed)
		var original := _start(source, fixed, 192837, true)
		_check(current.snapshot() == original.snapshot() and current.heroes[0].hand.is_empty(), edition + ": legacy fixed-hand opening remains unchanged")

func _openings() -> void:
	var source: ELProfile = profiles.el2
	for faction: String in STARTERS:
		for first in 2:
			for interleave in [-1, 0, 1]:
				for seed_value in [1, 11, 91, 192837]:
					var plain := _options(source, faction, first, interleave)
					var baseline := _start(source, plain, seed_value)
					var empty := plain.duplicate(true)
					empty.opening_slots = [-1, -1]
					var no_preference := _start(source, empty, seed_value)
					var stripped := no_preference.snapshot()
					stripped.setup.erase("opening_slots")
					_check(stripped == baseline.snapshot() and no_preference.history == baseline.history, faction + ": explicit empty selection changes only setup metadata")
					for slot in [0, 5, 15]:
						if slot >= plain.players[0].cards.size(): continue
						var options := plain.duplicate(true)
						options.opening_slots = [slot, -1]
						var before := options.duplicate(true)
						var duel := _start(source, options, seed_value)
						if duel.heroes.size() != 2: continue
						var hero: Dictionary = duel.heroes[0]
						var card: String = hero.deck[slot]
						_check(options == before, "Opening setup does not mutate caller-owned arrays")
						_check(hero.hand.size() == 5 and duel.heroes[1].hand.size() == 5 and card in hero.hand, faction + ": signature occupies one of five ordinary opening cards")
						_check(hero.spell_uses == baseline.heroes[0].spell_uses and ELSpellCharges.valid(source, hero), faction + ": normal finite charges and reservations remain valid")
						_check(hero.hand.slice(0, 4) == baseline.heroes[0].hand.slice(0, 4) and hero.hand_slots.slice(0, 4) == baseline.heroes[0].hand_slots.slice(0, 4), faction + ": first four natural draws are preserved")
						_check(duel.heroes[1] == baseline.heroes[1] and duel.rng_state == baseline.rng_state, faction + ": enemy opening and shared RNG remain paired")
						_check(hero.hand_slots.all(func(value: int) -> bool: return value >= 0) and hero.drawn.size() == 5, faction + ": every opening card uses a real slot and normal cycle entry")
						if card in baseline.heroes[0].hand.slice(0, 4):
							natural_cases += 1
							if slot not in baseline.heroes[0].hand_slots.slice(0, 4): duplicate_hits += 1
							stripped = duel.snapshot()
							stripped.setup.erase("opening_slots")
							_check(stripped == baseline.snapshot() and duel.history == baseline.history, faction + ": an already drawn copy leaves the entire natural opening unchanged")
						else:
							forced_cases += 1
							_check(hero.hand[4] == card and hero.hand_slots[4] == slot and hero.drawn.count(slot) == 1, faction + ": missing spell is the fifth draw from its nominated slot")
							_check(duel.hand_display(0)[0] == 4, faction + ": forced signature arrives at the ordinary leftmost position")
					if seed_value == 11:
						var options := plain.duplicate(true)
						options.opening_slots = [0, 7]
						var both := _start(source, options, seed_value)
						_check(both.heroes[0].deck[0] in both.heroes[0].hand and both.heroes[1].deck[7] in both.heroes[1].hand and both.rng_state == baseline.rng_state, "Each ordinary hero may nominate one slot without shifting RNG")
	_check(forced_cases > 0 and natural_cases > 0 and duplicate_hits > 0, "Matrix exercised missing spells, natural hits, and other-copy natural hits")

func _rejections() -> void:
	var source: ELProfile = profiles.el2
	var options := _options(source, "Red")
	var live := _start(source, options)
	var saved := live.snapshot()
	var bad: Array = [null, 0, "0,-1", {}, [], [0], [0, -1, -1], ["0", -1], [0.5, -1], [true, -1], [-2, -1], [999, -1], [-1, 999]]
	for value: Variant in bad:
		var invalid := options.duplicate(true)
		invalid.opening_slots = value
		_check(not live.start(source, 7, invalid) and live.snapshot() == saved, "Malformed opening option is rejected atomically: " + str(value))
	for key: String in ["adventure", "puzzle_fixed_hands"]:
		for value: Variant in ([false, "true", null] if key == "adventure" else [true, "false", null]):
			var invalid := options.duplicate(true)
			invalid.opening_slots = [0, -1]
			invalid[key] = value
			_check(not live.start(source, 7, invalid) and live.snapshot() == saved, key + ": unsupported opening mode preserves a live duel")
	var invalid := _options(profiles.el1, "Red")
	invalid.opening_slots = [0, -1]
	_check(not live.start(profiles.el1, 7, invalid) and live.snapshot() == saved and live.profile == source, "An explicit EL1 opening option is rejected without changing the live profile")
	for kind: Variant in ["monster", "missing", false]:
		invalid = options.duplicate(true)
		invalid.opening_slots = [0, -1]
		invalid.players[0].kind = kind
		_check(not live.start(source, 7, invalid) and live.snapshot() == saved, "Only a nominated ordinary hero is accepted")
	var zero := live.heroes.duplicate(true)
	zero[0].spell_uses[0] = 0
	invalid = options.duplicate(true)
	invalid.opening_slots = [0, -1]
	_check(not ELDuel.opening_slots_error(source, invalid, zero, true).is_empty(), "A starting signature must have an available charge")
	_check(ELDuel.opening_slots_error(source, invalid, zero).is_empty(), "An exhausted mid-duel signature slot remains valid to restore")
	var legal := _start(source, invalid)
	var raw := legal.snapshot()
	for value: Variant in bad:
		var forged := raw.duplicate(true)
		forged.setup.opening_slots = value
		_check(not live.restore(source, {"format": "etherlords-duel", "version": 1, "state": _json(forged)}) and live.snapshot() == saved, "Malformed saved opening instruction is rejected atomically")
	for key: String in ["adventure", "puzzle_fixed_hands"]:
		var forged := raw.duplicate(true)
		forged.setup[key] = false if key == "adventure" else true
		_check(not live.restore(source, {"format": "etherlords-duel", "version": 1, "state": _json(forged)}) and live.snapshot() == saved, "Saved opening cannot reinterpret its battle mode")

func _restore(duel: ELDuel, label: String) -> ELDuel:
	var saved := duel.snapshot()
	var resumed := ELDuel.new()
	roundtrips += 1
	if _check(resumed.restore(duel.profile, {"format": "etherlords-duel", "version": 1, "state": _json(saved)}), label + ": JSON checkpoint restores"):
		_check(resumed.snapshot() == saved, label + ": snapshot restores exactly without a new opening")
	return resumed

func _single_zap_options(first := 0) -> Dictionary:
	var options := _options(profiles.el2, "Red", first)
	var replacements: Array[String] = ["BROT", "CRBL", "STWO"]
	var retained := false
	for index in options.players[0].cards.size():
		if options.players[0].cards[index] != "ZAPP": continue
		if not retained: retained = true
		else: options.players[0].cards[index] = replacements.pop_front()
	options.players[0].skills = {}
	options.opening_slots = [options.players[0].cards.find("ZAPP"), -1]
	return options

func _cast_and_discard() -> void:
	var source: ELProfile = profiles.el2
	for first in 2:
		var options := _single_zap_options(first)
		var duel := _start(source, options)
		var resumed := _restore(duel, "Unplayed signature")
		if first == 1:
			_check(duel.end_phase() and resumed.end_phase() and duel.snapshot() == resumed.snapshot(), "Second mover receives the ordinary sixth card on its first own turn")
		var slot: int = options.opening_slots[0]
		var at: int = duel.heroes[0].hand.find("ZAPP")
		var before: Array = duel.heroes[0].spell_uses.duplicate()
		var mana := int(duel.heroes[0].mana)
		var life := int(duel.heroes[1].health)
		_check(at >= 0 and duel.heroes[0].hand_slots[at] == slot and duel.cast(at, 1), "Signature is cast through the ordinary hand action")
		_check(duel.heroes[0].mana == mana - 1 and duel.heroes[1].health == life - 1 and duel.heroes[0].spell_uses[slot] == 0, "Casting pays printed ether and exactly the originating page's last charge")
		before[slot] -= 1
		_check(duel.heroes[0].spell_uses == before, "Other pages gain no charges from signature casting")
		resumed = _restore(duel, "Cast and exhausted signature")
		for step in 4:
			_check(duel.end_phase() == resumed.end_phase() and duel.snapshot() == resumed.snapshot(), "Spent-signature continuation preserves exact draws and RNG")
		for draw in 24:
			duel._draw(0)
			resumed._draw(0)
		_check(duel.snapshot() == resumed.snapshot() and "ZAPP" not in duel.heroes[0].hand and duel.heroes[0].spell_uses[slot] == 0, "Later cycles never recreate the exhausted opening page")
		_restore(duel, "Exhausted signature after normal draw-cycle resets")
		duel = _start(source, options)
		at = duel.heroes[0].hand.find("ZAPP")
		var uses := int(duel.heroes[0].spell_uses[slot])
		duel._take_card(0, at)
		_check(duel.heroes[0].spell_uses[slot] == uses and ELSpellCharges.available(duel.heroes[0])[slot] == uses, "Ordinary discard releases the reservation without spending or creating a charge")
		resumed = _restore(duel, "Discarded signature")
		_check("ZAPP" not in resumed.heroes[0].hand, "Restore does not replace a discarded signature")
		_check(duel._draw(0) == resumed._draw(0) and duel.snapshot() == resumed.snapshot() and "ZAPP" not in duel.heroes[0].hand, "Next normal draw respects the current cycle instead of retriggering the opening")
	# The normal hand limit still discards the oldest/rightmost card.
	var options := _single_zap_options()
	var duel := _start(source, options)
	var oldest: String = duel.heroes[0].hand[duel.hand_display(0).back()]
	duel._give_card(0, "STRT", -1, true)
	duel.end_phase()
	_check(duel.heroes[0].hand.size() == 5 and duel.history.any(func(event: Dictionary) -> bool: return event.get("kind") == "discard" and event.get("card") == oldest and event.get("hand_limit", false)), "Signature adds no protection from ordinary automatic hand trimming")

func _scripts_and_powers() -> void:
	var source: ELProfile = profiles.el2
	var script_name := "opening_signature_probe"
	var code := "started = 0\ninit_count = 0\nfunction CHook_Init()\n init_count = init_count + 1\nend\nfunction Begin()\n if started == 0 then\n  started = 1\n  ExCastSpell(exMe, \"CRBL\")\n  ExCastSpell(exMe, \"STRT\")\n  ExAddSpellToHand(exMe, \"ZAPP\")\n end\nend\nfunction CHook_BeginMyTurn(turn)\n Begin()\nend\nfunction CHook_BeginEnemyTurn(turn)\n Begin()\nend\n"
	ELBattleScripts.fixtures[ELBattleScripts.chunk_path(script_name)] = code.to_utf8_buffer()
	for first in 2:
		var options := _single_zap_options(first)
		options.scripts = [{"name": script_name, "side": 1}]
		var ordinary := options.duplicate(true)
		ordinary.erase("opening_slots")
		var baseline := _start(source, ordinary)
		var duel := _start(source, options)
		_check(duel.scripts != null and duel.scripts.notes.is_empty() and duel.scripts.states.size() == 1, "Original startup scripts still load and execute")
		_check(duel.scripts.snapshot() == baseline.scripts.snapshot() and duel.heroes[1] == baseline.heroes[1] and duel.creatures == baseline.creatures, "Signature preserves script globals, enemy opening, summons and wards")
		_check(duel.army(1).size() == 1 and duel.has_flag(duel.army(1)[0].id, "FS") and duel.heroes[1].hand.size() == 6, "A scripted summon, aura and extra card retain their original effects")
		var resumed := _restore(duel, "Signature with startup script")
		for step in 2:
			_check(duel.end_phase() == resumed.end_phase() and duel.snapshot() == resumed.snapshot(), "Scripted continuation does not rerun initialization or opening selection")
		duel.scripts.close()
		resumed.scripts.close()
		baseline.scripts.close()
	ELBattleScripts.fixtures.erase(ELBattleScripts.chunk_path(script_name))
	for first in 2:
		var options := _options(source, "Black", first)
		options.opening_slots = [0, -1]
		var duel := _start(source, options)
		var before := duel.heroes.duplicate(true)
		var rng := duel.rng_state
		_check(Powers.apply_opening(duel, ["power_data_attraction", "power_energy_barrier"]), "Guardian enchantments attach after a signature opening")
		for side in 2:
			_check(duel.heroes[side].hand == before[side].hand and duel.heroes[side].spell_uses == before[side].spell_uses and duel.heroes[side].health == before[side].health, "Signature plus powers causes no setup cast, draw trigger, damage or new charge")
		_check(duel.rng_state == rng, "Opening enchantments leave signature draw RNG unchanged")
		_restore(duel, "Signature with Data Attraction and Energy Barrier")
		options = _options(source, "Blue", first)
		options.opening_slots = [0, -1]
		options.players[0] = Powers.prepare_hero(options.players[0], ["power_concentration"])
		duel = _start(source, options)
		_check(Powers.apply_opening(duel, ["power_concentration"]) and duel.heroes[0].hand.size() == 5, "Concentration adds no extra opening card")
		while int(duel.heroes[0].turns) < 3: duel.end_phase()
		_check(duel.history.filter(func(event: Dictionary) -> bool: return event.get("kind") == "skill" and event.get("skill") == "CONC" and event.get("side") == 0).size() == 1, "Concentration still draws on its third own turn")
		_restore(duel, "Signature after Concentration extra draw")

func _native() -> void:
	if not ELCombatBrain.available: return
	var source: ELProfile = profiles.el2
	ELCombatSearch.smart_engine = true
	ELCombatSearch.smart_engine_info = "full"
	ELCombatSearch.smart_engine_budget = 2000
	ELCombatSearch.smart_engine_ms = 0
	ELCombatSearch.smart_engine_prove = 0
	ELCombatSearch.smart_engine_beyond = 0
	for faction: String in STARTERS:
		for first in 2:
			var options := _options(source, faction, first)
			options.opening_slots = [0, -1]
			var duel := _start(source, options)
			duel.smart_sides.assign([0, 1])
			if first == 1: duel.end_phase()
			var before := duel.snapshot()
			var context := ELCombatSearch.plain_context(duel, 0)
			var packed := ELCombatBrain.ask(context, duel, 1, 256, true, 6)
			var packet := ELCombatBrain.last_packed.to_int32_array()
			_check(not packed.get("raw", PackedInt32Array()).is_empty() and packet.size() > ELCombatBrain.HEADER + 38 and packet[ELCombatBrain.HEADER + 38] == 0, "Native state treats the signature as charged book content, not a generated card")
			_check(duel.snapshot() == before, "Native inspection does not mutate signature reservation or draw state")
			var stats := {}
			var command := ELCombatSearch.think(duel, stats)
			var accepted := not command.is_empty() and ELCombatSearch.apply(duel, command)
			_check(accepted and ELSpellCharges.valid(source, duel.heroes[0]), faction + ": native decision remains legal with a reserved opening page")
			if accepted: native_decisions += 1
			native_rows.append({"faction": faction, "first_side": first, "command": command,
				"engine": stats.get("engine", ""), "accepted": accepted, "crowding": ELCombatBrain.last_crowding})
