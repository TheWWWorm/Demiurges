extends SceneTree
## Plays a first-game single map with the local player standing still (or
## played by the original computer rules) and prints what the computer
## players do with their days: tasks, purchases at spell shops and component
## portals, skills, recruits and global spells, and how well they plan.
##
##   godot --headless --path game --script ../tools/first_ai_sim.gd -- [--map=<id>|all] [--days=40]
##         [--campaign=Good|Evil] [--smart=true] [--free=true] [--difficulty=1] [--seed=212]
##         [--opponent=still|active] [--estimate=false] [--fight-monsters=false] [--lookahead=true] [--living=false]
##         [--list] [--quiet] [--dump] [--balance] [--random=<preset>[,<preset>...] [--map-seed=212]]
##
## `--list` prints the single map ids. Without `--map` the first catalogue map
## with a spell shop is played; `--campaign` plays that campaign's chapters
## (all of them, or the one named by `--map`) from the human's seat. `--seed`
## seeds the session's random numbers. `--opponent=active` has the human's
## seat planned by the original computer rules (without the remake option),
## as a baseline opponent; by default it stands still and its battles go to
## the attacker. `--estimate` decides strategic battles by the strength
## estimate instead of the original level rule. `--lookahead=false` turns
## off the smarter planner's short lookahead, `--living=true` turns on the
## living-world switch (patrols, raids, escorts, retreats, doctrines). `--dump` adds each player's
## ether, global spells, books and known shops at the end. `--balance` adds
## first resource-site capture, planning counters and forecast versus duel
## outcome as one JSON line per faction or battle. `--random` plays a generated
## world from each named random-map preset (current generator, seed
## `--map-seed`) instead of a stock map.
##
## Each computer player's summary counts, per hero and day:
##   idle         no objective at the end of the day;
##   no progress  neither a step nor an action on the spot (a capture,
##                a purchase, a visit, a battle won);
##   stalled      an objective, no step, and not beside its target;
## and also unused movement (points left at night, share of the day's
## movement), lost objectives (objective-days: valid castles, sites,
## creatures and usable buildings neither open nor held), route-rule
## breaches (steps onto tiles the player had not explored, steps into a guard
## area other than the order's target), castle threats (an enemy hero
## within 12 tiles of the castle) and the days until a hero of the player
## came within 4 tiles of it, income, and planning passes and time.
##
## The run ends with a summary per computer player and exits 1 when a map
## stops with an error or a turn never settles.
##
## It needs the first game's files (user://profiles.json, as set up by the
## game); without them it is skipped. Nothing is saved.

var director: ELAdventureDirector
var state: ELAdventureSession
var quiet := false
var stats := {}
var stuck := false
var active := false
var explored_before := PackedByteArray()
var threats := {}
var recruits := {}
var turn_number := 0

func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.trim_prefix("--%s=" % name)
		if arg == "--" + name: return "true"
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var paths: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profiles.json")) if FileAccess.file_exists("user://profiles.json") else null
	if paths is not Dictionary or not paths.has("el1"):
		print("SKIP: no first-game files configured (user://profiles.json)")
		quit(0)
		return
	var profile := ELProfile.new()
	if not profile.mount("el1", str(paths.el1)):
		print("SKIP: the first game's files could not be mounted")
		quit(0)
		return
	quiet = _arg("quiet", "false") == "true"
	active = _arg("opponent", "still") == "active"
	var catalog := ELSingleScenario.catalog(profile)
	if _arg("list", "false") == "true":
		for entry: Dictionary in catalog: print("%s  %s  players=%s" % [entry.id, ELSingleScenario.title(profile, entry), str(entry.get("players", []).size())])
		quit(0)
		return
	var wanted := _arg("map", "")
	var failed := false
	if not _arg("random", "").is_empty():
		for preset: String in _arg("random", "").split(","):
			for map_seed: String in _arg("map-seed", "212").split(","):
				if _play(profile, {"id": "random:%s:%s" % [preset, map_seed], "random": preset, "map_seed": map_seed}, int(_arg("days", "40")), false) == "fail": failed = true
		quit(1 if failed else 0)
		return
	var chapters := _arg("campaign", "")
	if not chapters.is_empty():
		# Campaign chapters ("Good", "Evil"...): the human's seat and the chapter rules.
		var campaign := ELCampaign.new()
		if not campaign.load_campaign(profile, chapters):
			print("SKIP: " + campaign.error)
			quit(0)
			return
		for row: Dictionary in campaign.scenarios:
			if not wanted.is_empty() and wanted != "all" and str(row.file_name) != wanted: continue
			var entry := {"id": str(row.file_name), "title": str(row.get("header", "")), "script": str(row.get("script", "")), "player": int(str(row.get("player", "1"))), "campaign": row.has("number")}
			if _play(profile, entry, int(_arg("days", "40")), false) == "fail": failed = true
		quit(1 if failed else 0)
		return
	for entry: Dictionary in catalog:
		if not wanted.is_empty() and wanted != "all" and str(entry.id) != wanted: continue
		var result := _play(profile, entry, int(_arg("days", "40")), wanted.is_empty())
		if result == "skip": continue
		if result == "fail": failed = true
		if wanted != "all": break
	quit(1 if failed else 0)

func _stat(player: int) -> Dictionary:
	if not stats.has(player): stats[player] = {"spells": 0, "runes": 0, "skills": 0, "recruits": 0, "globals": 0, "visits": 0, "idle": 0, "hero_days": 0, "kills": 0,
		"no_progress": 0, "stalled": 0, "ap_left": 0, "ap_total": 0, "lost": 0, "unexplored_steps": 0, "guard_steps": 0, "threats": 0, "answered": 0, "response_days": 0, "castles": 0, "duplicates": 0}
	return stats[player]

func _play(profile: ELProfile, entry: Dictionary, days: int, need_shop: bool) -> String:
	seed(int(_arg("seed", "212")))
	var map := ELAdventureMap.new()
	if entry.has("random"):
		var options := {}
		for preset: Dictionary in ELFirstRandomMap.presets():
			if preset.id == entry.random: options = ELFirstRandomMap.defaults().merged(preset.options, true)
		if options.is_empty():
			print("SKIP %s: unknown random-map preset" % entry.id)
			return "skip"
		options.seed = str(entry.map_seed)
		var generator := ELFirstRandomMap.new()
		map = generator.generate(profile, options)
		if map == null:
			print("FAIL %s: %s" % [entry.id, generator.error])
			return "fail"
	elif not map.load_map(profile, str(entry.id)):
		print("SKIP %s: %s" % [entry.id, map.error])
		return "skip"
	state = ELAdventureSession.new()
	if not state.start(map, int(_arg("difficulty", "1")), int(_arg("seed", "212")), str(entry.get("script", "")), int(entry.get("player", 1)), bool(entry.get("campaign", false))):
		print("SKIP %s: %s" % [entry.id, state.error])
		return "skip"
	director = ELAdventureDirector.new()
	if not director.build(state):
		print("SKIP %s: %s" % [entry.id, director.error])
		return "skip"
	var shops := 0
	var portals := 0
	for item: Dictionary in state.objects.values():
		if item.get("type") == "el1_spell_shop": shops += 1
		if item.get("type") == "rune_shop": portals += 1
	if need_shop and shops == 0: return "skip"
	director.smart_ai = _arg("smart", "true") == "true"
	director.fight_neutral_monsters = _arg("fight-monsters", "false") == "true"
	director.free_movement = _arg("free", "true") == "true"
	if "battle_estimate" in director: director.set("battle_estimate", _arg("estimate", "false") == "true")
	if "living_world" in director: director.set("living_world", _arg("living", "false") == "true")
	var planner: Script = load("res://src/content/first_ai_planner.gd") if ResourceLoader.exists("res://src/content/first_ai_planner.gd") else null
	if planner != null and "lookahead" in planner: planner.set("lookahead", _arg("lookahead", "true") == "true")
	director.fast_mode = true
	director.set_meta("first_ai_stats", {})
	var balance := _arg("balance", "false") == "true"
	if balance: director.set_meta("first_ai_balance", true)
	if _arg("confirm-replays", "false") == "true": director.set_meta("first_ai_replay", true)
	var capture := {}
	var participants: Array[int] = ELFirstAI.computer_players(state) if balance else ([] as Array[int])
	var timeline := {"turn": 0, "dawn": {}, "acted": {}}
	stats = {}
	threats = {}
	recruits = {}
	stuck = false
	var books := {}
	var fell := {}
	state.event.connect(func(data: Dictionary):
		match data.get("kind"):
			"site_captured":
				timeline.acted[int(data.get("hero", -1))] = true
				var player := int(data.player)
				if balance and player in participants and not capture.has(player) and state.object(data.id).get("group") in ["mines", "mana_nodes"]:
					capture[player] = int(timeline.turn)
			"building_used", "castle_assaulted", "pickup_taken", "resources_collected":
				timeline.acted[int(data.get("hero", -1))] = true
			"skill_learned":
				var hero := state.object(data.id)
				if int(hero.owner) != state.current_player: _stat(int(hero.owner)).skills += 1
			"hero_placed":
				var hero := state.object(data.id)
				if data.get("recruited", false) and int(hero.owner) != state.current_player:
					var dawn: Dictionary = timeline.dawn
					dawn.get_or_add(int(hero.uid), [Vector2i(hero.x, hero.y), _deeds(hero)])
				if balance:
					recruits[int(hero.uid)] = {"player": int(hero.owner), "hero": str(hero.name),
						"hired": turn_number, "first_step": null}
					_stat(int(hero.owner)).recruits += 1
					_say("day %d  P%d recruits %s (level %d)" % [state.day, hero.owner, hero.name, hero.level])
			"inventory_changed":
				var hero := state.object(data.id)
				if int(hero.get("owner", 0)) == state.current_player: return
				var before: Dictionary = books.get(int(hero.uid), {"cards": [], "uses": []})
				var gained: Array = []
				var runes := 0
				for slot in hero.cards.size():
					if slot >= before.cards.size() or before.cards[slot] != hero.cards[slot]: gained.append("%s for %s" % [hero.cards[slot], before.cards[slot] if slot < before.cards.size() else "-"])
					elif int(hero.rune_uses[slot]) > int(before.uses[slot]): runes += int(hero.rune_uses[slot]) - int(before.uses[slot])
				if not gained.is_empty():
					_stat(int(hero.owner)).spells += gained.size()
					_say("day %d  P%d %s buys %s" % [state.day, hero.owner, hero.name, ", ".join(gained)])
				if runes > 0:
					_stat(int(hero.owner)).runes += runes
					_say("day %d  P%d %s buys %d runes" % [state.day, hero.owner, hero.name, runes])
				books[int(hero.uid)] = {"cards": hero.cards.duplicate(), "uses": hero.rune_uses.duplicate()}
			"player_eliminated":
				fell[int(data.get("player", -1))] = int(state.day)
				_say("day %d  P%s is out" % [state.day, str(data.get("player", "?"))])
	)
	director.presentation.connect(func(data: Dictionary):
		# Movement left when the night's actions begin, before it is restored.
		if data.get("kind") == "strategy_phase" and data.get("phase") == "use" and director.strategy.get("free", "night") == "night":
			for player: int in ELFirstAI.computer_players(state):
				for hero: Dictionary in ELFirstAI.heroes_of(state, player):
					_stat(player).ap_left += maxi(0, int(hero.ap))
					_stat(player).ap_total += maxi(1, int(hero.strategy_capacity))
	)
	explored_before = state.explored.duplicate()
	director.grid.actor_moved.connect(_stepped)
	var monsters_at_start := 0
	for item: Dictionary in state.objects.values():
		if item.get("type") == "monster" and item.get("alive", false): monsters_at_start += 1
	print("=== %s (%s): %d spell shops, %d component portals, smart=%s free=%s seed=%s opponent=%s lookahead=%s living=%s fight-monsters=%s difficulty=%d, human P%d" % [entry.id, "random map" if entry.has("random") else ELSingleScenario.title(profile, entry), shops, portals, director.smart_ai, director.free_movement, _arg("seed", "212"), "active" if active else "still", _arg("lookahead", "true"), _arg("living", "false"), director.fight_neutral_monsters, state.difficulty, state.current_player])
	var income := {}
	for player: int in state.players:
		if player == state.current_player: continue
		var castle := ELFirstScenario.castle_object(state, player)
		var own := 0
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and int(item.get("owner", -1)) == player and item.get("alive", false): own += 1
		income[player] = int(ELStrategy.mana_budget(state, player).income)
		print("    P%d %s: castle %s, heroes at start %d, relation to human %s, computer %s" % [player, state.players[player].color, "none" if castle.is_empty() else "(%d,%d)" % [castle.x, castle.y], own, str(state.players[player].get("relations", {}).get(state.current_player, "-")), ELFirstAI.computer_players(state).has(player)])
	var alive_at_start := {}
	for player: int in state.players: alive_at_start[player] = ELFirstScenario.alive(state, player)
	var last_globals := {}
	var outcome_day := -1
	for day in days:
		turn_number = day + 1
		timeline.turn = turn_number
		timeline.acted.clear()
		for item: Dictionary in state.objects.values():
			if item.get("type") == "hero" and item.get("alive", false) and item.has("cards") and item.has("rune_uses"): books[int(item.uid)] = {"cards": item.cards.duplicate(), "uses": item.rune_uses.duplicate()}
		var before := _snapshot()
		timeline.dawn = before
		if not _settle(): break
		if active and not _human_day(): break
		if not director.end_day():
			print("day %d: the day cannot end: %s %s" % [state.day, director.notice, director.error])
			break
		if not _settle(): break
		for player: int in ELFirstAI.computer_players(state):
			var record := ELGlobalSpells.data(state, player)
			var actives: Array = []
			for spell: Dictionary in record.get("active", []): actives.append(str(spell.code))
			var seen: Array = last_globals.get(player, [])
			for code: String in actives:
				if not seen.has(code):
					_stat(player).globals += 1
					_say("day %d  P%d casts %s" % [state.day, player, code])
			last_globals[player] = actives
			var tasks := {}
			for pair: Array in ELFirstAI.data(state, player).assigned: tasks[int(pair[0])] = pair[1]
			var lines: Array = []
			for hero: Dictionary in ELFirstAI.heroes_of(state, player):
				var task: Dictionary = tasks.get(int(hero.uid), {})
				var s := _stat(player)
				s.hero_days += 1
				var target := state.object(int(task.get("target", -1)))
				var was: Array = before.get(int(hero.uid), [])
				var moved: bool = not was.is_empty() and was[0] != Vector2i(hero.x, hero.y)
				var acted: bool = timeline.acted.has(int(hero.uid)) or (not was.is_empty() and was[1] != _deeds(hero))
				if task.is_empty(): s.idle += 1
				if not moved and not acted: s.no_progress += 1
				if not task.is_empty() and not moved and not (not target.is_empty() and ELStrategy.adjacent(director, hero, target)): s.stalled += 1
				lines.append("%s L%d (%d,%d) %s%s runes %d%%" % [hero.name, hero.level, hero.x, hero.y, task.get("kind", "idle"), (":" + str(target.get("name", ""))) if not target.is_empty() else "", int(ELFirstAIEconomy.rune_health(state, hero) * 100)])
			_stat(player).lost += _lost(player)
			_stat(player).duplicates += _duplicates(player)
			_threats(player)
			if not quiet: print("day %d  P%d %s | %s | making %s" % [state.day, player, _resources(player), "; ".join(lines), str(record.get("production", {}).get("code", "-"))])
		if not state.outcome.is_empty():
			outcome_day = int(state.day)
			print("day %d: outcome %s" % [state.day, state.outcome])
			break
	var monsters_left := 0
	for item: Dictionary in state.objects.values():
		if item.get("type") == "monster" and item.get("alive", false): monsters_left += 1
	print("MONSTERS: %d at start, %d left after day %d" % [monsters_at_start, monsters_left, state.day])
	var failed := false
	var timing: Dictionary = director.get_meta("first_ai_stats", {})
	var fallen: Array = []
	for player: int in state.players:
		if alive_at_start.get(player, false) and not ELFirstScenario.alive(state, player): fallen.append("P%d@%s" % [player, str(fell.get(player, "?"))])
	for player: int in ELFirstAI.computer_players(state):
		var s := _stat(player)
		var known := 0
		for item: Dictionary in state.objects.values():
			if ELFirstAIEconomy.is_shop(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)): known += 1
		var levels: Array = []
		for hero: Dictionary in ELFirstAI.heroes_of(state, player): levels.append(int(hero.level))
		var sites := 0
		for item: Dictionary in state.objects.values():
			if item.get("group") in ["mines", "mana_nodes"] and int(item.get("owner", -1)) == player: sites += 1
		print("SUMMARY P%d: heroes %s, spells bought %d, runes bought %d, skills %d, recruits %d, global spells %d, idle hero-days %d/%d, shops known %d, %s" % [player, str(levels), s.spells, s.runes, s.skills, s.recruits, s.globals, s.idle, s.hero_days, known, _resources(player)])
		print("METRICS P%d: no-progress %d/%d, stalled %d, unused movement %d%%, lost objective-days %d, unexplored steps %d, guard steps %d, threats %d answered %d (avg %.1f days), sites held %d, duplicate assignments %d, ether income %d -> %d" % [player, s.no_progress, s.hero_days, s.stalled, int(100.0 * s.ap_left / maxi(1, s.ap_total)), s.lost, s.unexplored_steps, s.guard_steps, s.threats, s.answered, float(s.response_days) / maxi(1, s.answered), sites, s.duplicates, int(income.get(player, 0)), int(ELStrategy.mana_budget(state, player).income)])
	if balance:
		for player: int in participants:
			var s := _stat(player)
			var sites := 0
			for item: Dictionary in state.objects.values():
				if item.get("group") in ["mines", "mana_nodes"] and int(item.get("owner", -1)) == player: sites += 1
			print("FACTION " + JSON.stringify({"player": player, "first_site_turn": capture.get(player), "sites": sites, "no_progress": s.no_progress, "hero_days": s.hero_days, "reasons": timing.get("reasons", {}).get(player, {})}))
		for recruit: Dictionary in recruits.values(): print("RECRUIT " + JSON.stringify(recruit))
		for outcome: Dictionary in timing.get("monster_outcomes", []):
			print("MATCHUP " + JSON.stringify(outcome))
		print("FORECAST " + JSON.stringify({"trials": int(timing.get("forecast_trials", 0)), "extended": int(timing.get("forecast_extended", 0)), "usec": int(timing.get("forecast_usec", 0))}))
	var passes := maxi(1, int(timing.get("passes", 0)))
	print("RESULT: outcome %s day %d, castles fallen %s, duplicate assignments after passes %d, planning passes %d, %.1f ms per pass (objectives %.1f, matching %.1f of which lookahead %.1f, orders %.1f), slowest pass %.1f ms" % [state.outcome if not state.outcome.is_empty() else "-", outcome_day if outcome_day >= 0 else int(state.day), str(fallen), int(timing.get("duplicates", 0)), int(timing.get("passes", 0)), float(timing.get("usec", 0)) / 1000.0 / passes, float(timing.get("objectives", 0)) / 1000.0 / passes, float(timing.get("assign", 0)) / 1000.0 / passes, float(timing.get("lookahead", 0)) / 1000.0 / passes, float(timing.get("command", 0)) / 1000.0 / passes, float(timing.get("slowest", 0)) / 1000.0])
	if not director.error.is_empty():
		print("ERROR: " + director.error)
		failed = true
	if stuck: failed = true
	if _arg("dump", "false") == "true": _dump(profile)
	if _arg("explain", "false") == "true": _explain()
	return "fail" if failed else "ok"

## The smarter planner's best options for every computer hero at the end.
func _explain() -> void:
	var planner: Script = load("res://src/content/first_ai_planner.gd") if ResourceLoader.exists("res://src/content/first_ai_planner.gd") else null
	if planner == null or not ELFirstAIEconomy.applies(director): return
	for player: int in ELFirstAI.computer_players(state):
		var ai := ELFirstAI.data(state, player)
		var closed: Array[Vector2i] = ELFirstAI._close_unexplored(director, player)
		var pool: Array = (ELFirstAI as Script).call("objectives", director, player)
		var danger: Dictionary = planner.call("threats", director, player)
		for hero: Dictionary in ELFirstAI.heroes_of(state, player):
			var role := 0 if int(ai.champion) == int(hero.uid) else 1
			var rows: Array = []
			for task: Dictionary in pool:
				var points: float = planner.call("utility", director, hero, role, task, danger, true)
				if points > -INF: rows.append([points, "%s:%s" % [task.kind, str(state.object(int(task.get("target", -1))).get("name", task.get("tile", "")))]])
			rows.sort_custom(func(a: Array, b: Array): return a[0] > b[0])
			print("EXPLAIN P%d %s L%d role %d: %s" % [player, hero.name, hero.level, role, ", ".join(rows.slice(0, 8).map(func(r: Array): return "%s %.0f" % [r[1], r[0]]))])
		for point: Vector2i in closed: director.grid._update_cell(point)

## The human's seat as a baseline opponent: the original rules plan its
## heroes, which then move as the player's would.
func _human_day() -> bool:
	var player := state.current_player
	var smart := director.smart_ai
	director.smart_ai = false
	ELFirstAI.plan_player(director, player)
	director.smart_ai = smart
	if not ELStrategy.free_mode(director): return true
	for hero: Dictionary in ELFirstAI.heroes_of(state, player):
		if hero.get("strategy_order", {}).is_empty() or int(hero.ap) <= 0: continue
		if ELStrategy.act(director, hero) and not _settle(): return false
	return true

## Each computer hero's tile and personal progress at the start of a day.
func _snapshot() -> Dictionary:
	var result := {}
	for player: int in ELFirstAI.computer_players(state):
		for hero: Dictionary in ELFirstAI.heroes_of(state, player): result[int(hero.uid)] = [Vector2i(hero.x, hero.y), _deeds(hero)]
	return result

func _deeds(hero: Dictionary) -> String:
	return var_to_str([int(hero.experience), hero.get("cards", []), hero.get("rune_uses", []), hero.get("skills", {}),
		hero.get("artifacts", []), int(hero.health), int(hero.strategy_capacity)])

## Objectives a player could pursue that its plans have lost track of.
func _lost(player: int) -> int:
	var ai := ELFirstAI.data(state, player)
	var known := {}
	for task: Dictionary in ai.tasks: known[int(task.get("target", -1))] = true
	for pair: Array in ai.assigned:
		if state.object(pair[0]).get("alive", false): known[int(pair[1].get("target", -1))] = true
	var heroes := ELFirstAI.heroes_of(state, player)
	if heroes.is_empty(): return 0
	var count := 0
	for item: Dictionary in state.objects.values():
		if known.has(int(item.uid)) or not item.get("alive", false): continue
		var valid := false
		if ELFirstScenario.is_castle(item): valid = int(item.owner) >= 1 and int(item.owner) != player and ELFirstScenario.alive(state, int(item.owner))
		elif item.get("group") in ["mines", "mana_nodes"]: valid = int(item.get("owner", -1)) < 0
		elif item.get("group") == "resource_cuts": valid = true
		elif item.get("type") == "monster" and int(item.get("owner", 0)) <= 0: valid = item.get("visible", false) and item.get("placed", true)
		elif item.get("group") == "additional_buildings" and not ELFirstAI.SKIPPED_BUILDINGS.has(item.get("name")) and ELAdditionalBuildings.supported(item):
			for hero: Dictionary in heroes:
				if ELAdditionalBuildings.visit_problem(state, hero, item).is_empty(): valid = true
		if valid: count += 1
	return count

## Shared objectives (everything but a learning building or a siege) held
## by more than one living hero of the player at the end of the day.
func _duplicates(player: int) -> int:
	var holders := {}
	for pair: Array in ELFirstAI.data(state, player).assigned:
		if not state.object(pair[0]).get("alive", false): continue
		var key := ELFirstAI._key(pair[1], -1)
		if bool(pair[1].get("personal", false)) or pair[1].get("kind") in ["patrol", "escort"]: continue
		holders[key] = int(holders.get(key, 0)) + 1
	var count := 0
	for key: String in holders: if int(holders[key]) > 1: count += 1
	return count

## Castle threats and how long until a hero of the player comes near.
func _threats(player: int) -> void:
	var castle := ELFirstScenario.castle_object(state, player)
	if castle.is_empty(): return
	var at := Vector2i(castle.x, castle.y)
	var own := ELFirstAI.heroes_of(state, player)
	for item: Dictionary in state.objects.values():
		var key := "%d:%d" % [player, int(item.get("uid", -1))]
		var near: bool = item.get("type") == "hero" and item.get("alive", false) and int(item.get("owner", -1)) >= 1 and int(item.owner) != player and state.hostile(item, castle) and maxi(absi(int(item.x) - at.x), absi(int(item.y) - at.y)) <= 12
		if not near:
			threats.erase(key)
			continue
		if not threats.has(key):
			threats[key] = {"day": int(state.day), "answered": false}
			_stat(player).threats += 1
		var threat: Dictionary = threats[key]
		if threat.answered: continue
		for hero: Dictionary in own:
			if maxi(absi(int(hero.x) - int(item.x)), absi(int(hero.y) - int(item.y))) <= 4:
				threat.answered = true
				_stat(player).answered += 1
				_stat(player).response_days += int(state.day) - int(threat.day)
				break

## A computer hero's step: onto ground its player had not explored, or into
## a guard area that is not its order's target.
func _stepped(actor: Dictionary) -> void:
	var recruit: Dictionary = recruits.get(int(actor.uid), {})
	if not recruit.is_empty() and recruit.first_step == null: recruit.first_step = turn_number
	var player := int(actor.get("owner", -1))
	if actor.get("type") == "hero" and ELFirstAI.computer_players(state).has(player) and director.grid.contains(Vector2i(actor.x, actor.y)):
		var index := int(actor.y) * state.map.width + int(actor.x)
		if ELFog.active(state, player) and index < explored_before.size() and explored_before[index] & ELFog.bit(player) == 0: _stat(player).unexplored_steps += 1
		var guards := director.interception.enemies(state, actor, Vector2i(actor.x, actor.y))
		var target := int(actor.get("strategy_order", {}).get("use", -1))
		if not guards.is_empty() and not guards.has(target): _stat(player).guard_steps += 1
	explored_before = state.explored.duplicate()

## Books, known shops with their stock and prices, and the global spells on offer.
func _dump(profile: ELProfile) -> void:
	for player: int in ELFirstAI.computer_players(state):
		var budget := ELStrategy.mana_budget(state, player)
		print("--- P%d (%s): ether income %d, hero upkeep %d, spell upkeep %d, summons %d" % [player, state.players[player].color, budget.income, budget.spent, ELGlobalSpells.spell_upkeep(state, player), int(ELGlobalSpells.data(state, player).get("summons", 0))])
		for code: String in ELMapPickups.available_codes(state, player):
			print("    global %s: ether %d, upkeep %d, %s, problem '%s'" % [code, ELGlobalSpells.ether_cost(state, player, code), ELGlobalSpells.upkeep(profile, code), str(ELGlobalSpells.resources(profile, code)), ELGlobalSpells.produce_problem(state, player, code)])
		for hero: Dictionary in ELFirstAI.heroes_of(state, player):
			var book: Array = []
			for slot in hero.cards.size():
				var row: Dictionary = profile.table("CombatSpells").get(hero.cards[slot], {})
				book.append("%s(%s%s c%s)x%d" % [hero.cards[slot], str(row.get("Rarity", "?")).left(2), "", str(row.get("Cost", "?")), int(hero.rune_uses[slot])])
			print("    %s L%d skills %s: %s" % [hero.name, hero.level, str(hero.get("skills", {})), " ".join(book)])
			for item: Dictionary in state.objects.values():
				if not ELFirstAIEconomy.is_shop(item) or not ELFog.explored(state, player, Vector2i(item.x, item.y)): continue
				if item.type == "el1_spell_shop":
					var stock: Array = []
					for card: String in ELFirstSpellShop.authored_stock(profile, item, ELFirstSpellShop.hero_color(profile, hero)):
						var row: Dictionary = profile.table("CombatSpells").get(card, {})
						var price := ELFirstSpellShop.price(profile, hero, hero.cards, card, -1)
						var bill: Array = []
						for kind: String in price: if int(price[kind]) > 0: bill.append("%s %d" % [kind.left(2), price[kind]])
						stock.append("%s(%s c%s: %s)" % [card, str(row.get("Rarity", "?")).left(2), str(row.get("Cost", "?")), " ".join(bill)])
					print("      shop %s L%d at (%d,%d) wants %d: %s" % [item.name, item.level, item.x, item.y, ELFirstAIEconomy.wants(director, hero, item), " ".join(stock)])
				else:
					print("      portal %s L%d (%s) at (%d,%d) wants %d" % [item.name, item.level, str(ELRuneShop.definition(profile, item).get("Rarity", "")), item.x, item.y, ELFirstAIEconomy.wants(director, hero, item)])
			break

func _say(text: String) -> void:
	if not quiet: print("  * " + text)

func _resources(player: int) -> String:
	var parts: Array = []
	var stock: Dictionary = state.players[player].resources
	for kind: String in stock:
		if int(stock[kind]) != 0: parts.append("%s %d" % [kind.left(2), stock[kind]])
	return " ".join(parts)

## Runs the director until the local player may plan again.
func _settle() -> bool:
	for step in 200000:
		if not director.error.is_empty() or not state.outcome.is_empty(): return director.error.is_empty()
		if not director.dialogue.is_empty():
			director.acknowledge("OK")
			continue
		if director.encounter != null:
			var first := state.object(director.encounter.attacker())
			var second := state.object(director.encounter.target())
			director.encounter = null
			if active:
				# A baseline opponent fights by the same rule as the computer.
				ELFirstAI.resolve(director, first, second)
				continue
			# The local player's heroes never fight here: the attacker wins.
			var mine := first if int(first.owner) == state.current_player else second
			var other := second if mine == first else first
			ELFirstAI.resolve(director, first, second, int(other.uid))
			continue
		if director._shopping():
			if director.first_shop != null: director.first_shop.cancel()
			if director.rune_shop != null: director.rune_shop.cancel()
			director.first_shop = null
			director.rune_shop = null
			continue
		if director.strategy.is_empty() and director.movement.is_empty() and director.travel.is_empty() and director.free_queue.is_empty() and state.commands.is_empty() and director.can_move(): return true
		director.advance(0.1)
	print("day %d: the turn did not settle" % state.day)
	stuck = true
	return false
