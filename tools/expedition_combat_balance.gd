extends SceneTree
## AI-PLAYED Expedition balance probes: no assigned winner, injected lethal,
## or forced end-phase. Both sides use the game's real full-information AI.
## The offline fixture contains wiki card data and recorded original starter
## books. Other books are explicitly authored proxies. Sparse observed ether
## totals are interpolated: this is NOT the original CombatManaIncome table.
## Scripted campaign guardians cannot be reproduced without original files.
##
## python3 tools/expedition_balance_fixture.py --workspace /tmp/expedition-balance
## godot --headless --path game --script ../tools/expedition_combat_balance.gd -- \
##   --fixture=/tmp/expedition-balance/fixture.json --output=/tmp/balance.jsonl \
##   --styles=starter --variants=base --limit=8
##
## Use --el2=/installation for original card/hero/income tables. Authored
## opponents remain proxies; --fixture still supplies documented starter books.
## --income=observed|lower|upper|flat selects an explicit OFFLINE proxy.
## --offset/--limit permit bounded, resumable batches. Output flushes each game.
## Elite tradeoffs: --styles=pressure,engine,thin
## --variants=base,overcharged,fortified,veteran,veteran_overcharged,veteran_fortified
## Veteran's ordinary modifier applies BEFORE the optional elite tradeoff.

const FACTIONS := ["Red", "Green", "Blue", "Black"]
const STARTERS := {"Red": "STR1", "Green": "STG1", "Blue": "STU1", "Black": "STB1"}
const STYLES := ["starter", "starter12", "pressure", "engine", "thin"]
const VARIANTS := ["base", "tactics", "wounded", "prism", "level2", "level3", "crest", "prism_crest", "veteran_hp", "veteran_level", "veteran", "overcharged", "fortified", "veteran_overcharged", "veteran_fortified", "living_heart", "blood_crown"]
# Removing four duplicate slots retains all original starter card identities.
# These are authored reductions of a recorded book, not original presets.
# Removal changes the draw cycle and sacrifices finite charges: 32 total uses
# become 24 at basic Resources. Both effects are exercised by the real duel.
const STARTER_REMOVALS := {
	"Red": ["STRT", "FRWA", "ZAPP", "LSST"],
	"Green": ["SPFG", "TIWR", "SHCL", "MNDP"],
	"Blue": ["LSUS", "AVSC", "LSDS", "TGSK"],
	"Black": ["MCWO", "ENFL", "TWEN", "JRRG"],
}
const BOOKS := {
	"Red": {
		"pressure": ["STRT", "STRT", "STRT", "STRT", "DRAT", "DRAT", "DRAT", "KBWR", "KBWR", "CLIG", "CLIG", "ZAPP", "ZAPP", "STRG", "STRG", "LSST"],
		"engine": ["WLMG", "WLMG", "ORSH", "ORSH", "ORGD", "ORGD", "CLIG", "CLIG", "COMT", "COMT", "FRBL", "ZAPP", "ZAPP", "GEYS", "WEAK", "WEAK"],
		"thin": ["STRT", "STRT", "DRAT", "DRAT", "KBWR", "KBWR", "CLIG", "CLIG", "ZAPP", "STRG", "STRG", "LSST"],
	},
	"Green": {
		"pressure": ["BEWK", "BEWK", "BEWK", "BEWK", "BEWR", "BEWR", "BEWR", "BEWR", "BEQN", "BEQN", "MOBE", "MOBE", "UPGD", "UPGD", "BLSS", "BLSS"],
		"engine": ["TNSA", "TNSA", "TNSA", "TANT", "TANT", "TANT", "GRTN", "GRTN", "UPGD", "UPGD", "CANV", "CLSN", "SYMB", "SYMB", "BLSS", "BLSS"],
		"thin": ["BEWK", "BEWK", "BEWR", "BEWR", "BEWR", "BEQN", "BEQN", "MOBE", "MOBE", "UPGD", "BLSS", "BLSS"],
	},
	"Blue": {
		"pressure": ["RVHL", "RVHL", "RVHL", "RVHL", "AVSC", "AVSC", "AVSC", "AVMK", "AVMK", "SPWR", "SPWR", "STAT", "STAT", "CLNP", "LSUS", "LSUS"],
		"engine": ["GBBR", "GBBR", "GBBR", "GBBR", "GBIN", "GBIN", "GBGN", "GBGN", "UNSM", "UNSM", "SPWR", "SPWR", "FOGG", "FOGG", "STAT", "STAT"],
		"thin": ["RVHL", "RVHL", "AVSC", "AVSC", "AVMK", "AVMK", "SPWR", "SPWR", "STAT", "CLNP", "LSUS", "LSUS"],
	},
	"Black": {
		"pressure": ["BRAB", "BRAB", "BRAB", "BRAB", "IRAB", "IRAB", "IRAB", "MNHP", "MNHP", "TWEN", "TWEN", "REPR", "REPR", "CLFR", "PRFY", "JRRG"],
		"engine": ["MCWO", "MCWO", "MCWO", "MCWO", "MCWU", "MCWU", "WLIL", "WLIL", "WETX", "WETX", "ENFL", "ENFL", "PRFY", "REPR", "REPR", "CLFR"],
		"thin": ["BRAB", "BRAB", "BRAB", "IRAB", "IRAB", "MNHP", "TWEN", "TWEN", "REPR", "CLFR", "PRFY", "JRRG"],
	},
}

var profile: ELProfile
var fixture := {}
var data_mode := ""
var income_mode := "observed"
var output: FileAccess
var results: Array[Dictionary] = []
var failures := 0

func _arg(name: String, fallback := "") -> String:
	var prefix := "--" + name + "="
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture_path := _arg("fixture")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if raw is not Dictionary or raw.get("expedition_balance") is not Dictionary:
		printerr("Run tools/expedition_balance_fixture.py first and pass its --fixture path.")
		quit(1)
		return
	fixture = raw
	income_mode = _arg("income", "observed")
	if income_mode not in ["observed", "lower", "upper", "flat"]:
		printerr("Unknown income proxy: " + income_mode)
		quit(1)
		return
	profile = _profile(_arg("el2"))
	if profile == null:
		quit(1)
		return
	var output_path := _arg("output", "user://expedition-combat-balance.jsonl")
	output = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("Could not open output: " + output_path)
		quit(1)
		return
	ELCombatSearch.smart_engine = true
	ELCombatSearch.smart_engine_info = "full"
	ELCombatSearch.smart_engine_budget = clampi(int(_arg("nodes", "25000")), 1000, 8000000)
	ELCombatSearch.smart_engine_ms = clampi(int(_arg("think-ms", "75")), 0, 5000)
	ELCombatSearch.search_ms = maxi(50, ELCombatSearch.smart_engine_ms)
	# Fixed short search budget for controlled batch experiments, not the
	# production opponent's full 5-second budget. All comparisons share it.
	ELCombatSearch.smart_engine_prove = 0
	ELCombatSearch.smart_engine_beyond = 0
	var settings := {"type": "settings", "data_mode": data_mode, "income": income_mode,
		"fixture": fixture_path, "native": ELCombatBrain.available,
		"arguments": OS.get_cmdline_user_args(),
		"nodes": ELCombatSearch.smart_engine_budget, "think_ms": ELCombatSearch.smart_engine_ms,
		"forced_winners": false, "scripted_bosses": false,
		"boss_relic_economy_simulated": false,
		"prism_bonus": int(_arg("prism-bonus", "1")), "crest_bonus": int(_arg("crest-bonus", "2")),
		"limitations": fixture.expedition_balance.limitations}
	_write(settings)
	print("INPUT: ", data_mode, "; income=", income_mode, "; native=", ELCombatBrain.available)
	var cases := _cases()
	if cases.is_empty() or _arg("enemy-style", "starter") not in STYLES:
		printerr("No valid cases, or an unknown --enemy-style. Check --styles and --variants.")
		output.close()
		quit(1)
		return
	var start := clampi(int(_arg("offset", "0")), 0, cases.size())
	var end := mini(cases.size(), start + clampi(int(_arg("limit", "16")), 1, 4096))
	if start == end:
		printerr("The requested --offset is beyond the available cases.")
		output.close()
		quit(1)
		return
	var began := Time.get_ticks_msec()
	var total_limit := clampi(int(_arg("total-ms", "300000")), 1000, 3600000)
	for index in range(start, end):
		if Time.get_ticks_msec() - began >= total_limit:
			_write({"type": "batch_limit", "next_offset": index, "requested_end": end})
			break
		var result := _play(cases[index])
		result.case_index = index
		results.append(result)
		_write(result)
		print("COMBAT %d/%d %s/%s %s first=%d status=%s winner=%d rounds=%d life=%d/%d ms=%d" % [index + 1, cases.size(), result.faction, result.style, result.variant, result.first_side, result.status, result.winner, result.rounds, result.player_life, result.enemy_life, result.elapsed_ms])
	ELPracticeAI.finish()
	var summary := _summary()
	summary.elapsed_ms = Time.get_ticks_msec() - began
	summary.requested_games = end - start
	summary.complete = results.size() == end - start
	_write(summary)
	output.close()
	print("BALANCE SUMMARY: ", JSON.stringify(summary))
	quit(1 if failures > 0 else (0 if summary.complete else 2))

func _profile(installation: String) -> ELProfile:
	var source := ELProfile.new()
	if not installation.is_empty():
		if not source.mount("el2", installation):
			printerr(source.error)
			return null
		data_mode = "installed tables; recorded/authored benchmark books"
		return source
	source.id = "el2"
	source.title = "Expedition combat proxy"
	source.tables = fixture.el2.duplicate(true)
	source.texts = source.tables.get("texts", {}).duplicate()
	for name: String in ["HeroTemplates", "HeroesStats", "HeroesSpecs", "Artefacts", "Shapes", "CombatSceneDB", "ScenesNames", "CombatDecks", "CombatManaIncome"]:
		source.tables[name] = {}
	for faction: String in FACTIONS:
		source.tables.HeroTemplates[ELCatalog.default_hero(source, faction)] = {"BaseHealth": 7, "HealthIncrease": 3, "Level": 1, "Skills": []}
		source.tables.CombatSceneDB[faction + ".001"] = {}
	for rank in 3:
		source.tables.HeroesSkills["PRVD" + str(rank + 1)] = {"Code": "PRVD", "Level": rank + 1, "Name": "Resources"}
	var previous := {}
	for turn in range(1, 62):
		var row := {}
		for level in range(1, 21):
			var cumulative := _income_total(1 if income_mode == "flat" else level, turn)
			var before := int(previous.get(level, 0))
			cumulative = clampi(cumulative, before, before + 2)
			row["Level%d" % level] = cumulative - before
			previous[level] = cumulative
		source.tables.CombatManaIncome[str(turn)] = row
	data_mode = "wiki card data + recorded starter books + explicitly interpolated income proxy"
	return source

func _income_total(level: int, turn: int) -> int:
	# Anchor levels have multiple independent, non-conflicting observations.
	# Unobserved turns and intermediate levels are interpolation, disclosed in
	# every report. lower/upper test the rounding uncertainty of missing rows.
	var anchors: Array[int] = [1, 4, 8, 12]
	var low := 1
	var high := 12
	for anchor: int in anchors:
		if anchor <= level: low = anchor
		if anchor >= level:
			high = anchor
			break
	if level > 12: high = 12
	var base := _observed_total(low, turn)
	if low != high: base = lerpf(base, _observed_total(high, turn), float(level - low) / float(high - low))
	elif level > 12: base += float(level - 12) * turn / 16.0
	if income_mode == "lower": return floori(base)
	if income_mode == "upper": return ceili(base)
	return roundi(base)

func _observed_total(level: int, turn: int) -> float:
	var observations: Dictionary = fixture.expedition_balance.observed_channels[str(level)]
	var points: Array[int] = [0]
	for key: String in observations:
		if observations[key].counts.size() == 1: points.append(int(key))
	points.sort()
	var previous_turn := 0
	var previous_value := 0.0
	for next_turn: int in points:
		if next_turn == 0: continue
		var next_value := float(observations[str(next_turn)].counts.keys()[0])
		if turn <= next_turn:
			return lerpf(previous_value, next_value, float(turn - previous_turn) / float(next_turn - previous_turn))
		previous_turn = next_turn
		previous_value = next_value
	# Extrapolation is used only after the last observed turn; the real duel's
	# level-dependent ether disturbance still terminates long fights normally.
	return previous_value + float(turn - previous_turn) * (0.45 + float(level - 1) * 0.055)

func _book(faction: String, style: String) -> Array[String]:
	var result: Array[String] = []
	if style in ["starter", "starter12"]:
		result.assign(fixture.expedition_balance.books[STARTERS[faction]].cards)
		if style == "starter12":
			for card: String in STARTER_REMOVALS[faction]: result.erase(card)
	else: result.assign(BOOKS[faction][style])
	return result

func _cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var styles := _arg("styles", ",".join(STYLES)).split(",", false)
	var variants := _arg("variants", ",".join(VARIANTS)).split(",", false)
	for style: String in styles:
		if style not in STYLES:
			printerr("Unknown style: " + style)
			return result
	for variant: String in variants:
		if variant not in VARIANTS:
			printerr("Unknown variant: " + variant)
			return result
	for variant: String in variants:
		for style: String in styles:
			if variant in ["crest", "prism_crest"] and style not in ["thin", "starter12"]: continue
			for repeat_index in clampi(int(_arg("repeats", "1")), 1, 32):
				for index in FACTIONS.size():
					for first_side in 2:
						result.append({"type": "combat", "variant": variant, "style": style, "faction": FACTIONS[index],
							"enemy_faction": FACTIONS[(index + 1 + repeat_index % 3) % 4], "first_side": first_side,
							"seed": 41213 + repeat_index * 1009 + index * 101, "repeat": repeat_index})
	return result

func _play(spec: Dictionary) -> Dictionary:
	var result := spec.duplicate(true)
	var starter: bool = spec.style in ["starter", "starter12"]
	var level := int(_arg("player-level", "1" if starter else "3"))
	var health := int(_arg("player-life", "24" if starter else "28"))
	if spec.variant == "living_heart": health += 8
	var maximum := health
	if spec.variant == "wounded": health -= 6
	if spec.variant in ["prism", "prism_crest"]: level += int(_arg("prism-bonus", "1"))
	if spec.variant in ["crest", "prism_crest"]: level += int(_arg("crest-bonus", "2"))
	if spec.variant == "level2": level += 2
	if spec.variant == "level3": level += 3
	if spec.variant == "blood_crown": level += 1
	level = clampi(level, 1, 20)
	var player := {"faction": spec.faction, "cards": _book(spec.faction, spec.style),
		"health": health, "level": level, "skills": {"PRVD": 0}, "specialization": "NONE"}
	var enemy := {"id": "authored-proxy-" + str(spec.enemy_faction), "title": "Authored benchmark opponent",
		"faction": spec.enemy_faction, "cards": _book(spec.enemy_faction, _arg("enemy-style", "starter" if starter else "pressure")),
		"health": int(_arg("enemy-life", "10" if starter else "25")), "level": int(_arg("enemy-level", "1" if starter else "5")),
		"skills": {}, "specialization": "NONE"}
	if spec.variant in ["veteran_hp", "veteran", "veteran_overcharged", "veteran_fortified"]:
		enemy.health = ceili(float(enemy.health) * 1.15)
	if spec.variant in ["veteran_level", "veteran", "veteran_overcharged", "veteran_fortified"]:
		enemy.level = mini(20, int(enemy.level) + 1)
	result.enemy_base_level = enemy.level
	result.enemy_base_life = enemy.health
	var variant_error := ""
	if spec.variant in ["overcharged", "veteran_overcharged"]:
		if int(enemy.level) >= 20: variant_error = "Overcharged requires an enemy below level 20."
		else:
			enemy.level = int(enemy.level) + 1
			enemy.health = maxi(1, ceili(float(enemy.health) * 0.85))
	elif spec.variant in ["fortified", "veteran_fortified"]:
		if int(enemy.level) <= 1: variant_error = "Fortified requires an enemy above level 1."
		else:
			enemy.level = int(enemy.level) - 1
			enemy.health = ceili(float(enemy.health) * 1.25)
	if spec.variant == "tactics":
		enemy = ELExpeditionEncounters.apply_tactics(profile, enemy, "elite", int(_arg("act", "1" if starter else "2")), 3, int(spec.seed))
	result.player_level = level
	result.player_starting_life = health
	result.enemy_level = enemy.level
	result.enemy_starting_life = enemy.health
	result.player_cards = player.cards
	result.enemy_cards = enemy.cards
	result.strategy = enemy.get("strategy_id", "")
	result.winner = -1
	result.rounds = 0
	result.player_life = health
	result.enemy_life = enemy.health
	result.elapsed_ms = 0
	result.status = "invalid"
	if not variant_error.is_empty():
		result.error = variant_error
		failures += 1
		return result
	for side: Dictionary in [player, enemy]:
		for card: String in side.cards:
			if ELCatalog.rule(profile, card).is_empty() or not ELDuelCosts.spell_allowed(profile, card, side.faction):
				result.error = "Unavailable/wrong-faction benchmark card: " + card
				failures += 1
				return result
	ELCombatSearch.reset_caches()
	var duel := ELDuel.new()
	if not duel.start(profile, int(spec.seed), {"adventure": true, "players": [player, enemy], "first_side": spec.first_side, "arena": "Green.001"}):
		result.error = duel.error
		failures += 1
		return result
	duel.smart_sides.assign([0, 1])
	duel.heroes[0].maximum = maximum
	result.player_starting_charges = _charges(duel.heroes[0])
	result.enemy_starting_charges = _charges(duel.heroes[1])
	var began := Time.get_ticks_msec()
	var refused_before := ELPracticeAI.refused
	var empty_before := ELPracticeAI.empty
	var commands := 0
	var phase_commands := 0
	var native_searches := 0
	var mark: Array = []
	var game_limit := clampi(int(_arg("game-ms", "30000")), 1000, 300000)
	result.status = "running"
	while duel.phase != ELDuel.Phase.FINISHED:
		if Time.get_ticks_msec() - began >= game_limit:
			result.status = "timeout"
			break
		if duel.round_number > 45 or commands >= 900:
			result.status = "limit"
			break
		var now := [duel.round_number, duel.attacker, duel.phase]
		if now != mark:
			mark = now
			phase_commands = 0
		phase_commands += 1
		if phase_commands > 80:
			result.status = "stalled"
			break
		ELPracticeAI.step(duel)
		if ELPracticeAI.last_decision.get("engine") in ["native", "proof", "beyond"]: native_searches += 1
		commands += 1
	if duel.phase == ELDuel.Phase.FINISHED:
		result.status = "finished"
		result.winner = duel.winner
	result.rounds = duel.round_number
	result.player_life = int(duel.heroes[0].health)
	result.enemy_life = int(duel.heroes[1].health)
	result.elapsed_ms = Time.get_ticks_msec() - began
	result.commands = commands
	result.native_searches = native_searches
	result.player_remaining_charges = _charges(duel.heroes[0])
	result.enemy_remaining_charges = _charges(duel.heroes[1])
	result.refused = ELPracticeAI.refused - refused_before
	result.empty = ELPracticeAI.empty - empty_before
	if result.status != "finished" or result.refused > 0 or result.empty > 0: failures += 1
	return result

func _charges(hero: Dictionary) -> int:
	var total := 0
	for count: int in hero.spell_uses: total += count
	return total

func _write(row: Dictionary) -> void:
	output.store_line(JSON.stringify(row, "", true, true))
	output.flush()

func _summary() -> Dictionary:
	var groups := {}
	for row: Dictionary in results:
		var key := str(row.variant) + "/" + str(row.style)
		if not groups.has(key):
			groups[key] = {"games": 0, "finished": 0, "wins": 0, "draws": 0, "rounds": 0, "remaining_life": 0,
				"wins_by_round_6": 0, "wins_by_round_8": 0, "wins_by_round_10": 0,
				"games_by_first_side": [0, 0], "wins_by_first_side": [0, 0]}
		var group: Dictionary = groups[key]
		group.games += 1
		group.games_by_first_side[int(row.first_side)] += 1
		if row.status != "finished": continue
		group.finished += 1
		group.wins += int(row.winner == 0)
		if row.winner == 0:
			group.wins_by_round_6 += int(row.rounds <= 6)
			group.wins_by_round_8 += int(row.rounds <= 8)
			group.wins_by_round_10 += int(row.rounds <= 10)
			group.wins_by_first_side[int(row.first_side)] += 1
		group.draws += int(row.winner == -1)
		group.rounds += row.rounds
		group.remaining_life += maxi(0, int(row.player_life))
	return {"type": "summary", "games": results.size(), "failures": failures, "groups": groups}
