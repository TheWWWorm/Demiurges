class_name ELArenaRun
extends RefCounted
## A complete offline draft run. All combat uses the ordinary duel rules.
## Drafts, opponents and battle chance have independent deterministic seeds;
## a checkpoint restores the exact battle, never a new opening or draw roll.

const SAVE_PATH := "user://arena-el2.json"
const SAVE_FORMAT := "demiurges-draft-arena"
const SAVE_VERSION := 1
const MAX_SAVE_BYTES := 4 * 1024 * 1024
const FACTIONS: Array[String] = ["Red", "Blue", "Green", "Black"]
const STYLES: Array[String] = ["balanced", "aggressive", "control", "synergy"]
const NAMES: Array[String] = ["Ash", "Vesper", "Flint", "Morrow", "Briar", "Rook", "Cinder", "Vale", "Thorn", "Echo", "Sable", "Wren"]
## 0: every hero is its race's heroes.def figure without a specialization or
## artifact (runs saved before 1). 1: each offered hero and each opponent has
## its own figure fixed by the run seed; after the hero the player picks a
## specialization and an artifact, opponents get seeded ones. 2: a hero skill
## at a seeded rank is picked after the artifact (opponents: a seeded one).
const HERO_VERSION := 2
## Specializations and artifacts offered to the player, one pick each.
const LOADOUT_OFFER := 3

var profile: ELProfile
var seed_value := 0
var rules_version := ELArenaRules.OPEN_RULES
var hero_levels := ELArenaRules.DEFAULT_LEVELS
var run_id := ""
var phase := "hero"
var hero_choices: Array[String] = []
var hero_version := HERO_VERSION
var faction := ""
var specialization := "NONE"
var artifacts: Array = []
## The picked hero skill, {code: rank}, beside the fixed Providence.
var skill: Dictionary = {}
var draft: ELArenaDraft
var wins := 0
var losses := 0
var draws := 0
var opponent: Dictionary = {}
var matches: Array[Dictionary] = []
var outcome := ""
var current_match_id := ""
var error := ""
## Tests and tooling can isolate their saves or keep a run entirely in memory.
var save_path := SAVE_PATH
var auto_save := true
var _pool_signatures: Dictionary = {}
var _battle_checkpoint: Dictionary = {}

## A new run is not written until persist() succeeds. The caller can therefore
## keep a previous run intact if creation or that first write fails.
func create(source: ELProfile, run_seed: int, rules := ELArenaRules.OPEN_RULES, levels := ELArenaRules.DEFAULT_LEVELS) -> bool:
	error = ""
	if source == null or source.id != "el2": return _fail("Draft Arena needs Etherlords II.")
	if run_seed < 0 or run_seed > 0x7fffffff: return _fail("Arena seeds must be between 0 and 2147483647.")
	if rules not in [ELArenaRules.LEGACY_RULES, ELArenaRules.OPEN_RULES, ELArenaRules.FACTION_RULES]: return _fail("Unsupported Arena draft rules.")
	var allowed := ELDuelCosts.hero_levels(source)
	for level: int in [levels.x, levels.y]:
		if level < allowed.x or level > allowed.y: return _fail("Arena hero level is outside the supported range.")
	var signatures := {}
	for magic: String in FACTIONS:
		if ELArenaRules.pool(source, magic, rules).size() < 6:
			return _fail("The Arena card pool is unavailable for " + magic + ".")
		signatures[magic] = ELArenaRules.pool_signature(source, magic, rules)
	profile = source
	rules_version = rules
	hero_levels = levels
	seed_value = run_seed & 0xffffffff
	# The identity is separate from all random streams: replaying a seed still
	# creates a different run, so an old battle cannot finish the new one.
	run_id = ("%d:%d:%d" % [seed_value, Time.get_unix_time_from_system(), Time.get_ticks_usec()]).sha256_text().left(24)
	hero_choices = _heroes(seed_value)
	hero_version = HERO_VERSION
	_pool_signatures = signatures
	phase = "hero"
	faction = ""
	specialization = "NONE"
	artifacts = []
	skill = {}
	draft = null
	wins = 0
	losses = 0
	draws = 0
	opponent = {}
	matches.clear()
	outcome = ""
	current_match_id = ""
	_battle_checkpoint = {}
	return true

static func _heroes(seed: int) -> Array[String]:
	var choices: Array[String] = FACTIONS.duplicate()
	var random := RandomNumberGenerator.new()
	random.seed = ELDuelMatch._mix(seed ^ 0x46e158c3)
	for i in range(choices.size() - 1, 0, -1):
		var j := random.randi_range(0, i)
		var held := choices[i]
		choices[i] = choices[j]
		choices[j] = held
	choices.resize(3)
	return choices

func _seed(salt: int, index := 0) -> int:
	return ELDuelMatch._mix(seed_value ^ salt ^ ELDuelMatch._mix(index + 1)) & 0x7fffffff

## The player's hero of a race: its seeded figure template, and once chosen
## the specialization, artifacts and skill the player drafted.
func hero_loadout(magic: String) -> Dictionary:
	if hero_version < 1 or profile == null: return ELArenaRules.NO_LOADOUT
	var figure := String(ELArenaRules.loadout(profile, magic, _seed(0x5d1f3a27, FACTIONS.find(magic))).template)
	if magic != faction: return {"template": figure, "specialization": "NONE", "artifacts": [], "skills": {}}
	return {"template": figure, "specialization": specialization, "artifacts": artifacts.duplicate(), "skills": skill.duplicate()}

## Opponents keep a specialization, artifact and (from version 2) skill fixed
## by the run seed.
func _opponent_loadout(index: int, magic: String) -> Dictionary:
	if hero_version < 1: return ELArenaRules.NO_LOADOUT
	# Never the player's own figure, so the two sides always look different.
	var result := ELArenaRules.loadout(profile, magic, _seed(0x6b3c2e19, index), String(hero_loadout(faction).template))
	if hero_version < 2: result.erase("skills")
	return result

## The specializations offered to the chosen hero (empty before the choice).
func spec_offer() -> Array[String]:
	if hero_version < 1 or faction.is_empty(): return []
	return ELArenaRules.offer(ELArenaRules.specializations(profile, faction), _seed(0x41c7b2d5), LOADOUT_OFFER)

func artifact_offer() -> Array[String]:
	if hero_version < 1 or faction.is_empty(): return []
	return ELArenaRules.offer(ELDuelCosts.duel_artifacts(profile), _seed(0x2f8e6a13), LOADOUT_OFFER)

## Three different hero skills, each at its own seeded rank (0 to 2), so a
## strong skill may come at a low rank beside a weaker one at its highest.
func skill_offer() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if hero_version < 2 or faction.is_empty(): return result
	var codes := ELArenaRules.offer(ELArenaRules.skills(profile), _seed(0x6c2d94e1), LOADOUT_OFFER)
	for index in codes.size():
		result.append({"code": codes[index], "rank": _seed(0x1b7f3c59, index) % (ELHeroSkills.MAX_RANK + 1)})
	return result

## The hero's steps in order, each with whether it offers anything.
func _steps() -> Array:
	return [["spec", not spec_offer().is_empty()], ["artifact", not artifact_offer().is_empty()], ["skill", not skill_offer().is_empty()]]

## The phase after `from` (the hero or one of its steps): a step with nothing
## to offer is skipped.
func _after_hero(from: String) -> String:
	var passed := from == "hero"
	for step: Array in _steps():
		if passed and step[1]: return step[0]
		if step[0] == from: passed = true
	return "draft"

func choose_hero(magic: String) -> bool:
	error = ""
	if phase != "hero" or not hero_choices.has(magic): return _fail("Choose one of the three offered heroes.")
	var next := ELArenaDraft.new()
	if not next.create(profile, magic, _seed(0x248bac65), rules_version): return _fail(next.error)
	var previous := snapshot()
	faction = magic
	draft = next
	phase = _after_hero("hero")
	return _commit(previous)

## Takes one offer of the specialization, artifact or skill step.
func choose_loadout(index: int) -> bool:
	error = ""
	var count := 0
	match phase:
		"spec": count = spec_offer().size()
		"artifact": count = artifact_offer().size()
		"skill": count = skill_offer().size()
	if index < 0 or index >= count: return _fail("Choose one of the offered options.")
	var previous := snapshot()
	match phase:
		"spec": specialization = spec_offer()[index]
		"artifact": artifacts = [artifact_offer()[index]]
		"skill":
			var offered: Dictionary = skill_offer()[index]
			skill = {String(offered.code): int(offered.rank)}
	phase = _after_hero(phase)
	return _commit(previous)

func pick(index: int) -> bool:
	error = ""
	if phase != "draft" or draft == null: return _fail("There is no Arena pick to make.")
	var previous := snapshot()
	if not draft.choose(index): return _fail(draft.error)
	if draft.finished(): phase = "ready"
	return _commit(previous)

func finished() -> bool:
	return phase == "finished"

func _match_id(index: int) -> String:
	return "%s-%03d" % [run_id, index + 1]

func _arenas() -> Array[String]:
	var result: Array[String] = []
	for key: String in profile.table("CombatSceneDB"): result.append(key)
	result.sort()
	return result

## This choice depends on the run seed and match number, never on the player's
## faction, cards or earlier offers. Every stage uses the same strong drafter.
func _opponent_identity(index: int) -> Dictionary:
	var identity := _seed(0x762b91ef, index)
	var arenas := _arenas()
	if arenas.is_empty(): return {}
	return {"id": "bot-%08x" % identity, "name": NAMES[identity % NAMES.size()],
		"faction": FACTIONS[_seed(0x1c648f3b, index) % FACTIONS.size()],
		"style": STYLES[_seed(0x592ac781, index) % STYLES.size()],
		"draft_seed": _seed(0x30db9f15, index), "encounter_id": _match_id(index),
		"battle_seed": _seed(0x654a9b27, index), "first_side": _seed(0x2ec47193, index) & 1,
		"arena": arenas[_seed(0x197ce4b5, index) % arenas.size()]}

func _make_opponent(index: int) -> Dictionary:
	var result := _opponent_identity(index)
	if result.is_empty():
		_fail("No Arena battlefield is available.")
		return {}
	var chosen := ELArenaDraftBot.make(profile, result.faction, int(result.draft_seed), result.style, rules_version)
	if chosen == null or not chosen.finished():
		_fail(chosen.error if chosen != null else "The computer's Arena draft failed.")
		return {}
	result.cards = chosen.cards.duplicate()
	result.draft = chosen.snapshot()
	var loadout := _opponent_loadout(index, result.faction)
	if hero_version >= 1: result.loadout = loadout.duplicate(true)
	result.preset = ELArenaRules.hero_preset(profile, result.faction, result.cards, rules_version, hero_levels.y, loadout)
	if result.preset.is_empty():
		_fail("The computer drafted an invalid spellbook.")
		return {}
	result.preset.id = result.id
	result.preset.name = result.name
	return result

func _options(foe: Dictionary) -> Dictionary:
	var mine := hero_loadout(faction)
	var player := ELArenaRules.hero_preset(profile, faction, draft.cards, rules_version, hero_levels.x, mine)
	if player.is_empty(): return {}
	var theirs: Dictionary = foe.get("loadout", ELArenaRules.NO_LOADOUT)
	var options := ELDuelPresets.options(profile, [player, foe.preset], str(foe.arena), [String(mine.template), String(theirs.get("template", ""))])
	options.first_side = int(foe.first_side)
	options.arena_run_id = run_id
	options.arena_match_id = str(foe.encounter_id)
	return options

## The first call commits the opponent, opening state and battle seed together.
## Further calls resume that exact checkpoint and cannot redraft the opponent.
func build_battle() -> ELDuel:
	error = ""
	if phase == "battle": return _restore_battle(_battle_checkpoint)
	if phase != "ready" or draft == null or not draft.finished():
		_fail("Finish the Arena draft before entering a battle.")
		return null
	var foe := _make_opponent(matches.size())
	if foe.is_empty(): return null
	var options := _options(foe)
	if options.is_empty():
		_fail("The Arena spellbook is invalid.")
		return null
	var duel := ELDuel.new()
	if not duel.start(profile, int(foe.battle_seed), options):
		_fail(duel.error)
		return null
	var previous := snapshot()
	opponent = foe
	current_match_id = str(foe.encounter_id)
	phase = "battle"
	_battle_checkpoint = duel.snapshot()
	return duel if _commit(previous) else null

func _belongs(duel: ELDuel) -> bool:
	return duel != null and duel.profile == profile and not opponent.is_empty() \
		and duel.setup.get("arena_run_id") == run_id and duel.setup.get("arena_match_id") == current_match_id \
		and duel.setup == _options(opponent) and duel.heroes.size() == 2 \
		and duel.heroes[0].deck == draft.cards and duel.heroes[1].deck == opponent.cards

func _restore_battle(saved: Dictionary) -> ELDuel:
	if saved.is_empty():
		_fail("The Arena battle checkpoint is missing.")
		return null
	var duel := ELDuel.new()
	if not duel.restore(profile, {"format": "etherlords-duel", "version": 1, "state": saved}):
		_fail(duel.error)
		return null
	if not _belongs(duel):
		_fail("This battle does not match the Arena's drafted spellbooks.")
		return null
	for side in 2:
		var hero: Dictionary = duel.heroes[side]
		var loadout: Dictionary = hero_loadout(faction) if side == 0 else opponent.get("loadout", ELArenaRules.NO_LOADOUT)
		if int(hero.level) != hero_levels[side] or hero.skills != ELArenaRules.hero_skills(loadout) \
			or hero.get("spec", "NONE") != String(loadout.get("specialization", "NONE")) \
			or Array(hero.get("artifacts", [])).size() != Array(loadout.get("artifacts", [])).size():
			_fail("This battle does not match the Arena hero rules.")
			return null
	return duel

func save_battle(duel: ELDuel) -> bool:
	error = ""
	if phase != "battle" or not _belongs(duel): return _fail("This battle belongs to another Arena match.")
	var saved := duel.snapshot()
	if saved == _battle_checkpoint: return true
	var previous := snapshot()
	_battle_checkpoint = saved
	return _commit(previous)

## A recorded encounter is acknowledged again without changing the score.
## On disk failure all changes roll back, so retrying this same battle is safe.
func resolve_battle(duel: ELDuel) -> bool:
	error = ""
	if duel == null or duel.profile != profile or duel.phase != ELDuel.Phase.FINISHED \
		or duel.setup.get("arena_run_id") != run_id:
		return _fail("The Arena battle has not finished.")
	var id := str(duel.setup.get("arena_match_id", ""))
	for row: Dictionary in matches:
		if row.id == id:
			return true if int(row.winner) == duel.winner else _fail("This Arena result conflicts with its recorded outcome.")
	if phase != "battle" or not _belongs(duel): return _fail("This battle belongs to another Arena match.")
	if duel.winner not in [-1, 0, 1]: return _fail("The Arena battle has an invalid result.")
	var previous := snapshot()
	if duel.winner == 0: wins += 1
	elif duel.winner == 1: losses += 1
	else: draws += 1
	matches.append({"id": id, "index": matches.size(), "winner": duel.winner,
		"outcome": "win" if duel.winner == 0 else ("loss" if duel.winner == 1 else "draw"),
		"opponent": opponent.duplicate(true), "turns": duel.round_number,
		"player_health": maxi(0, int(duel.heroes[0].health)), "opponent_health": maxi(0, int(duel.heroes[1].health)),
		"wins": wins, "losses": losses, "draws": draws})
	_battle_checkpoint = {}
	phase = "result"
	if wins >= ELArenaRules.WIN_LIMIT or losses >= ELArenaRules.LOSS_LIMIT:
		phase = "finished"
		outcome = "victory" if wins >= ELArenaRules.WIN_LIMIT else "defeat"
	return _commit(previous)

func continue_run() -> bool:
	error = ""
	if phase != "result": return _fail("There is no Arena result to continue from.")
	var previous := snapshot()
	phase = "ready"
	opponent = {}
	current_match_id = ""
	_battle_checkpoint = {}
	return _commit(previous)

func retire() -> bool:
	error = ""
	if finished(): return outcome == "retired" or _fail("This Arena run has already ended.")
	if profile == null: return _fail("There is no Arena run to retire.")
	var previous := snapshot()
	phase = "finished"
	outcome = "retired"
	_battle_checkpoint = {}
	return _commit(previous)

func snapshot() -> Dictionary:
	return {"format": SAVE_FORMAT, "version": SAVE_VERSION, "rules_version": rules_version,
		"edition": "el2", "seed": seed_value, "run_id": run_id, "phase": phase,
		"hero_levels": [hero_levels.x, hero_levels.y],
		"hero_choices": hero_choices.duplicate(), "hero_version": hero_version, "faction": faction,
		"specialization": specialization, "artifacts": artifacts.duplicate(), "skill": skill.duplicate(),
		"draft": draft.snapshot() if draft != null else {}, "pool_signatures": _pool_signatures.duplicate(),
		"wins": wins, "losses": losses, "draws": draws, "outcome": outcome,
		"opponent": opponent.duplicate(true), "matches": matches.duplicate(true),
		"current_match_id": current_match_id, "battle": _battle_checkpoint.duplicate(true)}

func persist() -> bool:
	error = ""
	if profile == null or run_id.is_empty(): return _fail("There is no Arena run to save.")
	var bytes := JSON.stringify(snapshot(), "", true, true).to_utf8_buffer()
	if bytes.size() > MAX_SAVE_BYTES: return _fail("The Arena checkpoint is too large.")
	if not ELSafeFile.write_bytes(save_path, bytes): return _fail("Could not save the Arena run. The previous checkpoint is unchanged.")
	return true

static func has_save(path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

func restore(source: ELProfile) -> bool:
	error = ""
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null: return _fail("No Arena checkpoint is available.")
	if file.get_length() > MAX_SAVE_BYTES: return _fail("The Arena checkpoint is too large.")
	return restore_snapshot(source, JSON.parse_string(file.get_as_text()))

func _commit(previous: Dictionary) -> bool:
	if not auto_save or persist(): return true
	var failure := error
	_adopt(profile, previous)
	error = failure
	return false

## Only called with a validated save or this run's own pre-transition snapshot.
func _adopt(source: ELProfile, data: Dictionary) -> void:
	profile = source
	rules_version = int(data.rules_version)
	hero_levels = Vector2i(int(data.hero_levels[0]), int(data.hero_levels[1]))
	seed_value = int(data.seed)
	run_id = str(data.run_id)
	phase = str(data.phase)
	hero_choices.assign(data.hero_choices)
	hero_version = int(data.get("hero_version", 0))
	faction = str(data.faction)
	specialization = str(data.get("specialization", "NONE"))
	artifacts = Array(data.get("artifacts", [])).duplicate()
	skill = {}
	for code: Variant in Dictionary(data.get("skill", {})): skill[String(code)] = int(data.skill[code])
	draft = null
	if not Dictionary(data.draft).is_empty():
		draft = ELArenaDraft.new()
		draft.restore(source, data.draft)
	_pool_signatures = Dictionary(data.pool_signatures).duplicate()
	wins = int(data.wins)
	losses = int(data.losses)
	draws = int(data.draws)
	outcome = str(data.outcome)
	opponent = Dictionary(data.opponent).duplicate(true)
	matches.assign(Array(data.matches).duplicate(true))
	current_match_id = str(data.current_match_id)
	_battle_checkpoint = Dictionary(data.battle).duplicate(true)

func restore_snapshot(source: ELProfile, raw: Variant) -> bool:
	error = ""
	if source == null or source.id != "el2": return _fail("Draft Arena needs Etherlords II.")
	if raw is not Dictionary or raw.get("format") != SAVE_FORMAT or raw.get("edition") != "el2" \
		or raw.get("version") != SAVE_VERSION \
		or not ELLuaSave._integer(raw.get("rules_version"), ELArenaRules.LEGACY_RULES, ELArenaRules.FACTION_RULES):
		return _fail("The Arena checkpoint uses different rules or an unknown format.")
	var data: Dictionary = ELMatchSave._integers(raw)
	var levels: Variant = raw.get("hero_levels", [ELArenaRules.DEFAULT_LEVEL, ELArenaRules.DEFAULT_LEVEL])
	var allowed := ELDuelCosts.hero_levels(source)
	if levels is not Array or levels.size() != 2 or not ELLuaSave._integer(levels[0], allowed.x, allowed.y) \
		or not ELLuaSave._integer(levels[1], allowed.x, allowed.y):
		return _fail("The Arena checkpoint has invalid hero levels.")
	data.hero_levels = [int(levels[0]), int(levels[1])]
	if not ELLuaSave._integer(raw.get("hero_version", 0), 0, HERO_VERSION):
		return _fail("The Arena checkpoint uses an unknown hero format.")
	data.hero_version = int(raw.get("hero_version", 0))
	data.specialization = raw.get("specialization", "NONE")
	data.artifacts = raw.get("artifacts", [])
	if data.specialization is not String or data.artifacts is not Array or not Array(data.artifacts).all(func(item: Variant) -> bool: return item is String):
		return _fail("The Arena checkpoint has an invalid hero.")
	var saved_skill: Variant = raw.get("skill", {})
	if saved_skill is not Dictionary or saved_skill.size() > 1 or not saved_skill.keys().all(func(code: Variant) -> bool: return code is String and ELLuaSave._integer(saved_skill[code], 0, ELHeroSkills.MAX_RANK)):
		return _fail("The Arena checkpoint has an invalid hero skill.")
	data.skill = saved_skill
	for key: String in ["run_id", "phase", "faction", "outcome", "current_match_id"]:
		if data.get(key) is not String: return _fail("The Arena checkpoint has invalid run settings.")
	if not ELLuaSave._integer(data.get("seed"), 0, 0x7fffffff) or not _valid_id(data.run_id):
		return _fail("The Arena checkpoint has an invalid identity.")
	if data.phase not in ["hero", "spec", "artifact", "skill", "draft", "ready", "battle", "result", "finished"]:
		return _fail("The Arena checkpoint has an invalid phase.")
	for key: String in ["draft", "pool_signatures", "opponent", "battle"]:
		if data.get(key) is not Dictionary: return _fail("The Arena checkpoint is incomplete.")
	if data.get("hero_choices") is not Array or data.hero_choices != _heroes(int(data.seed)) or data.get("matches") is not Array:
		return _fail("The Arena checkpoint has invalid offered heroes or results.")
	for row: Variant in data.matches:
		if row is not Dictionary: return _fail("The Arena checkpoint has an invalid match history.")
	for magic: String in FACTIONS:
		if data.pool_signatures.get(magic) != ELArenaRules.pool_signature(source, magic, int(data.rules_version)):
			return _fail("The installed Arena card pool has changed. Start a new run to use the new rules.")
	for key: String in ["wins", "losses", "draws"]:
		if not ELLuaSave._integer(data.get(key), 0, 100000): return _fail("The Arena checkpoint has an invalid score.")
	if int(data.wins) > ELArenaRules.WIN_LIMIT or int(data.losses) > ELArenaRules.LOSS_LIMIT:
		return _fail("The Arena checkpoint exceeds the run limits.")
	var candidate := ELArenaRun.new()
	candidate.auto_save = false
	candidate.profile = source
	candidate.seed_value = int(data.seed)
	candidate.run_id = str(data.run_id)
	candidate.hero_version = int(data.hero_version)
	if not data.draft.is_empty():
		var check_draft := ELArenaDraft.new()
		if not check_draft.restore(source, data.draft) or check_draft.rules_version != int(data.rules_version) or check_draft.faction != data.faction \
			or check_draft.seed_value != candidate._seed(0x248bac65) or not data.hero_choices.has(data.faction):
			return _fail("The Arena draft transcript is invalid.")
	elif not data.faction.is_empty(): return _fail("The Arena draft is missing.")
	candidate._adopt(source, data)
	if not candidate._valid_state(): return _fail(candidate.error)
	_adopt(source, candidate.snapshot())
	return true

static func _valid_id(value: String) -> bool:
	if value.length() != 24: return false
	for code: int in value.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)): return false
	return true

func _valid_opponent(foe: Dictionary, index: int) -> bool:
	var expected := _opponent_identity(index)
	if expected.is_empty(): return _fail("The Arena battlefield is unavailable.")
	for key: String in expected:
		if foe.get(key) != expected[key]: return _fail("The Arena opponent does not match the run seed.")
	if foe.get("draft") is not Dictionary or foe.get("cards") is not Array or foe.get("preset") is not Dictionary:
		return _fail("The Arena opponent's draft is missing.")
	var check_draft := ELArenaDraft.new()
	if not check_draft.restore(profile, foe.draft) or check_draft.rules_version != rules_version or not check_draft.finished() \
		or check_draft.faction != foe.faction or check_draft.seed_value != int(foe.draft_seed) or check_draft.cards != foe.cards:
		return _fail("The Arena opponent's draft transcript is invalid.")
	var loadout := _opponent_loadout(index, foe.faction)
	if (hero_version >= 1 and foe.get("loadout") != loadout) or (hero_version < 1 and foe.has("loadout")):
		return _fail("The Arena opponent's hero does not match the run seed.")
	var preset := ELArenaRules.hero_preset(profile, foe.faction, foe.cards, rules_version, hero_levels.y, loadout)
	if preset.is_empty(): return _fail("The Arena opponent's spellbook is invalid.")
	preset.id = foe.id
	preset.name = foe.name
	if preset != foe.preset: return _fail("The Arena opponent's hero rules have changed.")
	return true

## The player's specialization and artifact come from their offers, in order:
## the specialization step, then the artifact step, then the cards.
func _valid_loadout() -> bool:
	var taken := {"spec": specialization != "NONE", "artifact": not artifacts.is_empty(), "skill": not skill.is_empty()}
	if hero_version < 1 or faction.is_empty():
		return not taken.values().has(true) or _fail("The Arena hero has an unexpected specialization, artifact or skill.")
	var offered_skill := skill_offer().any(func(entry: Dictionary) -> bool: return skill == {String(entry.code): int(entry.rank)})
	if (taken.spec and specialization not in spec_offer()) or (taken.artifact and (artifacts.size() != 1 or String(artifacts[0]) not in artifact_offer())) \
		or (taken.skill and not offered_skill):
		return _fail("The Arena hero's specialization, artifact or skill was not offered.")
	# Steps are taken in order: every offered step before the current phase is
	# done, none from it on; a retired run may stop after any step.
	var open := false
	for step: Array in _steps():
		var name: String = step[0]
		if name == phase: open = true
		if not step[1]:
			if taken[name]: return _fail("The Arena hero has a choice that was never offered.")
			if name == phase: return _fail("The Arena hero step has nothing to offer.")
			continue
		if open and taken[name]: return _fail("The Arena hero's choices are out of order.")
		if not open and not taken[name]:
			if phase != "finished": return _fail("The Arena hero is missing a choice.")
			open = true
	return true

func _valid_state() -> bool:
	var tally := [0, 0, 0]
	for i in matches.size():
		var row: Dictionary = matches[i]
		if row.get("id") != _match_id(i) or row.get("index") != i or row.get("winner") not in [-1, 0, 1] \
			or row.get("opponent") is not Dictionary or not _valid_opponent(row.opponent, i):
			return _fail("The Arena match history is invalid.")
		if tally[0] >= ELArenaRules.WIN_LIMIT or tally[1] >= ELArenaRules.LOSS_LIMIT:
			return _fail("The Arena history continues after the run ended.")
		var slot := 2 if int(row.winner) == -1 else int(row.winner)
		tally[slot] += 1
		if row.get("outcome") != ["win", "loss", "draw"][slot] \
			or row.get("wins") != tally[0] or row.get("losses") != tally[1] or row.get("draws") != tally[2]:
			return _fail("The Arena match history has inconsistent scores.")
		for key: String in ["turns", "player_health", "opponent_health"]:
			if not ELLuaSave._integer(row.get(key), 1 if key == "turns" else 0, 0x7fffffff):
				return _fail("The Arena match history has invalid battle results.")
	if tally != [wins, losses, draws]: return _fail("The Arena score does not match its results.")
	if outcome not in ["", "victory", "defeat", "retired"] or (phase == "finished") != (not outcome.is_empty()):
		return _fail("The Arena run has an inconsistent outcome.")
	if outcome == "victory" and (wins != ELArenaRules.WIN_LIMIT or losses >= ELArenaRules.LOSS_LIMIT): return _fail("The Arena victory score is invalid.")
	if outcome == "defeat" and (losses != ELArenaRules.LOSS_LIMIT or wins >= ELArenaRules.WIN_LIMIT): return _fail("The Arena defeat score is invalid.")
	if outcome in ["", "retired"] and (wins >= ELArenaRules.WIN_LIMIT or losses >= ELArenaRules.LOSS_LIMIT): return _fail("The Arena run should already have ended.")
	if draft == null:
		return true if phase in ["hero", "finished"] and outcome in ["", "retired"] and matches.is_empty() \
			and opponent.is_empty() and current_match_id.is_empty() and _battle_checkpoint.is_empty() else _fail("The Arena draft is missing.")
	if not _valid_loadout(): return false
	if not draft.finished():
		if phase in ["spec", "artifact", "skill"] and not draft.cards.is_empty(): return _fail("The Arena hero changed after drafting began.")
		return true if phase in ["spec", "artifact", "skill", "draft", "finished"] and outcome in ["", "retired"] and matches.is_empty() \
			and opponent.is_empty() and current_match_id.is_empty() and _battle_checkpoint.is_empty() else _fail("The Arena draft is incomplete.")
	if phase in ["hero", "spec", "artifact", "skill", "draft"]: return _fail("The Arena draft is complete but the run has not advanced.")
	if phase == "ready":
		return true if opponent.is_empty() and current_match_id.is_empty() and _battle_checkpoint.is_empty() else _fail("The Arena lobby has an unexpected battle.")
	if phase == "battle":
		if current_match_id != _match_id(matches.size()) or not _valid_opponent(opponent, matches.size()): return _fail("The active Arena opponent is invalid.")
		return _restore_battle(_battle_checkpoint) != null
	if not _battle_checkpoint.is_empty(): return _fail("A completed Arena match still has an active checkpoint.")
	if phase == "result" or outcome in ["victory", "defeat"]:
		return true if not matches.is_empty() and current_match_id == matches[-1].id and opponent == matches[-1].opponent else _fail("The Arena result is missing its match.")
	# Retirement may happen in the lobby, after a result or during a battle.
	if opponent.is_empty(): return current_match_id.is_empty() or _fail("The retired Arena run has an incomplete opponent.")
	var previous: bool = not matches.is_empty() and current_match_id == matches[-1].id
	var index := matches.size() - 1 if previous else matches.size()
	return current_match_id == _match_id(index) and _valid_opponent(opponent, index)

func _fail(message: String) -> bool:
	error = message
	return false
