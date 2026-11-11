class_name ELStrategy
extends RefCounted
## First-game orders are planned, then resolved before income and daily refresh.
## Strategic AI, rituals and scenario scripts are separate; ELForts owns forts.

static func capacity(base: int, rank := -1, player_bonus := 0, addition := 0) -> int:
	var multiplier: float = 1.0 if rank < 0 else [1.25, 1.5, 2.0][rank]
	var amount := int(base * multiplier + 0.5)
	return amount + int(amount * player_bonus * 0.1 + 0.5) + addition

static func recalculate(hero: Dictionary) -> void:
	# Wanderers' Citadels held by the owner add a tenth each; spring bonuses follow.
	hero.strategy_capacity = capacity(int(hero.base_ap), int(hero.get("skills", {}).get("MOBL", -1)), int(hero.get("citadel_bonus", [0, 0])[1]), ELAdditionalBuildings.buffs(hero).y)

static func initialize(profile: ELProfile, hero: Dictionary) -> void:
	hero.strategy_version = 1
	# HeroTemplates loads both sight and base movement from the Sight column.
	hero.base_ap = int(profile.table("HeroTemplates").get(hero.name, {}).get("Sight", 0)) if hero.type == "hero" else 0
	recalculate(hero)
	hero.ap = hero.base_ap
	hero.strategy_order = {}
	hero.upkeep_paid = true
	hero.intercepted = false

static func upkeep(profile: ELProfile, hero: Dictionary) -> int:
	var cost := int(profile.table("HeroesStats").get("ManaUpkeep", {}).get("Level%d" % int(hero.level), 0))
	var rank := int(hero.get("skills", {}).get("ADPT", -1))
	return int(cost * (1.0 if rank < 0 else [0.75, 0.5, 0.0][rank]))

static func allocation(profile: ELProfile, income: int, heroes: Array) -> Dictionary:
	var spent := 0
	var required := 0
	var paid: Array[bool] = []
	for hero: Dictionary in heroes:
		var cost := upkeep(profile, hero)
		required += cost
		var funded := spent + cost <= income
		paid.append(funded)
		if funded: spent += cost
	return {"income": income, "spent": spent, "required": required, "available": maxi(0, income - spent), "paid": paid}

static func mana_budget(state: ELAdventureSession, player: int, apply := false) -> Dictionary:
	var heroes: Array[Dictionary] = []
	# Dictionary insertion order preserves the original owned-hero registration order.
	for actor: Dictionary in state.objects.values():
		if actor.type == "hero" and actor.alive and actor.owner == player: heroes.append(actor)
	var result := allocation(state.map.profile, ELResourceSites.mana_income(state, player), heroes)
	if apply:
		for index in heroes.size(): heroes[index].upkeep_paid = result.paid[index]
		# The day's free ether is fixed at night end (is its only
		# writer besides mission start and castle regeneration): heroes hired,
		# lost or sites taken during the day change it only at the next night.
		if state.map.profile.id == "el1" and state.players.has(player): state.players[player].free_ether = int(result.available)
	elif state.map.profile.id == "el1" and state.players.has(player):
		# Mission start sets each player's free ether to the full income
		# hero upkeep is first allocated at the
		# first night's end, so day 1 shows 50 / 50.
		var fixed: Variant = state.players[player].get("free_ether")
		if fixed is int or fixed is float: result.available = maxi(0, int(fixed))
		elif int(state.day) <= 1: result.available = int(result.income)
		# Global spell upkeep and investment already drew on today's ether.
		result.spells = int(state.players[player].get("global_spells", {}).get("spent_today", 0))
		result.available = maxi(0, int(result.available) - int(result.spells))
	return result

static func restore(profile: ELProfile, actor: Dictionary, map: ELAdventureMap) -> bool:
	if not actor.has("strategy_version"): initialize(profile, actor)
	if not ELLuaSave._integer(actor.strategy_version, 1, 1) or not ELLuaSave._integer(actor.base_ap, 0, 100000) or not ELLuaSave._integer(actor.ap, 0, 100000) or not ELLuaSave._integer(actor.get("strategy_capacity"), 0, 100000) or not actor.get("upkeep_paid") is bool: return false
	if not actor.has("intercepted"): actor.intercepted = false
	if not actor.intercepted is bool or not actor.get("fortified", false) is bool: return false
	var order: Variant = actor.get("strategy_order")
	if not order is Dictionary: return false
	if not order.is_empty():
		if not order.get("destination") is Array or order.destination.size() != 2 or not ELLuaSave._integer(order.get("use"), -1, 0x7fffffff): return false
		if not ELLuaSave._integer(order.destination[0], 0, map.width - 1) or not ELLuaSave._integer(order.destination[1], 0, map.height - 1): return false
		order.destination = [int(order.destination[0]), int(order.destination[1])]
		order.use = int(order.use)
	actor.strategy_capacity = int(actor.strategy_capacity)
	return true

static func order_path(director: ELAdventureDirector, actor: Dictionary) -> Array[Vector2i]:
	var order: Dictionary = actor.get("strategy_order", {})
	if order.is_empty(): return []
	var from := Vector2i(actor.x, actor.y)
	var target := {}
	if int(order.use) >= 0:
		target = director.state.object(order.use)
		if target.is_empty() or not target.alive or not target.visible or not target.enabled: return []
	# EL1: a player's hero is routed only across tiles that player sees now
	# (the computer's own planning uses its explored tiles instead).
	var closed := _close_unseen(director, actor)
	var path := director.grid.approach(from, target) if not target.is_empty() else director.grid.path(from, Vector2i(order.destination[0], order.destination[1]))
	for point: Vector2i in closed: director.grid.land.set_point_solid(point, false)
	return path

static func _close_unseen(director: ELAdventureDirector, actor: Dictionary) -> Array[Vector2i]:
	var closed: Array[Vector2i] = []
	var state := director.state
	var player := int(actor.get("owner", -1))
	if state.map.profile.id != "el1" or not ELFog.active(state, player): return closed
	if not director.is_human_strategy_order(player) and ELFirstAI.computer_players(state).has(player): return closed
	var seen: PackedByteArray = state.fog.get("visible", PackedByteArray())
	var size := state.map.width * state.map.height
	if seen.size() != size: return closed
	var mask := ELFog.bit(player)
	for index in size:
		if seen[index] & mask != 0: continue
		var point := Vector2i(index % state.map.width, index / state.map.width)
		if director.grid.land.is_point_solid(point): continue
		director.grid.land.set_point_solid(point, true)
		closed.append(point)
	return closed

static func plan(director: ELAdventureDirector, actor: Dictionary, destination: Vector2i, use_id: int) -> bool:
	if not director.grid.contains(destination): return false
	if actor.get("fortified", false):
		director.notice = "Leave the fort before giving this hero new orders."
		return false
	if int(actor.get("camp", -1)) >= 0:
		director.notice = "Leave the training camp before giving this hero new orders."
		return false
	if ELGlobalSpells.hero_has(actor, ELGlobalSpells.WARRIOR):
		director.notice = "This hero is preparing an ethereal attack."
		return false
	if int(actor.get("spell_fort", 0)) > 0:
		director.notice = "This hero holds its ground under a fortification spell."
		return false
	var castle := director.state.object(use_id) if use_id >= 0 else {}
	if ELFirstScenario.is_castle(castle):
		var problem := ELFirstScenario.assault_problem(director.state, actor, castle)
		if not problem.is_empty():
			director.notice = problem
			return false
	var previous: Dictionary = actor.strategy_order
	actor.strategy_order = {"destination": [destination.x, destination.y], "use": use_id}
	var path := order_path(director, actor)
	if path.is_empty():
		actor.strategy_order = previous
		director.notice = "No route to that location."
		return false
	if path.size() == 1 and use_id < 0: actor.strategy_order = {}
	director.presentation.emit({"kind": "route", "id": actor.uid, "path": path})
	var preview := director.interception.preview(director.state, actor, path)
	if not preview.is_empty() and not director.interception.enemies(director.state, actor, preview[-1]).is_empty():
		director.notice = ELInterception.ROUTE_NOTICE
		director.presentation.emit({"kind": "notice", "text": director.notice})
	return true

static func begin(director: ELAdventureDirector) -> bool:
	var state := director.state
	if free_mode(director): return begin_free(director)
	# Computer players plan once the local player has ended the day.
	ELFirstAI.plan(director)
	var actors: Array[Dictionary] = []
	for actor: Dictionary in state.objects.values():
		# Scripted neutral heroes move only when their chapter gives them an order.
		if actor.type == "hero" and actor.alive and actor.visible and (state.players.has(actor.owner) or (int(actor.owner) <= 0 and not actor.get("strategy_order", {}).is_empty())): actors.append(actor)
	actors.sort_custom(func(a: Dictionary, b: Dictionary): return a.experience > b.experience if a.experience != b.experience else a.uid > b.uid)
	var ids: Array[int] = []
	for actor: Dictionary in actors: ids.append(actor.uid)
	director.strategy = {"phase": "movement", "actors": ids, "index": 0, "combats": [], "legacy_orders": false}
	# Unused ether restores castle energy before the night begins.
	ELFirstScenario.regenerate(state)
	state.day += 1
	director.presentation.emit({"kind": "strategy_phase", "phase": "movement"})
	return true

static func adjacent(director: ELAdventureDirector, actor: Dictionary, target: Dictionary) -> bool:
	var size: Vector2i = director.grid.footprints.get(int(target.uid), {}).get("size", Vector2i.ONE)
	return Rect2i(int(target.x) - 1, int(target.y) - 1, size.x + 2, size.y + 2).has_point(Vector2i(actor.x, actor.y))

## An ethereal battle (Warrior of the Realm) is marked with a third entry.
static func queue_combat(director: ELAdventureDirector, first: int, second: int, ethereal := false) -> void:
	if director.strategy.is_empty() or first == second: return
	for pair: Array in director.strategy.combats:
		if pair.has(first) and pair.has(second): return
	director.strategy.combats.append([first, second, 1] if ethereal else [first, second])

static func entered(director: ELAdventureDirector, actor: Dictionary) -> void:
	var enemies := director.interception.enemies(director.state, actor, Vector2i(actor.x, actor.y))
	if enemies.is_empty(): return
	actor.intercepted = true
	director.warn_danger(actor)
	for id: int in enemies: queue_combat(director, id, actor.uid)
	director.presentation.emit({"kind": "notice", "text": "%s was intercepted." % actor.get("title", actor.name)})

static func after_movement(director: ELAdventureDirector, actor: Dictionary) -> void:
	if not actor.get("alive", false): return
	var order: Dictionary = actor.get("strategy_order", {})
	if order.is_empty() or order.use < 0: return
	var target := director.state.object(order.use)
	if director.state.map.profile.id == "el1" and ELAdditionalBuildings.DUNGEONS.has(target.get("name")) and ELAdditionalBuildings.supported(target):
		ELAdditionalBuildings.precombat(director, actor, target)
		return
	# A hero inside a training camp has left the map and cannot be attacked.
	if target.is_empty() or not target.alive or not target.get("placed", true) or target.type not in ["hero", "monster"] or not (director.state.hostile(actor, target) or ELFirstAI.hunts(director.state, actor, target)) or not adjacent(director, actor, target): return
	# InterceptEnemy executes during the movement pass, before the next hero.
	target.intercepted = true
	queue_combat(director, actor.uid, target.uid)
	actor.strategy_order = {}

static func advance(director: ELAdventureDirector) -> void:
	var state := director.state
	for budget in 32:
		if director.strategy.is_empty() or not director.movement.is_empty() or director.encounter != null or director._shopping() or not director.error.is_empty(): return
		var turn: Dictionary = director.strategy
		if turn.phase == "combat" and turn.legacy_orders:
			# Earlier saves had no pair queue; finish their remaining attack orders.
			for id: int in turn.actors.slice(turn.index): after_movement(director, state.object(id))
			turn.index = 0
			turn.legacy_orders = false
		var limit: int = turn.combats.size() if turn.phase == "combat" else turn.actors.size()
		if turn.index >= limit:
			if turn.phase == "use":
				if director.strategy_shop_wait.is_valid() and director.strategy_shop_wait.call(): return
				if turn.get("free", "") in ["act", "ai"]:
					_finish_act(director, turn)
					return
				# Night end: the weekly spring expiry precedes the movement refill;
				# building day-start resets follow. The elapsed-day counter is the
				# number of nights begun (state day 1 is the mission's first day).
				ELAdditionalBuildings.end_night(state, state.day - 1)
				for actor: Dictionary in state.objects.values():
					if actor.type in ["hero", "monster"]: actor.intercepted = false
					if actor.type == "hero" and actor.alive: actor.ap = int(actor.strategy_capacity)
				ELFirstScenario.end_night(director)
				ELAdditionalBuildings.new_day(state, state.day - 1)
				ELResourceSites.settle_income(state, true)
				for player: int in state.players: mana_budget(state, player, true)
				if ELGlobalSpells.applies(state):
					for player: int in state.players: ELGlobalSpells.settle(state, player)
				director.strategy = {}
				# Accepted peace offers and broken alliances come into force.
				ELDiplomacy.new_day(state)
				state.event.emit({"kind": "day_changed", "day": state.day})
				director.presentation.emit({"kind": "strategy_phase", "phase": "planning"})
				ELFirstScenario.evaluate(director)
				return
			# Ethereal attacks are planned once the moves are over.
			if turn.phase == "movement" and turn.get("free", "night") == "night": ELGlobalSpells.plan_ethereal(director)
			turn.phase = "combat" if turn.phase == "movement" else "use"
			turn.index = 0
			director.presentation.emit({"kind": "strategy_phase", "phase": turn.phase})
			continue
		if turn.phase == "combat":
			var pair: Array = turn.combats[turn.index]
			turn.index += 1
			var first := state.object(pair[0])
			var second := state.object(pair[1])
			var forfeit_winner := director.strategic_forfeit_winner(pair[0], pair[1])
			if pair.size() > 2:
				if not first.alive or not second.alive: continue
				if director.is_strategy_human(first.owner) or director.is_strategy_human(second.owner): director.start_ethereal(first.uid, second.uid)
				elif forfeit_winner >= 0: ELGlobalSpells.ethereal_result(state, second.uid, forfeit_winner)
				else: ELGlobalSpells.ethereal_result(state, second.uid, ELFirstAI.winner(state, first, second).uid)
				continue
			if not first.alive or not second.alive or not (state.hostile(first, second) or ELFirstAI.hunts(state, first, second)): continue
			# Preserve the host's usual seat order when present. A guest's
			# encounter still opens and waits for a result if the host is absent.
			if second.owner == state.current_player or (first.owner != state.current_player and director.is_strategy_human(second.owner)):
				director.use_object(second.uid, first.uid, second.uid)
			elif director.is_strategy_human(first.owner):
				director.use_object(first.uid, second.uid, second.uid)
			elif not ELFirstAI.resolve(director, first, second, forfeit_winner): return
			continue
		var actor := state.object(turn.actors[turn.index])
		turn.index += 1
		if actor.is_empty() or not actor.alive or actor.get("strategy_order", {}).is_empty(): continue
		var order: Dictionary = actor.strategy_order
		# Free movement: heroes moved during the day; the night moves no one.
		if turn.phase == "movement" and turn.get("free", "") == "night": continue
		if turn.phase == "movement":
			var path := order_path(director, actor)
			if path.is_empty():
				actor.strategy_order = {}
				continue
			path.assign(director.interception.preview(state, actor, path))
			var available := int(actor.ap)
			var count := 1
			if path.size() > 1 and not director.interception.can_step(state, director.grid, actor, path[1]): path.resize(1)
			for point: Vector2i in path.slice(1):
				var cost := director.grid.passability(point)
				if cost < 0 or cost > available: break
				available -= cost
				count += 1
			if count > 1:
				path.resize(count)
				director.movement = {"id": actor.uid, "path": path, "index": 0, "progress": 0.0, "queued": false, "use": -1, "strategic": true}
				actor.orders.assign(["move"])
				director.presentation.emit({"kind": "route", "id": actor.uid, "path": path})
			else:
				after_movement(director, actor)
				if order.use < 0 and Vector2i(actor.x, actor.y) == Vector2i(order.destination[0], order.destination[1]): actor.strategy_order = {}
			continue
		if order.use < 0: continue
		var target := state.object(order.use)
		if target.is_empty() or not target.alive or not target.visible or not target.enabled:
			actor.strategy_order = {}
			continue
		if target.type in ["hero", "monster"] and (state.hostile(actor, target) or ELFirstAI.hunts(state, actor, target)): continue
		if not adjacent(director, actor, target): continue
		if ELFirstScenario.is_castle(target):
			# The assault order persists: the hero strikes again every night
			# (with free movement, at night only, not on each move).
			if turn.get("free", "") in ["act", "ai"]: continue
			if not ELFirstScenario.assault(director, actor, target): actor.strategy_order = {}
			continue
		# Free movement: other uses ran when the hero arrived.
		if turn.get("free", "") == "night": continue
		actor.strategy_order = {}
		# A computer hero at a spell shop or component portal buys on the spot
		# (remake option); the shop screens are the local player's.
		if target.get("type") in ["el1_spell_shop", "rune_shop"] and int(actor.get("owner", 0)) >= 1 and not director.is_strategy_human(int(actor.owner)):
			ELFirstAIEconomy.visit(director, actor, target)
			continue
		if ELResourceSites.TYPES.has(target.group):
			ELResourceSites.capture(state, actor.uid, target.uid, false)
		else:
			director.use_object(actor.uid, target.uid)

static func restore_turn(raw: Variant, state: ELAdventureSession) -> Dictionary:
	if not raw is Dictionary: return {"error": "Invalid strategy turn."}
	if raw.is_empty(): return {}
	if state.map.profile.id != "el1" or raw.get("phase") not in ["movement", "combat", "use"] or not raw.get("actors") is Array: return {"error": "Invalid strategy phase."}
	var ids: Array[int] = []
	for id: Variant in raw.actors:
		if not ELLuaSave._integer(id, 0, 0x7fffffff) or not state.objects.has(int(id)) or state.object(id).type != "hero" or ids.has(int(id)): return {"error": "Invalid strategy actor."}
		ids.append(int(id))
	var combats: Array = []
	if not raw.get("combats", []) is Array or raw.get("combats", []).size() > 10000 or not raw.get("legacy_orders", false) is bool: return {"error": "Invalid strategic combats."}
	for pair: Variant in raw.get("combats", []):
		if not pair is Array or pair.size() not in [2, 3] or (pair.size() == 3 and not ELLuaSave._integer(pair[2], 1, 1)): return {"error": "Invalid strategic combat pair."}
		for id: Variant in pair.slice(0, 2):
			if not ELLuaSave._integer(id, 0, 0x7fffffff) or state.object(id).get("type") not in ["hero", "monster"]: return {"error": "Invalid strategic combat actor."}
		var normalized := [int(pair[0]), int(pair[1])]
		if normalized[0] == normalized[1]: return {"error": "Duplicate strategic combat."}
		for other: Array in combats:
			if other.has(normalized[0]) and other.has(normalized[1]): return {"error": "Duplicate strategic combat."}
		combats.append(normalized + [1] if pair.size() == 3 else normalized)
	var legacy: bool = raw.get("legacy_orders", not raw.has("combats"))
	var limit: int = combats.size() if raw.phase == "combat" and not legacy else ids.size()
	if not ELLuaSave._integer(raw.get("index"), 0, limit): return {"error": "Invalid strategy cursor."}
	var turn := {"phase": raw.phase, "actors": ids, "index": int(raw.index), "combats": combats, "legacy_orders": legacy}
	if raw.has("free"):
		if raw.free not in ["act", "ai", "night"]: return {"error": "Invalid strategy phase."}
		turn.free = raw.free
	return turn

## Remake option "free movement" (single-player first-game maps): heroes move
## at once, as many times a day as their movement points allow. A move runs
## the movement, battle and use passes for that hero alone. Ending the day
## lets each computer player move its heroes the same way; then the night
## strikes castles, sends ethereal attacks and starts the next day. Network
## and hot-seat games and the tutorial keep simultaneous orders.
static func free_mode(director: ELAdventureDirector) -> bool:
	var state := director.state
	return director.free_movement and state.map.profile.id == "el1" and director._strategic_players.is_empty() and not state.tutorial

## Moves `actor` along its order now.
static func act(director: ELAdventureDirector, actor: Dictionary, kind := "act") -> bool:
	if actor.is_empty() or not actor.get("alive", false) or actor.get("strategy_order", {}).is_empty(): return false
	director.strategy = {"phase": "movement", "actors": [int(actor.uid)], "index": 0, "combats": [], "legacy_orders": false, "free": kind}
	director.presentation.emit({"kind": "strategy_phase", "phase": "movement"})
	return true

## The move is over. A hero that fought its way clear may go on with the
## points it has left; the turn passes on (the player plans again, a computer
## player moves its next hero).
static func _finish_act(director: ELAdventureDirector, turn: Dictionary) -> void:
	var state := director.state
	director.strategy = {}
	for id: int in turn.actors:
		var actor := state.object(id)
		if actor.get("alive", false) and actor.get("intercepted", false) and director.interception.enemies(state, actor, Vector2i(actor.x, actor.y)).is_empty(): actor.intercepted = false
	ELFirstScenario.evaluate(director)
	if not director.free_queue.is_empty():
		free_next(director)
		return
	director.presentation.emit({"kind": "strategy_phase", "phase": "planning"})

## End of the player's day: the computer players' turns, scripted neutral
## heroes, then the night.
static func begin_free(director: ELAdventureDirector) -> bool:
	var state := director.state
	ELFirstAI.scripts(director)
	director.free_queue = []
	for player: int in ELFirstAI.computer_players(state):
		if not director.is_strategy_human(player): director.free_queue.append({"kind": "ai", "player": player, "round": 0, "pending": [], "planned": false, "positions": {}})
	var neutral: Array = []
	for actor: Dictionary in state.objects.values():
		if actor.type == "hero" and actor.alive and actor.visible and int(actor.owner) <= 0 and not actor.get("strategy_order", {}).is_empty(): neutral.append(int(actor.uid))
	if not neutral.is_empty(): director.free_queue.append({"kind": "neutral", "pending": neutral})
	director.free_queue.append({"kind": "night"})
	free_next(director)
	return true

## How often a computer player plans again in one day while its heroes still
## make progress.
const FREE_AI_ROUNDS := 6

static func free_next(director: ELAdventureDirector) -> void:
	var state := director.state
	for budget in 256:
		if director.free_queue.is_empty() or not state.outcome.is_empty() or not director.error.is_empty(): return
		var entry: Dictionary = director.free_queue[0]
		match entry.kind:
			"ai":
				var player := int(entry.player)
				if not state.scenario.get("castles", {}).is_empty() and not ELFirstScenario.alive(state, player):
					director.free_queue.pop_front()
					continue
				if not entry.planned:
					# Plan again only while the last round moved a hero that
					# still has points left.
					if int(entry.round) > 0:
						var progress := false
						for hero: Dictionary in ELFirstAI.heroes_of(state, player):
							var before: Variant = entry.positions.get(str(hero.uid))
							if before != null and before != [int(hero.x), int(hero.y)] and int(hero.ap) > 0: progress = true
						if not progress or int(entry.round) >= FREE_AI_ROUNDS:
							director.free_queue.pop_front()
							continue
					ELFirstAI.plan_player(director, player, int(entry.round) == 0)
					entry.planned = true
					entry.round = int(entry.round) + 1
					entry.positions = {}
					entry.pending = []
					for hero: Dictionary in ELFirstAI.heroes_of(state, player):
						entry.positions[str(hero.uid)] = [int(hero.x), int(hero.y)]
						if int(hero.ap) > 0 and not hero.get("strategy_order", {}).is_empty(): entry.pending.append(int(hero.uid))
				if entry.pending.is_empty():
					entry.planned = false
					continue
				if act(director, state.object(int(entry.pending.pop_front())), "ai"): return
			"neutral":
				if entry.pending.is_empty():
					director.free_queue.pop_front()
					continue
				if act(director, state.object(int(entry.pending.pop_front())), "ai"): return
			_:
				director.free_queue.pop_front()
				_begin_night(director)
				return

## The night of a free-movement day: heroes beside an enemy castle strike it,
## ethereal attacks are planned and fought, then income and the new day.
static func _begin_night(director: ELAdventureDirector) -> void:
	var state := director.state
	var ids: Array[int] = []
	for actor: Dictionary in state.objects.values():
		if actor.type == "hero" and actor.alive and actor.visible and not actor.get("strategy_order", {}).is_empty(): ids.append(int(actor.uid))
	director.strategy = {"phase": "movement", "actors": ids, "index": 0, "combats": [], "legacy_orders": false, "free": "night"}
	# Unused ether restores castle energy before the night begins.
	ELFirstScenario.regenerate(state)
	state.day += 1
	director.presentation.emit({"kind": "strategy_phase", "phase": "movement"})

## The rest of a free-movement day from a save (JSON numbers come back as
## floats); anything malformed is dropped and the night follows.
static func restore_queue(raw: Variant, state: ELAdventureSession) -> Array:
	var queue: Array = []
	if not raw is Array or raw.size() > 64: return queue
	for item: Variant in raw:
		if not item is Dictionary or item.get("kind") not in ["ai", "neutral", "night"]: return [{"kind": "night"}]
		var entry := {"kind": item.kind}
		if item.kind != "night":
			var pending: Array = []
			for id: Variant in item.get("pending", []) if item.get("pending") is Array else []:
				if ELLuaSave._integer(id, 0, 0x7fffffff) and state.object(int(id)).get("type") == "hero": pending.append(int(id))
			entry.pending = pending
		if item.kind == "ai":
			if not ELLuaSave._integer(item.get("player"), 1, 64) or not ELLuaSave._integer(item.get("round"), 0, FREE_AI_ROUNDS): return [{"kind": "night"}]
			entry.player = int(item.player)
			entry.round = int(item.round)
			entry.planned = bool(item.get("planned", false))
			entry.positions = {}
			if item.get("positions") is Dictionary:
				for key: Variant in item.positions:
					var at: Variant = item.positions[key]
					if at is Array and at.size() == 2: entry.positions[str(key)] = [int(at[0]), int(at[1])]
		queue.append(entry)
	return queue
