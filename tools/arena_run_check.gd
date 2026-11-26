extends SceneTree
## Arena lifecycle and save-boundary checks. Default input is explicitly
## synthetic; --fixture <catalog-fixture.json> uses the catalog-derived test
## tables and --el2 <installation> exercises the installed game tables.
## No real Arena checkpoint is read, replaced or deleted.
##
## godot --headless --path game --script ../tools/arena_run_check.gd

const DraftCheck := preload("arena_draft_check.gd")
const FOLDER := "user://arena_run_check"
const TEST_SAVE := FOLDER + "/run.json"
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size(): return args[i + 1]
		if args[i].begins_with(name + "="): return args[i].trim_prefix(name + "=")
	return ""

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	DirAccess.remove_absolute(TEST_SAVE)
	var source: ELProfile
	var installation := _argument("--el2")
	if installation.is_empty():
		source = DraftCheck.synthetic_profile(_argument("--fixture"))
		print("INPUT: synthetic profile (not an installed-game balance test)")
	else:
		source = ELProfile.new()
		if not source.mount("el2", installation):
			check(false, "Mount Etherlords II: " + source.error)
			_finish()
			return
		print("INPUT: mounted Etherlords II")
	if source == null:
		check(false, "The test profile is available")
		_finish()
		return
	_persistence(source)
	_lifecycle(source)
	_limits(source)
	_retirement(source)
	_pool_modes(source)
	_hero_levels(source)
	_hero_loadouts(source)
	_finish()


func _drafted(source: ELProfile, seed: int, version := ELArenaRun.HERO_VERSION) -> ELArenaRun:
	var run := ELArenaRun.new()
	run.auto_save = false
	if not run.create(source, seed): return null
	run.hero_version = version
	if not _draft(run): return null
	return run

## Each offered hero and opponent has its own figure; after the hero the
## player picks a specialization, then an artifact; opponents get seeded
## ones. Runs saved before that keep the plain heroes.def heroes.
func _hero_loadouts(source: ELProfile) -> void:
	var installed := not ELArenaRules.hero_templates(source, "Red").is_empty()
	var seen := {}
	for seed: int in [11, 12, 13, 14, 15, 16]:
		var run := ELArenaRun.new()
		run.auto_save = false
		if not run.create(source, seed): continue
		for magic: String in run.hero_choices:
			var loadout := run.hero_loadout(magic)
			check(loadout == run.hero_loadout(magic) and loadout.specialization == "NONE" and loadout.artifacts.is_empty(), "An offered hero's figure is fixed by the seed and has no choices yet")
			if not installed: continue
			check(String(loadout.template) in ELArenaRules.hero_templates(source, magic), "%s: the offered figure is one of the race's duel heroes" % magic)
			seen[loadout.template] = true
	if installed: check(seen.size() >= 8, "Different runs offer different heroes (%d figures in six runs)" % seen.size())
	var picking := ELArenaRun.new()
	picking.auto_save = false
	picking.create(source, 4243)
	picking.choose_hero(picking.hero_choices[1])
	if installed:
		var magic := picking.faction
		var specs := picking.spec_offer()
		check(picking.phase == "spec" and specs.size() == ELArenaRun.LOADOUT_OFFER and specs.all(func(code: String) -> bool: return ELDuelCosts.spec_allowed(source, code, magic) and code != "NONE"), "The hero is followed by three specializations of its race")
		check(not picking.choose_loadout(3) and picking.phase == "spec", "Only an offered specialization can be taken")
		var resumed := ELArenaRun.new()
		check(resumed.restore_snapshot(source, JSON.parse_string(JSON.stringify(picking.snapshot()))) and resumed.phase == "spec" and resumed.spec_offer() == specs, "The specialization step resumes with the same offer")
		check(picking.choose_loadout(2) and picking.specialization == specs[2] and picking.phase == "artifact", "The chosen specialization is kept and the artifact step follows")
		var items := picking.artifact_offer()
		check(items.size() == ELArenaRun.LOADOUT_OFFER and items.all(func(code: String) -> bool: return code in ELDuelCosts.duel_artifacts(source)), "Three different duel artifacts are offered")
		var forged: Dictionary = JSON.parse_string(JSON.stringify(picking.snapshot()))
		forged.artifacts = [items[0]]
		check(not ELArenaRun.new().restore_snapshot(source, forged), "An artifact cannot be saved before its step")
		check(picking.choose_loadout(1) and picking.artifacts == [items[1]] and picking.phase == "skill", "The chosen artifact is kept and the skill step follows")
		var skills := picking.skill_offer()
		var codes := skills.map(func(entry: Dictionary) -> String: return String(entry.code))
		check(skills.size() == 3 and codes.all(func(code: String) -> bool: return codes.count(code) == 1 and code in ELArenaRules.skills(source) and code != "PRVD") \
			and skills.all(func(entry: Dictionary) -> bool: return int(entry.rank) >= 0 and int(entry.rank) <= ELHeroSkills.MAX_RANK), "Three different hero skills are offered, each at a rank")
		var ranks := {}
		for seed: int in range(300, 340):
			var sample := ELArenaRun.new()
			sample.auto_save = false
			sample.create(source, seed)
			sample.choose_hero(sample.hero_choices[0])
			while sample.phase in ["spec", "artifact"]: sample.choose_loadout(0)
			for entry: Dictionary in sample.skill_offer(): ranks[int(entry.rank)] = true
		check(ranks.size() == 3, "Offered skills come at every rank across runs")
		var resumed_skill := ELArenaRun.new()
		check(resumed_skill.restore_snapshot(source, JSON.parse_string(JSON.stringify(picking.snapshot()))) and resumed_skill.skill_offer() == skills, "The skill step resumes with the same skills and ranks")
		forged = JSON.parse_string(JSON.stringify(picking.snapshot()))
		forged.skill = {String(skills[0].code): (int(skills[0].rank) + 1) % 3}
		check(not ELArenaRun.new().restore_snapshot(source, forged), "A skill cannot be saved before its step")
		check(picking.choose_loadout(0) and picking.skill == {String(skills[0].code): int(skills[0].rank)} and picking.phase == "draft" and picking.draft.cards.is_empty(), "The chosen skill is kept at its rank and the card draft begins")
		forged = JSON.parse_string(JSON.stringify(picking.snapshot()))
		forged.skill = {String(skills[0].code): (int(skills[0].rank) + 1) % 3}
		check(not ELArenaRun.new().restore_snapshot(source, forged), "A skill at a rank that was not offered is refused")
		forged = JSON.parse_string(JSON.stringify(picking.snapshot()))
		forged.specialization = "NONE" if picking.specialization != "NONE" else specs[0]
		check(not ELArenaRun.new().restore_snapshot(source, forged), "A draft without its chosen specialization is refused")
		var other: Array = ELArenaRules.specializations(source, magic).filter(func(code: String) -> bool: return code not in specs)
		if not other.is_empty():
			forged.specialization = other[0]
			check(not ELArenaRun.new().restore_snapshot(source, forged), "A specialization that was not offered is refused")
	var run := _drafted(source, 4242)
	if run == null:
		check(false, "A loadout run drafts")
		return
	var mine := run.hero_loadout(run.faction)
	if installed:
		check(mine.specialization == run.spec_offer()[0] and mine.artifacts == [run.artifact_offer()[0]], "The player's hero carries the picked specialization and artifact")
		check(mine.skills == {String(run.skill_offer()[0].code): int(run.skill_offer()[0].rank)}, "The player's hero carries the picked skill")
	for index in 4:
		var duel := run.build_battle()
		if duel == null:
			check(false, "Loadout battle %d starts: %s" % [index, run.error])
			return
		var theirs: Dictionary = run.opponent.get("loadout", {})
		check(duel.heroes[0].spec == mine.specialization and duel.heroes[0].artifacts.size() == mine.artifacts.size(), "Battle %d: the player's hero has its specialization and artifact" % index)
		check(duel.heroes[1].spec == theirs.get("specialization") and duel.heroes[1].artifacts.size() == Array(theirs.get("artifacts", [])).size(), "Battle %d: the opponent has its own specialization and artifact" % index)
		check(duel.heroes[0].skills == ELArenaRules.hero_skills(mine) and duel.heroes[1].skills == ELArenaRules.hero_skills(theirs), "Battle %d: both heroes fight with Providence and their skill (%s, %s)" % [index, duel.heroes[0].skills, duel.heroes[1].skills])
		if installed: check(Dictionary(theirs.get("skills", {})).size() == 1, "Battle %d: the opponent has a seeded skill" % index)
		for side in 2:
			var learned: Dictionary = duel.heroes[side].skills
			if learned.has("HEAL"):
				var plain := ELDuelPresets.health(source, {"faction": duel.heroes[side].faction, "level": duel.heroes[side].level, "skills": {}}, String(duel.setup.players[side].hero))
				check(int(duel.heroes[side].health) > plain, "Battle %d: Vitality raises the hero's life in battle" % index)
		if installed:
			var heroes: Array = duel.setup.players.map(func(player: Dictionary) -> String: return String(player.hero))
			check(heroes[0] == mine.template and heroes[1] == theirs.template and heroes[0] != heroes[1], "Battle %d: the two sides are different heroes (%s, %s)" % [index, heroes[0], heroes[1]])
		var saved := run.snapshot()
		var restored := ELArenaRun.new()
		check(restored.restore_snapshot(source, JSON.parse_string(JSON.stringify(saved))), "Battle %d: the loadout battle resumes" % index)
		if index == 0:
			var forged: Dictionary = JSON.parse_string(JSON.stringify(saved))
			forged.opponent.loadout.specialization = "RVVE" if theirs.get("specialization") != "RVVE" else "GBLP"
			check(not ELArenaRun.new().restore_snapshot(source, forged), "A changed opponent specialization is refused")
		_end(duel, 0)
		if not run.resolve_battle(duel) or not run.continue_run():
			check(false, "Loadout battle %d resolves: %s" % [index, run.error])
			return
	var legacy := _drafted(source, 4242, 0)
	if legacy == null:
		check(false, "A legacy run drafts")
		return
	var duel := legacy.build_battle()
	check(duel != null and duel.heroes.all(func(hero: Dictionary) -> bool: return hero.spec == "NONE" and hero.artifacts.is_empty()), "A legacy run keeps heroes without specialization or artifacts")
	if duel != null:
		check(duel.setup.players.all(func(player: Dictionary) -> bool: return player.hero == ELDuelPresets.default_template(source, String(player.faction))), "A legacy run keeps the heroes.def figures")
	var old: Dictionary = JSON.parse_string(JSON.stringify(legacy.snapshot()))
	old.erase("hero_version")
	old.erase("skill")
	var resumed := ELArenaRun.new()
	check(resumed.restore_snapshot(source, old) and resumed.hero_version == 0 and resumed.phase == "battle", "A battle saved before loadouts resumes unchanged")
	# Runs saved with a specialization and artifact but before hero skills.
	var earlier := _drafted(source, 4244, 1)
	if earlier == null:
		check(false, "A run without hero skills drafts")
		return
	var earlier_duel := earlier.build_battle()
	check(earlier_duel != null and earlier_duel.heroes.all(func(hero: Dictionary) -> bool: return hero.skills == ELArenaRules.SKILLS), "A run from before hero skills fights with Providence only")
	check(earlier.skill.is_empty() and not earlier.opponent.get("loadout", {}).has("skills"), "A run from before hero skills gives neither side a skill")
	var saved_earlier: Dictionary = JSON.parse_string(JSON.stringify(earlier.snapshot()))
	saved_earlier.erase("skill")
	var resumed_earlier := ELArenaRun.new()
	check(resumed_earlier.restore_snapshot(source, saved_earlier) and resumed_earlier.hero_version == 1 and resumed_earlier.phase == "battle", "A battle saved before hero skills resumes unchanged")
	if installed:
		var midway := ELArenaRun.new()
		midway.auto_save = false
		midway.create(source, 4245)
		midway.hero_version = 1
		midway.choose_hero(midway.hero_choices[0])
		while midway.phase in ["spec", "artifact"]: midway.choose_loadout(0)
		var saved_midway: Dictionary = JSON.parse_string(JSON.stringify(midway.snapshot()))
		saved_midway.erase("skill")
		var resumed_midway := ELArenaRun.new()
		check(midway.phase == "draft" and resumed_midway.restore_snapshot(source, saved_midway) and resumed_midway.phase == "draft" and resumed_midway.skill_offer().is_empty(), "A draft saved before hero skills resumes without a skill step")


func _pool_modes(source: ELProfile) -> void:
	for rules: int in [ELArenaRules.LEGACY_RULES, ELArenaRules.FACTION_RULES, ELArenaRules.OPEN_RULES]:
		var run := ELArenaRun.new()
		run.auto_save = false
		if not run.create(source, 20261118, rules) or not run.choose_hero(run.hero_choices[0]):
			check(false, "Rules %d can begin a draft" % rules)
			continue
		_loadout(run)
		while run.phase == "draft":
			if not run.pick(ELArenaDraftBot.choose(run.draft)):
				check(false, run.error)
				break
		var duel := run.build_battle()
		check(duel != null, "Rules %d starts a real duel" % rules)
		if duel == null: continue
		for hero: Dictionary in duel.heroes:
			var off_faction: bool = hero.deck.any(func(card: String) -> bool: return source.table("CombatSpells")[card].Color not in [hero.faction, "White"])
			check(off_faction == (rules == ELArenaRules.OPEN_RULES), "Rules %d applies to %s deck in combat" % [rules, hero.faction])
			if rules == ELArenaRules.FACTION_RULES:
				check(hero.deck.all(func(card: String) -> bool: return source.table("CombatSpells")[card].Color == hero.faction), "Faction-only excludes neutral cards for %s" % hero.faction)
		var restored := ELArenaRun.new()
		var restored_ok := restored.restore_snapshot(source, JSON.parse_string(JSON.stringify(run.snapshot())))
		check(restored_ok and restored.rules_version == rules and restored.draft.cards == run.draft.cards, "Rules %d survives saving and resuming" % rules)

func _hero_levels(source: ELProfile) -> void:
	var run := ELArenaRun.new()
	run.auto_save = false
	check(not run.create(source, 212, ELArenaRules.OPEN_RULES, Vector2i(0, 14)), "Out-of-range hero levels are rejected")
	if not run.create(source, 212, ELArenaRules.OPEN_RULES, Vector2i(1, 13)):
		check(false, run.error)
		return
	run.choose_hero(run.hero_choices[0])
	_loadout(run)
	while run.phase == "draft":
		if not run.pick(ELArenaDraftBot.choose(run.draft)):
			check(false, run.error)
			return
	var battle := run.build_battle()
	check(battle != null and battle.heroes[0].level == 1 and battle.heroes[1].level == 13, "The actual duel uses the chosen levels for each hero")
	var restored := ELArenaRun.new()
	var snapshot := run.snapshot()
	check(restored.restore_snapshot(source, JSON.parse_string(JSON.stringify(snapshot))) and restored.hero_levels == Vector2i(1, 13), "Both levels survive restoring a mid-battle save")
	snapshot.hero_levels = [1.5, 13]
	check(not restored.restore_snapshot(source, snapshot) and restored.hero_levels == Vector2i(1, 13), "A fractional saved level is refused without replacing the run")
	run.create(source, 212)
	snapshot = run.snapshot()
	snapshot.erase("hero_levels")
	check(restored.restore_snapshot(source, snapshot) and restored.hero_levels == Vector2i(5, 5), "Earlier checkpoints resume at the original level 5")

func _finish() -> void:
	check(checks >= 50, "The full lifecycle suite executed")
	ELSafeFile.test_write_limit = -1
	DirAccess.remove_absolute(TEST_SAVE)
	for name: String in DirAccess.get_files_at(FOLDER):
		if name.begins_with("run.json.") and name.ends_with(".tmp"): DirAccess.remove_absolute(FOLDER.path_join(name))
	DirAccess.remove_absolute(FOLDER)
	print("ARENA RUN: %d checks, %d failure(s)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new(source: ELProfile, seed: int, disk := false) -> ELArenaRun:
	var run := ELArenaRun.new()
	run.save_path = TEST_SAVE
	run.auto_save = disk
	if not run.create(source, seed):
		check(false, "Create run: " + run.error)
		return null
	return run

func _draft(run: ELArenaRun, hero_index := 0) -> bool:
	if run == null: return false
	if run.phase == "hero" and not run.choose_hero(run.hero_choices[hero_index]):
		check(false, "Choose hero: " + run.error)
		return false
	_loadout(run)
	while run.phase == "draft":
		if not run.pick(ELArenaDraftBot.choose(run.draft)):
			check(false, "Complete draft: " + run.error)
			return false
	return run.phase == "ready"

## Takes the first specialization and artifact offers, when there are any.
func _loadout(run: ELArenaRun, choice := 0) -> void:
	while run.phase in ["spec", "artifact", "skill"]:
		if not run.choose_loadout(choice):
			check(false, "Choose the hero's %s: %s" % [run.phase, run.error])
			return

func _roundtrip(run: ELArenaRun) -> ELArenaRun:
	var restored := ELArenaRun.new()
	restored.auto_save = false
	restored.save_path = TEST_SAVE
	var raw: Variant = JSON.parse_string(JSON.stringify(run.snapshot(), "", true, true))
	if not restored.restore_snapshot(run.profile, raw):
		check(false, "Restore " + run.phase + " checkpoint: " + restored.error)
		return null
	return restored

func _persistence(source: ELProfile) -> void:
	var run := _new(source, 32019, true)
	if run == null: return
	check(not FileAccess.file_exists(TEST_SAVE), "Creation leaves the previous save untouched until persist")
	check(run.hero_choices.size() == 3 and run.hero_choices[0] != run.hero_choices[1] and run.hero_choices[1] != run.hero_choices[2], "Three distinct faction choices")
	check(run.persist(), "Initial Arena checkpoint is written")
	var before := run.snapshot()
	var bytes := FileAccess.get_file_as_bytes(TEST_SAVE)
	check(not run.choose_hero("missing") and run.snapshot() == before, "An unavailable hero cannot change the run")
	ELSafeFile.test_write_limit = 1
	check(not run.choose_hero(run.hero_choices[0]), "A failed hero checkpoint is reported")
	ELSafeFile.test_write_limit = -1
	check(run.snapshot() == before and FileAccess.get_file_as_bytes(TEST_SAVE) == bytes, "A failed hero checkpoint preserves memory and disk")
	check(run.choose_hero(run.hero_choices[0]), "A hero choice succeeds after storage recovers")
	_loadout(run)
	for i in 6:
		if not run.pick(ELArenaDraftBot.choose(run.draft)):
			check(false, "Six initial draft picks: " + run.error)
			return
	var restored := ELArenaRun.new()
	restored.save_path = TEST_SAVE
	check(restored.restore(source), "An unfinished draft resumes from its own save")
	check(restored.snapshot() == run.snapshot(), "Draft resume preserves every offer and pick")
	before = run.snapshot()
	bytes = FileAccess.get_file_as_bytes(TEST_SAVE)
	ELSafeFile.test_write_limit = 1
	check(not run.pick(0), "A failed pick checkpoint is reported")
	ELSafeFile.test_write_limit = -1
	check(run.snapshot() == before and FileAccess.get_file_as_bytes(TEST_SAVE) == bytes, "A failed pick does not consume or reroll the offer")
	var damaged := before.duplicate(true)
	damaged.draft.offer[0] = "forged"
	check(not restored.restore_snapshot(source, damaged) and restored.snapshot() == before, "A forged draft offer is refused without damaging the loaded run")
	damaged = before.duplicate(true)
	damaged.version = 999
	check(not restored.restore_snapshot(source, damaged), "Unknown save versions are refused")
	damaged = before.duplicate(true)
	damaged.pool_signatures.Red = "changed"
	check(not restored.restore_snapshot(source, damaged), "Changed card pool signatures cannot resume silently")
	damaged = before.duplicate(true)
	damaged.matches = [null]
	check(not restored.restore_snapshot(source, damaged), "Malformed match rows are refused without a typed-array error")
	if not _draft(run): return
	check(run.draft.cards.size() == 16 and run.draft.history.size() == 16, "The run reaches the lobby only after sixteen recorded picks")
	before = run.snapshot()
	bytes = FileAccess.get_file_as_bytes(TEST_SAVE)
	ELSafeFile.test_write_limit = 1
	check(run.build_battle() == null, "An opponent is not launched when its checkpoint fails")
	ELSafeFile.test_write_limit = -1
	check(run.snapshot() == before and FileAccess.get_file_as_bytes(TEST_SAVE) == bytes, "A failed launch preserves the lobby and previous checkpoint")
	var battle := run.build_battle()
	check(battle != null, "A battle launches after storage recovers: " + run.error)
	if battle == null: return
	var checkpoint := battle.snapshot()
	check(run.save_battle(battle), "An unchanged battle checkpoint is safe")
	check(restored.restore(source), "A battle checkpoint loads from disk")
	var resumed := restored.build_battle()
	check(resumed != null and resumed.snapshot() == checkpoint, "Battle resume preserves the complete opening state and RNG")
	before = run.snapshot()
	bytes = FileAccess.get_file_as_bytes(TEST_SAVE)
	battle.end_phase()
	ELSafeFile.test_write_limit = 1
	check(not run.save_battle(battle), "A failed battle autosave is reported")
	ELSafeFile.test_write_limit = -1
	check(run.snapshot() == before and FileAccess.get_file_as_bytes(TEST_SAVE) == bytes, "A failed battle autosave keeps the last committed state")
	check(run.save_battle(battle), "Retrying the unchanged live battle commits it")
	check(restored.restore(source), "The advanced battle resumes from disk")
	resumed = restored.build_battle()
	check(resumed != null and resumed.snapshot() == battle.snapshot(), "Resume after actions preserves hands, phase and RNG")
	_end(battle, 0)
	before = run.snapshot()
	bytes = FileAccess.get_file_as_bytes(TEST_SAVE)
	ELSafeFile.test_write_limit = 1
	check(not run.resolve_battle(battle), "A failed result checkpoint is reported")
	ELSafeFile.test_write_limit = -1
	check(run.snapshot() == before and FileAccess.get_file_as_bytes(TEST_SAVE) == bytes, "A failed result does not increment the score")
	check(run.resolve_battle(battle) and run.wins == 1 and run.phase == "result", "Retrying the result commits exactly one win")
	bytes = FileAccess.get_file_as_bytes(TEST_SAVE)
	check(run.resolve_battle(battle) and run.wins == 1 and run.matches.size() == 1, "A repeated finished-battle callback never scores twice")
	check(FileAccess.get_file_as_bytes(TEST_SAVE) == bytes, "Idempotent result acknowledgement does not rewrite the save")
	check(restored.restore(source) and restored.wins == 1 and restored.phase == "result", "A committed result resumes without replaying or rescoring it")
	damaged = run.snapshot()
	damaged.wins = 2
	check(not restored.restore_snapshot(source, damaged), "A score inconsistent with the match ledger is refused")
	check(run.continue_run() and run.phase == "ready" and run.opponent.is_empty(), "Continue returns to the lobby with the drafted deck unchanged")
	check(DirAccess.get_files_at(FOLDER).size() == 1, "Failed saves leave no temporary files behind")
	DirAccess.remove_absolute(TEST_SAVE)

func _lifecycle(source: ELProfile) -> void:
	var run := _new(source, 77123)
	var other := _new(source, 77123)
	if not _draft(run) or not _draft(other, 1): return
	var battle := run.build_battle()
	var other_battle := other.build_battle()
	check(battle != null and other_battle != null, "Ordinary duel battles accept both complete drafts")
	if battle == null or other_battle == null: return
	check(run.run_id != other.run_id, "Repeating a seed creates a distinct run identity")
	check(run.opponent.draft == other.opponent.draft and run.opponent.battle_seed == other.opponent.battle_seed,
		"Opponent drafting and battle seed do not depend on the player's chosen faction or cards")
	check(run.opponent.cards.size() == 16 and run.opponent.draft.history.size() == 16, "The opponent has sixteen real three-card picks")
	check(battle.heroes[0].deck == run.draft.cards and battle.heroes[1].deck == run.opponent.cards, "The duel receives the exact two drafted spellbooks")
	check(not battle.setup.get("adventure", false) and battle.setup.get("arena_run_id") == run.run_id, "Arena uses normal duel rules and identifies the run")
	check(battle.heroes[0].level == battle.heroes[1].level and battle.heroes.all(func(hero: Dictionary) -> bool: return hero.skills.get("PRVD") == 0 and hero.skills.size() <= ELArenaRules.SKILLS.size() + 1),
		"Both sides use the same hero level, Providence and at most one picked skill")
	var before := run.snapshot()
	check(not run.save_battle(other_battle) and run.snapshot() == before, "A different run's battle cannot replace the checkpoint")
	var repeated := run.build_battle()
	check(repeated != null and repeated.snapshot() == battle.snapshot(), "Opening the same active encounter cannot redraw it")
	var loaded := _roundtrip(run)
	if loaded != null:
		var resumed := loaded.build_battle()
		check(resumed != null and resumed.snapshot() == battle.snapshot(), "An in-memory JSON roundtrip preserves the active battle")
	_end(battle, -1)
	check(run.resolve_battle(battle) and run.draws == 1 and run.wins == 0 and run.losses == 0, "A draw consumes neither a win nor a loss")
	check(run.continue_run(), "A drawn run continues")
	var next := run.build_battle()
	check(next != null and run.current_match_id != before.current_match_id, "The next encounter has a new persistent identity")
	if next == null: return
	_end(next, 1)
	check(run.resolve_battle(next) and run.losses == 1 and run.draws == 1, "A defeat adds exactly one loss after a draw")
	loaded = _roundtrip(run)
	check(loaded != null and loaded.matches.size() == 2, "Match transcripts and outcome history survive a roundtrip")

func _end(duel: ELDuel, winner: int) -> void:
	if winner == -1:
		duel.heroes[0].health = 0
		duel.heroes[1].health = 0
	else:
		duel.heroes[1 - winner].health = 0
	duel._check_winner()

func _limits(source: ELProfile) -> void:
	for winner in [0, 1]:
		var run := _new(source, 1400 + winner)
		if not _draft(run): continue
		var limit := ELArenaRules.WIN_LIMIT if winner == 0 else ELArenaRules.LOSS_LIMIT
		for i in limit:
			var battle := run.build_battle()
			if battle == null:
				check(false, "Run limit battle starts: " + run.error)
				break
			_end(battle, winner)
			if not run.resolve_battle(battle):
				check(false, "Run limit battle resolves: " + run.error)
				break
			if i + 1 < limit and not run.continue_run(): break
		var expected := "victory" if winner == 0 else "defeat"
		check(run.finished() and run.outcome == expected and run.matches.size() == limit,
			"The run ends at %d %s" % [limit, "wins" if winner == 0 else "losses"])
		check(run.build_battle() == null and not run.continue_run(), "A finished " + expected + " cannot start another scored encounter")
		var loaded := _roundtrip(run)
		check(loaded != null and loaded.outcome == expected, "The final " + expected + " summary restores")

func _retirement(source: ELProfile) -> void:
	for stage: String in ["hero", "spec", "artifact", "draft", "ready", "battle", "result"]:
		var run := _new(source, 90817)
		if run == null: return
		if stage in ["spec", "artifact"]:
			if not run.choose_hero(run.hero_choices[0]): continue
			if stage == "artifact" and run.phase == "spec": run.choose_loadout(0)
			if run.phase != stage: continue
		elif stage == "draft":
			if not run.choose_hero(run.hero_choices[0]): continue
			_loadout(run)
			if not run.pick(0): continue
		elif stage in ["ready", "battle", "result"]:
			if not _draft(run): continue
		if stage in ["battle", "result"]:
			var battle := run.build_battle()
			if battle == null:
				check(false, "Retirement battle starts: " + run.error)
				continue
			if stage == "result":
				_end(battle, 0)
				if not run.resolve_battle(battle): continue
		var score := [run.wins, run.losses, run.draws]
		check(run.retire() and run.finished() and run.outcome == "retired", "Retirement works from " + stage)
		check(run.retire() and score == [run.wins, run.losses, run.draws], "Retirement is idempotent and preserves the " + stage + " score")
		var loaded := _roundtrip(run)
		check(loaded != null and loaded.outcome == "retired", "Retirement from " + stage + " resumes to its summary")
