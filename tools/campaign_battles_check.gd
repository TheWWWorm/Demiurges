extends SceneTree
## Plays the battles of the campaign chapters to their end, both heroes played
## by the computer opponent as the game plays it (ELPracticeAI.step, the
## "Smarter" setting on both sides unless --ai says otherwise).
##
## Every chapter of every campaign is opened as a campaign chapter (map, its
## script, the director settled past the opening dialogue). Each creature or
## hero hostile to the player's hero is then met through the game's own
## encounter (ELAdventureEncounter.prepare: decks, levels by difficulty, fort
## rods, artifacts, arena, first side, and in the second game the battle
## scripts of the creature and of the battlegrounds round it). The player's
## hero is stood on the opponent's tile while the battle is prepared, so the
## arena and the battleground scripts are those of a hero that walked there,
## and the chapter's Hook_OnPreUse is called for the pair first, as the map
## does when the hero attacks (several boss scripts read a count that hook
## sets: without it they fail on their first turn). What the hook answers is
## noted (preuse=refused: on the map the attack would not have gone on) but
## the battle is played all the same; --no-preuse leaves the hook out.
## Second game: creatures a chapter's script only brings in later (templates
## of the map no placed figure uses, the Musician of chapter 13 among them)
## are created next to the hero and met the same way (kind "made").
## Battles that differ in nothing but the figure's place (same template,
## level, life, book, scripts) are played once unless --all is given.
##
##   godot --headless --path game --script ../tools/campaign_battles_check.gd -- \
##       [--game=el2|el1] [--shard=I/N] [--only=TEXT] [--chapter=TEXT] [--limit=N] [--all] [--list]
##       [--difficulty=N] [--seed=N] [--rounds=N] [--seconds=N] [--ai=smart|orig|easy]
##       [--player=smart|orig|easy] [--per-chapter=N] [--set=name=value,...] [--path=copy|direct]
##       [--no-scripts] [--no-preuse] [--var=name=number,...] [--verbose]
##
## --only=TEXT keeps the battles whose label (campaign/row, map, script, the
## opponent's id and name) contains TEXT, e.g. --only=Green/3, --only=mission13c
## or --only=#1234; --chapter=TEXT opens only the chapters whose label
## (campaign/row, map, script) contains TEXT, e.g. --chapter=Green/1
## --only=#25022 for one battle without opening the others; --limit=N plays the first N of the shard; --per-chapter=N
## at most N battles of a chapter (a sample across chapters); --list only
## prints the battles. --set overrides ELCombatSearch's `smart_*` variables
## (the prefix left out), e.g. --set=engine_ms=300 for a quicker pass over
## every battle; without it the opponent thinks as shipped. --ai sets the computer side's player, --player the
## player's side (both "smart" by default).
##
## Each decision is thought out as the battle screen has it thought out: on
## a lookahead copy of the duel with the decision's request (what
## ELPracticeAI.step hands its worker thread), then sent with
## ELPracticeAI.send. --path=direct calls ELPracticeAI.step instead, which
## for a duel not on screen thinks on the duel itself (the path of the
## benchmarks and of the strategic relay's neutral side).
##
## --var sets mission variables before each battle is prepared: several boss
## scripts read a count the chapter's own script only sets later in the
## chapter (e.g. --var=Adv_HopperCount=3), and fail on it at the chapter's
## start. --no-scripts plays the same battles with their battle scripts left out
## (a comparison run: what the scripts change in the opponent's play).
##
## One BATTLE line per battle: the chapter, the opponent, who won, how it
## ended (won, rounds: the round cap, time: the time cap, stuck: nothing was
## accepted for a long while), rounds, accepted commands, thinks, the longest
## and mean decision in ms, how the commands were found (ELCombatSearch.think's
## "engine"), commands the rules refused, steps with no command, phases cut
## off at PHASE_CAP commands, decisions more than half a second past the think
## limit (ELCombatSearch.engine_ms(); "late"), commands that only led back to a position
## already seen (ELPracticeAI.cycles), what the battle scripts did (events
## they raised, their notes), the errors and warnings the engine logged
## during the battle, and for the Musician the dragons its script called.
## TOTAL lines and the decision times' percentiles close the run; DECISIONS
## lists every decision's ms for pooling shards.
##
## Needs the player's game files (user://profiles.json or --el1=/--el2=).

const PHASE_CAP := 80
const DRAGONS := ["BLDG", "GRDG", "RDDG", "BUDG"]
const DRAGON_SCRIPT := "e2mission13cdragonboss"
const LETTER := {"Red": "R", "Green": "G", "Black": "B", "Blue": "U"}

## Errors and warnings the engine logs (script errors, push_warning), kept
## per battle. A think may log from a worker thread.
class Catcher extends Logger:
	var lock := Mutex.new()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	## Errors of the engine itself (in a headless run mostly the stand-in
	## renderer's), counted apart from the scripts' errors.
	var engine: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		var text := "%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function]
		lock.lock()
		if error_type == Logger.ERROR_TYPE_WARNING: warnings.append(text)
		elif error_type == Logger.ERROR_TYPE_SCRIPT: errors.append(text)
		else: engine.append(text)
		lock.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func take() -> Array:
		lock.lock()
		var result := [errors.duplicate(), warnings.duplicate(), engine.duplicate()]
		errors.clear()
		warnings.clear()
		engine.clear()
		lock.unlock()
		return result

var profile: ELProfile
var game := "el2"
var catcher := Catcher.new()
var verbose := false
var decisions := PackedInt32Array()
var totals := {"battles": 0, "won_player": 0, "won_enemy": 0, "no_winner": 0, "rounds_cap": 0, "time_cap": 0, "stuck": 0, "not_built": 0, "scripted": 0,
	"commands": 0, "thinks": 0, "refused": 0, "empty": 0, "recovered": 0, "phase_cap": 0, "late": 0, "cycles": 0, "script_events": 0, "script_notes": 0,
	"scripted_battles": 0, "errors": 0, "warnings": 0, "dragon_battles": 0, "dragon_failures": 0, "chapters": 0, "chapters_failed": 0}
var engines := {}
## Decisions taken on a model that left something out, and what, by name.
var incomplete := 0
var reasons := {}
var anomalies: Array[String] = []

func _arg(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="): return arg.substr(name.length() + 3)
		if arg == "--" + name: return "1"
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = _arg("game", "el2")
	verbose = _arg("verbose", "") == "1"
	var folder := _arg(game, "")
	if folder.is_empty() and FileAccess.file_exists("user://profiles.json"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json"))
		if saved is Dictionary: folder = String(saved.get(game, ""))
	profile = ELProfile.new()
	if folder.is_empty() or not profile.mount(game, folder):
		printerr("Game files are required: pass --%s=<folder>" % game)
		quit(1)
		return
	for item: String in _arg("set", "").split(",", false):
		var name := "smart_" + item.get_slice("=", 0)
		if not (ELCombatSearch as Script).source_code.contains("static var %s " % name) and not (ELCombatSearch as Script).source_code.contains("static var %s:" % name):
			printerr("Unknown setting: " + name)
			quit(1)
			return
		(ELCombatSearch as Script).set(name, str_to_var(item.get_slice("=", 1)))
	OS.add_logger(catcher)
	print("ENGINE compiled=%s game=%s ai=%s player=%s difficulty=%s think_ms=%d set=%s path=%s" % [str(ELCombatBrain.available), game, _arg("ai", "smart"), _arg("player", "smart"), _arg("difficulty", "1"), ELCombatSearch.smart_engine_ms, _arg("set", "-"), _arg("path", "copy")])
	var shard := _arg("shard", "0/1")
	var only := _arg("only", "").to_lower()
	var limit := int(_arg("limit", "0"))
	var per_chapter := int(_arg("per-chapter", "0"))
	var listing := _arg("list", "") == "1"
	var counter := 0
	var played := 0
	var began := Time.get_ticks_msec()
	for campaign_id: String in ELCampaign.available(profile):
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, campaign_id):
			print("CHAPTER %s: campaign does not load (%s)" % [campaign_id, campaign.error])
			totals.chapters_failed += 1
			continue
		for row in campaign.scenarios.size():
			var scenario: Dictionary = campaign.scenarios[row]
			var label := "%s/%d map=%s script=%s" % [campaign_id, row, str(scenario.file_name), str(scenario.get("script", ""))]
			# A chapter no battle of which is wanted is not opened: --only by
			# chapter, and shards share the chapters when nothing narrower is asked.
			if not _arg("chapter", "").is_empty() and not label.to_lower().contains(_arg("chapter", "").to_lower()): continue
			if not only.is_empty() and not only.begins_with("#") and not label.to_lower().contains(only) and not _names_filter(only): continue
			var opened := _open(campaign_id, row, scenario)
			if opened.is_empty():
				totals.chapters_failed += 1
				continue
			totals.chapters += 1
			var state: ELAdventureSession = opened[0]
			var hero := int(opened[2])
			var in_chapter := 0
			for target: Dictionary in _encounters(state, hero):
				var item := state.object(int(target.id))
				var name := "%s #%d %s" % [label, int(target.id), str(item.get("name", "?"))]
				if not only.is_empty() and not name.to_lower().contains(only): continue
				counter += 1
				if (counter - 1) % int(shard.get_slice("/", 1)) != int(shard.get_slice("/", 0)): continue
				if per_chapter > 0 and in_chapter >= per_chapter: continue
				if limit > 0 and played >= limit: continue
				in_chapter += 1
				played += 1
				if listing:
					print("ENCOUNTER %s kind=%s type=%s level=%d life=%d cards=%d script=%s" % [name, target.kind, str(item.get("type")), int(item.get("level", 0)), int(item.get("health", 0)), Array(item.get("cards", [])).size(), str(item.get("battle_script", ""))])
					continue
				_battle(state, hero, int(target.id), str(target.kind), name)
			state.close()
			opened.clear()
	_report(Time.get_ticks_msec() - began)
	ELPracticeAI.finish()
	quit(1 if totals.errors > 0 or totals.dragon_failures > 0 or totals.stuck > 0 else 0)

## Whether `only` may name an opponent instead of a chapter (a chapter filter
## has a slash or names a map or script).
func _names_filter(only: String) -> bool:
	return not only.contains("/") and not only.contains("mission") and not only.contains("map=") and not only.contains("script=")

## Opens a chapter as the campaign does: [session, director, the player's hero].
func _open(campaign_id: String, row: int, scenario: Dictionary) -> Array:
	var label := "%s/%d %s %s" % [campaign_id, row, str(scenario.file_name), str(scenario.get("script", ""))]
	var map := ELAdventureMap.new()
	if not map.load_map(profile, str(scenario.file_name)):
		print("CHAPTER %s: map does not load (%s)" % [label, map.error])
		return []
	var state := ELAdventureSession.new()
	if not state.start(map, int(_arg("difficulty", "1")), 212, str(scenario.get("script", "")), int(str(scenario.get("player", "1"))), true):
		print("CHAPTER %s: does not start (%s)" % [label, state.error])
		return []
	var director := ELAdventureDirector.new()
	if not director.build(state):
		print("CHAPTER %s: director does not build (%s)" % [label, director.error])
		state.close()
		return []
	if game == "el2":
		var progress := ELSecondCampaign.for_chapter(profile, campaign_id, scenario, int(_arg("difficulty", "1")))
		if not progress.is_empty(): ELSecondCampaign.start_chapter(state, progress)
	# Past the opening dialogue and whatever the script sets up on its first steps.
	var began := Time.get_ticks_msec()
	for frame in 400:
		director.advance(0.05)
		if not director.dialogue.is_empty(): director.acknowledge("OK")
		elif frame > 5 and director.can_move(): break
		if director.encounter != null or Time.get_ticks_msec() - began > 15000: break
	var hero := int(state.main_hero) if game == "el2" else -1
	if hero < 0 or not state.object(hero).get("alive", false):
		hero = -1
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) == state.current_player and not Array(item.get("cards", [])).is_empty():
				if hero < 0 or int(item.uid) < hero: hero = int(item.uid)
	var logged := catcher.take()
	var faults: Array = logged[0]
	if hero < 0:
		print("CHAPTER %s: no hero of the player to fight with (error: %s)" % [label, state.error])
		state.close()
		return []
	var own := state.object(hero)
	var lent := _lend(own, campaign_id, row)
	print("CHAPTER %s: hero #%d %s level %d life %d cards %d%s; %d objects%s" % [label, hero, str(own.get("name", "?")), int(own.get("level", 0)), int(own.get("health", 0)), Array(own.get("cards", [])).size(), lent, state.objects.size(),
		"" if faults.is_empty() else "; %d errors while opening, first: %s" % [faults.size(), faults[0]]])
	return [state, director, hero]

## A chapter opened by itself has no book carried from the chapter before
## it, and in the second game no level either where the map leaves the
## carried one (level one in a late chapter): such a hero is lent the level
## the Green chapters author for their row (1, 4, 7, 10; the White campaign
## starts again at its second chapter) with the life that goes with it, and
## the preset book of its colour for its level (the starter below level
## four), failing that the colour's sixteen cheapest spells. Returns a note
## for the chapter line. --no-lend leaves the hero as the map has it.
func _lend(own: Dictionary, campaign_id: String, row: int) -> String:
	if not Array(own.get("cards", [])).is_empty() or _arg("no-lend", "") == "1": return ""
	var raised := ""
	if game == "el2" and int(own.get("level", 1)) <= 1:
		var level := 1 + 3 * (row - 1 if campaign_id == "White" else row)
		if level > 1:
			own.level = level
			own.health = 10 + 3 * (level - 1)
			raised = "lent level %d and life %d, " % [level, int(own.health)]
	var looks: Dictionary = profile.table("Shapes").get(own.get("shape", ""), {}) if not str(own.get("shape", "")).is_empty() else profile.table("HeroTemplates").get(own.get("name", ""), {})
	var colour := str(looks.get("Color", ""))
	var names: Array[String] = []
	if LETTER.has(colour):
		var level := int(own.get("level", 1))
		if level >= 4: names.append("PR%s%d" % [LETTER[colour], clampi(level / 2, 2, 6)])
		names.append(str(ELCatalog.STARTERS.get(colour, "")))
	for name: String in names:
		var cards := ELCatalog.deck(profile, name)
		if cards.is_empty(): continue
		own.cards = Array(cards)
		return " (%slent book %s)" % [raised, name]
	var cheapest := ELCatalog.available_cards(profile, colour).slice(0, 16)
	if cheapest.is_empty(): return " (%sno book to lend for colour '%s')" % [raised, colour]
	own.cards = Array(cheapest)
	return " (%slent the %d cheapest %s spells)" % [raised, cheapest.size(), colour]

## The opponents of the chapter, in id order: {id, kind}. "placed" figures
## stand on the map; "made" ones are created from a template no placed figure
## uses (second game).
func _encounters(state: ELAdventureSession, hero: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var own := state.object(hero)
	var seen := {}
	var used := {}
	var ids: Array = state.objects.keys()
	ids.sort()
	var everything := _arg("all", "") == "1"
	for id: int in ids:
		var item := state.object(id)
		if item.get("type") not in ["hero", "monster"]: continue
		used[str(item.get("name", ""))] = true
		if id == hero or not item.get("alive", false) or not state.hostile(own, item): continue
		if game == "el2" and int(item.get("owner", -1)) == 1: continue
		var key := [str(item.get("name", "")), int(item.get("level", 0)), int(item.get("health", 0)), item.get("cards", []), str(item.get("battle_script", "")), str(item.get("type", ""))].hash()
		if seen.has(key) and not everything: continue
		seen[key] = true
		result.append({"id": id, "kind": "placed"})
	if game == "el2":
		var templates: Array = state.map.mobs.keys()
		templates.sort()
		for template: String in templates:
			if used.has(template) or template == str(own.get("name", "")): continue
			var made := state.create_hero(0, template, int(own.get("x", 0)), int(own.get("y", 0)), false)
			if made < 0:
				if state.vm != null: state.vm.error = ""
				continue
			var item := state.object(made)
			if Array(item.get("cards", [])).is_empty() or not state.hostile(own, item): continue
			result.append({"id": made, "kind": "made"})
	return result

func _settings(kind: String) -> Dictionary:
	return {"smart": kind not in ["orig", "easy"], "easy": kind == "easy"}

func _battle(state: ELAdventureSession, hero: int, opponent: int, kind: String, label: String) -> void:
	totals.battles += 1
	var own := state.object(hero)
	var other := state.object(opponent)
	# The hero meets the opponent where it stands.
	var kept := [own.get("x"), own.get("y")]
	if kind == "placed" and int(other.get("x", -1)) >= 0:
		own.x = other.x
		own.y = other.y
	for item: String in _arg("var", "").split(",", false):
		state.set_variable(item.get_slice("=", 0), float(item.get_slice("=", 1)))
	seed([int(_arg("seed", "1")), label].hash())
	var preuse := "-"
	if state.vm != null and _arg("no-preuse", "") != "1" and state.vm.has_function("Hook_OnPreUse"):
		var answer := state.vm.invoke("Hook_OnPreUse", [float(opponent), float(hero)])
		if not state.vm.error.is_empty():
			preuse = "error(%s)" % state.vm.error
			state.vm.error = ""
		else: preuse = "refused" if not answer.is_empty() and not ELAdventureSession._truthy_flag(answer[0]) else "ok"
		# What the hook queued for the map (talk, camera) is not played here.
		state.commands.clear()
		if not state.object(hero).get("alive", false) or not state.object(opponent).get("alive", false):
			totals.not_built += 1
			print("BATTLE %s: NOT BUILT (the chapter's Hook_OnPreUse removed a side)" % label)
			return
	var encounter := ELAdventureEncounter.new()
	var ok := encounter.prepare(state, hero, opponent)
	own.x = kept[0]
	own.y = kept[1]
	if not ok or encounter.battle == null:
		if ok and encounter.scripted_winner >= 0:
			totals.scripted += 1
			print("BATTLE %s: decided by the chapter's script (winner #%d), no duel" % [label, encounter.scripted_winner])
		else:
			totals.not_built += 1
			var text := "BATTLE %s: NOT BUILT (%s)" % [label, encounter.error]
			print(text)
			anomalies.append(text)
		if state.vm != null: state.vm.error = ""
		catcher.take()
		return
	var duel := encounter.battle
	if _arg("no-scripts", "") == "1" and duel.setup.has("scripts"):
		var plain: Dictionary = duel.setup.duplicate(true)
		plain.erase("scripts")
		if duel.scripts != null: duel.scripts.close()
		duel = ELDuel.new()
		if not duel.start(profile, [int(_arg("seed", "1")), label].hash() & 0x7fff, plain):
			print("BATTLE %s: NOT BUILT without its scripts (%s)" % [label, duel.error])
			return
	var player_side := 0 if encounter.hero_id == hero else 1
	var scripts: Array = duel.setup.get("scripts", [])
	var script_names: Array[String] = []
	var dragon_side := -1
	for entry: Dictionary in scripts:
		script_names.append("%s@%d" % [str(entry.name).get_file(), int(entry.side)])
		if str(entry.name).to_lower().contains(DRAGON_SCRIPT): dragon_side = int(entry.side)
	var loaded := duel.scripts.states.size() if duel.scripts != null else 0
	# --hooks=1: the hooks each loaded script answers, one HOOKS line a battle.
	if _arg("hooks", "") == "1" and duel.scripts != null:
		var told: Array[String] = []
		for layer: Dictionary in duel.scripts.states: told.append("%s@%d:%s" % [str(layer.name).get_file(), int(layer.side), ",".join((layer.hooks as Dictionary).keys())])
		print("HOOKS %s %s" % [label, " | ".join(told)])
	var script_events := {}
	var watch := func(data: Dictionary) -> void:
		var what := str(data.get("kind", ""))
		if what.begins_with("script_") or bool(data.get("script", false)):
			var name := what if what.begins_with("script_") else "script:" + what
			script_events[name] = int(script_events.get(name, 0)) + 1
	duel.event.connect(watch)
	var sides := [_settings(_arg("player", "smart")), _settings(_arg("ai", "smart"))]
	if player_side == 1: sides.reverse()
	var round_cap := int(_arg("rounds", "60"))
	var time_cap := float(_arg("seconds", "240")) * 1000.0
	var refused := ELPracticeAI.refused
	var empty := ELPracticeAI.empty
	var recovered := ELPracticeAI.recovered
	var cycles := ELPracticeAI.cycles
	var found := {}
	var thinks := 0
	var longest := 0
	var total_ms := 0
	var capped := 0
	var late := 0
	var late_limit := ELCombatSearch.engine_ms() + 500 if ELCombatSearch.engine_ms() > 0 else 0
	var commands := 0
	var mark: Array = []
	var recent: Array = []
	var dragons := _count(duel, dragon_side)
	var idle := 0
	var serial := duel.accepted_serial
	var ended := "won"
	var direct := _arg("path", "copy") == "direct"
	var began := Time.get_ticks_msec()
	ELCombatSearch.reset_caches()
	while duel.phase != ELDuel.Phase.FINISHED:
		if duel.round_number > round_cap:
			ended = "rounds"
			break
		if float(Time.get_ticks_msec() - began) > time_cap:
			ended = "time"
			break
		var side := duel.active_side()
		var here := [duel.turn_serial, duel.phase, side]
		if here != mark:
			mark = here
			commands = 0
			recent.clear()
		commands += 1
		if commands > PHASE_CAP:
			capped += 1
			print("    phase cap: round %d, side %d, %s phase; the last commands: %s" % [duel.round_number, side, "attack" if duel.phase == ELDuel.Phase.ATTACK else "defence", str(recent)])
			duel.end_phase()
			continue
		var settings: Dictionary = sides[side]
		var smart: Array[int] = []
		if settings.smart: smart.append(side)
		duel.smart_sides = smart
		ELCombatSearch.original_budget = ELCombatSearch.EASY_BUDGET if settings.easy else ELCombatSearch.BUDGET
		var before := duel.accepted_serial
		var position := ELCombatSearch._position(duel)
		var started := Time.get_ticks_usec()
		var decision := {}
		if direct:
			ELPracticeAI.step(duel)
			decision = ELPracticeAI.last_decision
		else:
			ELCombatBrain.prepare(duel)
			var asked := ELCombatSearch.request(duel)
			var copy := duel.search_copy()
			var stats := {}
			var command := ELCombatSearch.think(copy, stats, false, asked)
			if copy.scripts != null and copy.scripts.search_only: copy.scripts.close()
			decision = {"command": command, "engine": String(stats.get("engine", "")), "stages": stats.get("stages", {}), "crowding": stats.get("crowding", [])}
			ELPracticeAI.send(duel, command, false, asked)
		var spent := int((Time.get_ticks_usec() - started) / 1000)
		thinks += 1
		total_ms += spent
		longest = maxi(longest, spent)
		if late_limit > 0 and spent > late_limit:
			late += 1
			if verbose or late == 1: print("    late: round %d side %d took %d ms (limit of one think %d ms) for %s by %s, stages (usec) %s" % [duel.round_number, side, spent, ELCombatSearch.smart_engine_ms, str(decision.get("command", {})), str(decision.get("engine", "")), str(decision.get("stages", {}))])
		decisions.append(spent)
		var engine := String(decision.get("engine", "?"))
		if engine.is_empty(): engine = "?"
		found[engine] = int(found.get(engine, 0)) + 1
		engines[engine] = int(engines.get(engine, 0)) + 1
		# What the model left out of the position decided on, by reason.
		var left_out: Array = decision.get("crowding", [])
		if not left_out.is_empty(): incomplete += 1
		for reason: String in left_out: reasons[reason.rstrip("01")] = int(reasons.get(reason.rstrip("01"), 0)) + 1
		if verbose: print("    r%d side%d %s %s %d ms" % [duel.round_number, side, engine, str(decision.get("command", {})), spent])
		var sent: Dictionary = decision.get("command", {})
		recent.append("%s:%s" % [engine, _brief(duel, sent)])
		if recent.size() > 12: recent.pop_front()
		dragons = maxi(dragons, _count(duel, dragon_side))
		# A step that changes nothing at all, many times over, is a stall.
		if duel.accepted_serial == before and duel.phase != ELDuel.Phase.FINISHED and ELCombatSearch._position(duel) == position:
			idle += 1
			if idle > 50:
				ended = "stuck"
				break
		else: idle = 0
	var spent_ms := Time.get_ticks_msec() - began
	duel.event.disconnect(watch)
	var notes: Array = duel.scripts.notes.duplicate() if duel.scripts != null else []
	var logged := catcher.take()
	var faults: Array = logged[0]
	var warned: Array = logged[1]
	var engine_faults: Array = logged[2]
	var winner := "none"
	if duel.phase == ELDuel.Phase.FINISHED and duel.winner >= 0: winner = "player" if duel.winner == player_side else "enemy"
	var events := 0
	for name: String in script_events: events += int(script_events[name])
	var d_refused := ELPracticeAI.refused - refused
	var d_empty := ELPracticeAI.empty - empty
	var d_cycles := ELPracticeAI.cycles - cycles
	var text := "BATTLE %s kind=%s preuse=%s L%d/%d vs L%d/%d %s arena=%s first=%s seed=%d winner=%s ended=%s rounds=%d commands=%d thinks=%d max_ms=%d mean_ms=%.1f wall_s=%.1f engines=%s late=%d refused=%d empty=%d recovered=%d phase_cap=%d cycles=%d scripts=%s loaded=%d script_events=%d%s notes=%d errors=%d engine_errors=%d warnings=%d" % [
		label, kind, preuse, int(duel.heroes[player_side].level), int(own.get("health", 0)), int(duel.heroes[1 - player_side].level), int(other.get("health", 0)), str(other.get("type", "")),
		str(duel.setup.get("arena", "")), "player" if int(duel.setup.get("first_side", 0)) == player_side else "enemy", int(_arg("seed", "1")),
		winner, ended, duel.round_number, duel.accepted_serial - serial, thinks, longest, float(total_ms) / maxf(1.0, float(thinks)), float(spent_ms) / 1000.0, str(found),
		late, d_refused, d_empty, ELPracticeAI.recovered - recovered, capped, d_cycles, str(script_names), loaded, events, "" if script_events.is_empty() else str(script_events), notes.size(), faults.size(), engine_faults.size(), warned.size()]
	# Battle scripts that shape a creature as it is summoned (the one hook a
	# lookahead runs), and the creatures still in play that one shaped.
	var summon_hooks := 0
	if duel.scripts != null:
		for layer: Dictionary in duel.scripts.states:
			if (layer.hooks as Dictionary).has("CHook_OnLogicSummon"): summon_hooks += 1
	var shaped := 0
	for c: Dictionary in duel.creatures.values():
		if c.get("script_base", false): shaped += 1
	text += " summon_hooks=%d shaped=%d" % [summon_hooks, shaped]
	var odd: Array[String] = []
	if dragon_side >= 0:
		totals.dragon_battles += 1
		text += " dragons=%d" % dragons
		if dragons < 4:
			totals.dragon_failures += 1
			odd.append("the Musician's four dragons did not appear (%d)" % dragons)
	if scripts.size() > 0: totals.scripted_battles += 1
	if loaded < scripts.size(): odd.append("%d of %d battle scripts loaded" % [loaded, scripts.size()])
	if ended != "won": odd.append("ended by the %s cap" % ended if ended != "stuck" else "stuck: steps changed nothing")
	elif winner == "none": odd.append("finished with no winner")
	if d_refused > 0: odd.append("%d refused commands" % d_refused)
	if d_empty > 0: odd.append("%d steps with no command" % d_empty)
	if capped > 0: odd.append("%d phase caps" % capped)
	if late > 0: odd.append("%d decisions well past the think limit (longest %d ms)" % [late, longest])
	if d_cycles > 0: odd.append("%d commands led back" % d_cycles)
	if not notes.is_empty(): odd.append("script notes: " + " | ".join(notes.slice(0, 3)))
	if not faults.is_empty(): odd.append("script errors: " + " | ".join(faults.slice(0, 3)))
	if not engine_faults.is_empty(): odd.append("engine errors: " + " | ".join(engine_faults.slice(0, 3)))
	if not warned.is_empty(): odd.append("warnings: " + " | ".join(warned.slice(0, 3)))
	print(text)
	if not odd.is_empty():
		var line := "ANOMALY %s: %s" % [label, "; ".join(odd)]
		print(line)
		anomalies.append(line)
	match ended:
		"rounds": totals.rounds_cap += 1
		"time": totals.time_cap += 1
		"stuck": totals.stuck += 1
		_:
			if winner == "player": totals.won_player += 1
			elif winner == "enemy": totals.won_enemy += 1
			else: totals.no_winner += 1
	totals.commands += duel.accepted_serial - serial
	totals.thinks += thinks
	totals.refused += d_refused
	totals.empty += d_empty
	totals.recovered += ELPracticeAI.recovered - recovered
	totals.phase_cap += capped
	totals.late += late
	totals.cycles += d_cycles
	totals.script_events += events
	totals.script_notes += notes.size()
	totals.errors += faults.size() + engine_faults.size()
	totals.warnings += warned.size()
	if duel.scripts != null: duel.scripts.close()
	encounter.battle = null
	if state.vm != null: state.vm.error = ""
	state.error = ""

## A command in a few words, cards named by their code.
func _brief(duel: ELDuel, command: Dictionary) -> String:
	match String(command.get("kind", "")):
		"cast": return "cast %s>%d" % [str(command.get("card", command.get("index", "?"))), int(command.get("target", -1))]
		"attack": return "attack #%d" % int(command.id)
		"block": return "block #%d>#%d" % [int(command.id), int(command.target)]
		"ability": return "ability %s of #%d>%d" % [str(command.key), int(command.id), int(command.get("target", -1))]
		"end_phase": return "end"
	return str(command)

## The script side's dragons on the field.
func _count(duel: ELDuel, side: int) -> int:
	if side < 0: return 0
	var count := 0
	for id: int in duel.creatures:
		if int(duel.creatures[id].owner) == side and String(duel.creatures[id].card) in DRAGONS: count += 1
	return count

func _percentile(sorted: Array, q: float) -> int:
	if sorted.is_empty(): return 0
	return int(sorted[clampi(int(ceil(q * float(sorted.size()))) - 1, 0, sorted.size() - 1)])

func _report(spent: int) -> void:
	print("TOTAL game=%s shard=%s chapters=%d chapters_failed=%d battles=%d won_player=%d won_enemy=%d no_winner=%d rounds_cap=%d time_cap=%d stuck=%d not_built=%d scripted_result=%d" % [game, _arg("shard", "0/1"),
		totals.chapters, totals.chapters_failed, totals.battles, totals.won_player, totals.won_enemy, totals.no_winner, totals.rounds_cap, totals.time_cap, totals.stuck, totals.not_built, totals.scripted])
	print("TOTAL commands=%d thinks=%d refused=%d empty=%d recovered=%d phase_cap=%d late=%d cycles=%d battles_with_scripts=%d script_events=%d script_notes=%d dragon_battles=%d dragon_failures=%d errors=%d warnings=%d wall_s=%d" % [
		totals.commands, totals.thinks, totals.refused, totals.empty, totals.recovered, totals.phase_cap, totals.late, totals.cycles, totals.scripted_battles, totals.script_events, totals.script_notes,
		totals.dragon_battles, totals.dragon_failures, totals.errors, totals.warnings, spent / 1000])
	print("TOTAL engines=%s" % str(engines))
	print("MODEL decisions=%d incomplete=%d reasons=%s" % [totals.thinks, incomplete, str(reasons)])
	var sorted: Array = Array(decisions)
	sorted.sort()
	print("LATENCY decisions=%d p50=%d ms p95=%d ms p99=%d ms max=%d ms" % [sorted.size(), _percentile(sorted, 0.5), _percentile(sorted, 0.95), _percentile(sorted, 0.99), int(sorted[-1]) if not sorted.is_empty() else 0])
	print("DECISIONS %s" % ",".join(sorted.map(func(t: int) -> String: return str(t))))
	print("ANOMALIES %d" % anomalies.size())
