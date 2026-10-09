class_name ELFirstAI
extends RefCounted
## First-game strategic opponents. Battles between computer and neutral sides
## are decided at once, without a duel and without any message to the local
## player: the loser simply leaves the map. Computer heroes gain experience and
## levels (with their health) but never spend skill picks: in both games only
## the human's level-up dialog chooses skills, so they keep their authored ones.

## Winner of a strategic battle that the local player takes no part in. The
## pair keeps its queue order (guard or interceptor first).
static func winner(state: ELAdventureSession, first: Dictionary, second: Dictionary) -> Dictionary:
	var first_neutral := int(first.get("owner", 0)) <= 0
	var second_neutral := int(second.get("owner", 0)) <= 0
	if state.map.id == "mission23" and (first_neutral or second_neutral):
		# Roaming neutral heroes are this chapter's hunters; its creatures are prey.
		if first_neutral: return first if first.type == "hero" else second
		return first if second.type == "monster" else second
	if first_neutral or second_neutral: return second if first_neutral else first
	# Weighted by level: the first side wins with chance (L1 + 1) / (L1 + L2 + 1).
	var level := int(first.get("level", 1))
	var roll := ELAdditionalBuildings._random(state) % (level + int(second.get("level", 1)) + 1)
	return second if level < roll else first

## Decides the battle and applies its result. Returns false on a script failure.
static func resolve(director: ELAdventureDirector, first: Dictionary, second: Dictionary) -> bool:
	var state := director.state
	var victor := winner(state, first, second)
	var loser := second if victor == first else first
	if state.players.has(int(victor.owner)) and int(victor.owner) >= 1:
		state.add_experience(victor.uid, ELHeroProgression.battle_reward(state.map.profile, int(loser.get("level", 1))))
		if loser.type == "monster": ELAdventureEncounter.loot(state, victor, loser)
	take_artifacts(victor, loser)
	state._native([float(loser.uid)], "ExKillHero")
	if not state.hook("Hook_OnHeroKill", [float(loser.uid)]): return director._fail(state.error)
	ELFirstScenario.evaluate(director, {"hero": first.uid, "opponent": second.uid, "winner": victor.uid})
	return true

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
const KINDS := ["monster", "mine", "cut", "node", "tower", "building", "explore", "hero"]
const AVOIDED := 10000
const NONE := 0x7fffffff
const EXPLORE_LIMIT := 9
const EXPLORE_SPACING := 200

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

static func data(state: ELAdventureSession, player: int) -> Dictionary:
	var record: Dictionary = state.players[player]
	if not record.get("ai") is Dictionary: record.ai = {"version": VERSION, "built": false, "tasks": [], "assigned": [], "champion": -1}
	return record.ai

## Night orders for every computer player.
static func plan(director: ELAdventureDirector) -> void:
	var state := director.state
	if state.map.profile.id != "el1": return
	scripts(director)
	for player: int in computer_players(state): plan_player(director, player)

static func plan_player(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var ai := data(state, player)
	if not ai.built:
		ai.tasks = candidates(state, player)
		ai.built = true
	refresh(director, player)
	var heroes := heroes_of(state, player)
	# The most experienced hero (first on ties) leads and defends the realm.
	var champion := {}
	for hero: Dictionary in heroes:
		if champion.is_empty() or int(hero.experience) > int(champion.experience): champion = hero
	ai.champion = int(champion.get("uid", -1))
	# Fewer than two heroes: a free level-one recruit joins beside the castle.
	# It first receives orders on the next day.
	if heroes.size() < 2: ELGlobalSpells.summon(state, player, 1)
	# mission13: after day ten the Kinet leader may send an ethereal attack on
	# the first player's castle (one chance in three each day).
	if state.map.id == "mission13" and player == 2 and state.day > 10 and not champion.is_empty() and ELAdditionalBuildings._random(state) % 3 == 1:
		ELGlobalSpells.script_attack(state, player, champion, 1)
	# Route costs only cross tiles this player has explored.
	var closed := _close_unexplored(director, player)
	var assigned := {}
	for pair: Array in ai.assigned:
		if state.object(pair[0]).get("alive", false): assigned[int(pair[0])] = pair[1]
	for hero: Dictionary in heroes:
		if ELGlobalSpells.held(hero): continue
		var role := 0 if hero == champion else 1
		var task: Dictionary = assigned.get(int(hero.uid), {})
		if not task.is_empty() and finished(director, hero, task): task = {}
		if task.is_empty():
			var best := NONE
			for candidate: Dictionary in ai.tasks:
				var cost := cost(director, hero, role, candidate, best)
				if cost < best:
					best = cost
					task = candidate
			if not task.is_empty(): ai.tasks.erase(task)
		hero.strategy_order = {}
		if task.is_empty():
			assigned.erase(int(hero.uid))
			continue
		assigned[int(hero.uid)] = task
		command(director, hero, task)
	for point: Vector2i in closed: director.grid._update_cell(point)
	ai.assigned = []
	for id: int in assigned: ai.assigned.append([id, assigned[id]])

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

## The persistent list, built once: neutral creatures nearest the castle
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
		if item.type == "monster" and int(item.owner) <= 0 and item.alive and item.visible and item.get("placed", true): monsters.append(item)
	monsters.sort_custom(func(a: Dictionary, b: Dictionary): return _distance(home, a) < _distance(home, b))
	for item: Dictionary in monsters: tasks.append({"kind": "monster", "target": item.uid})
	for group: String in ["mines", "resource_cuts", "mana_nodes"]:
		for id: int in ids:
			var item := state.object(id)
			if item.get("group") == group and item.alive: tasks.append({"kind": {"mines": "mine", "resource_cuts": "cut", "mana_nodes": "node"}[group], "target": id})
	for id: int in ids:
		var item := state.object(id)
		if ELFirstScenario.is_castle(item) and int(item.owner) >= 1 and int(item.owner) != player and item.get("placed", true): tasks.append({"kind": "tower", "target": id})
	for id: int in ids:
		var item := state.object(id)
		if item.get("group") == "additional_buildings" and not SKIPPED_BUILDINGS.has(item.get("name")) and ELAdditionalBuildings.supported(item): tasks.append({"kind": "building", "target": id})
	return tasks

## Each turn: drop unclaimed tasks that no longer apply, then add this turn's
## exploration targets and enemy heroes.
static func refresh(director: ELAdventureDirector, player: int) -> void:
	var state := director.state
	var ai := data(state, player)
	var kept: Array = []
	for task: Dictionary in ai.tasks:
		var item := state.object(task.get("target", -1))
		match task.kind:
			"mine", "node": if int(item.get("owner", -1)) >= 0: continue
			"cut", "monster": if not item.get("alive", false): continue
			"explore", "hero": continue
		if task.kind != "explore" and item.is_empty(): continue
		kept.append(task)
	for tile: Vector2i in frontier(director, player): kept.append({"kind": "explore", "target": -1, "tile": [tile.x, tile.y]})
	var ids: Array = state.objects.keys()
	ids.sort()
	for id: int in ids:
		var item := state.object(id)
		if item.type == "hero" and int(item.owner) >= 1 and int(item.owner) != player and item.alive and item.visible and item.get("placed", true): kept.append({"kind": "hero", "target": id})
	ai.tasks = kept

## Explored, unoccupied tiles beside unexplored ones, nearest the castle first
## and spread apart. Players without fog (EL2, neutrals) have nothing unknown.
## Only tiles the player's heroes can reach over explored ground are sampled,
## so walled-off edges seen across obstacles do not crowd out reachable ones.
static func frontier(director: ELAdventureDirector, player: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var state := director.state
	if not ELFog.active(state, player) or state.explored.size() != state.map.width * state.map.height: return result
	var mask := ELFog.bit(player)
	var seen := state.explored
	var castle := ELFirstScenario.castle_object(state, player)
	var home := Vector2i(castle.get("x", 0), castle.get("y", 0))
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
	var tiles: Array[Vector2i] = []
	for y in state.map.height:
		for x in state.map.width:
			if reached[y * width + x] == 0 or seen[y * width + x] & mask == 0 or director.grid.passability(Vector2i(x, y)) < 0: continue
			var edge := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var point := Vector2i(x + dx, y + dy)
					if director.grid.contains(point) and seen[point.y * state.map.width + point.x] & mask == 0: edge = true
			if edge: tiles.append(Vector2i(x, y))
	tiles.sort_custom(func(a: Vector2i, b: Vector2i): return (a - home).length_squared() < (b - home).length_squared())
	for tile: Vector2i in tiles:
		if result.size() >= EXPLORE_LIMIT: break
		if result.all(func(other: Vector2i): return (other - tile).length_squared() > EXPLORE_SPACING): result.append(tile)
	return result

static func finished(director: ELAdventureDirector, hero: Dictionary, task: Dictionary) -> bool:
	var state := director.state
	var item := state.object(task.get("target", -1))
	match task.kind:
		"monster", "cut": return not item.get("alive", false)
		"hero": return true
		"mine", "node": return int(item.get("owner", -1)) == int(hero.owner)
		"tower": return not ELFirstScenario.alive(state, int(item.get("owner", -1)))
		"building": return not ELAdditionalBuildings.visit_problem(state, hero, item).is_empty()
		"explore":
			var tile := Vector2i(task.tile[0], task.tile[1])
			return Vector2i(hero.x, hero.y) == tile or director.grid.path(Vector2i(hero.x, hero.y), tile).is_empty()
	return true

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
			if role == 1: return AVOIDED
			return _route_cost(director, hero, item, true)
		"tower":
			if role != 0 or level < 6 or not ELFirstScenario.assault_problem(state, hero, item).is_empty(): return NONE
			if limit <= 0: return NONE
			if _route_cost(director, hero, item, true) != NONE: return 0
			return AVOIDED if limit > AVOIDED and _route_cost(director, hero, item, false) != NONE else NONE
		"mine", "cut", "node", "building":
			if task.kind == "building" and not ELAdditionalBuildings.visit_problem(state, hero, item).is_empty(): return NONE
			if task.kind in ["mine", "cut", "node"] and role != 1: return NONE
			if task.kind == "cut" and not item.get("alive", false): return NONE
			var square := _distance(Vector2i(hero.x, hero.y), item)
			var value := square / 2 if task.kind == "node" else square / 3
			if value >= limit or _route_cost(director, hero, item, false) == NONE: return NONE
			return value
		"explore":
			if role != 1: return NONE
			var path := director.grid.path(Vector2i(hero.x, hero.y), Vector2i(task.tile[0], task.tile[1]))
			return NONE if path.is_empty() else director.grid.path_cost(path)
	return NONE

## Issues the day's order: the same orders a player's clicks produce.
static func command(director: ELAdventureDirector, hero: Dictionary, task: Dictionary) -> void:
	var item := director.state.object(task.get("target", -1))
	if task.kind == "explore":
		hero.strategy_order = {"destination": [int(task.tile[0]), int(task.tile[1])], "use": -1}
		return
	var use := int(item.uid)
	if task.kind in ["mine", "cut", "node"] and _route_cost(director, hero, item, true) == NONE:
		# Without a safe route the hero walks the plain route and may be stopped.
		var path := director.grid.approach(Vector2i(hero.x, hero.y), item)
		if path.size() < 2: return
		hero.strategy_order = {"destination": [path[-1].x, path[-1].y], "use": -1}
		return
	hero.strategy_order = {"destination": [int(item.x), int(item.y)], "use": use}

static func _distance(from: Vector2i, item: Dictionary) -> int:
	return (Vector2i(int(item.get("x", 0)), int(item.get("y", 0))) - from).length_squared()

## Movement cost of the best route beside the target. A clean route keeps out
## of every hostile interception zone other than the target's own.
static func _route_cost(director: ELAdventureDirector, hero: Dictionary, item: Dictionary, clean: bool) -> int:
	var grid := director.grid
	var from := Vector2i(hero.x, hero.y)
	if ELStrategy.adjacent(director, hero, item): return 0
	var closed: Array[Vector2i] = []
	if clean:
		for point: Vector2i in director.interception.cells:
			if point == from or not grid.contains(point) or grid.land.is_point_solid(point): continue
			var guards := director.interception.enemies(director.state, hero, point)
			if guards.is_empty() or guards == [int(item.uid)]: continue
			grid.land.set_point_solid(point, true)
			closed.append(point)
	var path := grid.approach(from, item)
	for point: Vector2i in closed: grid._update_cell(point)
	return NONE if path.is_empty() else grid.path_cost(path)

static func restore(state: ELAdventureSession) -> String:
	for player: int in state.players:
		var raw: Variant = state.players[player].get("ai")
		if raw == null: continue
		if not raw is Dictionary or raw.get("version") != VERSION or not raw.get("built") is bool or not raw.get("tasks") is Array or not raw.get("assigned") is Array or raw.tasks.size() > 100000: return "Invalid saved computer plans."
		if not ELLuaSave._integer(raw.get("champion"), -1, 0x7fffffff): return "Invalid saved computer plans."
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
		state.players[player].ai = {"version": VERSION, "built": raw.built, "tasks": tasks, "assigned": assigned, "champion": int(raw.champion)}
	return ""

static func _task(state: ELAdventureSession, raw: Variant) -> Dictionary:
	if not raw is Dictionary or not KINDS.has(raw.get("kind")) or not ELLuaSave._integer(raw.get("target"), -1, 0x7fffffff): return {}
	var task := {"kind": str(raw.kind), "target": int(raw.target)}
	if task.kind == "explore":
		var tile: Variant = raw.get("tile")
		if not tile is Array or tile.size() != 2 or not ELLuaSave._integer(tile[0], 0, state.map.width - 1) or not ELLuaSave._integer(tile[1], 0, state.map.height - 1): return {}
		task.tile = [int(tile[0]), int(tile[1])]
	elif not state.objects.has(task.target): return {}
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
