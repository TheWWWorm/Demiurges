class_name ELFirstAI
extends RefCounted
## First-game strategic opponents. Original map AI settles non-local battles
## without a duel. Smarter and Living world play hero-versus-monster duels
## off screen. The Smarter map AI adds skill picks, shopping and
## global spells (ELFirstAIEconomy) and plans with ELFirstAIPlanner.

## Winner of a strategic battle that the local player takes no part in. The
## pair keeps its queue order (guard or interceptor first). The original
## rule: a player's side always beats a neutral one, and between players the
## first side wins with chance (L1 + 1) / (L1 + L2 + 1). `estimate` (a remake
## switch, off by default) weighs the two sides' books, health, skills and
## artifacts instead (ELFirstAIPlanner.win_chance).
static func winner(state: ELAdventureSession, first: Dictionary, second: Dictionary, estimate := false) -> Dictionary:
	var first_neutral := int(first.get("owner", 0)) <= 0
	var second_neutral := int(second.get("owner", 0)) <= 0
	if state.map.id == "mission23" and (first_neutral or second_neutral):
		# Roaming neutral heroes are this chapter's hunters; its creatures are prey.
		if first_neutral: return first if first.type == "hero" else second
		return first if second.type == "monster" else second
	if estimate:
		# The draw (0..32767) is compared with the chance scaled to its whole
		# range: a remainder by 10000 would favour the first side.
		var chance := ELFirstAIPlanner.estimate(state, first, second)
		return first if ELAdditionalBuildings._random(state) < int(chance * 32768.0) else second
	if first_neutral or second_neutral: return second if first_neutral else first
	# Weighted by level: the first side wins with chance (L1 + 1) / (L1 + L2 + 1).
	var level := int(first.get("level", 1))
	var roll := ELAdditionalBuildings._random(state) % (level + int(second.get("level", 1)) + 1)
	return second if level < roll else first

## Decides the battle and applies its result. Returns false on a script failure.
static func resolve(director: ELAdventureDirector, first: Dictionary, second: Dictionary, forfeit_winner := -1) -> bool:
	if forfeit_winner < 0 and plays_monster_duel(director, first, second):
		return _fight_monster(director, first, second)
	var state := director.state
	var victor := state.object(forfeit_winner) if forfeit_winner >= 0 else winner(state, first, second, director.battle_estimate)
	var loser := second if victor == first else first
	if state.players.has(int(victor.owner)) and int(victor.owner) >= 1:
		state.add_experience(victor.uid, ELHeroProgression.battle_reward(state.map.profile, int(loser.get("level", 1))))
		if loser.type == "monster": ELAdventureEncounter.loot(state, victor, loser)
	take_artifacts(victor, loser)
	state._native([float(loser.uid)], "ExKillHero")
	if not state.hook("Hook_OnHeroKill", [float(loser.uid)]): return director._fail(state.error)
	ELFirstScenario.evaluate(director, {"hero": first.uid, "opponent": second.uid, "winner": victor.uid})
	return true

static func plays_monster_duel(director: ELAdventureDirector, first: Dictionary, second: Dictionary) -> bool:
	if not ELFirstAIEconomy.applies(director): return false
	var first_is_hero: bool = first.get("type") == "hero"
	var hero := first if first_is_hero else second
	var monster := second if first_is_hero else first
	var owner := int(hero.get("owner", 0))
	return hero.get("type") == "hero" and owner > 0 and director.state.players.has(owner) and not director.is_strategy_human(owner) \
		and monster.get("type") == "monster" and int(monster.get("owner", 0)) <= 0

# Keep headless battles bounded even when both books run out of attacks.
const MONSTER_DUEL_STEPS := 512
# Three draws for each initiative parity when terrain allows either side to start.
const FORECAST_SEEDS := [9026, 18437, 27662, 3837, 14212, 31599]
const EXTRA_SEEDS := [5398, 23951, 31076, 12079]
const CONFIRMATION_SEEDS := [947, 6537, 20302, 29846]
const EXTRA_WINS := 8
const CONFIRMATION_WINS := 11
const NARROW_WIN_MARGIN := 0.3
const MONSTER_LOSS_COOLDOWN := 4

## Check a shortlisted monster or lair before committing a hero to the trip.
static func forecast_objective(director: ELAdventureDirector, hero: Dictionary, task: Dictionary, budget: Dictionary = {}) -> bool:
	var kind: String = task.get("kind", "")
	if kind not in ["monster", "building"]: return true
	var item := director.state.object(task.get("target", -1))
	if not item.get("alive", false): return false
	if kind == "monster":
		var at := Vector2i(item.x, item.y)
		if director.interception.zones.has(int(item.uid)) and not ELStrategy.adjacent(director, hero, item):
			var from := Vector2i(hero.x, hero.y)
			var closed := close_guards(director, hero, int(item.uid))
			var route := director.grid.approach(from, item)
			if route.is_empty() and not closed.is_empty():
				for tile: Vector2i in closed: director.grid._update_cell(tile)
				closed.clear()
				route = director.grid.approach(from, item)
			route = ELStrategy.screen_monster_route(director, hero, route, item, at, closed, budget)
			for tile: Vector2i in closed: director.grid._update_cell(tile)
			if route.is_empty(): return false
			for tile: Vector2i in route.slice(1):
				if director.interception.enemies(director.state, hero, tile).has(int(item.uid)): return true
		return can_attack_monster(director, hero, item, false, at, budget)
	if ELAdditionalBuildings.DUNGEONS.has(item.get("name")):
		var mob := director.state.object(item.monster)
		if not mob.get("alive", false): return false
		var route := director.grid.approach(Vector2i(hero.x, hero.y), item)
		var at := Vector2i(item.x, item.y) if route.is_empty() else route[-1]
		return can_attack_monster(director, hero, mob, false, at, budget)
	return true

## Starting books and modifiers fully determine the trials for a terrain and
## seat order. Cache the result through free-movement replans and across days.
static func _duel_roster(state: ELAdventureSession, actor: Dictionary, shape: String, row: Dictionary) -> Array:
	var identity := [actor.name, shape]
	if actor.type == "hero" and shape.is_empty() and not row.is_empty():
		# For a template hero the duel supplies the complete book, skills,
		# health and level. The template's only combat input is its faction.
		identity = ["hero", str(row.get("Color", ""))]
	return [identity, actor.level, actor.health, actor.get("specialization", ""), actor.get("monster_difficulty", -1),
		actor.cards, actor.get("rune_uses", []), actor.get("rune_under", []), actor.get("skills", {}), actor.get("artifacts", []).map(func(art: Dictionary) -> String: return str(art.name)),
		actor.get("global_spells", []), int(ELForts.garrison_of(state, actor).get("fort_level", 0))]

static func _forecast_key(state: ELAdventureSession, hero: Dictionary, monster: Dictionary, guard_first: bool, at: Vector2i) -> String:
	var hero_shape := str(hero.get("shape", ""))
	var hero_row := ELAdventureEncounter.combat_definition(state, hero, hero_shape)
	var mob_shape := str(monster.get("shape", ""))
	var mob_row := ELAdventureEncounter.combat_definition(state, monster, mob_shape)
	var colours: Array[String] = [str(hero_row.get("Color", "")), str(mob_row.get("Color", ""))]
	var placed: Array[bool] = [Vector2i(hero.x, hero.y) != Vector2i(-1, -1), Vector2i(monster.x, monster.y) != Vector2i(-1, -1)]
	var terrain := ELAdventureEncounter.terrain_class(state.map, at) if at != Vector2i.ZERO else -1
	# Different terrains with the same initiative play the same headless duel.
	var initiative := ELAdventureEncounter.terrain_first_side(state.map.profile.id, terrain, colours, placed)
	return var_to_str([guard_first, initiative, _duel_roster(state, hero, hero_shape, hero_row), _duel_roster(state, monster, mob_shape, mob_row)])

static func _last_active_hero(director: ELAdventureDirector, owner: int) -> bool:
	# Cache the answer for a planning pass. In movement/combat the roster
	# is live: a death can make the next fight worth checking more closely.
	if _active_heroes is Dictionary and _active_heroes.has(owner): return int(_active_heroes[owner]) <= 1
	var count := 0
	for hero: Dictionary in heroes_of(director.state, owner):
		if not ELGlobalSpells.held(hero): count += 1
	if _active_heroes is Dictionary: _active_heroes[owner] = count
	return count <= 1

static var _active_heroes: Variant = null

static func can_attack_monster(director: ELAdventureDirector, hero: Dictionary, monster: Dictionary, guard_first: bool, at: Vector2i, budget: Dictionary = {}) -> bool:
	if not plays_monster_duel(director, hero, monster): return true
	var state := director.state
	var retry: Dictionary = state.players[int(hero.owner)].get("ai", {}).get("retry", {})
	if int(retry.get(_monster_retry_key(hero, monster), 0)) > int(state.day): return false
	var key := _forecast_key(state, hero, monster, guard_first, at)
	var cache := director.monster_forecasts
	var record: Dictionary = cache.get(key, {})
	var can_sample := int(budget.get("remaining", 1)) > 0
	var started := Time.get_ticks_usec()
	var before := int(record.get("samples", 0))
	if record.is_empty():
		if not can_sample: return budget.get("allow_unknown", false)
		if budget.has("remaining"): budget.remaining -= 1
		if cache.size() >= 2048: cache.clear()
		record = {"wins": 0, "samples": 0, "life": 0.0}
		_sample_monster_duels(state, hero, monster, guard_first, at, FORECAST_SEEDS, EXTRA_WINS - EXTRA_SEEDS.size(), record)
		record.base_samples = int(record.samples)
		record.base_wins = int(record.wins)
		record.base_life = float(record.life)
		record.base_approved = int(record.wins) == FORECAST_SEEDS.size()
		record.narrow = record.base_approved and float(record.life) / maxi(1, int(record.wins)) < NARROW_WIN_MARGIN
		cache[key] = record
	var approved: bool = record.base_approved
	var mixed := not approved and int(record.get("base_wins", 0)) >= EXTRA_WINS - EXTRA_SEEDS.size()
	if mixed or (approved and (record.narrow or _last_active_hero(director, int(hero.owner)))):
		if not record.has("extended"):
			if not can_sample: return budget.get("allow_unknown", false)
			if before > 0 and budget.has("remaining"): budget.remaining -= 1
			_sample_monster_duels(state, hero, monster, guard_first, at, EXTRA_SEEDS, EXTRA_WINS, record)
			record.extended = int(record.wins) >= EXTRA_WINS
			# A fight with losses in the base sample has to hold up against a
			# fresh set before the AI risks a hero on it.
			if record.extended and mixed:
				_sample_monster_duels(state, hero, monster, guard_first, at, CONFIRMATION_SEEDS, CONFIRMATION_WINS, record)
				record.extended = int(record.wins) >= CONFIRMATION_WINS
		approved = record.extended
	if int(record.samples) > before and director.has_meta("first_ai_stats"):
		var stats: Dictionary = director.get_meta("first_ai_stats")
		var usec := Time.get_ticks_usec() - started
		stats.forecast_trials = int(stats.get("forecast_trials", 0)) + int(record.samples) - before
		stats.forecast_usec = int(stats.get("forecast_usec", 0)) + usec
		stats.forecast_peak = maxi(int(stats.get("forecast_peak", 0)), usec)
		if record.has("extended"): stats.forecast_extended = int(stats.get("forecast_extended", 0)) + 1
	if approved and not director.monster_losses.is_empty():
		var loss: Dictionary = director.monster_losses.get(_monster_loss_key(hero, monster), {})
		if int(loss.get("until", 0)) > int(state.day):
			var assessment := _forecast_quality(record, mixed or record.narrow or _last_active_hero(director, int(hero.owner)))
			var previous: Vector2 = loss.quality
			if assessment.x < previous.x + 0.05 and assessment.y < previous.y + 0.12:
				ELFirstAI.note_stat(director, int(hero.owner), "repeat_loss_avoided")
				return false
	return approved

static func _monster_loss_key(hero: Dictionary, monster: Dictionary) -> Array:
	return [int(hero.owner), int(monster.uid), int(hero.level), int(hero.health), hero.cards, hero.rune_uses]

static func _forecast_quality(record: Dictionary, extra: bool) -> Vector2:
	var wins := int(record.get("wins" if extra else "base_wins", 0))
	var samples := int(record.get("samples" if extra else "base_samples", 0))
	var life := float(record.get("life" if extra else "base_life", 0.0))
	return Vector2(float(wins) / maxi(1, samples), life / maxi(1, wins))

static func _sample_monster_duels(state: ELAdventureSession, hero: Dictionary, monster: Dictionary, guard_first: bool, at: Vector2i, seeds: Array, needed: int, record: Dictionary) -> void:
	var first := int(monster.uid) if guard_first else int(hero.uid)
	var second := int(hero.uid) if guard_first else int(monster.uid)
	var side := int(guard_first)
	for index in seeds.size():
		var fight := ELAdventureEncounter.new()
		record.samples += 1
		if not fight.prepare_map_ai_duel(state, first, second, int(seeds[index]), at, hero): break
		if _play_monster_duel(fight.battle) and fight.battle.winner == side:
			record.wins += 1
			record.win_mask = int(record.get("win_mask", 0)) | (1 << (int(record.samples) - 1))
			var unit := fight.battle.heroes[side]
			record.life += clampf(float(unit.health) / maxf(1.0, float(unit.maximum)), 0.0, 1.0)
		if int(record.wins) + seeds.size() - index - 1 < needed: break

## An interim purchase can move the hero towards a viable battle. Compare
## only identical seeds on the same initial approach, with at least two
## additional wins and at least three observed wins in the upgraded book.
static func upgrade_improves_guard(director: ELAdventureDirector, hero: Dictionary, preview: Dictionary, guard: Dictionary, budget: Dictionary) -> bool:
	if forecast_objective(director, preview, {"kind": "monster", "target": int(guard.uid)}, budget): return true
	var state := director.state
	var at := Vector2i(guard.x, guard.y)
	var guard_first := false
	if director.interception.zones.has(int(guard.uid)) and not ELStrategy.adjacent(director, hero, guard):
		var route := director.grid.approach(Vector2i(hero.x, hero.y), guard)
		for tile: Vector2i in route.slice(1):
			if not director.interception.enemies(state, hero, tile).has(int(guard.uid)): continue
			at = tile
			guard_first = true
			break
	var cache := director.monster_forecasts
	var before: Dictionary = cache.get(_forecast_key(state, hero, guard, guard_first, at), {})
	var after: Dictionary = cache.get(_forecast_key(state, preview, guard, guard_first, at), {})
	var samples := mini(int(before.get("base_samples", 0)), int(after.get("base_samples", 0)))
	var won := 0
	var difference := 0
	for index in samples:
		var win := (int(after.get("win_mask", 0)) >> index) & 1
		won += win
		difference += win - ((int(before.get("win_mask", 0)) >> index) & 1)
	return won >= 3 and difference >= 2

static func _play_monster_duel(battle: ELDuel) -> bool:
	for step in MONSTER_DUEL_STEPS:
		if battle.phase == ELDuel.Phase.FINISHED: return true
		ELPracticeAI.heuristic_step(battle)
	# If a book spins on repeatable actions, both sides pass. The duel
	# engine still resolves attacks and ether disturbance normally.
	for step in MONSTER_DUEL_STEPS:
		if battle.phase == ELDuel.Phase.FINISHED: return true
		battle.end_phase()
	return battle.phase == ELDuel.Phase.FINISHED

static func _fight_monster(director: ELAdventureDirector, first: Dictionary, second: Dictionary) -> bool:
	var state := director.state
	var fight := ELAdventureEncounter.new()
	var guard_first: bool = first.type == "monster"
	var hero := second if guard_first else first
	var monster := first if guard_first else second
	var at := Vector2i(second.x, second.y)
	if at == Vector2i(-1, -1): at = Vector2i(first.x, first.y)
	var battle_seed := ELAdditionalBuildings._random(state)
	if not fight.prepare_map_ai_duel(state, int(first.uid), int(second.uid), battle_seed):
		push_warning("Unable to prepare a computer duel against %s: %s" % [monster.name, fight.error])
		_cancel_unavailable_duel(director, hero, monster)
		return true
	if not _play_monster_duel(fight.battle): return director._fail("The computer duel did not finish.")
	var won := fight.battle.winner == int(guard_first)
	var forecast: Dictionary = director.monster_forecasts.get(_forecast_key(state, hero, monster, guard_first, at), {})
	var extra: bool = not forecast.is_empty() and forecast.has("extended") and (not forecast.base_approved or forecast.narrow or _last_active_hero(director, int(hero.owner)))
	var loss_key := _monster_loss_key(hero, monster).duplicate(true) if not won and not forecast.is_empty() else []
	if director.has_meta("first_ai_balance"):
		var unit := fight.battle.heroes[int(guard_first)]
		var report := {"player": int(hero.owner), "day": int(state.day), "hero": str(hero.name), "monster": str(monster.name),
			"won": won, "draw": fight.battle.winner < 0,
			"actual_health": clampf(float(unit.health) / maxf(1.0, float(unit.maximum)), 0.0, 1.0)}
		if director.has_meta("first_ai_replay"):
			var replay := ELAdventureEncounter.new()
			if replay.prepare_map_ai_duel(state, int(first.uid), int(second.uid), battle_seed, at) and _play_monster_duel(replay.battle):
				report.preview_match = replay.battle.winner == fight.battle.winner
			report.battle_seed = battle_seed
			report.monster_id = int(monster.uid)
			report.terrain = ELAdventureEncounter.terrain_class(state.map, at)
		if not forecast.is_empty():
			report.wins = int(forecast.wins if extra else forecast.base_wins)
			report.trials = int(forecast.samples if extra else forecast.base_samples)
			report.win_health = float(forecast.life if extra else forecast.base_life) / maxi(1, int(report.wins))
			report.extra_trials = extra
		var stats: Dictionary = director.get_meta("first_ai_stats", {})
		stats.get_or_add("monster_outcomes", []).append(report)
	if not fight.finish(): return director._fail(fight.error)
	# Give other plans a chance after a loss; a better matchup can try sooner.
	if not loss_key.is_empty():
		director.monster_losses[loss_key] = {"until": int(state.day) + MONSTER_LOSS_COOLDOWN, "quality": _forecast_quality(forecast, extra)}
	ELFirstScenario.evaluate(director, {"hero": first.uid, "opponent": second.uid, "winner": fight.winner})
	return true

static func _monster_retry_key(hero: Dictionary, monster: Dictionary) -> String:
	var dungeon := int(monster.get("dungeon", -1))
	var task := {"kind": "building", "target": dungeon} if dungeon >= 0 else {"kind": "monster", "target": int(monster.uid)}
	return _key(task, int(hero.uid)) + "@" + str(hero.uid)

## Unsupported encounters can be called by a saved or scripted order.
## No fight took place, so clear the order and leave both rosters intact.
static func _cancel_unavailable_duel(director: ELAdventureDirector, hero: Dictionary, monster: Dictionary) -> void:
	director._step_out_of_zone(hero)
	var state := director.state
	hero.strategy_order = {}
	var ai := data(state, int(hero.owner))
	var retry: Dictionary = ai.get_or_add("retry", {})
	retry[_monster_retry_key(hero, monster)] = int(state.day) + RETRY_DAYS
	var assigned: Array = ai.assigned
	ai.assigned = assigned.filter(func(pair: Array) -> bool: return int(pair[0]) != int(hero.uid))

## A hero who defeats another hero takes the battle artifacts it carried.
static func take_artifacts(victor: Dictionary, loser: Dictionary) -> Array:
	var taken: Array = []
	if victor.get("type") != "hero" or loser.get("type") != "hero": return taken
	taken.assign(loser.get("artifacts", []))
	if taken.is_empty(): return taken
	if not victor.has("artifacts"): victor.artifacts = []
	victor.artifacts.append_array(taken)
	loser.artifacts = []
	return taken

const VERSION := 1
## Buildings the computer never sets out to use.
const SKIPPED_BUILDINGS := ["Lake", "WhiteCastle", "AncientTomb", "AltarOfWar", "TownBunker", "MoveableRock", "TrainingCamp", "ReflectingBowl", "WardingStone", "Runestone1", "Runestone2"]
## "patrol" and "escort" come only from the living-world switch.
const KINDS := ["monster", "mine", "cut", "node", "tower", "building", "explore", "hero", "shop", "patrol", "escort", "pickup"]
const AVOIDED := 10000
const NONE := 0x7fffffff
const EXPLORE_LIMIT := 9
const EXPLORE_SPACING := 200
## An assignment that gives no order, or no step on a new day, for this many
## planning passes running is given up; that hero then leaves the objective
## alone for RETRY_DAYS days (other heroes may take it at once).
const BLOCKED_PASSES := 2
const RETRY_DAYS := 2

## Computer players in planning order: after the local player's End Turn, in
## index order. Neutral creatures and roaming heroes keep their places.
static func computer_players(state: ELAdventureSession) -> Array[int]:
	var result: Array[int] = []
	for player: int in state.players:
		# Every player of the shipped maps has a castle; one without is left alone.
		if player < 1 or player == state.current_player or ELFirstScenario.castle_object(state, player).is_empty(): continue
		if not state.scenario.get("castles", {}).is_empty() and not ELFirstScenario.alive(state, player): continue
		result.append(player)
	result.sort()
	return result

## The player's plans: `tasks` the open objectives of the last planning pass,
## `assigned` [hero, task] pairs (a task's `tries` counts passes without
## progress, `mark` the hero's tile and day at its last step), `retry`
## objectives a hero gave up and the day it may try again, `seen` where and
## when enemy heroes were last seen (smarter players), `threats` the enemy
## heroes that were within reach of a castle on the last pass, `alarm` the
## days until the castle would fall despite the heroes sent to defend it (when
## it would), `commander` the field commander, `doctrine` the living-world
## doctrine once chosen.
static func data(state: ELAdventureSession, player: int) -> Dictionary:
	var record: Dictionary = state.players[player]
	if not record.get("ai") is Dictionary: record.ai = {"version": VERSION, "built": false, "tasks": [], "assigned": [], "champion": -1}
	return record.ai

## Night orders for every computer player.
static func plan(director: ELAdventureDirector) -> void:
	var state := director.state
	if state.map.profile.id != "el1": return
	scripts(director)
	for player: int in computer_players(state):
		if not director.is_strategy_human(player): plan_player(director, player)

## With free movement a player plans again after each round of moves; the
## daily events (a recruit, a scripted ethereal attack) happen once a day.
##
## Each pass rebuilds the player's objectives from the world, keeps the
## objectives living heroes hold (a fallen hero's lapse and are open again),
## drops held objectives that are finished, no longer valid or make no
## progress, then gives each free hero the best open one.
static func plan_player(director: ELAdventureDirector, player: int, daily := true) -> void:
	var state := director.state
	var started := Time.get_ticks_usec()
	var ai := data(state, player)
	ai.built = true
	var heroes := heroes_of(state, player)
	# The most experienced hero (first on ties) leads and defends the realm.
	var champion := {}
	for hero: Dictionary in heroes:
		if champion.is_empty() or int(hero.experience) > int(champion.experience): champion = hero
	ai.champion = int(champion.get("uid", -1))
	# Remake option: a champion held in a fort still meets ethereal attacks,
	# while the most experienced hero free to move leads in the field.
	var leader := commander(state, player) if ELFirstAIEconomy.applies(director) else champion
	if leader.is_empty(): ai.erase("commander")
	else: ai.commander = int(leader.uid)
	# Fewer than two heroes: a free level-one recruit joins beside the castle.
	# It first receives orders on the next day.
	if daily and heroes.size() < 2: ELGlobalSpells.summon(state, player, 1, ELFirstAIEconomy.applies(director))
	# Remake option: skills, global spells (ELFirstAIEconomy).
	if daily: ELFirstAIEconomy.daily(director, player)
	# mission13: after day ten the Kinet leader may send an ethereal attack on
	# the first player's castle (one chance in three each day).
	if daily and state.map.id == "mission13" and player == 2 and state.day > 10 and not champion.is_empty() and ELAdditionalBuildings._random(state) % 3 == 1:
		ELGlobalSpells.script_attack(state, player, champion, 1)
	var smart := ELFirstAIEconomy.applies(director)
	var free_movement := smart and ELStrategy.free_mode(director)
	if smart: ELFirstAIPlanner.observe(director, player)
	# Route costs only cross tiles this player has explored.
	var closed := _close_unexplored(director, player)
	ELFirstAIEconomy.begin_pass()
	_guard_cells = {}
	_active_heroes = {}
	var lap := Time.get_ticks_usec()
	var pool := objectives(director, player)
	lap = _lap(director, "objectives", lap)
	var open := {}
	for task: Dictionary in pool: open[_identity(task)] = true
	var retry: Dictionary = ai.get("retry", {})
	for key: String in retry.keys():
		if int(retry[key]) <= int(state.day): retry.erase(key)
	# Living heroes keep what they hold; a fallen hero's objective is open again.
	var assigned := {}
	var reserved := {}
	var listed_heroes := {}
	for hero: Dictionary in heroes: listed_heroes[int(hero.uid)] = true
	for pair: Array in ai.assigned:
		# A hero a script took off the map keeps no reservation either.
		if listed_heroes.has(int(pair[0])):
			assigned[int(pair[0])] = pair[1]
			reserved[_key(pair[1], int(pair[0]))] = int(pair[0])
	var free: Array[Dictionary] = []
	var roles := {}
	for hero: Dictionary in heroes:
		if ELGlobalSpells.held(hero): continue
		var role := 0 if hero == leader else 1
		roles[int(hero.uid)] = role
		var task: Dictionary = assigned.get(int(hero.uid), {})
		var drop := false
		if not task.is_empty() and (finished(director, hero, task) or not _valid(task, open, smart)): drop = true
		elif free_movement and int(hero.ap) <= 0 and not task.is_empty() and task.kind != "tower": drop = true
		# A promotion or demotion since the task was given: it must still suit the role.
		elif not task.is_empty() and not _role_allows(director, hero, role, task, smart): drop = true
		elif smart and not task.is_empty() and not forecast_objective(director, hero, task): drop = true
		elif smart and not task.is_empty() and task.kind != "patrol" and (not free_movement or hero.strategy_order.is_empty()) and not can_start_order(director, hero, task, {"remaining": 3}):
			retry[_key(task, int(hero.uid)) + "@" + str(hero.uid)] = int(state.day) + 1
			drop = true
		# Remake option: a siege that would not ruin the castle (its damage
		# undone by the castle's regeneration) is reconsidered (other heroes
		# may join it, or another goal is better).
		elif smart and task.get("kind") == "tower" and ELFirstAIPlanner.siege_nights(director, hero, state.object(task.target)) < 0: drop = true
		# Living world: a patrol is what an idle hero does; it looks for work every pass.
		elif task.get("kind") == "patrol": drop = true
		# Remake option: spells bought without runes draw only cantrips until
		# a component portal fills them; while a reachable one can, the
		# errand waits (ELFirstAIEconomy.urgent).
		elif not task.is_empty() and task.kind != "shop" and not (task.kind == "tower" and ELStrategy.adjacent(director, hero, state.object(task.target))) and ELFirstAIEconomy.urgent(director, hero): drop = true
		elif not task.is_empty() and int(task.get("tries", 0)) >= BLOCKED_PASSES:
			retry[_key(task, int(hero.uid)) + "@" + str(hero.uid)] = int(state.day) + RETRY_DAYS
			drop = true
		if drop:
			reserved.erase(_key(task, int(hero.uid)))
			assigned.erase(int(hero.uid))
			task = {}
		hero.strategy_order = {}
		if task.is_empty(): free.append(hero)
	ai.retry = retry
	if smart:
		ELFirstAIPlanner.assign(director, player, heroes, roles, pool, assigned, reserved, free)
		ELFirstAIPlanner.patrols(director, player, heroes, assigned)
		lap = _lap(director, "assign", lap)
	else:
		for hero: Dictionary in free:
			var best := NONE
			var task := {}
			for candidate: Dictionary in pool:
				if not _available(candidate, hero, reserved, retry): continue
				var cost := cost(director, hero, int(roles[int(hero.uid)]), candidate, best)
				if cost < best:
					best = cost
					task = candidate
			if task.is_empty(): continue
			task = task.duplicate()
			assigned[int(hero.uid)] = task
			reserved[_key(task, int(hero.uid))] = int(hero.uid)
	for hero: Dictionary in heroes:
		var task: Dictionary = assigned.get(int(hero.uid), {})
		if task.is_empty() or ELGlobalSpells.held(hero): continue
		if not task.has("since"): task.since = int(state.day)
		command(director, hero, task)
		_progress(director, hero, task)
	ELFirstAIEconomy.end_pass()
	_guard_cells = null
	_active_heroes = null
	lap = _lap(director, "command", lap)
	for point: Vector2i in closed: director.grid._update_cell(point)
	ai.assigned = []
	for id: int in assigned: ai.assigned.append([id, assigned[id]])
	# The open objectives, for the next pass's checks and the simulator.
	var listed: Array = []
	for task: Dictionary in pool:
		if not reserved.has(_key(task, -1)): listed.append(task)
	ai.tasks = listed
	if director.has_meta("first_ai_stats"):
		var stats: Dictionary = director.get_meta("first_ai_stats")
		stats.passes = int(stats.get("passes", 0)) + 1
		stats.usec = int(stats.get("usec", 0)) + Time.get_ticks_usec() - started
		stats.slowest = maxi(int(stats.get("slowest", 0)), Time.get_ticks_usec() - started)
		# Shared objectives held by more than one hero after the pass (none expected).
		var holders := {}
		for id: int in assigned:
			if not bool(assigned[id].get("personal", false)) and assigned[id].get("kind") not in ["patrol", "escort"]: holders[_key(assigned[id], -1)] = int(holders.get(_key(assigned[id], -1), 0)) + 1
		for key: String in holders:
			if int(holders[key]) > 1: stats.duplicates = int(stats.get("duplicates", 0)) + 1

## The headless simulator aggregates reasons and decisions by faction.
static func note_stat(director: ELAdventureDirector, player: int, reason: String) -> void:
	if not director.has_meta("first_ai_balance"): return
	var stats: Dictionary = director.get_meta("first_ai_stats", {})
	var reasons: Dictionary = stats.get_or_add("reasons", {})
	var faction: Dictionary = reasons.get_or_add(player, {})
	faction[reason] = int(faction.get(reason, 0)) + 1

## Planning time by stage, when the simulator asks for it (tools/first_ai_sim.gd).
static func _lap(director: ELAdventureDirector, stage: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	if director.has_meta("first_ai_stats"):
		var stats: Dictionary = director.get_meta("first_ai_stats")
		stats[stage] = int(stats.get(stage, 0)) + now - since
	return now

## The objective a task stands for: a site, a creature or a castle by its id,
## an exploration target by its tile. A learning building is one objective
## per hero (each may learn there once); see _key.
static func _identity(task: Dictionary) -> String:
	if task.get("kind") == "explore": return "explore:%d:%d" % [int(task.tile[0]), int(task.tile[1])]
	return "%s:%d" % [task.kind, int(task.target)]

## The reservation a hero holds: a personal objective (a learning building,
## which each hero may use once; with the remake option a castle, which
## heroes may besiege together) is per hero, everything else is shared by
## the whole player.
static func _key(task: Dictionary, hero: int) -> String:
	if hero >= 0 and bool(task.get("personal", false)): return _identity(task) + "@" + str(hero)
	return _identity(task)

static func _valid(task: Dictionary, open: Dictionary, smart: bool) -> bool:
	# Explore targets are sampled afresh each pass; one being walked to stays
	# until it is reached (finished). In the original a site stays the hero's
	# errand until it is held, so an enemy that took it meanwhile loses it
	# again; with the remake option a site an ally took is given up.
	if task.get("kind") in ["explore", "hero", "patrol"] or (not smart and task.get("kind") in ["mine", "node"]): return true
	return open.has(_identity(task))

## The leader in the field: the most experienced hero (first on ties) that is
## free to move, not held in a fort, a training camp or a fortification spell.
static func commander(state: ELAdventureSession, player: int) -> Dictionary:
	var best := {}
	for hero: Dictionary in heroes_of(state, player):
		if ELGlobalSpells.held(hero): continue
		if best.is_empty() or int(hero.experience) > int(best.experience): best = hero
	return best

## The field commander of the last planning pass (the champion before one).
static func commander_id(state: ELAdventureSession, player: int) -> int:
	var ai := data(state, player)
	return int(ai.get("commander", ai.get("champion", -1)))

## Whether a held objective still suits the hero's role (the role may have
## changed since it was given): the rules that give objectives, without their
## route searches.
static func _role_allows(director: ELAdventureDirector, hero: Dictionary, role: int, task: Dictionary, smart: bool) -> bool:
	if smart:
		if task.get("kind") == "shop" and task.has("guard"): return ELFirstAIEconomy.is_shop(director.state.object(task.target))
		return ELFirstAIPlanner.legal(director, hero, role, task)
	match task.get("kind"):
		"monster", "tower": return role == 0
		"mine", "cut", "node", "explore": return role == 1
	return true

## Whether the target of an objective can be used now: the test the executed
## order makes (ELStrategy.order_path), so nothing planned is refused later.
static func usable(item: Dictionary) -> bool:
	return not item.is_empty() and item.get("alive", false) and item.get("visible", true) and item.get("enabled", true) and item.get("placed", true)

static func _available(candidate: Dictionary, hero: Dictionary, reserved: Dictionary, retry: Dictionary) -> bool:
	var key := _key(candidate, int(hero.uid))
	return not reserved.has(key) and not retry.has(key + "@" + str(hero.uid))

## Assignment bookkeeping after the order: no order counts as a pass without
## progress, and so does a new day that found the hero on the same tile with
## an order that did not move it (a siege or a use beside the target is
## progress of its own).
static func _progress(director: ELAdventureDirector, hero: Dictionary, task: Dictionary) -> void:
	var state := director.state
	var here := [int(hero.x), int(hero.y)]
	var mark: Array = task.get("mark", [])
	if mark.size() != 3 or [int(mark[0]), int(mark[1])] != here:
		task.mark = here + [int(state.day)]
		if not hero.strategy_order.is_empty():
			task.tries = 0
			return
	if hero.strategy_order.is_empty():
		# An escort beside its besieger is where it should be.
		if task.kind == "escort" and ELStrategy.adjacent(director, hero, state.object(task.get("target", -1))): return
		task.tries = int(task.get("tries", 0)) + 1
		return
	var target := state.object(task.get("target", -1))
	if not target.is_empty() and ELStrategy.adjacent(director, hero, target): return
	if int(task.mark[2]) < int(state.day) and int(hero.ap) > 0:
		task.tries = int(task.get("tries", 0)) + 1
		task.mark = here + [int(state.day)]

## Closes the unexplored tiles in the land graph for one planning pass and
## returns them so they can be reopened.
static func _close_unexplored(director: ELAdventureDirector, player: int) -> Array[Vector2i]:
	var closed: Array[Vector2i] = []
	var state := director.state
	var size := state.map.width * state.map.height
	if not ELFog.active(state, player) or state.explored.size() != size: return closed
	var mask := ELFog.bit(player)
	for index in size:
		if state.explored[index] & mask != 0: continue
		var point := Vector2i(index % state.map.width, index / state.map.width)
		if director.grid.land.is_point_solid(point): continue
		director.grid.land.set_point_solid(point, true)
		closed.append(point)
	return closed

static func heroes_of(state: ELAdventureSession, player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var item := state.object(id)
		if item.type == "hero" and int(item.owner) == player and item.alive and item.visible and item.get("placed", true): result.append(item)
	return result

## The original's objective list: neutral creatures nearest the castle
## first, then sites, enemy castles and buildings.
static func candidates(state: ELAdventureSession, player: int) -> Array:
	var castle := ELFirstScenario.castle_object(state, player)
	var home := Vector2i(castle.x, castle.y) if not castle.is_empty() else Vector2i.ZERO
	var ids: Array = state.objects.keys()
	ids.sort()
	var monsters: Array[Dictionary] = []
	var tasks: Array = []
	for id: int in ids:
		var item := state.object(id)
		if item.type == "monster" and int(item.owner) <= 0 and usable(item): monsters.append(item)
	monsters.sort_custom(func(a: Dictionary, b: Dictionary): return _distance(home, a) < _distance(home, b))
	for item: Dictionary in monsters: tasks.append({"kind": "monster", "target": item.uid})
	for group: String in ["mines", "resource_cuts", "mana_nodes"]:
		for id: int in ids:
			var item := state.object(id)
			if item.get("group") == group and usable(item): tasks.append({"kind": {"mines": "mine", "resource_cuts": "cut", "mana_nodes": "node"}[group], "target": id})
	for id: int in ids:
		var item := state.object(id)
		if ELFirstScenario.is_castle(item) and int(item.owner) >= 1 and int(item.owner) != player and item.get("placed", true): tasks.append({"kind": "tower", "target": id})
	for id: int in ids:
		var item := state.object(id)
		if item.get("group") == "additional_buildings" and usable(item) and not SKIPPED_BUILDINGS.has(item.get("name")) and ELAdditionalBuildings.supported(item):
			var task := {"kind": "building", "target": id}
			if ELAdditionalBuildings.VISITED.has(str(item.name)): task.personal = true
			tasks.append(task)
	return tasks

## This pass's open objectives, rebuilt from the world each time so that
## nothing is lost when a hero falls, a building resets or a creature
## appears: the original list (creatures, sites not yet held, castles of
## living enemies, buildings), then exploration targets and the enemy heroes
## the player sees now. With the remake option sites an enemy holds stay worth
## taking, and the spell shops and component portals the player has seen are
## added.
static func objectives(director: ELAdventureDirector, player: int) -> Array:
	var state := director.state
	var smart := ELFirstAIEconomy.applies(director)
	var kept: Array = []
	for task: Dictionary in candidates(state, player):
		var item := state.object(task.target)
		match task.kind:
			"mine", "node":
				var holder := int(item.get("owner", -1))
				if holder >= 0 and (holder == player or not smart or ELGlobalSpells._allied(state, player, holder)): continue
			"tower":
				# A castle at peace (a scripted or agreed alliance) is no target.
				if not ELFirstScenario.alive(state, int(item.owner)) or not state.hostile({"owner": player}, item): continue
				# Remake option: several heroes may besiege one castle together.
				if smart: task.personal = true
		kept.append(task)
	if smart: kept.append_array(ELFirstAIPlanner.exploration(director, player))
	else:
		for tile: Vector2i in frontier(director, player): kept.append({"kind": "explore", "target": -1, "tile": [tile.x, tile.y]})
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var item := state.object(id)
		if item.type == "hero" and int(item.owner) >= 1 and int(item.owner) != player and item.alive and observed(state, player, item): kept.append({"kind": "hero", "target": id})
	if smart:
		kept.append_array(ELFirstAIPlanner.scouting(director, player))
		if ELFirstAIPlanner.living(director): kept.append_array(ELFirstAIPlanner.escorts(director, player))
		for id: int in ids:
			var item := state.object(id)
			if ELFirstAIEconomy.is_shop(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)): kept.append({"kind": "shop", "target": id})
			# Artifacts and global-spell scrolls the player has seen.
			elif ELMapPickups.is_pickup(item) and usable(item) and ELFog.explored(state, player, Vector2i(item.x, item.y)): kept.append({"kind": "pickup", "target": id})
	return kept

## An enemy hero is a target only while the player sees it: its authored
## visibility and the player's (or an ally's) sight of its tile now.
static func observed(state: ELAdventureSession, player: int, item: Dictionary) -> bool:
	return item.get("visible", false) and item.get("placed", true) and ELFog.visible(state, player, Vector2i(int(item.x), int(item.y)))

## Explored, unoccupied tiles beside unexplored ones, nearest the castle first
## and spread apart. Players without fog (EL2, neutrals) have nothing unknown.
## Only tiles the player's heroes can reach over explored ground are sampled,
## so walled-off edges seen across obstacles do not crowd out reachable ones.
static func frontier(director: ELAdventureDirector, player: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var tiles := frontier_tiles(director, player)
	var castle := ELFirstScenario.castle_object(director.state, player)
	var home := Vector2i(castle.get("x", 0), castle.get("y", 0))
	tiles.sort_custom(func(a: Vector2i, b: Vector2i): return (a - home).length_squared() < (b - home).length_squared())
	for tile: Vector2i in tiles:
		if result.size() >= EXPLORE_LIMIT: break
		if result.all(func(other: Vector2i): return (other - tile).length_squared() > EXPLORE_SPACING): result.append(tile)
	return result

## Every explored, passable tile beside an unexplored one that the player's
## heroes reach over explored ground, in row order.
static func frontier_tiles(director: ELAdventureDirector, player: int) -> Array[Vector2i]:
	var state := director.state
	var tiles: Array[Vector2i] = []
	if not ELFog.active(state, player) or state.explored.size() != state.map.width * state.map.height: return tiles
	var mask := ELFog.bit(player)
	var seen := state.explored
	var width := state.map.width
	var reached := PackedByteArray()
	reached.resize(seen.size())
	var queue: Array[Vector2i] = []
	for hero: Dictionary in heroes_of(state, player):
		var start := Vector2i(hero.x, hero.y)
		if director.grid.contains(start) and reached[start.y * width + start.x] == 0:
			reached[start.y * width + start.x] = 1
			queue.append(start)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var next := at + Vector2i(dx, dy)
				if not director.grid.contains(next): continue
				var index := next.y * width + next.x
				if reached[index] != 0 or seen[index] & mask == 0 or director.grid.land.is_point_solid(next): continue
				reached[index] = 1
				queue.append(next)
	for y in state.map.height:
		for x in state.map.width:
			if reached[y * width + x] == 0 or seen[y * width + x] & mask == 0 or director.grid.passability(Vector2i(x, y)) < 0: continue
			var edge := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var point := Vector2i(x + dx, y + dy)
					if director.grid.contains(point) and seen[point.y * state.map.width + point.x] & mask == 0: edge = true
			if edge: tiles.append(Vector2i(x, y))
	return tiles

static func finished(director: ELAdventureDirector, hero: Dictionary, task: Dictionary) -> bool:
	var state := director.state
	var item := state.object(task.get("target", -1))
	match task.kind:
		"monster", "cut": return not item.get("alive", false)
		"hero": return true
		"mine", "node": return int(item.get("owner", -1)) == int(hero.owner) or not item.get("alive", false)
		"tower": return not ELFirstScenario.alive(state, int(item.get("owner", -1))) or not ELFirstScenario.assault_problem(state, hero, item).is_empty()
		"pickup": return not usable(item)
		"building": return not ELAdditionalBuildings.visit_problem(state, hero, item).is_empty()
		"shop":
			if task.has("guard"): return not ELFirstAIEconomy.is_shop(item) or not state.object(task.guard).get("alive", false)
			return ELFirstAIEconomy.wants(director, hero, item) == 0
		"explore":
			var tile := Vector2i(task.tile[0], task.tile[1])
			# The way to a castle is sought until the castle is found.
			var castle := state.object(int(task.get("toward", -1)))
			if not castle.is_empty() and ELFog.explored(state, int(hero.owner), Vector2i(int(castle.x), int(castle.y))): return true
			return Vector2i(hero.x, hero.y) == tile or director.grid.path(Vector2i(hero.x, hero.y), tile).is_empty()
		"patrol": return not item.get("alive", false) or int(item.get("owner", -1)) != int(hero.owner) or ELStrategy.adjacent(director, hero, item)
		"escort": return not item.get("alive", false) or not besieging(state, item)
	return true

## Whether a hero holds a siege objective of its player.
static func besieging(state: ELAdventureSession, hero: Dictionary) -> bool:
	if not state.players.has(int(hero.get("owner", -1))): return false
	for pair: Array in data(state, int(hero.owner)).assigned:
		if int(pair[0]) == int(hero.uid) and pair[1].get("kind") == "tower": return true
	return false

## Lower is better; NONE means the task does not apply to this hero.
## `limit` skips route searches that cannot beat the best cost so far.
static func cost(director: ELAdventureDirector, hero: Dictionary, role: int, task: Dictionary, limit := NONE) -> int:
	var state := director.state
	var item := state.object(task.get("target", -1))
	var level := int(hero.get("level", 1))
	match task.kind:
		"monster":
			if role != 0 or not item.get("alive", false) or int(item.get("level", 1)) > level + 1: return NONE
			return _route_cost(director, hero, item, false)
		"hero":
			if not item.get("alive", false) or int(item.get("level", 1)) - level >= 2 or not state.hostile(hero, item): return NONE
			# A supporter attacks only when nothing else is left to do, and
			# only an enemy it can reach.
			if role == 1: return AVOIDED if limit > AVOIDED and _route_cost(director, hero, item, false) != NONE else NONE
			return _route_cost(director, hero, item, true)
		"tower":
			if role != 0 or level < 6 or not ELFirstScenario.assault_problem(state, hero, item).is_empty(): return NONE
			# Remake option: no siege is begun with spells that still wait for runes.
			if ELFirstAIEconomy.urgent(director, hero) and not ELStrategy.adjacent(director, hero, item): return NONE
			if limit <= 0: return NONE
			if _route_cost(director, hero, item, true) != NONE: return 0
			return AVOIDED if limit > AVOIDED and _route_cost(director, hero, item, false) != NONE else NONE
		"mine", "cut", "node", "building":
			if task.kind == "building" and not ELAdditionalBuildings.visit_problem(state, hero, item).is_empty(): return NONE
			if task.kind in ["mine", "cut", "node"] and role != 1: return NONE
			if task.kind == "cut" and not item.get("alive", false): return NONE
			var square := _distance(Vector2i(hero.x, hero.y), item)
			var value := square / 2 if task.kind == "node" else square / 3
			# Remake option: ether nodes come first, since ether pays for heroes and global spells.
			if task.kind == "node" and ELFirstAIEconomy.applies(director): value = square / 8
			if value >= limit or _route_cost(director, hero, item, false) == NONE: return NONE
			return value
		"shop":
			# Worth a detour when there is something to buy; a hero short of
			# runes goes sooner, one with empty spells at once. Champions shop
			# too, since they do the fighting.
			var count := ELFirstAIEconomy.wants(director, hero, item)
			if count == 0: return NONE
			var route := _route_cost(director, hero, item, true)
			# Remake option: the leading hero fights its way to a guarded shop.
			if route == NONE and role == 0 and ELFirstAIEconomy.applies(director): route = _fought_cost(director, hero, item)
			if route == NONE: return NONE
			var trip := ELFirstAIEconomy.trip_cost(state, hero, item, route, count)
			return NONE if trip < 0 else trip
		"explore":
			if role != 1: return NONE
			var path := director.grid.path(Vector2i(hero.x, hero.y), Vector2i(task.tile[0], task.tile[1]))
			return NONE if path.is_empty() else director.grid.path_cost(path)
	return NONE

## Issues the day's order: the same orders a player's clicks produce. The
## order carries the rules its route was planned under (ELStrategy.order_path
## keeps to them when the hero walks): this player's explored ground, and
## outside guard areas other than the target's own when the plan found a
## clean way.
static func command(director: ELAdventureDirector, hero: Dictionary, task: Dictionary) -> void:
	var item := director.state.object(task.get("target", -1))
	var player := int(hero.owner)
	if task.kind == "explore":
		hero.strategy_order = {"destination": [int(task.tile[0]), int(task.tile[1])], "use": -1, "route": route_rules(director, player, ELFirstAIEconomy.applies(director))}
		return
	if task.kind in ["patrol", "escort"]:
		# Walks beside its own site or its besieger without using it.
		var way := director.grid.approach(Vector2i(hero.x, hero.y), item)
		if way.size() < 2: return
		hero.strategy_order = {"destination": [way[-1].x, way[-1].y], "use": -1, "route": route_rules(director, player, false)}
		return
	var use := int(item.uid)
	var clean := _route_cost(director, hero, item, true) != NONE
	if task.kind in ["mine", "cut", "node"] and not clean:
		# Without a safe route the hero walks the plain route and may be stopped.
		var path := director.grid.approach(Vector2i(hero.x, hero.y), item)
		if path.size() < 2: return
		hero.strategy_order = {"destination": [path[-1].x, path[-1].y], "use": -1, "route": route_rules(director, player, false)}
		return
	# Smarter monster orders use the screened approach chosen by the planner.
	var smart := ELFirstAIEconomy.applies(director)
	var guarded: bool = not clean or (task.kind == "building" and (not smart or ELAdditionalBuildings.DUNGEONS.has(item.get("name")))) or (task.kind == "monster" and not smart)
	hero.strategy_order = {"destination": [int(item.x), int(item.y)], "use": use, "route": route_rules(director, player, not guarded, use)}

## Checks the order the movement phase will execute while fog is already
## closed for the planning player. Keep the actor's current order intact.
static func can_start_order(director: ELAdventureDirector, hero: Dictionary, task: Dictionary, budget: Dictionary) -> bool:
	var previous: Dictionary = hero.get("strategy_order", {})
	hero.strategy_order = {}
	command(director, hero, task)
	var order: Dictionary = hero.strategy_order
	# A clean approach to an ordinary object has already been routed by
	# command(). Screen paths which could still enter the target's guard zone.
	var target := director.state.object(int(order.get("use", -1)))
	var clean: bool = order.get("route", {}).get("guards", false) and usable(target) and target.type != "hero" and not director.interception.zones.has(int(target.uid))
	# Free movement can discover an incidental guard just before stepping
	# and plan again the same day. Cache-only checks keep those passes cheap.
	var route_budget := {"remaining": 0, "allow_unknown": true} if ELStrategy.free_mode(director) else budget
	var path := last_path if clean else ELStrategy.order_path(director, hero, route_budget, true)
	hero.strategy_order = previous
	if path.is_empty(): return task.kind == "escort" and ELStrategy.adjacent(director, hero, director.state.object(task.target))
	if int(order.use) >= 0 and ELStrategy.adjacent(director, hero, target): return true
	return path.size() > 1 and director.interception.can_step(director.state, director.grid, hero, path[1])

## The rules of a planned route: whose explored ground it keeps to (-1: any
## tile) and whether it keeps out of hostile guard areas other than that of
## `target`.
static func route_rules(director: ELAdventureDirector, player: int, avoid_guards: bool, target := -1) -> Dictionary:
	var state := director.state
	var known := player if ELFog.active(state, player) and state.explored.size() == state.map.width * state.map.height else -1
	return {"known": known, "guards": avoid_guards, "target": target}

static func _distance(from: Vector2i, item: Dictionary) -> int:
	return (Vector2i(int(item.get("x", 0)), int(item.get("y", 0))) - from).length_squared()

## Movement cost of the best route beside the target. A clean route keeps out
## of every hostile interception zone other than the target's own.
## `quick` searches only toward the two open cells beside the target nearest
## the hero (falling back to every cell), for estimates.
static func _route_cost(director: ELAdventureDirector, hero: Dictionary, item: Dictionary, clean: bool, quick := false) -> int:
	var grid := director.grid
	var from := Vector2i(hero.x, hero.y)
	last_path = [from]
	if ELStrategy.adjacent(director, hero, item): return 0
	var closed := close_guards(director, hero, int(item.get("uid", -1))) if clean else ([] as Array[Vector2i])
	var path: Array[Vector2i] = []
	if quick:
		var size: Vector2i = grid.footprints.get(int(item.uid), {}).get("size", Vector2i.ONE)
		var cells: Array[Vector2i] = []
		for y in range(-1, size.y + 1):
			for x in range(-1, size.x + 1):
				var point := Vector2i(int(item.x) + x, int(item.y) + y)
				if (x < 0 or x >= size.x or y < 0 or y >= size.y) and grid.contains(point) and not grid.land.is_point_solid(point): cells.append(point)
		cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.distance_squared_to(from) < b.distance_squared_to(from))
		for point: Vector2i in cells.slice(0, 2):
			path = grid.path(from, point)
			if not path.is_empty(): break
	if path.is_empty(): path = grid.approach(from, item)
	for point: Vector2i in closed: grid._update_cell(point)
	last_path = path
	return NONE if path.is_empty() else grid.path_cost(path)

## The route of the last _route_cost or _fought_cost (empty: none found).
static var last_path: Array[Vector2i] = []

## Close hostile guard cells other than the destination guard and the hero's
## tile. Reopen the returned cells with grid._update_cell.
static func close_guards(director: ELAdventureDirector, hero: Dictionary, target: int) -> Array[Vector2i]:
	var grid := director.grid
	var from := Vector2i(hero.x, hero.y)
	var closed: Array[Vector2i] = []
	for entry: Array in _hostile_cells(director, hero):
		var point: Vector2i = entry[0]
		if point == from or grid.land.is_point_solid(point) or entry[1] == [target]: continue
		grid.land.set_point_solid(point, true)
		closed.append(point)
	return closed

## Hostile guard cells for this hero: [cell, guards]. Kept for one planning
## pass (the zones and the hero's side do not change while it plans).
static var _guard_cells: Variant = null

static func _hostile_cells(director: ELAdventureDirector, hero: Dictionary) -> Array:
	var key := "%d:%d" % [int(hero.get("uid", -1)), int(hero.get("owner", -1))]
	if _guard_cells is Dictionary and _guard_cells.has(key): return _guard_cells[key]
	var result: Array = []
	for point: Vector2i in director.interception.cells:
		if not director.grid.contains(point): continue
		var guards := director.interception.enemies(director.state, hero, point)
		if not guards.is_empty(): result.append([point, guards])
	if _guard_cells is Dictionary: _guard_cells[key] = result
	return result

## Cost of the way to an object past guards, when the hero may fight every
## one of them (the rule of the "monster" task); NONE otherwise.
static func _fought_cost(director: ELAdventureDirector, hero: Dictionary, item: Dictionary) -> int:
	var grid := director.grid
	var path := grid.approach(Vector2i(hero.x, hero.y), item)
	last_path = path
	if path.is_empty(): return NONE
	var level := int(hero.get("level", 1))
	for point: Vector2i in path:
		if not director.interception.cells.has(point): continue
		for uid: int in director.interception.enemies(director.state, hero, point):
			if int(director.state.object(uid).get("level", 1)) - level >= 2: return NONE
	return grid.path_cost(path)

static func restore(state: ELAdventureSession) -> String:
	for player: int in state.players:
		var raw: Variant = state.players[player].get("ai")
		if raw == null: continue
		if not raw is Dictionary or raw.get("version") != VERSION or not raw.get("built") is bool or not raw.get("tasks") is Array or not raw.get("assigned") is Array or raw.tasks.size() > 100000: return "Invalid saved computer plans."
		if not ELLuaSave._integer(raw.get("champion"), -1, 0x7fffffff) or not ELLuaSave._integer(raw.get("hired", 0), -1000, 0x7fffffff): return "Invalid saved computer plans."
		var tasks: Array = []
		for task: Variant in raw.tasks:
			var clean := _task(state, task)
			if clean.is_empty(): return "Invalid saved computer task."
			tasks.append(clean)
		var assigned: Array = []
		for pair: Variant in raw.assigned:
			if not pair is Array or pair.size() != 2 or not ELLuaSave._integer(pair[0], 0, 0x7fffffff) or state.object(pair[0]).get("type") != "hero": return "Invalid saved computer task."
			var clean := _task(state, pair[1])
			if clean.is_empty(): return "Invalid saved computer task."
			assigned.append([int(pair[0]), clean])
		var record := {"version": VERSION, "built": raw.built, "tasks": tasks, "assigned": assigned, "champion": int(raw.champion)}
		if raw.has("hired"): record.hired = int(raw.hired)
		# Later additions; older saves have none of them.
		for field: String in ["retry", "seen"]:
			var table: Variant = raw.get(field, {})
			if not table is Dictionary or table.size() > 10000: return "Invalid saved computer plans."
			var copy := {}
			for key: Variant in table:
				var value: Variant = table[key]
				if field == "retry":
					if not key is String or not ELLuaSave._integer(value, 0, 0x7fffffff): return "Invalid saved computer plans."
					copy[key] = int(value)
				else:
					if not value is Array or value.size() != 3 or not ELLuaSave._integer(value[0], 0, state.map.width - 1) or not ELLuaSave._integer(value[1], 0, state.map.height - 1) or not ELLuaSave._integer(value[2], 0, 0x7fffffff): return "Invalid saved computer plans."
					copy[str(key)] = [int(value[0]), int(value[1]), int(value[2])]
			if not copy.is_empty(): record[field] = copy
		var threats: Variant = raw.get("threats", [])
		if not threats is Array or threats.size() > 1000: return "Invalid saved computer plans."
		var list: Array = []
		for id: Variant in threats:
			if not ELLuaSave._integer(id, 0, 0x7fffffff): return "Invalid saved computer plans."
			list.append(int(id))
		if not list.is_empty(): record.threats = list
		# The field commander (whose shopping share is larger), the castle's
		# soonest foreseen fall and the doctrine (absent in older saves).
		if raw.has("commander"):
			if not ELLuaSave._integer(raw.commander, -1, 0x7fffffff): return "Invalid saved computer plans."
			record.commander = int(raw.commander)
		if raw.has("alarm"):
			if not ELLuaSave._integer(raw.alarm, 0, 0x7fffffff): return "Invalid saved computer plans."
			record.alarm = int(raw.alarm)
		if raw.has("doctrine"):
			if not ELFirstAIPlanner.DOCTRINES.has(str(raw.doctrine)): return "Invalid saved computer plans."
			record.doctrine = str(raw.doctrine)
		state.players[player].ai = record
	return ""

static func _task(state: ELAdventureSession, raw: Variant) -> Dictionary:
	if not raw is Dictionary or not KINDS.has(raw.get("kind")) or not ELLuaSave._integer(raw.get("target"), -1, 0x7fffffff): return {}
	var task := {"kind": str(raw.kind), "target": int(raw.target)}
	if task.kind == "explore":
		var tile: Variant = raw.get("tile")
		if not tile is Array or tile.size() != 2 or not ELLuaSave._integer(tile[0], 0, state.map.width - 1) or not ELLuaSave._integer(tile[1], 0, state.map.height - 1): return {}
		task.tile = [int(tile[0]), int(tile[1])]
		# The castle whose way the exploration seeks (absent in older saves).
		if raw.has("toward"):
			if not ELLuaSave._integer(raw.toward, 0, 0x7fffffff) or not state.objects.has(int(raw.toward)): return {}
			task.toward = int(raw.toward)
	elif not state.objects.has(task.target): return {}
	if raw.has("guard"):
		if task.kind != "shop" or not ELLuaSave._integer(raw.guard, 0, 0x7fffffff) or state.object(int(raw.guard)).get("type") != "monster": return {}
		task.guard = int(raw.guard)
	if raw.has("refill"):
		var refill: Variant = raw.refill
		if not task.has("guard") or not refill is Array or refill.size() != 3 or not ELLuaSave._integer(refill[0], 0, 14) or not refill[1] is String or not ELSpellInventory.is_spell(state.map.profile, refill[1]) or not ELLuaSave._integer(refill[2], 1, 15): return {}
		task.refill = [int(refill[0]), refill[1], int(refill[2])]
	# Assignment progress (absent in older saves).
	if raw.has("personal"):
		if not raw.personal is bool: return {}
		task.personal = raw.personal
	for field: String in ["tries", "since"]:
		if raw.has(field):
			if not ELLuaSave._integer(raw[field], 0, 0x7fffffff): return {}
			task[field] = int(raw[field])
	if raw.has("mark"):
		var mark: Variant = raw.mark
		if not mark is Array or mark.size() != 3 or not ELLuaSave._integer(mark[0], 0, state.map.width - 1) or not ELLuaSave._integer(mark[1], 0, state.map.height - 1) or not ELLuaSave._integer(mark[2], 0, 0x7fffffff): return {}
		task.mark = [int(mark[0]), int(mark[1]), int(mark[2])]
	return task

## Hardcoded chapter heroes of the neutral side; every other neutral hero and
## creature stays where it is. Orders are given afresh each day.
const MISSION23_TARGETS := {"Ramung": Vector2i(30, 67), "Gamma-400": Vector2i(41, 33), "Delta-500": Vector2i(40, 34)}
const MISSION23_HUNTERS := ["Griselda", "Lienhart"]

static func scripts(director: ELAdventureDirector) -> void:
	var state := director.state
	var id := state.map.id
	if not id.contains("mission13") and not id.contains("mission23"): return
	var ids: Array = state.objects.keys()
	ids.sort()
	for uid: int in ids:
		var hero := state.object(uid)
		if hero.type != "hero" or int(hero.owner) > 0 or not hero.alive or not hero.visible or not hero.get("placed", true): continue
		var name := str(hero.name)
		hero.strategy_order = {}
		if id.contains("mission13"):
			# Gunnilda goes for the first local hero she can reach without crossing a guard area.
			if name == "Gunnilda":
				for prey: Dictionary in heroes_of(state, 1):
					if _route_cost(director, hero, prey, true) != NONE:
						hero.strategy_order = {"destination": [int(prey.x), int(prey.y)], "use": int(prey.uid)}
						break
			continue
		if not state.scenario.get("campaign", true): continue
		if name == "Ramung":
			_walk(director, hero, MISSION23_TARGETS.Ramung)
			continue
		if MISSION23_HUNTERS.has(name):
			# The nearest other neutral by route length.
			var best := {}
			var best_length := NONE
			for other_id: int in ids:
				var other := state.object(other_id)
				if other == hero or int(other.get("owner", 1)) > 0 or other.get("type") not in ["hero", "monster"] or not other.alive or not other.visible or not other.get("placed", true): continue
				var path := director.grid.approach(Vector2i(hero.x, hero.y), other)
				if not path.is_empty() and path.size() < best_length:
					best_length = path.size()
					best = other
			if not best.is_empty(): hero.strategy_order = {"destination": [int(best.x), int(best.y)], "use": int(best.uid)}
		if name.contains("Beta-700"):
			for prey: Dictionary in heroes_of(state, 1):
				if (Vector2i(prey.x, prey.y) - Vector2i(hero.x, hero.y)).length_squared() < 50 and _route_cost(director, hero, prey, false) != NONE:
					hero.strategy_order = {"destination": [int(prey.x), int(prey.y)], "use": int(prey.uid)}
					break
		# Gamma-400's route is cut to its first step: it creeps one tile a day.
		if name.contains("Gamma-400"): _walk(director, hero, MISSION23_TARGETS["Gamma-400"], true)
		if name.contains("Delta-500"): _walk(director, hero, MISSION23_TARGETS["Delta-500"])

static func _walk(director: ELAdventureDirector, hero: Dictionary, point: Vector2i, one_step := false) -> void:
	var path := director.grid.path(Vector2i(hero.x, hero.y), point)
	if Vector2i(hero.x, hero.y) == point or path.size() < 2: return
	if one_step: point = path[1]
	hero.strategy_order = {"destination": [point.x, point.y], "use": -1}

## mission23's hunters attack other neutrals, which are otherwise never hostile.
static func hunts(state: ELAdventureSession, actor: Dictionary, target: Dictionary) -> bool:
	return state.map.id.contains("mission23") and MISSION23_HUNTERS.has(str(actor.get("name", ""))) and int(actor.get("owner", 1)) <= 0 and int(target.get("owner", 1)) <= 0 and target.get("type") in ["hero", "monster"] and actor != target
